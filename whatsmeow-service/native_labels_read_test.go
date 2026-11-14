package main

import (
	"bytes"
	"context"
	"errors"
	"testing"

	"github.com/polymorfa/hypermeow/appstate"
	"github.com/polymorfa/hypermeow/proto/waServerSync"
	"github.com/polymorfa/hypermeow/store"
	"github.com/polymorfa/hypermeow/types"
	waLog "github.com/polymorfa/hypermeow/util/log"
	"google.golang.org/protobuf/proto"
)

// Synthetic memory stores only; no network or actual device keys are used.
type proofKeys struct{ key store.AppStateSyncKey }

func (s *proofKeys) PutAppStateSyncKey(context.Context, []byte, store.AppStateSyncKey) error {
	return errors.New("unexpected key write")
}
func (s *proofKeys) GetAppStateSyncKey(_ context.Context, _ []byte) (*store.AppStateSyncKey, error) {
	return &s.key, nil
}
func (s *proofKeys) GetLatestAppStateSyncKeyID(context.Context) ([]byte, error) {
	return []byte{1}, nil
}
func (s *proofKeys) GetAllAppStateSyncKeys(context.Context) ([]*store.AppStateSyncKey, error) {
	return []*store.AppStateSyncKey{&s.key}, nil
}

type proofState struct {
	version uint64
	hash    [128]byte
	macs    map[string][]byte
	writes  int
}

func (s *proofState) PutAppStateVersion(_ context.Context, _ string, v uint64, h [128]byte) error {
	s.version = v
	s.hash = h
	s.writes++
	return nil
}
func (s *proofState) GetAppStateVersion(context.Context, string) (uint64, [128]byte, error) {
	return s.version, s.hash, nil
}
func (s *proofState) DeleteAppStateVersion(context.Context, string) error {
	s.version = 0
	s.hash = [128]byte{}
	s.writes++
	return nil
}
func (s *proofState) PutAppStateMutationMACs(_ context.Context, _ string, _ uint64, m []store.AppStateMutationMAC) error {
	if s.macs == nil {
		s.macs = map[string][]byte{}
	}
	for _, v := range m {
		s.macs[string(v.IndexMAC)] = append([]byte(nil), v.ValueMAC...)
	}
	s.writes++
	return nil
}
func (s *proofState) DeleteAppStateMutationMACs(_ context.Context, _ string, ids [][]byte) error {
	for _, v := range ids {
		delete(s.macs, string(v))
	}
	s.writes++
	return nil
}
func (s *proofState) GetAppStateMutationMAC(_ context.Context, _ string, id []byte) ([]byte, error) {
	return s.macs[string(id)], nil
}

func TestSyntheticReadDoesNotTouchLiveAppState(t *testing.T) {
	ctx := context.Background()
	keys := &proofKeys{key: store.AppStateSyncKey{Data: bytes.Repeat([]byte{42}, 32)}}
	encoderStore := &proofState{}
	encoder := appstate.NewProcessor(&store.Device{AppStateKeys: keys, AppState: encoderStore}, waLog.Noop)
	patch := appstate.BuildLabelEdit("synthetic-label", "Pago", 3, false)
	patch.Mutations[0].Value.LabelEditAction.PredefinedID = proto.Int32(4)
	raw, err := encoder.EncodePatch(ctx, []byte{1}, appstate.HashState{}, patch)
	if err != nil {
		t.Fatal(err)
	}
	var serverPatch waServerSync.SyncdPatch
	if err = proto.Unmarshal(raw, &serverPatch); err != nil {
		t.Fatal(err)
	}
	serverPatch.Version = &waServerSync.SyncdVersion{Version: proto.Uint64(1)}
	liveState := &proofState{version: 77}
	liveDevice := &store.Device{AppStateKeys: keys, AppState: liveState}
	mutations, err := decodeLabelsInScratch(ctx, liveDevice, []*appstate.PatchList{{Name: appstate.WAPatchRegular, Patches: []*waServerSync.SyncdPatch{&serverPatch}}})
	if err != nil {
		t.Fatal(err)
	}
	if len(mutations) != 1 || mutations[0].Action.GetLabelEditAction().GetName() != "Pago" {
		t.Fatal("label not read")
	}
	if liveState.writes != 0 || liveState.version != 77 {
		t.Fatal("live store was changed")
	}
	serverPatch.PatchMAC[0] ^= 1
	if _, err := decodeLabelsInScratch(ctx, liveDevice, []*appstate.PatchList{{Name: appstate.WAPatchRegular, Patches: []*waServerSync.SyncdPatch{&serverPatch}}}); err == nil {
		t.Fatal("tampered patch was accepted")
	}
	if liveState.writes != 0 || liveState.version != 77 {
		t.Fatal("failure altered live store")
	}
}

