package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/alecthomas/kong"

	"github.com/steipete/goplaces"
)

const locationCoordinatesRequired = "lat, lng, radius required"

// App wires CLI output and API access.
type App struct {
	client *goplaces.Client
	out    io.Writer
	json   bool
	color  Color
}

// Run executes the CLI with the provided arguments.
func Run(args []string, stdout, stderr io.Writer) int {
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
		kong.WithHyphenPrefixedParameters(true),
		kong.Writers(stdout, stderr),
		kong.Exit(func(code int) {
			exitCode = code
			panic(exitSignal{code: code})
		}),
		kong.Vars{"version": currentVersion()},
	)
	if err != nil {
		writeError(stderr, err.Error())
		return 1
	}

	ctx, exited, err := parseWithExit(parser, args, &exitCode)
	if exited {
		return exitCode
	}
	if err != nil {
		if parseErr, ok := err.(*kong.ParseError); ok {
			_ = parseErr.Context.PrintUsage(true)
			writeError(stderr, parseErr.Error())
			return parseErr.ExitCode()
		}
		writeError(stderr, err.Error())
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
		writeError(writer, validation.Error())
		return 2
	}
	if errors.Is(err, goplaces.ErrMissingAPIKey) {
		writeError(writer, err.Error())
		return 2
	}
	writeError(writer, err.Error())
	return 1
}

func writeError(writer io.Writer, message string) {
	_, _ = fmt.Fprintln(writer, sanitizeTerminalText(message))
}
