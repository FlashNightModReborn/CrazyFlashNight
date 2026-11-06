"""Compile fixed personnel into per-instance spawn slots; never execute prose contracts."""
from pathlib import Path
from collections import Counter, defaultdict
import copy
import hashlib
import json
import math
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from choice_reward_catalog import item_catalog
from unit_registry import UnitRegistry
import soldier_programs

SOURCE = HERE / 'fixed-roster.source.json'
CONTRACTS = HERE / 'soldier-action-contracts.source.json'
TACTICS = ('shield_breach reverse_rear_guard fixed_bastion pursuit_leash segmented_lane advance_flush '
           'landing_watch bright_burst relocate_then_flush range_rotation shield_counter judgment_line '
           'disciplined_screen feint_retreat alternating_fire punish_commit paired_windows weapon_handoff '
           'reserve_gate robot_observer threshold_flush final_phase_guard').split()
ROLES = {'line', 'suppress', 'precision', 'breach', 'flush', 'mobile', 'counter', 'dual'}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def read_source():
    return json.loads(SOURCE.read_text('utf-8'))


def number(value, low, high, label, whole=False):
    if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high or whole and int(value) != value:
        raise ValueError('Invalid ' + label)
    return value


def words(element, key):
    return {v.strip() for v in (element.findtext(key) or '').split(',') if v.strip()}


def mod_catalog():
    directory = ROOT / 'data/items/equipment_mods'
    return {m.findtext('name'): m for entry in ET.parse(directory / 'list.xml').findall('items')
            for m in ET.parse(directory / entry.text).findall('mod')}


def equipment(slot, use, level, items, mods, admission):
    if slot is None:
        if use == '长枪':
            raise ValueError('Every fixed soldier needs a primary weapon')
        return None
    name = slot['name']
    if name not in admission or any(c in name for c in '#,\r\n'):
        raise ValueError('Weapon lacks fixed-enemy admission: ' + name)
    item = items.get(name)
    if item is None or item.findtext('type') != '武器' or item.findtext('use') != use:
        raise ValueError('Fixed equipment slot mismatch: ' + name)
    equip_level = int(item.findtext('data/level', '999'))
    if equip_level > level:
        raise ValueError('Fixed equipment exceeds actor level: ' + name)
    enhancement = number(slot['enhancement'], 1, 13, 'enhancement', True)
    if slot.get('tier') is not None:
        raise ValueError('Fixed158 admits base forms only')
    selected = slot['mods']
    if type(selected) is not list or len(set(selected)) != len(selected):
        raise ValueError('Invalid or repeated fixed mods')
    capacity = int(item.findtext('data/modslot', str(3 if equip_level < 12 else 2 if equip_level < 30 else 1)))
    if len(selected) > capacity:
        raise ValueError('Fixed mod slots exceeded: ' + name)
    tags, occupied = words(item, 'inherentTags'), set()
    subtype = item.get('weapontype', '')
    special = item.find('subweapon') is not None
    for mod_name in selected:
        mod = mods.get(mod_name)
        if mod is None or mod_name not in items or any(c in mod_name for c in '#,\r\n'):
            raise ValueError('Unknown fixed mod: ' + mod_name)
        tag = mod.findtext('tag')
        if (use not in words(mod, 'use') or subtype in words(mod, 'excludeWeapontype')
                or words(mod, 'weapontype') and subtype not in words(mod, 'weapontype')
                or not words(mod, 'requireTags') <= tags
                or tag in occupied or tag in words(item, 'blockedTags')
                or item.find('allowedModTags') is not None and tag not in words(item, 'allowedModTags')):
            raise ValueError('Incompatible fixed mod: ' + name + ' / ' + mod_name)
        # This closed roster uses eight audited structural mods. New complex
        # conditions need the actual EquipmentUtil oracle before admission.
        if mod.find('installCondition') is not None or mod.find('lifecycle') is not None or mod.find('skill') is not None:
            raise ValueError('Unsupported fixed mod condition: ' + mod_name)
        if mod.find('subweapon') is not None:
            if special or item.find('.//skillLocked') is not None:
                raise ValueError('Fixed special slot collision: ' + name)
            special = True
        occupied.add(tag)
        tags |= words(mod, 'provideTags')
    serialized = name + '#' + str(int(enhancement)) + '##' + ','.join(selected)
    if serialized != slot['serialized']:
        raise ValueError('Fixed equipment string does not round-trip: ' + name)
    ammo = item.findtext('data/clipname')
    if ammo not in items or items[ammo].findtext('use') != '弹夹':
        raise ValueError('Fixed weapon ammunition is absent: ' + name)
    overrides = slot.get('instanceValueOverrides')
    if overrides is not None:
        if name != 'G1111' or set(overrides) != {'isRocketMode'} or type(overrides['isRocketMode']) is not bool:
            raise ValueError('Fixed G1111 mode must be an actual Boolean')
        return dict(name=name, value=dict(level=int(enhancement), mods=list(selected), shot=0,
                                         isRocketMode=overrides['isRocketMode']))
    if name == 'G1111':
        raise ValueError('Missing fixed G1111 mode')
    return serialized


