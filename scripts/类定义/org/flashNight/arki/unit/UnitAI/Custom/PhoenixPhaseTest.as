import org.flashNight.arki.unit.UnitAI.Custom.PhoenixPhaseController;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitBattleRecord;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.component.Damage.ActualTerminalDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Shield.ShieldStack;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.neur.ScheduleTimer.UnitUpdateWheel;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.behavior.CombatModule;
import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/** Real RSL actor and art; real impact collision; rewards are a read-only spy. */
class org.flashNight.arki.unit.UnitAI.Custom.PhoenixPhaseTest {
    private static var pass:Number,fail:Number,age:Number,step:Number,deaths:Number,rewards:Number,hits:Number;
    private static var world:MovieClip,u:MovieClip,dummy:MovieClip,far:MovieClip,driver:MovieClip;
    private static var c:Object,marks:Object,finished:Boolean;
    private static function check(ok:Boolean,name:String):Void {
        if(ok)pass++;else {fail++;trace("PhoenixPhaseTest FAIL: "+name);}
    }
    public static function runAllTests():Void {
        pass=0;fail=0;age=0;step=0;deaths=0;rewards=0;hits=0;finished=false;marks={};
        _root.暂停=false;_root.是否阴影=true;_root.血腥开关=true;
        _root.重力加速度=1;_root.最大等级=60;_root.难度等级=1;_root.控制目标="fixturePlayer";
        _root.Xmin=-1000;_root.Xmax=1000;_root.Ymin=-500;_root.Ymax=1000;
        _root.duplicateOf=ObjectUtil.clone;
        _root.装备引用配置={配置装扮:function():MovieClip{return null;}};
        _root.帧计时器={当前帧数:0,帧率:30,unitUpdateWheel:UnitUpdateWheel.I(),
            添加冷却任务:function():Void{},移除任务:function():Void{},添加任务:function():Number{return 0;}};
        _root.collisionLayer={hitTest:function(x:Number,y:Number,shape:Boolean):Boolean{return false;}};
        _root.对象浅拷贝=function(o:Object):Object {var r:Object={};for(var key:String in o)r[key]=o[key];return r;};
        _root.子弹区域shoot传递=function(p:Object):Void {PhoenixPhaseTest.realImpact(p);};
        driver=_root.createEmptyMovieClip("__phoenixTest",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            if(++PhoenixPhaseTest.age>900) {PhoenixPhaseTest.check(false,"loading watchdog");PhoenixPhaseTest.finish();}
        };
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            PhoenixPhaseTest.check(ok,"load actual monster profile");
            if(!ok){PhoenixPhaseTest.finish();return;}
            _root.敌人属性表=XMLParser.parseXMLNode(this.firstChild);
            PhoenixPhaseTest.spawnWorld();
        };
        xml.load("../data/enemy_properties/原版敌人 2013-2016.xml");
    }
    private static function spawnWorld():Void {
        world=_root.createEmptyMovieClip("__phoenixWorld",_root.getNextHighestDepth());
        _root.gameworld=world;world.dispatcher=new EventDispatcher();world._x=200;world._y=400;
        // Functional fixture: omit continuous stage rasterization. Explicit
        // BitmapData captures still render the real actor and its vector FX.
        // This suite makes no full-game frame-rate claim.
        world._visible=false;
        DepthManager.instance=new DepthManager(world,100,1048575,4);DepthManager.instance.calibrate(-500,1000);
        org.flashNight.arki.component.Collider.ColliderFactoryRegistry.init();
        StaticInitializer.factory=new AABBColliderFactory(4);TargetCacheManager.initialize();Mover.init();
        dummy=makeDummy("fixturePlayer",40);far=makeDummy("farPlayer",450);
        spawn(false);age=0;
        driver.onEnterFrame=function():Void {
            try{PhoenixPhaseTest.advance();}
            catch(error){PhoenixPhaseTest.check(false,"exception: "+error);PhoenixPhaseTest.finish();}
        };
    }
    private static function makeDummy(name:String,x:Number):MovieClip {
        var t:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());
        t._x=x;t._y=0;t.Z轴坐标=0;t.hp=100000;t.hp满血值=100000;
        t.是否为敌人=false;t.兵种="主角-男";t.version=1000;t.等级=20;t.重量=60;
        t.躲闪率=999999;t.懒闪避=0;t.防御力=0;t.魔法抗性={基础:0,热:0};
        t.无敌=false;t.NPC=false;t.防止无限飞=false;t.man={无敌标签:false};
        t.shield=new ShieldStack();t.damageTakenMultiplier=1;t.ti61CrumbleTakenMultiplier=1;
        t.dispatcher=new EventDispatcher();
        var body:MovieClip=t.createEmptyMovieClip("area",0);body.beginFill(0x335566,100);
        body.moveTo(-15,-120);body.lineTo(15,-120);body.lineTo(15,0);body.lineTo(-15,0);body.lineTo(-15,-120);body.endFill();body._visible=false;
        t.aabbCollider=new AABBCollider(0,0,0,0);t.aabbCollider.updateFromUnitArea(t);
        TargetCacheManager.addUnit(t);return t;
    }
    private static function spawn(nirvana:Boolean):Void {
        trace("PhoenixPhaseTest Spawn: kind="+PhoenixPhaseController.KIND+" controller="+typeof PhoenixPhaseController+" root="+_root._url);
        u=world.attachMovie(PhoenixPhaseController.KIND,nirvana?"nirvana":"phoenix",world.getNextHighestDepth(),
            {_x:0,_y:0,兵种:PhoenixPhaseController.KIND,等级:20,是否为敌人:true,名字:"火凤",身高:175,宠物属性:{涅槃重生:nirvana}});
        check(u!=undefined,"real Phoenix linkage attaches");
        if(!u)finish();
    }
    private static function observe():Void {
        c=u.__phoenixPhase;
        check(c!=undefined && u.__unitInitializedVersion==u.version,"shared initializer and unit-local controller completed");
        u.dispatcher.subscribe("death",function():Void{PhoenixPhaseTest.deaths++;},u);
        u.计算经验值=function():Void{PhoenixPhaseTest.rewards++;this.已加经验值=true;};
    }
    private static function realImpact(p:Object):Void {
        if(p.区域定位area._name!="__phoenixImpact")return;
        check(p.区域定位area!=undefined && p.击倒率>0,"local impact has real geometry and finite impact divisor");
        check(Math.abs(p.shootX-c.x)<.05 && p.shootZ==c.z,"impact uses frozen world anchor");
        var before:Number=dummy.hp,farBefore:Number=far.hp;
        BulletFactory.prepareBulletData(p,u);
        var bullet:Object=BulletFactory.createBullet(p,u,u.方向=="右"?0:180);
        BulletQueueProcessor.processQueue();
        check(bullet.hitCount>0 && dummy.hp<before,"transition passes production collision and damage settlement");
        check(far.hp==farBefore,"distant target is outside the transition strike");
        trace("PhoenixPhaseTest Impact: phase="+c.phase+" power="+p.子弹威力+" damage="+(before-dummy.hp)+" hits="+bullet.hitCount);
        hits++;
    }
    private static function advance():Void {
        if(finished)return;
        age++;_root.帧计时器.当前帧数++;EnhancedCooldownWheel.I().tick();UnitUpdateWheel.I().tick();
        if(age>1000){check(false,"phase watchdog step="+step+" frame="+c.frame+" state="+u.状态);finish();return;}
        if(step==0 && age>=3) {
            observe();marks.baseMax=u.hp满血值;marks.baseAttack=u.空手攻击力;marks.speed=u.行走X速度;
            check(c.phase==0 && c.count==0,"ordinary actor starts in phase one");
            trace("PhoenixPhaseTest Profile: kind="+u.兵种+" level="+u.等级+" hpMin="+u.hp_min+" max="+u.hp满血值+" attack="+u.空手攻击力);
            check(u.hp满血值>=5000 && u.空手攻击力>=70,"real spawn kind selects the actual monster profile rather than defaults");
            checkBehavior("phase-one");capture("standing");u.hp=1000;
            check(!c.transition && c.phase==0,"1500 HP no longer starts a transition");
            u._y=u.Z轴坐标-50;u.浮空=true;
            ActualTerminalDamageHandle.getInstance().handleBulletDamage({},dummy,u,null,new DamageResult());
            check(c.transition && u.hp==1 && c.count==1,"real forced-terminal damage is intercepted before public zero HP");
            u.hp=-99999;u.hp=99999;u.无敌=false;u.状态改变("血腥死");u.dispatcher.publish("kill",u);
            check(u.hp==1 && u.无敌 && !u._killed && deaths==0 && !u.__battleRecord.down,"same-frame damage heal kill and invulnerability writes cannot bypass transition");
            step=1;return;
        }
        if(step==1) {
            if(c.step=="down") {
                check(u.man._totalframes==66 && c.downFrames==30 && u.man._currentframe==c.age+1,"down clock owns the actual loaded down clip and stops before its legacy get-up");
                if(c.age==0 || c.age==29)capture("down-"+c.age);marks.down=true;check(!u.浮空 && Math.abs(u._y-u.Z轴坐标)<.05,"first transition is grounded before its complete down animation");}
            if(c.step=="show" && (c.frame==1 || c.frame==80))capture("rise-"+c.frame);

            if(c.step=="show" && c.frame>=40 && !marks.paused) {
                marks.paused=true;marks.pausedFrame=c.frame;marks.pauseUntil=age+5;_root.暂停=true;
            }
            if(_root.暂停) {
                check(c.frame==marks.pausedFrame && c.visual._currentframe==marks.pausedFrame,"one existing pause gate freezes controller and art together");
                if(age>=marks.pauseUntil)_root.暂停=false;
                return;
            }
            if(!c.transition && c.phase==1) {
                checkBehavior("phase-two");capture("after-rise");
                check(marks.down && c.count==1 && c.impacts==1 && hits==1,"one full grounded phase-two transition and one real burst");
                check(u.hp>marks.baseMax*.95 && !u.无敌 && deaths==0 && rewards==0,"phase two refills without early settlement or permanent invulnerability");
                check(Math.abs(u.行走X速度-marks.speed*1.5)<.001,"phase-two speed is applied once through the existing derived speed");
                u.Z轴坐标=12.013;u._y=-55;u.浮空=true;
                var lethal:Object=BulletFactory.createSettlementBullet({子弹种类:"近战子弹",伤害类型:"真伤",
                    子弹威力:10000000,霰弹值:1,击倒率:1,水平击退速度:4,垂直击退速度:4},dummy);
                u.无敌=false;u.man.无敌标签=false;u.防止无限飞=false;
                BulletQueueProcessor.injectHit(lethal,dummy,u,u._x,u._y-70,1);
                check(c.transition && u.hp==1 && !u._killed && deaths==0 && c.thinker._parent===u,
                    "real melee direct-death producer cannot settle an intermediate life");
                marks.x=c.x;marks.z=c.z;step=2;
            }
            return;
        }
        if(step==2) {
            check(c.x==marks.x && c.z==marks.z && Math.abs(u._x-marks.x)<.05,"third transition never tracks its target");
            if(c.step=="show" && (c.frame==82 || c.frame==158 || c.frame==182))capture("third-"+c.frame);


            if(c.step=="show" && c.frame<159) {
                check(c.impacts==1,"airborne presentation does not cause extra damage");
                check(c.visual._y<=0 && c.visual._y>=c.apex-.05,"air entrant follows a bounded vertical presentation");
                if(c.frame==82)check(Math.abs(c.visual._y-c.lift)<.05,"air transition starts at the actual captured height");
                if(c.frame==93)check(Math.abs(c.visual._y-c.lift)<.05,"air entrant first stabilizes while the flames gather");
                if(c.frame==95) {marks.firstRise=Math.abs(c.visual._y-c.lift);check(marks.firstRise<2,"gentle ascent has no initial launch impulse");}
                if(c.frame==100)check(Math.abs(c.visual._y-c.lift)>marks.firstRise*5,"gentle ascent accelerates after its restrained start");
                if(c.frame==120)check(Math.abs(c.visual._y-c.apex)<2,"gentle ascent slows down before hovering");
                if(c.frame==121 || c.frame==150)check(Math.abs(c.visual._y-c.apex)<.05,"air transition reaches and holds the authored hover height");
                if(c.frame>82 && c.frame<128)check(c.visual.charge._totalframes==32 && c.visual.charge._currentframe==1+(c.frame-82)%32 && c.visual.charge._alpha>0,"real graphic flame layer follows the sole presentation clock");
                if(c.frame>=128)check(c.visual.charge._alpha==0,"charge flame retires before the existing landing presentation");
                if(c.frame==158)check(c.visual._y>c.apex && c.visual._y<0,"air transition descends before its final impact");
            }

            if(!c.transition && c.phase==2) {
                checkBehavior("phase-three");
                check(c.count==2 && c.impacts==2 && hits==2,"third-phase landing emits one local impact");
                check(u.man._visible && c.aura!=undefined,"final handoff restores the standing body and its existing ember aura");
                check(u.hp==1500 && u.hp满血值==1500 && !u.无敌 && !u.浮空,"final phase preserves existing HP and restores ordinary combat");
                check(deaths==0 && rewards==0 && !u._killed,"neither intermediate life settles a kill");
                capture("phase-three");u.hp=0;u.dispatcher.publish("kill",u);u.dispatcher.publish("kill",u);
                check(deaths==1 && u._killed,"final death settles once despite duplicate kill entry");
                u.死亡检测();check(rewards==1,"final shared death awards experience once");
                spawn(true);marks.spawnAge=age;step=3;
            }
            return;
        }
        if(step==3 && age>=marks.spawnAge+3) {
            observe();
            checkBehavior("nirvana");capture("nirvana-standing");
            check(c.nirvana && c.phase==1 && c.count==0,"Nirvana starts in the fused second phase without an extra introduction");
            check(u.hp满血值==marks.baseMax*2,"actual pet promotion doubles the initial life maximum");
            check(Math.abs(u.空手攻击力-(marks.baseAttack+10)*.7)<.001,"promotion and phase attack changes each apply once");
            u.hp=100;_root.敌人函数.粉红头发御姐自回血(u,26,130);
            check(u.hp==126,"Nirvana retains second-phase healing instead of self-burning");
            u.状态改变("击倒");marks.knockAge=age;step=4;return;
        }
        if(step==4 && age>=marks.knockAge+2) {
            check(u.状态=="被击" && !u.浮空,"living Nirvana keeps its existing anti-knockdown branch");
            u.hp-=100000;step=5;return;
        }
        if(step==5 && c.transition && c.step=="show" && c.frame<159) {
            check(Math.abs(u._x-c.x)<.05 && u.Z轴坐标==c.z,"ground transition keeps its original horizontal position and landing depth");
            if(c.frame==82) {check(c.visual._y==0,"ground transition starts at ground level");capture("nirvana-ground");}
            if(c.frame==88) {check(c.visual._y==0 && c.visual.charge._alpha>40,"ground flames grow before the body leaves the floor");capture("nirvana-charge");}
            if(c.frame==93)trace("PhoenixPhaseTest Charge: y="+c.visual._y+" alpha="+c.visual.charge._alpha);
            if(_root.phoenixLiftCapture===true && c.frame<=136 && c.frame%2==0 && marks.motionFrame!=c.frame) {
                marks.motionFrame=c.frame;captureMotion();
            }
            if(c.frame==93) {check(c.visual._y==0 && Math.abs(c.visual.charge._alpha-90)<.5,"ground charge has a distinct stable pose before liftoff");capture("nirvana-charge-full");}
            if(c.frame==100) {check(c.visual._y<0 && c.visual._y>c.apex*.2,"ground body gently begins rising after charging");capture("nirvana-rise-start");}
            if(c.frame==108) {check(c.visual._y<0 && c.visual._y>c.apex,"ground body is supported by a visible flame during ascent");capture("nirvana-rise");}
            if(c.frame==121) {check(Math.abs(c.visual._y+208.95)<.05,"ground transition reaches the original demo's 208.95px hover height");capture("nirvana-hover");}
            if(c.frame==158)check(c.visual._y>c.apex && c.visual._y<0,"ground transition visibly descends before landing");
            if((c.frame==90 && !marks.chargePaused) || (c.frame==110 && !marks.flightPaused)) {
                if(c.frame==90)marks.chargePaused=true;else marks.flightPaused=true;
                marks.flightFrame=c.frame;marks.flightY=c.visual._y;marks.flameFrame=c.visual.charge._currentframe;
                marks.flameAlpha=c.visual.charge._alpha;marks.flightUntil=age+3;_root.暂停=true;
            }
            if(_root.暂停) {
                check(c.frame==marks.flightFrame && c.visual._y==marks.flightY && c.visual.charge._currentframe==marks.flameFrame && c.visual.charge._alpha==marks.flameAlpha,"pause freezes charge graphics and vertical ascent together");
                if(age>=marks.flightUntil)_root.暂停=false;
            }
        }
        if(step==5 && !c.transition && c.phase==2) {
            check(c.count==1 && c.impacts==1 && hits==3,"Nirvana shares the same final transition without a first-life replay");
            check(deaths==1 && rewards==1,"fused transition still has no early death settlement");
            trace("PhoenixPhaseTest Complete Transitions: 3");finish();
        }
    }
    private static function checkBehavior(label:String):Void {
        var facing:String=u.方向,x:Number=u._x,z:Number=u.Z轴坐标;
        var savedRootScale:Object=_root.myxscale;
        check(u._currentframe==2 && u.状态=="空手站立",label+" root timeline is stopped on its actual standing frame");
        check((facing=="右" && u._xscale>0) || (facing=="左" && u._xscale<0),label+" stored initial facing agrees with the rendered body");
        // Spoof another unit's loader value: this actor must not inherit it.
        _root.myxscale=-37;
        u.方向改变("右");
        check(u.方向=="右" && Math.abs(u._xscale-u._yscale)<.01,label+" turns right independently of root scale");
        u.方向改变("左");
        check(u.方向=="左" && Math.abs(u._xscale+u._yscale)<.01,label+" turns left independently of root scale");
        u.锁定方向=true;u.方向改变("右");
        check(u.方向=="左" && u._xscale<0,label+" keeps the existing direction lock");u.锁定方向=false;
        _root.myxscale=savedRootScale;
        var data:UnitAIData=new UnitAIData(u);data.target=dummy;
        var combat:Object=new CombatModule(data);
        combat.superMachine={getActionCount:function():Number {return 0;}};
        var targetX:Number=dummy._x,targetZ:Number=dummy.Z轴坐标;
        dummy.Z轴坐标=dummy._y=z;dummy._x=x+250;
        combat.chase();u.行走();
        check(u._x>x && u.方向=="右" && u._xscale>0 && u.状态=="空手行走",label+" real enemy chase and movement approach a target on the right");
        dummy._x=x-250;var moved:Number=u._x;
        combat.chase();u.行走();
        check(u._x<moved && u.方向=="左" && u._xscale<0,label+" real enemy chase and movement approach a target on the left");
        dummy._x=u._x;dummy.Z轴坐标=z+40;combat.chase();u.行走();
        check(u.Z轴坐标>z,label+" keeps depth movement toward a lower lane");
        dummy.Z轴坐标=z-40;var lower:Number=u.Z轴坐标;combat.chase();u.行走();
        check(u.Z轴坐标<lower,label+" keeps depth movement toward an upper lane");
        dummy.Z轴坐标=u.Z轴坐标;dummy._x=u._x+40;combat.chase();
        check(u.方向=="右" && u._xscale>0 && u.状态=="空手攻击",label+" real enemy AI can enter a right-facing attack");
        u.动画完毕();dummy._x=u._x-40;combat.chase();
        check(u.方向=="左" && u._xscale<0 && u.状态=="空手攻击",label+" real enemy AI can enter a left-facing attack");
        u.动画完毕();
        check(u.状态=="空手站立" && !u.倒地,label+" attack completion returns to the shared ready state");
        u._x=x;u.Z轴坐标=u._y=z;u.方向改变(facing);
        u.左行=u.右行=u.上行=u.下行=false;
        dummy._x=targetX;dummy.Z轴坐标=dummy._y=targetZ;
        u.aabbCollider.updateFromUnitArea(u);dummy.aabbCollider.updateFromUnitArea(dummy);
        trace("PhoenixPhaseTest Behavior: "+label+" real chase both directions, depth, attacks, finish; actor="+u._currentframe+" facing="+u.方向+" scale="+u._xscale);
    }
    private static function captureMotion():Void {
        trace("PhoenixPhaseTest Motion Frame: "+c.frame+" y="+c.visual._y);
        var bitmap:BitmapData=new BitmapData(180,240,true,0);
        var m:Matrix=new Matrix(u._xscale/200,0,0,u._yscale/200,90,220+c.visual._y*u._yscale/200);
        bitmap.draw(c.visual,m,null,"normal",null,true);
        emitSnapshot(bitmap,"motion-"+c.frame);
        marks.motionCount=Number(marks.motionCount||0)+1;
        if(c.frame==136)trace("PhoenixPhaseTest Motion Captures: "+marks.motionCount);
    }
    private static function capture(id:String):Void {
        if(_root.phoenixPhaseCapture!==true)return;
        var bitmap:BitmapData=new BitmapData(520,540,true,0);
        var m:Matrix=u.transform.matrix.clone();m.tx=260;m.ty=490+u._y-u.Z轴坐标;
        bitmap.draw(u,m,null,"normal",null,true);emitSnapshot(bitmap,id);
    }
    private static function emitSnapshot(bitmap:BitmapData,id:String):Void {
        var output:String="[ASSET_BITMAP_BEGIN] phoenix-"+id+" "+bitmap.width+" "+bitmap.height+"\n";
        var bounds:Rectangle=bitmap.getColorBoundsRect(0xFFFFFFFF,0,false);
        for(var y:Number=bounds.y;y<bounds.y+bounds.height;y++) {
            var row:String="",last:Number=0,count:Number=bounds.x;
            for(var x:Number=bounds.x;x<bounds.x+bounds.width;x++) {
                var pixel:Number=bitmap.getPixel32(x,y);
                if(pixel==last)count++;
                else{if(count)row+=hex(last)+":"+count+",";last=pixel;count=1;}
            }
            if(last==0)count+=bitmap.width-(bounds.x+bounds.width);
            else {row+=hex(last)+":"+count+",";last=0;count=bitmap.width-(bounds.x+bounds.width);}
            row+=hex(last)+":"+count;
            output+="[ASSET_BITMAP_ROW] "+y+" "+row+"\n";
        }
        trace(output+"[ASSET_BITMAP_END] phoenix-"+id);
        bitmap.dispose();
    }
    private static function hex(pixel:Number):String {
        var low:String=(pixel&65535).toString(16);
        while(length(low)<4)low="0"+low;
        return ((pixel>>>16)&65535).toString(16)+low;
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        delete u.__phoenixPhase.thinker.onEnterFrame;
        _root.暂停=true;u.stop();u.man.stop();
        trace("PhoenixPhaseTest Tests Passed: "+pass);
        trace("PhoenixPhaseTest Tests Failed: "+fail);
        _root.phoenixPhaseTestComplete();
    }
}
