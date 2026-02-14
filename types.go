package goplaces

// SearchRequest defines a text search with optional filters.
type SearchRequest struct {
	Query        string        `json:"query"`
	Filters      *Filters      `json:"filters,omitempty"`
	LocationBias *LocationBias `json:"location_bias,omitempty"`
	Limit        int           `json:"limit,omitempty"`
	PageToken    string        `json:"page_token,omitempty"`
	Language     string        `json:"language,omitempty"`
	Region       string        `json:"region,omitempty"`
}

// Filters are optional search refinements.
type Filters struct {
	Keyword     string   `json:"keyword,omitempty"`
	Types       []string `json:"types,omitempty"`
	OpenNow     *bool    `json:"open_now,omitempty"`
	MinRating   *float64 `json:"min_rating,omitempty"`
	PriceLevels []int    `json:"price_levels,omitempty"`
}

// LocationBias limits search results to a circular area.
type LocationBias struct {
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
	RadiusM float64 `json:"radius_m"`
}

// LatLng holds geographic coordinates.
type LatLng struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// SearchResponse contains a list of places and optional pagination token.
type SearchResponse struct {
	Results       []PlaceSummary `json:"results"`
	NextPageToken string         `json:"next_page_token,omitempty"`
}

// AutocompleteRequest defines input for autocomplete suggestions.
type AutocompleteRequest struct {
	Input        string        `json:"input"`
	SessionToken string        `json:"session_token,omitempty"`
	Limit        int           `json:"limit,omitempty"`
	Language     string        `json:"language,omitempty"`
	Region       string        `json:"region,omitempty"`
	LocationBias *LocationBias `json:"location_bias,omitempty"`
}

// AutocompleteResponse contains suggestions from autocomplete.
type AutocompleteResponse struct {
	Suggestions []AutocompleteSuggestion `json:"suggestions"`
}

// AutocompleteSuggestion is a place or query prediction.
type AutocompleteSuggestion struct {
	Kind           string   `json:"kind"`
	PlaceID        string   `json:"place_id,omitempty"`
	Place          string   `json:"place,omitempty"`
	Text           string   `json:"text,omitempty"`
	MainText       string   `json:"main_text,omitempty"`
	SecondaryText  string   `json:"secondary_text,omitempty"`
	Types          []string `json:"types,omitempty"`
	DistanceMeters *int     `json:"distance_meters,omitempty"`
}

// NearbySearchRequest defines a nearby search query.
type NearbySearchRequest struct {
	LocationRestriction *LocationBias `json:"location_restriction,omitempty"`
	Limit               int           `json:"limit,omitempty"`
	IncludedTypes       []string      `json:"included_types,omitempty"`
	ExcludedTypes       []string      `json:"excluded_types,omitempty"`
	Language            string        `json:"language,omitempty"`
	Region              string        `json:"region,omitempty"`
}

// NearbySearchResponse contains nearby search results.
type NearbySearchResponse struct {
	Results       []PlaceSummary `json:"results"`
	NextPageToken string         `json:"next_page_token,omitempty"`
}

// PlaceSummary is a compact view of a place.
type PlaceSummary struct {
	PlaceID         string   `json:"place_id"`
	Name            string   `json:"name,omitempty"`
	Address         string   `json:"address,omitempty"`
	Location        *LatLng  `json:"location,omitempty"`
	Rating          *float64 `json:"rating,omitempty"`
	UserRatingCount *int     `json:"user_rating_count,omitempty"`
	PriceLevel      *int     `json:"price_level,omitempty"`
	Types           []string `json:"types,omitempty"`
	OpenNow         *bool    `json:"open_now,omitempty"`
}

