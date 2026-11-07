"""Apply the reviewed fixed158 plan with an exact original-record comparison.

Only weapon slots, their installed material candidate, and actor-only gun profiles
are imported. Identity, schedules, AI programs and projectile budgets stay authored.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import fixed_roster as fixed

HERE = Path(__file__).resolve().parent
SLOTS = ('primary', 'secondary1', 'secondary2')


def digest(value):
    return hashlib.sha256(fixed.canonical(value)).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--proposal', type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(args.proposal.read_text('utf-8-sig'))
    source = fixed.read_source()
    if plan['schema'] != 'cf6-fixed158-offline-plan.v1' or len(plan['roster']) != 158:
        raise ValueError('Unexpected firepower proposal')
    originals = {r['unitIdentity']: r for r in source['roster']}
    items = fixed.item_catalog()
    config = ET.parse(fixed.ROOT / 'data/equipment/equipment_config.xml')
    tier_map = {x.get('name'): x.get('key') for x in config.findall('.//TierMapping')}
    runtime = dict(schema='cf6-fixed158-firepower.source.v1', proposalSha256=hashlib.sha256(args.proposal.read_bytes()).hexdigest(),
                   proposalSourceHead=plan['sourceHead'], defaultStage='C', profiles={})
    forms = set()
    for proposed in plan['roster']:
        row = originals[proposed['identity']]
        if digest(row) != proposed['originalSourceRecordSha256']:
            raise ValueError('Original fixed seat changed: ' + proposed['identity'])
        frozen = {k: v for k, v in row.items() if k not in SLOTS}
        if frozen != proposed['immutableRuntimeContract']:
            raise ValueError('Immutable contract changed: ' + proposed['identity'])
        profile = dict(schema=1, role=row['role'], roleClass=row['roleClass'], slots={})
        # Range/timing belongs to the existing AI program, not the replacement gun.
        row['programWeapon'] = dict(name=row['primary']['name'],
                                   weaponType=items[row['primary']['name']].get('weapontype'))
        for slot in SLOTS:
            chosen = copy.deepcopy(proposed[slot])
            if chosen is None:
                continue
            form = chosen['form']
            if form != (tier_map.get(chosen['tier']) if chosen['tier'] else 'data'):
                raise ValueError('Exact tier/form mapping failed: ' + str(chosen))
            if items[chosen['name']].find(form) is None:
                raise ValueError('Missing selected native form')
            if chosen['enhancement'] != row[slot]['enhancement']:
                raise ValueError('Unexpected enhancement change')
            forms.add((chosen['name'], form, chosen['tier']))
            chosen['serialized'] = '{}#{}#{}#{}'.format(chosen['name'], chosen['enhancement'],
                                                       chosen['tier'] or '', ','.join(chosen['mods']))
            row[slot] = chosen
            data = proposed['npcFirepower'][slot]
            profile['slots'][slot] = dict(name=chosen['name'], tier=chosen['tier'], enhancement=chosen['enhancement'],
                mods=chosen['mods'], family=data['family'], skill=data['stageC']['effectiveSkillLevel'],
                nano=data['stageC']['poisonReservation']['effectiveSource'], minPhysicalFactor=0.025,
                weaponOnlyRaw=data['stageAWeaponOnlyRaw'], expectedB=data['stageB']['rawPowerAfter'],
                expectedC=data['stageC']['rawPowerAfter'])
        row['lootRules']['materialCandidate'] = proposed['lootDelta']['proposedMaterialCandidate']
        runtime['profiles'][row['unitIdentity']] = profile
    source['admission']['forms'] = [dict(name=n, form=f, tier=t) for n, f, t in sorted(forms, key=lambda x: (x[0], x[1]))]
    admitted = {r['name'] for r in source['admission']['weapons']}
    for name in sorted({x[0] for x in forms} - admitted):
        source['admission']['weapons'].append(dict(name=name, decision='B',
            reason='Fixed158 exact-form candidate; global balance audit is unchanged. Native validation required.'))
    fixed.SOURCE.write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (HERE / 'soldier-firepower.source.json').write_text(json.dumps(runtime, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(personnel=158, slots=sum(len(p['slots']) for p in runtime['profiles'].values()),
                         exactForms=len(forms), proposalSha256=runtime['proposalSha256'])))


if __name__ == '__main__':
    main()
