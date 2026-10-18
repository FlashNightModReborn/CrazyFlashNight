from pathlib import Path
import hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
report = json.loads((O / 'r14-full-awake-phase-aware-summary.json').read_text('utf8'))
assert report['fullMatrix'] and not report['strengthPassed']
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == '5216f91cd863fad8a7451b5c7f7f6130ef9e5e1db25b1fdeeb3aba807520ac5f'
changes = {}

def edit(path, old, new, count=1):
    if path not in changes: changes[path] = (R / path).read_text('utf-8-sig')
    assert changes[path].count(old) == count, (path, old, changes[path].count(old))
    changes[path] = changes[path].replace(old, new)

p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, 'slamShieldCapacity:0.02,slamShieldStrength:6,slamShieldFrames:120,',
        'slamShieldCapacity:0.03,slamShieldStrength:10,slamShieldFrames:120,')
edit(p, 'beamStarts:0,beamContacts:0,beamHits:0,beamHitPower:0,',
        'beamStarts:0,beamContacts:0,beamHits:0,beamHitPower:0,beamShieldSpent:0,beamShieldUnused:0,beamShieldSamples:0,')
edit(p, 'elderNextBurst=0;elderSlamHeavyWindow=null;', 'elderNextBurst=0;elderSlamHeavyWindow=null;elderBeamShieldSample=null;')
edit(p, 'elderCancelAttack=function():Void {', '''// 在替换、到期后的收招或形态结束时读取本层实物；不修改盾或伤害结算。
elderRecordBeamShield=function():Void {
    var sample:Object=this.elderBeamShieldSample;
    if(sample==null)return;
    var remaining:Number=sample.shield.getCapacity();
    this.elderCombatStats.beamShieldSpent+=sample.capacity-remaining;
    this.elderCombatStats.beamShieldUnused+=remaining;
    this.elderCombatStats.beamShieldSamples++;
    this.elderBeamShieldSample=null;
};
elderCancelAttack=function():Void {
    this.elderRecordBeamShield();''')
edit(p, '    this.elderCombatReported=true;\n    var target:MovieClip=',
        '    this.elderCombatReported=true;this.elderRecordBeamShield();\n    var target:MovieClip=')
edit(p, '+" beam="+stats.beamStarts+"/"+stats.beamContacts+" beamActual="+stats.beamHits+"/"+stats.beamHitPower+" kicks="',
        '+" beam="+stats.beamStarts+"/"+stats.beamContacts+" beamActual="+stats.beamHits+"/"+stats.beamHitPower\n        +" beamShield="+stats.beamShieldSpent+"/"+stats.beamShieldUnused+" shieldSamples="+stats.beamShieldSamples+" kicks="')
edit(p, 'spec.totalFrames,"机械蓄能盾",null);', '''spec.totalFrames,"机械蓄能盾",null);
            if(this.elderBeamShield>=0)this.elderBeamShieldSample={shield:this.shield.getShieldById(this.elderBeamShield),capacity:capacity};''')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p, 'near(hard.getStrength(),600) && near(hard.getCapacity(),20)', 'near(hard.getStrength(),1000) && near(hard.getCapacity(),30)')
edit(p, '{子弹威力:600,吸血:50,击溃:1,additionalEffectDamage:0}', '{子弹威力:1000,吸血:50,击溃:1,additionalEffectDamage:0}')
edit(p, 'pressure.子弹威力=601;', 'pressure.子弹威力=1001;')
edit(p, 'near(hard.getCapacity(),10) && actor.shield.getStrength()==600', 'near(hard.getCapacity(),20) && actor.shield.getStrength()==1000')
edit(p, '        actor.hp满血值=oldMax;actor.损伤值=oldLoss;attacker.removeMovieClip();', '''        // Replay the actual level-30 panel against the authored rage-heavy power.
        var pressureAttack:Number=actor.空手攻击力,pressureLevel:Number=actor.等级;
        actor.等级=30;actor.空手攻击力=1033;actor.hp满血值=15318;
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;
        gateResult=settle(data,actor,t,false);hardId=actor.elderSlamShield;hard=actor.shield.getShieldById(hardId);
        check(near(hard.getStrength(),10330) && near(hard.getCapacity(),459.54),"actual level-thirty slam grant covers the observed rage-heavy threshold");
        attacker.hp=500;actor.损伤值=100;pressure.子弹威力=8925;pressure.additionalEffectDamage=0;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp==500 && actor.hp满血值==15318,"8925-power rage-heavy cannot leech or crumble through the actual low-level grant");
        actor.shield.absorbDamage(1000,false,1);actor.损伤值=100;pressure.additionalEffectDamage=0;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp>500 && actor.hp满血值==15165,"exhausting the bounded low-level grant restores the same rage-heavy effects");
        actor.空手攻击力=pressureAttack;actor.等级=pressureLevel;
        actor.hp满血值=oldMax;actor.损伤值=oldLoss;attacker.removeMovieClip();''')
