# goplaces Homebrew Release Playbook

This is the required `verified-hashes-v1` handoff contract for a published, notarized goplaces release. It is not currently runnable; see [Current Blocker](#current-blocker). Do not mutate `openclaw/homebrew-tap` or change public install instructions until that blocker is resolved under a serialized gate.

## Frozen Tap Trust Anchor

- Repository: `openclaw/homebrew-tap`.
- Pinned base commit: `45b93a0b3de27e46b636a0cef819fb1ecef25bcd`.
- Workflow: `.github/workflows/update-formula.yml`.
- Workflow numeric ID: `220664022`.
- Updater: `.github/scripts/update_formula.py`.
- Required updater marker: `# verified-hashes-v1`.

The protected default branch, workflow bytes, updater bytes, and marker must match this pinned contract before dispatch. A newer tap commit is not implicitly trusted.

## Required Handoff

Only begin after the GitHub release is published and the newest protected-main Apple-silicon and Intel proofs accept the exact release assets.

1. Download the published archives twice into independent temporary directories. Verify both copies against the frozen numeric release record, then derive handoff hashes only from the second verified copy.
2. Recheck the goplaces signed tag object, peeled commit, protected `main`, release ID, asset IDs, sizes, digests, and newest verifier run.
3. Dispatch the pinned tap workflow from protected current default `main` with GitHub API version `2026-03-10`. Supply `formula=goplaces`, the release tag, source repository, explicit artifact template, all four platform hashes, source tag object, source tag commit, and a unique request ID.
4. Require the live tap workflow’s numeric ID to remain exactly `220664022`. Require the run record’s canonical path to equal `.github/workflows/update-formula.yml`; pin the protected tap branch and head SHA separately. Snapshot existing run IDs, consume the response’s numeric `workflow_run_id`, reject any pre-existing or concurrent substitution, watch that exact run, and recheck the same canonical path after it completes.
5. Require the workflow head SHA to equal protected current tap default, and require exactly one new tap commit. That commit must be the direct child of the pinned base and carry the exact updater-defined provenance trailers for the source repository, tag object, tag commit, and request ID. The four verified hashes remain bound by the dispatch record and the exact Formula bytes checked next.
6. Read `Formula/goplaces.rb` from that exact tap commit, not from a moving branch. Require the exact version, four release URLs, and four verified hashes. The tap must not rebuild, resign, repackage, mirror, or substitute release assets.
7. Install from a clean checkout pinned to that exact tap commit. Installed binary bytes must equal the corresponding verified release archive member. Verify architecture, reported version, signing identity, Team ID, canonical designated requirement, hardened runtime, secure timestamp, and online notarization.
8. Run the package test, then recheck the goplaces tag refs, source default branch, tap base, tap commit, workflow/updater bytes, and exact live tap default-branch head as the final external closeout action. Any movement fails closed.

The handoff must preserve `com.apple.quarantine`. Neither the tap nor its package definition may remove it.

Each gated attempt persists mode-`0400` dispatch intent, bound-run, tap-result, install-intent, install-started, and completion records under the tag-specific release state directory. A restart resumes only the next proven phase: it reconciles an unseen dispatch before considering a new POST, accepts only the exact direct-child tap commit, never reinstalls from a completion record, and re-verifies an already-started install before closeout.

An unbound intent with no exact run after the bounded, fully paginated reconciliation window fails closed and sends no second dispatch. Keep the serialized gate held and preserve the state. Do not delete the intent merely because the API is empty; a manual reset is allowed only after an independent review proves the POST never occurred and records that proof. Otherwise leave the intent intact and escalate the release as blocked.

## Current Blocker

At pinned tap commit `45b93a0b3de27e46b636a0cef819fb1ecef25bcd`, `Formula/goplaces.rb` does not exist. The generic `verified-hashes-v1` updater accepts Formula input and therefore cannot update the existing `Casks/goplaces.rb`.

The current published Cask also strips `com.apple.quarantine`. Removing that generator behavior from local goplaces release preparation is necessary, but it does not rewrite the already-published tap entry and does not make the generic Formula handoff work.

Therefore:

- do not dispatch the tap workflow for goplaces;
- do not claim exact-run, exact-commit, install-byte, signature, or notarization proof through Homebrew;
- do not change README or website installation text away from the currently published Cask command;
- resolve the tap side under separate review. Either the compatible Formula/Cask change must occur within the one authorized direct-child handoff commit, or the reviewed tap change must establish a new pinned base and updated trust anchor before dispatch. Never insert a pre-dispatch tap commit while continuing to claim the old pinned base.

After the blocker is resolved and the full handoff passes, public install text can change to:

```bash
brew install openclaw/tap/goplaces
```

Until then, the existing published-install documentation remains:

```bash
brew install --cask openclaw/tap/goplaces
```
