#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031,SC2034,SC2154,SC2329
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
release_script="${repo_root}/scripts/release-local"
# shellcheck source=scripts/test-git-fixture.sh
source "${repo_root}/scripts/test-git-fixture.sh"
readonly SHA="1111111111111111111111111111111111111111"
readonly TAG_OBJECT="2222222222222222222222222222222222222222"
readonly TAG_COMMIT="$SHA"

die() {
  echo "release-local test: $*" >&2
  exit 1
}

expect_failure() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    die "$name unexpectedly succeeded"
  fi
}

test_sha256() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

test_jq_freeze_survives_command_substitution() {
  local scratch output
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-jq-freeze.XXXXXX")"
  output="${scratch}/second.json"
  (
    source_release
    ensure_git_isolation
    [[ "$(jq -nr '"first"')" == first ]] || exit 80
    [[ -z "$jq_binary" ]] || exit 81
    [[ -f "${git_isolation_root}/parser-bin/jq" && ! -L "${git_isolation_root}/parser-bin/jq" ]] || exit 82
    [[ "$($STAT_BIN -f '%Lp' "${git_isolation_root}/parser-bin/jq")" == 500 ]] || exit 83
    jq -n '"second"' > "$output"
    [[ "$jq_binary" == "${git_isolation_root}/parser-bin/jq" ]] || exit 84
    recheck_jq_parser
  )
  [[ "$(jq -er . "$output")" == second ]] || die "parent jq did not adopt the command-substitution parser copy"
  rm -rf "$scratch"
}

test_identity() {
  /usr/bin/stat -f '%d:%i' "$1"
}

test_verifier_nonce() {
  local tag="$1" state="$2" release_id="$3" record_sha256="$4" attempt="$5"
  printf '%s\n' \
    goplaces-verifier-intent-v1 "$tag" "$state" "$TAG_OBJECT" "$TAG_COMMIT" "$SHA" \
    "$release_id" "$record_sha256" "$attempt" |
    /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

source_release() {
  GOPLACES_RELEASE_LOCAL_TESTING=1
  GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
  export GOPLACES_RELEASE_LOCAL_TESTING GOPLACES_RELEASE_LOCAL_SOURCE_ONLY
  # shellcheck source=release-local
  source "$release_script"
  protected_source_root="$repo_root"
  ensure_git_isolation
}

test_static_contract() {
  local download_line offline_line brew_test_line post_brew_status_line override_output tap_predispatch_line tap_dispatch_line mutation_shape
  local mutation_root mutation_gh mutation_sentinel mutation_error
  bash -n "$release_script"
  [[ "$(head -n 1 "$release_script")" == '#!/bin/bash -p' ]] || die "release entrypoint does not ignore BASH_ENV at startup"
  grep -Fq 'codesign-run -- /usr/bin/env' "$release_script" || die "draft/pilot must use release-mac-app codesign-run"
  [[ "$(grep -Fc '/bin/bash -p "$release_mac_app" codesign-run --' "$release_script")" == 2 ]] || die "release-mac-app is not entered through fixed privileged Bash"
  grep -Fq 'IFS= read -r GITHUB_TOKEN <&3; exec 3<&-; export GITHUB_TOKEN; exec "$@"' "$release_script" || die "draft authentication is not deferred until the protected producer command"
  grep -Fq '/usr/bin/env -i' "$release_script" || die "release-mac-app does not receive an empty outer environment"
  ! grep -Fq -- '--with-package-secrets' "$release_script" || die "producer still allows package-secret loading inside release-mac-app"
  grep -Fq 'GOPLACES_OFFICIAL_RELEASE=1' "$release_script" || die "official producer mode is missing"
  grep -Fq 'X-GitHub-Api-Version: ${API_VERSION}' "$release_script" || die "GitHub API version header is missing"
  grep -Fq 'readonly API_VERSION="2026-03-10"' "$release_script" || die "GitHub API version is not pinned"
  grep -Fq 'test controls are restricted to paired source-only fixtures' "$release_script" || die "production entrypoint does not reject test overrides"
  override_output="$(GOPLACES_RELEASE_LOCAL_TESTING=1 "$release_script" 2>&1 || true)"
  grep -Fq 'test controls are restricted to paired source-only fixtures' <<<"$override_output" || die "unpaired release test mode reached the production entrypoint"
  override_output="$(GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 "$release_script" --check 2>&1 || true)"
  if GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 "$release_script" --check >/dev/null 2>&1; then
    die "paired source-only test mode false-passed as a direct invocation"
  fi
  grep -Fq 'source-only test mode cannot be executed directly' <<<"$override_output" ||
    die "paired source-only direct invocation failed outside the entrypoint guard"
  grep -Fq 'source-only test mode cannot use a GitHub mutation transport' "$release_script" || die "test mode can reach GitHub mutation transports"
  grep -Fq 'source-only test mode cannot mutate or execute Homebrew packages' "$release_script" || die "test mode can reach Homebrew mutation transports"
  expect_failure "source-only real credential transport" bash -p -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; gh_auth_token
  ' _ "$release_script"
  mutation_root="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-mutation-guard.XXXXXX")"
  mutation_gh="${mutation_root}/gh"
  mutation_sentinel="${mutation_root}/transport-ran"
  mutation_error="${mutation_root}/error"
  cat > "$mutation_gh" <<'EOF'
#!/bin/bash -p
touch "$MUTATION_SENTINEL"
exit 0
EOF
  chmod +x "$mutation_gh"
  for mutation_shape in '-X post' '--method=post' '--method post' '-f value=hostile' '-fvalue=hostile' '-Fvalue=hostile' '--field=value=hostile' '--raw-field=value=hostile' '--input=/tmp/hostile'; do
    rm -f "$mutation_sentinel" "$mutation_error"
    if /bin/bash -p -c '
      export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
      export MOCK_FIXTURE_ROOT="$3" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="$4" MUTATION_SENTINEL="$5"
      source "$1"
      case "$2" in
        "-X post") gh_api -X post repos/openclaw/goplaces ;;
        "--method=post") gh_api --method=post repos/openclaw/goplaces ;;
        "--method post") gh_api --method post repos/openclaw/goplaces ;;
        "-f value=hostile") gh_api -f value=hostile repos/openclaw/goplaces ;;
        "-fvalue=hostile") gh_api -fvalue=hostile repos/openclaw/goplaces ;;
        "-Fvalue=hostile") gh_api -Fvalue=hostile repos/openclaw/goplaces ;;
        "--field=value=hostile") gh_api --field=value=hostile repos/openclaw/goplaces ;;
        "--raw-field=value=hostile") gh_api --raw-field=value=hostile repos/openclaw/goplaces ;;
        "--input=/tmp/hostile") gh_api --input=/tmp/hostile repos/openclaw/goplaces ;;
      esac
    ' _ "$release_script" "$mutation_shape" "$mutation_root" "$mutation_gh" "$mutation_sentinel" >/dev/null 2>"$mutation_error"; then
      die "source-only GitHub mutation shape $mutation_shape unexpectedly succeeded"
    fi
    grep -Fq 'source-only test mode cannot use a GitHub mutation transport' "$mutation_error" ||
      die "source-only GitHub mutation shape $mutation_shape failed outside the guard"
    [[ ! -e "$mutation_sentinel" ]] || die "source-only GitHub mutation shape $mutation_shape reached the transport"
  done
  rm -rf "$mutation_root"
  expect_failure "source-only Homebrew option-prefix mutation" /bin/bash -p -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; homebrew_command --debug install --formula hostile.rb
  ' _ "$release_script"
  grep -Fq 'readonly TAP_BASE="45b93a0b3de27e46b636a0cef819fb1ecef25bcd"' "$release_script" || die "tap trust base is not pinned"
  grep -Fq 'readonly TAP_WORKFLOW_ID="220664022"' "$release_script" || die "tap workflow numeric identity is not pinned"
  grep -Fq 'readonly TAR_BIN="/usr/bin/bsdtar"' "$release_script" || die "system tar does not name the canonical nonsymlink executable"
  grep -Fq 'HOMEBREW_NO_INSTALL_FROM_API=1' "$release_script" || die "Homebrew package inventory can trigger API installation"
  grep -Fq 'homebrew_command list "$kind_flag" --full-name' "$release_script" || die "Homebrew installed-state proof is not a no-name full inventory"
  grep -Fq 'homebrew_command --prefix --formula goplaces' "$release_script" || die "installed binary lookup is not Formula-specific"
  grep -Fq 'readonly EXPECTED_GH_VERSION="2.96.0"' "$release_script" || die "GitHub CLI version is not pinned"
  grep -Fq 'candidate=/opt/homebrew/opt/gh/bin/gh' "$release_script" || die "GitHub CLI does not bypass the mutable bin wrapper"
  ! grep -Fq 'candidate=/opt/homebrew/bin/gh' "$release_script" || die "GitHub CLI still freezes the mutable wrapper"
  grep -Fq "select(.path == \$path)" "$release_script" || die "workflow path is not exact"
  if grep -Eq 'release(s)?/latest|/releases/tags/' "$release_script"; then
    die "release flow uses a mutable latest or tag-name release endpoint"
  fi
  if grep -Eq '(^|[[:space:]])(spctl|syspolicy|syspolicy_check|stapler)([[:space:]]|$)|/usr/bin/security|[[:space:]]op[[:space:]]' "$release_script"; then
    die "release flow directly invokes a forbidden keychain or policy CLI"
  fi
  grep -Fq 'gh_api --method PATCH "repos/${REPOSITORY}/releases/${release_id}"' "$release_script" || die "publication is not a numeric release PATCH"
  grep -Fq 'dispatch_verifier "$tag" published' "$release_script" || die "publication lacks post-PATCH public verifier"
  grep -Fq 'prepare_remote_source "$protected_source_root" pilot' "$release_script" || die "protected release source is not fetched from the remote"
  grep -Fq 'prepare_remote_source "$source" tagged "$tag"' "$release_script" || die "draft is not pinned to fresh remote tag source"
  [[ "$(grep -Fc 'prepare_remote_source "$source" tagged "$tag"' "$release_script")" == 1 ]] || die "draft prepares tagged source more than once"
  grep -Fq -- '-f "inputs[release_id]=${release_id}"' "$release_script" || die "numeric release ID dispatch input is not encoded as the declared string"
  ! grep -Fq -- '-F "inputs[release_id]=' "$release_script" || die "numeric release ID dispatch input uses typed JSON encoding"
  grep -Fq 'run_protected_script scripts/verify-macos-binary.sh "$installed" "$host_arch" "$version" execute' "$release_script" || die "Homebrew proof does not use the protected positional native verifier interface"
  [[ "$(grep -Fc 'status --porcelain --untracked-files=all' "$release_script")" == 4 ]] || die "security status calls do not use the exact required argv"
  [[ "$(grep -Fc 'recheck_tap_install_source "$tap_source"' "$release_script")" == 1 ]] || die "Homebrew proof lacks one post-test clean-checkout recheck"
  brew_test_line="$(grep -nF 'homebrew_command test "$formula"' "$release_script" | cut -d: -f1)"
  post_brew_status_line="$(grep -nF 'recheck_tap_install_source "$tap_source"' "$release_script" | cut -d: -f1)"
  [[ "$brew_test_line" =~ ^[0-9]+$ && "$post_brew_status_line" =~ ^[0-9]+$ && "$brew_test_line" -lt "$post_brew_status_line" ]] || die "tap checkout is not rechecked after brew test"
  ! grep -Fq 'status --porcelain=v1' "$release_script" || die "security status uses a noncanonical porcelain spelling"
  grep -Fq 'rev-parse --path-format=absolute --git-path info/grafts' "$release_script" || die "ancestry gate does not resolve the legacy graft path"
  grep -Fq "for-each-ref --format='%(refname)' refs/replace/" "$release_script" || die "ancestry gate does not reject replacement refs"
  grep -Fq 'readonly SYSTEM_GIT_BIN="/usr/bin/git"' "$release_script" || die "production Git is not pinned to /usr/bin/git"
  grep -Fq 'verify_tag_signature "$repo_root" "$observed_object" "$allowed_signers"' "$release_script" || die "local signature verification is not pinned to the observed tag object"
  [[ "$(grep -Fc 'isolated_git cat-file -p "$observed_object"' "$release_script")" == 3 ]] || die "tag payload fields are not read from the observed tag object"
  ! grep -Fq 'isolated_git cat-file -p "$ref"' "$release_script" || die "tag payload still dereferences the mutable local ref"
  grep -Fq 'local tag object moved during signature verification' "$release_script" || die "local tag object lacks a post-signature recheck"
  grep -Fq 'local tag commit moved during signature verification' "$release_script" || die "local tag commit lacks a post-signature recheck"
  grep -Fq 'bind_release_tag_identity "$tag"' "$release_script" || die "tag identity is not persisted before release mutation"
  grep -Fq 'fresh source tag verification record differs from frozen identity' "$release_script" || die "fresh source verifier output is not bound to the frozen tag"
  grep -Fq '[[ "$tap_head" == "$TAP_BASE" ]]' "$release_script" || die "tap head is not pinned to the reviewed trust anchor"
  grep -Fq 'prepare_tap_install_source "$tap_source" "$tap_result_head" "$verified_formula"' "$release_script" || die "Homebrew proof does not use a fresh exact-commit tap checkout"
  tap_predispatch_line="$(grep -nF 'recheck_tap_contract_before "${scratch}/tap-before-dispatch" "$tap_head" "$tap_workflow_id"' "$release_script" | cut -d: -f1)"
  tap_dispatch_line="$(grep -nF 'gh_api --method POST "repos/${TAP_REPOSITORY}/actions/workflows/${tap_workflow_id}/dispatches"' "$release_script" | cut -d: -f1)"
  [[ "$tap_predispatch_line" =~ ^[0-9]+$ && "$tap_dispatch_line" =~ ^[0-9]+$ && $((tap_predispatch_line + 1)) -eq tap_dispatch_line ]] ||
    die "exact tap predispatch recheck is not immediately before the workflow POST"
  grep -Fq 'readonly RELEASE_MAC_APP_DEFAULT="/Users/steipete/Projects/agent-scripts/skills/release-mac-app/scripts/mac-release"' "$release_script" || die "release-mac-app is not pinned independently of HOME"
  grep -Fq 'readonly RELEASE_MAC_APP_EXPECTED_SHA256="34bb6c6ac8529c3aa6d6b4bb738655840c4ae7c00595154219ef806b17460454"' "$release_script" || die "release-mac-app entrypoint digest is not pinned"
  grep -Fq 'readonly RELEASE_MAC_APP_LIB_EXPECTED_SHA256="ce78a32104c58ee3b5141a25a2dd74a99b00c4692bcd0e25df3fb5fadbe6fbb0"' "$release_script" || die "release-mac-app library digest is not pinned"
  grep -Fq '[[ "$source_digest" == "$RELEASE_MAC_APP_EXPECTED_SHA256" ]]' "$release_script" || die "release-mac-app entrypoint is not checked against reviewed bytes"
  grep -Fq '[[ "$source_lib_digest" == "$RELEASE_MAC_APP_LIB_EXPECTED_SHA256" ]]' "$release_script" || die "release-mac-app library is not checked against reviewed bytes"
  ! grep -Fq 'RELEASE_MAC_APP_DEFAULT="${HOME}' "$release_script" || die "release-mac-app still trusts ambient HOME"
  grep -Fq 'readonly SECRET_SCOPE_SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"' "$release_script" || die "secret-scope system PATH is not exact"
  grep -Fq 'PATH="$SECRET_SCOPE_SYSTEM_PATH"' "$release_script" || die "codesign-run does not enter with the system-only PATH"
  grep -Fq 'producer-bin.XXXXXX' "$release_script" || die "producer tools are not frozen outside Homebrew PATH prefixes"
  grep -Fq 'GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org' "$release_script" || die "check suite lacks an explicit authenticated-free module download phase"
  [[ "$(grep -Fc '/usr/bin/env -i PATH="$producer_path"' "$release_script")" == 2 ]] || die "check suite empty-environment launcher is not pinned"
  ! grep -Eq '^[[:space:]]+env -i PATH="\$producer_path"' "$release_script" || die "check suite trusts an ambient env executable"
  grep -Fq '"${download_env[@]}" "$go_bin" mod download all' "$release_script" || die "check suite does not populate its isolated module cache"
  ! grep -Fq 'need govulncheck' "$release_script" || die "check suite still depends on ambient govulncheck PATH"
  grep -Fq '"${download_env[@]}" GOBIN="$audit_bin" "$go_bin" install golang.org/x/vuln/cmd/govulncheck@v1.5.0' "$release_script" || die "check suite does not install pinned govulncheck with pinned Go"
  grep -Fq 'require_canonical_executable "$govulncheck_bin" "frozen govulncheck"' "$release_script" || die "installed govulncheck is not frozen before proof"
  grep -Fq 'readonly EXPECTED_GOVULNCHECK_MODULE_SUM="h1:jGVVuNZ7NrBJlFB7IBkZ/R9c8gYCja+SWqrHpBCYJZA="' "$release_script" || die "govulncheck reviewed module sum is not pinned"
  grep -Fq '"$go_bin" version -m "$govulncheck_bin"' "$release_script" || die "installed govulncheck build information is not inspected"
  grep -Fq "\$'\\tmod\\tgolang.org/x/vuln\\tv1.5.0\\t'" "$release_script" || die "installed govulncheck module identity is not checked"
  grep -Fq '/bin/chmod -R u+w "$scratch"' "$release_script" || die "check-suite module cache is not made removable"
  grep -Fq '"${clean_env[@]}" "$govulncheck_bin" -db=https://vuln.go.dev -test ./...' "$release_script" || die "source vulnerability scan does not pin the official database URL"
  grep -Fq 'SNAPSHOT_EXPECTED_COMMIT="$default_sha" SNAPSHOT_REQUIRE_CLEAN=1' "$release_script" || die "local snapshot proof is not bound to protected clean source"
  grep -Fq 'GO_BIN="$go_bin" ./scripts/test-reproducible-builds.sh dist' "$release_script" || die "local reproducibility gate does not compare generated snapshot artifacts"
  download_line="$(grep -nF '"${download_env[@]}" "$go_bin" mod download all' "$release_script" | cut -d: -f1)"
  govuln_install_line="$(grep -nF '"${download_env[@]}" GOBIN="$audit_bin" "$go_bin" install golang.org/x/vuln/cmd/govulncheck@v1.5.0' "$release_script" | cut -d: -f1)"
  offline_line="$(grep -nF 'GOPROXY=off GOSUMDB=off' "$release_script" | head -n 1 | cut -d: -f1)"
  [[ "$download_line" =~ ^[0-9]+$ && "$govuln_install_line" =~ ^[0-9]+$ && "$offline_line" =~ ^[0-9]+$ && "$download_line" -lt "$govuln_install_line" && "$govuln_install_line" -lt "$offline_line" ]] || die "offline proof begins before dependencies and pinned govulncheck are populated"
  grep -Fq './scripts/recheck-release-source.sh' "$release_script" || die "codesign-run lacks its protected post-manifest source recheck"
  [[ "$(grep -Fc 'status --porcelain --untracked-files=all' "${repo_root}/scripts/recheck-release-source.sh")" == 1 ]] || die "post-manifest source recheck lacks exact status argv"
  ! grep -Fq 'status --porcelain=v1' "${repo_root}/scripts/recheck-release-source.sh" || die "post-manifest source recheck uses a noncanonical porcelain spelling"
  grep -Fq 'exec "$goreleaser_bin" "${goreleaser_arguments[@]}"' "${repo_root}/scripts/recheck-release-source.sh" || die "post-manifest source recheck does not exec the pinned absolute GoReleaser"
  grep -Fq 'PATH="${producer_bin}:${system_path}"' "${repo_root}/scripts/recheck-release-source.sh" || die "post-manifest producer PATH is not frozen"
  grep -Fq 'GOPLACES_RELEASE_TEST_MODE' "$release_script" || die "official producer does not remove signing test controls"
  grep -Fq 'PATH=$SYSTEM_PATH' "${repo_root}/scripts/codesign-macos.sh" || die "official signing hook does not reset to system PATH"
  if grep -Eq 'homebrew_|HOMEBREW_|com\.apple\.quarantine|xattr' "${repo_root}/.goreleaser.yml"; then
    die "GoReleaser still owns Homebrew or quarantine mutation"
  fi
  grep -Eq '^[[:space:]]+draft:[[:space:]]*true' "${repo_root}/.goreleaser.yml" || die "GoReleaser release is not draft-only"
}

test_govulncheck_build_info_validation() {
  local binary good bad
  binary="/private/tmp/frozen/govulncheck"
  good="${binary}: go1.26.5"$'\n\tpath\tgolang.org/x/vuln/cmd/govulncheck\n\tmod\tgolang.org/x/vuln\tv1.5.0\th1:jGVVuNZ7NrBJlFB7IBkZ/R9c8gYCja+SWqrHpBCYJZA='
  (
    source_release
    validate_govulncheck_build_info "$good" "$binary"
  )
  for bad in \
    "${good/go1.26.5/go1.26.4}" \
    "${good/golang.org\/x\/vuln\/cmd\/govulncheck/example.invalid\/govulncheck}" \
    "${good/v1.5.0/v1.4.2}" \
    "${good/jGVVuNZ7NrBJlFB7IBkZ\/R9c8gYCja+SWqrHpBCYJZA=/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=}"; do
    if (
      source_release
      validate_govulncheck_build_info "$bad" "$binary"
    ) >/dev/null 2>&1; then
      die "hostile govulncheck build information was accepted"
    fi
  done
}

