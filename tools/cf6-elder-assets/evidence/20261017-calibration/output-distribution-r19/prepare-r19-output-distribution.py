from pathlib import Path
import hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
report = json.loads((O / 'r18-pilot-awake-phase-aware-summary.json').read_text('utf8'))
assert len(report['rows']) == 12 and sum(r['won'] for r in report['rows']) == 1
assert (R / 'tmp/arena-worker-experiments/cf6-cal-r18-pilot-20261018/experiment-report.json').is_file()
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == '7597910d7fcbca69a09fb0f4900fa2bb5029a14d8463d11658aec89c90bb5d33'
changes = {}

def edit(path, old, new):
    if path not in changes: changes[path] = (R / path).read_text('utf-8-sig')
    assert changes[path].count(old) == 1, (path, old, changes[path].count(old))
    changes[path] = changes[path].replace(old, new)

p = 'tools/cf6-elder-assets/build.py'
edit(p, "'slam':{'id':1007,'state':'重击','hits':[37],'power':12,'damage':'物理'},",
        "'slam':{'id':1007,'state':'重击','hits':[37],'power':8,'damage':'物理'},")
p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, '    meleeShieldCapacity:0.1,',
        '    shieldAttackScale:35/43,meleeShieldCapacity:0.1,')
edit(p, 'reactivePulseFrames:3,reactivePulseMissingRatio:0.003125,reactivePulseCapacityLimit:0.000625,reactiveDecayFrames:36,',
        'reactivePulseFrames:1,reactivePulseMissingRatio:0.003125/3,reactivePulseCapacityLimit:0.000625/3,reactiveDecayFrames:36,')
for old, new in [
    ('this.空手攻击力*tune.reactiveStrength', 'this.空手攻击力*tune.shieldAttackScale*tune.reactiveStrength'),
    ('this.空手攻击力*this.elderTuning.beamShieldStrength', 'this.空手攻击力*this.elderTuning.shieldAttackScale*this.elderTuning.beamShieldStrength'),
    ('this.空手攻击力*this.elderTuning.slamShieldStrength', 'this.空手攻击力*this.elderTuning.shieldAttackScale*this.elderTuning.slamShieldStrength'),
    ('this.空手攻击力*strengthRate', 'this.空手攻击力*this.elderTuning.shieldAttackScale*strengthRate')]:
    edit(p, old, new)
edit(p, 'elderNextSlam=0;',
        '// 砸地倍率变化会由统一公式重算攻击；35/43 折算抵消其对各层盾强的附带放大。\nelderNextSlam=0;')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as'
edit(p, 'action=="slam"?1200:', 'action=="slam"?800:')
p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p, '        var actor:MovieClip=samples.kicks.actor;', '''        check(near(samples.kicks.actor.elderTuning.shieldAttackScale,35/43),"formula-driven attack growth is explicitly normalized for shield strength");
        // Keep legacy exact-threshold fixtures at reference attack 100; real level-30 panels are exercised below.
        var shieldActions:Array=["beam","kicks","slam","heavyBeam"];
        for(var shieldActionIndex:Number=0;shieldActionIndex<shieldActions.length;shieldActionIndex++)
            samples[shieldActions[shieldActionIndex]].actor.空手攻击力=100*43/35;
        var actor:MovieClip=samples.kicks.actor;''')
edit(p, 'actor.等级=30;actor.空手攻击力=1033;actor.hp满血值=15318;',
        'actor.等级=30;actor.空手攻击力=1265;actor.hp满血值=15318;')
edit(p, 'near(hard.getStrength(),10330)', 'near(hard.getStrength(),12650*35/43)')
edit(p, 'actor.hp=actor.hp满血值=1000;actor.空手攻击力=100;actor.防御力=300;actor.elderClock=0;',
        'actor.hp=actor.hp满血值=1000;actor.空手攻击力=100*43/35;actor.防御力=300;actor.elderClock=0;')
edit(p, 'actor.elderClock=2;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits for its own three-frame interval");',
        'actor.elderClock=0;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits until the next active frame");')
edit(p, 'actor.elderClock=3;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);',
        'actor.elderClock=1;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);')
edit(p, 'near(layer.getCapacity(),0.625) && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"halved pulses at twice the frequency retain the same supplement ceiling per thirty active frames"',
        'near(layer.getCapacity(),0.625/3) && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"one-third pulses every active frame retain the same supplement ceiling"')
edit(p, 'actor.shield.update(18);check(near(layer.getCapacity(),0.3125),',
        'actor.shield.update(18);check(near(layer.getCapacity(),0.3125/3),')
edit(p, 'actor.elderReactiveShield==id && near(layer.getCapacity(),0.3125),"paused actor',
        'actor.elderReactiveShield==id && near(layer.getCapacity(),0.3125/3),"paused actor')
