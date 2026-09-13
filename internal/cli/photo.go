package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

// PhotoCmd fetches a photo URL.
type PhotoCmd struct {
	Name        string `arg:"" name:"photo_name" help:"Photo resource name (places/.../photos/...)."`
	MaxWidthPx  int    `help:"Max width in pixels (1-4800). Required if --max-height is omitted." name:"max-width"`
	MaxHeightPx int    `help:"Max height in pixels (1-4800). Required if --max-width is omitted." name:"max-height"`
}

// Run executes the photo command.
func (c *PhotoCmd) Run(app *App) error {
	response, err := app.client.PhotoMedia(context.Background(), goplaces.PhotoMediaRequest{
		Name:        c.Name,
		MaxWidthPx:  c.MaxWidthPx,
		MaxHeightPx: c.MaxHeightPx,
	})
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response)
	}

	_, err = fmt.Fprintln(app.out, renderPhoto(app.color, response))
	return err
}
