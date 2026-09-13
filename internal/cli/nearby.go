package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

// NearbyCmd runs nearby searches.
type NearbyCmd struct {
	Limit       int      `help:"Max results (1-20)." default:"10"`
	Type        []string `help:"Included place types. Repeatable."`
	ExcludeType []string `help:"Excluded place types. Repeatable."`
	Language    string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region      string   `help:"CLDR region code (e.g. US, DE)."`
	Lat         *float64 `help:"Latitude for location restriction."`
	Lng         *float64 `help:"Longitude for location restriction."`
	RadiusM     *float64 `help:"Radius in meters for location restriction." aliases:"radius"`
}

// Run executes the nearby command.
func (c *NearbyCmd) Run(app *App) error {
	if c.Lat == nil || c.Lng == nil || c.RadiusM == nil {
		return goplaces.ValidationError{Field: "location_restriction", Message: locationCoordinatesRequired}
	}

	request := goplaces.NearbySearchRequest{
		LocationRestriction: &goplaces.LocationBias{
			Lat:     *c.Lat,
			Lng:     *c.Lng,
			RadiusM: *c.RadiusM,
		},
		Limit:         c.Limit,
		IncludedTypes: c.Type,
		ExcludedTypes: c.ExcludeType,
		Language:      c.Language,
		Region:        c.Region,
	}

	response, err := app.client.NearbySearch(context.Background(), request)
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response)
	}

	_, err = fmt.Fprintln(app.out, renderNearby(app.color, response))
	return err
}
