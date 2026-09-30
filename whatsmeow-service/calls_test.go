package main

import (
	"encoding/binary"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coder/websocket"
	meowcaller "github.com/purpshell/meowcaller"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

func TestCallToken(t *testing.T) {
	t.Setenv("WHATSMEOW_SHARED_SECRET", "test-call-secret")
	claims := callClaims{
		InboxID:        "27",
		ContactJID:     "15551234567@s.whatsapp.net",
		ConversationID: 3058,
		AgentID:        1,
		RegisteredClaims: jwt.RegisteredClaims{
			Audience:  jwt.ClaimStrings{"whatsmeow-calls"},
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Minute)),
		},
	}

	for _, tc := range []struct {
		name      string
		secret    string
		inbox     string
		target    string
		expired   bool
		wantError bool
	}{
		{name: "authorized direct call", secret: "test-call-secret", inbox: "27", target: claims.ContactJID},
		{name: "wrong signature", secret: "wrong-secret", inbox: "27", target: claims.ContactJID, wantError: true},
		{name: "different inbox", secret: "test-call-secret", inbox: "28", target: claims.ContactJID, wantError: true},
		{name: "group destination", secret: "test-call-secret", inbox: "27", target: "12345@g.us", wantError: true},
		{name: "expired token", secret: "test-call-secret", inbox: "27", target: claims.ContactJID, expired: true, wantError: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			issuedClaims := claims
			issuedClaims.ContactJID = tc.target
			if tc.expired {
				issuedClaims.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Minute))
			}
			encoded, err := jwt.NewWithClaims(jwt.SigningMethodHS256, issuedClaims).SignedString([]byte(tc.secret))
			if err != nil {
				t.Fatal(err)
			}
			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Params = gin.Params{{Key: "channel_id", Value: tc.inbox}}
			c.Request = httptest.NewRequest("GET", "/calls/"+tc.inbox, nil)
			c.Request.Header.Set("Sec-WebSocket-Protocol", "chatwoot.calls, token."+encoded)
			_, err = callToken(c)
			if (err != nil) != tc.wantError {
				t.Fatalf("callToken error = %v, wantError = %v", err, tc.wantError)
			}
		})
	}
}

func TestBrowserVideoSinkKeepsOrientationAndRecoversAfterQueueLoss(t *testing.T) {
	socket := &callSocket{out: make(chan callPacket, 1), done: make(chan struct{})}
	sink := &browserVideoSink{socket: socket, call: &meowcaller.Call{}}
	idr := []byte{0, 0, 0, 1, 0x65, 0x01}
	delta := []byte{0, 0, 1, 0x41, 0x01}
	for _, orientation := range []int{0, 1, 2, 3} {
		sink.SetOrientation(orientation)
		_ = sink.WriteVideo(idr)
		packet := <-socket.out
		if packet.typ != websocket.MessageBinary || packet.data[0] != callOrientedVideoDown || packet.data[1] != byte(orientation) {
			t.Fatalf("wrong frame metadata: %v", packet)
		}
	}
	_ = sink.WriteVideo(idr)
	_ = sink.WriteVideo(delta) // Full queue loses a reference frame.
	<-socket.out
	_ = sink.WriteVideo(delta)
	if len(socket.out) != 0 || !sink.needsKeyframe {
		t.Fatal("dependent frames must wait for a new IDR after loss")
	}
	_ = sink.WriteVideo(idr)
	if len(socket.out) != 1 || sink.needsKeyframe {
		t.Fatal("a new IDR must resume delivery")
	}
}

func TestBrowserAudioSourceUsesSixteenKilohertzFrames(t *testing.T) {
	source := newBrowserAudioSource()
	pcm := make([]byte, 1920)
	binary.LittleEndian.PutUint16(pcm[:2], uint16(int16(16384)))
	source.push(pcm)
	frame, err := source.ReadFrame()
	if err != nil {
		t.Fatal(err)
	}
	if len(frame) != 960 || frame[0] != 0.5 {
		t.Fatalf("got %d samples, first = %f", len(frame), frame[0])
	}
	_ = source.Close()
}
