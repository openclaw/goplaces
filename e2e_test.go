//go:build e2e
// +build e2e

package goplaces

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"
)

func TestE2ESearchAndDetails(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_PLACES_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_PLACES_API_KEY not set")
	}

	query := os.Getenv("GOOGLE_PLACES_E2E_QUERY")
	if query == "" {
		query = "coffee in Seattle"
	}
	language := os.Getenv("GOOGLE_PLACES_E2E_LANGUAGE")
	if language == "" {
		language = "en"
	}
	region := os.Getenv("GOOGLE_PLACES_E2E_REGION")
	if region == "" {
		region = "US"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	client := NewClient(Options{
		APIKey:  apiKey,
		BaseURL: os.Getenv("GOOGLE_PLACES_E2E_BASE_URL"),
		Timeout: 10 * time.Second,
	})

	search, err := client.Search(ctx, SearchRequest{
		Query:    query,
		Limit:    1,
		Language: language,
		Region:   region,
	})
	if err != nil {
		t.Fatalf("search error: %v", err)
	}
	if len(search.Results) == 0 {
		t.Fatalf("expected search results")
	}

	placeID := search.Results[0].PlaceID
	if placeID == "" {
		t.Fatalf("expected place id")
	}

	details, err := client.DetailsWithOptions(ctx, DetailsRequest{
		PlaceID:        placeID,
		Language:       language,
		Region:         region,
		IncludeReviews: true,
	})
	if err != nil {
		t.Fatalf("details error: %v", err)
	}
	if details.PlaceID == "" {
		t.Fatalf("expected details place id")
	}
}

func TestE2EAutocomplete(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_PLACES_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_PLACES_API_KEY not set")
	}

	query := os.Getenv("GOOGLE_PLACES_E2E_QUERY")
	if query == "" {
		query = "coffee"
	}
	language := os.Getenv("GOOGLE_PLACES_E2E_LANGUAGE")
	if language == "" {
		language = "en"
	}
	region := os.Getenv("GOOGLE_PLACES_E2E_REGION")
	if region == "" {
		region = "US"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	client := NewClient(Options{
		APIKey:  apiKey,
		BaseURL: os.Getenv("GOOGLE_PLACES_E2E_BASE_URL"),
		Timeout: 10 * time.Second,
	})

	response, err := client.Autocomplete(ctx, AutocompleteRequest{
		Input:        query,
		Limit:        3,
		Language:     language,
		Region:       region,
		SessionToken: "goplaces-e2e",
	})
	if err != nil {
		t.Fatalf("autocomplete error: %v", err)
	}
	if len(response.Suggestions) == 0 {
		t.Fatalf("expected autocomplete suggestions")
	}
}

func TestE2ENearbySearch(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_PLACES_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_PLACES_API_KEY not set")
	}

	lat := envFloat("GOOGLE_PLACES_E2E_LAT", 47.6062)
	lng := envFloat("GOOGLE_PLACES_E2E_LNG", -122.3321)
	radius := envFloat("GOOGLE_PLACES_E2E_RADIUS_M", 1500)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	client := NewClient(Options{
		APIKey:  apiKey,
		BaseURL: os.Getenv("GOOGLE_PLACES_E2E_BASE_URL"),
		Timeout: 10 * time.Second,
	})

	response, err := client.NearbySearch(ctx, NearbySearchRequest{
		LocationRestriction: &LocationBias{Lat: lat, Lng: lng, RadiusM: radius},
		Limit:               3,
		IncludedTypes:       []string{"cafe"},
		Language:            "en",
		Region:              "US",
	})
	if err != nil {
		t.Fatalf("nearby error: %v", err)
	}
	if len(response.Results) == 0 {
		t.Fatalf("expected nearby results")
	}
}

func TestE2EDirectionsAvoidTolls(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_PLACES_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_PLACES_API_KEY not set")
	}

	from := os.Getenv("GOOGLE_PLACES_E2E_DIRECTIONS_FROM")
	if from == "" {
		from = "Paris, France"
	}
	to := os.Getenv("GOOGLE_PLACES_E2E_DIRECTIONS_TO")
	if to == "" {
		to = "Brest, France"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	client := NewClient(Options{
		APIKey:            apiKey,
		DirectionsBaseURL: os.Getenv("GOOGLE_DIRECTIONS_E2E_BASE_URL"),
		Timeout:           15 * time.Second,
	})

	response, err := client.Directions(ctx, DirectionsRequest{
		From:       from,
		To:         to,
		Mode:       "drive",
		AvoidTolls: true,
		Language:   "en",
		Region:     "FR",
	})
	if err != nil {
		t.Fatalf("directions error: %v", err)
	}
	if response.DistanceMeters == 0 || response.DurationSeconds == 0 {
		t.Fatalf("expected distance and duration, got %#v", response)
	}
}

func TestE2EPhotoMedia(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_PLACES_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_PLACES_API_KEY not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	client := NewClient(Options{
		APIKey:  apiKey,
		BaseURL: os.Getenv("GOOGLE_PLACES_E2E_BASE_URL"),
		Timeout: 10 * time.Second,
	})

	placeID := os.Getenv("GOOGLE_PLACES_E2E_PHOTO_PLACE_ID")
	if placeID == "" {
		query := os.Getenv("GOOGLE_PLACES_E2E_PHOTO_QUERY")
		if query == "" {
			query = "Space Needle Seattle"
		}
		search, err := client.Search(ctx, SearchRequest{Query: query, Limit: 1})
		if err != nil {
			t.Fatalf("photo search error: %v", err)
		}
		if len(search.Results) == 0 {
			t.Fatalf("expected photo search results")
		}
		placeID = search.Results[0].PlaceID
	}

	details, err := client.DetailsWithOptions(ctx, DetailsRequest{
		PlaceID:       placeID,
		IncludePhotos: true,
	})
	if err != nil {
		t.Fatalf("photo details error: %v", err)
	}
	if len(details.Photos) == 0 {
		t.Skip("no photos available for e2e place")
	}

	photo := details.Photos[0]
	response, err := client.PhotoMedia(ctx, PhotoMediaRequest{
		Name:       photo.Name,
		MaxWidthPx: 800,
	})
	if err != nil {
		t.Fatalf("photo media error: %v", err)
	}
	if response.PhotoURI == "" {
		t.Fatalf("expected photo uri")
	}
}

func envFloat(key string, fallback float64) float64 {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return fallback
	}
	return parsed
}