def profile(row, items=None):
    blueprint = row['aiBlueprint']
    extension = blueprint['proposedExtensions']
    budget = row['nominalFireBudget']
    if row['role'] not in ROLES or blueprint['role'] != row['role']:
        raise ValueError('Unknown fixed role')
    if blueprint['strategy'] not in ('line', 'mobile', 'adaptive', 'switch'):
        raise ValueError('Unknown fixed strategy')
    tactic = extension['majorTactic']
    if row['roleClass'] == 'instructor' and tactic not in TACTICS or tactic is not None and tactic not in TACTICS:
        raise ValueError('Unknown or missing instructor tactic')
    number(extension['shootRange'], 95, 680, 'role shoot range')
    number(extension['approachStopRange'], 0, extension['shootRange'], 'role stop distance')
    number(extension['laneRange'], 1, 80, 'role lane')
    number(extension['windupFrames'], 1, 120, 'visible warning', True)
    number(extension['lockAimLastFrames'], 0, extension['windupFrames'], 'locked warning', True)
    number(extension['finiteThrowableCount'], 0, 3, 'throwable limit', True)
    number(budget['maxPlannedActionProjectiles'], 1, 14, 'final damage-unit ceiling', True)
    bounds = json.loads((ROOT / 'tools/cf6-soldier-assets/tactical-profiles.json').read_text('utf-8'))['bounds']
    for key, value in blueprint['existingScalarOverrides'].items():
        field = key.removeprefix('特种兵战术_')
        if field not in bounds:
            raise ValueError('Unknown tactical scalar: ' + key)
        number(value, *bounds[field], key)
    result = dict(role=row['role'], roleClass=row['roleClass'], strategy=blueprint['strategy'],
                  scalars=blueprint['existingScalarOverrides'], extensions=extension, budget=copy.deepcopy(budget))
    result['extensions'] = copy.deepcopy(extension)
    if items is None:
        items = item_catalog()
    weapon_type = items[row['primary']['name']].get('weapontype')
    result['program'] = soldier_programs.compile_program(result, weapon_type, row['primary']['name'])
    aim = next(stage for stage in result['program']['stages'] if stage['kind'] == 'warning')
    result['extensions']['windupFrames'] = aim['frames']
    result['extensions']['lockAimLastFrames'] = aim['lock']
    # Direct XML split and final damaging units are distinct. An M203 carrier
    # creates one actual explosion, just as FSC7 and the finite hand grenade do.
    final = result['budget']
    primary_cost = final.get('primaryFinalDamageUnitsPerAction', final['primaryProjectilesPerAction']) / final['primaryTriggerLimit']
    sub_cost = 2 if (row.get('subweapon') or {}).get('bullet') == '榴弹' else final['subweaponProjectilesPerAction']
    final['subweaponFinalDamageUnitsPerAction'] = sub_cost
    cycle_max = granted_max = 0
    for variant in ('stages', 'dual', 'phase2', 'fallback', 'shield', 'grenade', 'pressure'):
        counts = dict(primary=0, dual=0, sub=0, **{'throw': 0})
        for stage in result['program'].get(variant, []):
            if stage['kind'] == 'fire': counts[stage['mode']] += stage['events']
        longgun = counts['primary'] * primary_cost + counts['sub'] * sub_cost + counts['throw'] * 2
        sidearms = counts['dual'] * final['sidearmProjectilesPerAction'] / max(1, final['sidearmSynchronizedTriggerLimit'])
        cycle_max = max(cycle_max, longgun + sidearms)
        granted_max = max(granted_max, max(longgun, sidearms) if result['program']['mixed'] else longgun + sidearms)
    number(cycle_max, 1, 20, 'final cycle damage units', True)
    number(granted_max, 1, 14, 'final granted attack damage units', True)
    final['scriptedCycleDamageUnits'] = int(cycle_max)
    final['maxGrantedDamageUnits'] = int(granted_max)
    return result




