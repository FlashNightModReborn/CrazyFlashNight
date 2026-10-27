"""Audit the explicit level-adjustment policy and freeze live XML for Flash regression."""
from pathlib import Path
import copy
import hashlib
import json
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tmp/unified61-review'
EXCLUDED = ('Origin12战术版', 'AA12战术版', 'Vepr12战术版', '极品UZI的KING版')


def main():
    paths = set()
    items = []
    excluded = []
    for path in sorted((ROOT / 'data/items').glob('*.xml')):
        if path.name != '防具_40+级.xml' and not path.name.startswith('武器'):
            continue
        paths.add(path)
        for item in E.parse(str(path)).getroot().findall('item'):
            name = item.findtext('name')
            if item.findtext('allowedModTags') == '等级校正':
                assert item.findtext('data/modslot') == '1', name
                assert '电力' in item.findtext('inherentTags', '').split(','), name
                assert '等级校正' not in item.findtext('blockedTags', '').split(','), name
                items.append(copy.deepcopy(item))
            elif name in EXCLUDED:
                assert item.find('allowedModTags') is None, name
                excluded.append(copy.deepcopy(item))
    assert len(items) == 26 and len(excluded) == 4
    assert sum(item.findtext('setId') == 'unified_type_61_armor' for item in items) == 5
    mods = []
    mod_list = ROOT / 'data/items/equipment_mods/list.xml'
    paths.add(mod_list)
    for entry in E.parse(str(mod_list)).getroot().findall('items'):
        path = mod_list.parent / entry.text
        paths.add(path)
        mods.extend(copy.deepcopy(mod) for mod in E.parse(str(path)).getroot().findall('mod'))
    allowed = [mod for mod in mods if mod.findtext('tag') == '等级校正']
    assert {mod.findtext('name') for mod in allowed} == {'电脑芯片', '成长的勋章'}
    for mod in allowed:
        stats = mod.find('stats')
        assert len(stats) == 1 and stats[0].tag == 'flat'
        assert len(stats[0]) == 1 and stats[0][0].tag == 'level'
        assert int(stats[0][0].text) < 0
        assert all(mod.find(field) is None for field in ('lifecycle', 'skill', 'subweapon'))
    identities = [{'path': path.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                  for path in sorted(paths)]
    closure = hashlib.sha256(json.dumps(identities, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode('utf-8')).hexdigest()
    fixture = E.Element('fixture')
    E.SubElement(fixture, 'sourceClosure').text = closure
    for name, rows in (('items', items), ('mods', mods), ('excluded', excluded)):
        parent = E.SubElement(fixture, name)
        for row in rows:
            parent.append(row)
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / 'mod-policy-fixture.xml'
    target.write_bytes(E.tostring(fixture, encoding='utf-8', xml_declaration=True, pretty_print=True))
    report = {'items': [item.findtext('name') for item in items], 'closedItems': len(items), 'mods': len(mods),
              'allowedMods': [mod.findtext('name') for mod in allowed], 'excludedPreserved': list(EXCLUDED),
              'sourceClosure': closure, 'sources': identities, 'fixtureSha256': hashlib.sha256(target.read_bytes()).hexdigest()}
    (OUT / 'mod-policy-fixture.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k not in ('sources', 'items')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
