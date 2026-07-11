# goplaces Vision

`goplaces` is the small, dependable Go client and command-line tool for common Google Places API (New) workflows and selected Routes API workflows.

It should make place data pleasant to use from a terminal, reliable in shell automation, and straightforward to embed in Go without forcing users to build field masks, request payloads, pagination plumbing, or output formatting themselves.

## Priorities

When priorities conflict, choose in this order:

1. Correct, secure API behavior.
2. Stable automation contracts.
3. Clear errors and useful defaults.
4. Fast, readable human output.
5. Broader endpoint coverage.

## Product Shape

- One focused Go module with a reusable public package and one `goplaces` binary.
- Places API (New) is the center of gravity. Routes support exists where it directly improves place discovery or answers a common terminal workflow.
- The library owns typed requests and responses, validation, field masks, endpoint construction, and sanitized API errors.
- The CLI owns argument parsing, environment configuration, human rendering, JSON rendering, and exit behavior.
- Human output is concise by default. `--json` is the machine-readable path.
- Dependencies stay few, healthy, and on current stable compatible releases. The required Go version follows a supported stable toolchain.

## Compatibility Contracts

The following are compatibility surfaces:

- Exported identifiers and behavior in `github.com/steipete/goplaces`.
- CLI command names, documented flags, environment variables, and exit-code classes.
- JSON field names and response shapes emitted by `--json`.
- Documented install commands and release artifact names.

Human-readable text layout, color, spacing, and wording may improve without being treated as a machine API. Upstream Google fields that are not represented by the public types are not implicitly supported.

Before 1.0, a necessary breaking change must still be deliberate: document the reason and migration in the changelog, keep it out of patch releases, and prefer a clean new contract over an indefinite compatibility shim. Security fixes may tighten validation or reject previously accepted unsafe input.

## In Scope

- Text search, nearby search, autocomplete, details, photos, and free-form place resolution.
- Directions and route-aware place search built on the Routes API.
- Filters, locale hints, pagination, time-aware routing, route modifiers, and fields that materially improve those workflows.
- Deterministic JSON suitable for scripts and agents.
- Mockable endpoint overrides, focused client tests, and opt-in authenticated end-to-end tests.
- Release archives, checksums, Go installation, and Homebrew installation.

## Non-Goals

- A generated or exhaustive client for every Google Maps Platform endpoint.
- A long-running daemon, hosted proxy, credential broker, database, GUI, or account-management layer.
- Scraping Google consumer products or bypassing API keys, billing, quotas, or provider policy.
- Mirroring every upstream response field before a real user workflow needs it.
- Preserving undocumented quirks, human-output formatting, or test-only behavior as permanent compatibility promises.

## Feature Standard

A new user-facing workflow is ready when it has:

- A typed library boundary and explicit validation.
- Minimal field masks and request payloads appropriate to the workflow.
- CLI access when the workflow is useful from a terminal.
- Stable JSON output and readable human output where applicable.
- Tests for success, validation, upstream errors, and sensitive-output sanitization.
- Documentation with API enablement, billing or quota implications, and practical examples.
- Built-binary proof; authenticated end-to-end proof when an external API boundary changes.

## Security and Privacy

- API keys come from explicit flags or environment variables and must never appear in errors, logs, test fixtures, or public proof.
- Error output is sanitized before it reaches users.
- Endpoint overrides remain available for testing and controlled proxying; they do not weaken secret handling.
- New dependencies receive a health and security review. Security scanners and vulnerability checks remain release gates.

## Release Policy

- “Shipped” means available in a tagged GitHub Release, not merely merged to `main`.
- Releases include versioned archives, checksums, and verified downstream installation proof.
- Official macOS archives use the hardened runtime, a secure timestamp, Developer ID Application signing, and notarization. Homebrew must preserve quarantine and install the verified published bytes.
- Official release artifacts come from a fresh official-remote checkout pinned to the verified signed tag, never mutable maintainer working-tree bytes.
- Ordinary source and cross-platform builds remain credential-free. Only the managed local release path may access signing or notarization credentials, and CI must never publish unsigned Darwin artifacts.
- User-visible changes belong in `CHANGELOG.md`.
- Release automation must fail closed when credentials, artifacts, package metadata, or downstream installation proof are missing.
