"""Closed, executable action tables for fixed158; prose is never evaluated.

Frames below are active 30 Hz frames. Native weapon cadence, animation terminal
events and projectile retirement are additional gates, never inferred deadlines.
"""
import copy
import json
from pathlib import Path


TACTICS = ('shield_breach reverse_rear_guard fixed_bastion pursuit_leash segmented_lane '
           'advance_flush landing_watch bright_burst relocate_then_flush range_rotation '
           'shield_counter judgment_line disciplined_screen feint_retreat alternating_fire '
           'punish_commit paired_windows weapon_handoff reserve_gate robot_observer '
           'threshold_flush final_phase_guard').split()


def warning(frames, mode='primary', lock=0, **kwargs):
    # A ready gun acquires its aim on the next active frame. Throws and
    # under-barrel launches keep a short physical preparation in their pose.
    frames = min(frames, {'primary': 1, 'dual': 1, 'sub': 3, 'throw': 6}[mode])
    return dict(kind='warning', frames=frames, mode=mode, lock=min(lock, frames), **kwargs)


def fire(events=1, mode='primary', gap=1, frames=75, **kwargs):
    return dict(kind='fire', frames=frames, mode=mode, events=events, gap=gap, **kwargs)


def wait(frames, **kwargs):
    return dict(kind='wait', frames=frames, mode='none', **kwargs)


def move(direction, distance, frames, **kwargs):
    return dict(kind='move', mode='none', direction=direction, distance=distance, frames=frames, **kwargs)


def rest(frames):
    return dict(kind='recover', frames=frames, mode='none')


def primary(events, windup, recovery, *, lock=0, frames=75, gap=1):
    return [warning(windup, lock=lock), fire(events, frames=frames, gap=gap), rest(recovery)]


def dual(events, recovery, windup=18, retreat=0):
    result = [warning(windup, 'dual'), fire(events, 'dual', frames=75)]
    if retreat:
        result.insert(0, move('away', retreat, 18, pose='dual'))
    return result + [rest(recovery)]


