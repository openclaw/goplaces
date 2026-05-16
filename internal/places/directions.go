package places

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

const (
	defaultDirectionsBaseURL = defaultRoutesBaseURL
)

const directionsFieldMask = "routes.description,routes.warnings,routes.legs.distanceMeters,routes.legs.duration,routes.legs.localizedValues.distance,routes.legs.localizedValues.duration,routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,routes.legs.steps.localizedValues.distance,routes.legs.steps.localizedValues.staticDuration,routes.legs.steps.navigationInstruction.instructions,routes.legs.steps.navigationInstruction.maneuver,routes.legs.steps.travelMode"

const (
	directionsModeWalk    = "walking"
	directionsModeDrive   = "driving"
	directionsModeBicycle = "bicycling"
	directionsModeTransit = "transit"
)

const (
	directionsUnitsMetric   = "metric"
	directionsUnitsImperial = "imperial"
)

const (
	routesUnitsMetric   = "METRIC"
	routesUnitsImperial = "IMPERIAL"
)

var directionsUnits = map[string]struct{}{
	directionsUnitsMetric:   {},
	directionsUnitsImperial: {},
}

// DirectionsRequest describes a directions query between two locations.
type DirectionsRequest struct {
	From          string  `json:"from,omitempty"`
	To            string  `json:"to,omitempty"`
	FromPlaceID   string  `json:"from_place_id,omitempty"`
	ToPlaceID     string  `json:"to_place_id,omitempty"`
	FromLocation  *LatLng `json:"from_location,omitempty"`
	ToLocation    *LatLng `json:"to_location,omitempty"`
	Mode          string  `json:"mode,omitempty"`
	Language      string  `json:"language,omitempty"`
	Region        string  `json:"region,omitempty"`
	Units         string  `json:"units,omitempty"`
	AvoidTolls    bool    `json:"avoid_tolls,omitempty"`
	AvoidHighways bool    `json:"avoid_highways,omitempty"`
	AvoidFerries  bool    `json:"avoid_ferries,omitempty"`
	DepartureTime string  `json:"departure_time,omitempty"`
	ArrivalTime   string  `json:"arrival_time,omitempty"`
}

// DirectionsResponse contains a single route summary and steps.
type DirectionsResponse struct {
	Mode            string           `json:"mode"`
	Summary         string           `json:"summary,omitempty"`
	StartAddress    string           `json:"start_address,omitempty"`
	EndAddress      string           `json:"end_address,omitempty"`
	DistanceText    string           `json:"distance_text,omitempty"`
	DistanceMeters  int              `json:"distance_meters,omitempty"`
	DurationText    string           `json:"duration_text,omitempty"`
	DurationSeconds int              `json:"duration_seconds,omitempty"`
	DepartureTime   string           `json:"departure_time,omitempty"`
	ArrivalTime     string           `json:"arrival_time,omitempty"`
	Warnings        []string         `json:"warnings,omitempty"`
	Steps           []DirectionsStep `json:"steps,omitempty"`
}

// DirectionsStep is a single navigation step.
type DirectionsStep struct {
	Instruction     string `json:"instruction,omitempty"`
	DistanceText    string `json:"distance_text,omitempty"`
	DistanceMeters  int    `json:"distance_meters,omitempty"`
	DurationText    string `json:"duration_text,omitempty"`
	DurationSeconds int    `json:"duration_seconds,omitempty"`
	TravelMode      string `json:"travel_mode,omitempty"`
	Maneuver        string `json:"maneuver,omitempty"`
}

// Directions fetches directions between two locations using the Routes API.
func (c *Client) Directions(ctx context.Context, req DirectionsRequest) (DirectionsResponse, error) {
	req = applyDirectionsDefaults(req)
	if err := validateDirectionsRequest(req); err != nil {
		return DirectionsResponse{}, err
	}

	body := buildDirectionsBody(req)
	endpoint := directionsEndpoint(c.directionsBaseURL)
	payload, err := c.doRequest(ctx, http.MethodPost, endpoint, body, directionsFieldMask)
	if err != nil {
		return DirectionsResponse{}, err
	}

	var apiResponse directionsRoutesResponse
	if err := json.Unmarshal(payload, &apiResponse); err != nil {
		return DirectionsResponse{}, fmt.Errorf("goplaces: decode directions response: %w", err)
	}
	if len(apiResponse.Routes) == 0 || len(apiResponse.Routes[0].Legs) == 0 {
		return DirectionsResponse{}, errors.New("goplaces: no directions returned")
	}

	route := apiResponse.Routes[0]
	leg := route.Legs[0]
	steps := make([]DirectionsStep, 0, len(leg.Steps))
	for _, step := range leg.Steps {
		steps = append(steps, DirectionsStep{
			Instruction:     strings.TrimSpace(step.NavigationInstruction.Instructions),
			DistanceText:    strings.TrimSpace(step.LocalizedValues.Distance.Text),
			DistanceMeters:  step.DistanceMeters,
			DurationText:    strings.TrimSpace(step.LocalizedValues.StaticDuration.Text),
			DurationSeconds: parseDurationSeconds(step.StaticDuration),
			TravelMode:      strings.TrimSpace(step.TravelMode),
			Maneuver:        strings.TrimSpace(step.NavigationInstruction.Maneuver),
		})
	}

	return DirectionsResponse{
		Mode:            strings.ToUpper(req.Mode),
		Summary:         strings.TrimSpace(route.Description),
		StartAddress:    directionsLocationLabel(req.FromPlaceID, req.FromLocation, req.From),
		EndAddress:      directionsLocationLabel(req.ToPlaceID, req.ToLocation, req.To),
		DistanceText:    strings.TrimSpace(leg.LocalizedValues.Distance.Text),
		DistanceMeters:  leg.DistanceMeters,
		DurationText:    strings.TrimSpace(leg.LocalizedValues.Duration.Text),
		DurationSeconds: parseDurationSeconds(leg.Duration),
		DepartureTime:   req.DepartureTime,
		ArrivalTime:     req.ArrivalTime,
		Warnings:        route.Warnings,
		Steps:           steps,
	}, nil
}

