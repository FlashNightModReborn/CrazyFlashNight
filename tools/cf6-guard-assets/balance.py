"""User-fixed stage 6 / tier 3, with timing and pellet coefficients from the action."""
from pathlib import Path
import argparse
import copy
import importlib.util
import json
import math
import re
import subprocess
import sys
import xml.etree.ElementTree as E

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
LINK='敌人-CF6光头保安'
DISPLAY_NAME='CF6光头保安·普通型'
TRANSFORM_LINK='敌人-CF6变身光头保安'
UNIT_ID=468
PROPERTY_FILE='CF6重制敌人.xml'
SOURCE='敌人-大学军校生'
spec=importlib.util.spec_from_file_location('guard_balance_io',ROOT/'tools/cf6-bladebot-assets/balance.py')
common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
common.LINK,common.UNIT_ID=LINK,UNIT_ID


def expected(transform=False):
    link=TRANSFORM_LINK if transform else LINK
    unit_id=469 if transform else UNIT_ID
    display_name='CF6光头保安·变身型' if transform else DISPLAY_NAME
    census=json.loads((ROOT/'tools/cf7-balance-tool/data/monster-census.json').read_text('utf-8-sig'))
    tail_factor=census['attackTempoTailFactor']
    weighted=40+33*tail_factor
    tempo=next(b['factor'] for b in census['attackTempoBands'] if weighted<b['maxWindupFrames']*(1+tail_factor))
    pellet_values=re.findall(r'\bpellets\s*:\s*(\d+)',(HERE/'GuardAI.as').read_text('utf-8-sig'))
    assert len(pellet_values)==1 and 0<int(pellet_values[0])<=32
    pellets=int(pellet_values[0])
    pierce_factor=census['pierceSegmentRules']['pierceFactor']
    flags={'阶段':6,'档次系数':3,'成长系数':1,'攻速系数':tempo,'攻击倍率':1,
        '段数系数':pellets*pierce_factor,'速度系数':2,'高攻低血防系数':1,'霸体系数':2,'高防低血系数':1}
    inputs={common.FLAG_KEYS[k]:v for k,v in flags.items()}
    expression="import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';console.log(JSON.stringify(computeMonsterRow("+json.dumps(inputs)+")));"
    values=json.loads(subprocess.check_output(['node','tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs','-e',expression],cwd=ROOT,text=True,encoding='utf8'))
    entry=copy.deepcopy(E.parse(ROOT/'data/enemy_properties/大学.xml').getroot().find(SOURCE))
    entry.tag=link;entry.find('displayname').text=display_name
    for k,v in {'速度_min':50,'速度_max':60,'躲闪率_min':20,'躲闪率_max':10,'重量':80,'韧性系数':5}.items():
        entry.find(k).text=str(v)
    resistance=entry.find('魔法抗性')
    for child in list(resistance):resistance.remove(child)
    E.SubElement(resistance,'人类').text='20'
    E.SubElement(entry,'battleRecordAppearance').text='fixed'
    for k,v in flags.items():entry.find('标识/'+k).text=f'{v:g}'
    for k,formula in common.FIELDS.items():entry.find(k).text=str(math.floor(values[formula]+0.5))
    unit={'id':unit_id,'spritename':link,'level':30,'name':display_name,'is_hostile':True,'height':175,
        'data':{'primary':None,'secondary':None,'secondary2':None,'melee':None}}
    receipt={'formula':'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
        'schemaReference':SOURCE,'unitId':unit_id,'linkage':link,'defaultTransform':transform,'phaseParameter':'光头保安变身','requestedStage':6,'requestedTier':3,
        'fixedByUser':['阶段','档次系数'],'input':inputs,'flags':flags,
        'integerPanel':{k:int(entry.find(k).text) for k in common.FIELDS},
        'balanceTarget':'Clearly below the ordinary soldier, but at least 20 percent net HP exchange in qualified comparison samples',
        'observedBasis':{'rulebook':'tools/cf7-balance-tool/docs/monster-flag-rulebook.md',
            'speedMean':55,'attackFirstHitFrames':[41],'attackLastHitFrames':[41],'attackTotalFrames':[74],
            'windupMean':40,'tailMean':33,'tempoTailFactor':tail_factor,'weightedTempo':weighted,
            'tempoThresholdScale':1+tail_factor,'physicalMultipliers':[1],'pellets':pellets,
            'bulletKind':'穿刺子弹','pierceFactor':pierce_factor,'effectiveSegments':pellets*pierce_factor,
            'measurementScope':'fixed shotgun in the empty-hand attack state; monster panel owns damage',
            'hitRecoveryFrames':[8,7],'knockdownAndDownBothDelegate':True,
            'baseArmorBand':2,'tenacity':5,'tenacityDecimal':0,
            'temporaryWindupStance':{'frames':[1,41],'endsImmediatelyAfterShot':True,'damageReduction':0},
            'temporaryAttackGuardDoesNotChangeArmorBand':True},
        'pelletReference':'CF6 original guard timeline uses three pellets. Fixed SPAS12 is native artwork only; enemy damage uses the monster formula.',
        'scope':'First-life humanoid panel only. Three piercing pellets, no equipment bonuses, critical or shield buff. Second life uses existing unit 460 at inherited level with fresh combat state.'}
    return entry,unit,receipt


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
    for transform in (False,True):
        entry,unit,receipt=expected(transform)
        link,unit_id=unit['spritename'],unit['id']
        common.LINK,common.UNIT_ID=link,unit_id
        receipt_path=HERE/('transform-balance-inputs.json' if transform else 'balance-inputs.json')
        target=ROOT/'data/enemy_properties'/PROPERTY_FILE
        units_path=ROOT/'data/units/units.json'
        ledger_path=ROOT/'tools/cf7-balance-tool/data/monster-flag-ledger.json'
        units=json.loads(units_path.read_text('utf-8-sig'))
        matching=[r for r in units if r['id']==unit_id or r['spritename']==link]
        if len(matching)>1 or any(r['id']!=unit_id or r['spritename']!=link for r in matching):
            raise ValueError('Unit registration collision')
        if args.write:
            text=target.read_text('utf8');updated=common.update_enemy_text(text,entry)
            if text!=updated:target.write_text(updated,'utf8',newline='\n')
            text=units_path.read_text('utf-8-sig');updated=common.update_registration_text(text,unit)
            if text!=updated:units_path.write_text(updated,'utf8',newline='\n')
            ledger=json.loads(ledger_path.read_text('utf8'));ledger['claims'][link]={'阶段':6,'档次系数':3}
            ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
            receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n','utf8',newline='\n')
        assert common.canonical(E.parse(target).getroot().find(link))==common.canonical(entry)
        assert next(r for r in json.loads(units_path.read_text('utf-8-sig')) if r['id']==unit_id)==unit
        assert sum(e.text==PROPERTY_FILE for e in E.parse(ROOT/'data/enemy_properties/list.xml').getroot())==1
        assert json.loads(ledger_path.read_text('utf8'))['claims'][link]=={'阶段':6,'档次系数':3}
        assert json.loads(receipt_path.read_text('utf8'))==receipt
        print(json.dumps({'ok':True,'unitId':unit_id,'stage':6,'tier':3,'tempo':receipt['flags']['攻速系数'],
            'panel':receipt['integerPanel']},ensure_ascii=False))

if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf8')
    main()
