package main

import (
	"context"
	"testing"

	"github.com/polymorfa/hypermeow/store"
	"github.com/polymorfa/hypermeow/types"
)

type syntheticPaidAliasStore struct{ pn, lid types.JID }

func (s syntheticPaidAliasStore) GetPNForLID(context.Context, types.JID) (types.JID, error) {
	return s.pn, nil
}

func TestPaidSessionPinRejectsReplacementPairing(t *testing.T) {
	pn := types.NewJID("555000000000", types.DefaultUserServer)
	lid := types.NewJID("123456789000", types.HiddenUserServer)
	device := &store.Device{ID: &pn, LID: lid}
	t.Setenv("NATIVE_PAID_EXPECTED_SESSION_IDENTITY", nativePaidSessionIdentity(device))
	if !nativePaidSessionMatches(device) {
		t.Fatal("current session rejected")
	}
	device.LID = types.NewJID("123456789001", types.HiddenUserServer)
	if nativePaidSessionMatches(device) {
		t.Fatal("replacement session accepted")
	}
	if nativePaidSessionMatches(nil) {
		t.Fatal("missing session accepted")
	}
}
func (s syntheticPaidAliasStore) GetLIDForPN(context.Context, types.JID) (types.JID, error) {
	return s.lid, nil
}

func TestPaidAliasMustBeReversibleAndIndividual(t *testing.T) {
	pn := types.NewJID("555000000000", types.DefaultUserServer)
	lid := types.NewJID("123456789000", types.HiddenUserServer)
	ids := syntheticPaidAliasStore{pn: pn, lid: lid}
	for _, target := range []types.JID{pn, lid} {
		alias, err := verifiedNativePaidAlias(context.Background(), ids, target)
		if err != nil || alias == target || alias.IsEmpty() {
			t.Fatal(alias, err)
		}
	}
	ids.pn = types.NewJID("555000000001", types.DefaultUserServer)
	if _, err := verifiedNativePaidAlias(context.Background(), ids, pn); err == nil {
		t.Fatal("contradictory alias accepted")
	}
	if _, err := verifiedNativePaidAlias(context.Background(), nil, pn); err == nil {
		t.Fatal("missing identity store accepted")
	}
	if _, err := verifiedNativePaidAlias(context.Background(), ids, types.NewJID("123", types.GroupServer)); err == nil {
		t.Fatal("group accepted")
	}
}
