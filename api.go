// Package goplaces provides a Go client for the Google Places API (New).
package goplaces

import (
	"context"

	"github.com/steipete/goplaces/internal/places"
)

// DefaultBaseURL is the default endpoint for the Places API (New).
const DefaultBaseURL = places.DefaultBaseURL

// ErrMissingAPIKey indicates a missing API key.
var ErrMissingAPIKey = places.ErrMissingAPIKey

// NewClient builds a client with sane defaults.
func NewClient(opts Options) *Client {
	return &Client{inner: *places.NewClient(opts)}
}

// Client wraps access to the Google Places API.
type Client struct {
	inner places.Client
}

// Search runs a Places text search.
func (c *Client) Search(ctx context.Context, req SearchRequest) (SearchResponse, error) {
	return c.inner.Search(ctx, req)
}

// Autocomplete returns place and query suggestions for partial input.
func (c *Client) Autocomplete(ctx context.Context, req AutocompleteRequest) (AutocompleteResponse, error) {
	return c.inner.Autocomplete(ctx, req)
}

// NearbySearch searches places near a lat/lng radius.
func (c *Client) NearbySearch(ctx context.Context, req NearbySearchRequest) (NearbySearchResponse, error) {
	return c.inner.NearbySearch(ctx, req)
}

// Details fetches place details by place ID.
func (c *Client) Details(ctx context.Context, placeID string) (PlaceDetails, error) {
	return c.inner.Details(ctx, placeID)
}

// DetailsWithOptions fetches place details with optional locale and field options.
func (c *Client) DetailsWithOptions(ctx context.Context, req DetailsRequest) (PlaceDetails, error) {
	return c.inner.DetailsWithOptions(ctx, req)
}

// PhotoMedia fetches a photo media URL.
func (c *Client) PhotoMedia(ctx context.Context, req PhotoMediaRequest) (PhotoMediaResponse, error) {
	return c.inner.PhotoMedia(ctx, req)
}

// Resolve resolves a free-form location into place candidates.
func (c *Client) Resolve(ctx context.Context, req LocationResolveRequest) (LocationResolveResponse, error) {
	return c.inner.Resolve(ctx, req)
}

// Route searches for places along a route between two locations.
func (c *Client) Route(ctx context.Context, req RouteRequest) (RouteResponse, error) {
	return c.inner.Route(ctx, req)
}

// Directions fetches directions between two locations.
func (c *Client) Directions(ctx context.Context, req DirectionsRequest) (DirectionsResponse, error) {
	return c.inner.Directions(ctx, req)
}

type (
	// Options configures the Places client.
	Options = places.Options
	// ValidationError describes an invalid request payload.
	ValidationError = places.ValidationError
	// APIError represents an HTTP error from the Places API.
	APIError = places.APIError

	// SearchRequest defines a text search with optional filters.
	SearchRequest = places.SearchRequest
	// Filters are optional search refinements.
	Filters = places.Filters
	// LocationBias limits search results to a circular area.
	LocationBias = places.LocationBias
	// LatLng holds geographic coordinates.
	LatLng = places.LatLng
	// SearchResponse contains a list of places and optional pagination token.
	SearchResponse = places.SearchResponse

	// AutocompleteRequest defines input for autocomplete suggestions.
	AutocompleteRequest = places.AutocompleteRequest
	// AutocompleteResponse contains suggestions from autocomplete.
	AutocompleteResponse = places.AutocompleteResponse
	// AutocompleteSuggestion is a place or query prediction.
	AutocompleteSuggestion = places.AutocompleteSuggestion

	// NearbySearchRequest defines a nearby search query.
	NearbySearchRequest = places.NearbySearchRequest
	// NearbySearchResponse contains nearby search results.
	NearbySearchResponse = places.NearbySearchResponse
	// PlaceSummary is a compact view of a place.
	PlaceSummary = places.PlaceSummary
	// PlaceDetails is a detailed view of a place.
	PlaceDetails = places.PlaceDetails
	// DetailsRequest fetches place details with optional locale hints.
	DetailsRequest = places.DetailsRequest

	// Review represents a user review of a place.
	Review = places.Review
	// LocalizedText is a text value with an optional language code.
	LocalizedText = places.LocalizedText
	// AuthorAttribution describes a review author.
	AuthorAttribution = places.AuthorAttribution
	// ReviewVisitDate describes the date a reviewer visited a place.
	ReviewVisitDate = places.ReviewVisitDate
	// Photo describes photo metadata for a place.
	Photo = places.Photo
	// PhotoMediaRequest fetches a photo URL from a photo resource name.
	PhotoMediaRequest = places.PhotoMediaRequest
	// PhotoMediaResponse contains the photo URL for a photo name.
	PhotoMediaResponse = places.PhotoMediaResponse

	// LocationResolveRequest resolves a text location into place candidates.
	LocationResolveRequest = places.LocationResolveRequest
	// LocationResolveResponse contains resolved locations.
	LocationResolveResponse = places.LocationResolveResponse
	// ResolvedLocation is a place candidate for a location string.
	ResolvedLocation = places.ResolvedLocation

	// RouteRequest describes a query to search along a route.
	RouteRequest = places.RouteRequest
	// RouteResponse contains sampled waypoints with search results.
	RouteResponse = places.RouteResponse
	// RouteWaypoint ties a sampled route location to search results.
	RouteWaypoint = places.RouteWaypoint

	// DirectionsRequest describes a directions query between two locations.
	DirectionsRequest = places.DirectionsRequest
	// DirectionsResponse contains a single route summary and steps.
	DirectionsResponse = places.DirectionsResponse
	// DirectionsStep is a single navigation step.
	DirectionsStep = places.DirectionsStep
)
