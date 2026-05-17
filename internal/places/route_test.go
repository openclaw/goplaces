package places

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestComputeRoutePolyline(t *testing.T) {
	var gotBody map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != routesPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Header.Get("X-Goog-FieldMask") != routesFieldMask {
			t.Fatalf("unexpected field mask: %s", r.Header.Get("X-Goog-FieldMask"))
		}
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		_, _ = w.Write([]byte("{\"routes\": [{\"polyline\": {\"encodedPolyline\": \"_p~iF~ps|U_ulLnnqC_mqNvxq`@\"}}]}"))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", RoutesBaseURL: server.URL})
	polyline, err := client.computeRoutePolyline(context.Background(), RouteRequest{
		From: "Seattle",
		To:   "Portland",
		Mode: travelModeDrive,
	})
	if err != nil {
		t.Fatalf("computeRoutePolyline error: %v", err)
	}
	if polyline == "" {
		t.Fatalf("expected polyline")
	}
	if gotBody["travelMode"] != travelModeDrive {
		t.Fatalf("unexpected travelMode: %#v", gotBody["travelMode"])
	}
}

func TestComputeRoutePolylineFullBaseURL(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != routesPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte("{\"routes\": [{\"polyline\": {\"encodedPolyline\": \"_p~iF~ps|U\"}}]}"))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", RoutesBaseURL: server.URL + routesPath})
	polyline, err := client.computeRoutePolyline(context.Background(), RouteRequest{
		From: "Seattle",
		To:   "Portland",
		Mode: travelModeDrive,
	})
	if err != nil {
		t.Fatalf("computeRoutePolyline error: %v", err)
	}
	if polyline == "" {
		t.Fatalf("expected polyline")
	}
}

func TestDecodePolyline(t *testing.T) {
	points, err := decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
	if err != nil {
		t.Fatalf("decodePolyline error: %v", err)
	}
	if len(points) != 3 {
		t.Fatalf("expected 3 points, got %d", len(points))
	}
	if points[0].Lat != 38.5 || points[0].Lng != -120.2 {
		t.Fatalf("unexpected first point: %#v", points[0])
	}
}

func TestDecodePolylineInvalid(t *testing.T) {
	_, err := decodePolyline("")
	if err == nil {
		t.Fatalf("expected decode error")
	}
}

func TestDecodePolylineMalformed(t *testing.T) {
	_, err := decodePolyline("abc")
	if err == nil {
		t.Fatalf("expected malformed error")
	}
}

func TestSampleWaypoints(t *testing.T) {
	points := []LatLng{{Lat: 0, Lng: 0}, {Lat: 0, Lng: 1}, {Lat: 0, Lng: 2}}
	waypoints := sampleWaypoints(points, 2)
	if len(waypoints) != 2 {
		t.Fatalf("expected 2 waypoints, got %d", len(waypoints))
	}
	if waypoints[0].Lng != 0 || waypoints[1].Lng != 2 {
		t.Fatalf("unexpected waypoints: %#v", waypoints)
	}
}

func TestSampleWaypointsSingle(t *testing.T) {
	points := []LatLng{{Lat: 1, Lng: 1}, {Lat: 2, Lng: 2}}
	waypoints := sampleWaypoints(points, 1)
	if len(waypoints) != 1 {
		t.Fatalf("expected 1 waypoint")
	}
}

func TestSampleWaypointsSinglePoint(t *testing.T) {
	points := []LatLng{{Lat: 1, Lng: 1}}
	waypoints := sampleWaypoints(points, 5)
	if len(waypoints) != 1 {
		t.Fatalf("expected 1 waypoint")
	}
}

func TestSampleWaypointsZeroTotal(t *testing.T) {
	points := []LatLng{{Lat: 1, Lng: 1}, {Lat: 1, Lng: 1}}
	waypoints := sampleWaypoints(points, 3)
	if len(waypoints) != 1 {
		t.Fatalf("expected 1 waypoint")
	}
	if waypoints[0] != points[0] {
		t.Fatalf("unexpected waypoint: %#v", waypoints[0])
	}
}

func TestSampleWaypointsMaxExceedsPoints(t *testing.T) {
	points := []LatLng{{Lat: 0, Lng: 0}, {Lat: 0, Lng: 0}, {Lat: 0, Lng: 1}}
	waypoints := sampleWaypoints(points, 5)
	if len(waypoints) != 2 {
		t.Fatalf("expected 2 waypoints, got %d", len(waypoints))
	}
}

func TestPointAtDistanceBounds(t *testing.T) {
	points := []LatLng{{Lat: 0, Lng: 0}, {Lat: 0, Lng: 2}}
	cumulative := cumulativeDistances(points)
	if got := pointAtCumulative(points, cumulative, -1); got != points[0] {
		t.Fatalf("expected first point, got %#v", got)
	}
	if got := pointAtCumulative(points, cumulative, cumulative[len(cumulative)-1]+1); got != points[1] {
		t.Fatalf("expected last point, got %#v", got)
	}
}

func TestUniqueWaypoints(t *testing.T) {
	points := []LatLng{{Lat: 1, Lng: 1}, {Lat: 1, Lng: 1}, {Lat: 2, Lng: 2}}
	unique := uniqueWaypoints(points)
	if len(unique) != 2 {
		t.Fatalf("expected 2 unique points, got %d", len(unique))
	}
}

func TestDistanceMeters(t *testing.T) {
	distance := distanceMeters(LatLng{Lat: 0, Lng: 0}, LatLng{Lat: 0, Lng: 1})
	if distance <= 0 {
		t.Fatalf("expected positive distance")
	}
}

