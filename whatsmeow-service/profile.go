package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"image/jpeg"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/appstate"
	"github.com/polymorfa/hypermeow/types"
)

type profileClient interface {
	GetUserInfo(context.Context, []types.JID) (map[types.JID]types.UserInfo, error)
	GetProfilePictureInfo(context.Context, types.JID, *whatsmeow.GetProfilePictureParams) (*types.ProfilePictureInfo, error)
	GetBusinessProfile(context.Context, types.JID) (*types.BusinessProfile, error)
	UpdateBusinessProfile(context.Context, types.BusinessProfileUpdate) error
	SetStatusMessage(context.Context, types.SetStatusInput) error
	SendAppState(context.Context, appstate.PatchInfo) error
	SetGroupPhoto(context.Context, types.JID, []byte) (string, error)
}

type profileMutation struct {
	Name     *string                  `json:"name"`
	About    *string                  `json:"about"`
	Business *businessProfileMutation `json:"business"`
}

type businessProfileMutation struct {
	Address     *string                `json:"address"`
	Email       *string                `json:"email"`
	Description *string                `json:"description"`
	Websites    *[]string              `json:"websites"`
	Hours       *businessHoursMutation `json:"hours"`
}

type businessHoursMutation struct {
	TimeZone string                `json:"timezone"`
	Days     []businessDayMutation `json:"days"`
}

type businessDayMutation struct {
	Day   string `json:"day"`
	Mode  string `json:"mode"`
	Open  int    `json:"open"`
	Close int    `json:"close"`
}

func (m profileMutation) validate() error {
	if m.Name == nil && m.About == nil && m.Business == nil {
		return fmt.Errorf("Profile update is empty")
	}
	if m.Name != nil && (strings.TrimSpace(*m.Name) == "" || utf8.RuneCountInString(*m.Name) > 25) {
		return fmt.Errorf("Name must contain 1 to 25 characters")
	}
	if m.About != nil && utf8.RuneCountInString(*m.About) > 139 {
		return fmt.Errorf("About must contain at most 139 characters")
	}
	return nil
}

func (m businessProfileMutation) update() types.BusinessProfileUpdate {
	u := types.BusinessProfileUpdate{Address: m.Address, Email: m.Email, Description: m.Description, Websites: m.Websites}
	if m.Hours != nil {
		u.Hours = &types.BusinessHoursUpdate{TimeZone: m.Hours.TimeZone}
		for _, d := range m.Hours.Days {
			u.Hours.Days = append(u.Hours.Days, types.BusinessHoursDay{DayOfWeek: d.Day, Mode: d.Mode, OpenTime: d.Open, CloseTime: d.Close})
		}
	}
	return u
}

func currentProfilePicture(ctx context.Context, client profileClient, jid types.JID) (gin.H, error) {
	info, err := client.GetProfilePictureInfo(ctx, jid.ToNonAD(), &whatsmeow.GetProfilePictureParams{Preview: false})
	if errors.Is(err, whatsmeow.ErrProfilePictureNotSet) {
		return gin.H{"photo_url": "", "photo_status": "none"}, nil
	}
	if errors.Is(err, whatsmeow.ErrProfilePictureUnauthorized) {
		return gin.H{"photo_url": "", "photo_status": "hidden"}, nil
	}
	if err != nil {
		return nil, err
	}
	if info == nil {
		return gin.H{"photo_url": "", "photo_status": "none"}, nil
	}
	return gin.H{"photo_url": info.URL, "photo_status": "available"}, nil
}

func ownProfileSnapshot(ctx context.Context, client profileClient, jid types.JID, name, businessName string) (gin.H, error) {
	jid = jid.ToNonAD()
	users, err := client.GetUserInfo(ctx, []types.JID{jid})
	if err != nil {
		return nil, err
	}
	info, ok := users[jid]
	if !ok {
		return nil, fmt.Errorf("WhatsApp did not return the connected profile")
	}
	photo, err := currentProfilePicture(ctx, client, jid)
	if err != nil {
		return nil, err
	}
	photo["name"], photo["about"], photo["phone"] = name, info.Status, "+"+jid.User
	photo["is_business"] = info.VerifiedName != nil || businessName != ""
	if photo["is_business"] == true {
		business, err := client.GetBusinessProfile(ctx, jid)
		if err != nil {
			return nil, err
		}
		days := []gin.H{}
		for _, d := range business.BusinessHours {
			days = append(days, gin.H{"day": d.DayOfWeek, "mode": d.Mode, "open": d.OpenTime, "close": d.CloseTime})
		}
		photo["business"] = gin.H{"address": business.Address, "email": business.Email, "description": business.Description, "websites": business.Websites,
			"categories": business.Categories, "hours": gin.H{"timezone": business.BusinessHoursTimeZone, "days": days}}
	}
	return photo, nil
}

