"""Test-only item inputs from real XML. Does not change item numbers or runtime data."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
import argparse

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    'longForm': ('武器_刀_长柄.xml', '烬灭裁决'),
    'dualForm': ('武器_刀_双刀.xml', '烬灭裁决双刀'),
    'vocal': ('武器_刀_直剑.xml', '主唱光剑'),
    'keyboard': ('武器_刀_镰刀.xml', '键盘镰刀'),
    'dominator': ('武器_手枪_特殊.xml', 'dominator'),
    'guitar': ('武器_长枪_特殊.xml', None),
    'bloodSword': ('武器_刀_直剑.xml', '血色光剑天秤'),
    'huofengHead': ('防具_20-39级.xml', '火凤头部装备'),
    'huofengChest': ('防具_20-39级.xml', '火凤胸甲'),
    'huofengLegs': ('防具_20-39级.xml', '火凤下装'),
    'huofengHands': ('防具_20-39级.xml', '火凤手甲'),
    'huofengFeet': ('防具_20-39级.xml', '火凤战靴'),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()

def data(element):
    if list(element):
        return {child.tag: data(child) for child in element}
    value = (element.text or '').strip()
    try:
        number = float(value)
        return int(number) if number.is_integer() else number
    except ValueError:
        return value

def literal(value):
    if isinstance(value, dict):
        assert all(re.fullmatch(r'[^\W\d]\w*', key) for key in value)
        return '{' + ','.join(key + ':' + literal(v) for key,v in value.items()) + '}'
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))

rows = {}
hashes = {}
for key,(filename,name) in SOURCES.items():
    path = ROOT / 'data/items' / filename
    hashes[filename] = hashlib.sha256(path.read_bytes()).hexdigest()
    items = ET.parse(path).getroot().iter('item')
    if name:
        item = next(item for item in items if item.findtext('name') == name)
    else:
        item = next(item for item in items if any(n.text == '吉他喷火初始化' for n in item.iter('initRoutines')))
    rows[key] = {name: item.findtext(name) for name in ['name','type','use']}
    if item.findtext('actiontype') is not None:
        rows[key]['actiontype'] = item.findtext('actiontype')
    rows[key]['data'] = data(item.find('data'))
    rows[key]['params'] = {}
    init = next(iter(item.iter('initParam')), None)
    if init is not None:
        rows[key]['params'] = {n.tag: data(n) for n in init if len(list(n)) == 0}

destination = ROOT / 'scripts/类定义/org/flashNight/arki/unit/PlayerStatItemFixtures.as'
if not destination.exists():
    if args.check:
        raise SystemExit('Generated fixture is missing')
    shutil.copy2(ROOT / 'scripts/类定义/org/flashNight/arki/unit/PlayerStatProjectionTest.as', destination)
assert destination.read_bytes()[:3] == b'\xef\xbb\xbf'
source = '/** Generated test inputs; edit tools/player-stat-refresh/generate-mode-fixtures.py. */\n'
source += 'class org.flashNight.arki.unit.PlayerStatItemFixtures {\n'
source += ' public static function read():Object { return ' + literal(rows) + '; }\n}\n'
content = b'\xef\xbb\xbf' + source.replace('\n','\r\n').encode('utf-8')
if args.check:
    if destination.read_bytes() != content:
        raise SystemExit('Generated fixture is stale; run generate-mode-fixtures.py')
else:
    destination.write_bytes(content)
print(json.dumps({'testOnly': True, 'sourceHashes': hashes, 'output': str(destination)}, ensure_ascii=True))
