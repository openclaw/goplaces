package places

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

const autocompleteFieldMask = "suggestions.placePrediction.placeId,suggestions.placePrediction.place,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.types,suggestions.placePrediction.distanceMeters,suggestions.queryPrediction.text,suggestions.queryPrediction.structuredFormat"

// Autocomplete returns place and query suggestions for an input string.
func (c *Client) Autocomplete(ctx context.Context, req AutocompleteRequest) (AutocompleteResponse, error) {
	req = applyAutocompleteDefaults(req)
	if err := validateAutocompleteRequest(req); err != nil {
		return AutocompleteResponse{}, err
	}

	body := map[string]any{
		"input": strings.TrimSpace(req.Input),
	}
	if strings.TrimSpace(req.SessionToken) != "" {
		body["sessionToken"] = strings.TrimSpace(req.SessionToken)
	}
	if strings.TrimSpace(req.Language) != "" {
		body["languageCode"] = strings.TrimSpace(req.Language)
	}
	if strings.TrimSpace(req.Region) != "" {
		body["regionCode"] = strings.TrimSpace(req.Region)
	}
	if req.LocationBias != nil {
		body["locationBias"] = circlePayload(req.LocationBias)
	}

	endpoint, err := c.buildURL("/places:autocomplete", nil)
	if err != nil {
		return AutocompleteResponse{}, err
	}
	payload, err := c.doRequest(ctx, http.MethodPost, endpoint, body, autocompleteFieldMask)
	if err != nil {
		return AutocompleteResponse{}, err
	}

	var response autocompleteResponsePayload
	if err := json.Unmarshal(payload, &response); err != nil {
		return AutocompleteResponse{}, fmt.Errorf("goplaces: decode autocomplete response: %w", err)
	}

	suggestions := make([]AutocompleteSuggestion, 0, len(response.Suggestions))
	for _, suggestion := range response.Suggestions {
		mapped, ok := mapAutocompleteSuggestion(suggestion)
		if !ok {
			continue
		}
		suggestions = append(suggestions, mapped)
	}

	if req.Limit > 0 && len(suggestions) > req.Limit {
		suggestions = suggestions[:req.Limit]
	}

	return AutocompleteResponse{Suggestions: suggestions}, nil
}

type autocompleteResponsePayload struct {
	Suggestions []autocompleteSuggestionPayload `json:"suggestions"`
}

type autocompleteSuggestionPayload struct {
	PlacePrediction *placePredictionPayload `json:"placePrediction,omitempty"`
	QueryPrediction *queryPredictionPayload `json:"queryPrediction,omitempty"`
}

type placePredictionPayload struct {
	PlaceID          string                   `json:"placeId,omitempty"`
	Place            string                   `json:"place,omitempty"`
	Text             *autocompleteTextPayload `json:"text,omitempty"`
	StructuredFormat *structuredFormatPayload `json:"structuredFormat,omitempty"`
	Types            []string                 `json:"types,omitempty"`
	DistanceMeters   *int                     `json:"distanceMeters,omitempty"`
}

type queryPredictionPayload struct {
	Text             *autocompleteTextPayload `json:"text,omitempty"`
	StructuredFormat *structuredFormatPayload `json:"structuredFormat,omitempty"`
}

type structuredFormatPayload struct {
	MainText      *autocompleteTextPayload `json:"mainText,omitempty"`
	SecondaryText *autocompleteTextPayload `json:"secondaryText,omitempty"`
}

type autocompleteTextPayload struct {
	Text string `json:"text,omitempty"`
}

func mapAutocompleteSuggestion(payload autocompleteSuggestionPayload) (AutocompleteSuggestion, bool) {
	if payload.PlacePrediction != nil {
		prediction := payload.PlacePrediction
		structured := prediction.StructuredFormat
		return AutocompleteSuggestion{
			Kind:           "place",
			PlaceID:        prediction.PlaceID,
			Place:          prediction.Place,
			Text:           autocompleteText(prediction.Text),
			MainText:       autocompleteText(structuredText(structured, true)),
			SecondaryText:  autocompleteText(structuredText(structured, false)),
			Types:          prediction.Types,
			DistanceMeters: prediction.DistanceMeters,
		}, true
	}
	if payload.QueryPrediction != nil {
		prediction := payload.QueryPrediction
		structured := prediction.StructuredFormat
		return AutocompleteSuggestion{
			Kind:          "query",
			Text:          autocompleteText(prediction.Text),
			MainText:      autocompleteText(structuredText(structured, true)),
			SecondaryText: autocompleteText(structuredText(structured, false)),
		}, true
	}
	return AutocompleteSuggestion{}, false
}

func structuredText(payload *structuredFormatPayload, main bool) *autocompleteTextPayload {
	if payload == nil {
		return nil
	}
	if main {
		return payload.MainText
	}
	return payload.SecondaryText
}

func autocompleteText(payload *autocompleteTextPayload) string {
	if payload == nil {
		return ""
	}
	return payload.Text
}

func applyAutocompleteDefaults(req AutocompleteRequest) AutocompleteRequest {
	if req.Limit == 0 {
		req.Limit = defaultAutocompleteLimit
	}
	return req
}

func validateAutocompleteRequest(req AutocompleteRequest) error {
	if strings.TrimSpace(req.Input) == "" {
		return ValidationError{Field: "input", Message: "required"}
	}
	if req.Limit < 1 || req.Limit > maxAutocompleteLimit {
		return ValidationError{Field: "limit", Message: fmt.Sprintf("must be 1-%d", maxAutocompleteLimit)}
	}
	if req.LocationBias != nil {
		if err := validateLocationBias(req.LocationBias); err != nil {
			return err
		}
	}
	return nil
}
