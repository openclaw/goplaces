#!/bin/bash -p
# shellcheck disable=SC2016,SC2071
set -euo pipefail
unset BASH_ENV ENV CDPATH

die() {
  echo "release verifier check: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 TAG EXPECTED_TAG_OBJECT EXPECTED_TAG_COMMIT RELEASE_ID EXPECTED_MAIN_SHA EXPECTED_RUN_ID" >&2
  exit 2
}

[[ $# -eq 6 ]] || usage

tag="$1"
expected_tag_object="$2"
expected_tag_commit="$3"
release_id="$4"
expected_main="$5"
expected_run_id="$6"
dispatch_nonce="${EXPECTED_DISPATCH_NONCE:-}"
state="${EXPECTED_RELEASE_STATE:-draft}"
repository="openclaw/goplaces"
api_url="${GITHUB_API_URL:-https://api.github.com}"
api_version="2026-03-10"
testing="${GOPLACES_RELEASE_TESTING:-0}"
curl_bin=""
unzip_bin=""
jq_source=""
jq_bin=""
jq_sha256=""
jq_identity=""
script_root="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

canonical_executable() {
  local candidate="$1"
  local label="$2"
  local directory
  local canonical
  local target
  local count=0

  [[ "$candidate" == /* ]] || die "$label path must be absolute"
  canonical="$candidate"
  while [[ -L "$canonical" ]]; do
    count=$((count + 1))
    [[ "$count" -le 8 ]] || die "$label symlink chain is too deep"
    target="$(/usr/bin/readlink "$canonical")" || die "could not resolve $label symlink"
    if [[ "$target" == /* ]]; then
      canonical="$target"
    else
      directory="$(cd -P "$(/usr/bin/dirname "$canonical")" && pwd -P)" || die "could not resolve $label directory"
      canonical="$directory/$target"
    fi
  done
  directory="$(cd -P "$(/usr/bin/dirname "$canonical")" && pwd -P)" || die "could not resolve $label directory"
  canonical="$directory/$(/usr/bin/basename "$canonical")"
  [[ -f "$canonical" && ! -L "$canonical" && -x "$canonical" ]] || die "$label must be a regular nonsymlink executable"
  printf '%s\n' "$canonical"
}

sha256_file() {
  local digest
  digest="$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" || die "could not hash $2"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || die "$2 SHA-256 is malformed"
  printf '%s\n' "$digest"
}

file_identity() {
  local identity
  identity="$(/usr/bin/stat -f '%d:%i' "$1")" || die "could not inspect $2 identity"
  [[ "$identity" =~ ^[0-9]+:[0-9]+$ ]] || die "$2 identity is malformed"
  printf '%s\n' "$identity"
}

recheck_jq() {
  local canonical
  canonical="$(canonical_executable "$jq_bin" "frozen jq")"
  [[ "$canonical" == "$jq_bin" ]] || die "frozen jq path changed"
  [[ "$(sha256_file "$jq_bin" "frozen jq")" == "$jq_sha256" ]] || die "frozen jq bytes changed"
  [[ "$(file_identity "$jq_bin" "frozen jq")" == "$jq_identity" ]] || die "frozen jq identity changed"
}

jq_run() {
  local result
  recheck_jq
  if /usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/jq-home" TMPDIR="$scratch" LC_ALL=C \
    "$jq_bin" "$@"; then
    result=0
  else
    result=$?
  fi
  recheck_jq
  return "$result"
}

curl_run() {
  if [[ "$testing" == 0 ]]; then
    /usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/curl-home" TMPDIR="$scratch" LC_ALL=C \
      "$curl_bin" "$@"
  else
    "$curl_bin" "$@"
  fi
}

unzip_run() {
  /usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/unzip-home" TMPDIR="$scratch" LC_ALL=C \
    "$unzip_bin" "$@"
}

verify_tag_run() {
  local result
  recheck_jq
  if [[ "$testing" == 0 ]]; then
    if /usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/tag-home" TMPDIR="$scratch" LC_ALL=C \
      JQ_BIN="$jq_bin" /bin/bash -p "$verify_tag_bin" "$@"; then
      result=0
    else
      result=$?
    fi
  elif /bin/bash -p "$verify_tag_bin" "$@"; then
    result=0
  else
    result=$?
  fi
  recheck_jq
  return "$result"
}

case "$testing" in
  0)
    [[ -z "${CURL_BIN+x}" && -z "${UNZIP_BIN+x}" && -z "${JQ_BIN+x}" && \
      -z "${VERIFY_TAG_BIN+x}" && -z "${ALLOW_TEST_API_URL+x}" ]] ||
      die "tool and API overrides require GOPLACES_RELEASE_TESTING=1"
    curl_bin=/usr/bin/curl
    unzip_bin=/usr/bin/unzip
    case "$(/usr/bin/uname -m)" in
      arm64) jq_source=/opt/homebrew/opt/jq/bin/jq ;;
      x86_64) jq_source=/usr/local/opt/jq/bin/jq ;;
      *) die "unsupported macOS architecture for jq" ;;
    esac
    verify_tag_bin="$script_root/scripts/verify-release-tag.sh"
    ;;
  1)
    curl_bin="${CURL_BIN:-}"
    unzip_bin="${UNZIP_BIN:-}"
    jq_source="${JQ_BIN:-}"
    verify_tag_bin="${VERIFY_TAG_BIN:-}"
    ;;
  *) die "GOPLACES_RELEASE_TESTING must be 0 or 1" ;;
esac

safe_json_id() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || return 1
  if (( ${#value} < 16 )); then
    return 0
  fi
  (( ${#value} == 16 )) && [[ "$value" < 9007199254740992 ]]
}

[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag"
for sha in "$expected_tag_object" "$expected_tag_commit" "$expected_main"; do
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "expected object and commit identities must be lowercase 40-character SHAs"
done
[[ "$expected_tag_commit" == "$expected_main" ]] || die "tag commit must equal protected current default"
safe_json_id "$release_id" || die "invalid release ID"
safe_json_id "$expected_run_id" || die "invalid expected run ID"
[[ "$dispatch_nonce" =~ ^[0-9a-f]{64}$ ]] || die "EXPECTED_DISPATCH_NONCE is required"
[[ "$state" == draft || "$state" == published ]] || die "invalid release state"
[[ "$api_url" == https://api.github.com || ("$testing" == 1 && "${ALLOW_TEST_API_URL:-0}" == 1) ]] || die "unexpected GitHub API URL"
[[ -n "${GH_TOKEN:-}" && "$GH_TOKEN" =~ ^[A-Za-z0-9_]+$ ]] || die "GH_TOKEN is required and must contain safe characters"
proof_token="$GH_TOKEN"
unset GH_TOKEN GITHUB_TOKEN
[[ "$curl_bin" == /* && -f "$curl_bin" && ! -L "$curl_bin" && -x "$curl_bin" ]] || die "curl must be an absolute regular nonsymlink executable"
[[ "$unzip_bin" == /* && -f "$unzip_bin" && ! -L "$unzip_bin" && -x "$unzip_bin" ]] || die "unzip must be an absolute regular nonsymlink executable"
[[ "$jq_source" == /* ]] || die "jq must be an absolute executable"
[[ -x "$verify_tag_bin" ]] || die "tag verifier is not executable"

scratch="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/goplaces-proof.XXXXXX")"
scratch="$(cd "$scratch" && pwd -P)"
auth_config="$scratch/curl-auth.conf"
trap '/bin/rm -rf "$scratch"' EXIT
umask 077
/bin/mkdir "$scratch/jq-home"
/bin/mkdir "$scratch/curl-home"
/bin/mkdir "$scratch/unzip-home"
/bin/mkdir "$scratch/tag-home"
/bin/chmod 700 "$scratch/jq-home" "$scratch/curl-home" "$scratch/unzip-home" "$scratch/tag-home"
jq_source="$(canonical_executable "$jq_source" "jq")"
if [[ "$testing" == 0 ]]; then
  case "$(/usr/bin/uname -m):$jq_source" in
    arm64:/opt/homebrew/Cellar/jq/1.8.2/bin/jq|x86_64:/usr/local/Cellar/jq/1.8.2/bin/jq) ;;
    *) die "jq is not the reviewed 1.8.2 Cellar executable" ;;
  esac
fi
jq_source_sha256="$(sha256_file "$jq_source" "jq source")"
jq_source_identity="$(file_identity "$jq_source" "jq source")"
jq_bin="$scratch/jq"
/bin/cp "$jq_source" "$jq_bin" || die "could not freeze jq"
/bin/chmod 500 "$jq_bin"
[[ "$(sha256_file "$jq_source" "jq source")" == "$jq_source_sha256" ]] || die "jq source bytes changed while freezing"
[[ "$(file_identity "$jq_source" "jq source")" == "$jq_source_identity" ]] || die "jq source identity changed while freezing"
jq_sha256="$(sha256_file "$jq_bin" "frozen jq")"
[[ "$jq_sha256" == "$jq_source_sha256" ]] || die "frozen jq bytes differ from source"
jq_identity="$(file_identity "$jq_bin" "frozen jq")"
jq_run --version > "$scratch/jq-version.txt"
[[ "$(/bin/cat "$scratch/jq-version.txt")" == jq-1.8.2 ]] || die "jq must be version 1.8.2"
printf 'header = "Authorization: Bearer %s"\n' "$proof_token" > "$auth_config"
unset proof_token

api_get() {
  local url="$1"
  local output="$2"
  local accept="${3:-application/vnd.github+json}"
  local status
  status="$(curl_run --disable --config "$auth_config" --silent --show-error --retry 3 \
    --header "Accept: $accept" \
    --header "X-GitHub-Api-Version: $api_version" \
    --output "$output" --write-out '%{http_code}' "$url")" || die "GitHub API request failed"
  [[ "$status" == 200 ]] || die "GitHub API request returned HTTP $status"
}

download_logs() {
  local url="$1"
  local output="$2"
  local headers="$scratch/logs.headers"
  local body="$scratch/logs.body"
  local status redirect_count redirect_url
  status="$(curl_run --disable --config "$auth_config" --silent --show-error --retry 3 \
    --header 'Accept: application/vnd.github+json' \
    --header "X-GitHub-Api-Version: $api_version" \
    --dump-header "$headers" --output "$body" --write-out '%{http_code}' "$url")" ||
    die "verifier log request failed"
  if [[ "$status" == 200 ]]; then
    /bin/mv "$body" "$output"
    return
  fi
  [[ "$status" == 302 ]] || die "verifier log API returned unexpected HTTP $status"
  redirect_count="$(/usr/bin/awk 'BEGIN {IGNORECASE=1} /^Location:[[:space:]]/ {count++} END {print count + 0}' "$headers")"
  [[ "$redirect_count" -eq 1 ]] || die "verifier log API returned an ambiguous redirect"
  redirect_url="$(/usr/bin/awk 'BEGIN {IGNORECASE=1} /^Location:[[:space:]]/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print}' "$headers")"
  case "$redirect_url" in
    https://*.blob.core.windows.net/*|https://results-receiver.actions.githubusercontent.com/*) ;;
    *) die "verifier log API redirected to an unapproved HTTPS host" ;;
  esac
  status="$(curl_run --disable --silent --show-error --retry 3 --proto '=https' \
    --output "$output" --write-out '%{http_code}' "$redirect_url")" || die "verifier log redirect fetch failed"
  [[ "$status" == 200 ]] || die "verifier log redirect returned HTTP $status"
}

repo_json="$scratch/repo.json"
api_get "$api_url/repos/$repository" "$repo_json"
default_branch="$(jq_run -r '.default_branch | select(type == "string")' "$repo_json")"
[[ "$default_branch" =~ ^[A-Za-z0-9._/-]+$ ]] || die "repository default branch is invalid"

branch_json="$scratch/branch.json"
api_get "$api_url/repos/$repository/branches/$default_branch" "$branch_json"
jq_run -e --arg branch "$default_branch" --arg sha "$expected_main" '.name == $branch and .protected == true and .commit.sha == $sha' "$branch_json" >/dev/null || die "default branch is not protected at expected main"

workflow_json="$scratch/workflow.json"
api_get "$api_url/repos/$repository/actions/workflows/release-assets.yml" "$workflow_json"
workflow_id="$(jq_run -r '.id | select(type == "number" and . > 0 and . <= 9007199254740991 and floor == .)' "$workflow_json")"
safe_json_id "$workflow_id" || die "workflow ID is invalid"
[[ "$workflow_id" == 309911276 ]] || die "workflow numeric identity is not pinned"
jq_run -e '.name == "release-assets" and .path == ".github/workflows/release-assets.yml" and .state == "active"' "$workflow_json" >/dev/null || die "workflow identity is invalid"

release_json="$scratch/release.json"
api_get "$api_url/repos/$repository/releases/$release_id" "$release_json"
if [[ "$state" == draft ]]; then expected_draft=true; else expected_draft=false; fi
jq_run -e --arg tag "$tag" --argjson id "$release_id" --argjson draft "$expected_draft" '
  .id == $id and .tag_name == $tag and .draft == $draft and .prerelease == false and
  (.assets | type == "array" and length == 7) and all(.assets[]; (.updated_at | type == "string"))
' "$release_json" >/dev/null || die "numeric release identity or state is invalid"
newest_asset_at="$(jq_run -r '[.assets[].updated_at] | max' "$release_json")"

runs_json="$scratch/runs.json"
printf '{"workflow_runs":[]}\n' > "$runs_json"
page=1
while :; do
  runs_page="$scratch/runs-page-$page.json"
  api_get "$api_url/repos/$repository/actions/workflows/$workflow_id/runs?event=workflow_dispatch&branch=$default_branch&status=success&per_page=100&page=$page" "$runs_page"
  jq_run -e '.workflow_runs | type == "array"' "$runs_page" >/dev/null || die "workflow-runs page is invalid"
  page_count="$(jq_run '.workflow_runs | length' "$runs_page")"
  merged_runs="$scratch/runs-merged.json"
  jq_run -s '{workflow_runs:(.[0].workflow_runs + .[1].workflow_runs)}' "$runs_json" "$runs_page" > "$merged_runs"
  /bin/mv "$merged_runs" "$runs_json"
  [[ "$page_count" -lt 100 ]] && break
  page=$((page + 1))
  [[ "$page" -le 20 ]] || die "workflow-run pagination exceeded safety limit"
done
jq_run -e '
  (.workflow_runs | all(.[]; (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .))) and
  (([.workflow_runs[].id] | unique | length) == (.workflow_runs | length))
' "$runs_json" >/dev/null || die "workflow-run pages contain invalid or duplicate run IDs"
expected_title="Verify $tag $state release $release_id nonce $dispatch_nonce"
[[ ${#expected_title} -le 160 ]] || die "verifier run title is unexpectedly long"
selected="$scratch/selected.json"
jq_run \
  --arg branch "$default_branch" \
  --arg title "$expected_title" '
    [.workflow_runs[] | select(
      .event == "workflow_dispatch" and
      .head_branch == $branch and
      .display_title == $title and
      .status == "completed" and
      .conclusion == "success"
    )] | sort_by(.created_at, .id) | reverse | .[0] // empty
  ' "$runs_json" > "$selected"
[[ -s "$selected" ]] || die "no successful verifier run matches the release identity"
selected_id="$(jq_run -r '.id | select(type == "number" and . > 0 and . <= 9007199254740991 and floor == .)' "$selected")"
safe_json_id "$selected_id" || die "selected run ID is invalid"
[[ "$selected_id" == "$expected_run_id" ]] || die "dispatched run is not the newest otherwise-relevant proof"
jq_run -e \
  --argjson id "$selected_id" \
  --argjson workflow_id "$workflow_id" \
  --arg sha "$expected_main" '
    .id == $id and .workflow_id == $workflow_id and
    .path == ".github/workflows/release-assets.yml" and
    .head_sha == $sha and .run_attempt == 1 and
    .repository.full_name == "openclaw/goplaces"
  ' "$selected" >/dev/null || die "newest verifier proof is bound to the wrong protected code"
run_created_at="$(jq_run -r '.created_at' "$selected")"
[[ "$run_created_at" > "$newest_asset_at" ]] || die "verifier proof is not newer than every release asset"

exact_run="$scratch/run.json"
api_get "$api_url/repos/$repository/actions/runs/$selected_id" "$exact_run"
cmp_selected="$scratch/run-selected-projection.json"
cmp_exact="$scratch/run-exact-projection.json"
projection='{id,workflow_id,path,event,head_branch,head_sha,display_title,status,conclusion,created_at,run_attempt,repository:{full_name:.repository.full_name}}'
jq_run -S "$projection" "$selected" > "$cmp_selected"
jq_run -S "$projection" "$exact_run" > "$cmp_exact"
/usr/bin/cmp -s "$cmp_selected" "$cmp_exact" || die "exact run record differs from newest-run record"

jobs_json="$scratch/jobs.json"
api_get "$api_url/repos/$repository/actions/runs/$selected_id/jobs?per_page=100" "$jobs_json"
jq_run -e '
  (.jobs | type == "array" and length == 2) and
  ([.jobs[].name] | sort == ["verify-arm64","verify-x86_64"]) and
  all(.jobs[]; .status == "completed" and .conclusion == "success" and .run_attempt == 1)
' "$jobs_json" >/dev/null || die "both exact native verifier jobs are required"

logs_zip="$scratch/logs.zip"
download_logs "$api_url/repos/$repository/actions/runs/$selected_id/logs" "$logs_zip"
/bin/rm -f "$auth_config"
logs_txt="$scratch/logs.txt"
unzip_run -p "$logs_zip" > "$logs_txt" || die "could not read verifier logs"
proof_inventory_digest=""
for proof_arch in arm64 x86_64; do
  marker_prefix="GOPLACES_RELEASE_PROOF_V1 arch=$proof_arch run_id=$selected_id tag=$tag tag_object=$expected_tag_object tag_commit=$expected_tag_commit release_id=$release_id default_sha=$expected_main inventory_sha256="
  [[ "$(/usr/bin/grep -Fc "$marker_prefix" "$logs_txt")" -eq 1 ]] || die "missing or duplicate $proof_arch proof marker"
  /usr/bin/grep -E "${marker_prefix}[0-9a-f]{64}$" "$logs_txt" >/dev/null || die "$proof_arch proof marker has an invalid inventory digest"
  marker_line="$(/usr/bin/grep -F "$marker_prefix" "$logs_txt")"
  current_digest="${marker_line##*inventory_sha256=}"
  [[ "$current_digest" =~ ^[0-9a-f]{64}$ ]] || die "$proof_arch inventory digest is invalid"
  if [[ -z "$proof_inventory_digest" ]]; then
    proof_inventory_digest="$current_digest"
  else
    [[ "$current_digest" == "$proof_inventory_digest" ]] || die "native proof markers bind different inventories"
  fi
done

tag_json="$scratch/tag-final.json"
verify_tag_run "$tag" "$expected_main" "$tag_json" >/dev/null
jq_run -e --arg object "$expected_tag_object" --arg commit "$expected_tag_commit" '.object_sha == $object and .commit_sha == $commit' "$tag_json" >/dev/null || die "remote tag moved after verifier proof"

printf '%s\n' "$selected_id"
