#!/usr/bin/env bash

# Run fixture Git without inherited configuration, hooks, templates, or signing.
test_fixture_git() {
  local isolation_root="$1"
  shift

  [[ "$isolation_root" == /* && -d "$isolation_root" && ! -L "$isolation_root" ]] || {
    echo "test fixture Git isolation root is unsafe" >&2
    return 2
  }

  local home="$isolation_root/home"
  local tmp="$isolation_root/tmp"
  local template="$isolation_root/template"
  local xdg="$isolation_root/xdg"
  /bin/mkdir -p "$home" "$tmp" "$template" "$xdg"
  [[ -d "$home" && ! -L "$home" && -d "$tmp" && ! -L "$tmp" && -d "$template" && ! -L "$template" && -d "$xdg" && ! -L "$xdg" ]] || {
    echo "test fixture Git isolation directories are unsafe" >&2
    return 2
  }
  /bin/chmod 700 "$home" "$tmp" "$template" "$xdg"

  /usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    HOME="$home" \
    XDG_CONFIG_HOME="$xdg" \
    TMPDIR="$tmp" \
    LC_ALL=C \
    TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_NO_REPLACE_OBJECTS=1 \
    GIT_TERMINAL_PROMPT=0 \
    /usr/bin/git \
      -c core.hooksPath=/dev/null \
      -c init.templateDir="$template" \
      -c commit.gpgSign=false \
      -c tag.gpgSign=false \
      -c tag.forceSignAnnotated=false \
      "$@"
}
