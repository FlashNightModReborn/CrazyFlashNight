"""2026-09-10 accepted XML parameters. Offline arithmetic, never field evidence."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

import jk_followup as j

P = j.PROFILE
SUB = j.m.ITEMS[j.QJZ].find('subweapon')


def build(tier=13, set_id=j.TI, weapon=j.QJZ):
    return j.configured(set_id, weapon, tier, neck='枪械大加成项链')


def cast(b, hp, mp, shield):
    maximum = j.shield_capacity(b, P['bloodShieldRatio'])
    if hp <= 1 or mp < 0 or not b['hasBloodSword']:
        return {'accepted': False}
    paid_hp = min(hp - 1, hp * P['bloodSkillHpRatio'])
    paid_mp = min(mp, max(0, maximum - shield) * P['shieldMpPerPoint'])
    return {'accepted': True, 'hpPaid': paid_hp, 'mpPaid': paid_mp,
            'hp': hp - paid_hp, 'mp': mp - paid_mp, 'shield': maximum,
            'bonus': b['bloodLoss'] * paid_hp / b['hpMax'] if mp > paid_mp else 0,
            'bonusSecondsAfterSlam': P['bloodSkillBuffSeconds']}


def blood_wave_profile():
    """读取真实动作的独立发射次数；不把联弹段数或视觉个数当击溃次数。"""
    path = 'flashswf/arts/things0/LIBRARY/Codex/Ti61-血剑战技/战技容器-猩红天秤.xml'
    j.m.SOURCES.add(path)
    ns = {'x': 'http://ns.adobe.com/xfl/2008/'}
    tree = ET.parse(j.ROOT / path)
    waves, blade_actions = [], 0
    for frame in tree.findall('.//x:DOMFrame', ns):
        code = frame.findtext('x:Actionscript/x:script', '', ns)
        if '子弹区域shoot传递(waveProps)' in code:
            waves.append(int(frame.attrib['index']) + 1)
        if '刀口位置生成子弹(_parent, bladeProps)' in code:
            blade_actions += 1
    blade_count = int(j.m.ITEMS[j.BLOOD].findtext('data/bladeCount'))
    contacts = blade_actions * blade_count + len(waves)
    return {'crumblePercent': P['bloodCrumblePercent'], 'executePercent': P['bloodExecutePercent'],
            'powerPerSegmentBloodLossRatio': P['bloodPulsePowerRatio'],
            'waveFrames': waves, 'bladeActions': blade_actions, 'bladeCount': blade_count,
            'maximumFinisherChecksIfEveryEmissionContactsOnce': contacts,
            'maxHpReductionPercentWithoutRoundingOrVulnerability':
                (1 - (1 - P['bloodCrumblePercent'] / 100) ** contacts) * 100,
            'evidence': 'source timeline count only; contact, target coverage and frame time require Flash testing'}


def produce():
    b = build()
    peak = float(SUB.findtext('hitBehavior/peak'))
    capacity = int(SUB.findtext('capacity'))
    ray = dict(j.CONFIG['ray'], durationFrames=int(SUB.findtext('hitBehavior/durationFrames')),
               intervalFrames=round(float(SUB.findtext('cd')) * .03),
               directDamagePerContact=float(SUB.findtext('power')), directDamageBeforeDefence=True)
    shields, casts, fire = [], [], []
    for tier in (0, 1, 5, 9, 13):
        v = build(tier)
        shield = j.shield_capacity(v, P['bloodShieldRatio'])
        shields.append({'tier': tier, 'hp': v['hpMax'], 'mp': v['mpMax'], 'armorHp': v['armorHp'],
                        'bloodLoss': v['bloodLoss'], 'shield': shield,
                        'hpPlusShieldAt130Percent': v['hpMax'] * 1.3 + shield,
                        'emptyNaturalPrice': shield * P['shieldMpPerPoint'] + P['startupMp'],
                        'fullBlueShieldAfterStartup': min(shield, max(0, v['mpMax'] - P['startupMp']) / P['shieldMpPerPoint'])})
    shield = shields[-1]['shield']
    for hp_ratio in (1.3, 1, .5):
        for shield_ratio in (0, .1, 1):
            casts.append({'hpRatio': hp_ratio, 'shieldRatio': shield_ratio,
                          **cast(b, b['hpMax'] * hp_ratio, b['mpMax'], shield * shield_ratio)})
    with patch.dict(j.CONFIG, {'ray': ray}):
        for online in (1, .8, .6, 0):
            for p in (0, peak):
                schedule = j.firing_schedule(b, j.QJZ, 'roll_cd', capacity if p else 0)
                trials = [j.outgoing(b, peak=p, ray_capacity=capacity, schedule=schedule,
                                    counters=True, seed=i, online_fraction=online,
                                    crumble_vulnerability=True) for i in range(1, 33)]
                fire.append({'weapon': j.QJZ, 'onlineFraction': online, 'peak': p,
                             'ttkSeconds': j.summary([x['ttk'] for x in trials]),
                             'meanShotBuff': trials[0]['meanMainBuff'], 'batteryClips': trials[0]['rayClipsLoadedIncludingInitial']})
        advanced = build(13, j.ADVANCED, j.M134)
        trials = [j.outgoing(advanced, j.M134, policy='normal', counters=True, seed=i) for i in range(1, 33)]
        fire.append({'weapon': j.M134, 'set': j.ADVANCED,
                     'ttkSeconds': j.summary([x['ttk'] for x in trials])})
    blood_wave = blood_wave_profile()
    sources = sorted(j.m.SOURCES | {str(Path(__file__).relative_to(j.ROOT)).replace('\\', '/')})
    return {'status': 'local_implementation_values_field_validation_pending',
            'sourceSha256': {p: hashlib.sha256((j.ROOT / p).read_bytes()).hexdigest() for p in sources},
            'parameters': {'shieldCoefficient': P['bloodShieldRatio'], 'shieldMpPerPoint': P['shieldMpPerPoint'],
                           'rechargeSeconds': P['fullRechargeSeconds'], 'lazyDodgeMaximum': P['shieldLazyDodge'],
                           'rayPeak': peak, 'rayCapacity': capacity, 'rayIntervalFrames': ray['intervalFrames'],
                           'bloodCooldownMs': int(j.m.ITEMS[j.BLOOD].findtext('skill/cd'))},
            'loadouts': shields, 'bloodSkill': casts, 'bloodWave': blood_wave, 'fire': fire,
            'recoveryComparison': {'advancedDefence': advanced['defence'], 'titaniumDefence': b['defence'],
                                   'advancedHp': advanced['hpMax'], 'titaniumHp': b['hpMax'],
                                   'oneFullMpRecoveryShield': b['mpMax'] / P['shieldMpPerPoint']},
            'limits': ['Two avoided/partially hit assaults require field testing; no promise to tank two full space slashes.',
                       'TTK uses source formula contacts and counter sensitivity, not collision/AI/field probabilities.',
                       'Offensive schedule starts with paid loaded batteries; initialLoaded=0 requires preloading.',
                       'Firing may refill through roll before 17 rays run out; there is no artificial 60 percent cap.',
                       'Blood animation and weapon switching interrupt firing; TTK excludes this optional buff.',
                       'Four HP potions versus two HP/two MP must compare actual potion amount, overheal and wasted recovery.',
                       'Lazy dodge is the existing threat-dependent maximum; true damage retains its existing dodge bypass.']}


class Contract(unittest.TestCase):
    def test_blood_wave_budget(self):
        profile = blood_wave_profile()
        self.assertEqual((profile['crumblePercent'], profile['executePercent']), (.09, 9))
        self.assertEqual(profile['waveFrames'], [26, 29, 32, 35, 38, 41, 44])
        self.assertEqual(profile['maximumFinisherChecksIfEveryEmissionContactsOnce'], 13)
        self.assertLess(profile['maxHpReductionPercentWithoutRoundingOrVulnerability'], 1.2)

    def test_source_parameters(self):
        self.assertEqual((P['bloodShieldRatio'], P['shieldMpPerPoint'], P['fullRechargeSeconds']), (1.5, .5, 4))
        self.assertEqual((SUB.findtext('capacity'), SUB.findtext('reserveName')), ('17', '能量电池'))

    def test_low_blade_does_not_gain_overheal_total_pool(self):
        values = [build(i)['hpMax'] * 1.3 + j.shield_capacity(build(i), 1.5) for i in (1, 5, 9, 13)]
        self.assertEqual(sorted(values), values)

    def test_skill_decisions(self):
        b = build()
        maximum = j.shield_capacity(b, 1.5)
        empty = cast(b, b['hpMax'], b['mpMax'], 0)
        self.assertEqual(empty['mp'], 0)
        self.assertEqual(empty['bonus'], 0)
        full = cast(b, b['hpMax'], b['mpMax'], maximum)
        self.assertEqual(full['mpPaid'], 0)
        self.assertAlmostEqual(full['bonus'], b['bloodLoss'] * .35)
        half = cast(b, b['hpMax'] / 2, b['mpMax'], maximum)
        self.assertAlmostEqual(half['bonus'], full['bonus'] / 2)
        extra = cast(b, b['hpMax'] * 1.3, b['mpMax'], maximum)
        self.assertAlmostEqual(extra['bonus'], full['bonus'] * 1.3)
        self.assertFalse(cast(b, 1, 20, 0)['accepted'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', action='store_true')
    parser.add_argument('--out', type=Path, default=j.ROOT / 'tmp/ti61-implementation/model.json')
    args = parser.parse_args()
    if args.test:
        unittest.main(argv=['accepted'], verbosity=2)
    else:
        report = produce()
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({key: report[key] for key in ('parameters', 'loadouts', 'fire', 'recoveryComparison')}, ensure_ascii=False, indent=2))
