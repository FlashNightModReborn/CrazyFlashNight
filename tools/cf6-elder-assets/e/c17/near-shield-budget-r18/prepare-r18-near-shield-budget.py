from pathlib import Path
import hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
report = json.loads((O / 'r17-pilot-awake-phase-aware-summary.json').read_text('utf8'))
assert len(report['rows']) == 12 and sum(r['won'] for r in report['rows']) == 2
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == 'ce30fa634395d2c07312e24baf4102898e2666cb58b1805d56d7a8a7c798663f'
changes = {}

def edit(path, old, new):
    if path not in changes: changes[path] = (R / path).read_text('utf-8-sig')
    assert changes[path].count(old) == 1, (path, old, changes[path].count(old))
    changes[path] = changes[path].replace(old, new)

p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, 'meleeShieldCapacity:0.2,meleeShieldStrengthLow:0.45,meleeShieldStrengthHigh:0.18,',
        'meleeShieldCapacity:0.1,meleeShieldStrengthLow:0.30,meleeShieldStrengthHigh:0.12,')
edit(p, 'slamShieldCapacity:0.03,slamShieldStrength:10,slamShieldFrames:120,',
        'slamShieldCapacity:0.015,slamShieldStrength:10,slamShieldFrames:120,')
edit(p, 'reactivePulseFrames:6,reactivePulseMissingRatio:0.00625,reactivePulseCapacityLimit:0.00125,reactiveDecayFrames:36,',
        'reactivePulseFrames:3,reactivePulseMissingRatio:0.003125,reactivePulseCapacityLimit:0.000625,reactiveDecayFrames:36,')
edit(p, 'kicksShieldGrants:0,slamShieldGrants:0};',
        'kicksShieldGrants:0,slamShieldGrants:0,kicksShieldAbsorbed:0,slamShieldAbsorbed:0};')
edit(p, 'elderRewardMelee=function(target:MovieClip,action:String):Void {', '''elderMeleeShieldAbsorb=function(layer:Object,amount:Number):Void {
    var sample:Object=layer.elderMeleeAccounting,actor:MovieClip=sample.actor;
    if(actor.elderIdentity!==sample.identity || !(amount>0))return;
    var currentId:Number=sample.action=="slam"?actor.elderSlamShield:actor.elderMeleeShield;
    if(currentId!=layer.getId())return;
    actor.elderCombatStats[sample.action+"ShieldAbsorbed"]+=amount;
};
elderRewardMelee=function(target:MovieClip,action:String):Void {''')
edit(p, 'this.elderTuning.slamShieldFrames,"机械砸地盾",null);',
        'this.elderTuning.slamShieldFrames,"机械砸地盾",{onHit:this.elderMeleeShieldAbsorb});')
edit(p, 'Math.max(1,this.空手攻击力*strengthRate),shieldFrames,"机械反击盾",null);',
        'Math.max(1,this.空手攻击力*strengthRate),shieldFrames,"机械反击盾",{onHit:this.elderMeleeShieldAbsorb});')
edit(p, '    if(action=="slam" && target.hp>0 && target._parent===this._parent){', '''    var grantedId:Number=action=="slam"?this.elderSlamShield:this.elderMeleeShield;
    if(grantedId>=0){
        var grantedLayer:Object=this.shield.getShieldById(grantedId);
        grantedLayer.elderMeleeAccounting={actor:this,identity:this.elderIdentity,action:action};
    }
    if(action=="slam" && target.hp>0 && target._parent===this._parent){''')
