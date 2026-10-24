"""Complete StikJIT's framework bundle without changing its code or scripts."""
import json
from pathlib import Path
import plistlib
import shutil
import struct
import sys

root = Path(__file__).resolve().parents[2]
app = Path(sys.argv[1]).resolve()
framework = app / 'Extensions/OmarchyJITHelper.appex/Frameworks/StikJIT.framework'
binary = framework / 'StikJIT'
assert binary.is_file(), 'The bundled JIT framework is missing'
code = binary.read_bytes()
assert code[:4] == b'\xcf\xfa\xed\xfe', 'Expected an ARM64 Mach-O framework'
offset = 32
minimum = None
for _ in range(struct.unpack_from('<I', code, 16)[0]):
    command, size = struct.unpack_from('<II', code, offset)
    assert size >= 8 and offset + size <= len(code), 'Invalid Mach-O command'
    if command == 0x32:
        platform, version = struct.unpack_from('<II', code, offset + 8)
        assert platform == 2, 'Expected an iOS framework'
        minimum = '.'.join(str(value) for value in [version >> 16, (version >> 8) & 255, version & 255])
    offset += size
assert minimum is not None, 'Framework deployment target is missing'
for script in ['legacy.js', 'universal.js']:
    assert (framework / script).is_file(), 'Framework script is missing: ' + script
info_path = framework / 'Info.plist'
if not info_path.exists():
    main_info = plistlib.loads((app / 'Info.plist').read_bytes())
    version = json.loads((root / 'ios/integrated-dependencies.json').read_text())['stikJIT']['version']
    info = {
        'CFBundleDevelopmentRegion': 'en', 'CFBundleExecutable': 'StikJIT',
        'CFBundleIdentifier': main_info['CFBundleIdentifier'] + '.StikJIT',
        'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': 'StikJIT',
        'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': version,
        'CFBundleVersion': version, 'CFBundleSupportedPlatforms': ['iPhoneOS'],
        'MinimumOSVersion': minimum,
    }
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    print('Added StikJIT framework metadata; minimum iOS ' + minimum + '.')
else:
    info = plistlib.loads(info_path.read_bytes())
    assert info['CFBundleExecutable'] == 'StikJIT' and info['CFBundlePackageType'] == 'FMWK'
notices = app / 'Notices'
notices.mkdir(exist_ok=True)
for filename in ['README.txt', 'StikJIT-bundle-metadata.txt']:
    shutil.copyfile(root / 'ios/Notices' / filename, notices / filename)
assert binary.read_bytes() == code, 'Metadata completion changed library code'
