from pathlib import Path
import hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
# Preparation may be written ahead; execution waits for every R16 pilot row to be collected.
report = json.loads((O / 'r16-pilot-awake-phase-aware-summary.json').read_text('utf8'))
assert not report['fullMatrix'] and len(report['rows']) == 12
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == '9d6002d4b6512c23c8a8006da2d612be45a7664f084cf553e7a58c7ebb58c32d'
changes = {}

def edit(path, old, new):
    if path not in changes:
        changes[path] = (R / path).read_text('utf-8-sig')
    assert changes[path].count(old) == 1, (path, old, changes[path].count(old))
    changes[path] = changes[path].replace(old, new)

p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, 'reactivePulseFrames:24,reactivePulseMissingRatio:0.05,reactivePulseCapacityLimit:0.01,reactiveDecayFrames:36,',
        'reactivePulseFrames:6,reactivePulseMissingRatio:0.0125,reactivePulseCapacityLimit:0.0025,reactiveDecayFrames:36,')
edit(p, 'reactiveLeechHits:0,reactiveRageLeechHits:0,reactiveCrumbleHits:0,',
        'reactiveLeechHits:0,reactiveRageLeechHits:0,reactiveCrumbleHits:0,reactiveRageSources:{},')
edit(p, '        if((result._efFlags&32)!=0){stats.reactiveLeechHits++;if(shooter.狂暴模式==1)stats.reactiveRageLeechHits++;}',
        '''        if((result._efFlags&32)!=0){
            stats.reactiveLeechHits++;
            if(shooter.狂暴模式==1){
                stats.reactiveRageLeechHits++;
                var sourceKey:String="n:"+shooter._name,entry:Object=stats.reactiveRageSources[sourceKey];
                if(entry==undefined){
                    entry={name:shooter._name,hits:0,maxPower:0,firstClock:actor.elderClock,lastClock:actor.elderClock};
                    stats.reactiveRageSources[sourceKey]=entry;
                }
                entry.hits++;entry.lastClock=actor.elderClock;entry.maxPower=Math.max(entry.maxPower,Number(bullet.子弹威力));
            }
        }''')
edit(p, 'elderReportCombat=function():Void {', '''elderRageSourceSummary=function():String {
    var sources:Object=this.elderCombatStats.reactiveRageSources,summary:String="";
    for(var key:String in sources){
        var entry:Object=sources[key];
        summary+=(summary==""?"":"|")+entry.name+"@"+entry.hits+"@"+entry.maxPower+"@"+entry.firstClock+"-"+entry.lastClock;
    }
    return summary==""?"none":summary;
};
elderReportCombat=function():Void {''')
edit(p, '+" incomingLeech="+stats.reactiveLeechHits+" rageLeech="+stats.reactiveRageLeechHits+" incomingCrumble="+stats.reactiveCrumbleHits+" kicks="',
        '+" incomingLeech="+stats.reactiveLeechHits+" rageLeech="+stats.reactiveRageLeechHits+" rageSources="+this.elderRageSourceSummary()+" incomingCrumble="+stats.reactiveCrumbleHits+" kicks="')
edit(p, '// 在替换、到期后的收招或形态结束时读取本层实物；不修改盾或伤害结算。', '''// 按真实吸收回调计量；AdaptiveShield 的单盾扁平化不允许长期缓存层对象后读取数值。
elderBeamShieldAbsorb=function(layer:Object,amount:Number):Void {
    var sample:Object=layer.elderBeamAccounting,actor:MovieClip=sample.actor;
    if(sample.active && actor.elderIdentity===sample.identity && actor.elderBeamShieldSample===sample && amount>0)
        sample.absorbed+=amount;
};
// 替换、收招、到期或形态结束时只结清一次，不改变盾或伤害结算。''')
edit(p, '    var remaining:Number=sample.shield.getCapacity();\n    this.elderCombatStats.beamShieldSpent+=sample.capacity-remaining;',
        '    var remaining:Number=Math.max(0,sample.capacity-sample.absorbed);\n    this.elderCombatStats.beamShieldSpent+=sample.absorbed;\n    sample.active=false;')
