package places

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

const maxNearbyTypes = 50

const nearbyFieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.priceLevel,places.types,places.currentOpeningHours,places.businessStatus"

// NearbySearch performs a nearby search around a location restriction.
func (c *Client) NearbySearch(ctx context.Context, req NearbySearchRequest) (NearbySearchResponse, error) {
	req = applyNearbyDefaults(req)
	if err := validateNearbyRequest(req); err != nil {
		return NearbySearchResponse{}, err
	}

	body := map[string]any{
		"locationRestriction": circlePayload(req.LocationRestriction),
		"maxResultCount":      req.Limit,
	}
	setLocale(body, req.Language, req.Region)
	if len(req.IncludedTypes) > 0 {
		body["includedTypes"] = req.IncludedTypes
	}
	if len(req.ExcludedTypes) > 0 {
		body["excludedTypes"] = req.ExcludedTypes
	}

	endpoint, err := c.buildURL("/places:searchNearby", nil)
	if err != nil {
		return NearbySearchResponse{}, err
	}
	payload, err := c.doRequest(ctx, http.MethodPost, endpoint, body, nearbyFieldMask)
	if err != nil {
		return NearbySearchResponse{}, err
	}

	var response searchResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return NearbySearchResponse{}, fmt.Errorf("goplaces: decode nearby response: %w", err)
	}

	results := mapPlaceSummaries(response.Places)

	return NearbySearchResponse{Results: results, NextPageToken: response.NextPageToken}, nil
}

func applyNearbyDefaults(req NearbySearchRequest) NearbySearchRequest {
	if req.Limit == 0 {
		req.Limit = defaultNearbyLimit
	}
	return req
}

func validateNearbyRequest(req NearbySearchRequest) error {
	if req.LocationRestriction == nil {
		return ValidationError{Field: "location_restriction", Message: validationMessageRequired}
	}
	if err := validateCircle(req.LocationRestriction, "location_restriction"); err != nil {
		return err
	}
	if req.Limit < 1 || req.Limit > maxNearbyLimit {
		return ValidationError{Field: validationFieldLimit, Message: fmt.Sprintf("must be 1-%d", maxNearbyLimit)}
	}
	if len(req.IncludedTypes) > maxNearbyTypes {
		return ValidationError{Field: "included_types", Message: fmt.Sprintf("must contain at most %d types", maxNearbyTypes)}
	}
	if len(req.ExcludedTypes) > maxNearbyTypes {
		return ValidationError{Field: "excluded_types", Message: fmt.Sprintf("must contain at most %d types", maxNearbyTypes)}
	}
	included := make(map[string]struct{}, len(req.IncludedTypes))
	for _, placeType := range req.IncludedTypes {
		included[placeType] = struct{}{}
	}
	for _, placeType := range req.ExcludedTypes {
		if _, exists := included[placeType]; exists {
			return ValidationError{Field: "excluded_types", Message: "must not overlap included_types"}
		}
	}
	return nil
}
