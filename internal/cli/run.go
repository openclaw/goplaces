package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/alecthomas/kong"
	"github.com/steipete/goplaces"
)

// App wires CLI output and API access.
type App struct {
	client *goplaces.Client
	out    io.Writer
	err    io.Writer
	json   bool
	color  Color
}

// Run executes the CLI with the provided arguments.
func Run(args []string, stdout io.Writer, stderr io.Writer) int {
	if stdout == nil {
		stdout = os.Stdout
	}
	if stderr == nil {
		stderr = os.Stderr
	}

	root := Root{}
	exitCode := 0
	parser, err := kong.New(
		&root,
		kong.Name("goplaces"),
		kong.Description("Search and resolve places via the Google Places API (New)."),
		kong.UsageOnError(),
		kong.ConfigureHelp(kong.HelpOptions{Compact: true, Summary: true}),
		kong.Writers(stdout, stderr),
		kong.Exit(func(code int) {
			exitCode = code
			panic(exitSignal{code: code})
		}),
		kong.Vars{"version": Version},
	)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}

	ctx, exited, err := parseWithExit(parser, args, &exitCode)
	if exited {
		return exitCode
	}
	if err != nil {
		if parseErr, ok := err.(*kong.ParseError); ok {
			_ = parseErr.Context.PrintUsage(true)
			_, _ = fmt.Fprintln(stderr, parseErr.Error())
			return parseErr.ExitCode()
		}
		_, _ = fmt.Fprintln(stderr, err)
		return 2
	}
	if root.Global.JSON {
		// JSON output should never include ANSI escapes.
		root.Global.NoColor = true
	}

	client := goplaces.NewClient(goplaces.Options{
		APIKey:            root.Global.APIKey,
		BaseURL:           root.Global.BaseURL,
		RoutesBaseURL:     root.Global.RoutesBaseURL,
		DirectionsBaseURL: root.Global.DirectionsBaseURL,
		Timeout:           root.Global.Timeout,
	})

	app := &App{
		client: client,
		out:    stdout,
		err:    stderr,
		json:   root.Global.JSON,
		color:  NewColor(colorEnabled(root.Global.NoColor)),
	}

	ctx.Bind(app)
	if err := ctx.Run(); err != nil {
		return handleError(stderr, err)
	}

	return 0
}

type exitSignal struct {
	code int
}

func parseWithExit(parser *kong.Kong, args []string, exitCode *int) (ctx *kong.Context, exited bool, err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			if signal, ok := recovered.(exitSignal); ok {
				// kong uses Exit() hooks; convert to a normal return.
				if exitCode != nil {
					*exitCode = signal.code
				}
				exited = true
				ctx = nil
				err = nil
				return
			}
			panic(recovered)
		}
	}()
	ctx, err = parser.Parse(args)
	return ctx, exited, err
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

	filters := goplaces.Filters{}
	setFilters := false
	if c.Keyword != "" {
		filters.Keyword = c.Keyword
		setFilters = true
	}
	if len(c.Type) > 0 {
		filters.Types = c.Type
		setFilters = true
	}
	if c.OpenNow != nil {
		filters.OpenNow = c.OpenNow
		setFilters = true
	}
	if c.MinRating != nil {
		filters.MinRating = c.MinRating
		setFilters = true
	}
	if len(c.PriceLevel) > 0 {
		filters.PriceLevels = c.PriceLevel
		setFilters = true
	}
	if setFilters {
		request.Filters = &filters
	}

	if c.Lat != nil || c.Lng != nil || c.RadiusM != nil {
		if c.Lat == nil || c.Lng == nil || c.RadiusM == nil {
			return goplaces.ValidationError{Field: "location_bias", Message: "lat, lng, radius required"}
		}
		request.LocationBias = &goplaces.LocationBias{
			Lat:     *c.Lat,
			Lng:     *c.Lng,
			RadiusM: *c.RadiusM,
		}
	}

	response, err := app.client.Search(context.Background(), request)
	if err != nil {
		return err
	}

	if app.json {
		if err := writeJSON(app.out, response.Results); err != nil {
			return err
		}
		if response.NextPageToken != "" {
			_, _ = fmt.Fprintln(app.err, "next_page_token:", response.NextPageToken)
		}
		return nil
	}

	_, err = fmt.Fprintln(app.out, renderSearch(app.color, response))
	return err
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

	if c.Lat != nil || c.Lng != nil || c.RadiusM != nil {
		if c.Lat == nil || c.Lng == nil || c.RadiusM == nil {
			return goplaces.ValidationError{Field: "location_bias", Message: "lat, lng, radius required"}
		}
		request.LocationBias = &goplaces.LocationBias{
			Lat:     *c.Lat,
			Lng:     *c.Lng,
			RadiusM: *c.RadiusM,
		}
	}

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

// Run executes the nearby command.
func (c *NearbyCmd) Run(app *App) error {
	if c.Lat == nil || c.Lng == nil || c.RadiusM == nil {
		return goplaces.ValidationError{Field: "location_restriction", Message: "lat, lng, radius required"}
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
		if err := writeJSON(app.out, response.Results); err != nil {
			return err
		}
		if response.NextPageToken != "" {
			_, _ = fmt.Fprintln(app.err, "next_page_token:", response.NextPageToken)
		}
		return nil
	}

	_, err = fmt.Fprintln(app.out, renderNearby(app.color, response))
	return err
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

func writeJSON(writer io.Writer, value any) error {
	payload, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	_, err = writer.Write(append(payload, '\n'))
	return err
}

func handleError(writer io.Writer, err error) int {
	if err == nil {
		return 0
	}
	var validation goplaces.ValidationError
	if errors.As(err, &validation) {
		_, _ = fmt.Fprintln(writer, validation.Error())
		return 2
	}
	if errors.Is(err, goplaces.ErrMissingAPIKey) {
		_, _ = fmt.Fprintln(writer, err.Error())
		return 2
	}
	_, _ = fmt.Fprintln(writer, err.Error())
	return 1
}
