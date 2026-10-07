package goplaces

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestTruncatedErrorResponsePreservesHTTPStatusAndReadCause(t *testing.T) {
	for _, status := range []int{http.StatusTooManyRequests, http.StatusServiceUnavailable, http.StatusUnauthorized} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Length", "100")
				w.WriteHeader(status)
				_, _ = w.Write([]byte(`{"error":"partial-test-key`))
			}))
			defer server.Close()
			client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
			_, err := client.Search(context.Background(), SearchRequest{Query: "coffee"})
			var apiErr *APIError
			if !errors.As(err, &apiErr) || apiErr.StatusCode != status {
				t.Errorf("status lost: %v", err)
			}
			if !errors.Is(err, io.ErrUnexpectedEOF) {
				t.Errorf("read cause lost: %v", err)
			}
			if strings.Contains(err.Error(), "test-key") {
				t.Errorf("error exposed API key: %v", err)
			}
		})
	}
}

func TestTruncatedSuccessResponseRetainsReadFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "100")
		_, _ = w.Write([]byte(`{"places":[]}`))
	}))
	defer server.Close()
	_, err := NewClient(Options{APIKey: "test-key", BaseURL: server.URL}).Search(context.Background(), SearchRequest{Query: "coffee"})
	var apiErr *APIError
	if errors.As(err, &apiErr) || !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("success read failure: %v", err)
	}
}
