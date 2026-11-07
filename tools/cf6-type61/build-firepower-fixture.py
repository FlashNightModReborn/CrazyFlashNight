"""Native oracle cases bind the current complete loadout and independent budget anchors."""
import argparse
import json
import shutil
from pathlib import Path
import fixed_roster as fixed
from importlib.util import spec_from_file_location, module_from_spec

ROOT = fixed.ROOT
TARGET = ROOT / 'scripts/类定义/org/flashNight/arki/scene/Cf6SoldierFirepowerFixture.as'


def generate():
    source = fixed.read_source()
    fire = fixed.firepower_source()
    rows = []
    roles = dict(suppress=1, line=.85, mobile=.65, breach=.35, precision=.2, flush=.25, counter=.5, dual=.5)
    for r in source['roster']:
        fp = fire['profiles'][r['unitIdentity']]
        for slot, p in fp['slots'].items():
            rows.append([r['unitIdentity'], ('primary','secondary1','secondary2').index(slot), r['level'],
                ('ordinary','elite','instructor').index(r['roleClass']), roles[r['role']], p['name'], p['tier'],
                {'single_physical':1,'native_magic':2}.get(p['family'],0),p['skill'],p['nano'],p['enhancement'],
                p['weaponOnlyRaw'],p['expectedB'],p['expectedC']])
    text = '// Generated current loadout XML/bisection expectations; native tests only.\n'
    text += 'class org.flashNight.arki.scene.Cf6SoldierFirepowerFixture {\n'
    parts=[]
    for i in range(0,len(rows),24):
        parts.append('part'+str(i)+'()')
        text += '    private static function part'+str(i)+'():Array {return '+json.dumps(rows[i:i+24],ensure_ascii=False,separators=(',',':'))+';}\n'
    forms={(p['name'],p['tier']) for fp in fire['profiles'].values() for p in fp['slots'].values()}
    text += '    public static function cases():Array {return [].concat('+','.join(parts)+');}\n'
    text += '    public static function formCount():Number {return '+str(len(forms))+';}\n}\n'
    return b'\xef\xbb\xbf'+text.encode('utf-8')


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    data=generate()
    if args.check:
        if not TARGET.exists() or TARGET.read_bytes()!=data:raise ValueError('Stale native firepower oracle')
    else:
        if not TARGET.exists():shutil.copyfile(TARGET.with_name('Cf6FixedRosterFixture.as'),TARGET)
        TARGET.write_bytes(data)
    print(json.dumps(dict(bytes=len(data),check=args.check)))
