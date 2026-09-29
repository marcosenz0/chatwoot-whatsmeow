package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/types"
	meowcaller "github.com/purpshell/meowcaller"
)

const (
	callAudioUp   = byte(1)
	callVideoUp   = byte(2)
	callAudioDown = byte(3)
	callVideoDown = byte(4)
)

type callClaims struct {
	InboxID        string `json:"inbox_id"`
	ContactJID     string `json:"contact_jid"`
	ConversationID int64  `json:"conversation_id"`
	AgentID        int64  `json:"agent_id"`
	jwt.RegisteredClaims
}

type callCommand struct {
	Action string `json:"action"`
}

type callEvent struct {
	Event      string `json:"event"`
	CallID     string `json:"call_id,omitempty"`
	Video      bool   `json:"video,omitempty"`
	VideoState int    `json:"video_state"`
	Phase      int    `json:"phase,omitempty"`
	Message    string `json:"message,omitempty"`
}

type callPacket struct {
	typ  websocket.MessageType
	data []byte
}

type callSocket struct {
	conn   *websocket.Conn
	claims *callClaims
	out    chan callPacket
	done   chan struct{}
	once   sync.Once
}

func (s *callSocket) send(typ websocket.MessageType, data []byte) {
	select {
	case <-s.done:
		return
	case s.out <- callPacket{typ: typ, data: data}:
	default:
		// Media must not stall WhatsApp's receive loop when an agent's browser is slow.
	}
}

func (s *callSocket) event(event callEvent) {
	data, err := json.Marshal(event)
	if err == nil {
		s.send(websocket.MessageText, data)
	}
}

func (s *callSocket) media(kind byte, data []byte) {
	packet := make([]byte, len(data)+1)
	packet[0] = kind
	copy(packet[1:], data)
	s.send(websocket.MessageBinary, packet)
}

func (s *callSocket) write(ctx context.Context) {
	for {
		select {
		case <-s.done:
			return
		case packet := <-s.out:
			writeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			err := s.conn.Write(writeCtx, packet.typ, packet.data)
			cancel()
			if err != nil {
				s.once.Do(func() { close(s.done) })
				return
			}
		}
	}
}

type browserAudioSource struct {
	frames chan []float32
	done   chan struct{}
	once   sync.Once
	first  sync.Once
}

func newBrowserAudioSource() *browserAudioSource {
	return &browserAudioSource{frames: make(chan []float32, 8), done: make(chan struct{})}
}

func (a *browserAudioSource) ReadFrame() ([]float32, error) {
	select {
	case frame := <-a.frames:
		return frame, nil
	case <-a.done:
		return nil, io.EOF
	}
}

func (a *browserAudioSource) Close() error {
	a.once.Do(func() { close(a.done) })
	return nil
}

func (a *browserAudioSource) push(data []byte) {
	if len(data) != meowcaller.FrameSamples*2 {
		return
	}
	a.first.Do(func() { log.Print("Whatsmeow browser call: first microphone audio frame") })
	frame := make([]float32, meowcaller.FrameSamples)
	for i := range frame {
		frame[i] = float32(int16(binary.LittleEndian.Uint16(data[i*2:]))) / 32768
	}
	select {
	case <-a.done:
	case a.frames <- frame:
	default:
	}
}

type browserCallManager struct {
	mu       sync.Mutex
	wa       *whatsmeow.Client
	caller   *meowcaller.Client
	sockets  map[*callSocket]struct{}
	active   *meowcaller.Call
	pending  *meowcaller.Call
	owner    *callSocket
	audio    *browserAudioSource
	starting bool
}

var (
	browserCallsMu sync.RWMutex
	browserCalls   = make(map[*whatsmeow.Client]*browserCallManager)
)

func registerBrowserCalls(client *whatsmeow.Client) {
	if os.Getenv("WHATSMEOW_CALLS_ENABLED") != "true" {
		return
	}
	manager := &browserCallManager{wa: client, sockets: make(map[*callSocket]struct{})}
	manager.caller = meowcaller.NewClient(client)
	manager.caller.OnIncomingCall(manager.onIncoming)
	browserCallsMu.Lock()
	browserCalls[client] = manager
	browserCallsMu.Unlock()
}

