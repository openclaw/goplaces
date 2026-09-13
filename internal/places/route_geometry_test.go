package places

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestDecodePolylineRejectsInvalidCoordinates(t *testing.T) {
	for _, encoded := range []string{"!!", "\x7f?", strings.Repeat("~", 14), strings.Repeat("_", 8) + "??", "acidP?", "`cidP?", "?agsia@", "?`gsia@"} {
		if _, err := decodePolyline(encoded); err == nil {
			t.Errorf("accepted invalid polyline %q", encoded)
		}
	}
}

func TestSampleWaypointsAcrossDateLine(t *testing.T) {
	for _, direction := range []float64{1, -1} {
		points := []LatLng{{Lng: direction * 179}, {Lng: direction * 179.5}, {Lng: direction * -179.5}, {Lng: direction * -179}}
		for _, count := range []int{1, 3} {
			sampled := sampleWaypoints(points, count)
			if len(sampled) != count {
				t.Fatalf("sample count: %d", len(sampled))
			}
			midpoint := sampled[len(sampled)/2]
			if math.Abs(math.Abs(midpoint.Lng)-180) > 1e-6 || midpoint.Lat != 0 {
				t.Errorf("date-line midpoint: %+v", midpoint)
			}
		}
	}
	if got := uniqueWaypoints([]LatLng{{Lng: 180}, {Lng: -180}}); len(got) != 1 {
		t.Errorf("duplicate date-line points: %+v", got)
	}
}

func TestSampleWaypointsAntipodal(t *testing.T) {
	points := []LatLng{{Lat: -58.77137, Lng: 17.12345}, {Lat: 58.77137, Lng: -162.87655}}
	distance := distanceMeters(points[0], points[1])
	if math.IsNaN(distance) || math.Abs(distance-earthRadiusMeters*math.Pi) > 0.1 {
		t.Fatalf("antipodal distance: %v", distance)
	}
	sampled := sampleWaypoints(points, 1)
	if len(sampled) != 1 || math.IsNaN(sampled[0].Lat) || math.IsNaN(sampled[0].Lng) {
		t.Fatalf("antipodal waypoint: %+v", sampled)
	}
}

func TestRouteRejectsMalformedPolylineBeforeSearch(t *testing.T) {
	var searches atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != routesPath {
			searches.Add(1)
		}
		_, _ = fmt.Fprint(w, `{"routes":[{"polyline":{"encodedPolyline":"!!"}}],"places":[]}`)
	}))
	defer server.Close()
	client := NewClient(Options{APIKey: "synthetic-key", BaseURL: server.URL, RoutesBaseURL: server.URL})
	_, err := client.Route(t.Context(), RouteRequest{Query: "coffee", From: "A", To: "B"})
	var validation ValidationError
	if err == nil || errors.As(err, &validation) || !strings.Contains(err.Error(), "invalid polyline") {
		t.Fatalf("expected upstream polyline error, got %v", err)
	}
	if searches.Load() != 0 {
		t.Fatal("malformed polyline triggered place searches")
	}
}
