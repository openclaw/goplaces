#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SIGN_SCRIPT="$ROOT/scripts/codesign-macos.sh"
VERIFY_SCRIPT="$ROOT/scripts/verify-macos-binary.sh"
AUTHORITY='Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)'
DESIGNATED_REQUIREMENT='identifier "org.openclaw.goplaces" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = FWJYW4S8P8'
EXPECTED_SIGNER='steipete@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII9XsaCcr8TInPnHcuTVfvXXcsoUFrOE7menfbEIHFW9'
EXPECTED_FINGERPRINT='SHA256:WmI9lVtd7F2c5XyRHbZVO3yYYJzwsSNzcZQMPT147HI'
TEST_MODE=goplaces-release-contract-test-v1

fail() {
  echo "test-codesign-macos: $*" >&2
  exit 1
}

tmp=$(mktemp -d /tmp/goplaces-codesign-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mock_bin="$tmp/mock-bin"
hostile_bin="$tmp/hostile-bin"
mkdir -p "$mock_bin" "$hostile_bin"
export MOCK_LOG="$tmp/events.log"
export MOCK_ZIP_PATH="$tmp/notary-zip-path"
export EXPECTED_DR="$DESIGNATED_REQUIREMENT"
export HOSTILE_TOOL_LOG="$tmp/hostile-tools.log"

cat >"$hostile_bin/hostile-tool" <<'MOCK'
#!/bin/bash
printf '%s\n' "$0" >>"$HOSTILE_TOOL_LOG"
exit 97
MOCK
chmod +x "$hostile_bin/hostile-tool"
for hostile_tool in codesign ditto jq lipo plutil shasum stat uname xcrun; do
  ln -s hostile-tool "$hostile_bin/$hostile_tool"
done

cat >"$mock_bin/codesign" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf 'codesign' >>"$MOCK_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$MOCK_LOG"
done
printf '\n' >>"$MOCK_LOG"

display=0
requirements=0
signing=0
online=0
last=
for arg in "$@"; do
  last=$arg
  case "$arg" in
    --display) display=1 ;;
    --requirements) requirements=1 ;;
    --sign) signing=1 ;;
    --check-notarization) online=1 ;;
  esac
done

if [[ "$signing" == "1" ]]; then
  [[ "${MOCK_SIGN_FAIL:-0}" != "1" ]] || exit 41
  printf '\n# MOCK-SIGNED\n' >>"$last"
  exit 0
fi

if [[ "$display" == "1" && "$requirements" == "1" ]]; then
  printf 'designated => %s\n' "${MOCK_DR:-$EXPECTED_DR}" >&2
  if [[ "${MOCK_EXTRA_DR:-0}" == "1" ]]; then
    printf 'designated => identifier "hostile.example"\n' >&2
  fi
  exit 0
fi

if [[ "$display" == "1" ]]; then
  first_authority=${MOCK_FIRST_AUTHORITY:-Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)}
  printf 'Identifier=%s\n' "${MOCK_IDENTIFIER:-org.openclaw.goplaces}" >&2
  printf 'CodeDirectory v=20500 size=123 flags=%s hashes=4+0 location=embedded\n' \
    "${MOCK_FLAGS:-0x10000(runtime)}" >&2
  printf 'Authority=%s\n' "$first_authority" >&2
  if [[ "$first_authority" != 'Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)' ]]; then
    printf 'Authority=Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)\n' >&2
  fi
  printf 'Authority=Developer ID Certification Authority\n' >&2
  printf 'TeamIdentifier=%s\n' "${MOCK_TEAM:-FWJYW4S8P8}" >&2
  if [[ "${MOCK_OMIT_RUNTIME_VERSION:-0}" != "1" ]]; then
    printf 'Runtime Version=%s\n' "${MOCK_RUNTIME_VERSION:-15.0.0}" >&2
  fi
  if [[ "${MOCK_OMIT_TIMESTAMP:-0}" != "1" ]]; then
    printf 'Timestamp=%s\n' "${MOCK_TIMESTAMP:-Jul 10, 2026 at 12:00:00}" >&2
  fi
  exit 0
fi

[[ "${MOCK_VERIFY_FAIL:-0}" != "1" ]] || exit 42
if [[ "$online" == "1" ]]; then
  [[ "${MOCK_ONLINE_FAIL:-0}" != "1" ]] || exit 43
  if [[ "${MOCK_MUTATE_VERIFY:-0}" == "1" ]]; then
    mutation_target=${MOCK_VERIFY_BINARY:-$last}
    printf '\n# MUTATED-DURING-VERIFY\n' >>"$mutation_target"
  fi
