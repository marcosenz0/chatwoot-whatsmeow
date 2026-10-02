package main

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/types"
	"github.com/polymorfa/hypermeow/types/events"
)

type groupMutation struct {
	GroupJID          string   `json:"group_jid"`
	Name              *string  `json:"name"`
	Topic             *string  `json:"topic"`
	Photo             *string  `json:"photo"`
	AllowMemberEdit   *bool    `json:"allow_member_edit"`
	AllowMemberSend   *bool    `json:"allow_member_send"`
	AllowMemberAdd    *bool    `json:"allow_member_add"`
	RequireApproval   *bool    `json:"require_approval"`
	DisappearingTimer *uint32  `json:"disappearing_timer"`
	Participants      []string `json:"participants"`
	Operation         string   `json:"operation"`
	CommunityJID      string   `json:"community_jid"`
}

func processGroupChangeForInbox(channelID, accountID string, client *whatsmeow.Client, event *events.GroupInfo) {
	settings, err := getChannelSettings(channelID)
	if err != nil || settings.IgnoreGroups {
		return
	}
	changes := []gin.H{}
	for _, change := range []struct {
		kind         string
		participants []types.JID
	}{
		{"join", event.Join}, {"leave", event.Leave}, {"promote", event.Promote}, {"demote", event.Demote},
	} {
		if len(change.participants) == 0 {
			continue
		}
		names := make([]string, 0, len(change.participants))
		for _, jid := range change.participants {
			member := buildGroupMemberResponse(client, types.GroupParticipant{JID: jid}, false)
			names = append(names, firstNonBlank(member.Name, member.PhoneNumber, member.JID))
		}
		changes = append(changes, gin.H{"kind": change.kind, "names": strings.Join(names, ", ")})
	}
	if event.Name != nil {
		changes = append(changes, gin.H{"kind": "name"})
	}
	if event.Topic != nil {
		changes = append(changes, gin.H{"kind": "topic"})
	}
	if event.Locked != nil || event.Announce != nil || event.MembershipApprovalMode != nil {
		changes = append(changes, gin.H{"kind": "permissions"})
	}
	if event.Ephemeral != nil {
		changes = append(changes, gin.H{"kind": "ephemeral"})
	}
	if len(changes) == 0 {
		return
	}
	groupNameMu.Lock()
	delete(groupNameCache, event.JID.String())
	groupNameMu.Unlock()
	name := getGroupName(client, event.JID)
	if event.Name != nil {
		name = event.Name.Name
	}
	timestamp := event.Timestamp
	if timestamp.IsZero() {
		timestamp = time.Now()
	}
	sendWebhookNotification(accountID, channelID, map[string]interface{}{
		"event": "group_change", "group_jid": event.JID.ToNonAD().String(), "group_name": name,
		"name_changed": event.Name != nil, "timestamp": timestamp.Unix(), "version": event.ParticipantVersionID, "changes": changes,
	})
}

func (r groupMutation) validate() error {
	if r.Name != nil && (strings.TrimSpace(*r.Name) == "" || len([]rune(*r.Name)) > 100) {
		return fmt.Errorf("Group name must contain 1 to 100 characters")
	}
	if r.Topic != nil && len([]rune(*r.Topic)) > 2048 {
		return fmt.Errorf("Group description is too long")
	}
	if r.DisappearingTimer != nil {
		switch *r.DisappearingTimer {
		case 0, 86400, 604800, 7776000:
		default:
			return fmt.Errorf("Invalid disappearing message duration")
		}
	}
	if r.Photo != nil && *r.Photo != "" {
		data, err := base64.StdEncoding.DecodeString(*r.Photo)
		if err != nil || len(data) > 2*1024*1024 || http.DetectContentType(data) != "image/jpeg" {
			return fmt.Errorf("Group photo must be a JPEG under 2 MB")
		}
	}
	return nil
}

