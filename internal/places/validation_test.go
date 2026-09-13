package places

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func TestRequestsRejectNonFiniteNumbersBeforeHTTP(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		_, _ = fmt.Fprint(w, `{"routes":[{"polyline":{"encodedPolyline":"??"}}],"places":[]}`)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "synthetic-key", BaseURL: server.URL, RoutesBaseURL: server.URL, DirectionsBaseURL: server.URL})
	ctx := t.Context()
	cases := []struct {
		name, field string
		run         func(float64) error
	}{
		{"search latitude", "location_bias.lat", func(v float64) error {
			_, err := client.Search(ctx, SearchRequest{Query: "coffee", LocationBias: &LocationBias{Lat: v, RadiusM: 1}})
			return err
		}},
		{"search longitude", "location_bias.lng", func(v float64) error {
			_, err := client.Search(ctx, SearchRequest{Query: "coffee", LocationBias: &LocationBias{Lng: v, RadiusM: 1}})
			return err
		}},
		{"search rating", "filters.min_rating", func(v float64) error {
			_, err := client.Search(ctx, SearchRequest{Query: "coffee", Filters: &Filters{MinRating: &v}})
			return err
		}},
		{"autocomplete radius", "location_bias.radius_m", func(v float64) error {
			_, err := client.Autocomplete(ctx, AutocompleteRequest{Input: "cof", LocationBias: &LocationBias{RadiusM: v}})
			return err
		}},
		{"nearby latitude", "location_restriction.lat", func(v float64) error {
			_, err := client.NearbySearch(ctx, NearbySearchRequest{LocationRestriction: &LocationBias{Lat: v, RadiusM: 1}})
			return err
		}},
		{"nearby radius", "location_restriction.radius_m", func(v float64) error {
			_, err := client.NearbySearch(ctx, NearbySearchRequest{LocationRestriction: &LocationBias{RadiusM: v}})
			return err
		}},
		{"directions origin", "from.lat", func(v float64) error {
			_, err := client.Directions(ctx, DirectionsRequest{FromLocation: &LatLng{Lat: v}, To: "B"})
			return err
		}},
		{"directions destination", "to.lng", func(v float64) error {
			_, err := client.Directions(ctx, DirectionsRequest{From: "A", ToLocation: &LatLng{Lng: v}})
			return err
		}},
		{"route radius", "radius_m", func(v float64) error {
			_, err := client.Route(ctx, RouteRequest{Query: "coffee", From: "A", To: "B", RadiusM: v})
			return err
		}},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			for _, value := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
				before := calls.Load()
				err := tt.run(value)
				var validation ValidationError
				if !errors.As(err, &validation) || validation.Field != tt.field {
					t.Errorf("value %v: want validation field %s, got %v", value, tt.field, err)
				}
				if calls.Load() != before {
					t.Errorf("value %v reached HTTP", value)
				}
			}
		})
	}
}
