package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
	"github.com/skip2/go-qrcode"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/binary/proto"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// Active clients map
var (
	clients             = make(map[string]*whatsmeow.Client)
	clientsMu           sync.RWMutex
	qrCodes             = make(map[string]string)
	qrCodesMu           sync.RWMutex
	profilePictureCache = make(map[string]cacheEntry)
	profilePictureMu    sync.RWMutex
	groupNameCache      = make(map[string]cacheEntry)
	groupNameMu         sync.RWMutex
	dbContainer         *sqlstore.Container
	webhookURL          string
)

type cacheEntry struct {
	Value     string
	ExpiresAt time.Time
}

type SessionRequest struct {
	ChannelID string `json:"channel_id" binding:"required"`
	AccountID string `json:"account_id" binding:"required"`
}

type MessageRequest struct {
	ChannelID string `json:"channel_id" binding:"required"`
	To        string `json:"to" binding:"required"`
	Body      string `json:"body" binding:"required"`
}

func main() {
	// Initialize configurations
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		// Fallback staging DB URI
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	webhookURL = os.Getenv("WEBHOOK_URL")
	if webhookURL == "" {
		webhookURL = "http://chatwoot-staging:3000/api/v1/accounts/%s/whatsmeow/%s/callback"
	}

	log.Println("Initializing Whatsmeow Go Service...")

	// Connect to database
	var err error
	dbContainer, err = sqlstore.New(context.Background(), "postgres", dbURI, waLog.Stdout("Database", "DEBUG", true))
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Auto-restore previous logins
	go restoreSessions()

	// Start presence ticker for Always Online
	startPresenceTicker()

	// Initialize Gin
	r := gin.Default()
	r.Use(corsMiddleware())

	// Healthcheck
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "healthy"})
	})

	// Endpoints
	r.POST("/sessions", handleCreateSession)
	r.GET("/sessions/:channel_id/qr", handleGetQR)
	r.GET("/sessions/:channel_id/status", handleGetStatus)
	r.DELETE("/sessions/:channel_id", handleDisconnectSession)
	r.POST("/messages", handleSendMessage)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Whatsmeow Go Service listening on port %s", port)
	r.Run(":" + port)
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

type WhatsmeowSettings struct {
	AlwaysOnline bool `json:"always_online"`
	ReadMessages bool `json:"read_messages"`
	RejectCalls  bool `json:"reject_calls"`
	IgnoreGroups bool `json:"ignore_groups"`
	IgnoreStatus bool `json:"ignore_status"`
	IgnoreNews   bool `json:"ignore_newsletters"`
	Newsletter   bool `json:"newsletter"`
}

func getChannelSettings(inboxID string) (WhatsmeowSettings, error) {
	var settings WhatsmeowSettings
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		return settings, err
	}
	defer db.Close()

	query := `
		SELECT c.always_online, c.read_messages, c.reject_calls, c.ignore_groups, c.ignore_status, c.ignore_newsletters, c.newsletter
		FROM inboxes i 
		JOIN channel_whatsmeow c ON i.channel_id = c.id 
		WHERE i.id = $1 AND i.channel_type = 'Channel::Whatsmeow'
		LIMIT 1
	`
	var alwaysOnline, readMessages, rejectCalls, ignoreGroups, ignoreStatus, ignoreNews, newsletter bool
	err = db.QueryRow(query, inboxID).Scan(
		&alwaysOnline,
		&readMessages,
		&rejectCalls,
		&ignoreGroups,
		&ignoreStatus,
		&ignoreNews,
		&newsletter,
	)
	if err != nil {
		return settings, err
	}

	settings.AlwaysOnline = alwaysOnline
	settings.ReadMessages = readMessages
	settings.RejectCalls = rejectCalls
	settings.IgnoreGroups = ignoreGroups
	settings.IgnoreStatus = ignoreStatus
	settings.IgnoreNews = ignoreNews
	settings.Newsletter = newsletter

	return settings, nil
}

func startPresenceTicker() {
	ticker := time.NewTicker(60 * time.Second)
	go func() {
		for range ticker.C {
			clientsMu.RLock()
			for channelID, client := range clients {
				if client.IsConnected() && client.IsLoggedIn() {
					settings, err := getChannelSettings(channelID)
					if err == nil && settings.AlwaysOnline {
						err := client.SendPresence(context.Background(), types.PresenceAvailable)
						if err != nil {
							log.Printf("Failed to send presence for channel %s: %v", channelID, err)
						}
					}
				}
			}
			clientsMu.RUnlock()
		}
	}()
}

