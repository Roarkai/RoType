#!/usr/bin/env python3
"""Package the current product source without Git metadata, local research, keys or build outputs."""
import argparse
import io
import json
import pathlib
import plistlib
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = int(plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleVersion'])
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=pathlib.Path)
args = parser.parse_args()
OUTPUT = args.output or ROOT / f'dist/RoType-build{BUILD}-source.tar.gz'
PREFIX = f'RoType-build{BUILD}-source'
if OUTPUT.exists():
    raise RuntimeError(f'Refusing to overwrite source archive: {OUTPUT}')
PRODUCT_DIRS = {'Sources', 'Shared', 'Resources', 'Rime', 'Squirrel', 'Installer', 'VoiceRuntime',
                'ThirdParty', 'LICENSES', 'scripts', 'Tests', 'docs'}
ROOT_FILES = {'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'Package.swift', '.gitmodules', '.gitignore'}
NEW_DIRS = {'Sources', 'Shared', 'VoiceRuntime', 'Tests', 'Resources', 'Installer', 'Squirrel', 'Rime'}
paths = set()
modules = {}

def git(directory, *args):
    return subprocess.check_output(['git', '-C', str(directory), *args])

def collect(directory):
    for entry in git(directory, 'ls-files', '-s', '-z').split(b'\0'):
        if not entry:
            continue
        header, name = entry.split(b'\t', 1)
        mode, revision, _stage = header.decode().split()
        path = directory / name.decode()
        relative = path.relative_to(ROOT)
        if relative.parts[0] not in PRODUCT_DIRS and str(relative) not in ROOT_FILES:
            continue
        if relative.parts[:2] == ('docs', 'research'):
            continue
        if mode == '160000':
            if not path.is_dir():
                raise RuntimeError(f'Missing source checkout: {relative}')
            modules[str(relative)] = git(path, 'rev-parse', 'HEAD').decode().strip()
            collect(path)
        elif path.exists():
            paths.add(relative)

collect(ROOT)
# Rime plugins are separate Git checkouts ignored by the parent repository, not gitlinks.
for plugin in sorted((ROOT / 'Squirrel/librime/plugins').iterdir()):
    if plugin.is_dir() and (plugin / '.git').exists():
        modules[str(plugin.relative_to(ROOT))] = git(plugin, 'rev-parse', 'HEAD').decode().strip()
        collect(plugin)
for raw in git(ROOT, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\0'):
    if raw:
        path = pathlib.Path(raw.decode())
        if path.parts[0] in NEW_DIRS and path.suffix in {'.swift', '.h', '.m', '.json', '.resolved', '.py', '.sh', '.plist', '.entitlements', '.lua', '.yaml', '.pdf', '.png'}:
            paths.add(path)
# New build scripts are necessary for the native worker and signing chain.
for path in (ROOT / 'scripts').iterdir():
    if path.suffix in {'.sh', '.swift', '.py'}:
        paths.add(path.relative_to(ROOT))
omitted_fixtures = []
for path in list(paths):
    if path.suffix.lower() in {'.pem', '.p12', '.pfx', '.key'} or path.name.startswith('.env'):
        if path.parts[:3] == ('Squirrel', 'Sparkle', 'Tests'):
            paths.remove(path)
            omitted_fixtures.append(str(path))
            continue
        raise RuntimeError(f'Refusing potential credential file: {path}')
    if '.git' in path.parts or '.build' in path.parts or 'dist' in path.parts:
        raise RuntimeError(f'Refusing non-source path: {path}')
required = {'Squirrel/sources/RoTypeVoiceServer.swift', 'Sources/RoTypeApp/VoiceActivation.swift',
            'VoiceRuntime/Package.swift', 'Installer/tools/RetireVoice.swift',
            'Shared/RoTypeXPCProtocol/include/RoTypeDictationXPCProtocol.h'}
missing = required - {str(path) for path in paths}
if missing:
    raise RuntimeError(f'Missing required native source: {sorted(missing)}')
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(OUTPUT, 'w:gz', dereference=False) as archive:
    for path in sorted(paths):
        archive.add(ROOT / path, arcname=str(pathlib.Path(PREFIX) / path), recursive=False)
    metadata = json.dumps({'build': BUILD, 'baseCommit': git(ROOT, 'rev-parse', 'HEAD').decode().strip(),
                           'includesWorkingTreeChanges': bool(git(ROOT, 'status', '--porcelain', '--untracked-files=no').strip()), 'submodules': modules,
                           'omittedUpstreamTestKeyFixtures': omitted_fixtures}, indent=2).encode()
    info = tarfile.TarInfo(f'{PREFIX}/SOURCE-SNAPSHOT.json')
    info.size = len(metadata)
    info.mode = 0o644
    archive.addfile(info, io.BytesIO(metadata))
print(f'{len(paths)} source files; {OUTPUT.stat().st_size:,} bytes; {OUTPUT}')
