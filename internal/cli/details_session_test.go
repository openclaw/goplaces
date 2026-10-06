package cli

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRunDetailsSessionToken(t *testing.T) {
	const token = "7c9a1efa-0e97-4e8d-af1e-fae4f738467b"
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.URL.Query().Get("sessionToken") != token {
			t.Errorf("missing matching token: %s", r.URL.RawQuery)
		}
		if r.Method != http.MethodGet || r.URL.Path != "/places/selected" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"id":"selected"}`))
	}))
	defer server.Close()
	var out, errOut bytes.Buffer
	code := Run([]string{"details", "selected", "--session-token", token, "--api-key", "test-key", "--base-url", server.URL, "--json"}, &out, &errOut)
	if code != 0 || calls != 1 {
		t.Fatalf("code=%d calls=%d stderr=%s", code, calls, errOut.String())
	}
}
