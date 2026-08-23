package cli

import (
	"context"
	"fmt"

	"github.com/steipete/goplaces"
)

// RouteCmd searches along a route between two locations.
type RouteCmd struct {
	Query        string  `arg:"" name:"query" help:"Search text."`
	From         string  `help:"Origin location (address or place name)."`
	To           string  `help:"Destination location (address or place name)."`
	Mode         string  `help:"Travel mode: DRIVE, WALK, BICYCLE, TWO_WHEELER, TRANSIT." default:"DRIVE"`
	RadiusM      float64 `help:"Search radius in meters." default:"1000" aliases:"radius"`
	MaxWaypoints int     `help:"Max sampled waypoints along the route." default:"5"`
	Limit        int     `help:"Max results per waypoint (1-20)." default:"5"`
	Language     string  `help:"BCP-47 language code (e.g. en, en-US)."`
	Region       string  `help:"CLDR region code (e.g. US, DE)."`
}

// Run executes the route command.
func (c *RouteCmd) Run(app *App) error {
	request := goplaces.RouteRequest{
		Query:        c.Query,
		From:         c.From,
		To:           c.To,
		Mode:         c.Mode,
		RadiusM:      c.RadiusM,
		MaxWaypoints: c.MaxWaypoints,
		Limit:        c.Limit,
		Language:     c.Language,
		Region:       c.Region,
	}

	response, err := app.client.Route(context.Background(), request)
	if err != nil {
		return err
	}

	if app.json {
		return writeJSON(app.out, response)
	}

	_, err = fmt.Fprintln(app.out, renderRoute(app.color, response))
	return err
}
