package cli

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRunRouteJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case routesComputePath:
			_, _ = w.Write([]byte("{\"routes\":[{\"polyline\":{\"encodedPolyline\":\"_p~iF~ps|U_ulLnnqC_mqNvxq`@\"}}]}"))
		case placesSearchPath:
			_, _ = w.Write([]byte(`{"places":[{"id":"abc","displayName":{"text":"Cafe"}}]}`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"route",
		"coffee",
		"--from", "A",
		"--to", "B",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--routes-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "\"waypoints\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunRouteHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case routesComputePath:
			_, _ = w.Write([]byte("{\"routes\":[{\"polyline\":{\"encodedPolyline\":\"_p~iF~ps|U_ulLnnqC_mqNvxq`@\"}}]}"))
		case placesSearchPath:
			_, _ = w.Write([]byte(`{"places":[{"id":"abc","displayName":{"text":"Cafe"}}]}`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"route",
		"coffee",
		"--from", "A",
		"--to", "B",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--routes-base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "Route waypoints") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestRunRouteValidationError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"route",
		"coffee",
		"--from", "A",
		"--to", "B",
		"--mode", "FLY",
		"--api-key", "test-key",
	}, &stdout, &stderr)

	if exitCode != 2 {
		t.Fatalf("expected validation error exit code 2, got %d", exitCode)
	}
}

func TestRunRouteMissingFrom(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"route",
		"coffee",
		"--to", "B",
		"--api-key", "test-key",
	}, &stdout, &stderr)

	if exitCode != 2 {
		t.Fatalf("expected validation error exit code 2, got %d", exitCode)
	}
}

func TestRunRouteAcceptsRadiusAlias(t *testing.T) {
	var searchRadius float64
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case routesComputePath:
			_, _ = w.Write([]byte(`{"routes": [{"polyline": {"encodedPolyline": "_p~iF~ps|U"}}]}`))
		case placesSearchPath:
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Errorf("decode request: %v", err)
				return
			}
			if bias, ok := payload["locationBias"].(map[string]any); ok {
				if circle, ok := bias["circle"].(map[string]any); ok {
					if radius, ok := circle["radius"].(float64); ok {
						searchRadius = radius
					}
				}
			}
			_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
		default:
			t.Errorf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	var stdout, stderr bytes.Buffer
	exitCode := Run([]string{
		"route", "coffee",
		"--from", "A",
		"--to", "B",
		"--radius", "2500",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--routes-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stderr=%s)", exitCode, stderr.String())
	}
	if searchRadius != 2500 {
		t.Fatalf("expected radius 2500 from --radius alias, got %v", searchRadius)
	}
}
