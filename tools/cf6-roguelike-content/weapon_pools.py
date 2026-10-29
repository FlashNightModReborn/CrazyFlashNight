"""Explicit CF6 report whitelist, resolved against live item/tier XML. No random or save authority."""
from pathlib import Path
import copy
import xml.etree.ElementTree as ET
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from choice_reward_catalog import item_catalog

SOURCE = Path(__file__).with_name('weapon-pools.source.json')


def weapon_data(option, items):
    """Resolve an authored instance using the same registered tier key as EquipmentConfigManager."""
    weapon = items.get(option['weapon'])
    if weapon is None or weapon.findtext('type') != '武器':
        raise ValueError('choice weapon is not a real weapon')
    data = copy.deepcopy(weapon.find('data'))
    if 'weaponTier' in option:
        if weapon.findtext('use') not in ('长枪', '手枪'):
            raise ValueError('direct tier loadout requires a gun slot')
        tier = option['weaponTier']
        mapping = {e.get('name'): e.get('key') for e in ET.parse(ROOT / 'data/equipment/equipment_config.xml').findall('.//TierMapping')}
        if type(tier) is not str or tier not in mapping or weapon.find(mapping[tier]) is None:
            raise ValueError('weapon does not support the requested tier')
        for field in weapon.find(mapping[tier]):
            old = data.find(field.tag)
            if old is not None: data.remove(old)
            data.append(copy.deepcopy(field))
    return weapon, data


def source():
    value = json.loads(SOURCE.read_text('utf-8'))
    if value['schema'] != 'cf6-weapon-pools.v1' or len(value['weapons']) != len(set(value['weapons'])):
        raise ValueError('invalid CF6 weapon whitelist')
    return value


def instances(excluded=()):
    config, items = source(), item_catalog()
    result = []
    for name in config['weapons']:
        if name not in items or name in config['excluded']:
            raise ValueError('unknown/excluded CF6 whitelist item: ' + name)
        item = items[name]
        if item.findtext('type') != '武器' or item.findtext('use') not in ('长枪', '手枪'):
            continue
        for tier in [None] + config['tierNames']:
            option = {'weapon': name}
            if tier is not None: option['weaponTier'] = tier
            try: _, data = weapon_data(option, items)
            except ValueError:
                if tier is None: raise
                continue
            level = int(data.findtext('level', '999'))
            ammo = data.findtext('clipname')
            if not config['baseLevelMinimum'] <= level <= config['maxLevel']: continue
            if ammo not in items or items[ammo].findtext('use') != '弹夹':
                raise ValueError('CF6 gun form has no usable ammunition: ' + name)
            if name in excluded: continue
            option.update(level=level, ammo=ammo, weaponCount=2 if item.findtext('use') == '手枪' else 1)
            result.append(option)
    return result


def historical_instances(excluded=()):
    config, items = source(), item_catalog()
    policy = config['historicalPolicy']
    if policy['selection'] != 'strict-historical' or policy['allowedTierNames']:
        raise ValueError('CF6 historical delivery requires its explicit period whitelist')
    result = []
    for name in policy['acceptedWeaponNames']:
        if name in excluded or name in policy.get('kOnlyWeaponNames',[]): continue
        weapon, data = weapon_data({'weapon':name}, items)
        if weapon.findtext('use') not in ('长枪','手枪'): raise ValueError('historical gun whitelist contains another slot')
        level = int(data.findtext('level','999'))
        if not config['baseLevelMinimum'] <= level <= config['maxLevel']: continue
        ammo = data.findtext('clipname')
        if ammo not in items or items[ammo].findtext('use') != '弹夹': raise ValueError('historical gun lacks matching ammunition')
        result.append(dict(weapon=name,level=level,ammo=ammo,weaponCount=2 if weapon.findtext('use')=='手枪' else 1))
    return result


def random_pools(excluded):
    rows = historical_instances(excluded)
    return {mid: [r['weapon'] for r in rows if max(35, cap - 15) <= r['level'] <= cap]
            for mid, cap in source()['randomMapLevels'].items()}


def gun_bundles(excluded):
    bundles, levels = [], {}
    for row in historical_instances(excluded):
        label = (row.get('weaponTier', '') + '·' if row.get('weaponTier') else '') + row['weapon']
        identity = row['weapon'] + '#' + row.get('weaponTier', '')
        bid = 'cf6.sting.weapon.' + hashlib.sha256(identity.encode()).hexdigest()[:12]
        bundle = dict(id=bid, name=label + '装载', title=label,
                      description=('双持两把，' if row['weaponCount'] == 2 else '一把，') + '附配套弹药与急救。',
                      grade='high' if row['level'] >= 50 else 'medium', weapon=row['weapon'],
                      weaponCount=row['weaponCount'], mods=[],
                      consumables=[dict(name=row['ammo'], count=12 if row['weaponCount'] == 2 else 6),dict(name='普通hp药剂',count=2)])
        if 'weaponTier' in row: bundle['weaponTier'] = row['weaponTier']
        bundles.append(bundle); levels[bid] = row['level']
    return bundles, levels


def audit():
    rows = instances()
    items = item_catalog()
    evidence = {name: dict(type=items[name].findtext('type'), use=items[name].findtext('use'),
                          baseLevel=items[name].findtext('data/level'),
                          currentDescription=items[name].findtext('description', ''),
                          xmlSource=source()['historyEvidence'][name]['xmlSource'],
                          report=source()['historyEvidence'][name]) for name in source()['weapons']}
    return {'schema': 'cf6-weapon-pools-audit.v1', 'source': source(), 'currentItemEvidence': evidence,
            'liveInstances': rows, 'historicalInstances': historical_instances(), 'baseCount': sum('weaponTier' not in r for r in rows),
            'tierCount': sum('weaponTier' in r for r in rows),
            'limitation': 'Source/XML audit only; no compilation, delivery or gameplay acceptance.'}


if __name__ == '__main__':
    print(json.dumps(audit(), ensure_ascii=False, indent=2))
