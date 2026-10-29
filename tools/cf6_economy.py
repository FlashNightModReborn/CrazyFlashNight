"""CF6 economy authoring checks. No inventory/save writes or random authority."""
import math
import json
from pathlib import Path
from choice_reward_catalog import exact, integer, load, validate
from cf6_acquisition import channels

QUOTA_MAPS = {'E1': 'A09', 'E2': 'A13', 'E3': 'A14', 'E4': 'A17', 'E5': 'A19'}


def enemies(stage):
    for wave in stage['stage']['Wave']['SubWave']:
        yield from wave['EnemyGroup']['Enemy']
    for group in stage.get('bossEncounter', {}).get('groups', []):
        yield from group['enemies']
    for group in stage.get('bossEncounter', {}).get('nextPhase', {}).get('groups', []):
        yield from group['enemies']


def historical_allowlist(shop=False):
    source = json.loads((Path(__file__).parent / 'cf6-roguelike-content/weapon-pools.source.json').read_text('utf-8'))
    policy = source['historicalPolicy']
    if policy['selection'] != 'strict-historical' or policy['allowedTierNames']:
        raise ValueError('historical weapon eligibility is not frozen')
    return set(policy['acceptedWeaponNames']) | (set(policy.get('acceptedShopWeaponNames',[])) if shop else set())


def check_historical_names(names, items, where):
    allowed = historical_allowlist(where == 'shop/budget')
    for name in names:
        meta = items.get(name)
        if meta is None: raise ValueError('unknown item in historical ' + where + ': ' + str(name))
        if meta is not None and meta.findtext('type') == '武器' and meta.findtext('use') in ('长枪','手枪') and name not in allowed:
            raise ValueError('later or unresolved weapon in historical ' + where + ': ' + name)


def validate_historical_budget(budget, items):
    names = list(budget['commonShopItems'])
    for node in budget['merchantNodes']: names.extend(node['addWeapons'])
    for row in budget['shoppingRoute']:
        names.extend(name for name in [row.get('purchaseWeapon'),row.get('ammoWeapon')] if name)
    names.extend(row['weapon'] for row in budget['stressPurchases'])
    check_historical_names(names, items, 'shop/budget')
    gold,_,_=channels()
    for node in budget['merchantNodes']:
        for name in node['addWeapons']:
            if name not in gold:raise ValueError('CF6 cash shop bypasses original acquisition channel: '+name)


