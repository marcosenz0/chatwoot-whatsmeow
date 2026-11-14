package main

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/polymorfa/hypermeow/appstate"
)

//go:embed migrations/native_paid_receipts.sql
var nativePaidReceiptsSchema string

type nativePaidReceiptStore interface {
	reserve(context.Context, string, paidLabelRequest) (string, bool, error)
	finish(context.Context, string, paidLabelRequest, string) error
}

type postgresNativePaidReceipts struct{ db *sql.DB }

func initializeNativePaidReceipts(ctx context.Context, db *sql.DB) error {
	// A read-only rollout does not create or modify the receipt table.
	if !nativeLabelFeatureConfigured() || !nativePaidWriteEnabled() {
		return nil
	}
	if db == nil {
		return errors.New("native_paid_database_unavailable")
	}
	_, err := db.ExecContext(ctx, nativePaidReceiptsSchema)
	return err
}

func (s postgresNativePaidReceipts) reserve(ctx context.Context, channel string, req paidLabelRequest) (string, bool, error) {
	if s.db == nil {
		return "", false, errors.New("native_paid_database_unavailable")
	}
	hash := paidRequestHash(req, channel)
	var state string
	err := s.db.QueryRowContext(ctx, `INSERT INTO whatsmeow_native_paid_receipts
		(channel_id,order_id,nonce,request_hash,status) VALUES ($1,$2,$3,$4,'reserved')
		ON CONFLICT DO NOTHING RETURNING status`, channel, req.OrderID, strings.ToLower(req.Nonce), hash).Scan(&state)
	if err == nil {
		return state, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", false, err
	}
	var storedHash string
	err = s.db.QueryRowContext(ctx, `SELECT request_hash,status FROM whatsmeow_native_paid_receipts
		WHERE channel_id=$1 AND order_id=$2`, channel, req.OrderID).Scan(&storedHash, &state)
	if errors.Is(err, sql.ErrNoRows) {
		return "authorization_conflict", false, nil
	}
	if err != nil {
		return "", false, err
	}
	if storedHash != hash {
		return "authorization_conflict", false, nil
	}
	if state == "reserved" {
		state = "uncertain"
	}
	return state, false, nil
}

func (s postgresNativePaidReceipts) finish(ctx context.Context, channel string, req paidLabelRequest, state string) error {
	result, err := s.db.ExecContext(ctx, `UPDATE whatsmeow_native_paid_receipts SET status=$4,updated_at=NOW()
		WHERE channel_id=$1 AND order_id=$2 AND request_hash=$3 AND status='reserved'`, channel, req.OrderID, paidRequestHash(req, channel), state)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil || rows != 1 {
		return errors.New("native_paid_receipt_not_finalized")
	}
	return nil
}

func applyNativePaidOnce(ctx context.Context, receipts nativePaidReceiptStore, channel string, req paidLabelRequest, patch appstate.PatchInfo, alreadyObserved bool, send func(context.Context, appstate.PatchInfo) error) (int, string) {
	state, fresh, err := receipts.reserve(ctx, channel, req)
	if err != nil {
		return http.StatusServiceUnavailable, "receipt_store_unavailable"
	}
	if !fresh {
		return http.StatusConflict, state
	}
	status, outcome := http.StatusOK, "observed_on_target"
	if req.ExpiresUnix <= time.Now().Unix() {
		status, outcome = http.StatusConflict, "rejected_expired"
	} else if !alreadyObserved {
		status, outcome = submitPaidPatchOnce(ctx, patch, send)
	}
	// Persisting the outcome is part of completing a write. If this fails, the
	// committed reservation prevents replay even after a crash or restart.
	if err = receipts.finish(ctx, channel, req, outcome); err != nil {
		return http.StatusBadGateway, "uncertain"
	}
	return status, outcome
}
