package goplaces

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

func TestNearbyFilterValidationPublicBoundary(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { calls++; _, _ = w.Write([]byte(`{"places":[]}`)) }))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	oversized := make([]string, 51)
	for i := range oversized {
		oversized[i] = fmt.Sprintf("type_%d", i)
	}
	for _, tc := range []struct {
		name               string
		included, excluded []string
		field              string
	}{
		{"included cap", oversized, nil, "included_types"},
		{"excluded cap", nil, oversized, "excluded_types"},
		{"conflict", []string{"cafe", "restaurant"}, []string{"restaurant"}, "excluded_types"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := client.NearbySearch(context.Background(), NearbySearchRequest{LocationRestriction: &LocationBias{Lat: 1, Lng: 2, RadiusM: 100}, IncludedTypes: tc.included, ExcludedTypes: tc.excluded})
			var validation ValidationError
			if !errors.As(err, &validation) || validation.Field != tc.field {
				t.Errorf("expected %s validation, got %v", tc.field, err)
			}
		})
	}
	if calls != 0 {
		t.Fatalf("invalid requests reached transport: %d", calls)
	}
}

func TestNearbyDisjointFiftyTypeFiltersPreserved(t *testing.T) {
	included := make([]string, 50)
	for i := range included {
		included[i] = fmt.Sprintf("type_%d", i)
	}
	excluded := []string{"excluded_type"}
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var body struct {
			Included []string `json:"includedTypes"`
			Excluded []string `json:"excludedTypes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Errorf("decode request: %v", err)
		}
		if !reflect.DeepEqual(included, body.Included) || !reflect.DeepEqual(excluded, body.Excluded) {
			t.Errorf("changed filters: %#v", body)
		}
		_, _ = w.Write([]byte(`{"places":[{"id":"valid-place"}]}`))
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL})
	result, err := client.NearbySearch(context.Background(), NearbySearchRequest{LocationRestriction: &LocationBias{Lat: 1, Lng: 2, RadiusM: 100}, IncludedTypes: included, ExcludedTypes: excluded})
	if err != nil || calls != 1 || len(result.Results) != 1 || result.Results[0].PlaceID != "valid-place" {
		t.Fatalf("valid boundary: calls=%d result=%#v err=%v", calls, result, err)
	}
}
