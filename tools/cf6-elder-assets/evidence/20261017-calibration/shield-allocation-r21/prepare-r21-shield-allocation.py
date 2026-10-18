"""Prepare independent shield capacity budgets after the complete R20 pilot is frozen."""
from pathlib import Path
import datetime, hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
P = R / 'tools/cf6-elder-assets/evidence/20261017-calibration'
load = lambda p: json.loads(p.read_text('utf-8-sig'))
sha = lambda data: hashlib.sha256(data).hexdigest()
prior = P / 'history/r20-pilot-awake/phase-aware-summary.json'
analysis = load(prior)
assert len(analysis['rows']) == 12 and not analysis['fullMatrix']
assert not load(P / 'range-support-r20/summary.json')['fullMatrixAccepted']
assert load(P / 'history/r20-pilot-awake/display-assessment.json')['qualified']
assert (R / 'tmp/arena-worker-experiments/cf6-cal-r20-pilot-20261018/experiment-report.json').is_file()
assert not (O / 'before-r21-shield-allocation.zip').exists()
for binding in load(P / 'history/r20-pilot-awake/plan/input-identity.json')['sourceBindings']:
    assert sha((R / binding['path']).read_bytes()) == binding['sha256'], binding['path']

changes = {}
def edit(name, before, after, count=1):
    data = changes.get(name, (R / name).read_bytes())
    a, b = before.encode('utf8'), after.encode('utf8')
    assert data.count(a) == count, (name, before, data.count(a))
    changes[name] = data.replace(a, b)

p = 'tools/cf6-elder-assets/build.py'
edit(p, "'slam':{'id':1007,'state':'重击','hits':[37],'power':8,'damage':'物理'},",
        "'slam':{'id':1007,'state':'重击','hits':[37],'power':18,'damage':'物理'},")
p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, 'shieldAttackScale:35/43,shieldCapacityScale:0.5,',
        'shieldAttackScale:55/43,meleeShieldCapacityScale:0.5,beamShieldCapacityScale:0.2,reactiveShieldCapacityScale:0.75,')
edit(p, '35/43 折算抵消其对各层盾强的附带放大。',
        '55/43 折算抵消其对各层盾强的附带变化，保留整数面板舍入后的微小差异。')
edit(p, 'amount*=tune.shieldCapacityScale;', 'amount*=tune.reactiveShieldCapacityScale;')
edit(p, 'state.baseHp*tune.reactiveCapacityLimit*tune.shieldCapacityScale,',
        'state.baseHp*tune.reactiveCapacityLimit*tune.reactiveShieldCapacityScale,')
edit(p, 'this.hp满血值*this.elderTuning.shieldCapacityScale*Math.min(',
        'this.hp满血值*this.elderTuning.beamShieldCapacityScale*Math.min(')
edit(p, 'this.hp满血值*this.elderTuning.slamShieldCapacity*this.elderTuning.shieldCapacityScale,',
        'this.hp满血值*this.elderTuning.slamShieldCapacity*this.elderTuning.meleeShieldCapacityScale,')
edit(p, 'this.hp满血值*this.elderTuning.meleeShieldCapacity*this.elderTuning.shieldCapacityScale,',
        'this.hp满血值*this.elderTuning.meleeShieldCapacity*this.elderTuning.meleeShieldCapacityScale,')
edit(p, '+" shieldScale="+this.elderTuning.shieldCapacityScale',
        '+" shieldScale="+this.elderTuning.meleeShieldCapacityScale+" beamScale="+this.elderTuning.beamShieldCapacityScale+" reactiveScale="+this.elderTuning.reactiveShieldCapacityScale')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as'
edit(p, 'action=="slam"?800:', 'action=="slam"?1800:')
p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p, 'shieldAttackScale,35/43),"formula-driven attack growth is explicitly normalized for shield strength"',
        'shieldAttackScale,55/43),"formula-driven attack redistribution is explicitly normalized for shield strength"')