edit(p, 'spec.totalFrames,"机械蓄能盾",null);\n            if(this.elderBeamShield>=0)this.elderBeamShieldSample={shield:this.shield.getShieldById(this.elderBeamShield),capacity:capacity};',
        '''spec.totalFrames,"机械蓄能盾",{onHit:this.elderBeamShieldAbsorb});
            if(this.elderBeamShield>=0){
                this.elderBeamShieldSample={actor:this,identity:this.elderIdentity,capacity:capacity,absorbed:0,active:true};
                var beamLayer:Object=this.shield.getShieldById(this.elderBeamShield);beamLayer.elderBeamAccounting=this.elderBeamShieldSample;
            }''')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p, 'actor.elderClock=23;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits for its own twenty-four-frame interval");',
        'actor.elderClock=5;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits for its own six-frame interval");')
edit(p, 'actor.elderClock=24;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);',
        'actor.elderClock=6;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);')
edit(p, 'check(layer.getCapacity()==10 && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"periodic supplement uses missing HP with a one-percent per-pulse ceiling");',
        'check(near(layer.getCapacity(),2.5) && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"quarter-sized pulses retain the same nominal per-second supplement ceiling");')
edit(p, 'actor.shield.update(18);check(near(layer.getCapacity(),5),"temporary HP loses half its capacity after eighteen active shield frames");',
        'actor.shield.update(18);check(near(layer.getCapacity(),1.25),"temporary HP loses half its capacity after eighteen active shield frames");')
edit(p, 'actor.elderReactiveShield==id && near(layer.getCapacity(),5),"paused actor',
        'actor.elderReactiveShield==id && near(layer.getCapacity(),1.25),"paused actor')
edit(p, '        var attackerHp:Number=attacker.hp;incoming.hitCount=0;settle(incoming,attacker,actor,false);',
        '        var rageSource:Object=actor.elderCombatStats.reactiveRageSources["n:"+attacker._name];\n        check(rageSource.hits==1 && rageSource.maxPower==300 && rageSource.name==attacker._name,"rage-leech diagnostics retain the actual source identity and raw power without changing settlement");\n        var attackerHp:Number=attacker.hp;incoming.hitCount=0;settle(incoming,attacker,actor,false);')
edit(p, '        reactiveShieldTests(actor);', '''        var stackedShield:Object=actor.shield;
        actor.shield=AdaptiveShield.createDormant("single-beam-accounting");actor.shield.setOwner(actor);
        spentBefore=actor.elderCombatStats.beamShieldSpent;unusedBefore=actor.elderCombatStats.beamShieldUnused;
        samplesBefore=actor.elderCombatStats.beamShieldSamples;
        actor.elderBeginAttack(actor.man,"beam");
        var singlePenetration:Number=actor.shield.absorbDamage(100,false,1);actor.elderCancelAttack();
        check(singlePenetration==25 && near(actor.elderCombatStats.beamShieldSpent-spentBefore,75)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,125),"single-shield container accounting records actual absorption without stale layer reads");
        actor.elderBeginAttack(actor.man,"beam");actor.shield.update(44);actor.elderCancelAttack();actor.elderRecordBeamShield();
        check(near(actor.elderCombatStats.beamShieldSpent-spentBefore,75)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,325)
            && actor.elderCombatStats.beamShieldSamples==samplesBefore+2,"single-shield expiry preserves once-only consumed and unused accounting");
        actor.shield=stackedShield;
        reactiveShieldTests(actor);''')

