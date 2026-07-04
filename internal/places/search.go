package places

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

const searchFieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.priceLevel,places.types,places.currentOpeningHours,places.businessStatus,nextPageToken"

// Search performs a text search with optional filters.
func (c *Client) Search(ctx context.Context, req SearchRequest) (SearchResponse, error) {
	req = applySearchDefaults(req)
	if err := validateSearchRequest(req); err != nil {
		return SearchResponse{}, err
	}

	body := buildSearchBody(req)
	endpoint, err := c.buildURL("/places:searchText", nil)
	if err != nil {
		return SearchResponse{}, err
	}
	payload, err := c.doRequest(ctx, http.MethodPost, endpoint, body, searchFieldMask)
	if err != nil {
		return SearchResponse{}, err
	}

	var response searchResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return SearchResponse{}, fmt.Errorf("goplaces: decode search response: %w", err)
	}

	results := make([]PlaceSummary, 0, len(response.Places))
	for _, place := range response.Places {
		results = append(results, mapPlaceSummary(place))
	}

	return SearchResponse{
		Results:       results,
		NextPageToken: response.NextPageToken,
	}, nil
}

func buildSearchBody(req SearchRequest) map[string]any {
	textQuery := req.Query
	if req.Filters != nil && strings.TrimSpace(req.Filters.Keyword) != "" {
		// Google expects a single text query; append keywords here.
		textQuery = strings.TrimSpace(textQuery + " " + req.Filters.Keyword)
	}

	body := map[string]any{
		"textQuery": textQuery,
		"pageSize":  req.Limit,
	}
	if strings.TrimSpace(req.Language) != "" {
		body["languageCode"] = strings.TrimSpace(req.Language)
	}
	if strings.TrimSpace(req.Region) != "" {
		body["regionCode"] = strings.TrimSpace(req.Region)
	}

	if req.PageToken != "" {
		body["pageToken"] = req.PageToken
	}

	if req.LocationBias != nil {
		// Places API expects a circular bias object.
		body["locationBias"] = circlePayload(req.LocationBias)
	}

	if req.Filters != nil {
		filters := req.Filters
		if len(filters.Types) > 0 {
			// API accepts a single includedType; use the first value.
			body["includedType"] = filters.Types[0]
		}
		if filters.OpenNow != nil {
			body["openNow"] = *filters.OpenNow
		}
		if filters.MinRating != nil {
			body["minRating"] = *filters.MinRating
		}
		if len(filters.PriceLevels) > 0 {
			levels := make([]string, 0, len(filters.PriceLevels))
			for _, level := range filters.PriceLevels {
				if mapped, ok := priceLevelToEnum[level]; ok {
					levels = append(levels, mapped)
				}
			}
			if len(levels) > 0 {
				body["priceLevels"] = levels
			}
		}
	}

	return body
}

func mapPlaceSummary(place placeItem) PlaceSummary {
	return PlaceSummary{
		PlaceID:         place.ID,
		Name:            displayName(place.DisplayName),
		Address:         place.FormattedAddress,
		Location:        mapLatLng(place.Location),
		Rating:          place.Rating,
		UserRatingCount: place.UserRatingCount,
		PriceLevel:      mapPriceLevel(place.PriceLevel),
		Types:           place.Types,
		OpenNow:         openNow(place.CurrentOpeningHours),
		BusinessStatus:  strings.TrimSpace(place.BusinessStatus),
	}
}

func applySearchDefaults(req SearchRequest) SearchRequest {
	if req.Limit == 0 {
		req.Limit = defaultSearchLimit
	}
	return req
}

func validateSearchRequest(req SearchRequest) error {
	if strings.TrimSpace(req.Query) == "" {
		return ValidationError{Field: validationFieldQuery, Message: validationMessageRequired}
	}
	if req.Limit < 1 || req.Limit > maxSearchLimit {
		return ValidationError{Field: validationFieldLimit, Message: fmt.Sprintf("must be 1-%d", maxSearchLimit)}
	}

	if req.Filters != nil {
		if req.Filters.MinRating != nil {
			if *req.Filters.MinRating < 0 || *req.Filters.MinRating > 5 {
				return ValidationError{Field: "filters.min_rating", Message: "must be 0-5"}
			}
		}
		for _, level := range req.Filters.PriceLevels {
			if level < 0 || level > 4 {
				return ValidationError{Field: "filters.price_levels", Message: "must be 0-4"}
			}
		}
	}

	if req.LocationBias != nil {
		if err := validateLocationBias(req.LocationBias); err != nil {
			return err
		}
	}

	return nil
}
