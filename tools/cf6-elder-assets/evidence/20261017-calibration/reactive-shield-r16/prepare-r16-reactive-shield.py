from pathlib import Path
import hashlib, json, zipfile

R = Path.cwd()
O = R / 'tmp/cf6-combat-calibration-20261017'
assert hashlib.sha256((R / 'flashswf/arts/new/Codex老头素材.swf').read_bytes()).hexdigest() == 'd15c6778237384db72be2351a50097dc9995115d0118ab1695d6d834e9d86bee'
assert json.loads((O / 'native-r15-hard-counter/player-aim/result.json').read_text('utf-8-sig'))['exitCode'] == 0
changes = {}

def edit(path, old, new, count=1):
    if path not in changes:
        changes[path] = (R / path).read_text('utf-8-sig')
    assert changes[path].count(old) == count, (path, old, changes[path].count(old))
    changes[path] = changes[path].replace(old, new)

p = 'tools/cf6-elder-assets/ElderAI.as'
edit(p, 'elderCombatReported=false;', 'elderCombatReported=false;elderReactiveShield=-1;elderReactiveState=null;')
edit(p, '    beamStarts:0,beamContacts:0,beamHits:0,beamHitPower:0,',
        '    reactiveLostHp:0,reactiveForced:0,reactivePulses:0,reactiveGranted:0,reactiveAbsorbed:0,reactiveLeechHits:0,reactiveRageLeechHits:0,reactiveCrumbleHits:0,\n    beamStarts:0,beamContacts:0,beamHits:0,beamHitPower:0,')
edit(p, '    slamShieldCapacity:0.03,slamShieldStrength:10,slamShieldFrames:120,',
        '    slamShieldCapacity:0.03,slamShieldStrength:10,slamShieldFrames:120,\n    reactiveLossStep:0.05,reactiveForcedConversion:1,reactiveCapacityLimit:0.10,reactiveStrength:10,\n    reactivePulseFrames:24,reactivePulseMissingRatio:0.05,reactivePulseCapacityLimit:0.01,reactiveDecayFrames:36,')
