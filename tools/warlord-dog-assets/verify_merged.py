"""Strict three-dog coexistence against the fetched upstream bank and registry."""
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as E

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def main():
    # Reuse the upstream tag reader's pure functions without invoking its
    # historical two-export-only main assertion. Keep that source unchanged.
    reader=ROOT/'tools/two-dogs-assets/readback.py'
    source=reader.read_text(encoding='utf-8').split("owner='flashswf/",1)[0]
    scope={'__file__':str(reader),'__name__':'three_dog_swf_reader'}
    exec(compile(source,str(reader),'exec'),scope)
    scan,attack=scope['scan'],scope['attack_contract']
    owner='flashswf/arts/new/Codex专用素材.swf'
    upstream=scan(subprocess.check_output(['git','show','HEAD:'+owner],cwd=ROOT))
    current=scan((ROOT/owner).read_bytes())
    guard='敌人-军阀铁卫犬'
    others={'敌人-制式军警犬','敌人-盗贼撕咬犬'}
    assert set(current['exports'])==set(upstream['exports'])|{guard}
    assert others<=set(upstream['exports'])
    for name,ident in upstream['exports'].items():
        assert current['spriteFrames'].get(current['exports'][name])==upstream['spriteFrames'].get(ident),(name,'published upstream frame count')
    for name in others|{guard}:
        assert current['spriteFrames'][current['exports'][name]]==121
    shared=scan((ROOT/'flashswf/arts/things-new.swf').read_bytes())
    anchors=[r for r in shared['imports'] if 'Codex专用素材' in r['assets']]
    assert len(anchors)==1 and 'Codex专用素材.swf' in anchors[0]['url']
    assert not subprocess.check_output(['git','diff','--name-only','HEAD','--',
        'flashswf/arts/new/Codex专用素材/LIBRARY',
        'flashswf/arts/new/Codex素材源稿/两犬-V6','tools/two-dogs-assets',
        'scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/FormerSheriffController.as',
        'data/enemy_properties/两犬.xml','data/enemy_properties/list.xml'],cwd=ROOT)
    units=json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
    old_units=json.loads(subprocess.check_output(['git','show','HEAD:data/units/units.json'],cwd=ROOT).decode('utf-8-sig'))
    assert len({u['id'] for u in units})==len(units)
    for number in (13,475,476):
        assert next(u for u in units if u['id']==number)==next(u for u in old_units if u['id']==number)
    unit_id=json.loads((HERE/'balance-inputs.json').read_text(encoding='utf-8'))['unitId']
    assert unit_id==477 and next(u for u in units if u['id']==unit_id)['spritename']==guard
    asset_map=E.parse(ROOT/'data/items/asset_source_map.xml').getroot()
    for name in others|{guard}:
        rows=[r for r in asset_map if r.get('id')==name]
        assert len(rows)==1 and rows[0].tag=='asset' and rows[0].get('swf')==owner
    assert not subprocess.check_output(['git','ls-files','-u'],cwd=ROOT)
    print(json.dumps({'result':'PASS','head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
        'unitIds':{'制式军警犬':475,'盗贼撕咬犬':476,'军阀铁卫犬':unit_id},
        'allUnitIdsUnique':True,'originalAndUpstreamDogRecordsUnchanged':True,
        'upstreamTwoDogSourcesUnchanged':True,'allTrackedUpstreamLibrarySourcesUnchanged':True,
        'upstreamFormerSheriffControllerUnchanged':True,'exactExportUnion':True,'exportCount':len(current['exports']),
        'allPublishedUpstreamExportFrameCountsPreserved':True,
        'rootFrames':121,'sharedAnchor':anchors[0],
        'upstreamAttackContracts':{n:attack(current,n) for n in sorted(others)},
        'compiledBankSha256':hashlib.sha256((ROOT/owner).read_bytes()).hexdigest()},ensure_ascii=False))


if __name__=='__main__':main()
