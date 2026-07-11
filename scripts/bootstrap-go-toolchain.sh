#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Go toolchain bootstrap: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 DEST_DIR" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage

destination="$1"
testing="${GOPLACES_RELEASE_TESTING:-0}"
case "$testing" in
  0)
    curl_bin=/usr/bin/curl
    tar_bin=/usr/bin/tar
    shasum_bin=/usr/bin/shasum
    uname_bin=/usr/bin/uname
    ;;
  1)
    curl_bin="${CURL_BIN:-}"
    tar_bin="${TAR_BIN:-/usr/bin/tar}"
    shasum_bin="${SHASUM_BIN:-/usr/bin/shasum}"
    uname_bin="${UNAME_BIN:-/usr/bin/uname}"
    ;;
  *) die "GOPLACES_RELEASE_TESTING must be 0 or 1" ;;
esac

[[ -x "$curl_bin" ]] || die "trusted curl executable is required"
[[ -x "$tar_bin" ]] || die "trusted tar executable is required"
[[ -x "$shasum_bin" ]] || die "trusted shasum executable is required"
[[ -x "$uname_bin" ]] || die "trusted uname executable is required"
[[ ! -e "$destination" && ! -L "$destination" ]] || die "destination already exists"
parent="$(dirname "$destination")"
[[ -d "$parent" && ! -L "$parent" ]] || die "destination parent must be a real directory"
parent="$(cd "$parent" && pwd -P)"
destination="$parent/$(basename "$destination")"

case "$($uname_bin -m)" in
  arm64)
    archive_name=go1.26.5.darwin-arm64.tar.gz
    expected_size=64738542
    expected_sha256=efb87ff28af9a188d0536ef5d42e63dd52ba8263cd7344a993cc48dd11dedb6a
    ;;
  x86_64)
    archive_name=go1.26.5.darwin-amd64.tar.gz
    expected_size=67836304
    expected_sha256=6231d8d3b8f5552ec6cbf6d685bdd5482e1e703214b120e89b3bf0d7bf1ef725
    ;;
  *) die "unsupported macOS architecture" ;;
esac
archive_url="https://dl.google.com/go/$archive_name"

if [[ "$testing" == 1 ]]; then
  archive_url="${EXPECTED_ARCHIVE_URL:-$archive_url}"
  expected_size="${EXPECTED_ARCHIVE_SIZE:-$expected_size}"
  expected_sha256="${EXPECTED_ARCHIVE_SHA256:-$expected_sha256}"
fi
[[ "$archive_url" == https://dl.google.com/go/go1.26.5.darwin-*.tar.gz ]] || die "unexpected toolchain URL"
[[ "$expected_size" =~ ^[1-9][0-9]*$ ]] || die "invalid pinned archive size"
[[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || die "invalid pinned archive digest"

scratch="$(mktemp -d "$parent/.goplaces-go.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
archive="$scratch/$archive_name"
status="$($curl_bin \
  --disable \
  --silent --show-error \
  --retry 3 \
  --proto '=https' \
  --tlsv1.2 \
  --output "$archive" \
  --write-out '%{http_code}' \
  "$archive_url")" || die "toolchain download failed"
[[ "$status" == 200 ]] || die "toolchain download returned HTTP $status"
[[ "$(wc -c < "$archive" | tr -d '[:space:]')" == "$expected_size" ]] || die "toolchain archive size mismatch"
[[ "$($shasum_bin -a 256 "$archive" | awk '{print $1}')" == "$expected_sha256" ]] || die "toolchain archive digest mismatch"

members="$scratch/members.txt"
$tar_bin -tzf "$archive" > "$members" || die "toolchain archive listing failed"
[[ -s "$members" ]] || die "toolchain archive is empty"
while IFS= read -r member; do
  [[ "$member" == go || "$member" == go/* ]] || die "toolchain archive has an unexpected root"
  [[ "$member" != /* && "$member" != *'/../'* && "$member" != '../'* && "$member" != *'/..' ]] ||
    die "toolchain archive has an unsafe path"
done < "$members"

mkdir "$destination"
$tar_bin -xzf "$archive" -C "$destination" --no-same-owner || die "toolchain extraction failed"
go_root="$destination/go"
[[ -d "$go_root" && ! -L "$go_root" ]] || die "toolchain root is invalid"
[[ -f "$go_root/bin/go" && ! -L "$go_root/bin/go" && -x "$go_root/bin/go" ]] || die "toolchain Go executable is invalid"
[[ "$(GOENV=off GOTOOLCHAIN=local GOWORK=off GOTELEMETRY=off "$go_root/bin/go" env GOVERSION)" == go1.26.5 ]] ||
  die "extracted toolchain version mismatch"

rm -f "$archive" "$members"
trap - EXIT
printf '%s\n' "$go_root"
