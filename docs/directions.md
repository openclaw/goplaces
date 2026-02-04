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

Imperial units:

```bash
goplaces directions --from-place-id <fromId> --to-place-id <toId> --units imperial
```

## Notes

- Default mode is walking.
- Default units are metric (use `--units imperial` for miles/feet).
- Use `--steps` for turn-by-turn instructions.
- Use `--compare drive` to add a driving ETA.
