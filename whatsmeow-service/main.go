package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"mime"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
	"github.com/skip2/go-qrcode"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/binary/proto"
	waWeb "go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

const (
	sendMessageTimeout         = 60 * time.Second
	defaultStatusSendTimeout   = 5 * time.Minute
	groupMemberProfileFetchMax = 120
	groupListProfileFetchMax   = 80
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
	ForceNew  bool   `json:"force_new"`
}

type MessageRequest struct {
	ChannelID   string                `json:"channel_id" binding:"required"`
	To          string                `json:"to" binding:"required"`
	Body        string                `json:"body"`
	Attachments []WhatsmeowAttachment `json:"attachments"`
	Contacts    []WhatsmeowContact    `json:"contacts"`
	Quoted      *QuotedMessageRequest `json:"quoted"`
}

type StatusRequest struct {
	Content        string               `json:"content"`
	BackgroundARGB uint32               `json:"background_argb"`
	TextARGB       uint32               `json:"text_argb"`
	Font           int32                `json:"font"`
	Attachment     *WhatsmeowAttachment `json:"attachment"`
	Contacts       []StatusContact      `json:"contacts"`
}

type StatusReadRequest struct {
	MessageID string `json:"message_id" binding:"required"`
	SenderJID string `json:"sender_jid" binding:"required"`
	Timestamp int64  `json:"timestamp" binding:"required"`
}

// StatusReplyRequest represents a reply to a remote WhatsApp Status. Status
// replies are delivered as direct messages to the Status author, while their
// message context refers back to status@broadcast.
type StatusReplyRequest struct {
	MessageID string               `json:"message_id" binding:"required"`
	SenderJID string               `json:"sender_jid" binding:"required"`
	Timestamp int64                `json:"timestamp" binding:"required"`
	Content   string               `json:"content"`
	Reaction  string               `json:"reaction"`
	Sticker   *WhatsmeowAttachment `json:"sticker"`
	// Attachment is accepted as a compatibility alias for sticker. Only
	// Whatsmeow sticker attachments are accepted by this endpoint.
	Attachment *WhatsmeowAttachment `json:"attachment"`
}

type StatusContact struct {
	JID  string `json:"jid"`
	Name string `json:"name"`
}

type ReactionRequest struct {
	ChannelID string `json:"channel_id" binding:"required"`
	To        string `json:"to" binding:"required"`
	Sender    string `json:"sender"`
	MessageID string `json:"message_id" binding:"required"`
	Emoji     string `json:"emoji"`
}

type MessageDeleteRequest struct {
	ChannelID string `json:"channel_id" binding:"required"`
	To        string `json:"to" binding:"required"`
	Sender    string `json:"sender"`
	MessageID string `json:"message_id" binding:"required"`
}

type MessageEditRequest struct {
	ChannelID string `json:"channel_id" binding:"required"`
	To        string `json:"to" binding:"required"`
	MessageID string `json:"message_id" binding:"required"`
	Body      string `json:"body" binding:"required"`
}

type QuotedMessageRequest struct {
	MessageID   string `json:"message_id"`
	Participant string `json:"participant"`
	Text        string `json:"text"`
	FileType    string `json:"file_type"`
	FromMe      bool   `json:"from_me"`
}

type QuotedMessagePayload struct {
	MessageID   string
	Participant string
	Content     string
	FileType    string
}

type WhatsmeowAttachment struct {
	FileName      string                 `json:"file_name"`
	ContentType   string                 `json:"content_type"`
	FileType      string                 `json:"file_type"`
	Meta          map[string]interface{} `json:"meta,omitempty"`
	RecordedAudio bool                   `json:"recorded_audio"`
	DataBase64    string                 `json:"data_base64"`
}

type WhatsmeowContact struct {
	DisplayName       string                 `json:"display_name"`
	FullName          string                 `json:"full_name"`
	FirstName         string                 `json:"first_name"`
	LastName          string                 `json:"last_name"`
	PhoneNumber       string                 `json:"phone_number"`
	WhatsAppID        string                 `json:"whatsapp_id"`
	JID               string                 `json:"jid"`
	Organization      string                 `json:"organization"`
	Title             string                 `json:"title"`
	Email             string                 `json:"email"`
	Website           string                 `json:"website"`
	Note              string                 `json:"note"`
	Category          string                 `json:"category"`
	AvatarURL         string                 `json:"avatar_url"`
	ProfilePictureURL string                 `json:"profile_picture_url"`
	Vcard             string                 `json:"vcard"`
	BusinessProfile   map[string]interface{} `json:"business_profile"`
}

type GroupMemberResponse struct {
	JID               string `json:"jid"`
	LIDJID            string `json:"lid_jid"`
	Name              string `json:"name"`
	PhoneNumber       string `json:"phone_number"`
	DisplayName       string `json:"display_name"`
	ProfilePictureURL string `json:"profile_picture_url"`
	IsAdmin           bool   `json:"is_admin"`
	IsSuperAdmin      bool   `json:"is_super_admin"`
	IsSavedContact    bool   `json:"is_saved_contact"`
	IsSelf            bool   `json:"is_self"`
	Error             int    `json:"error,omitempty"`
	AddRequestCode    string `json:"add_request_code,omitempty"`
	AddRequestExpires string `json:"add_request_expires,omitempty"`
}

type GroupResponse struct {
	JID               string `json:"jid"`
	Name              string `json:"name"`
	ProfilePictureURL string `json:"profile_picture_url"`
	ParticipantCount  int    `json:"participant_count"`
	IsAnnounce        bool   `json:"is_announce"`
	IsLocked          bool   `json:"is_locked"`
}

type GroupInviteRequest struct {
	Code       string `json:"code"`
	InviteCode string `json:"invite_code"`
	URL        string `json:"url"`
	Link       string `json:"link"`
}

type GroupInviteResponse struct {
	Code                   string `json:"code"`
	Link                   string `json:"link"`
	JID                    string `json:"jid"`
	GroupJID               string `json:"group_jid"`
	Name                   string `json:"name"`
	ProfilePictureURL      string `json:"profile_picture_url"`
	ParticipantCount       int    `json:"participant_count"`
	IsAnnounce             bool   `json:"is_announce"`
	IsLocked               bool   `json:"is_locked"`
	IsJoinApprovalRequired bool   `json:"is_join_approval_required"`
	Joined                 bool   `json:"joined"`
	PendingApproval        bool   `json:"pending_approval"`
}

type AddGroupMemberRequest struct {
	GroupJID         string `json:"group_jid" binding:"required"`
	ParticipantJID   string `json:"participant_jid"`
	ParticipantPhone string `json:"participant_phone"`
}

type ResolvedGroupParticipant struct {
	JID               types.JID
	LIDJID            types.JID
	Name              string
	PhoneNumber       string
	ProfilePictureURL string
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
	r.GET("/sessions/:channel_id/groups", handleGetGroups)
	r.GET("/sessions/:channel_id/group_invite", handleGetGroupInvite)
	r.POST("/sessions/:channel_id/group_invite", handleJoinGroupInvite)
	r.GET("/sessions/:channel_id/group_members", handleGetGroupMembers)
	r.POST("/sessions/:channel_id/group_members", handleAddGroupMember)
	r.GET("/sessions/:channel_id/profile_picture", handleGetProfilePicture)
	r.GET("/sessions/:channel_id/check_number", handleCheckNumber)
	r.POST("/sessions/:channel_id/statuses", internalTokenMiddleware(), handleSendStatus)
	r.POST("/sessions/:channel_id/statuses/read", internalTokenMiddleware(), handleReadStatus)
	r.POST("/sessions/:channel_id/statuses/reply", internalTokenMiddleware(), handleReplyToStatus)
	r.DELETE("/sessions/:channel_id", handleDisconnectSession)
	r.POST("/messages", handleSendMessage)
	r.POST("/messages/reaction", handleSendReaction)
	r.POST("/messages/delete", handleDeleteMessage)
	r.POST("/messages/edit", handleEditMessage)

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
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, X-Whatsmeow-Internal-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

func internalTokenMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		expectedToken := strings.TrimSpace(os.Getenv("WHATSMEOW_SHARED_SECRET"))
		if expectedToken == "" {
			c.Next()
			return
		}

		providedToken := c.GetHeader("X-Whatsmeow-Internal-Token")
		if subtle.ConstantTimeCompare([]byte(providedToken), []byte(expectedToken)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
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

func updateChannelPhoneAndStatus(channelID string, phone string, status string) {
	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		log.Printf("Failed to open database to update phone/status: %v", err)
		return
	}
	defer db.Close()

	query := `
		UPDATE channel_whatsmeow c
		SET phone_number = $1, status = $2
		FROM inboxes i
		WHERE i.channel_id = c.id AND i.id = $3 AND i.channel_type = 'Channel::Whatsmeow'
	`
	_, err = db.Exec(query, phone, status, channelID)
	if err != nil {
		log.Printf("Failed to update phone/status in database for channel %s: %v", channelID, err)
	} else {
		log.Printf("Updated channel %s phone to %s and status to %s in database", channelID, phone, status)
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

	clientsMu.RLock()
	client, exists := clients[req.ChannelID]
	clientsMu.RUnlock()

	if exists && client != nil && !req.ForceNew {
		if client.IsConnected() && client.IsLoggedIn() {
			payload := gin.H{
				"status":     "connected",
				"channel_id": req.ChannelID,
				"message":    "Session already connected",
			}
			if client.Store.ID != nil {
				payload["jid"] = client.Store.ID.String()
				payload["phone_number"] = client.Store.ID.User
			}
			c.JSON(http.StatusOK, payload)
			return
		}

		if client.IsConnected() {
			qrCodesMu.RLock()
			qrCodeBase64 := qrCodes[req.ChannelID]
			qrCodesMu.RUnlock()

			payload := gin.H{
				"status":     "connecting",
				"channel_id": req.ChannelID,
			}
			if qrCodeBase64 != "" {
				payload["status"] = "pairing"
				payload["qr_code"] = qrCodeBase64
			}
			c.JSON(http.StatusOK, payload)
			return
		}
	}

	if req.ForceNew {
		var staleClient *whatsmeow.Client
		clientsMu.Lock()
		if exists && client != nil && !client.IsLoggedIn() {
			staleClient = client
		}
		delete(clients, req.ChannelID)
		clientsMu.Unlock()

		safeDisconnectClient(staleClient)

		qrCodesMu.Lock()
		delete(qrCodes, req.ChannelID)
		qrCodesMu.Unlock()
	}

	deviceStore := dbContainer.NewDevice()

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
						updateChannelPhoneAndStatus(req.ChannelID, phone, "connected")
						inboxIDs, _, _ := lookupAllInboxesAndAccounts(phone)
						clientsMu.Lock()
						clients[req.ChannelID] = client
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
		err := client.Connect()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to connect: %v", err)})
			updateChannelStatus(req.ChannelID, "disconnected")
			return
		}

		if client.Store.ID != nil {
			phone := client.Store.ID.User
			updateChannelPhoneAndStatus(req.ChannelID, phone, "connected")
			inboxIDs, _, _ := lookupAllInboxesAndAccounts(phone)
			clientsMu.Lock()
			clients[req.ChannelID] = client
			for _, ibID := range inboxIDs {
				clients[ibID] = client
			}
			clientsMu.Unlock()
			updateAllChannelsStatusByPhone(phone, "connected")
		} else {
			updateChannelStatus(req.ChannelID, "connected")
		}

		payload := gin.H{
			"status":     "connected",
			"channel_id": req.ChannelID,
		}
		if client.Store.ID != nil {
			payload["jid"] = client.Store.ID.String()
			payload["phone_number"] = client.Store.ID.User
		}
		c.JSON(http.StatusOK, payload)
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
	}
	if client.Store.ID != nil {
		payload["jid"] = client.Store.ID.String()
		payload["phone_number"] = client.Store.ID.User
	}
	if qrCodeBase64 != "" {
		payload["qr_code"] = qrCodeBase64
	}

	c.JSON(http.StatusOK, payload)
}

func handleGetGroups(c *gin.Context) {
	channelID := c.Param("channel_id")

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	groups, err := client.GetJoinedGroups(context.Background())
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("Failed to fetch groups: %v", err)})
		return
	}

	fetchProfilePictures := len(groups) <= groupListProfileFetchMax
	responses := make([]GroupResponse, 0, len(groups))
	for _, group := range groups {
		if group == nil || group.JID.IsEmpty() {
			continue
		}
		responses = append(responses, buildGroupResponse(client, group, fetchProfilePictures))
	}
	sortGroups(responses)

	c.JSON(http.StatusOK, gin.H{
		"groups": responses,
		"count":  len(responses),
	})
}

func handleGetGroupInvite(c *gin.Context) {
	channelID := c.Param("channel_id")
	code, ok := groupInviteCodeFromRequest(c)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp group invite link"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	info, err := client.GetGroupInfoFromLink(ctx, code)
	if err != nil {
		c.JSON(groupInviteErrorStatus(err), gin.H{"error": fmt.Sprintf("Failed to fetch group invite: %v", err)})
		return
	}

	c.JSON(http.StatusOK, groupInviteResponse(client, info, code, false, false))
}

func handleJoinGroupInvite(c *gin.Context) {
	channelID := c.Param("channel_id")
	code, ok := groupInviteCodeFromRequest(c)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp group invite link"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	groupJID, err := client.JoinGroupWithLink(ctx, code)
	if err != nil {
		c.JSON(groupInviteErrorStatus(err), gin.H{"error": fmt.Sprintf("Failed to join group invite: %v", err)})
		return
	}

	info, infoErr := client.GetGroupInfo(ctx, groupJID.ToNonAD())
	joined := infoErr == nil
	if infoErr != nil {
		info, _ = client.GetGroupInfoFromLink(ctx, code)
	}

	response := groupInviteResponse(client, info, code, joined, !joined)
	if response.JID == "" && !groupJID.IsEmpty() {
		response.JID = groupJID.ToNonAD().String()
		response.GroupJID = response.JID
	}

	c.JSON(http.StatusOK, response)
}

func handleGetGroupMembers(c *gin.Context) {
	channelID := c.Param("channel_id")
	groupID := c.Query("group_jid")

	groupJID, ok := parseJID(groupID)
	if !ok || !isGroupJID(groupJID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp group JID"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	info, err := client.GetGroupInfo(context.Background(), groupJID.ToNonAD())
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("Failed to fetch group members: %v", err)})
		return
	}

	fetchProfilePictures := len(info.Participants) <= groupMemberProfileFetchMax
	members := make([]GroupMemberResponse, 0, len(info.Participants))
	selfJID, selfPhoneNumber := currentClientJID(client)
	selfIsAdmin := false
	selfIsSuperAdmin := false
	for _, participant := range info.Participants {
		member := buildGroupMemberResponse(client, participant, fetchProfilePictures)
		if groupParticipantMatches(participant, selfJID) {
			member.IsSelf = true
			member.Name = firstNonBlank(client.Store.PushName, member.Name)
			member.PhoneNumber = firstNonBlank(selfPhoneNumber, member.PhoneNumber)
			selfIsAdmin = participant.IsAdmin || participant.IsSuperAdmin
			selfIsSuperAdmin = participant.IsSuperAdmin
		}
		members = append(members, member)
	}
	sortGroupMembers(members)

	canAddMembers := selfIsAdmin || selfIsSuperAdmin || info.MemberAddMode == types.GroupMemberAddModeAllMember

	c.JSON(http.StatusOK, gin.H{
		"group_jid":           groupJID.ToNonAD().String(),
		"group_name":          info.Name,
		"members":             members,
		"count":               len(members),
		"self_jid":            jidString(selfJID),
		"self_phone_number":   selfPhoneNumber,
		"self_is_admin":       selfIsAdmin,
		"self_is_super_admin": selfIsSuperAdmin,
		"member_add_mode":     string(info.MemberAddMode),
		"can_add_members":     canAddMembers,
	})
}

