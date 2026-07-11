#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail
export LC_ALL=C

fail() {
  echo "release asset tests: $*" >&2
  exit 1
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$tmp/failure.stdout" 2>"$tmp/failure.stderr"; then
    fail "$label unexpectedly succeeded"
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
# shellcheck source=scripts/test-git-fixture.sh
source "$root/scripts/test-git-fixture.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-release-tests.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fixture_git_isolation="$tmp/fixture-git-isolation"
mkdir -p "$fixture_git_isolation"
jq_fixture="$(command -v jq)"
[[ "$("$jq_fixture" --version)" == jq-1.8.2 ]] || fail "tests require jq 1.8.2"
unzip_fixture=/usr/bin/unzip
[[ -x "$unzip_fixture" && ! -L "$unzip_fixture" ]] || fail "system unzip fixture is unavailable"

workflow=.github/workflows/release-assets.yml
[[ -f "$workflow" ]] || fail "release-assets workflow is missing"
grep -Fq 'name: release-assets' "$workflow" || fail "workflow name is not frozen"
grep -Fq 'run-name: Verify ${{ inputs.tag }} ${{ inputs.state }} release ${{ inputs.release_id }} nonce ${{ inputs.dispatch_nonce }}' "$workflow" || fail "run title is not exact"
grep -Fq 'DISPATCH_NONCE: ${{ inputs.dispatch_nonce }}' "$workflow" || fail "dispatch nonce is not passed to the protected entry gate"
grep -Fq 'runner: macos-15' "$workflow" || fail "native arm64 runner is missing"
grep -Fq 'runner: macos-15-intel' "$workflow" || fail "native Intel runner is missing"
if grep -Eq '^[[:space:]]*uses:' "$workflow"; then fail "release verifier must not depend on mutable actions"; fi
grep -Fq 'Install exact pinned Go toolchain' "$workflow" || fail "pinned toolchain bootstrap step is missing"
grep -Fq 'govulncheck@v1.5.0' "$workflow" || fail "govulncheck version is not pinned"
[[ "$(grep -Fc '"$RUNNER_TEMP/tools/govulncheck" -db=https://vuln.go.dev -test ./...' "$workflow")" -eq 1 ]] || fail "exact tagged source must receive one official-database vulnerability scan including tests"
grep -Fq "GOPROXY=off GOSUMDB=off GOVCS='*:off'" "$workflow" || fail "exact tagged source scan is not module-offline"
grep -Fq 'GOENV=off GOTOOLCHAIN=local GOWORK=off GOTELEMETRY=off' "$workflow" || fail "Go configuration is not hermetic"
grep -Fq 'contents: write' "$workflow" || fail "draft download permission is not explicit"
[[ "$(grep -Fc '${{ github.token }}' "$workflow")" -eq 1 ]] || fail "workflow token must appear in exactly one step"
[[ "$(grep -Ec '^[[:space:]]+GH_TOKEN:' "$workflow")" -eq 1 ]] || fail "GH_TOKEN must be scoped to exactly one step"
download_line="$(grep -n 'Download exact numeric release assets' "$workflow" | cut -d: -f1)"
static_line="$(grep -n 'Freeze and statically verify release inventory' "$workflow" | cut -d: -f1)"
rebuild_line="$(grep -n 'Rebuild exact non-Darwin bytes' "$workflow" | cut -d: -f1)"
execute_line="$(grep -n 'Recheck tag and execute native candidate last' "$workflow" | cut -d: -f1)"
[[ "$download_line" -lt "$static_line" && "$static_line" -lt "$rebuild_line" && "$rebuild_line" -lt "$execute_line" ]] || fail "candidate execution is not ordered after every static/rebuild gate"

production_files=(
  .github/workflows/release-assets.yml
  scripts/codesign-macos.sh
  scripts/verify-macos-binary.sh
  scripts/verify-release-tag.sh
  scripts/bootstrap-go-toolchain.sh
  scripts/download-release-assets.sh
  scripts/validate-release-record.sh
  scripts/validate-verifier-dispatch.sh
  scripts/freeze-release-inventory.sh
  scripts/verify-release-assets.sh
  scripts/rebuild-release-assets.sh
  scripts/check-release-verifier.sh
)
[[ -x scripts/bootstrap-go-toolchain.sh ]] || fail "toolchain bootstrap is not executable"
if /usr/bin/grep -En '(^|[^[:alnum:]_])(spctl|syspolicy|syspolicy_check|stapler)([^[:alnum:]_]|$)' \
  "${production_files[@]}" >"$tmp/forbidden.txt"; then
  cat "$tmp/forbidden.txt" >&2
  fail "a prohibited raw policy tool appears in release code"
fi
if /usr/bin/grep -En -- '--location|actions/setup-go' \
  .github/workflows/release-assets.yml scripts/bootstrap-go-toolchain.sh scripts/download-release-assets.sh \
  >"$tmp/mutable-download.txt"; then
  cat "$tmp/mutable-download.txt" >&2
  fail "protected downloads must not follow redirects or use mutable setup actions"
fi
for helper in scripts/download-release-assets.sh scripts/check-release-verifier.sh; do
  grep -Fxq '#!/bin/bash -p' "$helper" || fail "$helper does not enter privileged Bash mode"
  grep -Fxq 'unset BASH_ENV ENV CDPATH' "$helper" || fail "$helper does not clear shell startup and directory search variables"
  grep -Fq 'curl_bin=/usr/bin/curl' "$helper" || fail "$helper does not force system curl in production"
  grep -Fq 'jq is not the reviewed 1.8.2 Cellar executable' "$helper" || fail "$helper does not pin jq 1.8.2"
  grep -Fq 'frozen jq bytes changed' "$helper" || fail "$helper does not recheck frozen jq bytes"
  grep -Fq 'frozen jq identity changed' "$helper" || fail "$helper does not recheck frozen jq identity"
  grep -Fq '/usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/jq-home"' "$helper" || fail "$helper does not isolate jq configuration"
  grep -Fq '/usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/curl-home"' "$helper" || fail "$helper does not isolate production curl configuration"
done
grep -Fq 'unzip_bin=/usr/bin/unzip' scripts/check-release-verifier.sh || fail "verifier checker does not force system unzip in production"
grep -Fq '/usr/bin/env -i PATH=/usr/bin:/bin HOME="$scratch/unzip-home"' scripts/check-release-verifier.sh || fail "verifier checker does not isolate unzip configuration"
grep -Fq '/usr/bin/awk' scripts/download-release-assets.sh || fail "release downloader does not force system awk"
grep -Fq 'go1.26.5.darwin-amd64.tar.gz' scripts/bootstrap-go-toolchain.sh || fail "Intel toolchain URL is not pinned"
grep -Fq '6231d8d3b8f5552ec6cbf6d685bdd5482e1e703214b120e89b3bf0d7bf1ef725' scripts/bootstrap-go-toolchain.sh || fail "Intel toolchain digest is not pinned"
grep -Fq '67836304' scripts/bootstrap-go-toolchain.sh || fail "Intel toolchain size is not pinned"
grep -Fq 'go1.26.5.darwin-arm64.tar.gz' scripts/bootstrap-go-toolchain.sh || fail "arm64 toolchain URL is not pinned"
grep -Fq 'efb87ff28af9a188d0536ef5d42e63dd52ba8263cd7344a993cc48dd11dedb6a' scripts/bootstrap-go-toolchain.sh || fail "arm64 toolchain digest is not pinned"
grep -Fq '64738542' scripts/bootstrap-go-toolchain.sh || fail "arm64 toolchain size is not pinned"
grep -Fq 'refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG' "$workflow" || fail "exact annotated tag ref is not fetched into source"
[[ "$(grep -Fc 'status --porcelain --untracked-files=all' "$workflow")" -eq 3 ]] || fail "workflow source trees are not checked with exact all-untracked status"

bootstrap_payload="$tmp/bootstrap-payload"
mkdir -p "$bootstrap_payload/go/bin"
cat >"$bootstrap_payload/go/bin/go" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == env && "$2" == GOVERSION ]]
printf 'go1.26.5\n'
MOCK
chmod +x "$bootstrap_payload/go/bin/go"
bootstrap_archive="$tmp/bootstrap.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$bootstrap_archive" -C "$bootstrap_payload" go
bootstrap_size="$(wc -c < "$bootstrap_archive" | tr -d '[:space:]')"
bootstrap_sha="$(sha256_file "$bootstrap_archive")"
bootstrap_curl="$tmp/bootstrap-curl"
cat >"$bootstrap_curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output=
previous=
url=
for arg in "$@"; do
  [[ "$previous" == --output ]] && output=$arg
  previous=$arg
  url=$arg
