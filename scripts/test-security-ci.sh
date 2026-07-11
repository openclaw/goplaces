#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "security CI test: $*" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"
# shellcheck source=scripts/test-git-fixture.sh
source "$repo_root/scripts/test-git-fixture.sh"

release_workflow=.github/workflows/release.yml
ci_workflow=.github/workflows/ci.yml
hydrate_workflow=.github/workflows/crabbox-hydrate.yml
pages_workflow=.github/workflows/pages.yml
hydrate_fetch=./scripts/fetch-public-main.sh

forbidden_workflow_pattern='permissions:[[:space:]]*write-all|^[[:space:]]+[A-Za-z0-9_-]+:[^#]*write|secrets|\$\{\{|(^|[[:space:]])[&*][^[:space:]]+|GITHUB_TOKEN|GH_TOKEN|upload-artifact|gh release|HOMEBREW_|MAC_RELEASE_|CODESIGN_|GOPLACES_OFFICIAL_RELEASE|notarytool|(^|[[:space:]])codesign([[:space:]]|$)'
assert_checkout_credentials_disabled() {
  local workflow="$1"
  if ! awk '
    function finish_checkout() {
      if (checkout && !safe) bad = 1
      checkout = 0
      in_with = 0
      persist_seen = 0
    }
    function indentation(line, prefix) {
      prefix = line
      sub(/[^ ].*$/, "", prefix)
      return length(prefix)
    }
    {
      if ($0 ~ /^[ ]*($|#)/) next
      indent = indentation($0)
      trimmed = $0
      sub(/^[ ]*/, "", trimmed)
      sub(/[ ]*$/, "", trimmed)

      if (checkout && indent <= step_indent) {
        finish_checkout()
      }
      if ((trimmed ~ /^- uses:/ || trimmed ~ /^uses:/) && index(trimmed, "actions/checkout@")) {
        finish_checkout()
        checkout = 1
        seen_checkout = 1
        step_indent = (trimmed ~ /^- uses:/) ? indent : indent - 2
        safe = 0
        next
      }
      if (!checkout) next
      if (trimmed == "with:" && indent == step_indent + 2) {
        in_with = 1
        with_indent = indent
        next
      }
      if (in_with && indent <= with_indent) {
        in_with = 0
      }
      if (in_with && indent == with_indent + 2 && trimmed ~ /^persist-credentials:/) {
        if (trimmed == "persist-credentials: false" && !persist_seen) {
          safe = 1
        } else {
          bad = 1
        }
        persist_seen = 1
      }
    }
    END {
      finish_checkout()
      if (!seen_checkout) bad = 1
      exit bad
    }
  ' "$workflow"; then
    die "$workflow has a checkout without persist-credentials: false in its with block"
  fi
}

assert_workflow_safe() {
  local workflow="$1"
  local permission_count

  permission_count="$(grep -Ec '^[[:space:]]*permissions:' "$workflow" || true)"
  [[ "$permission_count" -eq 1 ]] || die "$workflow must have exactly one workflow-level permissions block"
  if ! awk '
    /^permissions:[[:space:]]*$/ {
      block = 1
      found_block = 1
      next
    }
    block && /^[^[:space:]]/ {
      block = 0
    }
    block && /^[[:space:]]*($|#)/ {
      next
    }
    block && /^  contents:[[:space:]]*read[[:space:]]*$/ && !found_contents {
      found_contents = 1
      next
    }
    block {
      bad = 1
    }
    END {
      exit !(found_block && found_contents && !bad)
    }
  ' "$workflow"; then
    die "$workflow permissions must contain only contents: read"
  fi
  if grep -Eq "$forbidden_workflow_pattern" "$workflow"; then
    die "$workflow contains publication, signing, or secret access"
  fi
  assert_checkout_credentials_disabled "$workflow"
}

require_code_pattern() {
  local workflow="$1"
  local pattern="$2"
  local description="$3"
  if ! grep -Ev '^[[:space:]]*#' "$workflow" | grep -Eq "$pattern"; then
    die "$workflow omits executable $description"
  fi
}

assert_active_workflow_steps() {
  local workflow="$1"
  /usr/bin/ruby -ryaml - "$workflow" <<'RUBY'
workflow = YAML.load_file(ARGV.fetch(0))
jobs = workflow.fetch("jobs")
steps = jobs.values.flat_map { |job| job.fetch("steps", []) }
raise "malformed step" unless steps.all? { |step| step.is_a?(Hash) }
raise "disabled release proof step" if steps.any? { |step| step.key?("if") }

run_lines = steps.flat_map do |step|
  step.fetch("run", "").to_s.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
end
required_runs = [
  'shellcheck_bin="$(./scripts/bootstrap-shellcheck.sh "$RUNNER_TEMP/shellcheck")"',
  "go install golang.org/x/vuln/cmd/govulncheck@v1.5.0",
  "./scripts/verify-snapshot-security.sh",
  "./scripts/test-reproducible-builds.sh dist",
  "./scripts/test-codesign-macos.sh",
  "./scripts/test-release-assets.sh",
  "./scripts/test-release-local.sh",
  "./scripts/test-security-ci.sh",
]
required_runs.each { |command| raise "missing active #{command}" unless run_lines.include?(command) }
raise "missing active source scan" unless run_lines.any? { |line| line.match?(%r{govulncheck.*-db=https://vuln\.go\.dev.*-test\s+\./\.\.\.}) }

snapshot = steps.find { |step| step["run"].to_s.strip == "./scripts/verify-snapshot-security.sh" }
raise "snapshot clean gate missing" unless snapshot&.fetch("env", {})&.fetch("SNAPSHOT_REQUIRE_CLEAN", nil).to_s == "1"
goreleaser = steps.find { |step| step["uses"] == "goreleaser/goreleaser-action@v7" && step.fetch("with", {})["args"] == "release --snapshot --clean --skip=publish --config .goreleaser.yml" }
raise "active GoReleaser snapshot missing" unless goreleaser && goreleaser.fetch("with", {})["version"] == "v2.16.0"
RUBY
}

assert_workflow_proof() {
  local workflow="$1"
  local contract_test

  require_code_pattern "$workflow" '^[[:space:]]+version:[[:space:]]+v2\.16\.0[[:space:]]*$' "GoReleaser v2.16.0 pin"
  require_code_pattern "$workflow" '^[[:space:]]+args:[[:space:]]+release --snapshot --clean --skip=publish --config \.goreleaser\.yml[[:space:]]*$' "non-publishing snapshot"
  require_code_pattern "$workflow" '^[[:space:]]+run:[[:space:]]+go install golang\.org/x/vuln/cmd/govulncheck@v1\.5\.0[[:space:]]*$' "govulncheck v1.5.0 install"
  # shellcheck disable=SC2016
  require_code_pattern "$workflow" 'shellcheck_bin="\$\(\./scripts/bootstrap-shellcheck\.sh "\$RUNNER_TEMP/shellcheck"\)"' "pinned ShellCheck bootstrap"
  require_code_pattern "$workflow" '^[[:space:]]+run:[^#]*govulncheck[^#]*-db=https://vuln\.go\.dev[^#]*-test[[:space:]]+\./\.\.\.[^#]*$' "official-database source vulnerability scan including tests"
  require_code_pattern "$workflow" '^[[:space:]]+SNAPSHOT_REQUIRE_CLEAN:[[:space:]]+"1"[[:space:]]*$' "clean snapshot provenance requirement"
  require_code_pattern "$workflow" '^[[:space:]]+run:[[:space:]]+\./scripts/verify-snapshot-security\.sh[[:space:]]*$' "snapshot binary verification"
  require_code_pattern "$workflow" '^[[:space:]]+run:[[:space:]]+\./scripts/test-reproducible-builds\.sh dist[[:space:]]*$' "snapshot recipe reproduction"
  for contract_test in test-codesign-macos.sh test-release-assets.sh test-release-local.sh test-security-ci.sh; do
    require_code_pattern "$workflow" "^[[:space:]]+\\./scripts/${contract_test}[[:space:]]*$" "$contract_test"
  done
  assert_active_workflow_steps "$workflow" || die "$workflow release proofs are not active workflow steps"
}

for workflow in "$release_workflow" "$ci_workflow"; do
  assert_workflow_safe "$workflow"
  assert_workflow_proof "$workflow"
done
for workflow in "$release_workflow" "$ci_workflow" "$hydrate_workflow" "$pages_workflow"; do
  assert_checkout_credentials_disabled "$workflow"
done
# shellcheck disable=SC2016
grep -Fq './scripts/fetch-public-main.sh "$GITHUB_WORKSPACE"' "$hydrate_workflow" || die "Crabbox does not use the isolated public fetch helper"
if grep -Eq '^[[:space:]]*(/usr/bin/)?git[[:space:]]+fetch|github\.token|GH_TOKEN|GITHUB_TOKEN|secrets\.' "$hydrate_workflow"; then
  die "Crabbox workflow contains a raw or credentialed fetch path"
fi
for proof in \
  'GIT_CONFIG=/dev/null' \
  'GIT_CONFIG_NOSYSTEM=1' \
  'GIT_CONFIG_GLOBAL=/dev/null' \
  'GIT_ASKPASS=/usr/bin/false' \
  'credential.helper=' \
  'http.extraHeader=' \
  'https://github.com/openclaw/goplaces.git'; do
  grep -Fq "$proof" "$hydrate_fetch" || die "public fetch helper omits $proof"
done
grep -Eq '^[[:space:]]+/usr/bin/env -i \\$' scripts/test-reproducible-builds.sh || die "reproducible builds must pin its empty-environment command"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-security-ci.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

hydrate_fixture="$scratch/hydrate-fixture"
hydrate_fixture_git="$scratch/hydrate-fixture-git"
hydrate_mock_dir="$scratch/hydrate-mock"
hydrate_hostile_bin="$scratch/hydrate-hostile-bin"
hydrate_hostile_home="$scratch/hydrate-hostile-home"
hydrate_runner_temp="$scratch/hydrate-runner-temp"
mkdir -p "$hydrate_fixture" "$hydrate_fixture_git" "$hydrate_mock_dir" "$hydrate_hostile_bin" "$hydrate_hostile_home" "$hydrate_runner_temp"
test_fixture_git "$hydrate_fixture_git" -C "$hydrate_fixture" init -q
cat >"$hydrate_mock_dir/git" <<'EOF'
#!/bin/bash -p
set -euo pipefail
mock_dir="${0%/*}"
[[ "$PATH" == /usr/bin:/bin:/usr/sbin:/sbin ]]
[[ "$HOME" == */home && "$XDG_CONFIG_HOME" == */xdg && "$TMPDIR" == */tmp ]]
[[ "$GIT_CONFIG" == /dev/null && "$GIT_CONFIG_NOSYSTEM" == 1 ]]
[[ "$GIT_CONFIG_SYSTEM" == /dev/null && "$GIT_CONFIG_GLOBAL" == /dev/null ]]
[[ "$GIT_NO_REPLACE_OBJECTS" == 1 && "$GIT_TERMINAL_PROMPT" == 0 ]]
[[ "$GIT_ASKPASS" == /usr/bin/false && "$SSH_ASKPASS" == /usr/bin/false ]]
[[ "$GIT_SSH_COMMAND" == /usr/bin/false && "$GCM_INTERACTIVE" == Never ]]
for forbidden in BASH_ENV ENV CDPATH GH_TOKEN GITHUB_TOKEN GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
  [[ -z "${!forbidden+x}" ]]
done
expected_configs=(
  core.hooksPath=/dev/null
  credential.helper=
  core.askPass=/usr/bin/false
  credential.interactive=false
  http.extraHeader=
)
for expected in "${expected_configs[@]}"; do
  [[ "${1:-}" == -c && "${2:-}" == "$expected" ]]
  shift 2
done
[[ "${1:-}" == -C ]]
repo="$2"
shift 2
case "${1:-}" in
  rev-parse)
    case "$*" in
      'rev-parse --absolute-git-dir') printf '%s/.git\n' "$repo" ;;
      'rev-parse --path-format=absolute --git-path info/grafts') printf '%s/.git/info/grafts\n' "$repo" ;;
      'rev-parse --path-format=absolute --git-path objects/info/alternates') printf '%s/.git/objects/info/alternates\n' "$repo" ;;
      *) exit 91 ;;
    esac
    ;;
  for-each-ref) ;;
  fetch)
    [[ "$*" == "fetch --no-tags --depth=50 https://github.com/openclaw/goplaces.git +refs/heads/main:refs/remotes/origin/main" ]]
    : >"$mock_dir/fetch-ran"
    ;;
  *) exit 92 ;;
