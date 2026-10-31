"""Shared authoring identity rules; runtime output remains canonical 兵种N."""
import copy
import json
from pathlib import Path
import re

MAX_ID = 2147483647
MAX_KEY_LENGTH = 96
LEGACY_TYPE = re.compile(r'兵种(0|[1-9][0-9]*)')
SEMANTIC_KEY = re.compile(r'[A-Za-z\u3400-\u9fff][A-Za-z0-9_\u3400-\u9fff-]*(?:\.[A-Za-z0-9_\u3400-\u9fff·-]+)+')
RESERVED_SEGMENTS = {'__proto__', 'prototype', 'constructor'}


def valid_key(value):
    return (isinstance(value, str) and len(value) <= MAX_KEY_LENGTH
            and SEMANTIC_KEY.fullmatch(value) is not None
            and not RESERVED_SEGMENTS.intersection(value.split('.')))


class UnitRegistry:
    def __init__(self, units):
        if not isinstance(units, list) or not units:
            raise ValueError('Unit registry must be a non-empty array')
        self.by_id = {}
        self.by_key = {}
        for index, unit in enumerate(units):
            label = 'units[' + str(index) + ']'
            if (not isinstance(unit, dict) or type(unit.get('id')) not in (int, float)
                    or not 0 <= unit['id'] <= MAX_ID
                    or unit['id'] != int(unit['id'])):
                raise ValueError(label + ': invalid unit id')
            if unit['id'] in self.by_id:
                raise ValueError(label + ': duplicate unit id ' + str(unit['id']))
            if not isinstance(unit.get('spritename'), str) or not unit['spritename']:
                raise ValueError(label + ': missing spritename')
            self.by_id[unit['id']] = unit
            if 'key' in unit:
                if not valid_key(unit['key']):
                    raise ValueError(label + ': invalid unit key ' + str(unit['key']))
                if unit['key'] in self.by_key:
                    raise ValueError(label + ': duplicate unit key ' + unit['key'])
                self.by_key[unit['key']] = int(unit['id'])

    @classmethod
    def load(cls, root):
        return cls(json.loads((Path(root) / 'data/units/units.json').read_text('utf-8-sig')))

    def resolve_type(self, reference, context='unit reference'):
        if not isinstance(reference, str):
            raise ValueError(context + ': unit reference must be a string')
        if len(reference) > MAX_KEY_LENGTH:
            raise ValueError(context + ': unit reference is too long')
        legacy = LEGACY_TYPE.fullmatch(reference)
        identity = int(legacy.group(1)) if legacy else self.by_key.get(reference)
        if identity not in self.by_id:
            raise ValueError(context + ': unknown unit reference ' + reference)
        return '兵种' + str(identity)

    def resolve_id(self, reference, context='unit reference'):
        if type(reference) in (int, float):
            if not 0 <= reference <= MAX_ID or reference != int(reference) or reference not in self.by_id:
                raise ValueError(context + ': unknown unit id ' + str(reference))
            return int(reference)
        return int(self.resolve_type(reference, context)[2:])

    def get(self, reference, context='unit reference'):
        return self.by_id[self.resolve_id(reference, context)]


def preserve_unit_key(candidate, registered_units, *, new_key=None):
    """Keep the target's key, never a copied template key; new rows need a key.

    Generators own gameplay fields, but only the registry owns an existing key.
    new_key is used solely when the target id has never been registered.
    """
    result = copy.deepcopy(candidate)
    result.pop('key', None)
    existing = UnitRegistry(registered_units).by_id.get(result['id'])
    if existing is not None:
        if 'key' in existing:
            result['key'] = existing['key']
    else:
        if not valid_key(new_key):
            raise ValueError('New unit ' + str(result['id']) + ' requires an explicit semantic key')
        result['key'] = new_key
    # Validate the resulting whole registry before any caller writes it.
    UnitRegistry([row for row in registered_units if row['id'] != result['id']] + [result])
    return result


def normalize_book_units(source, registry):
    """Resolve only documented spawn fields; arbitrary Parameters are opaque."""
    data = copy.deepcopy(source)

    def enemy_list(enemies, context):
        if not isinstance(enemies, list):
            return  # The existing shape validator reports malformed containers.
        for index, enemy in enumerate(enemies):
            if isinstance(enemy, dict) and 'Type' in enemy:
                enemy['Type'] = registry.resolve_type(enemy['Type'], context + '[' + str(index) + '].Type')

    def encounter(plan, context):
        if not isinstance(plan, dict):
            return
        for index, group in enumerate(plan.get('groups', [])):
            if not isinstance(group, dict):
                continue
            enemy_list(group.get('enemies'), context + '.groups[' + str(index) + '].enemies')
            # Campus reinforcement pools use numeric ids at runtime.
            if isinstance(group.get('pools'), list):
                for pool_index, pool in enumerate(group['pools']):
                    if isinstance(pool, list):
                        group['pools'][pool_index] = [registry.resolve_id(ref, context + '.pools') for ref in pool]
        if 'nextPhase' in plan:
            encounter(plan['nextPhase'], context + '.nextPhase')

    for index, stage in enumerate(data.get('maps', [])):
        if not isinstance(stage, dict):
            continue
        context = 'maps[' + str(index) + ']'
        if isinstance(stage.get('enemies'), list):
            stage['enemies'] = [registry.resolve_id(ref, context + '.enemies') for ref in stage['enemies']]
        waves = stage.get('stage', {}).get('Wave', {}).get('SubWave', [])
        if isinstance(waves, list):
            for wave_index, wave in enumerate(waves):
                if isinstance(wave, dict):
                    enemy_list(wave.get('EnemyGroup', {}).get('Enemy'), context + '.Wave[' + str(wave_index) + '].Enemy')
        encounter(stage.get('bossEncounter'), context + '.bossEncounter')
    encounter(data.get('bossEncounter'), 'bossEncounter')
    return data
