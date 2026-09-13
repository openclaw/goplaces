package places

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
)

const securityTestKey = "synthetic-api-key"

func TestClientRejectsCrossOriginRedirect(t *testing.T) {
	var received atomic.Int32
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		received.Add(1)
		_, _ = fmt.Fprint(w, `{"id":"unexpected"}`)
	}))
	defer destination.Close()
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, destination.URL+"/places/fixture?key="+securityTestKey, http.StatusFound)
	}))
	defer source.Close()
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: source.URL})
	_, err := client.Details(t.Context(), "fixture")
	if err == nil {
		t.Fatal("cross-origin redirect was followed")
	}
	if received.Load() != 0 {
		t.Fatal("redirect destination received a request")
	}
	if strings.Contains(err.Error(), securityTestKey) {
		t.Fatal("redirect error exposed the API key")
	}
	var urlErr *url.Error
	if !errors.As(err, &urlErr) {
		t.Fatalf("lost typed URL error: %T", err)
	}
}

func TestClientSameOriginRedirect(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Header.Get("X-Goog-Api-Key") != securityTestKey {
			t.Error("API key missing on same-origin request")
		}
		if r.URL.Path != "/final" {
			http.Redirect(w, r, "/final", http.StatusFound)
			return
		}
		_, _ = fmt.Fprint(w, `{"id":"fixture"}`)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: server.URL})
	place, err := client.Details(t.Context(), "fixture")
	if err != nil || place.PlaceID != "fixture" || calls.Load() != 2 {
		t.Fatalf("place=%+v calls=%d err=%v", place, calls.Load(), err)
	}
}

func TestClientPreservesCustomRedirectPolicy(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", "https://example.invalid/redirect")
		w.WriteHeader(http.StatusFound)
		_, _ = fmt.Fprint(w, `{"id":"stopped"}`)
	}))
	defer server.Close()
	var calls int
	httpClient := server.Client()
	httpClient.CheckRedirect = func(_ *http.Request, _ []*http.Request) error { calls++; return http.ErrUseLastResponse }
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: server.URL, HTTPClient: httpClient})
	for range 2 {
		place, err := client.Details(t.Context(), "fixture")
		if err != nil || place.PlaceID != "stopped" {
			t.Fatalf("place=%+v err=%v", place, err)
		}
	}
	if calls != 2 {
		t.Fatalf("custom policy calls=%d", calls)
	}
}

func TestClientPreservesRedirectLimit(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		http.Redirect(w, r, "/loop", http.StatusFound)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: server.URL})
	_, err := client.Details(t.Context(), "fixture")
	if err == nil || !strings.Contains(err.Error(), "stopped after 10 redirects") || calls.Load() != 10 {
		t.Fatalf("calls=%d err=%v", calls.Load(), err)
	}
}

func TestClientRedactsAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "rejected "+securityTestKey, http.StatusForbidden)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: server.URL})
	_, err := client.Details(t.Context(), "fixture")
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("expected APIError, got %v", err)
	}
	if strings.Contains(apiErr.Body, securityTestKey) || strings.Contains(err.Error(), securityTestKey) {
		t.Fatal("API error exposed the key")
	}
	if apiErr.StatusCode != http.StatusForbidden || apiErr.Body != "rejected [REDACTED]" {
		t.Fatalf("unexpected API error: %+v", apiErr)
	}
}

type securityTransport func(*http.Request) (*http.Response, error)

func (f securityTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestClientRedactsTransportErrorAndPreservesCause(t *testing.T) {
	cause := fmt.Errorf("rejected %s: %w", securityTestKey, context.Canceled)
	client := NewClient(Options{APIKey: securityTestKey, HTTPClient: &http.Client{Transport: securityTransport(func(*http.Request) (*http.Response, error) { return nil, cause })}})
	_, err := client.Details(t.Context(), "fixture")
	if err == nil || strings.Contains(err.Error(), securityTestKey) {
		t.Fatal("transport error exposed the key")
	}
	if !errors.Is(err, context.Canceled) || !errors.Is(err, cause) {
		t.Fatalf("lost error cause: %v", err)
	}
}

func TestClientRedactsInvalidURL(t *testing.T) {
	client := NewClient(Options{APIKey: securityTestKey, BaseURL: "http://%" + securityTestKey})
	_, err := client.Details(t.Context(), "fixture")
	if err == nil || strings.Contains(err.Error(), securityTestKey) {
		t.Fatal("invalid URL error exposed the key")
	}
}

func TestSameOrigin(t *testing.T) {
	for _, tt := range []struct {
		a, b string
		want bool
	}{
		{"https://example.com/a", "https://EXAMPLE.com:443/b", true},
		{"http://example.com/a", "http://example.com:80/b", true},
		{"https://example.com", "http://example.com", false},
		{"http://example.com:8000", "http://example.com:8001", false},
		{"https://example.com", "https://sub.example.com", false},
		{"custom://example.com", "custom://example.com", true},
	} {
		a, err := url.Parse(tt.a)
		if err != nil {
			t.Fatal(err)
		}
		b, err := url.Parse(tt.b)
		if err != nil {
			t.Fatal(err)
		}
		if sameOrigin(a, b) != tt.want {
			t.Errorf("sameOrigin(%s,%s) want %v", tt.a, tt.b, tt.want)
		}
	}
}
