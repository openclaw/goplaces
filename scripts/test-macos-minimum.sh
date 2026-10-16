#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/goplaces-minimum.XXXXXX")
trap 'rm -rf "$work"' EXIT
printf 'package main\nfunc main() {}\n' >"$work/main.go"
for arch in amd64 arm64; do
  CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" go build -p 2 -o "$work/$arch" "$work/main.go"
  "$root/scripts/check-macos-minimum.sh" "$work/$arch" "$arch"
done
if "$root/scripts/check-macos-minimum.sh" "$work/amd64" arm64; then
  echo 'minimum gate accepted a mislabeled architecture' >&2; exit 1
fi
# Produce a real Mach-O with the wrong deployment target to prove rejection.
/usr/bin/xcrun vtool -set-build-version macos 14.0 14.0 -replace -output "$work/newer" "$work/arm64"
if "$root/scripts/check-macos-minimum.sh" "$work/newer" arm64; then
  echo 'minimum gate accepted macOS 14' >&2; exit 1
fi
echo 'macOS minimum gate tests passed'