esac
EOF
cat >"$hydrate_hostile_bin/git" <<EOF
#!/bin/sh
: >"$scratch/ambient-hydrate-git-ran"
exit 97
EOF
cat >"$scratch/hydrate-startup" <<EOF
#!/bin/sh
: >"$scratch/hydrate-startup-ran"
EOF
chmod +x "$hydrate_mock_dir/git" "$hydrate_hostile_bin/git" "$scratch/hydrate-startup"
cat >"$hydrate_hostile_home/.gitconfig" <<'EOF'
[credential]
  helper = hostile
[http]
  extraHeader = Authorization: hostile-fixture
EOF
PATH="$hydrate_hostile_bin:/usr/bin:/bin" \
  HOME="$hydrate_hostile_home" \
  BASH_ENV="$scratch/hydrate-startup" \
  ENV="$scratch/hydrate-startup" \
  CDPATH="$hydrate_hostile_home" \
  GH_TOKEN=hostile-fixture \
  GITHUB_TOKEN=hostile-fixture \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=credential.helper \
  GIT_CONFIG_VALUE_0=hostile \
  RUNNER_TEMP="$hydrate_runner_temp" \
  GOPLACES_HYDRATE_FETCH_TESTING=1 \
  GIT_BIN="$hydrate_mock_dir/git" \
  "$hydrate_fetch" "$hydrate_fixture"