func stopBrowserCalls(client *whatsmeow.Client) {
	browserCallsMu.Lock()
	manager := browserCalls[client]
	delete(browserCalls, client)
	browserCallsMu.Unlock()
	if manager == nil {
		return
	}
	manager.mu.Lock()
	call, audio := manager.active, manager.audio
	manager.active, manager.pending, manager.owner, manager.audio = nil, nil, nil, nil
	manager.mu.Unlock()
	if audio != nil {
		_ = audio.Close()
	}
	if call != nil {
		_ = call.Hangup()
	}
}

func callManagerFor(client *whatsmeow.Client) *browserCallManager {
	browserCallsMu.RLock()
	defer browserCallsMu.RUnlock()
	return browserCalls[client]
}

func callPeerMatches(client *whatsmeow.Client, peer types.JID, contactJID string) bool {
	target, ok := parseJID(contactJID)
	if !ok || target.IsEmpty() {
		return false
	}
	if sameBareJID(peer, target) {
		return true
	}
	resolvedPeer := resolvePhoneJID(client, peer)
	resolvedTarget := resolvePhoneJID(client, target)
	return !resolvedPeer.IsEmpty() && !resolvedTarget.IsEmpty() && sameBareJID(resolvedPeer, resolvedTarget)
}

func (m *browserCallManager) onIncoming(call *meowcaller.Call) {
	m.mu.Lock()
	if m.active != nil || m.pending != nil || m.starting {
		m.mu.Unlock()
		_ = call.Reject()
		return
	}
	m.pending = call
	sockets := make([]*callSocket, 0, len(m.sockets))
	for socket := range m.sockets {
		if callPeerMatches(m.wa, call.Peer(), socket.claims.ContactJID) {
			sockets = append(sockets, socket)
		}
	}
	m.mu.Unlock()
	call.OnEnd(func(reason string) {
		m.mu.Lock()
		pending := m.pending == call
		matching := make([]*callSocket, 0, len(m.sockets))
		if pending {
			for socket := range m.sockets {
				if callPeerMatches(m.wa, call.Peer(), socket.claims.ContactJID) {
					matching = append(matching, socket)
				}
			}
		}
		m.mu.Unlock()
		for _, socket := range matching {
			socket.event(callEvent{Event: "ended", CallID: call.ID(), Message: reason})
		}
		m.finish(call)
	})
	for _, socket := range sockets {
		socket.event(callEvent{Event: "incoming", CallID: call.ID(), Video: call.IsVideo()})
	}
}

func (m *browserCallManager) attach(socket *callSocket, call *meowcaller.Call) {
	audio := newBrowserAudioSource()
	var firstReceived sync.Once
	m.mu.Lock()
	m.audio = audio
	m.mu.Unlock()

	call.Play(audio)
	call.Receive(meowcaller.SinkFunc(func(frame []float32) {
		firstReceived.Do(func() { log.Print("Whatsmeow browser call: first decoded remote audio frame") })
		data := make([]byte, len(frame)*2)
		for i, sample := range frame {
			value := int(sample * 32768)
			if value > 32767 {
				value = 32767
			} else if value < -32768 {
				value = -32768
			}
			binary.LittleEndian.PutUint16(data[i*2:], uint16(int16(value)))
		}
		socket.media(callAudioDown, data)
	}))
	call.ReceiveVideo(meowcaller.VideoSinkFunc(func(frame []byte) {
		socket.media(callVideoDown, frame)
	}))
	call.OnVideoKeyframeRequest(func() { socket.event(callEvent{Event: "keyframe"}) })
	call.OnVideoState(func(state meowcaller.VideoState) {
		socket.event(callEvent{Event: "video_state", CallID: call.ID(), Video: call.IsVideo(), VideoState: state.Raw})
	})
	call.OnStateChange(func(phase meowcaller.CallPhase) {
		socket.event(callEvent{Event: "phase", CallID: call.ID(), Phase: int(phase), Video: call.IsVideo()})
	})
	call.OnReady(func() {
		socket.event(callEvent{Event: "connected", CallID: call.ID(), Video: call.IsVideo()})
	})
	call.OnEnd(func(reason string) {
		socket.event(callEvent{Event: "ended", CallID: call.ID(), Message: reason})
		m.finish(call)
	})
}

