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

func TestRunDirectionsJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Header.Get("X-Goog-Api-Key") != "test-key" {
			t.Fatalf("unexpected api key header: %s", r.Header.Get("X-Goog-Api-Key"))
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
  "routes":[{"description":"Main","legs":[{"distanceMeters":1000,"duration":"600s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"10 mins"}},"steps":[]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from", "A",
		"--to", "B",
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "\"mode\": \"WALKING\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestRunDirectionsWithDepartureTime(t *testing.T) {
	const departure = "2030-05-10T18:57:00-03:00"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		if payload["departureTime"] != departure {
			t.Fatalf("unexpected departure time: %#v", payload["departureTime"])
		}
		if payload["routingPreference"] != "TRAFFIC_AWARE" {
			t.Fatalf("unexpected routing preference: %#v", payload["routingPreference"])
		}
		_, _ = w.Write([]byte(`{
  "routes":[{"description":"Main","legs":[{"distanceMeters":26084,"duration":"2215s","localizedValues":{"distance":{"text":"26.1 km"},"duration":{"text":"37 mins"}},"steps":[]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from-lat=-22.8112259",
		"--from-lng=-43.2585631",
		"--to-lat=-22.9837626",
		"--to-lng=-43.2322048",
		"--mode", "drive",
		"--departure-time", departure,
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	var result goplaces.DirectionsResponse
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		t.Fatalf("decode output: %v (stdout=%s)", err, stdout.String())
	}
	if result.DepartureTime != departure || result.DurationSeconds != 2215 {
		t.Fatalf("unexpected result: %#v", result)
	}
}

func TestRunDirectionsAcceptsSpaceSeparatedNegativeCoordinates(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		assertNestedFloat(t, payload, -22.8112259, "origin", "location", "latLng", "latitude")
		assertNestedFloat(t, payload, -43.2585631, "origin", "location", "latLng", "longitude")
		assertNestedFloat(t, payload, -22.9837626, "destination", "location", "latLng", "latitude")
		assertNestedFloat(t, payload, -43.2322048, "destination", "location", "latLng", "longitude")
		_, _ = w.Write([]byte(`{
  "routes":[{"legs":[{"distanceMeters":26084,"duration":"2215s","localizedValues":{"distance":{"text":"26.1 km"},"duration":{"text":"37 mins"}},"steps":[]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from-lat", "-22.8112259",
		"--from-lng", "-43.2585631",
		"--to-lat", "-22.9837626",
		"--to-lng", "-43.2322048",
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestRunDirectionsWithTransitArrivalTime(t *testing.T) {
	const arrival = "2030-05-10T19:57:00-03:00"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		if payload["travelMode"] != directionsModeTransitAPI {
			t.Fatalf("unexpected travel mode: %#v", payload["travelMode"])
		}
		if payload["arrivalTime"] != arrival {
			t.Fatalf("unexpected arrival time: %#v", payload["arrivalTime"])
		}
		_, _ = w.Write([]byte(`{
  "routes":[{"description":"Main","legs":[{"distanceMeters":26084,"duration":"2215s","localizedValues":{"distance":{"text":"26.1 km"},"duration":{"text":"37 mins"}},"steps":[]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from", "Pike Place Market",
		"--to", "Space Needle",
		"--mode", "transit",
		"--arrival-time", arrival,
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	var result goplaces.DirectionsResponse
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		t.Fatalf("decode output: %v (stdout=%s)", err, stdout.String())
	}
	if result.ArrivalTime != arrival || result.DurationSeconds != 2215 {
		t.Fatalf("unexpected result: %#v", result)
	}
}

func TestRunDirectionsCompareJSON(t *testing.T) {
	seenModes := make(map[string]int)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		mode, _ := payload["travelMode"].(string)
		seenModes[mode]++
		responseBody := `{
  "routes":[{"description":"Main","legs":[{"distanceMeters":1000,"duration":"600s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"10 mins"}},"steps":[]}]}]
}`
		if mode == directionsModeDriveAPI {
			responseBody = `{
  "routes":[{"description":"Main","legs":[{"distanceMeters":1000,"duration":"240s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"4 mins"}},"steps":[]}]}]
}`
		}
		_, _ = w.Write([]byte(responseBody))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from", "A",
		"--to", "B",
		"--compare", "drive",
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	var results []goplaces.DirectionsResponse
	if err := json.Unmarshal(stdout.Bytes(), &results); err != nil {
		t.Fatalf("decode output: %v (stdout=%s)", err, stdout.String())
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 directions results, got %d", len(results))
	}
	if results[0].Mode != "WALKING" || results[1].Mode != "DRIVING" {
		t.Fatalf("unexpected mode order: %#v", results)
	}
	if seenModes[directionsModeWalkAPI] != 1 || seenModes[directionsModeDriveAPI] != 1 {
		t.Fatalf("expected both modes requested once, got: %#v", seenModes)
	}
}

func TestRunDirectionsCompareDriveWithAvoidFlags(t *testing.T) {
	seenModifiers := make(map[string]map[string]any)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		mode, _ := payload["travelMode"].(string)
		if modifiers, ok := payload["routeModifiers"].(map[string]any); ok {
			seenModifiers[mode] = modifiers
		} else {
			seenModifiers[mode] = nil
		}
		responseBody := `{
  "routes":[{"description":"Main","legs":[{"distanceMeters":1000,"duration":"600s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"10 mins"}},"steps":[]}]}]
}`
		if mode == directionsModeDriveAPI {
			responseBody = `{
  "routes":[{"description":"Main","legs":[{"distanceMeters":1000,"duration":"240s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"4 mins"}},"steps":[]}]}]
}`
		}
		_, _ = w.Write([]byte(responseBody))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from", "A",
		"--to", "B",
		"--compare", "drive",
		"--avoid-tolls",
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if seenModifiers[directionsModeWalkAPI] != nil {
		t.Fatalf("walking request should not include routeModifiers: %#v", seenModifiers[directionsModeWalkAPI])
	}
	driveModifiers := seenModifiers[directionsModeDriveAPI]
	if driveModifiers["avoidTolls"] != true {
		t.Fatalf("driving comparison missing avoidTolls: %#v", driveModifiers)
	}
}

func TestRunDirectionsArrivalTimeCompareRejectsBeforeRequest(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from", "A",
		"--to", "B",
		"--mode", "transit",
		"--arrival-time", "2030-05-10T19:57:00-03:00",
		"--compare", "drive",
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 2 {
		t.Fatalf("expected validation exit code 2, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if requests != 0 {
		t.Fatalf("expected no requests, got %d", requests)
	}
}

func TestRunDirectionsHumanCompareWithSteps(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		mode, _ := payload["travelMode"].(string)
		if mode == "" {
			t.Fatalf("missing mode")
		}
		_, _ = w.Write([]byte(`{
  "routes":[{"description":"Main","legs":[{"distanceMeters":1000,"duration":"600s","localizedValues":{"distance":{"text":"1 km"},"duration":{"text":"10 mins"}},"steps":[{"distanceMeters":200,"staticDuration":"120s","localizedValues":{"distance":{"text":"0.2 km"},"staticDuration":{"text":"2 mins"}},"navigationInstruction":{"instructions":"Head north"}}]}]}]
}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"directions",
		"--from", "A",
		"--to", "B",
		"--compare", "drive",
		"--steps",
		"--api-key", "test-key",
		"--directions-base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "Directions (WALKING)") || !strings.Contains(stdout.String(), "Directions (DRIVING)") {
		t.Fatalf("missing compare output: %s", stdout.String())
	}
	if !strings.Contains(stdout.String(), "Head north") {
		t.Fatalf("missing steps output: %s", stdout.String())
	}
}

func TestRunDirectionsValidationErrors(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{
			name: "invalid mode",
			args: []string{"directions", "--from", "A", "--to", "B", "--mode", "plane", "--api-key", "x"},
		},
		{
			name: "invalid compare",
			args: []string{"directions", "--from", "A", "--to", "B", "--compare", "plane", "--api-key", "x"},
		},
		{
			name: "same compare mode",
			args: []string{"directions", "--from", "A", "--to", "B", "--mode", "walk", "--compare", directionsModeWalkingAPI, "--api-key", "x"},
		},
		{
			name: "partial from latlng",
			args: []string{"directions", "--from-lat", "1", "--to", "B", "--api-key", "x"},
		},
		{
			name: "partial to latlng",
			args: []string{"directions", "--from", "A", "--to-lng", "2", "--api-key", "x"},
		},
		{
			name: "departure and arrival",
			args: []string{"directions", "--from", "A", "--to", "B", "--departure-time", "2030-05-10T18:57:00-03:00", "--arrival-time", "2030-05-10T19:57:00-03:00", "--api-key", "x"},
		},
		{
			name: "invalid departure time",
			args: []string{"directions", "--from", "A", "--to", "B", "--departure-time", "tomorrow", "--api-key", "x"},
		},
		{
			name: "arrival requires transit",
			args: []string{"directions", "--from", "A", "--to", "B", "--mode", "drive", "--arrival-time", "2030-05-10T19:57:00-03:00", "--api-key", "x"},
		},
	}

	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			var stdout bytes.Buffer
			var stderr bytes.Buffer
			exitCode := Run(testCase.args, &stdout, &stderr)
			if exitCode != 2 {
				t.Fatalf("expected validation exit code 2, got %d (stdout=%s stderr=%s)", exitCode, stdout.String(), stderr.String())
			}
		})
	}
}
