"""Copy existing BOM-bearing AS2 donor, then generate the owned prepared classes."""
from pathlib import Path
import argparse
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEST = ROOT/'scripts/类定义/org/flashNight/arki/scene'


def install(check=False):
    donor = DEST/'BookRunRules.as'
    bom = donor.read_bytes()[:3]
    if bom != b'\xef\xbb\xbf':raise ValueError('AS2 donor must carry a UTF-8 BOM')
    for source in sorted(HERE.glob('*.as.txt')):
        target = DEST/source.name.removesuffix('.txt')
        raw = bom + source.read_bytes()
        if check:
            if not target.is_file() or target.read_bytes() != raw:raise ValueError('stale class '+str(target))
        else:
            if not target.exists():shutil.copyfile(donor,target)
            target.write_bytes(raw)
        print(target.relative_to(ROOT))
    for name in ['TestLoader.as.template','run-native-tests.ps1']:
        template=HERE/name
        raw=bom+template.read_bytes().removeprefix(bom)
        if check:
            if template.read_bytes()!=raw:raise ValueError('native runner/template needs BOM')
        else:
            template.write_bytes(raw)


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    install(args.check)
