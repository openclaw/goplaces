package places

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDirectionsRequestPlaceID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != routesPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Header.Get("X-Goog-Api-Key") != "test-key" {
			t.Fatalf("unexpected api key header: %s", r.Header.Get("X-Goog-Api-Key"))
		}
		if r.Header.Get("X-Goog-FieldMask") != directionsFieldMask {
			t.Fatalf("unexpected field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		var payload map[string]any
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		if payload["travelMode"] != travelModeWalk {
			t.Fatalf("unexpected travel mode: %#v", payload["travelMode"])
		}
		if payload["units"] != routesUnitsMetric {
			t.Fatalf("unexpected units: %#v", payload["units"])
		}
		origin, ok := payload["origin"].(map[string]any)
		if !ok || origin["placeId"] != "from" {
			t.Fatalf("unexpected origin payload: %#v", payload["origin"])
		}
		destination, ok := payload["destination"].(map[string]any)
		if !ok || destination["placeId"] != "to" {
			t.Fatalf("unexpected destination payload: %#v", payload["destination"])
		}

		_, _ = w.Write([]byte(`{
  "routes": [{
    "description": "Main",
    "warnings": ["test"],
    "legs": [{
      "distanceMeters": 1000,
      "duration": "600s",
      "localizedValues": {
        "distance": {"text": "1 km"},
        "duration": {"text": "10 mins"}
      },
      "steps": [{
        "distanceMeters": 200,
        "staticDuration": "120s",
        "localizedValues": {
          "distance": {"text": "0.2 km"},
          "staticDuration": {"text": "2 mins"}
        },
        "travelMode": "WALK",
        "navigationInstruction": {
          "instructions": "Head north",
          "maneuver": "TURN_LEFT"
        }
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
	if response.DurationSeconds != 600 {
		t.Fatalf("unexpected duration seconds: %d", response.DurationSeconds)
	}
	if response.StartAddress != "place_id:from" || response.EndAddress != "place_id:to" {
		t.Fatalf("unexpected start/end labels: %q -> %q", response.StartAddress, response.EndAddress)
	}
	if len(response.Steps) != 1 || response.Steps[0].Instruction != "Head north" {
		t.Fatalf("unexpected steps: %#v", response.Steps)
	}
	if response.Steps[0].Maneuver != "TURN_LEFT" {
		t.Fatalf("unexpected step maneuver: %#v", response.Steps[0])
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

func TestDirectionsRouteModifiersRequireDrive(t *testing.T) {
	req := DirectionsRequest{From: "A", To: "B", Mode: "walk", AvoidTolls: true}
	err := validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "route_modifiers") {
		t.Fatalf("expected route modifier validation error, got %v", err)
	}
}

func TestDirectionsTimeValidation(t *testing.T) {
	req := DirectionsRequest{
		From:          "A",
		To:            "B",
		DepartureTime: "2030-05-10T18:57:00-03:00",
		ArrivalTime:   "2030-05-10T19:57:00-03:00",
	}
	err := validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "time") {
		t.Fatalf("expected mutually exclusive time validation error, got %v", err)
	}

	req = DirectionsRequest{From: "A", To: "B", DepartureTime: "tomorrow"}
	err = validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "departure_time") {
		t.Fatalf("expected departure time validation error, got %v", err)
	}

	req = DirectionsRequest{From: "A", To: "B", Mode: "drive", ArrivalTime: "2030-05-10T19:57:00-03:00"}
	err = validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "arrival_time") {
		t.Fatalf("expected arrival time mode validation error, got %v", err)
	}

	req = DirectionsRequest{From: "A", To: "B", Mode: "transit", ArrivalTime: "tomorrow"}
	err = validateDirectionsRequest(applyDirectionsDefaults(req))
	if err == nil || !strings.Contains(err.Error(), "arrival_time") {
		t.Fatalf("expected arrival time format validation error, got %v", err)
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
		"walk":      directionsModeWalk,
		"walking":   directionsModeWalk,
		"drive":     directionsModeDrive,
		"driving":   directionsModeDrive,
		"bike":      directionsModeBicycle,
		"bicycle":   directionsModeBicycle,
		"bicycling": directionsModeBicycle,
		"transit":   directionsModeTransit,
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

func TestDirectionsEndpointCompatibility(t *testing.T) {
	if got := directionsEndpoint("https://routes.googleapis.com"); got != "https://routes.googleapis.com"+routesPath {
		t.Fatalf("unexpected endpoint: %s", got)
	}
	full := "https://routes.googleapis.com" + routesPath
	if got := directionsEndpoint(full); got != full {
		t.Fatalf("unexpected full endpoint handling: %s", got)
	}
}

func TestParseDurationSeconds(t *testing.T) {
	if got := parseDurationSeconds("600s"); got != 600 {
		t.Fatalf("unexpected parsed duration: %d", got)
	}
	if got := parseDurationSeconds("not-a-duration"); got != 0 {
		t.Fatalf("unexpected parsed invalid duration: %d", got)
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

func TestDirectionsNoRoutesReturned(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"routes":[]}`))
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
		if r.URL.Path != routesPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		if payload["travelMode"] != travelModeDrive {
			t.Fatalf("unexpected mode: %#v", payload["travelMode"])
		}
		if payload["languageCode"] != "en-US" {
			t.Fatalf("unexpected language: %#v", payload["languageCode"])
		}
		if payload["regionCode"] != "US" {
			t.Fatalf("unexpected region: %#v", payload["regionCode"])
		}
		if payload["units"] != routesUnitsImperial {
			t.Fatalf("unexpected units: %#v", payload["units"])
		}
		_, _ = w.Write([]byte(`{
  "routes":[{
    "legs":[{
      "distanceMeters":1609,
      "duration":"300s",
      "localizedValues":{"distance":{"text":"1 mi"},"duration":{"text":"5 mins"}},
      "steps":[]
    }]
  }]
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

func TestDirectionsRequestRouteModifiers(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != routesPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		modifiers, ok := payload["routeModifiers"].(map[string]any)
		if !ok {
			t.Fatalf("missing routeModifiers: %#v", payload)
		}
		if modifiers["avoidTolls"] != true || modifiers["avoidHighways"] != true || modifiers["avoidFerries"] != true {
			t.Fatalf("unexpected routeModifiers: %#v", modifiers)
		}
		_, _ = w.Write([]byte(`{
  "routes":[{
    "legs":[{
      "distanceMeters":1609,
      "duration":"300s",
      "localizedValues":{"distance":{"text":"1 mi"},"duration":{"text":"5 mins"}},
      "steps":[]
    }]
  }]
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
	_, err := client.Directions(context.Background(), DirectionsRequest{
		From:          "Seattle",
		To:            "Portland",
		Mode:          "drive",
		AvoidTolls:    true,
		AvoidHighways: true,
		AvoidFerries:  true,
	})
	if err != nil {
		t.Fatalf("Directions error: %v", err)
	}
}

func TestDirectionsRequestTimes(t *testing.T) {
	t.Run("departure", func(t *testing.T) {
		const departure = "2030-05-10T18:57:00-03:00"
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode body: %v", err)
			}
			if payload["departureTime"] != departure {
				t.Fatalf("unexpected departure time: %#v", payload["departureTime"])
			}
			if payload["routingPreference"] != "TRAFFIC_AWARE" {
				t.Fatalf("unexpected routing preference: %#v", payload["routingPreference"])
			}
			_, _ = w.Write([]byte(`{
  "routes":[{
    "legs":[{
      "distanceMeters":1609,
      "duration":"300s",
      "localizedValues":{"distance":{"text":"1 mi"},"duration":{"text":"5 mins"}},
      "steps":[]
    }]
  }]
}`))
		}))
		defer server.Close()

		client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
		response, err := client.Directions(context.Background(), DirectionsRequest{
			From:          "Seattle",
			To:            "Portland",
			Mode:          "drive",
			DepartureTime: departure,
		})
		if err != nil {
			t.Fatalf("Directions error: %v", err)
		}
		if response.DepartureTime != departure {
			t.Fatalf("unexpected departure time in response: %#v", response)
		}
	})

	t.Run("arrival", func(t *testing.T) {
		const arrival = "2030-05-10T19:57:00-03:00"
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode body: %v", err)
			}
			if payload["arrivalTime"] != arrival {
				t.Fatalf("unexpected arrival time: %#v", payload["arrivalTime"])
			}
			if _, ok := payload["routingPreference"]; ok {
				t.Fatalf("unexpected routing preference: %#v", payload["routingPreference"])
			}
			_, _ = w.Write([]byte(`{
  "routes":[{
    "legs":[{
      "distanceMeters":1609,
      "duration":"300s",
      "localizedValues":{"distance":{"text":"1 mi"},"duration":{"text":"5 mins"}},
      "steps":[]
    }]
  }]
}`))
		}))
		defer server.Close()

		client := NewClient(Options{APIKey: "test-key", DirectionsBaseURL: server.URL})
		response, err := client.Directions(context.Background(), DirectionsRequest{
			From:        "Seattle",
			To:          "Portland",
			Mode:        "transit",
			ArrivalTime: arrival,
		})
		if err != nil {
			t.Fatalf("Directions error: %v", err)
		}
		if response.ArrivalTime != arrival {
			t.Fatalf("unexpected arrival time in response: %#v", response)
		}
	})
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