func handleAddGroupMember(c *gin.Context) {
	channelID := c.Param("channel_id")
	var request AddGroupMemberRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "group_jid is required"})
		return
	}

	groupJID, ok := parseJID(request.GroupJID)
	if !ok || !isGroupJID(groupJID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp group JID"})
		return
	}

	participantJID, ok := parseParticipantJID(request.ParticipantJID, request.ParticipantPhone)
	if !ok || isGroupJID(participantJID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp participant phone / JID"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	participants, err := client.UpdateGroupParticipants(
		context.Background(),
		groupJID.ToNonAD(),
		[]types.JID{participantJID.ToNonAD()},
		whatsmeow.ParticipantChangeAdd,
	)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("Failed to add group member: %v", err)})
		return
	}
	if len(participants) == 0 {
		c.JSON(http.StatusBadGateway, gin.H{"error": "WhatsApp did not return a participant update confirmation"})
		return
	}

	result := buildGroupMemberResponse(client, participants[0], false)
	if result.Error != 0 {
		message := fmt.Sprintf("WhatsApp returned participant error %d", result.Error)
		if result.AddRequestCode != "" {
			message = "WhatsApp requires an invite request for this participant instead of adding them directly"
		}
		c.JSON(http.StatusBadRequest, gin.H{
			"error":       message,
			"participant": result,
		})
		return
	}

	confirmedMember, ok := waitForGroupParticipant(client, groupJID, participantJID)
	if !ok {
		c.JSON(http.StatusConflict, gin.H{
			"error":       "WhatsApp accepted the request, but the participant is not in the group member list yet",
			"participant": result,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"participant": confirmedMember,
		"message":     "Group member added",
	})
}

func handleGetProfilePicture(c *gin.Context) {
	channelID := c.Param("channel_id")
	jidValue := c.Query("jid")
	forceRefresh := strings.EqualFold(c.Query("force"), "true")

	jid, ok := parseJID(jidValue)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp JID"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"jid":                 jid.ToNonAD().String(),
		"profile_picture_url": getProfilePictureURLWithRefresh(client, jid, forceRefresh),
		"checked_at":          time.Now().UTC().Format(time.RFC3339),
	})
}

func handleCheckNumber(c *gin.Context) {
	channelID := c.Param("channel_id")
	rawValue := c.Query("phone")
	if rawValue == "" {
		rawValue = c.Query("jid")
	}

	phone, ok := normalizePhoneForWhatsAppCheck(rawValue)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid WhatsApp phone number / JID"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	results, err := client.IsOnWhatsApp(ctx, []string{phone})
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("Failed to check WhatsApp number: %v", err)})
		return
	}

	isOnWhatsApp := false
	jid := ""
	query := strings.TrimPrefix(phone, "+")
	if len(results) > 0 {
		isOnWhatsApp = results[0].IsIn
		query = results[0].Query
		if results[0].JID.User != "" {
			jid = results[0].JID.ToNonAD().String()
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"phone":          phone,
		"query":          query,
		"jid":            jid,
		"is_on_whatsapp": isOnWhatsApp,
		"checked_at":     time.Now().UTC().Format(time.RFC3339),
	})
}

func handleDisconnectSession(c *gin.Context) {
	channelID := c.Param("channel_id")

	clientsMu.Lock()
	client, exists := clients[channelID]
	delete(clients, channelID)
	clientsMu.Unlock()

	phone := ""
	if exists && client != nil && client.Store.ID != nil {
		phone = client.Store.ID.User
		inboxIDs, _, err := lookupAllInboxesAndAccounts(phone)
		if err != nil {
			log.Printf("Failed to lookup inboxes for disconnecting phone %s: %v", phone, err)
		}

		clientsMu.Lock()
		for _, ibID := range inboxIDs {
			delete(clients, ibID)
		}
		clientsMu.Unlock()
	}

	safeDisconnectClient(client)

	qrCodesMu.Lock()
	delete(qrCodes, channelID)
	qrCodesMu.Unlock()

	if phone != "" {
		updateAllChannelsStatusByPhone(phone, "disconnected")
	} else {
		updateChannelStatus(channelID, "disconnected")
	}

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
	if strings.TrimSpace(req.Body) == "" && len(req.Attachments) == 0 && len(req.Contacts) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Message body, attachment or contact is required"})
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

	sendCtx, cancelSend := context.WithTimeout(context.Background(), sendMessageTimeout)
	defer cancelSend()

	msg, err := buildOutgoingMessage(sendCtx, client, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	resp, err := client.SendMessage(sendCtx, targetJID, msg, whatsmeow.SendRequestExtra{Timeout: sendMessageTimeout - 5*time.Second})
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

func handleSendStatus(c *gin.Context) {
	var req StatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if strings.TrimSpace(req.Content) == "" && (req.Attachment == nil || req.Attachment.DataBase64 == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Status content or attachment is required"})
		return
	}
	if req.Attachment != nil && !statusMediaTypeSupported(*req.Attachment) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only image and video Status media is supported"})
		return
	}

	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	timeout := statusSendTimeout()
	startedAt := time.Now()
	log.Printf("Publishing Status on channel %s with %d synced Chatwoot contacts", c.Param("channel_id"), len(req.Contacts))
	sendCtx, cancelSend := context.WithTimeout(context.Background(), timeout)
	defer cancelSend()
	if err := syncStatusContacts(sendCtx, client, req.Contacts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to sync Status contacts: %v", err)})
		return
	}
	message, err := buildStatusMessage(sendCtx, client, req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	response, err := client.SendMessage(
		sendCtx,
		types.StatusBroadcastJID,
		message,
		whatsmeow.SendRequestExtra{Timeout: timeout - 5*time.Second},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to send Status: %v", err)})
		return
	}
	log.Printf("Published Status %s on channel %s in %s", response.ID, c.Param("channel_id"), time.Since(startedAt).Round(time.Millisecond))

	ownJID, _ := currentClientJID(client)
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"id":        response.ID,
		"timestamp": response.Timestamp.Unix(),
		"jid":       jidString(ownJID),
	})
}

func handleReadStatus(c *gin.Context) {
	var req StatusReadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}
	senderJID, ok := parseJID(req.SenderJID)
	if !ok || senderJID.IsEmpty() || senderJID.ToNonAD() == types.StatusBroadcastJID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid Status sender JID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	err := client.MarkRead(
		ctx,
		[]types.MessageID{types.MessageID(req.MessageID)},
		time.Unix(req.Timestamp, 0),
		types.StatusBroadcastJID,
		senderJID.ToNonAD(),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to mark Status as read: %v", err)})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

func handleReplyToStatus(c *gin.Context) {
	var req StatusReplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.MessageID = strings.TrimSpace(req.MessageID)
	req.SenderJID = strings.TrimSpace(req.SenderJID)
	req.Content = strings.TrimSpace(req.Content)
	req.Reaction = strings.TrimSpace(req.Reaction)
	if req.MessageID == "" || req.SenderJID == "" || req.Timestamp <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Status message_id, sender_jid and timestamp are required"})
		return
	}

	sticker, replyMode, err := statusReplyMode(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	statusSender, ok := parseJID(req.SenderJID)
	if !ok || !isStatusReplySender(statusSender) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid Status sender JID"})
		return
	}

	targetJID := statusReplyTarget(client, statusSender)
	if targetJID.IsEmpty() {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unable to resolve Status sender JID"})
		return
	}

	sendCtx, cancelSend := context.WithTimeout(context.Background(), sendMessageTimeout)
	defer cancelSend()

	contextInfo := statusReplyContextInfo(req.MessageID, statusSender)
	message, err := buildStatusReplyMessage(sendCtx, client, req, sticker, replyMode, contextInfo, statusSender)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := client.SendMessage(
		sendCtx,
		targetJID,
		message,
		whatsmeow.SendRequestExtra{Timeout: sendMessageTimeout - 5*time.Second},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to send Status reply: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":          true,
		"id":               response.ID,
		"timestamp":        response.Timestamp.Unix(),
		"message_id":       req.MessageID,
		"source_status_id": req.MessageID,
		"source_timestamp": req.Timestamp,
		"mode":             replyMode,
		"to":               jidString(targetJID),
	})
}

func statusReplyMode(req StatusReplyRequest) (*WhatsmeowAttachment, string, error) {
	stickers := make([]WhatsmeowAttachment, 0, 2)
	if req.Sticker != nil {
		stickers = append(stickers, *req.Sticker)
	}
	if req.Attachment != nil {
		stickers = append(stickers, *req.Attachment)
	}

	modeCount := 0
	if req.Content != "" {
		modeCount++
	}
	if req.Reaction != "" {
		modeCount++
	}
	if len(stickers) > 0 {
		modeCount++
	}
	if modeCount != 1 {
		return nil, "", fmt.Errorf("Status reply must contain exactly one of content, reaction or sticker")
	}
	if len(stickers) > 1 {
		return nil, "", fmt.Errorf("Status reply accepts one sticker attachment")
	}
	if len(stickers) == 0 {
		if req.Reaction != "" {
			return nil, "reaction", nil
		}
		return nil, "text", nil
	}

	sticker := stickers[0]
	if strings.TrimSpace(sticker.DataBase64) == "" {
		return nil, "", fmt.Errorf("Status reply sticker data is required")
	}
	if !attachmentIsSticker(sticker) && !strings.EqualFold(strings.TrimSpace(sticker.FileType), "sticker") {
		return nil, "", fmt.Errorf("Status reply attachment must be a Whatsmeow sticker")
	}
	if !attachmentIsSticker(sticker) {
		if sticker.Meta == nil {
			sticker.Meta = map[string]interface{}{}
		}
		sticker.Meta["whatsmeow_sticker"] = true
	}
	return &sticker, "sticker", nil
}

func isStatusReplySender(jid types.JID) bool {
	if jid.IsEmpty() || sameBareJID(jid, types.StatusBroadcastJID) {
		return false
	}
	return jid.Server == types.DefaultUserServer || jid.Server == types.HiddenUserServer
}

func statusReplyTarget(client *whatsmeow.Client, sender types.JID) types.JID {
	if resolved := resolveStatusPhoneJID(client, sender); !resolved.IsEmpty() {
		return resolved
	}
	return sender.ToNonAD()
}

func statusReplyContextInfo(statusID string, sender types.JID) *proto.ContextInfo {
	return &proto.ContextInfo{
		StanzaID:    stringPtr(statusID),
		Participant: stringPtr(sender.ToNonAD().String()),
		RemoteJID:   stringPtr(types.StatusBroadcastJID.String()),
	}
}

func buildStatusReplyMessage(
	ctx context.Context,
	client *whatsmeow.Client,
	req StatusReplyRequest,
	sticker *WhatsmeowAttachment,
	mode string,
	contextInfo *proto.ContextInfo,
	statusSender types.JID,
) (*proto.Message, error) {
	switch mode {
	case "text":
		return &proto.Message{
			ExtendedTextMessage: &proto.ExtendedTextMessage{
				Text:        stringPtr(req.Content),
				ContextInfo: contextInfo,
			},
		}, nil
	case "reaction":
		return client.BuildReaction(types.StatusBroadcastJID, statusSender.ToNonAD(), types.MessageID(req.MessageID), req.Reaction), nil
	case "sticker":
		return buildOutgoingMediaMessage(ctx, client, "", *sticker, contextInfo)
	default:
		return nil, fmt.Errorf("Unsupported Status reply mode")
	}
}

func clientForChannel(channelID string) (*whatsmeow.Client, bool) {
	clientsMu.RLock()
	client, exists := clients[channelID]
	clientsMu.RUnlock()
	return client, exists && client != nil && client.IsConnected() && client.IsLoggedIn()
}

func statusSendTimeout() time.Duration {
	seconds, err := strconv.Atoi(strings.TrimSpace(os.Getenv("WHATSMEOW_STATUS_SEND_TIMEOUT_SECONDS")))
	if err != nil || seconds < 60 {
		return defaultStatusSendTimeout
	}
	if seconds > 900 {
		seconds = 900
	}
	return time.Duration(seconds) * time.Second
}

func statusMediaTypeSupported(attachment WhatsmeowAttachment) bool {
	mediaType := outgoingMediaType(attachment)
	return mediaType == whatsmeow.MediaImage || mediaType == whatsmeow.MediaVideo
}

func syncStatusContacts(ctx context.Context, client *whatsmeow.Client, contacts []StatusContact) error {
	if len(contacts) == 0 || client == nil || client.Store == nil || client.Store.Contacts == nil {
		return nil
	}

	entries := make([]store.ContactEntry, 0, len(contacts))
	seen := make(map[string]struct{}, len(contacts))
	for _, contact := range contacts {
		jid, ok := parseJID(contact.JID)
		if !ok || !isPhoneJID(jid) {
			continue
		}
		jid = jid.ToNonAD()
		key := jid.String()
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}

		name := strings.TrimSpace(contact.Name)
		if name == "" {
			name = phoneNumberFromJID(jid)
		}
		firstName := strings.Fields(name)
		first := name
		if len(firstName) > 0 {
			first = firstName[0]
		}
		entries = append(entries, store.ContactEntry{JID: jid, FirstName: first, FullName: name})
	}

	if len(entries) == 0 {
		return nil
	}
	return client.Store.Contacts.PutAllContactNames(ctx, entries)
}

func buildStatusMessage(ctx context.Context, client *whatsmeow.Client, req StatusRequest) (*proto.Message, error) {
	if req.Attachment != nil && req.Attachment.DataBase64 != "" {
		return buildOutgoingMediaMessage(ctx, client, strings.TrimSpace(req.Content), *req.Attachment, nil)
	}

	backgroundARGB := req.BackgroundARGB
	if backgroundARGB == 0 {
		backgroundARGB = 0xFF0B8467
	}
	textARGB := req.TextARGB
	if textARGB == 0 {
		textARGB = 0xFFFFFFFF
	}
	font := supportedStatusFont(req.Font)
	return &proto.Message{
		ExtendedTextMessage: &proto.ExtendedTextMessage{
			Text:           stringPtr(strings.TrimSpace(req.Content)),
			TextArgb:       uint32Ptr(textARGB),
			BackgroundArgb: uint32Ptr(backgroundARGB),
			Font:           &font,
		},
	}, nil
}

