package places

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strings"
)

const (
	defaultRoutesBaseURL = "https://routes.googleapis.com"
	routesPath           = "/directions/v2:computeRoutes"
	routesFieldMask      = "routes.polyline.encodedPolyline"
)

const (
	defaultRouteLimit      = 5
	defaultRouteRadiusM    = 1000
	defaultRouteWaypoints  = 5
	maxRouteWaypoints      = 20
	maxRouteSearchParallel = 4
	earthRadiusMeters      = 6371000.0
	routePolylinePrecision = 1e5
)

const (
	travelModeDrive      = "DRIVE"
	travelModeWalk       = "WALK"
	travelModeBicycle    = "BICYCLE"
	travelModeTwoWheeler = "TWO_WHEELER"
	travelModeTransit    = "TRANSIT"
)

var travelModes = map[string]struct{}{
	travelModeDrive:      {},
	travelModeWalk:       {},
	travelModeBicycle:    {},
	travelModeTwoWheeler: {},
	travelModeTransit:    {},
}

// RouteRequest describes a query to search along a route.
type RouteRequest struct {
	Query        string  `json:"query"`
	From         string  `json:"from"`
	To           string  `json:"to"`
	Mode         string  `json:"mode,omitempty"`
	RadiusM      float64 `json:"radius_m,omitempty"`
	MaxWaypoints int     `json:"max_waypoints,omitempty"`
	Limit        int     `json:"limit,omitempty"`
	Language     string  `json:"language,omitempty"`
	Region       string  `json:"region,omitempty"`
}

// RouteResponse contains sampled waypoints with search results.
type RouteResponse struct {
	Waypoints []RouteWaypoint `json:"waypoints"`
}

// RouteWaypoint ties a sampled route location to search results.
type RouteWaypoint struct {
	Location LatLng         `json:"location"`
	Results  []PlaceSummary `json:"results"`
}

// Route searches for places along a route between two locations.
func (c *Client) Route(ctx context.Context, req RouteRequest) (RouteResponse, error) {
	req = applyRouteDefaults(req)
	if err := validateRouteRequest(req); err != nil {
		return RouteResponse{}, err
	}

	polyline, err := c.computeRoutePolyline(ctx, req)
	if err != nil {
		return RouteResponse{}, err
	}

	points, err := decodePolyline(polyline)
	if err != nil {
		return RouteResponse{}, err
	}

	waypoints := sampleWaypoints(points, req.MaxWaypoints)
	if len(waypoints) == 0 {
		return RouteResponse{}, errors.New("goplaces: no route waypoints")
	}

	results, err := c.searchRouteWaypoints(ctx, req, waypoints)
	if err != nil {
		return RouteResponse{}, err
	}

	return RouteResponse{Waypoints: results}, nil
}

type routeSearchResult struct {
	index    int
	waypoint LatLng
	response SearchResponse
	err      error
}

func (c *Client) searchRouteWaypoints(ctx context.Context, req RouteRequest, waypoints []LatLng) ([]RouteWaypoint, error) {
	searchCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	parallel := min(maxRouteSearchParallel, len(waypoints))
	sem := make(chan struct{}, parallel)
	responses := make(chan routeSearchResult, len(waypoints))

	for index, waypoint := range waypoints {
		go func(index int, waypoint LatLng) {
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-searchCtx.Done():
				responses <- routeSearchResult{index: index, waypoint: waypoint, err: searchCtx.Err()}
				return
			}

			response, err := c.Search(searchCtx, SearchRequest{
				Query:    req.Query,
				Limit:    req.Limit,
				Language: req.Language,
				Region:   req.Region,
				LocationBias: &LocationBias{
					Lat:     waypoint.Lat,
					Lng:     waypoint.Lng,
					RadiusM: req.RadiusM,
				},
			})
			responses <- routeSearchResult{index: index, waypoint: waypoint, response: response, err: err}
		}(index, waypoint)
	}

	collected := make([]routeSearchResult, len(waypoints))
	var firstErr error
	for range waypoints {
		result := <-responses
		collected[result.index] = result
		if result.err != nil && firstErr == nil {
			firstErr = result.err
			cancel()
		}
	}
	if firstErr != nil {
		return nil, firstErr
	}

	seen := make(map[string]struct{})
	results := make([]RouteWaypoint, 0, len(waypoints))
	for _, result := range collected {
		results = append(results, RouteWaypoint{
			Location: result.waypoint,
			Results:  dedupePlaceSummaries(result.response.Results, seen),
		})
	}
	return results, nil
}

