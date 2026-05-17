# goplaces

Modern Go client and CLI for the Google Places API (New), plus selected Routes API workflows.

Docs site: https://goplaces.sh

Use it when you want Google place data from a terminal, shell script, agent, or Go program without hand-writing Places field masks and request payloads. `goplaces` keeps the human CLI pleasant, but the same commands also emit stable JSON for automation.

Typical jobs:

- Find places by text, type, rating, price, current open state, and location bias.
- Inspect a place: address, coordinates, phone, website, hours, photos, reviews, current open state, and business status.
- Autocomplete partial place/query input.
- Search nearby a lat/lng radius.
- Resolve free-form locations to place candidates.
- Search for places along a route.
- Get directions, travel time, distance, steps, units, and drive route modifiers.

## Project Shape

- `cmd/goplaces`: CLI entrypoint built around the library.
- Root package `github.com/steipete/goplaces`: stable public Go API.
- `internal/places`: Places + Routes implementation and focused client tests.
- `internal/cli`: command parsing, output rendering, and CLI tests.
- Places API (New): search, nearby, details, autocomplete, photo media, resolve.
- Routes API: route polyline sampling and directions.
- Output: compact color text by default, JSON with `--json`.
- Runtime config: environment variables or flags.

## Install / Run

Latest release: v0.4.1 (2026-05-17).

- Homebrew: `brew install steipete/tap/goplaces`
- Go: `go install github.com/steipete/goplaces/cmd/goplaces@latest`
- Source: `make goplaces`

## API Setup

`goplaces` needs a Google API key with the right APIs enabled:

- Places API (New) for `search`, `nearby`, `autocomplete`, `details`, `photo`, and `resolve`.
- Routes API for `route` and `directions`.

```bash
export GOOGLE_PLACES_API_KEY="..."
```

Optional overrides:

- `GOOGLE_PLACES_BASE_URL` (testing, proxying, or mock servers)
- `GOOGLE_ROUTES_BASE_URL` (testing Routes API or proxying)
- `GOOGLE_DIRECTIONS_BASE_URL` (testing Routes API directions calls or proxying)

### Create a Key

1. **Create a Google Cloud Project**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Click "Select a project" → "New Project"
   - Name it (e.g., "goplaces") and click "Create"

