# AGENTS.md

`goplaces` is a small Go CLI. Keep changes focused, dependency-light, and easy
to validate with standard Go tooling.

## Rules

- Keep stdout parseable when adding machine-readable output.
- Do not commit credentials, local config, or generated `bin/` outputs.
- Prefer stdlib and existing package patterns before adding dependencies.
- Update README/docs when command flags or behavior change.

## Checks

```bash
go mod tidy
git diff --exit-code -- go.mod go.sum
go vet ./...
go test ./...
git diff --check
```
