"""Synchronize only Type61 descriptions, preserving all other live XML bytes."""
import argparse
import json
import re
from pathlib import Path
from xml.sax.saxutils import escape
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def load_copy():
    return json.loads((HERE / 'copy.json').read_text('utf-8'))


def item_description(entry):
    return '<font color="#66ccff">' + entry['effect'] + '</font>\n\n' + entry['lore']


def replace_description(block, value):
    result, changed = re.subn(r'(<description>).*?(</description>)',
                             lambda m: m[1] + escape(value) + m[2], block,
                             count=1, flags=re.S)
    assert changed == 1
    return result


def expected_files(copy):
    armor = ROOT / 'data/items/防具_40+级.xml'
    sets = ROOT / 'data/items/item_sets.xml'
    armor_text = armor.read_bytes().decode('utf-8')
    seen = set()
    def item(match):
        block = match[0]
        name = E.fromstring(block.encode('utf-8')).findtext('name')
        if name not in copy['items']:
            return block
        assert name not in seen
        seen.add(name)
        return replace_description(block, item_description(copy['items'][name]))
    new_armor = re.sub(r'<item>.*?</item>', item, armor_text, flags=re.S)
    assert seen == set(copy['items'])
    sets_text = sets.read_bytes().decode('utf-8')
    matched = []
    def definition(match):
        block = match[0]
        if E.fromstring(block.encode('utf-8')).findtext('id') != 'unified_type_61_armor':
            return block
        matched.append(block)
        block = replace_description(block, copy['setDescription'])
        block, count = re.subn(r'<effect_0>.*?</effect_0>',
                              lambda m: replace_description(m[0], copy['effectDescription']),
                              block, flags=re.S)
        assert count == 1
        return block
    new_sets = re.sub(r'<set>.*?</set>', definition, sets_text, flags=re.S)
    assert len(matched) == 1
    return {armor: new_armor.encode('utf-8'), sets: new_sets.encode('utf-8')}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = expected_files(load_copy())
    stale = [str(path.relative_to(ROOT)) for path, data in expected.items() if path.read_bytes() != data]
    if args.check:
        if stale:
            raise SystemExit('Copy is stale: ' + ', '.join(stale))
    else:
        for path, data in expected.items():
            E.fromstring(data)
            if path.read_bytes() != data:
                path.write_bytes(data)
    print(json.dumps({'mode': 'check' if args.check else 'sync', 'items': 5, 'updated': stale}, ensure_ascii=False))


if __name__ == '__main__':
    main()
