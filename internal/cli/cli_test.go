package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/steipete/goplaces"
)

const (
	placesSearchPath  = "/places:searchText"
	placesNearbyPath  = "/places:searchNearby"
	routesComputePath = "/directions/v2:computeRoutes"
	directionsPath    = "/maps/api/directions/json"
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
	// JSON output should be an array, not an object with "results" key
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
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
	// JSON output should be an array, not an object with "results" key
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
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
	// JSON output should be an array, not an object with "results" key
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
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
		query := r.URL.Query()
		if query.Get("origin") != "A" {
			t.Fatalf("unexpected origin: %s", query.Get("origin"))
		}
		if query.Get("destination") != "B" {
			t.Fatalf("unexpected destination: %s", query.Get("destination"))
		}
		if query.Get("mode") != "walking" {
			t.Fatalf("unexpected mode: %s", query.Get("mode"))
		}
		if query.Get("units") != "metric" {
			t.Fatalf("unexpected units: %s", query.Get("units"))
		}
		if query.Get("key") != "test-key" {
			t.Fatalf("unexpected key: %s", query.Get("key"))
		}
		_, _ = w.Write([]byte(`{
  "status":"OK",
  "routes":[{"summary":"Main","legs":[{"distance":{"text":"1 km","value":1000},"duration":{"text":"10 mins","value":600},"start_address":"A","end_address":"B","steps":[]}]}]
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
		"--directions-base-url", server.URL + directionsPath,
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

func TestRunDirectionsCompareJSON(t *testing.T) {
	seenModes := make(map[string]int)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		mode := r.URL.Query().Get("mode")
		seenModes[mode]++
		duration := "10 mins"
		seconds := 600
		if mode == "driving" {
			duration = "4 mins"
			seconds = 240
		}
		_, _ = w.Write([]byte(`{
  "status":"OK",
  "routes":[{"summary":"Main","legs":[{"distance":{"text":"1 km","value":1000},"duration":{"text":"` + duration + `","value":` + fmt.Sprintf("%d", seconds) + `},"start_address":"A","end_address":"B","steps":[]}]}]
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
		"--api-key", "test-key",
		"--directions-base-url", server.URL + directionsPath,
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
	if seenModes["walking"] != 1 || seenModes["driving"] != 1 {
		t.Fatalf("expected both modes requested once, got: %#v", seenModes)
	}
}

func TestRunDirectionsHumanCompareWithSteps(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != directionsPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		mode := r.URL.Query().Get("mode")
		if mode == "" {
			t.Fatalf("missing mode")
		}
		_, _ = w.Write([]byte(`{
  "status":"OK",
  "routes":[{"summary":"Main","legs":[{"distance":{"text":"1 km","value":1000},"duration":{"text":"10 mins","value":600},"start_address":"A","end_address":"B","steps":[{"html_instructions":"Head <b>north</b>","distance":{"text":"0.2 km","value":200},"duration":{"text":"2 mins","value":120}}]}]}]
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
		"--directions-base-url", server.URL + directionsPath,
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
			args: []string{"directions", "--from", "A", "--to", "B", "--mode", "walk", "--compare", "walking", "--api-key", "x"},
		},
		{
			name: "partial from latlng",
			args: []string{"directions", "--from-lat", "1", "--to", "B", "--api-key", "x"},
		},
		{
			name: "partial to latlng",
			args: []string{"directions", "--from", "A", "--to-lng", "2", "--api-key", "x"},
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
		"walk":      "walking",
		"walking":   "walking",
		"drive":     "driving",
		"driving":   "driving",
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
	if strings.TrimSpace(stdout.String()) != Version {
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
	// JSON output should be an array
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
	}
	// next_page_token should be written to stderr
	if !strings.Contains(stderr.String(), "next_page_token: token123") {
		t.Fatalf("expected next_page_token in stderr, got: %s", stderr.String())
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
	// JSON output should be an array
	if !strings.HasPrefix(strings.TrimSpace(stdout.String()), "[") {
		t.Fatalf("expected JSON array output, got: %s", stdout.String())
	}
	// next_page_token should be written to stderr
	if !strings.Contains(stderr.String(), "next_page_token: nearby-token") {
		t.Fatalf("expected next_page_token in stderr, got: %s", stderr.String())
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
