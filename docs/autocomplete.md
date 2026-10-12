# Autocomplete

Autocomplete returns place + query suggestions for partial text.

## CLI

```bash
goplaces autocomplete "cof" \
  --session-token "goplaces-demo" \
  --limit 5 \
  --language en \
  --region US
```

Optional location bias:

```bash
goplaces autocomplete "pizza" --lat 40.7411 --lng -73.9897 --radius-m 1500
```

## Library

```go
response, err := client.Autocomplete(ctx, goplaces.AutocompleteRequest{
    Input:        "cof",
    SessionToken: "goplaces-demo",
    Limit:        5,
    Language:     "en",
    Region:       "US",
})
```

Complete the session with the selected place ID and the same token:

```bash
goplaces details "SELECTED_PLACE_ID" --session-token "goplaces-demo"
```

```go
place, err := client.DetailsWithOptions(ctx, goplaces.DetailsRequest{
    PlaceID:      "SELECTED_PLACE_ID",
    SessionToken: "goplaces-demo",
})
```

## Notes

- Generate a unique token per session, pass the same token to autocomplete and the terminating details request, and use API keys from the same Google Cloud project. Do not reuse a completed token.
- Session pricing depends on the terminating details request and its requested fields; this client preserves its existing details field mask. The current non-Essentials details field mask means Google bills a terminating session details request at its Enterprise + Atmosphere SKU. See [Google session pricing](https://developers.google.com/maps/documentation/places/web-service/session-pricing) and [session token guidance](https://developers.google.com/maps/documentation/places/web-service/using-session-tokens).
- Limit is applied client-side after the API response.

`--radius-m` also accepts the shorter `--radius` spelling.
