import org.flashNight.arki.unit.Action.Skill.SheriffShieldRush;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.component.Damage.LifeStealDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.SpeedDeriveInitializer;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntime;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.skill.SkillResourceService;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.component.Shield.Shield;
import org.flashNight.arki.hud.PlayerHudShieldProjection;
import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightDefense;
import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/** Real XML, production F/routing/buff/movement and published native SWF.
 * Keyboard state and final bullet sink are injected. No real saves or rewards.
 */
class org.flashNight.arki.unit.Action.Skill.ShieldRushTest {
    private static var passed:Number,failed:Number,caseId:Number,age:Number,total:Number;
    private static var world:MovieClip,library:MovieClip,u:MovieClip,driver:MovieClip;
    private static var loader:MovieClipLoader,item:Object,ctx:Object,shots:Array,saved:Object;
    private static var watched:Object,finished:Boolean;
    private static var lightRef:Object,lightFrames:Number;
    private static var hitFactory:AABBColliderFactory;
    private static function check(ok:Boolean,name:String):Void {
        if(ok)passed++;else {failed++;trace("ShieldRushTest FAIL: "+name);}
    }
    private static function near(a:Number,b:Number):Boolean {return Math.abs(a-b)<.1;}
    public static function runAllTests():Void {
        passed=0;failed=0;caseId=0;total=0;finished=false;
        lightFrames=0;
        hitFactory=new AABBColliderFactory(1);
        saved={world:_root.gameworld,clock:_root.帧计时器,pause:_root.暂停,control:_root.控制目标,
            collision:_root.collisionLayer,shoot:_root.子弹区域shoot传递,skin:_root.装备引用配置,shadow:_root.是否阴影,depth:DepthManager.instance};
        world=_root.createEmptyMovieClip("__shieldRushWorld",_root.getNextHighestDepth());_root.gameworld=world;
        world._x=250;world._y=220; // The focused stage is 500px wide; keep both directions in view.
        _root.帧计时器={当前帧数:0,添加冷却任务:function(n:Number,f:Function):Void {}};
        _root.当前玩家总数=1;_root.暂停=false;_root.武器技能键=70;
        EquipmentLightBridge.disconnect();
        var caps:Object={equipmentLights:2};caps["native"]=true;EquipmentLightBridge.configure(caps);
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach};
        _root.collisionLayer={hitTest:function(x:Number,y:Number,shape:Boolean):Boolean {
            return ShieldRushTest.caseId==7 || (ShieldRushTest.caseId==17 && x>=40 && x<=48)
                || (ShieldRushTest.caseId==24 && y<=-8 && y>=-16);
        }};
        _root.子弹区域shoot传递=function(p:Object):Void {
            // Exercise production inheritance after real skill-mode routing;
            // the previous no-op bonus stub hid the dropped gun effect.
            BulletInitializer.inheritShooterAttributes(p,ShieldRushTest.u);
            ShieldRushTest.checkLifeSteal(p);
            // Consume the actual native swept rectangle with the production
            // AABB factory, then check thin targets along the high-speed path.
            var bullet={_x:p.shootX,_y:p.shootY};
            var collider=ShieldRushTest.hitFactory.createFromBullet(bullet,p.区域定位area);
            var b:Object={xMin:collider.left,xMax:collider.right,yMin:collider.top,yMax:collider.bottom};
            if(ShieldRushTest.caseId==8 || ShieldRushTest.caseId==9) {
                for(var targetIndex:Number=0;targetIndex<ShieldRushTest.watched.targetHits.length;targetIndex++) {
                    var tx:Number=(100+350*targetIndex)*(ShieldRushTest.caseId==8?-1:1);
                    var target:AABBCollider=new AABBCollider(tx-.5,tx+.5,b.yMin+1,b.yMax-1);
                    if(collider.checkCollision(target,0).isColliding)ShieldRushTest.watched.targetHits[targetIndex]=true;
                }
            }
            ShieldRushTest.shots.push({power:p.子弹威力,vampirism:p.吸血,x:ShieldRushTest.u._x,kind:p.子弹种类,
                z:p.shootZ,bounds:b,zRange:p.Z轴攻击范围,age:ShieldRushTest.ctx.tickId,
                phase:ShieldRushTest.ctx.phase,direction:ShieldRushTest.ctx.direction});
            ShieldRushTest.hitFactory.releaseCollider(collider);
        };
        Mover.init();
        driver=_root.createEmptyMovieClip("__shieldRushDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            if (++ShieldRushTest.total>3600) {ShieldRushTest.check(false,"watchdog");ShieldRushTest.finish();}
        };
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            ShieldRushTest.check(ok,"load actual shotgun XML");
            if(!ok){ShieldRushTest.finish();return;}
            var rows:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(this.firstChild).item);
            for(var i:Number=0;i<rows.length;i++)if(rows[i].name=="特勤霰弹枪")ShieldRushTest.item=rows[i];
            ShieldRushTest.loadArt();
        };
        xml.load("../data/items/武器_长枪_霰弹枪.xml");
    }
    private static function loadArt():Void {
        check(item.skill.skillname==SheriffShieldRush.NAME && item.skill.skillLocked===true,"real locked skill descriptor");
        check(item.data.power==350 && item.data.modslot==0 && item.skill.parameters.hitInterval==3 && item.skill.parameters.speedBonus==2 && item.skill.parameters.maxRushLoops==3 && item.skill.parameters.laneSpeedRatio==.5 && item.skill.parameters.rushFrames==undefined && item.skill.parameters.chargedFrames==undefined,"real XML uses +2, three full loops and the existing half-speed lane steering convention");
        var tuning:Object=SheriffShieldRush.tuning(item.skill.parameters);
        check(SheriffShieldRush.chargeLevel(0,tuning)==1 && SheriffShieldRush.chargeLevel(17,tuning)==1,"tap and charge below 18 frames get one loop");
        check(SheriffShieldRush.chargeLevel(18,tuning)==2 && SheriffShieldRush.chargeLevel(35,tuning)==2,"18 through 35 charge frames get two loops");
        check(SheriffShieldRush.chargeLevel(36,tuning)==3,"full 36-frame charge gets exactly three loops");
        check(item.data.vampirism==3,"real intrinsic siphon magazine supplies three percent gun lifesteal");
        var gunActor:Object={被动技能:{},长枪属性:item.data};
        check(ShootInitCore.calculateWeaponPower(gunActor,"长枪",350,true)==350,"ordinary unmodified shotgun still uses intrinsic 350 gun power");
        gunActor.被动技能={枪械攻击:{启用:true,等级:10},枪械师:{启用:true,等级:10}};
        gunActor.长枪额外攻击加成倍率=.5;
        check(near(ShootInitCore.calculateWeaponPower(gunActor,"长枪",1064,true),2743.2),"ordinary +13 ray shooting retains enhancement, gun passives and long-gun bonuses");
        library=world.createEmptyMovieClip("library",1);
        loader=new MovieClipLoader();
        var listener:Object={};
        listener.onLoadInit=function(mc:MovieClip):Void {
            ShieldRushTest.u=mc.createEmptyMovieClip("actor",mc.getNextHighestDepth());
            ShieldRushTest.prepare();
        };
        listener.onLoadError=function(mc:MovieClip,error:String):Void {ShieldRushTest.check(false,"SWF "+error);ShieldRushTest.finish();};
        loader.addListener(listener);loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",library);
    }
    private static function prepare():Void {
        DepthManager.instance=new DepthManager(library,100,1048575,4);
        check(DepthManager.instance.calibrate(-1000,1000),"real depth manager for diagonal movement");
        u.方向改变=_root.主角函数.方向改变;
        checkFacingHelper();
        u.状态改变=function(state:String):Void {
            // Normal poses are distinct timeline instances in game. Preserve
            // that identity instead of reusing the routed dynamic 'man' path.
            if(this.man.getDepth()<0)this.man.swapDepths(0);
            this.man.removeMovieClip();this.container.removeMovieClip();
            delete this.man; // Release the normal-pose alias before native attachMovie binds man.
            this.状态=state;
            if(state=="战技") {
                this.createEmptyMovieClip("container",1);
                this.container._x=3.4;this.container._y=-62.35;
                this.container._xscale=27.708435;this.container._yscale=27.690125;
            } else {
                this.man=this.createEmptyMovieClip("__normalMan"+this.version,0);
                this.man.swapDepths(-16383);
                ShieldRushTest.normalGun(this);
            }
        };
        u.动画完毕=function():Void {this.状态改变(this.hp>0 ? this.攻击模式+"站立" : "血腥死");};
        u.根据模式重新读取武器加成=_root.主角函数.根据模式重新读取武器加成;
        u.UpdateBigSmallState=function(big:String,small:String):Void {this.fixtureBig=big;};
        u.aabbCollider={updateFromUnitArea:function(unit:MovieClip):Void {unit.colliderUpdates++;}};
        u.装载主动战技=_root.主角函数.装载主动战技;
        u.释放主动战技=_root.主角函数.释放主动战技;
        var fields:Array=["身体","上臂","左下臂","右下臂","左手","右手","屁股","左大腿","右大腿","小腿","脚"];
        for(var i:Number=0;i<fields.length;i++)u[fields[i]]="男变装-Codex-重装特勤"+fields[i];
        u.左手="变装-Codex-重装特勤左手";u.右手="变装-Codex-重装特勤右手";u.脚="变装-Codex-重装特勤战靴";
        u.面具="变装-Codex-重装特勤头盔";u.长枪_装扮=item.data.dressup;
        _root.主动战技函数.长枪.特勤盾冲.载入=function(man:MovieClip):Void {
            SheriffShieldRush.loaded(man);
            // One owner for the injected keyboard/clock, before the first native
            // onEnterFrame can latch the real (unpressed) hardware key.
            delete man.onEnterFrame;
        };
        check(SkillResourceService.weapon({mp:0},{战技函数:{原子释放:true},消耗mp:30},{}).state=="ready","dynamic atomic skill still bypasses fixed MP projection");
        startCase();
        driver.onEnterFrame=function():Void {
            try {ShieldRushTest.advance();}
            catch(error){ShieldRushTest.check(false,"unexpected "+error);ShieldRushTest.finish();}
        };
    }
    private static function checkFacingHelper():Void {
        var rootDirection=_root.方向,rootOld=_root.旧方向,rootScale=_root.myxscale;
        _root.方向="root-sentinel";_root.旧方向="old-sentinel";_root.myxscale=999;
        var a:MovieClip=world.createEmptyMovieClip("__facingA",world.getNextHighestDepth());
        var b:MovieClip=world.createEmptyMovieClip("__facingB",world.getNextHighestDepth());
        a.方向改变=b.方向改变=_root.主角函数.方向改变;
        a.createEmptyMovieClip("新版人物文字信息",1);b.createEmptyMovieClip("新版人物文字信息",1);
        a.方向="右";a.myxscale=73;b.方向="左";b.myxscale=91;
        a.方向改变("左");b.方向改变("右");
        check(a.方向=="左" && a.旧方向=="右" && a._xscale==-73 && a.新版人物文字信息._xscale==-100,"real facing helper updates the receiving unit and nameplate");
        check(b.方向=="右" && b.旧方向=="左" && b._xscale==91 && b.新版人物文字信息._xscale==100,"real facing helper keeps separate unit scale and direction");
        check(_root.方向=="root-sentinel" && _root.旧方向=="old-sentinel" && _root.myxscale==999,"real facing helper cannot read or overwrite root facing fields");
        a.锁定方向=true;a.方向改变("右");
        check(a.方向=="左" && a._xscale==-73,"real facing helper obeys direction lock");
        a.锁定方向=false;a.飞行浮空=true;a.方向改变("右");
        check(a.方向=="左" && a._xscale==-73,"real facing helper obeys flight lock");
        a.removeMovieClip();b.removeMovieClip();
        _root.方向=rootDirection;_root.旧方向=rootOld;_root.myxscale=rootScale;
    }
    private static function startCase():Void {
        trace("ShieldRushTest Case: "+caseId);
        age=0;shots=[];watched={lightContinuous:true,lightProperties:true,layerOrder:true,shadowStable:true,runTicks:0,cycles:0,poseCadence:true};ctx=null;
        watched.targetHits=caseId==8?[false,false,false,false,false]:[false,false,false,false,false,false];
        world._x=250;world._y=220;
        _root.是否阴影=caseId!=13;
        u._x=0;u._y=0;u.Z轴坐标=0;u.hp=500;u.mp=500;
        u._xscale=caseId==8 ? -100 : 100;u.方向=caseId==8 ? "左" : "右";
        u.myxscale=100;u.锁定方向=false;u.飞行浮空=false;
        u.上行=u.下行=u.左行=u.右行=false;
        u.行走X速度=(caseId==8 ? 15 : (caseId==9||caseId==17 ? 20 : 4));
        u.奔跑速度倍率=2;_root.控制目标=u._name;
        SpeedDeriveInitializer.initialize(u);
        watched.runSpeed=u.跑X速度;
        u.攻击模式="长枪";u.倒地=false;u.浮空=false;u.换弹中=false;u.刚体=false;
        u.性别=caseId==9 ? "女" : "男";u.colliderUpdates=0;
        u.长枪={name:item.name,value:{level:1,shot:0,mods:[]}};u.长枪数据=item;
        // Zero, invalid and extreme enhanced gun power must not gate or scale
        // this defensive skill. Do not mutate the shared real XML definition.
        u.长枪属性={power:caseId==0?0:(caseId==1?Number("invalid"):(caseId==2?999999:item.data.power))};
        u.主动战技={};u.syncRefs={};u.被动技能={枪械攻击:{启用:true,等级:30}};
        u.长枪额外攻击加成倍率=99;u.damageTakenMultiplier=1;
        u.基础吸血=caseId==1||caseId==10||caseId==13?2:0;
        u.长枪吸血=caseId==10?Number("invalid"):Number(item.data.vampirism);
        u.基础伤害类型="物理";u.基础毒=0;u.基础击溃=0;u.基础命中加成=0;u.基础斩杀=0;u.基础命中率=100;
        u.根据模式重新读取武器加成("长枪");
        watched.vampirism=caseId==10?2:3+u.基础吸血;
        u.dispatcher=new EventDispatcher();u.buffManager=new BuffManager(u,{});
        u.version=caseId+1;u.躲闪率=3;u.闪避加成=0;
        u.状态改变("长枪站立");
        lightRef={自机:u,装备类型:"长枪",生命周期函数列表:[]};
        check(EquipmentLightController.initialize(lightRef,item.lifecycle.attr_equipmentLight.init.initParam),"case "+caseId+" real XML binds existing gun light");
        check(lightCount()==1 && lightRef.lightBeam===u.长枪_引用.装备光束,"case "+caseId+" normal gun has one native light");
        check(EquipmentLightDefense.getActiveBonus(u)==20 && near(lightRef.equipmentLight.energy,1.45),"case "+caseId+" existing flashlight properties");
        watched.lightId=lightRef.equipmentLight.id;
        u.防御力=caseId==16?Number("invalid"):(caseId==25?0:(caseId==26?-50:(caseId==27?Number.POSITIVE_INFINITY:600+caseId)));
        watched.defense=caseId==16||caseId>=25?0:600+caseId;
        u.shield=AdaptiveShield.createDormant("shield-rush-test");u.shield.setOwner(u);
        u.hp满血值=500;
        if(caseId==14) {
            watched.external=Shield.createTemporary(200,75,500,"external shield");
            u.shield.addShield(watched.external,true);
        }
        u.装载主动战技(item.skill,"长枪");_root.控制目标=u._name;
        u.__weaponSkillInputConsumed=false;ManualCooldownService.reset(ManualCooldownService.WEAPON_SKILL_KEY);
        if(caseId==9) {
            var fs:Array=["身体","上臂","左下臂","右下臂","屁股","左大腿","右大腿","小腿"];
            for(var j:Number=0;j<fs.length;j++)u[fs[j]]="女变装-Codex-重装特勤"+fs[j];
        }
        if(caseId==10)_root.技能函数.霸体减伤(u,80,500,"external");
        if(caseId==11) {
            u.mp=29;
            check(SkillResourceService.weapon(u,u.主动战技.长枪,{}).state=="blocked","HUD exposes fixed MP refusal for atomic skill");
            var denied:Object=WeaponSkillInputService.updateUnit(u,true,true,null,++_root.帧计时器.当前帧数);
            check(!denied.released && u.mp==29 && !u.__sheriffShieldRush,"MP refusal pays no resources");
            check(ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY),"MP refusal starts no cooldown");
            nextCase();return;
        }
        if(caseId==18) {
            u.行走X速度=Number("invalid");
            var invalidSpeed:Object=WeaponSkillInputService.updateUnit(u,true,true,null,++_root.帧计时器.当前帧数);
            check(!invalidSpeed.released && u.mp==500 && !u.__sheriffShieldRush,"invalid running speed pays no resources and creates no unbounded movement");
            check(u.状态=="长枪站立" && ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY),"invalid speed leaves normal action and cooldown intact");
            nextCase();return;
        }
        if(caseId==12)RoutingRuntime.setAttachMovieAdapterForTest({attachMovie:function(parent,linkage,name,depth,initObj):MovieClip{return undefined;}});
        var result:Object=WeaponSkillInputService.updateUnit(u,true,true,null,++_root.帧计时器.当前帧数);
        if(caseId==12) {
            RoutingRuntime.clearAttachMovieAdapterForTest();
            check(!result.released && u.mp==500 && !u.__sheriffShieldRush,"missing published linkage pays nothing");
            check(u.状态=="长枪站立","missing linkage restores ordinary action");
            nextCase();return;
        }
        check(result.released && result.startSharedCooldown && u.mp==470,"case "+caseId+" real F entry pays MP once");
        check(u.man._totalframes==152,"case "+caseId+" published action includes all stride-specific brake branches");
        ctx=u.__sheriffShieldRush;
        check(ctx!=undefined && u.状态=="战技","case "+caseId+" production container routing");
        if(!ctx){finish();return;}
        check(ctx.defenseAtCast==watched.defense,"case "+caseId+" damage snapshots defense before routing and ignores gun power and passives");
        check(u.吸血==u.基础吸血 && ctx.weaponVampirism==(caseId==10?0:3),"case "+caseId+" real routing removes gun bonus from actor while this cast preserves its gun lifesteal");
        ctx.startX=u._x;
    }
    private static function advance():Void {
        if(finished)return;
        if(watched.casePending){startCase();return;}
        if(watched.returnWaiting) {
            if(!lightRef.lightBeam._visible || lightCount()!=1)trace("ShieldRushTest RETURN GAP: case="+caseId+" man="+u.man+" depth="+u.man.getDepth()+" beam="+lightRef.lightBeam+" shown="+lightRef.lightBeam._visible+" claim="+(lightRef.lightBeam._cf7EquipmentLightOwner===lightRef)+" target="+u.长枪_引用+" count="+lightCount());
            check(lightRef.lightBeam._visible && lightCount()==1,"case "+caseId+" gun light survives deferred load without a dark return frame");
            nextCase();return;
        }
        if(++total>3600){check(false,"case timeout");finish();return;}
        age++;
        if(age==1) {
            delete u.man.onEnterFrame;
            check(near(ctx.speed,watched.runSpeed+2),"case "+caseId+" real derived running speed receives flat +2");
            check(Math.abs(ctx.man.肢体2._x-72.53116)<.06 && Math.abs(ctx.man.肢体18._x+86.50562)<.06,
                "case "+caseId+" opening feet match the native aiming stance without a relaxed-pose jump");
            check(playerShadowMatches(u.man.接地阴影),"case "+caseId+" published shadow matches ordinary player unit-space bounds and origin");
            var oldXScale:Number=u._xscale,oldYScale:Number=u._yscale;
            u._xscale=oldXScale*.75;u._yscale=oldYScale*1.25;
            var groundBounds:Object=u.man.接地阴影.getBounds(world);
            check(near(groundBounds.xMax-groundBounds.xMin,66.04772*Math.abs(u._xscale)/100) && near(groundBounds.yMax-groundBounds.yMin,26.87971*Math.abs(u._yscale)/100),"case "+caseId+" parent scaling and facing apply to shadow exactly once");
            u._xscale=oldXScale;u._yscale=oldYScale;
            check(u.man.盾具._totalframes==15,"case "+caseId+" deferred transform child loaded");
            check(u.man.__sheriffRushToken===ctx,"case "+caseId+" actual first-frame bridge ran");
            check(u.man.肢体10.挂点.装扮!=undefined,"case "+caseId+" standard dressed body holder loaded");
            if(caseId==0||caseId==9)capture("rush-"+caseId+"-entry");
            observeLight();
        }
        if(age==2) {
            u.防御力=9999; // Neither damage nor shield may reread later defense.
            if(caseId==2)u.行走X速度=50; // Charge must retain the release-time speed snapshot.
            if(caseId==2)u.长枪吸血=99; // The cast retains the original gun projection.
            if(caseId==3){u.吸血=20;watched.vampirism=20;} // Preserve stronger live effects.
            if(caseId==14){u.基础吸血=4;u.吸血=4;watched.vampirism=7;}
        }
        _root.帧计时器.当前帧数++;
        var held:Boolean=caseId!=0 && caseId!=21 && !(caseId==2 && age>34);
        steeringInput();
        if(caseId==3 && age==8) {
            _root.暂停=true;var oldAge:Number=ctx.age;
            u.左行=true;
            SheriffShieldRush.tick(u.man,false);
            check(ctx.age==oldAge && !ctx.released && u.方向=="右","pause freezes art, facing and key release");
            u.左行=false;
            _root.暂停=false;
        }
        if((caseId==4||caseId==5||caseId==6) && ctx.phase=="hold") {
            check(u.man.刚体标签!=undefined && near(u.damageTakenMultiplier,.5),"guard installs real buff and scoped poise");
            if(caseId==4){u.刚体=true;u.hp=0;}
            if(caseId==5)u.长枪={name:"other"};
            if(caseId==6)u.状态改变("被击");
        }
        if(caseId==15 && ctx.phase=="hold") {
            _root.gameworld=_root.createEmptyMovieClip("__otherShieldRushWorld",_root.getNextHighestDepth());
        }
        var before:String=ctx.phase;
        if(before=="brake" && ctx.age==0) {
            watched.stopPose=[];
            for(var stopIndex:Number=0;stopIndex<21;stopIndex++) {
                watched.stopPose.push((stopIndex==13?ctx.man.盾具:ctx.man["肢体"+stopIndex]).transform.matrix);
            }
        }
        if(!ctx.cleaned)SheriffShieldRush.tick(ctx.man,held);
        if(before=="rush") {
            watched.runTicks++;
            watched.poseCadence=watched.poseCadence && ctx.man._currentframe==20+watched.runTicks%16;
            if(watched.runTicks%16==0)watched.cycles++;
        }
        if(caseId==19 && !ctx.cleaned) {
            var expected:String=u.右行?"右":"左";
            check(u.方向==expected && ctx.direction==expected && (u._xscale<0)==(expected=="左"),"all-phase steering uses real player facing and mirrors the whole action");
            watched["steered_"+before]=true;
        }
        if(caseId==23 && before=="rush")check(u.方向==(watched.runTicks<=8?"右":"左"),"direction lock is respected, then steering resumes");
        // Follow the actor like the game camera; 760/960-unit high-speed cases
        // otherwise leave this 500px fixture and correctly cull their lights.
        world._x=250-u._x;
        world._y=220-u._y;
        if(!ctx.cleaned)observeLight();
        if(ctx.phase=="brake" && ctx.age==1) {
            var continuousStop:Boolean=true;
            for(var stopPart:Number=0;stopPart<21;stopPart++) {
                var oldMatrix:Matrix=watched.stopPose[stopPart];
                var nowMatrix:Matrix=(stopPart==13?ctx.man.盾具:ctx.man["肢体"+stopPart]).transform.matrix;
                continuousStop=continuousStop && near(oldMatrix.a,nowMatrix.a) && near(oldMatrix.b,nowMatrix.b)
                    && near(oldMatrix.c,nowMatrix.c) && near(oldMatrix.d,nowMatrix.d)
                    && near(oldMatrix.tx,nowMatrix.tx) && near(oldMatrix.ty,nowMatrix.ty);
            }
            check(continuousStop,"case "+caseId+" brake begins at the exact last displayed stride without a pose jump");
        }
        if(ctx.phase=="close" && ctx.age>0 && !ctx.cleaned) {
            check(ctx.man.盾具._currentframe==16-ctx.age,"case "+caseId+" fold frame "+ctx.age+" is actually displayed");
            if((caseId==0||caseId==9) && (ctx.age==5||ctx.age==10||ctx.age==15))capture("rush-"+caseId+"-return-"+ctx.age);
            if(ctx.age==15) {
                watched.endpointRendered=true;
                check(ctx.man._currentframe==56 && ctx.man.盾具._currentframe==1,"case "+caseId+" folded endpoint remains alive for a rendered frame");
                // Independently read from player XFL combat-leg frame 0. The
                // rejected relaxed preview stance was x=30.43 / -52.57 here.
                check(Math.abs(ctx.man.肢体2._x-72.53116)<.06 && Math.abs(ctx.man.肢体18._x+86.50562)<.06,
                    "case "+caseId+" final feet match the actual combat stance rather than web relaxed legs");
            }
        }
        u.buffManager.update(1);
        u.shield.update(1);
        if(caseId==15 && _root.gameworld!==world) {
            _root.gameworld.removeMovieClip();_root.gameworld=world;
        }
        if(ctx.guarded && !watched.shield) {
            watched.shield=true;
            if(watched.defense==0) {
                check(!ctx.shieldLayer && ctx.shieldCapacity==0 && u.shield.getCapacity()==0,"invalid defense creates no infinite or negative shield");
            } else {
                watched.layer=ctx.shieldLayer;
                check(ctx.shieldLayer.getMaxCapacity()==600+caseId,"case "+caseId+" defense snapshot gives one full temporary layer");
                check(u.shield.getShieldById(ctx.shieldLayer.getId())===ctx.shieldLayer,"case "+caseId+" real AdaptiveShield preserves removable layer identity");
                check(ctx.shieldLayer.getRechargeRate()==0 && u.hp满血值==500,"case "+caseId+" no recharge or max HP mutation");
                check(PlayerHudShieldProjection.read(u).strengthKind=="finite","case "+caseId+" shield visible to production HUD projection");
                if(caseId==13) {
                    check(u.shield.absorbDamage(800,false,1)==187,"broken shield passes only remaining damage");
                    u.shield.update(0);
                    check(u.shield.getCapacity()==0,"exhausted temporary shield leaves no phantom capacity");
                }
                if(caseId==14) {
                    check(u.shield.absorbDamage(100,false,1)==0 && ctx.shieldLayer.getCapacity()==514 && watched.external.getCapacity()==200,"skill shield takes damage without spending the equipment shield");
                }
            }
        }
        if(caseId==13 && ctx.phase=="hold" && ctx.charge==10) {
            check(ctx.shieldLayer===watched.layer && u.shield.getCapacity()==0,"holding never replenishes a broken shield");
        }
        // Flash may queue new child load scripts until the next physical frame.
        if(ctx.phase=="hold" && !watched.hold) {
            watched.hold=true;
            check(near(u.damageTakenMultiplier,caseId==10?.2:.5),"case "+caseId+" production damage reduction");
            check(ctx.man.盾具._currentframe==15,"case "+caseId+" whole shield before hold");
            if(caseId==1||caseId==9)capture("rush-"+caseId+"-guard");
        }
        if(ctx.phase=="rush" && !watched.rush) {
            watched.rush=true;
            watched.pathStart=ctx.lastImpactBounds;
            if(caseId==2)check(near(ctx.speed,10) && ctx.level==2 && ctx.rushLength==32,"partial charge selects two loops and retains release-time speed despite later buffs");
            check(!WeaponSkillInputService.updateUnit(u,true,true,null,_root.帧计时器.当前帧数),"held F cannot retrigger");
            if(caseId==0)check(ctx.ratio==0,"tap during transformation remains minimum charge");
            if(caseId==1||caseId==8||caseId==9)check(ctx.ratio==1,"held input auto launches at cap");
            if(caseId==2)check(ctx.ratio>0 && ctx.ratio<1,"early release retains partial charge");
            check(ctx.man.盾具.灯晕._alpha>90 && ctx.man.盾具.装备光束._alpha>125,"case "+caseId+" one local launch glint");
            if(caseId==1) {
                EquipmentLightController.clearActionVisual(u,"长枪",{});
                check(u.man.__equipmentLightVisuals.长枪.owner===ctx && lightCount()==1,"old cast cannot clear current action light");
                var foreign:MovieClip=world.createEmptyMovieClip("foreignPort",world.getNextHighestDepth());
                var refused:Boolean=!EquipmentLightBridge.sample(lightRef,foreign,1,foreign);
                foreign.removeMovieClip();EquipmentLightController.update(lightRef);
                check(refused && lightCount()==1,"foreign anchor rejected and original light retained");
            }
        }
        if(ctx.phase=="rush" && ctx.age==6)check(Math.abs(ctx.man.盾具.灯晕._alpha-55)<.5 && near(ctx.man.盾具.装备光束._alpha,100),"case "+caseId+" launch glint ends without flashing on stride loops");
        if(ctx.phase=="rush" && ctx.age==3 && (caseId==0||caseId==9))capture("rush-"+caseId+"-charge");
        if(ctx.phase=="close" && !watched.close) {
            watched.close=true;
            check(near(u.damageTakenMultiplier,caseId==10?.2:1),"case "+caseId+" protection retires before gun return");
            check(!ctx.man.刚体标签,"case "+caseId+" no residual scoped poise");
            if(caseId==0||caseId==9)capture("rush-"+caseId+"-close");
        }
        if(ctx.cleaned) {
            check(watched.shadowStable,"case "+caseId+" shadow keeps ordinary size origin and visibility throughout all action phases");
            check(watched.layerOrder,"case "+caseId+" every active frame keeps the far-hand shield behind the entire player rig and above ground shadow");
            check(watched.lightContinuous,"case "+caseId+" every active frame keeps one light at actual lens with correct facing");
            check(watched.lightProperties,"case "+caseId+" transformation retains same light identity energy and one evasion bonus");
            check(!u.man.__equipmentLightVisuals.长枪,"case "+caseId+" action light lease retired");
            EquipmentLightController.update(lightRef);
            var shouldLight:Boolean=caseId!=4 && caseId!=5 && caseId!=15;
            check(shouldLight ? lightCount()==1 && lightRef.lightBeam===u.长枪_引用.装备光束 && near(lightRef.lightBeam._alpha,100) : lightCount()==0,"case "+caseId+" normal gun resumes or invalid light goes dark");
            check(u.shield.getCapacity()==(caseId==14 ? 200 : 0),"case "+caseId+" retires only its own shield on exit");
            if(caseId==14)check(u.shield.getShieldById(watched.external.getId())===watched.external,"external layer identity survives skill cleanup");
            check(!u.__sheriffShieldRush,"case "+caseId+" context released");
            check(near(u.damageTakenMultiplier,caseId==10?.2:1),"case "+caseId+" buff cleaned with other source preserved");
            check(u.mp==470 && u.长枪.value.shot!=1,"case "+caseId+" no repeated MP or ammo payment");
            if(caseId<4||caseId==7||caseId==8||caseId==9||caseId==10||caseId==13||caseId==14||caseId==16||caseId==17||caseId>=19) {
                check(u.状态=="长枪站立","case "+caseId+" returns to normal gun action");
                check(watched.endpointRendered,"case "+caseId+" routing waits until the return pose has been displayed");
                if(watched.defense==0) {
                    check(shots.length==0 && ctx.hits==0,"invalid cast-time defense emits no damaging hits even after defense becomes valid");
                } else {
                    check(shots.length>0 && shots[0].kind=="近战子弹","case "+caseId+" ordinary melee hit emitter");
                    var expectedPower:Number=watched.defense*(ctx.level==1?.6:(ctx.level==2?1:1.4));
                    var damageStable:Boolean=true;
                    for(var damageIndex:Number=0;damageIndex<shots.length;damageIndex++)
                        damageStable=damageStable && near(shots[damageIndex].power,expectedPower) && shots[damageIndex].zRange>=30;
                    check(damageStable,"case "+caseId+" every impact uses cast-time defense and the independent tier multiplier, including broken or damaged shields");
                }
                if(caseId<3||caseId==13||caseId==14||caseId==16||caseId>=25)
                    trace("ShieldRushTest Damage: case="+caseId+" defense="+ctx.defenseAtCast+" level="+ctx.level+" power="+(shots.length>0?shots[0].power:0)+" hits="+shots.length);
                if(caseId==0||caseId==1||caseId==8||caseId==9||caseId==17)
                    trace("ShieldRushTest Travel: case="+caseId+" running="+watched.runSpeed+" speed="+ctx.speed+" x="+u._x+" samples="+shots.length);
                if(caseId==7)check(Math.abs(u._x)<1 && shots.length<3,"wall stops travel and stationary hit loop");
                else if(caseId==17)check(near(u._x,32) && shots.length==1,"42-speed rush stops before an 8-unit wall instead of skipping across it");
                else if(caseId<19)check(u.colliderUpdates>0 && near(Math.abs(u._x),ctx.speed*ctx.rushLength),"case "+caseId+" real Mover preserves derived speed and configured duration");
                if(caseId!=7 && caseId!=17)check(watched.poseCadence && watched.cycles==ctx.level && watched.runTicks==ctx.level*16,"case "+caseId+" runs the entire native cycle once per charge level without speed-based skipping");
                if(caseId==0)check(shots.length==6 && near(u._x,160),"8-speed tap runs one complete loop at speed 10 for distance 160");
                if(caseId==1)check(shots.length==17 && near(u._x,480),"8-speed full charge runs three loops at speed 10 for distance 480");
                if(caseId==8)check(shots.length==48 && near(u._x,-1536),"30-speed mirrored build gets speed 32 and three full cycles");
                if(caseId==9)check(shots.length==48 && near(u._x,2016),"40-speed build gets speed 42 and one sweep each frame for three cycles");
                var covered:Boolean=true,oncePerFrame:Boolean=true;
                var left:Number=watched.pathStart.xMin,right:Number=watched.pathStart.xMax;
                for(var si:Number=0;si<shots.length;si++) {
                    var sb:Object=shots[si].bounds;
                    covered=covered && sb.xMin<=right+.1 && sb.xMax>=left-.1;
                    left=Math.min(left,sb.xMin);right=Math.max(right,sb.xMax);
                    if(si>0)oncePerFrame=oncePerFrame && shots[si].age>shots[si-1].age;
                }
                if(caseId<19 && caseId!=16)check(covered && left<=watched.pathStart.xMin-.05+Math.min(0,u._x)+.1 && right>=watched.pathStart.xMax+Math.max(0,u._x)-.1,"case "+caseId+" emitted sweep bounds cover the entire travelled path without endpoint gaps");
                check(oncePerFrame,"case "+caseId+" movement substeps never multiply same-frame impacts");
                if(caseId==8)check(near(u._x,-1536) && shots[0].bounds.xMax<shots[0].x,"mirrored hitbox stays in front and travels left");
                if(caseId>=19)checkSteeringResult();
                if(caseId==8 || caseId==9) {
                    var allTargets:Boolean=true;
                    for(var ti:Number=0;ti<watched.targetHits.length;ti++)allTargets=allTargets && watched.targetHits[ti];
                    check(allTargets,"case "+caseId+" production AABB collision finds every one-unit target along the fast path");
                }
            } else {
                check(shots.length==0,"interruption before rush emits no hits");
                if(caseId==4)check(u.刚体 && u.状态=="血腥死","death recovery preserves another rigid source");
            }
            if(shouldLight)watched.returnWaiting=true;
            else nextCase();
        }
    }
    private static function checkLifeSteal(props:Object):Void {
        check(props.吸血==watched.vampirism,"case "+caseId+" impact inherits gun plus base lifesteal once and retains stronger actor effects");
        if(shots.length>0)return;
        // Feed a controlled post-damage value into the actual life-steal
        // handler. Assert real HP mutation, not merely the emitted property.
        var patient:Object={hp:100,hp满血值:1000};
        var target:Object={hp:5000,损伤值:1000};
        var result:DamageResult=new DamageResult();
        var handler:LifeStealDamageHandle=LifeStealDamageHandle.getInstance();
        handler.handleBulletDamage(props,patient,target,null,result);
        check(patient.hp==100+watched.vampirism*10 && result._efLifeSteal==watched.vampirism*10,"case "+caseId+" production lifesteal handler restores HP from resolved damage");
        trace("ShieldRushTest Lifesteal: case="+caseId+" percent="+props.吸血+" damage="+target.损伤值+" healed="+(patient.hp-100));
        patient.hp=100;result.reset();
        target.shield=Shield.createTemporary(props.子弹威力,props.子弹威力,500,"lifesteal-test");
        handler.handleBulletDamage(props,patient,target,null,result);
        check(patient.hp==100 && result._efLifeSteal==0,"case "+caseId+" target shield strength still blocks lifesteal through the production rule");
    }

    private static function steeringInput():Void {
        u.上行=u.下行=u.左行=u.右行=false;u.锁定方向=false;
        if(caseId==19) {
            var right:Boolean=ctx.phase=="open"?ctx.age<5:
                (ctx.phase=="hold"?ctx.charge>=8:(ctx.phase=="rush"?ctx.age<8:ctx.phase=="brake"));
            u.右行=right;u.左行=!right;
        } else if(caseId==20 && ctx.phase=="rush") {
            u.右行=true;u.上行=ctx.age<16;u.下行=!u.上行;
        } else if(caseId==21 && ctx.phase=="rush" && ctx.age==15) {
            u.左行=true;
        } else if(caseId==22 && ctx.phase=="rush") {
            u.右行=ctx.age%2==0;u.左行=!u.右行;
        } else if(caseId==23 && ctx.phase=="rush") {
            u.左行=true;u.锁定方向=ctx.age<8;
        } else if(caseId==24 && ctx.phase=="rush") {
            u.右行=true;u.上行=true;
        }
    }

    private static function checkSteeringResult():Void {
        var tight:Boolean=true;
        for(var i:Number=0;i<shots.length;i++)tight=tight && shots[i].bounds.xMax-shots[i].bounds.xMin<62;
        check(tight,"case "+caseId+" turns never join opposite front hitboxes into a body-spanning sweep");
        if(caseId==19) {
            check(near(u._x,-320) && u.方向=="左","mid-rush reverse changes actual travel and survives gun return");
            check(watched.steered_open && watched.steered_hold && watched.steered_rush && watched.steered_brake && watched.steered_close,"every phase receives steering through the normal player direction method");
        } else if(caseId==20) {
            check(near(u._x,480) && near(u.Z轴坐标,80) && near(u._y,80),"up then down steering follows half horizontal speed and keeps screen Y and lane synchronized");
            check(u.__dmIdx!=undefined && u.colliderUpdates>48,"diagonal travel uses actual depth management and collider updates");
            var low:Number=0,high:Number=0;
            for(var j:Number=0;j<shots.length;j++){low=Math.min(low,shots[j].z-shots[j].zRange);high=Math.max(high,shots[j].z+shots[j].zRange);}
            check(low<=-110 && high>=110,"swept depth intervals cover both extremes of the steered route");
        } else if(caseId==21) {
            check(near(u._x,140) && shots.length==7,"last-tick turn preserves both old and new travelled segments");
            check(shots[shots.length-1].phase=="brake" && shots[shots.length-1].direction=="左" && shots[shots.length-2].direction=="右","final reversed segment flushes on the next tick instead of double-hitting or disappearing");
        } else if(caseId==22) {
            check(near(u._x,0) && shots.length==48,"continuous alternating steering preserves speed and at most one hit per tick");
        } else if(caseId==23) {
            check(near(u._x,-320),"steering obeys an external facing lock without clearing it itself");
        } else if(caseId==24) {
            check(near(u._x,480) && near(u.Z轴坐标,-5),"a thin lane wall stops vertical substeps without tunnelling or cancelling forward travel");
        }
        trace("ShieldRushTest Steering: case="+caseId+" loops="+ctx.level+" ticks="+watched.runTicks+" x="+u._x+" z="+u.Z轴坐标+" samples="+shots.length);
    }

    private static function nextCase():Void {
        EquipmentLightController.dispose(lightRef);
        check(lightCount()==0 && EquipmentLightDefense.getActiveBonus(u)==0,"case "+caseId+" light and defense owner disposed");
        check(!lightRef.lightPlacement && !lightRef.lightBeam,"case "+caseId+" placement and action subscriptions released");
        u.buffManager.clearAllBuffs();u.buffManager.destroy();u.dispatcher.destroy();
        if(++caseId==28){finish();return;}
        // Each fixture owns a physical frame boundary, so prior unload/load
        // events cannot be delivered onto the next same-named test actor.
        watched={casePending:true};
    }
    private static function capture(id:String):Void {
        // Return contacts need silhouette/joint evidence. Keep their lossless
        // readback smaller so six additional captures do not dominate the run.
        var ending:Boolean=id.indexOf("-return-")>=0;
        var scale:Number=ending?.75:1;
        var bitmap:BitmapData=new BitmapData(640*scale,480*scale,true,0);
        var wasVisible:Boolean=library._visible;library._visible=true;
        bitmap.draw(u.man,new Matrix(.75*scale,0,0,.75*scale,180*scale,250*scale),null,"normal",null,true);
        library._visible=wasVisible;
        dumpBitmap(bitmap,id);bitmap.dispose();
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        if(ctx)SheriffShieldRush.cleanup(ctx);
        EquipmentLightController.dispose(lightRef);EquipmentLightBridge.disconnect();
        DepthManager.instance.dispose();DepthManager.instance=saved.depth;
        RoutingRuntime.clearAttachMovieAdapterForTest();
        driver.removeMovieClip();world.removeMovieClip();
        _root.gameworld=saved.world;_root.帧计时器=saved.clock;_root.暂停=saved.pause;
        _root.控制目标=saved.control;_root.collisionLayer=saved.collision;
        _root.子弹区域shoot传递=saved.shoot;_root.装备引用配置=saved.skin;_root.是否阴影=saved.shadow;
        trace("ShieldRushTest Tests Passed: "+passed);trace("ShieldRushTest Tests Failed: "+failed);
        trace("ShieldRushTest Lit Frames Checked: "+lightFrames);
        _root.shieldRushTestComplete();
    }

    private static function normalGun(actor:MovieClip):Void {
        if(!actor.man._parent)return;
        actor.man.装备枪.removeMovieClip();
        actor.长枪_引用=actor.man.attachMovie("枪-长枪-Codex-特勤霰弹枪","装备枪",1);
        actor.dispatcher.publish("长枪_引用");
    }

    private static function playerShadowMatches(shadow:MovieClip):Boolean {
        if(shadow==undefined)return false;
        // Ordinary player XFL: long-gun lower-body host * authored shadow
        // matrix * native radial shape. These are unit-space bounds, not
        // action-local _width, which hid the old double-scale mismatch.
        var b:Object=shadow.getBounds(u);
        return near(b.xMin,-33.84507) && near(b.xMax,32.20265) && near(b.yMin,-11.19056) && near(b.yMax,15.68915);
    }

    private static function lightCount():Number {
        var p:String=EquipmentLightBridge.payload();
        return p=="" ? 0 : p.split(";").length-1;
    }

    private static function observeLight():Void {
        lightFrames++;
        watched.shadowStable=watched.shadowStable && playerShadowMatches(ctx.man.接地阴影) && ctx.man.接地阴影._visible==(_root.是否阴影==true);
        var shieldDepth:Number=ctx.man.盾具.getDepth();
        var order:Boolean=shieldDepth>ctx.man.接地阴影.getDepth();
        // Check all native wrappers, including head, torso, both arms and both
        // legs, throughout open/hold/run/brake/close rather than only at entry.
        for(var i:Number=0;i<21;i++)if(i!=13)order=order && ctx.man["肢体"+i].getDepth()>shieldDepth;
        watched.layerOrder=watched.layerOrder && order;
        var prop:MovieClip=ctx.man.盾具,port:MovieClip=prop.手电口;
        var origin:Object={x:0,y:0};port.localToGlobal(origin);world.globalToLocal(origin);
        var beamOrigin:Object={x:0,y:3};prop.装备光束.localToGlobal(beamOrigin);world.globalToLocal(beamOrigin);
        var glowOrigin:Object={x:0,y:0};prop.灯晕.localToGlobal(glowOrigin);world.globalToLocal(glowOrigin);
        var e:Object=lightRef.equipmentLight;
        var continuous:Boolean=prop.装备光束._visible
            && lightRef.lightBeam===prop.装备光束 && port._parent===prop
            && near(e.x,origin.x) && near(e.y,origin.y) && e.dx*(u._xscale<0?-1:1)>.9 && lightCount()==1
            && near(beamOrigin.x,origin.x) && near(beamOrigin.y,origin.y)
            && near(glowOrigin.x,origin.x) && near(glowOrigin.y,origin.y);
        if(watched.lightContinuous && !continuous)trace("ShieldRushTest LIGHT GAP: case="+caseId+" age="+age+" pose="+ctx.man._currentframe+" phase="+ctx.phase+" shown="+prop.装备光束._visible+" owner="+(lightRef.lightBeam===prop.装备光束)+" port="+(port._parent===prop)+" actual="+e.x+","+e.y+" expected="+origin.x+","+origin.y+" beam="+beamOrigin.x+","+beamOrigin.y+" glow="+glowOrigin.x+","+glowOrigin.y+" dx="+e.dx+" count="+lightCount());
        watched.lightContinuous=watched.lightContinuous && continuous;
        watched.lightProperties=watched.lightProperties && e.id==watched.lightId
            && near(e.energy,1.45) && EquipmentLightDefense.getActiveBonus(u)==20;
    }

    private static function dumpBitmap(bitmap:BitmapData, id:String):Void {
        trace("[ASSET_BITMAP_BEGIN] "+id+" "+bitmap.width+" "+bitmap.height);
        // Native full-color bounds skip only pixels known to be exactly zero.
        // Keep original canvas coordinates and lossless zero runs at both sides.
        var bounds:Rectangle=bitmap.getColorBoundsRect(0xFFFFFFFF,0,false);
        var endX:Number=bounds.x+bounds.width,endY:Number=bounds.y+bounds.height;
        for (var y:Number=bounds.y;y<endY;y++) {
            var row:String="",last:Number=-1,count:Number=0,opaque:Boolean=false;
            if (bounds.x>0) { last=0;count=bounds.x; }
            for (var x:Number=bounds.x;x<endX;x++) {
                var pixel:Number=bitmap.getPixel32(x,y);
                if (pixel!=0) opaque=true;
                if (pixel==last) count++;
                else { if (count) row+=bitmapColorHex(last)+":"+count+",";last=pixel;count=1; }
            }
            if (endX<bitmap.width) {
                if (last==0) count+=bitmap.width-endX;
                else { row+=bitmapColorHex(last)+":"+count+",";last=0;count=bitmap.width-endX; }
            }
            row+=bitmapColorHex(last)+":"+count;
            if (opaque) trace("[ASSET_BITMAP_ROW] "+y+" "+row);
        }
        trace("[ASSET_BITMAP_END] "+id);
    }
    private static function bitmapColorHex(pixel:Number):String {
        // AVM1 formats signed INT_MIN as "-(0000000". Serialize safe 16-bit halves.
        var low:String=(pixel & 65535).toString(16);
        while (low.length<4) low="0"+low;
        return ((pixel >>> 16) & 65535).toString(16)+low;
    }
}