def runtime_profile(value):
    """Executable projection; reviewed narrative/evidence stays in authoring sources."""
    result=copy.deepcopy(value)
    result['budget']={k:v for k,v in result['budget'].items() if not isinstance(v,str)}
    for key in ('effectBudget','phaseEligibility','unknownMajorTacticPolicy','subweaponReload'):
        result['extensions'].pop(key,None)
    return result


def runtime_catalog(source=None, items=None):
    source = read_source() if source is None else source
    items = item_catalog() if items is None else items
    profiles, identities = {}, {}
    for row in source['roster']:
        projected = profile(row, items)
        key = 'p' + hashlib.sha256(canonical(projected)).hexdigest()[:16]
        profiles[key] = projected
        identities[row['unitIdentity']] = dict(profileId=key, mapId=row['mapId'],
            startingPhase=row['startingPhase'], roleClass=row['roleClass'], sourceSeat=row['sourceSeat'])
    # Version owns the executable tables as well as the authored personnel.
    version = 'fixed158-v2-' + hashlib.sha256(canonical(dict(source=source, profiles=profiles))).hexdigest()[:16]
    return dict(schema='cf6-fixed-roster.runtime.v1', version=version, profiles=profiles, identities=identities,
                counts=dict(personnel=158, sources=len({r['sourceJsonPointer'] for r in source['roster']}), ordinary=96, elite=40, instructor=22))


def pointer(data, path):
    value = data
    for key in path.strip('/').split('/'):
        value = value[int(key)] if isinstance(value, list) else value[key]
    return value