func lookupInboxAndAccount(phone string) (string, string, error) {
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		return "", "", err
	}
	defer db.Close()

	var inboxID int
	var accountID int
	query := `
		SELECT i.id, i.account_id 
		FROM inboxes i 
		JOIN channel_whatsmeow c ON i.channel_id = c.id 
		WHERE i.channel_type = 'Channel::Whatsmeow' 
		  AND (c.phone_number = $1 OR c.phone_number = '+' || $1)
		LIMIT 1
	`
	err = db.QueryRow(query, phone).Scan(&inboxID, &accountID)
	if err != nil {
		return "", "", err
	}

	return fmt.Sprintf("%d", inboxID), fmt.Sprintf("%d", accountID), nil
}

func lookupAllInboxesAndAccounts(phone string) ([]string, []string, error) {
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		return nil, nil, err
	}
	defer db.Close()

	query := `
		SELECT i.id, i.account_id 
		FROM inboxes i 
		JOIN channel_whatsmeow c ON i.channel_id = c.id 
		WHERE i.channel_type = 'Channel::Whatsmeow' 
		  AND (c.phone_number = $1 OR c.phone_number = '+' || $1)
	`
	rows, err := db.Query(query, phone)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var inboxIDs []string
	var accountIDs []string
	for rows.Next() {
		var inboxID int
		var accountID int
		if err := rows.Scan(&inboxID, &accountID); err == nil {
			inboxIDs = append(inboxIDs, fmt.Sprintf("%d", inboxID))
			accountIDs = append(accountIDs, fmt.Sprintf("%d", accountID))
		}
	}

	return inboxIDs, accountIDs, nil
}

func updateAllChannelsStatusByPhone(phone string, status string) {
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		log.Printf("Failed to open database to update status: %v", err)
		return
	}
	defer db.Close()

	query := `
		UPDATE channel_whatsmeow 
		SET status = $1 
		WHERE phone_number = $2 OR phone_number = '+' || $2
	`
	_, err = db.Exec(query, status, phone)
	if err != nil {
		log.Printf("Failed to update status in database for phone %s: %v", phone, err)
	} else {
		log.Printf("Updated channels with phone %s status to %s in database", phone, status)
	}
}

func updateChannelStatus(channelID string, status string) {
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		log.Printf("Failed to open database to update status: %v", err)
		return
	}
	defer db.Close()

	query := `
		UPDATE channel_whatsmeow c 
		SET status = $1 
		FROM inboxes i 
		WHERE i.channel_id = c.id AND i.id = $2 AND i.channel_type = 'Channel::Whatsmeow'
	`
	_, err = db.Exec(query, status, channelID)
	if err != nil {
		log.Printf("Failed to update status in database for channel %s: %v", channelID, err)
	} else {
		log.Printf("Updated channel %s status to %s in database", channelID, status)
	}
}

func restoreSessions() {
	devices, err := dbContainer.GetAllDevices(context.Background())
	if err != nil {
		log.Printf("Failed to retrieve logins for restoration: %v", err)
		return
	}

	log.Printf("Found %d saved device sessions to restore.", len(devices))
	for _, device := range devices {
		log.Printf("Restoring session for JID: %s JIDUser: %s", device.ID.String(), device.ID.User)

		phone := device.ID.User
		inboxIDs, accountIDs, err := lookupAllInboxesAndAccounts(phone)
		if err != nil || len(inboxIDs) == 0 {
			log.Printf("Failed to lookup inbox/account for device JID %s: %v. Using fallback.", device.ID.User, err)
			inboxIDs = []string{phone}
			accountIDs = []string{"1"}
		} else {
			log.Printf("Found mapped Inbox IDs: %v, Account IDs: %v for JID: %s", inboxIDs, accountIDs, device.ID.User)
		}

		client := whatsmeow.NewClient(device, waLog.Stdout("WhatsmeowClient", "INFO", true))

		err = client.Connect()
		if err != nil {
			log.Printf("Failed to connect restored client %s: %v", device.ID.String(), err)
			updateAllChannelsStatusByPhone(phone, "disconnected")
			continue
		}

		updateAllChannelsStatusByPhone(phone, "connected")

		// Store client mapping for all associated inboxes
		clientsMu.Lock()
		for _, inboxID := range inboxIDs {
			clients[inboxID] = client
		}
		clientsMu.Unlock()

		// Register event handler
		client.AddEventHandler(func(evt interface{}) {
			eventHandler(client, evt)
		})

		log.Printf("Successfully restored and connected: %s (inboxes: %v)", device.ID.String(), inboxIDs)
	}
}

