#!/bin/bash
set -euo pipefail

iphomarchy_script_dir=$(cd "$(dirname "$0")" && pwd)
iphomarchy_parts_dir=$iphomarchy_script_dir
if [[ ! -f "$iphomarchy_parts_dir/iPhomarchy.utm.zip.part-001" && -f "$iphomarchy_script_dir/../iPhomarchy.utm.zip.part-001" ]]; then
  iphomarchy_parts_dir=$(cd "$iphomarchy_script_dir/.." && pwd)
fi
iphomarchy_output="$iphomarchy_parts_dir/iPhomarchy.utm.zip"
iphomarchy_expected=966b4a2557a2c024b02e7819c082f6ad6689b44cbc4e3fbbdaaee1510307ca73
iphomarchy_expected_bytes=3908445304
iphomarchy_parts=()
for iphomarchy_suffix in 001 002 003 004 005 006 007 008 009; do
  iphomarchy_part="$iphomarchy_parts_dir/iPhomarchy.utm.zip.part-$iphomarchy_suffix"
  [[ -f "$iphomarchy_part" ]] || { echo "Missing download: ${iphomarchy_part##*/}. Keep all nine parts together." >&2; exit 1; }
  iphomarchy_parts+=("$iphomarchy_part")
done
if command -v shasum >/dev/null 2>&1; then
  iphomarchy_hash_command=(shasum -a 256)
else
  iphomarchy_hash_command=(sha256sum)
fi
iphomarchy_hash() { "${iphomarchy_hash_command[@]}" "$1" | awk '{print $1}'; }

if [[ -e "$iphomarchy_output" ]]; then
  [[ -f "$iphomarchy_output" && $(iphomarchy_hash "$iphomarchy_output") == "$iphomarchy_expected" ]] || {
    echo "An existing iPhomarchy.utm.zip has different contents. Move it before assembling." >&2; exit 1;
  }
  echo "The complete, verified VM ZIP already exists: $iphomarchy_output"
  exit 0
fi

if [[ -f "$iphomarchy_script_dir/iPhomarchy-parts.sha256" ]]; then
  echo 'Checking the nine downloads…'
  (cd "$iphomarchy_parts_dir" && "${iphomarchy_hash_command[@]}" -c "$iphomarchy_script_dir/iPhomarchy-parts.sha256")
fi
iphomarchy_partial="$iphomarchy_output.partial"
[[ ! -e "$iphomarchy_partial" ]] || { echo 'A previous partial assembly exists. Remove iPhomarchy.utm.zip.partial, then retry.' >&2; exit 1; }
trap 'rm -f "$iphomarchy_partial"' EXIT

echo 'Assembling iPhomarchy (about 3.9 GB)…'
cat "${iphomarchy_parts[@]}" > "$iphomarchy_partial"
[[ $(wc -c < "$iphomarchy_partial" | tr -d ' ') == "$iphomarchy_expected_bytes" ]] || { echo 'Assembled size is incorrect.' >&2; exit 1; }
[[ $(iphomarchy_hash "$iphomarchy_partial") == "$iphomarchy_expected" ]] || { echo 'Assembled checksum failed.' >&2; exit 1; }
mv "$iphomarchy_partial" "$iphomarchy_output"
trap - EXIT

echo "Ready: $iphomarchy_output"
echo 'Transfer this single ZIP to your iPhone, extract it and import the .utm bundle into UTM with JIT.'
if [[ $(uname -s) == Darwin ]]; then
  open -R "$iphomarchy_output"
fi
