#!/bin/bash -p
set -euo pipefail
set +vx
unset BASH_ENV ENV CDPATH

readonly git_bin=/usr/bin/git
readonly realpath_bin=/bin/realpath
readonly shasum_bin=/usr/bin/shasum
readonly stat_bin=/usr/bin/stat
readonly sed_bin=/usr/bin/sed
readonly grep_bin=/usr/bin/grep
readonly official_origin=https://github.com/openclaw/goplaces.git
readonly system_path=/usr/bin:/bin:/usr/sbin:/sbin
readonly expected_go_version=go1.26.5
readonly expected_goreleaser_version=2.16.0

die() {
  echo "release source recheck: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 pilot EXPECTED_MAIN TAG GORELEASER SHA ID GO SHA ID -- ARGS... | $0 draft EXPECTED_MAIN TAG TAG_OBJECT TAG_COMMIT GORELEASER SHA ID GO SHA ID -- ARGS..." >&2
  exit 2
}

for system_tool in "$git_bin" "$realpath_bin" "$shasum_bin" "$stat_bin" "$sed_bin" "$grep_bin"; do
  [[ -x "$system_tool" && ! -L "$system_tool" ]] || die "pinned system tool is unavailable: $system_tool"
done
[[ $# -ge 11 ]] || usage

mode="$1"
expected_main="$2"
tag="$3"
[[ "$expected_main" =~ ^[0-9a-f]{40}$ ]] || die "expected main must be a lowercase 40-character SHA"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "invalid release tag"
case "$mode" in
  pilot)
    [[ "${10:-}" == -- && $# -ge 11 ]] || usage
    goreleaser_bin="$4"
    expected_goreleaser_sha="$5"
    expected_goreleaser_identity="$6"
    go_bin="$7"
    expected_go_sha="$8"
    expected_go_identity="$9"
    shift 10
    ;;
  draft)
    [[ "$4" =~ ^[0-9a-f]{40}$ && "$5" =~ ^[0-9a-f]{40}$ && "${12:-}" == -- && $# -ge 13 ]] || usage
    expected_object="$4"
    expected_commit="$5"
    goreleaser_bin="$6"
    expected_goreleaser_sha="$7"
    expected_goreleaser_identity="$8"
    go_bin="$9"
    expected_go_sha="${10}"
    expected_go_identity="${11}"
    shift 12
    ;;
  *) usage ;;
esac
goreleaser_arguments=("$@")
[[ ${#goreleaser_arguments[@]} -gt 0 ]] || usage
[[ "$expected_goreleaser_sha" =~ ^[0-9a-f]{64}$ && "$expected_go_sha" =~ ^[0-9a-f]{64}$ ]] || die "producer executable digest is malformed"
[[ "$expected_goreleaser_identity" =~ ^[0-9]+:[0-9]+$ && "$expected_go_identity" =~ ^[0-9]+:[0-9]+$ ]] || die "producer executable identity is malformed"

canonical_executable() {
  local path="$1" label="$2" canonical
  [[ "$path" == /* ]] || die "$label path is not absolute"
  canonical="$($realpath_bin "$path")" || die "could not canonicalize $label"
  [[ "$canonical" == "$path" ]] || die "$label path is not canonical"
  [[ -f "$path" && ! -L "$path" && -x "$path" ]] || die "$label is not a regular nonsymlink executable"
}

executable_sha256() {
  local output digest
  output="$($shasum_bin -a 256 "$1")" || die "could not hash producer executable"
  digest="${output%% *}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || die "producer executable digest is malformed"
  printf '%s\n' "$digest"
}

executable_identity() {
  local identity
  identity="$($stat_bin -f '%d:%i' "$1")" || die "could not inspect producer executable identity"
  [[ "$identity" =~ ^[0-9]+:[0-9]+$ ]] || die "producer executable identity is malformed"
  printf '%s\n' "$identity"
}

recheck_executable() {
  local path="$1" expected_sha="$2" expected_identity="$3" label="$4"
  canonical_executable "$path" "$label"
  [[ "$(executable_sha256 "$path")" == "$expected_sha" ]] || die "$label bytes changed before execution"
  [[ "$(executable_identity "$path")" == "$expected_identity" ]] || die "$label identity changed before execution"
}

recheck_executable "$goreleaser_bin" "$expected_goreleaser_sha" "$expected_goreleaser_identity" GoReleaser
recheck_executable "$go_bin" "$expected_go_sha" "$expected_go_identity" Go
producer_bin="${go_bin%/*}"
[[ "${goreleaser_bin%/*}" == "$producer_bin" && -d "$producer_bin" && ! -L "$producer_bin" ]] || die "producer executables are not in one private directory"
[[ "$($realpath_bin "$producer_bin")" == "$producer_bin" ]] || die "producer executable directory is not canonical"
[[ "$($stat_bin -f '%Lp' "$producer_bin")" == 700 ]] || die "producer executable directory is not private"
[[ "$PATH" == "${producer_bin}:${system_path}" ]] || die "producer PATH is not the exact private tool directory plus system path"
[[ "${GOPLACES_OFFICIAL_RELEASE:-0}" == 1 ]] || die "official producer marker is absent"
for forbidden_name in \
  GOPLACES_RELEASE_TEST_MODE GOPLACES_RELEASE_TEST_TOOL_DIR \
  GORELEASER_CURRENT_TAG GORELEASER_PREVIOUS_TAG GORELEASER_EXPERIMENTAL GORELEASER_FORCE_TOKEN \
  MAC_RELEASE_OP_ITEM MAC_RELEASE_OP_ACCOUNT MAC_RELEASE_OP_VAULT MAC_RELEASE_OP_FIELDS \
  MAC_RELEASE_OP_USE_SERVICE_ACCOUNT MAC_RELEASE_OP_READ_PRIMARY MAC_RELEASE_OP_ENV_FILE MAC_RELEASE_OP_LOG_FILE \
  MAC_RELEASE_OP_TMUX_SOCKET MAC_RELEASE_OP_TMUX_SESSION MAC_RELEASE_OP_WAIT_SECONDS \
  MAC_RELEASE_CODESIGN_OP_ITEM MAC_RELEASE_CODESIGN_OP_ACCOUNT MAC_RELEASE_CODESIGN_OP_VAULT \
  MAC_RELEASE_CODESIGN_OP_PATH_FIELD MAC_RELEASE_CODESIGN_OP_PASSWORD_FIELD MAC_RELEASE_CODESIGN_OP_USE_SERVICE_ACCOUNT MAC_RELEASE_CODESIGN_OP_READ; do
  [[ -z "${!forbidden_name+x}" ]] || die "forbidden producer environment is present: $forbidden_name"
done
case "$mode" in
  pilot) [[ "${GOPLACES_PILOT_VERSION:-}" == "${tag#v}" ]] || die "pilot version marker is not exact" ;;
  draft) [[ -z "${GOPLACES_PILOT_VERSION+x}" ]] || die "draft inherited a pilot version marker" ;;
esac
case "$mode" in
  pilot)
    [[ ${#goreleaser_arguments[@]} == 6 && "${goreleaser_arguments[0]}" == release && "${goreleaser_arguments[1]}" == --snapshot &&
      "${goreleaser_arguments[2]}" == --clean && "${goreleaser_arguments[3]}" == --skip=publish &&
      "${goreleaser_arguments[4]}" == --config && "${goreleaser_arguments[5]}" == .goreleaser.yml ]] ||
      die "pilot GoReleaser arguments are not exact"
    ;;
  draft)
    notes="${goreleaser_arguments[5]:-}"
    [[ ${#goreleaser_arguments[@]} == 6 && "${goreleaser_arguments[0]}" == release && "${goreleaser_arguments[1]}" == --clean &&
      "${goreleaser_arguments[2]}" == --config && "${goreleaser_arguments[3]}" == .goreleaser.yml &&
      "${goreleaser_arguments[4]}" == --release-notes && "$notes" == /* && -f "$notes" && ! -L "$notes" ]] ||
      die "draft GoReleaser arguments are not exact"
    [[ "$($realpath_bin "$notes")" == "$notes" ]] || die "draft release notes path is not canonical"
    ;;
esac

[[ -d .git && ! -L .git ]] || die "fresh source Git directory is missing or a symlink"
top="$($git_bin -c core.hooksPath=/dev/null rev-parse --show-toplevel)" || die "fresh source is not a Git checkout"
[[ "$(cd "$top" && pwd -P)" == "$(pwd -P)" ]] || die "fresh source command is not running at the checkout root"

while IFS= read -r name; do
  case "$name" in
    core.repositoryformatversion|core.filemode|core.bare|core.logallrefupdates|core.ignorecase|core.precomposeunicode|remote.origin.url|remote.origin.fetch) ;;
    *) die "fresh source contains forbidden local Git config: $name" ;;
  esac
done < <($git_bin -c core.hooksPath=/dev/null config --local --name-only --list)

origin_values="$($git_bin -c core.hooksPath=/dev/null config --local --get-all remote.origin.url || true)"
[[ "$origin_values" == "$official_origin" ]] || die "fresh source local origin config is not exact"
fetch_values="$($git_bin -c core.hooksPath=/dev/null config --local --get-all remote.origin.fetch || true)"
[[ "$fetch_values" == '+refs/heads/*:refs/remotes/origin/*' ]] || die "fresh source local fetch config is not exact"
[[ "$($git_bin -c core.hooksPath=/dev/null config --local --get core.bare)" == false ]] || die "fresh source local core.bare is not false"

graft_path="$($git_bin -c core.hooksPath=/dev/null rev-parse --path-format=absolute --git-path info/grafts)" || die "could not resolve fresh source graft path"
git_dir="$($git_bin -c core.hooksPath=/dev/null rev-parse --absolute-git-dir)" || die "could not resolve fresh source Git directory"
alternates_path="$($git_bin -c core.hooksPath=/dev/null rev-parse --path-format=absolute --git-path objects/info/alternates)" || die "could not resolve fresh source alternates path"
[[ "$graft_path" == /* ]] || die "fresh source graft path is not absolute"
[[ "$git_dir" == /* && "$alternates_path" == /* ]] || die "fresh source Git metadata paths are not absolute"
[[ "$graft_path" == "$git_dir"/* && "$alternates_path" == "$git_dir"/* ]] || die "fresh source Git metadata path escaped"
[[ ! -e "$graft_path" && ! -L "$graft_path" ]] || die "fresh source contains forbidden legacy grafts"
[[ ! -e "$alternates_path" && ! -L "$alternates_path" ]] || die "fresh source contains forbidden alternate object stores"
replace_refs="$($git_bin -c core.hooksPath=/dev/null for-each-ref --format='%(refname)' refs/replace/)" || die "could not inspect fresh source replacement refs"
[[ -z "$replace_refs" ]] || die "fresh source contains forbidden replacement refs"

if $git_bin -c core.hooksPath=/dev/null symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  die "fresh source HEAD must be detached"
fi
head_sha="$($git_bin -c core.hooksPath=/dev/null rev-parse --verify HEAD)"
main_sha="$($git_bin -c core.hooksPath=/dev/null rev-parse --verify refs/remotes/origin/main)"
[[ "$head_sha" == "$expected_main" && "$main_sha" == "$expected_main" ]] || die "fresh source HEAD or protected-main snapshot moved"
status="$($git_bin -c core.hooksPath=/dev/null status --porcelain --untracked-files=all)"
[[ -z "$status" ]] || die "fresh source changed after release manifest loading"

case "$mode" in
  pilot)
    if $git_bin -c core.hooksPath=/dev/null show-ref --verify --quiet "refs/tags/${tag}"; then
      die "pilot tag unexpectedly exists in fresh source"
    fi
    ;;
  draft)
    [[ "$expected_object" =~ ^[0-9a-f]{40}$ && "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || die "draft tag identities must be lowercase 40-character SHAs"
    [[ "$expected_commit" == "$expected_main" ]] || die "draft tag commit differs from expected main"
    tag_object="$($git_bin -c core.hooksPath=/dev/null rev-parse --verify "refs/tags/${tag}^{tag}")" || die "fresh source draft tag is not annotated"
    tag_commit="$($git_bin -c core.hooksPath=/dev/null rev-parse --verify "refs/tags/${tag}^{commit}")" || die "fresh source draft tag does not peel to a commit"
    [[ "$tag_object" == "$expected_object" && "$tag_commit" == "$expected_commit" ]] || die "fresh source draft tag identity moved"
    payload_object="$($git_bin -c core.hooksPath=/dev/null cat-file -p "$tag_object" | $sed_bin -n 's/^object //p' | /usr/bin/head -n 1)"
    payload_type="$($git_bin -c core.hooksPath=/dev/null cat-file -p "$tag_object" | $sed_bin -n 's/^type //p' | /usr/bin/head -n 1)"
    payload_tag="$($git_bin -c core.hooksPath=/dev/null cat-file -p "$tag_object" | $sed_bin -n 's/^tag //p' | /usr/bin/head -n 1)"
    [[ "$payload_object" == "$expected_commit" && "$payload_type" == commit && "$payload_tag" == "$tag" ]] || die "fresh source draft tag payload moved"
    ;;
esac

go_version="$(/usr/bin/env -i PATH="$system_path" HOME="${HOME:-/tmp}" TMPDIR="${TMPDIR:-/tmp}" LC_ALL=C TZ=UTC GOENV=off GOTOOLCHAIN=local "$go_bin" env GOVERSION)" ||
  die "could not requery Go version"
[[ "$go_version" == "$expected_go_version" ]] || die "Go version changed before execution"
goreleaser_output="$(/usr/bin/env -i PATH="$system_path" HOME="${HOME:-/tmp}" TMPDIR="${TMPDIR:-/tmp}" LC_ALL=C TZ=UTC "$goreleaser_bin" --version 2>&1)" ||
  die "could not requery GoReleaser version"
goreleaser_version="$($sed_bin -n 's/^GitVersion:[[:space:]]*//p' <<<"$goreleaser_output")"
[[ "$($grep_bin -c '^GitVersion:' <<<"$goreleaser_output")" == 1 && "$goreleaser_version" == "$expected_goreleaser_version" ]] ||
  die "GoReleaser version changed before execution"
recheck_executable "$go_bin" "$expected_go_sha" "$expected_go_identity" Go
recheck_executable "$goreleaser_bin" "$expected_goreleaser_sha" "$expected_goreleaser_identity" GoReleaser

printf 'release source recheck: %s source accepted at %s\n' "$mode" "$expected_main"
export PATH="${producer_bin}:${system_path}"
exec "$goreleaser_bin" "${goreleaser_arguments[@]}"
