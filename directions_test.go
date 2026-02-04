package goplaces

import (
	"context"
	"net/http"
	"net/http/httptest"
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

func TestDirectionsLocationValidation(t *testing.T) {
	req := DirectionsRequest{FromPlaceID: "a", From: "b", To: "c"}
	if err := validateDirectionsRequest(applyDirectionsDefaults(req)); err == nil {
		t.Fatalf("expected validation error for multiple origin inputs")
	}
}
