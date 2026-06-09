package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
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
	_ "github.com/lib/pq"
	"github.com/skip2/go-qrcode"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/binary/proto"
	waWeb "go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

const (
	sendMessageTimeout         = 60 * time.Second
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
	FileName      string `json:"file_name"`
	ContentType   string `json:"content_type"`
	FileType      string `json:"file_type"`
	RecordedAudio bool   `json:"recorded_audio"`
	DataBase64    string `json:"data_base64"`
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
}

type GroupResponse struct {
	JID               string `json:"jid"`
	Name              string `json:"name"`
	ProfilePictureURL string `json:"profile_picture_url"`
	ParticipantCount  int    `json:"participant_count"`
	IsAnnounce        bool   `json:"is_announce"`
	IsLocked          bool   `json:"is_locked"`
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
	r.GET("/sessions/:channel_id/group_members", handleGetGroupMembers)
	r.GET("/sessions/:channel_id/profile_picture", handleGetProfilePicture)
	r.GET("/sessions/:channel_id/check_number", handleCheckNumber)
	r.DELETE("/sessions/:channel_id", handleDisconnectSession)
	r.POST("/messages", handleSendMessage)
	r.POST("/messages/reaction", handleSendReaction)
	r.POST("/messages/delete", handleDeleteMessage)

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
	for _, participant := range info.Participants {
		members = append(members, buildGroupMemberResponse(client, participant, fetchProfilePictures))
	}
	sortGroupMembers(members)

	c.JSON(http.StatusOK, gin.H{
		"group_jid":  groupJID.ToNonAD().String(),
		"group_name": info.Name,
		"members":    members,
		"count":      len(members),
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

	if processDeleteForInbox(channelID, accountID, messageEvent) {
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

func processEditForInbox(channelID string, accountID string, messageEvent *events.Message) bool {
	protocolMessage := rawEditedProtocolMessage(messageEvent.RawMessage)
	if !messageEvent.IsEdit && protocolMessage == nil {
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
	sendWebhookNotification(accountID, channelID, payload)
	return true
}

func editedMessageID(messageEvent *events.Message, protocolMessage *proto.ProtocolMessage) string {
	if messageEvent.Info.ID != "" {
		return messageEvent.Info.ID
	}

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
	payload := map[string]interface{}{
		"event":        "delete",
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
		return downloadAttachment(client, image, "image", image.GetMimetype(), defaultFileName("image", image.GetMimetype()))
	}
	if video := message.GetVideoMessage(); video != nil {
		return downloadAttachment(client, video, "video", video.GetMimetype(), defaultFileName("video", video.GetMimetype()))
	}
	if audio := message.GetAudioMessage(); audio != nil {
		return downloadAttachment(client, audio, "audio", audio.GetMimetype(), defaultFileName("audio", audio.GetMimetype()))
	}
	if document := message.GetDocumentMessage(); document != nil {
		fileName := document.GetFileName()
		if fileName == "" {
			fileName = document.GetTitle()
		}
		if fileName == "" {
			fileName = defaultFileName("file", document.GetMimetype())
		}
		return downloadAttachment(client, document, "file", document.GetMimetype(), fileName)
	}
	if sticker := message.GetStickerMessage(); sticker != nil {
		attachments := downloadAttachment(client, sticker, "image", normalizedMIME(sticker.GetMimetype(), "image/webp"), defaultFileName("sticker", "image/webp"))
		if len(attachments) > 0 {
			return attachments
		}
		return stickerThumbnailAttachment(sticker)
	}

	return nil
}

func hasMediaMessage(message *proto.Message) bool {
	message = unwrapMessage(message)
	return message != nil && (message.GetImageMessage() != nil || message.GetVideoMessage() != nil ||
		message.GetAudioMessage() != nil || message.GetDocumentMessage() != nil || message.GetStickerMessage() != nil)
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
	return message
}

func downloadAttachment(client *whatsmeow.Client, media whatsmeow.DownloadableMessage, fileType string, contentType string, fileName string) []WhatsmeowAttachment {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	data, err := client.Download(ctx, media)
	if err != nil {
		log.Printf("Failed to download incoming %s attachment: %v", fileType, err)
		return nil
	}

	contentType = normalizedMIME(contentType, fallbackMIME(fileType))
	if fileName == "" {
		fileName = defaultFileName(fileType, contentType)
	}

	return []WhatsmeowAttachment{{
		FileName:    fileName,
		ContentType: contentType,
		FileType:    fileType,
		DataBase64:  base64.StdEncoding.EncodeToString(data),
	}}
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
		DataBase64:  base64.StdEncoding.EncodeToString(thumbnail),
	}}
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

func sortGroups(groups []GroupResponse) {
	sort.SliceStable(groups, func(i, j int) bool {
		return strings.ToLower(groups[i].Name) < strings.ToLower(groups[j].Name)
	})
}

func sortGroupMembers(members []GroupMemberResponse) {
	sort.SliceStable(members, func(i, j int) bool {
		left := members[i]
		right := members[j]
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
		res, err := client.Post(url, "application/json", bytes.NewBuffer(body))
		if err != nil {
			log.Printf("Failed to send webhook callback: %v", err)
			return
		}
		defer res.Body.Close()
		log.Printf("Webhook callback response status: %s", res.Status)
	}()
}
