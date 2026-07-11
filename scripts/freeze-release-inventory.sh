#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

die() {
  echo "release inventory freeze: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 ASSET_DIR TAG [OUT_JSON]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage

asset_dir="${1%/}"
tag="$2"
out_json="${3:-}"
jq_bin="${JQ_BIN:-jq}"

for token_name in GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN HOMEBREW_TAP_GITHUB_TOKEN; do
  if declare -p "$token_name" >/dev/null 2>&1; then
    die "$token_name must be absent while freezing inventory"
  fi
done

[[ -d "$asset_dir" && ! -L "$asset_dir" ]] || die "asset directory must be a real directory"
asset_dir="$(cd "$asset_dir" && pwd -P)"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] || die "invalid tag"
command -v "$jq_bin" >/dev/null 2>&1 || die "jq is required"
[[ -x /usr/bin/unzip ]] || die "system unzip is required"
[[ -x /usr/bin/tar ]] || die "system tar is required"
[[ -x /usr/bin/shasum ]] || die "system shasum is required"

if find "$asset_dir" -mindepth 1 -type l -print -quit | grep -q .; then
  die "asset directory contains a symlink"
fi
if find "$asset_dir" -mindepth 1 -maxdepth 1 ! -type f -print -quit | grep -q .; then
  die "asset directory contains a non-file entry"
fi
[[ "$(find "$asset_dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d '[:space:]')" -eq 8 ]] || die "asset directory must contain seven assets plus release-record.json"

record="$asset_dir/release-record.json"
[[ -f "$record" && ! -L "$record" ]] || die "release record is missing"
version="${tag#v}"
expected_names="$($jq_bin -cn --arg version "$version" '[
  "goplaces_\($version)_darwin_amd64.tar.gz",
  "goplaces_\($version)_darwin_arm64.tar.gz",
  "goplaces_\($version)_linux_amd64.tar.gz",
  "goplaces_\($version)_linux_arm64.tar.gz",
  "goplaces_\($version)_windows_amd64.zip",
  "goplaces_\($version)_windows_arm64.zip",
  "goplaces_checksums.txt"
] | sort')"

