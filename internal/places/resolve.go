package places

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

const resolveFieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.types"

// Resolve converts a free-form location string into candidate places.
func (c *Client) Resolve(ctx context.Context, req LocationResolveRequest) (LocationResolveResponse, error) {
	req = applyResolveDefaults(req)
	if err := validateResolveRequest(req); err != nil {
		return LocationResolveResponse{}, err
	}

	body := map[string]any{
		"textQuery": req.LocationText,
		"pageSize":  req.Limit,
	}
	if strings.TrimSpace(req.Language) != "" {
		body["languageCode"] = strings.TrimSpace(req.Language)
	}
	if strings.TrimSpace(req.Region) != "" {
		body["regionCode"] = strings.TrimSpace(req.Region)
	}

	endpoint, err := c.buildURL("/places:searchText", nil)
	if err != nil {
		return LocationResolveResponse{}, err
	}
	payload, err := c.doRequest(ctx, http.MethodPost, endpoint, body, resolveFieldMask)
	if err != nil {
		return LocationResolveResponse{}, err
	}

	var response searchResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return LocationResolveResponse{}, fmt.Errorf("goplaces: decode resolve response: %w", err)
	}

	results := make([]ResolvedLocation, 0, len(response.Places))
	for _, place := range response.Places {
		results = append(results, mapResolvedLocation(place))
	}

	return LocationResolveResponse{Results: results}, nil
}

func mapResolvedLocation(place placeItem) ResolvedLocation {
	return ResolvedLocation{
		PlaceID:  place.ID,
		Name:     displayName(place.DisplayName),
		Address:  place.FormattedAddress,
		Location: mapLatLng(place.Location),
		Types:    place.Types,
	}
}

func applyResolveDefaults(req LocationResolveRequest) LocationResolveRequest {
	if req.Limit == 0 {
		req.Limit = defaultResolveLimit
	}
	return req
}

func validateResolveRequest(req LocationResolveRequest) error {
	if strings.TrimSpace(req.LocationText) == "" {
		return ValidationError{Field: "location_text", Message: validationMessageRequired}
	}
	if req.Limit < 1 || req.Limit > maxResolveLimit {
		return ValidationError{Field: validationFieldLimit, Message: fmt.Sprintf("must be 1-%d", maxResolveLimit)}
	}
	return nil
}
