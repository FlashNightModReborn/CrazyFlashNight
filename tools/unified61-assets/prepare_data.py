"""Create reviewable five-piece data and crafting inputs without touching live tables."""
from pathlib import Path
import copy
import json
from lxml import etree as E
from sync_copy import load_copy, item_description

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'tmp/unified61-assets'


def sub(parent, name, value=None, **attrs):
    result = E.SubElement(parent, name, {k: str(v) for k, v in attrs.items()})
    if value is not None:
        result.text = str(value)
    return result


def write_xml(path, root):
    path.write_bytes(E.tostring(root, encoding='utf-8', xml_declaration=True, pretty_print=True))


def main():
    design = json.loads((HERE / 'design.json').read_text('utf-8'))
    copy_text = load_copy()
    originals = {e.findtext('name'): e for e in E.parse(str(ROOT / 'data/items/防具_20-39级.xml')).getroot().findall('item')}
    items = E.Element('root')
    recipes = []
    plans = E.Element('records')
    reports = []
    effect_id = 'integrated_system'
    for spec in design['items']:
        old = originals[spec['source']]
        item = sub(items, 'item')
        for name, value in [('name', spec['name']), ('displayname', spec['name']), ('icon', 'Codex-' + spec['name']),
                            ('type', '防具'), ('use', spec['slot']), ('setId', design['setId']), ('price', design['marketPrice']),
                            ('blockedTags', design['blockedTags']), ('allowedModTags', design['allowedModTags']),
                            ('inherentTags', design['inherentTags'])]:
            sub(item, name, value)
        sub(item, 'description', item_description(copy_text['items'][spec['name']]))
        if spec['slot'] == '头部装备':
            sub(item, 'helmet', 'true')
        if spec['slot'] == '上装装备':
            sub(item, 'skill', '【喷气背包】保留原装升空机构，停止喷气时自动充气，按飞行键使用。')
        data = sub(item, 'data')
        sub(data, 'modslot', 1)
        sub(data, 'level', design['level'])
        sub(data, 'weight', spec['weight'])
        sub(data, 'dressup', old.findtext('data/dressup').replace('61式', 'Codex-统合61式'))
        for key in ('hp', 'mp', 'damage', 'defence'):
            sub(data, key, spec[key])
        lifecycle = sub(item, 'lifecycle')
        attr = sub(lifecycle, 'attr_统合61')
        sub(attr, 'skillInteraction', 'independent')
        gate = sub(attr, 'setGate')
        sub(gate, 'effectId', effect_id)
        sub(gate, 'componentId', spec['component'])
        init = sub(attr, 'init')
        sub(init, 'initRoutines', '统合61组件初始化')
        params = sub(init, 'initParam')
        if spec['slot'] == '上装装备':
            for key, value in design['config'].items():
                sub(params, key, value)
            cycle = sub(attr, 'cycle')
            sub(cycle, 'cycleRoutines', '统合61组件周期')
            bullet = sub(sub(attr, 'bullet'), 'bullet_0')
            for key, value in {'power': 0, 'bullet': '纵向联弹-穿刺子弹', 'split': 12, 'diffusion': 5,
                               'velocity': 32, 'sound': 'ak47.wav', 'muzzle': '冲锋枪枪火', 'bullethit': '火花',
                               'range': 30, 'impact': 10, 'knockback': 0, 'damagetype': '魔法', 'magictype': '热',
                               'bulletsize': 100}.items():
                sub(bullet, key, value)
            for original_attr in old.find('lifecycle'):
                lifecycle.append(copy.deepcopy(original_attr))
        suffix = spec['component'].split('_')[0]
        recipe_id = 'craft.unified61.' + suffix
        materials = [spec['source'] + '#1', '高耐力橡胶#2', '传感器#2']
        if spec['slot'] == '头部装备':
            materials.append('红外夜视仪#1')
        recipes.append({'recipeId': recipe_id, 'title': spec['name'] + '全装恢复图纸', 'name': spec['name'],
                        'price': design['craftGold'], 'kprice': design['craftKpoints'], 'materials': materials})
        evidence = 'data/crafting/进阶防具.json#' + recipe_id
        plan = sub(plans, 'record', itemName=spec['name'], sourceFile='data/items/防具_40+级.xml',
                   weightLayers=3, priceLayers=1, category=1, damageTypeFactor=1, adoptedGoldPrice=design['marketPrice'],
                   expectedKPointPrice=design['craftKpoints'], kpointEvidenceRef=evidence, status='confirmed',
                   note='40级三加权候选：合成1+配方K点成本1+高价1；90kg整套，限制插件，不额外计40级浮动或减益层。公式通过不代表实战定档。')
        budget = sub(plan, 'budgetBreakdown')
        for code in ('acquisition.crafting', 'acquisition.kpoint-cost', 'acquisition.high-price'):
            sub(budget, 'entry', code=code, delta=1, ruleRef='ABR-LAYER-001', evidenceRef=evidence)
        score = spec['hp'] + spec['mp'] + 3*spec['damage'] + 2*spec['defence']
        allowed = (design['level']*20 + spec['weight']*10)*1.25**3
        assert abs(score/allowed-1) <= .05
        reports.append({'item': spec['name'], 'score': score, 'budget': allowed, 'ratio': score/allowed})

    sets = E.Element('itemSets')
    definition = sub(sets, 'set')
    for key, value in [('id', design['setId']), ('name', design['setName']), ('order', 365),
                       ('description', copy_text['setDescription'])]:
        sub(definition, key, value)
    effect = sub(sub(definition, 'effects'), 'effect_0')
    for key, value in [('id', effect_id), ('threshold', 5), ('activationGroup', 'unified_type_61_full_set'),
                       ('kind', 'routine'), ('mode', 'member_components'), ('prepareRoutine', '统合61套装准备')]:
        sub(effect, key, value)
    components = sub(effect, 'components')
    for index, spec in enumerate(design['items']):
        component = sub(components, 'component_' + str(index))
        sub(component, 'id', spec['component'])
        sub(component, 'slot', spec['slot'])
    names = sub(effect, 'authorizedWeapons')
    for name in design['authorizedWeapons']:
        sub(names, 'weapon', name)
    sub(effect, 'description', copy_text['effectDescription'])
    OUT.mkdir(parents=True, exist_ok=True)
    write_xml(OUT / 'items.xml', items)
    write_xml(OUT / 'item_sets.xml', sets)
    write_xml(OUT / 'armor-plan.xml', plans)
    (OUT / 'crafting.json').write_text(json.dumps(recipes, ensure_ascii=False, indent=2), encoding='utf-8')
    (OUT / 'budget.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'items': len(reports), 'totalWeight': sum(i['weight'] for i in design['items']),
                      'score': sum(r['score'] for r in reports), 'budget': sum(r['budget'] for r in reports),
                      'liveTablesChanged': False}, ensure_ascii=False))


if __name__ == '__main__':
    main()
