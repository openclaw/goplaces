#!/bin/bash
set -euo pipefail
set +vx
export LC_ALL=C

EXPECTED_IDENTIFIER='org.openclaw.goplaces'
EXPECTED_TEAM='FWJYW4S8P8'
EXPECTED_AUTHORITY='Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)'
EXPECTED_DESIGNATED_REQUIREMENT='identifier "org.openclaw.goplaces" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = FWJYW4S8P8'

die() {
  echo "verify-macos-binary: $*" >&2
  exit 1
}

# Verification and candidate execution happen after the bounded download step.
# Reject even empty credential variables so callers must prove absence, not
# merely avoid using their values.
[[ -z "${GH_TOKEN+x}" ]] || die "GH_TOKEN must be absent"
[[ -z "${GITHUB_TOKEN+x}" ]] || die "GITHUB_TOKEN must be absent"
[[ -z "${NOTARYTOOL_KEYCHAIN_PROFILE+x}" ]] ||
  die "NOTARYTOOL_KEYCHAIN_PROFILE must be absent"
[[ -z "${CODESIGN_IDENTITY+x}" ]] || die "CODESIGN_IDENTITY must be absent"
[[ -z "${CODESIGN_KEYCHAIN+x}" ]] || die "CODESIGN_KEYCHAIN must be absent"
[[ -z "${MAC_RELEASE_CODESIGN_KEYCHAIN+x}" ]] ||
  die "MAC_RELEASE_CODESIGN_KEYCHAIN must be absent"
[[ -z "${MAC_RELEASE_CODESIGN_KEYCHAIN_PASSWORD+x}" ]] ||
  die "MAC_RELEASE_CODESIGN_KEYCHAIN_PASSWORD must be absent"

[[ "$#" -eq 4 ]] ||
  die "usage: $0 <binary> <arm64|x86_64> <version> <static|execute>"
binary=$1
expected_arch=$2
expected_version=$3
mode=$4

case "$expected_arch" in
  arm64|x86_64) ;;
  *) die "expected architecture must be arm64 or x86_64" ;;
esac
[[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?$ ]] ||
  die "expected version must be an unprefixed release version"
case "$mode" in
  static|execute) ;;
  *) die "mode must be static or execute" ;;
esac

SYSTEM_PATH=/usr/bin:/bin:/usr/sbin:/sbin
PATH=$SYSTEM_PATH
export PATH

test_mode=${GOPLACES_RELEASE_TEST_MODE-}
test_tool_dir=${GOPLACES_RELEASE_TEST_TOOL_DIR-}
if [[ "$test_mode" == "goplaces-release-contract-test-v1" ]]; then
  [[ "$test_tool_dir" == /* && -d "$test_tool_dir" ]] ||
    die "test tool directory must be an absolute directory"
  CODESIGN_BIN="$test_tool_dir/codesign"
  HASH_BIN="$test_tool_dir/shasum"
  LIPO_BIN="$test_tool_dir/lipo"
else
  [[ -z "$test_mode" && -z "$test_tool_dir" ]] ||
    die "test tool overrides require the exact test marker"
  CODESIGN_BIN=/usr/bin/codesign
  HASH_BIN=/usr/bin/shasum
  LIPO_BIN=/usr/bin/lipo
fi
for tool_path in "$CODESIGN_BIN" "$HASH_BIN" "$LIPO_BIN"; do
  [[ -x "$tool_path" ]] || die "required system tool is unavailable: $tool_path"
done

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "macOS verification requires macOS"
[[ ! -L "$binary" && -f "$binary" && -x "$binary" ]] ||
  die "binary must be a regular executable, not a symlink: $binary"

binary_dir=$(cd "$(dirname "$binary")" && pwd -P)
binary="$binary_dir/$(basename "$binary")"
initial_hash=$("$HASH_BIN" -a 256 "$binary")
initial_hash=${initial_hash%% *}

actual_arch=$("$LIPO_BIN" -archs "$binary")
[[ "$actual_arch" == "$expected_arch" ]] ||
  die "expected thin $expected_arch binary, got: $actual_arch"

"$CODESIGN_BIN" --verify --strict --verbose=4 \
  -R="$EXPECTED_DESIGNATED_REQUIREMENT" "$binary"
signature_info=$("$CODESIGN_BIN" --display --verbose=4 "$binary" 2>&1)
grep -Fx "Identifier=$EXPECTED_IDENTIFIER" <<<"$signature_info" >/dev/null ||
  die "binary has the wrong identifier"
grep -Fx "TeamIdentifier=$EXPECTED_TEAM" <<<"$signature_info" >/dev/null ||
  die "binary has the wrong Team ID"
first_authority=$(sed -n 's/^Authority=//p' <<<"$signature_info" | sed -n '1p')
[[ "$first_authority" == "$EXPECTED_AUTHORITY" ]] ||
  die "binary has the wrong signing authority"
grep -Eq '^CodeDirectory .* flags=0x[[:xdigit:]]+\(runtime\)([[:space:]]|$)' <<<"$signature_info" ||
  die "binary is missing hardened runtime"
grep -Eq '^Runtime Version=[0-9]+(\.[0-9]+)*$' <<<"$signature_info" ||
  die "binary is missing runtime-version metadata"
grep -Eq '^Timestamp=.+$' <<<"$signature_info" ||
  die "binary is missing a secure timestamp"
grep -Eq '^Timestamp=(none)?$' <<<"$signature_info" &&
  die "binary has no secure timestamp"

requirement_info=$("$CODESIGN_BIN" --display --requirements - "$binary" 2>&1)
actual_requirement=$(sed -n 's/^designated => //p' <<<"$requirement_info")
[[ "$actual_requirement" == "$EXPECTED_DESIGNATED_REQUIREMENT" ]] ||
  die "binary has a noncanonical designated requirement"
"$CODESIGN_BIN" --verify --strict --verbose=4 --check-notarization \
  -R="notarized" "$binary"

verified_hash=$("$HASH_BIN" -a 256 "$binary")
verified_hash=${verified_hash%% *}
[[ "$verified_hash" == "$initial_hash" ]] ||
  die "binary changed during static verification"

if [[ "$mode" == "execute" ]]; then
  actual_version=$(/usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    LC_ALL=C \
    "$binary" --version)
  [[ "$actual_version" == "$expected_version" ]] ||
    die "binary reports version $actual_version, expected $expected_version"
  executed_hash=$("$HASH_BIN" -a 256 "$binary")
  executed_hash=${executed_hash%% *}
  [[ "$executed_hash" == "$initial_hash" ]] ||
    die "binary changed during candidate execution"
fi

printf 'verified macOS binary: arch=%s version=%s mode=%s\n' \
  "$expected_arch" "$expected_version" "$mode"
