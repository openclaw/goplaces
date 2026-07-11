#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

die() {
  echo "release asset rebuild: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 SOURCE_DIR VERIFIED_DIR TAG INVENTORY_JSON" >&2
  exit 2
}

[[ $# -eq 4 ]] || usage

source_dir="${1%/}"
verified_dir="${2%/}"
tag="$3"
inventory="$4"
go_bin="${GO_BIN:-go}"
jq_bin="${JQ_BIN:-jq}"
testing="${GOPLACES_RELEASE_TESTING:-0}"
case "$testing" in
  0) git_bin=/usr/bin/git ;;
  1) git_bin="${GIT_BIN:-}" ;;
  *) die "GOPLACES_RELEASE_TESTING must be 0 or 1" ;;
esac

for token_name in GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN HOMEBREW_TAP_GITHUB_TOKEN; do
  if declare -p "$token_name" >/dev/null 2>&1; then
    die "$token_name must be absent during rebuild"
  fi
done
[[ -d "$source_dir" && ! -L "$source_dir" ]] || die "source directory must be a real directory"
[[ -d "$verified_dir" && ! -L "$verified_dir" ]] || die "verified directory must be a real directory"
[[ -f "$inventory" && ! -L "$inventory" ]] || die "inventory must be a regular file"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag"
command -v "$go_bin" >/dev/null 2>&1 || die "go is required"
[[ -x "$git_bin" ]] || die "trusted Git executable is required"
command -v "$jq_bin" >/dev/null 2>&1 || die "jq is required"
[[ "$($go_bin env GOVERSION)" == go1.26.5 ]] || die "rebuild requires Go 1.26.5"

source_dir="$(cd "$source_dir" && pwd -P)"
verified_dir="$(cd "$verified_dir" && pwd -P)"
safe_home="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-rebuild-git-home.XXXXXX")"
safe_git() {
  if [[ "$testing" == 1 ]]; then
    /usr/bin/env -i \
      PATH=/usr/bin:/bin:/usr/sbin:/sbin \
      HOME="$safe_home" \
      LC_ALL=C \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_CONFIG_SYSTEM=/dev/null \
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_NO_REPLACE_OBJECTS=1 \
      GIT_TERMINAL_PROMPT=0 \
      MOCK_SOURCE_HEAD="${MOCK_SOURCE_HEAD:-}" \
      MOCK_GIT_DIR="${MOCK_GIT_DIR:-}" \
      MOCK_TAG_OBJECT="${MOCK_TAG_OBJECT:-}" \
      MOCK_TAG_COMMIT="${MOCK_TAG_COMMIT:-}" \
      "$git_bin" "$@"
  else
    /usr/bin/env -i \
      PATH=/usr/bin:/bin:/usr/sbin:/sbin \
      HOME="$safe_home" \
      LC_ALL=C \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_CONFIG_SYSTEM=/dev/null \
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_NO_REPLACE_OBJECTS=1 \
      GIT_TERMINAL_PROMPT=0 \
      "$git_bin" "$@"
  fi
}
cleanup() { rm -rf "${scratch:-}" "$safe_home"; }
trap cleanup EXIT

