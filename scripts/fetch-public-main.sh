#!/bin/bash -p
set -euo pipefail
unset BASH_ENV ENV CDPATH

die() {
  echo "public main fetch: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || die "usage: $0 WORKSPACE"
workspace="$1"
[[ "$workspace" == /* && -d "$workspace" && ! -L "$workspace" ]] || die "workspace must be a real absolute directory"
workspace="$(cd "$workspace" && pwd -P)"
[[ -d "$workspace/.git" && ! -L "$workspace/.git" ]] || die "workspace must own a real Git directory"

testing="${GOPLACES_HYDRATE_FETCH_TESTING:-0}"
case "$testing" in
  0) git_bin=/usr/bin/git ;;
  1) git_bin="${GIT_BIN:-}" ;;
  *) die "invalid test mode" ;;
esac
[[ "$git_bin" == /* && -x "$git_bin" && ! -L "$git_bin" ]] || die "trusted Git executable is unavailable"

isolation_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
[[ "$isolation_parent" == /* && -d "$isolation_parent" && ! -L "$isolation_parent" ]] || die "temporary root is unsafe"
isolation="$(/usr/bin/mktemp -d "$isolation_parent/goplaces-public-fetch.XXXXXX")"
cleanup() { /bin/rm -rf "$isolation"; }
trap cleanup EXIT HUP INT TERM
/bin/mkdir -p "$isolation/home" "$isolation/tmp" "$isolation/xdg"
/bin/chmod 700 "$isolation/home" "$isolation/tmp" "$isolation/xdg"

safe_git() {
  /usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    HOME="$isolation/home" \
    XDG_CONFIG_HOME="$isolation/xdg" \
    TMPDIR="$isolation/tmp" \
    LC_ALL=C \
    TZ=UTC \
    GIT_CONFIG=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_NO_REPLACE_OBJECTS=1 \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/usr/bin/false \
    SSH_ASKPASS=/usr/bin/false \
    GIT_SSH_COMMAND=/usr/bin/false \
    GCM_INTERACTIVE=Never \
    "$git_bin" \
      -c core.hooksPath=/dev/null \
      -c credential.helper= \
      -c core.askPass=/usr/bin/false \
      -c credential.interactive=false \
      -c http.extraHeader= \
      "$@"
}

git_dir="$(safe_git -C "$workspace" rev-parse --absolute-git-dir 2>/dev/null)" || die "workspace is not a Git checkout"
[[ "$git_dir" == "$workspace/.git" ]] || die "workspace Git directory is not self-contained"
grafts="$(safe_git -C "$workspace" rev-parse --path-format=absolute --git-path info/grafts)" || die "could not resolve graft path"
alternates="$(safe_git -C "$workspace" rev-parse --path-format=absolute --git-path objects/info/alternates)" || die "could not resolve alternates path"
[[ "$grafts" == "$git_dir"/* && "$alternates" == "$git_dir"/* ]] || die "Git metadata escaped the workspace"
[[ ! -e "$grafts" && ! -L "$grafts" ]] || die "legacy Git grafts are forbidden"
[[ ! -e "$alternates" && ! -L "$alternates" ]] || die "alternate Git object stores are forbidden"
[[ -z "$(safe_git -C "$workspace" for-each-ref --format='%(refname)' refs/replace/)" ]] || die "Git replacement refs are forbidden"

# Checkout credentials must already be removed before the hydrated workspace is exposed.
if /usr/bin/env -i \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  HOME="$isolation/home" \
  XDG_CONFIG_HOME="$isolation/xdg" \
  LC_ALL=C \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_CONFIG_SYSTEM=/dev/null \
  GIT_CONFIG_GLOBAL=/dev/null \
  /usr/bin/git -c core.hooksPath=/dev/null -C "$workspace" \
    config --local --no-includes --get-regexp \
    '^(credential\.|http\.|url\..*\.insteadof|include(if\..*)?\.path|core\.(askpass|sshcommand))' \
    >/dev/null 2>&1; then
  die "workspace contains credential or transport indirection"
fi

safe_git -C "$workspace" fetch \
  --no-tags \
  --depth=50 \
  https://github.com/openclaw/goplaces.git \
  '+refs/heads/main:refs/remotes/origin/main'
