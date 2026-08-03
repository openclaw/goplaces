# Development

The repository requires the Go version declared in `go.mod`.

## Local checks

```sh
go mod download
go build ./...
make lint test coverage
```

The coverage target enforces the repository's coverage threshold. The CI workflow also runs workflow linting, static analysis, security scanners, release configuration checks, and credential-free release builds.

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
