"""Read-only verification of the two CF6 zombie registrations and Stage 6 balance."""
from pathlib import Path
from copy import deepcopy
import argparse
import hashlib
import json
import math
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as E
from build import workspace_identity_failures

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NS = {'x': 'http://ns.adobe.com/xfl/2008/'}


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--node', default='node')
    args = parser.parse_args()

    enemy_base = E.parse(ROOT / 'data/enemy_properties/原版敌人 2011-2012.xml').getroot()
    variants = E.parse(ROOT / 'data/enemy_properties/CF6重制敌人.xml').getroot()
    registrations = json.loads((ROOT / 'data/units/units.json').read_text(encoding='utf-8-sig'))
    source_map = E.parse(ROOT / 'data/items/asset_source_map.xml').getroot()
    properties_list = E.parse(ROOT / 'data/enemy_properties/list.xml').getroot()
    assert sum(e.text == 'CF6重制敌人.xml' for e in properties_list) == 1

    ledger = json.loads((HERE / 'balance-inputs.json').read_text(encoding='utf-8'))
    js = (
        "import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/dist/formulas/monsters.js';"
        "console.log(JSON.stringify("
        + json.dumps([r['input'] for r in ledger['rows']])
        + ".map(computeMonsterRow)));"
    )
    calculated = json.loads(
        subprocess.check_output([args.node, '--input-type=module', '-e', js], cwd=ROOT, text=True, encoding='utf-8')
    )
    fields = {
        '最小经验值': 'expMin',
        '最大经验值': 'expMax',
        'hp_min': 'hpMin',
        'hp_max': 'hpMax',
        '空手攻击力_min': 'atkMin',
        '空手攻击力_max': 'atkMax',
        '基本防御力_min': 'defMin',
        '基本防御力_max': 'defMax',
    }

    result = []
    for index, row in enumerate(ledger['rows']):
        link = row['linkage']
        unit_id = row['unitId']
        stage = row['stage']
        source_tag = row['source'].split('/', 1)[1]
        original = enemy_base.find(source_tag)
        assert original is not None, source_tag
        entry = variants.find(link)
        assert entry is not None, link
        assert entry.find('displayname').text == row['displayname']

        for flag in original.find('标识'):
            actual = float(entry.find('标识/' + flag.tag).text)
            assert actual == (stage if flag.tag == '阶段' else float(flag.text)), (link, flag.tag)
        for field, key in fields.items():
            assert int(entry.find(field).text) == math.floor(calculated[index][key] + 0.5), (link, field)
        for old in original:
            if old.tag not in set(fields) | {'displayname', '标识', '掉落物'}:
                assert E.tostring(old) == E.tostring(entry.find(old.tag)), (link, old.tag)

        matches = [x for x in registrations if x['id'] == unit_id or x['spritename'] == link]
        assert len(matches) == 1 and matches[0]['id'] == unit_id and matches[0]['spritename'] == link
        orig_unit = next(x for x in registrations if x['spritename'] == source_tag)
        expected = deepcopy(orig_unit)
        expected.update(id=unit_id, spritename=link, name=entry.find('displayname').text)
        assert expected == matches[0]

        asset = [e for e in source_map if e.get('id') == link]
        assert len(asset) == 1 and asset[0].get('swf') == 'flashswf/arts/new/Antigravity专用素材.swf'
        result.append({'unitId': unit_id, 'linkage': link, 'stage': stage, 'otherFlagsInherited': 9})

    # Verify things-new.fla contains Antigravity专用素材
    with zipfile.ZipFile(ROOT / 'flashswf/arts/things-new.fla', 'r') as zf:
        assert 'LIBRARY/Antigravity专用素材.xml' in zf.namelist()
        assert 'Antigravity专用素材.xml' in zf.read('DOMDocument.xml').decode('utf-8')
        assert 'libraryItemName="Antigravity专用素材"' in zf.read('LIBRARY/things-new.xml').decode('utf-8')

    manifest = json.loads((HERE / 'native-manifest.json').read_text(encoding='utf-8'))
    identity_failures = workspace_identity_failures(manifest)
    assert not identity_failures, '\n'.join(identity_failures)
    owner = ROOT / manifest['owner']
    includes = {e.get('href') for e in E.parse(owner / 'DOMDocument.xml').findall('x:symbols/x:Include', NS)}
    for row in manifest['outputs']:
        p = owner / row['path']
        assert hashlib.sha256(p.read_bytes()).hexdigest() == row['sha256'], 'native import identity drift: ' + row['path']
        assert row['path'][len('LIBRARY/'):] in includes

    for as_rel in [
        'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ZombieAssetTest.as',
        'scripts/test-runners/cf6-zombie/TestLoader.as.template',
        'scripts/run-cf6-zombie-asset-tests.ps1',
    ]:
        assert (ROOT / as_rel).read_bytes().startswith(b'\xef\xbb\xbf'), f'Missing UTF-8 BOM: {as_rel}'

    print(
        json.dumps(
            {
                'ok': True,
                'units': result,
                'formulaPanelsChecked': 16,
                'nativeSourceFilesVerified': len(manifest['outputs']),
                'nativeProjectFilesVerified': len(manifest['projectFiles']),
            },
            ensure_ascii=False,
        )
    )


if __name__ == '__main__':
    main()
