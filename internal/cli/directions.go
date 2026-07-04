package cli

import (
	"context"
	"strings"

	"github.com/steipete/goplaces"
)

const (
	directionsModeWalk               = "walk"
	directionsModeWalking            = "walking"
	directionsModeDrive              = "drive"
	directionsModeDriving            = "driving"
	directionsModeBicycling          = "bicycling"
	directionsModeTransit            = "transit"
	directionsValidationFieldCompare = "compare"
	directionsValidationMessageModes = "must be walk, drive, bicycle, or transit"
)

// DirectionsCmd fetches directions between two points.
type DirectionsCmd struct {
	From          string   `help:"Origin address or place name."`
	To            string   `help:"Destination address or place name."`
	FromPlaceID   string   `help:"Origin place ID." name:"from-place-id"`
	ToPlaceID     string   `help:"Destination place ID." name:"to-place-id"`
	FromLat       *float64 `help:"Origin latitude." name:"from-lat"`
	FromLng       *float64 `help:"Origin longitude." name:"from-lng"`
	ToLat         *float64 `help:"Destination latitude." name:"to-lat"`
	ToLng         *float64 `help:"Destination longitude." name:"to-lng"`
	Mode          string   `help:"Travel mode: walk, drive, bicycle, transit." default:"walk"`
	Compare       string   `help:"Compare with another mode: walk, drive, bicycle, transit."`
	Steps         bool     `help:"Include step-by-step instructions."`
	Units         string   `help:"Units: metric or imperial." default:"metric"`
	AvoidTolls    bool     `help:"Avoid toll roads when driving."`
	AvoidHighways bool     `help:"Avoid highways when driving."`
	AvoidFerries  bool     `help:"Avoid ferries when driving."`
	DepartureTime string   `help:"Route departure time as RFC3339 timestamp (for example 2030-05-10T18:57:00-03:00)." name:"departure-time"`
	ArrivalTime   string   `help:"Transit route arrival time as RFC3339 timestamp; mutually exclusive with --departure-time." name:"arrival-time"`
	Language      string   `help:"BCP-47 language code (e.g. en, en-US)."`
	Region        string   `help:"CLDR region code (e.g. US, DE)."`
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
			return goplaces.ValidationError{Field: directionsValidationFieldCompare, Message: directionsValidationMessageModes}
		}
		if compareMode == primaryMode {
			return goplaces.ValidationError{Field: directionsValidationFieldCompare, Message: "must be different from mode"}
		}
		if strings.TrimSpace(c.ArrivalTime) != "" {
			return goplaces.ValidationError{Field: directionsValidationFieldCompare, Message: "cannot combine with arrival_time"}
		}
	}

	hasAvoidModifiers := c.AvoidTolls || c.AvoidHighways || c.AvoidFerries
	if hasAvoidModifiers && primaryMode != directionsModeDriving && compareMode != directionsModeDriving {
		return goplaces.ValidationError{Field: "avoid", Message: "requires mode or compare to be drive"}
	}

	request := goplaces.DirectionsRequest{
		From:          c.From,
		To:            c.To,
		FromPlaceID:   c.FromPlaceID,
		ToPlaceID:     c.ToPlaceID,
		Mode:          primaryMode,
		Units:         c.Units,
		DepartureTime: c.DepartureTime,
		ArrivalTime:   c.ArrivalTime,
		Language:      c.Language,
		Region:        c.Region,
	}
	if primaryMode == directionsModeDriving {
		request.AvoidTolls = c.AvoidTolls
		request.AvoidHighways = c.AvoidHighways
		request.AvoidFerries = c.AvoidFerries
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
		if compareMode == directionsModeDriving {
			compareRequest.AvoidTolls = c.AvoidTolls
			compareRequest.AvoidHighways = c.AvoidHighways
			compareRequest.AvoidFerries = c.AvoidFerries
		} else {
			compareRequest.AvoidTolls = false
			compareRequest.AvoidHighways = false
			compareRequest.AvoidFerries = false
		}
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
	case directionsModeWalk, directionsModeWalking:
		return directionsModeWalking
	case directionsModeDrive, directionsModeDriving:
		return directionsModeDriving
	case "bike", "bicycle", directionsModeBicycling:
		return directionsModeBicycling
	case directionsModeTransit:
		return directionsModeTransit
	default:
		return ""
	}
}