edit(p, '        actor.shield=AdaptiveShield.createDormant("beam-shield-fixture");actor.shield.setOwner(actor);', '''        actor.elderRecordBeamShield();
        var spentBefore:Number=actor.elderCombatStats.beamShieldSpent,unusedBefore:Number=actor.elderCombatStats.beamShieldUnused,samplesBefore:Number=actor.elderCombatStats.beamShieldSamples;
        actor.shield=AdaptiveShield.createDormant("beam-shield-fixture");actor.shield.setOwner(actor);''')
edit(p, '        first=actor.elderBeamShield;actor.shield.update(43);', '''        check(near(actor.elderCombatStats.beamShieldSpent-spentBefore,75)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,125)
            && actor.elderCombatStats.beamShieldSamples==samplesBefore+1,"beam accounting reads actual spent and discarded capacity once at replacement");
        first=actor.elderBeamShield;actor.shield.update(43);''')
edit(p, '        var shieldAttack:Number=actor.空手攻击力,shieldHp:Number=actor.hp满血值;', '''        actor.elderRecordBeamShield();actor.elderRecordBeamShield();
        check(near(actor.elderCombatStats.beamShieldSpent-spentBefore,75)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,325)
            && actor.elderCombatStats.beamShieldSamples==samplesBefore+2,"expired remaining capacity is measured once without reviving or changing the shield");
        var shieldAttack:Number=actor.空手攻击力,shieldHp:Number=actor.hp满血值;''')

p = 'tools/cf6-elder-assets/README.md'
edit(p, '容量为当前满血值的 2%，强度为空手攻击力的 6 倍，持续 120 个有效帧。',
        '容量为当前满血值的 3%，强度为空手攻击力的 10 倍，持续 120 个有效帧。')
old = next(line for line in changes.get(p, (R / p).read_text('utf8')).splitlines() if line.startswith('当前强度校准尚未完成。'))
new = '当前强度校准尚未完成。R14 完整 36 场在连续显示观察下完成，运行、身份、存档保护和退出检查通过，但为 34 负、2 胜；仅兽王 60 级和指挥官 99 级两组同时满足均值、中位数及零胜局条件。兽王 30 级均值／中位数为 44.06%／43.90%，99 级为 52.11%／48.09%；指挥官 30 级为 46.93%／43.31%，60 级为 57.25%／41.53% 且有两场胜局。R15 候选先提高砸地硬盾强度并将容量小幅提高到 3%，新增光束盾实际消耗与收招／到期后剩余容量计量；该计量只读取原有盾实例，不改变护盾生命周期或伤害。普通束、重束、连打软盾、光束盾和公式面板仍保持 R14，等待新候选编译与实战确认后再决定远程交换调整。此前失败批次完整保留。当前状态与历次失败见[进行中的校准汇总](evidence/20261017-calibration/summary.json)。尚未提交推送，也未发布正式 runtime。'
edit(p, old, new)

paths = {row['path'] for row in json.loads((O / 'before-r14-shield-window-index.json').read_text('utf8'))}
paths.update(changes)
index = []
with zipfile.ZipFile(O / 'before-r15-hard-counter.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(paths):
        data = (R / name).read_bytes()
        archive.writestr(name, data)
        index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with (O / 'before-r15-hard-counter-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
for name, value in changes.items():
    prior = (R / name).read_bytes()
    newline = '\r\n' if b'\r\n' in prior else '\n'
    data = value.replace('\n', newline).encode('utf8')
    if name.endswith('.as') or prior.startswith(b'\xef\xbb\xbf'): data = b'\xef\xbb\xbf' + data
    (R / name).write_bytes(data)
for old, new in [('build-r14-elder', 'build-r15-elder'), ('build-and-test-r14', 'build-and-test-r15'), ('finish-native-cleanup-after-r14', 'finish-native-cleanup-after-r15')]:
    value = (O / (old + '.ps1')).read_text('utf-8-sig').replace('r14', 'r15').replace('R14', 'R15').replace('native-r15-shield-window', 'native-r15-hard-counter')
    with (O / (new + '.ps1')).open('xb') as f: f.write(value.encode('utf-8-sig'))
plan = json.loads((O / 'native-r14-shield-window-plan.json').read_text('utf8'))
plan['output'] = 'native-r15-hard-counter'
with (O / 'native-r15-hard-counter-plan.json').open('x', encoding='utf8') as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)
value = (O / 'check-elder-r14-image-equivalence.py').read_text('utf8').replace('R14', 'R15').replace('elder-r14-image-equivalence.json', 'elder-r15-image-equivalence.json')
with (O / 'check-elder-r15-image-equivalence.py').open('x', encoding='utf8') as f: f.write(value)
print(json.dumps({'changed': list(changes), 'hardShield': {'capacityRatio': .03, 'strengthRatio': 10, 'frames': 120}, 'beamLifecycleAndPowersUnchanged': True, 'compiled': False}, ensure_ascii=False))