fi
MOCK

cat >"$mock_bin/ditto" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'ditto' >>"$MOCK_LOG"
previous=
penultimate=
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$MOCK_LOG"
  penultimate=$previous
  previous=$arg
done
printf '\n' >>"$MOCK_LOG"
cp "$penultimate" "$previous"
MOCK

cat >"$mock_bin/xcrun" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${DEVELOPER_DIR+x}" ]] || exit 45
[[ -z "${SDKROOT+x}" ]] || exit 45
[[ -z "${TOOLCHAINS+x}" ]] || exit 45
[[ -z "${xcrun_log+x}" ]] || exit 45
[[ -z "${xcrun_nocache+x}" ]] || exit 45
[[ -z "${xcrun_verbose+x}" ]] || exit 45
printf 'xcrun' >>"$MOCK_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$MOCK_LOG"
done
printf '\n' >>"$MOCK_LOG"
[[ "$1" == "notarytool" && "$2" == "submit" ]]
[[ -f "$3" ]]
printf '%s\n' "$3" >"$MOCK_ZIP_PATH"
[[ "${MOCK_NOTARY_EXIT:-0}" != "1" ]] || exit 44
if [[ "${MOCK_MUTATE_ORIGINAL:-0}" == "1" ]]; then
  printf '#!/bin/sh\nprintf "mutated\\n"\n' >"${MOCK_ORIGINAL:?}"
fi
if [[ -n "${MOCK_NOTARY_JSON+x}" ]]; then
  printf '%s\n' "$MOCK_NOTARY_JSON"
else
  printf '{"status":"%s","id":"%s"}\n' \
    "${MOCK_NOTARY_STATUS:-Accepted}" \
    "${MOCK_NOTARY_ID:-12345678-1234-1234-1234-123456789abc}"
fi
MOCK

cat >"$mock_bin/lipo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'lipo\t%s\n' "$*" >>"$MOCK_LOG"
printf '%s\n' "${MOCK_ARCH:-arm64}"
MOCK

chmod +x "$mock_bin/codesign" "$mock_bin/ditto" "$mock_bin/xcrun" "$mock_bin/lipo"
ln -s /usr/bin/plutil "$mock_bin/plutil"
ln -s /usr/bin/shasum "$mock_bin/shasum"
ln -s /usr/bin/stat "$mock_bin/stat"

reset_mocks() {
  : >"$MOCK_LOG"
  rm -f "$MOCK_ZIP_PATH"
  unset MOCK_SIGN_FAIL MOCK_VERIFY_FAIL MOCK_ONLINE_FAIL MOCK_DR MOCK_EXTRA_DR
  unset MOCK_IDENTIFIER MOCK_TEAM MOCK_FIRST_AUTHORITY MOCK_FLAGS
  unset MOCK_RUNTIME_VERSION MOCK_OMIT_RUNTIME_VERSION MOCK_TIMESTAMP
  unset MOCK_OMIT_TIMESTAMP MOCK_NOTARY_EXIT MOCK_NOTARY_JSON
  unset MOCK_NOTARY_STATUS MOCK_NOTARY_ID MOCK_MUTATE_ORIGINAL
  unset MOCK_ORIGINAL MOCK_MUTATE_VERIFY MOCK_VERIFY_BINARY MOCK_ARCH
  unset TEST_OFFICIAL TEST_IDENTITY TEST_MANAGED TEST_KEYCHAIN
  unset TEST_RELEASE_KEYCHAIN TEST_PROFILE TEST_SNAPSHOT
}

make_binary() {
  path=$1
  version=${2:-0.4.5}
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
#!/bin/sh
printf 'execute\\n' >>'$MOCK_LOG'
printf '%s\\n' '$version'
EOF
  chmod +x "$path"
}

hash_file() {
  value=$(shasum -a 256 "$1")
  printf '%s\n' "${value%% *}"
}

expect_failure() {
  label=$1
  shift
  if "$@" >"$tmp/failure.stdout" 2>"$tmp/failure.stderr"; then
    fail "$label unexpectedly succeeded"
  fi
}

