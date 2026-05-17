# Changelog

## Unreleased

- Normalize and escape details/photo resource paths, including full `places/...` names and photo names already ending in `/media`.
- Surface public client methods in root package documentation and editor tooling.
- Accept full Routes API endpoint overrides for route search without duplicating `/directions/v2:computeRoutes`.
- Return full search and nearby response objects for JSON output, including `next_page_token`.
- Fix manual release dispatch tag handling to avoid shell interpolation and validate tag shape.
- Restore support for free (`0`) price-level search filters.

## 0.4.1 - 2026-05-17

- Harden Places request validation and human CLI output sanitization.
- Remove the advertised no-op `--verbose` flag.
- Add time-aware directions with `--departure-time` and transit-only `--arrival-time`. - thanks @voska

## 0.4.0 - 2026-05-04

- Add `business_status` to search, nearby, details, JSON output, and human CLI output. (#8) - thanks @doomsday-rgb
- Add drive-only `--avoid-tolls`, `--avoid-highways`, and `--avoid-ferries` direction flags backed by Routes API `routeModifiers`. (#7) - thanks @gabob23

## 0.3.0 - 2026-02-14

- Add user rating counts (`user_rating_count`) in search/nearby/details and CLI output (`Rating: 4.5 (532)`). (#3) - thanks @aligurelli
- Add `goplaces directions` on Routes API with walking default, units control (metric default), optional steps, and drive comparison. - thanks @joshp123

## 0.2.1 - 2026-01-23

- CLI: accept long flags with `--flag=value` (same behavior as space-separated).
- Docs: note `--flag=value` support for long flags.

## 0.2.0 - 2026-01-02

- Autocomplete suggestions for places and queries (client + CLI).
- Nearby search with included/excluded types and location restriction.
- Place photos in details plus photo media URL lookup.
- Route search along a driving route using the Routes API. (#1) — thanks @jamesbrooksco
- Added Routes API base URL override (`GOOGLE_ROUTES_BASE_URL`).
- Docs: expanded API key setup, inline CLI examples, and new feature docs.
- CI: upgrade golangci-lint v2; goreleaser build-only CI mode.

## 0.1.0 - 2026-01-02

- Go client for Google Places API (New).
- Text search with filters: keyword, type, open now, min rating, price levels.
- Location bias (lat/lng/radius) and pagination tokens.
- Place details with hours, phone, website, rating, price, types.
- Optional reviews in details (`IncludeReviews` / `--reviews`).
- Resolve free-form location strings to candidate places.
- Locale hints (language + region) for search/resolve/details.
- Typed models, validation errors, and API error surfacing.
- CLI commands: `search`, `details`, `resolve` with color output + `--json`.
- Env/flag config: API key, base URL, timeouts, verbose logging.
- Lint/format guardrails + >= 90% coverage gate.
- GitHub Actions CI for tests, coverage, and linting.
