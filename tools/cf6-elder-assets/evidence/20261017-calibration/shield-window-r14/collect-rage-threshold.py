from pathlib import Path
import hashlib, importlib.util, json, re, xml.etree.ElementTree as ET

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
source_names = [
    'data/enemy_properties/原版敌人 2013-2016.xml',
    'flashswf/arts/things5/LIBRARY/敌人-方舟兽王.xml',
    'flashswf/arts/things5/LIBRARY/Symbol 2033.xml',
    'scripts/引擎/引擎_lsy_常数.as',
    'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as',
    'scripts/类定义/org/flashNight/arki/merc/ArenaCalibrationService.as',
    'scripts/类定义/org/flashNight/arki/component/Damage/LifeStealDamageHandle.as',
    'scripts/类定义/org/flashNight/arki/component/Damage/CrumbleDamageHandle.as',
    'tools/cf6-elder-assets/ElderAI.as',
]
source = {name: (R / name).read_bytes() for name in source_names}
text = {name: data.decode('utf-8-sig') for name, data in source.items()}
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == '5216f91cd863fad8a7451b5c7f7f6130ef9e5e1db25b1fdeeb3aba807520ac5f'
max_attack = float(ET.fromstring(source[source_names[0]]).findtext('敌人-方舟兽王/空手攻击力_max'))
rage = re.findall(r'_parent\.空手攻击力\s*=\s*_parent\.空手攻击力_max\s*\*\s*([\d.]+)\s*\*\s*_root\.难度等级', text[source_names[1]])
assert rage and len(set(rage)) == 1
multiplier = float(rage[0])
heavy = re.findall(r'子弹属性\.子弹威力\s*=\s*_parent\._parent\.空手攻击力\s*\*\s*([\d.]+)', text[source_names[2]])
assert heavy and len(set(heavy)) == 1
heavy_multiplier = float(heavy[0])
assert '_root.难度等级 = 1;' in text[source_names[3]]
assert 'this.hp满血值 = _root.根据等级计算值(this.hp_min, this.hp_max, 等级值) * _root.难度等级;' in text[source_names[4]]
for name in source_names[6:8]:
    assert 'bullet.子弹威力 <= shield.getStrength()' in text[name]
rate = float(re.search(r'slamShieldStrength:([\d.]+)', text[source_names[8]]).group(1))
diagnostic_path = O / 'cf6-cal-r14-full-20261018-private-diagnostics/index-2-groups-4-shards-time-bound.json'
diagnostic = json.loads(diagnostic_path.read_text('utf8'))
levels = {}
for event in diagnostic['events']:
    if '[CF6_ELDER_PHASE_READY]' not in event['message']: continue
    values = {key: int(value) for key, value in re.findall(r'\b(level|maxHp|attack)=(\d+)', event['message'])}
    key = values['level']
    if key in levels: assert levels[key] == values
    levels[key] = values
assert set(levels) == {30, 60}
power = max_attack * multiplier * heavy_multiplier
report = {
    'status': 'source_threshold_analysis; not a new arena or native execution',
    'experiment': 'cf6-cal-r14-full-20261018',
    'observedGroups': ['beastking-level30', 'beastking-level60'],
    'sourceBindings': [{'path': name, 'sha256': hashlib.sha256(data).hexdigest()} for name, data in source.items()],
    'diagnosticIndexSha256': hashlib.sha256(diagnostic_path.read_bytes()).hexdigest(),
    'difficulty': {'value': 1, 'basis': 'Cold-start default, calibration passes no difficulty override, and observed initial rival HP matches the unscaled level formula in canonical phase analysis; not a direct global-variable trace.'},
    'rageHeavy': {'maxAttackField': max_attack, 'rageMultiplier': multiplier, 'heavyMultiplier': heavy_multiplier, 'rawPower': power},
    'currentSlamShieldRate': rate,
    'observedPhaseStarts': [dict(values, shieldStrength=values['attack'] * rate, blocksRageHeavy=values['attack'] * rate >= power) for _, values in sorted(levels.items())],
    'boundary': 'This establishes the generic raw-power gate and the observed actor statistics. It does not prove how often rage-heavy contacts occurred or that raising this shield alone will meet the full balance target.'
}
spec = importlib.util.spec_from_file_location('evidence', R / 'tmp/cf6-elder-20261016/evidence_utils.py')
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
u.jput(O / 'r14-rage-threshold-analysis.json', report)
state = u.js(O / 'evidence-history-assembly.json')
package = u.Package(P)
package.mapping = state['mapping']
assert not (P / 'integrity.json').exists()
package.freeze(source_names, 'shield-window-r14/rage-threshold-source.zip')
package.copy(O / 'r14-rage-threshold-analysis.json', 'shield-window-r14/rage-threshold-analysis.json')
package.copy(O / 'collect-r14-rage-threshold.py', 'shield-window-r14/collect-rage-threshold.py')
state['mapping'] = package.mapping
(O / 'evidence-history-assembly.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), 'utf8')
print(json.dumps({'rawPower': power, 'observed': report['observedPhaseStarts'], 'newExecution': False}))