run_sign() {
  GOPLACES_OFFICIAL_RELEASE=${TEST_OFFICIAL-1} \
    CODESIGN_IDENTITY=${TEST_IDENTITY-$AUTHORITY} \
    MAC_RELEASE_CODESIGN_KEYCHAIN_MANAGED=${TEST_MANAGED-1} \
    CODESIGN_KEYCHAIN=${TEST_KEYCHAIN-/tmp/foundation-release.keychain-db} \
    MAC_RELEASE_CODESIGN_KEYCHAIN=${TEST_RELEASE_KEYCHAIN-/tmp/foundation-release.keychain-db} \
    NOTARYTOOL_KEYCHAIN_PROFILE=${TEST_PROFILE-goplaces-notary} \
    GOPLACES_RELEASE_TEST_MODE=$TEST_MODE \
    GOPLACES_RELEASE_TEST_TOOL_DIR="$mock_bin" \
    DEVELOPER_DIR=/tmp/hostile-developer-dir \
    SDKROOT=/tmp/hostile-sdk \
    TOOLCHAINS=hostile.toolchain \
    xcrun_log=1 \
    xcrun_nocache=1 \
    xcrun_verbose=1 \
    PATH="$hostile_bin" \
    "$SIGN_SCRIPT" "$1" "${TEST_SNAPSHOT-true}"
}

run_verify() {
  env -u GH_TOKEN -u GITHUB_TOKEN -u NOTARYTOOL_KEYCHAIN_PROFILE \
    -u CODESIGN_IDENTITY -u CODESIGN_KEYCHAIN \
    -u MAC_RELEASE_CODESIGN_KEYCHAIN -u MAC_RELEASE_CODESIGN_KEYCHAIN_PASSWORD \
    GOPLACES_RELEASE_TEST_MODE=$TEST_MODE \
    GOPLACES_RELEASE_TEST_TOOL_DIR="$mock_bin" \
    PATH="$hostile_bin" \
    "$VERIFY_SCRIPT" "$@"
}

run_verify_with_credential() {
  credential_name=$1
  shift
  env -u GH_TOKEN -u GITHUB_TOKEN -u NOTARYTOOL_KEYCHAIN_PROFILE \
    -u CODESIGN_IDENTITY -u CODESIGN_KEYCHAIN \
    -u MAC_RELEASE_CODESIGN_KEYCHAIN -u MAC_RELEASE_CODESIGN_KEYCHAIN_PASSWORD \
    "$credential_name=" \
    GOPLACES_RELEASE_TEST_MODE=$TEST_MODE \
    GOPLACES_RELEASE_TEST_TOOL_DIR="$mock_bin" \
    PATH="$hostile_bin" \
    "$VERIFY_SCRIPT" "$@"
}

# Credential-free snapshots exit before checking the file, platform,
# credentials, test overrides, or any PATH-resolved tool.
GOPLACES_OFFICIAL_RELEASE=0 \
  CODESIGN_IDENTITY='wrong but ignored' \
  NOTARYTOOL_KEYCHAIN_PROFILE='ignored' \
  PATH="$hostile_bin" \
  "$SIGN_SCRIPT" "$tmp/does-not-exist" true
[[ ! -s "$HOSTILE_TOOL_LOG" ]] || fail "snapshot mode invoked a hostile PATH tool"

# Direct non-snapshot GoReleaser state fails before touching the platform or
# accepting an unsigned Darwin artifact.
if GOPLACES_OFFICIAL_RELEASE=0 PATH="$hostile_bin" \
  "$SIGN_SCRIPT" "$tmp/does-not-exist" false \
  >"$tmp/non-snapshot.stdout" 2>"$tmp/non-snapshot.stderr"; then
  fail "unsigned non-snapshot invocation succeeded"
fi
grep -F 'refusing to produce unsigned Darwin assets' "$tmp/non-snapshot.stderr" >/dev/null ||
  fail "unsigned non-snapshot failure was not explicit"
[[ ! -s "$HOSTILE_TOOL_LOG" ]] ||
  fail "unsigned non-snapshot failure invoked a hostile PATH tool"

if GOPLACES_OFFICIAL_RELEASE=0 PATH="$hostile_bin" \
  "$SIGN_SCRIPT" "$tmp/does-not-exist" hostile \
  >"$tmp/snapshot-state.stdout" 2>"$tmp/snapshot-state.stderr"; then
  fail "invalid snapshot state succeeded"
fi
[[ ! -s "$HOSTILE_TOOL_LOG" ]] || fail "invalid snapshot state invoked a PATH tool"

reset_mocks
TEST_OFFICIAL=maybe expect_failure "invalid official marker" run_sign "$tmp/missing"
[[ ! -s "$MOCK_LOG" ]] || fail "invalid marker invoked a platform tool"

