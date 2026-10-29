"""CF6 acquisition channels from existing non-book stores and crafting sources.
A catalog's sale value is not permission to make a weapon a cash purchase.
"""
import json
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def registries():
    return [ROOT/'data/shops/list.xml',ROOT/'data/kshop/list.xml',ROOT/'data/crafting/list.xml']
def sources():
    result=[]
    for directory,tag,extension in [('shops','shops',''),('kshop','kshop',''),('crafting','list','.json')]:
        base=ROOT/'data'/directory
        for entry in ET.parse(base/'list.xml').findall(tag):
            path=base/(entry.text+extension)
            if path.stem.startswith('书中-') or path.stem=='书中配给':continue
            if not path.is_file():raise ValueError('Registered acquisition source missing: '+str(path))
            result.append(path)
    return sorted(result)
def channels():
    gold, kpoints, recipes = {}, {}, {}
    for p in sources():
        data=json.loads(p.read_text('utf-8-sig'))
        if p.parent.name == 'npcs':
            for row in data.get('catalog',{}).values():
                # Conditional NPC stock does not prove an unconditional purchase.
                name=row if isinstance(row,str) else row.get('name') if isinstance(row,dict) and set(row)=={'name'} else None
                if name:gold.setdefault(name,[]).append(p.relative_to(ROOT).as_posix())
        elif p.parent.name == 'kshop':
            for row in data:kpoints.setdefault(row['item'],[]).append(dict(price=int(row['price']),source=p.relative_to(ROOT).as_posix()))
        else:
            for row in data:
                if isinstance(row,dict) and 'name' in row:
                    recipes.setdefault(row['name'],[]).append(dict(row,category=p.stem))
    return gold,kpoints,recipes

def route_plan(source, items):
    gold,kpoints,recipes=channels()
    cash={}; kunlocks={}; runlocks={}; handled={}; unresolved={}
    def add_cash(name,node):
        if name not in cash or node<cash[name]:cash[name]=node
    def visit(name,node,stack=()):
        if name not in items:raise ValueError('Unknown acquisition item: '+name)
        if name in stack:raise ValueError('Cyclic acquisition recipe: '+name)
        if name in handled and handled[name]<=node:return
        handled[name]=node
        weapon=items[name].findtext('type')=='武器'
        rows=recipes.get(name,[])
        if name in gold or (not weapon and not rows and name not in kpoints):add_cash(name,node)
        if name in kpoints and (name not in kunlocks or node<kunlocks[name]):kunlocks[name]=node
        for row in rows:
            rid=row['recipeId']
            if rid not in runlocks or node<runlocks[rid]:runlocks[rid]=node
            for material in row['materials']:visit(material.split('#')[0],node,stack+(name,))
        if weapon and name not in gold and name not in kpoints and not rows:
            unresolved[name]='finite authored rewards only; no gold/K/crafting shortcut'
    a=source['acquisition']
    for name,node in a['weaponNodes'].items():visit(name,node)
    for node,names in a['pluginNodes'].items():
        for name in names:visit(name,node)
    for node,names in a['necklaceNodes'].items():
        for name in names:visit(name,node)
    for name in ['强化石']+source['ammoCatalog']:
        if name in kpoints:kunlocks[name]='A01'
    # Plugin recipes are available with their original inputs and cost, not as cheap cash outputs.
    return dict(cash=cash,kpoints=kunlocks,recipes=runlocks,finiteOnly=unresolved)
