"""Recompute a fixed-allowance procurement bound from current, reachable channels.
No enemy drops, resale, random plugin discounts or unearned blood sword are credited.
"""
import argparse,collections,hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from choice_reward_catalog import item_catalog
from cf6_acquisition import channels,route_plan,sources,registries

def report(through_node=None, enhancements=None, primaries=None, purchase_node=None):
    source=json.loads((ROOT/'tools/cf6-type61/route.source.json').read_text('utf-8'))
    purchase_node=through_node if purchase_node is None else purchase_node
    if through_node and purchase_node<through_node:raise ValueError('Purchase cannot precede its credited resources')
    items=item_catalog();gold,kshop,recipes=channels();plan=route_plan(source,items)
    for row in json.loads((ROOT/'tools/cf6-type61/recipes.generated.json').read_text('utf-8')):
        recipes[row['name']]=[dict(row,category='书中配给')]
    source_stock=collections.Counter(e['name'] for e in source['actor']['equipment'])
    for node,rows in source['materialDeliveries'].items():
        if through_node is not None and node>through_node:continue
        for row in rows:source_stock[row['name']]+=row['count']
    # One initial medium mod can be alloy; the other random plugin rewards are not budgeted.
    source_stock['高强度合金']+=1
    source_stock['战术鱼骨零件']+=1
    checkpoints=[x for x in source['checkpoints'] if through_node is None or x['mapId']<=through_node]
    cash=source['startingMoney']+sum(x['money'] for x in checkpoints)
    fixed_k=sum(x['kpoints'] for x in checkpoints)
    fixed_stones=sum(x['stones'] for x in checkpoints)+2
    per_piece=sum((19*(i-1)**3)//20+1 for i in range(1,11))
    enhancements=[11]*10 if enhancements is None else enhancements
    if len(enhancements)!=10 or any(type(x)!=int or not 1<=x<=11 for x in enhancements):raise ValueError('Invalid ten-slot enhancement plan')
    stone_need=sum(sum((19*(i-1)**3)//20+1 for i in range(1,target)) for target in enhancements)
    results=[]
    for primary in (['M134','M134暴力版','钛合金QJZ171'] if primaries is None else primaries):
        stock=source_stock.copy();cost={'gold':0,'K':0};steps=[]
        def buy(name,count=1):
            used=min(count,stock[name]);stock[name]-=used;count-=used
            for _ in range(count):
                # Final titanium uses the route-specific consuming upgrade, never the global K shop.
                if name.startswith('钛合金61式') or name.startswith('统合61式'):
                    row=recipes[name][0];method='craft'
                elif name in plan['cash'] or name in gold:
                    if purchase_node and (name not in plan['cash'] or plan['cash'][name]>purchase_node):raise ValueError('Cash purchase unavailable at checkpoint: '+name)
                    cost['gold']+=int(items[name].findtext('price'));steps.append({'item':name,'via':'gold','gold':int(items[name].findtext('price'))});continue
                elif name in plan['kpoints']:
                    if purchase_node and plan['kpoints'][name]>purchase_node:raise ValueError('K purchase unavailable at checkpoint: '+name)
                    price=min(x['price'] for x in kshop[name]);cost['K']+=price;steps.append({'item':name,'via':'K','K':price});continue
                elif name in recipes:
                    available=[x for x in recipes[name] if x['recipeId'] in plan['recipes'] or x['recipeId'] in config['recipeUnlocks']]
                    if not available:raise ValueError('Recipe locked: '+name)
                    row=available[0];method='craft'
                else:raise ValueError('No deterministic procurement: '+name)
                if purchase_node and config['recipeUnlocks'].get(row['recipeId'],'ZZ')>purchase_node:raise ValueError('Craft unavailable at checkpoint: '+name)
                for material in row['materials']:
                    bits=material.split('#');buy(bits[0],int(bits[-1]))
                g=int(row['price'])*95//100;k=int(row['kprice'])*95//100
                cost['gold']+=g;cost['K']+=k;steps.append({'item':name,'via':method,'recipeId':row['recipeId'],'gold':g,'K':k})
        config=json.loads((ROOT/'data/stages/books/cf6-type61.json').read_text('utf-8'))['type61']
        for e in source['actor']['equipment']:
            if e['name'].startswith('61式'):buy('钛合金'+e['name'])
        buy(primary);buy('钛合金P90',2)
        # The old gun-specific mod baseline is retained. Ordinary M134 uses its own open configuration.
        primary_mods=['战术鱼骨零件','水冷机构','纳米执行单元'] if primary in ('钛合金QJZ171','M134') else ['水冷机构']
        for name in primary_mods:buy(name)
        buy('黑爪扩张弹',2);buy('高强度合金')
        missing_k=max(0,cost['K']-fixed_k);spare_k=max(0,fixed_k-cost['K'])
        missing_stones=max(0,stone_need-fixed_stones)
        k_stones=min(missing_stones,spare_k//50)
        stones_gold=(missing_stones-k_stones)*int(items['强化石'].findtext('price'))
        conversion=missing_k*int(items['K点'].findtext('price'));reserve=150000
        total=cost['gold']+conversion+stones_gold+reserve
        results.append(dict(primary=primary,baseProcurement=cost,steps=steps,primaryMods=primary_mods,
            piecesAt11=enhancements.count(11),enhancementPlan=enhancements,requiredStones=stone_need,
            stonesPerPiece=per_piece,missingStones=missing_stones,kForMissingCurrency=missing_k,
            goldForMissingK=conversion,goldForStones=stones_gold,reserve=reserve,totalGoldAfterFixedK=total,
            fixedGold=cash,fixedK=fixed_k,balanceBeforeDropsAndSales=cash-total))
    inputs=set(sources()) | set(registries()) | {Path(__file__),ROOT/'tools/cf6_acquisition.py',ROOT/'tools/cf6-type61/route.source.json',ROOT/'tools/cf6-type61/recipes.generated.json',ROOT/'data/stages/books/cf6-type61.json'}
    inputs.update(ROOT/'data/items'/x.text for x in __import__('xml.etree.ElementTree',fromlist=['ElementTree']).parse(ROOT/'data/items/list.xml').findall('items'))
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs) if p.is_file()}
    return dict(sourceHashes=hashes,schema='cf6-acquisition-budget.v1',throughNode=through_node,purchaseNode=purchase_node,
        scope='Static fixed-allowance procurement bound for the explicit ten-slot enhancement plan, including necklace. No survival, full-run or blood-sword guarantee.',
        assumptions=['Original gold/K/crafting channels; smith1 remains enabled','No sales, death gold/K, random high-mod rewards or optional drop materials credited',
        'One usable initial ordinary constellation is free; this model does not assume the rare blood sword',
        'Current procurement list and per-item fees only; not a timing or damage simulation'],routes=results)

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    dest=ROOT/'tools/cf6-type61/acquisition-budget.generated.json';body=(json.dumps(report(),ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if not dest.exists() or dest.read_bytes()!=body:raise SystemExit('stale acquisition budget')
    else:dest.write_bytes(body)
    for row in report()['routes']:print(row['primary'],row['baseProcurement'],'fixed-only balance',row['balanceBeforeDropsAndSales'])
if __name__=='__main__':main()
