package main

import (
	"strings"
	"testing"
)

func TestGroupMutationValidation(t *testing.T) {
	for _, value := range []string{"", strings.Repeat("a", 101)} {
		if (groupMutation{Name: &value}).validate() == nil {
			t.Fatal("invalid group name accepted")
		}
	}
	for _, timer := range []uint32{0, 86400, 604800, 7776000} {
		if err := (groupMutation{DisappearingTimer: &timer}).validate(); err != nil {
			t.Fatal(err)
		}
	}
	timer := uint32(60)
	if (groupMutation{DisappearingTimer: &timer}).validate() == nil {
		t.Fatal("unsupported disappearing duration accepted")
	}
	photo := "not-a-jpeg"
	if (groupMutation{Photo: &photo}).validate() == nil {
		t.Fatal("invalid photo accepted")
	}
}

func TestGroupMemberTargetsRejectsChatsAndDeduplicatesMembers(t *testing.T) {
	members, err := groupMemberTargets([]string{"556392977347@s.whatsapp.net", "556392977347@s.whatsapp.net", "123456789012345@lid"})
	if err != nil || len(members) != 2 {
		t.Fatalf("members=%v, err=%v", members, err)
	}
	for _, jid := range []string{"120363000000001@g.us", "status@broadcast", "invalid"} {
		if _, err := groupMemberTargets([]string{jid}); err == nil {
			t.Fatalf("invalid participant %s accepted", jid)
		}
	}
}