test_run_shape() {
  local scratch good bad title
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-run-shape.XXXXXX")"
  good="${scratch}/good.json"
  bad="${scratch}/bad.json"
  title="Verify v0.4.5 draft assets at ${SHA} for ${TAG_COMMIT} object ${TAG_OBJECT}"
  jq -n \
    --argjson id 29009699237 \
    --argjson workflow_id 309911276 \
    --arg path .github/workflows/release-assets.yml \
    --arg title "$title" \
    --arg sha "$SHA" \
    '{id:$id,workflow_id:$workflow_id,path:$path,display_title:$title,event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",created_at:"2026-07-10T10:00:00Z"}' > "$good"
  (
    source_release
    assert_exact_run "$good" 29009699237 309911276 .github/workflows/release-assets.yml "$title" main "$SHA" true
  )
  jq '.id = 9007199254740992' "$good" > "$bad"
  expect_failure "overflow exact run ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; assert_exact_run "$2" 9007199254740992 309911276 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"
  jq '.workflow_id = 9007199254740992' "$good" > "$bad"
  expect_failure "overflow exact workflow ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; assert_exact_run "$2" 29009699237 9007199254740992 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"
  jq '.workflow_id = 309911277' "$good" > "$bad"
  expect_failure "valid wrong workflow ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; assert_exact_run "$2" 29009699237 309911276 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"
  jq '.head_branch = "release"' "$good" > "$bad"
  expect_failure "wrong protected head branch" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; assert_exact_run "$2" 29009699237 309911276 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"
  jq '.head_sha = "3333333333333333333333333333333333333333"' "$good" > "$bad"
  expect_failure "wrong protected head SHA" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; assert_exact_run "$2" 29009699237 309911276 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"
  jq '.path = ".github/workflows/release-assets.yml@main"' "$good" > "$bad"
  expect_failure "native run @branch path" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"
    assert_exact_run "$2" 29009699237 309911276 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"
  jq '.path = "./.github/workflows/release-assets.yml"' "$good" > "$bad"
  expect_failure "native run leading-dot path" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"
    assert_exact_run "$2" 29009699237 309911276 .github/workflows/release-assets.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "$title" "$SHA"

  jq -n \
    --argjson id 29010348667 \
    --argjson workflow_id 220664022 \
    --arg path .github/workflows/update-formula.yml \
    --arg title "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" \
    --arg sha "$SHA" \
    '{id:$id,workflow_id:$workflow_id,path:$path,display_title:$title,event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",created_at:"2026-07-10T10:00:00Z",run_attempt:1,repository:{full_name:"openclaw/homebrew-tap"},url:("https://api.github.com/repos/openclaw/homebrew-tap/actions/runs/"+($id|tostring)),html_url:("https://github.com/openclaw/homebrew-tap/actions/runs/"+($id|tostring))}' > "$good"
  (
    source_release
    assert_exact_run "$good" 29010348667 220664022 .github/workflows/update-formula.yml "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" main "$SHA" true
    tap_workflow_id=220664022
    tap_default_branch=main
    tap_head="$SHA"
    assert_tap_run "$good" 29010348667 "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" true
  )
  jq '.workflow_id = 220664023' "$good" > "$bad"
  expect_failure "tap valid wrong workflow ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; tap_workflow_id=220664022; tap_default_branch=main; tap_head="$4"
    assert_tap_run "$2" 29010348667 "$3" true
  ' _ "$release_script" "$bad" "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" "$SHA"
  jq '.head_branch = "release"' "$good" > "$bad"
  expect_failure "tap wrong protected branch" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; tap_workflow_id=220664022; tap_default_branch=main; tap_head="$4"
    assert_tap_run "$2" 29010348667 "$3" true
  ' _ "$release_script" "$bad" "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" "$SHA"
  jq '.head_sha = "3333333333333333333333333333333333333333"' "$good" > "$bad"
  expect_failure "tap wrong protected head SHA" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; tap_workflow_id=220664022; tap_default_branch=main; tap_head="$4"
    assert_tap_run "$2" 29010348667 "$3" true
  ' _ "$release_script" "$bad" "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" "$SHA"
  jq '.path = ".github/workflows/update-formula.yml@main"' "$good" > "$bad"
  expect_failure "tap run @branch path" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"
    assert_exact_run "$2" 29010348667 220664022 .github/workflows/update-formula.yml "$3" main "$4" true
  ' _ "$release_script" "$bad" "Update goplaces for v0.4.5 (request-id=req; source-tag-object=${TAG_OBJECT}; source-tag-commit=${TAG_COMMIT})" "$SHA"
  rm -rf "$scratch"
}

test_workflow_record_uses_filename_lookup() {
  local scratch mock_bin log output nested_error before_calls
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-workflow-record.XXXXXX")"
  mock_bin="${scratch}/bin"
  log="${scratch}/gh.log"
  output="${scratch}/workflow.json"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/gh" <<'EOF'
#!/bin/bash -p
set -euo pipefail
printf '%s\n' "$*" >> "$WORKFLOW_LOOKUP_LOG"
endpoint="${*: -1}"
case "$endpoint" in
  repos/openclaw/goplaces/actions/workflows/release-assets.yml)
    printf '{"id":309911276,"path":".github/workflows/release-assets.yml","state":"active"}\n'
    ;;
  repos/openclaw/homebrew-tap/actions/workflows/update-formula.yml)
    printf '{"id":220664022,"path":".github/workflows/update-formula.yml","state":"active"}\n'
    ;;
  *) exit 90 ;;
esac
EOF
  chmod +x "${mock_bin}/gh"
  (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH WORKFLOW_LOOKUP_LOG="$log" MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
    workflow_record openclaw/goplaces .github/workflows/release-assets.yml "$output"
    workflow_record openclaw/homebrew-tap .github/workflows/update-formula.yml "$output"
  )
  grep -Fq 'repos/openclaw/goplaces/actions/workflows/release-assets.yml' "$log" || die "native workflow lookup did not use the workflow filename"
  grep -Fq 'repos/openclaw/homebrew-tap/actions/workflows/update-formula.yml' "$log" || die "tap workflow lookup did not use the workflow filename"
  ! grep -Fq 'actions/workflows/.github/workflows/' "$log" || die "workflow lookup embedded the canonical path as URL segments"
  nested_error="${scratch}/nested-error"
  before_calls="$(wc -l < "$log" | tr -d '[:space:]')"
  if WORKFLOW_LOOKUP_LOG="$log" MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh" /bin/bash -p -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; workflow_record openclaw/goplaces .github/workflows/nested/release-assets.yml "$2"
  ' _ "$release_script" "$output" >/dev/null 2>"$nested_error"; then
    die "nested workflow lookup path unexpectedly succeeded"
  fi
  grep -Fq 'workflow path is not a canonical top-level Actions workflow' "$nested_error" ||
    die "nested workflow lookup failed outside the path guard"
  [[ "$(wc -l < "$log" | tr -d '[:space:]')" == "$before_calls" ]] ||
    die "nested workflow lookup reached the GitHub transport"
  rm -rf "$scratch"
}

test_dispatch_response_binding() {
  local scratch response seen
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-dispatch-shape.XXXXXX")"
  response="${scratch}/response.json"
  seen="${scratch}/seen.json"
  printf '[100,200]\n' > "$seen"
  printf '{"workflow_run_id":29009699237,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/29009699237","html_url":"https://github.com/openclaw/goplaces/actions/runs/29009699237"}\n' > "$response"
  [[ "$(
    source_release
    parse_new_dispatch_id "$response" "$seen" verifier openclaw/goplaces
  )" == "29009699237" ]] || die "numeric dispatch ID was not accepted"

  printf '{"workflow_run_id":"29009699237"}\n' > "$response"
  expect_failure "string dispatch ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{}\n' > "$response"
  expect_failure "missing dispatch ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{"workflow_run_id":200,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/200","html_url":"https://github.com/openclaw/goplaces/actions/runs/200"}\n' > "$response"
  expect_failure "pre-existing dispatch ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{"workflow_run_id":29009699237,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/1","html_url":"https://github.com/openclaw/goplaces/actions/runs/29009699237"}\n' > "$response"
  expect_failure "wrong dispatch run_url" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{"workflow_run_id":29009699237,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/29009699237","html_url":"https://github.com/openclaw/goplaces/actions/runs/1"}\n' > "$response"
  expect_failure "wrong dispatch html_url" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{"workflow_run_id":29009699237,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/29009699237"}\n' > "$response"
  expect_failure "missing dispatch html_url" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{"workflow_run_id":29009699237,"html_url":"https://github.com/openclaw/goplaces/actions/runs/29009699237"}\n' > "$response"
  expect_failure "missing dispatch run_url" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '{"workflow_run_id":9007199254740992,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/9007199254740992","html_url":"https://github.com/openclaw/goplaces/actions/runs/9007199254740992"}\n' > "$response"
  expect_failure "overflow dispatch run ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '[9007199254740992]\n' > "$seen"
  printf '{"workflow_run_id":29009699237,"run_url":"https://api.github.com/repos/openclaw/goplaces/actions/runs/29009699237","html_url":"https://github.com/openclaw/goplaces/actions/runs/29009699237"}\n' > "$response"
  expect_failure "overflow pre-dispatch run inventory" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; parse_new_dispatch_id "$2" "$3" verifier openclaw/goplaces
  ' _ "$release_script" "$response" "$seen"
  printf '[100,200]\n' > "$seen"
  printf '{"workflow_run_id":29010348667,"run_url":"https://api.github.com/repos/openclaw/homebrew-tap/actions/runs/29010348667","html_url":"https://github.com/openclaw/homebrew-tap/actions/runs/29010348667"}\n' > "$response"
  [[ "$(
    source_release
    parse_new_dispatch_id "$response" "$seen" tap openclaw/homebrew-tap
  )" == "29010348667" ]] || die "tap dispatch URL binding was not accepted"
  rm -rf "$scratch"
}

test_verifier_dispatch_recovers_without_duplicate_post() {
  local scratch state record intent log run_id title record_digest nonce poll_count
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-dispatch-recovery.XXXXXX")"
  state="${scratch}/state"
  record="${scratch}/record.json"
  intent="${state}/verifier-draft-intent.json"
  log="${scratch}/events"
  poll_count="${scratch}/poll-count"
  run_id=29009699237
  title="Verify v0.4.5 draft assets at ${SHA} for ${TAG_COMMIT} object ${TAG_OBJECT}"
  mkdir -p "$state"
  printf '0\n' > "$poll_count"
  jq -n '{state:"draft"}' > "$record"
  record_digest="$(test_sha256 "$record")"
  nonce="$(test_verifier_nonce v0.4.5 draft 777 "$record_digest" 1)"
  title="Verify v0.4.5 draft release 777 nonce ${nonce}"
  jq -n \
    --arg tag v0.4.5 --arg state draft --arg object "$TAG_OBJECT" --arg commit "$TAG_COMMIT" --arg main "$SHA" \
    --argjson release_id 777 --argjson workflow_id 309911276 --arg record_sha256 "$record_digest" \
    --arg title "$title" --arg created_after 2026-07-10T09:59:59Z --arg nonce "$nonce" \
    '{schema:"goplaces-verifier-intent-v1",tag:$tag,state:$state,tag_object:$object,tag_commit:$commit,
      default_sha:$main,release_id:$release_id,workflow_id:$workflow_id,release_record_sha256:$record_sha256,
      attempt:1,dispatch_nonce:$nonce,expected_title:$title,created_after:$created_after,
      seen_run_ids:[10,11],failed_run_ids:[]}' > "$intent"
  (
    source_release
    default_branch=main
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    release_state_dir="$state"
    workflow_record() { jq -n '{id:309911276}' > "$3"; }
    jq -n --argjson id 29009699237 --arg title "$title" --arg sha "$SHA" '{
        id:$id,workflow_id:309911276,path:".github/workflows/release-assets.yml",display_title:$title,
        event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",
        run_attempt:1,created_at:"2026-07-10T10:00:00Z"}' > "${scratch}/run.json"
    fetch_workflow_runs() {
      local count
      count="$(cat "$poll_count")"
      count=$((count + 1))
      printf '%s\n' "$count" > "$poll_count"
      if ((count <= 2)); then
        printf '{"workflow_runs":[]}\n' > "$4"
      else
        jq -n --slurpfile run "${scratch}/run.json" '{workflow_runs:$run}' > "$4"
      fi
    }
    get_run_with_retry() { /bin/cp "${scratch}/run.json" "$3"; }
    gh_watch_run() { printf 'watch:%s\n' "$2" >> "$log"; }
    verify_remote_tag() { :; }
    recheck_source_default() { :; }
    run_protected_script() {
      [[ "$1" == scripts/validate-verifier-dispatch.sh ]] || exit 83
      [[ "${EXPECTED_RELEASE_STATE:-}" == draft && "${EXPECTED_TAG_COMMIT:-}" == "$TAG_COMMIT" &&
        "${EXPECTED_TAG_OBJECT:-}" == "$TAG_OBJECT" && "${EXPECTED_RUN_ID:-}" == "$run_id" &&
        "${EXPECTED_DISPATCH_NONCE:-}" == "$nonce" && "${RECOVERED_DISPATCH:-}" == 1 ]] || exit 84
      printf 'validated-nonce\n' >> "$log"
    }
    run_release_verifier_check() { printf 'proof:%s\n' "$4" >> "$log"; }
    gh_api() {
      if [[ " $* " == *' --method POST '* ]]; then
        printf 'unexpected-post\n' >> "$log"
        return 90
      fi
      /bin/cat "${scratch}/run.json"
    }
    sleep() { :; }
    dispatch_verifier v0.4.5 draft 777 "$record"
    dispatch_verifier v0.4.5 draft 777 "$record"
  )
  ! grep -Fq unexpected-post "$log" || die "recovered verifier dispatch performed a duplicate POST"
  [[ "$(grep -c '^watch:' "$log")" == 1 ]] || die "recovered verifier run was not watched exactly once"
  [[ "$(cat "$poll_count")" == 4 ]] || die "verifier recovery did not poll through delayed run visibility"
  [[ "$(grep -c '^validated-nonce$' "$log")" == 2 ]] || die "recovered verifier did not propagate its exact nonce to both validators"
  jq -e --argjson id "$run_id" --slurpfile record "$record" \
    'select(.workflow_run_id == $id and .release_record == $record[0])' "${state}/verifier-draft.json" >/dev/null ||
    die "recovered verifier proof was not frozen atomically"
  jq -e 'select(.workflow_run_id == 29009699237 and .recovered == true)' "$intent" >/dev/null ||
    die "recovered verifier intent did not bind the adopted run"
  rm -rf "$scratch"
}

test_newest_selection_fails_closed() {
  local scratch runs title
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-newest-run.XXXXXX")"
  runs="${scratch}/runs.json"
  title="Verify v0.4.5 draft assets at ${SHA} for ${TAG_COMMIT} object ${TAG_OBJECT}"
  jq -n --arg title "$title" --arg sha "$SHA" '{workflow_runs:[
    {id:10,workflow_id:309911276,path:".github/workflows/release-assets.yml",display_title:$title,event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",created_at:"2026-07-10T10:00:00Z"},
    {id:11,workflow_id:309911276,path:".github/workflows/release-assets.yml@main",display_title:$title,event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",created_at:"2026-07-10T10:01:00Z"}
  ]}' > "$runs"
  expect_failure "newer invalid proof fallback" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; newest_matching_run_id "$2" 309911276 .github/workflows/release-assets.yml "$3" main "$4"
  ' _ "$release_script" "$runs" "$title" "$SHA"

  jq -n --arg title "$title" --arg sha "$SHA" '{workflow_runs:[
    {id:12,workflow_id:309911276,path:".github/workflows/release-assets.yml",display_title:$title,event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",created_at:"2026-07-10T10:02:00Z"},
    {id:13,workflow_id:309911276,path:".github/workflows/release-assets.yml",display_title:$title,event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",created_at:"2026-07-10T10:02:00Z"}
  ]}' > "$runs"
  [[ "$(
    source_release
    newest_matching_run_id "$runs" 309911276 .github/workflows/release-assets.yml "$title" main "$SHA"
  )" == "13" ]] || die "same-time proof did not choose higher numeric ID"
  rm -rf "$scratch"
}

test_paginated_run_inventory() {
  local scratch mock_bin output
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-run-pages.XXXXXX")"
  mock_bin="${scratch}/bin"
  output="${scratch}/runs.json"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == api && "$*" == *'--paginate'* ]] || exit 90
printf '%s\n' '{"workflow_runs":[{"id":1,"workflow_id":309911276,"head_sha":"a"},{"id":2,"workflow_id":309911276,"head_sha":"b"}]}'
if [[ "${MOCK_CONFLICT:-0}" == 1 ]]; then
  printf '%s\n' '{"workflow_runs":[{"id":2,"workflow_id":309911276,"head_sha":"hostile"},{"id":3,"workflow_id":309911276,"head_sha":"c"}]}'
elif [[ "${MOCK_OVERFLOW:-0}" == 1 ]]; then
  printf '%s\n' '{"workflow_runs":[{"id":9007199254740992,"workflow_id":309911276,"head_sha":"hostile"}]}'
else
  printf '%s\n' '{"workflow_runs":[{"id":2,"workflow_id":309911276,"head_sha":"b"},{"id":3,"workflow_id":309911276,"head_sha":"c"}]}'
fi
EOF
  chmod +x "${mock_bin}/gh"
  (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
    fetch_workflow_runs openclaw/goplaces 309911276 main "$output"
  )
  [[ "$(jq -c '[.workflow_runs[].id]' "$output")" == '[1,2,3]' ]] || die "paginated run inventory was not complete and deduplicated"
  if (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH MOCK_CONFLICT=1 MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
    fetch_workflow_runs openclaw/goplaces 309911276 main "$output"
  ) >/dev/null 2>&1; then
    die "conflicting duplicate workflow run ID was accepted"
  fi
  if (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH MOCK_OVERFLOW=1 MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
    fetch_workflow_runs openclaw/goplaces 309911276 main "$output"
  ) >/dev/null 2>&1; then
    die "overflow workflow run ID was accepted"
  fi
  rm -rf "$scratch"
}

make_release_fixture() {
  local output="$1" notes="$2" draft="$3" digest name index=0 version=0.4.5
  digest="sha256:$(printf '%064d' 0)"
  local -a names=(
    "goplaces_${version}_darwin_amd64.tar.gz"
    "goplaces_${version}_darwin_arm64.tar.gz"
    "goplaces_${version}_linux_amd64.tar.gz"
    "goplaces_${version}_linux_arm64.tar.gz"
    "goplaces_${version}_windows_amd64.zip"
    "goplaces_${version}_windows_arm64.zip"
    goplaces_checksums.txt
  )
  printf '[]\n' > "${output}.assets"
  for name in "${names[@]}"; do
    index=$((index + 1))
    jq \
      --argjson id "$((1000 + index))" --arg name "$name" --argjson size "$((2000 + index))" --arg digest "$digest" \
      --arg api "https://api.github.com/repos/openclaw/goplaces/releases/assets/$((1000 + index))" \
      --arg browser "https://github.com/openclaw/goplaces/releases/download/v0.4.5/${name}" \
      '. + [{id:$id,name:$name,size:$size,digest:$digest,url:$api,browser_download_url:$browser,content_type:"application/octet-stream",state:"uploaded",created_at:"2026-07-10T10:00:00Z",updated_at:"2026-07-10T10:00:00Z"}]' \
      "${output}.assets" > "${output}.next"
    mv "${output}.next" "${output}.assets"
  done
  jq -n --argjson assets "$(cat "${output}.assets")" --rawfile body "$notes" --argjson draft "$draft" --arg sha "$SHA" '{
    id:777, tag_name:"v0.4.5", target_commitish:$sha, name:"v0.4.5", draft:$draft, prerelease:false, body:$body,
    created_at:"2026-07-10T10:00:00Z", updated_at:"2026-07-10T10:00:00Z", published_at:(if $draft then null else "2026-07-10T11:00:00Z" end), assets:$assets
  }' > "$output"
}