def compile_slots(book, source=None, items=None):
    source = read_source() if source is None else source
    items = item_catalog() if items is None else items
    mods = mod_catalog()
    if source['schema'] != 'cf6-fixed-roster.source.v1' or source['scope'] != dict(bookId='cf6-sting', routeId='type61'):
        raise ValueError('Unexpected fixed roster scope')
    if book.get('id') != 'cf6-sting' or book.get('routeId') != 'type61':
        raise ValueError('Fixed158 must not change the historical route or another book')
    rows = source['roster']
    if len(rows) != 158 or Counter(x['roleClass'] for x in rows) != Counter(ordinary=96, elite=40, instructor=22):
        raise ValueError('Fixed roster personnel count drift')
    if len({x['unitIdentity'] for x in rows}) != 158 or len({x['sourceSeat'] for x in rows}) != 158:
        raise ValueError('Repeated fixed identity or source seat')
    if len({x['mapId'] for x in rows}) != 12:
        raise ValueError('Fixed map coverage drift')
    admitted = {x['name'] for x in source['admission']['weapons'] if x['decision'] in ('A', 'B')}
    admitted_mods = {x['name'] for x in source['admission']['mods'] if x['decision'] == 'A'}
    registry = UnitRegistry.load(ROOT)
    catalog = runtime_catalog(source, items)
    version = catalog['version']
    profiles, groups = {}, defaultdict(list)
    for row in rows:
        original = pointer(book, row['sourceJsonPointer'])
        if (original['Quantity'] != row['sourceQuantity'] or original['Level'] != row['level']
                or registry.resolve_id(original['Type']) != row['unitId']):
            raise ValueError('Authored source changed: ' + row['sourceSeat'])
        if row['startingPhase'] != (2 if row['unitId'] % 2 == 0 else 1):
            raise ValueError('Fixed phase/linkage mismatch')
        number(row['sourceInstanceOrdinal'], 0, row['sourceQuantity'] - 1, 'source instance ordinal', True)
        spawn = row['proposedSpawn']
        number(spawn['x'], -100000, 100000, 'fixed x')
        number(spawn['y'], -100000, 100000, 'fixed z')
        relocated = row.get('relocation') is not None
        if (spawn['randomBiasEnabled'] is not False
                or spawn['keepSourceGroupScheduler'] is not (not relocated)
                or relocated and (row['unitIdentity'] not in ('CF6-C-PE-R-06', 'CF6-N-SW-01', 'CF6-M-IX')
                                  or spawn['phase'] not in ('boss', 'nextPhase') or spawn['removeSourceSeat'] is not True)):
            raise ValueError('Fixed roster must retain the authored group scheduler')
        authored_scale = original.get('Parameters', {}).get('cf6DifficultyScale', 1)
        if authored_scale != row['difficultyScale']:
            raise ValueError('Fixed actor difficulty multiplier drift')
        projected_profile = profile(row, items)
        profile_id = 'p' + hashlib.sha256(canonical(projected_profile)).hexdigest()[:16]
        profiles[profile_id] = projected_profile
        params = dict(cf6UnitIdentity=row['unitIdentity'], cf6SourceSeat=row['sourceSeat'], cf6SourceOrdinal=row['sourceInstanceOrdinal'], cf6RosterVersion=version,
                      cf6ProfileId=profile_id, cf6LootProfile=row['lootProfile'],
                      cf6LootMaterial=row['lootRules']['materialCandidate'], cf6DisplayTitle=row['displayName'], 称号=row['displayName'],
                      特种兵初始阶段=row['startingPhase'], 特种兵策略=row['aiBlueprint']['strategy'],
                      特种兵烟雾弹=row['smokeAbility'], 特种兵投掷物=False, 不掉装备=True, 掉落物=[])
        for field, slot, use in (('长枪', 'primary', '长枪'), ('手枪', 'secondary1', '手枪'), ('手枪2', 'secondary2', '手枪')):
            equipment_row = row[slot]
            if equipment_row is not None and not set(equipment_row['mods']) <= admitted_mods:
                raise ValueError('Fixed mod lacks era admission')
            value = equipment(equipment_row, use, row['level'], items, mods, admitted)
            if value is not None:
                params[field] = value
        if row['roleClass'] == 'ordinary' and (row['secondary1'] is not None or row['secondary2'] is not None):
            raise ValueError('Ordinary actor inherited sidearms')
        if row['roleClass'] != 'ordinary' and (row['secondary1'] is None or row['secondary2'] is None):
            raise ValueError('Mobile actor lost an independent hand')
        if row['throwable'] is not None:
            thrown = row['throwable']
            if thrown['name'] not in items or items[thrown['name']].findtext('use') != '手雷' or thrown['maxUses'] != 1:
                raise ValueError('Invalid finite throwable')
            params['特种兵投掷物'] = thrown['name']
        params['特种兵副武器'] = row['subweapon'] is not None
        params.update(row['aiBlueprint']['existingScalarOverrides'])
        if row['primary'].get('instanceValueOverrides') is not None:
            params['cf6G1111FixedMode'] = row['primary']['instanceValueOverrides']['isRocketMode']
        groups[row['sourceJsonPointer']].append(dict(ordinal=row['sourceInstanceOrdinal'], x=spawn['x'], y=spawn['y'],
                                                    parameters=params, relocation=copy.deepcopy(row.get('relocation')),
                                                    mapId=row['mapId']))
    for source_pointer, slots in groups.items():
        slots.sort(key=lambda x: x['ordinal'])
        expected = pointer(book, source_pointer)['Quantity']
        if [x['ordinal'] for x in slots] != list(range(expected)):
            raise ValueError('Source quantity is not bijective with fixed identities: ' + source_pointer)
    return dict(schema='cf6-fixed-roster.runtime.v1', version=version, profiles=profiles, identities=catalog['identities'], slots=dict(groups),
                counts=dict(personnel=158, sources=len(groups), ordinary=96, elite=40, instructor=22))