func handleOwnProfile(c *gin.Context) {
	client := connectedSession(c)
	if client == nil {
		return
	}
	profile, err := ownProfileSnapshot(c.Request.Context(), client, *client.Store.ID, client.Store.PushName, client.Store.BusinessName)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, profile)
}

func handleUpdateOwnProfile(c *gin.Context) {
	client := connectedSession(c)
	if client == nil {
		return
	}
	var m profileMutation
	if err := c.ShouldBindJSON(&m); err != nil {
		c.JSON(400, gin.H{"error": "Invalid profile update"})
		return
	}
	if err := m.validate(); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	ctx := c.Request.Context()
	// Business updates are restricted to the connected account, never a caller-supplied JID.
	if m.Business != nil {
		users, err := client.GetUserInfo(ctx, []types.JID{client.Store.ID.ToNonAD()})
		if err != nil {
			c.JSON(502, gin.H{"error": err.Error()})
			return
		}
		if users[client.Store.ID.ToNonAD()].VerifiedName == nil && client.Store.BusinessName == "" {
			c.JSON(400, gin.H{"error": "This is not a WhatsApp Business profile"})
			return
		}
		if err := client.UpdateBusinessProfile(ctx, m.Business.update()); err != nil {
			c.JSON(422, gin.H{"error": err.Error()})
			return
		}
	}
	if m.About != nil {
		if err := client.SetStatusMessage(ctx, types.SetStatusInput{Text: m.About}); err != nil {
			c.JSON(502, gin.H{"error": err.Error()})
			return
		}
	}
	if m.Name != nil {
		if err := client.SendAppState(ctx, appstate.BuildSettingPushName(*m.Name)); err != nil {
			c.JSON(502, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(200, gin.H{"success": true})
}

func decodeProfilePhoto(value string) ([]byte, error) {
	if len(value) > 3*1024*1024 {
		return nil, fmt.Errorf("Photo must be a JPEG under 2 MB")
	}
	data, err := base64.StdEncoding.DecodeString(value)
	if err != nil || len(data) == 0 || len(data) > 2*1024*1024 || http.DetectContentType(data) != "image/jpeg" {
		return nil, fmt.Errorf("Photo must be a JPEG under 2 MB")
	}
	config, err := jpeg.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width != config.Height || config.Width < 192 || config.Width > 2048 {
		return nil, fmt.Errorf("Photo must be square, between 192 and 2048 pixels")
	}
	return data, nil
}

func handleOwnProfilePhoto(c *gin.Context) {
	client := connectedSession(c)
	if client == nil {
		return
	}
	var err error
	if c.Request.Method == http.MethodPut {
		var body struct {
			Photo string `json:"photo"`
		}
		if c.ShouldBindJSON(&body) != nil {
			c.JSON(400, gin.H{"error": "Invalid photo"})
			return
		}
		data, decodeErr := decodeProfilePhoto(body.Photo)
		if decodeErr != nil {
			c.JSON(400, gin.H{"error": decodeErr.Error()})
			return
		}
		_, err = client.SetGroupPhoto(c.Request.Context(), types.EmptyJID, data)
	} else if c.Request.Method == http.MethodDelete {
		_, err = client.SetGroupPhoto(c.Request.Context(), types.EmptyJID, nil)
	}
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	photo, err := currentProfilePicture(c.Request.Context(), client, *client.Store.ID)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	setCachedProfilePicture(client.Store.ID.ToNonAD().String(), photo["photo_url"].(string), 0)
	c.JSON(200, photo)
}

func handleFullProfilePhoto(c *gin.Context) {
	jid, ok := parseJID(c.Query("jid"))
	if !ok {
		c.JSON(400, gin.H{"error": "Invalid WhatsApp JID"})
		return
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	photo, err := currentProfilePicture(c.Request.Context(), client, jid)
	if err != nil {
		c.JSON(502, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, photo)
}