p = 'tools/cf6-elder-assets/README.md'
old = next(line for line in (R / p).read_text('utf8').splitlines() if line.startswith('当前强度校准尚未完成。'))
new = '当前强度校准尚未完成。R16 的完整十二场诊断与应激盾边界测试已保留，仍不能替代完整三十六场验收。R17 候选继续保持“每累计损失 5% 初始满血即时补盾”的规则、100% 档位转换、单层 10% 容量上限、10 倍攻击力硬度及 36 帧衰减；周期改为每 6 个有效帧补充当前缺失生命的 1.25%，单次最多初始满血的 0.25%。这是四倍频率、四分之一单次额度，名义每秒补充上限不变，目的是缩短破盾后的空窗。狂暴吸血诊断新增实际施击实例、次数、最大原始威力及首末动作时钟，分别关联对手两种形态；这些字段不参与补盾或伤害决策。'
edit(p, old, new)
old = next(line for line in changes[p].splitlines() if line.startswith('该机制不治疗实际 HP，'))
new = '该机制不治疗实际 HP，也不撤销触发补盾的那一击已经完成的吸血；后续命中才受新盾保护。动作、倍率、已有砸地／连打盾与光束盾保持前轮，R17 尚待新鲜编译与原生回归，再进行独立对战确认。R16 首次夹具遗漏生产衰减盾接口的失败和修复回执均保留，不以重跑覆盖。当前身份、全部逐场结果与状态见[校准汇总](evidence/20261017-calibration/summary.json)，尚未提交推送或正式发布 runtime。'
edit(p, old, new)

paths = {row['path'] for row in json.loads((O / 'before-r16-reactive-shield-index.json').read_text('utf8'))}
paths.update(changes)
paths.update(['tools/cf6-elder-assets/build-playtest-fixture.py', 'scripts/test-runners/cf6-playtest/PlaytestFixture.as'])
index = []
with zipfile.ZipFile(O / 'before-r17-pulse-coverage.zip', 'x', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(paths):
        data = (R / name).read_bytes()
        z.writestr(name, data)
        index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with (O / 'before-r17-pulse-coverage-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
for name, text in changes.items():
    prior = (R / name).read_bytes()
    if b'\r\n' in prior:
        text = text.replace('\n', '\r\n')
    data = text.encode('utf8')
    if prior.startswith(b'\xef\xbb\xbf') or name.endswith('.as'):
        data = b'\xef\xbb\xbf' + data
    (R / name).write_bytes(data)
for source, dest in [('build-r16-elder', 'build-r17-elder'), ('finish-native-cleanup-after-r16', 'finish-native-cleanup-after-r17')]:
    text = (O / (source + '.ps1')).read_text('utf-8-sig').replace('r16', 'r17').replace('R16', 'R17')
    with (O / (dest + '.ps1')).open('xb') as f:
        f.write(text.encode('utf-8-sig'))
text = (O / 'build-and-test-r15.ps1').read_text('utf-8-sig').replace('r15', 'r17').replace('R15', 'R17').replace('native-r17-hard-counter', 'native-r17-pulse-coverage')
with (O / 'build-and-test-r17.ps1').open('xb') as f:
    f.write(text.encode('utf-8-sig'))
plan = json.loads((O / 'native-r16-reactive-shield-plan.json').read_text('utf8'))
plan['output'] = 'native-r17-pulse-coverage'
with (O / 'native-r17-pulse-coverage-plan.json').open('x', encoding='utf8') as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)
text = (O / 'check-elder-r16-image-equivalence.py').read_text('utf8').replace('R16', 'R17').replace('elder-r16-image-equivalence.json', 'elder-r17-image-equivalence.json')
with (O / 'check-elder-r17-image-equivalence.py').open('x', encoding='utf8') as f:
    f.write(text)
print(json.dumps({'changed': list(changes), 'pulseFrames': 6, 'perPulseCapacityRatio': .0025,
                  'nominalPulseCapacityPerSecondRatio': .0125, 'forcedTriggerAndStrengthUnchanged': True, 'compiled': False}))
