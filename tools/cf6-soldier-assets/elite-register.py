"""Inherit the ordinary panel with toughness and an explicit FR506 action module."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import xml.etree.ElementTree as E
import balance
import elite

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PAIRS=((466,478,elite.LINKAGES[0],'CF6特种精英·二阶段'),
       (467,479,elite.LINKAGES[1],'CF6特种精英·持盾一阶段'))


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
    units=json.loads(unit_text)
    entries=E.fromstring(text)
    tuning=json.loads((HERE/'elite-tuning.json').read_text(encoding='utf-8-sig'))
    toughness=tuning['toughnessCoefficient']
    sidearm=tuning['sidearmModule']['item']
    sidearm2=tuning['sidearmModule']['secondItem']
    assert sidearm=='FR506' and tuning['sidearmModule']['actions']==['retreat']
    assert type(toughness) in (int,float) and 50<=toughness<=100
    assert tuning['inheritedPanelExcept']==['韧性系数']
    receipt={'schema':'cf6-soldier.elite-panel-inheritance.v3','pairs':[],
        'basis':'Ordinary panel and primary equipment; authorized toughness and explicit retreat FR506 module.',
        'tuningSha256':hashlib.sha256((HERE/'elite-tuning.json').read_bytes()).hexdigest(),
        'sidearmModule':tuning['sidearmModule'],'extraDamageMultiplier':False,'extraArmor':False}
    for base_id,unit_id,link,name in PAIRS:
        base=next(x for x in units if x['id']==base_id)
        current=[x for x in units if x['id']==unit_id or x['spritename']==link]
        if any(x['id']!=unit_id or x['spritename']!=link for x in current) or len(current)>1:
            raise ValueError('Elite registration collision: '+str(unit_id))
        entry=copy.deepcopy(entries.find(base['spritename']))
        entry.tag=link
        entry.find('displayname').text=name
        base_toughness=float(entry.find('韧性系数').text)
        entry.find('韧性系数').text=str(toughness)
        unit=copy.deepcopy(base)
        unit.update(id=unit_id,spritename=link,name=name)
        unit['data']['secondary']=sidearm
        unit['data']['secondary2']=sidearm2
        balance.common.LINK=link
        balance.common.UNIT_ID=unit_id
        text=balance.common.update_enemy_text(text,entry)
        unit_text=balance.common.update_registration_text(unit_text,unit)
        mapping='<asset id="'+link+'" swf="flashswf/arts/new/Codex特种兵素材.swf" symbolName="Codex/特种兵/'+link+'" />'
        if not any(x.get('id')==link for x in E.fromstring(map_text)):
            closing='</'+E.fromstring(map_text).tag+'>'
            map_text=map_text.replace(closing,'  '+mapping+'\n'+closing,1)
        actual=E.fromstring(text).find(link)
        assert balance.common.canonical(actual)==balance.common.canonical(entry)
        assert next(x for x in json.loads(unit_text) if x['id']==unit_id)==unit
        receipt['pairs'].append({'baseUnit':base_id,'eliteUnit':unit_id,'baseLinkage':base['spritename'],
            'eliteLinkage':link,'panelEqualExcludingDisplayNameAndToughness':True,
            'equipmentDifferences':{key:{'ordinary':base['data'].get(key),'elite':value}
                for key,value in (('secondary',sidearm),('secondary2',sidearm2))},
            'panelDifferences':{'韧性系数':{'ordinary':base_toughness,'elite':toughness}},
            'sourcePanelSha256':hashlib.sha256(E.tostring(entries.find(base['spritename']))).hexdigest()})
    outputs=((properties,text),(units_path,unit_text),(map_path,map_text),
             (HERE/'elite-panel-inputs.json',json.dumps(receipt,ensure_ascii=False,indent=2)+'\n'))
    for path,value in outputs:
        if args.write:
            if not path.exists() or path.read_text(encoding='utf-8-sig')!=value:
                path.write_text(value,encoding='utf8',newline='\n')
        elif not path.exists() or path.read_text(encoding='utf-8-sig')!=value:
            raise ValueError('Stale elite registration: '+str(path))
    print(json.dumps(receipt,ensure_ascii=False))


if __name__=='__main__':
    main()