func supportedStatusFont(font int32) proto.ExtendedTextMessage_FontType {
	switch font {
	case 0, 1, 2, 6, 7, 8, 9, 10:
		return proto.ExtendedTextMessage_FontType(font)
	default:
		return proto.ExtendedTextMessage_FontType(6)
	}
}

func handleSendReaction(c *gin.Context) {
	var req ReactionRequest
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

	targetJID, ok := parseJID(req.To)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target phone number / JID"})
		return
	}

	senderJID := types.EmptyJID
	if strings.TrimSpace(req.Sender) != "" {
		parsedSender, senderOK := parseJID(req.Sender)
		if !senderOK {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid reaction sender JID"})
			return
		}
		senderJID = parsedSender
	}

	sendCtx, cancelSend := context.WithTimeout(context.Background(), sendMessageTimeout)
	defer cancelSend()

	reactionMessage := client.BuildReaction(
		targetJID,
		senderJID,
		types.MessageID(req.MessageID),
		strings.TrimSpace(req.Emoji),
	)
	resp, err := client.SendMessage(
		sendCtx,
		targetJID,
		reactionMessage,
		whatsmeow.SendRequestExtra{Timeout: sendMessageTimeout - 5*time.Second},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to send reaction: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"id":        resp.ID,
		"timestamp": resp.Timestamp.Unix(),
	})
}

func handleDeleteMessage(c *gin.Context) {
	var req MessageDeleteRequest
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

	targetJID, ok := parseJID(req.To)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target phone number / JID"})
		return
	}

	senderJID := types.EmptyJID
	if strings.TrimSpace(req.Sender) != "" {
		parsedSender, senderOK := parseJID(req.Sender)
		if !senderOK {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid message sender JID"})
			return
		}
		senderJID = parsedSender
	}

	sendCtx, cancelSend := context.WithTimeout(context.Background(), sendMessageTimeout)
	defer cancelSend()

	revokeMessage := client.BuildRevoke(targetJID, senderJID, types.MessageID(req.MessageID))
	resp, err := client.SendMessage(
		sendCtx,
		targetJID,
		revokeMessage,
		whatsmeow.SendRequestExtra{Timeout: sendMessageTimeout - 5*time.Second},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to delete message: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"id":        resp.ID,
		"timestamp": resp.Timestamp.Unix(),
	})
}

func handleEditMessage(c *gin.Context) {
	var req MessageEditRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	body := strings.TrimSpace(req.Body)
	if body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Message body is required"})
		return
	}

	clientsMu.RLock()
	client, exists := clients[req.ChannelID]
	clientsMu.RUnlock()

	if !exists || !client.IsConnected() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Session is not active or connected"})
		return
	}

	targetJID, ok := parseJID(req.To)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target phone number / JID"})
		return
	}

	sendCtx, cancelSend := context.WithTimeout(context.Background(), sendMessageTimeout)
	defer cancelSend()

	editMessage := client.BuildEdit(targetJID, types.MessageID(req.MessageID), &proto.Message{
		Conversation: stringPtr(body),
	})
	resp, err := client.SendMessage(
		sendCtx,
		targetJID,
		editMessage,
		whatsmeow.SendRequestExtra{Timeout: sendMessageTimeout - 5*time.Second},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to edit message: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"id":        resp.ID,
		"timestamp": resp.Timestamp.Unix(),
	})
}

func buildOutgoingMessage(ctx context.Context, client *whatsmeow.Client, req MessageRequest) (*proto.Message, error) {
	contextInfo := quotedContextInfo(req.Quoted)

	if len(req.Contacts) > 0 {
		return buildOutgoingContactMessage(req.Contacts, contextInfo)
	}

	if len(req.Attachments) > 0 {
		return buildOutgoingMediaMessage(ctx, client, req.Body, req.Attachments[0], contextInfo)
	}

	if contextInfo != nil {
		return &proto.Message{
			ExtendedTextMessage: &proto.ExtendedTextMessage{
				Text:        stringPtr(req.Body),
				ContextInfo: contextInfo,
			},
		}, nil
	}

	return &proto.Message{
		Conversation: stringPtr(req.Body),
	}, nil
}

func buildOutgoingContactMessage(contacts []WhatsmeowContact, contextInfo *proto.ContextInfo) (*proto.Message, error) {
	protoContacts := make([]*proto.ContactMessage, 0, len(contacts))
	for _, contact := range contacts {
		normalized := normalizeOutgoingContact(contact)
		if normalized.DisplayName == "" || normalized.Vcard == "" {
			continue
		}
		protoContacts = append(protoContacts, &proto.ContactMessage{
			DisplayName: stringPtr(normalized.DisplayName),
			Vcard:       stringPtr(normalized.Vcard),
			ContextInfo: contextInfo,
		})
	}

	if len(protoContacts) == 0 {
		return nil, fmt.Errorf("contact display name and phone number are required")
	}

	if len(protoContacts) == 1 {
		return &proto.Message{ContactMessage: protoContacts[0]}, nil
	}

	return &proto.Message{
		ContactsArrayMessage: &proto.ContactsArrayMessage{
			DisplayName: stringPtr(fmt.Sprintf("%d contatos", len(protoContacts))),
			Contacts:    protoContacts,
			ContextInfo: contextInfo,
		},
	}, nil
}

func buildOutgoingMediaMessage(
	ctx context.Context,
	client *whatsmeow.Client,
	caption string,
	attachment WhatsmeowAttachment,
	contextInfo *proto.ContextInfo,
) (*proto.Message, error) {
	data, err := base64.StdEncoding.DecodeString(attachment.DataBase64)
	if err != nil {
		return nil, fmt.Errorf("invalid attachment data")
	}
	if len(data) == 0 {
		return nil, fmt.Errorf("attachment data is empty")
	}

	mediaType := outgoingMediaType(attachment)
	contentType := normalizedMIME(attachment.ContentType, fallbackMIME(attachment.FileType))
	fileName := attachment.FileName
	if fileName == "" {
		fileName = defaultFileName(attachment.FileType, contentType)
	}
	var audioSeconds uint32
	var audioWaveform []byte
	if mediaType == whatsmeow.MediaAudio && attachment.RecordedAudio {
		data, contentType, fileName, audioSeconds, audioWaveform = prepareRecordedAudio(ctx, data, contentType, fileName)
	}

	if attachmentIsSticker(attachment) {
		contentType = normalizedMIME(contentType, "image/webp")
		upload, err := client.Upload(ctx, data, whatsmeow.MediaImage)
		if err != nil {
			return nil, fmt.Errorf("failed to upload sticker: %w", err)
		}

		return &proto.Message{
			StickerMessage: &proto.StickerMessage{
				Mimetype:           stringPtr(contentType),
				URL:                stringPtr(upload.URL),
				DirectPath:         stringPtr(upload.DirectPath),
				MediaKey:           upload.MediaKey,
				FileEncSHA256:      upload.FileEncSHA256,
				FileSHA256:         upload.FileSHA256,
				FileLength:         uint64Ptr(upload.FileLength),
				MediaKeyTimestamp:  int64Ptr(time.Now().Unix()),
				IsAnimated:         optionalBoolPtr(metaBool(attachment.Meta, "animated")),
				IsLottie:           optionalBoolPtr(metaBool(attachment.Meta, "lottie")),
				Width:              optionalUint32Ptr(metaUint32(attachment.Meta, "width")),
				Height:             optionalUint32Ptr(metaUint32(attachment.Meta, "height")),
				AccessibilityLabel: optionalStringPtr(metaString(attachment.Meta, "accessibility_label")),
				Emojis:             optionalStringPtr(metaString(attachment.Meta, "emojis")),
				ContextInfo:        contextInfo,
			},
		}, nil
	}

	upload, err := client.Upload(ctx, data, mediaType)
	if err != nil {
		return nil, fmt.Errorf("failed to upload media: %w", err)
	}

	switch mediaType {
	case whatsmeow.MediaImage:
		return &proto.Message{
			ImageMessage: &proto.ImageMessage{
				Caption:       optionalStringPtr(caption),
				Mimetype:      stringPtr(contentType),
				URL:           stringPtr(upload.URL),
				DirectPath:    stringPtr(upload.DirectPath),
				MediaKey:      upload.MediaKey,
				FileEncSHA256: upload.FileEncSHA256,
				FileSHA256:    upload.FileSHA256,
				FileLength:    uint64Ptr(upload.FileLength),
				ContextInfo:   contextInfo,
			},
		}, nil
	case whatsmeow.MediaVideo:
		return &proto.Message{
			VideoMessage: &proto.VideoMessage{
				Caption:       optionalStringPtr(caption),
				Mimetype:      stringPtr(contentType),
				URL:           stringPtr(upload.URL),
				DirectPath:    stringPtr(upload.DirectPath),
				MediaKey:      upload.MediaKey,
				FileEncSHA256: upload.FileEncSHA256,
				FileSHA256:    upload.FileSHA256,
				FileLength:    uint64Ptr(upload.FileLength),
				ContextInfo:   contextInfo,
			},
		}, nil
	case whatsmeow.MediaAudio:
		return &proto.Message{
			AudioMessage: &proto.AudioMessage{
				Mimetype:          stringPtr(contentType),
				PTT:               optionalBoolPtr(shouldSendAsPushToTalk(contentType, attachment.RecordedAudio)),
				Seconds:           optionalUint32Ptr(audioSeconds),
				URL:               stringPtr(upload.URL),
				DirectPath:        stringPtr(upload.DirectPath),
				MediaKey:          upload.MediaKey,
				FileEncSHA256:     upload.FileEncSHA256,
				FileSHA256:        upload.FileSHA256,
				FileLength:        uint64Ptr(upload.FileLength),
				MediaKeyTimestamp: int64Ptr(time.Now().Unix()),
				Waveform:          audioWaveform,
				ContextInfo:       contextInfo,
			},
		}, nil
	default:
		return &proto.Message{
			DocumentMessage: &proto.DocumentMessage{
				Caption:       optionalStringPtr(caption),
				Mimetype:      stringPtr(contentType),
				Title:         stringPtr(fileName),
				FileName:      stringPtr(fileName),
				URL:           stringPtr(upload.URL),
				DirectPath:    stringPtr(upload.DirectPath),
				MediaKey:      upload.MediaKey,
				FileEncSHA256: upload.FileEncSHA256,
				FileSHA256:    upload.FileSHA256,
				FileLength:    uint64Ptr(upload.FileLength),
				ContextInfo:   contextInfo,
			},
		}, nil
	}
}

func quotedContextInfo(quoted *QuotedMessageRequest) *proto.ContextInfo {
	if quoted == nil {
		return nil
	}

	messageID := strings.TrimSpace(quoted.MessageID)
	if messageID == "" {
		return nil
	}

	text := strings.TrimSpace(quoted.Text)
	if text == "" {
		text = quotedFileTypeLabel(quoted.FileType)
	}

	if text == "" {
		text = "Mensagem"
	}

	contextInfo := &proto.ContextInfo{
		StanzaID: stringPtr(messageID),
		QuotedMessage: &proto.Message{
			Conversation: stringPtr(text),
		},
	}

	if participant := strings.TrimSpace(quoted.Participant); participant != "" {
		contextInfo.Participant = stringPtr(participant)
	}

	return contextInfo
}

func outgoingMediaType(attachment WhatsmeowAttachment) whatsmeow.MediaType {
	if attachmentIsSticker(attachment) {
		return whatsmeow.MediaImage
	}

	fileType := strings.ToLower(attachment.FileType)
	contentType := strings.ToLower(attachment.ContentType)
	switch {
	case fileType == "image" || strings.HasPrefix(contentType, "image/"):
		return whatsmeow.MediaImage
	case fileType == "video" || strings.HasPrefix(contentType, "video/"):
		return whatsmeow.MediaVideo
	case fileType == "audio" || strings.HasPrefix(contentType, "audio/"):
		return whatsmeow.MediaAudio
	default:
		return whatsmeow.MediaDocument
	}
}

func attachmentIsSticker(attachment WhatsmeowAttachment) bool {
	return metaBool(attachment.Meta, "whatsmeow_sticker") ||
		metaBool(attachment.Meta, "whatsmeowSticker")
}

func metaBool(meta map[string]interface{}, key string) bool {
	value, ok := meta[key]
	if !ok {
		return false
	}

	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		return strings.EqualFold(strings.TrimSpace(typed), "true")
	default:
		return false
	}
}

func metaUint32(meta map[string]interface{}, key string) uint32 {
	value, ok := meta[key]
	if !ok {
		return 0
	}

	switch typed := value.(type) {
	case uint32:
		return typed
	case uint64:
		if typed > math.MaxUint32 {
			return 0
		}
		return uint32(typed)
	case int:
		if typed <= 0 || typed > math.MaxUint32 {
			return 0
		}
		return uint32(typed)
	case int64:
		if typed <= 0 || typed > math.MaxUint32 {
			return 0
		}
		return uint32(typed)
	case float64:
		if typed <= 0 || typed > math.MaxUint32 {
			return 0
		}
		return uint32(typed)
	default:
		return 0
	}
}

func metaString(meta map[string]interface{}, key string) string {
	value, ok := meta[key]
	if !ok {
		return ""
	}

	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	default:
		return ""
	}
}

func prepareRecordedAudio(ctx context.Context, data []byte, contentType string, fileName string) ([]byte, string, string, uint32, []byte) {
	if canSendAsPushToTalk(contentType) {
		return prepareVoiceNoteMetadata(ctx, data, "audio/ogg; codecs=opus", voiceNoteFileName(fileName))
	}

	converted, err := transcodeAudioToOggOpus(ctx, data, contentType)
	if err != nil {
		log.Printf("Failed to transcode recorded audio to OGG/Opus, sending as regular audio: %v", err)
		return data, contentType, fileName, 0, nil
	}

	return prepareVoiceNoteMetadata(ctx, converted, "audio/ogg; codecs=opus", voiceNoteFileName(fileName))
}

func prepareVoiceNoteMetadata(ctx context.Context, data []byte, contentType string, fileName string) ([]byte, string, string, uint32, []byte) {
	seconds, err := probeAudioDuration(ctx, data, contentType)
	if err != nil {
		log.Printf("Failed to probe voice note duration: %v", err)
		seconds = 1
	}

	waveform, err := generateAudioWaveform(ctx, data, contentType)
	if err != nil {
		log.Printf("Failed to generate voice note waveform: %v", err)
		waveform = defaultAudioWaveform()
	}

	return data, contentType, fileName, seconds, waveform
}

