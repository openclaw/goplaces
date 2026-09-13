package cli

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRunAutocompleteJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/places:autocomplete" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"suggestions": [{"placePrediction": {"placeId": "abc"}}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"autocomplete",
		"coffee",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	// JSON output should be an array, not an object with "suggestions" key
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
	}
}

func TestRunAutocompleteHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"suggestions": [{"placePrediction": {"placeId": "abc", "text": {"text": "Cafe"}}}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"autocomplete",
		"coffee",
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

func TestRunAutocompleteAcceptsSpaceSeparatedNegativeLongitude(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/places:autocomplete" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		assertNestedFloat(t, payload, 40.7411, "locationBias", "circle", "center", "latitude")
		assertNestedFloat(t, payload, -73.9897, "locationBias", "circle", "center", "longitude")
		assertNestedFloat(t, payload, 1500, "locationBias", "circle", "radius")
		_, _ = w.Write([]byte(`{"suggestions": [{"placePrediction": {"placeId": "abc"}}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"autocomplete",
		"pizza",
		"--lat", "40.7411",
		"--lng", "-73.9897",
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
