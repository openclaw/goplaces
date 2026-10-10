# Development

The repository keeps Go 1.26.8 as its minimum version and selects Go 1.27.2 through the `toolchain` directive in `go.mod`. Use Go 1.27.2 for development and builds so standard-library security fixes are included.

## Local checks

```sh
go mod download
go build ./...
make lint test coverage
```

The coverage target enforces the repository's coverage threshold. The CI workflow also runs workflow linting, static analysis, security scanners, release configuration checks, and credential-free release builds.

CI builds gosec 2.29.0 with `golang.org/x/tools` 0.51.0 in a temporary module so its importer supports Go 1.27 export data without adding scanner dependencies to the application module.

Use `make lint-check` to check formatting without modifying files. CI uses Go 1.27.2 on Linux, macOS, and Windows, runs race tests on macOS and Windows, and verifies the Node documentation metadata tests and generated index. Staticcheck runs through golangci-lint.

## Authenticated end-to-end tests

End-to-end tests are optional because they call Google services and incur normal quota or billing usage.

```sh
export GOOGLE_PLACES_API_KEY="..."
make e2e
```

The suite accepts these overrides for controlled proxies, mock servers, and test fixtures:

- `GOOGLE_PLACES_E2E_BASE_URL`
- `GOOGLE_PLACES_E2E_QUERY`
- `GOOGLE_PLACES_E2E_LANGUAGE`
- `GOOGLE_PLACES_E2E_REGION`
- `GOOGLE_DIRECTIONS_E2E_BASE_URL`
- `GOOGLE_PLACES_E2E_DIRECTIONS_FROM`
- `GOOGLE_PLACES_E2E_DIRECTIONS_TO`
