# Directions

Use the Routes API (`computeRoutes`) to get distance, duration, and step-by-step instructions.

## Enable the API

- Enable **Routes API** in Google Cloud Console for the same project as Places.
- Use the same `GOOGLE_PLACES_API_KEY` (recommended).

## Examples

Walking summary:

```bash
goplaces directions --from "Pike Place Market" --to "Space Needle"
```

Place ID driven:

```bash
goplaces directions --from-place-id <fromId> --to-place-id <toId>
```

Walking with driving comparison + steps:

```bash
goplaces directions --from-place-id <fromId> --to-place-id <toId> --compare drive --steps
```

Imperial units:

```bash
goplaces directions --from-place-id <fromId> --to-place-id <toId> --units imperial
```

Driving route modifiers:

```bash
goplaces directions --from "Paris" --to "Brest" --mode drive --avoid-tolls
goplaces directions --from "Paris" --to "Brest" --mode drive --avoid-highways --avoid-ferries
```

Time-aware routing:

```bash
goplaces directions --from "GIG Airport" --to "Leblon, Rio de Janeiro" --mode drive --departure-time "2026-05-10T18:57:00-03:00"
goplaces directions --from "Pike Place Market" --to "Space Needle" --arrival-time "2026-05-10T19:30:00-07:00"
```

## Notes

- Default mode is walking.
- Default units are metric (use `--units imperial` for miles/feet).
- Use `--steps` for turn-by-turn instructions.
- Use `--compare drive` to add a driving ETA.
- Use `--departure-time` or `--arrival-time` with an RFC3339 timestamp to request time-aware routing. The two flags are mutually exclusive.
- Use `--avoid-tolls`, `--avoid-highways`, and `--avoid-ferries` with `--mode drive` to request drive routes that avoid those features when reasonable.
