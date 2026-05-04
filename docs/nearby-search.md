# Nearby Search

Nearby search finds places around a specific location restriction.

## CLI

```bash
goplaces nearby --lat 47.6062 --lng -122.3321 --radius-m 1500 \
  --type cafe --type bakery \
  --limit 5
```

Exclude types:

```bash
goplaces nearby --lat 47.6062 --lng -122.3321 --radius-m 1500 \
  --exclude-type bar
```

## Library

```go
response, err := client.NearbySearch(ctx, goplaces.NearbySearchRequest{
    LocationRestriction: &goplaces.LocationBias{Lat: 47.6062, Lng: -122.3321, RadiusM: 1500},
    Limit:               5,
    IncludedTypes:       []string{"cafe"},
    ExcludedTypes:       []string{"bar"},
    Language:            "en",
    Region:              "US",
})
```

## Notes

- Location restriction (lat/lng/radius) is required.
- Use `IncludedTypes`/`--type` to filter result types.
- Results include `business_status` when Google returns it.
