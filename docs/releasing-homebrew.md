# goplaces Homebrew Release Playbook

This is the required `verified-hashes-v1` Formula handoff contract for a published, notarized goplaces release. Run `scripts/release-local homebrew vX.Y.Z` under the serialized release gate before release closeout advances `main`. The command targets `Formula/goplaces.rb`; local release preparation must not generate a Cask or publish Homebrew metadata.

## Frozen Tap Trust Anchor

- Repository: `openclaw/homebrew-tap`.
- Pinned base commit: `104616d9828cf28202bccff19c0738f179c2a3f8`.
- Workflow: `.github/workflows/update-formula.yml`.
- Workflow numeric ID: `220664022`.
- Updater: `.github/scripts/update_formula.py`.
- Required updater marker: `# verified-hashes-v1`.

This base includes the [Formula migration](https://github.com/openclaw/homebrew-tap/pull/56) and the [literal-URL updater fix](https://github.com/openclaw/homebrew-tap/pull/57). Verified updates must retain literal release URLs so Homebrew can infer the version without an explicit version declaration.

The protected default branch, workflow bytes, updater bytes (including `.github/scripts/formula_text.py` at the pinned commit), and marker must match this pinned contract before dispatch. A newer tap commit is not implicitly trusted.

## Required Handoff

Only begin after the GitHub release is published and the newest protected-main Apple-silicon and Intel proofs accept the exact release assets.

1. Download the published archives twice into independent temporary directories. Verify both copies against the frozen numeric release record, then derive handoff hashes only from the second verified copy.
2. Recheck the goplaces signed tag object, peeled commit, protected `main`, release ID, asset IDs, sizes, digests, and newest verifier run.
3. Dispatch the pinned tap workflow from protected current default `main` with GitHub API version `2026-03-10`. Supply `formula=goplaces`, the release tag, source repository, explicit artifact template, all four platform hashes, source tag object, source tag commit, and a unique request ID.
4. Require the live tap workflow’s numeric ID to remain exactly `220664022`. Require the run record’s canonical path to equal `.github/workflows/update-formula.yml`; pin the protected tap branch and head SHA separately. Snapshot existing run IDs, consume the response’s numeric `workflow_run_id`, reject any pre-existing or concurrent substitution, watch that exact run, and recheck the same canonical path after it completes.
5. Require the workflow head SHA to equal protected current tap default, and require exactly one new tap commit. That commit must be the direct child of the pinned base and carry the exact updater-defined provenance trailers for the source repository, tag object, tag commit, and request ID. The four verified hashes remain bound by the dispatch record and the exact Formula bytes checked next. An already-current Formula still receives one provenance commit with an unchanged tree; otherwise only `Formula/goplaces.rb` may change.
6. Read `Formula/goplaces.rb` from that exact tap commit, not from a moving branch. Require the exact version, four release URLs, and four verified hashes. The tap must not rebuild, resign, repackage, mirror, or substitute release assets.
7. Install from a clean checkout pinned to that exact tap commit. Installed binary bytes must equal the corresponding verified release archive member. Verify architecture, reported version, signing identity, Team ID, canonical designated requirement, hardened runtime, secure timestamp, and online notarization.
8. Run the package test, then recheck the goplaces tag refs, source default branch, tap base, tap commit, workflow/updater bytes, and exact live tap default-branch head as the final external closeout action. Any movement fails closed.

The handoff must preserve `com.apple.quarantine`. Neither the tap nor its package definition may remove it.

Each gated attempt persists mode-`0400` dispatch intent, bound-run, tap-result, install-intent, install-started, and completion records under the tag-specific release state directory. A restart resumes only the next proven phase: it reconciles an unseen dispatch before considering a new POST, accepts only the exact direct-child tap commit, never reinstalls from a completion record, and re-verifies an already-started install before closeout.

An unbound intent with no exact run after the bounded, fully paginated reconciliation window fails closed and sends no second dispatch. Keep the serialized gate held and preserve the state. Do not delete the intent merely because the API is empty; a manual reset is allowed only after an independent review proves the POST never occurred and records that proof. Otherwise leave the intent intact and escalate the release as blocked.

## Installation and Migration

The retired `Casks/goplaces.rb` is absent. Install the Formula with:

```bash
brew install openclaw/tap/goplaces
```

For an existing Cask installation, remove it before installing the Formula:

```bash
brew uninstall --cask goplaces
brew install openclaw/tap/goplaces
```

## Handoff After Release Closeout

The producer currently requires the release tag commit to equal protected current `main`, and its draft-to-published identity comparison still includes GitHub's changing `browser_download_url`. The v0.4.11 publication recovery recorded both limitations before this Formula migration. Do not move the tag, overwrite frozen release records, republish assets, or claim that the producer command passed when it did not.

For an already-published release such as v0.4.11, an equivalent serialized handoff must retain the checks above, with these explicit bindings:

- Freeze current protected source `main` independently from the original signed release commit; verify raw ancestry and that the release verifier workflow, signer policy, and verification scripts are unchanged since the successful published-asset proof.
- Revalidate the newest successful published-asset run at its original protected-main SHA, both native proof markers, and the exact frozen numeric asset inventory. Validate canonical URLs for each state, allowing only the documented draft-to-tag URL transition when comparing the original draft with the published record.
- Download and verify all published assets twice, derive all four handoff hashes from the second copy, then dispatch the pinned updater once with a unique request ID and bind the returned numeric run ID. Preserve read-only intent, run, result, installation, and completion receipts beside the original release state.
- Verify one direct-child provenance commit, exact Formula bytes, an install from that commit, binary equality, package test, signature and notarization, and final unchanged source/tag/tap identities. A missing or ambiguous dispatch response requires reconciliation, never a blind retry.

This recovery is a Homebrew handoff only. The original Apple-silicon and Intel proofs remain bound to their original release commit; they are not represented as fresh CI runs on the later documentation commit.