edit(p, '+" slam="+stats.slamStarts+"/"+stats.slamContacts+" kicksShield="+stats.kicksShieldGrants+" slamShield="+stats.slamShieldGrants',
        '+" slam="+stats.slamStarts+"/"+stats.slamContacts+" kicksShield="+stats.kicksShieldGrants+" slamShield="+stats.slamShieldGrants\n        +" meleeShieldAbsorbed="+stats.kicksShieldAbsorbed+"/"+stats.slamShieldAbsorbed')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edits = [
 ('near(shield.getCapacity(),200) && near(shield.getStrength(),18)', 'near(shield.getCapacity(),100) && near(shield.getStrength(),12)'),
 ('        check(shield.absorbDamage(100,false,1)==82 && near(shield.getCapacity(),182),"reward shield absorbs a bounded per-hit amount");',
  '        var kickAbsorbedBefore:Number=actor.elderCombatStats.kicksShieldAbsorbed;\n        check(shield.absorbDamage(100,false,1)==88 && near(shield.getCapacity(),88),"reward shield absorbs a bounded per-hit amount");\n        check(near(actor.elderCombatStats.kicksShieldAbsorbed-kickAbsorbedBefore,12),"actual soft-layer absorption reaches the owned diagnostic callback");'),
 ('        first=actor.elderMeleeShield;actor.shield.update(59);',
  '        kickAbsorbedBefore=actor.elderCombatStats.kicksShieldAbsorbed;actor.elderMeleeShieldAbsorb(shield,1);\n        check(actor.elderCombatStats.kicksShieldAbsorbed==kickAbsorbedBefore,"retired melee layer cannot add absorption to its replacement");\n        first=actor.elderMeleeShield;actor.shield.update(59);'),
 ('near(shield.getStrength(),45) && near(shield.getCapacity(),200)', 'near(shield.getStrength(),30) && near(shield.getCapacity(),100)'),
 ('shield.absorbDamage(100,false,1)==55 && near(shield.getCapacity(),155)', 'shield.absorbDamage(100,false,1)==70 && near(shield.getCapacity(),70)'),
 ('near(shield.getStrength(),31.5) && near(shield.getCapacity(),200)', 'near(shield.getStrength(),21) && near(shield.getCapacity(),100)'),
 ('near(hard.getStrength(),1000) && near(hard.getCapacity(),30)', 'near(hard.getStrength(),1000) && near(hard.getCapacity(),15)'),
 ('near(actor.shield.getShieldById(softId).getStrength(),18)', 'near(actor.shield.getShieldById(softId).getStrength(),12)'),
 ('        check(hard.absorbDamage(5,false,1)==0 && hard.absorbDamage(5,false,1)==0',
  '        var slamAbsorbedBefore:Number=actor.elderCombatStats.slamShieldAbsorbed;\n        check(hard.absorbDamage(5,false,1)==0 && hard.absorbDamage(5,false,1)==0'),
 ('near(hard.getCapacity(),20) && actor.shield.getStrength()==1000,"two small hits retain the thin hard layer\'s generic effect threshold");',
  'near(hard.getCapacity(),5) && actor.shield.getStrength()==1000,"two small hits retain the thin hard layer\'s generic effect threshold");\n        check(near(actor.elderCombatStats.slamShieldAbsorbed-slamAbsorbedBefore,10),"actual hard-layer absorption is recorded separately from the soft layer");'),
 ('actor.shield.getStrength()==18 && actor.shield.getShieldById(softId)!=null', 'actor.shield.getStrength()==12 && actor.shield.getShieldById(softId)!=null'),
 ('near(hard.getCapacity(),459.54)', 'near(hard.getCapacity(),229.77)'),
 ('actor.elderClock=5;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits for its own six-frame interval");',
  'actor.elderClock=2;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits for its own three-frame interval");'),
 ('actor.elderClock=6;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);',
  'actor.elderClock=3;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);'),
 ('near(layer.getCapacity(),1.25) && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"eighth-sized pulses at fourfold frequency halve the nominal per-second supplement ceiling"',
  'near(layer.getCapacity(),0.625) && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"halved pulses at twice the frequency retain the same supplement ceiling per thirty active frames"'),
 ('actor.shield.update(18);check(near(layer.getCapacity(),0.625),"temporary HP loses half its capacity after eighteen active shield frames");',
  'actor.shield.update(18);check(near(layer.getCapacity(),0.3125),"temporary HP loses half its capacity after eighteen active shield frames");'),
 ('actor.elderReactiveShield==id && near(layer.getCapacity(),0.625),"paused actor',
  'actor.elderReactiveShield==id && near(layer.getCapacity(),0.3125),"paused actor')]
for old, new in edits: edit(p, old, new)

p = 'tools/cf6-elder-assets/README.md'
edit(p, '机器人连打真实命中盾保持 20% 满血容量；强度率从 1 级的 45% 平滑过渡到 99 级的 18%',
        '机器人连打真实命中盾容量为满血的 10%；强度率从 1 级的 30% 平滑过渡到 99 级的 12%')