func transcodeAudioToOggOpus(ctx context.Context, data []byte, contentType string) ([]byte, error) {
	input, err := os.CreateTemp("", "whatsmeow-voice-*"+audioInputExtension(contentType))
	if err != nil {
		return nil, err
	}
	inputPath := input.Name()
	defer os.Remove(inputPath)

	if _, err := input.Write(data); err != nil {
		input.Close()
		return nil, err
	}
	if err := input.Close(); err != nil {
		return nil, err
	}

	output, err := os.CreateTemp("", "whatsmeow-voice-*.ogg")
	if err != nil {
		return nil, err
	}
	outputPath := output.Name()
	output.Close()
	defer os.Remove(outputPath)

	cmd := exec.CommandContext(
		ctx,
		"ffmpeg",
		"-hide_banner",
		"-loglevel",
		"error",
		"-y",
		"-i",
		inputPath,
		"-vn",
		"-ac",
		"1",
		"-c:a",
		"libopus",
		"-b:a",
		"32k",
		"-application",
		"voip",
		"-f",
		"ogg",
		outputPath,
	)
	if outputBytes, err := cmd.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("%w: %s", err, strings.TrimSpace(string(outputBytes)))
	}

	return os.ReadFile(outputPath)
}

func probeAudioDuration(ctx context.Context, data []byte, contentType string) (uint32, error) {
	inputPath, cleanup, err := writeTempAudio(data, contentType)
	if err != nil {
		return 0, err
	}
	defer cleanup()

	cmd := exec.CommandContext(
		ctx,
		"ffprobe",
		"-v",
		"error",
		"-show_entries",
		"format=duration",
		"-of",
		"default=noprint_wrappers=1:nokey=1",
		inputPath,
	)
	output, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	duration, err := strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
	if err != nil {
		return 0, err
	}

	seconds := uint32(math.Ceil(duration))
	if seconds == 0 {
		seconds = 1
	}
	return seconds, nil
}

func generateAudioWaveform(ctx context.Context, data []byte, contentType string) ([]byte, error) {
	inputPath, cleanup, err := writeTempAudio(data, contentType)
	if err != nil {
		return nil, err
	}
	defer cleanup()

	output, err := os.CreateTemp("", "whatsmeow-waveform-*.pcm")
	if err != nil {
		return nil, err
	}
	outputPath := output.Name()
	output.Close()
	defer os.Remove(outputPath)

	cmd := exec.CommandContext(
		ctx,
		"ffmpeg",
		"-hide_banner",
		"-loglevel",
		"error",
		"-y",
		"-i",
		inputPath,
		"-vn",
		"-ac",
		"1",
		"-ar",
		"8000",
		"-f",
		"s16le",
		outputPath,
	)
	if outputBytes, err := cmd.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("%w: %s", err, strings.TrimSpace(string(outputBytes)))
	}

	pcm, err := os.ReadFile(outputPath)
	if err != nil {
		return nil, err
	}
	return pcmWaveform(pcm), nil
}

func writeTempAudio(data []byte, contentType string) (string, func(), error) {
	input, err := os.CreateTemp("", "whatsmeow-audio-*"+audioInputExtension(contentType))
	if err != nil {
		return "", nil, err
	}
	inputPath := input.Name()
	cleanup := func() { os.Remove(inputPath) }

	if _, err := input.Write(data); err != nil {
		input.Close()
		cleanup()
		return "", nil, err
	}
	if err := input.Close(); err != nil {
		cleanup()
		return "", nil, err
	}
	return inputPath, cleanup, nil
}

func pcmWaveform(pcm []byte) []byte {
	if len(pcm) < 2 {
		return defaultAudioWaveform()
	}

	const waveformSize = 64
	samples := len(pcm) / 2
	waveform := make([]byte, waveformSize)
	for index := range waveform {
		start := index * samples / waveformSize
		end := (index + 1) * samples / waveformSize
		if end <= start {
			end = start + 1
		}

		var peak int
		for sampleIndex := start; sampleIndex < end && sampleIndex < samples; sampleIndex++ {
			offset := sampleIndex * 2
			sample := int(int16(uint16(pcm[offset]) | uint16(pcm[offset+1])<<8))
			if sample < 0 {
				sample = -sample
			}
			if sample > peak {
				peak = sample
			}
		}
		waveform[index] = byte(min(255, peak*255/32768))
	}
	return waveform
}

func defaultAudioWaveform() []byte {
	waveform := make([]byte, 64)
	for index := range waveform {
		waveform[index] = 32
	}
	return waveform
}

func audioInputExtension(contentType string) string {
	extension := extensionForMIME(contentType)
	if extension != "" {
		return extension
	}

	switch normalizedMIME(contentType, "") {
	case "audio/mp3", "audio/mpeg":
		return ".mp3"
	case "audio/webm":
		return ".webm"
	case "audio/wav", "audio/x-wav":
		return ".wav"
	case "audio/ogg":
		return ".ogg"
	default:
		return ".audio"
	}
}

func voiceNoteFileName(fileName string) string {
	fileName = strings.TrimSpace(fileName)
	if fileName == "" {
		return defaultFileName("audio", "audio/ogg")
	}

	if extensionStart := strings.LastIndex(fileName, "."); extensionStart > 0 {
		return fileName[:extensionStart] + ".ogg"
	}
	return fileName + ".ogg"
}

func shouldSendAsPushToTalk(contentType string, recordedAudio bool) bool {
	return recordedAudio && canSendAsPushToTalk(contentType)
}

func canSendAsPushToTalk(contentType string) bool {
	contentType = strings.ToLower(normalizedMIME(contentType, ""))
	return strings.Contains(contentType, "audio/ogg") || strings.Contains(contentType, "opus")
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

func parseParticipantJID(values ...string) (types.JID, bool) {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if strings.Contains(value, "@") {
			jid, ok := parseJID(value)
			if ok {
				return jid.ToNonAD(), true
			}
			continue
		}
		phone, ok := normalizePhoneForWhatsAppCheck(value)
		if !ok {
			continue
		}
		return types.NewJID(strings.TrimPrefix(phone, "+"), types.DefaultUserServer), true
	}
	return types.JID{}, false
}

func normalizePhoneForWhatsAppCheck(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", false
	}

	if strings.Contains(value, "@") {
		jid, ok := parseJID(value)
		if !ok {
			return "", false
		}
		value = jid.User
	}

	var digits strings.Builder
	for _, r := range value {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}

	number := digits.String()
	if len(number) < 10 || len(number) > 15 {
		return "", false
	}
	return "+" + number, true
}

func groupInviteCodeFromRequest(c *gin.Context) (string, bool) {
	candidates := []string{
		c.Query("code"),
		c.Query("invite_code"),
		c.Query("url"),
		c.Query("link"),
	}

	if c.Request.Method != http.MethodGet {
		var request GroupInviteRequest
		if err := c.ShouldBindJSON(&request); err == nil {
			candidates = append(candidates, request.Code, request.InviteCode, request.URL, request.Link)
		}
	}

	for _, candidate := range candidates {
		if code, ok := normalizeGroupInviteCode(candidate); ok {
			return code, true
		}
	}
	return "", false
}

func normalizeGroupInviteCode(value string) (string, bool) {
	value = strings.TrimSpace(value)
	value = strings.Trim(value, "\"'<>.,;:)]}")
	if value == "" {
		return "", false
	}

	lowerValue := strings.ToLower(value)
	looksLikeURL := strings.Contains(lowerValue, "://") || strings.HasPrefix(lowerValue, "www.") || strings.Contains(lowerValue, ".")
	for _, prefix := range []string{"https://", "http://"} {
		if strings.HasPrefix(lowerValue, prefix) {
			value = value[len(prefix):]
			lowerValue = strings.ToLower(value)
			break
		}
	}
	if strings.HasPrefix(lowerValue, "www.") {
		value = value[4:]
		lowerValue = strings.ToLower(value)
	}
	isWhatsAppInviteURL := strings.HasPrefix(lowerValue, "chat.whatsapp.com/")
	if looksLikeURL && !isWhatsAppInviteURL {
		return "", false
	}
	if isWhatsAppInviteURL {
		value = value[len("chat.whatsapp.com/"):]
	}
	if strings.Contains(value, "/") {
		parts := strings.Split(value, "/")
		value = parts[len(parts)-1]
	}
	if index := strings.IndexAny(value, "?#"); index >= 0 {
		value = value[:index]
	}
	value = strings.Trim(value, "\"'<>.,;:)]}")

	if !isGroupInviteCode(value) {
		return "", false
	}
	return value, true
}

func isGroupInviteCode(value string) bool {
	if len(value) < 6 {
		return false
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			continue
		}
		return false
	}
	return true
}

func groupInviteErrorStatus(err error) int {
	if errors.Is(err, whatsmeow.ErrInviteLinkInvalid) || errors.Is(err, whatsmeow.ErrInviteLinkRevoked) {
		return http.StatusBadRequest
	}
	return http.StatusBadGateway
}

func safeDisconnectClient(client *whatsmeow.Client) {
	if client == nil {
		return
	}
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Recovered from Whatsmeow disconnect panic: %v", r)
		}
	}()
	client.Disconnect()
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
		processReceiptForInbox(channelID, accountID, client, v)

	case *events.HistorySync:
		processHistorySyncForInbox(channelID, accountID, client, v)
	}
}

