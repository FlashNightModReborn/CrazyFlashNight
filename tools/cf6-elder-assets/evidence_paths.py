"""Short evidence destinations and read-only aliases for sealed receipts.

Mapping resolves only exact archived files; it never rewrites a receipt or runs
an archived script. All lengths are unnormalised UTF-16 code units.
"""
import argparse
from functools import lru_cache
import json
import re
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
OLD_PREFIXES = (
    'tools/cf6-elder-assets/evidence/20261017-calibration',
    'tools/cf6-elder-assets/evidence/20261018-loader-size-followup',
)
MAP_FILE = Path(__file__).with_name('evidence-path-map.json')


def utf16(value):
    return len(str(value).encode('utf-16-le')) // 2


def validate_output(target, root=ROOT):
    """Check before mkdir/write; never create or change filesystem state."""
    root, target = Path(root).resolve(), Path(target).resolve()
    try:
        relative = target.relative_to(root).as_posix()
    except ValueError:
        relative = None
    if relative is not None:
        if any(relative.casefold() == p.casefold() or relative.casefold().startswith(p.casefold() + '/') for p in OLD_PREFIXES):
            raise ValueError('Archived evidence root is retired; use e/<short-campaign>')
        if utf16(relative) > 179:
            raise ValueError('Evidence output exceeds supported relative budget 179 UTF-16')
    if utf16(str(target)) > 240:
        raise ValueError('Evidence output exceeds full visible budget 240 UTF-16')
    if any(utf16(part) > 255 for part in target.parts):
        raise ValueError('Evidence output component exceeds 255 UTF-16')
    return target


def new_path(campaign, member, root=ROOT):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,11}', campaign):
        raise ValueError('Campaign must be 1..12 lowercase ASCII letters/digits/hyphens')
    p = PurePosixPath(member)
    parts = member.split('/')
    reserved = re.compile(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', re.IGNORECASE)
    if (not member or p.is_absolute() or '\\' in member
            or any(x in ('', '.', '..') or x.endswith(('.', ' '))
                   or reserved.match(x) or any(ord(c) < 32 or c in '<>:\"|?*' for c in x) for x in parts)):
        raise ValueError('Member must be a safe Windows-compatible relative slash path')
    base = Path(root).resolve() / 'tools/cf6-elder-assets/e' / campaign
    target = (base / Path(*p.parts)).resolve()
    if not target.is_relative_to(base):
        raise ValueError('Evidence member escapes campaign through a symbolic link')
    return validate_output(target, root)


@lru_cache(maxsize=4)
def _exact_mapping(mapping_file):
    mapping = json.loads(Path(mapping_file).read_text(encoding='utf-8'))
    aliases = {}
    for row in mapping['files']:
        for name in (row['old'], row['new']):
            if name in aliases:
                raise ValueError('Duplicate exact archived path mapping')
            aliases[name] = row['new']
    return aliases


def resolve_archived(old_path, root=ROOT, mapping_file=MAP_FILE):
    """Map an exact repo-relative historical path; do not create a legacy alias."""
    try:
        relative = _exact_mapping(str(Path(mapping_file).resolve()))[old_path]
    except KeyError:
        raise ValueError('No exact archived path mapping') from None
    return Path(root) / relative


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    new = sub.add_parser('new'); new.add_argument('campaign'); new.add_argument('member')
    old = sub.add_parser('resolve'); old.add_argument('repo_relative_path')
    args = parser.parse_args()
    result = new_path(args.campaign, args.member) if args.command == 'new' else resolve_archived(args.repo_relative_path)
    print(result)


if __name__ == '__main__':
    main()