test_release_record_freeze() {
  local scratch notes raw canonical tampered reversed
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-release-record-test.XXXXXX")"
  notes="${scratch}/notes.md"
  raw="${scratch}/raw.json"
  canonical="${scratch}/canonical.json"
  tampered="${scratch}/tampered.json"
  reversed="${scratch}/reversed.json"
  printf '\n- Security and notarized release.\n' > "$notes"
  make_release_fixture "$raw" "$notes" true
  (
    source_release
    default_branch=main
    default_sha="$SHA"
    canonical_release_record "$raw" "$canonical" v0.4.5 draft "$notes"
  )
  [[ "$(jq '.assets | length' "$canonical")" == "7" ]] || die "canonical record lost assets"
  jq '.assets[1].id = .assets[0].id' "$raw" > "$tampered"
  expect_failure "duplicate asset ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; default_branch=main; default_sha="$2"; canonical_release_record "$3" "$4" v0.4.5 draft "$5"
  ' _ "$release_script" "$SHA" "$tampered" "${scratch}/bad.json" "$notes"
  jq '.assets[0].url = "https://api.github.com.evil/repos/openclaw/goplaces/releases/assets/1001"' "$raw" > "$tampered"
  expect_failure "evil asset API URL" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; default_branch=main; default_sha="$2"; canonical_release_record "$3" "$4" v0.4.5 draft "$5"
  ' _ "$release_script" "$SHA" "$tampered" "${scratch}/bad.json" "$notes"
  jq '.id = 9007199254740992' "$raw" > "$tampered"
  expect_failure "overflow release ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; default_branch=main; default_sha="$2"; canonical_release_record "$3" "$4" v0.4.5 draft "$5"
  ' _ "$release_script" "$SHA" "$tampered" "${scratch}/bad.json" "$notes"
  jq '.assets[0].id = 9007199254740992 | .assets[0].url = "https://api.github.com/repos/openclaw/goplaces/releases/assets/9007199254740992"' "$raw" > "$tampered"
  expect_failure "overflow asset ID" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; default_branch=main; default_sha="$2"; canonical_release_record "$3" "$4" v0.4.5 draft "$5"
  ' _ "$release_script" "$SHA" "$tampered" "${scratch}/bad.json" "$notes"
  jq '.assets |= reverse' "$raw" > "$reversed"
  (
    source_release
    default_branch=main
    default_sha="$SHA"
    canonical_release_record "$reversed" "${scratch}/reordered.json" v0.4.5 draft "$notes"
  )
  cmp -s "$canonical" "${scratch}/reordered.json" || die "asset ordering changed canonical release identity"
  rm -rf "$scratch"
}

test_draft_intent_is_crash_resumable() {
  local scratch state notes changed counter marker notes_source
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-draft-intent.XXXXXX")"
  state="${scratch}/state"
  notes="${scratch}/notes.md"
  changed="${scratch}/changed.md"
  mkdir -p "$state"
  printf '\n- Exact draft intent.\n' > "$notes"
  printf '\n- Moved notes.\n' > "$changed"
  (
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    INVENTORY_MODE=empty
    gh_api() {
      if [[ "$INVENTORY_MODE" == empty ]]; then
        printf '[]\n'
      else
        printf '[{"id":777,"tag_name":"v0.4.5","created_at":"2099-01-01T00:00:00Z"}]\n'
      fi
    }
    prepare_draft_intent v0.4.5 "$notes"
    [[ "$draft_intent_created" == true ]] || exit 80
    INVENTORY_MODE=release
    [[ "$(resolve_intended_draft_id v0.4.5)" == 777 ]] || exit 81
    fetch_release_record() { jq -n '{id:777,created_at:"2099-01-01T00:00:00Z",state:"draft"}' > "$5"; }
    printf 'partial\n' > "${scratch}/.draft-release.interrupted"
    freeze_initial_draft v0.4.5 "$notes"
  )
  jq -e 'select(.id == 777 and .state == "draft")' "${state}/draft-release.json" >/dev/null ||
    die "crash-resumed draft was not frozen as one atomic record"
  if (
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    validate_draft_intent v0.4.5 "$changed"
  ) >/dev/null 2>&1; then
    die "draft intent accepted changed release notes"
  fi

  state="${scratch}/unauthorized"
  mkdir -p "$state"
  if (
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    gh_api() { printf '[{"id":777,"tag_name":"v0.4.5","created_at":"2099-01-01T00:00:00Z"}]\n'; }
    prepare_draft_intent v0.4.5 "$notes"
  ) >/dev/null 2>&1; then
    die "pre-existing release was adopted without a frozen draft intent"
  fi

  state="${scratch}/eventual"
  counter="${scratch}/eventual-count"
  mkdir -p "$state"
  printf '0\n' > "$counter"
  (
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    gh_api() { printf '[]\n'; }
    prepare_draft_intent v0.4.5 "$notes"
    prepare_draft_intent v0.4.5 "$notes"
    [[ "$draft_intent_created" == false ]] || exit 82
    gh_api() {
      local call
      call="$(cat "$counter")"
      call=$((call + 1))
      printf '%s\n' "$call" > "$counter"
      if ((call < 3)); then
        printf '[]\n'
      else
        printf '[{"id":777,"tag_name":"v0.4.5","created_at":"1999-01-01T00:00:00Z"}]\n'
      fi
    }
    sleep() { :; }
    [[ "$(resolve_intended_draft_id_with_retry v0.4.5)" == 777 ]] || exit 83
  )
  [[ "$(cat "$counter")" == 3 ]] || die "draft recovery did not poll until the exact release became visible"

  state="${scratch}/persistent-empty"
  counter="${scratch}/persistent-count"
  marker="${scratch}/producer-ran"
  mkdir -p "$state"
  printf '0\n' > "$counter"
  notes_source="$notes"
  (
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    gh_api() { printf '[]\n'; }
    prepare_draft_intent v0.4.5 "$notes"
  )
  if (
    source_release
    prepare_official_producer_gate() { :; }
    preflight_repository() { default_sha="$SHA"; default_branch=main; protected_source_root="${state%/*}"; }
    verify_remote_tag() { tag_object="$TAG_OBJECT"; tag_commit="$TAG_COMMIT"; }
    recheck_source_default() { :; }
    init_release_state() { release_state_dir="$state"; }
    prepare_remote_source() { mkdir -p "$1"; }
    extract_release_notes() { /bin/cp "$notes_source" "$3"; }
    gh_api() {
      local call
      call="$(cat "$counter")"
      printf '%s\n' "$((call + 1))" > "$counter"
      printf '[]\n'
    }
    sleep() { :; }
    gh_auth_token() { touch "$marker"; printf 'fixture-token\n'; }
    run_codesigned_goreleaser() { touch "$marker"; }
    run_draft v0.4.5
  ) >/dev/null 2>&1; then
    die "existing unbound draft intent reran the producer"
  fi
  [[ ! -e "$marker" ]] || die "existing unbound draft intent reached credentials or producer execution"
  [[ "$(cat "$counter")" == 15 ]] || die "existing unbound draft intent did not complete bounded reconciliation"
  rm -rf "$scratch"
}

write_fixture_verifier_state() {
  local file="$1" state="$2" run_id="$3" record="$4" digest nonce intent title
  digest="$(test_sha256 "$record")"
  nonce="$(test_verifier_nonce v0.4.5 "$state" 777 "$digest" 1)"
  intent="${file%.json}-intent.json"
  title="Verify v0.4.5 ${state} release 777 nonce ${nonce}"
  jq -n \
    --arg state "$state" --argjson run_id "$run_id" --arg digest "$digest" --arg nonce "$nonce" --arg title "$title" \
    --arg object "$TAG_OBJECT" --arg commit "$TAG_COMMIT" --arg main "$SHA" \
    '{schema:"goplaces-verifier-intent-v1",tag:"v0.4.5",state:$state,tag_object:$object,tag_commit:$commit,
      default_sha:$main,release_id:777,workflow_id:309911276,release_record_sha256:$digest,
      attempt:1,dispatch_nonce:$nonce,expected_title:$title,created_after:"2026-07-10T09:59:59Z",
      seen_run_ids:[],failed_run_ids:[],workflow_run_id:$run_id,recovered:true}' > "$intent"
  jq -n \
    --argjson workflow_id 309911276 --argjson workflow_run_id "$run_id" --arg state "$state" \
    --arg tag v0.4.5 --arg tag_object "$TAG_OBJECT" --arg tag_commit "$TAG_COMMIT" --arg default_sha "$SHA" \
    --argjson release_id 777 --arg release_record_sha256 "$digest" --arg dispatch_nonce "$nonce" \
    --slurpfile release_record "$record" \
    '{workflow_id:$workflow_id,workflow_run_id:$workflow_run_id,state:$state,tag:$tag,tag_object:$tag_object,tag_commit:$tag_commit,
      default_sha:$default_sha,release_id:$release_id,release_record_sha256:$release_record_sha256,
      verifier_attempt:1,dispatch_nonce:$dispatch_nonce,release_record:$release_record[0]}' > "$file"
}

run_published_resume_fixture() {
  local fixture_root="$1" with_published_proof="$2" authorized="${3:-1}" tamper_draft="${4:-0}"
  local fixture_log="${fixture_root}/events" fixture_state="${fixture_root}/state" draft_record published_record draft_digest
  mkdir -p "$fixture_state" "${fixture_root}/protected"
  draft_record="${fixture_root}/draft-record.json"
  published_record="${fixture_root}/published-record.json"
  jq -n '{state:"draft"}' > "$draft_record"
  jq -n '{state:"published"}' > "$published_record"
  write_fixture_verifier_state "${fixture_state}/verifier-draft.json" draft 111 "$draft_record"
  if [[ "$tamper_draft" == 1 ]]; then
    jq '.release_record_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
      "${fixture_state}/verifier-draft.json" > "${fixture_state}/verifier-draft.bad"
    mv "${fixture_state}/verifier-draft.bad" "${fixture_state}/verifier-draft.json"
  fi
  if [[ "$authorized" == 1 ]]; then
    draft_digest="$(test_sha256 "$draft_record")"
    jq -n --arg tag v0.4.5 --arg object "$TAG_OBJECT" --arg commit "$TAG_COMMIT" --arg main "$SHA" \
      --argjson release_id 777 --arg draft_sha256 "$draft_digest" \
      '{schema:"goplaces-publish-intent-v1",tag:$tag,tag_object:$object,tag_commit:$commit,default_sha:$main,
        release_id:$release_id,draft_record_sha256:$draft_sha256}' > "${fixture_state}/publish-intent.json"
  fi
  if [[ "$with_published_proof" == 1 ]]; then
    write_fixture_verifier_state "${fixture_state}/verifier-published.json" published 222 "$published_record"
  fi
  (
    source_release
    preflight_repository() {
      default_branch=main
      default_sha="$SHA"
      protected_source_root="${fixture_root}/protected"
    }
    verify_remote_tag() {
      tag_object="$TAG_OBJECT"
      tag_commit="$TAG_COMMIT"
      printf 'tag\n' >> "$fixture_log"
    }
    init_release_state() { release_state_dir="$fixture_state"; }
    extract_release_notes() { printf '\n- Resumable publication.\n' > "$3"; }
    verify_frozen_release_current_state() {
      jq -n '{state:"published"}' > "$3"
      printf 'published\n'
    }
    load_frozen_release_id() { printf '777\n'; }
    run_release_verifier_check() { printf 'check:%s\n' "$2" >> "$fixture_log"; }
    recheck_source_default() { printf 'main\n' >> "$fixture_log"; }
    verify_frozen_release() {
      if [[ "${MOCK_PUBLISHED_MOVE:-0}" == 1 ]]; then
        jq -n '{state:"published",updated_at:"moved"}' > "$4"
      else
        jq -n '{state:"published"}' > "$4"
      fi
    }
    dispatch_verifier() {
      printf 'dispatch:%s\n' "$2" >> "$fixture_log"
      write_fixture_verifier_state "${fixture_state}/verifier-published.json" published 333 "$4"
    }
    gh_api() { printf 'unexpected-gh:%s\n' "$*" >> "$fixture_log"; return 91; }
    run_publish v0.4.5
  )
}

test_publish_is_resumable() {
  local scratch log
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-publish-resume.XXXXXX")"
  log="${scratch}/events"
  run_published_resume_fixture "$scratch" 1
  grep -Fq 'check:published' "$log" || die "completed publication rerun did not recheck its published verifier"
  ! grep -Eq 'dispatch:|unexpected-gh:' "$log" || die "completed publication rerun performed a public mutation"
  [[ -f "${scratch}/state/verifier-published.json" ]] || die "completed publication rerun lost its frozen verifier state"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-publish-resume.XXXXXX")"
  log="${scratch}/events"
  run_published_resume_fixture "$scratch" 0
  grep -Fq 'dispatch:published' "$log" || die "post-PATCH resumption did not continue with published verification"
  ! grep -Fq 'unexpected-gh:' "$log" || die "post-PATCH resumption attempted a second release PATCH"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-publish-resume.XXXXXX")"
  expect_failure "unauthorized out-of-band publication" run_published_resume_fixture "$scratch" 0 0
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-publish-resume.XXXXXX")"
  expect_failure "tampered draft verifier state" run_published_resume_fixture "$scratch" 0 1 1
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-publish-resume.XXXXXX")"
  MOCK_PUBLISHED_MOVE=1 expect_failure "published record movement after proof" run_published_resume_fixture "$scratch" 1
  rm -rf "$scratch"
}

test_formula_pairs_and_tap_commit_record() {
  local scratch formula hostile commit_record bad old_head new_head expected_message
  local darwin_amd64 darwin_arm64 linux_amd64 linux_arm64
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-formula-contract.XXXXXX")"
  formula="${scratch}/goplaces.rb"
  hostile="${scratch}/hostile.rb"
  commit_record="${scratch}/commit.json"
  bad="${scratch}/bad.json"
  old_head=3333333333333333333333333333333333333333
  new_head=4444444444444444444444444444444444444444
  darwin_amd64="$(printf '%064d' 1)"
  darwin_arm64="$(printf '%064d' 2)"
  linux_amd64="$(printf '%064d' 3)"
  linux_arm64="$(printf '%064d' 4)"
  cat > "$formula" <<EOF
class Goplaces < Formula
  version "0.4.5"
  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_darwin_arm64.tar.gz"
      sha256 "$darwin_arm64"
    else
      url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_darwin_amd64.tar.gz"
      sha256 "$darwin_amd64"
    end
  end
  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_linux_arm64.tar.gz"
      sha256 "$linux_arm64"
    else
      url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_linux_amd64.tar.gz"
      sha256 "$linux_amd64"
    end
  end
end
EOF
  (
    source_release
    validate_formula_content "$formula" v0.4.5 "$darwin_amd64" "$darwin_arm64" "$linux_amd64" "$linux_arm64"
  )
  cat > "$hostile" <<EOF
class Goplaces < Formula
  version "0.4.5"
  url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_darwin_arm64.tar.gz"
  sha256 "$darwin_amd64"
  url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_darwin_amd64.tar.gz"
  sha256 "$darwin_arm64"
  url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_linux_arm64.tar.gz"
  sha256 "$linux_amd64"
  url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_linux_amd64.tar.gz"
  sha256 "$linux_arm64"
  # url "https://github.com/openclaw/goplaces/releases/download/v0.4.5/goplaces_0.4.5_darwin_arm64.tar.gz"
  # sha256 "$darwin_arm64"
end
EOF
  expect_failure "comment or wrong-block Formula hash" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; validate_formula_content "$2" v0.4.5 "$3" "$4" "$5" "$6"
  ' _ "$release_script" "$hostile" "$darwin_amd64" "$darwin_arm64" "$linux_amd64" "$linux_arm64"

  expected_message="goplaces: update formula for v0.4.5

Source-Repository: openclaw/goplaces
Source-Tag-Object: ${TAG_OBJECT}
Source-Tag-Commit: ${TAG_COMMIT}
Request-ID: request-123"
  jq -n --arg sha "$new_head" --arg parent "$old_head" --arg message "$expected_message" \
    '{sha:$sha,parents:[{sha:$parent}],commit:{message:$message}}' > "$commit_record"
  (
    source_release
    validate_tap_commit_record "$commit_record" "$new_head" "$old_head" "$expected_message"
  )
  jq '.parents += [{sha:"5555555555555555555555555555555555555555"}]' "$commit_record" > "$bad"
  expect_failure "tap commit with two parents" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; validate_tap_commit_record "$2" "$3" "$4" "$5"
  ' _ "$release_script" "$bad" "$new_head" "$old_head" "$expected_message"
  jq '.sha = "5555555555555555555555555555555555555555"' "$commit_record" > "$bad"
  expect_failure "tap REST commit SHA mismatch" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; validate_tap_commit_record "$2" "$3" "$4" "$5"
  ' _ "$release_script" "$bad" "$new_head" "$old_head" "$expected_message"
  jq '.commit.message += "\nExtra-Trailer: hostile"' "$commit_record" > "$bad"
  expect_failure "ambiguous tap provenance trailer" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; validate_tap_commit_record "$2" "$3" "$4" "$5"
  ' _ "$release_script" "$bad" "$new_head" "$old_head" "$expected_message"
  rm -rf "$scratch"
}

test_trusted_ancestry_rejects_graph_overrides() {
  local scratch repository fixture_git_root empty_tree first second graft_path
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-ancestry-test.XXXXXX")"
  repository="${scratch}/repository"
  fixture_git_root="${scratch}/fixture-git"
  mkdir -p "$fixture_git_root"
  test_fixture_git "$fixture_git_root" init -q "$repository"
  test_fixture_git "$fixture_git_root" -C "$repository" config user.name release-test
  test_fixture_git "$fixture_git_root" -C "$repository" config user.email release-test@example.invalid
  empty_tree="$(test_fixture_git "$fixture_git_root" -C "$repository" mktree </dev/null)"
  first="$(printf 'first\n' | test_fixture_git "$fixture_git_root" -C "$repository" commit-tree --no-gpg-sign "$empty_tree")"
  second="$(printf 'second\n' | test_fixture_git "$fixture_git_root" -C "$repository" commit-tree --no-gpg-sign "$empty_tree")"
  if test_fixture_git "$fixture_git_root" -C "$repository" merge-base --is-ancestor "$first" "$second"; then
    die "unrelated commits unexpectedly have raw ancestry"
  fi
  graft_path="$(test_fixture_git "$fixture_git_root" -C "$repository" rev-parse --path-format=absolute --git-path info/grafts)"
  mkdir -p "$(dirname "$graft_path")"
  printf '%s %s\n' "$second" "$first" > "$graft_path"
  test_fixture_git "$fixture_git_root" -C "$repository" merge-base --is-ancestor "$first" "$second" 2>/dev/null ||
    die "legacy graft did not demonstrate that GIT_NO_REPLACE_OBJECTS is insufficient"
  expect_failure "legacy graft ancestry" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; trusted_is_ancestor "$2" "$3" "$4"
  ' _ "$release_script" "$repository" "$first" "$second"
  rm -f "$graft_path"
  test_fixture_git "$fixture_git_root" -C "$repository" update-ref "refs/replace/${second}" "$first"
  expect_failure "replacement-ref ancestry" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; trusted_is_ancestor "$2" "$3" "$4"
  ' _ "$release_script" "$repository" "$first" "$second"
  test_fixture_git "$fixture_git_root" -C "$repository" update-ref -d "refs/replace/${second}"
  ln -s missing-graft-target "$graft_path"
  expect_failure "broken graft symlink ancestry" bash -c '
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    source "$1"; trusted_is_ancestor "$2" "$3" "$4"
  ' _ "$release_script" "$repository" "$first" "$second"
  rm -rf "$scratch"
}

test_post_manifest_source_recheck() {
  local scratch repository home fixture_git_root tracked_sha raw_hidden raw_explicit wrapper producer_bin go_bin goreleaser_bin
  local go_sha go_identity goreleaser_sha goreleaser_identity producer_path exec_log go_backup goreleaser_backup
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-source-recheck.XXXXXX")"
  scratch="$(cd "$scratch" && pwd -P)"
  repository="${scratch}/repository"
  home="${scratch}/home"
  fixture_git_root="${scratch}/fixture-git"
  wrapper="${repo_root}/scripts/recheck-release-source.sh"
  producer_bin="${scratch}/producer-bin"
  go_bin="${producer_bin}/go"
  goreleaser_bin="${producer_bin}/goreleaser"
  exec_log="${scratch}/goreleaser-exec.log"
  go_backup="${scratch}/go.backup"
  goreleaser_backup="${scratch}/goreleaser.backup"
  mkdir -p "$home" "$producer_bin" "$fixture_git_root"
  chmod 700 "$producer_bin"
  cat > "$go_bin" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ "$*" == 'env GOVERSION' ]] || exit 91
printf 'go1.26.5\n'
EOF
  cat > "$goreleaser_bin" <<'EOF'
#!/bin/bash -p
set -euo pipefail
if [[ "$*" == --version ]]; then
  printf 'GitVersion:    2.16.0\n'
  exit 0
fi
[[ "${1:-}" == release ]] || exit 92
[[ "$PATH" == "${0%/*}:/usr/bin:/bin:/usr/sbin:/sbin" ]] || exit 93
[[ "$(command -v go)" == "${0%/*}/go" ]] || exit 94
for forbidden_name in GORELEASER_CURRENT_TAG GORELEASER_PREVIOUS_TAG GORELEASER_EXPERIMENTAL GORELEASER_FORCE_TOKEN; do
  [[ -z "${!forbidden_name+x}" ]] || exit 95