func dedupePlaceSummaries(results []PlaceSummary, seen map[string]struct{}) []PlaceSummary {
	deduped := make([]PlaceSummary, 0, len(results))
	for _, result := range results {
		id := strings.TrimSpace(result.PlaceID)
		if id != "" {
			if _, ok := seen[id]; ok {
				continue
			}
			seen[id] = struct{}{}
		}
		deduped = append(deduped, result)
	}
	return deduped
}

func applyRouteDefaults(req RouteRequest) RouteRequest {
	req.Query = strings.TrimSpace(req.Query)
	req.From = strings.TrimSpace(req.From)
	req.To = strings.TrimSpace(req.To)
	req.Mode = strings.ToUpper(strings.TrimSpace(req.Mode))
	if req.Mode == "" {
		req.Mode = travelModeDrive
	}
	if req.Limit == 0 {
		req.Limit = defaultRouteLimit
	}
	if req.RadiusM == 0 {
		req.RadiusM = defaultRouteRadiusM
	}
	if req.MaxWaypoints == 0 {
		req.MaxWaypoints = defaultRouteWaypoints
	}
	return req
}

func validateRouteRequest(req RouteRequest) error {
	if req.Query == "" {
		return ValidationError{Field: validationFieldQuery, Message: validationMessageRequired}
	}
	if req.From == "" {
		return ValidationError{Field: validationFieldFrom, Message: validationMessageRequired}
	}
	if req.To == "" {
		return ValidationError{Field: "to", Message: validationMessageRequired}
	}
	if req.Limit < 1 || req.Limit > maxSearchLimit {
		return ValidationError{Field: validationFieldLimit, Message: fmt.Sprintf("must be 1-%d", maxSearchLimit)}
	}
	if req.RadiusM <= 0 {
		return ValidationError{Field: validationFieldRadiusM, Message: "must be > 0"}
	}
	if req.RadiusM > maxCircleRadiusM {
		return ValidationError{Field: validationFieldRadiusM, Message: fmt.Sprintf("must be <= %d", maxCircleRadiusM)}
	}
	if req.MaxWaypoints < 1 || req.MaxWaypoints > maxRouteWaypoints {
		return ValidationError{Field: "max_waypoints", Message: fmt.Sprintf("must be 1-%d", maxRouteWaypoints)}
	}
	if _, ok := travelModes[req.Mode]; !ok {
		return ValidationError{Field: "mode", Message: "must be DRIVE, WALK, BICYCLE, TWO_WHEELER, or TRANSIT"}
	}
	return nil
}

func (c *Client) computeRoutePolyline(ctx context.Context, req RouteRequest) (string, error) {
	body := map[string]any{
		"origin": map[string]any{
			payloadFieldAddress: req.From,
		},
		"destination": map[string]any{
			payloadFieldAddress: req.To,
		},
		"travelMode":       req.Mode,
		"polylineQuality":  "OVERVIEW",
		"polylineEncoding": "ENCODED_POLYLINE",
	}
	if req.Language != "" {
		body["languageCode"] = req.Language
	}
	if req.Region != "" {
		body["regionCode"] = req.Region
	}

	endpoint := routesEndpoint(c.routesBaseURL)
	payload, err := c.doRequest(ctx, http.MethodPost, endpoint, body, routesFieldMask)
	if err != nil {
		return "", err
	}

	var response routesResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return "", fmt.Errorf("goplaces: decode route response: %w", err)
	}
	if len(response.Routes) == 0 {
		return "", errors.New("goplaces: no routes returned")
	}
	polyline := strings.TrimSpace(response.Routes[0].Polyline.EncodedPolyline)
	if polyline == "" {
		return "", errors.New("goplaces: empty route polyline")
	}
	return polyline, nil
}

func routesEndpoint(base string) string {
	if strings.HasSuffix(base, routesPath) {
		return base
	}
	return base + routesPath
}

