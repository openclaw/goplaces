# Client reference notes

The public package mirrors the CLI workflows through typed request and response types. The generated package reference is at [pkg.go.dev](https://pkg.go.dev/github.com/steipete/goplaces).

These request details are easy to miss when moving between the CLI and library:

- `Filters.Types` maps to Google's singular `includedType`; only the first value is sent.
- Search price levels use integers from `0` (free) through `4` (very expensive).
- Coordinates, radii, and minimum ratings must be finite numbers; invalid values fail validation before any API calls.
- Autocomplete accepts a zero-radius point bias; search and nearby radii must remain greater than zero. All circle radii are limited to 50,000 meters.
- Nearby included and excluded type lists accept at most 50 entries each and must not overlap.
- Directions timestamps use RFC3339 with two-digit hours, dot-separated fractional seconds, and valid timezone offsets.
- Details include reviews or photos only when `IncludeReviews` or `IncludePhotos` is set.
- `PhotoMediaRequest` requires `MaxWidthPx` or `MaxHeightPx`; each supplied dimension must be between 1 and 4800.
- Search and nearby responses include `NextPageToken` when Google returns one. Place summaries include business status when it is present upstream.
- Route search and directions require Routes API to be enabled.
- CLI directions route modifiers apply only to a driving primary or comparison route.

Field masks are defined with each request implementation so calls ask Google only for the fields represented by that workflow.

Redirects may stay within the original origin (scheme, hostname, and port); redirects to another origin are rejected to keep the API key scoped to the configured endpoint. Configure an endpoint override directly when using a different host. A custom `HTTPClient.CheckRedirect` can still stop redirects. API keys echoed in upstream or transport diagnostics are redacted; error causes remain available through `errors.Is` and `errors.As`.

Only final 2xx responses are decoded as results. Other HTTP statuses return an `APIError`, including redirects stopped with `http.ErrUseLastResponse` or returned without a `Location` header. Responses are limited to 1 MiB; larger bodies return an explicit size error instead of decoding a truncated payload. Oversized HTTP error responses retain their status in `APIError` and replace the body with a size diagnostic. The CLI exits with code 1 for these response failures.

Interrupted HTTP error bodies retain both the `APIError` status and the read-error cause through `errors.As` and `errors.Is`. A successful JSON `null` body is rejected instead of becoming an empty result. Endpoint overrides preserve proxy query parameters and escaped path segments; directions and route overrides may include the complete `/directions/v2:computeRoutes` path.

CLI parse errors write usage and diagnostics to stderr, leaving stdout available for results. Explicit result limits must be within the command's documented bounds, including when passing zero; omitting the flag retains its default. Library request structs still use zero-valued limits to select defaults. Human-readable results preserve Unicode shaping joiners used in names and emoji while removing terminal and bidi controls; diagnostics retain stricter format-control filtering.