reactive = '''// 以本形态初始化满血值固定损血门槛；同一笔已观察 HP 下降只入账一次。
// 命中后事件负责立即补盾，私有帧时钟负责周期补充；伤害与吸血结算仍由通用管线执行。
elderReactiveHit=function(target:MovieClip,shooter:MovieClip,bullet:Object,collision:Object,result:Object):Void {
    var actor:MovieClip=this.actor;
    if(!this.active || target!==actor || actor.elderIdentity!==this.identity || actor.elderReactiveState!==this || _root.暂停)return;
    if(!(actor.hp>0)){actor.elderClearReactiveShield();return;}
    if(result!=null){
        var stats:Object=actor.elderCombatStats;
        if((result._efFlags&32)!=0){stats.reactiveLeechHits++;if(shooter.狂暴模式==1)stats.reactiveRageLeechHits++;}
        if(result._crumbleDamage>0)stats.reactiveCrumbleHits++;
    }
    actor.elderObserveReactiveHp();
};
elderReactiveAbsorb=function(layer:Object,amount:Number):Void {
    var state:Object=layer.elderReactiveOwner,actor:MovieClip=state.actor;
    if(state.active && actor.elderIdentity===state.identity && actor.elderReactiveState===state && amount>0)
        actor.elderCombatStats.reactiveAbsorbed+=amount;
};
elderClearReactiveShield=function():Void {
    var state:Object=this.elderReactiveState;
    if(state!=null){
        state.active=false;
        state.dispatcher.unsubscribe("hit",state.callback,state);
        this.elderReactiveState=null;
    }
    if(this.elderReactiveShield>=0){_root.护盾函数.移除护盾(this,this.elderReactiveShield);this.elderReactiveShield=-1;}
};
elderGrantReactiveShield=function(amount:Number):Void {
    var state:Object=this.elderReactiveState,tune:Object=this.elderTuning;
    if(state==null || !state.active || !(this.hp>0) || !(amount>0))return;
    var old:Object=this.shield.getShieldById(this.elderReactiveShield);
    var remaining:Number=old==null?0:old.getCapacity();
    var capacity:Number=Math.min(state.baseHp*tune.reactiveCapacityLimit,remaining+amount);
    if(!(capacity>0))return;
    if(this.elderReactiveShield>=0)_root.护盾函数.移除护盾(this,this.elderReactiveShield);
    this.elderReactiveShield=_root.护盾函数.添加衰减护盾(this,capacity,
        Math.max(1,this.空手攻击力*tune.reactiveStrength),capacity/tune.reactiveDecayFrames,"机械应激盾",{onHit:this.elderReactiveAbsorb});
    if(this.elderReactiveShield>=0){
        var layer:Object=this.shield.getShieldById(this.elderReactiveShield);layer.elderReactiveOwner=state;
        this.elderCombatStats.reactiveGranted+=capacity-remaining;
    }
};
elderObserveReactiveHp=function():Void {
    var state:Object=this.elderReactiveState;
    if(state==null || !state.active || _root.暂停)return;
    var hp:Number=Number(this.hp);
    if((hp-hp)!=0)return;
    if(!(hp>0)){this.elderClearReactiveShield();return;}
    var lost:Number=state.lastHp-hp;state.lastHp=hp;
    if(!(lost>0))return;
    this.elderCombatStats.reactiveLostHp+=lost;state.lossRemainder+=lost;
    var steps:Number=Math.floor(state.lossRemainder/state.stepHp);
    if(steps>0){
        state.lossRemainder-=steps*state.stepHp;
        this.elderCombatStats.reactiveForced+=steps;
        this.elderGrantReactiveShield(steps*state.stepHp*this.elderTuning.reactiveForcedConversion);
    }
};
elderUpdateReactiveShield=function():Void {
    if(_root.暂停)return;
    if(this.elderForm!="robot" || !(this.hp>0)){this.elderClearReactiveShield();return;}
    var state:Object=this.elderReactiveState,tune:Object=this.elderTuning;
    if(state==null){
        var maximum:Number=Number(this.hp满血值),currentHp:Number=Number(this.hp);
        if(!(maximum>0) || !isFinite(maximum) || (currentHp-currentHp)!=0 || this.shield==null || typeof this.dispatcher.subscribe!="function")return;
        state={actor:this,identity:this.elderIdentity,dispatcher:this.dispatcher,callback:this.elderReactiveHit,active:true,
            baseHp:maximum,lastHp:currentHp,stepHp:maximum*tune.reactiveLossStep,lossRemainder:0,
            nextPulse:this.elderClock+tune.reactivePulseFrames};
        this.elderReactiveState=state;
        if(!state.dispatcher.subscribe("hit",state.callback,state)){state.active=false;this.elderReactiveState=null;return;}
    }
    this.elderObserveReactiveHp();
    if(this.elderClock<state.nextPulse)return;
    state.nextPulse=this.elderClock+tune.reactivePulseFrames;
    var missing:Number=state.baseHp-this.hp;
    var amount:Number=Math.min(state.baseHp*tune.reactivePulseCapacityLimit,missing*tune.reactivePulseMissingRatio);
    if(amount>0){this.elderCombatStats.reactivePulses++;this.elderGrantReactiveShield(amount);}
};

'''
edit(p, '// 在替换、到期后的收招或形态结束时读取本层实物；不修改盾或伤害结算。',
        reactive + '// 在替换、到期后的收招或形态结束时读取本层实物；不修改盾或伤害结算。')
edit(p, '    if(!(this.hp>0))this.elderSlamHeavyWindow=null;',
        '    if(!(this.hp>0)){this.elderSlamHeavyWindow=null;this.elderClearReactiveShield();}')
edit(p, '    this.elderCombatReported=true;this.elderRecordBeamShield();',
        '    this.elderCombatReported=true;this.elderRecordBeamShield();this.elderClearReactiveShield();')
edit(p, '+" beamShield="+stats.beamShieldSpent+"/"+stats.beamShieldUnused+" shieldSamples="+stats.beamShieldSamples+" kicks="',
        '+" beamShield="+stats.beamShieldSpent+"/"+stats.beamShieldUnused+" shieldSamples="+stats.beamShieldSamples\n        +" reactive="+stats.reactiveForced+"/"+stats.reactivePulses+" reactiveHp="+stats.reactiveLostHp+"/"+stats.reactiveGranted+"/"+stats.reactiveAbsorbed\n        +" incomingLeech="+stats.reactiveLeechHits+" rageLeech="+stats.reactiveRageLeechHits+" incomingCrumble="+stats.reactiveCrumbleHits+" kicks="')
edit(p, '状态改变=function(next:String):Void {',
        '状态改变=function(next:String):Void {\n    if(next=="消失")this.elderClearReactiveShield();')
