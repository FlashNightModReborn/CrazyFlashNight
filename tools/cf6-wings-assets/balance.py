"""Register/check Wings from the enhanced-agent baseline and the authoritative monster formula."""
from pathlib import Path
import argparse
import copy
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LINK = '敌人-CF6Wings'
DISPLAY_NAME = 'Wings'
UNIT_ID = 464
PROPERTY_FILE = 'CF6重制敌人.xml'
SOURCE = '敌人-闪6特工'
FIELDS = {'最小经验值': 'expMin', '最大经验值': 'expMax', 'hp_min': 'hpMin', 'hp_max': 'hpMax',
          '空手攻击力_min': 'atkMin', '空手攻击力_max': 'atkMax', '基本防御力_min': 'defMin', '基本防御力_max': 'defMax'}
FLAG_KEYS = {'阶段': 'stage', '速度系数': 'speedFactor', '攻速系数': 'atkSpeedFactor',
             '攻击倍率': 'atkMultiplier', '段数系数': 'segmentFactor', '霸体系数': 'superArmorFactor',
             '档次系数': 'tierFactor', '成长系数': 'growthFactor', '高攻低血防系数': 'highAtkFactor', '高防低血系数': 'highDefFactor'}


def expected():
    source = E.parse(ROOT / 'data/enemy_properties/诺亚新敌人.xml').getroot().find(SOURCE)
    flags = {node.tag: float(node.text) for node in source.find('标识')}
    flags.update(阶段=7, 档次系数=8)
    inputs = {FLAG_KEYS[key]: value for key, value in flags.items()}
    expression = "import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';console.log(JSON.stringify(computeMonsterRow(" + json.dumps(inputs) + ")));"
    values = json.loads(subprocess.check_output(['node', 'tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs', '-e', expression],
                                               cwd=ROOT, text=True, encoding='utf-8'))
    entry = copy.deepcopy(source)
    entry.tag = LINK
    entry.find('displayname').text = DISPLAY_NAME
    for key, value in flags.items():
        entry.find('标识/' + key).text = f'{value:g}'
    for key, formula in FIELDS.items():
        entry.find(key).text = str(math.floor(values[formula] + 0.5))
    units = json.loads((ROOT / 'data/units/units.json').read_text(encoding='utf-8-sig'))
    unit = copy.deepcopy(next(row for row in units if row['spritename'] == SOURCE))
    unit.update(id=UNIT_ID, spritename=LINK, name=DISPLAY_NAME)
    receipt = {'formula': 'tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts',
               'source': SOURCE, 'unitId': UNIT_ID, 'linkage': LINK, 'requestedStage': 7, 'requestedTier': 8,
               'input': inputs, 'integerPanel': {key: int(entry.find(key).text) for key in FIELDS},
               'flags': flags}
    return entry, unit, receipt, units


def canonical(element):
    return (element.tag, (element.text or '').strip(), tuple(canonical(child) for child in element))


def update_registration_text(text, unit):
    """Replace only this unit, keeping unrelated registry formatting intact."""
    decoder = json.JSONDecoder()
    pos = text.index('[') + 1
    encoded = '\n  '.join(json.dumps(unit, ensure_ascii=False, indent=2).splitlines())
    while True:
        while text[pos].isspace() or text[pos] == ',':
            pos += 1
        if text[pos] == ']':
            break
        row, end = decoder.raw_decode(text, pos)
        if row['id'] == UNIT_ID:
            return text if row == unit else text[:pos] + encoded + text[end:]
        pos = end
    prefix = text[:pos].rstrip()
    return prefix + (',' if json.loads(text) else '') + '\n  ' + encoded + '\n' + text[pos:]


def update_enemy_text(text, entry):
    """Update this unit only; preserve every other unit, comment and its formatting."""
    existing = E.fromstring(text).findall(LINK)
    if len(existing) > 1:
        raise ValueError('Duplicate Wings property entry')
    if existing and canonical(existing[0]) == canonical(entry):
        return text
    entry = copy.deepcopy(entry)
    entry.tail = None
    E.indent(entry, space='    ', level=1)
    encoded = E.tostring(entry, encoding='unicode')
    opening, closing = '<' + LINK + '>', '</' + LINK + '>'
    if existing:
        start = text.index(opening)
        end = text.index(closing, start) + len(closing)
        return text[:start] + encoded + text[end:]
    return text.replace('</root>', '    ' + encoded + '\n</root>', 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    entry, unit, receipt, units = expected()
    target = ROOT / 'data/enemy_properties' / PROPERTY_FILE
    ledger_path = ROOT / 'tools/cf7-balance-tool/data/monster-flag-ledger.json'
    ledger = json.loads(ledger_path.read_text(encoding='utf-8'))
    matching = [row for row in units if row['id'] == UNIT_ID or row['spritename'] == LINK]
    if any(row['id'] != UNIT_ID or row['spritename'] != LINK for row in matching) or len(matching) > 1:
        raise ValueError('Unit registration collision')
    list_path = ROOT / 'data/enemy_properties/list.xml'
    if args.write:
        properties_text = target.read_text(encoding='utf-8')
        updated_properties = update_enemy_text(properties_text, entry)
        if updated_properties != properties_text:
            target.write_text(updated_properties, encoding='utf-8', newline='\n')
        units_path = ROOT / 'data/units/units.json'
        units_text = units_path.read_text(encoding='utf-8-sig')
        updated_units = update_registration_text(units_text, unit)
        if updated_units != units_text:
            units_path.write_text(updated_units, encoding='utf-8', newline='\n')
        text = list_path.read_text(encoding='utf-8')
        registration = '<items>' + PROPERTY_FILE + '</items>'
        if registration not in text:
            list_path.write_text(text.replace('</root>', '  ' + registration + '\n</root>'), encoding='utf-8', newline='\n')
        ledger['claims'][LINK] = receipt['flags']
        ledger_path.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        (HERE / 'balance-inputs.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    assert canonical(E.parse(target).getroot().find(LINK)) == canonical(entry)
    assert next(row for row in json.loads((ROOT / 'data/units/units.json').read_text(encoding='utf-8-sig')) if row['id'] == UNIT_ID) == unit
    assert sum(e.text == PROPERTY_FILE for e in E.parse(list_path).getroot()) == 1
    assert json.loads(ledger_path.read_text(encoding='utf-8'))['claims'][LINK] == receipt['flags']
    assert json.loads((HERE / 'balance-inputs.json').read_text(encoding='utf-8')) == receipt
    print(json.dumps({'ok': True, 'unitId': UNIT_ID, 'stage': 7, 'tier': 8, 'panel': receipt['integerPanel']}, ensure_ascii=False))


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    main()
