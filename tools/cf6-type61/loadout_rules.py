"""Closed fixed158 authoring checks; production EquipmentUtil remains the oracle.

Only the admitted structural/stat mods are supported here. An unsupported condition
fails closed instead of growing a second general-purpose equipment engine.
"""
import math
from decimal import Decimal, ROUND_HALF_UP


def words(node, path):
    return {s.strip() for s in (node.findtext(path) or '').split(',') if s.strip()}


def contexts(item, selected, mods):
    use = {item.findtext('use'), item.get('weapontype', '')}
    types = {item.get('weapontype', '')}
    tags = words(item, 'inherentTags')
    for name in selected:
        use |= words(mods[name], 'grantsUse')
        types |= words(mods[name], 'grantsWeapontype')
    # grantsWeapontype affects the menu's compatibility, NOT useSwitch matching.
    for name in selected:
        mod = mods[name]
        tags |= words(mod, 'provideTags')
        for case in mod.findall('stats/useSwitch/use'):
            if set(case.get('name', '').split(',')) & use:
                tags |= words(case, 'provideTags')
    return use, types, tags


def stats_for(item, selected, mods):
    use, _, tags = contexts(item, selected, mods)
    for name in selected:
        mod = mods[name]
        stats = mod.find('stats')
        if stats is None:
            continue
        yield stats
        for container, field, context in [('useSwitch', 'use', use), ('tagSwitch', 'tag', tags)]:
            for case in stats.findall(container + '/' + field):
                if set(case.get('name', '').split(',')) & context:
                    yield case


def capacity(item, selected, mods):
    level = int(item.findtext('data/level', '999'))
    result = int(item.findtext('data/modslot', str(3 if level < 12 else 2 if level < 30 else 1)))
    for stats in stats_for(item, selected, mods):
        merged = stats.findtext('merge/modslot')
        if merged is not None:
            result = max(result, int(merged))
    return result


def validate(item, selected, mods, items):
    installed, occupied = [], set()
    special = item.find('subweapon') is not None
    for name in selected:
        mod = mods.get(name)
        if mod is None or name not in items or any(c in name for c in '#,\r\n'):
            raise ValueError('Unknown fixed mod: ' + name)
        if len(installed) >= capacity(item, installed, mods):
            raise ValueError('Fixed mod slots exceeded: ' + item.findtext('name'))
        use, types, tags = contexts(item, installed, mods)
        required = words(mod, 'requireTags')
        for case in mod.findall('stats/useSwitch/use'):
            if set(case.get('name', '').split(',')) & use:
                required |= words(case, 'requireTags')
        tag = mod.findtext('tag')
        if (not words(mod, 'use') & use or words(mod, 'excludeWeapontype') & types
                or words(mod, 'weapontype') and not words(mod, 'weapontype') & types
                or not required <= tags or tag in occupied
                or tag in words(item, 'blockedTags')
                or item.find('allowedModTags') is not None and tag not in words(item, 'allowedModTags')):
            raise ValueError('Incompatible fixed mod: ' + item.findtext('name') + ' / ' + name)
        # These features must be added with a fresh real-Flash oracle before admission.
        for path in ['installCondition', 'lifecycle', 'skill', 'stats/baseSwitch', 'stats/bulletSwitch']:
            if mod.find(path) is not None:
                raise ValueError('Unsupported fixed mod condition: ' + name + ' / ' + path)
        if mod.find('subweapon') is not None:
            if special or item.find('skill') is not None:
                raise ValueError('Fixed special slot collision: ' + item.findtext('name'))
            special = True
        occupied.add(tag)
        installed.append(name)


def power(item, slot, mods, enhance):
    """Independent arithmetic anchor for this closed set (no power overrides).

    Enhancement and mod percentage increments share the same additive zone.
    Native tests compare every final slot with EquipmentCalculator.calculatePure.
    """
    percentage = flat = Decimal(0)
    for stats in stats_for(item, slot['mods'], mods):
        for op in stats:
            if op.tag not in ('percentage', 'flat') and op.find('power') is not None:
                raise ValueError('Unsupported fixed power operator: ' + op.tag)
        percentage += Decimal(stats.findtext('percentage/power', '0')) / 100
        flat += Decimal(stats.findtext('flat/power', '0'))
    # Exact authored decimals keep positive half-integers from falling below .5
    # through Python's different addition order. All final anchors are then
    # checked against AVM1's actual PropertyOperators, not assumed equivalent.
    raw = Decimal(item.findtext('data/power')) * (Decimal(str(enhance[slot['enhancement']])) + percentage)
    return float(raw.quantize(Decimal(1), rounding=ROUND_HALF_UP) + flat)


def compensated(raw, row, profile, stage, is_long):
    """Independent numeric budget: solve the envelope by bisection, not AS2's quadratic."""
    if profile['family'] not in ('single_physical', 'native_magic'):
        return raw
    cls = ['ordinary', 'elite', 'instructor'].index(row['roleClass'])
    role = dict(suppress=1, line=.85, mobile=.65, breach=.35, precision=.2, flush=.25, counter=.5, dual=.5)[row['role']]
    q = role
    cap = [.20, .28, .35][cls] * q
    skill = profile['skill'] if stage == 2 else 0
    nano = profile['nano'] if stage == 2 else 0
    if profile['family'] == 'native_magic':
        q *= .25
        cap = min(cap, [.05, .08, .10][cls])
        skill = nano = 0
    g = q * max(0, min(120, 4 * row['level'] - 120))
    n = q * [.06, .10, .14][cls]
    u = (.5 + .03 * skill if is_long else .015 * skill) if skill else 0
    k = (30 if is_long else 20) if skill else 0
    total_cap = (.75 if is_long else .45) * role if skill else cap
    if raw * (1 + u) + k > raw * (1 + total_cap):
        u = k = 0
        total_cap = cap
    ceiling = raw * (1 + total_cap)
    nano = max(0, min(nano, math.floor(.025 * (ceiling - (raw * (1 + u) + k)) + 1e-9)))
    ceiling -= nano / .025
    def at(alpha):
        return (raw + alpha * g) * (1 + alpha * n + u) + k
    low, high = 0.0, 1.0
    for _ in range(90):
        mid = (low + high) / 2
        if at(mid) <= ceiling:
            low = mid
        else:
            high = mid
    return min(ceiling, at(low))
