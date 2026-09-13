package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

// DetailsCmd fetches place details.
type DetailsCmd struct {
	PlaceID  string `arg:"" name:"place_id" help:"Place ID."`
	Language string `help:"BCP-47 language code (e.g. en, en-US)."`
	Region   string `help:"CLDR region code (e.g. US, DE)."`
	Reviews  bool   `help:"Include reviews in the response."`
	Photos   bool   `help:"Include photos in the response."`
}

// Run executes the details command.
func (c *DetailsCmd) Run(app *App) error {
	response, err := app.client.DetailsWithOptions(context.Background(), goplaces.DetailsRequest{
		PlaceID:        c.PlaceID,
		Language:       c.Language,
		Region:         c.Region,
		IncludeReviews: c.Reviews,
		IncludePhotos:  c.Photos,
	})
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response)
	}

	_, err = fmt.Fprintln(app.out, renderDetails(app.color, response))
	return err
}
