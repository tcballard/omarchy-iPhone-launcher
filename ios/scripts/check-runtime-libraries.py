"""Reject build-machine dependencies and unresolved bundled Mach-O libraries."""
from pathlib import Path
import plistlib
import struct
import sys

LOADS = {0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x20, 0x23 | 0x80000000}

def commands(path):
    data = path.read_bytes()
    if data[:4] != b'\xcf\xfa\xed\xfe':
        return None
    offset = 32
    libraries, rpaths = [], []
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, offset)
        assert size >= 8 and offset + size <= len(data), f'Invalid Mach-O: {path}'
        if command in LOADS or command == 0x8000001C:
            start = struct.unpack_from('<I', data, offset + 8)[0]
            assert 12 <= start < size, f'Invalid library name: {path}'
            name = data[offset + start:offset + size].split(b'\0', 1)[0].decode()
            (rpaths if command == 0x8000001C else libraries).append(name)
        offset += size
    return libraries, rpaths

def check(app):
    bundles = [app, *app.glob('Extensions/*.appex'), *app.glob('PlugIns/*.appex')]
    executables = {}
    for bundle in bundles:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        executable = bundle / info['CFBundleExecutable']
        executables[bundle] = (executable, commands(executable)[1])
    count = 0
    for path in app.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        parsed = commands(path)
        if parsed is None:
            continue
        libraries, own_rpaths = parsed
        assert len(libraries) == len(set(libraries)), f'{path.relative_to(app)}: duplicate linked library'
        owner = next(parent for parent in path.parents if parent in executables)
        executable, host_rpaths = executables[owner]
        def expand(value, loader=path.parent):
            return Path(value.replace('@executable_path', str(executable.parent)).replace('@loader_path', str(loader)))
        rpaths = [expand(value) for value in own_rpaths]
        rpaths += [expand(value, executable.parent) for value in host_rpaths]
        for library in libraries:
            if library.startswith(('/usr/lib/', '/System/Library/')):
                continue
            assert library.startswith(('@rpath/', '@loader_path/', '@executable_path/')), f'{path.relative_to(app)}: build-machine or unsupported library path: {library}'
            if library.startswith('@rpath/'):
                candidates = [root / library.removeprefix('@rpath/') for root in rpaths]
            else:
                candidates = [expand(library)]
            assert any(candidate.is_file() and candidate.resolve().is_relative_to(app) for candidate in candidates), f'{path.relative_to(app)}: bundled library missing: {library}'
        count += 1
    print(f'Runtime library paths checked in {count} Mach-O binaries.')

if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
