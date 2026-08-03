# Client reference notes

The public package mirrors the CLI workflows through typed request and response types. The generated package reference is at [pkg.go.dev](https://pkg.go.dev/github.com/steipete/goplaces).

These request details are easy to miss when moving between the CLI and library:

- `Filters.Types` maps to Google's singular `includedType`; only the first value is sent.
- Search price levels use integers from `0` (free) through `4` (very expensive).
- Details include reviews or photos only when `IncludeReviews` or `IncludePhotos` is set.
- `PhotoMediaRequest` requires `MaxWidthPx` or `MaxHeightPx`; each supplied dimension must be between 1 and 4800.
- Search and nearby responses include `NextPageToken` when Google returns one. Place summaries include business status when it is present upstream.
- Route search and directions require Routes API to be enabled.
- CLI directions route modifiers apply only to a driving primary or comparison route.

Field masks are defined with each request implementation so calls ask Google only for the fields represented by that workflow.