[[ -e "$hydrate_mock_dir/fetch-ran" ]] || die "isolated public fetch did not execute"
[[ ! -e "$scratch/ambient-hydrate-git-ran" ]] || die "public fetch used ambient Git"
[[ ! -e "$scratch/hydrate-startup-ran" ]] || die "public fetch executed a hostile shell startup file"
test_fixture_git "$hydrate_fixture_git" -C "$hydrate_fixture" config --local http.https://github.com/.extraheader hostile-fixture
if RUNNER_TEMP="$hydrate_runner_temp" GOPLACES_HYDRATE_FETCH_TESTING=1 GIT_BIN="$hydrate_mock_dir/git" \
  "$hydrate_fetch" "$hydrate_fixture" >/dev/null 2>&1; then
  die "public fetch accepted a persisted checkout authorization header"
fi
test_fixture_git "$hydrate_fixture_git" -C "$hydrate_fixture" config --local --unset http.https://github.com/.extraheader

shellcheck_fixture="$scratch/shellcheck-v0.11.0"
shellcheck_archive="$scratch/shellcheck-v0.11.0.darwin.aarch64.tar.gz"
shellcheck_curl="$scratch/curl"
shellcheck_uname="$scratch/uname"
startup_sentinel="$scratch/startup-sentinel"
mkdir "$shellcheck_fixture"
cat > "$shellcheck_fixture/shellcheck" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "${1:-}" == --version ]]
cat <<'VERSION'
ShellCheck - shell script analysis tool
version: 0.11.0
license: GNU General Public License, version 3
website: https://www.shellcheck.net
VERSION
EOF
chmod 755 "$shellcheck_fixture/shellcheck"
(
  cd "$scratch"
  /usr/bin/bsdtar -czf "$shellcheck_archive" shellcheck-v0.11.0
)
cat > "$shellcheck_curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output=""
saw_disable=false
saw_location=false
saw_max_redirs=false
saw_proto=false
saw_proto_redir=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --disable) saw_disable=true; shift ;;
    --location) saw_location=true; shift ;;
    --max-redirs) [[ "$2" == 5 ]]; saw_max_redirs=true; shift 2 ;;
    --output) output=$2; shift 2 ;;
    --proto) [[ "$2" == '=https' ]]; saw_proto=true; shift 2 ;;
    --proto-redir) [[ "$2" == '=https' ]]; saw_proto_redir=true; shift 2 ;;
    --write-out) shift 2 ;;
    *) shift ;;
  esac