func decodePolyline(encoded string) ([]LatLng, error) {
	if strings.TrimSpace(encoded) == "" {
		return nil, errors.New("goplaces: empty polyline")
	}
	points := make([]LatLng, 0, len(encoded)/4)
	var lat, lng int
	for i := 0; i < len(encoded); {
		var delta int
		var shift uint
		for {
			if i >= len(encoded) {
				return nil, errors.New("goplaces: invalid polyline")
			}
			b := int(encoded[i]) - 63
			i++
			delta |= (b & 0x1f) << shift
			shift += 5
			if b < 0x20 {
				break
			}
		}
		lat += (delta >> 1) ^ (-(delta & 1))

		delta = 0
		shift = 0
		for {
			if i >= len(encoded) {
				return nil, errors.New("goplaces: invalid polyline")
			}
			b := int(encoded[i]) - 63
			i++
			delta |= (b & 0x1f) << shift
			shift += 5
			if b < 0x20 {
				break
			}
		}
		lng += (delta >> 1) ^ (-(delta & 1))

		points = append(points, LatLng{
			Lat: float64(lat) / routePolylinePrecision,
			Lng: float64(lng) / routePolylinePrecision,
		})
	}
	return points, nil
}

func sampleWaypoints(points []LatLng, maxWaypoints int) []LatLng {
	if len(points) == 0 || maxWaypoints <= 0 {
		return nil
	}
	if len(points) == 1 {
		return []LatLng{points[0]}
	}
	if maxWaypoints == 1 {
		return []LatLng{pointAtDistance(points, totalDistance(points)/2)}
	}
	if maxWaypoints >= len(points) {
		return uniqueWaypoints(points)
	}

	cumulative := cumulativeDistances(points)
	total := cumulative[len(cumulative)-1]
	if total == 0 {
		return []LatLng{points[0]}
	}
	spacing := total / float64(maxWaypoints-1)

	sampled := make([]LatLng, 0, maxWaypoints)
	for i := 0; i < maxWaypoints; i++ {
		target := spacing * float64(i)
		point := pointAtCumulative(points, cumulative, target)
		if len(sampled) == 0 || !samePoint(sampled[len(sampled)-1], point) {
			sampled = append(sampled, point)
		}
	}
	return sampled
}

func cumulativeDistances(points []LatLng) []float64 {
	distances := make([]float64, len(points))
	for i := 1; i < len(points); i++ {
		distances[i] = distances[i-1] + distanceMeters(points[i-1], points[i])
	}
	return distances
}

func totalDistance(points []LatLng) float64 {
	if len(points) < 2 {
		return 0
	}
	var total float64
	for i := 1; i < len(points); i++ {
		total += distanceMeters(points[i-1], points[i])
	}
	return total
}

func pointAtDistance(points []LatLng, target float64) LatLng {
	if len(points) == 0 {
		return LatLng{}
	}
	cumulative := cumulativeDistances(points)
	return pointAtCumulative(points, cumulative, target)
}

func pointAtCumulative(points []LatLng, cumulative []float64, target float64) LatLng {
	if target <= 0 {
		return points[0]
	}
	total := cumulative[len(cumulative)-1]
	if target >= total {
		return points[len(points)-1]
	}
	index := sort.Search(len(cumulative), func(i int) bool {
		return cumulative[i] >= target
	})
	if index == 0 {
		return points[0]
	}
	prev := points[index-1]
	next := points[index]
	segment := cumulative[index] - cumulative[index-1]
	if segment <= 0 {
		return next
	}
	fraction := (target - cumulative[index-1]) / segment
	return LatLng{
		Lat: prev.Lat + (next.Lat-prev.Lat)*fraction,
		Lng: prev.Lng + (next.Lng-prev.Lng)*fraction,
	}
}

func uniqueWaypoints(points []LatLng) []LatLng {
	result := make([]LatLng, 0, len(points))
	for _, point := range points {
		if len(result) == 0 || !samePoint(result[len(result)-1], point) {
			result = append(result, point)
		}
	}
	return result
}

func samePoint(a, b LatLng) bool {
	const epsilon = 1e-6
	return math.Abs(a.Lat-b.Lat) < epsilon && math.Abs(a.Lng-b.Lng) < epsilon
}

func distanceMeters(a, b LatLng) float64 {
	lat1 := a.Lat * math.Pi / 180
	lat2 := b.Lat * math.Pi / 180
	dlat := (b.Lat - a.Lat) * math.Pi / 180
	dlng := (b.Lng - a.Lng) * math.Pi / 180

	sinDLat := math.Sin(dlat / 2)
	sinDLng := math.Sin(dlng / 2)
	value := sinDLat*sinDLat + math.Cos(lat1)*math.Cos(lat2)*sinDLng*sinDLng
	return 2 * earthRadiusMeters * math.Asin(math.Sqrt(value))
}

type routesResponse struct {
	Routes []routeItem `json:"routes"`
}

type routeItem struct {
	Polyline routePolyline `json:"polyline"`
}

type routePolyline struct {
	EncodedPolyline string `json:"encodedPolyline"`
}
