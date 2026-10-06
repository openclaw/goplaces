package cli

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRunExplicitZeroLimitRejectsBeforeHTTP(t *testing.T) {
	for _, command := range [][]string{{"search", "coffee"}, {"autocomplete", "coffee"}, {"resolve", "Seattle"}, {"nearby", "--lat=1", "--lng=2", "--radius=3"}, {"route", "coffee", "--from=A", "--to=B"}} {
		t.Run(command[0], func(t *testing.T) {
			requests := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				requests++
				_, _ = w.Write([]byte(`{"places":[],"suggestions":[]}`))
			}))
			defer server.Close()
			args := append(append([]string{}, command...), "--limit=0", "--api-key=owned-test-key", "--base-url="+server.URL, "--routes-base-url="+server.URL)
			var stdout, stderr bytes.Buffer
			code := Run(args, &stdout, &stderr)
			if code != 2 || requests != 0 {
				t.Fatalf("exit=%d requests=%d stderr=%q", code, requests, stderr.String())
			}
			if !strings.Contains(stderr.String(), "limit") {
				t.Fatalf("missing limit diagnostic: %q", stderr.String())
			}
		})
	}
}

func TestRunLimitDefaultAndBounds(t *testing.T) {
	for _, tc := range []struct {
		name string
		flag []string
		want float64
	}{{"omitted", nil, 10}, {"minimum", []string{"--limit=1"}, 1}, {"maximum", []string{"--limit=20"}, 20}} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var request map[string]any
				if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
					t.Error(err)
				}
				if request["pageSize"] != tc.want {
					t.Errorf("page size %v, want %v", request["pageSize"], tc.want)
				}
				_, _ = w.Write([]byte(`{"places":[]}`))
			}))
			defer server.Close()
			args := append([]string{"search", "coffee", "--api-key=owned-test-key", "--base-url=" + server.URL}, tc.flag...)
			var stdout, stderr bytes.Buffer
			if code := Run(args, &stdout, &stderr); code != 0 {
				t.Fatalf("exit=%d stderr=%q", code, stderr.String())
			}
		})
	}
}