func applyDirectionsDefaults(req DirectionsRequest) DirectionsRequest {
	req.From = strings.TrimSpace(req.From)
	req.To = strings.TrimSpace(req.To)
	req.FromPlaceID = strings.TrimSpace(req.FromPlaceID)
	req.ToPlaceID = strings.TrimSpace(req.ToPlaceID)
	req.Mode = strings.ToLower(strings.TrimSpace(req.Mode))
	if req.Mode == "" {
		req.Mode = directionsModeWalk
	}
	if normalized := normalizeDirectionsMode(req.Mode); normalized != "" {
		req.Mode = normalized
	}
	if req.Units != "" {
		req.Units = strings.ToLower(strings.TrimSpace(req.Units))
	}
	if req.Units == "" {
		req.Units = directionsUnitsMetric
	}
	req.DepartureTime = strings.TrimSpace(req.DepartureTime)
	req.ArrivalTime = strings.TrimSpace(req.ArrivalTime)
	return req
}

func validateDirectionsRequest(req DirectionsRequest) error {
	if normalizeDirectionsMode(req.Mode) == "" {
		return ValidationError{Field: "mode", Message: "must be walk, drive, bicycle, or transit"}
	}
	if err := validateDirectionsLocation("from", req.FromPlaceID, req.FromLocation, req.From); err != nil {
		return err
	}
	if err := validateDirectionsLocation("to", req.ToPlaceID, req.ToLocation, req.To); err != nil {
		return err
	}
	if req.Units != "" {
		if _, ok := directionsUnits[req.Units]; !ok {
			return ValidationError{Field: "units", Message: "must be metric or imperial"}
		}
	}
	if (req.AvoidTolls || req.AvoidHighways || req.AvoidFerries) && req.Mode != directionsModeDrive {
		return ValidationError{Field: "route_modifiers", Message: "avoid tolls/highways/ferries require drive mode"}
	}
	if req.DepartureTime != "" && req.ArrivalTime != "" {
		return ValidationError{Field: "time", Message: "use only one of departure_time or arrival_time"}
	}
	if req.DepartureTime != "" {
		if _, err := time.Parse(time.RFC3339, req.DepartureTime); err != nil {
			return ValidationError{Field: "departure_time", Message: "must be RFC3339, e.g. 2030-05-10T18:57:00-03:00"}
		}
	}
	if req.ArrivalTime != "" {
		if req.Mode != directionsModeTransit {
			return ValidationError{Field: "arrival_time", Message: "requires transit mode"}
		}
		if _, err := time.Parse(time.RFC3339, req.ArrivalTime); err != nil {
			return ValidationError{Field: "arrival_time", Message: "must be RFC3339, e.g. 2030-05-10T19:57:00-03:00"}
		}
	}
	return nil
}

func validateDirectionsLocation(label, placeID string, location *LatLng, text string) error {
	provided := 0
	if strings.TrimSpace(placeID) != "" {
		provided++
	}
	if location != nil {
		provided++
		if location.Lat < -90 || location.Lat > 90 {
			return ValidationError{Field: label + ".lat", Message: "must be -90..90"}
		}
		if location.Lng < -180 || location.Lng > 180 {
			return ValidationError{Field: label + ".lng", Message: "must be -180..180"}
		}
	}
	if strings.TrimSpace(text) != "" {
		provided++
	}
	if provided == 0 {
		return ValidationError{Field: label, Message: "required"}
	}
	if provided > 1 {
		return ValidationError{Field: label, Message: "use only one of text, place_id, or lat/lng"}
	}
	return nil
}

func resolveDirectionsLocation(label, placeID string, location *LatLng, text string) (string, error) {
	if err := validateDirectionsLocation(label, placeID, location, text); err != nil {
		return "", err
	}
	if strings.TrimSpace(placeID) != "" {
		return "place_id:" + strings.TrimSpace(placeID), nil
	}
	if location != nil {
		return fmt.Sprintf("%.6f,%.6f", location.Lat, location.Lng), nil
	}
	return strings.TrimSpace(text), nil
}

