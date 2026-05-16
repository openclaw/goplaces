package places

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNearbySearchSuccess(t *testing.T) {
	var gotRequest map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/v1/places:searchNearby" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Header.Get("X-Goog-FieldMask") != nearbyFieldMask {
			t.Fatalf("unexpected field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(body, &gotRequest); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		_, _ = w.Write([]byte(`{
  "places": [
    {
      "id": "abc",
      "displayName": {"text": "Cafe"},
      "formattedAddress": "123 Street",
      "location": {"latitude": 1.23, "longitude": 4.56},
      "rating": 4.7,
      "userRatingCount": 42,
      "priceLevel": "PRICE_LEVEL_MODERATE",
      "types": ["cafe"],
      "currentOpeningHours": {"openNow": true}
    }
  ],
  "nextPageToken": "next"
}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL + "/v1"})
	response, err := client.NearbySearch(context.Background(), NearbySearchRequest{
		LocationRestriction: &LocationBias{Lat: 40.0, Lng: -70.0, RadiusM: 500},
		Limit:               5,
		IncludedTypes:       []string{"cafe"},
		ExcludedTypes:       []string{"bar"},
		Language:            "en",
		Region:              "US",
	})
	if err != nil {
		t.Fatalf("nearby error: %v", err)
	}
	if len(response.Results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(response.Results))
	}
	if response.Results[0].UserRatingCount == nil || *response.Results[0].UserRatingCount != 42 {
		t.Fatalf("unexpected user rating count: %#v", response.Results[0].UserRatingCount)
	}
	if response.NextPageToken != "next" {
		t.Fatalf("unexpected token: %s", response.NextPageToken)
	}

	if gotRequest["maxResultCount"].(float64) != 5 {
		t.Fatalf("unexpected maxResultCount: %#v", gotRequest["maxResultCount"])
	}
	if gotRequest["languageCode"] != "en" {
		t.Fatalf("unexpected languageCode: %#v", gotRequest["languageCode"])
	}
	if gotRequest["regionCode"] != "US" {
		t.Fatalf("unexpected regionCode: %#v", gotRequest["regionCode"])
	}
	if _, ok := gotRequest["locationRestriction"].(map[string]any); !ok {
		t.Fatalf("unexpected locationRestriction: %#v", gotRequest["locationRestriction"])
	}
}

func TestNearbySearchValidationFieldNames(t *testing.T) {
	err := validateNearbyRequest(NearbySearchRequest{
		LocationRestriction: &LocationBias{Lat: 1, Lng: 2, RadiusM: 0},
		Limit:               1,
	})
	var validationErr ValidationError
	if !errors.As(err, &validationErr) {
		t.Fatalf("expected validation error, got %v", err)
	}
	if validationErr.Field != "location_restriction.radius_m" {
		t.Fatalf("unexpected field: %s", validationErr.Field)
	}
}
