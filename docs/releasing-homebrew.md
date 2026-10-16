# Homebrew release handoff

The [Actions release pipeline](releasing.md) updates `Formula/goplaces.rb` in `openclaw/homebrew-tap` after publishing the verified release. The caller maps repository secret `HOMEBREW_TAP_TOKEN` to the shared workflow's `TAP_TOKEN`; no local publisher or separate manual handoff is used.

The shared workflow sends the exact verified filenames and SHA-256 hashes for Darwin and Linux, both amd64 and arm64, to `update-formula.yml`. The tap independently downloads and hashes the archives. The release workflow then verifies that the resulting formula contains exactly those four release URLs and hashes. It does not accept workflow success alone as proof.

Keep the formula binary-only: install the published signed archives without rebuilding, modifying the executable, or removing quarantine. Verify formula version and all four hashes against independently downloaded release assets before release closeout.

Install with:

```bash
brew install openclaw/tap/goplaces
```

For an older Cask installation:

```bash
brew uninstall --cask goplaces
brew install openclaw/tap/goplaces
```