func TestReadSyntheticFullSnapshotAndFailureCases(t *testing.T) {
	ctx := context.Background()
	keys := &proofKeys{key: store.AppStateSyncKey{Data: bytes.Repeat([]byte{42}, 32)}}
	encoder := appstate.NewProcessor(&store.Device{AppStateKeys: keys, AppState: &proofState{}}, waLog.Noop)
	patch := appstate.BuildLabelEdit("synthetic-label", "Pago", 3, false)
	patch.Mutations[0].Value.LabelEditAction.PredefinedID = proto.Int32(4)
	raw, err := encoder.EncodePatch(ctx, []byte{1}, appstate.HashState{}, patch)
	if err != nil {
		t.Fatal(err)
	}
	var p waServerSync.SyncdPatch
	if err = proto.Unmarshal(raw, &p); err != nil {
		t.Fatal(err)
	}
	snapshot := &waServerSync.SyncdSnapshot{Version: &waServerSync.SyncdVersion{Version: proto.Uint64(1)}, Mac: p.SnapshotMAC, KeyID: p.KeyID}
	for _, m := range p.Mutations {
		snapshot.Records = append(snapshot.Records, m.Record)
	}
	liveState := &proofState{version: 77}
	live := &store.Device{AppStateKeys: keys, AppState: liveState}
	fetch := func(_ context.Context, version uint64, first bool) (*appstate.PatchList, error) {
		if version != 0 || !first {
			t.Fatal("unexpected read")
		}
		return &appstate.PatchList{Name: appstate.WAPatchRegular, Snapshot: snapshot}, nil
	}
	catalog, err := readNativeLabelSnapshot(ctx, live, nil, fetch)
	if err != nil {
		t.Fatal(err)
	}
	if !catalog.complete["snapshot"] || len(catalog.bySession["snapshot"]) != 1 {
		t.Fatal("snapshot not read")
	}
	if liveState.version != 77 || liveState.writes != 0 {
		t.Fatal("live state changed")
	}
	bad := func(context.Context, uint64, bool) (*appstate.PatchList, error) {
		return &appstate.PatchList{Name: appstate.WAPatchRegular}, nil
	}
	if _, err = readNativeLabelSnapshot(ctx, live, nil, bad); err == nil {
		t.Fatal("missing snapshot accepted")
	}
	snapshot.Mac[0] ^= 1
	if _, err = readNativeLabelSnapshot(ctx, live, nil, fetch); err == nil {
		t.Fatal("tampered snapshot accepted")
	}
	if liveState.version != 77 || liveState.writes != 0 {
		t.Fatal("failed read changed live state")
	}
}

