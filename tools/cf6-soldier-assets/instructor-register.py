"""Register the instructor with the authorized stage-8 tier-9 mini-boss panel."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import subprocess
import xml.etree.ElementTree as E
import balance
import tactics

ROOT=Path(__file__).resolve().parents[2]
PAIRS=((466,480,tactics.LINKAGES[0],'CF6特种教官·二阶段'),
       (467,481,tactics.LINKAGES[1],'CF6特种教官·持盾一阶段'))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--write',action='store_true')
    args=parser.parse_args()
    properties=ROOT/'data/enemy_properties/CF6重制敌人.xml'
    units_path=ROOT/'data/units/units.json'
    map_path=ROOT/'data/items/asset_source_map.xml'
    text=properties.read_text(encoding='utf-8-sig')
    unit_text=units_path.read_text(encoding='utf-8-sig')
    map_text=map_path.read_text(encoding='utf-8-sig')
    units=json.loads(unit_text);entries=E.fromstring(text)
    tuning_path=Path(__file__).with_name('instructor-tuning.json')
    tuning=json.loads(tuning_path.read_text(encoding='utf-8'))
    if tuning['schema']!='cf6-instructor.panel-tuning.v1' or tuning['classification']!='mini_boss' \
            or tuning['stage']!=tuning['baseStage']+1 or tuning['stage']!=8 or tuning['tierFactor']!=9:
        raise ValueError('Instructor stage/tier differs from the authorized stage-8 tier-9 inputs')
    receipt={'schema':'cf6-instructor.panel-balance.v2','attributeBoost':True,
        'formula':'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
        'tuningSha256':hashlib.sha256(tuning_path.read_bytes()).hexdigest(),'tuning':tuning,'pairs':[]}
    for base_id,unit_id,link,name in PAIRS:
        base=next(x for x in units if x['id']==base_id)
        current=[x for x in units if x['id']==unit_id or x['spritename']==link]
        if any(x['id']!=unit_id or x['spritename']!=link for x in current) or len(current)>1:
            raise ValueError('Instructor registration collision: '+str(unit_id))
        entry=copy.deepcopy(entries.find(base['spritename']))
        entry.tag=link;entry.find('displayname').text=name
        if int(entry.findtext('标识/阶段'))!=tuning['baseStage']:
            raise ValueError('Ordinary soldier stage changed; instructor inputs require a new review')
        flags={key:float(entry.findtext('标识/'+key)) for key in balance.common.FLAG_KEYS}
        flags.update({'阶段':tuning['stage'],'档次系数':tuning['tierFactor']})
        inputs={balance.common.FLAG_KEYS[key]:value for key,value in flags.items()}
        expression="import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';console.log(JSON.stringify(computeMonsterRow("+json.dumps(inputs)+")));"
        values=json.loads(subprocess.check_output(['node','tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs','-e',expression],cwd=ROOT,text=True,encoding='utf-8'))
        for key,value in flags.items():entry.find('标识/'+key).text=f'{value:g}'
        for key,formula in balance.common.FIELDS.items():entry.find(key).text=str(math.floor(values[formula]+0.5))
        resistance=entry.find('魔法抗性')
        for tag in ('精英','首领'):
            for child in list(resistance.findall(tag)):resistance.remove(child)
        E.SubElement(resistance,'首领').text=str(tuning['bossResistance'])
        unit=copy.deepcopy(base);unit.update(id=unit_id,spritename=link,name=name)
        unit['data']['secondary']='FR506';unit['data']['secondary2']='FR506'
        balance.common.LINK=link;balance.common.UNIT_ID=unit_id
        text=balance.common.update_enemy_text(text,entry)
        unit_text=balance.common.update_registration_text(unit_text,unit)
        root=E.fromstring(map_text)
        found=[x for x in root if x.get('id')==link]
        expected={'id':link,'swf':'flashswf/arts/new/Codex特种兵素材.swf','symbolName':tactics.PREFIX+link}
        if found:
            if len(found)!=1 or found[0].attrib!=expected:raise ValueError('Instructor source mapping collision')
        else:
            closing='</'+root.tag+'>'
            mapping='  <asset '+ ' '.join(k+'="'+v+'"' for k,v in expected.items())+' />\n'
            map_text=map_text.replace(closing,mapping+closing,1)
        assert balance.common.canonical(E.fromstring(text).find(link))==balance.common.canonical(entry)
        assert next(x for x in json.loads(unit_text) if x['id']==unit_id)==unit
        receipt['pairs'].append({'ordinary':base_id,'instructor':unit_id,'panelEqualExceptDisplayName':False,
            'input':inputs,'flags':flags,'integerPanel':{key:int(entry.find(key).text) for key in balance.common.FIELDS},
            'classification':'mini_boss','eliteDamageEligible':False,'bossDamageEligible':True,
            'sidearms':['FR506','FR506'],'strategyParameter':'特种兵策略','defaultStrategy':'adaptive'})
    outputs=((properties,text),(units_path,unit_text),(map_path,map_text),
        (Path(__file__).with_name('instructor-panel-inputs.json'),json.dumps(receipt,ensure_ascii=False,indent=2)+'\n'))
    for path,value in outputs:
        changed=not path.exists() or path.read_text(encoding='utf-8-sig')!=value
        if changed and args.write:path.write_text(value,encoding='utf-8',newline='\n')
        elif changed:raise ValueError('Stale instructor registration: '+str(path))
    ledger_path=ROOT/'tools/cf7-balance-tool/data/monster-flag-ledger.json'
    ledger=json.loads(ledger_path.read_text(encoding='utf-8'))
    for _,_,link,_ in PAIRS:
        claim={'阶段':tuning['stage'],'档次系数':tuning['tierFactor']}
        if args.write:ledger['claims'][link]=claim
        elif ledger['claims'].get(link)!=claim:raise ValueError('Stale instructor stage/tier claim: '+link)
    if args.write:ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(receipt,ensure_ascii=False))


if __name__=='__main__':main()
