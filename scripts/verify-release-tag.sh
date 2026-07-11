#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

die() {
  echo "release tag verification: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 TAG EXPECTED_MAIN_SHA [OUT_JSON]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage

tag="$1"
expected_main="$2"
out_json="${3:-}"
jq_bin="${JQ_BIN:-jq}"
testing="${GOPLACES_RELEASE_TESTING:-0}"
case "$testing" in
  0)
    git_bin=/usr/bin/git
    ssh_keygen_bin=/usr/bin/ssh-keygen
    ;;
  1)
    git_bin="${GIT_BIN:-}"
    ssh_keygen_bin="${SSH_KEYGEN_BIN:-/usr/bin/ssh-keygen}"
    ;;
  *) die "GOPLACES_RELEASE_TESTING must be 0 or 1" ;;
esac

[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag: $tag"
[[ "$expected_main" =~ ^[0-9a-f]{40}$ ]] || die "expected main commit must be a lowercase 40-character SHA"
[[ -x "$git_bin" ]] || die "trusted Git executable is required"
command -v "$jq_bin" >/dev/null 2>&1 || die "jq is required"
[[ -x "$ssh_keygen_bin" ]] || die "trusted ssh-keygen executable is required"

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$script_root"
safe_home="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-git-home.XXXXXX")"
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
      MOCK_REPO_ROOT="${MOCK_REPO_ROOT:-}" \
      MOCK_GIT_DIR="${MOCK_GIT_DIR:-}" \
      MOCK_TAG_OBJECT="${MOCK_TAG_OBJECT:-}" \
      MOCK_TAG_COMMIT="${MOCK_TAG_COMMIT:-}" \
      MOCK_TAG="${MOCK_TAG:-}" \
      MOCK_LS_COUNT="${MOCK_LS_COUNT:-}" \
      MOCK_MOVE_TAG="${MOCK_MOVE_TAG:-0}" \
      MOCK_BAD_SIGNER="${MOCK_BAD_SIGNER:-0}" \
      MOCK_REPLACE_REF="${MOCK_REPLACE_REF:-0}" \
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
      "$git_bin" \
        -c core.hooksPath=/dev/null \
        -c commit.gpgSign=false \
        -c tag.gpgSign=false \
        -c tag.forceSignAnnotated=false \
        "$@"
  fi
}

repo_root="$(safe_git rev-parse --show-toplevel 2>/dev/null)" || die "not in a Git checkout"
cd "$repo_root"