done
[[ "$output" == /* && -n "${SHELLCHECK_TEST_ARCHIVE:-}" ]]
[[ "$saw_disable" == true && "$saw_location" == true && "$saw_max_redirs" == true ]]
[[ "$saw_proto" == true && "$saw_proto_redir" == true ]]
/bin/cp "$SHELLCHECK_TEST_ARCHIVE" "$output"
printf '200'
EOF
cat > "$shellcheck_uname" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "${1:-}" == -m ]]
printf 'arm64\n'
EOF
cat > "$scratch/startup" <<EOF
#!/bin/bash
/usr/bin/touch "$startup_sentinel"
EOF
chmod 755 "$shellcheck_curl" "$shellcheck_uname" "$scratch/startup"
shellcheck_archive_size="$(/usr/bin/stat -f '%z' "$shellcheck_archive")"
shellcheck_archive_sha="$(/usr/bin/shasum -a 256 "$shellcheck_archive")"
shellcheck_archive_sha="${shellcheck_archive_sha%% *}"
shellcheck_binary_sha="$(/usr/bin/shasum -a 256 "$shellcheck_fixture/shellcheck")"
shellcheck_binary_sha="${shellcheck_binary_sha%% *}"
shellcheck_installed="$(
  BASH_ENV="$scratch/startup" ENV="$scratch/startup" CDPATH="$scratch" \
    GOPLACES_SHELLCHECK_BOOTSTRAP_TEST_MODE=goplaces-shellcheck-bootstrap-test-v1 \
    CURL_BIN="$shellcheck_curl" UNAME_BIN="$shellcheck_uname" \
    SHELLCHECK_TEST_ARCHIVE="$shellcheck_archive" \
    EXPECTED_ARCHIVE_SIZE="$shellcheck_archive_size" \
    EXPECTED_ARCHIVE_SHA256="$shellcheck_archive_sha" \
    EXPECTED_BINARY_SHA256="$shellcheck_binary_sha" \
    "$repo_root/scripts/bootstrap-shellcheck.sh" "$scratch/shellcheck-install"
)"
expected_shellcheck_installed="$(cd "$scratch" && pwd -P)/shellcheck-install/shellcheck-v0.11.0/shellcheck"
[[ "$shellcheck_installed" == "$expected_shellcheck_installed" ]] ||
  die "ShellCheck bootstrap returned the wrong executable"
[[ -x "$shellcheck_installed" && ! -L "$shellcheck_installed" ]] ||
  die "ShellCheck bootstrap did not install a regular executable"
[[ ! -e "$startup_sentinel" ]] || die "ShellCheck bootstrap executed a hostile startup file"
if GOPLACES_SHELLCHECK_BOOTSTRAP_TEST_MODE=hostile \
  "$repo_root/scripts/bootstrap-shellcheck.sh" "$scratch/shellcheck-invalid-mode" >/dev/null 2>&1; then
  die "ShellCheck bootstrap accepted an invalid test marker"
fi
if GOPLACES_SHELLCHECK_BOOTSTRAP_TEST_MODE=goplaces-shellcheck-bootstrap-test-v1 \
  CURL_BIN="$shellcheck_curl" UNAME_BIN="$shellcheck_uname" \
  SHELLCHECK_TEST_ARCHIVE="$shellcheck_archive" \
  EXPECTED_ARCHIVE_SIZE="$shellcheck_archive_size" \
  EXPECTED_ARCHIVE_SHA256=0000000000000000000000000000000000000000000000000000000000000000 \
  EXPECTED_BINARY_SHA256="$shellcheck_binary_sha" \
  "$repo_root/scripts/bootstrap-shellcheck.sh" "$scratch/shellcheck-bad-digest" >/dev/null 2>&1; then
  die "ShellCheck bootstrap accepted the wrong archive digest"
fi

expect_unsafe_workflow() {
  local workflow="$1"
  local description="$2"
  if (assert_workflow_safe "$workflow") >/dev/null 2>&1; then
    die "$description workflow mutation was accepted"
  fi
}

expect_unsafe_checkout() {
  local workflow="$1"
  local description="$2"
  if (assert_checkout_credentials_disabled "$workflow") >/dev/null 2>&1; then
    die "$description checkout mutation was accepted"
  fi
}

for workflow in "$hydrate_workflow" "$pages_workflow"; do
  workflow_name="${workflow##*/}"
  awk '!changed && /persist-credentials:[[:space:]]*false/ {sub(/false/, "true"); changed=1} {print}' \
    "$workflow" >"$scratch/${workflow_name}.persist-true"
  expect_unsafe_checkout "$scratch/${workflow_name}.persist-true" "$workflow_name persisted credential"
  awk '!changed && /persist-credentials:[[:space:]]*false/ {changed=1; next} {print}' \
    "$workflow" >"$scratch/${workflow_name}.persist-missing"
  expect_unsafe_checkout "$scratch/${workflow_name}.persist-missing" "$workflow_name missing persistence policy"
done

expect_missing_workflow_proof() {
  local workflow="$1"
  local description="$2"
  if (assert_workflow_proof "$workflow") >/dev/null 2>&1; then
    die "$description workflow proof omission was accepted"
  fi
}

awk '{print; if ($0 == "  contents: read") print "  issues: write"}' "$release_workflow" > "$scratch/write-scope.yml"
expect_unsafe_workflow "$scratch/write-scope.yml" "generic write scope"

for scalar_style in '>-' '|'; do
  awk -v style="$scalar_style" '{print; if ($0 == "  contents: read") {print "  issues: " style; print "    write"}}' "$release_workflow" > "$scratch/write-scalar.yml"
  expect_unsafe_workflow "$scratch/write-scalar.yml" "scalar write scope"
done

cp "$release_workflow" "$scratch/bracket-secret.yml"
cat >> "$scratch/bracket-secret.yml" <<'EOF'
env:
  SECRET_INPUT: ${{ secrets['HOSTILE'] }}
EOF
expect_unsafe_workflow "$scratch/bracket-secret.yml" "bracket secret context"

cp "$release_workflow" "$scratch/object-secret.yml"
cat >> "$scratch/object-secret.yml" <<'EOF'
env:
  SECRET_INPUT: ${{ toJSON(secrets) }}
EOF
expect_unsafe_workflow "$scratch/object-secret.yml" "secret object context"

cp "$release_workflow" "$scratch/bracket-github-token.yml"
cat >> "$scratch/bracket-github-token.yml" <<'EOF'
env:
  AUTH_INPUT: ${{ github['token'] }}
EOF
expect_unsafe_workflow "$scratch/bracket-github-token.yml" "bracket GitHub token context"

cp "$release_workflow" "$scratch/object-github-token.yml"
cat >> "$scratch/object-github-token.yml" <<'EOF'
env:
  AUTH_INPUT: ${{ toJSON(github) }}
EOF
expect_unsafe_workflow "$scratch/object-github-token.yml" "GitHub context object"

awk '!changed && /persist-credentials:[[:space:]]*false/ {sub(/false/, "true"); changed=1} {print}' "$release_workflow" > "$scratch/persist-true.yml"
expect_unsafe_workflow "$scratch/persist-true.yml" "persisted checkout credential"

cp "$release_workflow" "$scratch/missing-persist.yml"
cat >> "$scratch/missing-persist.yml" <<'EOF'
  hostile-checkout:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        # persist-credentials: false
EOF
expect_unsafe_workflow "$scratch/missing-persist.yml" "checkout credential omission"

cp "$release_workflow" "$scratch/indented-missing-persist.yml"
cat >> "$scratch/indented-missing-persist.yml" <<'EOF'
  hostile-indented-checkout:
    runs-on: ubuntu-latest
    steps:
        - uses: actions/checkout@v7
          # persist-credentials: false
EOF
expect_unsafe_workflow "$scratch/indented-missing-persist.yml" "indented checkout credential omission"

awk '{if ($0 ~ /uses: actions\/checkout@v7/) sub(/uses: /, "uses: \&checkout_action "); print}' "$release_workflow" > "$scratch/checkout-anchor.yml"
cat >> "$scratch/checkout-anchor.yml" <<'EOF'
  hostile-aliased-checkout:
    runs-on: ubuntu-latest
    steps:
      - uses: *checkout_action
EOF
expect_unsafe_workflow "$scratch/checkout-anchor.yml" "aliased checkout credential omission"

awk '
  /run:.*govulncheck.*-test/ {
    match($0, /[^ ]/)
    prefix = substr($0, 1, RSTART - 1)
    print prefix "# " substr($0, RSTART)
    print prefix "run: \"true\""
    next
  }
  {print}
' "$release_workflow" > "$scratch/commented-source-scan.yml"
expect_missing_workflow_proof "$scratch/commented-source-scan.yml" "commented source vulnerability scan"

awk '
  /- name: Source vulnerability scan/ {print; print "        if: false"; next}
  {print}
' "$release_workflow" > "$scratch/disabled-source-scan.yml"
expect_missing_workflow_proof "$scratch/disabled-source-scan.yml" "disabled source vulnerability scan"

awk '
  /run:.*govulncheck.*-test/ {print "        run: true"; changed=1; next}
  {print}
  END {
    if (changed) {
      print "x-dead-proof: |"
      print "        run: '\''\"$(go env GOPATH)/bin/govulncheck\" -test ./...'\''"
    }
  }
' "$release_workflow" > "$scratch/dead-source-scan.yml"
expect_missing_workflow_proof "$scratch/dead-source-scan.yml" "dead YAML source vulnerability scan"

fixture="$scratch/fixture"
fixture_git_root="$scratch/fixture-git"
dist="$fixture/dist"
mock_log="$scratch/mock.log"
mkdir -p "$fixture" "$fixture_git_root"
test_fixture_git "$fixture_git_root" -C "$fixture" init -q
printf 'fixture source\n' > "$fixture/source.txt"
printf 'dist/\noutside\n' > "$fixture/.gitignore"
test_fixture_git "$fixture_git_root" -C "$fixture" add source.txt .gitignore
test_fixture_git "$fixture_git_root" -C "$fixture" -c user.name=fixture -c user.email=fixture.invalid commit --no-gpg-sign -q -m fixture
mock_commit="$(test_fixture_git "$fixture_git_root" -C "$fixture" rev-parse HEAD)"
mkdir -p "$dist"

make_binary() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  printf 'fixture binary\n' > "$path"
}

