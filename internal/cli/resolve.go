package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

// ResolveCmd resolves a location string into candidates.
type ResolveCmd struct {
	LocationText string `arg:"" name:"location" help:"Location text to resolve."`
	Limit        int    `help:"Max results (1-10)." default:"5"`
	Language     string `help:"BCP-47 language code (e.g. en, en-US)."`
	Region       string `help:"CLDR region code (e.g. US, DE)."`
}

// Run executes the resolve command.
func (c *ResolveCmd) Run(app *App) error {
	request := goplaces.LocationResolveRequest{
		LocationText: c.LocationText,
		Limit:        c.Limit,
		Language:     c.Language,
		Region:       c.Region,
	}

	response, err := app.client.Resolve(context.Background(), request)
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response.Results)
	}

	_, err = fmt.Fprintln(app.out, renderResolve(app.color, response))
	return err
}
