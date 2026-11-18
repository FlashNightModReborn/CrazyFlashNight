"""Restore a sealed CF6 evidence batch into a separate directory by its historical path."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import tempfile
from urllib.request import urlopen
import zipfile

from evidence_paths import ROOT, resolve_archived, utf16


INDEX = Path(__file__).with_name('evidence-archive-index.json')
MANIFEST = 'archive-manifest.json'
WINDOWS_RESERVED = re.compile(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', re.IGNORECASE)


def safe_parts(member):
    parts = member.split('/')
    if any(part in ('', '.', '..') or part.endswith(('.', ' '))
           or WINDOWS_RESERVED.match(part) or utf16(part) > 255
           or any(ord(c) < 32 or c in '<>:"|?*\\' for c in part) for part in parts):
        raise ValueError(f'Invalid archive member path: {member}')
    return parts


def locate(member):
    safe_parts(member)
    index = json.loads(INDEX.read_text(encoding='utf-8'))
    if index['schema'] != 1:
        raise ValueError('Unsupported evidence archive index schema')
    prefixes = tuple(row['prefix'] + '/' for row in index['archives'])
    canonical = member if member.startswith(prefixes) else resolve_archived(member, root=Path()).as_posix()
    candidates = [row for row in index['archives'] if canonical.startswith(row['prefix'] + '/')]
    if len(candidates) != 1:
        raise ValueError(f'No unique off-repo archive for {member}')
    return canonical, candidates[0]


def fetch(row, target):
    with urlopen(row['url'], timeout=60) as response, target.open('xb') as output:
        remaining = row['archiveBytes']
        while chunk := response.read(min(1024 * 1024, remaining + 1)):
            if len(chunk) > remaining:
                raise ValueError('Download exceeds the indexed archive size')
            output.write(chunk)
            remaining -= len(chunk)


def extract(archive, row, canonical, stage, output):
    with archive.open('rb') as stream:
        if archive.stat().st_size != row['archiveBytes'] or hashlib.file_digest(stream, 'sha256').hexdigest() != row['sha256']:
            raise ValueError('Archive size or SHA-256 does not match the index')

    with zipfile.ZipFile(archive) as bundle:
        infos = {entry.filename: entry for entry in bundle.infolist()}
        source = json.loads(bundle.read(MANIFEST))
        if (source['schema'], source['prefix'], source['sourceCommit']) != (1, row['prefix'], row['sourceCommit']):
            raise ValueError('Archive provenance does not match the index')
        files = {entry['path']: entry for entry in source['files']}
        if (len(files) != row['fileCount'] or len(files) != len(source['files']) or len(infos) != len(bundle.infolist())
                or set(infos) != set(files) | {MANIFEST} or sum(entry['bytes'] for entry in files.values()) != row['unpackedBytes']
                or len({name.casefold() for name in files}) != len(files)):
            raise ValueError('Archive member inventory does not match the index')
        if canonical not in files:
            raise ValueError(f'The exact requested member is absent: {canonical}')

        for member, entry in files.items():
            parts = safe_parts(member)
            file_info = infos[member]
            target = stage.joinpath(*parts)
            if (not member.startswith(row['prefix'] + '/') or entry['mode'] != '100644'
                    or stat.S_IFMT(file_info.external_attr >> 16) != stat.S_IFREG or file_info.file_size != entry['bytes']):
                raise ValueError(f'Unexpected archive file type or size: {member}')
            if utf16(output.joinpath(*parts)) > 240:
                raise ValueError('Restored path exceeds the existing 240 UTF-16 budget. Choose a shorter output path.')
            target.parent.mkdir(parents=True, exist_ok=True)
            sha = hashlib.sha256()
            blob = hashlib.sha1(f'blob {entry["bytes"]}\0'.encode('ascii'))
            written = 0
            with bundle.open(file_info) as stream, target.open('xb') as restored:
                while chunk := stream.read(1024 * 1024):
                    sha.update(chunk)
                    blob.update(chunk)
                    written += restored.write(chunk)
            if written != entry['bytes'] or sha.hexdigest() != entry['sha256'] or blob.hexdigest() != entry['blob']:
                raise ValueError(f'Restored bytes differ from the archive manifest: {member}')


def restore(member, output, archive=None):
    canonical, row = locate(member)
    output = output.resolve()
    if output.is_relative_to(ROOT.resolve()) or output.exists():
        raise ValueError('Choose a new output directory outside the game checkout')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.cf6-', dir=output.parent) as directory:
        work = Path(directory)
        if archive is None:
            archive = work / 'archive.zip'
            fetch(row, archive)
        stage = work / 'tree'
        extract(archive.resolve(strict=True), row, canonical, stage, output)
        if output.exists():
            raise ValueError('Output directory already exists')
        stage.rename(output)
    return output.joinpath(*safe_parts(canonical))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo_relative_path', help='Exact old or current repo-relative file path, with forward slashes')
    parser.add_argument('--output', required=True, type=Path, help='New scratch directory outside the game checkout')
    parser.add_argument('--archive', type=Path, help='Local ZIP instead of a download. The same indexed hash is checked.')
    args = parser.parse_args()
    try:
        print(restore(args.repo_relative_path, args.output, args.archive))
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
