# goplaces 📍 — Find the place. Skip the payload archaeology.

![goplaces banner](docs/assets/readme-banner.jpg)

[![CI](https://img.shields.io/github/actions/workflow/status/openclaw/goplaces/ci.yml?branch=main&style=flat-square&label=ci)](https://github.com/openclaw/goplaces/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/openclaw/goplaces?style=flat-square)](https://github.com/openclaw/goplaces/releases/latest)
[![Go](https://img.shields.io/badge/Go-1.26.5-00ADD8?style=flat-square&logo=go&logoColor=white)](https://go.dev/dl/)
[![License](https://img.shields.io/github/license/openclaw/goplaces?style=flat-square)](LICENSE)
[![Homebrew](https://img.shields.io/badge/Homebrew-openclaw%2Ftap-FBB040?style=flat-square&logo=homebrew&logoColor=black)](https://github.com/openclaw/homebrew-tap/blob/main/Casks/goplaces.rb)
[![Docs](https://img.shields.io/badge/docs-goplaces.sh-3b82f6?style=flat-square)](https://goplaces.sh)

`goplaces` is a Go client and CLI for Google Places API (New) and selected Routes API workflows. It is for terminal use, shell automation, agents, and Go programs that need typed requests and JSON output without hand-building field masks or request payloads.

## Install

Homebrew installs the published binary on macOS or Linux:

```sh
brew install --cask openclaw/tap/goplaces
```

With Go 1.26.5 or newer:

```sh
go install github.com/steipete/goplaces/cmd/goplaces@latest
```

Prebuilt archives and checksums are available from [GitHub Releases](https://github.com/openclaw/goplaces/releases/latest).

## Quick start

Enable **Places API (New)** in a Google Cloud project, create an API key, then run:

```sh
export GOOGLE_PLACES_API_KEY="..."
goplaces search "coffee near Central Park" --limit 5
goplaces search "coffee near Central Park" --limit 5 --json
```

The default output is compact text for people; `--json` emits the response shape for scripts and agents. See [API key setup](docs/api-key-setup.md) for API enablement, key restrictions, billing, and quota guidance.

## Commands

| Command | What it does |
| --- | --- |
| [`search`](https://goplaces.sh/commands/search.html) | Finds places by text, filters, and optional location bias. |
| [`nearby`](https://goplaces.sh/commands/nearby.html) | Finds places inside a latitude, longitude, and radius. |
| [`autocomplete`](https://goplaces.sh/commands/autocomplete.html) | Returns place and query suggestions for partial input. |
| [`details`](https://goplaces.sh/commands/details.html) | Fetches place details, with optional reviews and photos. |
| [`photo`](https://goplaces.sh/commands/photo.html) | Resolves a Places photo resource to a media URL. |
| [`resolve`](https://goplaces.sh/commands/resolve.html) | Resolves free-form location text to place candidates. |
| [`route`](https://goplaces.sh/commands/route.html) | Samples a route and searches for places near its waypoints. |
| [`directions`](https://goplaces.sh/commands/directions.html) | Returns distance, duration, warnings, and optional steps. |

Run `goplaces <command> --help` for the current flags. Long flags accept both `--flag value` and `--flag=value`.

The `route` and `directions` commands also require **Routes API**. Directions default to walking with metric units and support driving comparisons, route modifiers, and departure or transit arrival times.

## Configuration

`GOOGLE_PLACES_API_KEY` supplies the API key to the CLI and Go client. The same key can access both APIs when they are enabled in one Google Cloud project.

These endpoint overrides are intended for tests, proxies, and mock servers:

| Environment variable | Default |
| --- | --- |
| `GOOGLE_PLACES_BASE_URL` | `https://places.googleapis.com/v1` |
| `GOOGLE_ROUTES_BASE_URL` | `https://routes.googleapis.com` |
| `GOOGLE_DIRECTIONS_BASE_URL` | `https://routes.googleapis.com` |

Global flags include `--api-key`, `--timeout`, `--json`, and `--no-color`. Command-specific examples and response details live at [goplaces.sh](https://goplaces.sh).

## Go client

The root module exposes the same search, nearby, autocomplete, details, photo, resolve, route, and directions workflows as typed Go methods.

```go
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/steipete/goplaces"
)

func main() {
	client := goplaces.NewClient(goplaces.Options{APIKey: os.Getenv("GOOGLE_PLACES_API_KEY")})
	result, err := client.Search(context.Background(), goplaces.SearchRequest{Query: "coffee", Limit: 5})
	if err != nil {
		panic(err)
	}
	fmt.Println(len(result.Results))
}
```

See the [Go package reference](https://pkg.go.dev/github.com/steipete/goplaces) for exported request and response types. The project's intended scope and compatibility boundaries are in [VISION.md](VISION.md).

## Development

Go 1.26.5 is required.

```sh
go mod download
go build ./...
make lint test coverage
```

Authenticated end-to-end tests are optional; see [development notes](docs/development.md).

## License

MIT. See [LICENSE](LICENSE).
