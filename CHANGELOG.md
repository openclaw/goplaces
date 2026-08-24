# Changelog

## 0.4.8 - 2026-08-24

- Release: 0.4.5, 0.4.6 and 0.4.7 were tagged while bringing up the signed release automation and were never published; they carry the same code as this release.
- CLI: accept `--radius` as an alias for `--radius-m` on `search`, `nearby`, `autocomplete`, and `route`.
- Docs: validate generated llms metadata as plain text and keep the metadata helper import-safe. (#29) - thanks @vincentkoc
- Docs: rewrite the README around verified install, quick-start, and reference paths.
- Release: accept interpolated Cask URLs and make completed release reruns idempotent.
- Release: keep the pinned GitHub transport reusable across shell command substitutions.
- Release: accept the reviewed Homebrew revision of the pinned Node 26.5.0 toolchain.
- Release: bind the pinned Go toolchain to its canonical Homebrew root across isolated build and signing steps.
- Release: run credential-free release contract suites with the frozen jq 1.8.2 parser.
- Release: refresh the reviewed release toolchain pins to GitHub CLI 2.98.0, GoReleaser 2.17.1, Node 26.7.0, and Python 3.14.7.
- Release: accept the reviewed release-mac-app helper revision that scrubs package signing authority and narrows credential inheritance.
- Release: resolve the signing account's keychain domain in the Darwin codesign hook so official signing works under the producer's isolated HOME.
- Release: accept GitHub's release-body newline normalization, the untagged asset URLs GitHub serves for drafts, and its JWT-style Actions tokens.
- Release: match redirect headers without awk IGNORECASE so asset downloads work under the macOS awk the verifier runs on.
- CI: install the reviewed GitHub CLI before the release contract suite instead of inheriting the runner image's version.
- Security: require Go 1.26.7 and scan both source and built binaries with pinned govulncheck. The 1.26.6 floor landed in #30 - thanks @vincentkoc
- Build: update golangci-lint to 2.13.1 and staticcheck to 0.8.1 for Go 1.27 support.
- CLI: report the tagged module version for `go install github.com/steipete/goplaces/cmd/goplaces@latest`; linked release versions still win and local builds remain `dev`.
- Release: sign and notarize official macOS binaries with the OpenClaw Foundation Developer ID while keeping ordinary and cross-platform builds credential-free.

## 0.4.4 - 2026-07-04

- CLI: accept space-separated negative numeric flag values such as coordinates. (#17) - thanks @technicalpickles
- Release: update GoReleaser to 2.16.0 and migrate Homebrew publishing from Formula to Cask.
- Build: refresh the required Go toolchain and update golangci-lint to 2.12.2.
- Docs: define project direction and compatibility policy.

## 0.4.3 - 2026-05-20

- Sanitize API error text before writing CLI errors to stderr.
- Apply directions `--avoid-*` flags to a driving comparison request when the primary mode is not driving.
- Release: publish Homebrew formula updates through `openclaw/tap`.
- Docs: point Homebrew install and release links at `openclaw/tap` and `openclaw/goplaces`.

## 0.4.2 - 2026-05-17

- Add CI audit checks for workflows, Staticcheck, gosec, govulncheck, and GoReleaser config.
- Make human output truncation UTF-8 safe and strip Unicode format controls.
- Run route waypoint searches in parallel and deduplicate repeated place results.
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