edit(p, '100*43/35', '100*43/55', count=2)
edit(p, 'actor.空手攻击力=1265;', 'actor.空手攻击力=813;', count=2)
edit(p, '12650*35/43', '8130*55/43', count=2)
edit(p, 'check(samples.kicks.actor.elderTuning.shieldCapacityScale==0.5,"all production grants use the halved capacity budget while retaining hardness");',
        'check(samples.kicks.actor.elderTuning.meleeShieldCapacityScale==0.5 && samples.kicks.actor.elderTuning.beamShieldCapacityScale==0.2 && samples.kicks.actor.elderTuning.reactiveShieldCapacityScale==0.75,"melee, beam and reactive grants retain independent capacity budgets without changing hardness");')
edit(p, 'near(shield.getCapacity(),100) && shield.getStrength()==75,"beam action owns a bounded charging shield"',
        'near(shield.getCapacity(),40) && shield.getStrength()==75,"beam action owns a bounded charging shield"')
edit(p, 'shield.absorbDamage(100,false,1)==25 && near(shield.getCapacity(),25),"charging shield absorbs only its per-hit budget"',
        'shield.absorbDamage(100,false,1)==60 && near(shield.getCapacity(),0),"charging shield absorbs only its remaining capacity"')
edit(p, 'near(actor.elderCombatStats.beamShieldSpent-spentBefore,75)',
        'near(actor.elderCombatStats.beamShieldSpent-spentBefore,40)', count=4)
edit(p, 'near(actor.elderCombatStats.beamShieldUnused-unusedBefore,25)',
        'near(actor.elderCombatStats.beamShieldUnused-unusedBefore,0)', count=2)
edit(p, 'near(actor.elderCombatStats.beamShieldUnused-unusedBefore,125)',
        'near(actor.elderCombatStats.beamShieldUnused-unusedBefore,40)', count=2)
edit(p, 'actor.空手攻击力=2000;actor.hp满血值=10000;',
        'actor.空手攻击力=2000;actor.hp满血值=30000;')
edit(p, 'shield.getStrength()==800 && near(shield.getCapacity(),1000)',
        'shield.getStrength()==800 && near(shield.getCapacity(),1200)')
edit(p, 'shield.absorbDamage(1000,false,1)==200 && near(shield.getCapacity(),200)',
        'shield.absorbDamage(1000,false,1)==200 && near(shield.getCapacity(),400)')
edit(p, 'beamCaps:Array=[300,2000/13,50,200000/10201,200000/10201]',
        'beamCaps:Array=[120,800/13,20,80000/10201,80000/10201]')
edit(p, 'singlePenetration==25 &&', 'singlePenetration==60 &&')
edit(p, 'layer.getCapacity()==10 && layer.getStrength()==1000 && actor.hp==950',
        'layer.getCapacity()==15 && layer.getStrength()==1000 && actor.hp==950')
edit(p, 'getCapacity()==20 && actor.shield.getShieldCount()==2',
        'getCapacity()==30 && actor.shield.getShieldCount()==2')
edit(p, 'getCapacity()==50,"a multi-threshold burst records every crossing but respects the halved five-percent capacity ceiling"',
        'getCapacity()==75,"a multi-threshold burst records every crossing but respects the independent seven-and-a-half-percent capacity ceiling"')
edit(p, '0.625/6', '0.625/4')
edit(p, '0.3125/6', '0.3125/4', count=2)
edit(p, 'one-third pulses every active frame retain the same supplement ceiling',
        'periodic grants apply the independent reactive budget every active frame')
edit(p, 'near(actor.elderCombatStats.reactiveGranted-budgetGranted,3.125)',
        'near(actor.elderCombatStats.reactiveGranted-budgetGranted,4.6875)')
edit(p, 'thirty actual periodic grants apply the halved total supplement budget',
        'thirty actual periodic grants apply the independent reactive supplement budget')
edit(p, 'near(layer.getCapacity(),153.18)', 'near(layer.getCapacity(),229.77)')