edit(p, '    var owner:Object=this.elderAttackOwner;\n    if(owner!=null){',
        '    if(this.elderForm=="robot")this.elderUpdateReactiveShield();\n    var owner:Object=this.elderAttackOwner;\n    if(owner!=null){')

p = 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderCombatEffectsTest.as'
edit(p, 'import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;',
        'import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;\nimport org.flashNight.neur.Event.EventDispatcher;')
edit(p, '        trace("Cf6ElderCombatEffectsTest: "+passed+" passed, "+failed+" failed");return failed==0;',
        '        reactiveShieldTests(actor);\n        trace("Cf6ElderCombatEffectsTest: "+passed+" passed, "+failed+" failed");return failed==0;')
tests = '''    private static function reactiveShieldTests(actor:MovieClip):Void {
        actor.elderClearReactiveShield();
        var old:Object={hp:actor.hp,max:actor.hp满血值,attack:actor.空手攻击力,clock:actor.elderClock,
            dispatcher:actor.dispatcher,shield:actor.shield,identity:actor.elderIdentity,form:actor.elderForm,defense:actor.防御力};
        actor.hp=actor.hp满血值=1000;actor.空手攻击力=100;actor.防御力=300;actor.elderClock=0;
        actor.elderForm="robot";actor.elderIdentity={};actor.dispatcher=new EventDispatcher();
        actor.shield=AdaptiveShield.createDormant("reactive-fixture");actor.shield.setOwner(actor);
        var foreign:Shield=Shield.createTemporary(10,1,600,"foreign-reactive");actor.shield.addShield(foreign);
        var forcedBefore:Number=actor.elderCombatStats.reactiveForced,pulsesBefore:Number=actor.elderCombatStats.reactivePulses;
        actor.elderUpdateReactiveShield();
        var state:Object=actor.elderReactiveState;
        check(state.baseHp==1000 && state.stepHp==50 && actor.elderReactiveShield==-1,"reactive shield initializes one fixed per-form threshold without free capacity");
        actor.hp=951;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(actor.elderReactiveShield==-1 && state.lossRemainder==49,"sub-threshold real HP loss is retained without early grant");
        actor.hp=950;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        var id:Number=actor.elderReactiveShield,layer:Object=actor.shield.getShieldById(id);
        check(layer.getCapacity()==50 && layer.getStrength()==1000 && actor.hp==950,"crossing five percent grants a decaying hard shield without healing HP");
        actor.elderUpdateReactiveShield();actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(actor.elderReactiveShield==id && actor.elderCombatStats.reactiveForced==forcedBefore+1,"the same observed HP loss and repeated callbacks cannot duplicate a forced grant");
        actor.hp=970;actor.elderUpdateReactiveShield();
        check(state.lossRemainder==0 && actor.elderCombatStats.reactiveForced==forcedBefore+1,"healing rebases observation without creating shield credit");
        actor.hp=920;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(actor.shield.getShieldById(actor.elderReactiveShield).getCapacity()==100 && actor.shield.getShieldCount()==2,"second loss refreshes only the owned layer and preserves a foreign shield");
        actor.hp=710;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(state.lossRemainder==10 && actor.elderCombatStats.reactiveForced==forcedBefore+6
            && actor.shield.getShieldById(actor.elderReactiveShield).getCapacity()==100,"a multi-threshold burst records every crossing but respects the ten-percent capacity ceiling");
        actor.hp满血值=900;actor.elderUpdateReactiveShield();
        check(state.stepHp==50 && state.lossRemainder==10,"max-HP reduction does not shrink the fixed threshold or invent current-HP loss");
        actor.elderClearReactiveShield();actor.hp满血值=1000;actor.hp=800;actor.elderClock=0;actor.elderUpdateReactiveShield();
        actor.elderClock=23;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits for its own twenty-four-frame interval");
        actor.elderClock=24;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);
        check(layer.getCapacity()==10 && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"periodic supplement uses missing HP with a one-percent per-pulse ceiling");
        actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==id,"duplicate calls at one clock cannot repeat a periodic supplement");
        actor.shield.update(18);check(near(layer.getCapacity(),5),"temporary HP loses half its capacity after eighteen active shield frames");
        var pause:Object=_root.暂停;_root.暂停=true;var heldClock:Number=actor.elderClock;
        actor.elderTick();actor.elderUpdateReactiveShield();
        check(actor.elderClock==heldClock && actor.elderReactiveShield==id && near(layer.getCapacity(),5),"paused actor cannot advance the pulse clock or refresh temporary HP");_root.暂停=pause;
        actor.shield.update(18);
        check(actor.shield.getShieldById(id)==null && actor.shield.getShieldById(foreign.getId())!=null,"unrefreshed reactive capacity decays to zero at thirty-six frames and preserves foreign shields");

        // Exercise the real post-damage event order: the trigger hit has already settled its leech.
        actor.elderClearReactiveShield();actor.hp=actor.hp满血值=1000;actor.elderClock=0;actor.elderUpdateReactiveShield();
        var attacker:MovieClip=target();attacker.hp=500;attacker.hp满血值=1000;attacker.狂暴模式=1;
        var incoming:Object=bullet("kicks");incoming.子弹威力=300;incoming.击溃=0;incoming.斩杀=0;incoming.吸血=50;
        incoming.发射者=attacker._name;incoming.击中时触发函数=null;incoming.hitBehavior=null;
        incoming.damageManager=DamageManagerFactory.resolveForBullet(incoming);
        var lifeBefore:Number=actor.elderCombatStats.reactiveLeechHits,absorbedBefore:Number=actor.elderCombatStats.reactiveAbsorbed;
        settle(incoming,attacker,actor,false);
        check(attacker.hp>500 && actor.elderReactiveShield>=0 && actor.elderCombatStats.reactiveLeechHits==lifeBefore+1,"actual triggering blow retains settled leech and immediately generates protection for later hits");
        var attackerHp:Number=attacker.hp;incoming.hitCount=0;settle(incoming,attacker,actor,false);
        check(attacker.hp==attackerHp && actor.elderCombatStats.reactiveLeechHits==lifeBefore+1
            && actor.elderCombatStats.reactiveAbsorbed>absorbedBefore,"following actual hit consumes temporary HP while the hard threshold blocks leech");
        attacker.removeMovieClip();
        state=actor.elderReactiveState;actor.elderClearReactiveShield();actor.elderIdentity={};actor.hp=1000;actor.elderUpdateReactiveShield();
        var current:Object=actor.elderReactiveState;actor.hp=950;state.callback.apply(state,[actor,null,null,null,DamageResult.NULL]);
        check(actor.elderReactiveShield==-1 && current.lossRemainder==0,"retired dispatcher context cannot grant against a replacement identity");
        actor.elderObserveReactiveHp();check(actor.elderReactiveShield>=0,"current identity still receives its own legitimate loss grant");
        actor.hp=0;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(actor.elderReactiveState==null && actor.elderReactiveShield==-1 && actor.shield.getShieldById(foreign.getId())!=null,"death removes only owned reactive protection and retires its subscription");
        actor.hp=800;actor.elderForm="human";actor.elderUpdateReactiveShield();
        check(actor.elderReactiveState==null && actor.elderReactiveShield==-1,"human form cannot initialize the robot-only reactive shield");
        actor.elderForm="robot";actor.hp=actor.hp满血值=15318;actor.空手攻击力=1033;actor.elderClock=0;actor.elderUpdateReactiveShield();
        actor.hp=14552;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        layer=actor.shield.getShieldById(actor.elderReactiveShield);
        check(near(layer.getCapacity(),765.9) && layer.getStrength()==10330,"actual level-thirty five-percent grant covers the observed rage-heavy raw threshold");
        attacker=target();attacker.hp=500;attacker.hp满血值=1000;actor.损伤值=100;
        var rage:Object={子弹威力:8925,吸血:50,击溃:1,additionalEffectDamage:0};
        var rageResult:DamageResult=DamageResult.getIMPACT();rageResult.actualScatterUsed=1;
        LifeStealDamageHandle.getInstance().handleBulletDamage(rage,attacker,actor,null,rageResult);
        CrumbleDamageHandle.getInstance().handleBulletDamage(rage,attacker,actor,null,rageResult);
        check(attacker.hp==500 && actor.hp满血值==15318,"new reactive grant blocks both actual rage-heavy leech and crumble gates");
        actor.shield.absorbDamage(2000,false,1);actor.损伤值=100;
        LifeStealDamageHandle.getInstance().handleBulletDamage(rage,attacker,actor,null,rageResult);
        CrumbleDamageHandle.getInstance().handleBulletDamage(rage,attacker,actor,null,rageResult);
        check(attacker.hp>500 && actor.hp满血值==15165,"exhausted reactive capacity restores the original rage-heavy effects instead of granting permanent immunity");
        attacker.removeMovieClip();actor.elderClearReactiveShield();
        actor.dispatcher.destroy();actor.hp=old.hp;actor.hp满血值=old.max;actor.空手攻击力=old.attack;
        actor.elderClock=old.clock;actor.dispatcher=old.dispatcher;actor.shield=old.shield;
        actor.elderIdentity=old.identity;actor.elderForm=old.form;actor.防御力=old.defense;
    }
'''
edit(p, '    }\n}\n', '    }\n' + tests + '}\n')

