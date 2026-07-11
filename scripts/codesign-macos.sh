#!/bin/bash
set -euo pipefail
set +vx
export LC_ALL=C

EXPECTED_IDENTIFIER='org.openclaw.goplaces'
EXPECTED_TEAM='FWJYW4S8P8'
EXPECTED_AUTHORITY='Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)'
EXPECTED_DESIGNATED_REQUIREMENT='identifier "org.openclaw.goplaces" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = FWJYW4S8P8'

die() {
  echo "codesign-macos: $*" >&2
  exit 1
}

[[ "$#" -eq 2 ]] || die "usage: $0 <binary> <true|false>"
binary=$1
snapshot_build=$2

case "$snapshot_build" in
  true|false) ;;
  *) die "GoReleaser snapshot state must be true or false" ;;
esac

# Credential-free snapshots do not inspect signing state or invoke a platform
# tool. A non-snapshot release must opt in to the managed local producer before
# GoReleaser can reach its archive or publication pipes.
official_release=${GOPLACES_OFFICIAL_RELEASE-0}
case "$official_release" in
  0)
    [[ "$snapshot_build" == "true" ]] && exit 0
    die "refusing to produce unsigned Darwin assets for a non-snapshot release"
    ;;
  1) ;;
  *) die "GOPLACES_OFFICIAL_RELEASE must be 0 or 1" ;;
esac

SYSTEM_PATH=/usr/bin:/bin:/usr/sbin:/sbin
PATH=$SYSTEM_PATH
export PATH
unset DEVELOPER_DIR SDKROOT TOOLCHAINS
unset xcrun_log xcrun_nocache xcrun_verbose