def validate_economy(book, items, catalog=None):
    economy = book.get('economy')
    if economy is None:
        return
    exact(economy, 'randomWeapons eliteWeapons choices', 'CF6 economy')
    maps = {m['id']: m for m in book['maps']}
    historical = book.get('id') == 'cf6-sting' and book.get('routeId') == 'historical'
    route_scope = {'kind':'book', 'bookId':'cf6-sting'}
    if book.get('routeId') == 'type61':
        route_scope['routeId'] = 'type61'
    if historical:
        names = [e['name'] for e in book.get('actor',{}).get('equipment',[])]
        for section in ('randomWeapons','eliteWeapons'):
            names.extend(option['weapon'] for row in economy[section] for option in row['choices'])
        for stage in maps.values():
            names.extend(p['Name'] for p in stage['stage'].get('Pickups',{}).get('Pickup',[]))
            for enemy in enemies(stage):
                params = enemy.get('Parameters',{})
                names.extend(drop['名字'] for drop in params.get('掉落物',[]))
                names.extend(params[key].split('#')[0] for key in ('长枪','手枪','手枪2') if type(params.get(key)) is str)
        check_historical_names(names,items,'actor/fixed/random/elite/enemy')

    if book.get('id') == 'cf6-sting':
        policy=json.loads((Path(__file__).parent/'cf6-roguelike-content/weapon-pools.source.json').read_text('utf-8'))['historicalPolicy']
        restricted=set(policy.get('kOnlyWeaponNames',[]))
        free=[x['weapon'] for key in ('randomWeapons','eliteWeapons') for row in economy[key] for x in row['choices']]
        for stage in maps.values():
            free.extend(p['Name'] for p in stage['stage'].get('Pickups',{}).get('Pickup',[]))
            for enemy in enemies(stage):free.extend(x['名字'] for x in enemy.get('Parameters',{}).get('掉落物',[]))
        if restricted.intersection(free):raise ValueError('K-only CF6 weapon appears in free delivery')

    for key in economy:
        if type(economy[key]) is not list or len(economy[key]) > 20:
            raise ValueError('invalid CF6 economy rows')
    reserved, quotas, marked = set(), set(), {}
    for stage in maps.values():
        for enemy in enemies(stage):
            quota = enemy.get('Parameters', {}).get('cf6EliteQuota')
            if quota is not None:
                if quota not in QUOTA_MAPS or quota in marked or QUOTA_MAPS[quota] != stage['id']:
                    raise ValueError('unknown/duplicate/misplaced CF6 elite marker')
                carriers = ('兵种466','兵种467','兵种478','兵种479','兵种480','兵种481') if book.get('routeId')=='type61' else ('兵种466','兵种467')
                if enemy['Type'] not in carriers or enemy['Quantity'] != 1:
                    raise ValueError('CF6 elite must be one existing soldier')
                marked[quota] = enemy

    def row_choices(row, minimum, short_guns=False):
        if row['mapId'] not in maps: raise ValueError('unknown CF6 economy map')
        validate_anchor(maps[row['mapId']])
        options = row['choices']
        if type(options) is not list or not minimum <= len(options) <= 16:
            raise ValueError('CF6 random weapon pool needs real alternatives')
        names = set()
        for option in options:
            exact(option, 'weapon ammo ammoCount' + (' weaponCount' if 'weaponCount' in option else ''), 'CF6 weapon choice')
            gun = items.get(option['weapon'])
            if gun is None or gun.findtext('type') != '武器' or gun.findtext('use') not in (('长枪','手枪') if short_guns else ('长枪',)):
                raise ValueError('CF6 weapon must be an existing long gun')
            count = option.get('weaponCount', 1)
            integer(count, 1, 2, 'CF6 weapon count')
            if count != (2 if gun.findtext('use') == '手枪' else 1):
                raise ValueError('CF6 short guns require two independent instances')
            integer(int(gun.findtext('data/level', '999')), 1, 60, 'CF6 weapon level')
            ammo = items.get(option['ammo'])
            if ammo is None or ammo.findtext('use') != '弹夹' or gun.findtext('data/clipname') != option['ammo']:
                raise ValueError('CF6 ammunition does not match the selected weapon')
            integer(option['ammoCount'], 1, 30, 'CF6 ammunition count')
            if option['weapon'] in names: raise ValueError('duplicate CF6 weapon candidate')
            names.add(option['weapon'])
        return names

    def validate_anchor(stage):
        basic = stage['stage'].get('BasicInformation', {})
        for axis in ('PlayerX', 'PlayerY'):
            value = basic.get(axis)
            if type(value) not in (int, float) or not math.isfinite(value):
                raise ValueError('CF6 supply requires an authored finite world spawn')

    for row in economy['eliteWeapons']:
        exact(row, 'mapId quota choices', 'CF6 elite economy')
        quota = row['quota']
        if quota not in QUOTA_MAPS or quota in quotas or row['mapId'] != QUOTA_MAPS[quota] or quota not in marked:
            raise ValueError('CF6 elite quota has no exact carrier')
        quotas.add(quota)
        names = row_choices(row, 1 if quota in ('E1','E4') else 2)
        if names & reserved: raise ValueError('weapon repeats across CF6 elite sources')
        reserved |= names
        allowed_drops = names | {option['ammo'] for option in row['choices']}
        if any(drop['名字'] not in allowed_drops for drop in marked[quota].get('Parameters', {}).get('掉落物', [])):
            raise ValueError('CF6 elite replacement would discard an unrelated authored reward')
    if quotas != set(marked): raise ValueError('CF6 elite marker has no economy source')
    random_maps, random_names = set(), set()
    for row in economy['randomWeapons']:
        exact(row, 'mapId choices', 'CF6 random economy')
        names = row_choices(row, 2, True)
        if row['mapId'] in random_maps or names & reserved:
            raise ValueError('duplicate CF6 weapon delivery source')
        random_maps.add(row['mapId']); random_names |= names
    # Existing authored fixed pickups must not also deliver a reserved random/elite gun.
    for stage in maps.values():
        for pickup in stage['stage'].get('Pickups', {}).get('Pickup', []):
            if pickup['Name'] in reserved | random_names:
                raise ValueError('CF6 fixed pickup duplicates a random/elite weapon source')
        for enemy in enemies(stage):
            if enemy.get('Parameters', {}).get('cf6EliteQuota') in quotas: continue
            for drop in enemy.get('Parameters', {}).get('掉落物', []):
                if drop['名字'] in reserved | random_names:
                    raise ValueError('CF6 authored drop duplicates a random/elite weapon source')
    catalog = load() if catalog is None else validate(catalog)
    pools = {p['id']: p for p in catalog['pools']}
    bundles = {b['id']: b for b in catalog['bundles']}
    maxed = {s['name'] for s in book['actor']['skills']}
    seen_maps, seen_pools, choice_items = set(), set(), set()
    for row in economy['choices']:
        exact(row, 'mapId poolId itemName', 'CF6 choice delivery')
        pool = pools.get(row['poolId'])
        if (row['mapId'] not in maps or row['mapId'] in seen_maps or row['poolId'] in seen_pools
                or pool is None or pool['scope'] != route_scope
                or pool['itemName'] != row['itemName']):
            raise ValueError('CF6 choice delivery identity/scope mismatch')
        seen_maps.add(row['mapId']); seen_pools.add(row['poolId']); choice_items.add(row['itemName'])
        validate_anchor(maps[row['mapId']])
        guaranteed_total = 0
        for group in pool['groups']:
            # Consumable choices remain available after weapon ownership changes.
            guaranteed = 0
            for entry in group['entries']:
                bundle = bundles[entry['bundleId']]
                if bundle.get('kCost', 0) != 0: raise ValueError('CF6 first prototype cards must be free')
                if any(s['skillKey'] in maxed for s in bundle.get('skills', [])):
                    raise ValueError('CF6 card contains a historical maxed skill')
                contents = bundle.get('items', [])
                names = {r['itemName'] for r in contents} | ({bundle['weapon']} if 'weapon' in bundle else set())
                if names & reserved: raise ValueError('CF6 card duplicates reserved weapon delivery')
                if historical: check_historical_names(names,items,'choice')
                if not bundle.get('skills') and ('consumables' in bundle or any(items[n].findtext('type') not in ('武器','防具') for n in names)):
                    guaranteed += 1
            guaranteed_total += min(group['draw'], guaranteed)
        if guaranteed_total < 2:
            raise ValueError('CF6 pool cannot guarantee two eligible choices')
    authored_pools = {p['id'] for p in catalog['pools'] if p['scope'] == route_scope}
    if book.get('routeId') == 'type61':
        seen_pools.update(book.get('type61', {}).get('choicePoolIds', []))
    if seen_pools != authored_pools: raise ValueError('CF6 choice pool missing its unique delivery')
    for stage in maps.values():
        if any(p['Name'] in choice_items for p in stage['stage'].get('Pickups', {}).get('Pickup', [])):
            raise ValueError('CF6 choice pack duplicated in fixed pickups')
        if any(d['名字'] in choice_items for e in enemies(stage) for d in e.get('Parameters', {}).get('掉落物', [])):
            raise ValueError('CF6 choice pack duplicated in authored drops')