git_dir="$(safe_git rev-parse --absolute-git-dir 2>/dev/null)" || die "could not locate Git metadata"
[[ -d "$git_dir" && ! -L "$git_dir" ]] || die "Git metadata must be a real directory"
grafts="$(safe_git rev-parse --git-path info/grafts)" || die "could not resolve Git graft path"
alternates="$(safe_git rev-parse --git-path objects/info/alternates)" || die "could not resolve Git alternate path"
[[ "$grafts" == /* ]] || grafts="$repo_root/$grafts"
[[ "$alternates" == /* ]] || alternates="$repo_root/$alternates"
[[ "$grafts" == "$git_dir"/* && "$alternates" == "$git_dir"/* ]] || die "Git metadata path escaped its repository"
[[ ! -e "$grafts" && ! -L "$grafts" ]] || die "legacy Git grafts are forbidden"
[[ ! -e "$alternates" && ! -L "$alternates" ]] || die "alternate Git object stores are forbidden"
[[ -z "$(safe_git for-each-ref --format='%(refname)' refs/replace/)" ]] || die "Git replacement refs are forbidden"
if safe_git config --local --get-regexp '^(url\..*\.insteadof|include(if\..*)?\.path|core\.sshcommand|gpg\.ssh\.program)$' >/dev/null 2>&1; then
  die "unsafe repository-local Git configuration is forbidden"
fi

remote_url="$(safe_git remote get-url origin 2>/dev/null)" || die "origin is missing"
case "$remote_url" in
  https://github.com/openclaw/goplaces|https://github.com/openclaw/goplaces.git) ;;
  *) die "origin is not the official openclaw/goplaces repository" ;;
esac

policy=.github/release-allowed-signers
expected_policy='steipete@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII9XsaCcr8TInPnHcuTVfvXXcsoUFrOE7menfbEIHFW9'
expected_principal='steipete@gmail.com'
expected_fingerprint='SHA256:WmI9lVtd7F2c5XyRHbZVO3yYYJzwsSNzcZQMPT147HI'
[[ -f "$policy" && ! -L "$policy" ]] || die "missing regular signer policy: $policy"
protected_policy="$(mktemp "${TMPDIR:-/tmp}/goplaces-signers.XXXXXX")"
tag_payload="$(mktemp "${TMPDIR:-/tmp}/goplaces-tag-payload.XXXXXX")"
cleanup_ref="refs/goplaces-release-verify/$tag"
cleanup() {
  rm -f "$protected_policy" "$tag_payload"
  safe_git update-ref -d "$cleanup_ref" >/dev/null 2>&1 || true
  rm -rf "$safe_home"
}
trap cleanup EXIT

safe_git show "$expected_main:$policy" > "$protected_policy" 2>/dev/null || die "signer policy is absent from expected main"
/usr/bin/cmp -s "$policy" "$protected_policy" || die "working signer policy differs from expected main"
[[ "$(cat "$policy")" == "$expected_policy" ]] || die "signer policy does not match the repository-pinned signer"

signer_count="$(awk 'NF && $1 !~ /^#/ {count++} END {print count + 0}' "$policy")"
[[ "$signer_count" -eq 1 ]] || die "signer policy must contain exactly one signer"
signer_line="$(awk 'NF && $1 !~ /^#/ {print}' "$policy")"
read -r signer_principal key_type key_material trailing <<<"$signer_line"
[[ -n "$signer_principal" && -n "$key_type" && -n "$key_material" && -z "${trailing:-}" ]] || die "invalid signer policy line"
[[ "$signer_principal" != *','* && "$signer_principal" != *'*'* ]] || die "signer principal must be exact"
[[ "$signer_principal" == "$expected_principal" ]] || die "signer principal is not pinned"
[[ "$key_type" == ssh-* || "$key_type" == ecdsa-* || "$key_type" == sk-* ]] || die "unsupported signer key type"
policy_fingerprint="$($ssh_keygen_bin -lf "$policy" 2>/dev/null | awk 'NR == 1 {print $2}')"
[[ "$policy_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]+$ ]] || die "could not fingerprint signer policy"
[[ "$policy_fingerprint" == "$expected_fingerprint" ]] || die "signer key fingerprint is not pinned"

remote_refs="$(safe_git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")" || die "could not read remote tag"
tag_object="$(awk -v ref="refs/tags/$tag" '$2 == ref {print $1}' <<<"$remote_refs")"
tag_commit="$(awk -v ref="refs/tags/$tag^{}" '$2 == ref {print $1}' <<<"$remote_refs")"
[[ "$tag_object" =~ ^[0-9a-f]{40}$ && "$tag_commit" =~ ^[0-9a-f]{40}$ ]] || die "remote tag must be annotated and peel to a commit"
[[ "$(awk 'NF {count++} END {print count + 0}' <<<"$remote_refs")" -eq 2 ]] || die "remote tag lookup returned an ambiguous ref set"
[[ "$tag_commit" == "$expected_main" ]] || die "tag commit does not equal expected main"

safe_git fetch --quiet --force --no-tags origin "refs/tags/$tag:$cleanup_ref" || die "could not fetch remote tag object"
local_object="$(safe_git rev-parse "$cleanup_ref^{tag}" 2>/dev/null)" || die "fetched ref is not an annotated tag"
local_commit="$(safe_git rev-parse "$cleanup_ref^{commit}" 2>/dev/null)" || die "fetched tag does not peel to a commit"
[[ "$local_object" == "$tag_object" && "$local_commit" == "$tag_commit" ]] || die "fetched tag identity differs from remote refs"
[[ "$(safe_git cat-file -t "$tag_object")" == tag ]] || die "remote tag object is not a tag"
safe_git cat-file -p "$tag_object" > "$tag_payload" || die "could not read tag payload"
[[ "$(sed -n '1p' "$tag_payload")" == "object $tag_commit" ]] || die "tag payload points at the wrong object"
[[ "$(sed -n '2p' "$tag_payload")" == 'type commit' ]] || die "tag payload has the wrong object type"
[[ "$(sed -n '3p' "$tag_payload")" == "tag $tag" ]] || die "tag payload name does not match its ref"
[[ "$(sed -n '4p' "$tag_payload")" == tagger\ * ]] || die "tag payload has no exact tagger header"
[[ -z "$(sed -n '5p' "$tag_payload")" ]] || die "tag payload headers are ambiguous"
[[ "$(grep -Fc "object $tag_commit" "$tag_payload")" -eq 1 ]] || die "tag payload object header is ambiguous"
[[ "$(grep -Fc "tag $tag" "$tag_payload")" -eq 1 ]] || die "tag payload name header is ambiguous"
grep -Fq -- '-----BEGIN SSH SIGNATURE-----' "$tag_payload" || die "tag is not SSH-signed"

verify_output="$(
  safe_git \
    -c gpg.format=ssh \
    -c "gpg.ssh.program=$ssh_keygen_bin" \
    -c "gpg.ssh.allowedSignersFile=$repo_root/$policy" \
    verify-tag --raw "$tag_object" 2>&1
)" || die "tag signature is not allowed"
grep -Fq "Good \"git\" signature for $signer_principal" <<<"$verify_output" || die "verified signer principal does not match policy"
grep -Fq "$policy_fingerprint" <<<"$verify_output" || die "verified signer key does not match policy"

final_refs="$(safe_git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")" || die "could not re-read remote tag"
[[ "$final_refs" == "$remote_refs" ]] || die "remote tag moved during verification"

result="$($jq_bin -cn \
  --arg tag "$tag" \
  --arg object_sha "$tag_object" \
  --arg commit_sha "$tag_commit" \
  --arg signer "$signer_principal" \
  --arg fingerprint "$policy_fingerprint" \
  '{tag:$tag,object_sha:$object_sha,commit_sha:$commit_sha,signer:$signer,signer_fingerprint:$fingerprint}')"

if [[ -n "$out_json" ]]; then
  [[ ! -L "$out_json" ]] || die "output path is a symlink"
  out_parent="$(dirname "$out_json")"
  [[ -d "$out_parent" ]] || die "output parent does not exist"
  tmp_out="$(mktemp "$out_parent/.tag-record.XXXXXX")"
  printf '%s\n' "$result" > "$tmp_out"
  mv "$tmp_out" "$out_json"
else
  printf '%s\n' "$result"
fi