func handleCreateSession(c *gin.Context) {
	var req SessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if already active
	clientsMu.RLock()
	client, exists := clients[req.ChannelID]
	clientsMu.RUnlock()

	if exists {
		if client.IsConnected() {
			c.JSON(http.StatusOK, gin.H{
				"status":     "connected",
				"channel_id": req.ChannelID,
				"message":    "Session already connected",
			})
			return
		}
	}

	// Create new client store
	deviceStore, err := dbContainer.GetFirstDevice(context.Background())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to get device store: %v", err)})
		return
	}
	if deviceStore == nil {
		deviceStore = dbContainer.NewDevice()
	}

	client = whatsmeow.NewClient(deviceStore, waLog.Stdout("WhatsmeowClient", "DEBUG", true))
	clientsMu.Lock()
	clients[req.ChannelID] = client
	clientsMu.Unlock()

	// Start connection and listen for QR code
	if client.Store.ID == nil {
		// New login, register QR channel
		qrChan, err := client.GetQRChannel(context.Background())
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to get QR channel: %v", err)})
			return
		}

		err = client.Connect()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to connect: %v", err)})
			return
		}

		// Handle QR generation in background
		go func() {
			for qrEvt := range qrChan {
				if qrEvt.Event == "code" {
					log.Printf("New QR Code generated for channel %s", req.ChannelID)
					// Generate base64 PNG image of QR Code
					png, err := qrcode.Encode(qrEvt.Code, qrcode.Medium, 256)
					if err == nil {
						base64Img := base64.StdEncoding.EncodeToString(png)
						qrCodesMu.Lock()
						qrCodes[req.ChannelID] = "data:image/png;base64," + base64Img
						qrCodesMu.Unlock()
					}
				} else if qrEvt.Event == "success" {
					log.Printf("Successfully paired channel %s", req.ChannelID)
					qrCodesMu.Lock()
					delete(qrCodes, req.ChannelID)
					qrCodesMu.Unlock()

					// Wait a brief moment for Client Store ID to populate
					time.Sleep(1 * time.Second)
					if client.Store.ID != nil {
						phone := client.Store.ID.User
						inboxIDs, _, _ := lookupAllInboxesAndAccounts(phone)
						clientsMu.Lock()
						for _, ibID := range inboxIDs {
							clients[ibID] = client
						}
						clientsMu.Unlock()
						updateAllChannelsStatusByPhone(phone, "connected")
					} else {
						updateChannelStatus(req.ChannelID, "connected")
					}

					// Send webhook success to Rails
					sendWebhookNotification(req.AccountID, req.ChannelID, map[string]interface{}{
						"event":  "paired",
						"status": "success",
					})
				}
			}
		}()

		// Wait briefly for first QR code to be generated
		time.Sleep(1 * time.Second)

		qrCodesMu.RLock()
		qrCodeBase64 := qrCodes[req.ChannelID]
		qrCodesMu.RUnlock()

		c.JSON(http.StatusOK, gin.H{
			"status":     "pairing",
			"channel_id": req.ChannelID,
			"qr_code":    qrCodeBase64,
		})
	} else {
		// Restore connection
		err = client.Connect()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to connect: %v", err)})
			updateChannelStatus(req.ChannelID, "disconnected")
			return
		}

		if client.Store.ID != nil {
			phone := client.Store.ID.User
			inboxIDs, _, _ := lookupAllInboxesAndAccounts(phone)
			clientsMu.Lock()
			for _, ibID := range inboxIDs {
				clients[ibID] = client
			}
			clientsMu.Unlock()
			updateAllChannelsStatusByPhone(phone, "connected")
		} else {
			updateChannelStatus(req.ChannelID, "connected")
		}

		c.JSON(http.StatusOK, gin.H{
			"status":     "connected",
			"channel_id": req.ChannelID,
		})
	}

	// Register event handler for incoming messages
	client.AddEventHandler(func(evt interface{}) {
		eventHandler(client, evt)
	})
}

