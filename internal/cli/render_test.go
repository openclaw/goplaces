package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/steipete/goplaces"
)

func TestRenderSearch(t *testing.T) {
	open := true
	level := 2
	ratingCount := 532
	response := goplaces.SearchResponse{
		Results: []goplaces.PlaceSummary{
			{
				PlaceID:         "abc",
				Name:            "Cafe",
				Address:         "123 Street",
				Location:        &goplaces.LatLng{Lat: 1, Lng: 2},
				Rating:          floatPtr(4.5),
				UserRatingCount: &ratingCount,
				PriceLevel:      &level,
				Types:           []string{"cafe", "coffee_shop"},
				OpenNow:         &open,
				BusinessStatus:  "OPERATIONAL",
			},
		},
		NextPageToken: "next",
	}

	output := renderSearch(NewColor(false), response)
	if !strings.Contains(output, "Cafe") {
		t.Fatalf("missing name")
	}
	if !strings.Contains(output, "Rating") {
		t.Fatalf("missing rating")
	}
	if !strings.Contains(output, "4.5 (532)") {
		t.Fatalf("missing rating count")
	}
	if !strings.Contains(output, "Open now") {
		t.Fatalf("missing open now")
	}
	if !strings.Contains(output, "Status: OPERATIONAL") {
		t.Fatalf("missing status")
	}
	if !strings.Contains(output, "next") {
		t.Fatalf("missing next page token")
	}
}

func TestRenderSearchRatingCountOnly(t *testing.T) {
	ratingCount := 12
	response := goplaces.SearchResponse{
		Results: []goplaces.PlaceSummary{
			{
				PlaceID:         "abc",
				Name:            "Cafe",
				UserRatingCount: &ratingCount,
			},
		},
	}

	output := renderSearch(NewColor(false), response)
	if !strings.Contains(output, "12 ratings") {
		t.Fatalf("missing rating count-only output: %s", output)
	}
}

func TestRenderSearchEmpty(t *testing.T) {
	output := renderSearch(NewColor(false), goplaces.SearchResponse{})
	if !strings.Contains(output, "No results") {
		t.Fatalf("unexpected output: %s", output)
	}
}

func TestRenderSearchSanitizesTerminalControls(t *testing.T) {
	response := goplaces.SearchResponse{
		Results: []goplaces.PlaceSummary{
			{
				PlaceID:        "place-\x1b[31m1",
				Name:           "\x1b]52;c;SGVsbG8=\x07Cafe",
				Address:        "123\rStreet",
				BusinessStatus: "\x1b[31mOPERATIONAL",
			},
		},
		NextPageToken: "\x1b]0;title\x07next",
	}

	output := renderSearch(NewColor(false), response)
	for _, control := range []string{"\x1b", "\x07", "\r"} {
		if strings.Contains(output, control) {
			t.Fatalf("output contains raw control %q: %q", control, output)
		}
	}
	if !strings.Contains(output, "Cafe") || !strings.Contains(output, "Street") || !strings.Contains(output, "next") {
		t.Fatalf("missing sanitized printable text: %q", output)
	}
}

func TestRenderAutocomplete(t *testing.T) {
	response := goplaces.AutocompleteResponse{
		Suggestions: []goplaces.AutocompleteSuggestion{
			{
				Kind:          "place",
				PlaceID:       "abc",
				MainText:      "Cafe",
				SecondaryText: "Seattle",
				Types:         []string{"cafe"},
			},
		},
	}
	output := renderAutocomplete(NewColor(false), response)
	if !strings.Contains(output, "Suggestions") {
		t.Fatalf("missing suggestions header")
	}
	if !strings.Contains(output, "Cafe") {
		t.Fatalf("missing suggestion text")
	}
	if !strings.Contains(output, "Kind") {
		t.Fatalf("missing kind label")
	}
	if !strings.Contains(output, "cafe") {
		t.Fatalf("missing types")
	}
}

func TestRenderAutocompleteEmpty(t *testing.T) {
	output := renderAutocomplete(NewColor(false), goplaces.AutocompleteResponse{})
	if !strings.Contains(output, "No results") {
		t.Fatalf("unexpected output: %s", output)
	}
}