2. **Enable the Places API (New)**
   - Go to [APIs & Services → Library](https://console.cloud.google.com/apis/library)
   - Search for "Places API (New)" — make sure it says **(New)**!
   - Click "Enable"

3. **Enable the Routes API (for `route` and `directions`)**
   - Search for "Routes API"
   - Click "Enable"

4. **Create an API Key**
   - Go to [APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials)
   - Click "Create Credentials" → "API Key"
   - Copy the key

5. **Set the Environment Variable**
   ```bash
   export GOOGLE_PLACES_API_KEY="your-api-key-here"
   ```
   Add to your `~/.zshrc` or `~/.bashrc` to persist.

6. **(Recommended) Restrict the Key**
   - Click on the key in Credentials
   - Under "API restrictions", select "Restrict key" → add "Places API (New)" and "Routes API"
   - Set quota limits in [Quotas](https://console.cloud.google.com/apis/api/places.googleapis.com/quotas)

> **Note**: The Places API has usage costs. Check [pricing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing) and set budget alerts!

## CLI Overview

Long flags accept `--flag value` or `--flag=value` (examples use space).

```text
goplaces [--api-key=KEY] [--base-url=URL] [--routes-base-url=URL] [--directions-base-url=URL] [--timeout=10s] [--json] [--no-color]
         <command>

Commands:
  autocomplete  Autocomplete places and queries.
  nearby        Search nearby places by location.
  search   Search places by text query.
  route    Search places along a route.
  directions  Get directions between two points.
  details  Fetch place details by place ID.
  photo    Fetch a photo URL by photo name.
  resolve  Resolve a location string to candidate places.
```

Command map:

| Command | API | Use |
| --- | --- | --- |
| `search` | Places Text Search | Find places by query and filters. |
| `nearby` | Places Nearby Search | Find places around a lat/lng radius. |
| `autocomplete` | Places Autocomplete | Get place/query suggestions for partial input. |
| `details` | Place Details | Fetch rich place data by place ID. |
| `photo` | Place Photo Media | Turn a photo resource name into a media URL. |
| `resolve` | Places Text Search | Resolve a free-form location string. |
| `route` | Routes + Places | Sample a route and search near waypoints. |
| `directions` | Routes | Get distance, duration, warnings, and steps. |

## Examples

Search with filters + location bias:

```bash
goplaces search "coffee" --min-rating 4 --open-now --limit 5 \
  --lat 40.8065 --lng -73.9719 --radius-m 3000 --language en --region US
```

Pagination:

```bash
goplaces search "pizza" --page-token "NEXT_PAGE_TOKEN"
```

Autocomplete:

```bash
goplaces autocomplete "cof" --session-token "goplaces-demo" --limit 5 --language en --region US
```

Nearby search:

```bash
goplaces nearby --lat 47.6062 --lng -122.3321 --radius-m 1500 --type cafe --limit 5
```

Route search:

```bash
goplaces route "coffee" --from "Seattle, WA" --to "Portland, OR" --max-waypoints 5
```

Directions (walking with optional driving comparison):

```bash
goplaces directions --from "Pike Place Market" --to "Space Needle"
goplaces directions --from-place-id <fromId> --to-place-id <toId> --compare drive --steps
```

Driving route modifiers:

```bash
goplaces directions --from "Paris" --to "Brest" --mode drive --avoid-tolls
goplaces directions --from "Paris" --to "Brest" --mode drive --avoid-highways --avoid-ferries
```

Time-aware routing:

```bash
DEPARTURE_TIME="$(python3 -c 'from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc)+timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
ARRIVAL_TIME="$(python3 -c 'from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc)+timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
goplaces directions --from "GIG Airport" --to "Leblon, Rio de Janeiro" --mode drive --departure-time "$DEPARTURE_TIME"
goplaces directions --from "Pike Place Market" --to "Space Needle" --mode transit --arrival-time "$ARRIVAL_TIME"
```

Transit arrival times must be within Google's schedule window: up to 7 days in the past or 100 days in the future.

Units (default metric):

```bash
goplaces directions --from "Pike Place Market" --to "Space Needle" --units imperial
```

Details:

```bash
goplaces details ChIJ-bfVTh8VkFQRDZLQnmioK9s
goplaces details ChIJN1t_tDeuEmsRUsoyG83frY4 --reviews
goplaces details ChIJN1t_tDeuEmsRUsoyG83frY4 --photos
```

Photo URL:

```bash
goplaces photo "places/PLACE_ID/photos/PHOTO_ID" --max-width 1200
```

Resolve:

```bash
goplaces resolve "Riverside Park, New York" --limit 5
```

JSON output:

```bash
goplaces search "sushi" --json
```

Example JSON result fields include:

```json
{
  "place_id": "ChIJ-bfVTh8VkFQRDZLQnmioK9s",
  "name": "Space Needle",
  "address": "400 Broad St, Seattle, WA 98109, USA",
  "rating": 4.6,
  "user_rating_count": 58186,
  "open_now": true,
  "business_status": "OPERATIONAL"
}
```

## Library

```go
boolPtr := func(v bool) *bool { return &v }
floatPtr := func(v float64) *float64 { return &v }

client := goplaces.NewClient(goplaces.Options{
    APIKey:  os.Getenv("GOOGLE_PLACES_API_KEY"),
    Timeout: 8 * time.Second,
})

search, err := client.Search(ctx, goplaces.SearchRequest{
    Query: "italian restaurant",
    Filters: &goplaces.Filters{
        OpenNow:   boolPtr(true),
        MinRating: floatPtr(4.0),
        Types:     []string{"restaurant"},
    },
    LocationBias: &goplaces.LocationBias{Lat: 40.8065, Lng: -73.9719, RadiusM: 3000},
    Language:     "en",
    Region:       "US",
    Limit:        10,
})

details, err := client.DetailsWithOptions(ctx, goplaces.DetailsRequest{
    PlaceID:        "ChIJN1t_tDeuEmsRUsoyG83frY4",
    Language:       "en",
    Region:         "US",
    IncludeReviews: true,
})

autocomplete, err := client.Autocomplete(ctx, goplaces.AutocompleteRequest{
    Input:        "cof",
    SessionToken: "goplaces-demo",
    Limit:        5,
    Language:     "en",
    Region:       "US",
})

nearby, err := client.NearbySearch(ctx, goplaces.NearbySearchRequest{
    LocationRestriction: &goplaces.LocationBias{Lat: 47.6062, Lng: -122.3321, RadiusM: 1500},
    IncludedTypes:       []string{"cafe"},
    Limit:               5,
})

photo, err := client.PhotoMedia(ctx, goplaces.PhotoMediaRequest{
    Name:       "places/PLACE_ID/photos/PHOTO_ID",
    MaxWidthPx: 1200,
})

route, err := client.Route(ctx, goplaces.RouteRequest{
    Query:        "coffee",
    From:         "Seattle, WA",
    To:           "Portland, OR",
    MaxWaypoints: 5,
})
```

## Notes

- `Filters.Types` maps to `includedType` (Google accepts a single value). Only the first type is sent.
- Price levels in search filters map to Google enums: `0` (free) → `4` (very expensive).
- Reviews are returned only when `IncludeReviews`/`--reviews` is set.
- Photos are returned only when `IncludePhotos`/`--photos` is set.
- Photo media requires `MaxWidthPx` or `MaxHeightPx`; each provided dimension must be 1-4800.
- Route search requires the Google Routes API to be enabled.
- `business_status` is returned for search, nearby, and details when Google includes it.
- Direction route modifiers (`--avoid-tolls`, `--avoid-highways`, `--avoid-ferries`) require `--mode drive`.
- Field masks are defined alongside each request (e.g. `search.go`, `details.go`, `autocomplete.go`).
- The Places API is billed and quota-limited; keep an eye on your Cloud Console quotas.

## Testing

```bash
make lint test coverage
```

### E2E tests (optional)

```bash
export GOOGLE_PLACES_API_KEY="..."
make e2e
```

Optional env overrides:

- Use a custom endpoint (proxy/mock): `GOOGLE_PLACES_E2E_BASE_URL`
- Override the search text used in E2E: `GOOGLE_PLACES_E2E_QUERY`
- Override language code for E2E: `GOOGLE_PLACES_E2E_LANGUAGE`
- Override region code for E2E: `GOOGLE_PLACES_E2E_REGION`
- Override directions endpoints/locations: `GOOGLE_DIRECTIONS_E2E_BASE_URL`, `GOOGLE_PLACES_E2E_DIRECTIONS_FROM`, `GOOGLE_PLACES_E2E_DIRECTIONS_TO`
