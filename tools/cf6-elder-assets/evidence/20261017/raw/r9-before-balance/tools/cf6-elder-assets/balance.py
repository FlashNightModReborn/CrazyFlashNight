"""User-fixed C8/D9 human and C8/D20 robot; measured actions feed the workbook formula."""
from pathlib import Path
import argparse
import copy
import importlib.util
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as E
import build

ROOT,HERE=build.ROOT,build.HERE
spec=importlib.util.spec_from_file_location('elder_balance_io',ROOT/'tools/cf6-bladebot-assets/balance.py')
common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
CONFIG={'human':{'id':471,'name':'老头','tier':9,'height':180,'speed':[55,65],'tenacity':20,
                 'growth':1,'attackBias':2,'defenseBias':4},
        'robot':{'id':472,'name':'老头机器人','tier':20,'height':190,'speed':[45,65],'tenacity':40,
                 'growth':0.9,'attackBias':2,'defenseBias':40}}

def expected(form):
    config=CONFIG[form];rig=build.FORMS[form];link=build.LINKS[form]
    census=json.loads((ROOT/'tools/cf7-balance-tool/data/monster-census.json').read_text('utf-8-sig'))
    timeline=json.loads((build.ARCHIVES[form]/'reference/timelines.json').read_text('utf8'))
    actions=[]
    for name,a in rig['actions'].items():
        first,last=a['hits'][0],a['hits'][-1];total=len(timeline[str(a['id'])])
        actions.append({'name':name,'first':first,'last':last,'total':total,'windup':first-1,
            'tail':total-last+6,'segments':len(a['hits'])/max(1,(last-first+1)/census['attackSegmentWindowFrames']),
            'power':a['power'],'typeFactor':2 if a['damage']=='魔法' else 1})
    mean=lambda key:sum(a[key] for a in actions)/len(actions)
    weighted=mean('windup')+mean('tail')*census['attackTempoTailFactor']
    tempo=next(b['factor'] for b in census['attackTempoBands'] if weighted<b['maxWindupFrames']*(1+census['attackTempoTailFactor']))
    long_hit=max(rig['hitDurations'])>census['armorRules']['longKnockbackFrames']
    armor=(1 if long_hit else 2) if rig['canBeAirborne'] else (3 if long_hit else 4)
    armor+=min(.5,math.floor(config['tenacity']/20)*.1) if config['tenacity']>20 else 0
    flags={'阶段':8,'档次系数':config['tier'],'成长系数':config['growth'],'攻速系数':tempo,
        '攻击倍率':sum(a['power']*a['typeFactor'] for a in actions)/len(actions),'段数系数':mean('segments'),
        '速度系数':2,'高攻低血防系数':config['attackBias'],'霸体系数':armor,'高防低血系数':config['defenseBias']}
    # Serialized flags must be the actual formula inputs, without hidden precision.
    flags={k:float(f'{v:.8g}') for k,v in flags.items()}
    inputs={common.FLAG_KEYS[k]:v for k,v in flags.items()}
    expression="import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';console.log(JSON.stringify(computeMonsterRow("+json.dumps(inputs)+")));"
    values=json.loads(subprocess.check_output(['node','tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs','-e',expression],cwd=ROOT,text=True,encoding='utf8'))
    entry=copy.deepcopy(E.parse(ROOT/'data/enemy_properties/诺亚新敌人.xml').getroot().find('敌人-黑铁会改造人'));entry.tag=link
    entry.find('displayname').text=config['name']
    for key,value in {'速度_min':config['speed'][0],'速度_max':config['speed'][1],
        '躲闪率_min':100,'躲闪率_max':50,'重量':85 if form=='human' else 200,'韧性系数':config['tenacity']}.items():entry.find(key).text=str(value)
    resistance=entry.find('魔法抗性')
    for child in list(resistance):resistance.remove(child)
    for key,value in ({'装甲':20,'人类':20,'首领':20} if form=='human' else {'装甲':40,'机械':40,'首领':30}).items():E.SubElement(resistance,key).text=str(value)
    E.SubElement(entry,'battleRecordAppearance').text='fixed'
    for key,value in flags.items():entry.find('标识/'+key).text=f'{value:.8g}'
    for key,formula in common.FIELDS.items():entry.find(key).text=str(math.floor(values[formula]+0.5))
    unit={'id':config['id'],'spritename':link,'level':50,'name':config['name'],'is_hostile':True,'height':config['height'],
        'data':{'primary':None,'secondary':None,'secondary2':None,'melee':None}}
    receipt={'formula':'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts','form':form,
        'fixedByUser':['阶段','档次系数'],'input':inputs,'flags':flags,'actions':actions,'weightedTempo':weighted,
        'recoveryFrames':6,'attackTempoTailFactor':census['attackTempoTailFactor'],
        'integerPanel':{k:int(entry.find(k).text) for k in common.FIELDS},'configuration':config,
        'armorEvidence':{'hitDurations':rig['hitDurations'],'canBeAirborne':rig['canBeAirborne'],'longThreshold':census['armorRules']['longKnockbackFrames'],'derived':armor},
        'position':'Human then robot, meaningful threat to Ark Beast King and EXUSIAI commander, but neither target defeated.'}
    return entry,unit,receipt

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
    path=ROOT/'data/enemy_properties/CF6重制敌人.xml';units_path=ROOT/'data/units/units.json'
    ledger_path=ROOT/'tools/cf7-balance-tool/data/monster-flag-ledger.json'
    text=path.read_text('utf8');unit_text=units_path.read_text('utf-8-sig');ledger=json.loads(ledger_path.read_text('utf8'));receipts={}
    for form in CONFIG:
        entry,unit,receipt=expected(form);receipts[form]=receipt
        common.LINK,common.UNIT_ID=build.LINKS[form],CONFIG[form]['id']
        matches=[u for u in json.loads(unit_text) if u['id']==common.UNIT_ID or u['spritename']==common.LINK]
        assert len(matches)<2 and all(u['id']==common.UNIT_ID and u['spritename']==common.LINK for u in matches),'Unit collision'
        text=common.update_enemy_text(text,entry);unit_text=common.update_registration_text(unit_text,unit)
        ledger['claims'][common.LINK]={'阶段':8,'档次系数':CONFIG[form]['tier']}
    receipt_path=HERE/'balance-inputs.json'
    if args.write:
        if path.read_text('utf8')!=text:path.write_text(text,'utf8',newline='\n')
        if units_path.read_text('utf-8-sig')!=unit_text:units_path.write_text(unit_text,'utf8',newline='\n')
        ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
        receipt_path.write_text(json.dumps(receipts,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
    assert path.read_text('utf8')==text and units_path.read_text('utf-8-sig')==unit_text
    assert json.loads(ledger_path.read_text('utf8'))==ledger
    assert json.loads(receipt_path.read_text('utf8'))==receipts
    print(json.dumps({'ok':True,'forms':{k:{'flags':r['flags'],'panel':r['integerPanel']} for k,r in receipts.items()}},ensure_ascii=False))

if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf8')
    main()