done
[[ "$*" == *'--disable'* && "$*" != *'--location'* ]]
printf '%s\n' "$*" >> "$MOCK_BOOTSTRAP_LOG"
cp "$MOCK_BOOTSTRAP_ARCHIVE" "$output"
printf '%s' "${MOCK_HTTP_STATUS:-200}"
MOCK
bootstrap_uname="$tmp/bootstrap-uname"
cat >"$bootstrap_uname" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$MOCK_UNAME_ARCH"
MOCK
chmod +x "$bootstrap_curl" "$bootstrap_uname"
for bootstrap_arch in arm64 x86_64; do
  if [[ "$bootstrap_arch" == arm64 ]]; then archive_arch=arm64; else archive_arch=amd64; fi
  bootstrap_dest="$tmp/go-$bootstrap_arch"
  MOCK_BOOTSTRAP_LOG="$tmp/bootstrap.log" MOCK_BOOTSTRAP_ARCHIVE="$bootstrap_archive" MOCK_UNAME_ARCH="$bootstrap_arch" \
    GOPLACES_RELEASE_TESTING=1 CURL_BIN="$bootstrap_curl" UNAME_BIN="$bootstrap_uname" \
    EXPECTED_ARCHIVE_URL="https://dl.google.com/go/go1.26.5.darwin-$archive_arch.tar.gz" \
    EXPECTED_ARCHIVE_SIZE="$bootstrap_size" EXPECTED_ARCHIVE_SHA256="$bootstrap_sha" \
    ./scripts/bootstrap-go-toolchain.sh "$bootstrap_dest" >/dev/null
  [[ -x "$bootstrap_dest/go/bin/go" ]] || fail "bootstrap did not install $bootstrap_arch Go"
done
expect_failure "bootstrap wrong digest" env MOCK_BOOTSTRAP_LOG="$tmp/bootstrap.log" MOCK_BOOTSTRAP_ARCHIVE="$bootstrap_archive" MOCK_UNAME_ARCH=arm64 GOPLACES_RELEASE_TESTING=1 CURL_BIN="$bootstrap_curl" UNAME_BIN="$bootstrap_uname" EXPECTED_ARCHIVE_SIZE="$bootstrap_size" EXPECTED_ARCHIVE_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ./scripts/bootstrap-go-toolchain.sh "$tmp/go-wrong-digest"
expect_failure "bootstrap non-200" env MOCK_BOOTSTRAP_LOG="$tmp/bootstrap.log" MOCK_BOOTSTRAP_ARCHIVE="$bootstrap_archive" MOCK_UNAME_ARCH=arm64 MOCK_HTTP_STATUS=302 GOPLACES_RELEASE_TESTING=1 CURL_BIN="$bootstrap_curl" UNAME_BIN="$bootstrap_uname" EXPECTED_ARCHIVE_SIZE="$bootstrap_size" EXPECTED_ARCHIVE_SHA256="$bootstrap_sha" ./scripts/bootstrap-go-toolchain.sh "$tmp/go-redirect"

