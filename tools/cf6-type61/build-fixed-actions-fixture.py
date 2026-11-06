"""Materialize production action functions and tables for real AVM1 comparison."""
import argparse
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET
import fixed_roster as fixed

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TARGET=ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsFixture.as'


def literal(value):
    return re.sub(r'"([A-Za-z_\u4e00-\u9fa5][A-Za-z0-9_\u4e00-\u9fa5]*)"(?=\s*:)',r'\1',
                  json.dumps(value,ensure_ascii=False,separators=(',',':')))


def generate():
    items=fixed.item_catalog()
    catalog=fixed.runtime_catalog(items=items)
    profiles=catalog['profiles']
    instructors=[]
    for row in fixed.read_source()['roster']:
        profile=fixed.profile(row,items)
        key='p'+fixed.hashlib.sha256(fixed.canonical(profile)).hexdigest()[:16]
        profiles[key]=profile
        if row['roleClass']=='instructor':instructors.append(key)
    profiles={key:fixed.runtime_profile(value) for key,value in profiles.items()}
    version=catalog['version']
    source='// Generated from production fixed rules and tables; native tests only.\n'
    source+='class org.flashNight.arki.scene.Cf6FixedActionsFixture {\n'
    source+='    public static function config():Object {var p:Object={};\n'
    for i,key in enumerate(profiles):source+=f'        p.{key}=profile{i}();\n'
    source+='        var units:Object={};\n'
    identity_rows=list(catalog['identities'].items())
    for start in range(0,len(identity_rows),24):source+=f'        identities{start}(units);\n'
    source+='        return {schema:"cf6-fixed-roster.runtime.v1",version:'+literal(version)+',profiles:p,identities:units,counts:'+literal(catalog['counts'])+'};\n    }\n'
    for start in range(0,len(identity_rows),24):
        source+=f'    private static function identities{start}(units:Object):Void {{\n'
        for identity,row in identity_rows[start:start+24]:source+='        units['+literal(identity)+']='+literal(row)+';\n'
        source+='    }\n'

    source+='    public static function instructors():Array {return '+literal(instructors)+';}\n'
    metadata=[]
    for row in fixed.read_source()['roster']:
        kind={'ordinary':'特种兵','elite':'特种精英','instructor':'特种教官'}[row['roleClass']]
        metadata.append(dict(identity=row['unitIdentity'],level=row['level'],mapId=row['mapId'],
                             phase=row['startingPhase'],linkage='敌人-CF6'+('持盾' if row['startingPhase']==1 else '')+kind))
    for start in range(0,len(metadata),24):
        source+=f'    private static function metadata{start}():Array {{return '+literal(metadata[start:start+24])+';}\n'
    source+='    public static function metadata():Array {return [].concat('+','.join('metadata'+str(i)+'()' for i in range(0,len(metadata),24))+');}\n'
    item_names={row[slot]['name'] for row in fixed.read_source()['roster'] for slot in ('primary','secondary1','secondary2') if row[slot]}
    item_names.update(row['lootRules']['materialCandidate'] for row in fixed.read_source()['roster'])
    files=[]
    for entry in ET.parse(ROOT/'data/items/list.xml').findall('items'):
        path=ROOT/'data/items'/entry.text
        selected=any(item.findtext('name') in item_names for item in ET.parse(path).findall('item'))
        if selected or entry.text in ('消耗品_弹夹.xml','消耗品_手雷.xml','收集品_材料_插件.xml'):
            files.append(dict(kind='items',url='../data/items/'+entry.text))
    files.append(dict(kind='equipment',url='../data/equipment/equipment_config.xml'))
    for entry in ET.parse(ROOT/'data/items/equipment_mods/list.xml').findall('items'):
        files.append(dict(kind='mods',url='../data/items/equipment_mods/'+entry.text))
    source+='    public static function catalogFiles():Array {return '+literal(files)+';}\n'
    for i,profile in enumerate(profiles.values()):
        source+=f'    private static function profile{i}():Object {{return '+literal(profile)+';}\n'
    rules='\n'.join((ROOT/'tools/cf6-soldier-assets'/name).read_text('utf-8-sig')
                    for name in ('FixedActionRules.as','FixedActionTriggers.as'))
    names=re.findall(r'^(cf6Rule\w+)=function\(',rules,re.M)
    source+='    public static function rules():Object {\n'
    source+='\n'.join('        var '+name+':Function;' for name in names)+'\n'+rules
    source+='\n        return {'+','.join(name+':'+name for name in names)+'};\n    }\n}\n'
    return b'\xef\xbb\xbf'+source.encode('utf8')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    content=generate()
    if args.check:
        if not TARGET.exists() or TARGET.read_bytes()!=content:raise ValueError('Stale same-source action fixture')
    else:
        if not TARGET.exists():shutil.copyfile(TARGET.with_name('Cf6FixedRosterFixture.as'),TARGET)
        if TARGET.read_bytes()[:3]!=b'\xef\xbb\xbf':raise ValueError('Native fixture BOM missing')
        TARGET.write_bytes(content)
    print(json.dumps(dict(bytes=len(content),check=args.check,scope='native-test-only')))
