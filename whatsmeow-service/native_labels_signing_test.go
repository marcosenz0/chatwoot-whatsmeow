package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"
	"time"
)

func syntheticPaidRequest(t *testing.T) paidLabelRequest {
	t.Helper()
	t.Setenv("NATIVE_PAID_SIGNING_SECRET", "synthetic-secret-not-used-in-production-32-bytes")
	t.Setenv("NATIVE_PAID_ALLOWED_CHANNEL", "demo")
	t.Setenv("NATIVE_PAID_ALLOWED_ACCOUNT", "2")
	t.Setenv("NATIVE_PAID_LABEL_ID", "demo-label")
	t.Setenv("NATIVE_PAID_WRITE_ENABLED", "true")
	return paidLabelRequest{AccountID: 2, ConversationID: 42, OrderID: "00000000-0000-0000-0000-000000000001", AmountCents: 1490, LabelID: "demo-label", ChatJID: "555000000000@s.whatsapp.net", ExpiresUnix: time.Now().Add(time.Minute).Unix(), Nonce: "1234567890abcdef1234567890abcdef"}
}

func TestPaidAuthorizationBindsEveryFieldAndConfiguration(t *testing.T) {
	req := syntheticPaidRequest(t)
	mac := hmac.New(sha256.New, []byte("synthetic-secret-not-used-in-production-32-bytes"))
	mac.Write([]byte(paidPayload(req, "demo")))
	sig := hex.EncodeToString(mac.Sum(nil))
	if err := validatePaidLabelSignature(req, "demo", sig, time.Now()); err != nil {
		t.Fatal(err)
	}
	for name, mutate := range map[string]func(*paidLabelRequest){
		"account":      func(r *paidLabelRequest) { r.AccountID++ },
		"conversation": func(r *paidLabelRequest) { r.ConversationID++ },
		"order":        func(r *paidLabelRequest) { r.OrderID = "00000000-0000-0000-0000-000000000002" },
		"amount":       func(r *paidLabelRequest) { r.AmountCents++ },
		"label":        func(r *paidLabelRequest) { r.LabelID = "different-label" },
		"target":       func(r *paidLabelRequest) { r.ChatJID = "555000000001@s.whatsapp.net" },
		"nonce":        func(r *paidLabelRequest) { r.Nonce = "00000000000000000000000000000000" },
		"expiry":       func(r *paidLabelRequest) { r.ExpiresUnix++ },
	} {
		t.Run(name, func(t *testing.T) {
			changed := req
			mutate(&changed)
			if validatePaidLabelSignature(changed, "demo", sig, time.Now()) == nil {
				t.Fatal("modified signed request accepted")
			}
		})
	}
	if validatePaidLabelSignature(req, "other", sig, time.Now()) == nil || validatePaidLabelSignature(req, "demo", sig, time.Now().Add(2*time.Minute)) == nil {
		t.Fatal("scope or expiry bypassed")
	}
	t.Setenv("NATIVE_PAID_WRITE_ENABLED", "false")
	if validatePaidLabelSignature(req, "demo", sig, time.Now()) == nil {
		t.Fatal("write-disabled mode accepted mutation")
	}
}

func TestStablePaidOrderHashIgnoresAuthorizationRenewalButNotTarget(t *testing.T) {
	r := syntheticPaidRequest(t)
	hash := paidRequestHash(r, "demo")
	r.ExpiresUnix++
	r.Nonce = "00000000000000000000000000000000"
	if paidRequestHash(r, "demo") != hash {
		t.Fatal("renewal escaped order deduplication")
	}
	r.ChatJID = "555000000001@s.whatsapp.net"
	if paidRequestHash(r, "demo") == hash {
		t.Fatal("target not bound to receipt")
	}
}