tag=v0.4.5
version=0.4.5
commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tag_object=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
dispatch_nonce=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
export EXPECTED_DISPATCH_NONCE="$dispatch_nonce"
title_fixture="Verify ${tag} draft release 5550 nonce ${dispatch_nonce}"
[[ ${#title_fixture} -le 160 ]] || fail "dispatch title fixture is unexpectedly long"
asset_dir="$tmp/assets-source"
payload_dir="$tmp/payload"
mkdir -p "$asset_dir" "$payload_dir"
archives=()
for os in darwin linux windows; do
  for arch in amd64 arm64; do
    if [[ "$os" == windows ]]; then
      member=goplaces.exe
      archive="goplaces_${version}_${os}_${arch}.zip"
    else
      member=goplaces
      archive="goplaces_${version}_${os}_${arch}.tar.gz"
    fi
    rm -f "$payload_dir/$member"
    printf 'fixture %s %s\n' "$os" "$arch" >"$payload_dir/$member"
    chmod 0555 "$payload_dir/$member"
    if [[ "$os" == windows ]]; then
      (cd "$payload_dir" && zip -q -X "$asset_dir/$archive" "$member")
    else
      COPYFILE_DISABLE=1 tar -czf "$asset_dir/$archive" -C "$payload_dir" "$member"
    fi
    archives+=("$archive")
  done
done

: >"$asset_dir/goplaces_checksums.txt"
for archive in "${archives[@]}"; do
  printf '%s  %s\n' "$(sha256_file "$asset_dir/$archive")" "$archive" >>"$asset_dir/goplaces_checksums.txt"
done

assets_json='[]'
asset_id=7101
for name in "${archives[@]}" goplaces_checksums.txt; do
  size="$(wc -c <"$asset_dir/$name" | tr -d '[:space:]')"
  digest="sha256:$(sha256_file "$asset_dir/$name")"
  assets_json="$(jq -c \
    --argjson id "$asset_id" \
    --arg name "$name" \
    --argjson size "$size" \
    --arg digest "$digest" \
    '. + [{id:$id,name:$name,size:$size,digest:$digest,state:"uploaded",url:("https://api.github.com/repos/openclaw/goplaces/releases/assets/" + ($id|tostring)),created_at:"2026-07-10T09:00:00Z",updated_at:"2026-07-10T10:00:00Z"}]' <<<"$assets_json")"
  asset_id=$((asset_id + 1))
done

jq -nS \
  --arg tag "$tag" \
  --arg commit "$commit" \
  --argjson assets "$assets_json" '
  {
    schema:"goplaces-release-record-v1",repository:"openclaw/goplaces",state:"draft",
    id:5550,tag_name:$tag,name:$tag,target_commitish:$commit,draft:true,prerelease:false,
    body:"Release notes\n",created_at:"2026-07-10T08:00:00Z",published_at:null,
    updated_at:"2026-07-10T10:00:00Z",assets:$assets
  }' >"$asset_dir/release-record.json"

./scripts/validate-release-record.sh "$asset_dir/release-record.json" "$tag" "$commit" draft >/dev/null
env -u GH_TOKEN -u GITHUB_TOKEN ./scripts/freeze-release-inventory.sh "$asset_dir" "$tag" "$tmp/inventory.json" >/dev/null
[[ -s "$tmp/inventory.json" ]] || fail "inventory freeze emitted no record"
[[ "$(jq '.members | length' "$tmp/inventory.json")" -eq 6 ]] || fail "inventory does not contain six archive members"

jq '.assets[1].id = .assets[0].id' "$asset_dir/release-record.json" >"$tmp/duplicate-id.json"
expect_failure "duplicate asset ID" ./scripts/validate-release-record.sh "$tmp/duplicate-id.json" "$tag" "$commit" draft
jq '.assets[0].url += "@hostile"' "$asset_dir/release-record.json" >"$tmp/hostile-url.json"
expect_failure "hostile asset URL" ./scripts/validate-release-record.sh "$tmp/hostile-url.json" "$tag" "$commit" draft
jq '.assets[0].id = 9007199254740992' "$asset_dir/release-record.json" >"$tmp/overflow-id.json"
expect_failure "overflow asset ID" ./scripts/validate-release-record.sh "$tmp/overflow-id.json" "$tag" "$commit" draft

mutated_dir="$tmp/mutated-assets"
cp -R "$asset_dir" "$mutated_dir"
printf 'mutation\n' >>"$mutated_dir/${archives[0]}"
expect_failure "changed downloaded bytes" env -u GH_TOKEN -u GITHUB_TOKEN ./scripts/freeze-release-inventory.sh "$mutated_dir" "$tag" "$tmp/mutated-inventory.json"
expect_failure "token-bearing freeze" env GH_TOKEN=hostile ./scripts/freeze-release-inventory.sh "$asset_dir" "$tag"
expect_failure "empty token variable during freeze" env GH_TOKEN='' ./scripts/freeze-release-inventory.sh "$asset_dir" "$tag"

raw_release="$tmp/release-api.json"
jq '{id,tag_name,name,target_commitish,draft,prerelease,body,created_at,published_at,updated_at,assets}' "$asset_dir/release-record.json" >"$raw_release"
curl_mock="$tmp/curl-download"
cat >"$curl_mock" <<'MOCK'
#!/bin/bash -p
set -euo pipefail
[[ -z "${GH_TOKEN+x}" ]] || exit 70
[[ "${1:-}" == --disable ]] || exit 75
output=
headers=
config=
url=
previous=
for arg in "$@"; do
  if [[ "$previous" == --output ]]; then output=$arg; fi
  if [[ "$previous" == --dump-header ]]; then headers=$arg; fi
  if [[ "$previous" == --config ]]; then config=$arg; fi
  previous=$arg
  url=$arg
done
[[ -n "$output" ]]
printf '%s|config=%s|%s\n' "$url" "$config" "$*" >>"$MOCK_CURL_LOG"
[[ "$*" == *'--disable'* && "$*" != *'--location'* ]]
case "$url" in
  *'/releases?per_page='*) exit 72 ;;
  *'/releases/5550')
    count=0
    [[ ! -f "$MOCK_RELEASE_COUNT" ]] || count=$(/bin/cat "$MOCK_RELEASE_COUNT")
    count=$((count + 1))
    printf '%s\n' "$count" >"$MOCK_RELEASE_COUNT"
    if [[ "${MOCK_MUTATE_FINAL:-0}" == 1 && "$count" -eq 2 ]]; then
      "$MOCK_JQ_BIN" '.updated_at = "2026-07-10T11:00:00Z"' "$MOCK_RELEASE_JSON" >"$output"
    else
      /bin/cp "$MOCK_RELEASE_JSON" "$output"
    fi
    printf 200
    ;;
  *'/releases/assets/'*)
    id=${url##*/}
    name=$("$MOCK_JQ_BIN" -r --argjson id "$id" '.assets[] | select(.id == $id) | .name' "$MOCK_RELEASE_JSON")
    [[ -n "$name" ]]
    if [[ "${MOCK_REDIRECT:-0}" == 1 ]]; then
      : >"$output"
      : >"$headers"
      location="${MOCK_REDIRECT_URL:-https://release-assets.githubusercontent.com/github-production-release-asset/$id}"
      printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\n' "$location" >"$headers"
      [[ "${MOCK_DUPLICATE_LOCATION:-0}" != 1 ]] || printf 'Location: %s\r\n' "$location" >>"$headers"
      printf '%s' "${MOCK_ASSET_STATUS:-302}"
    else
      /bin/cp "$MOCK_ASSET_DIR/$name" "$output"
      [[ -z "$headers" ]] || : >"$headers"
      printf 200
    fi
    ;;
  https://release-assets.githubusercontent.com/*)
    [[ -z "$config" ]] || { printf leaked >"$MOCK_SENTINEL"; exit 73; }
    id=${url##*/}
    name=$("$MOCK_JQ_BIN" -r --argjson id "$id" '.assets[] | select(.id == $id) | .name' "$MOCK_RELEASE_JSON")
    /bin/cp "$MOCK_ASSET_DIR/$name" "$output"
    printf 200
    ;;
  https://evil.example/*)
    printf reached >"$MOCK_SENTINEL"
    exit 74
    ;;
  *) exit 71 ;;
esac
MOCK
chmod +x "$curl_mock"
hostile_bin="$tmp/hostile-tool-path"
hostile_home="$tmp/hostile-tool-home"
hostile_tool_sentinel="$tmp/hostile-tool-sentinel"
mkdir -p "$hostile_bin" "$hostile_home"
for hostile_name in bash curl jq unzip awk dirname basename mktemp mv wc tr grep env shasum stat readlink uname cp chmod mkdir rm cmp cat touch; do
  cat >"$hostile_bin/$hostile_name" <<'MOCK'
#!/bin/bash
set -euo pipefail
/usr/bin/touch "$HOSTILE_TOOL_SENTINEL"
exit 119
MOCK
  chmod +x "$hostile_bin/$hostile_name"
done
hostile_bash_env="$tmp/hostile-bash-env"
cat >"$hostile_bash_env" <<'MOCK'
/usr/bin/touch "${HOSTILE_TOOL_SENTINEL:?}"
MOCK
printf 'output = "%s"\n' "$tmp/hostile-curl-output" >"$hostile_home/.curlrc"
jq_swap="$tmp/jq-self-swap"
cat >"$jq_swap" <<MOCK
#!/bin/bash
set -euo pipefail
/bin/chmod 700 "\$0"
/usr/bin/printf '%s\n' '# swapped after freeze' >> "\$0"
exec "$jq_fixture" "\$@"
MOCK
chmod +x "$jq_swap"
jq_identity_swap="$tmp/jq-identity-swap"
cat >"$jq_identity_swap" <<MOCK
#!/bin/bash
set -euo pipefail
/bin/cp "\$0" "\${0}.replacement"
/bin/chmod 500 "\${0}.replacement"
/bin/mv -f "\${0}.replacement" "\$0"
exec "$jq_fixture" "\$@"
MOCK
chmod +x "$jq_identity_swap"
expect_failure "self-modifying frozen downloader jq" env GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_swap" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/jq-swap-download" 5550
grep -Fq 'frozen jq bytes changed' "$tmp/failure.stderr" || fail "downloader did not report frozen jq byte replacement"
expect_failure "same-byte replacement of frozen downloader jq" env GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_identity_swap" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/jq-identity-swap-download" 5550
grep -Fq 'frozen jq identity changed' "$tmp/failure.stderr" || fail "downloader did not report frozen jq identity replacement"
override_tool="$tmp/forbidden-production-tool"
cat >"$override_tool" <<'MOCK'
#!/bin/bash
set -euo pipefail
/usr/bin/touch "$HOSTILE_TOOL_SENTINEL"
exit 120
MOCK
chmod +x "$override_tool"
expect_failure "production downloader tool override" env HOSTILE_TOOL_SENTINEL="$hostile_tool_sentinel" CURL_BIN="$override_tool" JQ_BIN="$override_tool" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/production-override-download" 5550
[[ ! -e "$hostile_tool_sentinel" ]] || fail "production downloader executed an override tool"
downloaded="$tmp/downloaded"
rm -f "$tmp/download-count" "$tmp/download-sentinel"
MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/curl.log" \
  MOCK_RELEASE_COUNT="$tmp/download-count" MOCK_SENTINEL="$tmp/download-sentinel" MOCK_REDIRECT=1 \
  MOCK_JQ_BIN="$jq_fixture" HOSTILE_TOOL_SENTINEL="$hostile_tool_sentinel" PATH="$hostile_bin:$PATH" HOME="$hostile_home" BASH_ENV="$hostile_bash_env" ENV="$hostile_bash_env" CDPATH="$tmp" \
  GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token \
  ./scripts/download-release-assets.sh "$tag" "$downloaded" 5550 >/dev/null
[[ ! -e "$hostile_tool_sentinel" && ! -e "$tmp/hostile-curl-output" ]] || fail "downloader used hostile PATH or curl configuration"
[[ -s "$downloaded/release-record.json" ]] || fail "downloader did not preserve the normalized release record"
cmp -s "$downloaded/goplaces_checksums.txt" "$asset_dir/goplaces_checksums.txt" || fail "downloaded checksum bytes differ"
if grep -Fq '/releases?per_page=' "$tmp/curl.log"; then fail "numeric download performed mutable release-list discovery"; fi
[[ "$(grep -Fc 'Accept: application/octet-stream' "$tmp/curl.log")" -eq 7 ]] || fail "downloads did not use seven numeric octet-stream requests"
[[ "$(grep -Fc '/releases/5550|config=' "$tmp/curl.log")" -eq 2 ]] || fail "downloader did not read the exact numeric release exactly twice"
[[ "$(find "$downloaded" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d '[:space:]')" -eq 8 ]] || fail "redirect response scratch files escaped into destination"
[[ ! -e "$tmp/download-sentinel" ]] || fail "authentication leaked to release CDN"
expect_failure "existing destination" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/curl.log" MOCK_RELEASE_COUNT="$tmp/existing-count" MOCK_SENTINEL="$tmp/existing-sentinel" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$downloaded" 5550
ln -s "$tmp/nowhere" "$tmp/symlink-destination"
expect_failure "symlink destination" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/curl.log" MOCK_RELEASE_COUNT="$tmp/symlink-count" MOCK_SENTINEL="$tmp/symlink-sentinel" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/symlink-destination" 5550
expect_failure "overflow numeric release ID" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/curl.log" MOCK_RELEASE_COUNT="$tmp/overflow-count" MOCK_SENTINEL="$tmp/overflow-sentinel" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/overflow-destination" 9007199254740992
expect_failure "missing numeric release ID" env GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/missing-id"
expect_failure "extra downloader argument" env GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/extra-id" 5550 extra
expect_failure "release mutation during download" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/mutating-curl.log" MOCK_RELEASE_COUNT="$tmp/mutating-count" MOCK_SENTINEL="$tmp/mutating-sentinel" MOCK_MUTATE_FINAL=1 MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/mutating-destination" 5550
[[ ! -e "$tmp/mutating-destination" ]] || fail "mutated release produced a destination"
expect_failure "cross-host redirect" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/cross-host-curl.log" MOCK_RELEASE_COUNT="$tmp/cross-host-count" MOCK_SENTINEL="$tmp/cross-host-sentinel" MOCK_REDIRECT=1 MOCK_REDIRECT_URL=https://evil.example/asset MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/cross-host-destination" 5550
[[ ! -e "$tmp/cross-host-sentinel" ]] || fail "cross-host redirect was reached"
expect_failure "duplicate redirect location" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/duplicate-location-curl.log" MOCK_RELEASE_COUNT="$tmp/duplicate-location-count" MOCK_SENTINEL="$tmp/duplicate-location-sentinel" MOCK_REDIRECT=1 MOCK_DUPLICATE_LOCATION=1 MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/duplicate-location-destination" 5550
expect_failure "non-302 asset redirect" env MOCK_RELEASE_JSON="$raw_release" MOCK_ASSET_DIR="$asset_dir" MOCK_CURL_LOG="$tmp/asset-status-curl.log" MOCK_RELEASE_COUNT="$tmp/asset-status-count" MOCK_SENTINEL="$tmp/asset-status-sentinel" MOCK_REDIRECT=1 MOCK_ASSET_STATUS=301 MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$curl_mock" JQ_BIN="$jq_fixture" GH_TOKEN=fixture_token ./scripts/download-release-assets.sh "$tag" "$tmp/asset-status-destination" 5550

workflow_json="$tmp/workflow.json"
run_json="$tmp/run.json"
preexisting="$tmp/preexisting.json"
jq -n '{id:309911276,name:"release-assets",path:".github/workflows/release-assets.yml",state:"active"}' >"$workflow_json"
jq -n \
  --arg sha "$commit" --arg tag "$tag" --arg object "$tag_object" --arg nonce "$dispatch_nonce" '
  {
    id:29009699237,workflow_id:309911276,path:".github/workflows/release-assets.yml",
    event:"workflow_dispatch",head_branch:"main",head_sha:$sha,
    display_title:("Verify " + $tag + " draft release 5550 nonce " + $nonce),
    status:"completed",conclusion:"success",run_attempt:1,created_at:"2026-07-10T12:00:00Z",
    repository:{full_name:"openclaw/goplaces"},
    url:"https://api.github.com/repos/openclaw/goplaces/actions/runs/29009699237",
    html_url:"https://github.com/openclaw/goplaces/actions/runs/29009699237"
  }' >"$run_json"
printf '[]\n' >"$preexisting"
jq -n '{workflow_run_id:29009699237,run_url:"https://api.github.com/repos/openclaw/goplaces/actions/runs/29009699237",html_url:"https://github.com/openclaw/goplaces/actions/runs/29009699237"}' >"$tmp/dispatch-response.json"
EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 REQUIRE_SUCCESS=1 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" \
  ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting" >/dev/null
EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 REQUIRE_SUCCESS=1 RECOVERED_DISPATCH=1 \
  ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting" >/dev/null
expect_failure "recovered dispatch claiming a response" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 RECOVERED_DISPATCH=1 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
expect_failure "invalid recovered dispatch mode" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 RECOVERED_DISPATCH=2 ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
jq '.run_url += "/substitute"' "$tmp/dispatch-response.json" >"$tmp/dispatch-response-bad.json"
expect_failure "substituted dispatch response URL" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response-bad.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
jq '.path = ".github/workflows/release-assets.yml@main"' "$run_json" >"$tmp/run-suffixed.json"
expect_failure "suffixed workflow-run path" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$tmp/run-suffixed.json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
jq '.workflow_id = 309911277' "$run_json" >"$tmp/run-wrong-workflow.json"
expect_failure "dispatch valid wrong workflow ID" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$tmp/run-wrong-workflow.json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
jq '.head_branch = "release"' "$run_json" >"$tmp/run-wrong-branch.json"
expect_failure "dispatch wrong protected branch" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$tmp/run-wrong-branch.json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
jq '.head_sha = "3333333333333333333333333333333333333333"' "$run_json" >"$tmp/run-wrong-head.json"
expect_failure "dispatch wrong protected head SHA" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$tmp/run-wrong-head.json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
printf '[29009699237]\n' >"$tmp/preexisting-bad.json"
expect_failure "preexisting dispatched run" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$tmp/preexisting-bad.json"
expect_failure "missing expected run ID" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
expect_failure "missing dispatch response" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
expect_failure "mismatched expected run ID" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699238 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
expect_failure "overflow expected run ID" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=9007199254740992 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5550 "$preexisting"
expect_failure "wrong release ID title binding" env EXPECTED_RELEASE_STATE=draft EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" EXPECTED_RUN_ID=29009699237 DISPATCH_RESPONSE_JSON="$tmp/dispatch-response.json" ./scripts/validate-verifier-dispatch.sh "$run_json" "$workflow_json" main "$commit" "$tag" 5551 "$preexisting"

git_mock="$tmp/git-mock"
cat >"$git_mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  rev-parse)
    case "$2" in
      --show-toplevel) printf '%s\n' "$MOCK_REPO_ROOT" ;;
      --absolute-git-dir) printf '%s\n' "$MOCK_GIT_DIR" ;;
      --git-path) printf '%s/%s\n' "$MOCK_GIT_DIR" "$3" ;;
      *'^{tag}') printf '%s\n' "$MOCK_TAG_OBJECT" ;;
      *'^{commit}') printf '%s\n' "$MOCK_TAG_COMMIT" ;;
      *) exit 80 ;;
    esac
    ;;
  for-each-ref)
    [[ "${MOCK_REPLACE_REF:-0}" != 1 ]] || printf 'refs/replace/%s\n' "$MOCK_TAG_COMMIT"
    ;;
  config) exit 1 ;;
  remote) printf 'https://github.com/openclaw/goplaces.git\n' ;;
  show) cat "$MOCK_REPO_ROOT/.github/release-allowed-signers" ;;
  update-ref|fetch) ;;
  ls-remote)
    count=0
    [[ ! -f "$MOCK_LS_COUNT" ]] || count=$(cat "$MOCK_LS_COUNT")
    count=$((count + 1))
    printf '%s\n' "$count" >"$MOCK_LS_COUNT"
    object=$MOCK_TAG_OBJECT
    if [[ "${MOCK_MOVE_TAG:-0}" == 1 && "$count" -ge 2 ]]; then object=cccccccccccccccccccccccccccccccccccccccc; fi
    printf '%s\trefs/tags/%s\n%s\trefs/tags/%s^{}\n' "$object" "$MOCK_TAG" "$MOCK_TAG_COMMIT" "$MOCK_TAG"
    ;;
  cat-file)
    if [[ "$2" == -t ]]; then
      printf 'tag\n'
    else
      printf 'object %s\ntype commit\ntag %s\ntagger Release Test <release-test@localhost> 1783670400 +0000\n\nRelease fixture\n-----BEGIN SSH SIGNATURE-----\nfixture\n-----END SSH SIGNATURE-----\n' "$MOCK_TAG_COMMIT" "$MOCK_TAG"
    fi
    ;;
  -c)
    [[ "$*" == *'gpg.format=ssh'* ]]
    [[ "$*" == *'gpg.ssh.program=/usr/bin/ssh-keygen'* ]]
    [[ "$*" == *"verify-tag --raw $MOCK_TAG_OBJECT"* ]]
    if [[ "${MOCK_BAD_SIGNER:-0}" == 1 ]]; then
      printf 'Good "git" signature for hostile@example.com with ED25519 key SHA256:bad\n' >&2
    else
      printf 'Good "git" signature for steipete@gmail.com with ED25519 key SHA256:WmI9lVtd7F2c5XyRHbZVO3yYYJzwsSNzcZQMPT147HI\n' >&2
    fi
    ;;
  *) exit 81 ;;
