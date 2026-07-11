#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

die() {
  echo "release record validation: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 RECORD TAG EXPECTED_COMMIT EXPECTED_STATE [BASELINE_RECORD]" >&2
  exit 2
}

[[ $# -ge 4 && $# -le 5 ]] || usage

record="$1"
tag="$2"
expected_commit="$3"
expected_state="$4"
baseline="${5:-}"
jq_bin="${JQ_BIN:-jq}"

[[ -f "$record" && ! -L "$record" ]] || die "record must be a regular file"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag"
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || die "expected commit must be a lowercase 40-character SHA"
[[ "$expected_state" == draft || "$expected_state" == published ]] || die "state must be draft or published"
command -v "$jq_bin" >/dev/null 2>&1 || die "jq is required"

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

if [[ "$expected_state" == draft ]]; then
  expected_draft=true
else
  expected_draft=false
fi

"$jq_bin" -e \
  --arg tag "$tag" \
  --arg commit "$expected_commit" \
  --arg state "$expected_state" \
  --argjson draft "$expected_draft" \
  --argjson expected "$expected_assets" '
    .schema == "goplaces-release-record-v1" and
    .repository == "openclaw/goplaces" and
    .state == $state and
    (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
    .tag_name == $tag and
    .name == $tag and
    .target_commitish == $commit and
    .draft == $draft and
    .prerelease == false and
    (.body | type == "string" and length > 0) and
    (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.updated_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (if $state == "published" then
       (.published_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
     else .published_at == null end) and
    (.assets | type == "array" and length == 7) and
    ([.assets[].name] | sort == $expected) and
    (([.assets[].name] | unique | length) == 7) and
    (([.assets[].id] | unique | length) == 7) and
    (all(.assets[];
      (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      (.size | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
      .state == "uploaded" and
      (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      .url == ("https://api.github.com/repos/openclaw/goplaces/releases/assets/" + (.id | tostring)) and
      (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.updated_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    ))
  ' "$record" >/dev/null || die "record violates the exact release contract"

if [[ -n "${EXPECTED_RELEASE_NOTES_FILE:-}" ]]; then
  notes_file="$EXPECTED_RELEASE_NOTES_FILE"
  [[ -f "$notes_file" && ! -L "$notes_file" ]] || die "release notes expectation is not a regular file"
  actual_notes="$(mktemp "${TMPDIR:-/tmp}/goplaces-release-notes.XXXXXX")"
  trap 'rm -f "$actual_notes"' EXIT
  "$jq_bin" -r '.body' "$record" > "$actual_notes"
  /usr/bin/cmp -s "$notes_file" "$actual_notes" || die "release notes do not match tagged changelog notes"
  rm -f "$actual_notes"
  trap - EXIT
fi

if [[ -n "$baseline" ]]; then
  [[ -f "$baseline" && ! -L "$baseline" ]] || die "baseline must be a regular file"
  current_identity="$(mktemp "${TMPDIR:-/tmp}/goplaces-record-current.XXXXXX")"
  baseline_identity="$(mktemp "${TMPDIR:-/tmp}/goplaces-record-baseline.XXXXXX")"
  cleanup() { rm -f "$current_identity" "$baseline_identity"; }
  trap cleanup EXIT
  "$jq_bin" -S '{schema,repository,id,tag_name,name,target_commitish,prerelease,body,created_at,assets}' "$record" > "$current_identity"
  "$jq_bin" -S '{schema,repository,id,tag_name,name,target_commitish,prerelease,body,created_at,assets}' "$baseline" > "$baseline_identity"
  /usr/bin/cmp -s "$baseline_identity" "$current_identity" || die "release or asset identity changed from frozen baseline"
  cleanup
  trap - EXIT
fi

printf '%s\n' "$($jq_bin -r '.id' "$record")"
