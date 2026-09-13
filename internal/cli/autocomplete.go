package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

// AutocompleteCmd runs autocomplete queries.
type AutocompleteCmd struct {
	Input        string   `arg:"" name:"input" help:"Autocomplete input text."`
	Limit        int      `help:"Max suggestions (1-20)." default:"5"`
	SessionToken string   `help:"Session token for billing consistency."`
	Language     string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region       string   `help:"CLDR region code (e.g. US, DE)."`
	Lat          *float64 `help:"Latitude for location bias."`
	Lng          *float64 `help:"Longitude for location bias."`
	RadiusM      *float64 `help:"Radius in meters for location bias." aliases:"radius"`
}

// Run executes the autocomplete command.
func (c *AutocompleteCmd) Run(app *App) error {
	request := goplaces.AutocompleteRequest{
		Input:        c.Input,
		Limit:        c.Limit,
		SessionToken: c.SessionToken,
		Language:     c.Language,
		Region:       c.Region,
	}

	bias, err := optionalLocationBias(c.Lat, c.Lng, c.RadiusM)
	if err != nil {
		return err
	}
	request.LocationBias = bias

	response, err := app.client.Autocomplete(context.Background(), request)
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response.Suggestions)
	}

	_, err = fmt.Fprintln(app.out, renderAutocomplete(app.color, response))
	return err
}