// PlaceDetails is a detailed view of a place.
type PlaceDetails struct {
	PlaceID         string   `json:"place_id"`
	Name            string   `json:"name,omitempty"`
	Address         string   `json:"address,omitempty"`
	Location        *LatLng  `json:"location,omitempty"`
	Rating          *float64 `json:"rating,omitempty"`
	UserRatingCount *int     `json:"user_rating_count,omitempty"`
	PriceLevel      *int     `json:"price_level,omitempty"`
	Types           []string `json:"types,omitempty"`
	Phone           string   `json:"phone,omitempty"`
	Website         string   `json:"website,omitempty"`
	Hours           []string `json:"hours,omitempty"`
	OpenNow         *bool    `json:"open_now,omitempty"`
	Reviews         []Review `json:"reviews,omitempty"`
	Photos          []Photo  `json:"photos,omitempty"`
}

// LocationResolveRequest resolves a text location into place candidates.
type LocationResolveRequest struct {
	LocationText string `json:"location_text"`
	Limit        int    `json:"limit,omitempty"`
	Language     string `json:"language,omitempty"`
	Region       string `json:"region,omitempty"`
}

// DetailsRequest fetches place details with optional locale hints.
type DetailsRequest struct {
	PlaceID  string `json:"place_id"`
	Language string `json:"language,omitempty"`
	Region   string `json:"region,omitempty"`
	// IncludeReviews requests the reviews field in Place Details.
	IncludeReviews bool `json:"include_reviews,omitempty"`
	// IncludePhotos requests the photos field in Place Details.
	IncludePhotos bool `json:"include_photos,omitempty"`
}

// Review represents a user review of a place.
type Review struct {
	Name                           string             `json:"name,omitempty"`
	RelativePublishTimeDescription string             `json:"relative_publish_time_description,omitempty"`
	Text                           *LocalizedText     `json:"text,omitempty"`
	OriginalText                   *LocalizedText     `json:"original_text,omitempty"`
	Rating                         *float64           `json:"rating,omitempty"`
	Author                         *AuthorAttribution `json:"author,omitempty"`
	PublishTime                    string             `json:"publish_time,omitempty"`
	FlagContentURI                 string             `json:"flag_content_uri,omitempty"`
	GoogleMapsURI                  string             `json:"google_maps_uri,omitempty"`
	VisitDate                      *ReviewVisitDate   `json:"visit_date,omitempty"`
}

// LocalizedText is a text value with an optional language code.
type LocalizedText struct {
	Text         string `json:"text,omitempty"`
	LanguageCode string `json:"language_code,omitempty"`
}

// AuthorAttribution describes a review author.
type AuthorAttribution struct {
	DisplayName string `json:"display_name,omitempty"`
	URI         string `json:"uri,omitempty"`
	PhotoURI    string `json:"photo_uri,omitempty"`
}

// ReviewVisitDate describes the date a reviewer visited a place.
type ReviewVisitDate struct {
	Year  int `json:"year,omitempty"`
	Month int `json:"month,omitempty"`
	Day   int `json:"day,omitempty"`
}

// Photo describes photo metadata for a place.
type Photo struct {
	Name               string              `json:"name,omitempty"`
	WidthPx            int                 `json:"width_px,omitempty"`
	HeightPx           int                 `json:"height_px,omitempty"`
	AuthorAttributions []AuthorAttribution `json:"author_attributions,omitempty"`
}

// PhotoMediaRequest fetches a photo URL from a photo resource name.
type PhotoMediaRequest struct {
	Name        string `json:"name"`
	MaxWidthPx  int    `json:"max_width_px,omitempty"`
	MaxHeightPx int    `json:"max_height_px,omitempty"`
}

// PhotoMediaResponse contains the photo URL for a photo name.
type PhotoMediaResponse struct {
	Name     string `json:"name,omitempty"`
	PhotoURI string `json:"photo_uri,omitempty"`
}

// LocationResolveResponse contains resolved locations.
type LocationResolveResponse struct {
	Results []ResolvedLocation `json:"results"`
}

// ResolvedLocation is a place candidate for a location string.
type ResolvedLocation struct {
	PlaceID  string   `json:"place_id"`
	Name     string   `json:"name,omitempty"`
	Address  string   `json:"address,omitempty"`
	Location *LatLng  `json:"location,omitempty"`
	Types    []string `json:"types,omitempty"`
}