done
[[ -z "${GORELEASER_EXEC_LOG:-}" ]] || printf 'release\n' >> "$GORELEASER_EXEC_LOG"
EOF
  chmod +x "$go_bin" "$goreleaser_bin"
  /bin/cp "$go_bin" "$go_backup"
  /bin/cp "$goreleaser_bin" "$goreleaser_backup"
  go_sha="$(test_sha256 "$go_bin")"
  go_identity="$(test_identity "$go_bin")"
  goreleaser_sha="$(test_sha256 "$goreleaser_bin")"
  goreleaser_identity="$(test_identity "$goreleaser_bin")"
  producer_path="${producer_bin}:/usr/bin:/bin:/usr/sbin:/sbin"
  test_fixture_git "$fixture_git_root" -c init.defaultBranch=main init -q "$repository"
  printf 'package main\n' > "${repository}/main.go"
  test_fixture_git "$fixture_git_root" -C "$repository" add main.go
  test_fixture_git "$fixture_git_root" -C "$repository" -c user.name=release-test -c user.email=release-test@example.invalid commit --no-gpg-sign -q -m initial
  tracked_sha="$(test_fixture_git "$fixture_git_root" -C "$repository" rev-parse HEAD)"
  test_fixture_git "$fixture_git_root" -C "$repository" remote add origin https://github.com/openclaw/goplaces.git
  test_fixture_git "$fixture_git_root" -C "$repository" update-ref refs/remotes/origin/main "$tracked_sha"
  test_fixture_git "$fixture_git_root" -C "$repository" checkout -q --detach "$tracked_sha"
  /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 GORELEASER_EXEC_LOG="$exec_log" \
    "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
    "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null

  local release_control
  for release_control in GORELEASER_CURRENT_TAG GORELEASER_PREVIOUS_TAG GORELEASER_EXPERIMENTAL GORELEASER_FORCE_TOKEN; do
    if /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
      GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 \
      GORELEASER_EXEC_LOG="$exec_log" "$release_control=hostile" \
      "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
      "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null 2>&1; then
      die "post-manifest recheck accepted $release_control"
    fi
  done

  test_fixture_git "$fixture_git_root" -C "$repository" config --local status.showUntrackedFiles no
  printf 'package injected\n' > "${repository}/injected.go"
  raw_hidden="$(test_fixture_git "$fixture_git_root" -C "$repository" status --porcelain)"
  raw_explicit="$(test_fixture_git "$fixture_git_root" -C "$repository" status --porcelain --untracked-files=all)"
  [[ -z "$raw_hidden" ]] || die "hostile local status config did not conceal the injected Go file"
  [[ "$raw_explicit" == '?? injected.go' ]] || die "exact status argv did not reveal the injected Go file"
  if /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 GORELEASER_EXEC_LOG="$exec_log" \
    "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
    "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null 2>&1; then
    die "post-manifest recheck accepted hostile local status config"
  fi
  test_fixture_git "$fixture_git_root" -C "$repository" config --local --unset status.showUntrackedFiles
  if /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 GORELEASER_EXEC_LOG="$exec_log" \
    "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
    "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null 2>&1; then
    die "post-manifest recheck accepted an injected untracked Go file"
  fi
  rm -f "${repository}/injected.go"
  test_fixture_git "$fixture_git_root" -C "$repository" config --local gpg.ssh.program "${scratch}/fake-signature-program"
  if /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 GORELEASER_EXEC_LOG="$exec_log" \
    "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
    "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null 2>&1; then
    die "post-manifest recheck accepted forbidden local Git config"
  fi
  test_fixture_git "$fixture_git_root" -C "$repository" config --local --unset gpg.ssh.program
  printf '#!/bin/bash -p\nexit 99\n' > "$go_bin"
  if /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 GORELEASER_EXEC_LOG="$exec_log" \
    "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
    "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null 2>&1; then
    die "post-manifest recheck accepted in-place Go mutation"
  fi
  /bin/cp "$go_backup" "$go_bin"
  /bin/cp "$goreleaser_backup" "${scratch}/same-goreleaser"
  /bin/mv -f "${scratch}/same-goreleaser" "$goreleaser_bin"
  if /usr/bin/env -i -C "$repository" PATH="$producer_path" HOME="$home" TMPDIR="$scratch" LC_ALL=C TZ=UTC \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
    GOENV=off GOTOOLCHAIN=local GOWORK=off GOPLACES_OFFICIAL_RELEASE=1 GOPLACES_PILOT_VERSION=9.9.9 GORELEASER_EXEC_LOG="$exec_log" \
    "$wrapper" pilot "$tracked_sha" v9.9.9 "$goreleaser_bin" "$goreleaser_sha" "$goreleaser_identity" \
    "$go_bin" "$go_sha" "$go_identity" -- release --snapshot --clean --skip=publish --config .goreleaser.yml >/dev/null 2>&1; then
    die "post-manifest recheck accepted same-byte GoReleaser replacement"
  fi
  [[ "$(cat "$exec_log")" == release ]] || die "failed source/tool gates executed GoReleaser"
  rm -rf "$scratch"
}

test_production_git_is_pinned() {
  local scratch fake_git
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-production-git.XXXXXX")"
  fake_git="${scratch}/git"
  printf '#!/bin/bash\nexit 99\n' > "$fake_git"
  chmod +x "$fake_git"
  (
    GOPLACES_RELEASE_LOCAL_TESTING=1
    GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    export GOPLACES_RELEASE_LOCAL_TESTING GOPLACES_RELEASE_LOCAL_SOURCE_ONLY
    # shellcheck source=release-local
    source "$release_script"
    unset GOPLACES_RELEASE_LOCAL_TESTING
    git_isolation_root=""
    git_binary=""
    PATH="${scratch}:/usr/bin:/bin"
    GOPLACES_RELEASE_LOCAL_TEST_GIT_BIN="$fake_git"
    export PATH GOPLACES_RELEASE_LOCAL_TEST_GIT_BIN
    ensure_git_isolation
    [[ "$git_binary" == /usr/bin/git ]] || die "production mode accepted a PATH or test Git override"
  )
  rm -rf "$scratch"
}

make_fake_producer_tools() {
  local directory="$1" go_version="$2" goreleaser_version="$3"
  mkdir -p "$directory"
  chmod 700 "$directory"
  cat > "${directory}/go" <<EOF
#!/bin/bash -p
set -euo pipefail
[[ "\$*" == 'env GOVERSION' ]] || exit 91
printf '%s\\n' '$go_version'
EOF
  cat > "${directory}/goreleaser" <<EOF
#!/bin/bash -p
set -euo pipefail
if [[ "\$*" == --version ]]; then
  printf 'GitVersion:    %s\\n' '$goreleaser_version'
  exit 0
fi
[[ "\${1:-}" == release ]] || exit 92
[[ -z "\${GORELEASER_EXEC_LOG:-}" ]] || printf 'release\\n' >> "\$GORELEASER_EXEC_LOG"
EOF
  cat > "${directory}/node" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ "$*" == --version ]] || exit 93
printf 'v26.5.0\n'
EOF
  cat > "${directory}/expect" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ "$*" == -v ]] || exit 94
printf 'expect version 5.45.4\n'
EOF
  cat > "${directory}/python3" <<'EOF'
#!/bin/bash -p
set -euo pipefail
if [[ "$*" == '-I --version' ]]; then
  printf 'Python 3.14.6\n'
  exit 0
fi
[[ "${1:-}" == -I ]] || exit 95
shift
exec /usr/bin/python3 -I "$@"
EOF
  chmod +x "${directory}/go" "${directory}/goreleaser" "${directory}/node" "${directory}/expect" "${directory}/python3"
}

test_producer_gate_hardening() {
  local scratch tools launch helper helper_link sentinel old_go old_goreleaser mutation real_tmp alias_tmp
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-producer-gate.XXXXXX")"
  scratch="$(cd "$scratch" && pwd -P)"
  tools="${scratch}/tools"
  launch="${scratch}/launch"
  helper="${scratch}/release-mac-app"
  helper_link="${scratch}/release-mac-app-link"
  sentinel="${scratch}/hostile-path-ran"
  real_tmp="${scratch}/real-tmp"
  alias_tmp="${scratch}/tmp-alias"
  mkdir -p "$real_tmp"
  ln -s "$real_tmp" "$alias_tmp"
  make_fake_producer_tools "$tools" go1.26.5 2.16.0
  mkdir -p "$launch"
  ln -s "${tools}/go" "${launch}/go"
  ln -s "${tools}/goreleaser" "${launch}/goreleaser"
  ln -s "${tools}/node" "${launch}/node"
  ln -s "${tools}/expect" "${launch}/expect"
  ln -s "${tools}/python3" "${launch}/python3"
  cat > "$helper" <<'EOF'
#!/bin/bash -p
exit 0
EOF
  mkdir -p "${scratch}/lib"
  printf '# frozen mock helper library\n' > "${scratch}/lib/mac_release.sh"
  chmod +x "$helper"
  ln -s "$helper" "$helper_link"
  local hostile_name
  for hostile_name in sed grep dirname mktemp chmod; do
    cat > "${launch}/${hostile_name}" <<EOF
#!/bin/bash -p
touch '$sentinel'
exit 97
EOF
    chmod +x "${launch}/${hostile_name}"
  done

  if env -u GOPLACES_RELEASE_LOCAL_TESTING -u GOPLACES_RELEASE_LOCAL_SOURCE_ONLY RELEASE_MAC_APP_BIN= \
    "$release_script" --check >/dev/null 2>&1; then
    die "empty production release-mac-app override was accepted"
  fi
  if env -u GOPLACES_RELEASE_LOCAL_TESTING -u GOPLACES_RELEASE_LOCAL_SOURCE_ONLY RELEASE_MAC_APP_BIN="$helper" \
    "$release_script" --check >/dev/null 2>&1; then
    die "production release-mac-app override was accepted"
  fi
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper_link"
    source "$release_script"
    PATH="${launch}:/usr/bin:/bin"
    TMPDIR="$alias_tmp"
    export PATH TMPDIR
    prepare_producer_gate
    [[ "$git_isolation_root" == "$($REALPATH_BIN "$git_isolation_root")" ]] || die "Git isolation root retained a symlink alias"
  ) >/dev/null 2>&1; then
    die "symlink release-mac-app helper was accepted"
  fi
  (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${launch}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
    [[ "$producer_go" == "$git_isolation_root"/producer-bin.*/go ]] || die "Go was not frozen in the private producer directory"
    [[ "$producer_goreleaser" == "$git_isolation_root"/producer-bin.*/goreleaser ]] || die "GoReleaser was not frozen in the private producer directory"
    [[ "$(test_identity "$producer_go")" == "$(test_identity "${tools}/go")" ]] || die "frozen Go is not the resolved hard link"
    [[ "$(test_identity "$producer_goreleaser")" == "$(test_identity "${tools}/goreleaser")" ]] || die "frozen GoReleaser is not the resolved hard link"
    [[ "$(test_identity "$release_mac_app")" != "$(test_identity "$helper")" ]] || die "release-mac-app was not frozen as a private copy"
    [[ "$(test_sha256 "$release_mac_app")" == "$(test_sha256 "$helper")" ]] || die "frozen release-mac-app copy differs from its source"
    [[ "$(test_identity "$release_mac_app_lib")" != "$(test_identity "${scratch}/lib/mac_release.sh")" ]] || die "release-mac-app library was not frozen as a private copy"
    [[ "$(test_sha256 "$release_mac_app_lib")" == "$(test_sha256 "${scratch}/lib/mac_release.sh")" ]] || die "frozen release-mac-app library differs from its source"
    [[ "$(/usr/bin/stat -f '%Lp' "${producer_go%/*}")" == 700 ]] || die "producer directory is not private"
  )
  [[ ! -e "$sentinel" ]] || die "hostile PATH utility executed during producer resolution"

  old_go="${scratch}/old-go"
  make_fake_producer_tools "$old_go" go1.26.4 2.16.0
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${old_go}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
  ) >/dev/null 2>&1; then
    die "old Go entered the producer gate"
  fi
  old_goreleaser="${scratch}/old-goreleaser"
  make_fake_producer_tools "$old_goreleaser" go1.26.5 2.15.2
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${old_goreleaser}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
  ) >/dev/null 2>&1; then
    die "old GoReleaser entered the producer gate"
  fi

  mutation="${scratch}/mutation-tools"
  make_fake_producer_tools "$mutation" go1.26.5 2.16.0
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${mutation}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
    /bin/cp "$producer_goreleaser" "${scratch}/same-goreleaser"
    /bin/mv -f "${scratch}/same-goreleaser" "$producer_goreleaser"
    recheck_producer_gate
  ) >/dev/null 2>&1; then
    die "same-byte GoReleaser inode replacement was accepted"
  fi
  make_fake_producer_tools "$mutation" go1.26.5 2.16.0
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${mutation}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
    printf '#!/bin/bash -p\nexit 99\n' > "$producer_go"
    recheck_producer_gate
  ) >/dev/null 2>&1; then
    die "in-place Go byte mutation was accepted"
  fi
  make_fake_producer_tools "$mutation" go1.26.5 2.16.0
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${mutation}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
    /bin/cp "$release_mac_app" "${scratch}/same-helper"
    /bin/mv -f "${scratch}/same-helper" "$release_mac_app"
    recheck_producer_gate
  ) >/dev/null 2>&1; then
    die "same-byte release-mac-app replacement was accepted"
  fi
  make_fake_producer_tools "$mutation" go1.26.5 2.16.0
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="$helper"
    source "$release_script"
    PATH="${mutation}:/usr/bin:/bin"
    export PATH
    prepare_producer_gate
    /bin/chmod 600 "$release_mac_app_lib"
    printf '# mutated helper library\n' >> "$release_mac_app_lib"
    /bin/chmod 400 "$release_mac_app_lib"
    recheck_producer_gate
  ) >/dev/null 2>&1; then
    die "release-mac-app library mutation was accepted"
  fi
  rm -rf "$scratch"
}

test_signature_program_is_pinned() {
  local scratch repository fixture_git_root fake marker allowed mock_git log commit object
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-signature-program.XXXXXX")"
  repository="${scratch}/repository"
  fixture_git_root="${scratch}/fixture-git"
  fake="${scratch}/fake-ssh-keygen"
  marker="${scratch}/fake-ran"
  allowed="${scratch}/allowed-signers"
  mock_git="${scratch}/git"
  log="${scratch}/git.log"
  mkdir -p "$fixture_git_root"
  test_fixture_git "$fixture_git_root" init -q "$repository"
  printf '#!/bin/bash\nprintf %s "Good \\"git\\" signature for release@example.invalid"\ntouch %s\n' "'%s\\n'" "'$marker'" > "$fake"
  chmod +x "$fake"
  test_fixture_git "$fixture_git_root" -C "$repository" config gpg.ssh.program "$fake"
  [[ "$(test_fixture_git "$fixture_git_root" -C "$repository" config --get gpg.ssh.program)" == "$fake" ]] || die "hostile repository signature program was not installed"
  printf 'release@example.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' > "$allowed"
  printf 'fixture\n' > "${repository}/fixture.txt"
  test_fixture_git "$fixture_git_root" -C "$repository" add fixture.txt
  test_fixture_git "$fixture_git_root" -C "$repository" -c user.name='Release Test' -c user.email=release-test@example.invalid commit --no-gpg-sign -q -m fixture
  commit="$(test_fixture_git "$fixture_git_root" -C "$repository" rev-parse HEAD)"
  object="$(
    printf 'object %s\ntype commit\ntag v0.0.0\ntagger Release Test <release-test@example.invalid> 1783670400 +0000\n\nFixture\n-----BEGIN SSH SIGNATURE-----\ninvalid\n-----END SSH SIGNATURE-----\n' "$commit" |
      test_fixture_git "$fixture_git_root" -C "$repository" hash-object -t tag -w --stdin
  )"
  [[ "$object" =~ ^[0-9a-f]{40}$ ]] || die "could not create an unreferenced hostile tag object fixture"
  if (
    source_release
    verify_tag_signature "$repository" "$object" "$allowed"
  ) >/dev/null 2>&1; then
    die "invalid SSH tag-object fixture was accepted"
  fi
  [[ ! -e "$marker" ]] || die "repository-local fake signature program executed under real Git"
  cat > "$mock_git" <<'EOF'
#!/bin/bash -p
set -euo pipefail
printf ' <%s>' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"
joined=" $* "
[[ "$joined" == *' -c gpg.format=ssh '* ]] || exit 81
[[ "$joined" == *' -c gpg.ssh.program=/usr/bin/ssh-keygen '* ]] || exit 82
[[ "$joined" == *' verify-tag 2222222222222222222222222222222222222222 '* ]] || exit 83
EOF
  chmod +x "$mock_git"
  : > "$log"
  (
    source_release
    git_binary="$mock_git"
    export MOCK_LOG="$log"
    verify_tag_signature "$repository" "$TAG_OBJECT" "$allowed"
  )
  grep -Fq '<gpg.ssh.program=/usr/bin/ssh-keygen>' "$log" || die "pinned ssh-keygen was absent from signature verification"
  rm -rf "$scratch"
}

test_tag_identity_is_frozen() {
  local scratch state interrupted_state moved_object frozen_record mutation
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-tag-freeze.XXXXXX")"
  state="${scratch}/state"
  moved_object="3333333333333333333333333333333333333333"
  mkdir -p "$state"
  (
    source_release
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    release_state_dir="$state"
    bind_release_tag_identity v0.4.5
    adopt_verified_tag_identity "$TAG_OBJECT" "$TAG_COMMIT"
  )
  jq -e --arg tag v0.4.5 --arg object "$TAG_OBJECT" --arg commit "$TAG_COMMIT" --arg main "$SHA" \
    'select(.schema == "goplaces-tag-identity-v1" and .tag == $tag and .object_sha == $object and .commit_sha == $commit and .default_sha == $main)' \
    "${state}/tag-identity.json" >/dev/null || die "tag identity was not frozen exactly"
  (
    source_release
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    release_state_dir="$state"
    bind_release_tag_identity v0.4.5
  )
  frozen_record="${scratch}/tag-identity.safe.json"
  cp "${state}/tag-identity.json" "$frozen_record"
  for mutation in tag commit default; do
    chmod 600 "${state}/tag-identity.json"
    case "$mutation" in
      tag) jq '.tag = "v0.4.6"' "$frozen_record" > "${state}/tag-identity.json" ;;
      commit) jq '.commit_sha = "4444444444444444444444444444444444444444"' "$frozen_record" > "${state}/tag-identity.json" ;;
      default) jq '.default_sha = "5555555555555555555555555555555555555555"' "$frozen_record" > "${state}/tag-identity.json" ;;
    esac
    chmod 400 "${state}/tag-identity.json"
    if (
      source_release
      default_sha="$SHA"
      tag_object="$TAG_OBJECT"
      tag_commit="$TAG_COMMIT"
      release_state_dir="$state"
      bind_release_tag_identity v0.4.5
    ) >/dev/null 2>&1; then
      die "frozen tag identity accepted a mismatched ${mutation} field"
    fi
    chmod 600 "${state}/tag-identity.json"
    cp "$frozen_record" "${state}/tag-identity.json"
    chmod 400 "${state}/tag-identity.json"
  done
  if (
    source_release
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    adopt_verified_tag_identity "$moved_object" "$TAG_COMMIT"
  ) >/dev/null 2>&1; then
    die "same-process signed tag object movement was accepted"
  fi
  if (
    source_release
    default_sha="$SHA"
    tag_object="$moved_object"
    tag_commit="$TAG_COMMIT"
    release_state_dir="$state"
    bind_release_tag_identity v0.4.5
  ) >/dev/null 2>&1; then
    die "cross-process signed tag object movement was accepted"
  fi
  rm -f "${state}/tag-identity.json"
  printf '{}\n' > "${state}/draft-release.json"
  if (
    source_release
    default_sha="$SHA"
    tag_object="$moved_object"
    tag_commit="$TAG_COMMIT"
    release_state_dir="$state"
    bind_release_tag_identity v0.4.5
  ) >/dev/null 2>&1; then
    die "deleted tag identity was rebound beside surviving release state"
  fi
  interrupted_state="${scratch}/interrupted-state"
  mkdir -p "$interrupted_state"
  printf 'partial\n' > "${scratch}/.tag-identity.interrupted"
  (
    source_release
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    release_state_dir="$interrupted_state"
    bind_release_tag_identity v0.4.5
  )
  [[ -f "${interrupted_state}/tag-identity.json" ]] || die "sibling staging residue poisoned tag-state retry"
  rm -rf "$scratch"
}

test_gh_transport_is_pinned() {
  local scratch mock_bin log
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-gh-transport.XXXXXX")"
  mock_bin="${scratch}/bin"
  log="${scratch}/gh.log"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/gh" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ -z "${GH_HOST+x}" && -z "${GH_CONFIG_DIR+x}" && -z "${XDG_CONFIG_HOME+x}" ]] || exit 81
printf '%s\n' "$*" >> "$GH_TRANSPORT_LOG"
case "$*" in
  'api --hostname github.com -H X-GitHub-Api-Version: 2026-03-10 repos/openclaw/goplaces') printf '{}\n' ;;
  'auth token --hostname github.com') printf 'fixture_token\n' ;;
  'run watch 29009699237 --repo github.com/openclaw/goplaces --exit-status') ;;
  *) exit 82 ;;
esac
EOF
  chmod +x "${mock_bin}/gh"
  (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH GH_TRANSPORT_LOG="$log" GH_HOST=evil.example GH_CONFIG_DIR="${scratch}/evil-gh" XDG_CONFIG_HOME="${scratch}/evil-xdg"
    export MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
    gh_api repos/openclaw/goplaces >/dev/null
    [[ "$(gh_auth_token)" == fixture_token ]] || exit 83
    gh_watch_run openclaw/goplaces 29009699237
  )
  [[ "$(cat "$log")" == $'api --hostname github.com -H X-GitHub-Api-Version: 2026-03-10 repos/openclaw/goplaces\nauth token --hostname github.com\nrun watch 29009699237 --repo github.com/openclaw/goplaces --exit-status' ]] ||
    die "GitHub transport wrappers were not pinned exactly"
  rm -rf "$scratch"
}

make_preflight_fixture() {
  local root="$1"
  mkdir -p "${root}/scripts" "${root}/mock-bin/lib" "${root}/home/.config/gh"
  printf 'evil.example:\n  user: hostile\n' > "${root}/home/.config/gh/hosts.yml"
  cp "$release_script" "${root}/scripts/release-local"
  cp "${repo_root}/scripts/recheck-release-source.sh" "${root}/scripts/recheck-release-source.sh"
  chmod +x "${root}/scripts/release-local" "${root}/scripts/recheck-release-source.sh"
  printf 'module hostile.invalid/concealed\n\ngo 9.9.9\n' > "${root}/go.mod"
  printf 'version: 2\nhomebrew_casks:\n  - name: hostile\n' > "${root}/.goreleaser.yml"
  printf '## 9.9.9 - Unreleased\n\n- Hostile concealed maintainer notes.\n' > "${root}/CHANGELOG.md"
  cat > "${root}/.mac-release.env" <<'EOF'
MAC_RELEASE_BUNDLE_ID='org.openclaw.goplaces'
MAC_RELEASE_CODESIGN_IDENTITY='Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)'
MAC_RELEASE_CODESIGN_KEYCHAIN_MANAGED=1
MAC_RELEASE_CODESIGN_PASSWORDLESS=1
MAC_RELEASE_RUN_LOGIN_SHELL=0
MAC_RELEASE_CODESIGN_KEYCHAIN='/tmp/mock-release.keychain-db'
export NOTARYTOOL_KEYCHAIN_PROFILE='mock-notary-profile'
EOF
  chmod 600 "${root}/.mac-release.env"

  cat > "${root}/mock-bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git' >> "$MOCK_LOG"; printf ' <%s>' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
if [[ "${1:-}" == -c && "${2:-}" == core.hooksPath=/dev/null ]]; then
  shift 2
fi
[[ -z "${GIT_CONFIG_COUNT+x}" && -z "${GIT_INDEX_FILE+x}" && -z "${BASH_ENV+x}" ]] || {
  echo 'isolated git inherited hostile environment' >&2
  exit 94
}
case "$1 ${2:-}" in
  'remote get-url') printf '%s\n' "${MOCK_ORIGIN:-https://github.com/openclaw/goplaces}" ;;
  'fetch --prune') ;;
  'symbolic-ref --quiet') printf '%s\n' "${MOCK_BRANCH:-main}" ;;
  'rev-parse --verify') printf '%s\n' "${MOCK_SHA:-1111111111111111111111111111111111111111}" ;;
  'status --porcelain') [[ "${3:-}" == --untracked-files=all ]] || exit 95; printf '%s' "${MOCK_GIT_STATUS:-}" ;;
  'diff --check') ;;
  'show-ref --verify') exit 1 ;;
  'ls-remote --tags') ;;
  'ls-remote --heads') printf '%s\trefs/heads/main\n' "${MOCK_SHA:-1111111111111111111111111111111111111111}" ;;
  'init -q') mkdir -p "$3/.git" ;;
  '-C '*)
    case "${3:-} ${4:-}" in
      'remote add') ;;
      'fetch --quiet') ;;
      'rev-parse --verify') printf '%s\n' "${MOCK_SHA:-1111111111111111111111111111111111111111}" ;;
      'rev-parse --absolute-git-dir') printf '%s/.git\n' "$2" ;;
      'rev-parse --path-format=absolute')
        [[ "${5:-}" == --git-path ]] || exit 90
        case "${6:-}" in
          info/grafts) printf '%s/.git/info/grafts\n' "$2" ;;
          objects/info/alternates) printf '%s/.git/objects/info/alternates\n' "$2" ;;
          *) exit 90 ;;
        esac
        ;;
      'for-each-ref --format=%(refname)') ;;
      'merge-base --is-ancestor') ;;
      'checkout --quiet')
        mkdir -p "$2/scripts"
        printf 'module example.invalid/goplaces\n\ngo 1.26.5\n' > "$2/go.mod"
        printf 'version: 2\nrelease:\n  draft: true\n' > "$2/.goreleaser.yml"
        printf '## 0.4.5 - Unreleased\n\n- Protected pilot release.\n' > "$2/CHANGELOG.md"
        cp "$MOCK_FIXTURE_ROOT/scripts/release-local" "$2/scripts/release-local"
        cp "$MOCK_FIXTURE_ROOT/scripts/recheck-release-source.sh" "$2/scripts/recheck-release-source.sh"
        chmod +x "$2/scripts/release-local" "$2/scripts/recheck-release-source.sh"
        ;;
      'status --porcelain') [[ "${5:-}" == --untracked-files=all ]] || exit 95; printf '%s' "${MOCK_FRESH_STATUS:-}" ;;
      *) echo "unexpected isolated git command: $*" >&2; exit 90 ;;
    esac
    ;;
  *) echo "unexpected git command: $*" >&2; exit 90 ;;
esac
EOF
  cat > "${root}/mock-bin/go" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'go' >> "$MOCK_LOG"; printf ' <%s>' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
[[ "$*" == 'env GOVERSION' ]] || { echo "unexpected go command: $*" >&2; exit 90; }
printf '%s\n' "${MOCK_GO_VERSION:-go1.26.5}"
EOF
  cat > "${root}/mock-bin/goreleaser" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'goreleaser' >> "$MOCK_LOG"; printf ' <%s>' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
[[ "$*" == --version ]] || { echo "unexpected goreleaser command: $*" >&2; exit 90; }
printf 'GitVersion:    %s\n' "${MOCK_GORELEASER_VERSION:-2.16.0}"
EOF
  cat > "${root}/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh' >> "$MOCK_LOG"; printf ' <%s>' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
[[ "$1" == api ]] || { echo "unexpected gh command: $*" >&2; exit 90; }
joined=" $* "
[[ -z "${GH_HOST+x}" && -z "${GH_CONFIG_DIR+x}" ]] || { echo 'gh inherited a hostile host override' >&2; exit 92; }
[[ "$joined" == *' --hostname github.com '* ]] || { echo 'gh call is not pinned to github.com' >&2; exit 93; }
[[ "$joined" == *' X-GitHub-Api-Version: 2026-03-10 '* ]] || { echo 'missing API version' >&2; exit 91; }
endpoint=""
for arg in "$@"; do case "$arg" in repos/*) endpoint="$arg" ;; esac; done
case "$endpoint" in
  repos/openclaw/goplaces) printf '{"default_branch":"main"}\n' ;;
  repos/openclaw/goplaces/branches/main) printf '{"name":"main","protected":%s,"commit":{"sha":"%s"}}\n' "${MOCK_PROTECTED:-true}" "${MOCK_API_SHA:-${MOCK_SHA:-1111111111111111111111111111111111111111}}" ;;
  *) echo "unexpected gh endpoint: $endpoint" >&2; exit 90 ;;
esac
EOF
cat > "${root}/mock-bin/release-mac-app" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for forbidden_function in codesign security python3; do
  if declare -F "$forbidden_function" >/dev/null; then
    echo "release helper imported hostile function: $forbidden_function" >&2
    exit 90
  fi
done
/usr/bin/python3 -c 'import subprocess'
printf 'release-mac-app' >> "$MOCK_LOG"; printf ' <%s>' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
joined=" $* "
[[ "$PATH" == */producer-bin.*:/usr/bin:/bin:/usr/sbin:/sbin ]] || { echo 'release helper did not receive only its frozen runtimes plus system PATH' >&2; exit 91; }
[[ "$joined" != *'/opt/homebrew/bin'* && "$joined" != *'/usr/local/bin'* ]] || { echo 'producer command contains a mutable Homebrew PATH prefix' >&2; exit 91; }
[[ "$joined" != *'--with-package-secrets'* ]] || { echo 'package-secret mode reached release helper' >&2; exit 91; }
if [[ -n "${MAC_RELEASE_MANIFEST:-}" ]]; then
  [[ "$MAC_RELEASE_MANIFEST" == */release-manifest.*/manifest.env && -f "$MAC_RELEASE_MANIFEST" && ! -L "$MAC_RELEASE_MANIFEST" ]] || { echo 'release helper received wrong manifest' >&2; exit 91; }
  [[ "$(/usr/bin/stat -f '%Lp' "$MAC_RELEASE_MANIFEST")" == 400 ]] || { echo 'release helper manifest is not read-only' >&2; exit 91; }
fi
[[ "$joined" == *'/source '* || "$joined" == *'/protected-source '* ]] || { echo 'release helper did not receive fresh source' >&2; exit 92; }
[[ "$joined" != *" $MOCK_FIXTURE_ROOT "* ]] || { echo 'release helper received maintainer source' >&2; exit 93; }
[[ -z "${BASH_ENV+x}" && -z "${ENV+x}" && -z "${GIT_CONFIG_COUNT+x}" && -z "${GIT_INDEX_FILE+x}" ]] || { echo 'release helper inherited hostile startup or Git environment' >&2; exit 94; }
if [[ "$joined" == *'GOPLACES_PILOT_VERSION='* ]]; then
  [[ -z "${GITHUB_TOKEN+x}" ]] || { echo 'pilot inherited GitHub token' >&2; exit 95; }
  printf 'pilot-token-absent\n' >> "$MOCK_LOG"
else
  [[ -z "${GITHUB_TOKEN+x}" ]] || { echo 'draft token reached release helper setup' >&2; exit 96; }
  printf 'draft-token-deferred\n' >> "$MOCK_LOG"
fi
EOF
  printf '# frozen mock helper library\n' > "${root}/mock-bin/lib/mac_release.sh"
  chmod +x "${root}/mock-bin/"*
  write_fixture_producer_tools "$root" go1.26.5 2.16.0
}

write_fixture_producer_tools() {
  local root="$1" go_version="$2" goreleaser_version="$3"
  cat > "${root}/mock-bin/go" <<EOF
#!/bin/bash -p
set -euo pipefail
[[ "\$*" == 'env GOVERSION' ]] || { echo "unexpected go command: \$*" >&2; exit 90; }
printf '%s\\n' '$go_version'
EOF
  cat > "${root}/mock-bin/goreleaser" <<EOF
#!/bin/bash -p
set -euo pipefail
[[ "\$*" == --version ]] || { echo "unexpected goreleaser command: \$*" >&2; exit 90; }
printf 'GitVersion:    %s\\n' '$goreleaser_version'
EOF
  cat > "${root}/mock-bin/node" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ "$*" == --version ]] || exit 93
