package places

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestSearchSuccess(t *testing.T) {
	var gotRequest map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/v1/places:searchText" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Header.Get("X-Goog-Api-Key") != "test-key" {
			t.Fatalf("missing api key header")
		}
		if r.Header.Get("X-Goog-FieldMask") != searchFieldMask {
			t.Fatalf("unexpected field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(body, &gotRequest); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
  "places": [
    {
      "id": "abc",
      "displayName": {"text": "Cafe"},
      "formattedAddress": "123 Street",
      "location": {"latitude": 1.23, "longitude": 4.56},
      "rating": 4.7,
      "userRatingCount": 532,
      "priceLevel": "PRICE_LEVEL_MODERATE",
      "types": ["cafe"],
      "currentOpeningHours": {"openNow": true},
      "businessStatus": "OPERATIONAL"
    }
  ],
  "nextPageToken": "next"
}`))
	}))
	defer server.Close()

	client := NewClient(Options{
		APIKey:  " test-key\n",
		BaseURL: server.URL + "/v1",
		Timeout: time.Second,
	})

	open := true
	minRating := 4.0
	request := SearchRequest{
		Query:     "coffee",
		Limit:     5,
		PageToken: "token",
		Language:  "en",
		Region:    "US",
		Filters: &Filters{
			Keyword:     "best",
			Types:       []string{"cafe"},
			OpenNow:     &open,
			MinRating:   &minRating,
			PriceLevels: []int{2},
		},
		LocationBias: &LocationBias{Lat: 40.0, Lng: -70.0, RadiusM: 500},
	}

	response, err := client.Search(context.Background(), request)
	if err != nil {
		t.Fatalf("search error: %v", err)
	}
	if len(response.Results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(response.Results))
	}
	result := response.Results[0]
	if result.PlaceID != "abc" {
		t.Fatalf("unexpected place id: %s", result.PlaceID)
	}
	if result.Name != "Cafe" {
		t.Fatalf("unexpected name: %s", result.Name)
	}
	if result.PriceLevel == nil || *result.PriceLevel != 2 {
		t.Fatalf("unexpected price level: %#v", result.PriceLevel)
	}
	if result.UserRatingCount == nil || *result.UserRatingCount != 532 {
		t.Fatalf("unexpected user rating count: %#v", result.UserRatingCount)
	}
	if result.OpenNow == nil || *result.OpenNow != true {
		t.Fatalf("unexpected openNow: %#v", result.OpenNow)
	}
	if result.BusinessStatus != "OPERATIONAL" {
		t.Fatalf("unexpected business status: %s", result.BusinessStatus)
	}
	if response.NextPageToken != "next" {
		t.Fatalf("unexpected token: %s", response.NextPageToken)
	}

	if gotRequest["textQuery"] != "coffee best" {
		t.Fatalf("unexpected textQuery: %#v", gotRequest["textQuery"])
	}
	if gotRequest["pageSize"].(float64) != 5 {
		t.Fatalf("unexpected pageSize: %#v", gotRequest["pageSize"])
	}
	if gotRequest["pageToken"] != "token" {
		t.Fatalf("unexpected pageToken: %#v", gotRequest["pageToken"])
	}
	if gotRequest["languageCode"] != "en" {
		t.Fatalf("unexpected languageCode: %#v", gotRequest["languageCode"])
	}
	if gotRequest["regionCode"] != "US" {
		t.Fatalf("unexpected regionCode: %#v", gotRequest["regionCode"])
	}
}

func TestSearchHTTPError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte("bad"))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	_, err := client.Search(context.Background(), SearchRequest{Query: "coffee"})
	var apiErr *APIError
	if err == nil || !errors.As(err, &apiErr) {
		t.Fatalf("expected api error, got %v", err)
	}
	if apiErr.StatusCode != http.StatusBadRequest {
		t.Fatalf("unexpected status: %d", apiErr.StatusCode)
	}
}

func TestSearchInvalidJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("not-json"))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	_, err := client.Search(context.Background(), SearchRequest{Query: "coffee"})
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestBuildSearchBodyOmitsEmptyPriceLevels(t *testing.T) {
	request := SearchRequest{Query: "coffee", Filters: &Filters{PriceLevels: []int{9}}}
	body := buildSearchBody(request)
	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if bytes.Contains(payload, []byte("priceLevels")) {
		t.Fatalf("unexpected priceLevels in payload")
	}

	request = SearchRequest{Query: "coffee", Filters: &Filters{PriceLevels: []int{0, 2}}}
	body = buildSearchBody(request)
	levels, ok := body["priceLevels"].([]string)
	if !ok || len(levels) != 2 || levels[0] != "PRICE_LEVEL_FREE" || levels[1] != "PRICE_LEVEL_MODERATE" {
		t.Fatalf("unexpected price levels: %#v", body["priceLevels"])
	}
}

func TestSearchAllowsFreePriceLevelFilter(t *testing.T) {
	err := validateSearchRequest(SearchRequest{
		Query:   "coffee",
		Limit:   1,
		Filters: &Filters{PriceLevels: []int{0}},
	})
	if err != nil {
		t.Fatalf("expected free price level to be valid, got %v", err)
	}
}

func TestSearchRejectsInvalidPriceLevelFilter(t *testing.T) {
	err := validateSearchRequest(SearchRequest{
		Query:   "coffee",
		Limit:   1,
		Filters: &Filters{PriceLevels: []int{-1}},
	})
	var validationErr ValidationError
	if !errors.As(err, &validationErr) {
		t.Fatalf("expected validation error, got %v", err)
	}
	if validationErr.Field != "filters.price_levels" {
		t.Fatalf("unexpected field: %s", validationErr.Field)
	}
}
