package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/steipete/goplaces"
)

const (
	placesSearchPath         = "/places:searchText"
	placesNearbyPath         = "/places:searchNearby"
	routesComputePath        = "/directions/v2:computeRoutes"
	directionsPath           = routesComputePath
	directionsModeWalkAPI    = "WALK"
	directionsModeDriveAPI   = "DRIVE"
	directionsModeTransitAPI = "TRANSIT"
	directionsModeWalkingAPI = "walking"
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

func TestNormalizeDirectionsMode(t *testing.T) {
	cases := map[string]string{
		"walk":      directionsModeWalkingAPI,
		"walking":   directionsModeWalkingAPI,
		"drive":     directionsModeDriving,
		"driving":   directionsModeDriving,
		"bike":      "bicycling",
		"bicycle":   "bicycling",
		"bicycling": "bicycling",
		"transit":   "transit",
		"plane":     "",
	}
	for input, want := range cases {
		if got := normalizeDirectionsMode(input); got != want {
			t.Fatalf("normalizeDirectionsMode(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestRunDetailsJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/places/place-1" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"id": "place-1"}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"details",
		"place-1",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "\"place_id\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunDetailsWithReviews(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.Header.Get("X-Goog-FieldMask"), "reviews") {
			t.Fatalf("expected reviews in field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		_, _ = w.Write([]byte(`{"id": "place-1", "reviews": [{"name": "reviews/1"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"details",
		"place-1",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--reviews",
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "\"reviews\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunDetailsWithPhotos(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.Header.Get("X-Goog-FieldMask"), "photos") {
			t.Fatalf("expected photos in field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		_, _ = w.Write([]byte(`{"id": "place-1", "photos": [{"name": "places/place-1/photos/photo-1"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"details",
		"place-1",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--photos",
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "\"photos\"") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

func TestRunDetailsHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"id": "place-2", "displayName": {"text": "Park"}}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"details",
		"place-2",
		"--api-key", "test-key",
		"--base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "Park") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
}

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

func TestRunResolveHuman(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != placesSearchPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"places": [{"id": "loc-1", "displayName": {"text": "Downtown"}}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"resolve",
		"Downtown",
		"--api-key", "test-key",
		"--base-url", server.URL,
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "Downtown") {
		t.Fatalf("unexpected stdout: %s", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %s", stderr.String())
	}
}

func TestRunResolveJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"places": [{"id": "loc-2"}]}`))
	}))
	defer server.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{
		"resolve",
		"Downtown",
		"--api-key", "test-key",
		"--base-url", server.URL,
		"--json",
	}, &stdout, &stderr)

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	// JSON output should be an array, not an object with "results" key
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
	}
}

func TestRunVersion(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"--version"}, &stdout, &stderr)
	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if strings.TrimSpace(stdout.String()) != devVersion {
		t.Fatalf("unexpected version: %s", stdout.String())
	}
}

func TestRunMissingCommand(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{}, &stdout, &stderr)
	if exitCode == 0 {
		t.Fatalf("expected non-zero exit code")
	}
}

func TestRunParseError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"search", "--api-key", "x"}, &stdout, &stderr)
	if exitCode == 0 {
		t.Fatalf("expected parse error")
	}
}

func TestRunLocationBiasError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"search", "coffee", "--lat", "1", "--api-key", "x"}, &stdout, &stderr)
	if exitCode != 2 {
		t.Fatalf("expected validation error exit code 2, got %d", exitCode)
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

func TestRunHelp(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run([]string{"--help"}, &stdout, &stderr)
	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if stdout.Len() == 0 {
		t.Fatalf("expected help output")
	}
}

func TestVersionFlagIsBool(t *testing.T) {
	var flag VersionFlag
	if !flag.IsBool() {
		t.Fatalf("expected IsBool true")
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

func TestWriteJSONError(t *testing.T) {
	err := writeJSON(&bytes.Buffer{}, map[string]any{"bad": func() {}})
	if err == nil {
		t.Fatalf("expected json error")
	}
}

func TestWriteJSON(t *testing.T) {
	var out bytes.Buffer
	if err := writeJSON(&out, map[string]string{"ok": "true"}); err != nil {
		t.Fatalf("writeJSON error: %v", err)
	}
	if !strings.Contains(out.String(), "\"ok\"") {
		t.Fatalf("unexpected json output: %s", out.String())
	}
}

func TestHandleError(t *testing.T) {
	if code := handleError(&bytes.Buffer{}, nil); code != 0 {
		t.Fatalf("expected 0")
	}
	if code := handleError(&bytes.Buffer{}, goplaces.ValidationError{Field: "x", Message: "bad"}); code != 2 {
		t.Fatalf("expected validation exit 2")
	}
	if code := handleError(&bytes.Buffer{}, goplaces.ErrMissingAPIKey); code != 2 {
		t.Fatalf("expected missing api key exit 2")
	}
	if code := handleError(&bytes.Buffer{}, errors.New("boom")); code != 1 {
		t.Fatalf("expected generic exit 1")
	}
}

func assertNestedFloat(t *testing.T, payload map[string]any, want float64, path ...string) {
	t.Helper()

	var current any = payload
	for _, key := range path {
		node, ok := current.(map[string]any)
		if !ok {
			t.Fatalf("payload path %v reached non-object %#v", path, current)
		}
		current, ok = node[key]
		if !ok {
			t.Fatalf("payload missing path %v at %q", path, key)
		}
	}

	got, ok := current.(float64)
	if !ok {
		t.Fatalf("payload path %v = %#v, want float64", path, current)
	}
	if math.Abs(got-want) > 1e-9 {
		t.Fatalf("payload path %v = %v, want %v", path, got, want)
	}
}
