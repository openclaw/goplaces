# Releasing

v0.4.5 and later use a serialized, local, draft-first release flow for notarized macOS binaries. Tag CI performs credential-free validation only; it never publishes artifacts. Local preparation does not authorize a commit, tag, signing operation, notarization upload, GitHub mutation, or Homebrew mutation. Those steps wait for the explicit serialized gate.

## Trust Contract

- Release only from a clean checkout of protected, current default-branch `main`. Fetch first, require the live branch endpoint to report `protected: true`, and require its commit, fetched `origin/main`, local `HEAD`, and the release commit to be identical. Every security-relevant status check must use exact `git status --porcelain --untracked-files=all` semantics.
- Before any local ancestry decision, run Git with neutralized configuration and `GIT_NO_REPLACE_OBJECTS=1`, resolve `info/grafts` through the neutral wrapper with `git rev-parse --git-path info/grafts`, reject that file if it exists, and reject every ref enumerated under `refs/replace/`. `GIT_NO_REPLACE_OBJECTS=1` does not disable legacy graft files by itself.
- The release tag is signed and annotated, exists on the official origin, and resolves to the exact protected-`main` commit. Its signer must match the repository-pinned `.github/release-allowed-signers` policy.
- Official Darwin artifacts are built only from a fresh official-remote checkout pinned to that verified tag object and commit, with Git configuration neutralized and cleanliness rechecked. The maintainer checkout is never an official build input because index flags can conceal modified source.
- The official macOS code-signing identifier is `org.openclaw.goplaces`.
- The only accepted authority is `Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)`, with Team ID `FWJYW4S8P8`.
- The canonical designated requirement is:

  ```text
  identifier "org.openclaw.goplaces" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = FWJYW4S8P8
  ```

- Ordinary source builds, tests, snapshots, and cross-platform builds are credential-free. Signing is local-only through the managed release keychain exposed by `release-mac-app` / `codesign-run`; repository scripts never discover or unlock keychains themselves.
- Each Darwin binary is thin for its advertised architecture, signed with the hardened runtime and secure timestamp, and notarized. Notarization submits an ephemeral ZIP with `notarytool --no-s3-acceleration --wait`; that ZIP is deleted and never published.
- Notarization is an online gate. A release cannot be prepared offline and later represented as notarized.
- The repository verifier is the release policy boundary. It validates the exact identity, Team ID, designated requirement, runtime, timestamp, architecture, version, and online notarization state. Raw system-policy assessment, policy-check, and ticket-stapling CLI invocations are forbidden throughout producer, verifier, workflow, and release paths.
- Tag CI has read-only contents access, runs release-contract tests plus a credential-free GoReleaser snapshot, and cannot upload or publish unsigned Darwin artifacts.

## Prepare Locally

Keep `CHANGELOG.md` at `## X.Y.Z - Unreleased` throughout local preparation. Its section is the only release-note source; release commands read it from the protected commit or fresh tagged checkout, never from mutable maintainer working-tree bytes.

Run the full local proof set before requesting either serialized gate:

- all tests, race tests where supported, coverage, and `go vet`;
- pinned source and built-binary `govulncheck`;
- actionlint and shellcheck;
- release producer, verifier, dispatch, hostile-input, and publication mocks;
- two isolated credential-free builds with matching non-Darwin bytes;
- formatting and clean-diff checks;
- autoreview to no accepted or actionable findings.

Run `scripts/release-local --check` for the aggregated preflight when that command is present. It must reject ambient Go build controls, the wrong native Go version, a dirty or stale checkout, a non-default branch, and any mismatch with current protected `main`. The check builds pinned govulncheck v1.5.0 with the pinned Go 1.26.5 producer into its private audit directory, verifies the reviewed module checksum, then disables Go module resolution while querying the exact official vulnerability database URL. It never trusts a user-level `go/bin` lookup.

For a gated pilot or draft, copy `.mac-release.env.example` to the ignored `.mac-release.env`, keep mode `0400` or `0600`, and set the two direct runtime locators shown there: `MAC_RELEASE_CODESIGN_KEYCHAIN` and exported `NOTARYTOOL_KEYCHAIN_PROFILE`. The file is strictly parsed and frozen before `release-mac-app` reads it. Package-secret and 1Password lookup fields are rejected in this lane so the helper and producer can execute with pinned, system-only tool paths. `scripts/release-local` also pins the reviewed SHA-256 of both the external `mac-release` entrypoint and its library before either can enter the secret-bearing process; any helper update requires an explicit local review and pin update.

