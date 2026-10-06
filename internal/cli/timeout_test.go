package cli

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRunNonPositiveTimeoutRejectsBeforeHTTP(t *testing.T) {
	for _, timeout := range []string{"0s", "-1s"} {
		t.Run(timeout, func(t *testing.T) {
			requests := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { requests++; _, _ = w.Write([]byte(`{"places":[]}`)) }))
			defer server.Close()
			var stdout, stderr bytes.Buffer
			code := Run([]string{"search", "coffee", "--timeout=" + timeout, "--api-key=owned-test-key", "--base-url=" + server.URL}, &stdout, &stderr)
			if code != 2 || requests != 0 {
				t.Fatalf("exit=%d requests=%d stderr=%q", code, requests, stderr.String())
			}
			if !strings.Contains(stderr.String(), "timeout") {
				t.Fatalf("missing timeout diagnostic: %q", stderr.String())
			}
		})
	}
}

func TestRunPositiveTimeoutStillBoundsHTTP(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(50 * time.Millisecond)
		_, _ = w.Write([]byte(`{"places":[]}`))
	}))
	defer server.Close()
	var stdout, stderr bytes.Buffer
	code := Run([]string{"search", "coffee", "--timeout=5ms", "--api-key=owned-test-key", "--base-url=" + server.URL}, &stdout, &stderr)
	if code != 1 || !strings.Contains(stderr.String(), "deadline exceeded") {
		t.Fatalf("exit=%d stderr=%q", code, stderr.String())
	}
}
