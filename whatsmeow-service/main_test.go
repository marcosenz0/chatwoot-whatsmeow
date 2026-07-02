package main

import "testing"

func TestNormalizeGroupInviteCode(t *testing.T) {
	tests := map[string]string{
		"https://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ?mode=gi_t": "FkLadnTzxGo9S25GLHuWiZ",
		"http://chat.whatsapp.com/FkLadnTzxGo9S25GLHuWiZ":            "FkLadnTzxGo9S25GLHuWiZ",
		"chat.whatsapp.com/invite/FkLadnTzxGo9S25GLHuWiZ":            "FkLadnTzxGo9S25GLHuWiZ",
		"FkLadnTzxGo9S25GLHuWiZ":                                     "FkLadnTzxGo9S25GLHuWiZ",
	}

	for value, expected := range tests {
		code, ok := normalizeGroupInviteCode(value)
		if !ok || code != expected {
			t.Fatalf("normalizeGroupInviteCode(%q) = %q, %v; want %q, true", value, code, ok, expected)
		}
	}
}

func TestNormalizeGroupInviteCodeRejectsInvalidValues(t *testing.T) {
	values := []string{
		"https://example.com/FkLadnTzxGo9S25GLHuWiZ",
		"chat.whatsapp.com/a",
		"not a link",
	}

	for _, value := range values {
		if code, ok := normalizeGroupInviteCode(value); ok || code != "" {
			t.Fatalf("normalizeGroupInviteCode(%q) = %q, %v; want empty, false", value, code, ok)
		}
	}
}