git_dir="$(safe_git -C "$source_dir" rev-parse --absolute-git-dir 2>/dev/null)" || die "source is not a Git checkout"
[[ -d "$git_dir" && ! -L "$git_dir" ]] || die "source Git metadata must be a real directory"
if [[ "$testing" == 0 ]]; then
  [[ -d "${source_dir}/.git" && ! -L "${source_dir}/.git" ]] || die "source must own a real .git directory"
  source_top="$(safe_git -C "$source_dir" rev-parse --show-toplevel)" || die "could not resolve source checkout root"
  source_top="$(cd "$source_top" && pwd -P)"
  [[ "$source_top" == "$source_dir" ]] || die "source directory is not its own checkout root"
  if safe_git -C "$source_dir" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    die "source HEAD must be detached"
  fi
  while IFS= read -r config_name; do
    case "$config_name" in
      core.repositoryformatversion|core.filemode|core.bare|core.logallrefupdates|core.ignorecase|core.precomposeunicode|remote.origin.url|remote.origin.fetch) ;;
      *) die "source contains forbidden local Git config: $config_name" ;;
    esac
  done < <(safe_git -C "$source_dir" config --local --name-only --list)
  [[ "$(safe_git -C "$source_dir" config --local --get-all remote.origin.url || true)" == https://github.com/openclaw/goplaces.git ]] ||
    die "source origin is not the exact official remote"
  [[ "$(safe_git -C "$source_dir" config --local --get-all remote.origin.fetch || true)" == '+refs/heads/*:refs/remotes/origin/*' ]] ||
    die "source fetch configuration is not exact"
  [[ "$(safe_git -C "$source_dir" config --local --get core.bare)" == false ]] || die "source core.bare is not false"
fi
grafts="$(safe_git -C "$source_dir" rev-parse --git-path info/grafts)" || die "could not resolve Git graft path"
alternates="$(safe_git -C "$source_dir" rev-parse --git-path objects/info/alternates)" || die "could not resolve Git alternate path"
[[ "$grafts" == /* ]] || grafts="$source_dir/$grafts"
[[ "$alternates" == /* ]] || alternates="$source_dir/$alternates"
[[ "$grafts" == "$git_dir"/* && "$alternates" == "$git_dir"/* ]] || die "Git metadata path escaped its repository"
[[ ! -e "$grafts" && ! -L "$grafts" ]] || die "legacy Git grafts are forbidden"
[[ ! -e "$alternates" && ! -L "$alternates" ]] || die "alternate Git object stores are forbidden"
[[ -z "$(safe_git -C "$source_dir" for-each-ref --format='%(refname)' refs/replace/)" ]] || die "Git replacement refs are forbidden"
if safe_git -C "$source_dir" config --local --get-regexp \
  '^(url\..*\.insteadof|include(if\..*)?\.path|core\.sshcommand|gpg\.ssh\.program)$' >/dev/null 2>&1; then
  die "unsafe repository-local Git configuration is forbidden"
fi

source_head="$(safe_git -C "$source_dir" rev-parse HEAD)" || die "source is not a Git checkout"
[[ "$source_head" =~ ^[0-9a-f]{40}$ ]] || die "source HEAD is invalid"
[[ "${EXPECTED_TAG_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_TAG_COMMIT is required"
[[ "${EXPECTED_TAG_OBJECT:-}" =~ ^[0-9a-f]{40}$ ]] || die "EXPECTED_TAG_OBJECT is required"
[[ "$source_head" == "$EXPECTED_TAG_COMMIT" ]] || die "source HEAD differs from expected tag commit"
[[ "$(safe_git -C "$source_dir" rev-parse "refs/tags/$tag^{tag}")" == "$EXPECTED_TAG_OBJECT" ]] || die "source tag object differs from expected identity"
[[ "$(safe_git -C "$source_dir" rev-parse "refs/tags/$tag^{commit}")" == "$EXPECTED_TAG_COMMIT" ]] || die "source tag commit differs from expected identity"
[[ "$(safe_git -C "$source_dir" cat-file -t "$EXPECTED_TAG_OBJECT")" == tag ]] || die "expected tag object is not an annotated tag"
[[ -z "$(safe_git -C "$source_dir" status --porcelain --untracked-files=all)" ]] || die "source checkout is not clean"
"$jq_bin" -e --arg tag "$tag" '.schema == "goplaces-release-inventory-v1" and .tag == $tag' "$inventory" >/dev/null || die "inventory does not match tag"

go_path="$(command -v "$go_bin")"
[[ "$go_path" == /* && -x "$go_path" && ! -L "$go_path" ]] || die "Go must resolve to an absolute regular executable"
go_path="$(cd "$(dirname "$go_path")" && pwd -P)/$(basename "$go_path")"
module_cache="$($go_bin env GOMODCACHE)"
[[ -d "$module_cache" ]] || die "module cache is missing; run go mod download first"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-rebuild.XXXXXX")"
version="${tag#v}"
version_symbol="github.com/steipete/goplaces/internal/cli.Version"

build_once() {
  local pass="$1"
  local goos="$2"
  local goarch="$3"
  local suffix="$4"
  local output="$scratch/$pass/${goos}_${goarch}/goplaces$suffix"
  local cache="$scratch/cache-$pass-${goos}-${goarch}"
  local home="$scratch/home-$pass-${goos}-${goarch}"
  local tmp="$scratch/tmp-$pass-${goos}-${goarch}"
  mkdir -p "$(dirname "$output")" "$cache" "$home" "$tmp"
  (
    cd "$source_dir"
    /usr/bin/env -i \
      PATH=/usr/bin:/bin:/usr/sbin:/sbin \
      HOME="$home" \
      TMPDIR="$tmp" \
      LC_ALL=C \
      TZ=UTC \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_CONFIG_SYSTEM=/dev/null \
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_NO_REPLACE_OBJECTS=1 \
      GIT_TERMINAL_PROMPT=0 \
      GOENV=off \
      GOFLAGS=-mod=readonly \
      GOWORK=off \
      GOCACHE="$cache" \
      GOMODCACHE="$module_cache" \
      GOPROXY=off \
      GOSUMDB=off \
      GONOSUMDB='*' \
      GONOPROXY='*' \
      GOPRIVATE='*' \
      GOVCS='*:off' \
      GOTOOLCHAIN=local \
      GOTELEMETRY=off \
      CGO_ENABLED=0 \
      GOOS="$goos" \
      GOARCH="$goarch" \
      GOAMD64=v1 \
      GOARM64=v8.0 \
      "$go_path" build \
        -trimpath \
        -ldflags "-s -w -X $version_symbol=$version" \
        -o "$output" \
        ./cmd/goplaces
  )
}

compare_target() {
  local goos="$1"
  local goarch="$2"
  local suffix="$3"
  local released="$verified_dir/${goos}_${goarch}/goplaces$suffix"
  local first="$scratch/one/${goos}_${goarch}/goplaces$suffix"
  local second="$scratch/two/${goos}_${goarch}/goplaces$suffix"
  [[ -f "$released" && ! -L "$released" && -s "$released" ]] || die "verified release binary is missing: $goos/$goarch"
  build_once one "$goos" "$goarch" "$suffix"
  build_once two "$goos" "$goarch" "$suffix"
  /usr/bin/cmp -s "$first" "$second" || die "isolated rebuilds differ: $goos/$goarch"
  /usr/bin/cmp -s "$first" "$released" || die "release bytes differ from exact-tag rebuild: $goos/$goarch"
}

compare_target linux amd64 ""
compare_target linux arm64 ""
compare_target windows amd64 .exe
compare_target windows arm64 .exe

printf '%s\n' "rebuild verified exact non-Darwin release bytes from $source_head"
