"""Real XML/config fixture for the fixed158 equipment admission oracle."""
import argparse
import copy
import hashlib
import json
import xml.etree.ElementTree as ET
import fixed_roster as fixed
import loadout_rules as rules


def generate():
    source, fire = fixed.read_source(), fixed.firepower_source()
    items, mods = fixed.item_catalog(), fixed.mod_catalog()
    root = ET.Element('fixture')
    root.set('planSha256', source['loadoutRevision']['planSha256'])
    config = ET.parse(fixed.ROOT / 'data/equipment/equipment_config.xml').getroot()
    config.tag = 'config'
    root.append(config)
    node = ET.SubElement(root, 'items')
    names = sorted({r[k]['name'] for r in source['roster'] for k in ('primary', 'secondary1', 'secondary2') if r[k]})
    for name in names:
        node.append(copy.deepcopy(items[name]))
    node = ET.SubElement(root, 'mods')
    for name in sorted(mods):
        node.append(copy.deepcopy(mods[name]))
    node = ET.SubElement(root, 'cases')
    for row in source['roster']:
        for key in ('primary', 'secondary1', 'secondary2'):
            slot = row[key]
            if slot is None:
                continue
            case = ET.SubElement(node, 'case')
            data = dict(id=row['unitIdentity'] + '/' + key, name=slot['name'], tier=slot.get('tier') or '',
                        enhancement=slot['enhancement'], selected=','.join(slot['mods']),
                        expectedPower=fire['profiles'][row['unitIdentity']]['slots'][key]['weaponOnlyRaw'],
                        expectedSlots=rules.capacity(fixed.effective_item(slot, items), slot['mods'], mods),
                        sidearm=key != 'primary')
            for k, v in data.items():
                ET.SubElement(case, k).text = str(v).lower() if isinstance(v, bool) else str(v)
    ET.indent(root)
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = fixed.ROOT / 'tmp/cf6-loadout-oracle/fixture.xml'
    data = generate()
    if args.check:
        if not target.exists() or target.read_bytes() != data:
            raise ValueError('Stale real loadout fixture')
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print(json.dumps(dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), check=args.check)))
