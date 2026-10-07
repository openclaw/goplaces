#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-bootstrap-cleanup.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

die() {
  echo "bootstrap cleanup test: $*" >&2
  exit 1
}

cat > "$scratch/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output=$2; shift 2 ;;
    *) shift ;;
  esac
done
/bin/cp "$BOOTSTRAP_TEST_ARCHIVE" "$output"
printf '200'
EOF
cat > "$scratch/uname" <<'EOF'
#!/bin/bash
[[ "$1" == -m ]]
printf 'arm64\n'
EOF
chmod 755 "$scratch/curl" "$scratch/uname"

make_archive() {
  local kind=$1 version=$2
  local tree="$scratch/$kind-$version"
  if [[ "$kind" == go ]]; then
    mkdir -p "$tree/go/bin"
    printf '#!/bin/bash\nprintf "go%s\\n"\n' "$version" > "$tree/go/bin/go"
    chmod 755 "$tree/go/bin/go"
  else
    mkdir -p "$tree/shellcheck-v0.11.0"
    printf '#!/bin/bash\nprintf "version: %s\\n"\n' "$version" > "$tree/shellcheck-v0.11.0/shellcheck"
    chmod 755 "$tree/shellcheck-v0.11.0/shellcheck"
  fi
  if [[ "$kind" == go ]]; then
    (cd "$tree" && /usr/bin/bsdtar -czf "$scratch/$kind-$version.tar.gz" go)
  else
    (cd "$tree" && /usr/bin/bsdtar -czf "$scratch/$kind-$version.tar.gz" shellcheck-v0.11.0)
  fi
}

bootstrap() {
  local kind=$1 archive=$2 destination=$3
  local size digest binary_digest
  size=$(/usr/bin/stat -f '%z' "$archive")
  digest=$(/usr/bin/shasum -a 256 "$archive")
  digest=${digest%% *}
  if [[ "$kind" == go ]]; then
    GOPLACES_RELEASE_TESTING=1 CURL_BIN="$scratch/curl" UNAME_BIN="$scratch/uname" \
      BOOTSTRAP_TEST_ARCHIVE="$archive" EXPECTED_ARCHIVE_SIZE="$size" \
      EXPECTED_ARCHIVE_SHA256="$digest" \
      "$repo_root/scripts/bootstrap-go-toolchain.sh" "$destination"
  else
    binary_digest=$(/usr/bin/shasum -a 256 "${archive%.tar.gz}/shellcheck-v0.11.0/shellcheck")
    binary_digest=${binary_digest%% *}
    GOPLACES_SHELLCHECK_BOOTSTRAP_TEST_MODE=goplaces-shellcheck-bootstrap-test-v1 \
      CURL_BIN="$scratch/curl" UNAME_BIN="$scratch/uname" BOOTSTRAP_TEST_ARCHIVE="$archive" \
      EXPECTED_ARCHIVE_SIZE="$size" EXPECTED_ARCHIVE_SHA256="$digest" \
      EXPECTED_BINARY_SHA256="$binary_digest" \
      "$repo_root/scripts/bootstrap-shellcheck.sh" "$destination"
  fi
}

kinds=(go shellcheck)
if [[ $# -gt 0 ]]; then
  kinds=("$@")
fi
for kind in "${kinds[@]}"; do
  if [[ "$kind" == go ]]; then
    valid_version=1.26.8
    installed_suffix=go/bin/go
  else
    valid_version=0.11.0
    installed_suffix=shellcheck-v0.11.0/shellcheck
  fi
  make_archive "$kind" 0.0.0
  make_archive "$kind" "$valid_version"
  destination="$scratch/$kind-install"
  if bootstrap "$kind" "$scratch/$kind-0.0.0.tar.gz" "$destination" > "$scratch/failure.out" 2>&1; then
    die "$kind accepted the wrong extracted version"
  fi
  grep -q 'version mismatch' "$scratch/failure.out" || die "$kind did not reach extracted version verification"
  left_invalid_install=false
  [[ ! -e "$destination" && ! -L "$destination" ]] || left_invalid_install=true
  if bootstrap "$kind" "$scratch/$kind-$valid_version.tar.gz" "$destination" > "$scratch/success.out" 2>&1; then
    retry_succeeded=true
  else
    retry_succeeded=false
  fi
  if [[ "$left_invalid_install" == true ]]; then
    cat "$scratch/failure.out" "$scratch/success.out" >&2
    die "$kind left an invalid installation that blocks retry"
  fi
  [[ "$retry_succeeded" == true ]] || die "$kind valid retry failed"
  [[ -x "$destination/$installed_suffix" ]] || die "$kind retry did not install its executable"
  # A later attempt must preserve an existing, successful installation.
  if bootstrap "$kind" "$scratch/$kind-0.0.0.tar.gz" "$destination" > "$scratch/existing.out" 2>&1; then
    die "$kind accepted an existing destination"
  fi
  [[ -x "$destination/$installed_suffix" ]] || die "$kind removed an existing installation"
  grep -q 'destination already exists' "$scratch/existing.out" || die "$kind did not reject the existing destination"
  for temporary in "$scratch/.goplaces-go."* "$scratch/.goplaces-shellcheck."*; do
    [[ ! -e "$temporary" ]] || die "$kind leaked bootstrap scratch directories"
  done
  echo "bootstrap cleanup test: $kind rejects invalid versions, retries successfully and preserves existing installs"
done
