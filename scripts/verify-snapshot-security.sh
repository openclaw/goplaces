#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "snapshot security: $*" >&2
  exit 1
}

dist_dir="${1:-dist}"
dist_dir="${dist_dir%/}"
case "$dist_dir" in
  ./*) dist_dir="${dist_dir#./}" ;;
esac
[[ -n "$dist_dir" ]] || die "dist directory is empty"
[[ -d "$dist_dir" ]] || die "missing dist directory: $dist_dir"

manifest="$dist_dir/artifacts.json"
[[ -f "$manifest" && ! -L "$manifest" ]] || die "missing regular artifact manifest: $manifest"
metadata="$dist_dir/metadata.json"
[[ -f "$metadata" && ! -L "$metadata" ]] || die "missing regular release metadata: $metadata"
command -v jq >/dev/null 2>&1 || die "jq is required"

go_bin="${GO_BIN:-go}"
govulncheck_bin="${GOVULNCHECK_BIN:-}"
require_clean="${SNAPSHOT_REQUIRE_CLEAN:-0}"
[[ "$require_clean" == "0" || "$require_clean" == "1" ]] || die "SNAPSHOT_REQUIRE_CLEAN must be 0 or 1"
if [[ -z "$govulncheck_bin" ]]; then
  command -v "$go_bin" >/dev/null 2>&1 || die "go is required"
  govulncheck_bin="$($go_bin env GOPATH)/bin/govulncheck"
fi
[[ -x "$govulncheck_bin" ]] || die "govulncheck is not executable: $govulncheck_bin"
command -v "$go_bin" >/dev/null 2>&1 || die "go is required"

expected_commit="${SNAPSHOT_EXPECTED_COMMIT:-}"
if [[ -z "$expected_commit" ]]; then
  expected_commit="$(/usr/bin/git rev-parse HEAD 2>/dev/null)" || die "SNAPSHOT_EXPECTED_COMMIT is required outside a Git checkout"
fi
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || die "expected commit is not a full Git object ID: $expected_commit"
if [[ "$require_clean" == "1" ]]; then
  checkout_status="$(/usr/bin/git status --porcelain --untracked-files=all)" || die "could not inspect checkout status"
  [[ -z "$checkout_status" ]] || die "checkout changes present during clean snapshot verification"
fi

if ! jq -e --arg commit "$expected_commit" '
  type == "object"
  and .project_name == "goplaces"
  and .commit == $commit
  and (.version | type == "string" and length > 0)
' "$metadata" >/dev/null; then
  die "release metadata does not bind the snapshot to project goplaces at $expected_commit"
fi

expected="$({
  jq -cn --arg d "$dist_dir" '[
    {goos:"darwin", goarch:"amd64", target:"darwin_amd64_v1", name:"goplaces", id:"goplaces_darwin", path:($d + "/goplaces_darwin_darwin_amd64_v1/goplaces")},
    {goos:"darwin", goarch:"arm64", target:"darwin_arm64_v8.0", name:"goplaces", id:"goplaces_darwin", path:($d + "/goplaces_darwin_darwin_arm64_v8.0/goplaces")},
    {goos:"linux", goarch:"amd64", target:"linux_amd64_v1", name:"goplaces", id:"goplaces", path:($d + "/goplaces_linux_amd64_v1/goplaces")},
    {goos:"linux", goarch:"arm64", target:"linux_arm64_v8.0", name:"goplaces", id:"goplaces", path:($d + "/goplaces_linux_arm64_v8.0/goplaces")},
    {goos:"windows", goarch:"amd64", target:"windows_amd64_v1", name:"goplaces.exe", id:"goplaces", path:($d + "/goplaces_windows_amd64_v1/goplaces.exe")},
    {goos:"windows", goarch:"arm64", target:"windows_arm64_v8.0", name:"goplaces.exe", id:"goplaces", path:($d + "/goplaces_windows_arm64_v8.0/goplaces.exe")}
  ]'
})" || die "could not construct expected inventory"

if ! jq -e --arg d "$dist_dir" --argjson expected "$expected" '
  def normalized:
    {goos, goarch, target, name, id:(.extra.ID // ""), path};
  [.[] | select(.type == "Binary")] as $binaries
  | (($binaries | map(normalized) | sort_by(.target)) == ($expected | sort_by(.target)))
  and all($binaries[];
    (.path | type == "string")
    and (.path | startswith($d + "/"))
    and (.path | test("^[A-Za-z0-9_./-]+$")))
' "$manifest" >/dev/null; then
  die "artifact manifest does not contain exactly the six expected binaries"
fi

dist_abs="$(cd "$dist_dir" && pwd -P)"
scan_binary() {
  local binary="$1"
  local expected_goos="$2"
  local expected_goarch="$3"
  local parent_abs
  local binary_abs
  local build_info

  [[ -f "$binary" && ! -L "$binary" && -s "$binary" ]] || die "binary is missing, empty, or a symlink: $binary"
  parent_abs="$(cd "$(dirname "$binary")" && pwd -P)"
  binary_abs="$parent_abs/$(basename "$binary")"
  case "$binary_abs" in
    "$dist_abs"/*) ;;
    *) die "binary escapes dist directory: $binary" ;;
  esac

  build_info="$($go_bin version -m "$binary")" || die "could not read Go build information: $binary"
  printf '%s\n' "$build_info"
  grep -Eq ': go1\.26\.5$' <<<"$(printf '%s\n' "$build_info" | head -n 1)" || die "wrong Go toolchain in $binary"
  grep -Fqx $'\tpath\tgithub.com/steipete/goplaces/cmd/goplaces' <<<"$build_info" || die "wrong main package in $binary"
  grep -Fqx $'\tbuild\tCGO_ENABLED=0' <<<"$build_info" || die "CGO must be disabled in $binary"
  grep -Fqx $'\tbuild\tGOOS='"$expected_goos" <<<"$build_info" || die "wrong GOOS in $binary"
  grep -Fqx $'\tbuild\tGOARCH='"$expected_goarch" <<<"$build_info" || die "wrong GOARCH in $binary"
  grep -Fqx $'\tbuild\tvcs.revision='"$expected_commit" <<<"$build_info" || die "wrong VCS revision in $binary"
  grep -Eq $'^\tbuild\tvcs\.modified=(true|false)$' <<<"$build_info" || die "missing VCS state in $binary"
  if [[ "$require_clean" == "1" ]]; then
    grep -Fqx $'\tbuild\tvcs.modified=false' <<<"$build_info" || die "clean snapshot contains modified build provenance: $binary"
  fi
  "$govulncheck_bin" -db=https://vuln.go.dev -mode=binary "$binary"
}

scan_count=0
while IFS='|' read -r expected_goos expected_goarch binary; do
  scan_binary "$binary" "$expected_goos" "$expected_goarch"
  scan_count=$((scan_count + 1))
done < <(jq -r '.[] | select(.type == "Binary") | [.goos, .goarch, .path] | join("|")' "$manifest")
[[ "$scan_count" -eq 6 ]] || die "internal scan count mismatch: $scan_count"

echo "snapshot security: verified exact six-binary inventory and vulnerability scans"
