"""Reproducible static encounter and procurement scenarios, not an AVM1 playthrough."""
import argparse
import collections
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random
import sys
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from cf6_economy import enemies
from choice_reward_catalog import item_catalog
from encounters import ROLES
from unit_registry import UnitRegistry


def report():
    registry=UnitRegistry.load(ROOT)
    book_path=ROOT/'data/stages/books/cf6-type61.json'
    book=json.loads(book_path.read_text('utf-8'))
    units_path=ROOT/'data/units/units.json'
    units={row['id']:row for row in json.loads(units_path.read_text('utf-8-sig'))}
    properties={}
    prop_paths=sorted((ROOT/'data/enemy_properties').glob('*.xml'))
    for path in prop_paths:
        for row in ET.parse(path).getroot():properties[row.tag]=row
    ledger=[];income_enemies=[];level=35
    for stage in book['maps']:
        role_counts=collections.Counter();count=0;hp_sum=0
        for enemy in enemies(stage):
            unit=registry.resolve_id(enemy['Type']);p=enemy.get('Parameters',{})
            row=properties[units[unit]['spritename']]
            low=float(p.get('hp_min',row.findtext('hp_min')))
            high=float(p.get('hp_max',row.findtext('hp_max')))
            hp=math.floor(low+(high-low)/59*enemy['Level'])*p.get('cf6DifficultyScale',1)
            quantity=enemy['Quantity'];count+=quantity;hp_sum+=hp*quantity
            if unit in ROLES:role_counts[ROLES[unit]]+=quantity
            if not p.get('不掉钱',False):income_enemies.extend([(hp,level)]*quantity)
        ledger.append(dict(map=stage['id'],authoredEnemies=count,hp=hp_sum,soldiers=dict(role_counts)))
        checkpoint=next((r for r in book['type61']['checkpoints'] if r['mapId']==stage['id']),None)
        if checkpoint:level=checkpoint['level']
    items=item_catalog();sale_rows=[]
    for kind in ('randomWeapons','eliteWeapons'):
        for row in book['economy'][kind]:
            values=[int(items[o['weapon']].findtext('price'))//4*o.get('weaponCount',1) for o in row['choices']]
            sale_rows.append(dict(map=row['mapId'],source=row.get('quota','random'),minimum=min(values),maximum=max(values)))
    sales_min=sum(r['minimum'] for r in sale_rows);sales_max=sum(r['maximum'] for r in sale_rows)
    # Same probability and integer amount rules, independent reproducible RNG samples.
    # No assertion that Python's sequence reproduces Flash's random engine.
    rng=random.Random(20261028);samples=[]
    for _ in range(5000):
        gold=kpoints=0
        for hp,actor_level in income_enemies:
            if rng.randrange(6):continue
            value=rng.randrange(max(1,math.floor(hp/5)))+1
            is_k=rng.randrange(6)==0
            if value<10:value+=10
            cap=50+actor_level*actor_level*10 if is_k else 50+actor_level*3000
            if value>cap:value=cap+rng.randrange(max(1,math.floor((value-cap)/(100 if is_k else 5))))
            if is_k:kpoints+=value
            else:gold+=value
        samples.append((gold,kpoints))
    def percentiles(values):
        values=sorted(values)
        return {label:round(values[round((len(values)-1)*p)],2) for label,p in [('p10',.1),('median',.5),('p90',.9)]}
    spec=importlib.util.spec_from_file_location('acquisition_budget',HERE/'acquisition-budget.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    procurement=module.report();routes=[]
    milestones=[]
    for node,shop,encounter,enhancements in [('A10','A11','A13',[7]*10),('A16','A16','A17',[11]*5+[9]*5)]:
        budget=module.report(through_node=node,purchase_node=shop,enhancements=enhancements,primaries=['M134'])['routes'][0]
        if budget['balanceBeforeDropsAndSales']<0:raise ValueError('Defense funding arrives after encounter: '+encounter)
        if book['type61']['titaniumUpgrade']['unlockNode']>shop:raise ValueError('Titanium workbench opens after defense checkpoint')
        milestones.append(dict(fundedBy=node,purchaseAt=shop,beforeEncounter=encounter,requiresClearingFundingMap=True,
            shoppingBeforeClearingPurchaseMap=node<shop,build='Five titanium61 armor pieces, M134, two titanium P90s, ordinary constellation, starting necklace and budgeted plugins',budget=budget))
    for row in procurement['routes']:
        def balance(gold,kpoints,sales):
            k=row['fixedK']+kpoints;cost=row['baseProcurement']
            missing_k=max(0,cost['K']-k);spare_k=max(0,k-cost['K'])
            stones=max(0,row['missingStones']-spare_k//50)
            expense=cost['gold']+missing_k*int(items['K点'].findtext('price'))+stones*int(items['强化石'].findtext('price'))+row['reserve']
            return row['fixedGold']+gold+sales-expense
        routes.append(dict(primary=row['primary'],fixedOnly=row['balanceBeforeDropsAndSales'],
            afterMinimumFiniteSales=balance(0,0,sales_min),
            deathScenarioWithMinimumFiniteSales=percentiles([balance(g,k,sales_min) for g,k in samples]),
            deathScenarioWithoutSales=percentiles([balance(g,k,0) for g,k in samples])))
    paths=[Path(__file__),HERE/'encounters.py',HERE/'encounters.source.json',HERE/'route.source.json',HERE/'acquisition-budget.py',
        book_path,units_path,ROOT/'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
        ROOT/'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as',
        ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/PickUp/PickUpManager.as']+prop_paths
    return dict(schema='cf6-type61-encounter-budget.v1',scope='Static authored enemies and terminal procurement scenarios; no survival or timing guarantee.',
        assumptions=['All authored waves and finite boss support groups cleared and all modeled money picked up; weather multiplier 1, ordinary mode, default 1/6 money chance.',
            'Native transformations, incidental equipment drops, random plugin savings, throwable resale and rare blood sword are excluded.',
            'Finite-sale scenario liquidates one earned result per existing random/elite weapon quota at base price / 4; keeps starter, ordinary constellation, armor and purchased graduation equipment.',
            'A04 replacement and duplicate avoidance cannot reduce the original result sale value. 5000 independent Python RNG scenarios are a statistical reference, not AVM1 behavioral proof.',
            'Balances include ten pieces at +11 and the existing 150000 reserve; positive end balance does not prove earlier purchases are affordable.'],
        sourceHashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
        defenseMilestones=milestones,maps=ledger,totalAuthoredEnemies=sum(r['authoredEnemies'] for r in ledger),totalAuthoredHp=sum(r['hp'] for r in ledger),
        finiteWeaponSales=dict(minimum=sales_min,maximum=sales_max,rows=sale_rows),
        deathIncome=dict(gold=percentiles([r[0] for r in samples]),kpoints=percentiles([r[1] for r in samples])),routes=routes)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    data=report();body=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf-8');dest=HERE/'encounter-budget.generated.json'
    if args.check:
        if not dest.is_file() or dest.read_bytes()!=body:raise SystemExit('Stale encounter budget')
    else:dest.write_bytes(body)
    print(json.dumps({k:data[k] for k in ('totalAuthoredEnemies','deathIncome','routes')},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