func groupMemberTargets(values []string) ([]types.JID, error) {
	targets := make([]types.JID, 0, len(values))
	seen := make(map[types.JID]bool)
	for _, value := range values {
		jid, ok := parseJID(value)
		if !ok || !isNumericUser(jid.User) || (jid.Server != types.DefaultUserServer && jid.Server != types.HiddenUserServer) {
			return nil, fmt.Errorf("Invalid group participant")
		}
		jid = jid.ToNonAD()
		if !seen[jid] {
			targets = append(targets, jid)
			seen[jid] = true
		}
	}
	return targets, nil
}

func groupSnapshot(client *whatsmeow.Client, info *types.GroupInfo) gin.H {
	self, selfPhone := currentClientJID(client)
	members := make([]GroupMemberResponse, 0, len(info.Participants))
	admin := false
	for _, participant := range info.Participants {
		member := buildGroupMemberResponse(client, participant, false)
		if groupParticipantMatches(participant, self, client.Store.GetLID()) {
			member.IsSelf = true
			member.Name = firstNonBlank(client.Store.PushName, member.Name)
			member.PhoneNumber = firstNonBlank(selfPhone, member.PhoneNumber)
			admin = participant.IsAdmin || participant.IsSuperAdmin
		}
		members = append(members, member)
	}
	sortGroupMembers(members)
	return gin.H{
		"group_jid": info.JID.ToNonAD().String(), "group_name": info.Name, "topic": info.Topic,
		"profile_picture_url": cachedProfilePictureURL(info.JID),
		"created_at":          info.GroupCreated.Unix(), "owner_jid": info.OwnerJID.String(),
		"members": members, "count": len(members), "self_jid": self.String(), "self_is_admin": admin,
		"allow_member_edit": !info.IsLocked, "allow_member_send": !info.IsAnnounce,
		"allow_member_add": info.MemberAddMode == types.GroupMemberAddModeAllMember,
		"require_approval": info.IsJoinApprovalRequired, "disappearing_timer": info.DisappearingTimer,
		"can_edit":        admin || !info.IsLocked,
		"can_add_members": admin || info.MemberAddMode == types.GroupMemberAddModeAllMember,
		"community_jid":   info.LinkedParentJID.String(), "is_community": info.IsParent,
	}
}

func handleGroupDetails(c *gin.Context) {
	jid, ok := parseJID(c.Query("group_jid"))
	if !ok || !isGroupJID(jid) {
		c.JSON(400, gin.H{"error": "Invalid WhatsApp group"})
		return
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	info, err := client.GetGroupInfo(c.Request.Context(), jid.ToNonAD())
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, groupSnapshot(client, info))
}

func handleGroupContacts(c *gin.Context) {
	client := connectedSession(c)
	if client == nil {
		return
	}
	contacts, err := client.Store.Contacts.GetAllContacts(c.Request.Context())
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	query := strings.ToLower(strings.TrimSpace(c.Query("q")))
	members := make([]GroupMemberResponse, 0, len(contacts))
	seen := make(map[string]bool)
	for jid, contact := range contacts {
		if jid.Server != types.DefaultUserServer && jid.Server != types.HiddenUserServer {
			continue
		}
		// The directory is backed by this WhatsApp session, including contacts not yet imported into Chatwoot.
		member := buildGroupMemberResponse(client, types.GroupParticipant{JID: jid}, false)
		member.Name = firstNonBlank(contact.FullName, contact.FirstName, member.Name)
		member.IsSelf = isCurrentClientJID(client, jid)
		if seen[member.JID] {
			continue
		}
		seen[member.JID] = true
		if query == "" || strings.Contains(strings.ToLower(member.Name+" "+member.PhoneNumber+" "+member.JID), query) {
			members = append(members, member)
		}
	}
	sort.SliceStable(members, func(i, j int) bool { return strings.ToLower(members[i].Name) < strings.ToLower(members[j].Name) })
	offset, _ := strconv.Atoi(c.Query("offset"))
	if offset < 0 || offset > len(members) {
		offset = len(members)
	}
	end := offset + 100
	if end > len(members) {
		end = len(members)
	}
	c.JSON(200, gin.H{"contacts": members[offset:end], "count": len(members), "has_more": end < len(members)})
}

