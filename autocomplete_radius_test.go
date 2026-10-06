package goplaces

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAutocompletePointBiasPublicRequest(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var body struct {
			LocationBias struct {
				Circle struct {
					Radius float64 `json:"radius"`
				} `json:"circle"`
			} `json:"locationBias"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Errorf("decode request: %v", err)
		}
		if body.LocationBias.Circle.Radius != 0 {
			t.Errorf("radius = %v", body.LocationBias.Circle.Radius)
		}
		_, _ = w.Write([]byte(`{"suggestions":[{"placePrediction":{"placeId":"point-result"}}]}`))
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	response, err := client.Autocomplete(context.Background(), AutocompleteRequest{Input: "coffee", LocationBias: &LocationBias{Lat: 1, Lng: 2}})
	if err != nil {
		t.Fatalf("valid zero-radius autocomplete bias: %v", err)
	}
	if calls != 1 || len(response.Suggestions) != 1 || response.Suggestions[0].PlaceID != "point-result" {
		t.Fatalf("unexpected calls/result: %d %#v", calls, response)
	}
	for _, radius := range []float64{-1, math.NaN(), math.Inf(-1), math.Inf(1), 50001} {
		_, err := client.Autocomplete(context.Background(), AutocompleteRequest{Input: "coffee", LocationBias: &LocationBias{Lat: 1, Lng: 2, RadiusM: radius}})
		var validation ValidationError
		if !errors.As(err, &validation) || validation.Field != "location_bias.radius_m" {
			t.Errorf("invalid radius %v: %v", radius, err)
		}
	}
	for _, bias := range []*LocationBias{{Lat: 91, Lng: 2}, {Lat: 1, Lng: 181}} {
		_, err := client.Autocomplete(context.Background(), AutocompleteRequest{Input: "coffee", LocationBias: bias})
		var validation ValidationError
		if !errors.As(err, &validation) {
			t.Errorf("invalid coordinates: %v", err)
		}
	}
	// Endpoint-specific zero allowance must not weaken nearby restrictions or text-search validation.
	_, err = client.Search(context.Background(), SearchRequest{Query: "coffee", LocationBias: &LocationBias{Lat: 1, Lng: 2}})
	if err == nil {
		t.Fatal("search must retain its positive radius contract")
	}
	_, err = client.NearbySearch(context.Background(), NearbySearchRequest{LocationRestriction: &LocationBias{Lat: 1, Lng: 2}})
	if err == nil {
		t.Fatal("nearby must retain its positive radius contract")
	}
	if calls != 1 {
		t.Fatalf("invalid requests reached transport: %d", calls)
	}
}
