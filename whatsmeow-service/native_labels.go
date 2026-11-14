// Native labels use the already connected session; no second client is created.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	whatsmeow "github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/appstate"
	"github.com/polymorfa/hypermeow/proto/waServerSync"
	"github.com/polymorfa/hypermeow/store"
	"github.com/polymorfa/hypermeow/types"
	"github.com/polymorfa/hypermeow/types/events"
	waLog "github.com/polymorfa/hypermeow/util/log"
)

type paidLabelRequest struct {
	ChatJID        string `json:"chat_jid"`
	LabelID        string `json:"label_id"`
	AccountID      int64  `json:"account_id"`
	ConversationID int64  `json:"conversation_id"`
	OrderID        string `json:"order_id"`
	AmountCents    int64  `json:"amount_cents"`
	ExpiresUnix    int64  `json:"expires_unix"`
	Nonce          string `json:"nonce"`
	purpose        string
}

func prepareVerifiedPaidPatch(cat *nativeLabelCatalog, jid types.JID, requestedID string) (appstate.PatchInfo, error) {
	if cat == nil || strings.TrimSpace(requestedID) == "" {
		return appstate.PatchInfo{}, errors.New("catalog_or_id_missing")
	}
	patch, err := cat.paidPatch("snapshot", jid)
	if err != nil {
		return appstate.PatchInfo{}, err
	}
	if len(patch.Mutations) != 1 || len(patch.Mutations[0].Index) < 2 || patch.Mutations[0].Index[1] != requestedID {
		return appstate.PatchInfo{}, errors.New("label_id_mismatch")
	}
	return patch, nil
}

// No automatic retry: callers must reconcile uncertain outcomes by read-only check.
func submitPaidPatchOnce(ctx context.Context, patch appstate.PatchInfo, send func(context.Context, appstate.PatchInfo) error) (int, string) {
	if err := send(ctx, patch); errors.Is(err, whatsmeow.ErrPaidLabelConflict) {
		return http.StatusConflict, "rejected_conflict"
	} else if err != nil {
		return http.StatusBadGateway, "uncertain"
	}
	return http.StatusAccepted, "submitted"
}

func readLiveLabelCatalogue(ctx context.Context, client *whatsmeow.Client, target *types.JID) (*nativeLabelCatalog, error) {
	var aliases []types.JID
	if target != nil {
		alias, err := verifiedNativePaidAlias(ctx, client.Store.LIDs, *target)
		if err != nil || isCurrentClientJID(client, alias) {
			return nil, errors.New("target_alias_unverified")
		}
		aliases = append(aliases, alias)
	}
	return readNativeLabelSnapshot(ctx, client.Store, target, func(ctx context.Context, version uint64, snapshot bool) (*appstate.PatchList, error) {
		return client.FetchRegularLabelPageReadOnly(ctx, version, snapshot)
	}, aliases...)
}

type nativePaidAliasStore interface {
	GetPNForLID(context.Context, types.JID) (types.JID, error)
	GetLIDForPN(context.Context, types.JID) (types.JID, error)
}

// The current session must know both directions. Missing/contradictory aliases
// cannot turn a negative exact-JID observation into permission to relabel.
func verifiedNativePaidAlias(ctx context.Context, ids nativePaidAliasStore, target types.JID) (types.JID, error) {
	if ids == nil {
		return types.JID{}, errors.New("identity_store_unavailable")
	}
	target = target.ToNonAD()
	var alias, reverse types.JID
	var err error
	if target.Server == types.DefaultUserServer {
		alias, err = ids.GetLIDForPN(ctx, target)
		if err != nil || alias.Server != types.HiddenUserServer || alias.IsEmpty() {
			return types.JID{}, errors.New("lid_alias_unverified")
		}
		reverse, err = ids.GetPNForLID(ctx, alias.ToNonAD())
	} else if target.Server == types.HiddenUserServer {
		alias, err = ids.GetPNForLID(ctx, target)
		if err != nil || alias.Server != types.DefaultUserServer || alias.IsEmpty() {
			return types.JID{}, errors.New("pn_alias_unverified")
		}
		reverse, err = ids.GetLIDForPN(ctx, alias.ToNonAD())
	} else {
		return types.JID{}, errors.New("invalid_individual_target")
	}
	if err != nil || reverse.ToNonAD() != target {
		return types.JID{}, errors.New("identity_mapping_not_reversible")
	}
	return alias.ToNonAD(), nil
}

