"""Register the instructor candidate with the ordinary panel, without a stat boost."""
from pathlib import Path
import argparse
import copy
import json
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
    receipt={'schema':'cf6-instructor.panel-baseline.v1','attributeBoost':False,'pairs':[]}
    for base_id,unit_id,link,name in PAIRS:
        base=next(x for x in units if x['id']==base_id)
        current=[x for x in units if x['id']==unit_id or x['spritename']==link]
        if any(x['id']!=unit_id or x['spritename']!=link for x in current) or len(current)>1:
            raise ValueError('Instructor registration collision: '+str(unit_id))
        entry=copy.deepcopy(entries.find(base['spritename']))
        entry.tag=link;entry.find('displayname').text=name
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
        receipt['pairs'].append({'ordinary':base_id,'instructor':unit_id,'panelEqualExceptDisplayName':True,
            'sidearms':['FR506','FR506'],'strategyParameter':'特种兵策略','defaultStrategy':'adaptive'})
    outputs=((properties,text),(units_path,unit_text),(map_path,map_text),
        (Path(__file__).with_name('instructor-panel-inputs.json'),json.dumps(receipt,ensure_ascii=False,indent=2)+'\n'))
    for path,value in outputs:
        changed=not path.exists() or path.read_text(encoding='utf-8-sig')!=value
        if changed and args.write:path.write_text(value,encoding='utf-8',newline='\n')
        elif changed:raise ValueError('Stale instructor registration: '+str(path))
    print(json.dumps(receipt,ensure_ascii=False))


if __name__=='__main__':main()
