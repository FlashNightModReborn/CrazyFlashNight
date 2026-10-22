"""Deterministically generate BOM-bearing classes from owned templates."""
from pathlib import Path
import argparse
import shutil

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
DEST=ROOT/'scripts/类定义/org/flashNight/arki/scene'
DONOR=DEST/'BookRunRules.as'
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
bom=DONOR.read_bytes()[:3]
assert bom==b'\xef\xbb\xbf', 'donor must have UTF-8 BOM'
for source in sorted(HERE.glob('*.as.txt')):
    target=DEST/source.name.removesuffix('.txt')
    content=bom+source.read_bytes()
    if args.check:
        assert target.read_bytes()==content, f'stale {target}'
    else:
        if not target.exists(): shutil.copyfile(DONOR,target)
        target.write_bytes(content)
    print(target.relative_to(ROOT))
