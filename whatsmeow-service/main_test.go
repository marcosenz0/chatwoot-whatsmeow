package main

import (
	"testing"

	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

func TestNormalizeGroupInviteCode(t *testing.T) {
	tests := map[string]string{
		"https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ?mode=gi_t": "FkLadnTzxGo9S25GLHuWiZ",
		"http://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ":            "FkLadnTzxGo9S25GLHuWiZ",
		"chat.whatsapp.com/invite/FkLadnTzxGo9S25GLHuWiZ":            "FkLadnTzxGo9S25GLHuWiZ",
		"FkLadnTzxGo9S25GLHuWiZ":                                     "FkLadnTzxGo9S25GLHuWiZ",
	}

	for value, expected := range tests {
		code, ok := normalizeGroupInviteCode(value)
		if !ok || code != expected {
			t.Fatalf("normalizeGroupInviteCode(%q) = %q, %v; want %q, true", value, code, ok, expected)
		}
	}
}

func TestNormalizeGroupInviteCodeRejectsInvalidValues(t *testing.T) {
	values := []string{
		"https://example.com/FkLadnTzxGo9S25GLHuWiZ",
		"chat.whatsapp.com/a",
		"not a link",
	}

	for _, value := range values {
		if code, ok := normalizeGroupInviteCode(value); ok || code != "" {
			t.Fatalf("normalizeGroupInviteCode(%q) = %q, %v; want empty, false", value, code, ok)
		}
	}
}

func TestClassifyStatusViewReceiptUsesKnownOwnStatusWhenOwnerFieldsAreMissing(t *testing.T) {
	viewer := types.NewJID("5511999999999", types.DefaultUserServer)
	own := types.NewJID("5563999999999", types.DefaultUserServer)
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{
			Chat:   types.StatusBroadcastJID,
			Sender: viewer,
		},
		MessageIDs: []types.MessageID{"status-own-id"},
		Type:       types.ReceiptTypeRead,
	}

	classification := classifyStatusViewReceipt(
		receipt,
		viewer,
		own,
		types.JID{},
		map[types.MessageID]struct{}{"status-own-id": {}},
	)

	if classification.ViewerJID != viewer {
		t.Fatalf("viewer JID = %s; want %s", classification.ViewerJID, viewer)
	}
	if len(classification.MessageIDs) != 1 || classification.MessageIDs[0] != "status-own-id" {
		t.Fatalf("message IDs = %v; want [status-own-id]", classification.MessageIDs)
	}
}

func TestClassifyStatusViewReceiptDoesNotCountOurOwnReadOfAnotherStatus(t *testing.T) {
	own := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("101010101010", types.HiddenUserServer)
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{
			Chat:   types.StatusBroadcastJID,
			Sender: ownLID,
		},
		MessageIDs:    []types.MessageID{"remote-status-id"},
		Type:          types.ReceiptTypeRead,
		MessageSender: types.NewJID("5511999999999", types.DefaultUserServer),
	}

	classification := classifyStatusViewReceipt(receipt, ownLID, own, ownLID, nil)

	if len(classification.MessageIDs) != 0 {
		t.Fatalf("message IDs = %v; want none", classification.MessageIDs)
	}
	if classification.Reason != "self_participant" {
		t.Fatalf("reason = %q; want self_participant", classification.Reason)
	}
}

func TestClassifyStatusViewReceiptAcceptsPlayedReceiptWithOwnOwnerFallback(t *testing.T) {
	viewer := types.NewJID("5511999999999", types.DefaultUserServer)
	ownLID := types.NewJID("101010101010", types.HiddenUserServer)
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{
			Chat:               types.StatusBroadcastJID,
			Sender:             viewer,
			BroadcastListOwner: ownLID,
		},
		MessageIDs: []types.MessageID{"status-own-id"},
		Type:       types.ReceiptTypePlayed,
	}

	classification := classifyStatusViewReceipt(receipt, viewer, types.JID{}, ownLID, nil)

	if len(classification.MessageIDs) != 1 || classification.MessageIDs[0] != "status-own-id" {
		t.Fatalf("message IDs = %v; want [status-own-id]", classification.MessageIDs)
	}
}

func TestClassifyStatusViewReceiptRejectsUnknownExternalStatus(t *testing.T) {
	viewer := types.NewJID("5511999999999", types.DefaultUserServer)
	own := types.NewJID("5563999999999", types.DefaultUserServer)
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{
			Chat:               types.StatusBroadcastJID,
			Sender:             viewer,
			BroadcastListOwner: types.NewJID("5588999999999", types.DefaultUserServer),
		},
		MessageIDs: []types.MessageID{"remote-status-id"},
		Type:       types.ReceiptTypePlayed,
	}

	classification := classifyStatusViewReceipt(receipt, viewer, own, types.JID{}, nil)

	if len(classification.MessageIDs) != 0 {
		t.Fatalf("message IDs = %v; want none", classification.MessageIDs)
	}
	if classification.Reason != "no_matching_own_status" {
		t.Fatalf("reason = %q; want no_matching_own_status", classification.Reason)
	}
}
