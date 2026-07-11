#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

die() {
  echo "release asset verification: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 ASSET_DIR TAG NATIVE_ARCH INVENTORY_JSON OUTPUT_DIR" >&2
  exit 2
}

[[ $# -eq 5 ]] || usage

asset_dir="${1%/}"
tag="$2"
native_arch="$3"
inventory="$4"
output_dir="$5"
jq_bin="${JQ_BIN:-jq}"
go_bin="${GO_BIN:-go}"
govulncheck_bin="${GOVULNCHECK_BIN:-}"
mac_verifier="${MAC_VERIFY_BIN:-./scripts/verify-macos-binary.sh}"

for token_name in GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN HOMEBREW_TAP_GITHUB_TOKEN; do
  if declare -p "$token_name" >/dev/null 2>&1; then
    die "$token_name must be absent during verification"
  fi
done
[[ -d "$asset_dir" && ! -L "$asset_dir" ]] || die "asset directory must be a real directory"
asset_dir="$(cd "$asset_dir" && pwd -P)"
[[ -f "$inventory" && ! -L "$inventory" ]] || die "inventory must be a regular file"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag"
[[ "$native_arch" == arm64 || "$native_arch" == x86_64 ]] || die "native architecture must be arm64 or x86_64"
[[ ! -e "$output_dir" && ! -L "$output_dir" ]] || die "output directory already exists"
command -v "$jq_bin" >/dev/null 2>&1 || die "jq is required"
command -v "$go_bin" >/dev/null 2>&1 || die "go is required"
[[ -x "$mac_verifier" ]] || die "macOS verifier is not executable"
if [[ -z "$govulncheck_bin" ]]; then
  govulncheck_bin="$($go_bin env GOPATH)/bin/govulncheck"
fi
[[ -x "$govulncheck_bin" ]] || die "pinned govulncheck is not executable"
[[ "$($go_bin env GOVERSION)" == go1.26.5 ]] || die "verification requires Go 1.26.5"
[[ "$(/usr/bin/uname -m)" == "$native_arch" ]] || die "runner architecture does not match native verifier job"

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

record="$asset_dir/release-record.json"
[[ -f "$record" && ! -L "$record" ]] || die "release record is missing"
record_digest="sha256:$(sha256_file "$record")"
version="${tag#v}"
expected_assets="$($jq_bin -cn --arg version "$version" '[
  "goplaces_\($version)_darwin_amd64.tar.gz",
  "goplaces_\($version)_darwin_arm64.tar.gz",
  "goplaces_\($version)_linux_amd64.tar.gz",
  "goplaces_\($version)_linux_arm64.tar.gz",
  "goplaces_\($version)_windows_amd64.zip",
  "goplaces_\($version)_windows_arm64.zip",
  "goplaces_checksums.txt"
] | sort')"
expected_members="$($jq_bin -cn --arg version "$version" '[
  {archive:("goplaces_"+$version+"_darwin_amd64.tar.gz"),os:"darwin",arch:"amd64",member:"goplaces"},
  {archive:("goplaces_"+$version+"_darwin_arm64.tar.gz"),os:"darwin",arch:"arm64",member:"goplaces"},
  {archive:("goplaces_"+$version+"_linux_amd64.tar.gz"),os:"linux",arch:"amd64",member:"goplaces"},
  {archive:("goplaces_"+$version+"_linux_arm64.tar.gz"),os:"linux",arch:"arm64",member:"goplaces"},
  {archive:("goplaces_"+$version+"_windows_amd64.zip"),os:"windows",arch:"amd64",member:"goplaces.exe"},
  {archive:("goplaces_"+$version+"_windows_arm64.zip"),os:"windows",arch:"arm64",member:"goplaces.exe"}
] | sort_by(.archive)')"
checksum_digest="sha256:$(sha256_file "$asset_dir/goplaces_checksums.txt")"
"$jq_bin" -e \
  --arg tag "$tag" \
  --arg record_digest "$record_digest" \
  --arg checksum_digest "$checksum_digest" \
  --argjson expected_assets "$expected_assets" \
  --argjson expected_members "$expected_members" \
  --slurpfile record "$record" '
    .schema == "goplaces-release-inventory-v1" and
    .tag == $tag and
    .release_id == $record[0].id and
    .state == $record[0].state and
    .release_record_digest == $record_digest and
    .checksum_digest == $checksum_digest and
    (.assets | type == "array" and length == 7) and
    ([.assets[].name] | sort == $expected_assets) and
    ((.assets | sort_by(.name)) == ($record[0].assets | sort_by(.name))) and
    (all(.assets[];
      (keys | sort == ["created_at","digest","id","name","size","state","updated_at","url"]) and
      (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      (.size | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      .state == "uploaded" and
      .url == ("https://api.github.com/repos/openclaw/goplaces/releases/assets/" + (.id | tostring))
    )) and
    (.members | type == "array" and length == 6) and
    (([.members[] | {archive,os,arch,member}] | sort_by(.archive)) == $expected_members) and
    (all(.members[];
      (keys | sort == ["arch","archive","member","member_digest","member_size","os"]) and
      (.member_size | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      (.member_digest | type == "string" and test("^sha256:[0-9a-f]{64}$"))
    ))
  ' "$inventory" >/dev/null || die "inventory identity or release record digest is invalid"

if find "$asset_dir" -mindepth 1 -type l -print -quit | grep -q .; then
  die "asset directory contains a symlink"
fi
if find "$asset_dir" -mindepth 1 -maxdepth 1 ! -type f -print -quit | grep -q .; then
  die "asset directory contains a non-file entry"
fi
[[ "$(find "$asset_dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d '[:space:]')" -eq 8 ]] ||
  die "asset directory must contain exactly seven assets and one release record"
while IFS=$'\t' read -r name expected_size expected_digest; do
  asset="$asset_dir/$name"
  [[ -f "$asset" && ! -L "$asset" ]] || die "inventory asset is missing: $name"
  [[ "$(wc -c < "$asset" | tr -d '[:space:]')" == "$expected_size" ]] || die "inventory asset size is wrong: $name"
  [[ "sha256:$(sha256_file "$asset")" == "$expected_digest" ]] || die "inventory asset digest is wrong: $name"
done < <("$jq_bin" -r '.assets[] | [.name,.size,.digest] | @tsv' "$inventory")

scratch_parent="$(dirname "$output_dir")"
[[ -d "$scratch_parent" && ! -L "$scratch_parent" ]] || die "output parent must be a real directory"
scratch="$(mktemp -d "$scratch_parent/.goplaces-verified.XXXXXX")"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

expected_tag_commit="${EXPECTED_TAG_COMMIT:-}"
[[ "$expected_tag_commit" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_TAG_COMMIT is required for build provenance"

verify_build_info() {
  local binary="$1"
  local expected_os="$2"
  local expected_arch="$3"
  local info="$scratch/build-info.txt"
  "$go_bin" version -m "$binary" > "$info" || die "could not read Go build info: $expected_os/$expected_arch"
  [[ "$(sed -n '1p' "$info")" == "$binary: go1.26.5" ]] || die "wrong Go toolchain: $expected_os/$expected_arch"
  grep -Fqx $'\tpath\tgithub.com/steipete/goplaces/cmd/goplaces' "$info" || die "wrong main package: $expected_os/$expected_arch"
  [[ "$(awk -F '\t' -v tag="$tag" '$2 == "mod" && $3 == "github.com/steipete/goplaces" && $4 == tag {count++} END {print count + 0}' "$info")" -eq 1 ]] ||
    die "wrong tagged module version: $expected_os/$expected_arch"
  grep -Fqx $'\tbuild\t-trimpath=true' "$info" || die "trimpath provenance is missing: $expected_os/$expected_arch"
  grep -Fqx $'\tbuild\tCGO_ENABLED=0' "$info" || die "CGO provenance is wrong: $expected_os/$expected_arch"
  grep -Fqx $'\tbuild\tGOOS='"$expected_os" "$info" || die "GOOS provenance is wrong: $expected_os/$expected_arch"
  grep -Fqx $'\tbuild\tGOARCH='"$expected_arch" "$info" || die "GOARCH provenance is wrong: $expected_os/$expected_arch"
  if [[ "$expected_arch" == amd64 ]]; then
    grep -Fqx $'\tbuild\tGOAMD64=v1' "$info" || die "GOAMD64 provenance is wrong: $expected_os/$expected_arch"
    ! grep -Fq $'\tbuild\tGOARM64=' "$info" || die "unexpected GOARM64 provenance: $expected_os/$expected_arch"
  else
    grep -Fqx $'\tbuild\tGOARM64=v8.0' "$info" || die "GOARM64 provenance is wrong: $expected_os/$expected_arch"
    ! grep -Fq $'\tbuild\tGOAMD64=' "$info" || die "unexpected GOAMD64 provenance: $expected_os/$expected_arch"
  fi
  grep -Fqx $'\tbuild\tvcs=git' "$info" || die "Git provenance is missing: $expected_os/$expected_arch"
  grep -Fqx $'\tbuild\tvcs.revision='"$expected_tag_commit" "$info" || die "Git revision provenance is wrong: $expected_os/$expected_arch"
  grep -Fqx $'\tbuild\tvcs.modified=false' "$info" || die "dirty-source provenance was accepted: $expected_os/$expected_arch"
  "$govulncheck_bin" -db=https://vuln.go.dev -mode=binary "$binary" >/dev/null || die "binary vulnerability scan failed: $expected_os/$expected_arch"
}

while IFS=$'\t' read -r archive os arch member expected_size expected_digest; do
  target_dir="$scratch/${os}_${arch}"
  mkdir -p "$target_dir"
  binary="$target_dir/$member"
  case "$archive" in
    *.tar.gz) /usr/bin/tar -xOzf "$asset_dir/$archive" "$member" > "$binary" || die "could not extract $archive" ;;
    *.zip) /usr/bin/unzip -p "$asset_dir/$archive" "$member" > "$binary" || die "could not extract $archive" ;;
    *) die "unsupported archive format: $archive" ;;
  esac
  [[ -s "$binary" ]] || die "archive member is empty: $archive"
  [[ "$(wc -c < "$binary" | tr -d '[:space:]')" == "$expected_size" ]] || die "archive member size changed after inventory freeze: $archive"
  [[ "sha256:$(sha256_file "$binary")" == "$expected_digest" ]] || die "archive member changed after inventory freeze: $archive"
  chmod 0555 "$binary"
  verify_build_info "$binary" "$os" "$arch"
done < <("$jq_bin" -r '.members[] | [.archive,.os,.arch,.member,.member_size,.member_digest] | @tsv' "$inventory")

"$mac_verifier" "$scratch/darwin_amd64/goplaces" x86_64 "$version" static
"$mac_verifier" "$scratch/darwin_arm64/goplaces" arm64 "$version" static

mv "$scratch" "$output_dir"
trap - EXIT
printf '%s\n' "$output_dir"
