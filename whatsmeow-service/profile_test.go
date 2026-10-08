package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"image"
	"image/jpeg"
	"strings"
	"testing"
	"time"

	"github.com/polymorfa/hypermeow"
	"github.com/polymorfa/hypermeow/appstate"
	"github.com/polymorfa/hypermeow/types"
	"go.mau.fi/util/jsontime"
)

type profileTestClient struct {
	users       map[types.JID]types.UserInfo
	photo       *types.ProfilePictureInfo
	photoErr    error
	business    *types.BusinessProfile
	businessErr error
	queries     []types.JID
	preview     bool
}

func (f *profileTestClient) GetUserInfo(_ context.Context, jids []types.JID) (map[types.JID]types.UserInfo, error) {
	f.queries = append(f.queries, jids...)
	return f.users, nil
}
func (f *profileTestClient) GetProfilePictureInfo(_ context.Context, jid types.JID, p *whatsmeow.GetProfilePictureParams) (*types.ProfilePictureInfo, error) {
	f.queries = append(f.queries, jid)
	f.preview = p.Preview
	return f.photo, f.photoErr
}
func (f *profileTestClient) GetBusinessProfile(_ context.Context, jid types.JID) (*types.BusinessProfile, error) {
	f.queries = append(f.queries, jid)
	return f.business, f.businessErr
}
func (f *profileTestClient) UpdateBusinessProfile(context.Context, types.BusinessProfileUpdate) error {
	return nil
}
func (f *profileTestClient) SetStatusMessage(context.Context, types.SetStatusInput) error { return nil }
func (f *profileTestClient) SendAppState(context.Context, appstate.PatchInfo) error       { return nil }
func (f *profileTestClient) SetGroupPhoto(context.Context, types.JID, []byte) (string, error) {
	return "photo", nil
}

func TestOwnProfileUsesConnectedIdentityAndCurrentFullPhoto(t *testing.T) {
	jid := types.NewJID("5511999991111", types.DefaultUserServer)
	f := &profileTestClient{users: map[types.JID]types.UserInfo{jid: {Status: "Available"}}, photo: &types.ProfilePictureInfo{URL: "https://example.com/full.jpg"}}
	result, err := ownProfileSnapshot(context.Background(), f, jid, "Owner", "")
	if err != nil || result["photo_url"] != f.photo.URL || result["about"] != "Available" || result["name"] != "Owner" || result["is_business"] != false {
		t.Fatalf("profile=%v err=%v", result, err)
	}
	if f.preview {
		t.Fatal("requested a thumbnail instead of full photo")
	}
	for _, q := range f.queries {
		if q != jid {
			t.Fatalf("queried an unrelated identity: %v", q)
		}
	}
	f.photo.URL = "https://example.com/new-photo.jpg"
	result, err = ownProfileSnapshot(context.Background(), f, jid, "New name", "")
	if err != nil || result["photo_url"] != f.photo.URL || result["name"] != "New name" {
		t.Fatal("profile from phone was not refreshed")
	}
}

func TestFullPhotoRespectsPrivacyAndReportsNetworkFailures(t *testing.T) {
	for _, tt := range []struct {
		err    error
		status string
	}{{whatsmeow.ErrProfilePictureNotSet, "none"}, {whatsmeow.ErrProfilePictureUnauthorized, "hidden"}} {
		f := &profileTestClient{photoErr: tt.err}
		photo, err := currentProfilePicture(context.Background(), f, types.NewJID("5511999991111", types.DefaultUserServer))
		if err != nil || photo["photo_status"] != tt.status || photo["photo_url"] != "" {
			t.Fatalf("photo=%v err=%v", photo, err)
		}
	}
	f := &profileTestClient{photoErr: errors.New("network error")}
	if _, err := currentProfilePicture(context.Background(), f, types.EmptyJID); err == nil {
		t.Fatal("network failure was hidden as no photo")
	}
}

