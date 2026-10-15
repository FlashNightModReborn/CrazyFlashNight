import org.flashNight.arki.unit.Action.Skill.*;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntime;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.object.ObjectUtil;
import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/** Real XML, published player art, F/routing/dressup/fire commit and AABB.
 * Native bullet factory, queue, collision and HP settlement; no profile/save writes.
 */
class org.flashNight.arki.unit.Action.Skill.RockQueenBattleSkillTest {
    private static var passed:Number, failed:Number, age:Number, total:Number, index:Number;
    private static var items:Array, libs:Array, xmlIndex:Number;
    private static var world:MovieClip, driver:MovieClip, u:MovieClip, ctx:Object, ref:Object, events:Array;
    private static var finished:Boolean, pausedFrame:Number, factory:AABBColliderFactory;
    private static var ids:Array = ["vocal","keyboard","guitar","guitar-gun","guitar-flame"];
    private static var counts:Array = [3,9,4,8,9];
    private static var caseSlot:Number, travel:Number, previousX:Number, maxStep:Number;
    private static var productionShoot:Function, damageTarget:MovieClip, damageCache:Object;
    private static var damageTotals:Array, legacyTotal:Number;
    private static var healTargets:Array;
    private static var titles:Array = ["主唱突刺","旋镰横掠","吉他震地","吉他机枪扫射","吉他持续喷火"];
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else {failed++;trace("RockQueenBattleSkillTest FAIL: case="+index+" "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=age=total=index=xmlIndex=0;finished=false;items=[];libs=[];
        _root.暂停=false;_root.当前玩家总数=1;_root.技能点数=10;
        _root.是否阴影=true;Mover.init();
        _root.帧计时器={当前帧数:0,毫秒每帧:.03,添加冷却任务:function():Void{}};
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach};
        _root.按键输入检测=function():Boolean{return false;};
        _root.播放音效=function():Void{};_root.发布消息=function():Void{};
        productionShoot=_root.子弹区域shoot传递;
        org.flashNight.arki.component.Collider.ColliderFactoryRegistry.init();
        org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine.getInstance();
        _root.子弹区域shoot传递=function(p:Object):Void {RockQueenBattleSkillTest.capture(p);};
        _root.对象浅拷贝=function(p:Object):Object {var out:Object={};for(var key:String in p)out[key]=p[key];return out;};
        _root.soundEffectManager={playSound:function():Void{}};
        var caches:Object=TargetCacheManager;
        caches.acquireEnemyCache=function():Object{return RockQueenBattleSkillTest.damageCache;};
        caches.findAlliesInRange=function(caster:Object,interval:Number,leftRange:Number,rightRange:Number):Array {
            RockQueenBattleSkillTest.check(leftRange==900 && rightRange==900,"original crimson horizontal healing range");
            return RockQueenBattleSkillTest.healTargets;
        };
        factory=new AABBColliderFactory(1);
        // TestLoader 的 UI 组件占用保留高层；其 getNextHighestDepth 可越过 AVM1 可播放范围。
        var depth:Number=30000;
        while(_root.getInstanceAtDepth(depth))depth++;
        world=_root.createEmptyMovieClip("__rockScene",depth);
        _root.collisionLayer=_root.createEmptyMovieClip("__rockCollision",depth+1);
        driver=world.createEmptyMovieClip("driver",10);
        driver.onEnterFrame=function():Void {
            if(++RockQueenBattleSkillTest.total>4500){RockQueenBattleSkillTest.check(false,"watchdog");RockQueenBattleSkillTest.finish();}
        };
        loadXML();
    }
    private static function loadXML():Void {
        var files:Array=["武器_刀_直剑.xml","武器_刀_镰刀.xml","武器_长枪_特殊.xml"];
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {RockQueenBattleSkillTest.xmlLoaded(ok,this);};
        xml.load("../data/items/"+files[xmlIndex]);
    }
    private static function xmlLoaded(ok:Boolean, xml:XML):Void {
        check(ok,"actual item XML loaded");if(!ok){finish();return;}
        var names:Array=["主唱光剑","键盘镰刀","吉他喷火器"];
        var rows:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(xml.firstChild).item);
        for(var i:Number=0;i<rows.length;i++)if(rows[i].name==names[xmlIndex])items[xmlIndex]=rows[i];
        check(items[xmlIndex]!=undefined,"actual item found");
        if(++xmlIndex<3){loadXML();return;}
        check(items[0].skill.skillname==titles[0],"vocal XML skill");
        check(items[1].lifecycle.attr_0.init.initParam.skill_0.skillname==titles[1],"keyboard XML ground skill");
        var gp:Object=items[2].lifecycle.attr_0.init.initParam;
        check(gp.skill_0.skillname==titles[2] && gp.skill_1.skillname==titles[4] && gp.skill_2.skillname==titles[3],"all three guitar XML modes");
        loadArt();
    }
    private static function loadArt():Void {
        // 原生宿主显式共享导入两套发布资源，和主游戏一样处于同一 attachMovie 字典。
        // 单纯并列 loadClip 不能让 things0 的单位查到 fs配置素材 的武器导出。
        libs=[world];_root.gameworld=world;world._x=240;world._y=190;
        // 常规帧只运行原生时间轴；姿态通过下方 BitmapData.draw 独立读回，避免后台窗口降速。
        world._visible=false;
        checkStock();startCase();
        driver.onEnterFrame=function():Void {
            try {RockQueenBattleSkillTest.advance();}
            catch(error){RockQueenBattleSkillTest.check(false,"unexpected "+error);RockQueenBattleSkillTest.finish();}
        };
    }
    private static function checkStock():Void {
        var names:Array=titles.concat(["跳跃镰刀斩","弹射弧光斩","主唱广域裂空斩","主唱拔刀裂空斩","主唱横向裂空斩","吉他导弹烈炎炮","吉他导弹炮","吉他广域喷火","吉他烈炎炮"]);
        var frames:Array=[30,53,34,31,51,112,72,145,103,75,163,74,77,77];
        for(var i:Number=0;i<names.length;i++) {
            var mc:MovieClip=libs[0].attachMovie("战技容器-"+names[i],"stock"+i,100+i);
            check(mc._totalframes==frames[i],"stock "+names[i]+" frames="+mc._totalframes);
            mc.stop();mc.removeMovieClip();
            if(i>=5)check(!_root.主动战技函数.兵器[names[i]] && !_root.主动战技函数.长枪[names[i]],"stored animation has no player entry "+names[i]);
        }
    }
    private static function createUnit(slot:Number, face:Boolean):Void {
        u=libs[0].createEmptyMovieClip("actor"+index,20);
        u.hasDressup=true;u.hp=u.hp满血值=1000;u.mp=u.mp满血值=500;
        u.空手攻击力=100;u.version=index+1;u.生命周期函数列表=[];u.syncRefs={};u.被动技能={};
        u.等级=30;u.身高=175;u.垂直速度=0;u.起始Y=0;u.操控编号=-1;
        u.是否为敌人=false;u.硬直=function():Void{};
        u.左行=u.右行=u.上行=u.下行=false;
        u.方向改变=_root.主角函数.方向改变;
        u.aabbCollider={updateFromUnitArea:function():Void{}};
        u.性别=face?"女":"男";u._xscale=face?-100:100;u.方向=face?"左":"右";
        u.Z轴坐标=0;u.myxscale=100;u.主动战技={};u.基础伤害类型="物理";u.基础吸血=2;u.基础毒=0;u.基础击溃=0;
        u.基础命中率=100;u.基础命中加成=0;u.基础斩杀=0;u.兵器吸血=3;u.长枪吸血=3;u.兵器伤害类型="物理";
        u.兵器毒=7;u.兵器击溃=2;u.兵器斩杀=1;
        u.兵器暴击=function(bullet:Object):Number{return 1.5;};
        u.兵器命中加成=0;u.长枪命中加成=0;u.长枪伤害类型="物理";
        u.dispatcher=new EventDispatcher();u.enableShoot=true;FireEventComponent.initialize(u);
        u.自瞄中=true;u.攻击目标="aimTarget";
        if(!libs[0].aimTarget)libs[0].createEmptyMovieClip("aimTarget",25);
        libs[0].aimTarget.hp=100;libs[0].aimTarget._x=70;libs[0].aimTarget._y=-200;libs[0].aimTarget.Z轴坐标=0;
        u.攻击模式=slot>=3?"长枪":"兵器";
        u.状态改变=function(state:String):Void {
            if(this.man.getDepth()<0)this.man.swapDepths(0);
            this.man.removeMovieClip();this.container.removeMovieClip();delete this.man;
            this.状态=state;
            if(state=="战技") {
                this.createEmptyMovieClip("container",1);this.container._x=3.4;this.container._y=-62.35;
                this.container._xscale=27.708435;this.container._yscale=27.690125;
            } else {
                this.man=this.createEmptyMovieClip("__normalMan"+this.version,0);
                this.man.swapDepths(-16383);
                this.man.开始射击=function():Void{this._parent.__normalFireRequests++;};
            }
        };
        u.动画完毕=function():Void{this.状态改变(this.hp>0?this.攻击模式+"站立":"血腥死");};
        u.UpdateBigSmallState=function():Void{};
        u.__normalFireRequests=0;u.行走=function():Void{};
        u.根据模式重新读取武器加成=_root.主角函数.根据模式重新读取武器加成;
        u.装载主动战技=_root.主角函数.装载主动战技;u.释放主动战技=_root.主角函数.释放主动战技;
        var item:Object=items[Math.min(slot,2)];var p:Object=item.lifecycle.attr_0.init.initParam;
        var equip:Object={name:item.name,value:{level:1,shot:0,mods:[]}};
        if(slot<2){u.刀=equip;u.刀_装扮=item.data.dressup;u.刀属性=ObjectUtil.clone(item.data);}
        else {u.长枪=equip;u.长枪_装扮=item.data.dressup;u.长枪属性=ObjectUtil.clone(item.data);u.长枪弹匣容量=80;}
        if(slot==2){u.刀属性={power:item.data.power*p.bladePowerCoeff};}
        ref={自机:u,版本号:u.version,是否为主角:true,装备名称:item.name,是否刀枪复用:true,
            weaponMode:slot==0?"光剑":(slot==1?"镰刀":(slot==3?"机枪":"喷火器")),
            baseDamage:item.data.power,光刃攻击力系数:p.bladeAtkCoefficient,光刃基础伤害系数:p.bladeBaseDmgCoefficient,
            镰刀风车斩耗蓝量:5,子弹威力倍率:30,吉他震地耗蓝量:25,吉他震地威力倍率:45,
            机枪弹容上限:48,机枪剩余弹容:48,skill_1:p.skill_1,skill_2:p.skill_2};
        ref.rockBlade=p.rockBlade;
        RockQueenBattleSkill.bindEquipment(ref,slot==0?"vocal":(slot==1?"keyboard":"guitar"));
        if(slot==3){u.长枪属性.bullet=p.machineGunBullet;u.长枪属性.power*=p.machineGunPowerCoeff;u.长枪属性.velocity*=p.machineGunVelocityMultiplier;u.长枪弹匣容量*=p.machineGunCapacityMultiplier;}
        if(slot>=3)RockQueenBattleSkill.syncGunSkill(ref);
        else u.装载主动战技(slot==0?item.skill:(slot==2?RockQueenBattleSkill.slamSkill(ref,p.skill_0):p.skill_0),"兵器",item.name);
        u.状态改变(u.攻击模式+"站立");_root.控制目标=u._name;
    }
    private static function startCase():Void {
        trace("RockQueenBattleSkillTest Case: "+index);age=0;events=[];ctx=null;travel=previousX=maxStep=0;
        damageTotals=[0,0,0,0,0];legacyTotal=0;
        _root.是否阴影=index!=24;_root.collisionLayer.clear();
        var slot:Number=index<10?index%5:(index==14||index==16||index==17?0:3);
        if(index==18)slot=4;
        if(index>18 && index<29)slot=[0,1,3,4,4,0,1,0,1,2][index-19];
        if(index>=29)slot=0;
        caseSlot=slot;
        createUnit(slot,index>=5 && index<10);
        if(index>=29)prepareHealing();
        if(index==21 || index==22 || index==23){u.主手射击中=true;u.动作A=true;}
        if(index==26)ref.rockBlade=null;
        if(index==27 || index==28){u.空手攻击力=350;u.等级=80;u.刀属性.power=1600;u.技能等级=10;}
        if(index==25){u.右行=true;var wall:MovieClip=_root.collisionLayer;wall.beginFill(0);wall.moveTo(100,-1000);wall.lineTo(112,-1000);wall.lineTo(112,1000);wall.lineTo(100,1000);wall.lineTo(100,-1000);wall.endFill();check(wall.hitTest(110,0,true),"wall fixture has native collision at 110,0");trace("RockQueen wall: "+wall+" bounds="+wall._width+","+wall._height+" probe="+wall.hitTest(110,0,true));}
        ManualCooldownService.reset(ManualCooldownService.WEAPON_SKILL_KEY);
        if(index==14)u.mp=29;
        if(index==15)u.长枪.value.shot=u.长枪弹匣容量;
        if(index==18)u.长枪.value.shot=u.长枪弹匣容量-2;
        if(index==16)RoutingRuntime.setAttachMovieAdapterForTest({attachMovie:function():MovieClip{return undefined;}});
        var result:Object=WeaponSkillInputService.updateUnit(u,true,true,null,++_root.帧计时器.当前帧数);
        RoutingRuntime.clearAttachMovieAdapterForTest();
        if((index>=14 && index<=16) || index==26) {
            check(!result.released && !u.__rockQueenCast,"denied input has no cast");
            check(u.mp==(index==14?29:500) && ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY),"denied input pays no MP or cooldown");
            next();return;
        }
        ctx=u.__rockQueenCast;
        check(result.released && result.startSharedCooldown && ctx.active,"real F entry releases");
        check(index==29?(u.mp==470 || u.mp==470-ref.猩红增幅耗蓝量):u.mp==(slot==2?445:470),"MP paid exactly once; crimson keeps its own original cost");
        if(index==21 || index==22 || index==23)check(ctx.fromShooting && !u.主手射击中 && u.动作A,"ordinary fire lane released but held trigger preserved");
        if(!ctx){next();return;}
    }
    private static function capture(p:Object):Void {
        var c:Object=u.__rockQueenCast;
        check(c.active && !(_root.暂停),"only active unpaused cast fires");
        check(isFinite(p.子弹威力) && p.子弹威力>0 && isFinite(p.shootX) && isFinite(p.shootY),"finite positive damage and origin");
        BulletInitializer.inheritShooterAttributes(p,u);
        check(p.吸血>=3,"production weapon lifesteal inherited");
        if(caseSlot<3) {
            check(p.子弹种类=="近战联弹" && p.霰弹值==3 && p.最小霰弹值==3 && p.毒==7 && p.血量上限击溃==2 && p.斩杀>=1 && p.暴击===u.兵器暴击,"knife allocation inherits weapon effects");
        }
        if(p.区域定位area) {
            var bullet={_x:p.shootX,_y:p.shootY};
            var a=factory.createFromBullet(bullet,p.区域定位area);
            check(a.right>a.left && a.bottom>a.top && Math.abs(a.left-u._x)<1000,"production AABB matches native FX bounds");
            if(caseSlot==4)check(a.right-a.left>240 && a.right-a.left<700,"flame restored reach in world pixels: "+(a.right-a.left));
            factory.releaseCollider(a);
        } else {
            check(p.速度X==undefined && p.速度Y==undefined,"automatic aim cannot detach bullet direction from native barrel");
            var mu:MovieClip=c.man.rockWeapon.placement.装扮.枪口位置;
            var point:Object={x:0,y:0};mu.localToGlobal(point);_root.gameworld.globalToLocal(point);
            check(Math.abs(p.shootX-point.x)<.1 && Math.abs(p.shootY-point.y)<.1,"real muzzle origin aligned");
        }
        events.push({frame:c.lastFrame,x:p.shootX,y:p.shootY,power:p.子弹威力,face:u.方向,age:age});
        if((index<10 || index==27 || index==28) && caseSlot<3) checkDamagePipeline(p);
    }
    /** 真实工厂、AABB扫描、空护盾和DamageCalculator扣血；只隔离场景目标列表。 */
    private static function checkDamagePipeline(p:Object):Void {
        if(!damageTarget) {
            damageTarget=world.createEmptyMovieClip("damageTarget",50);
            damageTarget.createEmptyMovieClip("area",1);
            var ar:MovieClip=damageTarget.area;
            ar.beginFill(0);ar.moveTo(-14,-100);ar.lineTo(14,-100);ar.lineTo(14,0);ar.lineTo(-14,0);ar.lineTo(-14,-100);ar.endFill();
            damageTarget.dispatcher=new EventDispatcher();damageTarget.防御力=300;damageTarget.等级=30;
            damageTarget.躲闪率=0;damageTarget.魔法抗性={基础:0};
            damageTarget.shield=org.flashNight.arki.component.Shield.AdaptiveShield.acquireDormantFromPool("rockFixtureShield");
        }
        var facing:Number=u.方向=="左"?-1:1;
        var fx:Object=p.区域定位area.getRect(world);
        var positions:Array=[u._x+20*facing,u._x+75*facing,(fx.xMin+fx.xMax)/2,u._x+1200*facing,50*facing];
        var damage:Array=[];
        for(var i:Number=0;i<positions.length;i++) {
            damageTarget._x=positions[i];damageTarget._y=u._y;damageTarget.Z轴坐标=u.Z轴坐标;
            damageTarget.aabbCollider=factory.createFromUnitArea(damageTarget);
            var box=damageTarget.aabbCollider;
            damageCache={data:[damageTarget],leftValues:[box.left],rightValues:[box.right],rightMaxValues:[box.right]};
            damage[i]=settle(p);
            check(isFinite(damage[i]),"real target HP stays finite");
            if(i<2 || i==4)check(damage[i]>=Math.floor(p.子弹威力*.85*.5*3)-3,"real close HP meets physical damage floor probe="+i+" frame="+ctx.lastFrame+" damage="+damage[i]);
            if(i==3)check(damage[i]==0,"real out-of-range target is untouched");
            damageTotals[i]+=damage[i];
            if(i==0) {
                var old:Object=_root.对象浅拷贝(p);
                old.子弹种类="近战子弹";old.霰弹值=old.最小霰弹值=1;
                old.子弹威力=legacyBudget()/counts[caseSlot];
                legacyTotal+=settle(old);
                damageTarget.Z轴坐标=u.Z轴坐标+250;
                check(settle(p)==0,"other depth lane is untouched");
            }
            factory.releaseCollider(damageTarget.aabbCollider);
        }
        trace("RockQueen Damage: case="+index+" frame="+ctx.lastFrame+" HP="+damage);
    }
    private static function settle(p:Object):Number {
        damageTarget.hp=damageTarget.hp满血值=10000000;
        var copy:Object=_root.对象浅拷贝(p);
        // Compare physical skill allocations without percentage crumble/crit/toxic randomness.
        copy.lockShooterAttributes=true;
        copy.毒=copy.击溃=copy.血量上限击溃=copy.斩杀=copy.吸血=copy.nanoToxic=0;
        // Crit is a callable hook: numeric zero still enters CritDamageHandle and produces NaN.
        delete copy.暴击;
        copy.命中率=100000;
        var b:Object=productionShoot(copy);
        check(b!=undefined && b.aabbCollider.right>b.aabbCollider.left,"real melee bullet created and queued");
        BulletQueueProcessor.processQueue();
        return 10000000-damageTarget.hp;
    }
    private static function legacyBudget():Number {
        var slot:Number=caseSlot;
        var legacyHits:Number=slot==0?2:(slot==1?9:4);
        var base:Number=u.空手攻击力*.1+u.等级*(slot==1?15:25)+u.刀属性.power*(slot==0?4:(slot==1?1.5:3));
        if(slot>0 && u.等级<12)base=Math.floor(base*(u.等级+5)/20);
        var bonus:Number=slot==0?u.空手攻击力*.5+ref.baseDamage*2:(slot==1?5*30+ref.baseDamage:25*45);
        var budget:Number=slot==1?30:(slot==0?3:1);
        var reserve:Number=slot==1 && isFinite(u.技能等级)?3*(u.空手攻击力/4*(1+u.技能等级)+u.刀属性.power+470*1.8):0;
        return base*legacyHits+bonus*budget+reserve;
    }
    private static function snapshotPose(label:String):Void {
        var bitmap:BitmapData=new BitmapData(700,400,false,0xF0F0F0);
        var matrix:Matrix=new Matrix();matrix.translate(220,290);bitmap.draw(u,matrix);
        var runs:Array=[];var previous:Number=-1;var count:Number=0;
        for(var y:Number=0;y<400;y++)for(var x:Number=0;x<700;x++) {
            var color:Number=bitmap.getPixel(x,y);
            if(color==previous)count++;
            else {if(count)runs.push(previous.toString(16)+":"+count);previous=color;count=1;}
        }
        runs.push(previous.toString(16)+":"+count);bitmap.dispose();
        trace("RockQueen Pose: "+ids[caseSlot]+"-"+label+" "+runs.join(","));
    }
    private static function prepareHealing():Void {
        u.hp=700;
        var param:Object=items[0].lifecycle.attr_0.init.initParam;
        ref.猩红增幅耗蓝量=Math.floor(u.mp满血值/100*param.mpCostRatio/2);
        ref.猩红增幅时间戳名="rockNativeCrimson";
        ref.猩红增幅时间间隔=1000;
        check(ref.猩红增幅耗蓝量==2,"crimson cost uses original item ratio");
        healTargets=[];
        for(var i:Number=0;i<3;i++) {
            var ally:MovieClip=world.createEmptyMovieClip("healAlly"+i,60+i);
            ally.hp=i==2?0:1000;ally.hp满血值=2000;
            ally._x=100;ally._y=i==1?900:0;
            healTargets.push(ally);
        }
        if(index==30){u.上次动作时间={};u.上次动作时间[ref.猩红增幅时间戳名]=_root.帧计时器.当前帧数;}
    }
    private static function checkHealing():Void {
        var cost:Number=ref.猩红增幅耗蓝量;
        if(index==30) {
            _root.帧计时器.当前帧数+=40;
            RockQueenBattleSkill.frame(ctx.man,"vocal",ctx.lastFrame+1,0,15);
            check(u.hp==700 && u.mp==470 && healTargets[0].hp==1000,"cancelled cast cannot heal or charge late");
        } else {
            check(u.hp==750 && u.mp==470-cost,"real vocal cast restores 5 percent HP and charges once");
            check(healTargets[0].hp==1100 && healTargets[1].hp==1000 && healTargets[2].hp==0,"real area heal covers ally, excludes distant depth and dead unit");
            var stamp:Number=u.上次动作时间[ref.猩红增幅时间戳名];
            _root.帧计时器.当前帧数=stamp+31;
            _root.暂停=true;
            _root.装备生命周期函数.主唱光剑治疗周期(ref);
            check(u.hp==750 && u.mp==470-cost && u.上次动作时间[ref.猩红增幅时间戳名]==stamp,"paused crimson leaves HP MP and cooldown untouched");
            _root.暂停=false;u.mp=cost-1;
            _root.装备生命周期函数.主唱光剑治疗周期(ref);
            check(u.hp==750 && u.mp==cost-1 && u.上次动作时间[ref.猩红增幅时间戳名]==stamp,"insufficient MP cannot consume healing cooldown");
            u.mp=100;u.hp=0;
            _root.装备生命周期函数.主唱光剑治疗周期(ref);
            check(u.hp==0 && u.mp==100,"dead caster cannot heal or spend MP");
            u.hp=990;
            _root.装备生命周期函数.主唱光剑战斗周期(ref);
            check(u.hp==990 && u.mp==100,"idle normal pose does not activate crimson");
            u.man.兵器攻击标签=true;
            _root.装备生命周期函数.主唱光剑战斗周期(ref);
            check(u.hp==1000 && u.mp==100-cost,"ordinary attack resumes same healing and caps HP at maximum");
            _root.装备生命周期函数.主唱光剑战斗周期(ref);
            check(u.mp==100-cost && healTargets[0].hp==1200,"normal and skill support share cooldown without duplicate charge");
            trace("RockQueen Healing: castSelf=50 ally=100 cost="+cost+" capped=true sharedCooldown=true");
        }
        for(var i:Number=0;i<healTargets.length;i++)healTargets[i].removeMovieClip();
        healTargets=[];
    }
    private static function advance():Void {
        if(finished)return;if(++total>4500){check(false,"watchdog");finish();return;}
        ++age;++_root.帧计时器.当前帧数;
        var step:Number=Math.abs(u._x-previousX);travel+=step;maxStep=Math.max(maxStep,step);previousX=u._x;
        if(index==19){u.左行=age<14;u.右行=age>=14;}
        if(index==20){u.右行=age<30;u.左行=age>=30;u.上行=age>15 && age<25;}
        if(index==23 && age==20)u.动作A=false;
        if(age==10 && ctx.lastFrame==0){check(false,"native first-frame handshake did not run");RockQueenBattleSkill.cancel(ctx);finish();return;}
        if(index<5 && (age==2 || ctx.lastFrame==ctx.spec.frames-1))snapshotPose("f"+ctx.lastFrame);
        if(index==2 && (ctx.lastFrame==5 || ctx.lastFrame==7 || ctx.lastFrame==10 || ctx.lastFrame==13 || ctx.lastFrame==15 || ctx.lastFrame==18 || ctx.lastFrame==21 || ctx.lastFrame==24 || ctx.lastFrame==28 || ctx.lastFrame==31))snapshotPose("f"+ctx.lastFrame);
        if(index==29 && age==2) {
            var hpBefore:Number=u.hp;var mpBefore:Number=u.mp;
            RockQueenBattleSkill.frame(ctx.man,"vocal",ctx.lastFrame,ctx.man.__rockPose.sourceFrame,15);
            check(u.hp==750 && u.hp==hpBefore && u.mp==mpBefore,"duplicate timeline callback cannot duplicate healing");
        }
        if(age==4) {
            var weapon:MovieClip=ctx.man.rockWeapon.placement.装扮;
            check(weapon!=undefined && isFinite(weapon.动画._totalframes) && weapon.动画._totalframes>=15,"actual player weapon mounted");
            check((u.攻击模式=="长枪"?u.长枪_引用:u.刀_引用)===weapon,"canonical equipment reference belongs to active man");
            check(ctx.man.rockShadow!=undefined && u.skillShadow===ctx.man.rockShadow,"native skill shadow registered");
            check(ctx.man.rockShadow._visible==_root.是否阴影,"shadow follows player shadow setting");
            var image:BitmapData=new BitmapData(500,400,true,0);var matrix:Matrix=new Matrix();matrix.translate(230,180);image.draw(u,matrix);
            var bounds:Rectangle=image.getColorBoundsRect(0xFF000000,0,false);check(bounds.width>20 && bounds.height>20,"native player pose rasterizes "+bounds);image.dispose();
        }
        if(index==10 && age==10){_root.暂停=true;pausedFrame=ctx.lastFrame;}
        if(index==10 && age==16){check(ctx.lastFrame==pausedFrame,"pause freezes timeline and shots");_root.暂停=false;}
        if(index==11 && age==4)u.状态改变("兵器受击");
        if(index==12 && age==4)u.hp=0;
        if(index==13 && age==4)RockQueenBattleSkill.releaseEquipment(ref);
        if(index==30 && age==4)RockQueenBattleSkill.releaseEquipment(ref);
        if(index==17 && age==8){var old:Object=ctx;RockQueenBattleSkill.cancel(ctx);u.__weaponSkillInputConsumed=false;ManualCooldownService.reset(ManualCooldownService.WEAPON_SKILL_KEY);var again:Object=WeaponSkillInputService.updateUnit(u,true,true,null,++_root.帧计时器.当前帧数);ctx=u.__rockQueenCast;RockQueenBattleSkill.cleanup(old);check(again.released && ctx.active,"same-path repeated cast survives stale cleanup");events=[];}
        if(ctx.active && age<220)return;
        check(!ctx.active,"cast exits without a stuck state");
        if(index<10 || index==10 || index==17 || (index>18 && index!=30)) {
            var slot:Number=caseSlot;
            check(events.length==counts[slot],"exact event count expected="+counts[slot]+" actual="+events.length);
            if(slot>=3)check(u.长枪.value.shot==counts[slot],"ammo commits once per actual shot");
            check(u.状态==u.攻击模式+"站立","natural completion restores pose");
            if(slot<3) {
                var sum:Number=0;for(var e:Number=0;e<events.length;e++)sum+=events[e].power*ref.rockBlade.pellets;
                check(sum+.01>=legacyBudget(),"knife allocation covers legacy skill and equipment bonus "+sum);
                if(index<10 || index==27 || index==28) {
                    check(legacyTotal>0 && damageTotals[0]>=legacyTotal && damageTotals[1]>=legacyTotal && damageTotals[4]>=legacyTotal,"actual close HP loss exceeds old full damage budget");
                    trace("RockQueen DamageTotal: case="+index+" actual="+damageTotals+" legacy="+legacyTotal);
                }
            }
        } else if(index==18)check(events.length==2 && u.长枪.value.shot==u.长枪弹匣容量,"empty mid-cast stops after real remaining fuel");
        else check(events.length==0,"early interrupt produces no late hits");
        if(index==11)check(u.状态=="兵器受击","cleanup preserves replacement hurt state");
        if(index==12)check(u.状态=="血腥死","death leaves no firing lane");
        if(index==17)check(!WeaponSkillInputService.updateUnit(u,true,true,null,++_root.帧计时器.当前帧数),"held F cannot double trigger");
        if(index==0)check(events[0].age<10,"vocal first strike windup shortened");
        if(index==0)check(travel>=44 && travel<=46,"vocal idle input only moves a little");
        if(index==1)check(travel>=39 && travel<=41 && maxStep<=4.1,"keyboard idle input only drifts");
        if(index==20)check(maxStep>=24.9 && maxStep<=25.1,"held direction retains full keyboard dash speed");
        if(index==19)check(events[0].face=="左" && events[2].face=="右","vocal can reverse between thrusts");
        if(index==20)check(events[0].face=="右" && events[8].face=="左" && u.Z轴坐标<0,"keyboard steers both axes between passes");
        if(index==21 || index==22) {
            check(ctx.lastFrame<(index==21?60:78) && events[0].age<14,"held fire uses short entry and exit");
            var startFire:Function=u.man.开始射击;
            delete u.man.开始射击;
            RockQueenBattleSkill.resumeGun(ref);
            check(ref.rockResume!=undefined && u.__normalFireRequests==0,"handoff waits for the new shooting pose to bind");
            u.man.开始射击=startFire;
            RockQueenBattleSkill.resumeGun(ref);
            RockQueenBattleSkill.resumeGun(ref);
            check(u.__normalFireRequests==1 && !ref.rockResume,"equipment handoff requests ordinary fire once without a new press");
        }
        if(index==23)check(ctx.lastFrame==51 && !u.动作A && !ref.rockResume,"released trigger completes recovery without resuming fire");
        if(index==25)check(u._x<100.1 && travel<100.1,"keyboard dash respects native 12px wall collision x="+u._x+" travel="+travel+" probe="+_root.collisionLayer.hitTest(110,0,true));
        if(index==2)check(events[0].frame==18 && events[3].frame==24 && ctx.lastFrame==34,"guitar preserves charge then impact with lighter 34-frame recovery");
        if(index>=29)checkHealing();
        next();
    }
    private static function next():Void {
        _root.暂停=false;u.removeMovieClip();index++;
        if(index>30){finish();return;}startCase();
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;_root.暂停=false;
        trace("RockQueenBattleSkillTest Tests Passed: "+passed);
        trace("RockQueenBattleSkillTest Tests Failed: "+failed);
        _root.rockQueenTestComplete();
    }
}
