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

func TestMatchingStatusReceiptMessageIDsFindsOwnStatusOutsideBroadcastChat(t *testing.T) {
	messageIDs := []types.MessageID{"regular-message", "status-own-id", ""}
	knownStatusIDs := map[types.MessageID]struct{}{"status-own-id": {}}

	matched := matchingStatusReceiptMessageIDs(messageIDs, knownStatusIDs)

	if len(matched) != 1 || matched[0] != "status-own-id" {
		t.Fatalf("matched IDs = %v; want [status-own-id]", matched)
	}
}

func TestStatusReceiptCanUseRailsFallbackForBroadcast(t *testing.T) {
	receipt := &events.Receipt{MessageSource: types.MessageSource{Chat: types.StatusBroadcastJID}}

	if !statusReceiptCanUseRailsFallback(receipt, types.JID{}, types.JID{}) {
		t.Fatal("expected status broadcast receipt to use Rails fallback")
	}
}

func TestStatusReceiptCanUseRailsFallbackForOwnMessageSender(t *testing.T) {
	own := types.NewJID("5563999999999", types.DefaultUserServer)
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{Chat: types.NewJID("5511999999999", types.DefaultUserServer)},
		MessageSender: own,
	}

	if !statusReceiptCanUseRailsFallback(receipt, own, types.JID{}) {
		t.Fatal("expected receipt owned by current account to use Rails fallback")
	}
}

func TestStatusReceiptRejectsUnrelatedDirectReceiptFallback(t *testing.T) {
	own := types.NewJID("5563999999999", types.DefaultUserServer)
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{Chat: types.NewJID("5511999999999", types.DefaultUserServer)},
		MessageSender: types.NewJID("5588999999999", types.DefaultUserServer),
	}

	if statusReceiptCanUseRailsFallback(receipt, own, types.JID{}) {
		t.Fatal("did not expect unrelated direct receipt to use Rails fallback")
	}
}

func TestStatusUserReceiptViewPrefersPlayedAndNormalizesMilliseconds(t *testing.T) {
	receiptType, timestamp := statusUserReceiptView(1_700_000_000, 1_700_000_123_000)

	if receiptType != types.ReceiptTypePlayed {
		t.Fatalf("receipt type = %q; want played", receiptType)
	}
	if timestamp != 1_700_000_123 {
		t.Fatalf("timestamp = %d; want 1700000123", timestamp)
	}
}

func TestStatusUserReceiptViewUsesReadTimestamp(t *testing.T) {
	receiptType, timestamp := statusUserReceiptView(1_700_000_000, 0)

	if receiptType != types.ReceiptTypeRead || timestamp != 1_700_000_000 {
		t.Fatalf("receipt = %q/%d; want read/1700000000", receiptType, timestamp)
	}
}

func TestShouldRetryWebhookStatus(t *testing.T) {
	for _, statusCode := range []int{408, 429, 500, 503} {
		if !shouldRetryWebhookStatus(statusCode) {
			t.Fatalf("expected HTTP %d to be retried", statusCode)
		}
	}
	for _, statusCode := range []int{200, 201, 400, 401, 404} {
		if shouldRetryWebhookStatus(statusCode) {
			t.Fatalf("did not expect HTTP %d to be retried", statusCode)
		}
	}
}
