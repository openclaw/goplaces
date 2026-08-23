# Route Search

Route search samples waypoints along a route and runs a text search at each waypoint.

## CLI

```bash
goplaces route "coffee" --from "Seattle, WA" --to "Portland, OR" --max-waypoints 5
```

Options:

- `--mode` travel mode: DRIVE, WALK, BICYCLE, TWO_WHEELER, TRANSIT.
- `--radius-m` (alias `--radius`) search radius per waypoint.
- `--limit` results per waypoint.

## Library

```go
response, err := client.Route(ctx, goplaces.RouteRequest{
    Query:        "coffee",
    From:         "Seattle, WA",
    To:           "Portland, OR",
    Mode:         "DRIVE",
    RadiusM:      1000,
    MaxWaypoints: 5,
    Limit:        5,
})
```

## Notes

- Requires the Google Routes API to be enabled.
- Waypoints are sampled evenly along the route polyline.
