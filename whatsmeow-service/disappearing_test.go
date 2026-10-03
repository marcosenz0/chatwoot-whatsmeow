package main

import (
	"testing"

	"github.com/polymorfa/hypermeow/binary/proto"
	"github.com/polymorfa/hypermeow/types"
	"github.com/polymorfa/hypermeow/types/events"
	goproto "google.golang.org/protobuf/proto"
)

func TestUnavailableViewOncePreservesMessageIdentity(t *testing.T) {
	event := &events.UndecryptableMessage{Info: types.MessageInfo{ID: "view-once-id"}, UnavailableType: events.UnavailableTypeViewOnce}
	message := unavailableViewOnceEvent(event)
	if message == nil || message.Info.ID != event.Info.ID || !message.IsViewOnce || message.Message != nil {
		t.Fatal("view once notification must preserve its ID without inventing media")
	}
	payload := make(map[string]interface{})
	addDisappearingMessageMetadata(payload, message, false)
	if payload["view_once"] != true || payload["view_once_unavailable"] != true {
		t.Fatalf("missing notification markers: %v", payload)
	}
	event.UnavailableType = events.UnavailableTypeUnknown
	if unavailableViewOnceEvent(event) != nil {
		t.Fatal("ordinary decryption errors must not be labeled view once")
	}
}

func TestSuppliedViewOnceMediaAndTemporaryMessages(t *testing.T) {
	message := &events.Message{Message: &proto.Message{AudioMessage: &proto.AudioMessage{ViewOnce: goproto.Bool(true)}}}
	payload := make(map[string]interface{})
	addDisappearingMessageMetadata(payload, message, true)
	if payload["view_once"] != true || payload["view_once_unavailable"] != false {
		t.Fatalf("supplied audio must remain available: %v", payload)
	}
	message.Message = &proto.Message{ImageMessage: &proto.ImageMessage{ContextInfo: &proto.ContextInfo{Expiration: goproto.Uint32(86400)}}}
	payload = make(map[string]interface{})
	addDisappearingMessageMetadata(payload, message, true)
	if payload["ephemeral"] != true || payload["view_once"] != nil {
		t.Fatalf("timed messages must remain distinct from view once: %v", payload)
	}
}
