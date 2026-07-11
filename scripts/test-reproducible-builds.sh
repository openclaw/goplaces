#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "reproducible builds: $*" >&2
  exit 1
}

go_bin="${GO_BIN:-go}"
expected_go_version="go1.26.5"
version="${REPRO_VERSION:-0.0.0-repro}"
version_symbol="github.com/steipete/goplaces/internal/cli.Version"
snapshot_dir="${1:-}"

go_bin="$(command -v "$go_bin")" || die "go is required"
case "$go_bin" in
  /*) ;;
  *) go_bin="$(cd "$(dirname "$go_bin")" && pwd -P)/$(basename "$go_bin")" ;;
esac
clean_path="$(dirname "$go_bin"):/usr/bin:/bin:/usr/sbin:/sbin"
actual_go_version="$(/usr/bin/env -i PATH="$clean_path" HOME="$HOME" GOENV=off GOTOOLCHAIN=local GOWORK=off "$go_bin" env GOVERSION)"
[[ "$actual_go_version" == "$expected_go_version" ]] || die "requires $expected_go_version, found $actual_go_version"
if [[ -n "$snapshot_dir" ]]; then
  [[ -f "$snapshot_dir/metadata.json" && ! -L "$snapshot_dir/metadata.json" ]] || die "missing snapshot metadata: $snapshot_dir/metadata.json"
  [[ -f "$snapshot_dir/artifacts.json" && ! -L "$snapshot_dir/artifacts.json" ]] || die "missing snapshot manifest: $snapshot_dir/artifacts.json"
  version="$(jq -er '.version | select(type == "string" and length > 0)' "$snapshot_dir/metadata.json")" || die "invalid snapshot version"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?$ ]] || die "invalid reproducibility version: $version"

if [[ -n "${GOMODCACHE:-}" ]]; then
  [[ "$GOMODCACHE" == /* && -d "$GOMODCACHE" && ! -L "$GOMODCACHE" ]] ||
    die "GOMODCACHE must be an absolute, existing, non-symlink directory"
  module_cache="$(cd "$GOMODCACHE" && pwd -P)"
  [[ "$module_cache" == "$GOMODCACHE" ]] || die "GOMODCACHE must already be canonical"
else
  module_cache="$(/usr/bin/env -i PATH="$clean_path" HOME="$HOME" GOENV=off GOTOOLCHAIN=local GOWORK=off "$go_bin" env GOMODCACHE)"
fi
[[ -d "$module_cache" ]] || die "module cache is missing; run go mod download first"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-repro.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

build_once() {
  local pass="$1"
  local goos="$2"
  local goarch="$3"
  local suffix="$4"
  local cache="$scratch/cache-$pass"
  local home="$scratch/home-$pass"
  local tmp="$scratch/tmp-$pass"
  local output="$scratch/$pass/${goos}_${goarch}/goplaces$suffix"

  mkdir -p "$cache" "$home" "$tmp" "$(dirname "$output")"
  /usr/bin/env -i \
    PATH="$clean_path" \
    HOME="$home" \
    TMPDIR="$tmp" \
    LC_ALL=C \
    TZ=UTC \
    GOENV=off \
    GOWORK=off \
    GOFLAGS=-mod=readonly \
    GOCACHE="$cache" \
    GOMODCACHE="$module_cache" \
    GOPROXY=off \
    GOSUMDB=off \
    GOTOOLCHAIN=local \
    GOVCS='*:off' \
    GOTELEMETRY=off \
    CGO_ENABLED=0 \
    GOOS="$goos" \
    GOARCH="$goarch" \
    GOAMD64=v1 \
    GOARM64=v8.0 \
    "$go_bin" build \
      -trimpath \
      -ldflags "-s -w -X $version_symbol=$version" \
      -o "$output" \
      ./cmd/goplaces
}

compare_target() {
  local goos="$1"
  local goarch="$2"
  local suffix="$3"
  local build_id="$4"
  local first="$scratch/one/${goos}_${goarch}/goplaces$suffix"
  local second="$scratch/two/${goos}_${goarch}/goplaces$suffix"
  local snapshot_binary

  build_once one "$goos" "$goarch" "$suffix"
  build_once two "$goos" "$goarch" "$suffix"
  /usr/bin/cmp -s "$first" "$second" || die "binary differs across isolated builds: $goos/$goarch"
  if [[ -n "$snapshot_dir" ]]; then
    snapshot_binary="$(jq -er \
      --arg goos "$goos" \
      --arg goarch "$goarch" \
      --arg id "$build_id" \
      '[.[] | select(.type == "Binary" and .goos == $goos and .goarch == $goarch and (.extra.ID // "") == $id)]
       | if length == 1 then .[0].path else error("snapshot target mismatch") end' \
      "$snapshot_dir/artifacts.json")" || die "snapshot manifest target mismatch: $goos/$goarch"
    [[ -f "$snapshot_binary" && ! -L "$snapshot_binary" && -s "$snapshot_binary" ]] || die "invalid snapshot binary: $snapshot_binary"
    /usr/bin/cmp -s "$first" "$snapshot_binary" || die "snapshot does not match clean recipe rebuild: $goos/$goarch"
  fi

  /usr/bin/shasum -a 256 "$first"
}

compare_target darwin amd64 "" goplaces_darwin
compare_target darwin arm64 "" goplaces_darwin
compare_target linux amd64 "" goplaces
compare_target linux arm64 "" goplaces
compare_target windows amd64 .exe goplaces
compare_target windows arm64 .exe goplaces

echo "reproducible builds: exact six-target byte comparison passed"