p = 'tools/cf6-elder-assets/README.md'
old = next(line for line in (R / p).read_text('utf8').splitlines() if line.startswith('当前强度校准尚未完成。'))
new = '当前强度校准尚未完成。R15 的 2,406 项行为检查已通过，十二场诊断试验仍在使用冻结候选运行。用户追加“每损失 5% 生命强制生成、再周期补充”的应激盾方向；R16 源码准备按机器人本形态初始满血值固定门槛，每跨一档将该档损失转换为容量，并保留不足一档的余量。它与周期补充共用一层最高 10% 初始满血容量的硬盾，强度仍为空手攻击力的 10 倍；每 24 个有效帧按当前缺失生命的 5% 补充，单次不超过初始满血的 1%，每次生成的容量在没有新补充时于 36 帧内线性衰减至零。该机制不治疗实际 HP，也不修改全局吸血顺序；触发补盾的那一击已经完成吸血，后续命中才受新盾保护。动作、倍率、已有砸地／连打盾与光束盾保持 R15。新机制尚待编译、边界测试与完整对战验证，不能据此宣布兽王狂暴期零吸血。全部旧轮次、失败及运行身份仍见[校准汇总](evidence/20261017-calibration/summary.json)，尚未提交推送或正式发布 runtime。'
edit(p, old, new)