make_binary "$dist/goplaces_darwin_darwin_amd64_v1/goplaces"
make_binary "$dist/goplaces_darwin_darwin_arm64_v8.0/goplaces"
make_binary "$dist/goplaces_linux_amd64_v1/goplaces"
make_binary "$dist/goplaces_linux_arm64_v8.0/goplaces"
make_binary "$dist/goplaces_windows_amd64_v1/goplaces.exe"
make_binary "$dist/goplaces_windows_arm64_v8.0/goplaces.exe"

jq -n --arg d "$dist" '[
  {type:"Binary", goos:"darwin", goarch:"amd64", target:"darwin_amd64_v1", name:"goplaces", path:($d + "/goplaces_darwin_darwin_amd64_v1/goplaces"), extra:{ID:"goplaces_darwin"}},
  {type:"Binary", goos:"darwin", goarch:"arm64", target:"darwin_arm64_v8.0", name:"goplaces", path:($d + "/goplaces_darwin_darwin_arm64_v8.0/goplaces"), extra:{ID:"goplaces_darwin"}},
  {type:"Binary", goos:"linux", goarch:"amd64", target:"linux_amd64_v1", name:"goplaces", path:($d + "/goplaces_linux_amd64_v1/goplaces"), extra:{ID:"goplaces"}},
  {type:"Binary", goos:"linux", goarch:"arm64", target:"linux_arm64_v8.0", name:"goplaces", path:($d + "/goplaces_linux_arm64_v8.0/goplaces"), extra:{ID:"goplaces"}},
  {type:"Binary", goos:"windows", goarch:"amd64", target:"windows_amd64_v1", name:"goplaces.exe", path:($d + "/goplaces_windows_amd64_v1/goplaces.exe"), extra:{ID:"goplaces"}},
  {type:"Binary", goos:"windows", goarch:"arm64", target:"windows_arm64_v8.0", name:"goplaces.exe", path:($d + "/goplaces_windows_arm64_v8.0/goplaces.exe"), extra:{ID:"goplaces"}}
]' > "$dist/artifacts.json"
jq -n --arg commit "$mock_commit" '{project_name:"goplaces", version:"0.0.0-test", commit:$commit}' > "$dist/metadata.json"