func handleGetQR(c *gin.Context) {
	channelID := c.Param("channel_id")

	qrCodesMu.RLock()
	qrCodeBase64, exists := qrCodes[channelID]
	qrCodesMu.RUnlock()

	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "No active QR Code found for this channel. Start session first."})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"qr_code": qrCodeBase64,
	})
}

func handleGetStatus(c *gin.Context) {
	channelID := c.Param("channel_id")

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists {
		c.JSON(http.StatusOK, gin.H{"status": "disconnected"})
		return
	}

	status := "disconnected"
	if client.IsConnected() && client.IsLoggedIn() {
		status = "connected"
	} else if client.IsConnected() {
		status = "connecting"
	}

	qrCodesMu.RLock()
	qrCodeBase64 := qrCodes[channelID]
	qrCodesMu.RUnlock()

	payload := gin.H{
		"status": status,
		"jid":    client.Store.ID,
	}
	if qrCodeBase64 != "" {
		payload["qr_code"] = qrCodeBase64
	}

	c.JSON(http.StatusOK, payload)
}

func handleDisconnectSession(c *gin.Context) {
	channelID := c.Param("channel_id")

	clientsMu.Lock()
	client, exists := clients[channelID]
	if exists {
		client.Disconnect()
		if client.Store.ID != nil {
			phone := client.Store.ID.User
			inboxIDs, _, _ := lookupAllInboxesAndAccounts(phone)
			for _, ibID := range inboxIDs {
				delete(clients, ibID)
			}
			updateAllChannelsStatusByPhone(phone, "disconnected")
		} else {
			updateChannelStatus(channelID, "disconnected")
		}
		delete(clients, channelID)
	} else {
		updateChannelStatus(channelID, "disconnected")
	}
	clientsMu.Unlock()

	qrCodesMu.Lock()
	delete(qrCodes, channelID)
	qrCodesMu.Unlock()

	c.JSON(http.StatusOK, gin.H{
		"status":  "disconnected",
		"message": "Session terminated",
	})
}

func handleSendMessage(c *gin.Context) {
	var req MessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	clientsMu.RLock()
	client, exists := clients[req.ChannelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	// Parse target JID
	targetJID, ok := parseJID(req.To)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target phone number / JID"})
		return
	}

	// Send message
	msg := &proto.Message{
		Conversation: &req.Body,
	}
	resp, err := client.SendMessage(context.Background(), targetJID, msg)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to send message: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"id":        resp.ID,
		"timestamp": resp.Timestamp.Unix(),
	})
}

func parseJID(phone string) (types.JID, bool) {
	if phone == "" {
		return types.JID{}, false
	}
	// Target formats: e.g. "5511999999999", "5511999999999@s.whatsapp.net", or a platform JID.
	if strings.Contains(phone, "@") {
		jid, err := types.ParseJID(phone)
		return jid, err == nil
	}
	return types.NewJID(phone, types.DefaultUserServer), true
}

func eventHandler(client *whatsmeow.Client, evt interface{}) {
	if client.Store.ID == nil {
		return
	}
	phone := client.Store.ID.User

	switch evt.(type) {
	case *events.Connected:
		log.Printf("Client %s connected. Updating statuses to connected.", phone)
		updateAllChannelsStatusByPhone(phone, "connected")
	case *events.Disconnected:
		log.Printf("Client %s disconnected. Updating statuses to disconnected.", phone)
		updateAllChannelsStatusByPhone(phone, "disconnected")
	case *events.LoggedOut:
		log.Printf("Client %s logged out. Updating statuses to disconnected.", phone)
		updateAllChannelsStatusByPhone(phone, "disconnected")
	}

	inboxIDs, accountIDs, err := lookupAllInboxesAndAccounts(phone)
	if err != nil || len(inboxIDs) == 0 {
		log.Printf("No inboxes found for phone %s: %v", phone, err)
		return
	}

	for idx, inboxID := range inboxIDs {
		accountID := accountIDs[idx]
		processEventForInbox(inboxID, accountID, client, evt)
	}
}

