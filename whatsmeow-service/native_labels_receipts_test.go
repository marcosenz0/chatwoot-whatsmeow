package main

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/polymorfa/hypermeow/appstate"
)

// The fake models a committed external reservation retained when a caller dies.
// PostgreSQL uniqueness and query semantics are exercised separately.
type fakePaidReceipts struct {
	mu                    sync.Mutex
	reserved              bool
	state                 string
	reserveErr, finishErr error
}

func (s *fakePaidReceipts) reserve(context.Context, string, paidLabelRequest) (string, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.reserveErr != nil {
		return "", false, s.reserveErr
	}
	if s.reserved {
		if s.state == "reserved" {
			return "uncertain", false, nil
		}
		return s.state, false, nil
	}
	s.reserved = true
	s.state = "reserved"
	return s.state, true, nil
}
func (s *fakePaidReceipts) finish(_ context.Context, _ string, _ paidLabelRequest, state string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.finishErr != nil {
		return s.finishErr
	}
	s.state = state
	return nil
}

func TestPaidWriteCannotOutrunDurableReservation(t *testing.T) {
	req := syntheticPaidRequest(t)
	receipts := &fakePaidReceipts{reserveErr: errors.New("database unavailable")}
	status, state := applyNativePaidOnce(context.Background(), receipts, "demo", req, appstate.PatchInfo{}, false, func(context.Context, appstate.PatchInfo) error { t.Fatal("sent without reservation"); return nil })
	if status != http.StatusServiceUnavailable || state != "receipt_store_unavailable" {
		t.Fatal(status, state)
	}
}

func TestPaidWriteConcurrentDuplicateAndRestartNeverResend(t *testing.T) {
	req := syntheticPaidRequest(t)
	receipts := &fakePaidReceipts{finishErr: errors.New("connection lost after send")}
	var sends int64
	send := func(context.Context, appstate.PatchInfo) error { atomic.AddInt64(&sends, 1); return nil }
	var group sync.WaitGroup
	for range 30 {
		group.Add(1)
		go func() {
			defer group.Done()
			applyNativePaidOnce(context.Background(), receipts, "demo", req, appstate.PatchInfo{}, false, send)
		}()
	}
	group.Wait()
	if sends != 1 {
		t.Fatalf("sent %d times", sends)
	}
	// A new invocation sees the same external committed reservation after a
	// simulated lost result; an unfinalized reservation must remain uncertain.
	status, state := applyNativePaidOnce(context.Background(), receipts, "demo", req, appstate.PatchInfo{}, false, send)
	if status != http.StatusConflict || state != "uncertain" || sends != 1 {
		t.Fatal(status, state, sends)
	}
}

func TestAlreadyObservedPaidLabelNeverWrites(t *testing.T) {
	req := syntheticPaidRequest(t)
	receipts := &fakePaidReceipts{}
	status, state := applyNativePaidOnce(context.Background(), receipts, "demo", req, appstate.PatchInfo{}, true, func(context.Context, appstate.PatchInfo) error { t.Fatal("relabelled existing purchase"); return nil })
	if status != http.StatusOK || state != "observed_on_target" || receipts.state != "observed_on_target" {
		t.Fatal(status, state)
	}
}

func TestExpiredAuthorizationAfterReservationNeverWrites(t *testing.T) {
	req := syntheticPaidRequest(t)
	req.ExpiresUnix = time.Now().Add(-time.Second).Unix()
	receipts := &fakePaidReceipts{}
	status, state := applyNativePaidOnce(context.Background(), receipts, "demo", req, appstate.PatchInfo{}, false, func(context.Context, appstate.PatchInfo) error { t.Fatal("sent expired authorization"); return nil })
	if status != http.StatusConflict || state != "rejected_expired" || receipts.state != "rejected_expired" {
		t.Fatal(status, state)
	}
}
