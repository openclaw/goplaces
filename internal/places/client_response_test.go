package places

import (
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestClientResponseSizeBoundary(t *testing.T) {
	const limit = 1 << 20
	for _, tt := range []struct {
		name    string
		size    int
		wantErr bool
	}{
		{"below limit", limit - 1, false},
		{"at limit", limit, false},
		{"over limit", limit + 1, true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			prefix := `{"id":"fixture"}`
			body := prefix + strings.Repeat(" ", tt.size-len(prefix))
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				// Flush headers so the check also covers unknown content lengths.
				w.(http.Flusher).Flush()
				_, _ = fmt.Fprint(w, body)
			}))
			defer server.Close()
			client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
			place, err := client.Details(t.Context(), "fixture")
			if tt.wantErr {
				if err == nil || !strings.Contains(err.Error(), "response exceeds") || place.PlaceID != "" {
					t.Fatalf("expected size error without a result, got place=%+v err=%v", place, err)
				}
				return
			}
			if err != nil || place.PlaceID != "fixture" {
				t.Fatalf("place=%+v err=%v", place, err)
			}
		})
	}
}

func TestClientRejectsTrailingDataBeyondResponseLimit(t *testing.T) {
	body := `{"id":"fixture"}`
	body += strings.Repeat(" ", (1<<20)-len(body)) + `{"id":"trailing"}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, body)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	if place, err := client.Details(t.Context(), "fixture"); err == nil {
		t.Fatalf("accepted a truncated response: %+v", place)
	}
}

func TestClientRejectsNonSuccessStatus(t *testing.T) {
	for _, statusCode := range []int{http.StatusMultipleChoices, http.StatusFound, http.StatusNotModified} {
		t.Run(http.StatusText(statusCode), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(statusCode)
				_, _ = fmt.Fprint(w, `{"id":"unexpected"}`)
			}))
			defer server.Close()
			client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
			place, err := client.Details(t.Context(), "fixture")
			var apiErr *APIError
			if !errors.As(err, &apiErr) || apiErr.StatusCode != statusCode || place.PlaceID != "" {
				t.Fatalf("expected APIError for %d without a result, got place=%+v err=%v", statusCode, place, err)
			}
		})
	}
}

func TestClientOversizedAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = fmt.Fprint(w, strings.Repeat("x", 1<<20)+securityTestKey)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: server.URL})
	_, err := client.Details(t.Context(), "fixture")
	var apiErr *APIError
	if !errors.As(err, &apiErr) || apiErr.StatusCode != http.StatusBadGateway {
		t.Fatalf("expected APIError with upstream status, got %v", err)
	}
	if !strings.Contains(apiErr.Body, "response exceeds") || len(apiErr.Body) > 100 {
		t.Fatal("expected a concise size diagnostic instead of a truncated upstream body")
	}
}
