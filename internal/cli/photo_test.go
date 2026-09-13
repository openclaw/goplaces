package cli

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRunPhotoJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/places/place-1/photos/photo-1/media" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"photoUri": "https://example.com/photo.jpg"}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"photo",
		"places/place-1/photos/photo-1",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--max-width", "800",
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "\"photo_uri\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunPhotoHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"photoUri": "https://example.com/photo.jpg"}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"photo",
		"places/place-1/photos/photo-1",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--max-width", "800",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "photo.jpg") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}