esac
MOCK
chmod +x "$git_mock"
mock_git_dir="$tmp/mock-git"
mkdir -p "$mock_git_dir/info" "$mock_git_dir/objects/info"
rm -f "$tmp/ls-count"
GOPLACES_RELEASE_TESTING=1 MOCK_REPO_ROOT="$root" MOCK_GIT_DIR="$mock_git_dir" MOCK_TAG_OBJECT="$tag_object" MOCK_TAG_COMMIT="$commit" MOCK_TAG="$tag" MOCK_LS_COUNT="$tmp/ls-count" GIT_BIN="$git_mock" \
  ./scripts/verify-release-tag.sh "$tag" "$commit" "$tmp/tag-record.json" >/dev/null
jq -e --arg object "$tag_object" '.object_sha == $object' "$tmp/tag-record.json" >/dev/null || fail "tag verifier emitted wrong object"
rm -f "$tmp/ls-count"
expect_failure "tag movement" env GOPLACES_RELEASE_TESTING=1 MOCK_REPO_ROOT="$root" MOCK_GIT_DIR="$mock_git_dir" MOCK_TAG_OBJECT="$tag_object" MOCK_TAG_COMMIT="$commit" MOCK_TAG="$tag" MOCK_LS_COUNT="$tmp/ls-count" MOCK_MOVE_TAG=1 GIT_BIN="$git_mock" ./scripts/verify-release-tag.sh "$tag" "$commit"