func (m *browserCallManager) finish(call *meowcaller.Call) {
	m.mu.Lock()
	if m.pending == call {
		m.pending = nil
	}
	if m.active != call {
		m.mu.Unlock()
		return
	}
	audio := m.audio
	m.active, m.owner, m.audio = nil, nil, nil
	m.mu.Unlock()
	if audio != nil {
		_ = audio.Close()
	}
}

func (m *browserCallManager) dial(ctx context.Context, socket *callSocket, video bool) error {
	m.mu.Lock()
	if m.active != nil || m.pending != nil || m.starting {
		m.mu.Unlock()
		return errors.New("another call is already active")
	}
	m.starting = true
	m.mu.Unlock()

	call, err := m.caller.CallWithOptions(ctx, socket.claims.ContactJID, meowcaller.CallOptions{Video: video})
	m.mu.Lock()
	m.starting = false
	if err == nil {
		m.active, m.owner = call, socket
	}
	m.mu.Unlock()
	if err != nil {
		return err
	}
	m.attach(socket, call)
	socket.event(callEvent{Event: "dialing", CallID: call.ID(), Video: video})
	return nil
}

func (m *browserCallManager) answer(socket *callSocket) error {
	m.mu.Lock()
	call := m.pending
	if call == nil || m.active != nil || !callPeerMatches(m.wa, call.Peer(), socket.claims.ContactJID) {
		m.mu.Unlock()
		return errors.New("there is no incoming call for this contact")
	}
	m.pending, m.active, m.owner = nil, call, socket
	m.mu.Unlock()
	m.attach(socket, call)
	if err := call.Answer(); err != nil {
		_ = call.Reject()
		m.finish(call)
		return err
	}
	socket.event(callEvent{Event: "connected", CallID: call.ID(), Video: call.IsVideo()})
	return nil
}

func (m *browserCallManager) command(ctx context.Context, socket *callSocket, action string) error {
	if action == "dial_audio" || action == "dial_video" {
		return m.dial(ctx, socket, action == "dial_video")
	}
	if action == "answer" {
		return m.answer(socket)
	}
	m.mu.Lock()
	call, pending, owner := m.active, m.pending, m.owner
	m.mu.Unlock()
	if action == "reject" {
		if pending == nil || !callPeerMatches(m.wa, pending.Peer(), socket.claims.ContactJID) {
			return errors.New("there is no incoming call for this contact")
		}
		return pending.Reject()
	}
	if call == nil || owner != socket {
		return errors.New("this browser does not own the active call")
	}
	switch action {
	case "hangup":
		return call.Hangup()
	case "start_video":
		return call.StartVideo()
	case "accept_video":
		return call.AcceptVideo()
	case "stop_video":
		return call.StopVideo()
	case "enable_video":
		return call.SetVideoEnabled(true)
	case "disable_video":
		return call.SetVideoEnabled(false)
	default:
		return errors.New("unknown call action")
	}
}

func (m *browserCallManager) detach(socket *callSocket) {
	m.mu.Lock()
	delete(m.sockets, socket)
	call := m.active
	owned := m.owner == socket
	m.mu.Unlock()
	if owned && call != nil {
		_ = call.Hangup()
		m.finish(call)
	}
}

func (m *browserCallManager) initial(socket *callSocket) {
	m.mu.Lock()
	m.sockets[socket] = struct{}{}
	pending, active, owner := m.pending, m.active, m.owner
	m.mu.Unlock()
	if pending != nil && callPeerMatches(m.wa, pending.Peer(), socket.claims.ContactJID) {
		socket.event(callEvent{Event: "incoming", CallID: pending.ID(), Video: pending.IsVideo()})
	} else if active != nil && owner == socket {
		socket.event(callEvent{Event: "active", CallID: active.ID(), Video: active.IsVideo()})
	} else if active != nil {
		socket.event(callEvent{Event: "busy"})
	} else {
		socket.event(callEvent{Event: "idle"})
	}
}