edit(p, '        // Exercise the real post-damage event order:', '''        actor.elderClearReactiveShield();actor.hp=800;actor.hp满血值=1000;actor.elderClock=0;actor.elderUpdateReactiveShield();
        var budgetGranted:Number=actor.elderCombatStats.reactiveGranted,budgetPulses:Number=actor.elderCombatStats.reactivePulses;
        for(var budgetFrame:Number=1;budgetFrame<=30;budgetFrame++){
            actor.shield.update(1);actor.elderClock=budgetFrame;actor.elderUpdateReactiveShield();
        }
        check(near(actor.elderCombatStats.reactiveGranted-budgetGranted,6.25)
            && actor.elderCombatStats.reactivePulses==budgetPulses+30,"thirty actual periodic grants keep the unchanged total supplement budget");

        // Exercise the real post-damage event order:''')
edit(p, 'actor.hp=actor.hp满血值=15318;actor.空手攻击力=1033;',
        'actor.hp=actor.hp满血值=15318;actor.空手攻击力=1265;')
edit(p, 'layer.getStrength()==10330', 'near(layer.getStrength(),12650*35/43)')

p = 'tools/cf6-elder-assets/README.md'
edit(p, '砸击为 ×12；基础攻击与实际招式倍率同批重新送入公式。',
        '砸击为 ×8；基础攻击与实际招式倍率同批重新送入公式。各层实际盾强统一先将攻击力乘以 `35/43`，抵消本次攻击面板重算带来的附带增幅，再应用上述强度率与上限；30／60／99 级实际硬度均保持在前轮约 1% 的范围内。')
edit(p, '| 机器人 | 1007 砸击 | 62 | 37 | 物理近战 ×12、',
        '| 机器人 | 1007 砸击 | 62 | 37 | 物理近战 ×8、')
old = next(line for line in changes[p].splitlines() if line.startswith('当前强度校准尚未完成。'))
edit(p, old, '当前强度校准尚未完成。R18 十二场诊断为十一负、一胜、零超时；兽王 30／60／99 级平均净削血为 46.98%／52.41%／69.19%，EXUSIAI 为 68.58%／49.84%／65.65%，30 级 EXUSIAI 仍有一场胜局。R19 将砸地倍率从 ×12 调为 ×8，并由统一公式重算攻击面板，以缩小近战爆发与远程输出的差异；护盾统一折算攻击力，保持实际硬度接近前轮。应激盾仍每累计损失 5% 初始满血即时补充、40% 转换率、10% 单层容量上限和 36 帧衰减；周期由 3 帧缩短至每个有效帧，单次补充为当前缺失生命的 1/960、最多初始满血的 1/4800，每 30 个有效帧的补充上限仍为 0.625%。近战盾容量、光束盾、动作时序与重束四段倍率保持前轮。')
old = next(line for line in changes[p].splitlines() if line.startswith('该机制不治疗实际 HP，'))
edit(p, old, '该机制不治疗实际 HP，也不撤销触发补盾的那一击已经完成的吸血；后续命中才受新盾保护。R19 尚待新鲜编译、原生回归与独立对战，不能把 R18 的 2,436 项检查视为本轮通过。所有强度样本与失败均保留，完整三十六场验证、玩家体验和正式 runtime 发布分别记录。当前身份与逐场结果见[校准汇总](evidence/20261017-calibration/summary.json)，尚未提交推送或正式发布 runtime。')

paths = {row['path'] for row in json.loads((O / 'before-r18-near-shield-budget-index.json').read_text('utf8'))}
paths.update(changes)
index = []
with zipfile.ZipFile(O / 'before-r19-output-distribution.zip', 'x', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(paths):
        data = (R / name).read_bytes();z.writestr(name, data)
        index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with (O / 'before-r19-output-distribution-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
for name, text in changes.items():
    prior = (R / name).read_bytes()
    if b'\r\n' in prior: text = text.replace('\n', '\r\n')
    data = text.encode('utf8')
    if prior.startswith(b'\xef\xbb\xbf') or name.endswith('.as'): data = b'\xef\xbb\xbf' + data
    (R / name).write_bytes(data)
for source, dest in [('build-r18-elder', 'build-r19-elder'), ('finish-native-cleanup-after-r18', 'finish-native-cleanup-after-r19')]:
    text = (O / (source + '.ps1')).read_text('utf-8-sig').replace('r18', 'r19').replace('R18', 'R19')
    with (O / (dest + '.ps1')).open('xb') as f: f.write(text.encode('utf-8-sig'))
plan = json.loads((O / 'native-r18-near-shield-budget-plan.json').read_text('utf8'))
plan['output'] = 'native-r19-output-distribution'
with (O / 'native-r19-output-distribution-plan.json').open('x', encoding='utf8') as f: json.dump(plan, f, ensure_ascii=False, indent=2)
text = (O / 'check-elder-r18-image-equivalence.py').read_text('utf8').replace('R18', 'R19').replace('elder-r18-image-equivalence.json', 'elder-r19-image-equivalence.json')
with (O / 'check-elder-r19-image-equivalence.py').open('x', encoding='utf8') as f: f.write(text)
print(json.dumps({'changed': list(changes), 'slamPower': 8, 'pulseFrames': 1,
                  'pulseCeilingPer30ActiveFrames': .00625, 'shieldAttackScale': 35/43,
                  'forcedConversion': .4, 'compiled': False}))