"$jq_bin" -e --arg tag "$tag" --argjson expected "$expected_names" '
  .schema == "goplaces-release-record-v1" and
  .repository == "openclaw/goplaces" and
  .tag_name == $tag and
  (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
  (.assets | type == "array" and length == 7) and
  ([.assets[].name] | sort == $expected) and
  (([.assets[].id] | unique | length) == 7) and
  (all(.assets[];
    (.id | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
    (.size | type == "number" and . > 0 and . <= 9007199254740991 and floor == .) and
    (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$"))
  ))
' "$record" >/dev/null || die "release record inventory is invalid"

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

while IFS=$'\t' read -r name size digest; do
  path="$asset_dir/$name"
  [[ -f "$path" && ! -L "$path" ]] || die "missing regular asset: $name"
  actual_size="$(wc -c < "$path" | tr -d '[:space:]')"
  [[ "$actual_size" == "$size" ]] || die "asset size does not match frozen record: $name"
  [[ "sha256:$(sha256_file "$path")" == "$digest" ]] || die "asset digest does not match frozen record: $name"
done < <("$jq_bin" -r '.assets[] | [.name,.size,.digest] | @tsv' "$record")

checksums="$asset_dir/goplaces_checksums.txt"
[[ -f "$checksums" && ! -L "$checksums" ]] || die "checksum manifest is missing"
if LC_ALL=C grep -q $'\r' "$checksums"; then
  die "checksum manifest contains carriage returns"
fi
checksum_json="$(awk '
  NF != 2 || $1 !~ /^[0-9a-f]{64}$/ || $2 ~ /^\*/ {exit 2}
  {print $1 "\t" $2}
' "$checksums" | "$jq_bin" -Rn '[inputs | split("\t") | {digest:.[0],name:.[1]}]')" || die "checksum manifest format is invalid"
expected_archives="$($jq_bin -cn --argjson all "$expected_names" '$all | map(select(. != "goplaces_checksums.txt")) | sort')"
"$jq_bin" -e --argjson expected "$expected_archives" 'length == 6 and ([.[].name] | sort == $expected) and (([.[].name] | unique | length) == 6)' <<<"$checksum_json" >/dev/null || die "checksum manifest names are not exact"
while IFS=$'\t' read -r digest name; do
  [[ "$name" != */* && "$name" != .* ]] || die "unsafe checksum filename"
  [[ "$(sha256_file "$asset_dir/$name")" == "$digest" ]] || die "checksum manifest does not match archive: $name"
done < <("$jq_bin" -r '.[] | [.digest,.name] | @tsv' <<<"$checksum_json")

scratch="$(mktemp -d "${TMPDIR:-/tmp}/goplaces-inventory.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
members="$scratch/members.jsonl"
: > "$members"

for os in darwin linux windows; do
  for arch in amd64 arm64; do
    if [[ "$os" == windows ]]; then
      archive="goplaces_${version}_${os}_${arch}.zip"
      member_name="goplaces.exe"
      listing="$scratch/listing"
      /usr/bin/unzip -Z1 "$asset_dir/$archive" > "$listing" || die "could not list $archive"
      [[ "$(wc -l < "$listing" | tr -d '[:space:]')" -eq 1 && "$(cat "$listing")" == "$member_name" ]] || die "$archive must contain only $member_name"
      /usr/bin/unzip -p "$asset_dir/$archive" "$member_name" > "$scratch/member" || die "could not read $member_name from $archive"
    else
      archive="goplaces_${version}_${os}_${arch}.tar.gz"
      member_name="goplaces"
      listing="$scratch/listing"
      /usr/bin/tar -tzf "$asset_dir/$archive" > "$listing" || die "could not list $archive"
      [[ "$(wc -l < "$listing" | tr -d '[:space:]')" -eq 1 && "$(cat "$listing")" == "$member_name" ]] || die "$archive must contain only $member_name"
      /usr/bin/tar -xOzf "$asset_dir/$archive" "$member_name" > "$scratch/member" || die "could not read $member_name from $archive"
    fi
    [[ -s "$scratch/member" ]] || die "archive member is empty: $archive"
    "$jq_bin" -cn \
      --arg archive "$archive" \
      --arg os "$os" \
      --arg arch "$arch" \
      --arg member "$member_name" \
      --arg digest "sha256:$(sha256_file "$scratch/member")" \
      --argjson size "$(wc -c < "$scratch/member" | tr -d '[:space:]')" \
      '{archive:$archive,os:$os,arch:$arch,member:$member,member_size:$size,member_digest:$digest}' >> "$members"
  done
done

record_digest="sha256:$(sha256_file "$record")"
checksum_digest="sha256:$(sha256_file "$checksums")"
inventory="$scratch/release-inventory.json"
"$jq_bin" -nS \
  --arg tag "$tag" \
  --arg record_digest "$record_digest" \
  --arg checksum_digest "$checksum_digest" \
  --slurpfile record "$record" \
  --slurpfile members "$members" '
    {
      schema:"goplaces-release-inventory-v1",
      tag:$tag,
      release_id:$record[0].id,
      state:$record[0].state,
      release_record_digest:$record_digest,
      checksum_digest:$checksum_digest,
      assets:$record[0].assets,
      members:($members | sort_by(.archive))
    }
  ' > "$inventory"

if [[ -n "$out_json" ]]; then
  [[ ! -e "$out_json" && ! -L "$out_json" ]] || die "inventory output already exists"
  out_parent="$(dirname "$out_json")"
  [[ -d "$out_parent" && ! -L "$out_parent" ]] || die "inventory output parent must be a real directory"
  tmp_out="$(mktemp "$out_parent/.goplaces-inventory.XXXXXX")"
  cp "$inventory" "$tmp_out"
  chmod 0444 "$tmp_out"
  mv "$tmp_out" "$out_json"
  printf '%s\n' "$out_json"
else
  cat "$inventory"
fi
