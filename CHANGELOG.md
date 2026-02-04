# Changelog

## 0.2.2 - Unreleased

- Add Directions API support (`goplaces directions`) with walking default, units control (metric default), optional steps, and drive comparison.

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
