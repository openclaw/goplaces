# Directions

Use the Directions API (legacy) to get distance, duration, and step-by-step instructions.

## Enable the API

- Enable **Directions API** in Google Cloud Console for the same project as Places.
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

## Notes

- Default mode is walking.
- Use `--steps` for turn-by-turn instructions.
- Use `--compare drive` to add a driving ETA.
