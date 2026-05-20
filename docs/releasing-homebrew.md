# goplaces Homebrew Release Playbook

Homebrew formula update notes for the automated release.

## Prereqs

- Homebrew installed.
- Access to `openclaw/homebrew-tap`.

## Release

1) Tag + push: `git tag vX.Y.Z && git push origin vX.Y.Z`
2) GitHub Actions runs GoReleaser.
3) GoReleaser updates `openclaw/homebrew-tap` at `Formula/goplaces.rb`.

## Verify install

```bash
brew update && brew install openclaw/tap/goplaces
```

## Troubleshooting

- If the formula is missing or stale, inspect the release workflow token check and GoReleaser `brews` config.
- If a root-level `goplaces.rb` appears in the tap, remove it; `Formula/goplaces.rb` is canonical.
