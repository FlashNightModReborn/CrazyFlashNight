"""Restore exact historical native negative controls from LOCAL Git objects.

No fetch, compilation, binary editing, overwrite or deletion is performed.
--check is read-only. --output-root supports an isolated verification directory;
the repository, tracked manifest and unchanged AS2 fixture remain authoritative.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name('surface-controls.json')
COMMIT = '56eb0c15d5dee285692b07eb1028f4ced93088f3'
IDS = ('A18', 'A19', 'A20', 'A22')
PREFIX = 'tmp/cf6-fieldfix-20261023/traversal/old-native/'
FIXTURE = ROOT / 'scripts/类定义/org/flashNight/arki/scene/Cf6NativeSurfaceTest.as'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def git(*args):
    env = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_ALLOW_PROTOCOL='', GIT_TERMINAL_PROMPT='0',
               GIT_NO_REPLACE_OBJECTS='1', GIT_OPTIONAL_LOCKS='0')
    result = subprocess.run(['git', '-C', str(ROOT), *args], capture_output=True, env=env)
    if result.returncode:
        raise ValueError('Required historical Git object is unavailable locally. '
                         'Provide repository history containing commit ' + COMMIT
                         + '; this tool never fetches. Git: '
                         + result.stderr.decode('utf-8', errors='replace').strip())
    return result.stdout


def load_manifest():
    data = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    if (data.get('schema') != 'cf6-native-surface-controls.v1'
            or data.get('sourceCommit') != COMMIT
            or [r.get('id') for r in data.get('controls', [])] != list(IDS)):
        raise ValueError('Unreviewed surface-control manifest identity')
    for row in data['controls']:
        name = 'CF6_' + row['id'] + '_BG.swf'
        if (row.get('oldSwf') != PREFIX + name
                or row.get('newSwf') != 'flashswf/backgrounds/cf6/' + name
                or row.get('sourceGitPath') != row['newSwf']
                or not re.fullmatch('[0-9a-f]{40}', row.get('sourceBlob', ''))
                or not re.fullmatch('[0-9a-f]{64}', row.get('oldSha256', ''))
                or type(row.get('oldBytes')) is not int or row['oldBytes'] < 8):
            raise ValueError('Invalid exact surface-control binding: ' + str(row.get('id')))
    # Read the unchanged AVM1 literal as data, never execute or regenerate it.
    source = FIXTURE.read_text(encoding='utf-8-sig')
    match = re.search(r'rows=(\[.*?\]);', source, re.S)
    if not match:
        raise ValueError('Surface fixture rows literal is missing')
    rows = json.loads(re.sub(r'([,{])([A-Za-z]\w*):', r'\1"\2":', match.group(1)))
    expected = []
    for control in data['controls']:
        for version in ('old', 'new'):
            expected.append(dict(id=control['id'], kind='floor', version=version,
                                 url='../' + control[version + 'Swf'],
                                 upper=control['upper'], lower=control['lower']))
    expected.extend(data['shaftProbes'])
    if rows != expected:
        raise ValueError('Tracked probe points differ from the unchanged AS2 fixture')
    return data


def destination(output_root, relative):
    target = output_root / relative
    if not target.resolve().is_relative_to(output_root):
        raise ValueError('Surface control escapes output root')
    for part in (target, *target.parents):
        if part == output_root:
            break
        if part.exists() or part.is_symlink():
            info = part.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
                raise ValueError('Surface-control path contains a reparse point: ' + str(part))
    return target


def verify_existing(target, row):
    if target.exists():
        if not target.is_file():
            raise ValueError('Existing control is not a regular file: ' + str(target))
        raw = target.read_bytes()
        if len(raw) != row['oldBytes'] or sha(raw) != row['oldSha256']:
            raise ValueError('Existing historical control differs; preserved without overwrite: ' + str(target))
        return True
    return False


def prepare(output_root, check=False):
    output_root = output_root.resolve(strict=True)
    if not output_root.is_dir():
        raise ValueError('Output root must be an existing directory')
    data = load_manifest()
    if git('rev-parse', COMMIT + '^{commit}').decode().strip() != COMMIT:
        raise ValueError('Historical commit identity mismatch')
    plan = []
    # Validate ALL source blobs and ALL existing destinations before any writes.
    for row in data['controls']:
        blob = git('rev-parse', COMMIT + ':' + row['sourceGitPath']).decode().strip()
        if blob != row['sourceBlob']:
            raise ValueError('Historical Git blob identity mismatch: ' + row['id'])
        raw = git('cat-file', 'blob', blob)
        if (len(raw) != row['oldBytes'] or sha(raw) != row['oldSha256']
                or raw[:3] not in (b'FWS', b'CWS', b'ZWS')):
            raise ValueError('Historical SWF content identity mismatch: ' + row['id'])
        target = destination(output_root, row['oldSwf'])
        exists = verify_existing(target, row)
        if check and not exists:
            raise ValueError('Missing historical control (read-only check): ' + str(target))
        plan.append((row, target, raw, exists))
    result = []
    for row, target, raw, exists in plan:
        if not exists:
            target.parent.mkdir(parents=True, exist_ok=True)
            destination(output_root, row['oldSwf'])
            # Exclusive create refuses a competing writer; never truncate a file.
            with target.open('xb') as stream:
                stream.write(raw)
            verify_existing(target, row)
        result.append(dict(id=row['id'], status='verified' if exists else 'created',
                           path=str(target), sha256=row['oldSha256'], blob=row['sourceBlob']))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Read-only verification; missing controls fail')
    parser.add_argument('--output-root', type=Path, default=ROOT, help='Existing isolated root, default repository root')
    args = parser.parse_args()
    try:
        rows = prepare(args.output_root, args.check)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        parser.exit(1, 'Surface controls: ' + str(error) + '\n')
    print(json.dumps(dict(sourceCommit=COMMIT, controls=rows), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
