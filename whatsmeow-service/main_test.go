package main

import (
	"context"
	"strings"
	"testing"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/binary/proto"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

type fakeContactStore struct {
	contacts map[string]types.ContactInfo
}

func (f *fakeContactStore) PutPushName(context.Context, types.JID, string) (bool, string, error) {
	return false, "", nil
}

func (f *fakeContactStore) PutBusinessName(context.Context, types.JID, string) (bool, string, error) {
	return false, "", nil
}

func (f *fakeContactStore) PutContactName(context.Context, types.JID, string, string) error {
	return nil
}

func (f *fakeContactStore) PutAllContactNames(context.Context, []store.ContactEntry) error {
	return nil
}

func (f *fakeContactStore) PutManyRedactedPhones(context.Context, []store.RedactedPhoneEntry) error {
	return nil
}

func (f *fakeContactStore) GetContact(_ context.Context, jid types.JID) (types.ContactInfo, error) {
	return f.contacts[jid.ToNonAD().String()], nil
}

func (f *fakeContactStore) GetAllContacts(context.Context) (map[types.JID]types.ContactInfo, error) {
	return nil, nil
}

type fakeLIDStore struct {
	phoneJID types.JID
	lidJID   types.JID
}

func (f *fakeLIDStore) PutManyLIDMappings(context.Context, []store.LIDMapping) error {
	return nil
}

func (f *fakeLIDStore) PutLIDMapping(context.Context, types.JID, types.JID) error {
	return nil
}

func (f *fakeLIDStore) GetPNForLID(_ context.Context, lid types.JID) (types.JID, error) {
	if sameBareJID(lid, f.lidJID) {
		return f.phoneJID, nil
	}
	return types.JID{}, nil
}

func (f *fakeLIDStore) GetLIDForPN(_ context.Context, phone types.JID) (types.JID, error) {
	if sameBareJID(phone, f.phoneJID) {
		return f.lidJID, nil
	}
	return types.JID{}, nil
}

func (f *fakeLIDStore) GetManyLIDsForPNs(_ context.Context, phones []types.JID) (map[types.JID]types.JID, error) {
	result := make(map[types.JID]types.JID)
	for _, phone := range phones {
		if sameBareJID(phone, f.phoneJID) {
			result[phone] = f.lidJID
		}
	}
	return result, nil
}

func TestResolveMessageContactFromMeNeverUsesOwnIdentity(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("100000000000001", types.HiddenUserServer)
	peerJID := types.NewJID("5511925322715", types.DefaultUserServer)
	peerLID := types.NewJID("200000000000002", types.HiddenUserServer)
	client := &whatsmeow.Client{Store: &store.Device{ID: &ownJID, LID: ownLID}}
	info := types.MessageInfo{MessageSource: types.MessageSource{
		IsFromMe:     true,
		Sender:       ownLID,
		SenderAlt:    ownJID,
		Chat:         peerLID,
		RecipientAlt: peerJID,
	}}

	contact := resolveMessageContact(client, info)

	if !sameBareJID(contact.JID, peerJID) {
		t.Fatalf("contact JID = %s; want %s", contact.JID, peerJID)
	}
	if !sameBareJID(contact.LIDJID, peerLID) || !sameBareJID(contact.AltJID, peerLID) {
		t.Fatalf("contact LID/alt = %s/%s; want %s", contact.LIDJID, contact.AltJID, peerLID)
	}
	if contact.PhoneNumber != "+5511925322715" {
		t.Fatalf("contact phone = %q; want +5511925322715", contact.PhoneNumber)
	}
	if isCurrentClientJID(client, contact.JID) || isCurrentClientJID(client, contact.LIDJID) {
		t.Fatal("resolved contact must not contain an own-account identity")
	}
}

func TestResolveMessageContactUsesDeviceSentDestinationFallback(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("100000000000001", types.HiddenUserServer)
	peerJID := types.NewJID("559231998102", types.DefaultUserServer)
	client := &whatsmeow.Client{Store: &store.Device{ID: &ownJID, LID: ownLID}}
	info := types.MessageInfo{
		MessageSource: types.MessageSource{
			IsFromMe:     true,
			Sender:       ownLID,
			RecipientAlt: ownJID,
			Chat:         ownLID,
		},
		DeviceSentMeta: &types.DeviceSentMeta{DestinationJID: peerJID.String()},
	}

	contact := resolveMessageContact(client, info)

	if !sameBareJID(contact.JID, peerJID) {
		t.Fatalf("contact JID = %s; want device destination %s", contact.JID, peerJID)
	}
}

func TestResolveMessageContactInboundIgnoresRecipientIdentity(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("100000000000001", types.HiddenUserServer)
	peerJID := types.NewJID("553388753501", types.DefaultUserServer)
	peerLID := types.NewJID("200000000000002", types.HiddenUserServer)
	unrelatedRecipient := types.NewJID("559231998102", types.DefaultUserServer)
	client := &whatsmeow.Client{Store: &store.Device{ID: &ownJID, LID: ownLID}}
	info := types.MessageInfo{MessageSource: types.MessageSource{
		Sender:       peerLID,
		SenderAlt:    peerJID,
		Chat:         peerLID,
		RecipientAlt: unrelatedRecipient,
	}}

	contact := resolveMessageContact(client, info)

	if !sameBareJID(contact.JID, peerJID) || !sameBareJID(contact.LIDJID, peerLID) {
		t.Fatalf("contact JID/LID = %s/%s; want %s/%s", contact.JID, contact.LIDJID, peerJID, peerLID)
	}
}

func TestResolveMessageContactHonorsDirectionalPrimaryBeforeLaterPhone(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("100000000000001", types.HiddenUserServer)
	peerJID := types.NewJID("553388753501", types.DefaultUserServer)
	peerLID := types.NewJID("200000000000002", types.HiddenUserServer)
	unrelatedJID := types.NewJID("559231998102", types.DefaultUserServer)
	client := &whatsmeow.Client{Store: &store.Device{
		ID:   &ownJID,
		LID:  ownLID,
		LIDs: &fakeLIDStore{phoneJID: peerJID, lidJID: peerLID},
	}}
	info := types.MessageInfo{MessageSource: types.MessageSource{
		SenderAlt: peerLID,
		Sender:    unrelatedJID,
		Chat:      unrelatedJID,
	}}

	contact := resolveMessageContact(client, info)

	if !sameBareJID(contact.JID, peerJID) {
		t.Fatalf("contact JID = %s; want mapped primary peer %s", contact.JID, peerJID)
	}
}

func TestExtractAdContextSanitizesMetadataAndIncludesThumbnail(t *testing.T) {
	title := " Anúncio de teste "
	mediaURL := "https://cdn.example.com/ad.jpg"
	unsafeSourceURL := "javascript:alert(1)"
	ctwaClid := "clid-123"
	mediaType := proto.ContextInfo_ExternalAdReplyInfo_IMAGE
	showAttribution := true
	thumbnail := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}
	message := &proto.Message{ExtendedTextMessage: &proto.ExtendedTextMessage{ContextInfo: &proto.ContextInfo{
		ConversionSource:           stringPtr("facebook_ad"),
		EntryPointConversionSource: stringPtr("ctwa"),
		ExternalAdReply: &proto.ContextInfo_ExternalAdReplyInfo{
			Title:             &title,
			MediaType:         &mediaType,
			MediaURL:          &mediaURL,
			SourceURL:         &unsafeSourceURL,
			CtwaClid:          &ctwaClid,
			ShowAdAttribution: &showAttribution,
			Thumbnail:         thumbnail,
		},
	}}}

	adContext := extractAdContext(message)

	if adContext == nil {
		t.Fatal("expected ExternalAdReply context")
	}
	if adContext.Title != "Anúncio de teste" || adContext.CTWAClid != ctwaClid || adContext.AdType != "ctwa" {
		t.Fatalf("unexpected ad metadata: %+v", adContext)
	}
	if adContext.MediaURL != mediaURL || adContext.SourceURL != "" {
		t.Fatalf("sanitized URLs = %q/%q; want media URL and empty unsafe source URL", adContext.MediaURL, adContext.SourceURL)
	}
	if adContext.MediaType != "image" || !adContext.ShowAdAttribution {
		t.Fatalf("unexpected media/ad flags: %+v", adContext)
	}
	if !strings.HasPrefix(adContext.ThumbnailDataURL, "data:image/png;base64,") {
		t.Fatalf("thumbnail data URL = %q; want PNG data URL", adContext.ThumbnailDataURL)
	}
}