func processEventForInbox(channelID string, accountID string, client *whatsmeow.Client, evt interface{}) {
	switch v := evt.(type) {
	case *events.CallOffer:
		settings, err := getChannelSettings(channelID)
		if err == nil && settings.RejectCalls {
			err := client.RejectCall(context.Background(), v.From, v.CallID)
			if err != nil {
				log.Printf("Failed to reject call %s from %s: %v", v.CallID, v.From.String(), err)
			} else {
				log.Printf("Successfully rejected incoming call %s from %s", v.CallID, v.From.String())
			}
		}

	case *events.Message:
		processMessageForInbox(channelID, accountID, client, v)

	case *events.Receipt:
		processReceiptForInbox(channelID, accountID, v)

	case *events.HistorySync:
		processHistorySyncForInbox(channelID, accountID, client, v)
	}
}

func processReceiptForInbox(channelID string, accountID string, receipt *events.Receipt) {
	status := receiptStatus(receipt.Type)
	if status == "" || len(receipt.MessageIDs) == 0 {
		return
	}

	messageIDs := make([]string, 0, len(receipt.MessageIDs))
	for _, messageID := range receipt.MessageIDs {
		if messageID != "" {
			messageIDs = append(messageIDs, string(messageID))
		}
	}
	if len(messageIDs) == 0 {
		return
	}

	payload := map[string]interface{}{
		"event":        "receipt",
		"status":       status,
		"message_ids":  messageIDs,
		"receipt_type": string(receipt.Type),
		"chat":         jidString(receipt.Chat),
		"sender":       jidString(receipt.Sender),
		"timestamp":    receipt.Timestamp.Unix(),
	}
	sendWebhookNotification(accountID, channelID, payload)
}

func receiptStatus(receiptType types.ReceiptType) string {
	switch receiptType {
	case types.ReceiptTypeDelivered:
		return "delivered"
	case types.ReceiptTypeRead, types.ReceiptTypePlayed:
		return "read"
	default:
		return ""
	}
}

func processHistorySyncForInbox(channelID string, accountID string, client *whatsmeow.Client, historySync *events.HistorySync) {
	if historySync.Data == nil {
		return
	}

	cutoff := time.Now().Add(-72 * time.Hour)
	processed := 0
	for _, conversation := range historySync.Data.GetConversations() {
		chatJID, ok := parseHistoryChatJID(conversation.GetID(), conversation.GetPnJID(), conversation.GetLidJID())
		if !ok {
			log.Printf("Skipping history sync conversation with invalid JID on channel %s: %s", channelID, conversation.GetID())
			continue
		}

		for _, historyMessage := range conversation.GetMessages() {
			webMessage := historyMessage.GetMessage()
			if webMessage == nil {
				continue
			}

			messageEvent, err := client.ParseWebMessage(chatJID, webMessage)
			if err != nil {
				log.Printf("Failed to parse history sync message for %s on channel %s: %v", chatJID.String(), channelID, err)
				continue
			}
			if messageEvent == nil || messageEvent.Info.Timestamp.Before(cutoff) {
				continue
			}

			processMessageForInbox(channelID, accountID, client, messageEvent)
			processed++
		}
	}

	if processed > 0 {
		log.Printf("Processed %d recent history sync messages on channel %s", processed, channelID)
	}
}

func parseHistoryChatJID(ids ...string) (types.JID, bool) {
	for _, id := range ids {
		if id == "" {
			continue
		}
		jid, err := types.ParseJID(id)
		if err == nil {
			return jid, true
		}
	}
	return types.JID{}, false
}

