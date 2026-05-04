// Package goplaces provides a Go client for the Google Places API (New).
package goplaces

import "github.com/steipete/goplaces/internal/places"

// DefaultBaseURL is the default endpoint for the Places API (New).
const DefaultBaseURL = places.DefaultBaseURL

// ErrMissingAPIKey indicates a missing API key.
var ErrMissingAPIKey = places.ErrMissingAPIKey

// NewClient builds a client with sane defaults.
func NewClient(opts Options) *Client {
	return places.NewClient(opts)
}

type (
	// Client wraps access to the Google Places API.
	Client = places.Client
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
