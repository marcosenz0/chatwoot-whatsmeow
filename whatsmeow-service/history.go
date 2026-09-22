package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"
)

// History is persisted before processing. One worker bounds media downloads and
// webhook traffic across all inboxes; failed imports survive process restarts.
func configureHistorySync() {
	store.DeviceProps.RequireFullSync = proto.Bool(true)
	store.DeviceProps.HistorySyncConfig.FullSyncDaysLimit = proto.Uint32(365)
	store.DeviceProps.HistorySyncConfig.RecentSyncDaysLimit = proto.Uint32(90)
	store.DeviceProps.HistorySyncConfig.FullSyncSizeMbLimit = proto.Uint32(1024)
}

type historySettings struct {
	Days         int
	Auto         bool
	Account      string
	State        map[string]interface{}
	IgnoreGroups bool
}

func readHistorySettings(inbox string) (historySettings, error) {
	var s historySettings
	var state []byte
	err := statusLookupDB.QueryRow(`SELECT c.history_sync_days, c.history_sync_auto, i.account_id::text, c.history_sync_state, c.ignore_groups
		FROM inboxes i JOIN channel_whatsmeow c ON c.id=i.channel_id
		WHERE i.id=$1 AND i.channel_type='Channel::Whatsmeow'`, inbox).Scan(&s.Days, &s.Auto, &s.Account, &state, &s.IgnoreGroups)
	if err == nil {
		err = json.Unmarshal(state, &s.State)
	}
	return s, err
}

func updateHistoryState(inbox string, values map[string]interface{}) {
	data, err := json.Marshal(values)
	if err != nil {
		return
	}
	_, err = statusLookupDB.Exec(`UPDATE channel_whatsmeow c SET history_sync_state=history_sync_state || $2::jsonb
		FROM inboxes i WHERE i.id=$1 AND i.channel_type='Channel::Whatsmeow' AND i.channel_id=c.id`, inbox, string(data))
	if err != nil {
		log.Printf("History state for inbox %s: %v", inbox, err)
	}
}

func historyCutoff(s historySettings) time.Time {
	if value, ok := s.State["from"].(float64); ok && s.State["manual"] == true {
		return time.Unix(int64(value), 0)
	}
	return time.Now().AddDate(0, 0, -s.Days)
}