func processMessageForInbox(channelID string, accountID string, client *whatsmeow.Client, messageEvent *events.Message) {
	settings, err := getChannelSettings(channelID)
	if err == nil {
		isGroup := messageEvent.Info.MessageSource.IsGroup || messageEvent.Info.Sender.Server == "g.us" || messageEvent.Info.Chat.Server == "g.us"
		if settings.IgnoreGroups && isGroup {
			log.Printf("Ignoring group message from %s on channel %s (IgnoreGroups=true)", messageEvent.Info.Sender.String(), channelID)
			return
		}
		isStatus := messageEvent.Info.Chat.Server == "broadcast" || messageEvent.Info.Sender.Server == "broadcast"
		if settings.IgnoreStatus && isStatus {
			log.Printf("Ignoring status update from %s on channel %s (IgnoreStatus=true)", messageEvent.Info.Sender.String(), channelID)
			return
		}
		isNewsletter := isNewsletterJID(messageEvent.Info.Chat) || isNewsletterJID(messageEvent.Info.Sender) || isNewsletterJID(messageEvent.Info.SenderAlt)
		if settings.IgnoreNews && isNewsletter {
			log.Printf("Ignoring newsletter message from %s on channel %s (IgnoreNewsletters=true)", messageEvent.Info.Sender.String(), channelID)
			return
		}
	}

	messageText := extractMessageText(messageEvent.Message)
	if messageText == "" {
		return
	}

	isGroup := isGroupMessage(messageEvent.Info)
	contactJID := preferredContactJID(messageEvent.Info)
	participantJID := types.JID{}
	groupName := ""
	if isGroup {
		contactJID = messageEvent.Info.Chat.ToNonAD()
		participantJID = firstUsableJID(messageEvent.Info.SenderAlt, messageEvent.Info.Sender)
		groupName = getGroupName(client, contactJID)
	}

	sender := jidString(contactJID)
	if sender == "" {
		sender = jidString(messageEvent.Info.Chat)
	}

	log.Printf("Received message from %s on channel %s: %s", sender, channelID, messageText)

	// Mark message as read if auto-read is enabled
	if !messageEvent.Info.IsFromMe && err == nil && settings.ReadMessages {
		err := client.MarkRead(
			context.Background(),
			[]types.MessageID{messageEvent.Info.ID},
			messageEvent.Info.Timestamp,
			messageEvent.Info.Chat,
			messageEvent.Info.Sender,
		)
		if err != nil {
			log.Printf("Failed to mark message %s as read: %v", messageEvent.Info.ID, err)
		} else {
			log.Printf("Automatically marked message %s as read", messageEvent.Info.ID)
		}
	}

	senderName := messageEvent.Info.PushName
	if isGroup && groupName != "" {
		senderName = groupName
	}

	payload := map[string]interface{}{
		"event":               "message",
		"sender":              sender,
		"sender_alt":          jidString(messageEvent.Info.SenderAlt),
		"sender_name":         senderName,
		"sender_phone":        phoneNumberFromJID(contactJID),
		"profile_picture_url": getProfilePictureURL(client, contactJID),
		"chat":                jidString(messageEvent.Info.Chat),
		"chat_phone":          phoneNumberFromJID(messageEvent.Info.Chat),
		"recipient_alt":       jidString(messageEvent.Info.RecipientAlt),
		"from_me":             messageEvent.Info.IsFromMe,
		"message_id":          messageEvent.Info.ID,
		"content":             messageText,
		"timestamp":           messageEvent.Info.Timestamp.Unix(),
	}
	if isGroup {
		payload["is_group"] = true
		payload["group_jid"] = jidString(contactJID)
		payload["group_name"] = groupName
		payload["participant_jid"] = jidString(participantJID)
		payload["participant_name"] = messageEvent.Info.PushName
		payload["participant_phone"] = phoneNumberFromJID(participantJID)
		payload["participant_profile_picture_url"] = getProfilePictureURL(client, participantJID)
	}
	sendWebhookNotification(accountID, channelID, payload)
}

func extractMessageText(message *proto.Message) string {
	if message == nil {
		return ""
	}
	if text := message.GetConversation(); text != "" {
		return text
	}
	if text := message.GetExtendedTextMessage().GetText(); text != "" {
		return text
	}
	if text := message.GetImageMessage().GetCaption(); text != "" {
		return text
	}
	if text := message.GetVideoMessage().GetCaption(); text != "" {
		return text
	}
	if text := message.GetDocumentMessage().GetCaption(); text != "" {
		return text
	}
	if inner := message.GetEphemeralMessage().GetMessage(); inner != nil {
		return extractMessageText(inner)
	}
	if inner := message.GetViewOnceMessage().GetMessage(); inner != nil {
		return extractMessageText(inner)
	}
	if inner := message.GetViewOnceMessageV2().GetMessage(); inner != nil {
		return extractMessageText(inner)
	}
	if inner := message.GetViewOnceMessageV2Extension().GetMessage(); inner != nil {
		return extractMessageText(inner)
	}
	if inner := message.GetDocumentWithCaptionMessage().GetMessage(); inner != nil {
		return extractMessageText(inner)
	}
	return ""
}

func preferredContactJID(info types.MessageInfo) types.JID {
	if info.IsFromMe {
		return firstUsableJID(info.RecipientAlt, info.Chat, info.SenderAlt, info.Sender)
	}
	return firstUsableJID(info.SenderAlt, info.Sender, info.Chat)
}

