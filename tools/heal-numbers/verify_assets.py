"""Check canonical healing asset calls and reject newly added direct positive HP writes.

Standard library only; does not edit archives or rely on installed Flash.
"""
from pathlib import Path
import argparse
import io
import json
import re
import struct
import subprocess
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = json.loads((Path(__file__).parent / 'asset-contract.json').read_text('utf-8-sig'))
archives = {}


def open_archive(data):
    # Some Adobe archives have an incorrect directory length. Adjust RAM only.
    data = bytearray(data)
    end = data.rfind(b'PK\x05\x06')
    if end < 0:
        raise ValueError('Not an XFL ZIP archive')
    central = struct.unpack_from('<I', data, end + 16)[0]
    if data[central:central + 4] != b'PK\x01\x02':
        raise ValueError('Invalid central directory offset')
    struct.pack_into('<I', data, end + 12, end - central)
    return zipfile.ZipFile(io.BytesIO(data))


def member_text(source, member=None):
    if source.endswith('.fla'):
        if source not in archives:
            archives[source] = open_archive((ROOT / source).read_bytes())
        return archives[source].read(member).decode('utf-8-sig')
    return (ROOT / (member or source)).read_text('utf-8-sig')


def code_only(text):
    token = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*[\s\S]*?\*/|//[^\r\n]*'
    return re.sub(token, lambda m: ' ' * len(m.group()), text)


def scripts(text):
    root = ET.fromstring(text)
    return '\n'.join(''.join(x.itertext()) for x in root.iter()
                     if x.tag.split('}')[-1] == 'script')


def direct_heals(code):
    code = code_only(code)
    pattern = r'\bhp\s*(?:\+=|\+\+|=\s*[^;\r\n]*\bhp\s*\+)'
    return [line.strip() for line in code.splitlines() if re.search(pattern, line)]


def git_bytes(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, stderr=subprocess.DEVNULL)


def compare_diff(base):
    if not base or set(base) == {'0'}:
        return 0
    changed = git_bytes('diff', '--name-only', '-z', base, '--', 'scripts', 'flashswf').decode('utf-8').split('\0')
    for rel in filter(None, changed):
        if 'Test' in rel or '/test' in rel or '/unused/' in rel or not (ROOT / rel).is_file():
            continue
        if rel.endswith('.as'):
            # The authority is allowed to write HP; callers must delegate to it.
            if rel.endswith('/HealApplier.as'):
                continue
            current = direct_heals((ROOT / rel).read_text('utf-8-sig'))
            try:
                previous = direct_heals(git_bytes('show', base + ':' + rel).decode('utf-8-sig'))
            except subprocess.CalledProcessError:
                previous = []
            if any(current.count(line) > previous.count(line) for line in current):
                raise ValueError('New direct HP healing write: ' + rel)
        elif rel.endswith('.xml'):
            try:
                current = direct_heals(scripts((ROOT / rel).read_text('utf-8-sig')))
            except (ET.ParseError, UnicodeDecodeError):
                continue
            try:
                previous = direct_heals(scripts(git_bytes('show', base + ':' + rel).decode('utf-8-sig')))
            except (subprocess.CalledProcessError, ET.ParseError):
                previous = []
            if any(current.count(line) > previous.count(line) for line in current):
                raise ValueError('New direct HP healing write: ' + rel)
        elif rel.endswith('.fla'):
            with open_archive((ROOT / rel).read_bytes()) as current:
                try:
                    previous = open_archive(git_bytes('show', base + ':' + rel))
                except (subprocess.CalledProcessError, ValueError, zipfile.BadZipFile):
                    previous = None
                try:
                    for name in current.namelist():
                        if not name.endswith('.xml'):
                            continue
                        raw = current.read(name)
                        if b'<script' not in raw or b'hp' not in raw:
                            continue
                        positives = direct_heals(scripts(raw.decode('utf-8-sig')))
                        before = [] if previous is None or name not in previous.namelist() else direct_heals(
                            scripts(previous.read(name).decode('utf-8-sig')))
                        if any(positives.count(line) > before.count(line) for line in positives):
                            raise ValueError('New direct HP healing write: ' + rel + ' :: ' + name)
                finally:
                    if previous is not None:
                        previous.close()
    return len(list(filter(None, changed)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', help='Optional git base for added healing writes')
    args = parser.parse_args()
    count = 0
    for source in CONTRACT['sources']:
        if not (ROOT / source['source']).is_file():
            raise ValueError('Missing source: ' + source['source'])
        for member in source['members']:
            text = member_text(source['source'], member['path'])
            code = scripts(text)
            expected = r'\b_root\s*\.\s*加血动作\s*\.\s*' + re.escape(member['bridge']) + r'\s*\('
            actual = len(re.findall(expected, code_only(code)))
            if actual != member['calls'] or direct_heals(code):
                raise ValueError('Healing contract drift: ' + source['source'] + ' :: ' + member['path'])
            count += actual
    if count != CONTRACT['branches']:
        raise ValueError('Wrong total branch count')
    for reset in CONTRACT['displayResets']:
        text = member_text(reset['source'], reset.get('member'))
        reset_pattern = r'\b_root\s*\.\s*加血动作\s*\.\s*失效治疗显示\s*\('
        if len(re.findall(reset_pattern, code_only(scripts(text)))) != reset['calls']:
            raise ValueError('Display reset drift: ' + reset['source'])
    changed = compare_diff(args.base)
    print(json.dumps({'healingBranches': count, 'projects': len(CONTRACT['sources']),
                      'displayResets': 4, 'diffFilesChecked': changed, 'passed': True}))


if __name__ == '__main__':
    try:
        main()
    finally:
        for archive in archives.values():
            archive.close()
