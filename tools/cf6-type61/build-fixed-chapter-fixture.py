"""Native chapter environment and unit attributes from current authoring sources."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
TARGET=ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6FixedChapterFixture.as'

def literal(value):
    return re.sub(r'"([A-Za-z_\u4e00-\u9fa5][A-Za-z0-9_\u4e00-\u9fa5]*)"(?=\s*:)',r'\1',json.dumps(value,ensure_ascii=False,separators=(',',':')))

def build():
    book=json.loads((ROOT/'data/stages/books/cf6-type61.runtime.json').read_text('utf8'))
    roster=json.loads((ROOT/'tools/cf6-type61/fixed-roster.source.json').read_text('utf8'))['roster']
    ids=sorted({r['mapId'] for r in roster})
    environments={e.findtext('BackgroundURL'):e for e in ET.parse(ROOT/'data/environment/stage_environment.xml').getroot()}
    source='// Generated native test inputs; the chapter itself is loaded through BookDefinition.\nclass org.flashNight.arki.scene.Cf6FixedChapterFixture {\n'
    source+='    public static function mapIds():Array {return '+literal(ids)+';}\n'
    source+='    public static function environment(id:String):Object {\n'
    for index,mid in enumerate(ids):source+='        if(id=="'+mid+'")return env'+str(index)+'();\n'
    source+='        return null;\n    }\n'
    for index,mid in enumerate(ids):
        env=environments['CF6_'+mid+'_BG.swf']
        data={key:float(env.findtext(key)) for key in ('Xmin','Ymin','Xmax','Ymax')}
        data['Collision']=[{'Point':[p.text for p in c.findall('Point')]} for c in env.findall('Collision')]
        body=literal(data)
        if len(body.encode('utf8'))>24000:raise ValueError('Native environment function exceeds source budget')
        source+='    private static function env'+str(index)+'():Object {return '+body+';}\n'
    types=set()
    for stage in book['maps']:
        for wave in stage['stage']['Wave']['SubWave']:
            types.update(e['Type'] for e in wave['EnemyGroup']['Enemy'])
        for phase in (stage.get('bossEncounter',{}),stage.get('bossEncounter',{}).get('nextPhase',{})):
            for group in phase.get('groups',[]):types.update(e['Type'] for e in group['enemies'])
    attrs={}
    for row in json.loads((ROOT/'data/units/units.json').read_text('utf-8-sig')):
        key='兵种'+str(row['id'])
        if key not in types:continue
        attrs[key]={'单位编号':row['id'],'单位键':row.get('key'),'兵种名':row['spritename'],'等级':row['level'],
            '名字':row['name'],'是否为敌人':row['is_hostile'],'身高':row['height']}
        for field,original in (('长枪','primary'),('手枪','secondary'),('手枪2','secondary2'),('刀','melee'),('手雷','grenade')):
            attrs[key][field]=row['data'].get(original) or ''
    source+='    public static function unitAttributes():Object {return '+literal(attrs)+';}\n}\n'
    if len(literal(attrs).encode('utf8'))>24000:raise ValueError('Native unit function exceeds source budget')
    return b'\xef\xbb\xbf'+source.encode('utf8')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    raw=build()
    if args.check:
        if not TARGET.is_file() or TARGET.read_bytes()!=raw:raise SystemExit('stale fixed chapter fixture')
    else:
        if not TARGET.exists():shutil.copyfile(TARGET.with_name('Cf6FixedRosterFixture.as'),TARGET)
        TARGET.write_bytes(raw)
    print(json.dumps({'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'check':args.check}))