mock_go="$scratch/go"
mock_govulncheck="$scratch/govulncheck"
cat > "$mock_go" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'go %s\n' "$*" >> "$MOCK_LOG"
binary="${3:?missing binary}"
case "$binary" in
  *darwin_amd64*) goos=darwin; goarch=amd64 ;;
  *darwin_arm64*) goos=darwin; goarch=arm64 ;;
  *linux_amd64*) goos=linux; goarch=amd64 ;;
  *linux_arm64*) goos=linux; goarch=arm64 ;;
  *windows_amd64*) goos=windows; goarch=amd64 ;;
  *windows_arm64*) goos=windows; goarch=arm64 ;;
  *) exit 2 ;;
esac
toolchain=go1.26.5
main=github.com/steipete/goplaces/cmd/goplaces
if [[ "${MOCK_BUILD_INFO_FAULT:-}" == "toolchain" ]]; then toolchain=go0.0.0; fi
if [[ "${MOCK_BUILD_INFO_FAULT:-}" == "main" ]]; then main=example.invalid/hostile; fi
if [[ "${MOCK_BUILD_INFO_FAULT:-}" == "target" ]]; then goos=hostile; fi
printf '%s: %s\n' "$binary" "$toolchain"
printf '\tpath\t%s\n' "$main"
printf '\tbuild\tCGO_ENABLED=0\n'
printf '\tbuild\tGOOS=%s\n' "$goos"
printf '\tbuild\tGOARCH=%s\n' "$goarch"
revision="$MOCK_COMMIT"
if [[ "${MOCK_BUILD_INFO_FAULT:-}" == "revision" ]]; then revision=0000000000000000000000000000000000000000; fi
if [[ "${MOCK_BUILD_INFO_FAULT:-}" != "missing_revision" ]]; then
  printf '\tbuild\tvcs.revision=%s\n' "$revision"
