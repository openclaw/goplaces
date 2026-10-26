# Development

The repository keeps Go 1.26.8 as its minimum version and selects Go 1.27.3 through the `toolchain` directive in `go.mod`. Use Go 1.27.3 for development and builds so standard-library security fixes are included.

## Local checks

```sh
go mod download
go build ./...
make lint test coverage
```

The coverage target enforces the repository's coverage threshold. The CI workflow also runs workflow linting, static analysis, security scanners, release configuration checks, and credential-free release builds.

CI uses golangci-lint 2.15.0 and gosec 2.30.0. Both include `golang.org/x/tools` 0.52.0 for Go 1.27 export-data support; gosec no longer needs a temporary module to override its importer dependency.

Use `make lint-check` to check formatting without modifying files. CI uses Go 1.27.3 on Linux, macOS, and Windows, runs race tests on macOS and Windows, and verifies the Node documentation metadata tests and generated index. Staticcheck runs through golangci-lint.

The macOS audit and credential-free release checks use the Apple Silicon `xcode-27` runner (macOS 27). The existing Mach-O checks still require macOS 13.0 for both shipped Darwin architectures.

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