printf 'v26.5.0\n'
EOF
  cat > "${root}/mock-bin/expect" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ "$*" == -v ]] || exit 94
printf 'expect version 5.45.4\n'
EOF
  cat > "${root}/mock-bin/python3" <<'EOF'
#!/bin/bash -p
set -euo pipefail
if [[ "$*" == '-I --version' ]]; then
  printf 'Python 3.14.6\n'
  exit 0
fi
[[ "${1:-}" == -I ]] || exit 95
shift
exec /usr/bin/python3 -I "$@"
EOF
  chmod +x "${root}/mock-bin/go" "${root}/mock-bin/goreleaser" "${root}/mock-bin/node" "${root}/mock-bin/expect" "${root}/mock-bin/python3"
}

run_fixture() {
  local root="$1"
  local name
  local -a hostile_environment=(LC_ALL=C)
  shift
  for name in GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN HOMEBREW_TAP_GITHUB_TOKEN GH_HOST GH_CONFIG_DIR BASH_ENV ENV CDPATH GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_INDEX_FILE GORELEASER_CURRENT_TAG GORELEASER_PREVIOUS_TAG GORELEASER_EXPERIMENTAL GORELEASER_FORCE_TOKEN; do
    if [[ -n "${!name+x}" ]]; then
      hostile_environment+=("${name}=${!name}")
    fi
  done
  write_fixture_producer_tools "$root" "${MOCK_GO_VERSION:-go1.26.5}" "${MOCK_GORELEASER_VERSION:-2.16.0}"
  (
    cd "$root"
    /usr/bin/env -i \
      "${hostile_environment[@]}" \
      PATH="${root}/mock-bin:/opt/homebrew/bin:/usr/bin:/bin" \
      HOME="${root}/home" TMPDIR="${root}/tmp" MOCK_LOG="${root}/mock.log" \
      MOCK_GO_VERSION="${MOCK_GO_VERSION:-go1.26.5}" MOCK_GIT_STATUS="${MOCK_GIT_STATUS:-}" \
      MOCK_GORELEASER_VERSION="${MOCK_GORELEASER_VERSION:-2.16.0}" \
      MOCK_ORIGIN="${MOCK_ORIGIN:-https://github.com/openclaw/goplaces}" MOCK_BRANCH="${MOCK_BRANCH:-main}" MOCK_SHA="$SHA" \
      MOCK_PROTECTED="${MOCK_PROTECTED:-true}" MOCK_API_SHA="${MOCK_API_SHA:-$SHA}" \
      MOCK_FIXTURE_ROOT="$root" MOCK_FRESH_STATUS="${MOCK_FRESH_STATUS:-}" \
      GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 GOPLACES_RELEASE_LOCAL_SKIP_PROOFS=1 \
      GOPLACES_RELEASE_LOCAL_TEST_GIT_BIN="${root}/mock-bin/git" \
      GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${root}/mock-bin/gh" \
      RELEASE_MAC_APP_BIN="${root}/mock-bin/release-mac-app" \
      /bin/bash -p -c 'source "$1"; shift; main "$@"' _ "${root}/scripts/release-local" "$@"
  )
}

test_preflight_and_pilot_mocks() {
  local scratch
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-preflight-test.XXXXXX")"
  scratch="$(cd "$scratch" && pwd -P)"
  mkdir -p "${scratch}/home" "${scratch}/tmp"
  make_preflight_fixture "$scratch"
  : > "${scratch}/mock.log"
  run_fixture "$scratch" --check >/dev/null
  grep -Fq 'gh <api> <--hostname> <github.com> <-H> <X-GitHub-Api-Version: 2026-03-10> <repos/openclaw/goplaces>' "${scratch}/mock.log" || die "preflight did not pin the API host and version"

  MOCK_GO_VERSION=go1.26.4 expect_failure "old native Go" run_fixture "$scratch" --check
  MOCK_GO_VERSION=go1.26.6 expect_failure "future native Go" run_fixture "$scratch" --check
  MOCK_GORELEASER_VERSION=2.15.2 expect_failure "old GoReleaser" run_fixture "$scratch" pilot v0.4.5
  MOCK_GORELEASER_VERSION=2.17.0 expect_failure "future GoReleaser" run_fixture "$scratch" pilot v0.4.5
  MOCK_GIT_STATUS='?? hostile' expect_failure "dirty checkout" run_fixture "$scratch" --check
  MOCK_ORIGIN=https://github.com/example/goplaces expect_failure "wrong origin" run_fixture "$scratch" --check
  MOCK_BRANCH=release expect_failure "wrong branch" run_fixture "$scratch" --check
  : > "${scratch}/mock.log"
  MOCK_PROTECTED=false expect_failure "unprotected default branch" run_fixture "$scratch" pilot v0.4.5
  ! grep -Fq 'release-mac-app' "${scratch}/mock.log" || die "unprotected branch reached a release action"
  : > "${scratch}/mock.log"
  MOCK_API_SHA=3333333333333333333333333333333333333333 expect_failure "moved API default SHA" run_fixture "$scratch" pilot v0.4.5
  ! grep -Fq 'release-mac-app' "${scratch}/mock.log" || die "moved API SHA reached a release action"
  if (
    cd "$scratch"
    env -i PATH="${scratch}/mock-bin:/opt/homebrew/bin:/usr/bin:/bin" HOME="${scratch}/home" TMPDIR="${scratch}/tmp" MOCK_LOG="${scratch}/mock.log" \
      MOCK_SHA="$SHA" GOFLAGS=-mod=mod GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 GOPLACES_RELEASE_LOCAL_SKIP_PROOFS=1 \
      RELEASE_MAC_APP_BIN="${scratch}/mock-bin/release-mac-app" \
      /bin/bash -p -c 'source "$1"; shift; main "$@"' _ "${scratch}/scripts/release-local" --check
  ) >/dev/null 2>&1; then
    die "ambient GOFLAGS was accepted"
  fi
  local auth_name
  for auth_name in GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN HOMEBREW_TAP_GITHUB_TOKEN; do
    export "$auth_name="
    expect_failure "empty ambient $auth_name" run_fixture "$scratch" --check
    unset "$auth_name"
  done
  local release_control
  for release_control in GORELEASER_CURRENT_TAG GORELEASER_PREVIOUS_TAG GORELEASER_EXPERIMENTAL GORELEASER_FORCE_TOKEN; do
    export "$release_control=hostile"
    expect_failure "ambient $release_control" run_fixture "$scratch" --check
    unset "$release_control"
  done

  /bin/cp "${scratch}/.mac-release.env" "${scratch}/manifest.safe"
  printf "MAC_RELEASE_OP_ITEM='forbidden'\n" >> "${scratch}/.mac-release.env"
  : > "${scratch}/mock.log"
  expect_failure "manifest package-secret locator" run_fixture "$scratch" pilot v0.4.5
  ! grep -Fq 'release-mac-app' "${scratch}/mock.log" || die "forbidden manifest reached release-mac-app"
  /bin/mv -f "${scratch}/manifest.safe" "${scratch}/.mac-release.env"
  chmod 600 "${scratch}/.mac-release.env"

  /bin/cp "${scratch}/.mac-release.env" "${scratch}/manifest.safe"
  env -i PATH="${scratch}/mock-bin:/usr/bin:/bin" HOME="${scratch}/home" TMPDIR="${scratch}/tmp" \
    GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="${scratch}/mock-bin/release-mac-app" \
    /bin/bash -p -c '
      source "$1"
      prepare_producer_gate
      validate_release_manifest
      printf "MAC_RELEASE_OP_ITEM=\047mutated-original\047\n" >> "$repo_root/.mac-release.env"
      recheck_release_manifest
    ' _ "${scratch}/scripts/release-local"
  /bin/mv -f "${scratch}/manifest.safe" "${scratch}/.mac-release.env"
  chmod 600 "${scratch}/.mac-release.env"
  if env -i PATH="${scratch}/mock-bin:/usr/bin:/bin" HOME="${scratch}/home" TMPDIR="${scratch}/tmp" \
    GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="${scratch}/mock-bin/release-mac-app" \
    /bin/bash -p -c '
      source "$1"
      prepare_producer_gate
      validate_release_manifest
      /bin/chmod 600 "$release_manifest"
      printf "# mutated frozen bytes\n" >> "$release_manifest"
      /bin/chmod 400 "$release_manifest"
      recheck_release_manifest
    ' _ "${scratch}/scripts/release-local" >/dev/null 2>&1; then
    die "frozen release manifest byte mutation was accepted"
  fi
  if env -i PATH="${scratch}/mock-bin:/usr/bin:/bin" HOME="${scratch}/home" TMPDIR="${scratch}/tmp" \
    GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1 RELEASE_MAC_APP_BIN="${scratch}/mock-bin/release-mac-app" \
    /bin/bash -p -c '
      source "$1"
      prepare_producer_gate
      validate_release_manifest
      /bin/cp "$release_manifest" "${release_manifest}.replacement"
      /bin/chmod 400 "${release_manifest}.replacement"
      /bin/mv -f "${release_manifest}.replacement" "$release_manifest"
      recheck_release_manifest
    ' _ "${scratch}/scripts/release-local" >/dev/null 2>&1; then
    die "same-byte release manifest replacement was accepted"
  fi
  /bin/cp "${scratch}/.mac-release.env" "${scratch}/manifest.safe"
  /usr/bin/sed 's#/tmp/mock-release.keychain-db#/tmp/../hostile.keychain-db#' "${scratch}/manifest.safe" > "${scratch}/.mac-release.env"
  chmod 600 "${scratch}/.mac-release.env"
  expect_failure "nonnormalized manifest keychain locator" run_fixture "$scratch" pilot v0.4.5
  /bin/mv -f "${scratch}/manifest.safe" "${scratch}/.mac-release.env"
  chmod 600 "${scratch}/.mac-release.env"
  /bin/cp "${scratch}/.mac-release.env" "${scratch}/manifest.safe"
  printf "export NOTARYTOOL_KEYCHAIN_PROFILE='duplicate'\n" >> "${scratch}/.mac-release.env"
  expect_failure "duplicate manifest notary profile" run_fixture "$scratch" pilot v0.4.5
  /bin/mv -f "${scratch}/manifest.safe" "${scratch}/.mac-release.env"
  chmod 600 "${scratch}/.mac-release.env"

  : > "${scratch}/mock.log"
  # Models a maintainer checkout where assume-unchanged/skip-worktree and
  # status.showUntrackedFiles=no conceal build-influencing Go source. The
  # release wrapper must still receive only the separately fetched source.
  printf 'package hostile\n' > "${scratch}/concealed.go"
  local injection startup_sentinel
  injection="${scratch}/bash-env-injection"
  startup_sentinel="${scratch}/bash-env-ran"
  printf 'touch "%s"\n' "$startup_sentinel" > "$injection"
  BASH_ENV="$injection" GH_HOST=evil.example GH_CONFIG_DIR="${scratch}/evil-gh" \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.showUntrackedFiles GIT_CONFIG_VALUE_0=no GIT_INDEX_FILE="${scratch}/hostile-index" \
    run_fixture "$scratch" pilot v0.4.5 >/dev/null
  [[ ! -e "$startup_sentinel" ]] || die "BASH_ENV executed in the entrypoint or a release subprocess"
  grep -Fq 'release-mac-app <fixture-run> <--> </usr/bin/env> <-u> <GITHUB_TOKEN>' "${scratch}/mock.log" || die "pilot did not use the isolated codesigned source path"
  grep -Fq '<GOPLACES_PILOT_VERSION=0.4.5>' "${scratch}/mock.log" || die "pilot lost its exact version marker"
  grep -Eq '<\./scripts/recheck-release-source\.sh> <pilot> .* <--> <release> <--snapshot> <--clean> <--skip=publish> <--config> <\.goreleaser\.yml>' "${scratch}/mock.log" || die "pilot lost the protected exact tagless snapshot command"
  [[ "$(grep -Fc '<status> <--porcelain> <--untracked-files=all>' "${scratch}/mock.log")" -ge 2 ]] || die "maintainer and fresh-source status checks are not explicit about untracked files"
  grep -Eq '<-C> <[^>]*goplaces-git-isolation\.[^>]*/protected-source>' "${scratch}/mock.log" || die "pilot did not pin the wrapper to a fresh protected source directory"
  grep -Fq 'pilot-token-absent' "${scratch}/mock.log" || die "pilot did not prove GitHub token absence"
  if grep -Eq '<--method> <(POST|PATCH)>|/dispatches' "${scratch}/mock.log"; then
    die "pilot performed a public mutation"
  fi

  sentinel="${scratch}/sentinel"
  expect_failure "hostile tag" run_fixture "$scratch" pilot 'v0.4.5$(touch sentinel)'
  [[ ! -e "$sentinel" ]] || die "hostile tag executed shell content"
  rm -rf "$scratch"
}

