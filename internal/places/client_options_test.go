package places

import (
	"context"
	"errors"
	"testing"
)

func TestMissingAPIKey(t *testing.T) {
	client := NewClient(Options{})
	_, err := client.Search(context.Background(), SearchRequest{Query: "coffee"})
	if !errors.Is(err, ErrMissingAPIKey) {
		t.Fatalf("expected missing api key error")
	}
}

func TestValidationErrors(t *testing.T) {
	client := NewClient(Options{APIKey: "test-key", BaseURL: "http://example.com"})

	_, err := client.Search(context.Background(), SearchRequest{Query: ""})
	if err == nil {
		t.Fatalf("expected validation error")
	}

	minRating := 9.0
	_, err = client.Search(context.Background(), SearchRequest{Query: "coffee", Filters: &Filters{MinRating: &minRating}})
	if err == nil {
		t.Fatalf("expected rating error")
	}

	_, err = client.Search(context.Background(), SearchRequest{Query: "coffee", Limit: 42})
	if err == nil {
		t.Fatalf("expected limit error")
	}

	_, err = client.Search(context.Background(), SearchRequest{Query: "coffee", Filters: &Filters{PriceLevels: []int{9}}})
	if err == nil {
		t.Fatalf("expected price level error")
	}

	_, err = client.Search(context.Background(), SearchRequest{Query: "coffee", LocationBias: &LocationBias{Lat: 200, Lng: 0, RadiusM: 1}})
	if err == nil {
		t.Fatalf("expected location error")
	}

	_, err = client.Resolve(context.Background(), LocationResolveRequest{LocationText: ""})
	if err == nil {
		t.Fatalf("expected resolve error")
	}

	_, err = client.Resolve(context.Background(), LocationResolveRequest{LocationText: "x", Limit: 99})
	if err == nil {
		t.Fatalf("expected resolve limit error")
	}

	_, err = client.Autocomplete(context.Background(), AutocompleteRequest{Input: ""})
	if err == nil {
		t.Fatalf("expected autocomplete input error")
	}

	_, err = client.Autocomplete(context.Background(), AutocompleteRequest{Input: "x", Limit: 99})
	if err == nil {
		t.Fatalf("expected autocomplete limit error")
	}

	_, err = client.NearbySearch(context.Background(), NearbySearchRequest{})
	if err == nil {
		t.Fatalf("expected nearby location error")
	}

	_, err = client.NearbySearch(context.Background(), NearbySearchRequest{
		LocationRestriction: &LocationBias{Lat: 1, Lng: 2, RadiusM: 3},
		Limit:               99,
	})
	if err == nil {
		t.Fatalf("expected nearby limit error")
	}

	_, err = client.PhotoMedia(context.Background(), PhotoMediaRequest{Name: ""})
	if err == nil {
		t.Fatalf("expected photo media name error")
	}

	_, err = client.Details(context.Background(), "")
	if err == nil {
		t.Fatalf("expected details error")
	}
}

func TestNewClientDefaults(t *testing.T) {
	client := NewClient(Options{APIKey: "test-key"})
	if client.baseURL != DefaultBaseURL {
		t.Fatalf("unexpected baseURL: %s", client.baseURL)
	}
	if client.routesBaseURL != defaultRoutesBaseURL {
		t.Fatalf("unexpected routesBaseURL: %s", client.routesBaseURL)
	}
	if client.directionsBaseURL != defaultDirectionsBaseURL {
		t.Fatalf("unexpected directionsBaseURL: %s", client.directionsBaseURL)
	}
}

func TestNewClientCustomDirectionsBaseURL(t *testing.T) {
	client := NewClient(Options{
		APIKey:            "test-key",
		BaseURL:           "https://example.com/v1/",
		RoutesBaseURL:     "https://routes.example.com/",
		DirectionsBaseURL: "https://maps.example.com/directions/",
	})
	if client.baseURL != "https://example.com/v1" {
		t.Fatalf("unexpected baseURL: %s", client.baseURL)
	}
	if client.routesBaseURL != "https://routes.example.com" {
		t.Fatalf("unexpected routesBaseURL: %s", client.routesBaseURL)
	}
	if client.directionsBaseURL != "https://maps.example.com/directions" {
		t.Fatalf("unexpected directionsBaseURL: %s", client.directionsBaseURL)
	}
}

func TestMappingHelpers(t *testing.T) {
	if mapLatLng(nil) != nil {
		t.Fatalf("expected nil location")
	}
	if displayName(nil) != "" {
		t.Fatalf("expected empty display name")
	}
	if openNow(nil) != nil {
		t.Fatalf("expected nil open now")
	}
	if weekdayDescriptions(nil) != nil {
		t.Fatalf("expected nil hours")
	}
	if mapPriceLevel("UNKNOWN") != nil {
		t.Fatalf("expected nil price level")
	}
}