test_mode=${GOPLACES_RELEASE_TEST_MODE-}
test_tool_dir=${GOPLACES_RELEASE_TEST_TOOL_DIR-}
if [[ "$test_mode" == "goplaces-release-contract-test-v1" ]]; then
  [[ "$test_tool_dir" == /* && -d "$test_tool_dir" ]] ||
    die "test tool directory must be an absolute directory"
  CODESIGN_BIN="$test_tool_dir/codesign"
  DITTO_BIN="$test_tool_dir/ditto"
  HASH_BIN="$test_tool_dir/shasum"
  PLUTIL_BIN="$test_tool_dir/plutil"
  STAT_BIN="$test_tool_dir/stat"
  XCRUN_BIN="$test_tool_dir/xcrun"
else
  [[ -z "$test_mode" && -z "$test_tool_dir" ]] ||
    die "test tool overrides require the exact test marker"
  CODESIGN_BIN=/usr/bin/codesign
  DITTO_BIN=/usr/bin/ditto
  HASH_BIN=/usr/bin/shasum
  PLUTIL_BIN=/usr/bin/plutil
  STAT_BIN=/usr/bin/stat
  XCRUN_BIN=/usr/bin/xcrun
fi
for tool_path in \
  "$CODESIGN_BIN" "$DITTO_BIN" "$HASH_BIN" \
  "$PLUTIL_BIN" "$STAT_BIN" "$XCRUN_BIN"; do
  [[ -x "$tool_path" ]] || die "required system tool is unavailable: $tool_path"
done

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "official signing requires macOS"
[[ ! -L "$binary" && -f "$binary" && -x "$binary" ]] ||
  die "binary must be a regular executable, not a symlink: $binary"
[[ "${CODESIGN_IDENTITY:-}" == "$EXPECTED_AUTHORITY" ]] ||
  die "release-mac-app did not provide the frozen signing identity"
[[ "${MAC_RELEASE_CODESIGN_KEYCHAIN_MANAGED:-0}" == "1" ]] ||
  die "release-mac-app managed-keychain marker is missing"
[[ -n "${CODESIGN_KEYCHAIN:-}" && -n "${MAC_RELEASE_CODESIGN_KEYCHAIN:-}" ]] ||
  die "release-mac-app managed keychain markers are missing"
[[ "$CODESIGN_KEYCHAIN" == "$MAC_RELEASE_CODESIGN_KEYCHAIN" ]] ||
  die "release-mac-app managed keychain markers disagree"
[[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]] ||
  die "NOTARYTOOL_KEYCHAIN_PROFILE is required for official signing"

binary_dir=$(cd "$(dirname "$binary")" && pwd -P)
binary="$binary_dir/$(basename "$binary")"
original_hash=$("$HASH_BIN" -a 256 "$binary")
original_hash=${original_hash%% *}
original_mode=$("$STAT_BIN" -f '%Lp' "$binary")

work_dir=$(mktemp -d "$binary_dir/.goplaces-sign.XXXXXX")
candidate="$work_dir/$(basename "$binary")"
notary_zip="$work_dir/goplaces-notary.zip"
notary_result="$work_dir/notary-result.json"
requirements_file="$work_dir/designated-requirements.txt"

cleanup() {
  rc=$?
  set +e
  rm -rf "$work_dir"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

cp -p "$binary" "$candidate"
printf 'designated => %s\n' "$EXPECTED_DESIGNATED_REQUIREMENT" >"$requirements_file"

"$CODESIGN_BIN" --force \
  --keychain "$CODESIGN_KEYCHAIN" \
  --sign "$EXPECTED_AUTHORITY" \
  --identifier "$EXPECTED_IDENTIFIER" \
  --options runtime \
  --timestamp \
  --requirements "$requirements_file" \
  "$candidate"
signed_hash=$("$HASH_BIN" -a 256 "$candidate")
signed_hash=${signed_hash%% *}

"$DITTO_BIN" -c -k --sequesterRsrc --keepParent "$candidate" "$notary_zip"
"$XCRUN_BIN" notarytool submit "$notary_zip" \
  --no-s3-acceleration \
  --wait \
  --output-format json \
  --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" >"$notary_result"

notary_status=$("$PLUTIL_BIN" -extract status raw -o - "$notary_result" 2>/dev/null) ||
  die "notarytool response has no string status"
notary_id=$("$PLUTIL_BIN" -extract id raw -o - "$notary_result" 2>/dev/null) ||
  die "notarytool response has no string id"
[[ "$notary_status" == "Accepted" ]] ||
  die "notarytool did not accept the submission"
[[ "$notary_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] ||
  die "notarytool response has an invalid submission id"

rm -f "$notary_zip"
[[ ! -e "$notary_zip" ]] || die "ephemeral notarization archive was not removed"

"$CODESIGN_BIN" --verify --strict --verbose=4 \
  -R="$EXPECTED_DESIGNATED_REQUIREMENT" "$candidate"
signature_info=$("$CODESIGN_BIN" --display --verbose=4 "$candidate" 2>&1)
grep -Fx "Identifier=$EXPECTED_IDENTIFIER" <<<"$signature_info" >/dev/null ||
  die "signed candidate has the wrong identifier"
grep -Fx "TeamIdentifier=$EXPECTED_TEAM" <<<"$signature_info" >/dev/null ||
  die "signed candidate has the wrong Team ID"
first_authority=$(sed -n 's/^Authority=//p' <<<"$signature_info" | sed -n '1p')
[[ "$first_authority" == "$EXPECTED_AUTHORITY" ]] ||
  die "signed candidate has the wrong signing authority"
grep -Eq '^CodeDirectory .* flags=0x[[:xdigit:]]+\(runtime\)([[:space:]]|$)' <<<"$signature_info" ||
  die "signed candidate is missing hardened runtime"
grep -Eq '^Runtime Version=[0-9]+(\.[0-9]+)*$' <<<"$signature_info" ||
  die "signed candidate is missing runtime-version metadata"
grep -Eq '^Timestamp=.+$' <<<"$signature_info" ||
  die "signed candidate is missing a secure timestamp"
grep -Eq '^Timestamp=(none)?$' <<<"$signature_info" &&
  die "signed candidate has no secure timestamp"

requirement_info=$("$CODESIGN_BIN" --display --requirements - "$candidate" 2>&1)
actual_requirement=$(sed -n 's/^designated => //p' <<<"$requirement_info")
[[ "$actual_requirement" == "$EXPECTED_DESIGNATED_REQUIREMENT" ]] ||
  die "signed candidate has a noncanonical designated requirement"
"$CODESIGN_BIN" --verify --strict --verbose=4 --check-notarization \
  -R="notarized" "$candidate"

current_hash=$("$HASH_BIN" -a 256 "$binary")
current_hash=${current_hash%% *}
current_mode=$("$STAT_BIN" -f '%Lp' "$binary")
[[ "$current_hash" == "$original_hash" && "$current_mode" == "$original_mode" ]] ||
  die "original binary changed while notarization was in progress"

verified_hash=$("$HASH_BIN" -a 256 "$candidate")
verified_hash=${verified_hash%% *}
[[ "$verified_hash" == "$signed_hash" ]] ||
  die "signed candidate changed during notarization or verification"
mv -f "$candidate" "$binary"
promoted_hash=$("$HASH_BIN" -a 256 "$binary")
promoted_hash=${promoted_hash%% *}
[[ "$promoted_hash" == "$signed_hash" ]] || die "atomic promotion changed the signed binary"

rm -rf "$work_dir"
[[ ! -e "$work_dir" ]] || die "temporary signing directory was not removed"
trap - EXIT HUP INT TERM

printf 'signed and notarized %s (submission %s)\n' "$binary" "$notary_id"
