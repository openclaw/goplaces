package goplaces

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

const (
	defaultDirectionsBaseURL = "https://maps.googleapis.com/maps/api/directions/json"
)

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

var directionsModes = map[string]struct{}{
	directionsModeWalk:    {},
	directionsModeDrive:   {},
	directionsModeBicycle: {},
	directionsModeTransit: {},
}

var directionsUnits = map[string]struct{}{
	directionsUnitsMetric:   {},
	directionsUnitsImperial: {},
}

// DirectionsRequest describes a directions query between two locations.
type DirectionsRequest struct {
	From         string  `json:"from,omitempty"`
	To           string  `json:"to,omitempty"`
	FromPlaceID  string  `json:"from_place_id,omitempty"`
	ToPlaceID    string  `json:"to_place_id,omitempty"`
	FromLocation *LatLng `json:"from_location,omitempty"`
	ToLocation   *LatLng `json:"to_location,omitempty"`
	Mode         string  `json:"mode,omitempty"`
	Language     string  `json:"language,omitempty"`
	Region       string  `json:"region,omitempty"`
	Units        string  `json:"units,omitempty"`
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

// Directions fetches directions between two locations using the Google Directions API.
func (c *Client) Directions(ctx context.Context, req DirectionsRequest) (DirectionsResponse, error) {
	req = applyDirectionsDefaults(req)
	if err := validateDirectionsRequest(req); err != nil {
		return DirectionsResponse{}, err
	}

	origin, err := resolveDirectionsLocation("from", req.FromPlaceID, req.FromLocation, req.From)
	if err != nil {
		return DirectionsResponse{}, err
	}
	destination, err := resolveDirectionsLocation("to", req.ToPlaceID, req.ToLocation, req.To)
	if err != nil {
		return DirectionsResponse{}, err
	}

	query := map[string]string{
		"origin":      origin,
		"destination": destination,
		"mode":        req.Mode,
	}
	if strings.TrimSpace(req.Language) != "" {
		query["language"] = req.Language
	}
	if strings.TrimSpace(req.Region) != "" {
		query["region"] = req.Region
	}
	if strings.TrimSpace(req.Units) != "" {
		query["units"] = req.Units
	}

	endpoint, err := buildDirectionsURL(c.directionsBaseURL, query, c.apiKey)
	if err != nil {
		return DirectionsResponse{}, err
	}

	payload, err := c.doDirectionsRequest(ctx, endpoint)
	if err != nil {
		return DirectionsResponse{}, err
	}

	var apiResponse directionsAPIResponse
	if err := json.Unmarshal(payload, &apiResponse); err != nil {
		return DirectionsResponse{}, fmt.Errorf("goplaces: decode directions response: %w", err)
	}
	if apiResponse.Status != "OK" {
		return DirectionsResponse{}, fmt.Errorf("goplaces: directions status %s: %s", apiResponse.Status, strings.TrimSpace(apiResponse.ErrorMessage))
	}
	if len(apiResponse.Routes) == 0 || len(apiResponse.Routes[0].Legs) == 0 {
		return DirectionsResponse{}, errors.New("goplaces: no directions returned")
	}

	route := apiResponse.Routes[0]
	leg := route.Legs[0]
	steps := make([]DirectionsStep, 0, len(leg.Steps))
	for _, step := range leg.Steps {
		steps = append(steps, DirectionsStep{
			Instruction:     cleanInstruction(step.HTMLInstructions),
			DistanceText:    step.Distance.Text,
			DistanceMeters:  step.Distance.Value,
			DurationText:    step.Duration.Text,
			DurationSeconds: step.Duration.Value,
			TravelMode:      step.TravelMode,
			Maneuver:        step.Maneuver,
		})
	}

	return DirectionsResponse{
		Mode:            strings.ToUpper(req.Mode),
		Summary:         route.Summary,
		StartAddress:    leg.StartAddress,
		EndAddress:      leg.EndAddress,
		DistanceText:    leg.Distance.Text,
		DistanceMeters:  leg.Distance.Value,
		DurationText:    leg.Duration.Text,
		DurationSeconds: leg.Duration.Value,
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
	return nil
}

func validateDirectionsLocation(label string, placeID string, location *LatLng, text string) error {
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

func resolveDirectionsLocation(label string, placeID string, location *LatLng, text string) (string, error) {
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

func buildDirectionsURL(base string, query map[string]string, apiKey string) (string, error) {
	if strings.TrimSpace(apiKey) == "" {
		return "", ErrMissingAPIKey
	}
	parsed, err := url.Parse(base)
	if err != nil {
		return "", fmt.Errorf("goplaces: invalid directions url: %w", err)
	}
	values := parsed.Query()
	for key, value := range query {
		if strings.TrimSpace(value) == "" {
			continue
		}
		values.Set(key, value)
	}
	values.Set("key", apiKey)
	parsed.RawQuery = values.Encode()
	return parsed.String(), nil
}

func (c *Client) doDirectionsRequest(ctx context.Context, endpoint string) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("goplaces: build directions request: %w", err)
	}

	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("goplaces: directions request failed: %w", err)
	}
	defer func() {
		_ = response.Body.Close()
	}()

	payload, err := readResponseBody(response)
	if err != nil {
		return nil, err
	}

	if response.StatusCode >= http.StatusBadRequest {
		apiErr := &APIError{StatusCode: response.StatusCode, Body: strings.TrimSpace(string(payload))}
		return nil, apiErr
	}

	return payload, nil
}

type directionsAPIResponse struct {
	Status       string            `json:"status"`
	ErrorMessage string            `json:"error_message,omitempty"`
	Routes       []directionsRoute `json:"routes"`
}

type directionsRoute struct {
	Summary  string          `json:"summary,omitempty"`
	Warnings []string        `json:"warnings,omitempty"`
	Legs     []directionsLeg `json:"legs"`
}

type directionsLeg struct {
	Distance     directionsValue  `json:"distance"`
	Duration     directionsValue  `json:"duration"`
	StartAddress string           `json:"start_address,omitempty"`
	EndAddress   string           `json:"end_address,omitempty"`
	Steps        []directionsStep `json:"steps"`
}

type directionsStep struct {
	HTMLInstructions string          `json:"html_instructions,omitempty"`
	Distance         directionsValue `json:"distance"`
	Duration         directionsValue `json:"duration"`
	TravelMode       string          `json:"travel_mode,omitempty"`
	Maneuver         string          `json:"maneuver,omitempty"`
}

type directionsValue struct {
	Text  string `json:"text,omitempty"`
	Value int    `json:"value,omitempty"`
}

var htmlTagPattern = regexp.MustCompile(`<[^>]+>`)

func cleanInstruction(input string) string {
	cleaned := htmlTagPattern.ReplaceAllString(input, "")
	cleaned = html.UnescapeString(cleaned)
	cleaned = strings.TrimSpace(cleaned)
	cleaned = strings.Join(strings.Fields(cleaned), " ")
	return cleaned
}

func readResponseBody(response *http.Response) ([]byte, error) {
	payload, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("goplaces: read response: %w", err)
	}
	if len(payload) == 0 {
		return nil, errors.New("goplaces: empty response")
	}
	return payload, nil
}
