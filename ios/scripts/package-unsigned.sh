#!/bin/bash
set -euo pipefail
archive=$(cd "$1" && pwd)
output=$2
if [[ -e "$output/iPhomarchy-unsigned.ipa" ]]; then
    echo 'Output already exists; choose an empty output directory.' >&2
    exit 1
fi
mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/Payload"
ditto "$archive/Products/Applications/UTM.app" "$work/Payload/iPhomarchy.app"
cd "$work"
zip -qry "$output/iPhomarchy-unsigned.ipa" Payload
echo 'Created unsigned IPA. Development signing is required before installation.'