func handleNativePaidIdentity(c *gin.Context) {
	if !nativeLabelChannelAllowed(c.Param("channel_id")) {
		c.JSON(http.StatusForbidden, gin.H{"error": "native_labels_scope_disabled"})
		return
	}
	var req paidLabelRequest
	if err := c.ShouldBindJSON(&req); err != nil || !paidJID.MatchString(req.ChatJID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_individual_target"})
		return
	}
	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok || client.Store == nil || client.Store.ID == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "session_not_connected"})
		return
	}
	jid, ok := parseJID(req.ChatJID)
	if !ok || isCurrentClientJID(client, jid) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_target"})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()
	alias, err := verifiedNativePaidAlias(ctx, client.Store.LIDs, jid)
	if err != nil || isCurrentClientJID(client, alias) {
		c.JSON(http.StatusConflict, gin.H{"error": "target_alias_unverified"})
		return
	}
	pn, lid := jid.ToNonAD(), alias
	if jid.Server == types.HiddenUserServer {
		pn, lid = alias, jid.ToNonAD()
	}
	fingerprint := nativePaidSessionIdentity(client.Store)
	if fingerprint == "" {
		c.JSON(http.StatusConflict, gin.H{"error": "session_identity_unavailable"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "verified", "pn_jid": pn.String(), "lid_jid": lid.String(), "session_identity": fingerprint, "channel_id": c.Param("channel_id")})
}

func nativePaidSessionIdentity(device *store.Device) string {
	if device == nil || device.ID == nil || device.ID.IsEmpty() || device.LID.IsEmpty() {
		return ""
	}
	digest := sha256.Sum256([]byte(device.ID.ToNonAD().String() + "\n" + device.LID.ToNonAD().String()))
	return hex.EncodeToString(digest[:])
}

func handleReadNativeLabels(c *gin.Context) {
	if !nativeLabelChannelAllowed(c.Param("channel_id")) {
		c.JSON(http.StatusForbidden, gin.H{"error": "native_labels_scope_disabled"})
		return
	}
	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok {
		c.JSON(http.StatusConflict, gin.H{"error": "session_not_connected"})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()
	cat, err := readLiveLabelCatalogue(ctx, client, nil)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "label_catalog_unavailable"})
		return
	}
	cat.mu.Lock()
	defer cat.mu.Unlock()
	labels := []gin.H{}
	for _, v := range cat.bySession["snapshot"] {
		if !v.deleted {
			labels = append(labels, gin.H{"id": v.id, "name": v.name, "predefined_id": v.predefinedID})
		}
	}
	c.JSON(http.StatusOK, gin.H{"labels": labels, "source": "read_only_snapshot", "complete": cat.complete["snapshot"], "session_identity": nativePaidSessionIdentity(client.Store)})
}

// The caller is responsible for independently confirming payment. A successful
// patch submission does not prove the phone or Ads Manager has applied it.
func handleApplyNativePaidLabel(c *gin.Context) {
	handleNativePaidMutation(c, "payment")
}

// Owner-authorized smoke testing is separate from confirmed-payment signing.
// Its separate key and exact contact scope cannot authorize a customer sale.
func handleTestNativePaidLabel(c *gin.Context) {
	handleNativePaidMutation(c, "test")
}

