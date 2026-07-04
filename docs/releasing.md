# Releasing

Quick, repeatable release checklist. Mirrors gifgrep cadence.

## Before

- Update `CHANGELOG.md` for the new version.
- Run gate: `./scripts/check-coverage.sh` + `golangci-lint run ./...`.
- Ensure `main` is clean and pushed.
- Ensure `gh` is authenticated for `openclaw/goplaces` + `openclaw/homebrew-tap`.

## Tag + Build

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

GitHub Actions runs GoReleaser on tag push (`.github/workflows/release.yml`).
GoReleaser publishes the GitHub release archives, checksums, and Homebrew cask.

## Verify Release

- GitHub release exists for `vX.Y.Z` with archives and checksums.
- `openclaw/homebrew-tap` has `Casks/goplaces.rb` for `X.Y.Z` and maps former Formula users through `tap_migrations.json`.
- `brew update && brew install --cask openclaw/tap/goplaces` works.

## Notes

- CLI version set via ldflags in `.goreleaser.yml`:
  `-X github.com/steipete/goplaces/internal/cli.Version={{.Version}}`
- Local smoke build: `make goplaces`