func cacheHistoryMessage(inbox string, chat types.JID, web *waWeb.WebMessageInfo, info types.MessageInfo) error {
	data, err := proto.Marshal(web)
	if err != nil {
		return err
	}
	tx, err := statusLookupDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.Exec(`INSERT INTO whatsmeow_history_messages(inbox_id,chat_jid,message_id,message_at,payload)
		VALUES($1,$2,$3,$4,$5) ON CONFLICT(inbox_id,message_id) DO NOTHING`, inbox, chat.String(), info.ID, info.Timestamp, data)
	if err != nil {
		return err
	}
	_, err = tx.Exec(`INSERT INTO whatsmeow_history_chats(inbox_id,chat_jid,message_id,message_at,sender_jid,from_me)
		VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(inbox_id,chat_jid) DO UPDATE SET
		message_id=EXCLUDED.message_id,message_at=EXCLUDED.message_at,sender_jid=EXCLUDED.sender_jid,from_me=EXCLUDED.from_me
		WHERE EXCLUDED.message_at < whatsmeow_history_chats.message_at`, inbox, chat.String(), info.ID, info.Timestamp, info.Sender.String(), info.IsFromMe)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func handleHistorySync(c *gin.Context) {
	inbox := c.Param("channel_id")
	s, err := readHistorySettings(inbox)
	if err != nil {
		c.JSON(404, gin.H{"error": "Inbox not found"})
		return
	}
	var request struct {
		From  int64 `json:"from"`
		Pause bool  `json:"pause"`
	}
	if c.ShouldBindJSON(&request) != nil {
		c.JSON(400, gin.H{"error": "Invalid request"})
		return
	}
	if request.Pause {
		updateHistoryState(inbox, gin.H{"paused": true, "manual": false, "phase": "paused"})
		c.JSON(200, gin.H{"phase": "paused"})
		return
	}
	if request.From <= 0 || time.Unix(request.From, 0).After(time.Now()) || time.Unix(request.From, 0).Before(time.Now().AddDate(-10, 0, 0)) {
		c.JSON(400, gin.H{"error": "Choose a past date within the last ten years"})
		return
	}
	clientsMu.RLock()
	client := clients[inbox]
	clientsMu.RUnlock()
	if client == nil || !client.IsConnected() || !client.IsLoggedIn() {
		c.JSON(409, gin.H{"error": "Connect WhatsApp before synchronizing"})
		return
	}
	// Do not reset cursors of an already running request.
	if s.State["manual"] == true && s.State["paused"] != true {
		c.JSON(409, gin.H{"error": "A synchronization is already running"})
		return
	}
	if err = seedHistoryChats(inbox, true); err != nil {
		c.JSON(500, gin.H{"error": "Could not prepare history"})
		return
	}
	_, err = statusLookupDB.Exec(`UPDATE whatsmeow_history_chats SET requested_id=NULL,requested_at=NULL WHERE inbox_id=$1`, inbox)
	if err != nil {
		c.JSON(500, gin.H{"error": "Could not prepare synchronization"})
		return
	}
	_, err = statusLookupDB.Exec(`UPDATE whatsmeow_history_messages SET attempts=0,retry_at=NOW() WHERE inbox_id=$1 AND imported_at IS NULL`, inbox)
	if err != nil {
		c.JSON(500, gin.H{"error": "Could not resume imports"})
		return
	}
	updateHistoryState(inbox, gin.H{"paused": false, "manual": true, "from": request.From, "phase": "syncing", "started_at": time.Now().Unix(), "error": false})
	c.JSON(202, gin.H{"phase": "syncing"})
}

func startHistoryWorker() {
	go func() {
		ticker := time.NewTicker(3 * time.Second)
		defer ticker.Stop()
		lastCleanup := time.Time{}
		for range ticker.C {
			clientsMu.RLock()
			active := make(map[string]*whatsmeow.Client)
			for id, client := range clients {
				if client.IsConnected() && client.IsLoggedIn() {
					active[id] = client
				}
			}
			clientsMu.RUnlock()
			for id, client := range active {
				if err := runHistoryPass(id, client); err != nil {
					log.Printf("History worker inbox %s: %v", id, err)
					updateHistoryState(id, gin.H{"phase": "error", "error": true})
				}
			}
			if time.Since(lastCleanup) > 24*time.Hour {
				// Keep recoverable imports, but expire redundant raw copies after 7 days.
				_, err := statusLookupDB.Exec(`DELETE FROM whatsmeow_history_messages WHERE (imported_at IS NOT NULL AND received_at < NOW()-INTERVAL '7 days') OR (imported_at IS NULL AND received_at < NOW()-INTERVAL '30 days')`)
				if err == nil {
					lastCleanup = time.Now()
				}
			}
		}
	}()
}

func runHistoryPass(inbox string, client *whatsmeow.Client) error {
	s, err := readHistorySettings(inbox)
	if err != nil {
		return err
	}
	if s.State["paused"] == true || (!s.Auto && s.State["manual"] != true) {
		return nil
	}
	seeded, _ := s.State["seeded_at"].(float64)
	if time.Since(time.Unix(int64(seeded), 0)) > 24*time.Hour {
		if err := seedHistoryChats(inbox, false); err != nil {
			return err
		}
		updateHistoryState(inbox, gin.H{"seeded_at": time.Now().Unix()})
	}
	cutoff := historyCutoff(s)
	rows, err := statusLookupDB.Query(`SELECT id, chat_jid, payload FROM whatsmeow_history_messages
		WHERE inbox_id=$1 AND imported_at IS NULL AND message_at >= $2 AND attempts < 5 AND retry_at <= NOW()
		ORDER BY message_at,id LIMIT 10`, inbox, cutoff)
	if err != nil {
		return err
	}
	type entry struct {
		id   int64
		jid  string
		data []byte
	}
	batch := []entry{}
	for rows.Next() {
		var e entry
		if err = rows.Scan(&e.id, &e.jid, &e.data); err != nil {
			rows.Close()
			return err
		}
		batch = append(batch, e)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, e := range batch {
		// Re-read pause between messages, including during long media imports.
		current, err := readHistorySettings(inbox)
		if err != nil {
			return err
		}
		if current.State["paused"] == true {
			return nil
		}
		web := &waWeb.WebMessageInfo{}
		err = proto.Unmarshal(e.data, web)
		if err == nil {
			jid, parseErr := types.ParseJID(e.jid)
			err = parseErr
			if err == nil {
				var message *events.Message
				message, err = client.ParseWebMessage(jid, web)
				if err == nil && message != nil {
					err = processMessageForInbox(inbox, s.Account, client, message, true)
				}
			}
		}
		if err != nil {
			log.Printf("History import %d failed: %v", e.id, err)
			_, err = statusLookupDB.Exec(`UPDATE whatsmeow_history_messages SET attempts=attempts+1,retry_at=NOW()+INTERVAL '1 minute' WHERE id=$1`, e.id)
		} else {
			_, err = statusLookupDB.Exec(`UPDATE whatsmeow_history_messages SET imported_at=NOW() WHERE id=$1`, e.id)
		}
		if err != nil {
			return err
		}
	}
	// Ask the phone for older pages, one request per pass. No synthetic percentage:
	// WhatsApp does not expose a total number of messages available on the phone.
	if len(batch) < 10 {
		if err = requestOlderHistory(inbox, client, cutoff, s.IgnoreGroups); err != nil {
			return err
		}
	}
	var total, imported, pending, failed, waiting, unavailable int
	err = statusLookupDB.QueryRow(`SELECT COUNT(*),COUNT(imported_at),COUNT(*) FILTER(WHERE imported_at IS NULL),
		COUNT(*) FILTER(WHERE imported_at IS NULL AND attempts>=5)
		FROM whatsmeow_history_messages WHERE inbox_id=$1 AND message_at >= $2`, inbox, cutoff).Scan(&total, &imported, &pending, &failed)
	if err != nil {
		return err
	}
	err = statusLookupDB.QueryRow(`SELECT COUNT(*) FILTER(WHERE requested_id IS NULL OR requested_id<>message_id OR requested_at>NOW()-INTERVAL '2 minutes'),
		COUNT(*) FILTER(WHERE requested_id=message_id AND requested_at<=NOW()-INTERVAL '2 minutes')
		FROM whatsmeow_history_chats WHERE inbox_id=$1 AND message_at>$2
		AND (NOT $3 OR chat_jid NOT LIKE '%@g.us')`, inbox, cutoff, s.IgnoreGroups).Scan(&waiting, &unavailable)
	if err != nil {
		return err
	}
	phase := "idle"
	if pending > 0 {
		phase = "syncing"
	} else if waiting > 0 {
		phase = "waiting"
	} else if unavailable > 0 {
		phase = "partial"
	}
	if failed > 0 {
		phase = "error"
	}
	if received, ok := s.State["received_at"].(float64); ok && time.Since(time.Unix(int64(received), 0)) < 90*time.Second && pending == 0 {
		phase = "waiting"
	}
	values := gin.H{"phase": phase, "received": total, "imported": imported, "pending": pending, "failed": failed, "waiting": waiting, "unavailable": unavailable, "updated_at": time.Now().Unix()}
	if phase == "idle" || phase == "partial" || phase == "error" {
		values["manual"] = false
	}
	current, err := readHistorySettings(inbox)
	if err != nil {
		return err
	}
	if current.State["paused"] == true || current.State["started_at"] != s.State["started_at"] {
		return nil
	}
	updateHistoryState(inbox, values)
	return nil
}

func seedHistoryChats(inbox string, reset bool) error {
	// Seed existing conversations as well as chats discovered in new history chunks.
	// external_created_at is preferred; older installations only stored created_at.
	_, err := statusLookupDB.Exec(`INSERT INTO whatsmeow_history_chats(inbox_id,chat_jid,message_id,message_at,from_me)
		SELECT DISTINCT ON(ci.source_id) m.inbox_id,ci.source_id,m.source_id,
		COALESCE(to_timestamp(NULLIF(m.content_attributes->>'external_created_at','')::double precision),m.created_at),m.message_type=1
		FROM messages m JOIN conversations c ON c.id=m.conversation_id JOIN contact_inboxes ci ON ci.id=c.contact_inbox_id
		WHERE m.inbox_id=$1 AND m.source_id IS NOT NULL AND m.message_type IN(0,1)
		AND ci.source_id ~ '@(s.whatsapp.net|lid|g.us)$'
		ORDER BY ci.source_id,m.created_at DESC ON CONFLICT(inbox_id,chat_jid) DO UPDATE SET
		message_id=EXCLUDED.message_id,message_at=EXCLUDED.message_at,from_me=EXCLUDED.from_me
		WHERE $2`, inbox, reset)
	return err
}

func requestOlderHistory(inbox string, client *whatsmeow.Client, cutoff time.Time, ignoreGroups bool) error {
	rows, err := statusLookupDB.Query(`SELECT chat_jid,message_id,message_at,sender_jid,from_me
		FROM whatsmeow_history_chats WHERE inbox_id=$1 AND message_at>$2
		AND (requested_id IS NULL OR requested_id<>message_id)
		AND (NOT $3 OR chat_jid NOT LIKE '%@g.us')
		ORDER BY requested_at NULLS FIRST,message_at DESC LIMIT 1`, inbox, cutoff, ignoreGroups)
	if err != nil {
		return err
	}
	var chat, id, sender string
	var at time.Time
	var fromMe bool
	if !rows.Next() {
		err = rows.Err()
		rows.Close()
		return err
	}
	err = rows.Scan(&chat, &id, &at, &sender, &fromMe)
	rows.Close()
	if err != nil {
		return err
	}
	jid, err := types.ParseJID(chat)
	if err != nil {
		return err
	}
	_, err = statusLookupDB.Exec(`UPDATE whatsmeow_history_chats SET requested_id=message_id,requested_at=NOW() WHERE inbox_id=$1 AND chat_jid=$2`, inbox, chat)
	if err != nil {
		return err
	}
	senderJID, _ := types.ParseJID(sender)
	anchor := &types.MessageInfo{MessageSource: types.MessageSource{Chat: jid, Sender: senderJID, IsFromMe: fromMe, IsGroup: jid.Server == types.GroupServer}, ID: id, Timestamp: at}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_, err = client.SendPeerMessage(ctx, client.BuildHistorySyncRequest(anchor, 50))
	if err != nil {
		log.Printf("History request inbox %s failed: %v", inbox, err)
	}
	return err
}

func sendHistoryWebhook(account, inbox string, payload map[string]interface{}) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf(webhookURL, account, inbox), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Whatsmeow-Internal-Token", os.Getenv("WHATSMEOW_SHARED_SECRET"))
	response, err := (&http.Client{Timeout: 60 * time.Second}).Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("history webhook HTTP %s", strconv.Itoa(response.StatusCode))
	}
	return nil
}
