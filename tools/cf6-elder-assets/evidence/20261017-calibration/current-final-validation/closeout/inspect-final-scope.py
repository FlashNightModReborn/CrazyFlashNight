from pathlib import Path
import subprocess,json,hashlib
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
def lp(p):
 s=str(Path(p).resolve());return Path(s if s.startswith('\\\\?\\') else '\\\\?\\'+s)
raw=subprocess.check_output(['git','ls-files','-z','--modified','--others','--exclude-standard'])
raw+=subprocess.check_output(['git','diff','--cached','--name-only','-z'])
pending=sorted(set(p for p in raw.decode('utf8').split('\0') if p))
exact={'.gitattributes','agentsDoc/as2-anti-hallucination.md','agentsDoc/art-asset-assembly.md','agentsDoc/game-design.md','agentsDoc/testing-details.md',
 'data/enemy_properties/CF6重制敌人.xml','data/items/asset_source_map.xml','data/units/units.json',
 'flashswf/arts/things-new.fla','flashswf/arts/things-new.swf','launcher/web/modules/arena-unit-catalog.js','scripts/asLoader.swf',
 'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletHitEffectRegistry.as',
 'scripts/类定义/org/flashNight/arki/component/Buff/Effect/ElderBeamVulnerability.as',
 'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as','scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as',
 'sounds/export/人物/soundheadexplode.wav','tools/cf7-balance-tool/data/monster-flag-ledger.json'}
for family in ('guard','manman','soldier','wings','zombie'):
 exact.update('tools/cf6-'+family+'-assets/'+name for name in ('build.py','native-manifest.json'))
for name in ('audio','legacy-audio','bladebot-asset','bladebot-beam-render','elder-asset','elder-render','headbot-asset','headbot-render','knockback-scope','player-aim','robot-death-render'):
 exact.add('scripts/run-cf6-'+name+'-tests.ps1')
prefixes=['tools/cf6-'+family+'/' for family in ('audio','headbot-assets','elder-assets','bladebot-assets')]
prefixes+=['scripts/test-runners/cf6-'+name+'/' for name in ('audio','bladebot','bladebot-beam-render','elder','elder-render','headbot','headbot-render','knockback-scope','player-aim','playtest','robot-death-render')]
for owner in ('Antigravity专用素材','CodexWings素材','Codex光头保安素材','Codex大刀机器人素材','Codex大头机器人素材','Codex特种兵素材','Codex老头素材','Codex蛮蛮素材','素材库-诺亚新敌人'):
 exact.add('flashswf/arts/new/'+owner+'.swf');prefixes.append('flashswf/arts/new/'+owner+'/')
for owner in ('CF6大头机器人-R3','CF6老头人形-R7','CF6老头机器人-R7','CF6老头变形-R2'):
 prefixes.append('flashswf/arts/new/Codex素材源稿/'+owner+'/')
excluded={'flashswf/arts/new/素材库-诺亚新敌人.html'}
def allowed(p):
 return p in exact or any(p.startswith(prefix) for prefix in prefixes) or (p.startswith('sounds/export/人物/CF6_') and p.endswith(('.mp3','.wav'))) or (p.startswith('scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6') and p.endswith('.as'))
exact.update(['launcher/README.md', 'launcher/src/Guardian/WorldCompositor/WorldCompositorController.cs', 'launcher/tests/Guardian/WorldCompositorTests.cs', 'scripts/类定义/org/flashNight/arki/merc/ArenaCalibrationService.as', 'scripts/类定义/org/flashNight/arki/merc/ArenaWorkerProtocolTest.as', 'scripts/run-arena-worker-protocol-tests.ps1'])
unknown=[p for p in pending if p not in excluded and not allowed(p)]
print(json.dumps({"unknown":unknown,"pendingFiles":len(pending),"allowedPending":sum(allowed(p) for p in pending),"excluded":sorted(excluded)},ensure_ascii=False))