fi
modified=false
if [[ "${MOCK_BUILD_INFO_FAULT:-}" == "modified" ]]; then modified=true; fi
printf '\tbuild\tvcs.modified=%s\n' "$modified"
EOF
cat > "$mock_govulncheck" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'govulncheck %s\n' "$*" >> "$MOCK_LOG"
[[ "${MOCK_GOVULN_FAIL:-0}" != "1" ]] || exit 42
EOF
chmod +x "$mock_go" "$mock_govulncheck"

verify_fixture() {
  (
    cd "$fixture"
    env \
      MOCK_BUILD_INFO_FAULT="${MOCK_BUILD_INFO_FAULT:-}" \
      MOCK_GOVULN_FAIL="${MOCK_GOVULN_FAIL:-0}" \
      MOCK_LOG="$mock_log" \
      MOCK_COMMIT="$mock_commit" \
      GO_BIN="$mock_go" \
      GOVULNCHECK_BIN="$mock_govulncheck" \
      SNAPSHOT_EXPECTED_COMMIT="$mock_commit" \
      SNAPSHOT_REQUIRE_CLEAN=1 \
      "$repo_root/scripts/verify-snapshot-security.sh" "$dist"
  )
}

verify_fixture >/dev/null
[[ "$(grep -c '^go version -m ' "$mock_log")" -eq 6 ]] || die "expected six build-info checks"
[[ "$(grep -c '^govulncheck -db=https://vuln.go.dev -mode=binary ' "$mock_log")" -eq 6 ]] || die "expected six official-database binary vulnerability scans"

