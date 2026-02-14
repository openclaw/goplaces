package goplaces

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDirectionsRequestPlaceID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		if query.Get("origin") != "place_id:from" {
			t.Fatalf("unexpected origin: %s", query.Get("origin"))
		}
		if query.Get("destination") != "place_id:to" {
			t.Fatalf("unexpected destination: %s", query.Get("destination"))
		}
		if query.Get("mode") != directionsModeWalk {
			t.Fatalf("unexpected mode: %s", query.Get("mode"))
		}
		if query.Get("units") != directionsUnitsMetric {
			t.Fatalf("unexpected units: %s", query.Get("units"))
		}
		if query.Get("key") != "test-key" {
			t.Fatalf("unexpected key: %s", query.Get("key"))
		}
		_, _ = w.Write([]byte(`{
			"status": "OK",
			"routes": [{
				"summary": "Main",
				"warnings": ["test"],
				"legs": [{
					"distance": {"text": "1 km", "value": 1000},
					"duration": {"text": "10 mins", "value": 600},
					"start_address": "Start",
					"end_address": "End",
					"steps": [{
						"html_instructions": "Head <b>north</b>",
						"distance": {"text": "0.2 km", "value": 200},
						"duration": {"text": "2 mins", "value": 120},
						"travel_mode": "WALKING"
					}]
				}]
			}]
		}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	response, err := client.Directions(context.Background(), DirectionsRequest{
		FromPlaceID: "from",
		ToPlaceID:   "to",
		Mode:        "walk",
	})
	if err != nil {
		t.Fatalf("Directions error: %v", err)
	}
	if response.DistanceMeters != 1000 {
		t.Fatalf("unexpected distance: %d", response.DistanceMeters)
	}
	if len(response.Steps) != 1 || response.Steps[0].Instruction != "Head north" {
		t.Fatalf("unexpected steps: %#v", response.Steps)
	}
	if response.Mode != "WALKING" {
		t.Fatalf("unexpected mode: %s", response.Mode)
	}
}

func TestDirectionsModeValidation(t *testing.T) {
	if normalizeDirectionsMode("plane") != "" {
		t.Fatalf("expected empty normalization")
	}
	req := DirectionsRequest{From: "A", To: "B", Mode: "plane"}
	if err := validateDirectionsRequest(applyDirectionsDefaults(req)); err == nil {
		t.Fatalf("expected validation error")
	}
}

func TestDirectionsUnitsValidation(t *testing.T) {
	req := DirectionsRequest{From: "A", To: "B", Units: "fathoms"}
	if err := validateDirectionsRequest(applyDirectionsDefaults(req)); err == nil {
		t.Fatalf("expected validation error")
	}
}

func TestDirectionsLocationValidation(t *testing.T) {
	req := DirectionsRequest{FromPlaceID: "a", From: "b", To: "c"}
	if err := validateDirectionsRequest(applyDirectionsDefaults(req)); err == nil {
		t.Fatalf("expected validation error for multiple origin inputs")
	}
}

func TestNormalizeDirectionsModeAliases(t *testing.T) {
	cases := map[string]string{
		"walk":      "walking",
		"walking":   "walking",
		"drive":     "driving",
		"driving":   "driving",
		"bike":      "bicycling",
		"bicycle":   "bicycling",
		"bicycling": "bicycling",
		"transit":   "transit",
	}
	for input, want := range cases {
		if got := normalizeDirectionsMode(input); got != want {
			t.Fatalf("normalizeDirectionsMode(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestResolveDirectionsLocationVariants(t *testing.T) {
	value, err := resolveDirectionsLocation("from", "pid", nil, "")
	if err != nil || value != "place_id:pid" {
		t.Fatalf("unexpected place id resolution: value=%q err=%v", value, err)
	}

	value, err = resolveDirectionsLocation("to", "", &LatLng{Lat: 1.23, Lng: 4.56}, "")
	if err != nil || value != "1.230000,4.560000" {
		t.Fatalf("unexpected lat/lng resolution: value=%q err=%v", value, err)
	}

	value, err = resolveDirectionsLocation("to", "", nil, " Seattle ")
	if err != nil || value != "Seattle" {
		t.Fatalf("unexpected text resolution: value=%q err=%v", value, err)
	}
}

func TestBuildDirectionsURLErrors(t *testing.T) {
	if _, err := buildDirectionsURL("://bad", map[string]string{}, "k"); err == nil {
		t.Fatal("expected invalid URL error")
	}
	if _, err := buildDirectionsURL("https://example.com", map[string]string{}, ""); !errors.Is(err, ErrMissingAPIKey) {
		t.Fatalf("expected ErrMissingAPIKey, got %v", err)
	}
}

func TestDirectionsHTTPErrorWithEmptyBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	_, err := client.Directions(context.Background(), DirectionsRequest{From: "A", To: "B"})
	if err == nil {
		t.Fatal("expected error")
	}
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("expected APIError, got: %v", err)
	}
	if apiErr.StatusCode != http.StatusBadGateway {
		t.Fatalf("unexpected status: %d", apiErr.StatusCode)
	}
}

func TestDirectionsStatusError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"ZERO_RESULTS","error_message":"none"}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	_, err := client.Directions(context.Background(), DirectionsRequest{From: "A", To: "B"})
	if err == nil || !strings.Contains(err.Error(), "directions status ZERO_RESULTS") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDirectionsNoRoutesReturned(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"OK","routes":[]}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	_, err := client.Directions(context.Background(), DirectionsRequest{From: "A", To: "B"})
	if err == nil || !strings.Contains(err.Error(), "no directions returned") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDirectionsEmptyBodySuccessStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	_, err := client.Directions(context.Background(), DirectionsRequest{From: "A", To: "B"})
	if err == nil || !strings.Contains(err.Error(), "empty response") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDirectionsRequestLocaleAndImperialUnits(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		if query.Get("origin") != "Seattle" || query.Get("destination") != "Portland" {
			t.Fatalf("unexpected endpoints: %v", query)
		}
		if query.Get("mode") != directionsModeDrive {
			t.Fatalf("unexpected mode: %s", query.Get("mode"))
		}
		if query.Get("language") != "en-US" {
			t.Fatalf("unexpected language: %s", query.Get("language"))
		}
		if query.Get("region") != "US" {
			t.Fatalf("unexpected region: %s", query.Get("region"))
		}
		if query.Get("units") != directionsUnitsImperial {
			t.Fatalf("unexpected units: %s", query.Get("units"))
		}
		_, _ = w.Write([]byte(`{
			"status":"OK",
			"routes":[{"legs":[{"distance":{"text":"1 mi","value":1609},"duration":{"text":"5 mins","value":300},"start_address":"Seattle","end_address":"Portland","steps":[]}]}]
		}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	_, err := client.Directions(context.Background(), DirectionsRequest{
		From:     "Seattle",
		To:       "Portland",
		Mode:     "drive",
		Language: "en-US",
		Region:   "US",
		Units:    "imperial",
	})
	if err != nil {
		t.Fatalf("Directions error: %v", err)
	}
}

func TestDirectionsLocationBoundsValidation(t *testing.T) {
	req := DirectionsRequest{
		FromLocation: &LatLng{Lat: 91, Lng: 0},
		To:           "B",
	}
	err := validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "from.lat") {
		t.Fatalf("unexpected error for latitude: %v", err)
	}

	req = DirectionsRequest{
		From:       "A",
		ToLocation: &LatLng{Lat: 0, Lng: 181},
	}
	err = validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "to.lng") {
		t.Fatalf("unexpected error for longitude: %v", err)
	}
}

func TestCleanInstructionPreservesWordSpacing(t *testing.T) {
	got := cleanInstruction("Turn right<div>onto <b>Main St</b></div>")
	if got != "Turn right onto Main St" {
		t.Fatalf("unexpected instruction: %q", got)
	}
}