func isGroupMessage(info types.MessageInfo) bool {
	return info.MessageSource.IsGroup || isGroupJID(info.Sender) || isGroupJID(info.Chat)
}

func isGroupJID(jid types.JID) bool {
	return jid.Server == "g.us"
}

func firstUsableJID(candidates ...types.JID) types.JID {
	for _, jid := range candidates {
		if isPhoneJID(jid) {
			return jid.ToNonAD()
		}
	}
	for _, jid := range candidates {
		if !jid.IsEmpty() {
			return jid.ToNonAD()
		}
	}
	return types.JID{}
}

func isPhoneJID(jid types.JID) bool {
	return jid.Server == types.DefaultUserServer && isNumericUser(jid.User)
}

func isNewsletterJID(jid types.JID) bool {
	if jid.IsEmpty() {
		return false
	}
	return strings.EqualFold(jid.Server, "newsletter") || strings.Contains(strings.ToLower(jid.String()), "@newsletter")
}

func isNumericUser(user string) bool {
	user = strings.Split(user, ":")[0]
	if user == "" {
		return false
	}
	for _, r := range user {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func phoneNumberFromJID(jid types.JID) string {
	if !isPhoneJID(jid) {
		return ""
	}
	return "+" + strings.Split(jid.User, ":")[0]
}

func getGroupName(client *whatsmeow.Client, jid types.JID) string {
	if !isGroupJID(jid) {
		return ""
	}

	cacheKey := jidString(jid)
	groupNameMu.RLock()
	cached, ok := groupNameCache[cacheKey]
	groupNameMu.RUnlock()
	if ok && cached.ExpiresAt.After(time.Now()) {
		return cached.Value
	}

	info, err := client.GetGroupInfo(context.Background(), jid.ToNonAD())
	if err != nil {
		log.Printf("Failed to fetch group info for %s: %v", cacheKey, err)
		setCachedGroupName(cacheKey, "", 10*time.Minute)
		return ""
	}

	name := strings.TrimSpace(info.Name)
	setCachedGroupName(cacheKey, name, 24*time.Hour)
	return name
}

func setCachedGroupName(key string, value string, ttl time.Duration) {
	groupNameMu.Lock()
	groupNameCache[key] = cacheEntry{Value: value, ExpiresAt: time.Now().Add(ttl)}
	groupNameMu.Unlock()
}

func getProfilePictureURL(client *whatsmeow.Client, jid types.JID) string {
	if jid.IsEmpty() {
		return ""
	}

	cacheKey := jidString(jid)
	profilePictureMu.RLock()
	cached, ok := profilePictureCache[cacheKey]
	profilePictureMu.RUnlock()
	if ok && cached.ExpiresAt.After(time.Now()) {
		return cached.Value
	}

	info, err := client.GetProfilePictureInfo(context.Background(), jid.ToNonAD(), nil)
	if err != nil {
		log.Printf("Failed to fetch profile picture for %s: %v", cacheKey, err)
		setCachedProfilePicture(cacheKey, "", 30*time.Minute)
		return ""
	}
	if info == nil {
		setCachedProfilePicture(cacheKey, "", 30*time.Minute)
		return ""
	}

	setCachedProfilePicture(cacheKey, info.URL, 24*time.Hour)
	return info.URL
}

func setCachedProfilePicture(key string, value string, ttl time.Duration) {
	profilePictureMu.Lock()
	profilePictureCache[key] = cacheEntry{Value: value, ExpiresAt: time.Now().Add(ttl)}
	profilePictureMu.Unlock()
}

func jidString(jid types.JID) string {
	if jid.IsEmpty() {
		return ""
	}
	return jid.ToNonAD().String()
}

func sendWebhookNotification(accountID string, channelID string, payload map[string]interface{}) {
	url := fmt.Sprintf(webhookURL, accountID, channelID)
	log.Printf("Sending webhook payload to: %s", url)

	body, err := json.Marshal(payload)
	if err != nil {
		log.Printf("Failed to marshal webhook payload: %v", err)
		return
	}

	go func() {
		client := &http.Client{Timeout: 10 * time.Second}
		res, err := client.Post(url, "application/json", bytes.NewBuffer(body))
		if err != nil {
			log.Printf("Failed to send webhook callback: %v", err)
			return
		}
		defer res.Body.Close()
		log.Printf("Webhook callback response status: %s", res.Status)
	}()
}
