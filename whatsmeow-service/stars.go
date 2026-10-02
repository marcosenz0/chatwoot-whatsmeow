package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/appstate"
	"github.com/polymorfa/hypermeow/proto/waWeb"
	"github.com/polymorfa/hypermeow/types"
	"github.com/polymorfa/hypermeow/types/events"
	"google.golang.org/protobuf/proto"
)

func connectedSession(c *gin.Context) *whatsmeow.Client {
	clientsMu.RLock()
	client := clients[c.Param("channel_id")]
	clientsMu.RUnlock()
	if client == nil || !client.IsConnected() || !client.IsLoggedIn() {
		c.JSON(http.StatusConflict, gin.H{"error": "WhatsApp session is not connected"})
		return nil
	}
	return client
}

func handleStarMessage(c *gin.Context) {
	var request struct {
		Chat      string `json:"chat" binding:"required"`
		Sender    string `json:"sender"`
		MessageID string `json:"message_id" binding:"required"`
		FromMe    bool   `json:"from_me"`
		Starred   *bool  `json:"starred" binding:"required"`
	}
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "chat, message_id and starred are required"})
		return
	}
	chat, ok := parseJID(request.Chat)
	if !ok || (chat.Server != types.GroupServer && chat.Server != types.DefaultUserServer && chat.Server != types.HiddenUserServer) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp chat"})
		return
	}
	sender := chat
	if isGroupJID(chat) {
		sender, ok = parseJID(request.Sender)
		if !request.FromMe && (!ok || (sender.Server != types.DefaultUserServer && sender.Server != types.HiddenUserServer)) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "A group message sender is required"})
			return
		}
	}
	client := connectedSession(c)
	if client == nil {
		return
	}
	if request.FromMe {
		sender = client.Store.GetJID().ToNonAD()
	}
	err := client.SendAppState(c.Request.Context(), appstate.BuildStar(chat.ToNonAD(), sender.ToNonAD(), request.MessageID, request.FromMe, *request.Starred))
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("Could not update WhatsApp star: %v", err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"starred": *request.Starred})
}

func handleSyncStars(c *gin.Context) {
	client := connectedSession(c)
	if client == nil {
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Minute)
	defer cancel()
	if err := client.FetchAppState(ctx, appstate.WAPatchRegularHigh, true, false); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("Could not synchronize starred messages: %v", err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "synchronized"})
}

func processStarForInbox(inbox, account string, client *whatsmeow.Client, star *events.Star) {
	chat := star.ChatJID.ToNonAD()
	if !isGroupJID(chat) {
		chat = resolvePhoneJID(client, chat)
	}
	if chat.IsEmpty() || star.Action == nil {
		return
	}
	timestamp := star.Timestamp
	if timestamp.IsZero() {
		timestamp = time.Now()
	}
	payload := map[string]interface{}{
		"event": "star", "chat": chat.String(), "message_id": star.MessageID,
		"starred": star.Action.GetStarred(), "timestamp": timestamp.Unix(),
	}
	if err := sendHistoryWebhook(account, inbox, payload); err != nil {
		log.Printf("Could not import message star for inbox %s: %v", inbox, err)
		return
	}
	if !star.Action.GetStarred() {
		return
	}
	var exists bool
	err := statusLookupDB.QueryRow("SELECT EXISTS(SELECT 1 FROM messages WHERE inbox_id=$1 AND source_id=$2)", inbox, star.MessageID).Scan(&exists)
	if err != nil || exists {
		return
	}
	var data []byte
	err = statusLookupDB.QueryRow("SELECT payload FROM whatsmeow_history_messages WHERE inbox_id=$1 AND message_id=$2", inbox, star.MessageID).Scan(&data)
	if err == sql.ErrNoRows {
		// Ask the primary device for the original message without sending anything to the chat.
		_, err = client.SendPeerMessage(context.Background(), client.BuildUnavailableMessageRequest(star.ChatJID, star.SenderJID, star.MessageID))
	} else if err == nil {
		web := &waWeb.WebMessageInfo{}
		err = proto.Unmarshal(data, web)
		if err == nil {
			var message *events.Message
			message, err = client.ParseWebMessage(chat, web)
			if err == nil && message != nil {
				err = processMessageForInbox(inbox, account, client, message, true)
			}
		}
	}
	if err != nil {
		log.Printf("Could not recover starred message for inbox %s: %v", inbox, err)
	}
}
