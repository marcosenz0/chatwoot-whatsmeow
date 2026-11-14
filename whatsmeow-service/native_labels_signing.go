package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var paidOrderID = regexp.MustCompile(`^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$`)
var paidNonce = regexp.MustCompile(`^[a-fA-F0-9]{32}$`)
var paidLabelID = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`)
var paidJID = regexp.MustCompile(`^[0-9]{5,32}@(s\.whatsapp\.net|lid)$`)

func nativeLabelChannelAllowed(channel string) bool {
	allowed := os.Getenv("NATIVE_PAID_ALLOWED_CHANNEL")
	return allowed != "" && channel == allowed
}

func nativeLabelFeatureConfigured() bool {
	return os.Getenv("NATIVE_PAID_ALLOWED_CHANNEL") != ""
}

func nativePaidWriteEnabled() bool {
	return os.Getenv("NATIVE_PAID_WRITE_ENABLED") == "true"
}

func verifyConfiguredPaidCatalogue(cat *nativeLabelCatalog, requestedID string) error {
	configured, err := strconv.ParseInt(os.Getenv("NATIVE_PAID_PREDEFINED_ID"), 10, 32)
	if err != nil || os.Getenv("NATIVE_PAID_LABEL_ID") != requestedID {
		return errors.New("paid_label_not_configured")
	}
	cat.mu.Lock()
	defer cat.mu.Unlock()
	label, ok := cat.bySession["snapshot"][requestedID]
	if !ok || label.predefinedID == nil || int64(*label.predefinedID) != configured {
		return errors.New("paid_label_configuration_changed")
	}
	return nil
}

func paidPayload(req paidLabelRequest, channel string) string {
	return fmt.Sprintf("v1\n%s\n%d\n%d\n%s\n%d\n%s\n%s\n%d\n%s", channel, req.AccountID, req.ConversationID, req.OrderID, req.AmountCents, req.LabelID, req.ChatJID, req.ExpiresUnix, req.Nonce)
}

// The stable hash binds an order forever; rotating its nonce or expiry never
// permits sending the same payment to another chat or applying it a second time.
func paidRequestHash(req paidLabelRequest, channel string) string {
	stable := fmt.Sprintf("v1\n%s\n%d\n%d\n%s\n%d\n%s\n%s", channel, req.AccountID, req.ConversationID, strings.ToLower(req.OrderID), req.AmountCents, req.LabelID, req.ChatJID)
	hash := sha256.Sum256([]byte(stable))
	return hex.EncodeToString(hash[:])
}

func validatePaidLabelSignature(req paidLabelRequest, channel, signature string, now time.Time) error {
	secret := os.Getenv("NATIVE_PAID_SIGNING_SECRET")
	account, err := strconv.ParseInt(os.Getenv("NATIVE_PAID_ALLOWED_ACCOUNT"), 10, 64)
	if !nativePaidWriteEnabled() || len(secret) < 32 || !nativeLabelChannelAllowed(channel) || err != nil || account <= 0 || req.AccountID != account || req.ConversationID <= 0 {
		return errors.New("scope_invalid")
	}
	configuredLabel := os.Getenv("NATIVE_PAID_LABEL_ID")
	if configuredLabel == "" || req.LabelID != configuredLabel || req.AmountCents != 1490 || !paidOrderID.MatchString(req.OrderID) || !paidNonce.MatchString(req.Nonce) || !paidLabelID.MatchString(req.LabelID) || !paidJID.MatchString(req.ChatJID) {
		return errors.New("input_invalid")
	}
	if req.ExpiresUnix <= now.Unix() || req.ExpiresUnix > now.Add(90*time.Second).Unix() {
		return errors.New("expiry_invalid")
	}
	decoded, err := hex.DecodeString(strings.TrimSpace(signature))
	if err != nil {
		return errors.New("signature_invalid")
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(paidPayload(req, channel)))
	if !hmac.Equal(decoded, mac.Sum(nil)) {
		return errors.New("signature_invalid")
	}
	return nil
}
