package cli

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRunSearchWithEqualsFlags(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"places": [{"id": "abc"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"search",
		"coffee",
		"--api-key=test-key",
		"--base-url=" + server.URL,
		"--json",
		"--min-rating=4.2",
		"--limit=5",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
	}
}

func TestRunNearbyWithEqualsFlags(t *testing.T) {
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
		"--lat=1",
		"--lng=2",
		"--radius-m=3",
		"--type=cafe",
		"--exclude-type=bar",
		"--limit=5",
		"--api-key=test-key",
		"--base-url=" + server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
	}
}

func TestRunRouteWithEqualsFlags(t *testing.T) {
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
		"--from=A",
		"--to=B",
		"--api-key=test-key",
		"--base-url=" + server.URL,
		"--routes-base-url=" + server.URL,
		"--mode=WALK",
		"--radius-m=1200",
		"--max-waypoints=3",
		"--limit=2",
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	if !strings.Contains(stdout.String(), "\"waypoints\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunDirectionsWithEqualsFlags(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		if payload["travelMode"] != directionsModeWalkAPI {
			t.Fatalf("unexpected mode: %#v", payload["travelMode"])
		}
		if payload["units"] != "METRIC" {
			t.Fatalf("unexpected units: %#v", payload["units"])
		}
		_, _ = w.Write([]byte(`{
  "routes":[{"legs":[{"distanceMeters":1000,"duration":"600s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"10 mins"}},"steps":[]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from=A",
		"--to=B",
		"--api-key=test-key",
		"--directions-base-url=" + server.URL,
		"--mode=walk",
		"--units=metric",
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	if !strings.Contains(stdout.String(), "\"mode\": \"WALKING\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunDirectionsWithAvoidFlags(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		if payload["travelMode"] != directionsModeDriveAPI {
			t.Fatalf("unexpected mode: %#v", payload["travelMode"])
		}
		modifiers, ok := payload["routeModifiers"].(map[string]any)
		if !ok {
			t.Fatalf("missing routeModifiers: %#v", payload)
		}
		if modifiers["avoidTolls"] != true || modifiers["avoidHighways"] != true || modifiers["avoidFerries"] != true {
			t.Fatalf("unexpected routeModifiers: %#v", modifiers)
		}
		_, _ = w.Write([]byte(`{
  "routes":[{"legs":[{"distanceMeters":1000,"duration":"600s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"10 mins"}},"steps":[]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from=A",
		"--to=B",
		"--api-key=test-key",
		"--directions-base-url=" + server.URL,
		"--mode=drive",
		"--avoid-tolls",
		"--avoid-highways",
		"--avoid-ferries",
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
	if !strings.Contains(stdout.String(), "\"mode\": \"DRIVING\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}
