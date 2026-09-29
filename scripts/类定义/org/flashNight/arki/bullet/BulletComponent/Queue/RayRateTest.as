import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Config.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.sara.util.*;

/**
 * Controlled high-rate BQP fixture. Production XML/config, real Ray/Band Slab,
 * BQP selection/budgets, DamageCalculator, standard damage handlers, Dodge and
 * empty ShieldStack run without _raySettleProbe. Targets are disposable MCs.
 * Target-cache construction, weapon/ammo/AI, hit presentation and event
 * subscribers are fixture boundaries. Timings include observation wrappers,
 * exclude trace/setup, and do not measure painting, GPU, FPS or battle capacity.
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.RayRateTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var saved:Object;
    private static var world:MovieClip;
    private static var pumpClip:MovieClip;
    private static var cases:Array;
    private static var entries:Object;
    private static var current:Object;
    private static var baseline:Object;
    private static var caseIndex:Number;
    private static var reuse:Boolean;
    private static var completed:Boolean;
    private static var document:XML;
    private static var sourceAttempt:Number;
    private static var completeLine:String;
    private static var bqp:Object;
    private static var bridge:Object;
    private static var cacheApi:Object;
    private static var damageApi:Object;
    private static var effects:Object;
    private static var pink:Object;
    private static var uniform:Object;
    private static var mathEngine:SeededLinearCongruentialEngine;
    private static var damageFactory:DamageManagerFactory;
    private static var rayFactory:RayColliderFactory;
    private static var suiteStarted:Number;
    private static var scanCompare:Boolean;
    private static var baselineSummary:Object;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] RayRate: " + label); }
    }
    private static function finite(n:Number):Boolean { return (n - n) == 0; }
    private static function json(o:Object):String { return new LiteJSON().stringifySafe(o); }

    public static function runAllTests():Void {
        passed=0; failed=0; caseIndex=0; reuse=false; completed=false;
        sourceAttempt=0; suiteStarted=getTimer();
        scanCompare=_root.__rayRateScanCompare===true;baselineSummary=null;
        completeLine="FocusedTestRunId ray-rate Complete: " + _root.__rayRateRunId;
        bqp=BulletQueueProcessor; bridge=RayVisualBridge;
        cacheApi=TargetCacheManager; damageApi=DamageCalculator; effects=EffectSystem;
        world=_root.createEmptyMovieClip("__rayRateWorld",87651);
        pumpClip=_root.createEmptyMovieClip("__rayRatePump",87652);
        var initializer:Object=BulletInitializer;
        saved={world:_root.gameworld,paused:_root.暂停,debug:_root.调试模式,clock:_root.帧计时器,
            red:_root.受击变红,all:cacheApi.acquireAllCache,enemy:cacheApi.acquireEnemyCache,
            damage:damageApi.calculateDamage,effect:effects.Effect,rays:bqp._rayBullets,
            survivors:bqp._raySurvivors,persist:bqp._rayPersistent,probe:bqp._raySettleProbe,
            flameSerial:bqp._flameVfxSerialCounter,math:Math.random,
            attributeMap:initializer.attributeMap,rejectCandidateY:bqp.rejectRayCandidateY,
            offsetX:SceneCoordinateManager.effectOffset.x,offsetY:SceneCoordinateManager.effectOffset.y};
        try {
            install();
            if(scanCompare) {
                check(typeof saved.rejectCandidateY=="function","production Y-reject helper exists");
                if(typeof saved.rejectCandidateY!="function") throw "rejectRayCandidateY is unavailable";
                trace("[RAY_RATE_SCAN_MODE] channels=1; reference=rejectRayCandidateY-always-false; candidate=production-helper; shared=current-deferred-lo-placement; driver=32-ticks/100ms; not-old-binary-replay");
            }
            trace("[RAY_RATE_SCOPE] real=production-XML,Ray/Band-collider,BQP,Dodge,DamageCalculator,Crit/Universal/DodgeState-handlers,HP,empty-ShieldStack; substituted=target-cache-provider,weapon/ammo/AI,dispatch-subscribers,hit-visuals; timing=getTimer-ms1,instrumented-AS2-functions-only,no-paint/GPU/FPS; _raySettleProbe=null");
            loadSource();
        } catch(error) { abort("setup: "+error); }
    }

    private static function install():Void {
        _root.gameworld=world; _root.暂停=false; _root.调试模式=false;
        _root.帧计时器={当前帧数:0};
        SceneCoordinateManager.effectOffset.setTo(0,0);
        bqp._rayBullets=[];bqp._raySurvivors=[];bqp._rayPersistent=true;bqp._raySettleProbe=null;
        _root.受击变红=function():Void { if(RayRateTest.current!=null) RayRateTest.current.redCalls++; };
        effects.Effect=function() { if(RayRateTest.current!=null) RayRateTest.current.effectCalls++;return null; };
        cacheApi.acquireAllCache=function(u,n):Object { return RayRateTest.acquireCache(); };
        cacheApi.acquireEnemyCache=function(u,n):Object { return RayRateTest.acquireCache(); };
        damageApi.calculateDamage=function(b,s,t,m,d) { return RayRateTest.settle(b,s,t,m,d); };
        var resultClass:Object=DamageResult;
        saved.display=resultClass.prototype.triggerDisplay;
        resultClass.prototype.triggerDisplay=function():Void { if(RayRateTest.current!=null) RayRateTest.current.displayCalls++; };
        pink=PinkNoiseEngine.getInstance();uniform=LinearCongruentialEngine.getInstance();
        saved.pinkState=savePink();saved.uniformState=uniform.captureState();
        saved.pinkDraw=pink.randomFluctuation;saved.uniformNext=uniform.nextFloat;saved.uniformRate=uniform.successRate;
        pink.randomFluctuation=function(range:Number):Number { return RayRateTest.drawPink(range); };
        uniform.nextFloat=function():Number { return RayRateTest.drawUniform(); };
        uniform.successRate=function(chance:Number):Boolean { return RayRateTest.drawChance(chance); };
        mathEngine=new SeededLinearCongruentialEngine(161803);
        Math.random=mathRandom;
        saved.mathReadOnly=Math.random!==mathRandom;
        if(saved.mathReadOnly) { _global.ASSetPropFlags(Math,"random",0,4);Math.random=mathRandom; }
        check(Math.random===mathRandom,"deterministic Math.random counting hook installed");
        damageFactory=new DamageManagerFactory([CritDamageHandle.getInstance(),UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),MultiShotDamageHandle.getInstance(),NanoToxicDamageHandle.getInstance(),
            LifeStealDamageHandle.getInstance(),CrumbleDamageHandle.getInstance(),ExecuteDamageHandle.getInstance()],64);
        rayFactory=new RayColliderFactory(0);
    }
    private static function acquireCache():Object { current.cacheAcquires++;return current.cache; }
    private static function savePink():Object {
        return {seed:pink.seed,counter:pink.counter,s0:pink.s0,s1:pink.s1,s2:pink.s2,s3:pink.s3,s4:pink.s4};
    }
    private static function restorePink(state:Object):Void { for(var k:String in state) pink[k]=state[k]; }
    private static function drawPink(range:Number):Number {
        current.pinkCalls++;var f:Function=saved.pinkDraw;return f.call(pink,range);
    }
    private static function drawUniform():Number {
        current.uniformCalls++;var f:Function=saved.uniformNext;return f.call(uniform);
    }
    private static function drawChance(chance:Number):Boolean {
        current.chanceCalls++;var f:Function=saved.uniformRate;return f.call(uniform,chance);
    }
    private static function mathRandom():Number {
        if(current!=null) current.mathCalls++;
        return mathEngine.nextFloat();
    }
    private static function critical(b:Object):Number {
        current.critCalls++;
        var roll:Number=Math.random();
        current.critRolls.push(roll);
        return roll<0.25?2:1;
    }

    private static function loadSource():Void {
        var paths:Array=["../data/items/bullets_cases.xml","data/items/bullets_cases.xml"];
        document=new XML();document.ignoreWhite=true;
        document.onLoad=function(ok:Boolean):Void { RayRateTest.loaded(ok,this); };
        document.load(paths[sourceAttempt]);
    }
    private static function child(node:XMLNode,name:String):XMLNode {
        for(var i:Number=0;i<node.childNodes.length;i++) if(node.childNodes[i].nodeName==name) return node.childNodes[i];
        return null;
    }
    private static function loaded(ok:Boolean,xml:XML):Void {
        try {
            if(!ok) {
                sourceAttempt++;
                if(sourceAttempt<2) {loadSource();return;}
                abort("production bullets_cases.xml unavailable");return;
            }
            entries={};
            var initializer:Object=BulletInitializer;initializer.attributeMap={};
            var nodes:Array=xml.firstChild.childNodes;
            for(var i:Number=0;i<nodes.length;i++) {
                var node:XMLNode=nodes[i];if(node.nodeName!="bullet") continue;
                var attr:XMLNode=child(node,"attribute");var cfg:XMLNode=child(attr,"rayConfig");
                if(cfg==null) continue;
                var raw:Object={};
                for(var j:Number=0;j<cfg.childNodes.length;j++) {
                    var field:XMLNode=cfg.childNodes[j];
                    if(field.nodeType==1) raw[field.nodeName]=field.firstChild.nodeValue;
                }
                var budget:Number=Number(child(attr,"pierceLimit").firstChild.nodeValue);
                if(!(budget>0)) budget=1;
                var bulletName:String=String(child(node,"name").firstChild.nodeValue);
                entries[bulletName]={raw:raw,budget:budget};
                initializer.attributeMap[bulletName]={rayConfig:TeslaRayConfig.fromXML(raw),pierceLimit:budget};
            }
            buildCases();
            startCase();
            pumpClip.onEnterFrame=function():Void { RayRateTest.pump(); };
        } catch(error) {abort("XML/setup: "+error);}
    }
    private static function buildCases():Void {
        var modes:Array=[{mode:"single",bullet:"磁暴射线"},{mode:"pierce",bullet:"热能射线-强化"},
            {mode:"chain",bullet:"磁暴射线-强化"},{mode:"fork",bullet:"光棱射线-强化"},
            {mode:"combo",bullet:"谐振波射线-强化"},{mode:"flame",bullet:"喷火束"}];
        var rates:Array=[5,10,20,30];cases=[];
        if(scanCompare) {
            var chosen:Array=[0,2,1,5];
            for(var selected:Number=0;selected<chosen.length;selected++) {
                var item:Object=modes[chosen[selected]];
                check(entries[item.bullet]!=undefined,"scan comparison XML exists: "+item.bullet);
                if(entries[item.bullet]==undefined) throw "missing scan comparison XML";
                cases.push({mode:item.mode,bullet:item.bullet,rate:selected<2?30:20,
                    owners:2,muzzles:2,fireTicks:60,tailTicks:30,death:false});
            }
            return;
        }
        for(var m:Number=0;m<modes.length;m++) {
            var source:Object=entries[modes[m].bullet];
            check(source!=undefined,"production XML exists: "+modes[m].bullet);
            if(source==undefined) throw "missing production ray configuration";
            for(var r:Number=0;r<rates.length;r++) for(var group:Number=0;group<2;group++) {
                cases.push({mode:modes[m].mode,bullet:modes[m].bullet,rate:rates[r],owners:group==0?1:2,
                    muzzles:group==0?1:2,fireTicks:120,tailTicks:30,death:false});
            }
            // A short real-HP/kill topology switch companion, not a no-death-only oracle.
            cases.push({mode:modes[m].mode,bullet:modes[m].bullet,rate:30,owners:1,muzzles:1,
                fireTicks:60,tailTicks:30,death:true});
        }
    }
    private static function caps():Object {
        var names:Array=RayStyleRegistry.getStyleNames();var styles:Array=[];
        for(var i:Number=0;i<names.length;i++) styles.push({index:i,id:names[i]});
        return {version:1,generation:1,native:true,styles:styles,maxArcs:1024,drawLimit:4096,configLimit:1024,lightingVersion:1,channelVersion:1};
    }

    private static function startCase():Void {
        var spec:Object=cases[caseIndex];
        if(scanCompare) {
            bqp.rejectRayCandidateY=reuse?saved.rejectCandidateY:noYRejection;
            check(bqp.rejectRayCandidateY===(reuse?saved.rejectCandidateY:noYRejection),"exact scan helper installed");
        }
        RayVfxManager.reset();RayVisualBridge.resetScene();RayVisualBridge.disconnect();
        RayVfxManager.initWithContainer(world);RayVisualBridge.configure(caps());
        var children:Array=["targets","owners"];
        for(var i:Number=0;i<children.length;i++) world[children[i]].removeMovieClip();
        var targetHost:MovieClip=world.createEmptyMovieClip("targets",100);
        var ownerHost:MovieClip=world.createEmptyMovieClip("owners",101);
        var source:Object=entries[spec.bullet];
        current={spec:spec,key:spec.mode+"-"+spec.rate+"rps-"+spec.owners+"shooters-"+spec.muzzles+"muzzles"
                +(spec.death?"-deaths":"")+(scanCompare?(reuse?"-scan-y-filter":"-scan-original-check")
                    :(reuse?"-reuse":"-independent")),tick:0,shots:[],
            targets:[],owners:[],lanes:[],hits:[],retired:[],critRolls:[],ticks:[],processTicks:[],wireTicks:[],
            collisionCalls:0,cacheAcquires:0,settlements:0,events:0,kills:0,effectCalls:0,redCalls:0,
            displayCalls:0,legacyHooks:0,identityCount:0,sourceCount:0,sources:{},pinkCalls:0,uniformCalls:0,chanceCalls:0,mathCalls:0,critCalls:0,
            activeMax:0,visualMax:0,fallbackMax:0,wireBytes:0,wireMax:0,replays:[],
            config:TeslaRayConfig.fromXML(source.raw),budget:source.budget};
        current.replay=!scanCompare && !spec.death && spec.owners==1 && ((spec.mode=="single" && (spec.rate==10||spec.rate==30))
            || (spec.mode=="chain" && (spec.rate==10||spec.rate==30))
            || (spec.rate==30 && (spec.mode=="pierce"||spec.mode=="flame")));
        bqp._rayBullets=[];bqp._raySurvivors=[];bqp._flameVfxSerialCounter=0;
        uniform.restoreState(271828+caseIndex*997);
        pink.seed=314159+caseIndex*997;pink.reset();
        mathEngine=new SeededLinearCongruentialEngine(161803+caseIndex*997);
        makeTargets(targetHost,spec.death);
        makeOwners(ownerHost,spec.owners,spec.muzzles);
        current.cache=makeCache(current.targets);
        check(bqp._raySettleProbe==null,"no settlement short-circuit: "+current.key);
        trace("[RAY_RATE_CASE] "+json({key:current.key,bullet:spec.bullet,mode:current.config.rayMode,
            style:current.config.vfxStyle,ratePerMuzzle:spec.rate,owners:spec.owners,muzzlesPerOwner:spec.muzzles,
            targets:current.targets.length,pierceLimit:current.budget,fireTicks:spec.fireTicks,tailTicks:spec.tailTicks,
            width:current.config.thickness,rayLength:current.config.rayLength,replay:current.replay,channelVersion:1,channelReuse:scanCompare||reuse}));
    }
    private static function makeTargets(host:MovieClip,death:Boolean):Void {
        for(var row:Number=0;row<8;row++) for(var col:Number=0;col<12;col++) {
            var id:Number=row*12+col;
            var t:MovieClip=host.createEmptyMovieClip("T"+id,id);
            t.version=1000+id;
            t._x=130+col*65;t._y=100+row*45;t.Z轴坐标=0;t._rateId=id;
            t.hp=(death && col<3)?90:1000000;t.hp满血值=t.hp;t._rateStartHp=t.hp;
            t.等级=20;t.重量=60;t.躲闪率=20;t.懒闪避=0;
            t.防御力=40;t.魔法抗性={基础:12,热:18};t.无敌=false;t.NPC=false;t.防止无限飞=false;
            t.man={无敌标签:false};t.shield=new ShieldStack();
            t.aabbCollider=new AABBCollider(t._x-15,t._x+15,t._y-14,t._y+14);
            t.dispatcher={publish:function(topic,a,b,c,d,e):Void { RayRateTest.published(topic,a,b,c,d,e); }};
            current.targets.push(t);
        }
    }
    private static function makeOwners(host:MovieClip,count:Number,muzzleCount:Number):Void {
        var ys:Array=[145,235,325,415];
        for(var s:Number=0;s<count;s++) {
            var owner:MovieClip=host.createEmptyMovieClip("S"+s,s);owner.version=100+s;
            // BQP resolves the stable shooter name directly under gameworld.
            world["S"+s]=owner;
            owner.hp=1000000;owner.hp满血值=1000000;owner.等级=20;owner.命中率=80;
            owner.伤害加成=0;owner._xscale=100;owner.Z轴坐标=0;
            owner.dispatcher={publish:function(topic,a,b,c,d,e):Void { RayRateTest.published(topic,a,b,c,d,e); }};
            current.owners.push(owner);
            for(var m:Number=0;m<muzzleCount;m++) {
                var index:Number=s*muzzleCount+m;
                var muzzle:MovieClip=owner.createEmptyMovieClip("muzzle"+m,m);
                muzzle._x=60;muzzle._y=ys[index];
                var slot:String=m==0?"长枪":"手枪";
                var weapon:Object={name:"rate-fixture-"+s+"-"+m};owner[slot]=weapon;
                current.lanes.push({owner:owner,muzzle:muzzle,weapon:weapon,slot:slot,name:"S"+s});
            }
        }
    }
    private static function makeCache(targets:Array):Object {
        var ordered:Array=targets.slice(0);
        ordered.sort(function(a,b):Number { return a.aabbCollider.left-b.aabbCollider.left; });
        var left:Array=[],right:Array=[];var high:Number=-1000000;
        for(var i:Number=0;i<ordered.length;i++) {
            left[i]=ordered[i].aabbCollider.left;high=Math.max(high,ordered[i].aabbCollider.right);right[i]=high;
        }
        return {data:ordered,leftValues:left,rightMaxValues:right};
    }

    private static function spawn(lane:Object):Void {
        var cfg:TeslaRayConfig=current.config;
        var props:Object={rayConfig:cfg,flags:264,子弹种类:current.spec.bullet,发射者名:lane.name,霰弹值:1};
        // Independent events remain a valid current-protocol input. Compare them
        // without pretending that the paired Host lacks channelVersion support.
        if (scanCompare || reuse) bridge.captureShot(lane.owner,lane.slot,lane.muzzle,props,lane.weapon);
        var b:Object={};for(var key:String in props) b[key]=props[key];
        b._rateId=current.shots.length+1;b._rateBorn=current.tick;b._rateRetired=false;
        b._x=lane.muzzle._x;b._y=lane.muzzle._y;b._rotation=0;b.stateFlags=4;
        b.Z轴坐标=0;b.Z轴攻击范围=50;b.pierceLimit=current.budget;
        b.伤害类型="普通";b.魔法伤害属性="热";b.命中率=80;b.子弹威力=35;b.子弹速度=35;
        b.固伤=0;b.百分比伤害=0;b.霰弹值=1;b.nanoToxic=0;b.吸血=0;b.击溃=0;b.斩杀=0;
        b.additionalEffectDamage=0;b.hitCount=0;b.附加层伤害计算=0;b.是否为敌人=false;
        b.击中地图效果="";b.击中后子弹的效果="";b.暴击=critical;
        b.击中时触发函数=function():Void { RayRateTest.current.legacyHooks++; };
        b.damageManager=damageFactory.getDamageManager(b);
        var collider:Object;
        if(cfg.rayWidthFactor>0) {
            var band:BandRayCollider=new BandRayCollider(new Vector(b._x,b._y),new Vector(1,0),cfg.rayLength);
            band.setHalfWidth(b.Z轴攻击范围*cfg.rayWidthFactor*0.5);collider=band;
        } else collider=rayFactory.createCustomRay(new Vector(b._x,b._y),new Vector(1,0),cfg.rayLength);
        if(collider._rateOriginalCheck==undefined) {
            collider._rateOriginalCheck=collider.checkCollision;
            collider.checkCollision=function(other,z) {
                RayRateTest.current.collisionCalls++;
                return this._rateOriginalCheck(other,z);
            };
        }
        b.aabbCollider=collider;
        var lifecycle:Object=TeslaRayLifecycle.BASIC;
        lifecycle.bindSafeRemove(b);
        b._rateOriginalRemove=b.removeMovieClip;
        b.removeMovieClip=function():Void {
            RayRateTest.retire(this);this._rateOriginalRemove();
        };
        current.shots.push(b);
        lifecycle.bindFrameHandler(b);
        if(b._rayVisualIdentity!=null) {
            current.identityCount++;
            var sourceKey:String="s"+b._rayVisualIdentity.source;
            if(current.sources[sourceKey]!==true) {current.sources[sourceKey]=true;current.sourceCount++;}
        }
    }
    private static function settle(b:Object,s:Object,t:Object,m:Number,d:String):Object {
        var before:Number=t.hp;var f:Function=saved.damage;
        var result:Object=f.call(damageApi,b,s,t,m,d);
        current.settlements++;
        current.hits.push([current.tick,b._rateId,t._rateId,m,d,before-t.hp,result.dodgeStatus,result.actualScatterUsed]);
        return result;
    }
    private static function published(topic:String,a:Object,b:Object,c:Object,d:Object,e:Object):Void {
        current.events++;
        if(topic=="kill"||topic=="death") {current.kills++;a._killed=true;}
    }
    private static function retire(b:Object):Void {
        if(b._rateRetired) {check(false,"duplicate logical bullet retirement");return;}
        b._rateRetired=true;
        current.retired.push([current.tick,b._rateId,b.hitCount,b._rayBudget,b._flameTotalHitsDone,b._flameAge]);
    }

    private static function noYRejection(ray:Object,target:Object,zOffset:Number,halfWidth:Number):Boolean {
        return false;
    }
    private static function pump():Void {
        if(completed) return;
        var began:Number=getTimer();var steps:Number=0;
        try {
            while(steps<(scanCompare?32:8) && getTimer()-began<(scanCompare?100:20)) {
                if(current.tick<current.spec.fireTicks+current.spec.tailTicks) tick();
                else {finishCase();break;}
                steps++;
            }
        } catch(error) {abort("case "+current.key+" tick "+current.tick+": "+error);}
    }
    private static function tick():Void {
        var tickNo:Number=current.tick;
        _root.帧计时器.当前帧数=tickNo;
        var start:Number=getTimer();
        if(tickNo<current.spec.fireTicks) {
            var rate:Number=current.spec.rate;
            // Deterministic 30-Hz schedule also represents non-divisors (20/s).
            if(Math.floor((tickNo+1)*rate/30)>Math.floor(tickNo*rate/30))
                for(var lane:Number=0;lane<current.lanes.length;lane++) spawn(current.lanes[lane]);
        }
        var processing:Number=getTimer();
        bqp.processRayBullets();
        var processed:Number=getTimer();
        RayVfxManager.update();
        var wireStart:Number=getTimer();var payload:String=RayVisualBridge.flush();var ended:Number=getTimer();
        if(tickNo>=15 && tickNo<current.spec.fireTicks) {
            current.ticks.push(ended-start);current.processTicks.push(processed-processing);current.wireTicks.push(ended-wireStart);
        }
        current.activeMax=Math.max(current.activeMax,bqp._rayBullets.length);
        var stats:Object=RayVisualBridge.getStats();
        current.visualMax=Math.max(current.visualMax,stats.active);
        current.fallbackMax=Math.max(current.fallbackMax,RayVfxManager.getActiveCount()+RayVfxManager.getDelayedCount());
        var bytes:Number=payload==null?0:payload.length;
        current.wireBytes+=bytes;current.wireMax=Math.max(current.wireMax,bytes);
        if(current.replay) current.replays.push(payload);
        current.tick++;
    }
    private static function distribution(samples:Array):Object {
        var data:Array=samples.slice(0);data.sort(Array.NUMERIC);var total:Number=0;
        for(var i:Number=0;i<data.length;i++) total+=data[i];
        return {samples:data.length,p50Ms:data[Math.floor((data.length-1)*0.5)],
            p95Ms:data[Math.floor((data.length-1)*0.95)],maxMs:data[data.length-1],sumMs:total,meanMs:total/data.length};
    }
    private static function signature():Object {
        var hp:Array=[];for(var i:Number=0;i<current.targets.length;i++) hp.push(current.targets[i].hp);
        return {hits:current.hits,retired:current.retired,hp:hp,crit:current.critRolls,
            mathCalls:current.mathCalls,pinkCalls:current.pinkCalls,uniformCalls:current.uniformCalls,
            chanceCalls:current.chanceCalls,uniformState:uniform.captureState(),pinkState:savePink(),
            collisionCalls:current.collisionCalls,cacheAcquires:current.cacheAcquires,events:current.events,kills:current.kills,legacyHooks:current.legacyHooks};
    }
    private static function sameArray(a:Array,b:Array):Boolean {
        if(a.length!=b.length) return false;
        for(var i:Number=0;i<a.length;i++) {
            if(a[i] instanceof Array) {if(!sameArray(a[i],b[i])) return false;}
            else if(a[i]!==b[i]) return false;
        }
        return true;
    }
    // Fixed-order normalized record summary. This is not a hash of SWF bytes,
    // live object memory or wire, and the two rolling lanes are not cryptographic.
    private static function gameplaySummary(truth:Object):Object {
        var state:Object=truth.pinkState;
        var normalized:Array=[truth.hits,truth.retired,truth.hp,truth.crit,
            [truth.mathCalls,truth.pinkCalls,truth.uniformCalls,truth.chanceCalls],truth.uniformState,
            [state.seed,state.counter,state.s0,state.s1,state.s2,state.s3,state.s4],
            [truth.cacheAcquires,truth.events,truth.kills,truth.legacyHooks]];
        var text:String=json(normalized);var hashA:Number=5381;var hashB:Number=2166136261;
        for(var i:Number=0;i<length(text);i++) {
            var code:Number=text.charCodeAt(i);
            hashA=(hashA*33+code)%4294967296;
            hashB=(hashB*65599+code)%4294967296;
        }
        return {format:"recorded-gameplay-json-array-v1",algorithm:"two-rolling-u32-noncryptographic",
            hash:String(hashA)+":"+String(hashB),codeUnits:length(text),
            hitRows:truth.hits.length,retireRows:truth.retired.length,targetHpCount:truth.hp.length,
            criticalRollCount:truth.crit.length,excluded:"collisionCalls,timings,visuals,wire"};
    }
    private static function compare(a:Object,b:Object,summary:Object):Object {
        var hitEqual:Boolean=sameArray(a.hits,b.hits);
        var retirementEqual:Boolean=sameArray(a.retired,b.retired);
        var hpEqual:Boolean=sameArray(a.hp,b.hp);
        var critEqual:Boolean=sameArray(a.crit,b.crit);
        var randomCountEqual:Boolean=a.mathCalls==b.mathCalls && a.pinkCalls==b.pinkCalls
            && a.uniformCalls==b.uniformCalls && a.chanceCalls==b.chanceCalls;
        var randomStateEqual:Boolean=a.uniformState==b.uniformState && json(a.pinkState)==json(b.pinkState);
        var cacheEqual:Boolean=a.cacheAcquires==b.cacheAcquires;
        var collisionAllowed:Boolean=scanCompare?b.collisionCalls<=a.collisionCalls:b.collisionCalls==a.collisionCalls;
        var eventEqual:Boolean=a.events==b.events && a.kills==b.kills && a.legacyHooks==b.legacyHooks;
        check(hitEqual,"same per-shot hit order, multiplier, dodge, HP loss: "+current.key);
        check(retirementEqual,"same budgets and logical retirement: "+current.key);
        check(hpEqual,"same final target HP: "+current.key);
        check(critEqual,"same critical rolls: "+current.key);
        check(randomCountEqual,"same gameplay RNG consumption: "+current.key);
        check(randomStateEqual,"same final production RNG states: "+current.key);
        check(cacheEqual && collisionAllowed,"same cache work and allowed collision count: "+current.key);
        check(eventEqual,"same event and kill counts: "+current.key);
        var hashEqual:Boolean=baselineSummary.hash==summary.hash && baselineSummary.codeUnits==summary.codeUnits;
        check(hashEqual,"same full normalized gameplay summary: "+current.key);
        var groups:Array=[hitEqual,retirementEqual,hpEqual,critEqual,randomCountEqual,randomStateEqual,cacheEqual,eventEqual,hashEqual];
        var matched:Number=0;for(var j:Number=0;j<groups.length;j++) if(groups[j]) matched++;
        return {kind:scanCompare?"scan-prefilter":"visual-channel",key:current.key,
            gameplayEquivalent:matched==groups.length,groupsCompared:groups.length,groupsEqual:matched,
            hitRowsCompared:a.hits.length,retireRowsCompared:a.retired.length,targetHpCompared:a.hp.length,
            criticalRollsCompared:a.crit.length,cacheAcquiresEqual:cacheEqual,
            collisionBefore:a.collisionCalls,collisionAfter:b.collisionCalls,
            collisionReducedBy:a.collisionCalls-b.collisionCalls,collisionCountAllowed:collisionAllowed,
            summaryBefore:baselineSummary,summaryAfter:summary,
            boundary:"recorded values and RNG state equality; not binary or full-game equivalence"};
    }
    private static function finishCase():Void {
        check(current.shots.length==current.spec.rate*current.spec.fireTicks/30*current.lanes.length,"exact authored fire schedule: "+current.key);
        check(current.retired.length==current.shots.length && bqp._rayBullets.length==0,"all logical shots retire naturally: "+current.key);
        check(current.settlements>0 && current.pinkCalls>0 && current.critCalls>0,"real damage, variance and crit ran: "+current.key);
        check(current.collisionCalls>0,"real collider checks ran: "+current.key);
        var healthChanged:Boolean=false;
        for(var i:Number=0;i<current.targets.length;i++) {
            var t:Object=current.targets[i];
            if(t.hp<t._rateStartHp) healthChanged=true;
            check(finite(t.hp),"finite target HP "+i+" "+current.key);
        }
        check(healthChanged,"production DamageCalculator changed HP: "+current.key);
        if(reuse||scanCompare) {
            check(current.identityCount==current.shots.length,"real source identity captured for every shot: "+current.key);
            check(current.sourceCount==current.lanes.length,"independent shooter/muzzle source identities: "+current.key);
        }
        var stats:Object=RayVisualBridge.getStats();
        var truth:Object=signature();
        var summary:Object=gameplaySummary(truth);
        var comparison:Object=null;
        if(reuse) {
            comparison=compare(baseline,truth,summary);
            trace("[RAY_RATE_PAIR] "+json(comparison));
        } else {baseline=truth;baselineSummary=summary;}
        trace("[RAY_RATE_RESULT] "+json({key:current.key,ratePerMuzzle:current.spec.rate,
            comparisonKind:scanCompare?"scan-prefilter":"visual-channel",gameplaySummary:summary,comparison:comparison,
            shots:current.shots.length,settlements:current.settlements,retired:current.retired.length,
            activeMax:current.activeMax,visualMax:current.visualMax,flashFallbackMax:current.fallbackMax,
            collisionChecks:current.collisionCalls,cacheAcquires:current.cacheAcquires,events:current.events,kills:current.kills,
            mathCalls:current.mathCalls,pinkCalls:current.pinkCalls,uniformCalls:current.uniformCalls,chanceCalls:current.chanceCalls,
            critCalls:current.critCalls,identityCount:current.identityCount,sourceCount:current.sourceCount,
            channelUpdates:stats.channelUpdates,channelCoalesced:stats.channelCoalesced,wireBytes:current.wireBytes,maxWireBytesPerTick:current.wireMax,
            totalFunction:distribution(current.ticks),selectionAndSettlement:distribution(current.processTicks),
            wire:distribution(current.wireTicks),damagePipeline:"production",cacheProvider:"fixture-snapshot",
            candidateVisitCount:"not-instrumented",collisionCount:"real-checkCollision-calls-only",scope:"instrumented-AS2-not-frame-FPS"}));
        if(current.replay) {
            trace("[RAY_RATE_SCENE] "+current.key);
            for(var frame:Number=0;frame<current.replays.length;frame++) trace("[RAY_RATE_WIRE] "+current.replays[frame]);
        }
        if(reuse) {caseIndex++;reuse=false;baseline=null;baselineSummary=null;}else reuse=true;
        if(caseIndex<cases.length) startCase();else finish();
    }

    private static function abort(reason:String):Void {
        check(false,reason);finish();
    }
    private static function finish():Void {
        if(completed) return;completed=true;
        delete pumpClip.onEnterFrame;
        try {
            if(scanCompare) bqp.rejectRayCandidateY=saved.rejectCandidateY;
            RayVisualBridge.resetScene();RayVisualBridge.disconnect();RayVfxManager.reset();
            bqp._rayBullets=saved.rays;bqp._raySurvivors=saved.survivors;
            bqp._rayPersistent=saved.persist;bqp._raySettleProbe=saved.probe;bqp._flameVfxSerialCounter=saved.flameSerial;
            cacheApi.acquireAllCache=saved.all;cacheApi.acquireEnemyCache=saved.enemy;
            damageApi.calculateDamage=saved.damage;effects.Effect=saved.effect;
            var resultClass:Object=DamageResult;resultClass.prototype.triggerDisplay=saved.display;
            var initializer:Object=BulletInitializer;initializer.attributeMap=saved.attributeMap;
            pink.randomFluctuation=saved.pinkDraw;restorePink(saved.pinkState);
            uniform.nextFloat=saved.uniformNext;uniform.successRate=saved.uniformRate;uniform.restoreState(saved.uniformState);
            Math.random=saved.math;if(saved.mathReadOnly) _global.ASSetPropFlags(Math,"random",4,0);
            _root.gameworld=saved.world;_root.暂停=saved.paused;_root.调试模式=saved.debug;_root.帧计时器=saved.clock;
            _root.受击变红=saved.red;SceneCoordinateManager.effectOffset.setTo(saved.offsetX,saved.offsetY);
            world.removeMovieClip();
        } catch(error) {check(false,"fixture cleanup: "+error);}
        trace("[RAY_RATE_DONE] pairs="+caseIndex+" elapsedMs="+(getTimer()-suiteStarted));
        trace("RayRate Tests Passed: "+passed);
        trace("RayRate Tests Failed: "+failed);
        trace(completeLine);
        pumpClip.removeMovieClip();
    }
}
