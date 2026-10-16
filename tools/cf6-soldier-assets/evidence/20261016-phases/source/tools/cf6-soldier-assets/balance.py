"""Stage 7 / tier 5 ordinary soldier; preserve all unrelated data byte-for-byte."""
from pathlib import Path
import argparse
import copy
import importlib.util
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LINK = '敌人-CF6特种兵'
DISPLAY_NAME = 'CF6特种兵·二阶段'
UNIT_ID = 466
PROPERTY_FILE = 'CF6重制敌人.xml'
SOURCE = '敌人-大学军校生'
spec = importlib.util.spec_from_file_location('soldier_balance_io', ROOT/'tools/cf6-bladebot-assets/balance.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
common.LINK, common.UNIT_ID = LINK, UNIT_ID


def expected(shield=False):
    link,unit_id = ('敌人-CF6持盾特种兵',467) if shield else (LINK,UNIT_ID)
    display_name = 'CF6特种兵·持盾一阶段' if shield else DISPLAY_NAME
    armor_band = 4 if shield else 2
    census = json.loads((ROOT/'tools/cf7-balance-tool/data/monster-census.json').read_text(encoding='utf-8-sig'))
    tail_factor = census['attackTempoTailFactor']
    # Monster melee coefficients observe only the knife state. Equipped long-gun
    # states are excluded by the rulebook and get power/cadence from item data.
    first, last, total = [14], [14], [34]
    windup = sum(f-1 for f in first)/len(first)
    tail = sum(t-l for t,l in zip(total,last))/len(last)
    weighted = windup+tail*tail_factor
    tempo = next(b['factor'] for b in census['attackTempoBands'] if weighted < b['maxWindupFrames']*(1+tail_factor))
    flags = {'阶段':7,'档次系数':5,'速度系数':2,'攻速系数':tempo,'攻击倍率':1,
        '段数系数':1,'霸体系数':armor_band,'成长系数':1,'高攻低血防系数':1,'高防低血系数':2.2}
    inputs = {common.FLAG_KEYS[key]:value for key,value in flags.items()}
    expression = "import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';console.log(JSON.stringify(computeMonsterRow("+json.dumps(inputs)+")));"
    values = json.loads(subprocess.check_output(['node','tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs','-e',expression],cwd=ROOT,text=True,encoding='utf8'))
    entry = copy.deepcopy(E.parse(ROOT/'data/enemy_properties/大学.xml').getroot().find(SOURCE))
    entry.tag = link
    entry.find('displayname').text = display_name
    for key,value in {'速度_min':50,'速度_max':70,'躲闪率_min':20,'躲闪率_max':10,'重量':75,'韧性系数':5}.items():
        entry.find(key).text = str(value)
    resistance = entry.find('魔法抗性')
    for child in list(resistance):
        resistance.remove(child)
    for key,value in {'人类':20,'装甲':15}.items():
        E.SubElement(resistance,key).text = str(value)
    E.SubElement(entry,'battleRecordAppearance').text = 'fixed'
    for key,value in flags.items():
        entry.find('标识/'+key).text = f'{value:g}'
    for key,formula in common.FIELDS.items():
        entry.find(key).text = str(math.floor(values[formula]+0.5))
    unit = {'id':unit_id,'spritename':link,'level':30,'name':display_name,
        'is_hostile':True,'height':175,'data':{'primary':None,'secondary':None,'secondary2':None,'melee':None}}
    existing = next((r for r in json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
        if r['id']==unit_id),None)
    if existing:
        if existing['spritename']!=link or not isinstance(existing.get('data'),dict):
            raise ValueError('Existing soldier registration has a different owner or invalid equipment data')
        # units.json remains the external equipment authority. Recomputing the
        # monster panel must not erase a user's explicit loadout.
        unit['data'] = copy.deepcopy(existing['data'])
    receipt = {'formula':'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
        'schemaReference':SOURCE,'unitId':unit_id,'linkage':link,'requestedStage':7,'requestedTier':5,
        'fixedByUser':[] if shield else ['阶段','档次系数'],
        'stageTierBasis':'inherits the ordinary unit user baseline' if shield else 'user specified',
        'initialPhase':1 if shield else 2,'phaseParameter':'特种兵初始阶段',
        'secondLifeRatio':0.35 if shield else None,'input':inputs,'flags':flags,
        'integerPanel':{key:int(entry.find(key).text) for key in common.FIELDS},
        'observedBasis':{'rulebook':'tools/cf7-balance-tool/docs/monster-flag-rulebook.md',
            'speedMean':60,'attackFirstHitFrames':first,'attackLastHitFrames':last,'attackTotalFrames':total,
            'windupMean':windup,'tailMean':tail,'tempoTailFactor':tail_factor,'weightedTempo':weighted,
            'tempoThresholdScale':1+tail_factor,'physicalMultipliers':[1],
            'measurementScope':'knife state only; long-gun equipment states excluded by rulebook',
            'meleeSegments':1,'hitRecoveryFrames':[8,7],
            'knockdownAndDownBothDelegate':not shield,'baseArmorBand':armor_band,'tenacity':5,'tenacityDecimal':0,
            'phaseArmorBands':[4,2] if shield else [2],
            'normalImpactUsesRigidGate':shield,
            'phaseOneAuthoredHitRequiresForcedState':shield,
            'knifeCritical':{'chancePercent':10,'multiplier':6,'rawExpectedMultiplier':1.5},
            'knifeExecutePercent':5},
        'scope':'Fixed native body; standard equipment, shared cadet long-gun pool, external units.json data.primary takes priority. Rifle damage and cadence belong to item data; no player inventory is copied.'}
    return entry,unit,receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write',action='store_true')
    args = parser.parse_args()
    target = ROOT/'data/enemy_properties'/PROPERTY_FILE
    units_path = ROOT/'data/units/units.json'
    ledger_path = ROOT/'tools/cf7-balance-tool/data/monster-flag-ledger.json'
    for shield in (False,True):
        entry,unit,receipt = expected(shield)
        link,unit_id = unit['spritename'],unit['id']
        common.LINK,common.UNIT_ID = link,unit_id
        units = json.loads(units_path.read_text(encoding='utf-8-sig'))
        matching = [r for r in units if r['id']==unit_id or r['spritename']==link]
        if len(matching)>1 or any(r['id']!=unit_id or r['spritename']!=link for r in matching):
            raise ValueError('Unit registration collision')
        apply_one(args.write,target,units_path,ledger_path,entry,unit,receipt,shield)


def apply_one(write,target,units_path,ledger_path,entry,unit,receipt,shield):
    link,unit_id = unit['spritename'],unit['id']
    receipt_path = HERE/('shield-balance-inputs.json' if shield else 'balance-inputs.json')
    if write:
        text = target.read_text(encoding='utf8')
        updated = common.update_enemy_text(text,entry)
        if updated!=text:
            target.write_text(updated,encoding='utf8',newline='\n')
        text = units_path.read_text(encoding='utf-8-sig')
        updated = common.update_registration_text(text,unit)
        if updated!=text:
            units_path.write_text(updated,encoding='utf8',newline='\n')
        ledger = json.loads(ledger_path.read_text(encoding='utf8'))
        if not shield:
            ledger['claims'][link] = {'阶段':7,'档次系数':5}
        ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
        receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    assert common.canonical(E.parse(target).getroot().find(link)) == common.canonical(entry)
    assert next(r for r in json.loads(units_path.read_text(encoding='utf-8-sig')) if r['id']==unit_id) == unit
    assert sum(e.text==PROPERTY_FILE for e in E.parse(ROOT/'data/enemy_properties/list.xml').getroot()) == 1
    if not shield:
        assert json.loads(ledger_path.read_text(encoding='utf8'))['claims'][link] == {'阶段':7,'档次系数':5}
    assert json.loads(receipt_path.read_text(encoding='utf8')) == receipt
    print(json.dumps({'ok':True,'unitId':unit_id,'stage':7,'tier':5,'tempo':receipt['flags']['攻速系数'],
        'panel':receipt['integerPanel']},ensure_ascii=False))


if __name__ == '__main__':
    if hasattr(sys.stdout,'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    main()