cp "$dist/artifacts.json" "$scratch/artifacts.good.json"
jq 'del(.[0])' "$scratch/artifacts.good.json" > "$dist/artifacts.json"
if verify_fixture >/dev/null 2>&1; then
  die "missing snapshot target was accepted"
fi

jq '. + [.[0]]' "$scratch/artifacts.good.json" > "$dist/artifacts.json"
if verify_fixture >/dev/null 2>&1; then
  die "duplicate snapshot target was accepted"
fi

jq '.[0].extra.ID = "hostile"' "$scratch/artifacts.good.json" > "$dist/artifacts.json"
if verify_fixture >/dev/null 2>&1; then
  die "unexpected GoReleaser build ID was accepted"
fi

jq '.[0].extra.ID = "goplaces"' "$scratch/artifacts.good.json" > "$dist/artifacts.json"
if verify_fixture >/dev/null 2>&1; then
  die "Darwin binary from the unsigned build lane was accepted"
fi

cp "$scratch/artifacts.good.json" "$dist/artifacts.json"
cp "$dist/metadata.json" "$scratch/metadata.good.json"
jq '.commit = "0000000000000000000000000000000000000000"' "$scratch/metadata.good.json" > "$dist/metadata.json"
if verify_fixture >/dev/null 2>&1; then
  die "snapshot metadata for the wrong commit was accepted"
fi
cp "$scratch/metadata.good.json" "$dist/metadata.json"

for fault in toolchain main target revision missing_revision modified; do
  if MOCK_BUILD_INFO_FAULT="$fault" verify_fixture >/dev/null 2>&1; then
    die "hostile $fault build information was accepted"
  fi
done

make_binary "$dist/wrong/goplaces"
jq --arg path "$dist/wrong/goplaces" '.[0].path = $path' "$scratch/artifacts.good.json" > "$dist/artifacts.json"
if verify_fixture >/dev/null 2>&1; then
  die "wrong in-dist snapshot path was accepted"
fi
cp "$scratch/artifacts.good.json" "$dist/artifacts.json"

test_fixture_git "$fixture_git_root" -C "$fixture" config status.showUntrackedFiles no
printf 'package hostile\n' > "$fixture/hidden.go"
if verify_fixture >/dev/null 2>&1; then
  die "hidden untracked Go source was accepted"
fi
mv "$fixture/hidden.go" "$scratch/hidden.go"
test_fixture_git "$fixture_git_root" -C "$fixture" config --unset status.showUntrackedFiles

make_binary "$fixture/outside"
jq --arg path "$dist/../outside" '.[0].path = $path' "$scratch/artifacts.good.json" > "$dist/artifacts.json"
if verify_fixture >/dev/null 2>&1; then
  die "snapshot path traversal was accepted"
fi
cp "$scratch/artifacts.good.json" "$dist/artifacts.json"

darwin_binary="$dist/goplaces_darwin_darwin_amd64_v1/goplaces"
mv "$darwin_binary" "$scratch/darwin.good"
ln -s "$fixture/outside" "$darwin_binary"
if verify_fixture >/dev/null 2>&1; then
  die "symlinked snapshot binary was accepted"
fi
mv -f "$scratch/darwin.good" "$darwin_binary"

if MOCK_GOVULN_FAIL=1 verify_fixture >/dev/null 2>&1; then
  die "failing binary vulnerability scan was ignored"
fi

: > "$dist/goplaces_darwin_darwin_amd64_v1/goplaces"
if verify_fixture >/dev/null 2>&1; then
  die "empty snapshot binary was accepted"
fi

echo "security CI test: workflow and hostile snapshot checks passed"