p = 'agentsDoc/testing-details.md'
old = next(line for line in (R / p).read_text('utf8').splitlines() if line.startswith('- 老头两阶段：'))
edit(p, old, old + ' 应激盾另核真实 HP 下降跨 5% 的即时授予、余量与多阈值上限、周期补充、快速衰减、治疗基线、暂停、旧身份及死亡清理，并以真实命中事件验证触发击与后续击的吸血顺序。')

paths = {row['path'] for row in json.loads((O / 'before-r15-hard-counter-index.json').read_text('utf8'))}
paths.update(changes)
index = []
with zipfile.ZipFile(O / 'before-r16-reactive-shield.zip', 'x', zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(paths):
        data = (R / name).read_bytes()
        archive.writestr(name, data)
        index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
with (O / 'before-r16-reactive-shield-index.json').open('x', encoding='utf8') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
for name, value in changes.items():
    prior = (R / name).read_bytes()
    newline = '\r\n' if b'\r\n' in prior else '\n'
    data = value.replace('\n', newline).encode('utf8')
    if name.endswith('.as') or prior.startswith(b'\xef\xbb\xbf'):
        data = b'\xef\xbb\xbf' + data
    (R / name).write_bytes(data)
for source, dest in [('build-r15-elder', 'build-r16-elder'), ('build-and-test-r15', 'build-and-test-r16'), ('finish-native-cleanup-after-r15', 'finish-native-cleanup-after-r16')]:
    value = (O / (source + '.ps1')).read_text('utf-8-sig').replace('r15', 'r16').replace('R15', 'R16').replace('native-r16-hard-counter', 'native-r16-reactive-shield')
    with (O / (dest + '.ps1')).open('xb') as f:
        f.write(value.encode('utf-8-sig'))
plan = json.loads((O / 'native-r15-hard-counter-plan.json').read_text('utf8'))
plan['output'] = 'native-r16-reactive-shield'
with (O / 'native-r16-reactive-shield-plan.json').open('x', encoding='utf8') as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)
value = (O / 'check-elder-r15-image-equivalence.py').read_text('utf8').replace('R15', 'R16').replace('elder-r15-image-equivalence.json', 'elder-r16-image-equivalence.json')
with (O / 'check-elder-r16-image-equivalence.py').open('x', encoding='utf8') as f:
    f.write(value)
print(json.dumps({'changed': list(changes), 'robotOnly': True, 'lossStep': .05, 'capacityLimit': .1,
                  'pulseFrames': 24, 'pulseMissingRatio': .05, 'pulseCapacityLimit': .01, 'decayFrames': 36,
                  'attackPowerAndPanelUnchanged': True, 'compiled': False}, ensure_ascii=False))