def compile_program(profile, weapon_type, weapon_name, actual_weapon=None):
    ext, budget, scalar = profile['extensions'], profile['budget'], profile['scalars']
    actual_type = actual_weapon['weaponType'] if actual_weapon is not None else weapon_type
    actual_name = actual_weapon['name'] if actual_weapon is not None else weapon_name
    tactic = ext['majorTactic']
    recovery = scalar['特种兵战术_rifleRestFrames']
    stages = primary(budget['primaryTriggerLimit'], ext['windupFrames'], recovery,
                     lock=ext['lockAimLastFrames'], frames=scalar['特种兵战术_rifleFireFrames'])
    p = dict(schema=1, trigger='ordinary', waiting='acquire', stages=stages,
             recovery=recovery, danger=False, maxDistance=ext['shootRange'],
             minDistance=0, lane=ext['laneRange'], stopDistance=ext['approachStopRange'],
             tether=360, mixed=False, capabilities=['fixed_action', 'weapon_commit', 'weapon_pose'])
    if ext['subweaponBurstLimit']:
        lo, hi = ext['subweaponDistance']
        stages[-1:-1] = [wait(max(12, ext['subweaponMinActionAgeAfterFirstPrimary'] or 0)),
                         warning(ext['windupFrames'], 'sub', optional=True, minDistance=lo, maxDistance=hi),
                         fire(1, 'sub', minDistance=lo, maxDistance=hi)]
        p['capabilities'] += ['subweapon', 'projectile_lifetime']
    if budget['sidearmSynchronizedTriggerLimit']:
        p['dual'] = dual(budget['sidearmSynchronizedTriggerLimit'], recovery, ext['windupFrames'], 80)
    if ext['finiteThrowableCount']:
        p['grenade'] = [warning(24, 'throw', minDistance=180, maxDistance=480),
                      fire(1, 'throw', minDistance=180, maxDistance=480), rest(max(90, recovery))]
    if ext.get('shieldContactFireInterlock'):
        p['shield'] = [dict(kind='charge', mode='none', frames=90, distance=120),
                       warning(18), fire(budget['primaryTriggerLimit']), rest(recovery)]
        p['capabilities'].append('charge_terminal')
    # Preferred distance and bespoke tactical windows keep their authored meaning.
    # The ordinary primary can cover a wider visible lane while the soldier moves.
    reach = {'霰弹枪': 900, '突击步枪': 1040, '战斗步枪': 1120, '机枪': 1120,
             '压制机枪': 1120, '狙击步枪': 1200, '反器材武器': 1200,
             '特殊': 1040, '发射器': ext['shootRange']}[weapon_type]
    if weapon_name == '战术版喷火器':
        reach = ext['shootRange']
    p['fireDistance'] = max(reach, p['maxDistance'])
    p['pressure'] = primary(min(3, budget['primaryTriggerLimit']), 1,
                            18 if tactic else recovery, frames=36)
    if tactic is None:
        return finalize(p, profile, actual_type, actual_name)
    if tactic not in TACTICS:
        raise ValueError('Unknown instructor action: ' + str(tactic))
    p.update(trigger=tactic, waiting='hold', danger=True, capabilities=p['capabilities']+['danger_lease', 'projectile_lifetime'])
    p.pop('grenade', None)
    # A missing encounter event must not disable the soldier's firearm.
    # This is a separate bounded cycle, never an extra shot in a signature.
    # Explicit programs deliberately retain action counters across every stage.
    if tactic == 'shield_breach':
        p.update(stages=[dict(kind='charge', mode='none', frames=90, distance=120),
                         warning(18), fire(), rest(60)], recovery=60, minDistance=180,
                 waiting='close', tether=240, phase2=dual(budget['sidearmSynchronizedTriggerLimit'], 60, retreat=100))
        p['capabilities'].append('charge_terminal')
    elif tactic == 'reverse_rear_guard':
        p.update(stages=[move('away',100,18), warning(24,lock=9,minDistance=180),
                         fire(minDistance=180),rest(60)], recovery=60, tether=240)
        p['capabilities'].append('direct_attack')
    elif tactic == 'fixed_bastion':
        p.update(stages=primary(8,15,48,frames=48), recovery=48, waiting='anchor', tether=48)
    elif tactic == 'pursuit_leash':
        p.update(stages=[move('toward',180,30,stopDistance=180),warning(18,'dual'),
                         fire(1,'dual'),rest(48)], recovery=48, minDistance=180,
                 waiting='primary_fallback', fallback=primary(3,12,42,frames=36))
    elif tactic == 'segmented_lane':
        p.update(stages=[warning(15),fire(2,gap=2),move('lane',24,18),
                         warning(15),fire(),rest(54)], recovery=54, waiting='acquire')
    elif tactic == 'advance_flush':
        p.update(stages=[warning(24),fire(3),wait(12),warning(24,'sub',minDistance=220,maxDistance=420),
                         fire(1,'sub',minDistance=220,maxDistance=420),
                         dict(kind='projectile_wait',mode='none',frames=90),
                         move('toward',120,24,stopDistance=180),rest(66)], recovery=66,
                 minDistance=220,maxDistance=420,waiting='primary_fallback',fallback=primary(3,24,66,frames=48))
        p['capabilities'].append('subweapon')
    elif tactic == 'landing_watch':
        p.update(stages=[warning(27,lock=9),fire(gap=30),warning(27,lock=9),fire(),rest(75)],recovery=75)
        p['capabilities'].append('wings_recovery')
    elif tactic == 'bright_burst':
        p.update(stages=primary(2,21,66,gap=6), recovery=66, waiting='acquire')
    elif tactic == 'relocate_then_flush':
        # Relocation is part of the actual reload adapter, before its terminal
        # receipt. The initial magazine token never invents a reload or smoke.
        p.update(stages=[wait(18,visible=True),warning(30),fire(),rest(90)],recovery=90,
                 minDistance=220,maxDistance=420,waiting='reload')
        p['capabilities'].append('reload_commit')
    elif tactic == 'range_rotation':
        p.update(stages=[warning(12),fire(3),dict(kind='mode_hold',mode='none',frames=45),
                         move('toward',120,24,stopDistance=240),warning(18,'dual',maxDistance=240),
                         fire(1,'dual',maxDistance=240),move('away',120,24,stopDistance=360),rest(48)],
                 recovery=48, mixed=True, waiting='acquire')
    elif tactic == 'shield_counter':
        p.update(stages=[warning(18,'sub'),fire(1,'sub'),rest(48)],recovery=48,
                 minDistance=180,maxDistance=240,waiting='primary_fallback',fallback=primary(3,18,48,frames=42))
        p['capabilities'] += ['shield_recovery','subweapon']
    elif tactic == 'judgment_line':
        p.update(stages=primary(1,45,75,lock=15),recovery=75,minDistance=180,waiting='g1111_pair')
        p['capabilities'].append('g1111_pair')
    elif tactic == 'disciplined_screen':
        p.update(stages=primary(1,36,75),recovery=75,minDistance=220,maxDistance=460,waiting='g1111_pair')
        p['capabilities'].append('g1111_pair')
    elif tactic == 'feint_retreat':
        p.update(stages=[move('away',100,18),warning(18,'sub',minDistance=180,maxDistance=240,approaching=True),
                         fire(1,'sub',minDistance=180,maxDistance=240),rest(60)],recovery=60,tether=220,
                 waiting='primary_fallback',fallback=primary(3,18,42,frames=42))
        p['capabilities'].append('subweapon')
    elif tactic == 'alternating_fire':
        p.update(stages=[warning(24),fire(3),wait(24),
                         warning(24,'sub',optional=True,minDistance=220,maxDistance=420),
                         fire(1,'sub',minDistance=220,maxDistance=420),rest(66)],recovery=66,waiting='acquire')
        p['capabilities'].append('subweapon')
    elif tactic == 'punish_commit':
        p.update(stages=[dict(kind='draw',mode='primary',frames=60),warning(18),fire(),wait(9),fire(),rest(75)],
                 recovery=75,minDistance=180,maxDistance=240)
        p['capabilities'].append('player_commit')
    elif tactic == 'paired_windows':
        p.update(stages=primary(8,15,48,frames=48),recovery=48,waiting='pair')
        p['capabilities'].append('alternating_pair')
    elif tactic == 'weapon_handoff':
        p.update(stages=[warning(18),fire(2),warning(18,'dual',maxDistance=240),
                         fire(1,'dual',maxDistance=240),rest(60)],recovery=60,mixed=True,waiting='close')
    elif tactic == 'reserve_gate':
        p.update(stages=primary(1,30,90),recovery=90,waiting='anchor',tether=48)
        p['capabilities'].append('vanguard_event')
    elif tactic == 'robot_observer':
        p.update(stages=primary(1,27,75,lock=9),recovery=75)
        p['capabilities'].append('robot_recovery')
    elif tactic == 'threshold_flush':
        p.update(stages=[warning(24),fire(),wait(7),fire(),rest(66)],recovery=66,
                 minDistance=220,maxDistance=420)
        p['capabilities'].append('birth_crossing')
    elif tactic == 'final_phase_guard':
        p.update(stages=[warning(18),fire(3),warning(18,'sub',optional=True,minDistance=180,maxDistance=240),
                         fire(1,'sub',minDistance=180,maxDistance=240),rest(60)],recovery=60,
                 waiting='boss_guard',tether=220,phase2=dual(3,60,retreat=100))
        p['capabilities'] += ['human_guard','subweapon']
    return finalize(p, profile, actual_type, actual_name)


