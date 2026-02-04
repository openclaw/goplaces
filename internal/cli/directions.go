package cli

import (
	"context"
	"strings"

	"github.com/steipete/goplaces"
)

// DirectionsCmd fetches directions between two points.
type DirectionsCmd struct {
	From        string   `help:"Origin address or place name."`
	To          string   `help:"Destination address or place name."`
	FromPlaceID string   `help:"Origin place ID." name:"from-place-id"`
	ToPlaceID   string   `help:"Destination place ID." name:"to-place-id"`
	FromLat     *float64 `help:"Origin latitude." name:"from-lat"`
	FromLng     *float64 `help:"Origin longitude." name:"from-lng"`
	ToLat       *float64 `help:"Destination latitude." name:"to-lat"`
	ToLng       *float64 `help:"Destination longitude." name:"to-lng"`
	Mode        string   `help:"Travel mode: walk, drive, bicycle, transit." default:"walk"`
	Compare     string   `help:"Compare with another mode: walk, drive, bicycle, transit."`
	Steps       bool     `help:"Include step-by-step instructions."`
	Language    string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region      string   `help:"CLDR region code (e.g. US, DE)."`
}

// Run executes the directions command.
func (c *DirectionsCmd) Run(app *App) error {
	primaryMode := normalizeDirectionsMode(c.Mode)
	if primaryMode == "" {
		return goplaces.ValidationError{Field: "mode", Message: "must be walk, drive, bicycle, or transit"}
	}
	compareMode := ""
	if strings.TrimSpace(c.Compare) != "" {
		compareMode = normalizeDirectionsMode(c.Compare)
		if compareMode == "" {
			return goplaces.ValidationError{Field: "compare", Message: "must be walk, drive, bicycle, or transit"}
		}
		if compareMode == primaryMode {
			return goplaces.ValidationError{Field: "compare", Message: "must be different from mode"}
		}
	}

	request := goplaces.DirectionsRequest{
		From:        c.From,
		To:          c.To,
		FromPlaceID: c.FromPlaceID,
		ToPlaceID:   c.ToPlaceID,
		Mode:        primaryMode,
		Language:    c.Language,
		Region:      c.Region,
	}
	if c.FromLat != nil || c.FromLng != nil {
		if c.FromLat == nil || c.FromLng == nil {
			return goplaces.ValidationError{Field: "from_location", Message: "lat and lng required"}
		}
		request.FromLocation = &goplaces.LatLng{Lat: *c.FromLat, Lng: *c.FromLng}
	}
	if c.ToLat != nil || c.ToLng != nil {
		if c.ToLat == nil || c.ToLng == nil {
			return goplaces.ValidationError{Field: "to_location", Message: "lat and lng required"}
		}
		request.ToLocation = &goplaces.LatLng{Lat: *c.ToLat, Lng: *c.ToLng}
	}

	response, err := app.client.Directions(context.Background(), request)
	if err != nil {
		return err
	}

	var compareResponse *goplaces.DirectionsResponse
	if compareMode != "" {
		compareRequest := request
		compareRequest.Mode = compareMode
		second, err := app.client.Directions(context.Background(), compareRequest)
		if err != nil {
			return err
		}
		compareResponse = &second
	}

	if app.json {
		if compareResponse != nil {
			return writeJSON(app.out, []goplaces.DirectionsResponse{response, *compareResponse})
		}
		return writeJSON(app.out, response)
	}

	if compareResponse != nil {
		_, err = app.out.Write([]byte(renderDirections(app.color, response, c.Steps)))
		if err != nil {
			return err
		}
		_, err = app.out.Write([]byte("\n\n" + renderDirections(app.color, *compareResponse, c.Steps)))
		return err
	}

	_, err = app.out.Write([]byte(renderDirections(app.color, response, c.Steps)))
	return err
}

func normalizeDirectionsMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "walk", "walking":
		return "walking"
	case "drive", "driving":
		return "driving"
	case "bike", "bicycle", "bicycling":
		return "bicycling"
	case "transit":
		return "transit"
	default:
		return ""
	}
}
