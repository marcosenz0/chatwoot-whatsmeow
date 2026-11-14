package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestLabelRoutesRequireInternalToken(t *testing.T) {
	t.Setenv("WHATSMEOW_SHARED_SECRET", "synthetic-test-only")
	t.Setenv("NATIVE_PAID_ALLOWED_CHANNEL", "missing")
	r := gin.New()
	r.GET("/sessions/:channel_id/native-labels", internalTokenMiddleware(), handleReadNativeLabels)
	r.POST("/sessions/:channel_id/native-labels/paid", internalTokenMiddleware(), handleApplyNativePaidLabel)
	r.POST("/sessions/:channel_id/native-labels/check", internalTokenMiddleware(), handleCheckNativePaidLabel)
	for _, v := range []struct{ method, path, body string }{
		{http.MethodGet, "/sessions/1/native-labels", ""},
		{http.MethodPost, "/sessions/1/native-labels/paid", `{"label_id":"4","chat_jid":"test@s.whatsapp.net"}`},
		{http.MethodPost, "/sessions/1/native-labels/check", `{"label_id":"4","chat_jid":"test@s.whatsapp.net"}`},
	} {
		req := httptest.NewRequest(v.method, v.path, strings.NewReader(v.body))
		out := httptest.NewRecorder()
		r.ServeHTTP(out, req)
		if out.Code != http.StatusUnauthorized {
			t.Fatalf("%s accepted unauthenticated request", v.method)
		}
	}
	req := httptest.NewRequest(http.MethodGet, "/sessions/missing/native-labels", nil)
	req.Header.Set("X-Whatsmeow-Internal-Token", "synthetic-test-only")
	out := httptest.NewRecorder()
	r.ServeHTTP(out, req)
	if out.Code != http.StatusConflict {
		t.Fatalf("unconnected session returned %d", out.Code)
	}
}
