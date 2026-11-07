"""Apply the reviewed post-proposal loadout stage without rewriting the Pro input."""
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET
import fixed_roster as fixed
import loadout_rules as rules

PLAN = fixed.HERE / 'soldier-loadout-plan.source.json'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    plan = json.loads(PLAN.read_text('utf-8'))
    source, fire = fixed.read_source(), fixed.firepower_source()
    items, mods = fixed.item_catalog(), fixed.mod_catalog()
    enhance = {int(x.get('index')): float(x.text) for x in ET.parse(fixed.ROOT / 'data/equipment/equipment_config.xml').findall('.//LevelStatList/Level')}
    used = set()
    count = expanded = 0
    for row in source['roster']:
        for key in ('primary', 'secondary1', 'secondary2'):
            slot = row[key]
            if slot is None:
                continue
            entry = plan['slots'][row['unitIdentity'] + '/' + key]
            if {k: slot.get(k) for k in ('name', 'form', 'tier', 'enhancement')} != entry['identity']:
                raise ValueError('Loadout weapon identity drift: ' + row['unitIdentity'] + '/' + key)
            if slot['mods'] not in (entry['before'], entry['after']):
                raise ValueError('Unreviewed installed mod drift: ' + row['unitIdentity'] + '/' + key)
            slot['mods'] = list(entry['after'])
            slot['serialized'] = '{}#{}#{}#{}'.format(slot['name'], slot['enhancement'], slot.get('tier') or '', ','.join(slot['mods']))
            item = fixed.effective_item(slot, items)
            rules.validate(item, slot['mods'], mods, items)
            if key != 'primary' and (len(slot['mods']) > 1 or '手枪卡宾转换套件' in slot['mods']):
                raise ValueError('Independent sidearm policy violated')
            if key == 'primary' and entry['exception'] is None and (len(slot['mods']) != 3 or slot['mods'][0] != '战术鱼骨零件'):
                raise ValueError('Missing mandatory longgun rail')
            raw = rules.power(item, slot, mods, enhance)
            fp = fire['profiles'][row['unitIdentity']]['slots'][key]
            fp.update(mods=slot['mods'], weaponOnlyRaw=raw,
                      expectedB=rules.compensated(raw, row, fp, 1, key == 'primary'),
                      expectedC=rules.compensated(raw, row, fp, 2, key == 'primary'))
            used.update(slot['mods'])
            expanded += '战术鱼骨零件' in slot['mods']
            count += 1
        installed = [name for key in ('primary', 'secondary1', 'secondary2') if row[key]
                     for name in row[key]['mods']]
        if row['lootRules']['materialCandidate'] not in installed:
            row['lootRules']['materialCandidate'] = next((n for n in installed if n != '战术鱼骨零件'), None)
    if count != len(plan['slots']) or count != 282:
        raise ValueError('Loadout plan does not cover all 282 slots')
    source['admission']['mods'] = [dict(name=n, decision='A') for n in sorted(used)]
    fingerprint = hashlib.sha256(PLAN.read_bytes()).hexdigest()
    source['loadoutRevision'] = dict(version=plan['version'], planSha256=fingerprint)
    fire['loadoutPlanSha256'] = fingerprint
    fire['numericExpectationSource'] = 'Closed XML operators + independent bisection envelope; all 282 raw powers require real EquipmentCalculator oracle.'
    for path, value in [(fixed.SOURCE, source), (fixed.HERE / 'soldier-firepower.source.json', fire)]:
        data = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
        if args.check:
            if path.read_text('utf-8') != data:
                raise ValueError('Stale reviewed loadout stage: ' + path.name)
        else:
            path.write_text(data, encoding='utf-8')
    print(json.dumps(dict(slots=count, expandedLongguns=expanded, admittedMods=len(used), check=args.check)))


if __name__ == '__main__':
    main()