func processReceiptForInbox(channelID string, accountID string, client *whatsmeow.Client, receipt *events.Receipt) {
	if isStatusBroadcastReceipt(receipt) {
		processStatusReceiptForInbox(channelID, accountID, client, receipt)
		return
	}

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

func isStatusBroadcastReceipt(receipt *events.Receipt) bool {
	return receipt != nil && sameBareJID(receipt.Chat, types.StatusBroadcastJID)
}

func processStatusReceiptForInbox(channelID string, accountID string, client *whatsmeow.Client, receipt *events.Receipt) {
	if !isStatusViewReceiptType(receipt.Type) {
		logUnclassifiedStatusReceipt(channelID, receipt, types.JID{}, "unsupported_receipt_type")
		return
	}

	knownOwnStatusIDs, err := ownStatusReceiptMessageIDs(channelID, receipt.MessageIDs)
	if err != nil {
		log.Printf("Failed to look up Status receipt IDs on channel %s: %v", channelID, err)
	}

	viewerJID := statusReceiptViewerJID(client, receipt)
	ownJID, _ := currentClientJID(client)
	ownLID := types.JID{}
	if client != nil && client.Store != nil {
		ownLID = client.Store.LID.ToNonAD()
	}

	classification := classifyStatusViewReceipt(receipt, viewerJID, ownJID, ownLID, knownOwnStatusIDs)
	if len(classification.MessageIDs) == 0 {
		logUnclassifiedStatusReceipt(channelID, receipt, viewerJID, classification.Reason)
		return
	}

	processStatusViewReceiptForInbox(channelID, accountID, client, receipt, classification.ViewerJID, classification.MessageIDs)
}

func isStatusViewReceiptType(receiptType types.ReceiptType) bool {
	return receiptType == types.ReceiptTypeRead || receiptType == types.ReceiptTypePlayed
}

func statusReceiptViewerJID(client *whatsmeow.Client, receipt *events.Receipt) types.JID {
	if receipt == nil {
		return types.JID{}
	}

	viewerJID := firstUsableJID(receipt.SenderAlt, receipt.Sender)
	if resolvedJID := resolveStatusPhoneJID(client, viewerJID); !resolvedJID.IsEmpty() {
		return resolvedJID
	}
	return viewerJID
}

type statusViewReceiptClassification struct {
	ViewerJID  types.JID
	MessageIDs []types.MessageID
	Reason     string
}

func classifyStatusViewReceipt(
	receipt *events.Receipt,
	viewerJID types.JID,
	ownJID types.JID,
	ownLID types.JID,
	knownOwnStatusIDs map[types.MessageID]struct{},
) statusViewReceiptClassification {
	classification := statusViewReceiptClassification{ViewerJID: viewerJID}
	if receipt == nil || !isStatusBroadcastReceipt(receipt) {
		classification.Reason = "not_status_broadcast"
		return classification
	}
	if !isStatusViewReceiptType(receipt.Type) {
		classification.Reason = "unsupported_receipt_type"
		return classification
	}
	if len(receipt.MessageIDs) == 0 {
		classification.Reason = "missing_message_ids"
		return classification
	}
	if viewerJID.IsEmpty() {
		classification.Reason = "missing_participant"
		return classification
	}
	if isCurrentStatusAccountJID(viewerJID, ownJID, ownLID) {
		// A linked device reporting that we read somebody else's Status is not a
		// viewer of our own Status.
		classification.Reason = "self_participant"
		return classification
	}

	for _, messageID := range receipt.MessageIDs {
		if _, ok := knownOwnStatusIDs[messageID]; ok {
			classification.MessageIDs = append(classification.MessageIDs, messageID)
		}
	}
	if len(classification.MessageIDs) > 0 {
		return classification
	}

	// WhatsApp normally exposes the Status owner in the recipient field. In
	// LID-addressed variants that field can be empty or not match the phone JID,
	// so it is a compatibility fallback rather than the only proof. The source
	// IDs above are the authoritative path when the Status is already persisted.
	if isCurrentStatusAccountJID(receipt.MessageSender, ownJID, ownLID) ||
		isCurrentStatusAccountJID(receipt.BroadcastListOwner, ownJID, ownLID) {
		classification.MessageIDs = append(classification.MessageIDs, receipt.MessageIDs...)
		return classification
	}

	classification.Reason = "no_matching_own_status"
	return classification
}

func isCurrentStatusAccountJID(candidate types.JID, ownJID types.JID, ownLID types.JID) bool {
	return sameBareJID(candidate, ownJID) || sameBareJID(candidate, ownLID)
}

func ownStatusReceiptMessageIDs(inboxID string, messageIDs []types.MessageID) (map[types.MessageID]struct{}, error) {
	knownIDs := make(map[types.MessageID]struct{})
	if inboxID == "" || len(messageIDs) == 0 {
		return knownIDs, nil
	}

	statusIDs := make([]string, 0, len(messageIDs))
	for _, messageID := range messageIDs {
		if messageID != "" {
			statusIDs = append(statusIDs, string(messageID))
		}
	}
	if len(statusIDs) == 0 {
		return knownIDs, nil
	}

	dbURI := os.Getenv("DATABASE_URL")
	if dbURI == "" {
		dbURI = "postgres://postgres:StagingPassword123!@chatwoot-staging-db:5432/chatwoot_staging?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURI)
	if err != nil {
		return knownIDs, err
	}
	defer db.Close()

	rows, err := db.Query(`
		SELECT source_id
		FROM whatsmeow_statuses
		WHERE inbox_id = $1 AND from_me = TRUE AND source_id = ANY($2)
	`, inboxID, pq.Array(statusIDs))
	if err != nil {
		return knownIDs, err
	}
	defer rows.Close()

	for rows.Next() {
		var sourceID string
		if err := rows.Scan(&sourceID); err != nil {
			return knownIDs, err
		}
		knownIDs[types.MessageID(sourceID)] = struct{}{}
	}
	return knownIDs, rows.Err()
}

func logUnclassifiedStatusReceipt(channelID string, receipt *events.Receipt, viewerJID types.JID, reason string) {
	if receipt == nil {
		return
	}

	messageIDs := make([]string, 0, min(len(receipt.MessageIDs), 10))
	for _, messageID := range receipt.MessageIDs {
		if messageID == "" {
			continue
		}
		messageIDs = append(messageIDs, string(messageID))
		if len(messageIDs) == 10 {
			break
		}
	}

	log.Printf(
		"Unclassified WhatsApp Status receipt channel=%s reason=%s type=%s chat=%s participant=%s sender_alt=%s message_sender=%s broadcast_owner=%s ids=%s",
		channelID,
		reason,
		receipt.Type,
		jidString(receipt.Chat),
		jidString(receipt.Sender),
		jidString(receipt.SenderAlt),
		jidString(receipt.MessageSender),
		jidString(receipt.BroadcastListOwner),
		strings.Join(messageIDs, ","),
	)
}

func processStatusViewReceiptForInbox(
	channelID string,
	accountID string,
	client *whatsmeow.Client,
	receipt *events.Receipt,
	viewerJID types.JID,
	messageIDs []types.MessageID,
) {

	viewerName := getContactDisplayName(client, viewerJID, "")
	if viewerName == "" {
		viewerName = firstFriendlyDisplayName(phoneNumberFromJID(viewerJID), jidString(viewerJID))
	}
	viewerPhone := phoneNumberFromJID(viewerJID)
	viewerProfilePictureURL := getProfilePictureURL(client, viewerJID)

	for _, messageID := range messageIDs {
		if messageID == "" {
			continue
		}

		payload := map[string]interface{}{
			"event":               "status_view",
			"status":              "read",
			"receipt_type":        string(receipt.Type),
			"source_status_id":    string(messageID),
			"message_id":          string(messageID),
			"viewer_jid":          jidString(viewerJID),
			"viewer_name":         viewerName,
			"viewer_phone":        viewerPhone,
			"profile_picture_url": viewerProfilePictureURL,
			"chat":                jidString(receipt.Chat),
			"sender":              jidString(receipt.Sender),
			"sender_alt":          jidString(receipt.SenderAlt),
			"timestamp":           receipt.Timestamp.Unix(),
		}
		sendWebhookNotification(accountID, channelID, payload)
	}
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

	statusCutoff := time.Now().Add(-24 * time.Hour)
	processedStatuses := 0
	for _, webMessage := range historySync.Data.GetStatusV3Messages() {
		if webMessage == nil {
			continue
		}

		messageEvent, err := client.ParseWebMessage(types.StatusBroadcastJID, webMessage)
		if err != nil {
			log.Printf("Failed to parse Status history message on channel %s: %v", channelID, err)
			continue
		}
		if messageEvent == nil || messageEvent.Info.Timestamp.Before(statusCutoff) {
			continue
		}

		processMessageForInbox(channelID, accountID, client, messageEvent)
		processedStatuses++
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
	if processedStatuses > 0 {
		log.Printf("Processed %d active Status history messages on channel %s", processedStatuses, channelID)
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
	statusMessage := isStatusMessage(messageEvent.Info)
	if statusMessage && processDeleteForInbox(channelID, accountID, messageEvent) {
		return
	}

	settings, err := getChannelSettings(channelID)
	if err == nil {
		isGroup := !statusMessage && (messageEvent.Info.MessageSource.IsGroup || messageEvent.Info.Sender.Server == "g.us" || messageEvent.Info.Chat.Server == "g.us")
		if settings.IgnoreGroups && isGroup {
			log.Printf("Ignoring group message from %s on channel %s (IgnoreGroups=true)", messageEvent.Info.Sender.String(), channelID)
			return
		}
		if settings.IgnoreStatus && statusMessage {
			log.Printf("Ignoring status update from %s on channel %s (IgnoreStatus=true)", messageEvent.Info.Sender.String(), channelID)
			return
		}
		isNewsletter := isNewsletterJID(messageEvent.Info.Chat) || isNewsletterJID(messageEvent.Info.Sender) || isNewsletterJID(messageEvent.Info.SenderAlt)
		if settings.IgnoreNews && isNewsletter {
			log.Printf("Ignoring newsletter message from %s on channel %s (IgnoreNewsletters=true)", messageEvent.Info.Sender.String(), channelID)
			return
		}
	}

	if !statusMessage && processDeleteForInbox(channelID, accountID, messageEvent) {
		return
	}
	if statusMessage {
		processStatusForInbox(channelID, accountID, client, messageEvent)
		return
	}

	if processEditForInbox(channelID, accountID, messageEvent) {
		return
	}

	if processReactionForInbox(channelID, accountID, messageEvent) {
		return
	}

	messageText := extractMessageText(messageEvent.Message)
	attachments := extractMediaAttachments(client, messageEvent.Message)
	contacts := extractContactCards(client, messageEvent.Message)
	quotedMessage := extractQuotedMessage(messageEvent.Message)
	if messageText == "" && len(attachments) == 0 && len(contacts) == 0 {
		if !hasMediaMessage(messageEvent.Message) {
			return
		}
		log.Printf("Incoming media message had no downloadable attachments; media_type=%s message_id=%s", detectedMediaType(messageEvent.Message), messageEvent.Info.ID)
		messageText = "Media attachment could not be downloaded."
	}
	if messageText == "" && len(contacts) > 0 {
		messageText = contactMessageText(contacts)
	}

	isGroup := isGroupMessage(messageEvent.Info)
	contactJID := preferredContactJID(messageEvent.Info)
	participant := ResolvedGroupParticipant{}
	groupName := ""
	if isGroup {
		contactJID = messageEvent.Info.Chat.ToNonAD()
		groupName = getGroupName(client, contactJID)
		participant = resolveGroupParticipant(
			client,
			contactJID,
			messageEvent.Info.PushName,
			messageEvent.Info.SenderAlt,
			messageEvent.Info.Sender,
		)
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

	senderName := getContactDisplayName(client, contactJID, messageEvent.Info.PushName)
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
		"attachments":         attachments,
		"contacts":            contacts,
		"timestamp":           messageEvent.Info.Timestamp.Unix(),
	}
	if isGroup {
		payload["is_group"] = true
		payload["group_jid"] = jidString(contactJID)
		payload["group_name"] = groupName
		payload["participant_jid"] = jidString(participant.JID)
		payload["participant_lid_jid"] = jidString(participant.LIDJID)
		payload["participant_name"] = participant.Name
		payload["participant_phone"] = participant.PhoneNumber
		payload["participant_profile_picture_url"] = participant.ProfilePictureURL
	}
	if quotedMessage.MessageID != "" {
		payload["quoted_message_id"] = quotedMessage.MessageID
		payload["quoted_participant"] = quotedMessage.Participant
		payload["quoted_content"] = quotedMessage.Content
		payload["quoted_file_type"] = quotedMessage.FileType
	}
	sendWebhookNotification(accountID, channelID, payload)
}

func isStatusMessage(info types.MessageInfo) bool {
	return sameBareJID(info.Chat, types.StatusBroadcastJID)
}

func processStatusForInbox(channelID string, accountID string, client *whatsmeow.Client, messageEvent *events.Message) {
	messageText := extractMessageText(messageEvent.Message)
	attachments := extractMediaAttachments(client, messageEvent.Message)
	if messageText == "" && len(attachments) == 0 {
		if hasMediaMessage(messageEvent.Message) {
			log.Printf("Status media could not be downloaded; media_type=%s message_id=%s", detectedMediaType(messageEvent.Message), messageEvent.Info.ID)
		}
		return
	}

	senderJID := messageEvent.Info.Sender
	senderAlt := messageEvent.Info.SenderAlt
	displayJID := firstUsableJID(senderAlt, senderJID)
	if resolvedJID := resolveStatusPhoneJID(client, displayJID); !resolvedJID.IsEmpty() {
		displayJID = resolvedJID
		if senderAlt.IsEmpty() {
			senderAlt = resolvedJID
		}
	}
	if messageEvent.Info.IsFromMe {
		if ownJID, _ := currentClientJID(client); !ownJID.IsEmpty() {
			senderJID = ownJID
			displayJID = ownJID
		}
	}
	if senderJID.IsEmpty() {
		senderJID = displayJID
	}

	payload := map[string]interface{}{
		"event":                 "status",
		"sender":                jidString(senderJID),
		"sender_alt":            jidString(senderAlt),
		"sender_name":           getContactDisplayName(client, displayJID, messageEvent.Info.PushName),
		"sender_phone":          phoneNumberFromJID(displayJID),
		"profile_picture_url":   getProfilePictureURL(client, displayJID),
		"chat":                  jidString(messageEvent.Info.Chat),
		"from_me":               messageEvent.Info.IsFromMe,
		"message_id":            messageEvent.Info.ID,
		"content":               messageText,
		"attachments":           attachments,
		"timestamp":             messageEvent.Info.Timestamp.Unix(),
		"status_type":           statusType(messageEvent.Message),
		"status_metadata":       extractStatusMetadata(messageEvent.Message),
		"status_already_viewed": sourceStatusAlreadyViewed(messageEvent),
	}
	log.Printf("Received Status from %s on channel %s: %s", jidString(senderJID), channelID, messageEvent.Info.ID)
	sendWebhookNotification(accountID, channelID, payload)
}

func resolveStatusPhoneJID(client *whatsmeow.Client, jid types.JID) types.JID {
	if isPhoneJID(jid) {
		return jid.ToNonAD()
	}
	if client == nil || client.Store == nil || client.Store.LIDs == nil || jid.Server != types.HiddenUserServer {
		return types.JID{}
	}

	phoneJID, err := client.Store.LIDs.GetPNForLID(context.Background(), jid.ToNonAD())
	if err != nil || !isPhoneJID(phoneJID) {
		return types.JID{}
	}
	return phoneJID.ToNonAD()
}

func sourceStatusAlreadyViewed(messageEvent *events.Message) bool {
	return messageEvent.SourceWebMsg != nil && messageEvent.SourceWebMsg.GetStatusAlreadyViewed()
}

func statusType(message *proto.Message) string {
	message = unwrapMessage(message)
	if message == nil {
		return "text"
	}
	switch {
	case message.GetImageMessage() != nil:
		return "image"
	case message.GetVideoMessage() != nil:
		return "video"
	case message.GetAudioMessage() != nil:
		return "audio"
	default:
		return "text"
	}
}

func extractStatusMetadata(message *proto.Message) map[string]interface{} {
	message = unwrapMessage(message)
	metadata := map[string]interface{}{}
	if message == nil {
		return metadata
	}

	if text := message.GetExtendedTextMessage(); text != nil {
		metadata["background_argb"] = text.GetBackgroundArgb()
		metadata["text_argb"] = text.GetTextArgb()
		metadata["font_value"] = int32(text.GetFont())
	}
	if image := message.GetImageMessage(); image != nil {
		metadata["width"] = image.GetWidth()
		metadata["height"] = image.GetHeight()
	}
	if video := message.GetVideoMessage(); video != nil {
		metadata["width"] = video.GetWidth()
		metadata["height"] = video.GetHeight()
		metadata["duration_seconds"] = video.GetSeconds()
		if mimeType := normalizedMIME(video.GetMimetype(), ""); mimeType != "" {
			metadata["source_mimetype"] = mimeType
		}
		if thumbnail := video.GetJPEGThumbnail(); len(thumbnail) > 0 {
			metadata["thumbnail_base64"] = base64.StdEncoding.EncodeToString(thumbnail)
			metadata["thumbnail_content_type"] = "image/jpeg"
		}
	}
	if audio := message.GetAudioMessage(); audio != nil {
		metadata["duration_seconds"] = audio.GetSeconds()
	}

	return metadata
}

func processEditForInbox(channelID string, accountID string, messageEvent *events.Message) bool {
	protocolMessage := rawEditedProtocolMessage(messageEvent.RawMessage)
	if !isEditedMessageEvent(messageEvent, protocolMessage) {
		return false
	}

	messageID := editedMessageID(messageEvent, protocolMessage)
	if messageID == "" {
		return true
	}

	editedContent := extractMessageText(messageEvent.Message)
	if editedContent == "" && protocolMessage != nil {
		editedContent = extractMessageText(protocolMessage.GetEditedMessage())
	}
	if editedContent == "" {
		return true
	}

	chat := jidString(messageEvent.Info.Chat)
	timestamp := messageEvent.Info.Timestamp.Unix()
	if editTimestamp := editedMessageTimestamp(protocolMessage); editTimestamp > 0 {
		timestamp = editTimestamp
	}

	payload := map[string]interface{}{
		"event":          "edit",
		"message_id":     messageID,
		"edited_content": editedContent,
		"sender":         jidString(messageEvent.Info.Sender),
		"sender_alt":     jidString(messageEvent.Info.SenderAlt),
		"chat":           chat,
		"from_me":        messageEvent.Info.IsFromMe,
		"timestamp":      timestamp,
	}
	log.Printf(
		"Forwarding edited WhatsApp message %s on channel %s (event_id=%s protocol_id=%s edit_attr=%s is_edit=%t)",
		messageID,
		channelID,
		messageEvent.Info.ID,
		protocolMessageID(protocolMessage),
		messageEvent.Info.Edit,
		messageEvent.IsEdit,
	)
	sendWebhookNotification(accountID, channelID, payload)
	return true
}

func isEditedMessageEvent(messageEvent *events.Message, protocolMessage *proto.ProtocolMessage) bool {
	if messageEvent.IsEdit || protocolMessage != nil {
		return true
	}

	if messageEvent.Info.Edit == types.EditAttributeMessageEdit || messageEvent.Info.Edit == types.EditAttributeAdminEdit {
		return true
	}

	return messageEvent.NewsletterMeta != nil && !messageEvent.NewsletterMeta.EditTS.IsZero()
}

func editedMessageID(messageEvent *events.Message, protocolMessage *proto.ProtocolMessage) string {
	if id := protocolMessageID(protocolMessage); id != "" {
		return id
	}

	return messageEvent.Info.ID
}

func protocolMessageID(protocolMessage *proto.ProtocolMessage) string {
	if protocolMessage == nil {
		return ""
	}
	return protocolMessage.GetKey().GetID()
}

func editedMessageTimestamp(protocolMessage *proto.ProtocolMessage) int64 {
	if protocolMessage == nil {
		return 0
	}

	timestampMS := protocolMessage.GetTimestampMS()
	if timestampMS <= 0 {
		return 0
	}

	return timestampMS / 1000
}

func rawEditedProtocolMessage(message *proto.Message) *proto.ProtocolMessage {
	if message == nil {
		return nil
	}

	protocolMessage := message.GetProtocolMessage()
	if protocolMessage != nil && protocolMessage.GetType() == proto.ProtocolMessage_MESSAGE_EDIT {
		return protocolMessage
	}

	if editedMessage := message.GetEditedMessage().GetMessage(); editedMessage != nil {
		return rawEditedProtocolMessage(editedMessage)
	}
	if inner := message.GetDeviceSentMessage().GetMessage(); inner != nil {
		return rawEditedProtocolMessage(inner)
	}
	if inner := message.GetEphemeralMessage().GetMessage(); inner != nil {
		return rawEditedProtocolMessage(inner)
	}
	if inner := message.GetViewOnceMessage().GetMessage(); inner != nil {
		return rawEditedProtocolMessage(inner)
	}
	if inner := message.GetViewOnceMessageV2().GetMessage(); inner != nil {
		return rawEditedProtocolMessage(inner)
	}
	if inner := message.GetViewOnceMessageV2Extension().GetMessage(); inner != nil {
		return rawEditedProtocolMessage(inner)
	}
	if inner := message.GetDocumentWithCaptionMessage().GetMessage(); inner != nil {
		return rawEditedProtocolMessage(inner)
	}

	return nil
}

func processDeleteForInbox(channelID string, accountID string, messageEvent *events.Message) bool {
	message := unwrapMessage(messageEvent.Message)
	if message != nil {
		protocolMessage := message.GetProtocolMessage()
		if protocolMessage != nil && protocolMessage.GetType() == proto.ProtocolMessage_REVOKE {
			key := protocolMessage.GetKey()
			if key == nil || key.GetID() == "" {
				return true
			}

			chat := key.GetRemoteJID()
			if chat == "" {
				chat = jidString(messageEvent.Info.Chat)
			}

			sendDeleteWebhookNotification(
				channelID,
				accountID,
				messageEvent,
				key.GetID(),
				chat,
				key.GetFromMe(),
				key.GetParticipant(),
				messageEvent.Info.Timestamp.Unix(),
			)
			return true
		}
	}

	sourceWebMsg := messageEvent.SourceWebMsg
	if sourceWebMsg == nil || !isSourceWebMsgRevoke(sourceWebMsg.GetMessageStubType()) {
		return false
	}

	key := sourceWebMsg.GetTargetMessageID()
	if key == nil || key.GetID() == "" {
		key = sourceWebMsg.GetKey()
	}
	if key == nil || key.GetID() == "" {
		return true
	}

	chat := key.GetRemoteJID()
	if chat == "" {
		chat = sourceWebMsg.GetKey().GetRemoteJID()
	}
	if chat == "" {
		chat = jidString(messageEvent.Info.Chat)
	}

	timestamp := messageEvent.Info.Timestamp.Unix()
	if sourceWebMsg.GetRevokeMessageTimestamp() > 0 {
		timestamp = int64(sourceWebMsg.GetRevokeMessageTimestamp())
	}

	sendDeleteWebhookNotification(
		channelID,
		accountID,
		messageEvent,
		key.GetID(),
		chat,
		key.GetFromMe(),
		key.GetParticipant(),
		timestamp,
	)
	return true
}

func isSourceWebMsgRevoke(stubType waWeb.WebMessageInfo_StubType) bool {
	return stubType == waWeb.WebMessageInfo_REVOKE || stubType == waWeb.WebMessageInfo_ADMIN_REVOKE
}

func sendDeleteWebhookNotification(
	channelID string,
	accountID string,
	messageEvent *events.Message,
	messageID string,
	chat string,
	keyFromMe bool,
	participant string,
	timestamp int64,
) {
	event := "delete"
	if isStatusMessage(messageEvent.Info) || isStatusChat(chat) {
		event = "status_delete"
	}
	payload := map[string]interface{}{
		"event":        event,
		"message_id":   messageID,
		"sender":       jidString(messageEvent.Info.Sender),
		"sender_alt":   jidString(messageEvent.Info.SenderAlt),
		"chat":         chat,
		"from_me":      messageEvent.Info.IsFromMe,
		"key_from_me":  keyFromMe,
		"timestamp":    timestamp,
		"receipt_type": "revoke",
	}
	if participant != "" {
		payload["participant"] = participant
	}

	sendWebhookNotification(accountID, channelID, payload)
}

func isStatusChat(value string) bool {
	jid, ok := parseJID(value)
	return ok && sameBareJID(jid, types.StatusBroadcastJID)
}

func processReactionForInbox(channelID string, accountID string, messageEvent *events.Message) bool {
	if messageEvent.Message == nil {
		return false
	}

	reaction := messageEvent.Message.GetReactionMessage()
	if reaction == nil {
		return false
	}

	key := reaction.GetKey()
	if key == nil || key.GetID() == "" {
		return true
	}

	payload := map[string]interface{}{
		"event":      "reaction",
		"message_id": key.GetID(),
		"reaction":   reaction.GetText(),
		"sender":     jidString(messageEvent.Info.Sender),
		"sender_alt": jidString(messageEvent.Info.SenderAlt),
		"chat":       key.GetRemoteJID(),
		"from_me":    messageEvent.Info.IsFromMe,
		"timestamp":  messageEvent.Info.Timestamp.Unix(),
	}
	sendWebhookNotification(accountID, channelID, payload)
	return true
}

func extractQuotedMessage(message *proto.Message) QuotedMessagePayload {
	contextInfo := extractContextInfo(message)
	if contextInfo == nil || contextInfo.GetStanzaID() == "" {
		return QuotedMessagePayload{}
	}

	quotedMessage := contextInfo.GetQuotedMessage()
	fileType := quotedMessageFileType(quotedMessage)
	content := extractMessageText(quotedMessage)
	if content == "" {
		content = quotedFileTypeLabel(fileType)
	}

	return QuotedMessagePayload{
		MessageID:   contextInfo.GetStanzaID(),
		Participant: contextInfo.GetParticipant(),
		Content:     content,
		FileType:    fileType,
	}
}

func extractContextInfo(message *proto.Message) *proto.ContextInfo {
	message = unwrapMessage(message)
	if message == nil {
		return nil
	}

	if item := message.GetExtendedTextMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetImageMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetVideoMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetAudioMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetDocumentMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetStickerMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetLocationMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetContactMessage(); item != nil {
		return item.GetContextInfo()
	}
	if item := message.GetContactsArrayMessage(); item != nil {
		return item.GetContextInfo()
	}

	return nil
}

func quotedMessageFileType(message *proto.Message) string {
	message = unwrapMessage(message)
	if message == nil {
		return ""
	}

	switch {
	case message.GetImageMessage() != nil || message.GetStickerMessage() != nil:
		return "image"
	case message.GetVideoMessage() != nil:
		return "video"
	case message.GetAudioMessage() != nil:
		return "audio"
	case message.GetDocumentMessage() != nil:
		return "file"
	case message.GetContactMessage() != nil || message.GetContactsArrayMessage() != nil:
		return "contact"
	case message.GetLocationMessage() != nil:
		return "location"
	default:
		return ""
	}
}

func quotedFileTypeLabel(fileType string) string {
	switch strings.ToLower(strings.TrimSpace(fileType)) {
	case "audio":
		return "Mensagem de \u00e1udio"
	case "image":
		return "Mensagem de imagem"
	case "video":
		return "Mensagem de v\u00eddeo"
	case "file", "document":
		return "Arquivo"
	case "contact":
		return "Contato"
	case "location":
		return "Localiza\u00e7\u00e3o"
	default:
		return "Mensagem"
	}
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

func extractContactCards(client *whatsmeow.Client, message *proto.Message) []WhatsmeowContact {
	message = unwrapMessage(message)
	if message == nil {
		return nil
	}

	if contact := message.GetContactMessage(); contact != nil {
		return []WhatsmeowContact{buildContactCard(client, contact)}
	}
	if contactsArray := message.GetContactsArrayMessage(); contactsArray != nil {
		contacts := make([]WhatsmeowContact, 0, len(contactsArray.GetContacts()))
		for _, contact := range contactsArray.GetContacts() {
			if contact == nil {
				continue
			}
			contacts = append(contacts, buildContactCard(client, contact))
		}
		return contacts
	}

	return nil
}

func buildContactCard(client *whatsmeow.Client, contact *proto.ContactMessage) WhatsmeowContact {
	vcard := contact.GetVcard()
	card := parseVCardContact(vcard)
	card.DisplayName = firstNonBlank(contact.GetDisplayName(), card.DisplayName, card.FullName, card.PhoneNumber)
	card.Vcard = vcard
	card = enrichContactCard(client, card)

	return card
}

func parseVCardContact(vcard string) WhatsmeowContact {
	card := WhatsmeowContact{}
	for _, line := range unfoldedVCardLines(vcard) {
		key, params, value, ok := splitVCardLine(line)
		if !ok {
			continue
		}

		switch key {
		case "FN":
			card.FullName = firstNonBlank(card.FullName, value)
			card.DisplayName = firstNonBlank(card.DisplayName, value)
		case "N":
			parts := strings.Split(value, ";")
			if len(parts) > 0 {
				card.LastName = firstNonBlank(card.LastName, strings.TrimSpace(parts[0]))
			}
			if len(parts) > 1 {
				card.FirstName = firstNonBlank(card.FirstName, strings.TrimSpace(parts[1]))
			}
		case "TEL":
			card.PhoneNumber = firstNonBlank(card.PhoneNumber, normalizeVCardPhone(value))
			card.WhatsAppID = firstNonBlank(card.WhatsAppID, normalizeWhatsAppID(params))
		case "EMAIL":
			card.Email = firstNonBlank(card.Email, value)
		case "ORG":
			card.Organization = firstNonBlank(card.Organization, value)
		case "TITLE":
			card.Title = firstNonBlank(card.Title, value)
		case "URL":
			card.Website = firstNonBlank(card.Website, value)
		case "NOTE":
			card.Note = firstNonBlank(card.Note, value)
		case "X-WA-BIZ-NAME":
			card.Organization = firstNonBlank(card.Organization, value)
		case "X-WA-BIZ-DESCRIPTION":
			card.Note = firstNonBlank(card.Note, value)
		}
	}

	card.FullName = firstNonBlank(card.FullName, strings.TrimSpace(strings.Join([]string{card.FirstName, card.LastName}, " ")), card.DisplayName)
	card.DisplayName = firstNonBlank(card.DisplayName, card.FullName, card.Organization, card.PhoneNumber)
	if card.PhoneNumber == "" && card.WhatsAppID != "" {
		card.PhoneNumber = normalizeVCardPhone(card.WhatsAppID)
	}
	if card.JID == "" && card.WhatsAppID != "" {
		card.JID = fmt.Sprintf("%s@%s", digitsOnly(card.WhatsAppID), types.DefaultUserServer)
	}

	return card
}

func unfoldedVCardLines(vcard string) []string {
	rawLines := strings.Split(strings.ReplaceAll(vcard, "\r\n", "\n"), "\n")
	lines := make([]string, 0, len(rawLines))
	for _, rawLine := range rawLines {
		if rawLine == "" {
			continue
		}
		if (strings.HasPrefix(rawLine, " ") || strings.HasPrefix(rawLine, "\t")) && len(lines) > 0 {
			lines[len(lines)-1] += strings.TrimLeft(rawLine, " \t")
			continue
		}
		lines = append(lines, rawLine)
	}
	return lines
}

func splitVCardLine(line string) (string, string, string, bool) {
	parts := strings.SplitN(line, ":", 2)
	if len(parts) != 2 {
		return "", "", "", false
	}

	left := strings.TrimSpace(parts[0])
	value := unescapeVCardValue(strings.TrimSpace(parts[1]))
	keyParts := strings.Split(left, ";")
	key := strings.ToUpper(strings.TrimSpace(keyParts[0]))
	if key == "" || value == "" {
		return "", "", "", false
	}

	return key, left, value, true
}

func unescapeVCardValue(value string) string {
	replacer := strings.NewReplacer(`\n`, "\n", `\N`, "\n", `\,`, ",", `\;`, ";", `\\`, `\`)
	return replacer.Replace(value)
}

func normalizeWhatsAppID(params string) string {
	for _, part := range strings.Split(params, ";") {
		lower := strings.ToLower(strings.TrimSpace(part))
		if !strings.HasPrefix(lower, "waid=") {
			continue
		}
		return digitsOnly(strings.TrimSpace(part[5:]))
	}
	return ""
}

func normalizeVCardPhone(value string) string {
	digits := digitsOnly(value)
	if len(digits) < 8 || len(digits) > 15 {
		return strings.TrimSpace(value)
	}
	return "+" + digits
}

func digitsOnly(value string) string {
	var digits strings.Builder
	for _, r := range value {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	return digits.String()
}

func enrichContactCard(client *whatsmeow.Client, card WhatsmeowContact) WhatsmeowContact {
	jid, ok := contactCardJID(card)
	if !ok || jid.IsEmpty() {
		return card
	}

	card.JID = firstNonBlank(card.JID, jidString(jid.ToNonAD()))
	card.PhoneNumber = firstNonBlank(card.PhoneNumber, phoneNumberFromJID(jid))
	card.ProfilePictureURL = firstNonBlank(card.ProfilePictureURL, card.AvatarURL, getProfilePictureURL(client, jid))
	if name, ok := getSavedContactDisplayName(client, jid); ok {
		card.DisplayName = firstNonBlank(card.DisplayName, name)
		card.FullName = firstNonBlank(card.FullName, name)
	}
	card.BusinessProfile = businessProfileMap(client, jid)
	if len(card.BusinessProfile) > 0 {
		card.Organization = firstNonBlank(card.Organization, stringMapValue(card.BusinessProfile, "business_name"))
		card.Category = firstNonBlank(card.Category, stringMapValue(card.BusinessProfile, "category"))
		card.Email = firstNonBlank(card.Email, stringMapValue(card.BusinessProfile, "email"))
		card.Website = firstNonBlank(card.Website, stringMapValue(card.BusinessProfile, "website"))
	}

	return card
}

func contactCardJID(card WhatsmeowContact) (types.JID, bool) {
	for _, candidate := range []string{card.JID, card.WhatsAppID, card.PhoneNumber} {
		candidate = strings.TrimSpace(candidate)
		if candidate == "" {
			continue
		}
		if strings.Contains(candidate, "@") {
			jid, ok := parseJID(candidate)
			if ok {
				return jid, true
			}
			continue
		}
		digits := digitsOnly(candidate)
		if len(digits) >= 8 && len(digits) <= 15 {
			return types.NewJID(digits, types.DefaultUserServer), true
		}
	}
	return types.JID{}, false
}

func businessProfileMap(client *whatsmeow.Client, jid types.JID) map[string]interface{} {
	if client == nil || jid.IsEmpty() || !isPhoneJID(jid) {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	profile, err := client.GetBusinessProfile(ctx, jid.ToNonAD())
	if err != nil || profile == nil {
		if err != nil {
			log.Printf("Failed to fetch business profile for contact %s: %v", jidString(jid), err)
		}
		return nil
	}

	categories := make([]map[string]string, 0, len(profile.Categories))
	categoryNames := make([]string, 0, len(profile.Categories))
	for _, category := range profile.Categories {
		name := strings.TrimSpace(category.Name)
		if name != "" {
			categoryNames = append(categoryNames, name)
		}
		categories = append(categories, map[string]string{
			"id":   category.ID,
			"name": category.Name,
		})
	}

	hours := make([]map[string]string, 0, len(profile.BusinessHours))
	for _, businessHour := range profile.BusinessHours {
		hours = append(hours, map[string]string{
			"day_of_week": businessHour.DayOfWeek,
			"mode":        businessHour.Mode,
			"open_time":   businessHour.OpenTime,
			"close_time":  businessHour.CloseTime,
		})
	}

	businessName := firstNonBlank(profile.ProfileOptions["business_name"], profile.ProfileOptions["name"])
	website := firstNonBlank(
		profile.ProfileOptions["website"],
		profile.ProfileOptions["website_url"],
		profile.ProfileOptions["profile_website"],
		profile.ProfileOptions["catalog_website"],
	)

	return map[string]interface{}{
		"jid":                         jidString(profile.JID),
		"business_name":               businessName,
		"address":                     profile.Address,
		"email":                       profile.Email,
		"category":                    strings.Join(categoryNames, ", "),
		"categories":                  categories,
		"profile_options":             profile.ProfileOptions,
		"website":                     website,
		"business_hours_timezone":     profile.BusinessHoursTimeZone,
		"business_hours":              hours,
		"business_hours_display_text": businessHoursDisplayText(hours),
	}
}

func businessHoursDisplayText(hours []map[string]string) string {
	if len(hours) == 0 {
		return ""
	}

	for _, hour := range hours {
		if strings.EqualFold(hour["mode"], "open_24h") || strings.EqualFold(hour["mode"], "open") {
			return "Aberta 24 horas"
		}
	}
	return ""
}

func stringMapValue(data map[string]interface{}, key string) string {
	if value, ok := data[key].(string); ok {
		return strings.TrimSpace(value)
	}
	return ""
}

func contactMessageText(contacts []WhatsmeowContact) string {
	if len(contacts) == 0 {
		return ""
	}
	if len(contacts) == 1 {
		return "Contato: " + firstNonBlank(contacts[0].DisplayName, contacts[0].FullName, contacts[0].PhoneNumber)
	}
	return fmt.Sprintf("%d contatos compartilhados", len(contacts))
}

func normalizeOutgoingContact(contact WhatsmeowContact) WhatsmeowContact {
	if strings.TrimSpace(contact.Vcard) != "" {
		parsed := parseVCardContact(contact.Vcard)
		contact.DisplayName = firstNonBlank(contact.DisplayName, parsed.DisplayName)
		contact.FullName = firstNonBlank(contact.FullName, parsed.FullName)
		contact.FirstName = firstNonBlank(contact.FirstName, parsed.FirstName)
		contact.LastName = firstNonBlank(contact.LastName, parsed.LastName)
		contact.PhoneNumber = firstNonBlank(contact.PhoneNumber, parsed.PhoneNumber)
		contact.WhatsAppID = firstNonBlank(contact.WhatsAppID, parsed.WhatsAppID)
		contact.Organization = firstNonBlank(contact.Organization, parsed.Organization)
		contact.Title = firstNonBlank(contact.Title, parsed.Title)
		contact.Email = firstNonBlank(contact.Email, parsed.Email)
		contact.Website = firstNonBlank(contact.Website, parsed.Website)
		contact.Note = firstNonBlank(contact.Note, parsed.Note)
	}

	contact.PhoneNumber = normalizeVCardPhone(firstNonBlank(contact.PhoneNumber, contact.WhatsAppID, contact.JID))
	contact.DisplayName = firstNonBlank(contact.DisplayName, contact.FullName, strings.TrimSpace(strings.Join([]string{contact.FirstName, contact.LastName}, " ")), contact.Organization, contact.PhoneNumber)
	if strings.TrimSpace(contact.Vcard) == "" {
		contact.Vcard = buildVCard(contact)
	}
	return contact
}

func buildVCard(contact WhatsmeowContact) string {
	displayName := firstNonBlank(contact.DisplayName, contact.FullName, strings.TrimSpace(strings.Join([]string{contact.FirstName, contact.LastName}, " ")), contact.PhoneNumber)
	phone := normalizeVCardPhone(contact.PhoneNumber)
	if displayName == "" || phone == "" {
		return ""
	}

	firstName := firstNonBlank(contact.FirstName, displayName)
	lastName := contact.LastName
	waID := digitsOnly(firstNonBlank(contact.WhatsAppID, phone))
	lines := []string{
		"BEGIN:VCARD",
		"VERSION:3.0",
		fmt.Sprintf("N:%s;%s;;;", escapeVCardValue(lastName), escapeVCardValue(firstName)),
		"FN:" + escapeVCardValue(displayName),
		fmt.Sprintf("TEL;type=CELL;type=VOICE;waid=%s:%s", waID, escapeVCardValue(phone)),
	}
	if strings.TrimSpace(contact.Organization) != "" {
		lines = append(lines, "ORG:"+escapeVCardValue(contact.Organization))
	}
	if strings.TrimSpace(contact.Title) != "" {
		lines = append(lines, "TITLE:"+escapeVCardValue(contact.Title))
	}
	if strings.TrimSpace(contact.Email) != "" {
		lines = append(lines, "EMAIL;type=INTERNET:"+escapeVCardValue(contact.Email))
	}
	if strings.TrimSpace(contact.Website) != "" {
		lines = append(lines, "URL:"+escapeVCardValue(contact.Website))
	}
	if strings.TrimSpace(contact.Note) != "" {
		lines = append(lines, "NOTE:"+escapeVCardValue(contact.Note))
	}
	lines = append(lines, "END:VCARD")
	return strings.Join(lines, "\n")
}

func escapeVCardValue(value string) string {
	replacer := strings.NewReplacer(`\`, `\\`, "\n", `\n`, ";", `\;`, ",", `\,`)
	return replacer.Replace(strings.TrimSpace(value))
}

func extractMediaAttachments(client *whatsmeow.Client, message *proto.Message) []WhatsmeowAttachment {
	message = unwrapMessage(message)
	if message == nil {
		return nil
	}

	if image := message.GetImageMessage(); image != nil {
		return downloadAttachment(client, image, "image", image.GetMimetype(), defaultFileName("image", image.GetMimetype()), nil)
	}
	if video := message.GetVideoMessage(); video != nil {
		return downloadAttachment(
			client,
			video,
			"video",
			video.GetMimetype(),
			defaultFileName("video", video.GetMimetype()),
			videoAttachmentMeta(video),
		)
	}
	if audio := message.GetAudioMessage(); audio != nil {
		return downloadAttachment(
			client,
			audio,
			"audio",
			audio.GetMimetype(),
			defaultFileName("audio", audio.GetMimetype()),
			audioAttachmentMeta(audio),
		)
	}
	if document := message.GetDocumentMessage(); document != nil {
		fileName := document.GetFileName()
		if fileName == "" {
			fileName = document.GetTitle()
		}
		if fileName == "" {
			fileName = defaultFileName("file", document.GetMimetype())
		}
		return downloadAttachment(client, document, "file", document.GetMimetype(), fileName, nil)
	}
	if sticker := message.GetStickerMessage(); sticker != nil {
		log.Printf(
			"Incoming sticker metadata: mimetype=%q animated=%t lottie=%t direct_path=%t url=%t media_key=%t file_length=%d png_thumbnail=%d first_frame=%d",
			sticker.GetMimetype(),
			sticker.GetIsAnimated(),
			sticker.GetIsLottie(),
			sticker.GetDirectPath() != "",
			sticker.GetURL() != "",
			len(sticker.GetMediaKey()) > 0,
			sticker.GetFileLength(),
			len(sticker.GetPngThumbnail()),
			len(sticker.GetFirstFrameSidecar()),
		)
		attachments := downloadAttachment(
			client,
			stickerMessageForDownload(sticker),
			"image",
			normalizedMIME(sticker.GetMimetype(), "image/webp"),
			defaultFileName("sticker", "image/webp"),
			stickerAttachmentMeta(sticker),
		)
		if len(attachments) > 0 {
			return attachments
		}
		return stickerThumbnailAttachment(sticker)
	}

	return nil
}

func audioAttachmentMeta(audio *proto.AudioMessage) map[string]interface{} {
	if audio == nil {
		return nil
	}

	meta := map[string]interface{}{}
	if audio.GetPTT() {
		meta["recorded_audio"] = true
		meta["ptt"] = true
	}
	if audio.GetSeconds() > 0 {
		meta["duration_seconds"] = audio.GetSeconds()
	}
	if waveform := audio.GetWaveform(); len(waveform) > 0 {
		meta["waveform"] = base64.StdEncoding.EncodeToString(waveform)
	}
	if len(meta) == 0 {
		return nil
	}

	return meta
}

func videoAttachmentMeta(video *proto.VideoMessage) map[string]interface{} {
	if video == nil {
		return nil
	}

	meta := map[string]interface{}{}
	if video.GetSeconds() > 0 {
		meta["duration_seconds"] = video.GetSeconds()
	}
	if video.GetWidth() > 0 {
		meta["width"] = video.GetWidth()
	}
	if video.GetHeight() > 0 {
		meta["height"] = video.GetHeight()
	}
	if video.GetGifPlayback() {
		meta["gif_playback"] = true
	}
	if mimeType := normalizedMIME(video.GetMimetype(), ""); mimeType != "" {
		meta["source_mimetype"] = mimeType
	}
	if thumbnail := video.GetJPEGThumbnail(); len(thumbnail) > 0 {
		meta["thumbnail_base64"] = base64.StdEncoding.EncodeToString(thumbnail)
		meta["thumbnail_content_type"] = "image/jpeg"
	}

	return compactAttachmentMeta(meta)
}

func hasMediaMessage(message *proto.Message) bool {
	message = unwrapMessage(message)
	return message != nil && (message.GetImageMessage() != nil || message.GetVideoMessage() != nil ||
		message.GetAudioMessage() != nil || message.GetDocumentMessage() != nil || message.GetStickerMessage() != nil)
}

func detectedMediaType(message *proto.Message) string {
	message = unwrapMessage(message)
	if message == nil {
		return "unknown"
	}

	switch {
	case message.GetStickerMessage() != nil:
		return "sticker"
	case message.GetImageMessage() != nil:
		return "image"
	case message.GetVideoMessage() != nil:
		return "video"
	case message.GetAudioMessage() != nil:
		return "audio"
	case message.GetDocumentMessage() != nil:
		return "document"
	default:
		return "unknown"
	}
}

func unwrapMessage(message *proto.Message) *proto.Message {
	if message == nil {
		return nil
	}
	if inner := message.GetEphemeralMessage().GetMessage(); inner != nil {
		return unwrapMessage(inner)
	}
	if inner := message.GetViewOnceMessage().GetMessage(); inner != nil {
		return unwrapMessage(inner)
	}
	if inner := message.GetViewOnceMessageV2().GetMessage(); inner != nil {
		return unwrapMessage(inner)
	}
	if inner := message.GetViewOnceMessageV2Extension().GetMessage(); inner != nil {
		return unwrapMessage(inner)
	}
	if inner := message.GetDocumentWithCaptionMessage().GetMessage(); inner != nil {
		return unwrapMessage(inner)
	}
	if inner := message.GetLottieStickerMessage().GetMessage(); inner != nil {
		return unwrapMessage(inner)
	}
	return message
}

func downloadAttachment(client *whatsmeow.Client, media whatsmeow.DownloadableMessage, fileType string, contentType string, fileName string, meta map[string]interface{}) []WhatsmeowAttachment {
	timeout := 45 * time.Second
	if strings.EqualFold(fileType, "audio") || strings.EqualFold(fileType, "video") {
		timeout = 90 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	data, err := client.Download(ctx, media)
	if err != nil {
		if len(data) == 0 || !shouldUseDownloadedDataWithWarning(fileType, meta, err) {
			log.Printf("Failed to download incoming %s attachment: %v", fileType, err)
			return nil
		}
		log.Printf("Downloaded incoming %s attachment with non-fatal warning: %v", fileType, err)
	}
	if len(data) == 0 {
		log.Printf("Downloaded incoming %s attachment is empty", fileType)
		return nil
	}

	contentType = normalizedDownloadedMIME(fileType, contentType, data)
	if fileName == "" {
		fileName = defaultFileName(fileType, contentType)
	}
	if strings.EqualFold(fileType, "audio") {
		meta = enrichDownloadedAudioMeta(meta, data, contentType)
	}

	return []WhatsmeowAttachment{{
		FileName:    fileName,
		ContentType: contentType,
		FileType:    fileType,
		Meta:        meta,
		DataBase64:  base64.StdEncoding.EncodeToString(data),
	}}
}

func stickerMessageForDownload(sticker *proto.StickerMessage) *proto.StickerMessage {
	if sticker == nil || sticker.GetDirectPath() == "" || mediaURLHasPath(sticker.GetURL()) {
		return sticker
	}

	stickerCopy := *sticker
	stickerCopy.URL = nil
	return &stickerCopy
}

func mediaURLHasPath(rawURL string) bool {
	trimmedURL := strings.TrimSpace(rawURL)
	if trimmedURL == "" {
		return false
	}

	withoutScheme := strings.TrimPrefix(strings.TrimPrefix(trimmedURL, "https://"), "http://")
	slashIndex := strings.Index(withoutScheme, "/")
	return slashIndex >= 0 && slashIndex < len(withoutScheme)-1
}

func isNonFatalDownloadWarning(err error) bool {
	return errors.Is(err, whatsmeow.ErrFileLengthMismatch) || errors.Is(err, whatsmeow.ErrInvalidMediaSHA256)
}

func shouldUseDownloadedDataWithWarning(fileType string, meta map[string]interface{}, err error) bool {
	if !isNonFatalDownloadWarning(err) {
		return false
	}

	return strings.EqualFold(fileType, "image") && (metaBool(meta, "whatsmeow_sticker") || metaBool(meta, "whatsmeowSticker"))
}

func enrichDownloadedAudioMeta(meta map[string]interface{}, data []byte, contentType string) map[string]interface{} {
	enriched := cloneAttachmentMeta(meta)
	probeCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	seconds, err := probeAudioDuration(probeCtx, data, contentType)
	if err != nil {
		log.Printf("Failed to probe incoming audio duration: %v", err)
		return compactAttachmentMeta(enriched)
	}

	enriched["duration_seconds"] = seconds
	enriched["duration_source"] = "probe"
	return compactAttachmentMeta(enriched)
}

func cloneAttachmentMeta(meta map[string]interface{}) map[string]interface{} {
	cloned := map[string]interface{}{}
	for key, value := range meta {
		cloned[key] = value
	}
	return cloned
}

func compactAttachmentMeta(meta map[string]interface{}) map[string]interface{} {
	if len(meta) == 0 {
		return nil
	}
	return meta
}

func stickerThumbnailAttachment(sticker *proto.StickerMessage) []WhatsmeowAttachment {
	thumbnail := sticker.GetPngThumbnail()
	if len(thumbnail) == 0 {
		return nil
	}

	return []WhatsmeowAttachment{{
		FileName:    defaultFileName("sticker", "image/png"),
		ContentType: "image/png",
		FileType:    "image",
		Meta:        stickerAttachmentMeta(sticker),
		DataBase64:  base64.StdEncoding.EncodeToString(thumbnail),
	}}
}

func stickerAttachmentMeta(sticker *proto.StickerMessage) map[string]interface{} {
	meta := map[string]interface{}{
		"whatsmeow_sticker": true,
		"animated":          sticker.GetIsAnimated(),
		"lottie":            sticker.GetIsLottie(),
	}

	if width := sticker.GetWidth(); width > 0 {
		meta["width"] = width
	}
	if height := sticker.GetHeight(); height > 0 {
		meta["height"] = height
	}
	if label := strings.TrimSpace(sticker.GetAccessibilityLabel()); label != "" {
		meta["accessibility_label"] = label
	}
	if emojis := strings.TrimSpace(sticker.GetEmojis()); emojis != "" {
		meta["emojis"] = emojis
	}

	return meta
}

func fallbackMIME(fileType string) string {
	switch strings.ToLower(fileType) {
	case "sticker":
		return "image/webp"
	case "image":
		return "image/jpeg"
	case "audio":
		return "audio/ogg"
	case "video":
		return "video/mp4"
	default:
		return "application/octet-stream"
	}
}

func normalizedMIME(contentType string, fallback string) string {
	contentType = strings.ToLower(strings.TrimSpace(strings.Split(contentType, ";")[0]))
	if contentType == "" {
		return fallback
	}
	if contentType == "audio/opus" {
		return "audio/ogg"
	}
	return contentType
}

func normalizedDownloadedMIME(fileType string, contentType string, data []byte) string {
	normalized := normalizedMIME(contentType, "")
	if !strings.EqualFold(fileType, "video") {
		return normalizedMIME(contentType, fallbackMIME(fileType))
	}
	if strings.HasPrefix(normalized, "video/") {
		return normalized
	}

	if detected := normalizedMIME(http.DetectContentType(data), ""); strings.HasPrefix(detected, "video/") {
		return detected
	}
	return fallbackMIME(fileType)
}

func defaultFileName(fileType string, contentType string) string {
	extension := extensionForMIME(contentType)
	if extension == "" {
		switch strings.ToLower(fileType) {
		case "image":
			extension = ".jpg"
		case "sticker":
			extension = ".webp"
		case "audio":
			extension = ".ogg"
		case "video":
			extension = ".mp4"
		default:
			extension = ".bin"
		}
	}
	return fmt.Sprintf("whatsapp-%s-%d%s", strings.ToLower(fileType), time.Now().UnixNano(), extension)
}

func extensionForMIME(contentType string) string {
	contentType = normalizedMIME(contentType, "")
	if contentType == "audio/ogg" {
		return ".ogg"
	}
	extensions, err := mime.ExtensionsByType(contentType)
	if err != nil || len(extensions) == 0 {
		return ""
	}
	return extensions[0]
}

func stringPtr(value string) *string {
	return &value
}

func optionalStringPtr(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func uint64Ptr(value uint64) *uint64 {
	return &value
}

func optionalUint32Ptr(value uint32) *uint32 {
	if value == 0 {
		return nil
	}
	return &value
}

func uint32Ptr(value uint32) *uint32 {
	return &value
}

func int64Ptr(value int64) *int64 {
	return &value
}

func optionalBoolPtr(value bool) *bool {
	if !value {
		return nil
	}
	return &value
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

func firstLIDJID(candidates ...types.JID) types.JID {
	for _, jid := range candidates {
		if jid.Server == "lid" {
			return jid.ToNonAD()
		}
	}
	return types.JID{}
}

func resolveGroupParticipant(client *whatsmeow.Client, groupJID types.JID, pushName string, candidates ...types.JID) ResolvedGroupParticipant {
	fallbackJID := firstUsableJID(candidates...)
	fallbackLIDJID := firstLIDJID(candidates...)
	resolved := ResolvedGroupParticipant{
		JID:               fallbackJID,
		LIDJID:            fallbackLIDJID,
		Name:              firstFriendlyDisplayName(getContactDisplayName(client, fallbackJID, pushName), phoneNumberFromJID(fallbackJID), jidString(fallbackJID)),
		PhoneNumber:       phoneNumberFromJID(fallbackJID),
		ProfilePictureURL: getProfilePictureURL(client, fallbackJID),
	}

	if groupJID.IsEmpty() || client == nil {
		return resolved
	}

	info, err := client.GetGroupInfo(context.Background(), groupJID.ToNonAD())
	if err != nil {
		return resolved
	}

	for _, participant := range info.Participants {
		if !groupParticipantMatches(participant, candidates...) {
			continue
		}

		member := buildGroupMemberResponse(client, participant, false)
		memberJID := firstUsableJID(participant.PhoneNumber, participant.JID, participant.LID)
		phoneJID := firstUsableJID(participant.PhoneNumber, participant.JID)
		profileJID := memberJID
		if isPhoneJID(phoneJID) {
			profileJID = phoneJID
		}

		resolved.JID = memberJID
		resolved.LIDJID = firstLIDJID(participant.LID, participant.JID, fallbackLIDJID)
		resolved.Name = firstFriendlyDisplayName(member.Name, pushName, member.PhoneNumber, jidString(memberJID))
		resolved.PhoneNumber = member.PhoneNumber
		resolved.ProfilePictureURL = cachedProfilePictureURL(profileJID)
		if resolved.ProfilePictureURL == "" {
			resolved.ProfilePictureURL = getProfilePictureURL(client, profileJID)
		}
		return resolved
	}

	return resolved
}

func groupParticipantMatches(participant types.GroupParticipant, candidates ...types.JID) bool {
	participantJIDs := []types.JID{
		participant.PhoneNumber,
		participant.JID,
		participant.LID,
	}
	for _, candidate := range candidates {
		for _, participantJID := range participantJIDs {
			if sameBareJID(candidate, participantJID) {
				return true
			}
		}
	}
	return false
}

func sameBareJID(left types.JID, right types.JID) bool {
	return !left.IsEmpty() && !right.IsEmpty() && left.ToNonAD().String() == right.ToNonAD().String()
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

func currentClientJID(client *whatsmeow.Client) (types.JID, string) {
	if client == nil || client.Store == nil || client.Store.ID == nil {
		return types.JID{}, ""
	}
	jid := client.Store.ID.ToNonAD()
	return jid, phoneNumberFromJID(jid)
}

func isCurrentClientJID(client *whatsmeow.Client, candidate types.JID) bool {
	if client == nil || client.Store == nil || candidate.IsEmpty() {
		return false
	}
	if ownJID, _ := currentClientJID(client); sameBareJID(candidate, ownJID) {
		return true
	}
	return sameBareJID(candidate, client.Store.LID)
}

func waitForGroupParticipant(client *whatsmeow.Client, groupJID types.JID, participantJID types.JID) (GroupMemberResponse, bool) {
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Second)
		}
		info, err := client.GetGroupInfo(context.Background(), groupJID.ToNonAD())
		if err != nil {
			continue
		}
		for _, participant := range info.Participants {
			if groupParticipantMatches(participant, participantJID) {
				return buildGroupMemberResponse(client, participant, false), true
			}
		}
	}
	return GroupMemberResponse{}, false
}

func buildGroupMemberResponse(client *whatsmeow.Client, participant types.GroupParticipant, fetchProfilePicture bool) GroupMemberResponse {
	memberJID := firstUsableJID(participant.PhoneNumber, participant.JID, participant.LID)
	phoneJID := firstUsableJID(participant.PhoneNumber, participant.JID)
	lidJID := firstLIDJID(participant.LID, participant.JID)
	phone := phoneNumberFromJID(phoneJID)
	savedName, isSaved := getSavedContactDisplayName(client, memberJID)
	if !isSaved && !phoneJID.IsEmpty() {
		savedName, isSaved = getSavedContactDisplayName(client, phoneJID)
	}
	displayName := strings.TrimSpace(participant.DisplayName)
	name := firstNonBlank(savedName, displayName, phone, jidString(memberJID))
	profileJID := memberJID
	if isPhoneJID(phoneJID) {
		profileJID = phoneJID
	}
	profilePictureURL := cachedProfilePictureURL(profileJID)
	if profilePictureURL == "" && fetchProfilePicture {
		profilePictureURL = getProfilePictureURL(client, profileJID)
	}
	addRequestCode := ""
	addRequestExpires := ""
	if participant.AddRequest != nil {
		addRequestCode = participant.AddRequest.Code
		addRequestExpires = participant.AddRequest.Expiration.UTC().Format(time.RFC3339)
	}

	return GroupMemberResponse{
		JID:               jidString(memberJID),
		LIDJID:            jidString(lidJID),
		Name:              name,
		PhoneNumber:       phone,
		DisplayName:       displayName,
		ProfilePictureURL: profilePictureURL,
		IsAdmin:           participant.IsAdmin || participant.IsSuperAdmin,
		IsSuperAdmin:      participant.IsSuperAdmin,
		IsSavedContact:    isSaved,
		Error:             participant.Error,
		AddRequestCode:    addRequestCode,
		AddRequestExpires: addRequestExpires,
	}
}

func buildGroupResponse(client *whatsmeow.Client, group *types.GroupInfo, fetchProfilePicture bool) GroupResponse {
	groupJID := group.JID.ToNonAD()
	name := firstNonBlank(group.Name, groupJID.String())
	profilePictureURL := cachedProfilePictureURL(groupJID)
	if profilePictureURL == "" && fetchProfilePicture {
		profilePictureURL = getProfilePictureURL(client, groupJID)
	}

	participantCount := group.ParticipantCount
	if participantCount == 0 {
		participantCount = len(group.Participants)
	}

	return GroupResponse{
		JID:               groupJID.String(),
		Name:              name,
		ProfilePictureURL: profilePictureURL,
		ParticipantCount:  participantCount,
		IsAnnounce:        group.IsAnnounce,
		IsLocked:          group.IsLocked,
	}
}

func groupInviteResponse(client *whatsmeow.Client, group *types.GroupInfo, code string, joined bool, pendingApproval bool) GroupInviteResponse {
	if group == nil {
		return GroupInviteResponse{
			Code:            code,
			Link:            whatsmeow.InviteLinkPrefix + code,
			Joined:          joined,
			PendingApproval: pendingApproval,
		}
	}

	groupJID := group.JID.ToNonAD()
	name := firstNonBlank(group.Name, groupJID.String())
	profilePictureURL := cachedProfilePictureURL(groupJID)
	if profilePictureURL == "" {
		profilePictureURL = getGroupInviteProfilePictureURL(client, groupJID, code)
	}
	if profilePictureURL == "" && joined {
		profilePictureURL = getProfilePictureURL(client, groupJID)
	}

	participantCount := group.ParticipantCount
	if participantCount == 0 {
		participantCount = len(group.Participants)
	}

	return GroupInviteResponse{
		Code:                   code,
		Link:                   whatsmeow.InviteLinkPrefix + code,
		JID:                    groupJID.String(),
		GroupJID:               groupJID.String(),
		Name:                   name,
		ProfilePictureURL:      profilePictureURL,
		ParticipantCount:       participantCount,
		IsAnnounce:             group.IsAnnounce,
		IsLocked:               group.IsLocked,
		IsJoinApprovalRequired: group.IsJoinApprovalRequired,
		Joined:                 joined,
		PendingApproval:        pendingApproval,
	}
}

func sortGroups(groups []GroupResponse) {
	sort.SliceStable(groups, func(i, j int) bool {
		return strings.ToLower(groups[i].Name) < strings.ToLower(groups[j].Name)
	})
}

func sortGroupMembers(members []GroupMemberResponse) {
	sort.SliceStable(members, func(i, j int) bool {
		left := members[i]
		right := members[j]
		if left.IsSelf != right.IsSelf {
			return left.IsSelf
		}
		if left.IsSuperAdmin != right.IsSuperAdmin {
			return left.IsSuperAdmin
		}
		if left.IsAdmin != right.IsAdmin {
			return left.IsAdmin
		}
		if left.IsSavedContact != right.IsSavedContact {
			return left.IsSavedContact
		}
		return strings.ToLower(left.Name) < strings.ToLower(right.Name)
	})
}

func firstNonBlank(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func firstFriendlyDisplayName(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" && !isTechnicalJIDString(value) {
			return value
		}
	}
	return firstNonBlank(values...)
}

func isTechnicalJIDString(value string) bool {
	value = strings.ToLower(strings.TrimSpace(value))
	return strings.Contains(value, "@lid") ||
		strings.Contains(value, "@s.whatsapp.net") ||
		strings.Contains(value, "@g.us") ||
		strings.Contains(value, "@newsletter")
}

func getContactDisplayName(client *whatsmeow.Client, jid types.JID, fallback string) string {
	fallback = strings.TrimSpace(fallback)
	if name, ok := getSavedContactDisplayName(client, jid); ok {
		return name
	}
	return fallback
}

func getSavedContactDisplayName(client *whatsmeow.Client, jid types.JID) (string, bool) {
	if client == nil || client.Store == nil || client.Store.Contacts == nil || jid.IsEmpty() {
		return "", false
	}

	contact, err := client.Store.Contacts.GetContact(context.Background(), jid.ToNonAD())
	if err != nil || !contact.Found {
		return "", false
	}

	for _, name := range []string{contact.FullName, contact.FirstName, contact.BusinessName, contact.PushName} {
		if strings.TrimSpace(name) != "" {
			return strings.TrimSpace(name), true
		}
	}
	return "", false
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
	return getProfilePictureURLWithRefresh(client, jid, false)
}

func getProfilePictureURLWithRefresh(client *whatsmeow.Client, jid types.JID, forceRefresh bool) string {
	if jid.IsEmpty() {
		return ""
	}

	cacheKey := jidString(jid)
	if cachedURL, ok := getCachedProfilePicture(jid); ok && !forceRefresh {
		return cachedURL
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

func getGroupInviteProfilePictureURL(client *whatsmeow.Client, jid types.JID, code string) string {
	if jid.IsEmpty() || strings.TrimSpace(code) == "" {
		return ""
	}

	cacheKey := jidString(jid)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	info, err := client.GetProfilePictureInfo(ctx, jid.ToNonAD(), &whatsmeow.GetProfilePictureParams{InviteCode: code})
	if err != nil {
		log.Printf("Failed to fetch group invite profile picture for %s: %v", cacheKey, err)
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

func cachedProfilePictureURL(jid types.JID) string {
	cachedURL, _ := getCachedProfilePicture(jid)
	return cachedURL
}

func getCachedProfilePicture(jid types.JID) (string, bool) {
	if jid.IsEmpty() {
		return "", false
	}

	cacheKey := jidString(jid)
	profilePictureMu.RLock()
	cached, ok := profilePictureCache[cacheKey]
	profilePictureMu.RUnlock()
	if ok && cached.ExpiresAt.After(time.Now()) {
		return cached.Value, true
	}
	return "", false
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
		client := &http.Client{Timeout: 60 * time.Second}
		req, err := http.NewRequest(http.MethodPost, url, bytes.NewBuffer(body))
		if err != nil {
			log.Printf("Failed to create webhook callback request: %v", err)
			return
		}
		req.Header.Set("Content-Type", "application/json")
		if token := strings.TrimSpace(os.Getenv("WHATSMEOW_SHARED_SECRET")); token != "" {
			req.Header.Set("X-Whatsmeow-Internal-Token", token)
		}
		res, err := client.Do(req)
		if err != nil {
			log.Printf("Failed to send webhook callback: %v", err)
			return
		}
		defer res.Body.Close()
		log.Printf("Webhook callback response status: %s", res.Status)
	}()
}
