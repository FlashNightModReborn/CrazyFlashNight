"""Import untouched Black Dragon Hall backgrounds from the user-provided original archive.

--archive <zip> imports only the four backgrounds used by the Lee assault trial.
--check verifies the committed source manifest, sizes, hashes and exact SWF set.
The aftermath backgrounds used by the story are never overwritten.
"""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'flashswf/backgrounds/black-dragon-original'
MANIFEST = DEST / 'source-manifest.json'
INDICES = (2, 3, 4, 5)
PREFIX = 'CRAZYFLASHER7StandAloneStarter/resources/flashswf/'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def archive_digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()

def verify():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    assert manifest['schema'] == 'original-background-import.v1'
    assert manifest['unmodifiedSourceBytes'] is True
    expected = {f'hthhltnb_{i}_BG.swf' for i in INDICES}
    assert {row['file'] for row in manifest['files']} == expected
    assert {p.name for p in DEST.glob('*.swf')} == expected
    total = 0
    for row in manifest['files']:
        assert row['archiveEntry'] == PREFIX + row['file']
        data = (DEST / row['file']).read_bytes()
        assert data[:3] in (b'FWS', b'CWS')
        assert len(data) == row['bytes'] and digest(data) == row['sha256'], row['file']
        total += len(data)
    return {'files':len(expected), 'bytes':total, 'unmodifiedSourceBytes':True,
            'archiveSha256':manifest['archive']['sha256']}

def import_archive(archive):
    rows, payloads = [], {}
    with zipfile.ZipFile(archive) as source:
        for index in INDICES:
            name = f'hthhltnb_{index}_BG.swf'
            entry = PREFIX + name
            info = source.getinfo(entry)
            assert 12 < info.file_size < 1024 * 1024
            data = source.read(info)  # ZIP also verifies the entry CRC.
            assert data[:3] in (b'FWS', b'CWS')
            rows.append({'file':name, 'archiveEntry':entry, 'bytes':len(data),
                         'sha256':digest(data), 'zipCrc32':format(info.CRC, '08x')})
            payloads[name] = data
    manifest = {'schema':'original-background-import.v1', 'unmodifiedSourceBytes':True,
                'purpose':'Lee attacks Black Dragon Hall before its destruction',
                'archive':{'fileName':archive.name, 'bytes':archive.stat().st_size,
                           'sha256':archive_digest(archive)}, 'files':rows}
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    for name, data in payloads.items():
        existing = DEST / name
        assert not existing.exists() or existing.read_bytes() == data, ('Existing original asset differs', name)
    assert not MANIFEST.exists() or MANIFEST.read_bytes() == manifest_bytes, 'Existing source manifest differs'
    DEST.mkdir(parents=True, exist_ok=True)
    for name, data in payloads.items():
        (DEST / name).write_bytes(data)
    MANIFEST.write_bytes(manifest_bytes)
    return verify()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--archive', type=Path)
    group.add_argument('--check', action='store_true')
    args = parser.parse_args()
    print(json.dumps(import_archive(args.archive) if args.archive else verify(), ensure_ascii=False))