go_mock="$tmp/go-mock"
govuln_mock="$tmp/govulncheck-mock"
mac_mock="$tmp/mac-verify-mock"
cat >"$go_mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == env && "$2" == GOVERSION ]]; then printf 'go1.26.5\n'; exit 0; fi
if [[ "$1" == env && "$2" == GOMODCACHE ]]; then printf '%s\n' "$MOCK_MODULE_CACHE"; exit 0; fi
if [[ "$1" == version && "$2" == -m ]]; then
  binary=$3
  case "$binary" in
    *darwin_amd64*) os=darwin; arch=amd64 ;;
    *darwin_arm64*) os=darwin; arch=arm64 ;;
    *linux_amd64*) os=linux; arch=amd64 ;;
    *linux_arm64*) os=linux; arch=arm64 ;;
    *windows_amd64*) os=windows; arch=amd64 ;;
    *windows_arm64*) os=windows; arch=arm64 ;;
    *) exit 90 ;;
  esac
  printf '%s: go1.26.5\n' "$binary"
  printf '\tpath\tgithub.com/steipete/goplaces/cmd/goplaces\n'
  printf '\tmod\tgithub.com/steipete/goplaces\tv0.4.5\n'
  printf '\tbuild\t-ldflags="-s -w -X github.com/steipete/goplaces/internal/cli.Version=0.4.5"\n'
  printf '\tbuild\t-trimpath=true\n'
  printf '\tbuild\tCGO_ENABLED=0\n'
  printf '\tbuild\tGOOS=%s\n\tbuild\tGOARCH=%s\n' "$os" "$arch"
  if [[ "$arch" == amd64 ]]; then
    printf '\tbuild\tGOAMD64=v1\n'
  else
    printf '\tbuild\tGOARM64=v8.0\n'
  fi
  printf '\tbuild\tvcs=git\n'
  printf '\tbuild\tvcs.revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
  printf '\tbuild\tvcs.time=2026-07-10T08:00:00Z\n'
  printf '\tbuild\tvcs.modified=false\n'
  exit 0
fi
if [[ "$1" == build ]]; then
  git --version >/dev/null
  output=
  previous=
  for arg in "$@"; do
    [[ "$previous" == -o ]] && output=$arg
    previous=$arg
  done
  [[ -n "$output" ]]
  if [[ "${0##*/}" == go-bad ]]; then
    printf 'hostile rebuild\n' >"$output"
  else
    printf 'fixture %s %s\n' "$GOOS" "$GOARCH" >"$output"
  fi
  chmod +x "$output"
  exit 0