func directionsLocationLabel(placeID string, location *LatLng, text string) string {
	label, err := resolveDirectionsLocation("location", placeID, location, text)
	if err != nil {
		return ""
	}
	return label
}

func normalizeDirectionsMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "walk", "walking":
		return directionsModeWalk
	case "drive", "driving":
		return directionsModeDrive
	case "bike", "bicycle", "bicycling":
		return directionsModeBicycle
	case "transit":
		return directionsModeTransit
	default:
		return ""
	}
}

func directionsEndpoint(base string) string {
	if strings.HasSuffix(base, routesPath) {
		return base
	}
	return base + routesPath
}

func directionsTravelMode(mode string) string {
	switch normalizeDirectionsMode(mode) {
	case directionsModeWalk:
		return travelModeWalk
	case directionsModeDrive:
		return travelModeDrive
	case directionsModeBicycle:
		return travelModeBicycle
	case directionsModeTransit:
		return travelModeTransit
	default:
		return travelModeWalk
	}
}

func directionsRouteUnits(units string) string {
	switch strings.ToLower(strings.TrimSpace(units)) {
	case directionsUnitsImperial:
		return routesUnitsImperial
	default:
		return routesUnitsMetric
	}
}

func directionsWaypoint(placeID string, location *LatLng, text string) map[string]any {
	if trimmed := strings.TrimSpace(placeID); trimmed != "" {
		return map[string]any{"placeId": trimmed}
	}
	if location != nil {
		return map[string]any{
			"location": map[string]any{
				"latLng": map[string]any{
					"latitude":  location.Lat,
					"longitude": location.Lng,
				},
			},
		}
	}
	return map[string]any{"address": strings.TrimSpace(text)}
}

func buildDirectionsBody(req DirectionsRequest) map[string]any {
	body := map[string]any{
		"origin":      directionsWaypoint(req.FromPlaceID, req.FromLocation, req.From),
		"destination": directionsWaypoint(req.ToPlaceID, req.ToLocation, req.To),
		"travelMode":  directionsTravelMode(req.Mode),
		"units":       directionsRouteUnits(req.Units),
	}
	if strings.TrimSpace(req.Language) != "" {
		body["languageCode"] = strings.TrimSpace(req.Language)
	}
	if strings.TrimSpace(req.Region) != "" {
		body["regionCode"] = strings.TrimSpace(req.Region)
	}
	if req.AvoidTolls || req.AvoidHighways || req.AvoidFerries {
		body["routeModifiers"] = map[string]any{
			"avoidTolls":    req.AvoidTolls,
			"avoidHighways": req.AvoidHighways,
			"avoidFerries":  req.AvoidFerries,
		}
	}
	if req.DepartureTime != "" {
		body["departureTime"] = req.DepartureTime
		if normalizeDirectionsMode(req.Mode) == directionsModeDrive {
			body["routingPreference"] = "TRAFFIC_AWARE"
		}
	}
	if req.ArrivalTime != "" {
		body["arrivalTime"] = req.ArrivalTime
	}
	return body
}

func parseDurationSeconds(duration string) int {
	parsed, err := time.ParseDuration(strings.TrimSpace(duration))
	if err != nil {
		return 0
	}
	return int(parsed.Seconds())
}

type directionsRoutesResponse struct {
	Routes []directionsRoutesRoute `json:"routes"`
}

type directionsRoutesRoute struct {
	Description string                `json:"description,omitempty"`
	Warnings    []string              `json:"warnings,omitempty"`
	Legs        []directionsRoutesLeg `json:"legs"`
}

type directionsRoutesLeg struct {
	DistanceMeters  int                          `json:"distanceMeters"`
	Duration        string                       `json:"duration"`
	LocalizedValues directionsLegLocalizedValues `json:"localizedValues"`
	Steps           []directionsRoutesStep       `json:"steps"`
}

type directionsRoutesStep struct {
	DistanceMeters        int                             `json:"distanceMeters"`
	StaticDuration        string                          `json:"staticDuration"`
	TravelMode            string                          `json:"travelMode,omitempty"`
	NavigationInstruction directionsNavigationInstruction `json:"navigationInstruction"`
	LocalizedValues       directionsStepLocalizedValues   `json:"localizedValues"`
}

type directionsNavigationInstruction struct {
	Instructions string `json:"instructions,omitempty"`
	Maneuver     string `json:"maneuver,omitempty"`
}

type directionsLegLocalizedValues struct {
	Distance directionsLocalizedText `json:"distance"`
	Duration directionsLocalizedText `json:"duration"`
}

type directionsStepLocalizedValues struct {
	Distance       directionsLocalizedText `json:"distance"`
	StaticDuration directionsLocalizedText `json:"staticDuration"`
}

type directionsLocalizedText struct {
	Text string `json:"text,omitempty"`
}
