#!/bin/bash -p
# shellcheck disable=SC2016,SC2071
set -euo pipefail
unset BASH_ENV ENV CDPATH

die() {
  echo "release asset download: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 TAG DEST_DIR RELEASE_ID" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage

tag="$1"
destination="$2"
expected_release_id="$3"
release_state="${RELEASE_STATE:-draft}"
repository="${GITHUB_REPOSITORY:-openclaw/goplaces}"
api_url="${GITHUB_API_URL:-https://api.github.com}"
api_version="2026-03-10"
testing="${GOPLACES_RELEASE_TESTING:-0}"
curl_bin=""
jq_source=""
jq_bin=""
jq_sha256=""
jq_identity=""

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

case "$testing" in
  0)
    [[ -z "${CURL_BIN+x}" && -z "${JQ_BIN+x}" && -z "${ALLOW_TEST_API_URL+x}" ]] ||
      die "tool and API overrides require GOPLACES_RELEASE_TESTING=1"
    curl_bin=/usr/bin/curl
    case "$(/usr/bin/uname -m)" in
      arm64) jq_source=/opt/homebrew/opt/jq/bin/jq ;;
      x86_64) jq_source=/usr/local/opt/jq/bin/jq ;;
      *) die "unsupported macOS architecture for jq" ;;
    esac
    ;;
  1)
    curl_bin="${CURL_BIN:-}"
    jq_source="${JQ_BIN:-}"
    ;;
  *) die "GOPLACES_RELEASE_TESTING must be 0 or 1" ;;
esac

