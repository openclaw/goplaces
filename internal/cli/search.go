package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

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
	RadiusM    *float64 `help:"Radius in meters for location bias." aliases:"radius"`
}

// Run executes the search command.
func (c *SearchCmd) Run(app *App) error {
	request := goplaces.SearchRequest{
		Query:     c.Query,
		Limit:     c.Limit,
		PageToken: c.PageToken,
		Language:  c.Language,
		Region:    c.Region,
	}

	if c.Keyword != "" || len(c.Type) > 0 || c.OpenNow != nil || c.MinRating != nil || len(c.PriceLevel) > 0 {
		request.Filters = &goplaces.Filters{
			Keyword:     c.Keyword,
			Types:       c.Type,
			OpenNow:     c.OpenNow,
			MinRating:   c.MinRating,
			PriceLevels: c.PriceLevel,
		}
	}

	bias, err := optionalLocationBias(c.Lat, c.Lng, c.RadiusM)
	if err != nil {
		return err
	}
	request.LocationBias = bias

	response, err := app.client.Search(context.Background(), request)
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response)
	}

	_, err = fmt.Fprintln(app.out, renderSearch(app.color, response))
	return err
}
