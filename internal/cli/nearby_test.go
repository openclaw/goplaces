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

func TestRunNearbyJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesNearbyPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"nearby",
		"--lat", "1",
		"--lng", "2",
		"--radius-m", "3",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	var response goplaces.NearbySearchResponse
	if err := json.Unmarshal(stdout.Bytes(), &response); err != nil {
		t.Fatalf("decode json: %v", err)
	}
	if len(response.Results) != 1 || response.Results[0].PlaceID != "abc" {
		t.Fatalf("unexpected results: %#v", response.Results)
	}
}

func TestRunNearbyAcceptsSpaceSeparatedNegativeLongitude(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesNearbyPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		assertNestedFloat(t, payload, 47.6062, "locationRestriction", "circle", "center", "latitude")
		assertNestedFloat(t, payload, -122.3321, "locationRestriction", "circle", "center", "longitude")
		assertNestedFloat(t, payload, 1500, "locationRestriction", "circle", "radius")
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"nearby",
		"--lat", "47.6062",
		"--lng", "-122.3321",
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

func TestRunNearbyHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"places": [{"id": "abc", "displayName": {"text": "Cafe"}}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"nearby",
		"--lat", "1",
		"--lng", "2",
		"--radius-m", "3",
		"--api-key", "test-key",
		"--base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "Cafe") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestRunNearbyLocationRestrictionError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"nearby", "--lat", "1", "--api-key", "x"}, &stdout, &stderr)
	if exitCode != 2 {
		t.Fatalf("expected validation error exit code 2, got %d", exitCode)
	}
}

func TestRunNearbyJSONWithNextPageToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesNearbyPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}], "nextPageToken": "nearby-token"}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"nearby",
		"--lat", "1",
		"--lng", "2",
		"--radius-m", "3",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	var response goplaces.NearbySearchResponse
	if err := json.Unmarshal(stdout.Bytes(), &response); err != nil {
		t.Fatalf("decode json: %v", err)
	}
	if response.NextPageToken != "nearby-token" {
		t.Fatalf("expected next_page_token in JSON, got: %#v", response)
	}
	if len(response.Results) != 1 || response.Results[0].PlaceID != "abc" {
		t.Fatalf("unexpected results: %#v", response.Results)
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected empty stderr, got: %s", stderr.String())
	}
}
