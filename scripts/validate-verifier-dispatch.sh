#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2071
set -euo pipefail

die() {
  echo "verifier dispatch validation: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 RUN_JSON WORKFLOW_JSON DEFAULT_BRANCH EXPECTED_SHA TAG RELEASE_ID PREEXISTING_IDS_JSON" >&2
  exit 2
}

[[ $# -eq 7 ]] || usage

run_json="$1"
workflow_json="$2"
default_branch="$3"
expected_sha="$4"
tag="$5"
release_id="$6"
preexisting_ids="$7"
jq_bin="${JQ_BIN:-jq}"
state="${EXPECTED_RELEASE_STATE:-draft}"
tag_commit="${EXPECTED_TAG_COMMIT:-}"
tag_object="${EXPECTED_TAG_OBJECT:-}"
dispatch_nonce="${EXPECTED_DISPATCH_NONCE:-}"

safe_json_id() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1
  if (( ${#value} < 16 )); then
    return 0
  fi
  (( ${#value} == 16 )) && [[ "$value" < 9007199254740992 ]]
}

for input in "$run_json" "$workflow_json" "$preexisting_ids"; do
  [[ -f "$input" && ! -L "$input" ]] || die "input must be a regular file: $input"
done
command -v "$jq_bin" >/dev/null 2>&1 || die "jq is required"
[[ "$default_branch" =~ ^[A-Za-z0-9._/-]+$ && "$default_branch" != */../* ]] || die "invalid default branch"
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]] || die "expected SHA must be a lowercase 40-character commit"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag"
safe_json_id "$release_id" || die "invalid release ID"
[[ "$state" == draft || "$state" == published ]] || die "invalid release state"
[[ "$tag_commit" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_TAG_COMMIT is required"
[[ "$tag_object" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_TAG_OBJECT is required"
[[ "$dispatch_nonce" =~ ^[0-9a-f]{64}$ ]] || die "EXPECTED_DISPATCH_NONCE is required"

workflow_id="$($jq_bin -r '.id | select(type == "number" and . > 0 and . <= 9007199254740991 and floor == .)' "$workflow_json")"
safe_json_id "$workflow_id" || die "workflow has an invalid numeric ID"
[[ "$workflow_id" == 309911276 ]] || die "workflow numeric identity is not pinned"
"$jq_bin" -e '
  .path == ".github/workflows/release-assets.yml" and
  .state == "active" and
  .name == "release-assets"
' "$workflow_json" >/dev/null || die "workflow identity, path, or state is invalid"

"$jq_bin" -e 'type == "array" and all(.[]; type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and ((unique | length) == length)' "$preexisting_ids" >/dev/null || die "preexisting run IDs are invalid"

expected_title="Verify $tag $state release $release_id nonce $dispatch_nonce"
[[ ${#expected_title} -le 160 ]] || die "verifier run title is unexpectedly long"
run_id="$($jq_bin -r '.id | select(type == "number" and . > 0 and . <= 9007199254740991 and floor == .)' "$run_json")"
safe_json_id "$run_id" || die "run has an invalid numeric ID"
if "$jq_bin" -e --argjson id "$run_id" 'index($id) != null' "$preexisting_ids" >/dev/null; then
  die "dispatch returned a preexisting run ID"
fi
safe_json_id "${EXPECTED_RUN_ID:-}" || die "EXPECTED_RUN_ID is required and must be a safe numeric ID"
[[ "$run_id" == "$EXPECTED_RUN_ID" ]] || die "run ID differs from dispatch response"
case "${RECOVERED_DISPATCH:-0}" in
  0)
    [[ -n "${DISPATCH_RESPONSE_JSON:-}" && -f "$DISPATCH_RESPONSE_JSON" && ! -L "$DISPATCH_RESPONSE_JSON" ]] ||
      die "DISPATCH_RESPONSE_JSON must name a regular file"
    "$jq_bin" -e --argjson id "$run_id" '
      (keys | sort) == ["html_url","run_url","workflow_run_id"] and
      .workflow_run_id == $id and
      .run_url == ("https://api.github.com/repos/openclaw/goplaces/actions/runs/" + ($id | tostring)) and
      .html_url == ("https://github.com/openclaw/goplaces/actions/runs/" + ($id | tostring))
    ' "$DISPATCH_RESPONSE_JSON" >/dev/null || die "dispatch response does not bind the exact returned run"
    ;;
  1)
    [[ -z "${DISPATCH_RESPONSE_JSON:-}" ]] || die "recovered dispatch must not claim a lost response record"
    ;;
  *) die "RECOVERED_DISPATCH must be 0 or 1" ;;
esac

"$jq_bin" -e \
  --argjson workflow_id "$workflow_id" \
  --arg branch "$default_branch" \
  --arg sha "$expected_sha" \
  --arg title "$expected_title" \
  --argjson run_id "$run_id" '
    .id == $run_id and
    .workflow_id == $workflow_id and
    .path == ".github/workflows/release-assets.yml" and
    .event == "workflow_dispatch" and
    .run_attempt == 1 and
    .head_branch == $branch and
    .head_sha == $sha and
    .display_title == $title and
    (.status == "queued" or .status == "in_progress" or .status == "completed") and
    (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    .repository.full_name == "openclaw/goplaces" and
    .url == ("https://api.github.com/repos/openclaw/goplaces/actions/runs/" + ($run_id | tostring)) and
    .html_url == ("https://github.com/openclaw/goplaces/actions/runs/" + ($run_id | tostring))
  ' "$run_json" >/dev/null || die "run is not the exact dispatched protected-main verifier"

if [[ "${REQUIRE_SUCCESS:-0}" == 1 ]]; then
  "$jq_bin" -e '.status == "completed" and .conclusion == "success"' "$run_json" >/dev/null || die "run is not successfully completed"
fi

printf '%s\n' "$run_id"