test_codesign_wrapper_scopes_auth_and_startup_env() {
  local scratch source injection sentinel notes python_sentinel
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-codesign-env.XXXXXX")"
  scratch="$(cd "$scratch" && pwd -P)"
  mkdir -p "${scratch}/home" "${scratch}/tmp"
  make_preflight_fixture "$scratch"
  source="${scratch}/source"
  mkdir -p "$source/scripts"
  cp "${repo_root}/scripts/recheck-release-source.sh" "$source/scripts/recheck-release-source.sh"
  chmod +x "$source/scripts/recheck-release-source.sh"
  injection="${scratch}/bash-env"
  sentinel="${scratch}/bash-env-ran"
  python_sentinel="${scratch}/python-path-ran"
  mkdir -p "${scratch}/evil-python"
  cat > "${scratch}/evil-python/subprocess.py" <<'PY'
import os
open(os.environ["PYTHON_SENTINEL"], "w", encoding="utf-8").close()
PY
  printf 'touch "%s"\n' "$sentinel" > "$injection"
  : > "${scratch}/mock.log"
  (
    source_release
    PATH="${scratch}/mock-bin:$PATH"
    export PATH
    release_mac_app="${scratch}/mock-bin/release-mac-app"
    draft_github_token=mock_token_value
    export MOCK_LOG="${scratch}/mock.log" MOCK_FIXTURE_ROOT="$scratch"
    export BASH_ENV="$injection" ENV="$injection" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.showUntrackedFiles GIT_CONFIG_VALUE_0=no GIT_INDEX_FILE="${scratch}/hostile-index"
    export PYTHONPATH="${scratch}/evil-python" PYTHONHOME="${scratch}/evil-home" PYTHON_SENTINEL="$python_sentinel"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    notes="${scratch}/notes.md"
    printf 'notes\n' > "$notes"
    codesign() { touch "$sentinel"; }
    security() { touch "$sentinel"; }
    python3() { touch "$sentinel"; }
    export -f codesign security python3
    run_codesigned_goreleaser "$source" draft v0.4.5 release --clean --config .goreleaser.yml --release-notes "$notes"
  )
  [[ ! -e "$sentinel" ]] || die "codesign wrapper executed hostile shell startup content"
  [[ ! -e "$python_sentinel" ]] || die "release helper imported hostile Python startup content"
  grep -Fq 'draft-token-deferred' "${scratch}/mock.log" || die "draft authentication reached release helper setup"
  ! grep -Fq 'mock_token_value' "${scratch}/mock.log" || die "draft token leaked into command arguments"
  if (
    source_release
    PATH="${scratch}/mock-bin:$PATH"
    export PATH
    release_mac_app="${scratch}/mock-bin/release-mac-app"
    draft_github_token=""
    export MOCK_LOG="${scratch}/mock.log" MOCK_FIXTURE_ROOT="$scratch"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    run_codesigned_goreleaser "$source" draft v0.4.5 release --clean --config .goreleaser.yml --release-notes "${scratch}/notes.md"
  ) >/dev/null 2>&1; then
    die "empty draft authentication token was accepted"
  fi
  rm -rf "$scratch"
}

test_draft_canonicalizes_tmpdir_paths() {
  local scratch real_tmp alias_tmp marker
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-draft-path.XXXXXX")"
  scratch="$(cd "$scratch" && pwd -P)"
  real_tmp="${scratch}/real-tmp"
  alias_tmp="${scratch}/alias-tmp"
  marker="${scratch}/canonical-paths"
  mkdir -p "$real_tmp"
  ln -s "$real_tmp" "$alias_tmp"
  (
    export TMPDIR="$alias_tmp"
    GOPLACES_RELEASE_LOCAL_TESTING=1
    GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    export GOPLACES_RELEASE_LOCAL_TESTING GOPLACES_RELEASE_LOCAL_SOURCE_ONLY
    # shellcheck source=release-local
    source "$release_script"
    prepare_official_producer_gate() { :; }
    preflight_repository() { :; }
    verify_remote_tag() { :; }
    recheck_source_default() { :; }
    init_release_state() { :; }
    prepare_draft_intent() { draft_intent_created=true; }
    resolve_intended_draft_id() { :; }
    prepare_remote_source() { mkdir -p "$1"; }
    extract_release_notes() { printf 'notes\n' > "$3"; }
    gh_auth_token() { printf 'mocktoken\n'; }
    freeze_initial_draft() { :; }
    run_codesigned_goreleaser() {
      local source_path="$1" notes_path=""
      shift 3
      while (($#)); do
        if [[ "$1" == --release-notes ]]; then
          shift
          notes_path="${1:-}"
          break
        fi
        shift
      done
      [[ -n "$notes_path" && "$notes_path" == "$(/bin/realpath "$notes_path")" ]] || return 90
      [[ "$source_path" == "$(/bin/realpath "$source_path")" ]] || return 91
      printf 'canonical\n' > "$marker"
    }
    run_draft v0.4.5
  )
  [[ "$(cat "$marker")" == canonical ]] || die "draft did not pass canonical source and release-notes paths"
  rm -rf "$scratch"
}

test_reproducer_uses_frozen_module_cache() {
  local scratch cache fake_go log hostile_env sentinel
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-repro-cache.XXXXXX")"
  scratch="$(cd "$scratch" && pwd -P)"
  cache="${scratch}/module-cache"
  fake_go="${scratch}/go"
  log="${scratch}/go.log"
  mkdir -p "$cache"
  cat > "$fake_go" <<'EOF'
#!/bin/bash -p
set -euo pipefail
fake_root="$(cd "$(dirname "$0")" && pwd -P)"
[[ "${GOWORK:-}" == off ]] || exit 94
printf '%s\n' "$*" >> "${fake_root}/go.log"
case "$*" in
  'env GOVERSION') printf 'go1.26.5\n' ;;
  'env GOMODCACHE') exit 91 ;;
  build\ *)
    output=""
    while (($#)); do
      if [[ "$1" == -o ]]; then shift; output="${1:-}"; break; fi
      shift
    done
    [[ -n "$output" ]] || exit 92
    mkdir -p "$(dirname "$output")"
    printf 'deterministic fixture binary\n' > "$output"
    ;;
  *) exit 93 ;;
esac
EOF
  chmod +x "$fake_go"
  GO_BIN="$fake_go" GOMODCACHE="$cache" "${repo_root}/scripts/test-reproducible-builds.sh" >/dev/null
  ! grep -Fxq 'env GOMODCACHE' "$log" || die "reproducer discarded the frozen incoming module cache"
  [[ "$(grep -c '^build ' "$log")" == 12 ]] || die "reproducer did not build every target twice"
  hostile_env="${scratch}/hostile-bin"
  sentinel="${scratch}/ambient-env-ran"
  mkdir -p "$hostile_env"
  cat > "${hostile_env}/env" <<EOF
#!/bin/bash -p
touch '$sentinel'
exit 0
EOF
  chmod +x "${hostile_env}/env"
  : > "$log"
  PATH="${hostile_env}:$PATH" GO_BIN="$fake_go" GOMODCACHE="$cache" \
    "${repo_root}/scripts/test-reproducible-builds.sh" >/dev/null
  [[ ! -e "$sentinel" ]] || die "reproducer executed env from hostile PATH"
  [[ "$(grep -c '^build ' "$log")" == 12 ]] || die "pinned empty-environment command skipped reproduction"
  rm -rf "$scratch"
}

test_protected_helper_environment_is_allowlisted() {
  local scratch source probe log
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-protected-helper.XXXXXX")"
  source="${scratch}/source"
  probe="${source}/scripts/probe.sh"
  log="${scratch}/probe.log"
  mkdir -p "${source}/scripts"
  cat > "$probe" <<'EOF'
#!/bin/bash -p
set -euo pipefail
[[ "$PWD" == "$(cd "$(dirname "$0")/.." && pwd -P)" ]] || exit 81
[[ -n "${GH_TOKEN:-}" ]] || exit 82
for name in BASH_ENV ENV CDPATH GIT_CONFIG_COUNT GIT_INDEX_FILE GITHUB_API_URL ALLOW_TEST_API_URL CURL_BIN JQ_BIN VERIFY_TAG_BIN GITHUB_REPOSITORY GH_HOST GH_CONFIG_DIR; do
  [[ -z "${!name+x}" ]] || exit 83
done
printf 'protected-helper-safe\n' > "$1"
EOF
  chmod +x "$probe"
  (
    source_release
    protected_source_root="$source"
    export BASH_ENV="${scratch}/hostile" GITHUB_API_URL=https://evil.example ALLOW_TEST_API_URL=1 CURL_BIN="${scratch}/fake-curl" JQ_BIN="${scratch}/fake-jq"
    export VERIFY_TAG_BIN="${scratch}/fake-verifier" GITHUB_REPOSITORY=evil/repo GH_HOST=evil.example GH_CONFIG_DIR="${scratch}/evil-gh"
    GH_TOKEN=unit_secret_token run_protected_script scripts/probe.sh "$log"
  )
  [[ "$(cat "$log")" == protected-helper-safe ]] || die "protected helper did not run in its allowlisted environment"
  ! grep -Fq 'forwarded_environment+=("GH_TOKEN=' "$release_script" || die "protected helper places GH_TOKEN in env argv"
  rm -rf "$scratch"
}

