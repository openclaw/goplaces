#!/usr/bin/env bash
set -euo pipefail

binary=${1:?binary path required}
architecture=${2:?architecture required}
case "$architecture" in
  amd64) expected_arch=x86_64 ;;
  arm64) expected_arch=arm64 ;;
  *) echo "unsupported Darwin architecture: $architecture" >&2; exit 1 ;;
esac
[[ -f "$binary" && ! -L "$binary" ]] || exit 1
[[ "$(/usr/bin/lipo -archs "$binary")" == "$expected_arch" ]] || {
  echo "expected thin $expected_arch binary: $binary" >&2
  exit 1
}
# Check the actual load command, not an SDK/build-environment preference.
/usr/bin/otool -l "$binary" | /usr/bin/awk '
  $1 == "cmd" { build = ($2 == "LC_BUILD_VERSION"); if (build) count++ }
  build && $1 == "platform" { if ($2 == 1 || $2 == "macos") platforms++ }
  build && $1 == "minos" { if ($2 == "13.0" || $2 == "13.0.0") minimums++ }
  END { exit !(count == 1 && platforms == 1 && minimums == 1) }
' || { echo "expected LC_BUILD_VERSION macOS minos 13.0: $binary" >&2; exit 1; }
echo "verified $expected_arch macOS minimum 13.0: $binary"