func TestTotalDistanceEmpty(t *testing.T) {
	if totalDistance([]LatLng{{Lat: 1, Lng: 1}}) != 0 {
		t.Fatalf("expected zero distance")
	}
}

func TestPointAtDistanceEmpty(t *testing.T) {
	point := pointAtDistance(nil, 10)
	if point != (LatLng{}) {
		t.Fatalf("expected empty point")
	}
}

func TestValidateRouteRequest(t *testing.T) {
	err := validateRouteRequest(RouteRequest{})
	if err == nil {
		t.Fatalf("expected error")
	}
	err = validateRouteRequest(RouteRequest{
		Query:        "coffee",
		From:         "A",
		To:           "B",
		Mode:         "FLY",
		Limit:        1,
		RadiusM:      1,
		MaxWaypoints: 1,
	})
	if err == nil {
		t.Fatalf("expected mode error")
	}
}

func TestValidateRouteRequestBounds(t *testing.T) {
	err := validateRouteRequest(RouteRequest{
		Query:        "coffee",
		From:         "A",
		To:           "B",
		Mode:         travelModeDrive,
		Limit:        0,
		RadiusM:      -1,
		MaxWaypoints: 999,
	})
	if err == nil {
		t.Fatalf("expected bounds error")
	}

	err = validateRouteRequest(RouteRequest{
		Query:        "coffee",
		From:         "A",
		To:           "B",
		Mode:         travelModeDrive,
		Limit:        1,
		RadiusM:      maxCircleRadiusM + 1,
		MaxWaypoints: 1,
	})
	var validationErr ValidationError
	if !errors.As(err, &validationErr) {
		t.Fatalf("expected validation error, got %v", err)
	}
	if validationErr.Field != "radius_m" {
		t.Fatalf("unexpected field: %s", validationErr.Field)
	}
}

func TestApplyRouteDefaults(t *testing.T) {
	req := applyRouteDefaults(RouteRequest{
		Query: " coffee ",
		From:  " A ",
		To:    " B ",
		Mode:  "walk",
	})
	if req.Mode != travelModeWalk {
		t.Fatalf("unexpected mode: %s", req.Mode)
	}
	if req.Limit != defaultRouteLimit {
		t.Fatalf("unexpected limit: %d", req.Limit)
	}
}

func TestApplyRouteDefaultsEmpty(t *testing.T) {
	req := applyRouteDefaults(RouteRequest{})
	if req.Mode != travelModeDrive {
		t.Fatalf("expected default mode")
	}
	if req.Limit != defaultRouteLimit {
		t.Fatalf("expected default limit")
	}
	if req.RadiusM != defaultRouteRadiusM {
		t.Fatalf("expected default radius")
	}
	if req.MaxWaypoints != defaultRouteWaypoints {
		t.Fatalf("expected default waypoints")
	}
}

func TestComputeRoutePolylineErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"routes":[]}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", RoutesBaseURL: server.URL})
	_, err := client.computeRoutePolyline(context.Background(), RouteRequest{From: "A", To: "B"})
	if err == nil {
		t.Fatalf("expected route error")
	}
}

func TestComputeRoutePolylineEmpty(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"routes":[{"polyline":{"encodedPolyline":""}}]}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", RoutesBaseURL: server.URL})
	_, err := client.computeRoutePolyline(context.Background(), RouteRequest{From: "A", To: "B"})
	if err == nil {
		t.Fatalf("expected empty polyline error")
	}
}

func TestComputeRoutePolylineInvalidJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("not-json"))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", RoutesBaseURL: server.URL})
	_, err := client.computeRoutePolyline(context.Background(), RouteRequest{From: "A", To: "B"})
	if err == nil {
		t.Fatalf("expected json error")
	}
}

func TestRouteEndToEnd(t *testing.T) {
	searchCalls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case routesPath:
			_, _ = w.Write([]byte("{\"routes\": [{\"polyline\": {\"encodedPolyline\": \"_p~iF~ps|U_ulLnnqC_mqNvxq`@\"}}]}"))
		case "/places:searchText":
			searchCalls++
			_, _ = w.Write([]byte(`{"places":[{"id":"abc","displayName":{"text":"Cafe"}}]}`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL, RoutesBaseURL: server.URL})
	response, err := client.Route(context.Background(), RouteRequest{
		Query: "coffee",
		From:  "Seattle",
		To:    "Portland",
	})
	if err != nil {
		t.Fatalf("route error: %v", err)
	}
	if len(response.Waypoints) == 0 {
		t.Fatalf("expected waypoints")
	}
	if searchCalls == 0 {
		t.Fatalf("expected search calls")
	}
}

func TestRouteSearchError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case routesPath:
			_, _ = w.Write([]byte("{\"routes\": [{\"polyline\": {\"encodedPolyline\": \"_p~iF~ps|U_ulLnnqC_mqNvxq`@\"}}]}"))
		case "/places:searchText":
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte("bad"))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", BaseURL: server.URL, RoutesBaseURL: server.URL})
	_, err := client.Route(context.Background(), RouteRequest{
		Query: "coffee",
		From:  "Seattle",
		To:    "Portland",
	})
	if err == nil {
		t.Fatalf("expected route error")
	}
}

func TestRouteComputeRouteError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != routesPath {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"routes":[]}`))
	}))
	defer server.Close()

	client := NewClient(Options{APIKey: "test-key", RoutesBaseURL: server.URL})
	_, err := client.Route(context.Background(), RouteRequest{
		Query: "coffee",
		From:  "A",
		To:    "B",
	})
	if err == nil {
		t.Fatalf("expected route error")
	}
}