case_dir="$tmp/path with spaces"
binary="$case_dir/goplaces"
make_binary "$binary"

if GOPLACES_OFFICIAL_RELEASE=1 \
  GOPLACES_RELEASE_TEST_MODE=almost-the-test-marker \
  GOPLACES_RELEASE_TEST_TOOL_DIR="$hostile_bin" \
  PATH="$hostile_bin" \
  "$SIGN_SCRIPT" "$binary" true \
  >"$tmp/test-marker.stdout" 2>"$tmp/test-marker.stderr"; then
  fail "inexact test marker enabled tool overrides"
fi
grep -F 'test tool overrides require the exact test marker' \
  "$tmp/test-marker.stderr" >/dev/null || fail "inexact test marker did not fail explicitly"
[[ ! -s "$HOSTILE_TOOL_LOG" ]] || fail "inexact test marker invoked a hostile tool"

reset_mocks
TEST_IDENTITY='Developer ID Application: Wrong Identity (WRONGTEAM1)'
expect_failure "wrong identity" run_sign "$binary"
[[ ! -s "$MOCK_LOG" ]] || fail "wrong identity reached a signing tool"

reset_mocks
TEST_MANAGED=0 expect_failure "missing managed marker" run_sign "$binary"
[[ ! -s "$MOCK_LOG" ]] || fail "missing managed marker reached a signing tool"

reset_mocks
TEST_RELEASE_KEYCHAIN=/tmp/other.keychain-db
expect_failure "mismatched keychains" run_sign "$binary"
[[ ! -s "$MOCK_LOG" ]] || fail "mismatched keychains reached a signing tool"

reset_mocks
symlink="$case_dir/goplaces-link"
ln -s "$binary" "$symlink"
expect_failure "symlink input" run_sign "$symlink"
[[ ! -s "$MOCK_LOG" ]] || fail "symlink input reached a signing tool"

reset_mocks
before=$(hash_file "$binary")
run_sign "$binary" >"$tmp/sign.stdout"
after=$(hash_file "$binary")
[[ "$after" != "$before" ]] || fail "successful signing did not promote a new binary"
grep -F '# MOCK-SIGNED' "$binary" >/dev/null || fail "signed candidate was not promoted"
grep -F $'codesign\t--force' "$MOCK_LOG" >/dev/null || fail "codesign was not invoked"
grep -F $'\t--options\truntime' "$MOCK_LOG" >/dev/null || fail "hardened runtime flag missing"
grep -F $'\t--timestamp' "$MOCK_LOG" >/dev/null || fail "secure timestamp flag missing"
grep -F $'\t--identifier\torg.openclaw.goplaces' "$MOCK_LOG" >/dev/null ||
  fail "frozen identifier missing"
grep -F $'ditto\t-c\t-k\t--sequesterRsrc\t--keepParent' "$MOCK_LOG" >/dev/null ||
  fail "ephemeral ZIP does not preserve metadata"
notary_zip=$(cat "$MOCK_ZIP_PATH")
[[ "$(grep -c '^xcrun' "$MOCK_LOG")" == "1" ]] ||
  fail "notarytool must be invoked exactly once"
actual_notary_invocation=$(grep '^xcrun' "$MOCK_LOG")
expected_notary_invocation=$(printf \
  'xcrun\tnotarytool\tsubmit\t%s\t--no-s3-acceleration\t--wait\t--output-format\tjson\t--keychain-profile\tgoplaces-notary' \
  "$notary_zip")
[[ "$actual_notary_invocation" == "$expected_notary_invocation" ]] ||
  fail "notarytool invocation arguments or ordering drifted"
[[ ! -e "$notary_zip" ]] || fail "ephemeral notarization ZIP survived success"
if find "$case_dir" -maxdepth 1 -name '.goplaces-sign.*' -print -quit | grep -q .; then
  fail "temporary signing directory survived success"
fi

failure_binary="$case_dir/notary-rejected"
make_binary "$failure_binary"
failure_before=$(hash_file "$failure_binary")
reset_mocks
export MOCK_NOTARY_STATUS=Rejected
expect_failure "rejected notarization" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "rejected notarization replaced the original"

reset_mocks
export MOCK_NOTARY_ID='not-a-uuid'
expect_failure "invalid notarization UUID" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "invalid notarization UUID replaced the original"

reset_mocks
export MOCK_ONLINE_FAIL=1
expect_failure "online notarization failure" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "online verification failure replaced the original"

