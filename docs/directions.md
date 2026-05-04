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

## Notes

- Default mode is walking.
- Default units are metric (use `--units imperial` for miles/feet).
- Use `--steps` for turn-by-turn instructions.
- Use `--compare drive` to add a driving ETA.
- Use `--avoid-tolls`, `--avoid-highways`, and `--avoid-ferries` with `--mode drive` to request drive routes that avoid those features when reasonable.