fi
exit 91
MOCK
cat >"$govuln_mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_GOVULN_LOG"
MOCK
cat >"$mac_mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_MAC_LOG"
[[ "$4" == static ]]
MOCK
chmod +x "$go_mock" "$govuln_mock" "$mac_mock"
mkdir -p "$tmp/module-cache"
native_arch="$(uname -m)"
[[ "$native_arch" == arm64 || "$native_arch" == x86_64 ]] || fail "unsupported test host architecture"
MOCK_MODULE_CACHE="$tmp/module-cache" MOCK_GOVULN_LOG="$tmp/govuln.log" MOCK_MAC_LOG="$tmp/mac.log" EXPECTED_TAG_COMMIT="$commit" \
  GO_BIN="$go_mock" GOVULNCHECK_BIN="$govuln_mock" MAC_VERIFY_BIN="$mac_mock" \
  ./scripts/verify-release-assets.sh "$asset_dir" "$tag" "$native_arch" "$tmp/inventory.json" "$tmp/verified" >/dev/null
[[ "$(wc -l <"$tmp/govuln.log" | tr -d '[:space:]')" -eq 6 ]] || fail "binary vulnerability scan did not cover all six targets"
[[ "$(grep -Ec '^-db=https://vuln\.go\.dev -mode=binary ' "$tmp/govuln.log")" -eq 6 ]] || fail "all six vulnerability scans must pin the official database and use binary mode"
[[ "$(wc -l <"$tmp/mac.log" | tr -d '[:space:]')" -eq 2 ]] || fail "static macOS proof did not cover both Darwin archives"
expect_failure "token-bearing verifier" env GH_TOKEN=hostile EXPECTED_TAG_COMMIT="$commit" MOCK_MODULE_CACHE="$tmp/module-cache" GO_BIN="$go_mock" GOVULNCHECK_BIN="$govuln_mock" MAC_VERIFY_BIN="$mac_mock" ./scripts/verify-release-assets.sh "$asset_dir" "$tag" "$native_arch" "$tmp/inventory.json" "$tmp/token-output"
expect_failure "empty token variable during verifier" env GH_TOKEN='' EXPECTED_TAG_COMMIT="$commit" MOCK_MODULE_CACHE="$tmp/module-cache" GO_BIN="$go_mock" GOVULNCHECK_BIN="$govuln_mock" MAC_VERIFY_BIN="$mac_mock" ./scripts/verify-release-assets.sh "$asset_dir" "$tag" "$native_arch" "$tmp/inventory.json" "$tmp/token-output-empty"

git_source_mock="$tmp/git-source-mock"
cat >"$git_source_mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$3" in
  rev-parse)
    case "$4" in
      --absolute-git-dir) printf '%s\n' "$MOCK_GIT_DIR" ;;
      --git-path) printf '%s/%s\n' "$MOCK_GIT_DIR" "$5" ;;
      HEAD) printf '%s\n' "$MOCK_SOURCE_HEAD" ;;
      *'^{tag}') printf '%s\n' "$MOCK_TAG_OBJECT" ;;
      *'^{commit}') printf '%s\n' "$MOCK_TAG_COMMIT" ;;
      *) exit 94 ;;
    esac
    ;;
  for-each-ref) ;;
  config) exit 1 ;;
  cat-file) printf 'tag\n' ;;
  status)
    [[ "$*" == *'--untracked-files=all'* ]] || exit 93
    [[ ! -f "$2/injected.go" ]] || printf '?? injected.go\n'
    ;;
  *) exit 92 ;;
esac
MOCK
chmod +x "$git_source_mock"
mkdir -p "$tmp/source"
source_mock_git_dir="$tmp/source-git"
mkdir -p "$source_mock_git_dir/info" "$source_mock_git_dir/objects/info"
hostile_path="$tmp/hostile-path"
mkdir -p "$hostile_path"
cat >"$hostile_path/git" <<MOCK
#!/usr/bin/env bash
printf 'ambient git executed\n' >"$tmp/ambient-git-seen"
exit 99
MOCK
chmod +x "$hostile_path/git"
PATH="$hostile_path:$PATH" GOPLACES_RELEASE_TESTING=1 MOCK_MODULE_CACHE="$tmp/module-cache" MOCK_SOURCE_HEAD="$commit" MOCK_GIT_DIR="$source_mock_git_dir" MOCK_TAG_OBJECT="$tag_object" MOCK_TAG_COMMIT="$commit" GO_BIN="$go_mock" GIT_BIN="$git_source_mock" EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" \
  ./scripts/rebuild-release-assets.sh "$tmp/source" "$tmp/verified" "$tag" "$tmp/inventory.json" >/dev/null
[[ ! -e "$tmp/ambient-git-seen" ]] || fail "rebuild executed Git from ambient PATH"
printf '%s\n' "$tmp/hostile-object-store" >"$source_mock_git_dir/objects/info/alternates"
expect_failure "alternate rebuild object store" env GOPLACES_RELEASE_TESTING=1 MOCK_MODULE_CACHE="$tmp/module-cache" MOCK_SOURCE_HEAD="$commit" MOCK_GIT_DIR="$source_mock_git_dir" MOCK_TAG_OBJECT="$tag_object" MOCK_TAG_COMMIT="$commit" GO_BIN="$go_mock" GIT_BIN="$git_source_mock" EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" ./scripts/rebuild-release-assets.sh "$tmp/source" "$tmp/verified" "$tag" "$tmp/inventory.json"
rm -f "$source_mock_git_dir/objects/info/alternates"
printf 'package hostile\n' >"$tmp/source/injected.go"
expect_failure "untracked Go source injection" env GOPLACES_RELEASE_TESTING=1 MOCK_MODULE_CACHE="$tmp/module-cache" MOCK_SOURCE_HEAD="$commit" MOCK_GIT_DIR="$source_mock_git_dir" MOCK_TAG_OBJECT="$tag_object" MOCK_TAG_COMMIT="$commit" GO_BIN="$go_mock" GIT_BIN="$git_source_mock" EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" ./scripts/rebuild-release-assets.sh "$tmp/source" "$tmp/verified" "$tag" "$tmp/inventory.json"
rm -f "$tmp/source/injected.go"
status_source="$tmp/status-source"
fixture_signer="$tmp/fixture-signer"
fixture_process_marker="$tmp/fixture-process-ran"
fixture_hooks="$tmp/fixture-hooks"
fixture_global_config="$tmp/fixture-global-config"
mkdir -p "$fixture_hooks"
cat >"$fixture_signer" <<EOF
#!/bin/sh
: >"$fixture_process_marker"
exit 97
EOF
chmod +x "$fixture_signer"
cp "$fixture_signer" "$fixture_hooks/pre-commit"
cp "$fixture_signer" "$fixture_hooks/reference-transaction"
cat >"$fixture_global_config" <<EOF
[commit]
  gpgSign = true
[tag]
  gpgSign = true
  forceSignAnnotated = true
[gpg]
  format = ssh
[gpg "ssh"]
  program = $fixture_signer
[core]
  hooksPath = $fixture_hooks
