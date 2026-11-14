package main

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	whatsmeow "github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/appstate"
	"github.com/polymorfa/hypermeow/proto/waSyncAction"
	"github.com/polymorfa/hypermeow/types"
	"github.com/polymorfa/hypermeow/types/events"
)

func observed(id, name string, preset *int32, deleted bool, at time.Time) *events.LabelEdit {
	return &events.LabelEdit{LabelID: id, Timestamp: at, Action: &waSyncAction.LabelEditAction{Name: &name, PredefinedID: preset, Deleted: &deleted}}
}

func TestSubmitPaidPatchNeverAutomaticallyRetries(t *testing.T) {
	for _, tc := range []struct {
		err     error
		status  int
		outcome string
	}{{whatsmeow.ErrPaidLabelConflict, http.StatusConflict, "rejected_conflict"}, {context.DeadlineExceeded, http.StatusBadGateway, "uncertain"}, {errors.New("post submission sync failure"), http.StatusBadGateway, "uncertain"}, {nil, http.StatusAccepted, "submitted"}} {
		calls := 0
		status, outcome := submitPaidPatchOnce(context.Background(), appstate.PatchInfo{}, func(context.Context, appstate.PatchInfo) error { calls++; return tc.err })
		if calls != 1 || status != tc.status || outcome != tc.outcome {
			t.Fatal("incorrect submission semantics")
		}
	}
}

func TestNativeLabelPaidFailClosed(t *testing.T) {
	c := newNativeLabelCatalog()
	now := time.Now()
	preset := int32(1)
	jid := types.NewJID("555000000000", types.DefaultUserServer)
	c.observe("alice", observed("observed-a", "Pago", &preset, false, now))
	if _, err := c.paidPatch("alice", jid); err == nil {
		t.Fatal("incomplete catalog accepted")
	}
	c.complete["alice"] = true
	patch, err := c.paidPatch("alice", jid)
	if err != nil {
		t.Fatal(err)
	}
	if patch.Type != appstate.WAPatchRegular || len(patch.Mutations) != 1 {
		t.Fatal("unexpected patch")
	}
	mutation := patch.Mutations[0]
	if len(mutation.Index) != 3 || mutation.Index[1] != "observed-a" || mutation.Index[2] != jid.String() || !mutation.Value.GetLabelAssociationAction().GetLabeled() {
		t.Fatal("incorrect association")
	}
	if _, err := c.paidPatch("different-session", jid); err == nil {
		t.Fatal("cross-session catalog accepted")
	}
	if _, err := c.paidPatch("alice", types.NewJID("555", types.GroupServer)); err == nil {
		t.Fatal("group accepted")
	}
	c.observe("alice", observed("observed-b", "Pago", &preset, false, now.Add(time.Second)))
	if _, err := c.paidPatch("alice", jid); err == nil {
		t.Fatal("ambiguous labels accepted")
	}
	c.observe("alice", observed("observed-b", "Pago", &preset, true, now.Add(2*time.Second)))
	if _, err := c.paidPatch("alice", jid); err != nil {
		t.Fatal(err)
	}
	c.observe("alice", observed("observed-a", "Pago", nil, false, now.Add(3*time.Second)))
	if _, err := c.paidPatch("alice", jid); err == nil {
		t.Fatal("non-predefined label accepted")
	}
}

func TestPrepareVerifiedPaidPatchRejectsMismatch(t *testing.T) {
	c := newNativeLabelCatalog()
	preset := int32(4)
	c.observe("snapshot", observed("observed-a", "Pago", &preset, false, time.Now()))
	c.complete["snapshot"] = true
	jid := types.NewJID("555000000000", types.DefaultUserServer)
	if _, err := prepareVerifiedPaidPatch(c, jid, "another-id"); err == nil {
		t.Fatal("label id mismatch accepted")
	}
	if _, err := prepareVerifiedPaidPatch(c, jid, "observed-a"); err != nil {
		t.Fatal(err)
	}
}
