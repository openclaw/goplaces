#!/bin/bash -p
set -euo pipefail
set +vx
unset BASH_ENV ENV CDPATH
export LC_ALL=C

readonly SHELLCHECK_VERSION=0.11.0
readonly RELEASE_ROOT="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}"
readonly TEST_MARKER=goplaces-shellcheck-bootstrap-test-v1

die() {
  echo "ShellCheck bootstrap: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || die "usage: $0 DEST_DIR"
destination=$1

test_mode=${GOPLACES_SHELLCHECK_BOOTSTRAP_TEST_MODE-}
case "$test_mode" in
  "")
    curl_bin=/usr/bin/curl
    tar_bin=/usr/bin/bsdtar
    shasum_bin=/usr/bin/shasum
    stat_bin=/usr/bin/stat
    uname_bin=/usr/bin/uname
    ;;
  "$TEST_MARKER")
    curl_bin=${CURL_BIN-}
    tar_bin=${TAR_BIN-/usr/bin/bsdtar}
    shasum_bin=${SHASUM_BIN-/usr/bin/shasum}
    stat_bin=${STAT_BIN-/usr/bin/stat}
    uname_bin=${UNAME_BIN-/usr/bin/uname}
    ;;
  *) die "invalid test mode" ;;
esac

for tool in "$curl_bin" "$tar_bin" "$shasum_bin" "$stat_bin" "$uname_bin"; do
  [[ "$tool" == /* && -f "$tool" && ! -L "$tool" && -x "$tool" ]] ||
    die "required pinned tool is unavailable: $tool"
done
[[ "$destination" == /* ]] || die "destination must be absolute"
[[ ! -e "$destination" && ! -L "$destination" ]] || die "destination already exists"
parent=$(/usr/bin/dirname "$destination")
[[ -d "$parent" && ! -L "$parent" ]] || die "destination parent must be a real directory"
parent=$(cd "$parent" && pwd -P)
destination="$parent/$(/usr/bin/basename "$destination")"

case "$($uname_bin -m)" in
  arm64)
    archive_name="shellcheck-v${SHELLCHECK_VERSION}.darwin.aarch64.tar.gz"
    expected_archive_size=11370575
    expected_archive_sha256=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f
    expected_binary_sha256=61c17246d69f012cd458ae82f244c46023dac75d1b69733ca1cc7d28fb270fd7
    ;;
  x86_64)
    archive_name="shellcheck-v${SHELLCHECK_VERSION}.darwin.x86_64.tar.gz"
    expected_archive_size=6700263
    expected_archive_sha256=c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51
    expected_binary_sha256=2589be755bb115f4421b8271eb7c08df1e03729f00350c1e4cf53b4a0bf9c2df
    ;;
  *) die "unsupported macOS architecture" ;;
esac

if [[ "$test_mode" == "$TEST_MARKER" ]]; then
  expected_archive_size=${EXPECTED_ARCHIVE_SIZE-$expected_archive_size}
  expected_archive_sha256=${EXPECTED_ARCHIVE_SHA256-$expected_archive_sha256}
  expected_binary_sha256=${EXPECTED_BINARY_SHA256-$expected_binary_sha256}
fi
[[ "$expected_archive_size" =~ ^[1-9][0-9]*$ ]] || die "invalid archive size"
[[ "$expected_archive_sha256" =~ ^[0-9a-f]{64}$ ]] || die "invalid archive digest"
[[ "$expected_binary_sha256" =~ ^[0-9a-f]{64}$ ]] || die "invalid binary digest"

archive_url="${RELEASE_ROOT}/${archive_name}"
expected_member="shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
scratch=$(/usr/bin/mktemp -d "$parent/.goplaces-shellcheck.XXXXXX")
trap '/bin/rm -rf "$scratch"' EXIT HUP INT TERM
archive="$scratch/$archive_name"
members="$scratch/members.txt"

status=$($curl_bin \
  --disable \
  --silent --show-error \
  --location \
  --max-redirs 5 \
  --retry 3 \
  --proto '=https' \
  --proto-redir '=https' \
  --tlsv1.2 \
  --output "$archive" \
  --write-out '%{http_code}' \
  "$archive_url") || die "download failed"
[[ "$status" == 200 ]] || die "download returned HTTP $status"
[[ "$($stat_bin -f '%z' "$archive")" == "$expected_archive_size" ]] || die "archive size mismatch"
archive_digest=$($shasum_bin -a 256 "$archive")
archive_digest=${archive_digest%% *}
[[ "$archive_digest" == "$expected_archive_sha256" ]] || die "archive digest mismatch"

$tar_bin -tzf "$archive" > "$members" || die "archive listing failed"
[[ -s "$members" ]] || die "archive is empty"
member_count=0
while IFS= read -r member; do
  [[ "$member" == "shellcheck-v${SHELLCHECK_VERSION}/"* ]] || die "archive has an unexpected root"
  [[ "$member" != /* && "$member" != ../* && "$member" != *'/../'* && "$member" != *'/..' ]] ||
    die "archive has an unsafe path"
  [[ "$member" == "$expected_member" ]] && member_count=$((member_count + 1))
done < "$members"
[[ "$member_count" -eq 1 ]] || die "archive must contain exactly one ShellCheck executable"

/bin/mkdir "$destination"
$tar_bin -xzf "$archive" -C "$destination" --no-same-owner "$expected_member" || die "extraction failed"
binary="$destination/$expected_member"
[[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] || die "extracted executable is invalid"
binary_digest=$($shasum_bin -a 256 "$binary")
binary_digest=${binary_digest%% *}
[[ "$binary_digest" == "$expected_binary_sha256" ]] || die "extracted executable digest mismatch"
version_output=$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C "$binary" --version)
[[ "$(/usr/bin/grep -c '^version: 0\.11\.0$' <<<"$version_output")" -eq 1 ]] ||
  die "extracted executable version mismatch"

/bin/rm -f "$archive" "$members"
trap - EXIT HUP INT TERM
printf '%s\n' "$binary"