func handleNativePaidMutation(c *gin.Context, purpose string) {
	var req paidLabelRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.LabelID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	req.purpose = purpose
	if err := validatePaidLabelSignature(req, c.Param("channel_id"), c.GetHeader("X-Paid-Label-Signature"), time.Now()); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "paid_authorization_invalid"})
		return
	}
	if !strings.Contains(req.ChatJID, "@") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "individual_jid_required"})
		return
	}
	jid, ok := parseJID(req.ChatJID)
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_target"})
		return
	}
	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok {
		c.JSON(http.StatusConflict, gin.H{"error": "session_not_connected"})
		return
	}
	if !nativePaidSessionMatches(client.Store) {
		c.JSON(http.StatusConflict, gin.H{"error": "session_identity_mismatch"})
		return
	}
	if isCurrentClientJID(client, jid) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "own_chat_rejected"})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()
	cat, err := readLiveLabelCatalogue(ctx, client, &jid)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "label_catalog_unavailable"})
		return
	}
	patch, err := prepareVerifiedPaidPatch(cat, jid, req.LabelID)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "verified_paid_label_not_matched"})
		return
	}
	if err = verifyConfiguredPaidCatalogue(cat, req.LabelID); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "verified_paid_label_not_configured"})
		return
	}
	status, outcome := applyNativePaidOnce(ctx, postgresNativePaidReceipts{db: statusLookupDB}, c.Param("channel_id"), req, patch, cat.observedTargetLabels[req.LabelID], client.SubmitPaidLabelOnce)
	c.JSON(status, gin.H{"status": outcome, "delivery_verified": outcome == "observed_on_target", "retry_automatically": false, "meta_attribution_verified": false})
}

// Uses an authenticated request body rather than a URL containing the JID.
// Absence is not proof of failure because provider identities may have aliases.
func handleCheckNativePaidLabel(c *gin.Context) {
	if !nativeLabelChannelAllowed(c.Param("channel_id")) {
		c.JSON(http.StatusForbidden, gin.H{"error": "native_labels_scope_disabled"})
		return
	}
	var req paidLabelRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.LabelID) == "" || !strings.Contains(req.ChatJID, "@") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}
	jid, ok := parseJID(req.ChatJID)
	if !ok || jid.IsEmpty() || (jid.Server != types.DefaultUserServer && jid.Server != types.HiddenUserServer) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_target"})
		return
	}
	client, ok := clientForChannel(c.Param("channel_id"))
	if !ok {
		c.JSON(http.StatusConflict, gin.H{"error": "session_not_connected"})
		return
	}
	if !nativePaidSessionMatches(client.Store) {
		c.JSON(http.StatusConflict, gin.H{"error": "session_identity_mismatch"})
		return
	}
	if isCurrentClientJID(client, jid) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "own_chat_rejected"})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()
	cat, err := readLiveLabelCatalogue(ctx, client, &jid)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "label_catalog_unavailable"})
		return
	}
	if _, err = prepareVerifiedPaidPatch(cat, jid, req.LabelID); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "verified_paid_label_not_matched"})
		return
	}
	present := cat.observedTargetLabels[req.LabelID]
	if present {
		c.JSON(http.StatusOK, gin.H{"status": "observed_on_target", "meta_attribution_verified": false})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "not_observed", "meta_attribution_verified": false})
}

// Scratch state accepts decoder writes without ever touching the connected
// session's app-state store. It is intentionally short-lived and local.
type scratchAppState struct {
	version uint64
	hash    [128]byte
	macs    map[string][]byte
}

func (s *scratchAppState) PutAppStateVersion(_ context.Context, _ string, v uint64, h [128]byte) error {
	s.version = v
	s.hash = h
	return nil
}
func (s *scratchAppState) GetAppStateVersion(context.Context, string) (uint64, [128]byte, error) {
	return s.version, s.hash, nil
}
func (s *scratchAppState) DeleteAppStateVersion(context.Context, string) error {
	s.version = 0
	s.hash = [128]byte{}
	s.macs = map[string][]byte{}
	return nil
}
func (s *scratchAppState) PutAppStateMutationMACs(_ context.Context, _ string, _ uint64, m []store.AppStateMutationMAC) error {
	if s.macs == nil {
		s.macs = map[string][]byte{}
	}
	for _, v := range m {
		s.macs[string(v.IndexMAC)] = append([]byte(nil), v.ValueMAC...)
	}
	return nil
}
func (s *scratchAppState) DeleteAppStateMutationMACs(_ context.Context, _ string, ids [][]byte) error {
	for _, v := range ids {
		delete(s.macs, string(v))
	}
	return nil
}
func (s *scratchAppState) GetAppStateMutationMAC(_ context.Context, _ string, id []byte) ([]byte, error) {
	return s.macs[string(id)], nil
}