def apply(book, compiled):
    result = copy.deepcopy(book)
    removals, migrations = [], []
    for source_pointer, slots in compiled['slots'].items():
        enemy = pointer(result, source_pointer)
        params = enemy.setdefault('Parameters', {})
        for key in ('cf6EliteQuota', '长枪', '手枪', '手枪2', '称号'):
            params.pop(key, None)
        def runtime_slot(slot, ordinal):
            return dict(ordinal=ordinal, x=slot['x'], y=slot['y'], parameters=copy.deepcopy(slot['parameters']))
        retained = [s for s in slots if s['relocation'] is None]
        params.update(cf6FixedSlots=[runtime_slot(s, i) for i, s in enumerate(retained)],
                      cf6RosterVersion=compiled['version'], 不掉装备=True, 掉落物=[])
        enemy['Quantity'] = len(retained)
        for slot in slots:
            if slot['relocation'] is None:
                continue
            moved = copy.deepcopy(enemy)
            # The explicit migration relinquishes its wave scheduler. The
            # encounter's reviewed 45-frame interval now owns this one slot.
            moved.pop('Delay', None)
            moved.pop('Interval', None)
            for reserved in ('cf6BossOwnerToken', 'cf6SupportIdentity', 'publishStageEvent', '产生源', 'InstanceName'):
                moved['Parameters'].pop(reserved, None)
            moved['Quantity'] = 1
            moved['x'], moved['y'], moved['ranged'] = slot['x'], slot['y'], True
            moved['Parameters']['cf6FixedSlots'] = [runtime_slot(slot, 0)]
            migrations.append((slot, moved))
        if not retained:
            parent_path, index = source_pointer.rsplit('/', 1)
            removals.append((pointer(result, parent_path), int(index)))
    # Resolve all original pointers before changing any list indices.
    for parent in {id(p): p for p, _ in removals}.values():
        for index in sorted((i for p, i in removals if p is parent), reverse=True):
            del parent[index]
    for slot, enemy in sorted(migrations, key=lambda entry: (entry[0]['mapId'], entry[0]['relocation']['order'])):
        target = next(m for m in result['maps'] if m['id'] == slot['mapId'])['bossEncounter']
        relocation = slot['relocation']
        if relocation['phase'] == 'nextPhase':
            target = target['nextPhase']
        if target['intervalFrames'] != 45:
            raise ValueError('Reviewed finite support interval changed')
        target['groups'][relocation['group']]['enemies'].insert(relocation['order'], enemy)
    result['economy']['eliteWeapons'] = []
    result['type61']['soldiers'] = {key: copy.deepcopy(compiled[key]) for key in ('schema', 'version', 'profiles', 'identities', 'counts')}
    result['type61']['soldiers']['profiles']={key:runtime_profile(value) for key,value in compiled['profiles'].items()}
    return result


def validate_materialized(book):
    """Verify compiled identities, schedules and equipment against authored seats.

    Rebuild from the historical route, never from the already materialized input.
    This also catches a deleted/reinserted group that preserves global counts.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location('fixed158_validation_builder', Path(__file__).with_name('build-route.py'))
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    baseline = json.loads(builder.build(include_fixed=False)[builder.OUTPUT])
    expected = apply(baseline, compile_slots(baseline))
    expected['type61']['soldiers']['lootPolicy'] = json.loads(
        Path(__file__).with_name('soldier-loot-policy.source.json').read_text('utf8'))
    if book.get('routeId') != 'type61' or book.get('type61', {}).get('soldiers') != expected['type61']['soldiers']:
        raise ValueError('Fixed158 executable catalog or loot policy differs from authored inputs')
    registry = UnitRegistry.load(ROOT)
    def seats(chapter):
        result = []
        for stage in chapter['maps']:
            streams = [('wave', wi, wave['EnemyGroup']['Enemy'], wave.get('Interval'))
                       for wi, wave in enumerate(stage['stage']['Wave']['SubWave'])]
            boss = stage.get('bossEncounter', {})
            for phase, encounter in (('boss', boss), ('nextPhase', boss.get('nextPhase', {}))):
                streams.extend((phase, gi, group['enemies'], encounter.get('intervalFrames'))
                               for gi, group in enumerate(encounter.get('groups', [])))
            for phase, index, enemies, interval in streams:
                for ei, enemy in enumerate(enemies):
                    params = enemy.get('Parameters', {})
                    if 'cf6FixedSlots' not in params:
                        if any(k in params for k in ('cf6UnitIdentity', 'cf6ProfileId', 'cf6RosterVersion', 'cf6EliteQuota')):
                            raise ValueError('Fixed158 marker outside its materialized source group')
                        continue
                    result.append(dict(map=stage['id'], phase=phase, group=index, entry=ei,
                        interval=interval, type=registry.resolve_id(enemy['Type']), level=enemy['Level'],
                        quantity=enemy['Quantity'], parameters=params))
        return result
    if seats(book) != seats(expected):
        raise ValueError('Fixed158 materialized seat, scheduler, phase, position or equipment drift')
    if book['economy']['eliteWeapons']:
        raise ValueError('Fixed158 must retire random elite weapon overrides')
    for key in ('randomWeapons', 'choices'):
        if book['economy'][key] != baseline['economy'][key]:
            raise ValueError('Fixed158 must not broaden player reward pools')


if __name__ == '__main__':
    source_book = json.loads((ROOT / 'data/stages/books/cf6-type61.json').read_text('utf-8'))
    validate_materialized(source_book)
    compiled = runtime_catalog()
    print(json.dumps(dict(**compiled['counts'], profiles=len(compiled['profiles']), version=compiled['version']), ensure_ascii=False))
