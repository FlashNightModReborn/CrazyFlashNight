import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.Effect.ElderBeamVulnerability;
import org.flashNight.arki.component.Buff.Effect.FireControlVulnerability;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
import org.flashNight.neur.Event.EventDispatcher;

/** Real emitted action declarations pass through settlement, BuffManager and shield implementations. */
class org.flashNight.arki.unit.Action.Melee.Cf6ElderCombatEffectsTest {
    private static var samples:Object;
    private static var passed:Number,failed:Number,serial:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6ElderCombatEffectsTest: "+label);}
    }
    private static function near(a:Number,b:Number):Boolean {return Math.abs(a-b)<0.00001;}
    public static function reset():Void {samples={};passed=failed=serial=0;}
    public static function capture(action:String,data:Object,actor:MovieClip):Void {
        if(samples[action]==undefined){
            // Snapshot before another real-settlement fixture consumes this emitted bullet.
            var original:Object={};for(var key:String in data)original[key]=data[key];
            samples[action]={data:original,actor:actor};
        }
    }
    private static function target():MovieClip {
        var t:MovieClip=_root.cf6MakePlayerTarget(_root.gameworld,"effectTarget"+(++serial),175);
        t.buffManager=new BuffManager(t,{});t.createEmptyMovieClip("man",2);
        return t;
    }
    private static function bullet(action:String):Object {
        var result:Object={};for(var key:String in samples[action].data)result[key]=samples[action].data[key];
        result.固伤=0;result.flags=256;result.hitCount=0;result.damageManager=DamageManagerFactory.resolveForBullet(result);
        return result;
    }
    private static function settle(data:Object,actor:MovieClip,t:MovieClip,miss:Boolean):Object {
        actor.dispatcher={publish:function():Void {}};
        var queue:Object=BulletQueueProcessor;
        // Suppress only number rendering; calculation, actual-hit classification and callbacks are production.
        var impact:Object=DamageResult.getIMPACT();var display:Function=impact.triggerDisplay;
        impact.triggerDisplay=function(x:Number,y:Number,name:String):Void {};
        var context:Object={bullet:data,shooter:actor,Damage:DamageCalculator,flags:256,meleeMask:768};
        var result:Object=queue.settleHit(context,t,{overlapCenter:{x:t._x,y:t._y}},1,miss?"躲闪":"未躲闪",true);
        impact.triggerDisplay=display;
        return result;
    }
    public static function settleFollowup(data:Object,actor:MovieClip,t:MovieClip):Void {
        if(DamageManagerFactory.Basic==null)DamageManagerFactory.init();PinkNoiseEngine.getInstance();
        data.固伤=0;data.flags=256;data.hitCount=0;data.damageManager=DamageManagerFactory.resolveForBullet(data);
        settle(data,actor,t,false);
    }
    public static function runAllTests(nativeKnockback:Function):Boolean {
        if(DamageManagerFactory.Basic==null)DamageManagerFactory.init();PinkNoiseEngine.getInstance();
        check(samples.beam!=undefined && samples.kicks!=undefined && samples.slam!=undefined && samples.heavyBeam!=undefined,"all four emitted robot actions captured");
        if(failed>0)return false;
        check(near(samples.kicks.actor.elderTuning.shieldAttackScale,55/43),"formula-driven attack redistribution is explicitly normalized for shield strength");
        check(samples.kicks.actor.elderTuning.meleeShieldCapacityScale==0.5 && samples.kicks.actor.elderTuning.beamShieldCapacityScale==0.2 && samples.kicks.actor.elderTuning.reactiveShieldCapacityScale==0.75,"melee, beam and reactive grants retain independent capacity budgets without changing hardness");
        // Keep legacy exact-threshold fixtures at reference attack 100; real level-30 panels are exercised below.
        var shieldActions:Array=["beam","kicks","slam","heavyBeam"];
        for(var shieldActionIndex:Number=0;shieldActionIndex<shieldActions.length;shieldActionIndex++)
            samples[shieldActions[shieldActionIndex]].actor.空手攻击力=100*43/55;
        var reference:Number=samples.kicks.actor.空手攻击力*samples.kicks.actor.elderTuning.shieldAttackScale;
        trace("[CF6_SHIELD_REFERENCE] attackDelta="+(reference-100)+" hardDelta="+(reference*10-1000)+" beamDelta="+(reference*0.75-75)+" softDelta="+(reference*0.12-12));
        var actor:MovieClip=samples.kicks.actor;
        var originalShieldLevel:Number=actor.等级;actor.等级=99;
        actor.shield=AdaptiveShield.createDormant("melee-reward-fixture");actor.shield.setOwner(actor);
        var foreign:Shield=Shield.createTemporary(7,1,600,"foreign");actor.shield.addShield(foreign);
        var t:MovieClip=target(),data:Object=bullet("kicks"),before:Number=t.hp;
        settle(data,actor,t,true);
        check(t.hp==before && t.hp满血值==100000 && actor.shield.getShieldCount()==1,"MISS neither crumbles nor rewards shield");
        settle(data,actor,t,false);
        check(t.hp满血值==99500 && t.hp<before && t.损伤值>=500 && before-t.hp>=500,"actual punch uses 0.5 percent paired crumble");
        var first:Number=actor.elderMeleeShield,shield:IShield=actor.shield.getShieldById(first);
        check(first>=0 && near(shield.getCapacity(),50) && near(shield.getStrength(),12),"actual melee earns calibrated temporary shield");
        var kickAbsorbedBefore:Number=actor.elderCombatStats.kicksShieldAbsorbed;
        check(shield.absorbDamage(100,false,1)==88 && near(shield.getCapacity(),38),"reward shield absorbs a bounded per-hit amount");
        check(near(actor.elderCombatStats.kicksShieldAbsorbed-kickAbsorbedBefore,12),"actual soft-layer absorption reaches the owned diagnostic callback");
        settle(data,actor,t,false);
        check(actor.elderMeleeShield==first && actor.shield.getShieldCount()==2,"same contact cannot stack reward across targets");
        data=bullet("kicks");settle(data,actor,t,false);
        check(actor.elderMeleeShield!=first && actor.shield.getShieldById(first)==null && actor.shield.getShieldCount()==2
            && actor.shield.getShieldById(foreign.getId())!=null,"new contact refreshes only owned shield");
        kickAbsorbedBefore=actor.elderCombatStats.kicksShieldAbsorbed;actor.elderMeleeShieldAbsorb(shield,1);
        check(actor.elderCombatStats.kicksShieldAbsorbed==kickAbsorbedBefore,"retired melee layer cannot add absorption to its replacement");
        first=actor.elderMeleeShield;actor.shield.update(59);
        check(actor.shield.getShieldById(first)!=null,"shield lives through 59 frames");actor.shield.update(1);
        check(actor.shield.getShieldById(first)==null && actor.shield.getShieldById(foreign.getId())!=null,"shield expires at 60 without deleting foreign shield");
        actor.等级=1;data=bullet("kicks");settle(data,actor,t,false);
        shield=actor.shield.getShieldById(actor.elderMeleeShield);
        check(near(shield.getStrength(),30) && near(shield.getCapacity(),50),"level-one melee shield uses the low endpoint");
        check(shield.absorbDamage(100,false,1)==70 && near(shield.getCapacity(),20),"low-level reward shield applies its calibrated per-hit absorption");
        first=actor.elderMeleeShield;actor.shield.update(119);
        check(actor.shield.getShieldById(first)!=null,"level-one melee shield retains its longer coverage through frame 119");
        actor.shield.update(1);
        check(actor.shield.getShieldById(first)==null && actor.shield.getShieldById(foreign.getId())!=null,"level-one melee shield expires at 120 without touching foreign shield");
        actor.等级=50;data=bullet("kicks");settle(data,actor,t,false);
        first=actor.elderMeleeShield;shield=actor.shield.getShieldById(first);
        check(near(shield.getStrength(),21) && near(shield.getCapacity(),50),"middle-level reward uses the interpolated shield strength");
        actor.shield.update(89);check(actor.shield.getShieldById(first)!=null,"middle-level shield retains frame 89");
        actor.shield.update(1);check(actor.shield.getShieldById(first)==null && actor.shield.getShieldById(foreign.getId())!=null,"middle-level shield expires at 90 and preserves foreign shield");
        _root.护盾函数.移除护盾(actor,actor.elderMeleeShield);actor.elderMeleeShield=-1;
        actor.等级=Number("bad");actor.elderRewardMelee(t,"kicks");
        check(actor.shield.getShieldCount()==1 && actor.elderMeleeShield==-1,"invalid level cannot create an infinite-strength fallback shield");
        actor.等级=originalShieldLevel;
        var identity:Object=actor.elderIdentity;actor.elderIdentity={};data=bullet("kicks");settle(data,actor,t,false);
        check(actor.shield.getShieldCount()==1,"stale shooter identity cannot reward replacement");actor.elderIdentity=identity;

        // Actual emitted slam and kick callbacks own independent shield layers.
        actor.等级=99;data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;
        var hardGrants:Number=actor.elderCombatStats.slamShieldGrants;
        actor.攻击目标=t._name;
        check(actor.elderSlamHeavyWindow==null,"kicks never open a slam follow-up window");
        settle(data,actor,t,true);
        check(actor.elderSlamShield==-1 && actor.elderCombatStats.slamShieldGrants==hardGrants,"missed slam grants no hard shield");
        check(actor.elderSlamHeavyWindow==null,"missed slam grants no heavy permission");
        var gateResult:Object=settle(data,actor,t,false),hardId:Number=actor.elderSlamShield;
        var hard:IShield=actor.shield.getShieldById(hardId);
        check(hardId>=0 && near(hard.getStrength(),1000) && near(hard.getCapacity(),7.5)
            && actor.elderCombatStats.slamShieldGrants==hardGrants+1,"actual slam earns a hard shield with bounded capacity");
        var permission:Object=actor.elderSlamHeavyWindow;
        check(actor.elderHasSlamHeavyWindow(t,72) && permission.expires==actor.elderClock+180
            && t.buffManager.getBuffById(ElderBeamVulnerability.ID)==null && near(t.damageTakenMultiplier,1),"actual slam opens a same-target window without adding vulnerability");
        settle(data,actor,t,false);
        check(actor.elderSlamHeavyWindow===permission,"duplicate slam callback cannot refresh its heavy permission");
        check(actor.elderSlamShield==hardId && actor.elderCombatStats.slamShieldGrants==hardGrants+1,"duplicate slam callback cannot refresh the hard shield");
        actor.shield.update(90);data=bullet("kicks");settle(data,actor,t,false);
        var softId:Number=actor.elderMeleeShield;
        check(actor.elderSlamHeavyWindow===permission,"kick cannot replace or extend the slam heavy window");
        check(actor.elderSlamShield==hardId && actor.shield.getShieldById(hardId)!=null
            && near(actor.shield.getShieldById(softId).getStrength(),12),"later kick preserves the independent hard shield and stays soft");
        actor.shield.update(29);check(actor.shield.getShieldById(hardId)!=null,"hard shield retains frame 119 after a later kick");
        actor.shield.update(1);
        check(actor.shield.getShieldById(hardId)==null && actor.shield.getShieldById(softId)!=null,"kick refresh does not extend the 120-frame hard shield");
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;
        gateResult=settle(data,actor,t,false);hardId=actor.elderSlamShield;hard=actor.shield.getShieldById(hardId);
        check(actor.shield.getShieldById(softId)!=null && hard!=null,"new slam refreshes its own layer without deleting the soft shield");
        actor.elderCancelAttack();
        check(actor.elderHasSlamHeavyWindow(t,72),"earned slam permission survives ordinary action cancellation");
        var savedClock:Number=actor.elderClock;permission=actor.elderSlamHeavyWindow;
        actor.elderClock=permission.expires-72;check(actor.elderHasSlamHeavyWindow(t,72),"last full-channel start boundary remains eligible");
        actor.elderClock=permission.expires-71;check(!actor.elderHasSlamHeavyWindow(t,72) && actor.elderHasSlamHeavyWindow(t),"too little remaining time cannot start a full channel");
        actor.elderClock=permission.expires;check(!actor.elderHasSlamHeavyWindow(t) && actor.elderSlamHeavyWindow==null,"slam permission expires exactly at frame 180");
        actor.elderClock=savedClock;
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;settle(data,actor,t,false);
        hardId=actor.elderSlamShield;hard=actor.shield.getShieldById(hardId);
        var switched:MovieClip=target();actor.攻击目标=switched._name;
        check(!actor.elderHasSlamHeavyWindow(switched) && actor.elderSlamHeavyWindow==null,"switching targets revokes the earned window");
        actor.攻击目标=t._name;check(!actor.elderHasSlamHeavyWindow(t),"switching back cannot resurrect revoked permission");switched.removeMovieClip();
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;settle(data,actor,t,false);
        hardId=actor.elderSlamShield;hard=actor.shield.getShieldById(hardId);
        var replacedName:String=t._name;t.removeMovieClip();
        t=_root.cf6MakePlayerTarget(_root.gameworld,replacedName,175);t.buffManager=new BuffManager(t,{});t.createEmptyMovieClip("man",2);
        check(!actor.elderHasSlamHeavyWindow(t) && actor.elderSlamHeavyWindow==null,"real same-name MovieClip replacement cannot inherit permission");
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity={};settle(data,actor,t,false);
        check(actor.elderSlamHeavyWindow==null,"stale shooter callback cannot grant follow-up permission");
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;settle(data,actor,t,false);
        hardId=actor.elderSlamShield;hard=actor.shield.getShieldById(hardId);t.hp=0;
        check(!actor.elderHasSlamHeavyWindow(t) && actor.elderSlamHeavyWindow==null,"target death revokes the unmarked follow-up");t.hp=t.hp满血值;
        check(actor.shield.getShieldById(hardId)!=null && actor.shield.getShieldById(softId)!=null,"earned melee shields survive ordinary attack cancellation");

        // The shipped leech and crumble handlers consume this actual granted shield.
        var attacker:MovieClip=target();attacker.hp=500;attacker.hp满血值=1000;
        var oldMax:Number=actor.hp满血值,oldLoss:Number=actor.损伤值;
        var pressure:Object={子弹威力:1000,吸血:50,击溃:1,additionalEffectDamage:0};actor.损伤值=100;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp==500 && actor.hp满血值==oldMax,"hard shield blocks both leech and crumble at its exact power threshold");
        pressure.子弹威力=1001;actor.损伤值=100;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp>500 && actor.hp满血值==oldMax-10,"power above the hard shield threshold keeps both generic effects");
        actor.hp满血值=oldMax;actor.损伤值=100;attacker.hp=500;
        var slamAbsorbedBefore:Number=actor.elderCombatStats.slamShieldAbsorbed;
        check(hard.absorbDamage(2,false,1)==0 && hard.absorbDamage(2,false,1)==0
            && near(hard.getCapacity(),3.5) && near(actor.shield.getStrength(),1000),"two small hits retain the thin hard layer's generic effect threshold");
        check(near(actor.elderCombatStats.slamShieldAbsorbed-slamAbsorbedBefore,4),"actual hard-layer absorption is recorded separately from the soft layer");
        actor.shield.absorbDamage(25,false,1);
        check(near(actor.shield.getStrength(),12) && actor.shield.getShieldById(softId)!=null,"spent hard capacity immediately exposes the remaining soft layer");
        pressure.子弹威力=50;pressure.additionalEffectDamage=0;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp>500 && actor.hp满血值==oldMax-10,"soft shield does not inherit the spent hard shield's leech or crumble immunity");
        // Replay the actual level-30 panel against the authored rage-heavy power.
        var pressureAttack:Number=actor.空手攻击力,pressureLevel:Number=actor.等级;
        actor.等级=30;actor.空手攻击力=813;actor.hp满血值=15318;
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;
        gateResult=settle(data,actor,t,false);hardId=actor.elderSlamShield;hard=actor.shield.getShieldById(hardId);
        check(near(hard.getStrength(),8130*55/43) && near(hard.getCapacity(),114.885),"actual level-thirty slam grant covers the observed rage-heavy threshold");
        attacker.hp=500;actor.损伤值=100;pressure.子弹威力=8925;pressure.additionalEffectDamage=0;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp==500 && actor.hp满血值==15318,"8925-power rage-heavy cannot leech or crumble through the actual low-level grant");
        actor.shield.absorbDamage(1000,false,1);actor.损伤值=100;pressure.additionalEffectDamage=0;
        LifeStealDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        CrumbleDamageHandle.getInstance().handleBulletDamage(pressure,attacker,actor,null,DamageResult(gateResult));
        check(attacker.hp>500 && actor.hp满血值==15165,"exhausting the bounded low-level grant restores the same rage-heavy effects");
        actor.空手攻击力=pressureAttack;actor.等级=pressureLevel;
        actor.hp满血值=oldMax;actor.损伤值=oldLoss;attacker.removeMovieClip();
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;settle(data,actor,t,false);
        hardId=actor.elderSlamShield;var oldHp:Number=actor.hp;actor.hp=0;actor.elderCancelAttack();
        check(actor.shield.getShieldById(hardId)==null && actor.shield.getShieldById(softId)==null
            && actor.shield.getShieldById(foreign.getId())!=null,"death removes both owned melee layers and preserves a foreign shield");
        data=bullet("slam");data.发射者=actor._name;data.elderShooterIdentity=actor.elderIdentity;settle(data,actor,t,false);
        check(actor.elderSlamShield==-1 && actor.shield.getShieldCount()==1,"late slam cannot grant a dead shooter's hard shield");
        check(actor.elderSlamHeavyWindow==null,"dead shooter and late callback retain no slam permission");
        actor.hp=oldHp;actor.等级=originalShieldLevel;
        t.removeMovieClip();

        t=target();data=bullet("beam");actor=samples.beam.actor;before=t.hp;
        var beamHitsBefore:Number=actor.elderCombatStats.beamHits,beamPowerBefore:Number=actor.elderCombatStats.beamHitPower;
        settle(data,actor,t,true);
        check(t.hp==before && t.buffManager.getBuffById(ElderBeamVulnerability.ID)==null && actor.elderCombatStats.beamHits==beamHitsBefore,"missed red beam gives no vulnerability or actual-hit credit");
        settle(data,actor,t,false);
        check(t.hp<before && data.伤害类型=="魔法" && data.魔法伤害属性=="波" && data.子弹威力==300 && actor.elderCombatStats.beamHits==beamHitsBefore+1 && actor.elderCombatStats.beamHitPower==beamPowerBefore+3,"primer keeps authored wave damage and records actual contact");
        check(near(t.damageTakenMultiplier,1.25) && near(t.ti61CrumbleTakenMultiplier,1.25),"primer raises damage and crumble by 25 percent");
        t.buffManager.update(90);check(near(t.damageTakenMultiplier,1.125),"six-second vulnerability decays linearly at midpoint");
        ElderBeamVulnerability.applyToTarget(t,{peak:0.25,durationFrames:180});ElderBeamVulnerability.applyToTarget(t,{peak:0.25,durationFrames:180});
        check(near(t.damageTakenMultiplier,1.25),"multiple casters and repeat hits refresh without stacking");
        t.损伤值=0;var crumble:Object={击溃:0.5,子弹威力:100,additionalEffectDamage:0};
        CrumbleDamageHandle.instance.handleBulletDamage(crumble,{},t,{},DamageResult.getIMPACT());
        check(t.hp满血值==99375 && t.损伤值==625,"marked target takes enhanced real crumble");
        t.buffManager.update(180);check(near(t.damageTakenMultiplier,1) && near(t.ti61CrumbleTakenMultiplier,1),"expiry restores both multipliers");
        check(!actor.elderHasBeamMark(t),"zero remaining time cannot authorize heavy beam during deferred node cleanup");
        check(!ElderBeamVulnerability.applyToTarget(t,{peak:0.26,durationFrames:180})
            && !ElderBeamVulnerability.applyToTarget(t,{peak:0.25,durationFrames:30}),"invalid effect contracts rejected");
        check(!BulletHitEffectRegistry.apply(bullet("beam"),actor,t,{dodgeStatus:"HIT",scatterModelEnabled:true,actualScatterUsed:2,scatterMissCount:2}),"all-MISS scatter cannot apply mark");
        ElderBeamVulnerability.applyToTarget(t,{peak:0.25,durationFrames:180});t.hp=0;t.buffManager.update(1);
        check(!actor.elderHasBeamMark(t) && near(t.damageTakenMultiplier,1),"death immediately disables mark and effect");
        // MetaBuff first ejects its Pods, then retires its registered node on maintenance updates.
        for(var cleanupPass:Number=0;cleanupPass<3;cleanupPass++)t.buffManager.update(0);
        check(t.buffManager.getBuffById(ElderBeamVulnerability.ID)==null,"expired node finishes the normal cleanup transaction");
        t.hp=t.hp满血值=100000;
        check(FireControlVulnerability.applyToTarget(t,{peak:0.75,durationFrames:30}) && near(t.damageTakenMultiplier,1.75),"Titanium 171 retains independent 75-percent one-second contract");
        t.buffManager.update(30);check(near(t.damageTakenMultiplier,1),"Titanium 171 still expires at 30 frames");
        t.removeMovieClip();

        t=target();actor=samples.slam.actor;actor.shield=AdaptiveShield.createDormant("slam-shield");actor.shield.setOwner(actor);
        var originalClock:Number=actor.elderClock;
        t._x=actor._x+(actor.方向=="左"?-180:180);t._y=t.Z轴坐标=actor.Z轴坐标;
        t.刚体=true;t.免疫击退=t.浮空=t.倒地=t.硬直中=false;t.韧性系数=0;t.remainingImpactForce=0;
        t.移动钝感硬直=t.状态改变=function():Void {};
        t.移动=function(direction:String,speed:Number):Void {this._x+=direction=="右"?speed:-speed;};
        t.被击移动=nativeKnockback;
        data=bullet("slam");var impactResult:Object=settle(data,actor,t,false);
        var impact:MovieClip=_root.gameworld.createEmptyMovieClip("actualSlamImpact",_root.gameworld.getNextHighestDepth());
        for(var key:String in data)impact[key]=data[key];impact.破坏力=data.子弹威力;
        ImpactStateHandler.handleImpactState(t,impact,DamageResult(impactResult),actor.方向,true);
        check(t.speed==18 && t.减速度==0.5,"actual stagger route applies strong grounded knockback");
        for(var step:Number=0;step<40;step++)if(t.speed>0)t.onEnterFrame();
        var distance:Number=Math.abs(t._x-actor._x);actor.elderClock+=40;
        check(near(distance,495) && actor.elderComboReady(t,distance,0,0),"actual 180-to-495 knockback remains in the beam combo window");
        actor.攻击目标=t._name;actor.elderNextHeavyBeam=0;
        check(actor.elderChooseAttack(distance,0,0,true)=="heavyBeam" && !actor.elderHasBeamMark(t),"actual unmarked slam knockback selects the continuous follow-up");
        actor.elderNextHeavyBeam=actor.elderClock+1;
        check(actor.elderChooseAttack(distance,0,0,true)=="beam","slam permission does not bypass heavy cooldown");actor.elderNextHeavyBeam=0;
        actor.elderSlamHeavyWindow=null;
        ElderBeamVulnerability.applyToTarget(t,{peak:0.25,durationFrames:180});
        check(actor.elderChooseAttack(distance,0,0,true)=="heavyBeam","marked displaced target selects heavy follow-up");
        actor.elderClock=originalClock;actor.攻击目标="无";impact.removeMovieClip();
        check(data.斩杀==10 && data.水平击退速度==18 && data.垂直击退速度==0,"slam declares execute and grounded strong knockback");
        check(actor.elderCombo.target==t._name && actor.elderCombo.identity===t.__elderActionIdentity,"only actual slam hit arms target-bound beam combo");
        var killed:MovieClip=target();killed.hp=5000;data=bullet("slam");settle(data,actor,killed,false);
        check(killed.hp==0,"real execute handler finishes a target below ten percent");killed.removeMovieClip();t.removeMovieClip();

        t=target();actor=samples.heavyBeam.actor;data=bullet("heavyBeam");before=t.hp;
        var heavyHitsBefore:Number=actor.elderCombatStats.heavyBeamHits,heavyPowerBefore:Number=actor.elderCombatStats.heavyBeamHitPower;
        settle(data,actor,t,false);
        check(data.子弹威力==50 && data.伤害类型=="魔法" && data.魔法伤害属性=="波" && t.hp<before && actor.elderCombatStats.heavyBeamHits==heavyHitsBefore+1 && actor.elderCombatStats.heavyBeamHitPower==heavyPowerBefore+0.5,"continuous heavy beam starts with half power and records actual contact");
        check(t.buffManager.getBuffById(ElderBeamVulnerability.ID)==null,"heavy beam cannot grant its own prerequisite");t.removeMovieClip();
        actor=samples.beam.actor;actor.状态="空手攻击";
        actor.elderRecordBeamShield();
        var spentBefore:Number=actor.elderCombatStats.beamShieldSpent,unusedBefore:Number=actor.elderCombatStats.beamShieldUnused,samplesBefore:Number=actor.elderCombatStats.beamShieldSamples;
        actor.shield=AdaptiveShield.createDormant("beam-shield-fixture");actor.shield.setOwner(actor);
        foreign=Shield.createTemporary(7,1,300,"foreign");actor.shield.addShield(foreign);
        actor.elderBeginAttack(actor.man,"beam");first=actor.elderBeamShield;shield=actor.shield.getShieldById(first);
        check(first>=0 && near(shield.getCapacity(),40) && near(shield.getStrength(),75),"beam action owns a bounded charging shield");
        check(shield.absorbDamage(100,false,1)==60 && near(shield.getCapacity(),0),"charging shield absorbs only its remaining capacity");
        actor.elderBeginAttack(actor.man,"beam");
        check(actor.elderBeamShield!=first && actor.shield.getShieldById(first)==null && actor.shield.getShieldCount()==2,"new beam replaces only its own shield");
        check(near(actor.elderCombatStats.beamShieldSpent-spentBefore,40)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,0)
            && actor.elderCombatStats.beamShieldSamples==samplesBefore+1,"beam accounting reads actual spent and discarded capacity once at replacement");
        first=actor.elderBeamShield;actor.shield.update(43);
        check(actor.shield.getShieldById(first)!=null,"charging shield survives through frame 43 during recovery");actor.shield.update(1);
        check(actor.shield.getShieldById(first)==null && actor.shield.getShieldById(foreign.getId())!=null,"charging shield expires at frame 44 without deleting foreign shield");
        actor.elderRecordBeamShield();actor.elderRecordBeamShield();
        check(near(actor.elderCombatStats.beamShieldSpent-spentBefore,40)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,40)
            && actor.elderCombatStats.beamShieldSamples==samplesBefore+2,"expired remaining capacity is measured once without reviving or changing the shield");
        var shieldAttack:Number=actor.空手攻击力,shieldHp:Number=actor.hp满血值;
        actor.空手攻击力=2000;actor.hp满血值=30000;
        actor.elderBeginAttack(actor.man,"beam");shield=actor.shield.getShieldById(actor.elderBeamShield);
        check(shield.getStrength()==800 && near(shield.getCapacity(),1200),"high attack cannot exceed the fixed beam shield strength cap");
        check(shield.absorbDamage(1000,false,1)==200 && near(shield.getCapacity(),400),"large hits penetrate the capped beam shield");
        actor.elderCancelAttack();actor.空手攻击力=shieldAttack;actor.hp满血值=shieldHp;
        var beamLevel:Number=actor.等级,beamLevels:Array=[1,30,60,99,120],beamCaps:Array=[120,800/13,20,80000/10201,80000/10201];
        for(var beamIndex:Number=0;beamIndex<beamLevels.length;beamIndex++){
            actor.等级=beamLevels[beamIndex];actor.elderBeginAttack(actor.man,"beam");
            shield=actor.shield.getShieldById(actor.elderBeamShield);
            check(near(shield.getCapacity(),beamCaps[beamIndex]) && near(shield.getStrength(),75),"level-dependent beam capacity "+beamLevels[beamIndex]);
            actor.elderCancelAttack();
        }
        actor.等级=Number("bad");actor.elderBeginAttack(actor.man,"beam");
        check(actor.elderBeamShield==-1 && actor.shield.getShieldCount()==1,"invalid beam level cannot grant a fallback shield");
        actor.elderCancelAttack();actor.等级=beamLevel;
        actor.elderBeginAttack(actor.man,"beam");
        check(actor.elderNextBeam==actor.elderClock+80,"ordinary beam schedules the calibrated eighty-frame interval");
        actor.elderCancelAttack();
        actor.elderBeginAttack(actor.man,"beam");first=actor.elderBeamShield;actor.elderCancelAttack();
        check(actor.shield.getShieldById(first)==null && actor.shield.getShieldById(foreign.getId())!=null,"interruption removes only owned charging shield");
        var stackedShield:Object=actor.shield;
        actor.shield=AdaptiveShield.createDormant("single-beam-accounting");actor.shield.setOwner(actor);
        spentBefore=actor.elderCombatStats.beamShieldSpent;unusedBefore=actor.elderCombatStats.beamShieldUnused;
        samplesBefore=actor.elderCombatStats.beamShieldSamples;
        actor.elderBeginAttack(actor.man,"beam");
        var singlePenetration:Number=actor.shield.absorbDamage(100,false,1);actor.elderCancelAttack();
        check(singlePenetration==60 && near(actor.elderCombatStats.beamShieldSpent-spentBefore,40)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,0),"single-shield container accounting records actual absorption without stale layer reads");
        actor.elderBeginAttack(actor.man,"beam");actor.shield.update(44);actor.elderCancelAttack();actor.elderRecordBeamShield();
        check(near(actor.elderCombatStats.beamShieldSpent-spentBefore,40)
            && near(actor.elderCombatStats.beamShieldUnused-unusedBefore,40)
            && actor.elderCombatStats.beamShieldSamples==samplesBefore+2,"single-shield expiry preserves once-only consumed and unused accounting");
        actor.shield=stackedShield;
        reactiveShieldTests(actor);
        trace("Cf6ElderCombatEffectsTest: "+passed+" passed, "+failed+" failed");return failed==0;
    }
    private static function reactiveShieldTests(actor:MovieClip):Void {
        var decayApi:Boolean=typeof _root.护盾函数.添加衰减护盾=="function";
        check(decayApi,"exact production decay adapter is available");if(!decayApi)return;
        actor.elderClearReactiveShield();
        var old:Object={hp:actor.hp,max:actor.hp满血值,attack:actor.空手攻击力,clock:actor.elderClock,
            dispatcher:actor.dispatcher,shield:actor.shield,identity:actor.elderIdentity,form:actor.elderForm,defense:actor.防御力};
        actor.hp=actor.hp满血值=1000;actor.空手攻击力=100*43/55;actor.防御力=300;actor.elderClock=0;
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
        check(layer.getCapacity()==15 && near(layer.getStrength(),1000) && actor.hp==950,"crossing five percent grants a decaying hard shield without healing HP");
        actor.elderUpdateReactiveShield();actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(actor.elderReactiveShield==id && actor.elderCombatStats.reactiveForced==forcedBefore+1,"the same observed HP loss and repeated callbacks cannot duplicate a forced grant");
        actor.hp=970;actor.elderUpdateReactiveShield();
        check(state.lossRemainder==0 && actor.elderCombatStats.reactiveForced==forcedBefore+1,"healing rebases observation without creating shield credit");
        actor.hp=920;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(actor.shield.getShieldById(actor.elderReactiveShield).getCapacity()==30 && actor.shield.getShieldCount()==2,"second loss refreshes only the owned layer and preserves a foreign shield");
        actor.hp=710;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        check(state.lossRemainder==10 && actor.elderCombatStats.reactiveForced==forcedBefore+6
            && actor.shield.getShieldById(actor.elderReactiveShield).getCapacity()==75,"a multi-threshold burst records every crossing but respects the independent seven-and-a-half-percent capacity ceiling");
        actor.hp满血值=900;actor.elderUpdateReactiveShield();
        check(state.stepHp==50 && state.lossRemainder==10,"max-HP reduction does not shrink the fixed threshold or invent current-HP loss");
        actor.elderClearReactiveShield();actor.hp满血值=1000;actor.hp=800;actor.elderClock=0;actor.elderUpdateReactiveShield();
        actor.elderClock=0;actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==-1,"periodic supplement waits until the next active frame");
        actor.elderClock=1;actor.elderUpdateReactiveShield();id=actor.elderReactiveShield;layer=actor.shield.getShieldById(id);
        check(near(layer.getCapacity(),0.625/20) && actor.hp==800 && actor.elderCombatStats.reactivePulses==pulsesBefore+1,"periodic grants scale with actual missing HP instead of saturating at twenty percent loss");
        actor.elderUpdateReactiveShield();check(actor.elderReactiveShield==id,"duplicate calls at one clock cannot repeat a periodic supplement");
        actor.shield.update(18);check(near(layer.getCapacity(),0.3125/20),"temporary HP loses half its capacity after eighteen active shield frames");
        var pause:Object=_root.暂停;_root.暂停=true;var heldClock:Number=actor.elderClock;
        actor.elderTick();actor.elderUpdateReactiveShield();
        check(actor.elderClock==heldClock && actor.elderReactiveShield==id && near(layer.getCapacity(),0.3125/20),"paused actor cannot advance the pulse clock or refresh temporary HP");_root.暂停=pause;
        actor.shield.update(18);
        check(actor.shield.getShieldById(id)==null && actor.shield.getShieldById(foreign.getId())!=null,"unrefreshed reactive capacity decays to zero at thirty-six frames and preserves foreign shields");

        actor.elderClearReactiveShield();actor.hp=800;actor.hp满血值=1000;actor.elderClock=0;actor.elderUpdateReactiveShield();
        var budgetGranted:Number=actor.elderCombatStats.reactiveGranted,budgetPulses:Number=actor.elderCombatStats.reactivePulses;
        for(var budgetFrame:Number=1;budgetFrame<=30;budgetFrame++){
            actor.shield.update(1);actor.elderClock=budgetFrame;actor.elderUpdateReactiveShield();
        }
        check(near(actor.elderCombatStats.reactiveGranted-budgetGranted,0.9375)
            && actor.elderCombatStats.reactivePulses==budgetPulses+30,"thirty actual grants at twenty percent HP loss use one fifth of the maximum supplement budget");

        var woundedHp:Array=[500,1],woundedCapacity:Array=[0.078125,0.15609375];
        for(var woundedIndex:Number=0;woundedIndex<woundedHp.length;woundedIndex++){
            actor.elderClearReactiveShield();actor.hp=woundedHp[woundedIndex];actor.hp满血值=1000;
            actor.elderClock=0;actor.elderUpdateReactiveShield();actor.elderClock=1;actor.elderUpdateReactiveShield();
            layer=actor.shield.getShieldById(actor.elderReactiveShield);
            check(near(layer.getCapacity(),woundedCapacity[woundedIndex]) && actor.hp==woundedHp[woundedIndex],
                "actual periodic grant increases with deeper wounds without healing HP "+woundedHp[woundedIndex]);
        }

        // Exercise the real post-damage event order: the trigger hit has already settled its leech.
        actor.elderClearReactiveShield();actor.hp=actor.hp满血值=1000;actor.elderClock=0;actor.elderUpdateReactiveShield();
        var attacker:MovieClip=target();attacker.hp=500;attacker.hp满血值=1000;attacker.狂暴模式=1;
        var incoming:Object=bullet("kicks");incoming.子弹威力=300;incoming.击溃=0;incoming.斩杀=0;incoming.吸血=50;
        incoming.发射者=attacker._name;incoming.击中时触发函数=null;incoming.hitBehavior=null;
        incoming.damageManager=DamageManagerFactory.resolveForBullet(incoming);
        var lifeBefore:Number=actor.elderCombatStats.reactiveLeechHits,absorbedBefore:Number=actor.elderCombatStats.reactiveAbsorbed;
        settle(incoming,attacker,actor,false);
        check(attacker.hp>500 && actor.elderReactiveShield>=0 && actor.elderCombatStats.reactiveLeechHits==lifeBefore+1,"actual triggering blow retains settled leech and immediately generates protection for later hits");
        var rageSource:Object=actor.elderCombatStats.reactiveRageSources["n:"+attacker._name];
        check(rageSource.hits==1 && rageSource.maxPower==300 && rageSource.name==attacker._name,"rage-leech diagnostics retain the actual source identity and raw power without changing settlement");
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
        actor.elderForm="robot";actor.hp=actor.hp满血值=15318;actor.空手攻击力=813;actor.elderClock=0;actor.elderUpdateReactiveShield();
        actor.hp=14552;actor.dispatcher.publish("hit",actor,null,null,null,DamageResult.NULL);
        layer=actor.shield.getShieldById(actor.elderReactiveShield);
        check(near(layer.getCapacity(),229.77) && near(layer.getStrength(),8130*55/43),"actual level-thirty five-percent grant covers the observed rage-heavy raw threshold");
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
}