func callToken(c *gin.Context) (*callClaims, error) {
	var encoded string
	for _, protocol := range strings.Split(c.GetHeader("Sec-WebSocket-Protocol"), ",") {
		if strings.HasPrefix(strings.TrimSpace(protocol), "token.") {
			encoded = strings.TrimPrefix(strings.TrimSpace(protocol), "token.")
			break
		}
	}
	if encoded == "" {
		return nil, errors.New("call token is required")
	}
	secret := os.Getenv("WHATSMEOW_SHARED_SECRET")
	if secret == "" {
		return nil, errors.New("call authentication is not configured")
	}
	claims := &callClaims{}
	token, err := jwt.NewParser(
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithAudience("whatsmeow-calls"),
		jwt.WithExpirationRequired(),
	).ParseWithClaims(encoded, claims, func(*jwt.Token) (any, error) { return []byte(secret), nil })
	if err != nil || !token.Valid || claims.InboxID != c.Param("channel_id") ||
		claims.ConversationID <= 0 || claims.AgentID <= 0 {
		return nil, errors.New("invalid call token")
	}
	jid, ok := parseJID(claims.ContactJID)
	if !ok || jid.IsEmpty() || (jid.Server != types.DefaultUserServer && jid.Server != types.HiddenUserServer) {
		return nil, errors.New("invalid call destination")
	}
	return claims, nil
}

func handleBrowserCall(c *gin.Context) {
	if os.Getenv("WHATSMEOW_CALLS_ENABLED") != "true" {
		c.AbortWithStatus(http.StatusServiceUnavailable)
		return
	}
	origin := c.GetHeader("Origin")
	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme != "https" || origin != os.Getenv("WHATSMEOW_CALLS_ORIGIN") {
		c.AbortWithStatus(http.StatusForbidden)
		return
	}
	claims, err := callToken(c)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	client, ok := clientForChannel(claims.InboxID)
	if !ok {
		c.AbortWithStatus(http.StatusServiceUnavailable)
		return
	}
	manager := callManagerFor(client)
	if manager == nil {
		c.AbortWithStatus(http.StatusServiceUnavailable)
		return
	}
	conn, err := websocket.Accept(c.Writer, c.Request, &websocket.AcceptOptions{
		Subprotocols:       []string{"chatwoot.calls"},
		InsecureSkipVerify: true, // Origin was checked against the configured Chatwoot URL above.
	})
	if err != nil {
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "")
	conn.SetReadLimit(512 * 1024)
	ctx, cancel := context.WithCancel(c.Request.Context())
	defer cancel()
	socket := &callSocket{conn: conn, claims: claims, out: make(chan callPacket, 64), done: make(chan struct{})}
	go socket.write(ctx)
	manager.initial(socket)
	defer func() {
		socket.once.Do(func() { close(socket.done) })
		manager.detach(socket)
	}()
	for {
		messageType, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		if messageType == websocket.MessageText {
			var command callCommand
			if err := json.Unmarshal(data, &command); err != nil {
				socket.event(callEvent{Event: "error", Message: "invalid call command"})
				continue
			}
			commandCtx, commandCancel := context.WithTimeout(ctx, 30*time.Second)
			err = manager.command(commandCtx, socket, command.Action)
			commandCancel()
			if err != nil {
				socket.event(callEvent{Event: "error", Message: err.Error()})
			}
			continue
		}
		if messageType != websocket.MessageBinary || len(data) < 2 {
			continue
		}
		manager.mu.Lock()
		call, audio, owner := manager.active, manager.audio, manager.owner
		manager.mu.Unlock()
		if owner != socket || call == nil {
			continue
		}
		switch data[0] {
		case callAudioUp:
			if audio != nil {
				audio.push(data[1:])
			}
		case callVideoUp:
			if len(data) <= 256*1024 {
				_ = call.SendVideoWithDuration(data[1:], time.Second/15)
			}
		}
	}
}
