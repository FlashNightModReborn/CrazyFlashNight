"""Same-source loot policy for the isolated native persistence suite."""
import argparse, json, re, shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TARGET=ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6SoldierLootFixture.as'
def generate():
    policy=json.loads((HERE/'soldier-loot-policy.source.json').read_text('utf-8'))
    text=re.sub(r'"([A-Za-z_][A-Za-z0-9_]*)"(?=\s*:)',r'\1',json.dumps(policy,ensure_ascii=False,separators=(',',':')))
    return ('\ufeff// Generated from candidate loot policy; isolated native tests only.\n'
        'class org.flashNight.arki.scene.Cf6SoldierLootFixture {\n'
        '    public static function policy():Object {return '+text+';}\n}\n').encode('utf-8')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();data=generate()
    if args.check:
        if not TARGET.exists() or TARGET.read_bytes()!=data:raise ValueError('Stale native loot policy fixture')
    else:
        if not TARGET.exists():shutil.copyfile(TARGET.with_name('Cf6SoldierRoster.as'),TARGET)
        if TARGET.read_bytes()[:3]!=b'\xef\xbb\xbf':raise ValueError('Missing fixture BOM')
        TARGET.write_bytes(data)
    print(json.dumps(dict(bytes=len(data),check=args.check)))
