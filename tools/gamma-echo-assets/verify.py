"""Read-only verification of the two gamma-ECHO registrations and inherited balance."""
from pathlib import Path
from copy import deepcopy
import argparse
import hashlib
import json
import math
import subprocess
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--node', default='node')
    args = parser.parse_args()
    original = E.parse(ROOT / 'data/enemy_properties/诺亚新敌人.xml').getroot().find('敌人-诺亚克隆兽')
    variants = E.parse(ROOT / 'data/enemy_properties/γ-ECHO克隆兽.xml').getroot()
    registrations = json.loads((ROOT / 'data/units/units.json').read_text(encoding='utf-8-sig'))
    noah = next(x for x in registrations if x['spritename'] == '敌人-诺亚克隆兽')
    source_map = E.parse(ROOT / 'data/items/asset_source_map.xml').getroot()
    properties_list = E.parse(ROOT / 'data/enemy_properties/list.xml').getroot()
    assert sum(e.text == 'γ-ECHO克隆兽.xml' for e in properties_list) == 1
    ledger = json.loads((HERE / 'balance-inputs.json').read_text(encoding='utf-8'))
    js = "import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/dist/formulas/monsters.js';console.log(JSON.stringify(" + json.dumps([r['input'] for r in ledger['rows']]) + ".map(computeMonsterRow)));"
    calculated = json.loads(subprocess.check_output([args.node, '--input-type=module', '-e', js], cwd=ROOT, text=True, encoding='utf-8'))
    fields = {'最小经验值': 'expMin', '最大经验值': 'expMax', 'hp_min': 'hpMin', 'hp_max': 'hpMax',
              '空手攻击力_min': 'atkMin', '空手攻击力_max': 'atkMax', '基本防御力_min': 'defMin', '基本防御力_max': 'defMax'}
    result = []
    for index, (link, unit_id, stage) in enumerate([('敌人-延寿克隆兽', 459, 8), ('敌人-完全体克隆兽', 460, 9)]):
        entry = variants.find(link)
        assert entry is not None
        assert entry.find('displayname').text == ('暴君克隆兽' if stage == 9 else 'λ型克隆兽')
        for flag in original.find('标识'):
            actual = float(entry.find('标识/' + flag.tag).text)
            assert actual == (stage if flag.tag == '阶段' else float(flag.text)), (link, flag.tag)
        for field, key in fields.items():
            assert int(entry.find(field).text) == math.floor(calculated[index][key] + .5), (link, field)
        for old in original:
            if old.tag not in set(fields) | {'displayname', '标识'}:
                assert E.tostring(old) == E.tostring(entry.find(old.tag)), (link, old.tag)
        matches = [x for x in registrations if x['id'] == unit_id or x['spritename'] == link]
        assert len(matches) == 1 and matches[0]['id'] == unit_id and matches[0]['spritename'] == link
        expected = deepcopy(noah)
        expected.update(id=unit_id, spritename=link, name=entry.find('displayname').text)
        if 'key' in matches[0]:
            expected['key'] = matches[0]['key']
        elif 'key' in expected:
            del expected['key']
        assert expected == matches[0]
        asset = [e for e in source_map if e.get('id') == link]
        assert len(asset) == 1 and asset[0].get('swf') == 'flashswf/arts/new/Codex专用素材.swf'
        result.append({'unitId': unit_id, 'linkage': link, 'stage': stage, 'otherFlagsInherited': 9})
    manifest = json.loads((HERE / 'native-manifest.json').read_text(encoding='utf-8'))
    owner = ROOT / manifest['owner']
    includes = {e.get('href') for e in E.parse(owner / 'DOMDocument.xml').findall('x:symbols/x:Include', NS)}
    for row in manifest['outputs']:
        p = owner / row['path']
        assert hashlib.sha256(p.read_bytes()).hexdigest() == row['sha256'], 'native import identity drift: ' + row['path']
        assert row['path'][len('LIBRARY/'):] in includes
    for name in ['GammaEchoAI.as']:
        assert (HERE / name).read_bytes().startswith(b'\xef\xbb\xbf')
    print(json.dumps({'ok': True, 'units': result, 'formulaPanelsChecked': 16,
                      'nativeSourceFilesVerified': len(manifest['outputs'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