EOF
hostile_fixture_git() {
  HOME="$tmp/hostile-home" \
    PATH="$tmp/hostile-bin:/usr/bin:/bin" \
    GIT_CONFIG_SYSTEM="$fixture_global_config" \
    GIT_CONFIG_GLOBAL="$fixture_global_config" \
    GIT_CONFIG_COUNT=6 \
    GIT_CONFIG_KEY_0=commit.gpgSign \
    GIT_CONFIG_VALUE_0=true \
    GIT_CONFIG_KEY_1=tag.gpgSign \
    GIT_CONFIG_VALUE_1=true \
    GIT_CONFIG_KEY_2=tag.forceSignAnnotated \
    GIT_CONFIG_VALUE_2=true \
    GIT_CONFIG_KEY_3=gpg.format \
    GIT_CONFIG_VALUE_3=ssh \
    GIT_CONFIG_KEY_4=gpg.ssh.program \
    GIT_CONFIG_VALUE_4="$fixture_signer" \
    GIT_CONFIG_KEY_5=core.hooksPath \
    GIT_CONFIG_VALUE_5="$fixture_hooks" \
    test_fixture_git "$fixture_git_isolation" "$@"
}
mkdir -p "$status_source"
hostile_fixture_git -C "$status_source" init -q
hostile_fixture_git -C "$status_source" config --local commit.gpgSign true
hostile_fixture_git -C "$status_source" config --local tag.gpgSign true
hostile_fixture_git -C "$status_source" config --local tag.forceSignAnnotated true
hostile_fixture_git -C "$status_source" config --local gpg.format ssh
hostile_fixture_git -C "$status_source" config --local gpg.ssh.program "$fixture_signer"
hostile_fixture_git -C "$status_source" config --local core.hooksPath "$fixture_hooks"
grep -Fq "$fixture_signer" "$status_source/.git/config" || fail "hostile local signer config was not installed"
grep -Fq "$fixture_hooks" "$status_source/.git/config" || fail "hostile local hook config was not installed"
printf 'fixture\n' >"$status_source/tracked.txt"
hostile_fixture_git -C "$status_source" add tracked.txt
hostile_fixture_git -C "$status_source" -c user.name='Release Test' -c user.email='release-test@localhost' commit --no-gpg-sign -q -m fixture
status_head="$(hostile_fixture_git -C "$status_source" rev-parse HEAD)"
hostile_fixture_git -C "$status_source" -c user.name='Release Test' -c user.email='release-test@localhost' tag -a --no-sign "$tag" -m fixture
status_tag_object="$(hostile_fixture_git -C "$status_source" rev-parse "refs/tags/$tag^{tag}")"
[[ "$(hostile_fixture_git -C "$status_source" cat-file -t "$status_tag_object")" == tag ]] || fail "fixture tag is not annotated"
hostile_fixture_git -C "$status_source" cat-file -p "$status_tag_object" >"$tmp/fixture-tag-payload"
if grep -Fq -- '-----BEGIN SSH SIGNATURE-----' "$tmp/fixture-tag-payload"; then
  fail "fixture tag was signed despite the no-sign construction"
fi
[[ ! -e "$fixture_process_marker" ]] || fail "fixture signer or hook process was reached"
hostile_fixture_git -C "$status_source" config status.showUntrackedFiles no
printf 'package hostile\n' >"$status_source/injected.go"
expect_failure "hidden untracked Go source injection" env MOCK_MODULE_CACHE="$tmp/module-cache" GO_BIN="$go_mock" EXPECTED_TAG_COMMIT="$status_head" EXPECTED_TAG_OBJECT="$status_tag_object" ./scripts/rebuild-release-assets.sh "$status_source" "$tmp/verified" "$tag" "$tmp/inventory.json"
worktree_source="$tmp/core-worktree-source"
worktree_redirect="$tmp/core-worktree-redirect"
mkdir -p "$worktree_source" "$worktree_redirect"
test_fixture_git "$fixture_git_isolation" -C "$worktree_source" init -q
printf 'fixture\n' >"$worktree_source/tracked.txt"
test_fixture_git "$fixture_git_isolation" -C "$worktree_source" add tracked.txt
test_fixture_git "$fixture_git_isolation" -C "$worktree_source" -c user.name='Release Test' -c user.email='release-test@localhost' commit --no-gpg-sign -q -m fixture
worktree_head="$(test_fixture_git "$fixture_git_isolation" -C "$worktree_source" rev-parse HEAD)"
test_fixture_git "$fixture_git_isolation" -C "$worktree_source" -c user.name='Release Test' -c user.email='release-test@localhost' tag -a --no-sign "$tag" -m fixture
worktree_tag_object="$(test_fixture_git "$fixture_git_isolation" -C "$worktree_source" rev-parse "refs/tags/$tag^{tag}")"
test_fixture_git "$fixture_git_isolation" -C "$worktree_source" config core.worktree "$worktree_redirect"
printf 'package hostile\n' >"$worktree_source/injected.go"
expect_failure "core.worktree source redirection" env MOCK_MODULE_CACHE="$tmp/module-cache" GO_BIN="$go_mock" EXPECTED_TAG_COMMIT="$worktree_head" EXPECTED_TAG_OBJECT="$worktree_tag_object" ./scripts/rebuild-release-assets.sh "$worktree_source" "$tmp/verified" "$tag" "$tmp/inventory.json"
cp "$go_mock" "$tmp/go-bad"
chmod +x "$tmp/go-bad"
expect_failure "non-reproducible release bytes" env GOPLACES_RELEASE_TESTING=1 MOCK_MODULE_CACHE="$tmp/module-cache" MOCK_SOURCE_HEAD="$commit" MOCK_GIT_DIR="$source_mock_git_dir" MOCK_TAG_OBJECT="$tag_object" MOCK_TAG_COMMIT="$commit" GO_BIN="$tmp/go-bad" GIT_BIN="$git_source_mock" EXPECTED_TAG_COMMIT="$commit" EXPECTED_TAG_OBJECT="$tag_object" ./scripts/rebuild-release-assets.sh "$tmp/source" "$tmp/verified" "$tag" "$tmp/inventory.json"

proof_run_id=29009699237
checker_dir="$tmp/checker"
mkdir -p "$checker_dir"
jq -n '{default_branch:"main"}' >"$checker_dir/repo.json"
jq -n --arg sha "$commit" '{name:"main",protected:true,commit:{sha:$sha}}' >"$checker_dir/branch.json"
cp "$workflow_json" "$checker_dir/workflow.json"
cp "$raw_release" "$checker_dir/release.json"
jq --arg sha "$commit" --arg tag "$tag" --arg object "$tag_object" --arg nonce "$dispatch_nonce" '
  . + {run_attempt:1} |
  .display_title=("Verify " + $tag + " draft release 5550 nonce " + $nonce)
' "$run_json" >"$checker_dir/exact-run.json"
jq -n --slurpfile run "$checker_dir/exact-run.json" '{total_count:1,workflow_runs:$run}' >"$checker_dir/runs.json"
jq -n '{jobs:[
  {name:"verify-arm64",status:"completed",conclusion:"success",run_attempt:1},
  {name:"verify-x86_64",status:"completed",conclusion:"success",run_attempt:1}
]}' >"$checker_dir/jobs.json"
inventory_sha="$(sha256_file "$tmp/inventory.json")"
printf 'GOPLACES_RELEASE_PROOF_V1 arch=arm64 run_id=%s tag=%s tag_object=%s tag_commit=%s release_id=5550 default_sha=%s inventory_sha256=%s\n' "$proof_run_id" "$tag" "$tag_object" "$commit" "$commit" "$inventory_sha" >"$checker_dir/arm64.log"
printf 'GOPLACES_RELEASE_PROOF_V1 arch=x86_64 run_id=%s tag=%s tag_object=%s tag_commit=%s release_id=5550 default_sha=%s inventory_sha256=%s\n' "$proof_run_id" "$tag" "$tag_object" "$commit" "$commit" "$inventory_sha" >"$checker_dir/x86_64.log"
(cd "$checker_dir" && zip -q logs.zip arm64.log x86_64.log)