func TestReadSyntheticAssociationOnlyForExactTarget(t *testing.T) {
	ctx := context.Background()
	keys := &proofKeys{key: store.AppStateSyncKey{Data: bytes.Repeat([]byte{42}, 32)}}
	encoder := appstate.NewProcessor(&store.Device{AppStateKeys: keys, AppState: &proofState{}}, waLog.Noop)
	patch := appstate.BuildLabelEdit("synthetic-label", "Pago", 3, false)
	patch.Mutations[0].Value.LabelEditAction.PredefinedID = proto.Int32(4)
	target := types.NewJID("555000000000", types.DefaultUserServer)
	other := types.NewJID("555000000001", types.DefaultUserServer)
	patch.Mutations = append(patch.Mutations, appstate.BuildLabelChat(target, "synthetic-label", true).Mutations...)
	patch.Mutations = append(patch.Mutations, appstate.BuildLabelChat(other, "another-label", true).Mutations...)
	raw, err := encoder.EncodePatch(ctx, []byte{1}, appstate.HashState{}, patch)
	if err != nil {
		t.Fatal(err)
	}
	var p waServerSync.SyncdPatch
	if err = proto.Unmarshal(raw, &p); err != nil {
		t.Fatal(err)
	}
	snapshot := &waServerSync.SyncdSnapshot{Version: &waServerSync.SyncdVersion{Version: proto.Uint64(1)}, Mac: p.SnapshotMAC, KeyID: p.KeyID}
	for _, m := range p.Mutations {
		snapshot.Records = append(snapshot.Records, m.Record)
	}
	liveState := &proofState{version: 77}
	live := &store.Device{AppStateKeys: keys, AppState: liveState}
	fetch := func(context.Context, uint64, bool) (*appstate.PatchList, error) {
		return &appstate.PatchList{Name: appstate.WAPatchRegular, Snapshot: snapshot}, nil
	}
	cat, err := readNativeLabelSnapshot(ctx, live, &target, fetch)
	if err != nil {
		t.Fatal(err)
	}
	if !cat.observedTargetLabels["synthetic-label"] || len(cat.observedTargetLabels) != 1 {
		t.Fatal("target filtering failed")
	}
	if liveState.writes != 0 {
		t.Fatal("live state changed")
	}
}

func TestReadSyntheticSnapshotWithNextPage(t *testing.T) {
	ctx := context.Background()
	keys := &proofKeys{key: store.AppStateSyncKey{Data: bytes.Repeat([]byte{42}, 32)}}
	writerState := &proofState{}
	encoder := appstate.NewProcessor(&store.Device{AppStateKeys: keys, AppState: writerState}, waLog.Noop)
	first := appstate.BuildLabelEdit("one", "Pago", 3, false)
	first.Mutations[0].Value.LabelEditAction.PredefinedID = proto.Int32(4)
	raw, err := encoder.EncodePatch(ctx, []byte{1}, appstate.HashState{}, first)
	if err != nil {
		t.Fatal(err)
	}
	var p1 waServerSync.SyncdPatch
	if err = proto.Unmarshal(raw, &p1); err != nil {
		t.Fatal(err)
	}
	p1.Version = &waServerSync.SyncdVersion{Version: proto.Uint64(1)}
	_, state, err := encoder.DecodePatches(ctx, &appstate.PatchList{Name: appstate.WAPatchRegular, Patches: []*waServerSync.SyncdPatch{&p1}}, appstate.HashState{}, true)
	if err != nil {
		t.Fatal(err)
	}
	raw, err = encoder.EncodePatch(ctx, []byte{1}, state, appstate.BuildLabelEdit("two", "Outra", 2, false))
	if err != nil {
		t.Fatal(err)
	}
	var p2 waServerSync.SyncdPatch
	if err = proto.Unmarshal(raw, &p2); err != nil {
		t.Fatal(err)
	}
	p2.Version = &waServerSync.SyncdVersion{Version: proto.Uint64(2)}
	snapshot := &waServerSync.SyncdSnapshot{Version: &waServerSync.SyncdVersion{Version: proto.Uint64(1)}, Mac: p1.SnapshotMAC, KeyID: p1.KeyID}
	for _, m := range p1.Mutations {
		snapshot.Records = append(snapshot.Records, m.Record)
	}
	liveState := &proofState{version: 77}
	live := &store.Device{AppStateKeys: keys, AppState: liveState}
	calls := 0
	fetch := func(_ context.Context, version uint64, isSnapshot bool) (*appstate.PatchList, error) {
		calls++
		if isSnapshot && version == 0 {
			return &appstate.PatchList{Name: appstate.WAPatchRegular, Snapshot: snapshot, HasMorePatches: true}, nil
		}
		if !isSnapshot && version == 1 {
			return &appstate.PatchList{Name: appstate.WAPatchRegular, Patches: []*waServerSync.SyncdPatch{&p2}}, nil
		}
		t.Fatal("unexpected page/version")
		return nil, nil
	}
	cat, err := readNativeLabelSnapshot(ctx, live, nil, fetch)
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 || len(cat.bySession["snapshot"]) != 2 || !cat.complete["snapshot"] {
		t.Fatal("pagination incomplete")
	}
	if liveState.version != 77 || liveState.writes != 0 {
		t.Fatal("live state changed")
	}
}
