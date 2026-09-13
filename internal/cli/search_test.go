package cli

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/steipete/goplaces"
)

func TestRunSearchJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesSearchPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	var response goplaces.SearchResponse
	if err := json.Unmarshal(stdout.Bytes(), &response); err != nil {
		t.Fatalf("decode json: %v", err)
	}
	if len(response.Results) != 1 || response.Results[0].PlaceID != "abc" {
		t.Fatalf("unexpected results: %#v", response.Results)
	}
}

func TestRunSearchHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"places": [{"id": "abc", "displayName": {"text": "Cafe"}}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--api-key", "test-key",
		"--base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "Cafe") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunSearchWithFilters(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if payload["includedType"] != "cafe" {
			t.Fatalf("unexpected includedType: %#v", payload["includedType"])
		}
		if payload["languageCode"] != "en" {
			t.Fatalf("unexpected languageCode: %#v", payload["languageCode"])
		}
		if payload["regionCode"] != "US" {
			t.Fatalf("unexpected regionCode: %#v", payload["regionCode"])
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
		"--keyword", "best",
		"--type", "cafe",
		"--open-now=true",
		"--min-rating", "4.2",
		"--price-level", "1",
		"--lat", "40.0",
		"--lng=-70.0",
		"--radius-m", "500",
		"--language", "en",
		"--region", "US",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	var response goplaces.SearchResponse
	if err := json.Unmarshal(stdout.Bytes(), &response); err != nil {
		t.Fatalf("decode json: %v", err)
	}
	if len(response.Results) != 1 || response.Results[0].PlaceID != "abc" {
		t.Fatalf("unexpected results: %#v", response.Results)
	}
}

func TestRunSearchAcceptsSpaceSeparatedNegativeLongitude(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesSearchPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		assertNestedFloat(t, payload, 42.3467, "locationBias", "circle", "center", "latitude")
		assertNestedFloat(t, payload, -71.0972, "locationBias", "circle", "center", "longitude")
		assertNestedFloat(t, payload, 1500, "locationBias", "circle", "radius")
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--lat", "42.3467",
		"--lng", "-71.0972",
		"--radius-m", "1500",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestRunSearchSanitizesAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte("bad \x1b]52;c;clipboard\x07\rname\u202E"))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--api-key", "test-key",
		"--base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 1 {
		t.Fatalf("expected exit code 1, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stdout.Len() != 0 {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
	output := stderr.String()
	for _, unsafe := range []string{"\x1b", "\x07", "\r", "\u202E"} {
		if strings.Contains(output, unsafe) {
			t.Fatalf("stderr contains unsafe terminal text %q: %q", unsafe, output)
		}
	}
	if !strings.Contains(output, "goplaces: api error (400): bad ]52;c;clipboard name") {
		t.Fatalf("missing sanitized error text: %q", output)
	}
}

func TestRunSearchJSONWithNextPageToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesSearchPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}], "nextPageToken": "token123"}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	var response goplaces.SearchResponse
	if err := json.Unmarshal(stdout.Bytes(), &response); err != nil {
		t.Fatalf("decode json: %v", err)
	}
	if response.NextPageToken != "token123" {
		t.Fatalf("expected next_page_token in JSON, got: %#v", response)
	}
	if len(response.Results) != 1 || response.Results[0].PlaceID != "abc" {
		t.Fatalf("unexpected results: %#v", response.Results)
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected empty stderr, got: %s", stderr.String())
	}
}
