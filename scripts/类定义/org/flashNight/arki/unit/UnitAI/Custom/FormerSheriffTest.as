import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.component.Shield.ShieldStack;
import org.flashNight.arki.spatial.animation.FragmentAnimator;
import org.flashNight.arki.unit.UnitAI.Custom.FormerSheriffController;
import org.flashNight.arki.unit.Action.Skill.SheriffShieldRush;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitBattleRecord;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.component.Damage.ActualTerminalDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Effect.BloodBarEffectHandler;
import org.flashNight.arki.unit.UnitComponent.Updater.InformationComponentUpdater;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.neur.ScheduleTimer.UnitUpdateWheel;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/** Actual XML, native compiled NPC, production initializer, movement, buffs,
 * routing, reload and death records. Rush uses the real collision/damage path; rewards are spies.
 * No game save, host inventory or formal runtime is touched. */
class org.flashNight.arki.unit.UnitAI.Custom.FormerSheriffTest {
    private static var pass:Number,fail:Number,age:Number,fileIndex:Number;
    private static var items:Array,files:Array,world:MovieClip,u:MovieClip,driver:MovieClip;
    private static var dummy:MovieClip,ally:MovieClip,c:Object;
    private static var bullets:Number,deaths:Number,rewards:Number,inventoryWrites:Number;
    private static var marks:Object,finished:Boolean;
    private static var dressupCalls:Number;
    private static function check(ok:Boolean,name:String):Void {
        if(ok)pass++;else{fail++;trace("FormerSheriffTest FAIL: "+name);}
    }
    public static function runAllTests():Void {
        pass=0;fail=0;age=0;fileIndex=0;bullets=0;deaths=0;rewards=0;inventoryWrites=0;
        items=[];marks={};finished=false;dressupCalls=0;
        calibrationBoundaryTests();
        files=["enemy_properties/前治安官.xml"];
        _root.暂停=false;_root.是否阴影=true;_root.血腥开关=true;
        _root.重力加速度=1;_root.最大等级=60;_root.难度等级=1;_root.控制目标="fixturePlayer";
        // Every tested pose must work with runtime costume attachment disabled.
        _root.装备引用配置={配置装扮:function(clip:MovieClip,skin:String):MovieClip {
            var actor:MovieClip=clip;
            while(actor && actor._parent) {
                if(actor.兵种==FormerSheriffController.KIND) {
                    FormerSheriffTest.dressupCalls++;
                    trace("FormerSheriffTest Unexpected Dressup: "+clip+" skin="+skin);
                    break;
                }
                actor=actor._parent;
            }
            return null;
        }};
        _root.duplicateOf=ObjectUtil.clone;
        _root.帧计时器={当前帧数:0,帧率:30,unitUpdateWheel:UnitUpdateWheel.I(),
            添加冷却任务:function(n:Number,f:Function):Void {},
            移除任务:function(id:Number):Void {},
            添加任务:function(f:Function,delay:Number):Number {return 0;}};
        _root.物品栏={背包:{getItemAmount:function(name:String):Number{return 99;},
            consume:function():Void{FormerSheriffTest.inventoryWrites++;}},
            消耗:function():Void{FormerSheriffTest.inventoryWrites++;}};
        _root.collisionLayer={hitTest:function(x:Number,y:Number,shape:Boolean):Boolean {
            return x < -800 || x > 1500 || y < -200 || y > 400;
        }};
        // Keep the real native firing/reload pipeline; stop at the bullet sink.
        _root.对象浅拷贝=function(o:Object):Object {var copy:Object={};for(var key:String in o)copy[key]=o[key];return copy;};
        _root.子弹区域shoot传递=function(p:Object):Void {
            FormerSheriffTest.bullets++;
            if(FormerSheriffTest.u.__sheriffShieldRush.phase=="rush")FormerSheriffTest.realRushHit(p);
            else if(FormerSheriffTest.c.phase==2 && FormerSheriffTest.age<955) {
                FormerSheriffTest.check(p.击倒率>0,"phase-two impact never uses guaranteed toughness break sentinel");
                FormerSheriffTest.realRushHit(p);
            }
        };
        driver=_root.createEmptyMovieClip("__formerSheriffTest",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            if(++FormerSheriffTest.age>2000) {
                FormerSheriffTest.check(false,"loading watchdog");FormerSheriffTest.finish();
            }
        };
        nextFile();
    }
    private static function calibrationBoundaryTests():Void {
        var previousMode:Object=_root.斗兽标定模式;
        var probe:MovieClip=_root.createEmptyMovieClip("__sheriffCalibrationProbe",_root.getNextHighestDepth());
        for(var mask:Number=0;mask<8;mask++) {
            _root.斗兽标定模式=(mask&1)!=0;
            probe._arenaCalibrationUnit=(mask&2)!=0;
            probe.__formerSheriff={phase:1,hp:100,transitionCount:0,tune:{calibrationPhaseOne:(mask&4)!=0?1:0}};
            FormerSheriffController.setHP(probe,-20);
            var context:Object=probe.__formerSheriff;
            if(mask==7) {
                check(context.phase=="calibrationDefeated" && context.hp==-20 && context.transitionCount==0,
                    "calibration explicit first-life terminal exposes lethal HP without second life");
                FormerSheriffController.setHP(probe,-30);
                check(context.phase=="calibrationDefeated" && context.transitionCount==0,
                    "calibration repeated lethal damage cannot start transition");
            } else {
                check(context.phase=="transition" && context.hp==1 && context.transitionCount==1,
                    "normal transition retained outside complete calibration opt-in mask "+mask);
            }
        }
        _root.斗兽标定模式=previousMode;
        probe.removeMovieClip();
    }
    private static function nextFile():Void {
        if(fileIndex>=files.length){loadArt();return;}
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            FormerSheriffTest.check(ok,"real XML "+FormerSheriffTest.files[FormerSheriffTest.fileIndex]);
            if(!ok){FormerSheriffTest.finish();return;}
            var data:Object=XMLParser.parseXMLNode(this.firstChild);
            if(FormerSheriffTest.fileIndex==0)_root.敌人属性表=data;
            else {
                var rows:Array=XMLParser.configureDataAsArray(data.item);
                for(var i:Number=0;i<rows.length;i++)
                    if(String(rows[i].name).indexOf("特勤")>=0)FormerSheriffTest.items.push(rows[i]);
            }
            FormerSheriffTest.fileIndex++;FormerSheriffTest.nextFile();
        };
        xml.load("../data/"+files[fileIndex]);
    }
    private static function loadArt():Void {
        check(!ItemUtil.isItem("特勤霰弹枪"),"fixture has no player equipment data loaded");
        // The dedicated top-level XFL imports the real art and nameplate.
        // A nested loadMovie host cannot expose its RSL exports to root code.
        world=_root.createEmptyMovieClip("__formerSheriffLibrary",_root.getNextHighestDepth());
        spawn(world);
    }
    private static function spawn(mc:MovieClip):Void {
        _root.gameworld=mc;mc.dispatcher=new EventDispatcher();
        for(var displayKey:String in mc)if(typeof mc[displayKey]=="movieclip")mc[displayKey]._visible=false;
        mc._x=200;mc._y=230;
        DepthManager.instance=new DepthManager(mc,100,1048575,4);
        DepthManager.instance.calibrate(-500,1000);
        org.flashNight.arki.component.Collider.ColliderFactoryRegistry.init();
        StaticInitializer.factory=new AABBColliderFactory(4);
        TargetCacheManager.initialize();Mover.init();
        u=mc.attachMovie(FormerSheriffController.KIND,"sheriff",mc.getNextHighestDepth(),
            {_x:0,_y:0,等级:20,是否为敌人:true,名字:"前治安官",基础命中率:10});
        check(u!=undefined,"native NPC linkage attaches");
        if(!u){finish();return;}
        age=0;
        driver.onEnterFrame=function():Void {
            try{FormerSheriffTest.advance();}
            catch(error){FormerSheriffTest.check(false,"exception "+error);FormerSheriffTest.finish();}
        };
    }
    private static function realRushHit(p:Object):Void {
        var context:Object=u.__sheriffShieldRush;
        var area:Object=p.区域定位area.getRect(world);
        check(area.xMax>area.xMin && area.yMax>area.yMin && Math.abs(area.xMin-u._x)<500,"published native impact shape is nonempty and near the actor");
        BulletFactory.prepareBulletData(p,u);
        var bullet:Object=BulletFactory.createBullet(p,u,u.方向=="右"?0:180);
        var before:Number=dummy.hp;
        var targets:Array=TargetCacheManager.getCachedEnemy(u,1);
        var collider:Object=bullet.aabbCollider;
        check(collider.right>collider.left && collider.bottom>collider.top,"real impact bullet receives a finite collider from the production registry");
        var queueSizes:String="";
        for(var queueKey:String in BulletQueueProcessor.activeQueues)
            queueSizes+=queueKey+":"+BulletQueueProcessor.activeQueues[queueKey].getCount()+" ";
        trace("FormerSheriffTest Hit Path: targets="+targets.length+" first="+targets[0]._name+" queues="+queueSizes+" paused="+_root.暂停+" shooter="+bullet.发射者名+" flags="+bullet.flags+" aabb="+collider.left+","+collider.right+","+collider.top+","+collider.bottom+" Z="+bullet.Z轴坐标+" range="+bullet.Z轴攻击范围);
        BulletQueueProcessor.processQueue();
        if(bullet.hitCount>0)check(isFinite(bullet.破坏力) && bullet.破坏力>1,"real damage has initialized variance and finite power");
        trace("FormerSheriffTest Real Rush: phase="+c.phase+" power="+p.子弹威力+" damageType="+p.伤害类型+" bounds="+area.xMin+","+area.xMax+","+area.yMin+","+area.yMax+" z="+p.shootZ+" target="+dummy._x+","+dummy.Z轴坐标+" hp="+before+"->"+dummy.hp+" hitCount="+bullet.hitCount);
    }
    private static function makeDummy():Void {
        dummy=world.createEmptyMovieClip("fixturePlayer",world.getNextHighestDepth());
        dummy._x=450;dummy._y=0;dummy.Z轴坐标=0;dummy.hp=10000;
        dummy.是否为敌人=false;dummy.兵种="主角-男";dummy.version=1000;
        dummy.hp满血值=100000;dummy.等级=20;dummy.重量=60;dummy.躲闪率=999999;dummy.懒闪避=0;
        dummy.防御力=100;dummy.魔法抗性={基础:0};dummy.无敌=false;dummy.NPC=false;dummy.防止无限飞=false;
        dummy.man={无敌标签:false};dummy.shield=new ShieldStack();dummy.damageTakenMultiplier=1;dummy.ti61CrumbleTakenMultiplier=1;
        dummy.dispatcher=new EventDispatcher();dummy.aabbCollider={left:440,right:460,top:-140,bottom:0};TargetCacheManager.addUnit(dummy);
        var body:MovieClip=dummy.createEmptyMovieClip("area",dummy.getNextHighestDepth());
        body.beginFill(0x335566,100);body.moveTo(-20,-140);body.lineTo(20,-140);
        body.lineTo(20,0);body.lineTo(-20,0);body.lineTo(-20,-140);body.endFill();body._visible=false;
        dummy.aabbCollider=new org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider(0,0,0,0);
        dummy.aabbCollider.updateFromUnitArea(dummy);
    }
    private static function isolate(mode:String):Void {
        dummy.hp=0;c.target=null;c.nextSense=c.clock+10000;c.opening=2;
        if(u.__sheriffShieldRush)SheriffShieldRush.cleanup(u.__sheriffShieldRush);
        c.action=null;c.pendingReaction=null;c.reactionUntil=0;
        u.换弹中=false;u.攻击模式=mode;u.根据模式重新读取武器加成(mode);
        FormerSheriffController.animationDone(u);
        u._x=0;u._y=0;u.Z轴坐标=0;u.方向改变("右");
    }
    private static function advance():Void {
        if(finished)return;
        age++;_root.帧计时器.当前帧数++;
        EnhancedCooldownWheel.I().tick();UnitUpdateWheel.I().tick();
        if(age==3) {
            c=u.__formerSheriff;
            trace("FormerSheriffTest Init: ready="+c.ready+" hp="+u.hp+" def="+u.防御力+" frame="+u._currentframe+" state="+u.状态);
            check(c.ready===true && u.__unitInitializedVersion==u.version,"real initializer completed");
            check(u.unitAI==undefined && u.unitAIType=="None","no generic humanoid AI");
            check(u.hasDressup===false && u.hasFixedEquipment===false,"fixed NPC bypasses both costume and equipment-stat projection");
            check(u.魔法抗性.冲==_root.敌人属性表[u.兵种].魔法抗性.冲 && u.魔法抗性.冲>=0,
                "declared monster impact resistance survives legacy base fallback");
            check(u.魔法抗性.首领==_root.敌人属性表[u.兵种].魔法抗性.首领 && u.魔法抗性.首领>0,"boss resistance tag remains on the fixed NPC");
            marks.primaryResistance=u.魔法抗性;
            marks.declaredResistance=_root.敌人属性表[u.兵种].魔法抗性.冲;
            check(u.新版人物文字信息.头顶血槽.血槽底._width>0,"actual shared nameplate and HP bar loaded");
            check(u.icX==1 && u.icY==-155 && u.新版人物文字信息._y==u.icY,"authored overhead anchor and updater cache agree");
            check(c.head._currentframe==1,"fixed helmeted head at spawn");
            check(u.hp>6000 && u.防御力>0 && u.跑X速度>0,"finite configured monster stats without item tables");
            check(u.下装装备==undefined && u.头部装备==undefined && u.装备防御力==0,"armor is visual only and has no item/stat objects");
            check(u.长枪.value.mods==undefined && u.长枪.getData==undefined,"NPC firearm is a lightweight magazine, not BaseItem");
            check(u.hp满血值==Math.floor(4923+(9917-4923)/59*20)*c.tune.loneHealth,"HP comes from level-scaled monster XML and one lone-wolf modifier");
            u.dispatcher.subscribe("death",function():Void{FormerSheriffTest.deaths++;},u);
            u.计算经验值=function():Void{FormerSheriffTest.rewards++;this.已加经验值=true;};
            u.随机掉钱=function():Void{};
            var p:Object=c.tune;
            check(FormerSheriffController.pickStance("兵器",110,p)=="兵器","close hysteresis");
            check(FormerSheriffController.pickStance("长枪",110,p)=="长枪","medium hysteresis");
            check(FormerSheriffController.pickStance("手枪",300,p)=="手枪","far hysteresis");
            check(FormerSheriffController.pickStance("长枪",300,p)=="长枪","far approach hysteresis");
        }
        if(age==8 || age==88)snapshot("opening-"+age);
        if(age==130) {
            showHealthBar();
            check(c.opening==2 && c.action==null,"two opening animations finish once");
            check(u.buffManager.getBuffById("兴奋剂")!=null && u.buffManager.getBuffById("铁布衫")!=null,"permanent opening buffs exist");
            marks.speed=u.行走X速度;marks.defense=u.防御力;marks.gunBullets=bullets;
            trace("FormerSheriffTest Stats20: hp="+u.hp+" maxHP="+u.hp满血值+" attack="+u.空手攻击力+" defense="+u.防御力+" run="+u.跑X速度+" secondLifeRatio="+c.tune.secondLifeRatio);
            check(Math.abs(u.长枪属性.power-u.空手攻击力*c.tune.shotgunPower)<.01,"gun damage follows live monster attack after buffs");
            makeDummy();c.nextSense=0;
        }
        if(age==165) {
            check(u.攻击模式=="手枪","far target selects single pistol");
            check(u.手枪.value.shot>1,"NPC pistol sustains fire after the first shot");
            snapshot("far-pistol");
        }
        if(age==180){dummy._x=u._x+200;dummy.Z轴坐标=u.Z轴坐标;dummy._y=dummy.Z轴坐标;c.nextStance=0;}
        if(age==205){check(u.攻击模式=="长枪","medium selects shotgun");check(bullets>marks.gunBullets,"native firearm controller emits shots");snapshot("medium-shotgun");}
        if(age==220){dummy._x=u._x+45;c.nextStance=0;}
        if(age==245){check(u.攻击模式=="兵器","close selects baton");snapshot("near-baton");}
        if(age==250) {
            check(c.action=="baton","native close attack is active before reaction test");
            u.长枪.value.shot=2;c.nextRoll=0;c.reactionUntil=0;
            u.状态改变("被击");FormerSheriffController.afterHit(u);
            check(c.action=="翻滚换弹","ordinary baton attack yields to the first eligible hit reaction");
        }
        if(age==280) {
            isolate("手枪");c.nextRoll=0;u.长枪.value.shot=3;u.手枪.value.shot=2;u.mp=0;
            marks.hp=u.hp;u.hp-=23;
            var blood:Boolean=_root.血腥开关;_root.血腥开关=false;
            u.损伤值=23;
            u.dispatcher.publish("hit",u,dummy,{击倒率:0,水平击退速度:6,垂直击退速度:3},
                {overlapCenter:{x:u._x,y:u._y-70}},new DamageResult());
            _root.血腥开关=blood;
            check(!u.倒地 && !u.浮空 && u.垂直速度==0,"real hit updater hands physics to custom reaction");
            check(c.action=="翻滚换弹","non-shotgun stagger rolls with missing magazine");
            check(u.hp==marks.hp-23,"reaction keeps triggering damage");
            showHealthBar();
            check(u.新版人物文字信息.头顶血槽._visible && u.新版人物文字信息.头顶血槽.getBounds(u).yMax < -120,
                "real hit bar is visible above the actor after its HP updater resets jitter");
            marks.action=c.action;marks.rollCD=c.nextRoll;
        }
        if(age==288){snapshot("roll-reload");u.状态改变("击倒");FormerSheriffController.afterHit(u);
            check(c.nextRoll==marks.rollCD && c.action==marks.action,"repeat hit cannot restart roll");}
        if(age==330) {
            check(u.长枪.value.shot==0 && u.手枪.value.shot==0,"native roll refills both magazines");
            check(u.mp==0 && inventoryWrites==0,"zero MP and no player inventory consumption");
            isolate("手枪");u.状态改变("击倒");FormerSheriffController.afterHit(u);
            check(c.action=="小跳","full magazines select hop");
            marks.hopX=u._x;marks.hopZ=u.Z轴坐标;
            check(u.man.上下跳移动方向==c.hopDirection,"native up-down hop branch receives NPC lane direction");
        }
        if(age>=330 && age<=342 && age%2==0)snapshot("hop-"+age);
        if(age==350) {
            check(Math.abs(u._x-marks.hopX)<.1 && Math.abs(u.Z轴坐标-marks.hopZ)>=45,"hop leaves attack lane without horizontal travel");
            var savedZ:Number=u.Z轴坐标;
            u.Z轴坐标=398;c.target={Z轴坐标:300};
            check(FormerSheriffController.chooseHopDirection(u)=="上","hop chooses available lane when preferred direction is blocked");
            u.Z轴坐标=savedZ;c.target=null;
        }
        if(age==375) {
            isolate("长枪");c.nextRush=0;u.状态改变("被击");FormerSheriffController.afterHit(u);
            check(u.__sheriffShieldRush!=null,"shotgun hit enters actual rush container");
            check(u.__sheriffShieldRush.npc!=null && u.mp==0,"NPC rush uses explicit control without MP");
            marks.rush=u.__sheriffShieldRush;marks.rushCD=c.nextRush;marks.bullets=bullets;
        }
        if(age==388) {u.状态改变("击倒");FormerSheriffController.afterHit(u);
            check(u.__sheriffShieldRush===marks.rush && c.nextRush==marks.rushCD,"repeat hit cannot restart rush");}
        if(age==416)snapshot("reaction-rush-"+age);
        if(age==480) {
            check(c.action==null && u.__sheriffShieldRush==undefined,"NPC rush completes and restores weapon stance");
            check(bullets>marks.bullets,"native rush emits actual impact parameters");
            check(u.mp==0,"rush completion still has zero MP");
            isolate("长枪");u.长枪.value.shot=2;c.nextRoll=0;
            check(FormerSheriffController.chooseReaction(u)=="roll","rush cooldown falls back to roll");
            c.nextRoll=c.clock+100;
            check(FormerSheriffController.chooseReaction(u)=="hop","both cooldowns fall back to hop");
            marks.hp=u.hp=300;
            for(var j:Number=0;j<4;j++) {
                FormerSheriffController.applyLoneWolf(u,false);
                FormerSheriffController.applyLoneWolf(u,true);
            }
            check(u.hp<=marks.hp,"roster changes never grant repeated current HP");
            ally=world.createEmptyMovieClip("ally",world.getNextHighestDepth());
            ally.hp=100;ally.兵种="敌人-体育老师";ally.是否为敌人=true;
            check(FormerSheriffController.isCombatAlly(u,ally),"living custom ally counts");
            ally.hp=0;check(!FormerSheriffController.isCombatAlly(u,ally),"dead ally does not count");
            ally.hp=100;ally.兵种="商人";check(!FormerSheriffController.isCombatAlly(u,ally),"decorative NPC does not count");
            ally.兵种="敌人-体育老师";ally.aabbCollider={left:0,right:10,top:-100,bottom:0};ally.Z轴坐标=0;TargetCacheManager.addUnit(ally);c.nextSense=0;
        }
        if(age==491) {
            check(c.lone===false,"actual ally cache suppresses lone wolf");
            ally.hp=0;c.nextSense=0;
        }
        if(age==506)check(c.lone===true && u.hp<=marks.hp,"actual ally death restores bonus without free healing");
        if(age==515) {
            isolate("手枪");u.手枪.value.shot=0;u.长枪.value.shot=2;
            dummy.hp=10000;TargetCacheManager.addUnit(dummy);c.nextSense=0;
        }
        if(age>=515 && age<635) {
            dummy._x=u._x+500;dummy.Z轴坐标=u.Z轴坐标+100;dummy._y=dummy.Z轴坐标;
        }
        if(age==520) {
            check(u.攻击模式=="长枪" && (u.换弹中 || u.man.换弹标签),"safe off-lane target triggers missing-gun reload");
            snapshot("safe-reload");
        }
        if(age==635) {
            check(u.长枪.value.shot==0,"authored regular reload completes off lane");
            check(u.mp==0 && inventoryWrites==0,"regular NPC reload consumes no player resource");
        }
        if(age==645) {
            isolate("手枪");
            check(c.opening==2 && u.行走X速度==marks.speed,"stimulant never reapplied");
            // A fractional lane cannot be represented exactly by a MovieClip.
            // This exposed the old landing/airborne oscillation.
            u.Z轴坐标=12.013;u._y=u.Z轴坐标;
            dummy.hp=100000;dummy._x=u._x+180;dummy.Z轴坐标=u.Z轴坐标;dummy._y=dummy.Z轴坐标;
            dummy.aabbCollider=new org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider(dummy._x-20,dummy._x+20,dummy._y-140,dummy._y);
            TargetCacheManager.addUnit(dummy);marks.deathrattleTargetHP=dummy.hp;
            c.tune.phaseTwoRest=100000;
            c.nextRush=c.clock+9999;u.hp=50;u.无敌=true;
            ActualTerminalDamageHandle.getInstance().handleBulletDamage({},dummy,u,null,new DamageResult());
            check(c.phase=="transition" && c.transitionCount==1 && u.hp==1,"real terminal handler is intercepted before zero-HP consumers");
            check(!u.__battleRecord.down && !u._killed && deaths==0 && rewards==0,"no first-life onDown, kill, rewards or death");
            u.hp=-999;u.hp=999;u.状态改变("血腥死");
            u.dispatcher.publish("kill",u);
            check(c.transitionCount==1 && !u._killed && !u.__battleRecord.down,"repeated terminal writes and kill do not bypass transition");
        }
        if(age>645 && c.phase=="transition") {
            if(c.transitionStep=="air" && u._y<u.Z轴坐标-5) {
                marks.realAir=true;
                check(u.__air.running && u.__air.sources.knockback.man===c.fallOwner,
                    "fall source survives native pose replacement at "+age);
            }
            if(c.transitionStep=="land") {
                marks.realLanding=true;
                check(Math.abs(u._y-u.Z轴坐标)<.051 && !u.浮空,"landing slice starts on actual world ground");
            }
            if(c.transitionStep=="up")check(marks.realLanding===true,"get-up follows actual landing");
        }
        if(age>=648 && age<=708 && age%3==0)snapshot("fall-"+age);
        if(age>645 && age<805 && age%15==0) {
            check(deaths==0 && rewards==0 && !u.__battleRecord.down,"transition remains outside death accounting "+age);
            if(c.phase=="transition")check(u.无敌 && u.hp==1,"transition protection "+age);
            if(age==660 || age==690 || age==720 || age==765 || age==795)snapshot("transition-"+age);
        }
        if(age>=660 && age<=760 && age%5==0)snapshot("helmet-"+age);
        if(age==660) {
            var helmet:MovieClip=c.helmet.fragments.helmet1;
            check(helmet && FragmentAnimator.isAnimationRunning(c.helmet.animationId),"helmet uses the shared fragment animator");
            var pausedX:Number=helmet._x,pausedY:Number=helmet._y,pausedR:Number=helmet._rotation;
            var wasPaused:Boolean=_root.暂停;_root.暂停=true;c.helmet.onEnterFrame();_root.暂停=wasPaused;
            check(helmet._x==pausedX && helmet._y==pausedY && helmet._rotation==pausedR,"helmet fragment motion respects game pause");
        }
        if(age==765) {
            var landed:MovieClip=c.helmet.fragments.helmet1;
            check(!FragmentAnimator.isAnimationRunning(c.helmet.animationId),"shared fragment engine reaches its terminal stop");
            check(Math.abs(c.helmet._y+landed._y-12.013)<.051,"helmet settles on the fractional world ground plane");
            marks.helmetRest={x:landed._x,y:landed._y,rotation:landed._rotation};
        }
        // The real rush has carried the fixture actor outside this 500 px host.
        // Follow it with the fixture camera; retain production culling and light gates.
        if(age==800)world._x=200-u._x;
        if(age==815) {
            var resting:MovieClip=c.helmet.fragments.helmet1;
            check(resting._x==marks.helmetRest.x && resting._y==marks.helmetRest.y && resting._rotation==marks.helmetRest.rotation,
                "settled helmet remains still across 50 more native frames");
            trace("FormerSheriffTest Helmet: sharedFragment=true stopped="+!FragmentAnimator.isAnimationRunning(c.helmet.animationId)+" stableFrames=50");
            showHealthBar();
            trace("FormerSheriffTest Transition: phase="+c.phase+" step="+c.transitionStep+" shield="+u.__sheriffShieldRush.phase+" state="+u.状态);
            check(c.phase==2 && c.phaseTwoEntered && c.transitionCount==1,"one complete native phase-two handoff");
            check(dummy.hp<marks.deathrattleTargetHP,"deathrattle traverses real collision and damage settlement");
            check(marks.deathrattleTargetHP-dummy.hp>100,"deathrattle deals scaled damage rather than one-point fallback");
            check(marks.realAir && marks.realLanding,"death transition uses the shared airborne integrator and landing callback");
            check(c.helmetFlown && c.helmet._parent===world && c.action=="持盾待机","helmet detached and authored hairstyle frame exposed");
            check(u.__sheriffShieldRush==undefined && c.action=="持盾待机" && u.man.盾具!=undefined,"phase two holds unfolded shield");
            check(u.hp>0 && !u.无敌,"phase two is alive and no longer transition-invulnerable");
            check(deaths==0 && rewards==0 && !u.__battleRecord.down,"no premature settlement after handoff");
            check(dressupCalls==0 && u.dressupRegistry==undefined,"all native poses and shield rush use zero runtime dressup calls");
            check(u.新版人物文字信息._y==-155 && u.icY==-155,"HP updates and phase transition preserve overhead nameplate");
            trace("FormerSheriffTest Fixed Art: dressupCalls="+dressupCalls+" nameplateY="+u.icY);
            check(EquipmentLightBridge.isDrawn(c.light),"shield retains deployed equipment-light eligibility");
            snapshot("phase-two-held");
        }
        if(age==848 || age==905 || age==1023) {
            check(EquipmentLightBridge.isDrawn(c.light) && c.light.lightBeam._visible===true,
                "same shield light remains visible through combat and reload at "+age);
        }
        if(age==848)snapshot("p2-bash");
        if(age==905)snapshot("p2-knife");
        if(age==1023)snapshot("p2-reload");
        if(age==1214)snapshot("p2-death-fold");
        if(age==830) {
            c.tune.phaseTwoRest=4;c.phaseTwoReadyAt=c.clock;c.nextSense=c.clock+10000;
            dummy.hp=100000;dummy._x=u._x+60;dummy.Z轴坐标=u.Z轴坐标;
            dummy._y=dummy.Z轴坐标;dummy.aabbCollider.updateFromUnitArea(dummy);TargetCacheManager.addUnit(dummy);
            c.target=dummy;marks.phaseTwoHits=c.phaseTwoHits||0;
            marks.phaseTwoHP=u.hp;
            marks.phaseTwoTargetHP=dummy.hp;
        }
        if(age==955) {
            check(c.phaseTwoHits-marks.phaseTwoHits==4,"close bash then three knife impacts on authored attack frames");
            check(dummy.hp<marks.phaseTwoTargetHP-100,"phase-two bash and knife pass real collision and armor settlement");
            check(u.hp==marks.phaseTwoHP && c.transitionCount==1,"phase-two attacks never refill life or repeat transition");
            c.target=null;dummy.hp=0;c.nextSense=c.clock+10000;
            marks.pistolBullets=bullets;u.手枪.value.shot=5;
            FormerSheriffController.mountPhaseTwo(u,"持盾射击");
        }
        if(age==1075) {
            check(bullets-marks.pistolBullets==3,"partially used magazine fires exactly its remaining three rounds");
            check(u.手枪.value.shot==0 && c.phaseTwoReloads==1,"single-hand magazine commit happens once before stow");
            check(c.action=="持盾待机" && !u.换弹中,"pistol reload and stow return to common guard");
            check(u.mp==0 && inventoryWrites==0,"phase-two firearm consumes neither MP nor player stock");
            c.nextRush=0;c.reactionUntil=0;
            u.状态改变("被击");FormerSheriffController.afterHit(u);
            check(c.action!="rush","phase-two stagger alone does not trigger shield rush");
            u.状态改变("击倒");FormerSheriffController.afterHit(u);
            check(c.action=="rush" && u.__sheriffShieldRush.npc.startHeld,"knockdown triggers already-unfolded NPC rush");
            marks.rushCooldown=c.nextRush;
        }
        if(age==1080) {
            u.状态改变("击倒");FormerSheriffController.afterHit(u);
            check(c.nextRush==marks.rushCooldown,"repeated hits do not restart phase-two rush or its cooldown");
        }
        if(age==1200) {
            check(c.action=="持盾待机" && u.__sheriffShieldRush==undefined,"phase-two rush cleans effects and returns to unfolded guard");
            c.tune.deathFoldChance=1;
            marks.killCredits=0;
            dummy.dispatcher.subscribe("enemyKilled",function():Void{FormerSheriffTest.marks.killCredits++;},dummy);
            // The production melee producer publishes death directly after hit.
            // Running only a synthetic kill event missed this cleanup ordering.
            var lethal:Object=BulletFactory.createSettlementBullet({子弹种类:"近战子弹",伤害类型:"真伤",
                子弹威力:10000000,霰弹值:1,击倒率:1,水平击退速度:4,垂直击退速度:4},dummy);
            u.无敌=false;u.man.无敌标签=false;u.防止无限飞=false;
            BulletQueueProcessor.injectHit(lethal,dummy,u,u._x,u._y-70,1);
            check(c.finalDeath && c.deathFolded && !c.finalFinished,"terminal HP chooses one collapsed-shield death variant");
            check(u.hp==1 && deaths==0 && marks.killCredits==0 && c.thinker._parent===u,
                "real melee settlement cannot prematurely publish death or remove final-fall owner");
            u.dispatcher.publish("kill",u);u.hp=999;
            check(u.hp==1 && c.finalFatalHP<=0 && c.transitionCount==1,"final terminal writes cannot resurrect or repeat the first-life handoff");
        }
        if(age>1200 && age<1260 && !c.finalFinished) {
            check(c.thinker._parent===u && u.hp==1 && deaths==0 && u.无敌,
                "terminal animation retains its owner before actual landing at "+age);
        }
        if(age==1203)check(c.finalShield.fragments.shield1!=undefined,"native falling shield export attaches after the handoff frame");
        if(age==1270) {
            check(c.finalFinished && deaths==1 && rewards==1,"final landing reaches shared death and reward settlement exactly once");
            check(u.hp<=0 && marks.killCredits==1,"native final landing publishes one delayed killer credit");
            u.dispatcher.publish("kill",u);u.死亡检测();
            check(deaths==1 && rewards==1 && marks.killCredits==1,"duplicate terminal entry cannot settle twice");
            check(c.finalShield.fragments.shield1._currentframe==15,"collapse branch reaches its native gun endpoint");
            check(inventoryWrites==0 && dressupCalls==0,"complete two-phase lifecycle has no player inventory or dressup calls");
            marks.second=world.attachMovie(FormerSheriffController.KIND,"secondSheriff",world.getNextHighestDepth(),
                {_x:0,_y:0,等级:20,是否为敌人:true,名字:"前治安官",魔法抗性:{冲:42},前治安官参数:{deathFoldChance:0}});
        }
        if(age==1280) {
            var second:MovieClip=marks.second;var context:Object=second.__formerSheriff;
            check(second.魔法抗性.冲==42,"explicit encounter resistance overrides only its own monster profile");
            trace("FormerSheriffTest Resistance Isolation: template="+_root.敌人属性表[FormerSheriffController.KIND].魔法抗性.冲+
                " original="+marks.primaryResistance.冲+" second="+second.魔法抗性.冲+" expected="+marks.declaredResistance);
            check(_root.敌人属性表[FormerSheriffController.KIND].魔法抗性.冲==marks.declaredResistance &&
                marks.primaryResistance.冲==marks.declaredResistance,
                "one encounter override cannot mutate the shared template or another sheriff");
            marks.secondContext=context;context.phase=2;context.helmetFlown=true;context.target=null;
            context.nextSense=context.clock+10000;
            FormerSheriffController.phaseTwoGuard(second);
            second.hp=0;
            second.计算经验值=function():Void{this.已加经验值=true;};
            FormerSheriffController.beginFinalDeath(second);
            check(context.finalDeath && !context.deathFolded,"expanded-shield variant is independently selectable");
        }
        if(age==1350) {
            trace("FormerSheriffTest Second Death: finished="+marks.secondContext.finalFinished+" step="+marks.secondContext.finalStep+" age="+marks.secondContext.age+" frame="+marks.secondContext.finalShield.fragments.shield1._currentframe+" hp="+marks.secondContext.hp);
            check(marks.secondContext.finalFinished && marks.secondContext.finalShield.fragments.shield1._currentframe==1,
                "expanded-shield death reaches the same terminal lifecycle without collapsing");
            trace("FormerSheriffTest Native Transition Complete: "+(c.phaseTwoEntered?1:0));finish();
        }
        if(age>1400){check(false,"behavior watchdog");finish();}
    }
    private static function snapshot(id:String):Void {
        if(!u.man || _root.formerSheriffCapture!==true)return;
        // Keep the trace panel bounded: it lays out every pixel line in CS6.
        // Dense snapshots can make the test player slower than its watchdog.
        var selected:String=",phase-two-held,p2-bash,p2-knife,p2-reload,p2-death-fold,";
        if(selected.indexOf(","+id+",")<0)return;
        // Capture after the current timeline and the fixed head state settle.
        var request:Object={name:id};
        request.timer=setInterval(function(item:Object):Void {
            clearInterval(item.timer);FormerSheriffTest.captureSnapshot(item.name);
        },1,request);
    }
    private static function showHealthBar():Void {
        // Drive the real damage-display consumer, including its coordinate jitter
        // and the HP updater's restoration. No fake bar or repositioned overlay.
        BloodBarEffectHandler.updateStatus(u);
        var width:Number=u.新版人物文字信息.头顶血槽.血槽底._width*u.hp/u.hp满血值;
        InformationComponentUpdater.onHPChanged(u,width);
    }
    private static function captureSnapshot(id:String):Void {
        if(!u.man)return;
        if(id.indexOf("helmet-")==0) {
            var detail:BitmapData=new BitmapData(420,250,true,0);
            detail.draw(c.helmet,new Matrix(1,0,0,1,210,190),null,"normal",null,true);
            emitSnapshot(detail,id);return;
        }
        var bitmap:BitmapData=new BitmapData(420,350,true,0);
        // Actor-local capture removes only world travel, keeps real registration,
        // layers, costume, shadow and the real root/man scale.
        var m:Matrix=u.transform.matrix.clone();m.tx=170;m.ty=290+u._y-u.Z轴坐标;
        bitmap.draw(u,m,null,"normal",null,true);
        var helmet:MovieClip=c.helmet;
        if(helmet && helmet._parent) {
            var h:Matrix=helmet.transform.matrix.clone();h.tx+=170-u._x;h.ty+=290-u.Z轴坐标;
            bitmap.draw(helmet,h,null,"normal",null,true);
        }
        emitSnapshot(bitmap,id);
    }
    private static function emitSnapshot(bitmap:BitmapData,id:String):Void {
        var output:String="[ASSET_BITMAP_BEGIN] sheriff-"+id+" "+bitmap.width+" "+bitmap.height+"\n";
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
        trace(output+"[ASSET_BITMAP_END] sheriff-"+id);
        bitmap.dispose();
    }
    private static function hex(pixel:Number):String {
        var low:String=(pixel&65535).toString(16);
        while(length(low)<4)low="0"+low;
        return ((pixel>>>16)&65535).toString(16)+low;
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        delete driver.onEnterFrame;
        if(u.__formerSheriff)delete u.__formerSheriff.thinker.onEnterFrame;
        _root.暂停=true;u.stop();u.man.stop();delete u.man.onEnterFrame;
        trace("FormerSheriffTest Tests Passed: "+pass);
        trace("FormerSheriffTest Tests Failed: "+fail);
        _root.formerSheriffTestComplete();
    }
}