def finalize(program, profile, weapon_type, weapon_name):
    policy = json.loads((Path(__file__).parent / 'soldier-suppression.source.json').read_text(encoding='utf-8'))
    if (policy['schema'] != 'cf6-machinegun-suppression.v1' or policy['weaponTypes'] != ['机枪','压制机枪']
            or policy['fireFrames'] != 60 or policy['minimumRecoveryFrames'] != 30):
        raise ValueError('Unknown machinegun time budget')
    if weapon_type not in policy['weaponTypes']:
        return validate(program, profile)
    budget = profile['budget']
    original_limit = budget['primaryTriggerLimit']
    units_per_trigger = budget.get('primaryFinalDamageUnitsPerAction', budget['primaryProjectilesPerAction']) / original_limit
    program['suppression'] = dict(weaponName=weapon_name, weaponType=weapon_type, fireFrames=60, recoveryFrames=30)
    # Native code can dispatch at most one primary trigger in an active frame.
    # Sixty is the physical two-second upper bound, rather than a shorter burst cap.
    for name in ('stages','dual','phase2','fallback','shield','grenade','pressure'):
        stages = program.get(name, [])
        primary_stages = [s for s in stages if s['kind'] == 'fire' and s['mode'] == 'primary']
        if not primary_stages:
            continue
        total = sum(s['events'] for s in primary_stages)
        remaining = 60
        for index, stage in enumerate(primary_stages):
            frames = remaining if index == len(primary_stages)-1 else max(1, min(remaining-(len(primary_stages)-index-1), 60*stage['events']//total))
            remaining -= frames
            stage.update(frames=frames, events=frames, gap=1)
        stages[-1]['frames'] = 30
    budget['primaryTriggerLimit'] = 60
    budget['primaryProjectilesPerAction'] = 60 * budget['primarySplit']
    budget['primaryFinalDamageUnitsPerAction'] = int(60 * units_per_trigger)
    budget['longgunWithSubProjectilesPerAction'] = budget['primaryProjectilesPerAction'] + budget['subweaponProjectilesPerAction']
    return validate(program, profile)


def validate(program, profile):
    valid_kinds = {'warning','fire','wait','move','recover','charge','projectile_wait','mode_hold','draw'}
    budget = profile['budget']
    for name in ('stages','dual','phase2','fallback','shield','grenade','pressure'):
        stages = program.get(name)
        if stages is None:
            continue
        if not 2 <= len(stages) <= 16 or stages[-1]['kind'] != 'recover':
            raise ValueError('Unbounded action sequence')
        counts = dict(primary=0,dual=0,sub=0,throw=0)
        for stage in stages:
            if stage['kind'] not in valid_kinds or not 1 <= stage['frames'] <= 180:
                raise ValueError('Unknown stage or unbounded duration')
            if stage['mode'] not in ('none',*counts):
                raise ValueError('Unknown weapon mode')
            if stage['kind'] == 'fire':
                counts[stage['mode']] += stage['events']
            if stage['kind'] == 'warning' and not 0 <= stage['lock'] <= stage['frames']:
                raise ValueError('Invalid locked warning')
        if (counts['primary'] > budget['primaryTriggerLimit']
                or counts['dual'] > budget['sidearmSynchronizedTriggerLimit']
                or counts['sub'] > profile['extensions']['subweaponBurstLimit']
                or counts['throw'] > profile['extensions']['finiteThrowableCount']):
            raise ValueError('Program exceeds real weapon event ceiling')
        if counts['primary'] and counts['dual'] and not program['mixed']:
            raise ValueError('Undeclared composite primary/dual program')
    program['capabilities'] = sorted(set(program['capabilities']))
    return copy.deepcopy(program)