func TestAdThumbnailDataURLRejectsOversizedThumbnail(t *testing.T) {
	thumbnail := make([]byte, maxAdThumbnailBytes+1)
	if actual := adThumbnailDataURL(thumbnail); actual != "" {
		t.Fatalf("oversized thumbnail data URL = %q; want empty", actual)
	}
}

func TestLookupContactFromStoreResolvesPeerAndUsesBestName(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("100000000000001", types.HiddenUserServer)
	peerJID := types.NewJID("5511925322715", types.DefaultUserServer)
	peerLID := types.NewJID("200000000000002", types.HiddenUserServer)
	device := &store.Device{
		ID:  &ownJID,
		LID: ownLID,
		LIDs: &fakeLIDStore{
			phoneJID: peerJID,
			lidJID:   peerLID,
		},
		Contacts: &fakeContactStore{contacts: map[string]types.ContactInfo{
			peerJID.String(): {Found: true, FullName: "Mayara Variedades"},
			peerLID.String(): {Found: true, PushName: "Mayara"},
		}},
	}

	contact := lookupContactFromStore(context.Background(), device, peerLID)

	if contact.JID != peerJID.String() || contact.PhoneJID != peerJID.String() || contact.LIDJID != peerLID.String() {
		t.Fatalf("resolved identity = %+v; want peer PN/LID", contact)
	}
	if !contact.Found || contact.DisplayName != "Mayara Variedades" || contact.PushName != "Mayara" {
		t.Fatalf("resolved names = %+v; want full name with LID push-name fallback", contact)
	}
}

func TestLookupContactFromStoreRejectsOwnIdentity(t *testing.T) {
	ownJID := types.NewJID("5563999999999", types.DefaultUserServer)
	ownLID := types.NewJID("100000000000001", types.HiddenUserServer)
	device := &store.Device{ID: &ownJID, LID: ownLID, Contacts: &fakeContactStore{}}

	contact := lookupContactFromStore(context.Background(), device, ownLID)

	if contact.JID != "" || contact.Found {
		t.Fatalf("own-account lookup = %+v; want no contact", contact)
	}
}

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
