"""Authoring contract for weighted, grouped player-choice reward bundles."""
from pathlib import Path
import copy
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/rewards/choice-rewards.json'
ID = re.compile(r'[a-z][a-z0-9.-]{0,63}\Z')


def integer(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise ValueError('invalid ' + label)


def exact(value, keys, label):
    if type(value) is not dict or set(value) != set(keys.split()):
        raise ValueError('invalid fields in ' + label)


def words(element, key):
    return {v.strip() for v in element.findtext(key, '').split(',') if v.strip()}


def item_catalog():
    result = {}
    for entry in ET.parse(ROOT / 'data/items/list.xml').findall('items'):
        path = ROOT / 'data/items' / entry.text
        if path.is_file():
            result.update((item.findtext('name'), item) for item in ET.parse(path).findall('item'))
    return result


def validate_loadout(option, ceiling, items, mods):
    weapon = items.get(option['weapon'])
    if weapon is None or weapon.findtext('type') != '武器' or not 1 <= int(weapon.findtext('data/level', '999')) <= ceiling:
        raise ValueError('choice weapon exceeds its pool level')
    count = option.get('weaponCount', 1)
    integer(count, 1, 2, 'loadout weapon count')
    if count != (2 if weapon.findtext('use') == '手枪' else 1):
        raise ValueError('short-gun loadouts require two weapons; other slots require one')
    tags, occupied = words(weapon, 'inherentTags'), set()
    ammo = {weapon.findtext('data/clipname')} - {None, ''}
    # ItemUtil.getDefaultModSlot supplies this field when the XML omits it.
    level = int(weapon.findtext('data/level'))
    capacity = int(weapon.findtext('data/modslot', str(3 if level < 12 else 2 if level < 30 else 1)))
    if type(option['mods']) is not list or len(option['mods']) > 4 or len(set(option['mods'])) != len(option['mods']):
        raise ValueError('invalid bundle mods')
    for name in option['mods']:
        mod = mods.get(name)
        if mod is None or name not in items: raise ValueError('unknown bundle mod')
        kind, tag = weapon.get('weapontype', ''), mod.findtext('tag')
        allowed = words(mod, 'weapontype')
        # EquipmentUtil filters weapon subtypes only for the two gun slots.
        gun = weapon.findtext('use') in ('手枪', '长枪')
        if (weapon.findtext('use') not in words(mod, 'use')
                or (gun and ((allowed and kind not in allowed) or kind in words(mod, 'excludeWeapontype')))
                or not words(mod, 'requireTags') <= tags
                or (tag and (tag in occupied or tag in words(weapon, 'blockedTags')))):
            raise ValueError('incompatible bundle mod: ' + name)
        occupied.add(tag)
        tags.update(words(mod, 'providesTags'))
        if mod.findtext('stats/merge/modslot') is not None:
            capacity = int(mod.findtext('stats/merge/modslot'))
        if mod.findtext('subweapon/reserveName'): ammo.add(mod.findtext('subweapon/reserveName'))
    if len(option['mods']) > capacity: raise ValueError('bundle exceeds weapon mod slots')
    supplied = set()
    if type(option['consumables']) is not list or len(option['consumables']) > 8:
        raise ValueError('invalid bundle supplies')
    for row in option['consumables']:
        exact(row, 'name count', 'supply')
        item = items.get(row['name'])
        if item is None or item.findtext('use') not in ('弹夹', '药剂', '手雷') or row['name'] in supplied:
            raise ValueError('invalid bundle consumable')
        integer(row['count'], 1, 30, 'supply quantity')
        supplied.add(row['name'])
    if not ammo <= supplied: raise ValueError('bundle lacks weapon/underbarrel ammunition')


def validate_items(bundle, ceiling, items):
    rows = bundle['items']
    if type(rows) is not list or not 0 <= len(rows) <= 16 or not rows and not bundle.get('skills'): raise ValueError('invalid bundle items')
    names = set()
    for row in rows:
        exact(row, 'itemName quantity', 'bundle item')
        name = row['itemName']
        if type(name) is not str or name not in items or name in names: raise ValueError('unknown/duplicate bundle item')
        names.add(name)
        item = items[name]
        if int(item.findtext('data/level', '0')) > ceiling: raise ValueError('bundle item exceeds pool level')
        integer(row['quantity'], 1, 1 if item.findtext('type') in ('武器','防具') else 9999, 'bundle quantity')


def load():
    data = json.loads(SOURCE.read_text(encoding='utf-8'))
    validate(data)
    return data


def validate(data):
    exact(data, 'schema bundles pools', 'catalog')
    if data['schema'] != 'choice-rewards.v1': raise ValueError('unsupported choice catalog')
    if type(data['bundles']) is not list or not 1 <= len(data['bundles']) <= 128: raise ValueError('invalid bundles')
    if type(data['pools']) is not list or not 1 <= len(data['pools']) <= 32: raise ValueError('invalid pools')
    items = item_catalog()
    directory = ROOT / 'data/items/equipment_mods'
    mods = {m.findtext('name'): m for e in ET.parse(directory / 'list.xml').findall('items')
            for m in ET.parse(directory / e.text).findall('mod')}
    bundles, pool_ids, item_names, used = {}, set(), set(), set()
    for bundle in data['bundles']:
        keys = 'id name title description items' if 'items' in bundle else 'id name title description weapon mods consumables'
        exact(bundle, keys + (' weaponCount' if 'weapon' in bundle and 'weaponCount' in bundle else '') + (' skills' if 'skills' in bundle else '') + (' kCost' if 'kCost' in bundle else ''), 'bundle')
        integer(bundle.get('kCost', 0), 0, 1200, 'card K price')
        skills = bundle.get('skills', [])
        if type(skills) is not list or len(skills) > 2: raise ValueError('invalid skill rewards')
        skill_catalog = {s.findtext('Name'): s for s in ET.parse(ROOT / 'data/skills/skills.xml').findall('Skill') if s.findtext('Name')}
        skill_names = set()
        for grant in skills:
            exact(grant, 'skillKey level', 'skill reward')
            key = grant['skillKey']
            if key not in skill_catalog or key in skill_names: raise ValueError('unknown/duplicate skill reward')
            skill_names.add(key)
            integer(grant['level'], 1, int(skill_catalog[key].findtext('MaxLevel')), 'reward skill level')
        if not ID.fullmatch(bundle['id']) or bundle['id'] in bundles: raise ValueError('duplicate/invalid bundle id')
        for key, limit in [('name', 96), ('title', 64), ('description', 256)]:
            if type(bundle[key]) is not str or not 1 <= len(bundle[key]) <= limit or any(ord(c) < 32 for c in bundle[key]):
                raise ValueError('invalid bundle text')
        bundles[bundle['id']] = bundle
    for pool in data['pools']:
        exact(pool, 'id version title itemName scope maxItemLevel chooseCount rerolls groups', 'pool')
        if not ID.fullmatch(pool['id']) or pool['id'] in pool_ids or pool['itemName'] in item_names:
            raise ValueError('duplicate/invalid pool identity')
        pool_ids.add(pool['id']); item_names.add(pool['itemName'])
        for key in ('title', 'itemName'):
            if type(pool[key]) is not str or not 1 <= len(pool[key]) <= 96 or any(ord(c) < 32 for c in pool[key]): raise ValueError('invalid pool text')
        integer(pool['version'], 1, 1000000, 'pool version')
        integer(pool['maxItemLevel'], 1, 60, 'pool level')
        if pool['chooseCount'] != 1 or type(pool['chooseCount']) is not int or pool['rerolls'] != 0 or type(pool['rerolls']) is not int:
            raise ValueError('v1 supports one selection and no rerolls')
        scope = pool['scope']
        if type(scope) is not dict or scope.get('kind') not in ('character', 'book'): raise ValueError('invalid pool scope')
        exact(scope, 'kind bookId' if scope['kind'] == 'book' else 'kind', 'scope')
        if scope['kind'] == 'book' and not ID.fullmatch(scope['bookId']): raise ValueError('invalid book scope')
        if type(pool['groups']) is not list or not 1 <= len(pool['groups']) <= 4: raise ValueError('invalid groups')
        seen, group_ids, count = set(), set(), 0
        for group in pool['groups']:
            exact(group, 'id draw entries', 'group')
            if not ID.fullmatch(group['id']) or group['id'] in group_ids: raise ValueError('duplicate/invalid group')
            group_ids.add(group['id'])
            if type(group['entries']) is not list or not 1 <= len(group['entries']) <= 32: raise ValueError('empty/oversized group')
            integer(group['draw'], 1, len(group['entries']), 'group draw')
            count += group['draw']
            for row in group['entries']:
                exact(row, 'bundleId weight', 'pool entry')
                bid = row['bundleId']
                if bid not in bundles or bid in seen: raise ValueError('unknown/duplicate pool bundle')
                seen.add(bid); used.add(bid)
                integer(row['weight'], 1, 10000, 'bundle weight')
                if (bundles[bid].get('skills') or bundles[bid].get('kCost')) and scope['kind'] != 'book':
                    raise ValueError('skill and K rewards require an isolated book scope')
                if 'items' in bundles[bid]: validate_items(bundles[bid], pool['maxItemLevel'], items)
                else: validate_loadout(bundles[bid], pool['maxItemLevel'], items, mods)
        if not 2 <= count <= 4: raise ValueError('offer must contain two to four candidates')
    if used != bundles.keys(): raise ValueError('orphan bundle')
    return data


def resolve_book_choices(book, catalog=None):
    catalog = load() if catalog is None else validate(catalog)
    pools = {p['id']: p for p in catalog['pools']}
    bundles = {b['id']: b for b in catalog['bundles']}
    result = copy.deepcopy(book)
    for checkpoint in result['buildChoices'] + result.get('minorChoices', []):
        pool = pools[checkpoint['poolId']]
        if pool['scope'] != {'kind': 'book', 'bookId': book['id']} or checkpoint['choiceItem'] != pool['itemName'] or checkpoint['levelCeiling'] != pool['maxItemLevel']:
            raise ValueError('book checkpoint does not match its choice pool')
        ids = {row['bundleId'] for group in pool['groups'] for row in group['entries']}
        checkpoint['options'] = [{k:v for k,v in b.items() if k != 'id'} for b in catalog['bundles'] if b['id'] in ids and re.fullmatch(r'campus\.(initial|advanced)\.[1-4]', b['id'])]
    return result


def loadout_entries(bundle):
    count = bundle.get('weaponCount', 1)
    # Equipment quantity is its enhancement level in AS2. Two guns require two independent instances.
    entries = [{'itemName': bundle['weapon'], 'quantity': 1} for _ in range(count)]
    entries += [{'itemName': name, 'quantity': count} for name in bundle['mods']]
    entries += [{'itemName': row['name'], 'quantity': row['count']} for row in bundle['consumables']]
    return entries


def runtime_catalog(catalog):
    bundles = {b['id']: b for b in catalog['bundles']}
    result = []
    for pool in catalog['pools']:
        output = {k:copy.deepcopy(v) for k,v in pool.items() if k not in ('groups', 'maxItemLevel')}
        output['groups'] = []
        for group in pool['groups']:
            rows = []
            for row in group['entries']:
                b = bundles[row['bundleId']]
                if 'items' in b: entries = copy.deepcopy(b['items'])
                else: entries = loadout_entries(b)
                rows.append(dict(id=b['id'], weight=row['weight'], title=b['title'], description=b['description'], entries=entries, skills=copy.deepcopy(b.get('skills', [])), kCost=b.get('kCost', 0)))
            output['groups'].append(dict(draw=group['draw'], entries=rows))
        result.append(output)
    return result
