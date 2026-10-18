from pathlib import Path
import hashlib, json, zipfile, io, shutil
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
def sha(data): return hashlib.sha256(data).hexdigest()
def put(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): assert path.read_bytes() == data, 'Preserve baseline: '+str(path)
    else: path.write_bytes(data)
paths = set()
for folder in ['tools/cf6-headbot-assets', 'tools/cf6-elder-assets', 'tools/cf6-bladebot-assets',
               'flashswf/arts/new/Codex大头机器人素材', 'flashswf/arts/new/Codex老头素材', 'flashswf/arts/new/Codex大刀机器人素材',
               'scripts/test-runners/cf6-headbot', 'scripts/test-runners/cf6-headbot-render',
               'scripts/test-runners/cf6-elder', 'scripts/test-runners/cf6-elder-render',
               'scripts/test-runners/cf6-bladebot', 'scripts/test-runners/cf6-bladebot-beam-render']:
    for path in (ROOT/folder).rglob('*'):
        if path.is_file() and not any(part in ['evidence','__pycache__','bin'] for part in path.relative_to(ROOT/folder).parts):
            paths.add(path.relative_to(ROOT).as_posix())
paths.update(['data/enemy_properties/CF6重制敌人.xml', 'data/units/units.json', 'data/items/asset_source_map.xml',
    'flashswf/arts/new/Codex大头机器人素材.swf', 'flashswf/arts/new/Codex老头素材.swf', 'flashswf/arts/new/Codex大刀机器人素材.swf',
    'flashswf/arts/things-new.fla', 'flashswf/arts/things-new.swf', 'scripts/asLoader.swf',
    'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as', 'scripts/逻辑/单位函数/单位函数_fs_护盾函数.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletHitEffectRegistry.as',
    'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
    'scripts/类定义/org/flashNight/arki/component/Buff/Effect/FireControlVulnerability.as',
    'scripts/类定义/org/flashNight/arki/spatial/animation/FragmentAnimator.as',
    'scripts/类定义/org/flashNight/arki/spatial/animation/FragmentAnimationInstance.as',
    'scripts/类定义/org/flashNight/arki/spatial/animation/FragmentConfig.as',
    'scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as',
    'flashswf/arts/things0/LIBRARY/主角-男.xml', 'flashswf/arts/things0/LIBRARY/主角肢体素材/Symbol 6.xml',
    'flashswf/arts/things0/LIBRARY/shape/Symbol 5.xml',
    'agentsDoc/game-design.md', 'agentsDoc/testing-details.md'])
for name in ['Cf6HeadbotAssetTest','Cf6HeadbotRenderTest','Cf6ElderAssetTest','Cf6ElderRenderTest','Cf6BladebotAssetTest','Cf6BladebotBeamRenderTest']:
    paths.add('scripts/类定义/org/flashNight/arki/unit/Action/Melee/'+name+'.as')
for name in ['headbot-asset','headbot-render','elder-asset','elder-render','bladebot-asset','bladebot-beam-render']:
    paths.add('scripts/run-cf6-'+name+'-tests.ps1')
index=[]; buffer=io.BytesIO()
with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    for relative in sorted(paths):
        data=(ROOT/relative).read_bytes(); info=zipfile.ZipInfo(relative,(2026,10,17,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
        archive.writestr(info,data,compresslevel=9)
        index.append({'path':relative,'bytes':len(data),'sha256':sha(data)})
with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
    assert archive.testzip() is None
    assert all(sha(archive.read(row['path']))==row['sha256'] for row in index)
put(HERE/'baseline-source.zip',buffer.getvalue())
put(HERE/'baseline-source.index.json',(json.dumps({'files':index,'zipSha256':sha(buffer.getvalue())},ensure_ascii=False,indent=2)+'\n').encode('utf8'))
for name in ['codex-clipboard-fbda50c4-71e6-44f0-b2b2-559b7d5d1fec.png','codex-clipboard-6e70d0a1-9718-4303-8048-24ebdc8bc18c.png']:
    put(HERE/'user-report'/name,(Path('C:/Users/fs/AppData/Local/Temp')/name).read_bytes())
print(json.dumps({'baselineFiles':len(index),'zipBytes':len(buffer.getvalue()),'zipSha256':sha(buffer.getvalue()),'userImagesPreserved':2}))
