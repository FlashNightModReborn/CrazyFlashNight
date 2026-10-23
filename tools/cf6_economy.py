"""CF6 economy authoring checks. No inventory/save writes or random authority."""
import math
from choice_reward_catalog import exact, integer, load, validate

QUOTA_MAPS = {'E1': 'A09', 'E2': 'A13', 'E3': 'A14', 'E4': 'A17', 'E5': 'A19'}


def enemies(stage):
    for wave in stage['stage']['Wave']['SubWave']:
        yield from wave['EnemyGroup']['Enemy']
    for group in stage.get('bossEncounter', {}).get('groups', []):
        yield from group['enemies']
    for group in stage.get('bossEncounter', {}).get('nextPhase', {}).get('groups', []):
        yield from group['enemies']


def validate_economy(book, items, catalog=None):
    economy = book.get('economy')
    if economy is None:
        return
    exact(economy, 'randomWeapons eliteWeapons choices', 'CF6 economy')
    maps = {m['id']: m for m in book['maps']}
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
                if enemy['Type'] not in ('兵种466', '兵种467') or enemy['Quantity'] != 1:
                    raise ValueError('CF6 elite must be one existing soldier')
                marked[quota] = enemy

    def row_choices(row, minimum):
        if row['mapId'] not in maps: raise ValueError('unknown CF6 economy map')
        validate_anchor(maps[row['mapId']])
        options = row['choices']
        if type(options) is not list or not minimum <= len(options) <= 16:
            raise ValueError('CF6 random weapon pool needs real alternatives')
        names = set()
        for option in options:
            exact(option, 'weapon ammo ammoCount', 'CF6 weapon choice')
            gun = items.get(option['weapon'])
            if gun is None or gun.findtext('type') != '武器' or gun.findtext('use') != '长枪':
                raise ValueError('CF6 weapon must be an existing long gun')
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
        names = row_choices(row, 1 if quota == 'E1' else 2)
        if names & reserved: raise ValueError('weapon repeats across CF6 elite sources')
        reserved |= names
        allowed_drops = names | {option['ammo'] for option in row['choices']}
        if any(drop['名字'] not in allowed_drops for drop in marked[quota].get('Parameters', {}).get('掉落物', [])):
            raise ValueError('CF6 elite replacement would discard an unrelated authored reward')
    if quotas != set(marked): raise ValueError('CF6 elite marker has no economy source')
    random_maps, random_names = set(), set()
    for row in economy['randomWeapons']:
        exact(row, 'mapId choices', 'CF6 random economy')
        names = row_choices(row, 2)
        if row['mapId'] in random_maps or names & (reserved | random_names):
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
                or pool is None or pool['scope'] != {'kind':'book', 'bookId':'cf6-sting'}
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
                if names & (reserved | random_names): raise ValueError('CF6 card duplicates reserved weapon delivery')
                if not bundle.get('skills') and ('consumables' in bundle or any(items[n].findtext('type') not in ('武器','防具') for n in names)):
                    guaranteed += 1
            guaranteed_total += min(group['draw'], guaranteed)
        if guaranteed_total < 2:
            raise ValueError('CF6 pool cannot guarantee two eligible choices')
    authored_pools = {p['id'] for p in catalog['pools'] if p['scope'] == {'kind':'book','bookId':'cf6-sting'}}
    if seen_pools != authored_pools: raise ValueError('CF6 choice pool missing its unique delivery')
    for stage in maps.values():
        if any(p['Name'] in choice_items for p in stage['stage'].get('Pickups', {}).get('Pickup', [])):
            raise ValueError('CF6 choice pack duplicated in fixed pickups')
        if any(d['名字'] in choice_items for e in enemies(stage) for d in e.get('Parameters', {}).get('掉落物', [])):
            raise ValueError('CF6 choice pack duplicated in authored drops')
