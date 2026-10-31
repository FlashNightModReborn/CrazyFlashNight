"""Stage 7 / tier 16 is user-fixed; action coefficients come from the frozen rig."""
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

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LINK, UNIT_ID = '敌人-CF6大头机器人', 472
PROPERTY_FILE = 'CF6重制敌人.xml'
SOURCE = '敌人-黑铁会改造人'
spec = importlib.util.spec_from_file_location('headbot_balance_io', ROOT/'tools/cf6-bladebot-assets/balance.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
common.LINK, common.UNIT_ID = LINK, UNIT_ID


def expected():
    census = json.loads((ROOT/'tools/cf7-balance-tool/data/monster-census.json').read_text('utf-8-sig'))
    tail_factor = census['attackTempoTailFactor']
    actions = [build.ATTACKS[name] for name in ('beam','thrust')]
    timelines = json.loads((build.ARCHIVE/'reference/timelines.json').read_text('utf8'))
    first = [a['hits'][0] for a in actions]; last = [a['hits'][-1] for a in actions]
    totals = [len(timelines[str(a['id'])])+(build.BEAM_WINDUP if i==0 else 0) for i,a in enumerate(actions)]
    windup_mean = sum(v-1 for v in first)/len(actions)
    tail_mean = sum(total-hit for total,hit in zip(totals,last))/len(actions)
    powers = [a['power'] for a in actions]; types = [2 if a['damageType']=='魔法' else 1 for a in actions]
    multiplier = sum(power*kind for power,kind in zip(powers,types))/len(actions)
    segments = [len(a['hits']) for a in actions]; segment_mean = sum(segments)/len(actions)
    weighted = windup_mean + tail_mean*tail_factor
    tempo = next(b['factor'] for b in census['attackTempoBands'] if weighted < b['maxWindupFrames']*(1+tail_factor))
    flags = {'阶段':7, '档次系数':16, '成长系数':1, '攻速系数':tempo, '攻击倍率':multiplier,
        '段数系数':segment_mean, '速度系数':2, '高攻低血防系数':1, '霸体系数':4.5, '高防低血系数':1}
    inputs = {common.FLAG_KEYS[k]:v for k,v in flags.items()}
    expression = "import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';console.log(JSON.stringify(computeMonsterRow("+json.dumps(inputs)+")));"
    tsx_cli = ROOT/'tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs'
    node_cmd = ['node',str(tsx_cli),'-e',expression] if tsx_cli.exists() else ['node','--input-type=module','-e',expression]
    values = json.loads(subprocess.check_output(node_cmd,cwd=ROOT,text=True,encoding='utf8'))
    entry = copy.deepcopy(E.parse(ROOT/'data/enemy_properties/诺亚新敌人.xml').getroot().find(SOURCE))
    entry.tag = LINK
    entry.find('displayname').text = '大头机器人'
    for key,value in {'速度_min':45,'速度_max':60,'躲闪率_min':100,'躲闪率_max':50,'重量':200,'韧性系数':100}.items():
        entry.find(key).text = str(value)
    resistance = entry.find('魔法抗性')
    for child in list(resistance):
        resistance.remove(child)
    for key,value in {'装甲':30,'机械':40,'首领':20}.items():
        E.SubElement(resistance,key).text = str(value)
    E.SubElement(entry,'battleRecordAppearance').text = 'fixed'
    for key,value in flags.items():
        entry.find('标识/'+key).text = f'{value:g}'
    for key,formula in common.FIELDS.items():
        entry.find(key).text = str(math.floor(values[formula]+0.5))
    unit = {'id':UNIT_ID,'spritename':LINK,'level':40,'name':'大头机器人','is_hostile':True,'height':185,
        'data':{'primary':None,'secondary':None,'secondary2':None,'melee':None}}
    receipt = {'formula':'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
        'schemaReference':SOURCE,'unitId':UNIT_ID,'linkage':LINK,'requestedStage':7,'requestedTier':16,
        'fixedByUser':['阶段','档次系数'],'input':inputs,'flags':flags,
        'integerPanel':{k:int(entry.find(k).text) for k in common.FIELDS},
        'observedBasis':{'rulebook':'tools/cf7-balance-tool/docs/monster-flag-rulebook.md',
            'speedMean':52.5,'attackFirstHitFrames':first,'attackLastHitFrames':last,
            'attackTotalFrames':totals,'windupMean':windup_mean,'tailMean':tail_mean,'tempoTailFactor':tail_factor,
            'weightedTempo':weighted,'tempoThresholdScale':1+tail_factor,'powerMultipliers':powers,'damageTypeFactors':types,'attackMultiplierMean':multiplier,
            'effectiveContactSegments':segments,'segmentMean':segment_mean,'hitRecoveryFrames':[6,6],
            'knockdownAndDownBothDelegate':False,'baseArmorBand':4,'tenacity':100,'tenacityDecimal':0.5},
        'adaptation':{'speed':[45,60],'weight':200,'height':185,'defaultLevel':40,
            'growthAndAttackDefenseBias':[1,1,1],
            'damage':'Beam uses instantaneous wave magic damage; thrust remains physical. CF7 area bullets own resolution.',
            'targetPosition':'Stable same-level wins over Arkclaw; stage 7 and tier 16 stay fixed.',
            'hit':'Short reaction, horizontal knockback allowed, no airborne/down state; original hover preserved.'}}
    return entry,unit,receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write',action='store_true')
    args = parser.parse_args()
    entry,unit,receipt = expected()
    target = ROOT/'data/enemy_properties'/PROPERTY_FILE
    units_path = ROOT/'data/units/units.json'
    ledger_path = ROOT/'tools/cf7-balance-tool/data/monster-flag-ledger.json'
    receipt_path = HERE/'balance-inputs.json'
    units = json.loads(units_path.read_text('utf-8-sig'))
    matching = [r for r in units if r['id']==UNIT_ID or r['spritename']==LINK]
    if len(matching)>1 or any(r['id']!=UNIT_ID or r['spritename']!=LINK for r in matching):
        raise ValueError('Unit registration collision')
    if args.write:
        text = target.read_text('utf8')
        updated = common.update_enemy_text(text,entry)
        if text!=updated:
            target.write_text(updated,'utf8',newline='\n')
        text = units_path.read_text('utf-8-sig')
        updated = common.update_registration_text(text,unit)
        if text!=updated:
            units_path.write_text(updated,'utf8',newline='\n')
        ledger = json.loads(ledger_path.read_text('utf8'))
        ledger['claims'][LINK] = {'阶段':7,'档次系数':16}
        ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
        receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
    assert common.canonical(E.parse(target).getroot().find(LINK))==common.canonical(entry)
    assert next(r for r in json.loads(units_path.read_text('utf-8-sig')) if r['id']==UNIT_ID)==unit
    assert sum(e.text==PROPERTY_FILE for e in E.parse(ROOT/'data/enemy_properties/list.xml').getroot())==1
    assert json.loads(ledger_path.read_text('utf8'))['claims'][LINK]=={'阶段':7,'档次系数':16}
    assert json.loads(receipt_path.read_text('utf8'))==receipt
    print(json.dumps({'ok':True,'unitId':UNIT_ID,'stage':7,'tier':16,'panel':receipt['integerPanel']},ensure_ascii=False))


if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    main()