type readOnlySyncKeys struct{ source store.AppStateSyncKeyStore }

func (k readOnlySyncKeys) PutAppStateSyncKey(context.Context, []byte, store.AppStateSyncKey) error {
	return errors.New("read_only_keys")
}
func (k readOnlySyncKeys) GetAppStateSyncKey(c context.Context, id []byte) (*store.AppStateSyncKey, error) {
	return k.source.GetAppStateSyncKey(c, id)
}
func (k readOnlySyncKeys) GetLatestAppStateSyncKeyID(c context.Context) ([]byte, error) {
	return k.source.GetLatestAppStateSyncKeyID(c)
}
func (k readOnlySyncKeys) GetAllAppStateSyncKeys(c context.Context) ([]*store.AppStateSyncKey, error) {
	return k.source.GetAllAppStateSyncKeys(c)
}

// Decodes already-fetched, authenticated lists; does not fetch from WhatsApp.
// The caller must separately establish full snapshot and pagination coverage.
func decodeLabelsInScratch(ctx context.Context, live *store.Device, lists []*appstate.PatchList) ([]appstate.Mutation, error) {
	if live == nil || live.AppStateKeys == nil {
		return nil, errors.New("keys_unavailable")
	}
	processor := appstate.NewProcessor(&store.Device{AppStateKeys: readOnlySyncKeys{source: live.AppStateKeys}, AppState: &scratchAppState{}}, waLog.Noop)
	state := appstate.HashState{}
	var all []appstate.Mutation
	for _, list := range lists {
		if list == nil || list.Name != appstate.WAPatchRegular {
			return nil, errors.New("invalid_collection")
		}
		mutations, next, err := processor.DecodePatches(ctx, list, state, true)
		if err != nil {
			return nil, err
		}
		state = next
		for _, m := range mutations {
			if len(m.Index) > 0 && m.Index[0] == appstate.IndexLabelEdit {
				all = append(all, m)
			}
		}
	}
	return all, nil
}

type nativeLabelObservation struct {
	id           string
	name         string
	predefinedID *int32
	deleted      bool
	observedAt   time.Time
}

// Catalogues are partitioned by session identity. Snapshot completeness must
// be established independently; observing an arbitrary live event is not enough.
type nativeLabelCatalog struct {
	mu                   sync.Mutex
	bySession            map[string]map[string]nativeLabelObservation
	complete             map[string]bool
	observedTargetLabels map[string]bool
}