func handleCreateGroup(c *gin.Context) {
	var request groupMutation
	if c.ShouldBindJSON(&request) != nil || request.Name == nil {
		c.JSON(400, gin.H{"error": "Group name is required"})
		return
	}
	if err := request.validate(); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	participants, err := groupMemberTargets(request.Participants)
	if err != nil || len(participants) == 0 || len(participants) > 1023 {
		c.JSON(400, gin.H{"error": "Choose 1 to 1023 participants"})
		return
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	req := whatsmeow.ReqCreateGroup{Name: strings.TrimSpace(*request.Name), Participants: participants, MemberAddMode: types.GroupMemberAddModeAllMember}
	for _, participant := range participants {
		if isCurrentClientJID(client, participant) {
			c.JSON(400, gin.H{"error": "Your own WhatsApp account is already included as the group creator"})
			return
		}
	}
	if request.AllowMemberEdit != nil {
		req.IsLocked = !*request.AllowMemberEdit
	}
	if request.AllowMemberSend != nil {
		req.IsAnnounce = !*request.AllowMemberSend
	}
	if request.AllowMemberAdd != nil && !*request.AllowMemberAdd {
		req.MemberAddMode = types.GroupMemberAddModeAdmin
	}
	if request.RequireApproval != nil {
		req.IsJoinApprovalRequired = *request.RequireApproval
	}
	if request.DisappearingTimer != nil {
		req.DisappearingTimer = *request.DisappearingTimer
		req.IsEphemeral = *request.DisappearingTimer > 0
	}
	info, err := client.CreateGroup(c.Request.Context(), req)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	warnings := []string{}
	if request.Topic != nil {
		if err = client.SetGroupTopic(c.Request.Context(), info.JID, "", "", *request.Topic); err != nil {
			warnings = append(warnings, err.Error())
		}
	}
	if request.Photo != nil {
		photo, _ := base64.StdEncoding.DecodeString(*request.Photo)
		if _, err = client.SetGroupPhoto(c.Request.Context(), info.JID, photo); err != nil {
			warnings = append(warnings, err.Error())
		}
	}
	response := groupSnapshot(client, info)
	response["warnings"] = warnings
	c.JSON(201, response)
}

func handleUpdateGroup(c *gin.Context) {
	var request groupMutation
	if c.ShouldBindJSON(&request) != nil {
		c.JSON(400, gin.H{"error": "Invalid group settings"})
		return
	}
	if err := request.validate(); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	jid, ok := parseJID(request.GroupJID)
	if !ok || !isGroupJID(jid) {
		c.JSON(400, gin.H{"error": "Invalid WhatsApp group"})
		return
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	info, err := client.GetGroupInfo(c.Request.Context(), jid)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	snapshot := groupSnapshot(client, info)
	permissionChange := request.AllowMemberEdit != nil || request.AllowMemberSend != nil || request.AllowMemberAdd != nil || request.RequireApproval != nil
	if (permissionChange && snapshot["self_is_admin"] != true) || (!permissionChange && snapshot["can_edit"] != true) {
		c.JSON(403, gin.H{"error": "Your WhatsApp account cannot change these group settings"})
		return
	}
	ctx := c.Request.Context()
	updates := []func() error{}
	if request.Name != nil {
		updates = append(updates, func() error { return client.SetGroupName(ctx, jid, *request.Name) })
	}
	if request.Topic != nil {
		updates = append(updates, func() error { return client.SetGroupTopic(ctx, jid, info.TopicID, "", *request.Topic) })
	}
	if request.AllowMemberEdit != nil {
		updates = append(updates, func() error { return client.SetGroupLocked(ctx, jid, !*request.AllowMemberEdit) })
	}
	if request.AllowMemberSend != nil {
		updates = append(updates, func() error { return client.SetGroupAnnounce(ctx, jid, !*request.AllowMemberSend) })
	}
	if request.AllowMemberAdd != nil {
		mode := types.GroupMemberAddModeAdmin
		if *request.AllowMemberAdd {
			mode = types.GroupMemberAddModeAllMember
		}
		updates = append(updates, func() error { return client.SetGroupMemberAddMode(ctx, jid, mode) })
	}
	if request.RequireApproval != nil {
		updates = append(updates, func() error { return client.SetGroupJoinApprovalMode(ctx, jid, *request.RequireApproval) })
	}
	if request.DisappearingTimer != nil {
		updates = append(updates, func() error {
			return client.SetDisappearingTimer(ctx, jid, time.Duration(*request.DisappearingTimer)*time.Second, time.Now())
		})
	}
	if request.Photo != nil {
		photo, _ := base64.StdEncoding.DecodeString(*request.Photo)
		updates = append(updates, func() error { _, err := client.SetGroupPhoto(ctx, jid, photo); return err })
	}
	for _, update := range updates {
		if err = update(); err != nil {
			c.JSON(502, gin.H{"error": err.Error(), "refresh_required": true})
			return
		}
	}
	groupNameMu.Lock()
	delete(groupNameCache, jid.String())
	groupNameMu.Unlock()
	if request.Photo != nil {
		profilePictureMu.Lock()
		delete(profilePictureCache, jid.String())
		profilePictureMu.Unlock()
	}
	info, err = client.GetGroupInfo(ctx, jid)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, groupSnapshot(client, info))
}

func handleGroupAction(c *gin.Context) {
	var request groupMutation
	if c.ShouldBindJSON(&request) != nil {
		c.JSON(400, gin.H{"error": "Invalid group action"})
		return
	}
	jid, ok := parseJID(request.GroupJID)
	if !ok || !isGroupJID(jid) {
		c.JSON(400, gin.H{"error": "Invalid WhatsApp group"})
		return
	}
	switch request.Operation {
	case "add", "remove", "promote", "demote", "approve", "reject", "invite", "reset_invite", "leave", "link_community":
	default:
		c.JSON(400, gin.H{"error": "Unsupported group action"})
		return
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	ctx := c.Request.Context()
	info, err := client.GetGroupInfo(ctx, jid)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	snapshot := groupSnapshot(client, info)
	if request.Operation != "leave" && snapshot["self_is_admin"] != true && !(request.Operation == "add" && snapshot["can_add_members"] == true) && request.Operation != "invite" {
		c.JSON(403, gin.H{"error": "WhatsApp group administrator permission is required"})
		return
	}
	response := gin.H{}
	switch request.Operation {
	case "invite", "reset_invite":
		response["invite_link"], err = client.GetGroupInviteLink(ctx, jid, request.Operation == "reset_invite")
	case "leave":
		err = client.LeaveGroup(ctx, jid)
		response["left"] = err == nil
	case "link_community":
		parent, valid := parseJID(request.CommunityJID)
		if !valid || !isGroupJID(parent) {
			c.JSON(400, gin.H{"error": "Invalid community"})
			return
		}
		err = client.LinkGroup(ctx, parent, jid)
	default:
		var targets []types.JID
		targets, err = groupMemberTargets(request.Participants)
		if err != nil || len(targets) == 0 {
			c.JSON(400, gin.H{"error": "Choose group participants"})
			return
		}
		var results []types.GroupParticipant
		if request.Operation == "approve" || request.Operation == "reject" {
			results, err = client.UpdateGroupRequestParticipants(ctx, jid, targets, whatsmeow.ParticipantRequestChange(request.Operation))
		} else {
			results, err = client.UpdateGroupParticipants(ctx, jid, targets, whatsmeow.ParticipantChange(request.Operation))
		}
		members := make([]GroupMemberResponse, 0, len(results))
		for _, participant := range results {
			members = append(members, buildGroupMemberResponse(client, participant, false))
		}
		response["participants"] = members
	}
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, response)
}

func handleGroupRequests(c *gin.Context) {
	jid, ok := parseJID(c.Query("group_jid"))
	if !ok || !isGroupJID(jid) {
		c.JSON(400, gin.H{"error": "Invalid WhatsApp group"})
		return
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	requests, err := client.GetGroupRequestParticipants(c.Request.Context(), jid)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	response := []gin.H{}
	for _, request := range requests {
		member := buildGroupMemberResponse(client, types.GroupParticipant{JID: request.JID}, false)
		response = append(response, gin.H{"member": member, "requested_at": request.RequestedAt.Unix()})
	}
	c.JSON(200, gin.H{"requests": response})
}
