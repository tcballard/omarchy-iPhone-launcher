"""Collect notices from the exact Cargo.lock resolution; no signing material is read."""
import json
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
output = pathlib.Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
metadata = json.loads(subprocess.check_output([
    "cargo", "+1.98.1", "metadata", "--locked", "--format-version", "1",
    "--manifest-path", str(root / "ios/Pairing/Cargo.toml"),
]))
inventory = []
for package in metadata["packages"]:
    if package["source"] is None:
        continue
    source = pathlib.Path(package["manifest_path"]).parent
    destination = output / (package["name"] + "-" + package["version"])
    destination.mkdir(exist_ok=True)
    files = sorted(set(path for pattern in ("LICENSE*", "LICENCE*", "COPYING*", "NOTICE*")
                       for path in source.glob(pattern) if path.is_file()))
    for path in files:
        shutil.copyfile(path, destination / path.name)
    if package.get("license_file"):
        path = source / package["license_file"]
        if path.is_file():
            shutil.copyfile(path, destination / path.name)
    inventory.append({key: package.get(key) for key in ("name", "version", "license", "repository", "source")})
(output / "sources.json").write_text(json.dumps(inventory, indent=2) + "\n")
print(f"Collected license notices for {len(inventory)} locked Rust crates.")
