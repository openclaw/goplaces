package cli

import (
	"time"
)

// Root defines the CLI command tree.
type Root struct {
	Global       GlobalOptions   `embed:""`
	Autocomplete AutocompleteCmd `cmd:"" help:"Autocomplete places and queries."`
	Nearby       NearbyCmd       `cmd:"" help:"Search nearby places by location."`
	Search       SearchCmd       `cmd:"" help:"Search places by text query."`
	Route        RouteCmd        `cmd:"" help:"Search places along a route."`
	Directions   DirectionsCmd   `cmd:"" help:"Get directions and travel time between two points."`
	Details      DetailsCmd      `cmd:"" help:"Fetch place details by place ID."`
	Photo        PhotoCmd        `cmd:"" help:"Fetch a photo URL by photo name."`
	Resolve      ResolveCmd      `cmd:"" help:"Resolve a location string to candidate places."`
}

// GlobalOptions are flags shared by all commands.
type GlobalOptions struct {
	APIKey            string        `help:"Google Places API key." env:"GOOGLE_PLACES_API_KEY"`
	BaseURL           string        `help:"Places API base URL." env:"GOOGLE_PLACES_BASE_URL" default:"https://places.googleapis.com/v1"`
	RoutesBaseURL     string        `help:"Routes API base URL." env:"GOOGLE_ROUTES_BASE_URL" default:"https://routes.googleapis.com"`
	DirectionsBaseURL string        `help:"Directions API base URL." env:"GOOGLE_DIRECTIONS_BASE_URL" default:"https://maps.googleapis.com/maps/api/directions/json"`
	Timeout           time.Duration `help:"HTTP timeout." default:"10s"`
	JSON              bool          `help:"Output JSON."`
	NoColor           bool          `help:"Disable color output."`
	Verbose           bool          `help:"Verbose logging."`
	Version           VersionFlag   `name:"version" help:"Print version and exit."`
}

// SearchCmd runs text search queries.
type SearchCmd struct {
	Query      string   `arg:"" name:"query" help:"Search text."`
	Limit      int      `help:"Max results (1-20)." default:"10"`
	PageToken  string   `help:"Page token for pagination."`
	Language   string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region     string   `help:"CLDR region code (e.g. US, DE)."`
	Keyword    string   `help:"Keyword to append to the query."`
	Type       []string `help:"Place type filter (includedType). Repeatable."`
	OpenNow    *bool    `help:"Return only currently open places."`
	MinRating  *float64 `help:"Minimum rating (0-5)."`
	PriceLevel []int    `help:"Price levels 0-4. Repeatable."`
	Lat        *float64 `help:"Latitude for location bias."`
	Lng        *float64 `help:"Longitude for location bias."`
	RadiusM    *float64 `help:"Radius in meters for location bias."`
}

// AutocompleteCmd runs autocomplete queries.
type AutocompleteCmd struct {
	Input        string   `arg:"" name:"input" help:"Autocomplete input text."`
	Limit        int      `help:"Max suggestions (1-20)." default:"5"`
	SessionToken string   `help:"Session token for billing consistency."`
	Language     string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region       string   `help:"CLDR region code (e.g. US, DE)."`
	Lat          *float64 `help:"Latitude for location bias."`
	Lng          *float64 `help:"Longitude for location bias."`
	RadiusM      *float64 `help:"Radius in meters for location bias."`
}

// NearbyCmd runs nearby searches.
type NearbyCmd struct {
	Limit       int      `help:"Max results (1-20)." default:"10"`
	Type        []string `help:"Included place types. Repeatable."`
	ExcludeType []string `help:"Excluded place types. Repeatable."`
	Language    string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region      string   `help:"CLDR region code (e.g. US, DE)."`
	Lat         *float64 `help:"Latitude for location restriction."`
	Lng         *float64 `help:"Longitude for location restriction."`
	RadiusM     *float64 `help:"Radius in meters for location restriction."`
}

// DetailsCmd fetches place details.
type DetailsCmd struct {
	PlaceID  string `arg:"" name:"place_id" help:"Place ID."`
	Language string `help:"BCP-47 language code (e.g. en, en-US)."`
	Region   string `help:"CLDR region code (e.g. US, DE)."`
	Reviews  bool   `help:"Include reviews in the response."`
	Photos   bool   `help:"Include photos in the response."`
}

// PhotoCmd fetches a photo URL.
type PhotoCmd struct {
	Name        string `arg:"" name:"photo_name" help:"Photo resource name (places/.../photos/...)."`
	MaxWidthPx  int    `help:"Max width in pixels." name:"max-width"`
	MaxHeightPx int    `help:"Max height in pixels." name:"max-height"`
}

// ResolveCmd resolves a location string into candidates.
type ResolveCmd struct {
	LocationText string `arg:"" name:"location" help:"Location text to resolve."`
	Limit        int    `help:"Max results (1-10)." default:"5"`
	Language     string `help:"BCP-47 language code (e.g. en, en-US)."`
	Region       string `help:"CLDR region code (e.g. US, DE)."`
}