checker_curl="$tmp/curl-checker"
cat >"$checker_curl" <<'MOCK'
#!/bin/bash -p
set -euo pipefail
[[ -z "${GH_TOKEN+x}" ]] || exit 100
[[ "${1:-}" == --disable ]] || exit 102
output=
previous=
url=
for arg in "$@"; do
  [[ "$previous" == --output ]] && output=$arg
  previous=$arg
  url=$arg
done
case "$url" in
  */repos/openclaw/goplaces) /bin/cp "$MOCK_CHECKER_DIR/repo.json" "$output" ;;
  */branches/main) /bin/cp "$MOCK_CHECKER_DIR/branch.json" "$output" ;;
  */actions/workflows/release-assets.yml) /bin/cp "$MOCK_CHECKER_DIR/workflow.json" "$output" ;;
  */releases/5550) /bin/cp "$MOCK_CHECKER_DIR/release.json" "$output" ;;
  *'/actions/workflows/309911276/runs?'*) /bin/cp "$MOCK_RUNS_JSON" "$output" ;;
  */actions/runs/29009699237/jobs?per_page=100) /bin/cp "$MOCK_CHECKER_DIR/jobs.json" "$output" ;;
  */actions/runs/29009699237/logs) /bin/cp "$MOCK_CHECKER_DIR/logs.zip" "$output" ;;
  */actions/runs/29009699237) /bin/cp "$MOCK_CHECKER_DIR/exact-run.json" "$output" ;;
  *) exit 101 ;;
esac
printf 200
MOCK
tag_check_mock="$tmp/tag-check-mock"
cat >"$tag_check_mock" <<'MOCK'
#!/bin/bash -p
set -euo pipefail
[[ ! -e "$(/usr/bin/dirname "$3")/curl-auth.conf" ]] || exit 103
"$MOCK_JQ_BIN" -n --arg tag "$1" --arg object "$MOCK_TAG_OBJECT" --arg commit "$2" '{tag:$tag,object_sha:$object,commit_sha:$commit}' >"$3"
MOCK
chmod +x "$checker_curl" "$tag_check_mock"
expect_failure "self-modifying frozen checker jq" env GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_swap" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
grep -Fq 'frozen jq bytes changed' "$tmp/failure.stderr" || fail "verifier checker did not report frozen jq byte replacement: $(/bin/cat "$tmp/failure.stderr")"
expect_failure "same-byte replacement of frozen checker jq" env GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_identity_swap" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
grep -Fq 'frozen jq identity changed' "$tmp/failure.stderr" || fail "verifier checker did not report frozen jq identity replacement: $(/bin/cat "$tmp/failure.stderr")"
expect_failure "production verifier checker tool override" env HOSTILE_TOOL_SENTINEL="$hostile_tool_sentinel" CURL_BIN="$override_tool" JQ_BIN="$override_tool" UNZIP_BIN="$override_tool" VERIFY_TAG_BIN="$override_tool" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
[[ ! -e "$hostile_tool_sentinel" ]] || fail "production verifier checker executed an override tool"
MOCK_CHECKER_DIR="$checker_dir" MOCK_RUNS_JSON="$checker_dir/runs.json" MOCK_TAG_OBJECT="$tag_object" MOCK_JQ_BIN="$jq_fixture" \
  HOSTILE_TOOL_SENTINEL="$hostile_tool_sentinel" PATH="$hostile_bin:$PATH" HOME="$hostile_home" BASH_ENV="$hostile_bash_env" ENV="$hostile_bash_env" CDPATH="$tmp" \
  UNZIP="-d$tmp/hostile-unzip-output" UNZIPOPT="-d$tmp/hostile-unzipopt-output" \
  GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_fixture" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token \
  ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id" >/dev/null
[[ ! -e "$hostile_tool_sentinel" && ! -e "$tmp/hostile-curl-output" && ! -e "$tmp/hostile-unzip-output" && ! -e "$tmp/hostile-unzipopt-output" ]] || fail "verifier checker used hostile PATH or tool configuration"
cp "$checker_dir/logs.zip" "$checker_dir/logs-good.zip"
printf 'GOPLACES_RELEASE_PROOF_V1 arch=x86_64 run_id=%s tag=%s tag_object=%s tag_commit=%s release_id=5550 default_sha=%s inventory_sha256=%064d\n' "$proof_run_id" "$tag" "$tag_object" "$commit" "$commit" 0 >"$checker_dir/x86_64.log"
rm -f "$checker_dir/logs.zip"
(cd "$checker_dir" && zip -q logs.zip arm64.log x86_64.log)
expect_failure "native proof inventory mismatch" env MOCK_CHECKER_DIR="$checker_dir" MOCK_RUNS_JSON="$checker_dir/runs.json" MOCK_TAG_OBJECT="$tag_object" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_fixture" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
mv "$checker_dir/logs-good.zip" "$checker_dir/logs.zip"
jq '.workflow_runs += [(.workflow_runs[0] | .id=29009699238 | .path=".github/workflows/release-assets.yml@main" | .created_at="2026-07-10T13:00:00Z")]' "$checker_dir/runs.json" >"$checker_dir/runs-hostile.json"
expect_failure "newer suffixed-path proof substitution" env MOCK_CHECKER_DIR="$checker_dir" MOCK_RUNS_JSON="$checker_dir/runs-hostile.json" MOCK_TAG_OBJECT="$tag_object" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_fixture" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
jq '.workflow_runs[0].workflow_id = 309911277' "$checker_dir/runs.json" >"$checker_dir/runs-wrong-workflow.json"
expect_failure "newest proof valid wrong workflow ID" env MOCK_CHECKER_DIR="$checker_dir" MOCK_RUNS_JSON="$checker_dir/runs-wrong-workflow.json" MOCK_TAG_OBJECT="$tag_object" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_fixture" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
jq '.workflow_runs[0].head_branch = "release"' "$checker_dir/runs.json" >"$checker_dir/runs-wrong-branch.json"
expect_failure "newest proof wrong protected branch" env MOCK_CHECKER_DIR="$checker_dir" MOCK_RUNS_JSON="$checker_dir/runs-wrong-branch.json" MOCK_TAG_OBJECT="$tag_object" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_fixture" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"
jq '.workflow_runs[0].head_sha = "3333333333333333333333333333333333333333"' "$checker_dir/runs.json" >"$checker_dir/runs-wrong-head.json"
expect_failure "newest proof wrong protected head SHA" env MOCK_CHECKER_DIR="$checker_dir" MOCK_RUNS_JSON="$checker_dir/runs-wrong-head.json" MOCK_TAG_OBJECT="$tag_object" MOCK_JQ_BIN="$jq_fixture" GOPLACES_RELEASE_TESTING=1 CURL_BIN="$checker_curl" JQ_BIN="$jq_fixture" UNZIP_BIN="$unzip_fixture" VERIFY_TAG_BIN="$tag_check_mock" GH_TOKEN=fixture_token ./scripts/check-release-verifier.sh "$tag" "$tag_object" "$commit" 5550 "$commit" "$proof_run_id"

printf '%s\n' 'release asset tests: hostile static, REST, signer, provenance, reproducibility, dispatch, and newest-proof checks passed'