func TestRenderNearby(t *testing.T) {
	response := goplaces.NearbySearchResponse{
		Results: []goplaces.PlaceSummary{
			{PlaceID: "place-1", Name: "Cafe"},
		},
		NextPageToken: "next",
	}
	output := renderNearby(NewColor(false), response)
	if !strings.Contains(output, "Nearby") {
		t.Fatalf("missing nearby header")
	}
	if !strings.Contains(output, "Cafe") {
		t.Fatalf("missing place name")
	}
	if !strings.Contains(output, "next") {
		t.Fatalf("missing next page token")
	}
}

func TestRenderRoute(t *testing.T) {
	response := goplaces.RouteResponse{
		Waypoints: []goplaces.RouteWaypoint{
			{
				Location: goplaces.LatLng{Lat: 1, Lng: 2},
				Results:  []goplaces.PlaceSummary{{PlaceID: "place-1", Name: "Cafe"}},
			},
		},
	}
	output := renderRoute(NewColor(false), response)
	if !strings.Contains(output, "Route waypoints") {
		t.Fatalf("missing route header")
	}
	if !strings.Contains(output, "Waypoint 1") {
		t.Fatalf("missing waypoint label")
	}
	if !strings.Contains(output, "Cafe") {
		t.Fatalf("missing place name")
	}
}

func TestRenderRouteEmpty(t *testing.T) {
	output := renderRoute(NewColor(false), goplaces.RouteResponse{})
	if !strings.Contains(output, "No results") {
		t.Fatalf("unexpected output: %s", output)
	}
}

func TestRenderDirections(t *testing.T) {
	response := goplaces.DirectionsResponse{
		Mode:         "WALKING",
		StartAddress: "Start",
		EndAddress:   "End",
		DistanceText: "1 km",
		DurationText: "10 mins",
		Steps: []goplaces.DirectionsStep{
			{Instruction: "Head north", DistanceText: "0.2 km", DurationText: "2 mins"},
		},
	}
	output := renderDirections(NewColor(false), response, true)
	if !strings.Contains(output, "Directions") {
		t.Fatalf("missing directions header")
	}
	if !strings.Contains(output, "Head north") {
		t.Fatalf("missing step")
	}
	if !strings.Contains(output, "Distance") {
		t.Fatalf("missing distance")
	}
}

func TestRenderDirectionsWarningsAndEmptySteps(t *testing.T) {
	response := goplaces.DirectionsResponse{
		StartAddress: "Start",
		EndAddress:   "End",
		Warnings:     []string{"", "Use caution"},
	}

	output := renderDirections(NewColor(false), response, true)
	if !strings.Contains(output, "Warnings:") {
		t.Fatalf("missing warnings header: %s", output)
	}
	if !strings.Contains(output, "Use caution") {
		t.Fatalf("missing warning entry: %s", output)
	}
	if !strings.Contains(output, "No results.") {
		t.Fatalf("missing empty steps message: %s", output)
	}
}

func TestRenderDirectionsSanitizesTerminalControls(t *testing.T) {
	response := goplaces.DirectionsResponse{
		Mode:         "\x1b[31mDRIVE",
		StartAddress: "Start\x1b]0;x\x07",
		EndAddress:   "End",
		Warnings:     []string{"Use\rcaution"},
		Steps: []goplaces.DirectionsStep{
			{Instruction: "\x1b[31mHead north", DistanceText: "1\nkm"},
		},
	}

	output := renderDirections(NewColor(false), response, true)
	for _, control := range []string{"\x1b", "\x07", "\r"} {
		if strings.Contains(output, control) {
			t.Fatalf("output contains raw control %q: %q", control, output)
		}
	}
	if !strings.Contains(output, "Head north") || !strings.Contains(output, "Use caution") {
		t.Fatalf("missing sanitized directions text: %q", output)
	}
}

func TestDirectionsStepLineFallback(t *testing.T) {
	line := directionsStepLine(goplaces.DirectionsStep{})
	if line != "(no instruction)" {
		t.Fatalf("unexpected step line: %q", line)
	}
}

func TestFormatTitleFallback(t *testing.T) {
	title := formatTitle(NewColor(false), "", "")
	if !strings.Contains(title, "(no name)") {
		t.Fatalf("unexpected title: %s", title)
	}
}