// Read a complete regular snapshot into isolated scratch state. The fetcher is
// injected so tests cannot contact WhatsApp. Missing snapshots, interrupted or
// excessively long pagination, and invalid MACs all fail closed.
func readNativeLabelSnapshot(ctx context.Context, live *store.Device, target *types.JID, fetch func(context.Context, uint64, bool) (*appstate.PatchList, error), aliases ...types.JID) (*nativeLabelCatalog, error) {
	if live == nil || live.AppStateKeys == nil || fetch == nil {
		return nil, errors.New("reader_unavailable")
	}
	processor := appstate.NewProcessor(&store.Device{AppStateKeys: readOnlySyncKeys{source: live.AppStateKeys}, AppState: &scratchAppState{}}, waLog.Noop)
	state := appstate.HashState{}
	catalog := newNativeLabelCatalog()
	targets := map[types.JID]map[string]bool{}
	if target != nil {
		targets[target.ToNonAD()] = map[string]bool{}
		for _, alias := range aliases {
			targets[alias.ToNonAD()] = map[string]bool{}
		}
	}
	for page := 0; page < 20; page++ {
		list, err := fetch(ctx, state.Version, page == 0)
		if err != nil {
			return nil, err
		}
		if list == nil || list.Name != appstate.WAPatchRegular || (page == 0 && list.Snapshot == nil) || (page > 0 && list.Snapshot != nil) {
			return nil, errors.New("incomplete_or_invalid_snapshot")
		}
		mutations, next, err := processor.DecodePatches(ctx, list, state, true)
		if err != nil {
			return nil, err
		}
		if list.HasMorePatches && next.Version <= state.Version {
			return nil, errors.New("pagination_did_not_advance")
		}
		state = next
		for _, m := range mutations {
			if target != nil && len(m.Index) == 3 && m.Index[0] == appstate.IndexLabelAssociationChat {
				jid, parseErr := types.ParseJID(m.Index[2])
				labels, relevant := targets[jid.ToNonAD()]
				if parseErr != nil || !relevant {
					continue
				}
				if m.Operation == waServerSync.SyncdMutation_REMOVE {
					delete(labels, m.Index[1])
					continue
				}
				if m.Operation != waServerSync.SyncdMutation_SET || m.Action == nil || m.Action.GetLabelAssociationAction() == nil {
					return nil, errors.New("invalid_association_mutation")
				}
				labels[m.Index[1]] = m.Action.GetLabelAssociationAction().GetLabeled()
				continue
			}
			if len(m.Index) != 2 || m.Index[0] != appstate.IndexLabelEdit {
				continue
			}
			if m.Operation == waServerSync.SyncdMutation_REMOVE {
				catalog.forget("snapshot", m.Index[1])
				continue
			}
			if m.Operation != waServerSync.SyncdMutation_SET || m.Action == nil || m.Action.GetLabelEditAction() == nil {
				return nil, errors.New("invalid_label_mutation")
			}
			catalog.observe("snapshot", &events.LabelEdit{LabelID: m.Index[1], Action: m.Action.GetLabelEditAction(), Timestamp: time.Now()})
		}
		if !list.HasMorePatches {
			for _, labels := range targets {
				for label, present := range labels {
					catalog.observedTargetLabels[label] = catalog.observedTargetLabels[label] || present
				}
			}
			catalog.complete["snapshot"] = true
			return catalog, nil
		}
	}
	return nil, errors.New("pagination_limit")
}

func newNativeLabelCatalog() *nativeLabelCatalog {
	return &nativeLabelCatalog{bySession: make(map[string]map[string]nativeLabelObservation), complete: make(map[string]bool), observedTargetLabels: make(map[string]bool)}
}

func (c *nativeLabelCatalog) observe(session string, e *events.LabelEdit) {
	if strings.TrimSpace(session) == "" || e == nil || e.Action == nil || strings.TrimSpace(e.LabelID) == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.bySession[session] == nil {
		c.bySession[session] = make(map[string]nativeLabelObservation)
	}
	old, ok := c.bySession[session][e.LabelID]
	if ok && old.observedAt.After(e.Timestamp) {
		return
	}
	var preset *int32
	if e.Action.PredefinedID != nil {
		value := e.Action.GetPredefinedID()
		preset = &value
	}
	c.bySession[session][e.LabelID] = nativeLabelObservation{id: e.LabelID, name: e.Action.GetName(), predefinedID: preset, deleted: e.Action.GetDeleted(), observedAt: e.Timestamp}
}

func (c *nativeLabelCatalog) forget(session, id string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.bySession[session], id)
}

func (c *nativeLabelCatalog) paidPatch(session string, jid types.JID) (appstate.PatchInfo, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.complete[session] {
		return appstate.PatchInfo{}, errors.New("catalog_incomplete")
	}
	if jid.IsEmpty() || (jid.Server != types.DefaultUserServer && jid.Server != types.HiddenUserServer) {
		return appstate.PatchInfo{}, errors.New("invalid_individual_target")
	}
	var id string
	for _, label := range c.bySession[session] {
		if !label.deleted && label.predefinedID != nil && strings.EqualFold(strings.TrimSpace(label.name), "pago") {
			if id != "" {
				return appstate.PatchInfo{}, errors.New("ambiguous_paid_label")
			}
			id = label.id
		}
	}
	if id == "" {
		return appstate.PatchInfo{}, errors.New("predefined_paid_not_observed")
	}
	return appstate.BuildLabelChat(jid.ToNonAD(), id, true), nil
}
