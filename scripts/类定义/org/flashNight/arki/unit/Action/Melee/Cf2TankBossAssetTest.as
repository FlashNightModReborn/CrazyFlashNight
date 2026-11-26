import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/** Published author timelines; no saves, rewards, sockets or production actors. */
class org.flashNight.arki.unit.Action.Melee.Cf2TankBossAssetTest {
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number,loadTicks:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,images:Object,settled:Object,pauseFrames:Array,audioCalls:Object,fragmentPause:Object;
    private static var damageTarget:MovieClip,damageCache:Object;
    private static var link:String="敌人-闪2大机器人";

    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf2TankBossAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,gun:0,cannon:0,laser:0,grenade:0,melee:0,deathBurst:0,moves:0,done:0,deathChecks:0,
            removed:false,loops:0,lastPulse:-1,duplicateChecked:false,frames:[],pauseShots:0,cutoffShots:0,launchers:{},pulses:{},realHits:0,realHitPulses:0,realPulseHits:{}};
    }
    public static function runAllTests():Void {
        try {
            startSuite();
        } catch(error) {
            trace("[CF2_SUITE_EXCEPTION] "+error);
            check(false,"suite initialization exception");
            finish();
        }
    }
    private static function startSuite():Void {
        trace("[CF2_SUITE_ENTER]");
        passed=failed=ticks=loadTicks=0;ready=finished=false;cases=[];images={};settled={};audioCalls={};
        trace("[CF2_SUITE_FACTORY] "+typeof DamageManagerFactory.Basic);
        if(DamageManagerFactory.Basic==null)DamageManagerFactory.init();
        ColliderFactoryRegistry.init();BulletQueueProcessor.initialize();
        if(DamageManagerFactory.Basic==null)throw "Production damage factory did not initialize";
        trace("[CF2_SUITE_DAMAGE_READY]");
        if(PinkNoiseEngine.getInstance()==null)throw "Production noise source did not initialize";
        trace("[CF2_SUITE_RANDOM_READY]");
        trace("[CF2_SUITE_ROOT] "+_root._url);
        library=_root.createEmptyMovieClip("__cf2TankLibrary",900000);
        driver=_root.createEmptyMovieClip("__cf2TankDriver",900001);
        trace("[CF2_SUITE_CLIPS] library="+library+" driver="+driver);
        if(library==null || driver==null){check(false,"isolated host clips");finish();return;}
        driver.onEnterFrame=function():Void {Cf2TankBossAssetTest.tick();};
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        trace("[CF2_SUITE_WORLD_READY]");
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function(name:String):Void {Cf2TankBossAssetTest.noteAudio(name);};_root.发布消息=function():Void {};
        _root.效果=function():Void {};_root.add2map=function():Void {};_root.add2map2=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        damageTarget=null;damageCache=null;
        _root.对象浅拷贝=function(source:Object):Object {var out:Object={};for(var key:String in source)out[key]=source[key];return out;};
        TargetCacheManager.acquireEnemyCache=function():Object{return Cf2TankBossAssetTest.damageCache;};
        _root.子弹区域shoot传递=function(data:Object):Void {Cf2TankBossAssetTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=100000;this.mp=0;this.空手攻击力=100;this.等级=37;
            this.状态="初始化";this.攻击模式="空手";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=400;this._x=400;this.myxscale=100;this.是否为敌人=true;
            this.倒地=this.浮空=this.硬直中=this.刚体=this.免疫击退=this.锁定方向=false;
            this.防御力=1;this.damageTakenMultiplier=this.ti61CrumbleTakenMultiplier=1;
            this.魔法抗性={波:0};this.韧性系数=40;this.remainingImpactForce=0;
            this.行走X速度=4;this.行走Y速度=3;
            this.dispatcher={publish:function():Void {}};
            this.shield=AdaptiveShield.createDormant("tank-fixture");this.shield.setOwner(this);
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};
            this.方向改变=_root.敌人函数.方向改变;
            this.状态改变=_root.敌人函数.状态改变;
            this.移动=function(dir:String,speed:Number):Void {
                if(this.fixtureBlocked===true)return;
                if(dir=="左")this._x-=speed;else if(dir=="右")this._x+=speed;
                else if(dir=="上")this._y=this.Z轴坐标-=speed;else this._y=this.Z轴坐标+=speed;
                this.fixtureRecord.moves++;
            };
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.攻击目标="无";this.倒地=false;
                this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.死亡检测=function():Void {
                this.fixtureRecord.deathChecks++;
                if(this.hp<=0){this.fixtureRecord.removed=true;this.removeMovieClip();}
            };
            this.stop();
        };
        trace("[CF2_SUITE_INITIALIZERS_READY]");
        listener={onLoadInit:function(mc:MovieClip):Void {Cf2TankBossAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {
                Cf2TankBossAssetTest.check(false,"load "+error);Cf2TankBossAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        var accepted:Boolean=loader.loadClip("../flashswf/arts/new/Codex大机器人素材.swf",library);
        trace("[CF2_SUITE_LOAD] "+accepted);check(accepted,"load published private library");
        if(!accepted)finish();
    }
    private static function addCase(action:String,mode:String,side:Number):Void {
        var rec:Object=record();
        var actor:MovieClip=library.attachMovie(link,"tankCase"+cases.length,100+cases.length,{fixtureRecord:rec});
        check(actor!=null,"attach "+action+" "+mode+" "+side);
        cases.push({actor:actor,record:rec,action:action,mode:mode,side:side,started:false,
            oldToken:null,oldBodyIdentity:null,pauseFrame:0,pausePulse:0,initialX:0});
    }
    private static function loaded(mc:MovieClip):Void {
        trace("[CF2_SUITE_LIBRARY_LOADED]");
        mc.stop();
        var moves:Array=["melee","gatling","laser","barrage","mobile"];
        for(var side:Number=0;side<2;side++){
            for(var i:Number=0;i<moves.length;i++)addCase(moves[i],"normal",side);
            addCase("mobile","blocked",side);
            addCase("gatling","cancel",side);
            addCase("barrage","fatal",side);
            addCase("melee","death",side);
        }
        addCase("gatling","preowned",0);
        addCase("barrage","fatal-active",0);
        addCase("barrage","fatal-active",1);
        ready=true;ticks=0;
    }
    private static function capture(data:Object):Void {
        var actor:MovieClip=library[data.发射者],rec:Object=actor.fixtureRecord;
        if(rec==null)return;
        var owner:Object=actor.tankOwner,kind:String=data.cf2TankKind;
        rec.shots++;
        var pulseKey:String=kind+"_"+owner.pulse;
        if(rec.pulses[pulseKey]!==true){rec.pulses[pulseKey]=true;rec[kind]++;}
        rec.frames.push(actor.man._currentframe);
        check(data.产生源==actor._name,"projectile/auxiliary actor carries its exact owning unit");
        check(data.cf6DeathBurst===undefined && data.百分比伤害===undefined && data.友军伤害!==true,"no inherited special damage");
        var bounds:Object=data.区域定位area.getBounds(library);
        check(bounds.xMax>bounds.xMin && bounds.yMax>bounds.yMin,"nonempty native collision geometry");
        if(kind=="deathBurst"){
            check(actor.hp<=0 && actor.tankOwner==null && actor.tankDeathSpent===true,"death burst runs only once after lethal settle");
            check(data.子弹种类=="近战子弹" && data.伤害类型=="物理"
                && Math.abs(data.子弹威力-200)<0.01 && data.Z轴攻击范围==80
                && data.区域定位area!=null && data.shootZ==actor.Z轴坐标,"death burst contract");
            if(settled[kind]!==true){settled[kind]=true;settlement(data,actor);}
            return;
        }
        rec.loops=Math.max(rec.loops,owner.loops);
        check(owner.token===data.cf2TankToken && owner.pulse==data.cf2TankPulse,"emission belongs to current action");
        check(actor.刚体===true && actor.免疫击退===true && actor.锁定方向===true,"every emission protected and facing locked");
        check(data.区域定位area!=null && data.Z轴攻击范围==40 && data.shootZ==actor.Z轴坐标,"real area and lane declaration");
        if(!rec.duplicateChecked){
            rec.duplicateChecked=true;
            var before:Number=rec.shots;actor.tankStrike(actor.man);
            check(rec.shots==before,"synchronous damage callback cannot replay a pulse");
        }
        if(kind=="laser"){
            check(data.子弹种类=="近战子弹" && data.子弹速度==0 && data.伤害类型=="魔法"
                && data.魔法伤害属性=="波" && Math.abs(data.子弹威力-65)<0.01,"beam declaration");
            var span:Number=Math.max(bounds.xMax-bounds.xMin,bounds.yMax-bounds.yMin);
            check(span>100 && span<220,"compact localized beam sweep box");
        }else if(kind=="melee"){
            check(Math.abs(data.子弹威力-180)<0.01 && data.子弹速度==0 && data.伤害类型=="物理","three physical heavy strikes");
        }else if(kind=="grenade"){
            var slot:Number=data.cf2TankLauncher;
            check(data.子弹种类=="榴弹" && slot>=0 && slot<10 && slot==Math.floor(slot)
                && Math.abs(data.子弹威力-70)<0.01 && Math.abs(data.速度X)==data.子弹速度
                && (actor.方向=="右"?data.速度X>0:data.速度X<0)
                && data.速度Y<-3.5 && data.ZY比例===undefined,"ten explicit parabolic forward launchers");
            rec.launchers[owner.loops+"_"+slot]=true;
        }else{
            var isCannon:Boolean=kind=="cannon";
            var maxAim:Number=isCannon?10:22;
            check(data.子弹种类==(isCannon?"巴雷特子弹":"加强普通子弹")
                && data.子弹速度==(isCannon?72:34)
                && (!isCannon || (data.发射效果=="巴雷特枪火" && data.击中后子弹的效果=="战术巴雷特击中特效" && data.击中地图效果=="弹坑"))
                && !isNaN(data.fixedRotation) && Math.abs(data.cf2TankAimOffset)<=maxAim
                && Math.abs(data.子弹威力-(isCannon?260:55))<0.01,"projectile contract with bounded aim");
            var rad:Number=data.fixedRotation*Math.PI/180;
            if(isCannon){
                check(actor.方向=="右"?Math.cos(rad)>0.9:Math.cos(rad)<-0.9,"cannon fires strictly forward");
            }else if(owner.action=="gatling" || owner.action=="mobile"){
                check(actor.方向=="右"?Math.cos(rad)<-0.8:Math.cos(rad)>0.8,"gatling fires toward rear hemisphere");
            }
            var anglePacket:Object={fixedRotation:data.fixedRotation,子弹速度:data.子弹速度,角度偏移:data.角度偏移};
            check(Math.abs(ShootingAngleCalculator.calculate(anglePacket,actor)-data.fixedRotation)<0.001,
                "production angle calculator preserves visible weapon direction");
        }
        if(settled[kind]!==true){settled[kind]=true;settlement(data,actor);}
        if(kind=="melee" || kind=="laser")productionSettlement(data,actor,rec);
        if(actor._name=="tankCase0" && !images["melee-right"])render(actor,"melee-right");
        if(actor._name=="tankCase1" && !images["gatling-right"])render(actor,"gatling-right");
        if(actor._name=="tankCase2" && !images["laser-right"])render(actor,"laser-right");
        if(actor._name=="tankCase3" && !images["barrage-right"])render(actor,"barrage-right");
        if(actor._name=="tankCase4" && !images["mobile-right"])render(actor,"mobile-right");
        if(actor._name=="tankCase11" && !images["laser-left"])render(actor,"laser-left");
        if(rec.shots<3)trace("[CF2_TANK_PORT] actor="+actor._name+" kind="+kind
            +" frame="+actor.man._currentframe+" point="+data.shootX+","+data.shootY
            +" area="+bounds.xMin+","+bounds.yMin+","+bounds.xMax+","+bounds.yMax);
    }
    private static function productionSettlement(source:Object,actor:MovieClip,rec:Object):Void {
        if(damageTarget==null){
            damageTarget=_root.cf6MakePlayerTarget(library,"tankContinuousDamageTarget",175);
            damageTarget.createEmptyMovieClip("man",2);
        }
        damageTarget._x=source.shootX;damageTarget._y=actor.Z轴坐标;
        var box:Object=source.区域定位area.getRect(library);
        var targetArea:Object=damageTarget.area.getRect(library);
        damageTarget._x+=(box.xMin+box.xMax-targetArea.xMin-targetArea.xMax)/2;
        damageTarget._y+=(box.yMin+box.yMax-targetArea.yMin-targetArea.yMax)/2;
        damageTarget.Z轴坐标=actor.Z轴坐标;
        damageTarget.hp=damageTarget.hp满血值=10000000;
        var targetBox:AABBCollider=new AABBCollider(0,0,0,0);targetBox.updateFromUnitArea(damageTarget);
        damageTarget.aabbCollider=targetBox;
        damageCache={data:[damageTarget],leftValues:[targetBox.left],rightValues:[targetBox.right],rightMaxValues:[targetBox.right]};
        var packet:Object={};for(var key:String in source)packet[key]=source[key];
        packet.命中率=100000;
        BulletFactory.prepareBulletData(packet,actor);
        var bullet:Object=BulletFactory.createBullet(packet,actor,0);
        check(bullet!=null,"real factory accepts continuous "+source.cf2TankKind);
        check(bullet.aabbCollider.checkCollision(targetBox,bullet.Z轴坐标-damageTarget.Z轴坐标).isColliding===true,
            "continuous contact overlaps its target "+source.cf2TankKind);
        BulletQueueProcessor.processQueue();
        if(damageTarget.hp<damageTarget.hp满血值){
            rec.realHits++;
            var hitPulse:String=source.cf2TankKind+"_"+source.cf2TankPulse;
            if(rec.realPulseHits[hitPulse]!==true){rec.realPulseHits[hitPulse]=true;rec.realHitPulses++;}
        }
    }
    private static function noteAudio(name:String):Void {
        audioCalls[name]=audioCalls[name]==undefined?1:audioCalls[name]+1;
    }
    private static function bulletCopy(source:Object):Object {
        var data:Object={};
        for(var key:String in source)data[key]=source[key];
        data.固伤=0;data.flags=256;data.hitCount=0;data.伤害加成=0;
        data.damageManager=DamageManagerFactory.resolveForBullet(data);
        return data;
    }
    private static function settlement(source:Object,actor:MovieClip):Void {
        var target:MovieClip=_root.cf6MakePlayerTarget(library,"tankDamageTarget"+source.cf2TankKind,175);
        target._x=source.shootX;target._y=target.Z轴坐标=actor.Z轴坐标;
        target.createEmptyMovieClip("man",2);
        var sourceBox:AABBCollider=new AABBCollider(0,0,0,0);
        var targetBox:AABBCollider=new AABBCollider(0,0,0,0);
        // Production creates a distinct collision-cache owner per projectile.
        // Reusing actor.man would alias gun/cannon's identical local area keys.
        var packet:MovieClip=library.createEmptyMovieClip("tankCollisionPacket"+source.cf2TankKind,library.getNextHighestDepth());
        sourceBox.updateFromBullet(packet,source.区域定位area);
        var box:Object=source.区域定位area.getRect(library);
        var targetArea:Object=target.area.getRect(library);
        target._x+=(box.xMin+box.xMax-targetArea.xMin-targetArea.xMax)/2;
        target._y+=(box.yMin+box.yMax-targetArea.yMin-targetArea.yMax)/2;
        targetBox.updateFromUnitArea(target);
        check(sourceBox.checkCollision(targetBox,0).isColliding===true,
            "native area overlaps the isolated settlement target "+source.cf2TankKind);
        target._x+=10000;targetBox.updateFromUnitArea(target);
        check(sourceBox.checkCollision(targetBox,0).isColliding===false,
            "production collider rejects outside target "+source.cf2TankKind);
        target._x-=10000;targetBox.updateFromUnitArea(target);
        var collision:Object=sourceBox.checkCollision(targetBox,0);
        var original:Number=target.hp;
        var queue:Object=BulletQueueProcessor,impact:Object=DamageResult.getIMPACT();
        var display:Function=impact.triggerDisplay;impact.triggerDisplay=function():Void {};
        var miss:Object=bulletCopy(source);
        queue.settleHit({bullet:miss,shooter:actor,Damage:DamageCalculator,flags:256,meleeMask:768},
            target,collision,1,"躲闪",true);
        check(target.hp==original,"production MISS preserves target HP "+source.cf2TankKind);
        var hit:Object=bulletCopy(source);
        queue.settleHit({bullet:hit,shooter:actor,Damage:DamageCalculator,flags:256,meleeMask:768},
            target,collision,1,"未躲闪",true);
        check(target.hp<original && target.hp>0,"production settlement applies actual damage "+source.cf2TankKind);
        impact.triggerDisplay=display;target.removeMovieClip();packet.removeMovieClip();
    }
    private static function guardChecks(actor:MovieClip):Void {
        var owner:Object=actor.tankOwner,body:MovieClip=actor.man;
        check(owner!=null,"guard test has a live action");
        if(owner==null)return;
        var direction:String=actor.方向;
        actor.方向改变(direction=="左"?"右":"左");
        check(actor.方向==direction,"attacker cannot flip an attacking tank");
        actor.状态改变("被击");
        check(actor.状态==owner.state,"ordinary hurt state cannot interrupt rigid action");
        var attacker:MovieClip=_root.cf6MakePlayerTarget(library,"tankIncoming"+actor._name,175);
        var beforeHp:Number=actor.hp;
        var incoming:Object=bulletCopy({子弹威力:200,伤害类型:"物理",霰弹值:1,击倒率:3,
            水平击退速度:25,垂直击退速度:10});
        var queue:Object=BulletQueueProcessor,impact:Object=DamageResult.getIMPACT();
        var display:Function=impact.triggerDisplay;impact.triggerDisplay=function():Void {};
        queue.settleHit({bullet:incoming,shooter:attacker,Damage:DamageCalculator,flags:256,meleeMask:768},
            actor,{overlapCenter:{x:actor._x,y:actor._y}},1,"未躲闪",true);
        check(actor.hp<beforeHp && actor.hp>0,"rigid attack still takes production damage");
        check(actor.tankOwner===owner && actor.状态==owner.state && actor.方向==direction,
            "damage does not replace the protected action or facing");
        impact.triggerDisplay=display;attacker.removeMovieClip();
        var before:Number=body._currentframe;
        actor.tankBodyTick(body,{});
        check(body._currentframe==before,"stale body token cannot advance an action");
        var worldIdentity:Object=library.__cf2TankWorldIdentity;
        library.__cf2TankWorldIdentity={};
        var shots:Number=actor.fixtureRecord.shots;
        actor.tankStrike(body);actor.tankBodyTick(body,body.tankFrameIdentity);
        check(actor.fixtureRecord.shots==shots && body._currentframe==before,"old world cannot emit or advance");
        library.__cf2TankWorldIdentity=worldIdentity;
        var unitIdentity:Object=actor.tankIdentity,clock:Number=actor.tankClock;
        actor.tankTick({});
        check(actor.tankClock==clock,"old unit driver cannot tick a replacement");
        check(actor.tankIdentity===unitIdentity,"identity remains private");
    }
    private static function choices(actor:MovieClip):Void {
        actor.tankClock=100;actor.tankReadyAt=0;actor.tankNext={};actor.tankAttackSequence=0;
        check(actor.tankChoose(100,0)=="melee","close melee selection");
        check(actor.tankChoose(500,0)=="barrage","stationary all-weapons selection");
        actor.tankAttackSequence=1;
        check(actor.tankChoose(500,0)=="mobile","mobile all-weapons selection");
        actor.tankNext.mobile=actor.tankNext.barrage=200;
        check(actor.tankChoose(500,0)=="laser","beam fallback");
        actor.tankNext.laser=200;
        check(actor.tankChoose(600,0)=="","front target does not trigger rear gatling");
        check(actor.tankChoose(-150,0)=="melee","rear close melee selection without flipping");
        check(actor.tankChoose(-400,0)=="gatling","rear gatling selection without flipping");
        check(actor.tankChoose(-700,0)=="","rear out-of-range rejection");
        check(actor.tankChoose(500,41)=="","off-lane rejection");
        check(actor.tankChoose(Number("bad"),0)=="","nonfinite coordinate rejection");
        actor.tankReadyAt=200;check(actor.tankChoose(100,0)=="","recovery respected");
        actor.tankReadyAt=100000;
    }
    private static function tick():Void {
        if(finished)return;
        if(!ready){
            loadTicks++;
            if(loadTicks>600){check(false,"load watchdog");finish();}
            return;
        }
        ticks++;
        if(ticks==2){
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i],u:MovieClip=c.actor;
                check(u.tankIdentity!==undefined && u.tankDriver.unitIdentity===u.tankIdentity,
                    "native unit driver captured initialized identity "+i);
                var face:String=c.side==0?"右":"左";
                u.tankReadyAt=100000;u.方向改变(face);u.状态改变("空手站立");
                check(u.area._visible===false,"area stays hidden on stand state "+i);
                check(u.x轴攻击范围==0 && (u.unitAI.data==null || u.unitAI.data.xrange==0),
                    "generic CombatModule xrange stays disabled "+i);
                if(c.mode=="preowned")u.刚体=u.免疫击退=u.锁定方向=true;
                c.initialX=u._x;
            }
            cases[0].actor.tankBurstDeath(cases[0].actor.man);
            check(cases[0].record.deathBurst==0,"live actor preview never triggers death burst");
            choices(cases[0].actor);
        }
        if(ticks==4){
            render(cases[0].actor,"stand-right");
            cases[0].actor.状态改变("空手行走");
        }
        if(ticks==5)render(cases[0].actor,"walk-right");
        if(ticks==6){
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i],u:MovieClip=c.actor;
                if(c.mode=="death")continue;
                u.fixtureBlocked=c.mode=="blocked";u.状态改变(u.tankActions[c.action].state);c.started=true;
                check(u.man.tankArt._currentframe==1
                    && u.man.tankArt._totalframes==(u.tankActions[c.action].end-u.tankActions[c.action].start+1),
                    "zero frame-1 flicker on state switch "+i);
                check(u.area._visible===false,"area stays hidden on state switch "+i);
            }
        }
        if(ticks==10){
            guardChecks(cases[1].actor);guardChecks(cases[10].actor);
            _root.暂停=true;
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i];c.pauseFrame=c.actor.man._currentframe;
                c.pausePulse=c.actor.tankOwner.pulse;c.record.pauseShots=c.record.shots;
            }
        }
        if(ticks==15){
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i];
                check(c.actor.man._currentframe==c.pauseFrame && c.record.shots==c.record.pauseShots,"pause freezes actual timeline "+i);
            }
            _root.暂停=false;
        }
        if(ticks==20){
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i],u:MovieClip=c.actor;
                if(c.mode=="cancel" || c.mode=="preowned"){
                    c.oldBodyIdentity=u.man.tankFrameIdentity;c.oldToken=u.tankOwner.token;
                    u.tankCancelAttack();u.状态改变("被击");
                    var prior:Boolean=c.mode=="preowned";
                    check(u.刚体===prior && u.免疫击退===prior && u.锁定方向===prior,"cancel restores previous protection "+i);
                    var before:Number=u.man._currentframe;u.tankBodyTick(u.man,c.oldBodyIdentity);
                    check(u.man._currentframe==before,"old callback cannot advance replacement pose "+i);
                }else if(c.mode=="fatal" || c.mode=="death"){
                    u.hp=0;u.状态改变("血腥死");
                    check(u.tankOwner==null && u.刚体===false && u.锁定方向===false,"death cancels hard-rigid attack "+i);
                }
            }
        }
        if(ticks==29)render(cases[8].actor,"death-start");
        if(ticks==40){
            var fragment:MovieClip=cases[8].actor.man.尸体碎片.碎片1;
            check(fragment._name!=undefined,"actual mechanical fragment exists for pause test");
            fragmentPause={x:fragment._x,y:fragment._y,rotation:fragment._rotation,
                frame:cases[8].actor.man._currentframe};
            _root.暂停=true;
        }
        if(ticks==45){
            var fragment:MovieClip=cases[8].actor.man.尸体碎片.碎片1;
            check(fragment._x==fragmentPause.x && fragment._y==fragmentPause.y
                && fragment._rotation==fragmentPause.rotation
                && cases[8].actor.man._currentframe==fragmentPause.frame,
                "pause freezes production fragments and death timeline");
            _root.暂停=false;
        }
        if(ticks==52)render(cases[8].actor,"death-fragments");
        if(ticks==55){
            var fragment:MovieClip=cases[8].actor.man.尸体碎片.碎片1;
            check(fragment._x!=fragmentPause.x || fragment._y!=fragmentPause.y,
                "production fragments resume physical movement");
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i],u:MovieClip=c.actor;
                if(c.mode!="fatal-active")continue;
                c.record.cutoffShots=c.record.shots;
                check(c.record.cutoffShots>0,"fatal interruption happens after actual emissions "+i);
                u.hp=0;u.状态改变("血腥死");
                check(u.tankOwner==null && u.刚体===false && u.免疫击退===false && u.锁定方向===false,
                    "active barrage death releases protection immediately "+i);
            }
        }
        if(ticks==100)render(cases[8].actor,"death-late");
        if(ticks==310){
            for(var i:Number=0;i<cases.length;i++){
                var c:Object=cases[i],u:MovieClip=c.actor,rec:Object=c.record;
                if(c.mode=="fatal" || c.mode=="death" || c.mode=="fatal-active"){
                    check(rec.removed && rec.deathChecks==1,"death settles and retires exactly once "+i);
                    check(rec.deathBurst==1,"single death explosion burst fires exactly once "+i);
                    check((rec.shots-rec.deathBurst)==rec.cutoffShots,"fatal interruption cannot finish emitting "+i);
                }else{
                    check(u.tankOwner==null,"attack finishes "+i);
                    var prior:Boolean=c.mode=="preowned";
                    check(u.刚体===prior && u.免疫击退===prior && u.锁定方向===prior,"finish restores all owned flags "+i);
                    check(u.tankMissingPort==0,"all required native ports present "+i);
                    if(c.mode=="normal" || c.mode=="blocked"){
                        check(rec.done==1,"one action completion "+i);
                        if(c.action=="melee")check(rec.melee==3 && rec.realHitPulses==3,"three heavy melee contacts and real settlements "+i);
                        if(c.action=="gatling")check(rec.gun==9,"nine machine-gun projectiles "+i);
                        if(c.action=="laser")check(rec.laser==10 && rec.realHitPulses==10,"ten visible-beam pulses and real settlements "+i);
                        if(c.action=="barrage" || c.action=="mobile")check(rec.loops==3,"three complete inner cycles "+i);
                        if(c.action=="barrage" || c.action=="mobile"){
                            check(rec.grenade==30,"ten grenades per inner cycle "+i);
                            check(rec.gun==(c.action=="barrage"?36:33)
                                && rec.cannon==(c.action=="barrage"?3:4)
                                && rec.laser==(c.action=="barrage"?24:0),"all authored weapons participate "+i);
                            if(c.action=="barrage")check(rec.realHitPulses==24,"every barrage beam pulse settles through the real queue "+i);
                            for(var loop:Number=1;loop<=3;loop++)for(var slot:Number=0;slot<10;slot++)
                                check(rec.launchers[loop+"_"+slot]===true,"each authored launcher participates "+i+" "+loop+" "+slot);
                        }
                        if(c.action=="mobile"){
                            var deltaX:Number=u._x-c.initialX;
                            var distance:Number=Math.abs(deltaX);
                            check(distance<=480.1 && (c.mode=="blocked"?distance==0:((c.side==0?deltaX>150:deltaX<-150))),
                                "bounded collision-mediated forward movement "+i);
                        }else check(Math.abs(u._x-c.initialX)<0.1,"stationary action does not drift "+i);
                    }
                    trace("[CF2_TANK_CASE] "+i+" "+c.action+" "+c.mode+" side="+c.side
                        +" shots="+rec.shots+" gun="+rec.gun+" cannon="+rec.cannon+" laser="+rec.laser
                        +" grenades="+rec.grenade+" deathBurst="+rec.deathBurst
                        +" loops="+rec.loops+" done="+rec.done+" missingPorts="+u.tankMissingPort);
                }
            }
            finish();
        }
    }
    private static function hex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function render(actor:MovieClip,name:String):Void {
        check(actor!=null && actor._name!=undefined,"capture actor exists "+name);
        if(actor._name==undefined)return;
        var wide:Boolean=name.indexOf("laser")==0 || name.indexOf("barrage")==0;
        var width:Number=wide?1600:800,height:Number=wide?900:540;
        var image:BitmapData=new BitmapData(width,height,true,0xffe8e6e2);
        var transform:Matrix=actor.transform.matrix;
        transform.tx=wide?(actor.方向=="左"?1250:350):400;transform.ty=wide?650:440;
        var showInfo:Boolean=actor.人物文字信息._visible;actor.人物文字信息._visible=false;
        image.draw(actor,transform);actor.人物文字信息._visible=showInfo;
        var visible:Number=0;
        for(var y:Number=0;y<height;y+=4)for(var x:Number=0;x<width;x+=4)
            if(image.getPixel(x,y)!=0xe8e6e2)visible++;
        check(visible>100,"nonempty native pixels "+name);
        images[name]=true;
        var bounds:Object=actor.getBounds(actor);
        trace("[CF2_TANK_NATIVE_IMAGE] "+name+" pixels="+visible+" bounds="
            +bounds.xMin+","+bounds.yMin+","+bounds.xMax+","+bounds.yMax);
        if(_root.tankCapture===true){
            trace("[CF2_TANK_IMAGE_BEGIN] "+name+" "+width+" "+height);
            var content:Object=image.getColorBoundsRect(0xffffffff,0xffe8e6e2,false);
            var left:Number=content.x,right:Number=content.x+content.width;
            var top:Number=content.y,bottom:Number=content.y+content.height;
            var chunk:String="";
            for(var row:Number=0;row<height;row++){
                var parts:Array=[];
                if(row<top || !(row<bottom) || !(left<right)){
                    parts.push("ffe8e6e2:"+width);
                }else{
                    if(left>0)parts.push("ffe8e6e2:"+left);
                    var last:Number=image.getPixel32(left,row),count:Number=1;
                    for(var col:Number=left+1;col<right;col++){
                        var value:Number=image.getPixel32(col,row);
                        if(value==last)count++;else{parts.push(hex(last)+":"+count);last=value;count=1;}
                    }
                    parts.push(hex(last)+":"+count);
                    if(right<width)parts.push("ffe8e6e2:"+(width-right));
                }
                var encoded:String=row+"="+parts.join(",")+";";
                if(length(chunk)>0 && length(chunk)+length(encoded)>8192){
                    trace("[CF2_TANK_IMAGE_DATA] "+name+" "+chunk);chunk="";
                }
                chunk+=encoded;
            }
            if(length(chunk)>0)trace("[CF2_TANK_IMAGE_DATA] "+name+" "+chunk);
            trace("[CF2_TANK_IMAGE_END] "+name);
        }
        image.dispose();
    }
    private static function finish():Void {
        if(finished)return;finished=true;_root.暂停=false;
        var expected:Array=["stand-right","walk-right","melee-right","gatling-right","laser-right","laser-left",
            "barrage-right","mobile-right","death-start","death-fragments","death-late"];
        for(var i:Number=0;i<expected.length;i++)check(images[expected[i]]===true,"complete native image set "+expected[i]);
        var sounds:Array=["地震1.wav","re_MG_m249.wav","CF6_0992.mp3","G1炮开火.wav","re_GL_ChinaLake.wav","CF6_1009.mp3"];
        for(var i:Number=0;i<sounds.length;i++)check(audioCalls[sounds[i]]>0,"actual action sound callback "+sounds[i]);
        for(var i:Number=0;i<cases.length;i++)if(cases[i].actor._name!=undefined)cases[i].actor.removeMovieClip();
        if(damageTarget!=null)damageTarget.removeMovieClip();
        loader.removeListener(listener);library.removeMovieClip();delete driver.onEnterFrame;driver.removeMovieClip();
        trace("Cf2TankBossAssetTest: "+passed+" passed, "+failed+" failed; native tank actions");
        _root.cf2TankBossComplete();
    }
}