func TestWriteLineAndOpenNowNoValue(t *testing.T) {
	var out bytes.Buffer
	writeLine(&out, NewColor(false), "Label", "")
	if out.Len() != 0 {
		t.Fatalf("expected no output")
	}
	writeOpenNow(&out, NewColor(false), nil)
	if out.Len() != 0 {
		t.Fatalf("expected no output after open now")
	}
}

func TestRenderDetailsAndResolve(t *testing.T) {
	open := false
	level := 0
	details := goplaces.PlaceDetails{
		PlaceID:        "place-1",
		Name:           "Park",
		Address:        "Central",
		Rating:         floatPtr(4.2),
		PriceLevel:     &level,
		Types:          []string{"park"},
		Phone:          "+1 555",
		Website:        "https://example.com",
		Hours:          []string{"Mon: 9-5"},
		OpenNow:        &open,
		BusinessStatus: "CLOSED_TEMPORARILY",
		Photos: []goplaces.Photo{
			{Name: "places/place-1/photos/photo-1", WidthPx: 1200, HeightPx: 800},
		},
		Reviews: []goplaces.Review{
			{
				Rating:                         floatPtr(4.5),
				RelativePublishTimeDescription: "2 weeks ago",
				Text:                           &goplaces.LocalizedText{Text: "Great park"},
				Author:                         &goplaces.AuthorAttribution{DisplayName: "Alice"},
			},
		},
	}
	output := renderDetails(NewColor(false), details)
	if !strings.Contains(output, "Park") || !strings.Contains(output, "Hours:") {
		t.Fatalf("unexpected details output: %s", output)
	}
	if !strings.Contains(output, "Photos:") {
		t.Fatalf("missing photos output: %s", output)
	}
	if !strings.Contains(output, "Reviews:") || !strings.Contains(output, "Alice") {
		t.Fatalf("missing reviews output: %s", output)
	}
	if !strings.Contains(output, "Status: CLOSED_TEMPORARILY") {
		t.Fatalf("missing status output: %s", output)
	}

	resolve := goplaces.LocationResolveResponse{
		Results: []goplaces.ResolvedLocation{{PlaceID: "loc-1", Name: "Downtown"}},
	}
	outResolve := renderResolve(NewColor(false), resolve)
	if !strings.Contains(outResolve, "Resolved") {
		t.Fatalf("unexpected resolve output: %s", outResolve)
	}
}

func TestRenderPhoto(t *testing.T) {
	output := renderPhoto(NewColor(false), goplaces.PhotoMediaResponse{
		Name:     "places/place-1/photos/photo-1",
		PhotoURI: "https://example.com/photo.jpg",
	})
	if !strings.Contains(output, "Photo") {
		t.Fatalf("missing photo header")
	}
	if !strings.Contains(output, "photo.jpg") {
		t.Fatalf("missing photo uri")
	}
}

func TestColorEnabled(t *testing.T) {
	t.Setenv("NO_COLOR", "1")
	if colorEnabled(false) {
		t.Fatalf("expected color disabled")
	}
}

func TestColorEnabledTermDumb(t *testing.T) {
	t.Setenv("NO_COLOR", "")
	t.Setenv("TERM", "dumb")
	if colorEnabled(false) {
		t.Fatalf("expected color disabled")
	}
}

func TestColorEnabledTrue(t *testing.T) {
	prev, had := os.LookupEnv("NO_COLOR")
	_ = os.Unsetenv("NO_COLOR")
	t.Cleanup(func() {
		if had {
			_ = os.Setenv("NO_COLOR", prev)
		} else {
			_ = os.Unsetenv("NO_COLOR")
		}
	})
	t.Setenv("TERM", "xterm-256color")
	if !colorEnabled(false) {
		t.Fatalf("expected color enabled")
	}
}

func TestUniqueStrings(t *testing.T) {
	values := uniqueStrings([]string{"cafe", "Cafe", "cafe", ""})
	if len(values) != 2 {
		t.Fatalf("unexpected unique count: %d", len(values))
	}
}

func TestColorWrap(t *testing.T) {
	color := NewColor(true)
	value := color.Green("ok")
	if !strings.Contains(value, "ok") {
		t.Fatalf("unexpected wrapped value: %s", value)
	}
	value = color.Yellow("warn")
	if !strings.Contains(value, "warn") {
		t.Fatalf("unexpected wrapped value: %s", value)
	}
}

func floatPtr(v float64) *float64 {
	return &v
}
