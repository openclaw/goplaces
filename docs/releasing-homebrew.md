# goplaces Homebrew Release Playbook

Homebrew cask update notes for the automated release.

## Prereqs

- Homebrew installed.
- Access to `openclaw/homebrew-tap`.

## Release

1) Tag + push: `git tag vX.Y.Z && git push origin vX.Y.Z`
2) GitHub Actions runs GoReleaser.
3) GoReleaser updates `openclaw/homebrew-tap` at `Casks/goplaces.rb`.
4) The release workflow adds the `tap_migrations.json` entry and removes the retired Formula in the same commit.

## Verify install

```bash
brew update && brew install --cask openclaw/tap/goplaces
```

## Troubleshooting

- If the cask is missing or stale, inspect the release workflow token check and GoReleaser `homebrew_casks` config.
- `Casks/goplaces.rb` is canonical. The old `Formula/goplaces.rb` must stay absent after migration.
