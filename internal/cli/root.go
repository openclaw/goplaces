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
	DirectionsBaseURL string        `help:"Directions Routes API base URL." env:"GOOGLE_DIRECTIONS_BASE_URL" default:"https://routes.googleapis.com"`
	Timeout           time.Duration `help:"HTTP timeout." default:"10s"`
	JSON              bool          `help:"Output JSON."`
	NoColor           bool          `help:"Disable color output."`
	Version           VersionFlag   `name:"version" help:"Print version and exit."`
}
