# Releasing

Releases publish exclusively through [release.yml](../.github/workflows/release.yml), which calls [`openclaw/release-workflows`' Go CLI archetype at `@v1`](https://github.com/openclaw/release-workflows/blob/v1/README.md). The local publisher and its signing, draft, and handoff scripts are retired.

## Prepare and rehearse

1. Start from synchronized, clean, protected `main`. Require successful CI on the exact commit, including the credential-free snapshot/security checks.
2. Move every Unreleased bullet into a dated `## X.Y.Z - YYYY-MM-DD` section with a one-line `**Highlights:**`. Retain an empty `## Unreleased` above it. Land the release-preparation PR after review and CI.
3. Dispatch `release.yml` from that merged `main` commit with `version=X.Y.Z` and `dry_run=true`. Wait for that exact run to succeed before creating a tag. A rehearsal freezes current protected main, builds, signs, notarizes and verifies the artifacts without creating a tag, release, or Homebrew update.

```bash
gh workflow run release.yml --ref main -f version=X.Y.Z -F dry_run=true
```

## Publish

Create an annotated SSH-signed `vX.Y.Z` tag on the rehearsed release-preparation commit using the fleet release key. Verify it against `.github/release-allowed-signers` before pushing. Never replace an existing tag. The tag push starts publication; follow that exact run. Recovery can dispatch `release.yml` from current protected main with the same version and `dry_run=false`; the existing signed tag remains the immutable source. Consult the shared workflow's recovery contract before retrying a partially published run.

The caller requires independent push CI and valid tag signatures. Its credential-free macOS build pins the toolchain through `go.mod` and checks both thin Darwin binaries with `otool`: `LC_BUILD_VERSION` must declare macOS 13.0. Signing runs separately with the OpenClaw Foundation Developer ID, Team ID `FWJYW4S8P8`, hardened runtime, secure timestamp, and stable identifier `org.openclaw.goplaces`. Every Mac binary is notarized. Independent arm64 and Intel verifiers check signature, designated requirement, online notarization, architecture, inventory, checksums and native execution. Linux/Windows bytes also require an independent reproducible rebuild.

Only the publisher can promote the draft after matching both verifier attestations against the downloaded draft bytes. The six established platform archives and `goplaces_checksums.txt` retain their names; the workflow also publishes its inventory, signing manifest and release notes. Release notes must equal the dated changelog section. Bare CLI notarization uses `codesign --verify --strict --check-notarization -R=notarized`; raw executables do not support stapled tickets.

## Credentials and Homebrew

Provision repository secrets `MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_P8`. Preserve the existing `HOMEBREW_TAP_TOKEN` name; the caller maps it to the archetype's `TAP_TOKEN`. Follow the shared workflow README and the operator's 1Password procedure; never commit credentials.

The workflow hands verified archive names and hashes to `openclaw/homebrew-tap` and verifies `Formula/goplaces.rb` afterward. See [the Homebrew playbook](releasing-homebrew.md). Keeping `Unreleased` in the preparation commit preserves the repository convention and avoids needing an automated closeout PR.

## Verify and close out

Read the published release by tag and compare its body to the changelog. Download every asset by its URL, verify `goplaces_checksums.txt` and the inventory, then inspect both Mac binaries' signature, notarization ticket, architecture and minimum version. Run `--version` and a synthetic command using a downloaded native binary. Verify the Go module through `proxy.golang.org` and the four Homebrew URLs/hashes against downloaded archives. npm and Sparkle are not distribution channels for this CLI. Finish on synchronized clean `main` and record exact release/run URLs and verification results.