[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag: $tag"
[[ "$release_state" == draft || "$release_state" == published ]] || die "state must be draft or published"
[[ "$repository" == openclaw/goplaces ]] || die "repository must be openclaw/goplaces"
[[ "$api_url" == https://api.github.com || ("$testing" == 1 && "${ALLOW_TEST_API_URL:-0}" == 1) ]] || die "unexpected GitHub API URL"
[[ "$expected_release_id" =~ ^[1-9][0-9]*$ ]] || die "release ID must be a positive integer"
if [[ "${#expected_release_id}" -gt 16 || ("${#expected_release_id}" -eq 16 && "$expected_release_id" > 9007199254740991) ]]; then
  die "release ID exceeds the maximum safe JSON integer"
fi
[[ -n "${GH_TOKEN:-}" ]] || die "GH_TOKEN is required only for this download operation"
[[ "$GH_TOKEN" =~ ^[A-Za-z0-9_]+$ ]] || die "GH_TOKEN contains unsupported characters"
download_token="$GH_TOKEN"
unset GH_TOKEN GITHUB_TOKEN
[[ "$curl_bin" == /* && -f "$curl_bin" && ! -L "$curl_bin" && -x "$curl_bin" ]] || die "curl must be an absolute regular nonsymlink executable"
[[ "$jq_source" == /* ]] || die "jq must be an absolute executable"

[[ ! -e "$destination" && ! -L "$destination" ]] || die "destination already exists"
destination_parent="$(/usr/bin/dirname "$destination")"
[[ -d "$destination_parent" && ! -L "$destination_parent" ]] || die "destination parent must be a real directory"
destination_parent="$(cd "$destination_parent" && pwd -P)"
destination="$destination_parent/$(/usr/bin/basename "$destination")"

scratch="$(/usr/bin/mktemp -d "$destination_parent/.goplaces-download.XXXXXX")"
scratch="$(cd "$scratch" && pwd -P)"
auth_config="$scratch/curl-auth.conf"
cleanup() {
  /bin/rm -rf "$scratch"
}
trap cleanup EXIT
umask 077
/bin/mkdir "$scratch/jq-home"
/bin/mkdir "$scratch/curl-home"
/bin/chmod 700 "$scratch/jq-home" "$scratch/curl-home"
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
printf 'header = "Authorization: Bearer %s"\n' "$download_token" > "$auth_config"
unset download_token

api_get() {
  local url="$1"
  local output="$2"
  local status
  status="$(curl_run \
    --disable \
    --config "$auth_config" \
    --silent --show-error \
    --retry 3 \
    --header 'Accept: application/vnd.github+json' \
    --header "X-GitHub-Api-Version: $api_version" \
    --output "$output" \
    --write-out '%{http_code}' \
    "$url")" || die "GitHub API request failed"
  [[ "$status" == 200 ]] || die "GitHub API request returned HTTP $status"
}

if [[ -n "${EXPECTED_DEFAULT_SHA:-}" ]]; then
  [[ "$EXPECTED_DEFAULT_SHA" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_DEFAULT_SHA must be a lowercase 40-character commit"
  repo_record="$scratch/repository.json"
  api_get "$api_url/repos/$repository" "$repo_record"
  live_default="$(jq_run -r '.default_branch | select(type == "string")' "$repo_record")"
  [[ "$live_default" =~ ^[A-Za-z0-9._-]+$ ]] || die "live default branch is invalid"
  if [[ -n "${EXPECTED_DEFAULT_BRANCH:-}" && "$live_default" != "$EXPECTED_DEFAULT_BRANCH" ]]; then
    die "live default branch differs from workflow default branch"
  fi
  branch_record="$scratch/default-branch.json"
  api_get "$api_url/repos/$repository/branches/$live_default" "$branch_record"
  jq_run -e --arg branch "$live_default" --arg sha "$EXPECTED_DEFAULT_SHA" \
    '.name == $branch and .protected == true and .commit.sha == $sha' "$branch_record" >/dev/null ||
    die "live default branch is not protected at the expected workflow commit"
fi

download_asset() {
  local url="$1"
  local output="$2"
  local request_id="$3"
  local headers="$scratch/asset-response-$request_id.headers"
  local body="$scratch/asset-response-$request_id.body"
  local status
  local redirect_count
  local redirect_url

  status="$(curl_run \
    --disable \
    --config "$auth_config" \
    --silent --show-error \
    --retry 3 \
    --header 'Accept: application/octet-stream' \
    --header "X-GitHub-Api-Version: $api_version" \
    --dump-header "$headers" \
    --output "$body" \
    --write-out '%{http_code}' \
    "$url")" || die "authenticated asset request failed"

  if [[ "$status" == 200 ]]; then
    /bin/mv "$body" "$output"
    return
  fi
  [[ "$status" == 302 ]] || die "asset API returned unexpected HTTP $status"
  redirect_count="$(/usr/bin/awk 'BEGIN {IGNORECASE=1} /^Location:[[:space:]]/ {count++} END {print count + 0}' "$headers")"
  [[ "$redirect_count" -eq 1 ]] || die "asset API returned an ambiguous redirect"
  redirect_url="$(/usr/bin/awk 'BEGIN {IGNORECASE=1} /^Location:[[:space:]]/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print}' "$headers")"
  case "$redirect_url" in
    https://release-assets.githubusercontent.com/*) ;;
    *) die "asset API redirected to an unapproved HTTPS host" ;;
  esac

  # This second request deliberately has no auth config and cannot read
  # ~/.curlrc. The signed CDN URL is the sole authorization mechanism.
  status="$(curl_run \
    --disable \
    --silent --show-error \
    --retry 3 \
    --proto '=https' \
    --output "$output" \
    --write-out '%{http_code}' \
    "$redirect_url")" || die "unauthenticated asset redirect fetch failed"
  [[ "$status" == 200 ]] || die "asset redirect returned HTTP $status"
}

if [[ "$release_state" == draft ]]; then
  state_filter='.draft == true and .prerelease == false'
else
  state_filter='.draft == false and .prerelease == false'
fi

release="$scratch/release.json"
api_get "$api_url/repos/$repository/releases/$expected_release_id" "$release"
jq_run -e --arg tag "$tag" --argjson id "$expected_release_id" \
  ".id == \$id and .tag_name == \$tag and ($state_filter)" "$release" >/dev/null ||
  die "numeric release does not match expected tag and state"

release_id="$(jq_run -r '.id | select(type == "number" and . > 0 and . <= 9007199254740991 and floor == .)' "$release")"
[[ "$release_id" =~ ^[1-9][0-9]*$ ]] || die "release has an invalid numeric ID"
if [[ -n "$expected_release_id" && "$release_id" != "$expected_release_id" ]]; then
  die "release ID does not match expected identity"
fi

version="${tag#v}"
expected_assets="$(jq_run -cn --arg version "$version" '[
  "goplaces_\($version)_darwin_amd64.tar.gz",
  "goplaces_\($version)_darwin_arm64.tar.gz",
  "goplaces_\($version)_linux_amd64.tar.gz",
  "goplaces_\($version)_linux_arm64.tar.gz",
  "goplaces_\($version)_windows_amd64.zip",
  "goplaces_\($version)_windows_arm64.zip",
  "goplaces_checksums.txt"
] | sort')"

assets_valid="$(jq_run -r \
  --arg api "$api_url" \
  --arg repo "$repository" \
  --argjson expected "$expected_assets" '
    (.assets | type == "array") and
    ([.assets[].name] | sort == $expected) and
    (([.assets[].name] | unique | length) == 7) and
    (([.assets[].id] | unique | length) == 7) and
    (all(.assets[];
      (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      (.name | type == "string") and
      (.size | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      .state == "uploaded" and
      (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      .url == ($api + "/repos/" + $repo + "/releases/assets/" + (.id | tostring))
    ))
  ' "$release")"
[[ "$assets_valid" == true ]] || die "release asset inventory is not the exact seven-file contract"

normalized_record="$scratch/release-record.json"
jq_run -S \
  --arg state "$release_state" \
  --arg repo "$repository" '
    {
      schema:"goplaces-release-record-v1",
      repository:$repo,
      state:$state,
      id:.id,
      tag_name:.tag_name,
      name:.name,
      target_commitish:.target_commitish,
      draft:.draft,
      prerelease:.prerelease,
      body:.body,
      created_at:.created_at,
      published_at:.published_at,
      updated_at:.updated_at,
      assets:(.assets | map({id,name,size,digest,state,url,created_at,updated_at}) | sort_by(.name))
    }
  ' "$release" > "$normalized_record"

asset_rows="$scratch/assets.tsv"
jq_run -r '.assets[] | [.id,.name,.size,.digest,.url] | @tsv' "$normalized_record" > "$asset_rows"
while IFS=$'\t' read -r asset_id asset_name asset_size asset_digest asset_api_url; do
  [[ "$asset_id" =~ ^[1-9][0-9]*$ ]] || die "invalid asset ID"
  [[ "$asset_name" != */* && "$asset_name" != .* && -n "$asset_name" ]] || die "unsafe asset name"
  output="$scratch/$asset_name"
  download_asset "$asset_api_url" "$output" "$asset_id"
  [[ -f "$output" && ! -L "$output" ]] || die "asset download is not a regular file: $asset_name"
  actual_size="$(/usr/bin/wc -c < "$output" | /usr/bin/tr -d '[:space:]')"
  [[ "$actual_size" == "$asset_size" ]] || die "asset size changed during download: $asset_name"
  actual_digest="$(/usr/bin/shasum -a 256 "$output" | /usr/bin/awk '{print $1}')"
  [[ "sha256:$actual_digest" == "$asset_digest" ]] || die "asset digest changed during download: $asset_name"
done < "$asset_rows"

final_release="$scratch/release-final.json"
api_get "$api_url/repos/$repository/releases/$release_id" "$final_release"
final_record="$scratch/release-record-final.json"
jq_run -S \
  --arg state "$release_state" \
  --arg repo "$repository" '
    {
      schema:"goplaces-release-record-v1",
      repository:$repo,
      state:$state,
      id:.id,
      tag_name:.tag_name,
      name:.name,
      target_commitish:.target_commitish,
      draft:.draft,
      prerelease:.prerelease,
      body:.body,
      created_at:.created_at,
      published_at:.published_at,
      updated_at:.updated_at,
      assets:(.assets | map({id,name,size,digest,state,url,created_at,updated_at}) | sort_by(.name))
    }
  ' "$final_release" > "$final_record"
/usr/bin/cmp -s "$normalized_record" "$final_record" || die "release record changed during download"

/bin/rm -f "$auth_config" "$release" "$final_release" "$final_record" \
  "$scratch/repository.json" "$scratch/default-branch.json" \
  "$scratch"/asset-response-*.headers "$scratch"/asset-response-*.body \
  "$scratch/jq" "$scratch/jq-version.txt" "$asset_rows"
/bin/rm -rf "$scratch/jq-home" "$scratch/curl-home"
/bin/mv "$scratch" "$destination"
trap - EXIT
printf '%s\n' "$destination/release-record.json"
