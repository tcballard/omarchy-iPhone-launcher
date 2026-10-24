#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
utm=$(cd "$1" && pwd)
stage="$root/.build/integrated-dependencies"
mkdir -p "$stage"
node - "$root/ios/integrated-dependencies.json" "$stage" <<'JS'
const fs = require('node:fs/promises');
const crypto = require('node:crypto');
(async () => {
  const lock = JSON.parse(await fs.readFile(process.argv[2], 'utf8'));
  const response = await fetch(lock.stikJIT.url);
  if (!response.ok) throw new Error(`StikJIT download failed: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (crypto.createHash('sha256').update(bytes).digest('hex') !== lock.stikJIT.sha256)
    throw new Error('StikJIT checksum mismatch');
  await fs.writeFile(`${process.argv[3]}/StikJIT.zip`, bytes);
})().catch(error => { console.error(error.message); process.exitCode = 1; });
JS
unzip -q -o "$stage/StikJIT.zip" -d "$stage"
export CARGO_TARGET_DIR="$root/.build/pairing-target"
export IPHONEOS_DEPLOYMENT_TARGET=26.0
cargo +1.98.1 build --locked --release --target aarch64-apple-ios --manifest-path "$root/ios/Pairing/Cargo.toml"
mkdir -p "$utm/Omarchy/Dependencies"
cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libomarchy_pairing.a" "$utm/Omarchy/Dependencies/"
cp -R "$stage/StikJIT.xcframework/ios-arm64/StikJIT.framework" "$utm/Omarchy/Dependencies/"
python3 "$root/ios/scripts/pairing-notices.py" "$utm/Omarchy/Notices/PairingDependencies"
ruby "$root/ios/scripts/integrate-project.rb" "$utm"