edit(p, '30／60／99 级分别约为 37.01%／28.74%／18%', '30／60／99 级分别约为 24.67%／19.16%／12%')
edit(p, '砸地真实命中另授予独立的硬盾：容量为当前满血值的 3%', '砸地真实命中另授予独立的硬盾：容量为当前满血值的 1.5%')
old = next(line for line in changes[p].splitlines() if line.startswith('当前强度校准尚未完成。'))
edit(p, old, '当前强度校准尚未完成。R17 十二场诊断为十负、二胜、零超时：兽王 60 级与 EXUSIAI 99 级各有一场胜局，EXUSIAI 30 级组均值仅 51.22%。R18 因此收紧近战叠加保护：连打盾容量减半、软盾强度率降为前轮的三分之二，砸地硬盾容量减半。应激盾保持每累计损失 5% 初始满血即时补盾、40% 转换率、10% 单层容量上限、10 倍攻击力硬度与 36 帧衰减；周期由 6 帧缩短至 3 帧，单次补充减半为当前缺失生命的 0.3125%、最多初始满血的 0.0625%，每 30 个有效帧的补充上限仍为 0.625%。这用于缩短空档，不增加总补充预算。新增连打／砸地盾真实吸收回调计数，以分别核对近战层的收益。')
old = next(line for line in changes[p].splitlines() if line.startswith('该机制不治疗实际 HP，'))
edit(p, old, '该机制不治疗实际 HP，也不撤销触发补盾的那一击已经完成的吸血；后续命中才受新盾保护。招式倍率、动作、光束盾与公式面板保持前轮。R18 尚待新鲜编译、原生回归与独立对战，不能把 R17 已通过的 2,433 项检查视为 R18 通过。狂暴施击实例与吸收计数只用于诊断，不参与伤害决策；旧光束盾计量限制、夹具失败与所有过强样本均保留。当前身份与逐场结果见[校准汇总](evidence/20261017-calibration/summary.json)，尚未提交推送或正式发布 runtime。')

paths = {row['path'] for row in json.loads((O / 'before-r17-pulse-coverage-index.json').read_text('utf8'))}
paths.update(changes)
index = []
with zipfile.ZipFile(O / 'before-r18-near-shield-budget.zip', 'x', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(paths):
        data = (R / name).read_bytes()
        z.writestr(name, data)
        index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with (O / 'before-r18-near-shield-budget-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
for name, text in changes.items():
    prior = (R / name).read_bytes()
    if b'\r\n' in prior: text = text.replace('\n', '\r\n')
    data = text.encode('utf8')
    if prior.startswith(b'\xef\xbb\xbf') or name.endswith('.as'): data = b'\xef\xbb\xbf' + data
    (R / name).write_bytes(data)
for source, dest in [('build-r17-elder', 'build-r18-elder'), ('finish-native-cleanup-after-r17', 'finish-native-cleanup-after-r18')]:
    text = (O / (source + '.ps1')).read_text('utf-8-sig').replace('r17', 'r18').replace('R17', 'R18')
    with (O / (dest + '.ps1')).open('xb') as f: f.write(text.encode('utf-8-sig'))
text = (O / 'build-and-test-r17.ps1').read_text('utf-8-sig').replace('r17', 'r18').replace('R17', 'R18').replace('native-r18-pulse-coverage', 'native-r18-near-shield-budget')
with (O / 'build-and-test-r18.ps1').open('xb') as f: f.write(text.encode('utf-8-sig'))
plan = json.loads((O / 'native-r17-pulse-coverage-plan.json').read_text('utf8'))
plan['output'] = 'native-r18-near-shield-budget'
with (O / 'native-r18-near-shield-budget-plan.json').open('x', encoding='utf8') as f: json.dump(plan, f, ensure_ascii=False, indent=2)
text = (O / 'check-elder-r17-image-equivalence.py').read_text('utf8').replace('R17', 'R18').replace('elder-r17-image-equivalence.json', 'elder-r18-image-equivalence.json')
with (O / 'check-elder-r18-image-equivalence.py').open('x', encoding='utf8') as f: f.write(text)
print(json.dumps({'changed': list(changes), 'pulseFrames': 3, 'pulseCeilingPer30ActiveFrames': .00625,
                  'kicksCapacity': .10, 'kicksStrengthEndpoints': [.30, .12], 'slamCapacity': .015,
                  'forcedConversion': .4, 'strengthAndAttackPowersUnchanged': True, 'compiled': False}))