func TestOwnProfileReadsModernAboutInsteadOfStaleLegacyStatus(t *testing.T) {
	jid := types.NewJID("5511999991111", types.DefaultUserServer)
	text := "Modern About"
	f := &profileTestClient{users: map[types.JID]types.UserInfo{jid: {Status: "Old About", TextStatus: &types.SetStatusInput{
		Text: &text, Emoji: &types.SetStatusEmoji{Content: "👋"}, Duration: jsontime.S(24 * time.Hour),
	}}}, photoErr: whatsmeow.ErrProfilePictureNotSet}
	result, err := ownProfileSnapshot(context.Background(), f, jid, "Owner", "")
	if err != nil || result["about"] != text || result["about_duration"] != 86400 || result["about_emoji"] != "👋" {
		t.Fatalf("profile=%v err=%v", result, err)
	}
	text = ""
	result, err = ownProfileSnapshot(context.Background(), f, jid, "Owner", "")
	if err != nil || result["about"] != "" {
		t.Fatal("cleared modern About was replaced by stale legacy status")
	}
}

func TestModernAboutSetsPositiveDurationAndClearsWithNull(t *testing.T) {
	text := "Available"
	input := (profileMutation{About: &text}).aboutInput()
	if input.Text == nil || *input.Text != text || input.Duration.Duration != 24*time.Hour {
		t.Fatal("modern About lacks its required positive duration")
	}
	duration := 604800
	input = (profileMutation{About: &text, AboutDuration: &duration}).aboutInput()
	if input.Duration.Duration != 7*24*time.Hour {
		t.Fatal("selected About duration was not applied")
	}
	text = " "
	input = (profileMutation{About: &text, AboutDuration: &duration}).aboutInput()
	if input.Text != nil || !input.Duration.IsZero() || input.Emoji != nil {
		t.Fatal("clearing About must send null text with zero duration")
	}
}

func TestBusinessProfileIncludesFieldsAndHours(t *testing.T) {
	jid := types.NewJID("5511999991111", types.DefaultUserServer)
	f := &profileTestClient{users: map[types.JID]types.UserInfo{jid: {VerifiedName: &types.VerifiedName{}}}, business: &types.BusinessProfile{Address: "Address", Email: "owner@example.com", Description: "Business", Websites: []string{"https://example.com"}, BusinessHoursTimeZone: "America/Sao_Paulo", BusinessHours: []types.BusinessHoursConfig{{DayOfWeek: "mon", Mode: "specific_hours", OpenTime: "540", CloseTime: "1080"}}}, photoErr: whatsmeow.ErrProfilePictureNotSet}
	result, err := ownProfileSnapshot(context.Background(), f, jid, "Owner", "")
	if err != nil || result["is_business"] != true || result["business"] == nil {
		t.Fatalf("profile=%v err=%v", result, err)
	}
	f.businessErr = errors.New("business request failed")
	if _, err := ownProfileSnapshot(context.Background(), f, jid, "Owner", ""); err == nil {
		t.Fatal("business failure was hidden")
	}
}

func TestProfileRejectsEmptyOverlongNamesAndKeepsUnicode(t *testing.T) {
	for _, name := range []string{"", "  ", strings.Repeat("á", 26)} {
		if (profileMutation{Name: &name}).validate() == nil {
			t.Fatalf("invalid name %q accepted", name)
		}
	}
	name := strings.Repeat("á", 25)
	if err := (profileMutation{Name: &name}).validate(); err != nil {
		t.Fatal(err)
	}
	about := strings.Repeat("á", 140)
	if (profileMutation{About: &about}).validate() == nil {
		t.Fatal("overlong about accepted")
	}
	if (profileMutation{}).validate() == nil {
		t.Fatal("empty update accepted")
	}
}

func TestPhotoRejectsMalformedOversizeAndNonSquareUploads(t *testing.T) {
	for _, value := range []string{"", "bad base64", base64.StdEncoding.EncodeToString([]byte("<svg></svg>")), strings.Repeat("a", 3*1024*1024+1)} {
		if _, err := decodeProfilePhoto(value); err == nil {
			t.Fatal("invalid image accepted")
		}
	}
	for _, size := range []image.Point{{191, 191}, {640, 480}, {2049, 2049}, {640, 640}} {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, size.X, size.Y)), nil); err != nil {
			t.Fatal(err)
		}
		_, err := decodeProfilePhoto(base64.StdEncoding.EncodeToString(buf.Bytes()))
		if (err == nil) != (size.X == 640 && size.Y == 640) {
			t.Fatalf("size=%v err=%v", size, err)
		}
	}
}