After the signing/notarization gate, `scripts/release-local pilot vX.Y.Z` may exercise the local producer against a tagless snapshot. A pilot may contact Apple because notarization is inherently online, but it creates no tag or GitHub release.

## Tag and Create the Draft

These are public mutations and require the serialized public gate.

1. Replace `Unreleased` with the actual release date, land that exact commit on protected `main`, and rerun the full preflight.
2. Create and push a signed annotated `vX.Y.Z` tag. Re-fetch the remote tag and prove its object, peeled commit, and allowed signer before building.
3. Run `scripts/release-local draft vX.Y.Z`. The command must use `release-mac-app` / `codesign-run`, rebuild from a fresh official-remote clone pinned to the verified tag, create a GitHub draft only, and bind it to the already-pushed exact-main tag.
4. Require exactly seven release assets: Darwin amd64 and arm64 archives, Linux amd64 and arm64 archives, Windows amd64 and arm64 archives, and `goplaces_checksums.txt`. Unsigned, unnotarized, universal, mislabeled, missing, duplicate, or extra Darwin content fails closed.
5. Require the draft notes to equal the tagged changelog section. Resolve the draft by exact numeric REST identity, never by a mutable “latest” lookup.

## Verify the Draft

Run `scripts/release-local verify-draft vX.Y.Z` only after the draft inventory is frozen.

The dispatcher uses GitHub API version `2026-03-10` and dispatches `.github/workflows/release-assets.yml` from the protected current default branch. It requires the live workflow’s numeric ID to remain exactly `309911276` and the run record’s canonical path to equal `.github/workflows/release-assets.yml`; the protected branch and head SHA are pinned separately. It snapshots existing run IDs, consumes the dispatch response’s numeric `workflow_run_id`, rejects a pre-existing or substituted run, watches that exact ID, and then requires newest-proof selection to return the same run ID.

The native verifier runs independently on Apple silicon and Intel. Each job:

- obtains verifier code from protected current default `main` and requires it to equal the workflow SHA;
- treats the signed release tag as source data, not executable verifier policy;
- re-resolves the draft by its exact numeric release ID and downloads the exact numeric asset manifest;
- exposes a GitHub token only to the asset-download step, then proves the token is absent before verification or candidate execution;
- checks all six binaries’ build provenance and the frozen checksum manifest;
- rebuilds credential-free targets from the exact tag and requires reproducible non-Darwin bytes;
- performs static archive, signature, identity, notarization, architecture, version, and designated-requirement checks before executing the native candidate in an isolated environment;
- emits proof bound to the workflow, run, tag object, tag commit, draft identity, asset identities, and protected-main SHA.

The accepted proof is the newest otherwise-relevant successful run, ordered by creation time and numeric ID before exact identity checks. Both native jobs and both exact proof markers are mandatory. Recheck the remote tag object and peeled commit after the verifier completes.

## Publish

Run `scripts/release-local publish vX.Y.Z` only while holding the serialized public gate.

Publication freezes the numeric release and asset record, requires the newest accepted two-architecture proof, verifies release notes against the tagged changelog, and performs numeric REST GET/PATCH/GET operations against the same release ID. Recheck the signed tag object, peeled commit, protected-main commit, asset record, and workflow path before publication and again after the published record is read back. Any movement or same-name asset replacement aborts the release.

After publication:

- verify every public archive and checksum against the frozen release record;
- verify `go install github.com/steipete/goplaces/cmd/goplaces@vX.Y.Z` reports `X.Y.Z`, then retry `@latest` after the module proxy catches up;
- complete the Homebrew handoff only if the separate gate in [releasing-homebrew.md](releasing-homebrew.md) is unblocked;
- reopen the next patch section as `Unreleased`, commit that closeout separately, pull with `--ff-only`, and finish on clean synchronized `main`.

## Homebrew Status

The pinned `verified-hashes-v1` tap handoff is currently blocked for goplaces. Do not run or claim Homebrew handoff proof until [the documented blocker](releasing-homebrew.md#current-blocker) is resolved under its own serialized gate. Until then, public installation text remains the already-published Cask command.
