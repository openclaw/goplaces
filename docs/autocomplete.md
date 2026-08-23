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

## Notes

- Use a session token for billing consistency across autocomplete + details.
- Limit is applied client-side after the API response.

`--radius-m` also accepts the shorter `--radius` spelling.
