package main

import (
	"testing"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/store"
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

func TestStatusReceiptViewerJIDUsesBroadcastOwnerWhenSenderIsSelf(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("123456789", types.HiddenUserServer)
	viewerJID := types.NewJID("5511999999999", types.DefaultUserServer)
	client := &whatsmeow.Client{Store: &store.Device{ID: &ownJID, LID: ownLID}}
	receipt := &events.Receipt{
		MessageSource: types.MessageSource{
			Sender:             ownJID,
			SenderAlt:          ownLID,
			BroadcastListOwner: viewerJID,
		},
		MessageSender: viewerJID,
	}

	actual := statusReceiptViewerJID(client, receipt)

	if !sameBareJID(actual, viewerJID) {
		t.Fatalf("viewer JID = %s; want %s", actual, viewerJID)
	}
}

func TestFirstExternalStatusReceiptJIDRejectsSelfOnlyCandidates(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("123456789", types.HiddenUserServer)

	actual := firstExternalStatusReceiptJID(nil, ownJID, ownLID, ownJID, ownLID, types.StatusBroadcastJID)

	if !actual.IsEmpty() {
		t.Fatalf("viewer JID = %s; want empty", actual)
	}
}

func TestStatusSendRequestExtraUsesStableMessageID(t *testing.T) {
	extra := statusSendRequestExtra("stable-status-id", 60*time.Second)

	if extra.ID != types.MessageID("stable-status-id") {
		t.Fatalf("message ID = %q; want stable-status-id", extra.ID)
	}
	if extra.Timeout != 55*time.Second {
		t.Fatalf("timeout = %s; want 55s", extra.Timeout)
	}
}

func TestStatusMediaSupportsRecordedAudio(t *testing.T) {
	attachment := WhatsmeowAttachment{FileType: "audio", ContentType: "audio/mpeg"}

	if !statusMediaTypeSupported(attachment) {
		t.Fatal("expected Status audio media to be supported")
	}
	if prepared := prepareStatusAttachment(attachment); !prepared.RecordedAudio {
		t.Fatal("expected Status audio to use the recorded-audio/PTT path")
	}
}

func TestPrepareStatusAttachmentLeavesImagesUnchanged(t *testing.T) {
	attachment := WhatsmeowAttachment{FileType: "image", ContentType: "image/jpeg"}

	if prepared := prepareStatusAttachment(attachment); prepared.RecordedAudio {
		t.Fatal("did not expect Status image to use the recorded-audio path")
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