reset_mocks
export MOCK_IDENTIFIER='hostile.example'
expect_failure "producer wrong identifier" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "wrong identifier replaced the original"

reset_mocks
export MOCK_TEAM='BADTEAM123'
expect_failure "producer wrong Team ID" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "wrong Team ID replaced the original"

reset_mocks
export MOCK_FIRST_AUTHORITY='Developer ID Application: Hostile (BADTEAM123)'
expect_failure "producer wrong leaf authority" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "wrong leaf authority replaced the original"

reset_mocks
export MOCK_FLAGS='0x10000(notruntime)'
expect_failure "producer runtime lookalike" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "runtime lookalike replaced the original"

reset_mocks
export MOCK_RUNTIME_VERSION='hostile'
expect_failure "producer wrong runtime version" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "wrong runtime version replaced the original"

reset_mocks
export MOCK_TIMESTAMP=none
expect_failure "producer missing secure timestamp" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "missing secure timestamp replaced the original"

reset_mocks
export MOCK_DR='identifier "hostile.example"'
expect_failure "producer wrong designated requirement" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "wrong designated requirement replaced the original"

reset_mocks
export MOCK_VERIFY_FAIL=1
expect_failure "producer static signature failure" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "static signature failure replaced the original"

reset_mocks
export MOCK_MUTATE_VERIFY=1
expect_failure "producer candidate mutation" run_sign "$failure_binary"
[[ "$(hash_file "$failure_binary")" == "$failure_before" ]] ||
  fail "candidate mutation promoted over the original"

mutation_binary="$case_dir/source-mutation"
make_binary "$mutation_binary"
reset_mocks
export MOCK_MUTATE_ORIGINAL=1
export MOCK_ORIGINAL="$mutation_binary"
expect_failure "source mutation" run_sign "$mutation_binary"
grep -F 'mutated' "$mutation_binary" >/dev/null || fail "source mutation test did not run"
if grep -F '# MOCK-SIGNED' "$mutation_binary" >/dev/null; then
  fail "source mutation was overwritten by the signed candidate"
fi

verify_binary="$case_dir/verify-goplaces"
make_binary "$verify_binary"

reset_mocks
run_verify "$verify_binary" arm64 0.4.5 static >"$tmp/verify-static.stdout"
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "static mode executed the candidate"
fi

reset_mocks
run_verify "$verify_binary" arm64 0.4.5 execute >"$tmp/verify-execute.stdout"
[[ "$(tail -n 1 "$MOCK_LOG")" == "execute" ]] ||
  fail "candidate execution was not the final verifier action"

reset_mocks
export MOCK_FIRST_AUTHORITY='Developer ID Application: Hostile (BADTEAM123)'
expect_failure "wrong leaf authority" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "wrong leaf authority candidate executed"
fi

reset_mocks
export MOCK_TEAM='BADTEAM123'
expect_failure "wrong Team ID" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "wrong Team ID candidate executed"
fi

reset_mocks
export MOCK_FLAGS='0x10000(notruntime)'
expect_failure "runtime lookalike" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "runtime lookalike candidate executed"
fi

reset_mocks
export MOCK_OMIT_RUNTIME_VERSION=1
expect_failure "missing runtime version" run_verify "$verify_binary" arm64 0.4.5 static

reset_mocks
export MOCK_TIMESTAMP=none
expect_failure "missing secure timestamp" run_verify "$verify_binary" arm64 0.4.5 static

reset_mocks
export MOCK_EXTRA_DR=1
expect_failure "multiple designated requirements" run_verify "$verify_binary" arm64 0.4.5 static

reset_mocks
export MOCK_VERIFY_FAIL=1
expect_failure "static signature rejection" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "static signature rejection candidate executed"
fi

reset_mocks
export MOCK_ONLINE_FAIL=1
expect_failure "online ticket rejection" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "online ticket rejection candidate executed"
fi

reset_mocks
export MOCK_ARCH='arm64 x86_64'
expect_failure "universal binary" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "wrong-architecture candidate executed"
fi

reset_mocks
export MOCK_IDENTIFIER='hostile.example'
expect_failure "hostile identifier" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "invalid signature candidate executed"
fi

reset_mocks
export MOCK_MUTATE_VERIFY=1
export MOCK_VERIFY_BINARY="$verify_binary"
expect_failure "verification-time mutation" run_verify "$verify_binary" arm64 0.4.5 execute
if grep -Fx 'execute' "$MOCK_LOG" >/dev/null; then
  fail "mutated candidate executed"