readme = 'tools/cf6-elder-assets/README.md'
data = (R / readme).read_bytes()
assert b'R21' not in data
section = '''
## 2026-10-18 R21 护盾容量分配试验（施工中）

R20 在 750 射程下为 7 负、4 胜、1 平、0 超时，低、中等级兽王组净削血偏低，EXUSIAI 过强；其十二场结果全部保留。R21 保持射程、画面、碰撞及动作时序，将砸击倍率从 ×8 调到 ×18，通过同一公式把攻击倍率标识重算为 6.875，并降低基础攻击面板；30／60／99 级空攻为 813／1184／1666。普通束 ×3 与重束四段倍率保持，实际波伤害较 R20 下降约 36%，实际砸击威力上升约 45%。阶段、档次、HP、防御、人形和其他单位保持。盾强折算改为 `55/43`，三档实际硬度与 R20 的偏差不超过 1.4%，保留真实整数舍入差异。

三类容量预算分开：近战维持 R19 的 50%，光束起手盾从 R20 的 50% 收紧到 20%，应激盾从 50% 回调到 75%。持续／衰减规则保持，不按对手身份分支。R20 兽王对局出现 11–17 次砸击命中授盾，EXUSIAI 为 0–3 次；结合防御与波抗配置选择本轮输出分配，但这些观察不构成新参数的强度证明。

应激盾仍按每累计损失 5% 初始满血触发，实际转换率为 30%，本层容量上限为初始满血的 7.5%；每个有效帧周期补充为当前缺失生命的 1/1280，最多初始满血的 1/6400，每三十个有效帧的补充上限为 0.46875%。新的补充只合并本层剩余容量并重设衰减，不重复缩放旧容量。诊断分别输出近战、光束、应激三项倍率。

本轮尚待新鲜原生回归与独立斗兽验证，不能沿用 R20 的执行结果宣称通过。
'''
marker = b'## 2026-10-18 R20 '
start = data.index(marker)
next_section = data.find(b'\n## ', start + len(marker))
assert next_section > 0
data = data[:next_section] + section.encode('utf8') + data[next_section:]
table_old = '| 机器人 | 1007 砸击 | 62 | 37 | 物理近战 ×8、'.encode('utf8')
assert data.count(table_old) == 1
changes[readme] = data.replace(table_old, table_old.replace('×8'.encode('utf8'), '×18'.encode('utf8')))

paths = {row['path'] for row in load(O / 'before-r20-range-support-index.json')}
paths.update(row['path'] for row in load(P / 'history/r20-pilot-awake/plan/input-identity.json')['sourceBindings'])
paths.update(['data/units/units.json', 'tools/cf7-balance-tool/data/monster-flag-ledger.json',
              'launcher/web/modules/arena-unit-catalog.js'])
paths.update(changes)
index = []
with zipfile.ZipFile(O / 'before-r21-shield-allocation.zip', 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in sorted(paths):
        original = (R / name).read_bytes()
        z.writestr(name, original)
        index.append({'path': name, 'bytes': len(original), 'sha256': sha(original)})
with (O / 'before-r21-shield-allocation-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
for name, data in changes.items():
    if name.endswith('.as'):
        assert (R / name).read_bytes().startswith(b'\xef\xbb\xbf') and data.startswith(b'\xef\xbb\xbf')
    (R / name).write_bytes(data)
with (O / 'r21-authorized-changes.json').open('x', encoding='utf8') as f:
    json.dump({'recordedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'authorization': 'Existing user authorization to tune shield strength, capacity/coverage and multipliers, plus approved 750-range trial.',
               'changed': list(changes), 'evidence': str(prior), 'evidenceSha256': sha(prior.read_bytes()),
               'meleeShieldCapacityScale': .5, 'beamShieldCapacityScale': .2, 'reactiveShieldCapacityScale': .75,
               'slamPower': 18, 'attackMultiplierFlag': 6.875, 'shieldAttackScale': 55/43,
               'actualRobotAttackAtLevels30_60_99': [813,1184,1666],
               'robotAttackPanelRegenerationRequired': True, 'humanHpDefenseAndOtherUnitsChanged': False,
               'rangeAndGeometryChanged': False,
               'compiled': False}, f, ensure_ascii=False, indent=2)
print(json.dumps({'changed': list(changes), 'preservedBeforeFiles': len(index), 'compiled': False}))