run_final_tap_fixture() {
  local scratch="$1" log="$2" formula="$3" mode="$4"
  local expected_head="3333333333333333333333333333333333333333"
  (
    source_release
    tap_default_branch=main
    tap_workflow_id=220664022
    verify_homebrew_install() {
      [[ "$3" == "$formula" && "$5" == "$expected_head" ]] || exit 81
      printf 'brew-test-exact-formula\n' >> "$log"
    }
    verify_remote_tag() { printf 'git-remote-tag\n' >> "$log"; }
    recheck_source_default() { printf 'git-remote-main\n' >> "$log"; }
    verify_frozen_release() { printf 'gh-release\n' >> "$log"; }
    gh_api() {
      local endpoint="$1" protected=true branch_sha="$expected_head" branch_name=main compare_base="$TAP_BASE" compare_merge="$TAP_BASE" compare_head="$expected_head"
      printf 'gh:%s\n' "$endpoint" >> "$log"
      case "$endpoint" in
        repos/openclaw/homebrew-tap) printf '{"default_branch":"main"}\n' ;;
        repos/openclaw/homebrew-tap/compare/*)
          case "$mode" in
            compare-base) compare_base=4444444444444444444444444444444444444444 ;;
            compare-merge) compare_merge=4444444444444444444444444444444444444444 ;;
            compare-head) compare_head=4444444444444444444444444444444444444444 ;;
          esac
          printf '{"status":"ahead","ahead_by":1,"behind_by":0,"total_commits":1,"base_commit":{"sha":"%s"},"merge_base_commit":{"sha":"%s"},"head_commit":{"sha":"%s"}}\n' "$compare_base" "$compare_merge" "$compare_head"
          ;;
        repos/openclaw/homebrew-tap/branches/main)
          case "$mode" in
            success) ;;
            unprotected) protected=false ;;
            moved) branch_sha=4444444444444444444444444444444444444444 ;;
            branch-name) branch_name=release ;;
            compare-base|compare-merge|compare-head) ;;
            *) exit 82 ;;
          esac
          printf '{"name":"%s","protected":%s,"commit":{"sha":"%s"}}\n' "$branch_name" "$protected" "$branch_sha"
          ;;
        *) exit 83 ;;
      esac
    }
    fetch_content_record() {
      printf 'content:%s@%s\n' "$2" "$3" >> "$log"
      printf '{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' > "$4"
    }
    workflow_record() {
      printf 'workflow:%s\n' "$2" >> "$log"
      printf '{"id":220664022}\n' > "$3"
    }
    verify_tap_cask_quarantine() { printf 'cask:%s\n' "$1" >> "$log"; }
    complete_homebrew_closeout "$scratch" v0.4.5 "$formula" "${scratch}/assets" "$expected_head" "${scratch}/notes" "${scratch}/published"
  )
}

test_final_tap_check_is_last_external_closeout() {
  local scratch log formula mode
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-final-tap-order.XXXXXX")"
  log="${scratch}/events"
  formula="${scratch}/verified-goplaces.rb"
  run_final_tap_fixture "$scratch" "$log" "$formula" success
  [[ "$(head -n 1 "$log")" == brew-test-exact-formula ]] || die "Homebrew proof did not precede final external rechecks"
  [[ "$(tail -n 1 "$log")" == 'gh:repos/openclaw/homebrew-tap/branches/main' ]] || die "exact live tap branch is not the final external closeout action"
  for mode in unprotected moved branch-name; do
    : > "$log"
    if run_final_tap_fixture "$scratch" "$log" "$formula" "$mode" >/dev/null 2>&1; then
      die "post-brew ${mode} tap head unexpectedly succeeded"
    fi
    [[ "$(head -n 1 "$log")" == brew-test-exact-formula ]] || die "post-brew ${mode} regression failed before Homebrew proof"
    [[ "$(tail -n 1 "$log")" == 'gh:repos/openclaw/homebrew-tap/branches/main' ]] || die "post-brew ${mode} regression did not fail on the final live branch check"
  done
  for mode in compare-base compare-merge compare-head; do
    : > "$log"
    if run_final_tap_fixture "$scratch" "$log" "$formula" "$mode" >/dev/null 2>&1; then
      die "post-brew ${mode} direct-child mismatch unexpectedly succeeded"
    fi
    [[ "$(head -n 1 "$log")" == brew-test-exact-formula ]] || die "post-brew ${mode} regression failed before Homebrew proof"
    grep -Fq 'gh:repos/openclaw/homebrew-tap/compare/' "$log" || die "post-brew ${mode} regression did not reach the exact compare record"
  done
  rm -rf "$scratch"
}

test_pre_dispatch_tap_recheck_is_exact_base() {
  local scratch log
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-tap-before-dispatch.XXXXXX")"
  log="${scratch}/events"
  (
    source_release
    tap_head="$TAP_BASE"
    tap_workflow_id=220664022
    tap_trust_preflight() {
      [[ "$1" == "${scratch}/success" ]] || exit 81
      printf 'pre-dispatch-trust\n' >> "$log"
      tap_head="$TAP_BASE"
      tap_workflow_id=220664022
    }
    recheck_tap_contract_before "${scratch}/success" "$TAP_BASE" 220664022
  )
  [[ "$(cat "$log")" == pre-dispatch-trust ]] || die "successful exact-base pre-dispatch tap recheck did not run"
  if (
    source_release
    tap_head="$TAP_BASE"
    tap_workflow_id=220664022
    tap_trust_preflight() {
      tap_head=3333333333333333333333333333333333333333
      tap_workflow_id=220664022
    }
    recheck_tap_contract_before "${scratch}/moved" "$TAP_BASE" 220664022
  ) >/dev/null 2>&1; then
    die "moved pre-dispatch tap identity was accepted"
  fi
  if (
    source_release
    tap_head="$TAP_BASE"
    tap_workflow_id=220664022
    tap_trust_preflight() {
      tap_head="$TAP_BASE"
      tap_workflow_id=220664023
    }
    recheck_tap_contract_before "${scratch}/workflow-moved" "$TAP_BASE" 220664022
  ) >/dev/null 2>&1; then
    die "moved pre-dispatch tap workflow ID was accepted"
  fi
  rm -rf "$scratch"
}

test_tap_install_uses_fresh_exact_checkout() {
  local scratch formula log checkout_head result
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-tap-install-source.XXXXXX")"
  formula="${scratch}/verified-goplaces.rb"
  log="${scratch}/git.log"
  checkout_head="3333333333333333333333333333333333333333"
  printf 'class Goplaces < Formula\nend\n' > "$formula"
  (
    source_release
    tap_default_branch=main
    isolated_git() {
      printf '%s\n' "$*" >> "$log"
      case "$1" in
        init)
          mkdir -p "$3/.git" "$3/Formula"
          cp "$formula" "$3/Formula/goplaces.rb"
          ;;
        -C)
          case "${3:-} ${4:-}" in
            'remote add') [[ "${5:-}" == origin && "${6:-}" == https://github.com/openclaw/homebrew-tap.git ]] || exit 81 ;;
            'fetch --quiet') ;;
            'rev-parse --verify')
              case "${5:-}" in
                refs/remotes/origin/main) printf '%s\n' "${MOCK_TAP_HEAD:-$checkout_head}" ;;
                HEAD) printf '%s\n' "$checkout_head" ;;
                *) exit 82 ;;
              esac
              ;;
            'checkout --quiet') ;;
            'status --porcelain') [[ "${5:-}" == --untracked-files=all ]] || exit 95; printf '%s' "${MOCK_TAP_STATUS:-}" ;;
            *) exit 83 ;;
          esac
          ;;
        *) exit 84 ;;
      esac
    }
    trusted_is_ancestor() {
      [[ "$1" == "${scratch}/checkout" && "$2" == "$TAP_BASE" && "$3" == "$checkout_head" ]] || exit 85
      printf 'trusted-ancestry\n' >> "$log"
    }
    result="$(prepare_tap_install_source "${scratch}/checkout" "$checkout_head" "$formula")"
    [[ "$result" == "${scratch}/checkout/Formula/goplaces.rb" ]] || exit 86
  )
  grep -Fq 'remote add origin https://github.com/openclaw/homebrew-tap.git' "$log" || die "fresh tap checkout did not use the official remote"
  grep -Fq 'status --porcelain --untracked-files=all' "$log" || die "fresh tap checkout did not expose all untracked files"
  if (
    source_release
    tap_default_branch=main
    isolated_git() {
      case "$1" in
        init) mkdir -p "$3/.git" "$3/Formula"; cp "$formula" "$3/Formula/goplaces.rb" ;;
        -C)
          case "${3:-} ${4:-}" in
            'remote add'|'fetch --quiet'|'checkout --quiet') ;;
            'rev-parse --verify') printf '%s\n' "$checkout_head" ;;
            'status --porcelain') [[ "${5:-}" == --untracked-files=all ]] || exit 95; printf '?? injected.go\n' ;;
            *) exit 87 ;;
          esac
          ;;
        *) exit 88 ;;
      esac
    }
    trusted_is_ancestor() { :; }
    prepare_tap_install_source "${scratch}/dirty-checkout" "$checkout_head" "$formula"
  ) >/dev/null 2>&1; then
    die "dirty fresh tap checkout was accepted"
  fi
  if (
    source_release
    tap_default_branch=main
    isolated_git() {
      case "$1" in
        init) mkdir -p "$3/.git" "$3/Formula"; cp "$formula" "$3/Formula/goplaces.rb" ;;
        -C)
          case "${3:-} ${4:-}" in
            'remote add'|'fetch --quiet'|'checkout --quiet') ;;
            'rev-parse --verify')
              case "${5:-}" in
                refs/remotes/origin/main) printf '%s\n' "$checkout_head" ;;
                HEAD) printf '4444444444444444444444444444444444444444\n' ;;
                *) exit 89 ;;
              esac
              ;;
            'status --porcelain') [[ "${5:-}" == --untracked-files=all ]] || exit 95 ;;
            *) exit 90 ;;
          esac
          ;;
        *) exit 91 ;;
      esac
    }
    trusted_is_ancestor() { :; }
    prepare_tap_install_source "${scratch}/moved-checkout" "$checkout_head" "$formula"
  ) >/dev/null 2>&1; then
    die "moved fresh tap checkout was accepted"
  fi
  if (
    source_release
    tap_default_branch=main
    isolated_git() {
      case "$1" in
        init) mkdir -p "$3/.git" "$3/Formula"; cp "$formula" "$3/Formula/goplaces.rb" ;;
        -C)
          case "${3:-} ${4:-}" in
            'remote add'|'fetch --quiet'|'checkout --quiet') ;;
            'rev-parse --verify')
              case "${5:-}" in
                refs/remotes/origin/main) printf '4444444444444444444444444444444444444444\n' ;;
                HEAD) printf '%s\n' "$checkout_head" ;;
                *) exit 95 ;;
              esac
              ;;
            'status --porcelain') [[ "${5:-}" == --untracked-files=all ]] || exit 95 ;;
            *) exit 96 ;;
          esac
          ;;
        *) exit 97 ;;
      esac
    }
    trusted_is_ancestor() { :; }
    prepare_tap_install_source "${scratch}/moved-fetched-ref" "$checkout_head" "$formula"
  ) >/dev/null 2>&1; then
    die "fresh tap checkout accepted a moved fetched default ref"
  fi
  if (
    source_release
    tap_default_branch=main
    isolated_git() {
      case "$1" in
        init) mkdir -p "$3/.git" "$3/Formula"; printf 'hostile bytes\n' > "$3/Formula/goplaces.rb" ;;
        -C)
          case "${3:-} ${4:-}" in
            'remote add'|'fetch --quiet'|'checkout --quiet') ;;
            'rev-parse --verify') printf '%s\n' "$checkout_head" ;;
            'status --porcelain') [[ "${5:-}" == --untracked-files=all ]] || exit 95 ;;
            *) exit 92 ;;
          esac
          ;;
        *) exit 93 ;;
      esac
    }
    trusted_is_ancestor() { :; }
    prepare_tap_install_source "${scratch}/mismatched-formula" "$checkout_head" "$formula"
  ) >/dev/null 2>&1; then
    die "fresh tap checkout with mismatched Formula bytes was accepted"
  fi
  if (
    source_release
    isolated_git() {
      [[ "$*" == "-C ${scratch}/post-brew status --porcelain --untracked-files=all" ]] || exit 94
      printf '?? post-brew-injected.go\n'
    }
    recheck_tap_install_source "${scratch}/post-brew" "post-brew checkout dirty"
  ) >/dev/null 2>&1; then
    die "post-brew dirty tap checkout was accepted"
  fi
  rm -rf "$scratch"
}

run_homebrew_reproof_fixture() {
  local fixture="$1" mutation="$2" archive_dir copy_dir fixture_prefix
  archive_dir="${fixture}/archive"
  copy_dir="${fixture}/copy"
  fixture_prefix="${fixture}/prefix"
  mkdir -p "$archive_dir" "$copy_dir" "$fixture_prefix/bin" "${fixture}/home" "${fixture}/tmp"
  printf 'verified release binary\n' > "${archive_dir}/goplaces"
  tar -czf "${copy_dir}/goplaces_0.4.5_darwin_arm64.tar.gz" -C "$archive_dir" goplaces
  printf 'class Goplaces < Formula\nend\n' > "${fixture}/goplaces.rb"
  (
    source_release
    prepare_tap_install_source() {
      cp "$3" "${fixture}/checkout-goplaces.rb"
      printf '%s\n' "${fixture}/checkout-goplaces.rb"
    }
    need() { :; }
    uname() { if [[ "${1:-}" == -m ]]; then printf 'arm64\n'; else printf 'Darwin\n'; fi; }
    homebrew_command() {
      case "$1" in
        list) return 1 ;;
        install)
          mkdir -p "${fixture_prefix}/bin"
          cp "${archive_dir}/goplaces" "${fixture_prefix}/bin/goplaces"
          ;;
        --prefix) printf '%s\n' "$fixture_prefix" ;;
        test)
          case "$mutation" in
            binary) printf 'mutated by brew test\n' > "${fixture_prefix}/bin/goplaces" ;;
            formula) printf 'mutated Formula\n' > "$formula" ;;
          esac
          ;;
        *) return 90 ;;
      esac
    }
    run_protected_script() { printf 'verify\n' >> "${fixture}/verify.log"; }
    recheck_tap_install_source() { :; }
    verify_homebrew_install "$fixture" v0.4.5 "${fixture}/goplaces.rb" "$copy_dir" "$SHA"
  )
}

test_homebrew_reproves_after_package_test() {
  local scratch
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-reproof.XXXXXX")"
  run_homebrew_reproof_fixture "$scratch" none
  [[ "$(grep -c '^verify$' "${scratch}/verify.log")" == 2 ]] || die "installed binary was not verified both before and after brew test"
  rm -rf "$scratch"
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-reproof.XXXXXX")"
  expect_failure "brew test binary self-mutation" run_homebrew_reproof_fixture "$scratch" binary
  rm -rf "$scratch"
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-reproof.XXXXXX")"
  expect_failure "brew test Formula mutation" run_homebrew_reproof_fixture "$scratch" formula
  rm -rf "$scratch"
}

prepare_homebrew_dispatch_fixture() {
  local hb_root="$1" hb_binding="$2" hb_state hb_seen hb_response hb_release_sha
  local hb_darwin_amd64 hb_darwin_arm64 hb_linux_amd64 hb_linux_arm64 hb_title
  hb_state="${hb_root}/state"
  hb_seen="${hb_root}/seen.json"
  hb_response="${hb_root}/dispatch.json"
  mkdir -p "$hb_state" "${hb_root}/assets" "${hb_root}/protected" "${hb_root}/tmp"
  printf 'darwin amd64\n' > "${hb_root}/assets/goplaces_0.4.5_darwin_amd64.tar.gz"
  printf 'darwin arm64\n' > "${hb_root}/assets/goplaces_0.4.5_darwin_arm64.tar.gz"
  printf 'linux amd64\n' > "${hb_root}/assets/goplaces_0.4.5_linux_amd64.tar.gz"
  printf 'linux arm64\n' > "${hb_root}/assets/goplaces_0.4.5_linux_arm64.tar.gz"
  jq -n '{state:"published"}' > "${hb_root}/published-source.json"
  printf '[]\n' > "$hb_seen"
  hb_release_sha="$(test_sha256 "${hb_root}/published-source.json")"
  hb_darwin_amd64="$(test_sha256 "${hb_root}/assets/goplaces_0.4.5_darwin_amd64.tar.gz")"
  hb_darwin_arm64="$(test_sha256 "${hb_root}/assets/goplaces_0.4.5_darwin_arm64.tar.gz")"
  hb_linux_amd64="$(test_sha256 "${hb_root}/assets/goplaces_0.4.5_linux_amd64.tar.gz")"
  hb_linux_arm64="$(test_sha256 "${hb_root}/assets/goplaces_0.4.5_linux_arm64.tar.gz")"
  (
    export TMPDIR="${hb_root}/tmp"
    source_release
    release_state_dir="$hb_state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    prepare_homebrew_intent "${hb_state}/homebrew-intent.json" v0.4.5 777 "$hb_release_sha" \
      "$hb_darwin_amd64" "$hb_darwin_arm64" "$hb_linux_amd64" "$hb_linux_arm64" "$hb_seen"
    if [[ "$hb_binding" == direct ]]; then
      jq -n --argjson id 29010348667 --arg repo openclaw/homebrew-tap '{
        workflow_run_id:$id,
        run_url:("https://api.github.com/repos/" + $repo + "/actions/runs/" + ($id | tostring)),
        html_url:("https://github.com/" + $repo + "/actions/runs/" + ($id | tostring))
      }' > "$hb_response"
      bind_homebrew_intent_run "${hb_state}/homebrew-intent.json" 29010348667 false "$hb_response"
      validate_homebrew_intent "${hb_state}/homebrew-intent.json" v0.4.5 777 "$hb_release_sha" \
        "$hb_darwin_amd64" "$hb_darwin_arm64" "$hb_linux_amd64" "$hb_linux_arm64"
    fi
  )
  hb_title="$(jq -er '.expected_title' "${hb_state}/homebrew-intent.json")"
  jq -n --argjson id 29010348667 --arg title "$hb_title" \
    --arg sha 45b93a0b3de27e46b636a0cef819fb1ecef25bcd --arg repo openclaw/homebrew-tap '{
      id:$id,workflow_id:220664022,path:".github/workflows/update-formula.yml",display_title:$title,
      event:"workflow_dispatch",head_branch:"main",head_sha:$sha,status:"completed",conclusion:"success",
      run_attempt:1,created_at:"2026-07-10T10:00:00Z",repository:{full_name:$repo},
      url:("https://api.github.com/repos/" + $repo + "/actions/runs/" + ($id | tostring)),
      html_url:("https://github.com/" + $repo + "/actions/runs/" + ($id | tostring))
    }' > "${hb_root}/run.json"
  jq -n --slurpfile run "${hb_root}/run.json" '{workflow_runs:$run}' > "${hb_root}/runs.json"
  jq -n '{workflow_run_id:29009690000}' > "${hb_state}/verifier-published.json"
  printf '0\n' > "${hb_root}/poll-count"
  printf '0\n' > "${hb_root}/contract-count"
  : > "${hb_root}/events"
}

run_homebrew_dispatch_fixture() {
  local hb_root="$1" hb_mode="$2"
  (
    export TMPDIR="${hb_root}/tmp"
    source_release
    preflight_repository() {
      default_branch=main
      default_sha="$SHA"
      protected_source_root="${hb_root}/protected"
    }
    verify_remote_tag() { tag_object="$TAG_OBJECT"; tag_commit="$TAG_COMMIT"; }
    init_release_state() { release_state_dir="${hb_root}/state"; }
    extract_release_notes() { printf '\n- Homebrew recovery fixture.\n' > "$3"; }
    verify_frozen_release() { /bin/cp "${hb_root}/published-source.json" "$4"; }
    load_frozen_release_id() { printf '777\n'; }
    require_verifier_state() { :; }
    run_release_verifier_check() { :; }
    recheck_source_default() { :; }
    download_release_copy() {
      local hb_name
      mkdir -p "$5"
      for hb_name in \
        goplaces_0.4.5_darwin_amd64.tar.gz goplaces_0.4.5_darwin_arm64.tar.gz \
        goplaces_0.4.5_linux_amd64.tar.gz goplaces_0.4.5_linux_arm64.tar.gz; do
        /bin/cp "${hb_root}/assets/${hb_name}" "$5/$hb_name"
      done
      /bin/cp "${hb_root}/published-source.json" "$5/release-record.json"
    }
    run_protected_script() { :; }
    compare_release_copies() { :; }
    recheck_tap_contract_for_homebrew_state() {
      local hb_call
      hb_call="$(cat "${hb_root}/contract-count")"
      hb_call=$((hb_call + 1))
      printf '%s\n' "$hb_call" > "${hb_root}/contract-count"
      tap_default_branch=main
      tap_workflow_id=220664022
      if ((hb_call == 1)) && [[ "$hb_mode" != direct-child && "$hb_mode" != unbound-child ]]; then
        tap_head=45b93a0b3de27e46b636a0cef819fb1ecef25bcd
      else
        tap_head=3333333333333333333333333333333333333333
      fi
    }
    homebrew_install_eligibility_preflight() {
      printf 'unexpected-install-preflight\n' >> "${hb_root}/events"
      return 91
    }
    fetch_workflow_runs() {
      local hb_call
      hb_call="$(cat "${hb_root}/poll-count")"
      hb_call=$((hb_call + 1))
      printf '%s\n' "$hb_call" > "${hb_root}/poll-count"
      case "$hb_mode" in
        delayed) if ((hb_call <= 2)); then printf '{"workflow_runs":[]}\n' > "$4"; else /bin/cp "${hb_root}/runs.json" "$4"; fi ;;
        persistent) printf '{"workflow_runs":[]}\n' > "$4" ;;
        direct|direct-child|unbound-child) /bin/cp "${hb_root}/runs.json" "$4" ;;
        *) return 92 ;;
      esac
    }
    get_run_with_retry() { /bin/cp "${hb_root}/run.json" "$3"; }
    gh_watch_run() { printf 'unexpected-watch\n' >> "${hb_root}/events"; return 93; }
    gh_api() {
      if [[ " $* " == *' --method POST '* ]]; then
        printf 'unexpected-post\n' >> "${hb_root}/events"
        return 94
      fi
      [[ "$1" == 'repos/openclaw/homebrew-tap/actions/runs/29010348667' ]] || return 95
      /bin/cat "${hb_root}/run.json"
    }
    verify_tap_commit_with_retry() {
      printf 'class Goplaces < Formula\nend\n' > "$1/goplaces-result.rb"
      printf '3333333333333333333333333333333333333333\n'
    }
    complete_homebrew_closeout() { printf 'closeout\n' >> "${hb_root}/events"; }
    sleep() { :; }
    run_homebrew v0.4.5
  )
}

test_homebrew_dispatch_recovery_state_machine() {
  local scratch
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-recovery.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" unbound
  run_homebrew_dispatch_fixture "$scratch" delayed
  ! grep -Fq unexpected-post "${scratch}/events" || die "delayed Homebrew recovery performed a duplicate POST"
  ! grep -Fq unexpected-install-preflight "${scratch}/events" || die "recovered Homebrew dispatch reran the fresh-install preflight"
  [[ "$(cat "${scratch}/poll-count")" == 4 ]] || die "Homebrew recovery did not poll through delayed visibility and newest-run proof"
  [[ "$(grep -c '^closeout$' "${scratch}/events")" == 1 ]] || die "delayed Homebrew recovery did not reach closeout"
  jq -e 'select(.workflow_run_id == 29010348667 and .recovered == true)' "${scratch}/state/homebrew-intent.json" >/dev/null ||
    die "delayed Homebrew recovery did not bind the adopted run"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-unbound-child.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" unbound
  run_homebrew_dispatch_fixture "$scratch" unbound-child
  ! grep -Fq unexpected-post "${scratch}/events" || die "unbound direct-child Homebrew recovery performed a duplicate POST"
  jq -e 'select(.workflow_run_id == 29010348667 and .recovered == true)' "${scratch}/state/homebrew-intent.json" >/dev/null ||
    die "unbound direct-child Homebrew recovery did not bind the landed run"
  jq -e 'select(.tap_result_head == "3333333333333333333333333333333333333333")' "${scratch}/state/homebrew-result.json" >/dev/null ||
    die "unbound direct-child Homebrew recovery did not freeze the landed Formula result"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-recovery.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" unbound
  if run_homebrew_dispatch_fixture "$scratch" persistent >/dev/null 2>&1; then
    die "persistently invisible Homebrew dispatch unexpectedly resumed"
  fi
  [[ "$(cat "${scratch}/poll-count")" == 15 ]] || die "Homebrew recovery did not exhaust its bounded reconciliation"
  ! grep -Fq unexpected-post "${scratch}/events" || die "exhausted Homebrew recovery performed a duplicate POST"
  [[ ! -e "${scratch}/state/homebrew-result.json" ]] || die "exhausted Homebrew recovery froze a false result"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-recovery.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" direct
  run_homebrew_dispatch_fixture "$scratch" direct
  ! grep -Fq unexpected-post "${scratch}/events" || die "direct-bound Homebrew restart performed a duplicate POST"
  [[ "$(cat "${scratch}/poll-count")" == 1 ]] || die "direct-bound Homebrew restart did not perform exactly one newest-run proof"
  jq -e 'select(.workflow_run_id == 29010348667 and .recovered == false)' "${scratch}/state/homebrew-intent.json" >/dev/null ||
    die "direct Homebrew binding lost its false recovery marker"
  [[ -f "${scratch}/state/homebrew-result.json" ]] || die "direct-bound Homebrew restart did not freeze its result"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-recovery.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" direct
  jq '.conclusion = "failure"' "${scratch}/run.json" > "${scratch}/run-failed.json"
  /bin/mv "${scratch}/run-failed.json" "${scratch}/run.json"
  if run_homebrew_dispatch_fixture "$scratch" direct > /dev/null 2> "${scratch}/failed-error"; then
    die "failed bound Homebrew run unexpectedly resumed"
  fi
  grep -Fq 'bound Homebrew workflow run completed without success; refusing a duplicate dispatch' "${scratch}/failed-error" ||
    die "failed bound Homebrew run failed outside the no-redispatch guard"
  ! grep -Fq unexpected-post "${scratch}/events" || die "failed bound Homebrew run performed a duplicate POST"
  [[ ! -e "${scratch}/state/homebrew-result.json" ]] || die "failed bound Homebrew run froze a false result"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-direct-child.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" direct
  printf 'class Goplaces < Formula\nend\n' > "${scratch}/preexisting-formula.rb"
  (
    source_release
    release_state_dir="${scratch}/state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    freeze_homebrew_result "${scratch}/state/homebrew-result.json" "${scratch}/state/homebrew-intent.json" \
      v0.4.5 777 "$(test_sha256 "${scratch}/published-source.json")" \
      "$(test_sha256 "${scratch}/assets/goplaces_0.4.5_darwin_amd64.tar.gz")" \
      "$(test_sha256 "${scratch}/assets/goplaces_0.4.5_darwin_arm64.tar.gz")" \
      "$(test_sha256 "${scratch}/assets/goplaces_0.4.5_linux_amd64.tar.gz")" \
      "$(test_sha256 "${scratch}/assets/goplaces_0.4.5_linux_arm64.tar.gz")" \
      3333333333333333333333333333333333333333 "${scratch}/preexisting-formula.rb"
  )
  printf '%s\n' "$(test_sha256 "${scratch}/state/homebrew-result.json")" > "${scratch}/result-before-sha"
  run_homebrew_dispatch_fixture "$scratch" direct-child
  [[ "$(test_sha256 "${scratch}/state/homebrew-result.json")" == "$(cat "${scratch}/result-before-sha")" ]] ||
    die "direct-child Homebrew resume replaced its frozen result"
  [[ "$(cat "${scratch}/contract-count")" == 2 ]] || die "direct-child Homebrew resume did not recheck both recovery and result contracts"
  ! grep -Fq unexpected-post "${scratch}/events" || die "direct-child Homebrew resume performed a duplicate POST"
  [[ "$(grep -c '^closeout$' "${scratch}/events")" == 1 ]] || die "direct-child Homebrew resume did not reach closeout"
  rm -rf "$scratch"
}

test_homebrew_install_resume_guards() {
  local scratch state formula binary second published release_sha asset_sha tap_head host_arch asset marker error
  local package_log post_marker install_log fixture_prefix fake_brew
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-install-state.XXXXXX")"
  prepare_homebrew_dispatch_fixture "$scratch" direct
  state="${scratch}/state"
  formula="${scratch}/verified-goplaces.rb"
  binary="${scratch}/goplaces"
  second="${scratch}/download-two"
  published="${scratch}/published-source.json"
  tap_head=3333333333333333333333333333333333333333
  printf 'class Goplaces < Formula\nend\n' > "$formula"
  printf 'verified installed binary\n' > "$binary"
  mkdir -p "$second"
  host_arch="$(/usr/bin/uname -m)"
  case "$host_arch" in
    arm64) asset=goplaces_0.4.5_darwin_arm64.tar.gz ;;
    x86_64) asset=goplaces_0.4.5_darwin_amd64.tar.gz ;;
    *) die "Homebrew install-state test requires native macOS" ;;
  esac
  /usr/bin/bsdtar -czf "${second}/${asset}" -C "$scratch" goplaces
  release_sha="$(test_sha256 "$published")"
  asset_sha="$(test_sha256 "$binary")"
  (
    export TMPDIR="${scratch}/tmp"
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    freeze_homebrew_result "${state}/homebrew-result.json" "${state}/homebrew-intent.json" v0.4.5 777 "$release_sha" \
      "$asset_sha" "$asset_sha" "$asset_sha" "$asset_sha" "$tap_head" "$formula"
    prepare_homebrew_install_intent "${state}/homebrew-install-intent.json" "${state}/homebrew-result.json" \
      v0.4.5 777 "$release_sha" "$tap_head" "$formula" "$host_arch" "$asset" "$binary"
    freeze_homebrew_install_started "${state}/homebrew-install-started.json" "${state}/homebrew-install-intent.json" \
      "${state}/homebrew-result.json" v0.4.5 777 "$release_sha" "$tap_head" "$formula" "$host_arch" "$asset" "$binary"
    freeze_homebrew_complete "${state}/homebrew-complete.json" "${state}/homebrew-install-started.json" \
      "${state}/homebrew-result.json" v0.4.5 777 "$release_sha" "$tap_head" "$formula"
  )
  marker="${scratch}/mutation-ran"
  error="${scratch}/complete-error"
  if (
    export TMPDIR="${scratch}/tmp"
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    need() { :; }
    prepare_tap_install_source() {
      mkdir -p "$1/Formula"
      /bin/cp "$3" "$1/Formula/goplaces.rb"
      printf '%s\n' "$1/Formula/goplaces.rb"
    }
    homebrew_goplaces_install_state() { printf 'absent\n'; }
    homebrew_goplaces_cask_state() { printf 'absent\n'; }
    homebrew_command() { touch "$marker"; return 96; }
    final_homebrew_recheck() { touch "$marker"; return 97; }
    complete_homebrew_closeout "${scratch}/install-work" v0.4.5 "$formula" "$second" "$tap_head" \
      "${scratch}/notes.md" "$published" 777 "$release_sha" "${state}/homebrew-result.json"
  ) >/dev/null 2> "$error"; then
    die "complete Homebrew state with an absent Formula unexpectedly succeeded"
  fi
  grep -Fq 'completed Homebrew proof no longer has an installed goplaces; refusing closeout mutation' "$error" ||
    die "complete Homebrew state failed outside the absent-Formula guard"
  [[ ! -e "$marker" ]] || die "complete Homebrew state reinstalled or performed a closeout mutation"

  /bin/rm -f "${state}/homebrew-complete.json"
  install_log="${scratch}/install-events"
  fixture_prefix="${scratch}/prefix"
  mkdir -p "${fixture_prefix}/bin"
  : > "$install_log"
  (
    export TMPDIR="${scratch}/tmp"
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    need() { :; }
    prepare_tap_install_source() {
      mkdir -p "$1/Formula"
      /bin/cp "$3" "$1/Formula/goplaces.rb"
      printf '%s\n' "$1/Formula/goplaces.rb"
    }
    homebrew_goplaces_install_state() { printf 'absent\n'; }
    homebrew_goplaces_cask_state() { printf 'absent\n'; }
    homebrew_command() {
      case "${1:-}" in
        install)
          [[ "${2:-}" == --formula && -f "${3:-}" ]] || return 80
          printf 'install\n' >> "$install_log"
          /bin/cp "$binary" "${fixture_prefix}/bin/goplaces"
          ;;
        --prefix)
          [[ "${2:-}" == --formula && "${3:-}" == goplaces ]] || return 81
          printf 'prefix\n' >> "$install_log"
          printf '%s\n' "$fixture_prefix"
          ;;
        test)
          [[ -f "${2:-}" ]] || return 82
          printf 'test\n' >> "$install_log"
          ;;
        *) return 83 ;;
      esac
    }
    run_protected_script() { :; }
    recheck_tap_install_source() { :; }
    final_homebrew_recheck() { printf 'recheck\n' >> "$install_log"; }
    complete_homebrew_closeout "${scratch}/retry-work" v0.4.5 "$formula" "$second" "$tap_head" \
      "${scratch}/notes.md" "$published" 777 "$release_sha" "${state}/homebrew-result.json"
  )
  [[ "$(grep -c '^install$' "$install_log")" == 1 ]] || die "install-started absent Formula did not retry exactly once"
  [[ "$(grep -c '^test$' "$install_log")" == 1 ]] || die "retried Homebrew install did not run the Formula test"
  [[ "$(grep -c '^recheck$' "$install_log")" == 2 ]] || die "retried Homebrew install did not recheck before mutation and closeout"
  [[ -f "${state}/homebrew-complete.json" ]] || die "retried Homebrew install did not freeze completion"

  /bin/rm -f "${state}/homebrew-complete.json"
  : > "$install_log"
  (
    export TMPDIR="${scratch}/tmp"
    source_release
    release_state_dir="$state"
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    need() { :; }
    prepare_tap_install_source() {
      mkdir -p "$1/Formula"
      /bin/cp "$3" "$1/Formula/goplaces.rb"
      printf '%s\n' "$1/Formula/goplaces.rb"
    }
    homebrew_goplaces_install_state() { printf 'present\n'; }
    homebrew_goplaces_cask_state() { printf 'absent\n'; }
    homebrew_command() {
      case "${1:-}" in
        install) touch "$marker"; return 84 ;;
        --prefix)
          [[ "${2:-}" == --formula && "${3:-}" == goplaces ]] || return 85
          printf 'prefix\n' >> "$install_log"
          printf '%s\n' "$fixture_prefix"
          ;;
        test)
          [[ -f "${2:-}" ]] || return 86
          printf 'test\n' >> "$install_log"
          ;;
        *) return 87 ;;
      esac
    }
    run_protected_script() { :; }
    recheck_tap_install_source() { :; }
    final_homebrew_recheck() { :; }
    complete_homebrew_closeout "${scratch}/present-work" v0.4.5 "$formula" "$second" "$tap_head" \
      "${scratch}/notes.md" "$published" 777 "$release_sha" "${state}/homebrew-result.json"
  )
  [[ ! -e "$marker" ]] || die "install-started present Formula was reinstalled"
  [[ "$(grep -c '^prefix$' "$install_log")" == 1 && "$(grep -c '^test$' "$install_log")" == 1 ]] ||
    die "install-started present Formula did not resume verification and test"
  [[ -f "${state}/homebrew-complete.json" ]] || die "present Formula resume did not freeze completion"
  rm -rf "$scratch"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-cask-state.XXXXXX")"
  package_log="${scratch}/packages"
  post_marker="${scratch}/post"
  fake_brew="${scratch}/brew"
  cat > "$fake_brew" <<'EOF'
#!/bin/bash -p
set -euo pipefail
fixture_root="$(cd "$(dirname "$0")" && pwd -P)"
[[ "${HOMEBREW_NO_INSTALL_FROM_API:-}" == 1 && "${HOMEBREW_NO_AUTO_UPDATE:-}" == 1 &&
   "${HOMEBREW_NO_ANALYTICS:-}" == 1 && "${HOMEBREW_NO_INSTALL_CLEANUP:-}" == 1 ]] || exit 90
printf 'env-ok:%s\n' "$*" >> "${fixture_root}/packages"
case "$*" in
  'list --formula --full-name') : ;;
  'list --cask --full-name') printf 'openclaw/tap/goplaces\n' ;;
  *) exit 91 ;;
esac
EOF
  chmod +x "$fake_brew"
  if (
    source_release
    need() { :; }
    gh_api() { touch "$post_marker"; return 98; }
    brew_binary="$fake_brew"
    freeze_homebrew_transport() { :; }
    recheck_homebrew_runtime() { :; }
    homebrew_install_eligibility_preflight
  ) >/dev/null 2>&1; then
    die "present legacy goplaces Cask passed the pre-dispatch blocker"
  fi
  [[ "$(cat "$package_log")" == $'env-ok:list --formula --full-name\nenv-ok:list --cask --full-name' ]] ||
    die "Homebrew eligibility did not use the isolated formula- and Cask-specific inventories"
  [[ ! -e "$post_marker" ]] || die "Cask-present blocker reached a dispatch or unexpected Homebrew command"
  rm -rf "$scratch"
}

test_homebrew_state_tamper_fails_closed() {
  local scratch state error target release_sha asset_sha
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-state-tamper.XXXXXX")"
  state="${scratch}/orphan"
  mkdir -p "$state"
  printf '{}\n' > "${state}/homebrew-result.json"
  error="${scratch}/orphan-error"
  if (
    source_release
    release_state_dir="$state"
    validate_homebrew_phase_order "${state}/homebrew-intent.json" "${state}/homebrew-result.json"
  ) >/dev/null 2> "$error"; then
    die "orphaned Homebrew result unexpectedly passed phase validation"
  fi
  grep -Fq 'orphaned Homebrew state exists without its dispatch intent' "$error" ||
    die "orphaned Homebrew result failed outside the phase-order guard"

  state="${scratch}/symlink"
  mkdir -p "$state"
  target="${scratch}/intent-target"
  printf '{}\n' > "$target"
  ln -s "$target" "${state}/homebrew-intent.json"
  error="${scratch}/symlink-error"
  if (
    source_release
    release_state_dir="$state"
    validate_homebrew_phase_order "${state}/homebrew-intent.json" "${state}/homebrew-result.json"
  ) >/dev/null 2> "$error"; then
    die "symlinked Homebrew intent unexpectedly passed phase validation"
  fi
  grep -Fq 'required regular file is missing or a symlink' "$error" ||
    die "symlinked Homebrew intent failed outside the regular-file guard"

  state="${scratch}/mode"
  prepare_homebrew_dispatch_fixture "${scratch}/mode-fixture" unbound
  state="${scratch}/mode-fixture/state"
  chmod 600 "${state}/homebrew-intent.json"
  release_sha="$(test_sha256 "${scratch}/mode-fixture/published-source.json")"
  asset_sha="$(test_sha256 "${scratch}/mode-fixture/assets/goplaces_0.4.5_darwin_amd64.tar.gz")"
  error="${scratch}/mode-error"
  if (
    source_release
    default_sha="$SHA"
    tag_object="$TAG_OBJECT"
    tag_commit="$TAG_COMMIT"
    validate_homebrew_intent "${state}/homebrew-intent.json" v0.4.5 777 "$release_sha" \
      "$asset_sha" "$asset_sha" "$asset_sha" "$asset_sha"
  ) >/dev/null 2> "$error"; then
    die "wrong-mode Homebrew intent unexpectedly passed validation"
  fi
  grep -Fq 'Homebrew intent permissions changed' "$error" ||
    die "wrong-mode Homebrew intent failed outside the permission guard"
  rm -rf "$scratch"
}

test_homebrew_blocker_precedes_dispatch() {
  local scratch mock_bin log workflow_content updater_content compare_control
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-homebrew-blocker-test.XXXXXX")"
  mock_bin="${scratch}/bin"
  log="${scratch}/gh.log"
  mkdir -p "$mock_bin" "${scratch}/work"
  workflow_content="$(printf 'name: update-formula\n' | base64 | tr -d '\n')"
  updater_content="$(printf '# verified-hashes-v1\n' | base64 | tr -d '\n')"
  cat > "${mock_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_BLOCKER_LOG"
endpoint=""
for arg in "$@"; do case "$arg" in repos/*) endpoint="$arg" ;; esac; done
case "$endpoint" in
  repos/openclaw/homebrew-tap) printf '{"default_branch":"main"}\n' ;;
  repos/openclaw/homebrew-tap/branches/main) printf '{"name":"main","protected":%s,"commit":{"sha":"%s"}}\n' "${TAP_PROTECTED:-true}" "${TAP_HEAD:-45b93a0b3de27e46b636a0cef819fb1ecef25bcd}" ;;
  repos/openclaw/homebrew-tap/compare/45b93a0b3de27e46b636a0cef819fb1ecef25bcd...45b93a0b3de27e46b636a0cef819fb1ecef25bcd)
    printf '{"status":"%s","base_commit":{"sha":"%s"},"merge_base_commit":{"sha":"%s"},"head_commit":{"sha":"%s"}}\n' "${TAP_COMPARE_STATUS:-identical}" "${TAP_COMPARE_BASE:-$TAP_BASE}" "${TAP_COMPARE_MERGE_BASE:-$TAP_BASE}" "${TAP_COMPARE_HEAD:-$TAP_BASE}"
    ;;
  repos/openclaw/homebrew-tap/contents/.github/workflows/update-formula.yml*)
    printf '{"path":".github/workflows/update-formula.yml","type":"file","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","encoding":"base64","content":"%s"}\n' "$WORKFLOW_CONTENT"
    ;;
  repos/openclaw/homebrew-tap/contents/.github/scripts/update_formula.py*)
    printf '{"path":".github/scripts/update_formula.py","type":"file","sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","encoding":"base64","content":"%s"}\n' "$UPDATER_CONTENT"
    ;;
  repos/openclaw/homebrew-tap/contents/Formula/goplaces.rb*) exit 44 ;;
  *) echo "unexpected endpoint: $endpoint" >&2; exit 90 ;;
esac
EOF
  chmod +x "${mock_bin}/gh"
  export MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    export GH_BLOCKER_LOG="$log" TAP_BASE="45b93a0b3de27e46b636a0cef819fb1ecef25bcd" WORKFLOW_CONTENT="$workflow_content" UPDATER_CONTENT="$updater_content"
    PATH="${mock_bin}:$PATH"
    export PATH
    # shellcheck source=release-local
    source "$release_script"
    tap_trust_preflight "${scratch}/work"
  ) >/dev/null 2>&1; then
    die "missing Formula/goplaces.rb did not block Homebrew"
  fi
  if grep -Fq '/dispatches' "$log"; then
    die "Homebrew blocker was checked after dispatch"
  fi
  : > "$log"
  mkdir -p "${scratch}/work-moved"
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    export GH_BLOCKER_LOG="$log" TAP_BASE="45b93a0b3de27e46b636a0cef819fb1ecef25bcd" TAP_HEAD="3333333333333333333333333333333333333333" WORKFLOW_CONTENT="$workflow_content" UPDATER_CONTENT="$updater_content"
    PATH="${mock_bin}:$PATH"
    export PATH
    source "$release_script"
    tap_trust_preflight "${scratch}/work-moved"
  ) >/dev/null 2>&1; then
    die "unpinned tap head unexpectedly reached Homebrew handoff"
  fi
  grep -Fq 'repos/openclaw/homebrew-tap/branches/main' "$log" || die "moved tap head regression did not reach the protected branch record"
  if grep -Fq '/compare/' "$log"; then
    die "moved tap head was trusted before exact-base rejection"
  fi
  : > "$log"
  mkdir -p "${scratch}/work-unprotected"
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    export GH_BLOCKER_LOG="$log" TAP_BASE="45b93a0b3de27e46b636a0cef819fb1ecef25bcd" TAP_PROTECTED=false WORKFLOW_CONTENT="$workflow_content" UPDATER_CONTENT="$updater_content"
    PATH="${mock_bin}:$PATH"
    export PATH
    source "$release_script"
    tap_trust_preflight "${scratch}/work-unprotected"
  ) >/dev/null 2>&1; then
    die "unprotected pinned tap head unexpectedly reached Homebrew handoff"
  fi
  if grep -Fq '/compare/' "$log"; then
    die "unprotected tap head was trusted before protection rejection"
  fi
  : > "$log"
  mkdir -p "${scratch}/work-bad-compare"
  if (
    export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
    export GH_BLOCKER_LOG="$log" TAP_BASE="45b93a0b3de27e46b636a0cef819fb1ecef25bcd" TAP_COMPARE_STATUS=ahead WORKFLOW_CONTENT="$workflow_content" UPDATER_CONTENT="$updater_content"
    PATH="${mock_bin}:$PATH"
    export PATH
    source "$release_script"
    tap_trust_preflight "${scratch}/work-bad-compare"
  ) >/dev/null 2>&1; then
    die "hostile tap base comparison unexpectedly reached Homebrew handoff"
  fi
  grep -Fq '/compare/' "$log" || die "hostile tap comparison regression did not reach the compare record"
  if grep -Fq '/contents/' "$log"; then
    die "hostile tap comparison was accepted before content trust"
  fi
  for compare_control in TAP_COMPARE_BASE TAP_COMPARE_MERGE_BASE TAP_COMPARE_HEAD; do
    : > "$log"
    mkdir -p "${scratch}/work-${compare_control}"
    export "$compare_control=3333333333333333333333333333333333333333"
    if (
      export GOPLACES_RELEASE_LOCAL_TESTING=1 GOPLACES_RELEASE_LOCAL_SOURCE_ONLY=1
      export GH_BLOCKER_LOG="$log" TAP_BASE="45b93a0b3de27e46b636a0cef819fb1ecef25bcd" WORKFLOW_CONTENT="$workflow_content" UPDATER_CONTENT="$updater_content"
      PATH="${mock_bin}:$PATH"
      export PATH
      source "$release_script"
      tap_trust_preflight "${scratch}/work-${compare_control}"
    ) >/dev/null 2>&1; then
      die "hostile $compare_control tap comparison unexpectedly reached content trust"
    fi
    unset "$compare_control"
    grep -Fq '/compare/' "$log" || die "$compare_control regression did not reach the compare record"
    ! grep -Fq '/contents/' "$log" || die "$compare_control mismatch was accepted before content trust"
  done
  unset MOCK_FIXTURE_ROOT GOPLACES_RELEASE_LOCAL_TEST_GH_BIN
  rm -rf "$scratch"
}

test_tap_cask_inventory_fails_closed() {
  local scratch mock_bin hostile_content
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-cask-inventory.XXXXXX")"
  mock_bin="${scratch}/bin"
  mkdir -p "$mock_bin" "${scratch}/work"
  hostile_content="$(printf 'system "xattr", "-d", "com.apple.quarantine"\n' | base64 | tr -d '\n')"
  cat > "${mock_bin}/gh" <<'EOF'
#!/bin/bash -p
set -euo pipefail
endpoint=""
for arg in "$@"; do case "$arg" in repos/*) endpoint="$arg" ;; esac; done
case "$endpoint" in
  repos/openclaw/homebrew-tap/git/trees/*)
    case "${TREE_MODE:-error}" in
      error) exit 44 ;;
      absent) printf '{"truncated":false,"tree":[]}\n' ;;
      hostile) printf '{"truncated":false,"tree":[{"path":"Casks/goplaces.rb","type":"blob"}]}\n' ;;
      truncated) printf '{"truncated":true,"tree":[]}\n' ;;
    esac
    ;;
  repos/openclaw/homebrew-tap/contents/Casks/goplaces.rb*)
    printf '{"path":"Casks/goplaces.rb","type":"file","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","encoding":"base64","content":"%s"}\n' "$HOSTILE_CONTENT"
    ;;
  *) exit 90 ;;
esac
EOF
  chmod +x "${mock_bin}/gh"
  export MOCK_FIXTURE_ROOT="$scratch" GOPLACES_RELEASE_LOCAL_TEST_GH_BIN="${mock_bin}/gh"
  if (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH TREE_MODE=error HOSTILE_CONTENT="$hostile_content"
    verify_tap_cask_quarantine "$SHA" "${scratch}/work/error"
  ) >/dev/null 2>&1; then
    die "tap Cask API error was treated as absence"
  fi
  (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH TREE_MODE=absent HOSTILE_CONTENT="$hostile_content"
    verify_tap_cask_quarantine "$SHA" "${scratch}/work/absent"
  )
  if (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH TREE_MODE=truncated HOSTILE_CONTENT="$hostile_content"
    verify_tap_cask_quarantine "$SHA" "${scratch}/work/truncated"
  ) >/dev/null 2>&1; then
    die "truncated tap tree inventory was accepted"
  fi
  if (
    source_release
    PATH="${mock_bin}:$PATH"
    export PATH TREE_MODE=hostile HOSTILE_CONTENT="$hostile_content"
    verify_tap_cask_quarantine "$SHA" "${scratch}/work/hostile"
  ) >/dev/null 2>&1; then
    die "quarantine-stripping tap Cask was accepted"
  fi
  unset MOCK_FIXTURE_ROOT GOPLACES_RELEASE_LOCAL_TEST_GH_BIN
  rm -rf "$scratch"
}

main() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v shellcheck >/dev/null 2>&1 || die "shellcheck is required"
  test_static_contract
  test_govulncheck_build_info_validation
  test_jq_freeze_survives_command_substitution
  test_run_shape
  test_workflow_record_uses_filename_lookup
  test_dispatch_response_binding
  test_verifier_dispatch_recovers_without_duplicate_post
  test_newest_selection_fails_closed
  test_paginated_run_inventory
  test_release_record_freeze
  test_draft_intent_is_crash_resumable
  test_publish_is_resumable
  test_formula_pairs_and_tap_commit_record
  test_trusted_ancestry_rejects_graph_overrides
  test_post_manifest_source_recheck
  test_production_git_is_pinned
  test_producer_gate_hardening
  test_signature_program_is_pinned
  test_tag_identity_is_frozen
  test_gh_transport_is_pinned
  test_preflight_and_pilot_mocks
  test_codesign_wrapper_scopes_auth_and_startup_env
  test_draft_canonicalizes_tmpdir_paths
  test_reproducer_uses_frozen_module_cache
  test_protected_helper_environment_is_allowlisted
  test_final_tap_check_is_last_external_closeout
  test_pre_dispatch_tap_recheck_is_exact_base
  test_tap_install_uses_fresh_exact_checkout
  test_homebrew_reproves_after_package_test
  test_homebrew_dispatch_recovery_state_machine
  test_homebrew_install_resume_guards
  test_homebrew_state_tamper_fails_closed
  test_homebrew_blocker_precedes_dispatch
  test_tap_cask_inventory_fails_closed
  shellcheck "$release_script" "${repo_root}/scripts/recheck-release-source.sh" "$0"
  echo "release-local test: mocked gates, records, dispatches, publication, and Homebrew blocker passed"
}

main "$@"