fi
make_binary "$verify_binary"

for credential_name in \
  GH_TOKEN \
  GITHUB_TOKEN \
  NOTARYTOOL_KEYCHAIN_PROFILE \
  CODESIGN_IDENTITY \
  CODESIGN_KEYCHAIN \
  MAC_RELEASE_CODESIGN_KEYCHAIN \
  MAC_RELEASE_CODESIGN_KEYCHAIN_PASSWORD; do
  reset_mocks
  expect_failure "set credential $credential_name" \
    run_verify_with_credential "$credential_name" "$verify_binary" arm64 0.4.5 static
  [[ ! -s "$MOCK_LOG" ]] ||
    fail "credential rejection invoked a verification tool: $credential_name"
done

[[ "$(cat "$ROOT/.github/release-allowed-signers")" == "$EXPECTED_SIGNER" ]] ||
  fail "release signer policy drifted"
awk '{print $2, $3}' "$ROOT/.github/release-allowed-signers" >"$tmp/release-signing-key.pub"
ssh-keygen -lf "$tmp/release-signing-key.pub" | grep -F "$EXPECTED_FINGERPRINT" >/dev/null ||
  fail "release signer fingerprint drifted"

grep -Fx "MAC_RELEASE_CODESIGN_IDENTITY='$AUTHORITY'" \
  "$ROOT/.mac-release.env.example" >/dev/null || fail "env example identity drifted"
grep -Fx 'MAC_RELEASE_CODESIGN_KEYCHAIN_MANAGED=1' \
  "$ROOT/.mac-release.env.example" >/dev/null || fail "managed keychain policy drifted"
if grep -Eq '^(MAC_RELEASE_CODESIGN_KEYCHAIN|MAC_RELEASE_CODESIGN_OP_ITEM|MAC_RELEASE_OP_ITEM|NOTARYTOOL_KEYCHAIN_PROFILE)=' \
  "$ROOT/.mac-release.env.example"; then
  fail "env example contains a runtime credential locator or value"
fi

grep -Fx '  draft: true' "$ROOT/.goreleaser.yml" >/dev/null ||
  fail "GoReleaser is not draft-only"
grep -Fx '  target_commitish: "{{ .Commit }}"' "$ROOT/.goreleaser.yml" >/dev/null ||
  fail "GoReleaser release target is not the exact commit"
grep -F 'GOPLACES_PILOT_VERSION' "$ROOT/.goreleaser.yml" >/dev/null ||
  fail "pilot version override missing"
[[ "$(grep -Fc 'scripts/codesign-macos.sh' "$ROOT/.goreleaser.yml")" == "1" ]] ||
  fail "Darwin signing hook count drifted"
grep -F './scripts/codesign-macos.sh "{{ .Path }}" "{{ .IsSnapshot }}"' \
  "$ROOT/.goreleaser.yml" >/dev/null ||
  fail "Darwin hook does not pass trusted GoReleaser snapshot state"
if grep -Eq 'homebrew_casks|HOMEBREW_TAP|xattr' "$ROOT/.goreleaser.yml"; then
  fail "GoReleaser still mutates Homebrew or strips quarantine"
fi
for system_tool in \
  /usr/bin/codesign \
  /usr/bin/ditto \
  /usr/bin/lipo \
  /usr/bin/plutil \
  /usr/bin/shasum \
  /usr/bin/stat \
  /usr/bin/xcrun; do
  grep -F "$system_tool" "$SIGN_SCRIPT" "$VERIFY_SCRIPT" >/dev/null ||
    fail "production tool path is not pinned: $system_tool"
done
if grep -Eq '(^|[^[:alnum:]_])jq([^[:alnum:]_]|$)' "$SIGN_SCRIPT" "$VERIFY_SCRIPT"; then
  fail "release secret scope depends on non-system jq"
fi
for forbidden in 'sp''ctl' 'sysp''olicy' 'stap''ler'; do
  if grep -F "$forbidden" "$SIGN_SCRIPT" "$VERIFY_SCRIPT" "$ROOT/.goreleaser.yml" >/dev/null; then
    fail "raw macOS policy tool is forbidden: $forbidden"
  fi
done

[[ ! -s "$HOSTILE_TOOL_LOG" ]] || fail "a hostile PATH tool was invoked"

/bin/bash -n "$SIGN_SCRIPT" "$VERIFY_SCRIPT" "$0"
echo "codesign macOS mock tests passed"
