import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.StatHandler.ImpactHandler;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;

/** Paired real RSL timelines, canonical player area, native collision/damage/impact.
 * Controlled attributes/input schedules, center projectile only; not human PVE or whole-game balance.
 */
class org.flashNight.arki.unit.Action.Melee.Cf6PlayerPressureTest {
    private static var world:MovieClip,driver:MovieClip,walls:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var stage:Number,ticks:Number,passed:Number,failed:Number,caseCount:Number;
    private static var ready:Boolean,done:Boolean;
    private static var cases:Array,pending:Array,families:Array,names:Array,links:Array;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6PlayerPressureTest: "+label);}
    }
    public static function runAllTests():Void {
        stage=0;passed=failed=caseCount=0;done=false;
        families=["manman","bladebot","headbot","guard"];
        names=["蛮蛮","大刀机器人","大头机器人","光头保安"];
        links=["敌人-CF6蛮蛮","敌人-CF6大刀机器人","敌人-CF6大头机器人","敌人-CF6光头保安"];
        _root.暂停=false;_root.是否阴影=false;_root.控制目标="__pressure_no_manual";_root.控制目标全自动=false;
        _root.帧计时器={当前帧数:0};_root.钝感硬直时间=0;
        _root.效果=_root.播放音效=_root.发布消息=_root.add2map=_root.add2map2=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.敌人函数={配置音效:function():Void {},行走:function():Void {}};
        _root.敌人二级函数={攻击时移动:function():Void {},X轴追踪移动:function():Void {},Z轴追踪移动:function():Void {},计算攻击角度:function():Void {},固定角度移动:function():Void {}};
        _root.子弹属性初始化=function(point:MovieClip,kind:String,u:MovieClip):Object {return {子弹种类:kind,发射者:u._name,shootZ:u.Z轴坐标};};
        _root.子弹区域shoot传递=function(data:Object):MovieClip {Cf6PlayerPressureTest.capture(data);return null;};
        _root.子弹区域shoot=function(sound:String,pellets:Number,spread:Number,effect:String,kind:String,
            power:Number,speed:Number,lane:Number,hitEffect:String,shooter:String,sx:Number,sy:Number,
            sz:Number,friendly:Boolean,knockdown:Number,spark:String,horizontal:Number,vertical:Number,
            accuracy:Number,solid:Number,percent:Number,crumble:Number,ignore:Object,area:MovieClip):Void {
            Cf6PlayerPressureTest.capture({子弹种类:kind,子弹威力:power,子弹速度:speed,Z轴攻击范围:lane,
                发射者:shooter,shootX:sx,shootY:sy,shootZ:sz,击倒率:knockdown,
                水平击退速度:horizontal==undefined?3:horizontal,垂直击退速度:vertical==undefined?0:vertical,
                血量上限击溃:crumble,区域定位area:area,伤害类型:"物理"});
        };
        _root.初始化敌人模板=function():Void {Cf6PlayerPressureTest.initActor(this);};
        DamageManagerFactory.init();PinkNoiseEngine.getInstance();Mover.init();
        driver=_root.createEmptyMovieClip("__cf6PressureDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {Cf6PlayerPressureTest.tick();};loadStage();
    }
    private static function initActor(u:MovieClip):Void {
        u.hp=u.hp满血值=30000;u.等级=50;u.空手攻击力=100;u.防御力=1;u.damageTakenMultiplier=1;
        u.躲闪率=50;u.韧性系数=1;u.remainingImpactForce=0;u.ti61CrumbleTakenMultiplier=1;
        u.魔法抗性={波:0};u.dispatcher={publish:function():Void {}};
        u.shield=AdaptiveShield.createDormant("pressure-actor");u.shield.setOwner(u);
        u._x=200;u._y=u.Z轴坐标=200;u.myxscale=100;
        u.状态="空手站立";u.攻击模式="空手";u.方向="右";u.攻击目标="无";
        u.刚体=u.免疫击退=u.硬直中=u.浮空=u.倒地=false;u.unitAI={data:{}};
        u.行走X速度=3;u.行走Y速度=1.5;u.跑X速度=6;u.跑Y速度=3;
        u.方向改变=function(direction:String):Void {this.方向=direction;this._xscale=direction=="左"?-100:100;};
        if(u.状态改变==undefined)u.状态改变=function(state:String):Void {if(this.状态==state)return;this.状态=state;this.gotoAndStop(state);};
        u.动画完毕=function():Void {this.pressureRecord.completed++;this.倒地=this.浮空=false;this.状态改变("空手站立");};
        u.移动=function(direction:String,speed:Number):Void {Mover.move2D(this,direction,speed);};
        u.移动钝感硬直=u.死亡检测=function():Void {};
        u.被击移动=_root.cf6PressureKnockback;
        u.击飞浮空=function():Void {this.状态改变("被击");};u.击飞倒地=function():Void {this.动画完毕();};
        u.aabbCollider=new AABBCollider(0,0,0,0);
        if(u.行走==undefined)u.行走=function():Void {
            if(_root.暂停 || this.硬直中 || this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
            if(this.左行 || this.右行){this.方向改变(this.右行?"右":"左");this.移动(this.方向,this.跑X速度);}
            if(this.上行 || this.下行)this.移动(this.下行?"下":"上",this.跑Y速度);
        };
        u.stop();
    }
    private static function loadStage():Void {
        ready=false;ticks=0;cases=[];pending=[];
        world=_root.createEmptyMovieClip("__cf6PressureWorld"+stage,_root.getNextHighestDepth());
        _root.gameworld=world;world._visible=false;
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6PlayerPressureTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6PlayerPressureTest.check(false,"load "+error);Cf6PlayerPressureTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        var prefix:String=(stage&1)==0?"../tmp/cf6-performance-repair-20261031/before/":"../flashswf/arts/new/";
        check(loader.loadClip(prefix+"Codex"+names[Math.floor(stage/2)]+"素材.swf",world),"load paired stage "+stage);
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();var family:Number=Math.floor(stage/2);
        walls=_root.createEmptyMovieClip("__cf6PressureWalls"+stage,_root.getNextHighestDepth());
        _root.collisionLayer=walls;
        world.createEmptyMovieClip("地图",world.getNextHighestDepth());
        world.Xmin=-2000;world.Xmax=20000;world.Ymin=-500;world.Ymax=1500;
        DepthManager.instance=new DepthManager(world,100000,1000000,64);DepthManager.instance.calibrate(-500,1500);
        var profiles:Array=family==1?["standing","retreat","lane","jump","wall"]:["standing","retreat","lane","jump"];
        for(var side:Number=0;side<2;side++)for(var n:Number=0;n<profiles.length;n++){
            var rec:Object={shots:0,hits:0,damage:0,firstHit:-1,firstShot:-1,firstMelee:-1,completed:0,interruptions:0,pressureApplied:false,mode:profiles[n]};
            var u:MovieClip=world.attachMovie(links[family],"pressureUnit"+cases.length,world.getNextHighestDepth(),{pressureRecord:rec,光头保安变身:false});
            check(u!=null,"attach actual published actor "+stage+"/"+cases.length);
            var target:MovieClip=_root.cf6MakePlayerTarget(world,"pressurePlayer"+cases.length,175);
            target.hp=target.hp满血值=10000;target.防御力=300;target.韧性系数=1;target.躲闪率=50;target.remainingImpactForce=0;
            target.刚体=true;target.免疫击退=target.浮空=target.倒地=target.硬直中=false;
            target.方向=side==0?"左":"右";target.状态改变=target.移动钝感硬直=function():Void {};
            target.createEmptyMovieClip("man",2);target.被击移动=_root.cf6PressureKnockback;
            target.移动=function(direction:String,speed:Number):Void {this._x+=direction=="右"?speed:direction=="左"?-speed:0;};
            target.aabbCollider=new AABBCollider(0,0,0,0);
            // attachMovie's root initializer can run after this callback returns.
            // Place both bodies only on tick 3, after their real initialization.
            cases.push({actor:u,target:target,record:rec,side:side,originX:1000+cases.length*1500,originZ:200,profile:profiles[n]});
        }
        ready=true;ticks=0;
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=world[data.发射者],rec:Object=u.pressureRecord;
        if(rec==undefined)return;
        var target:MovieClip=world[u.pressureTarget];if(!(target.hp>0))return;
        rec.shots++;
        if(data.子弹种类!="近战子弹"){
            if(rec.firstShot<0)rec.firstShot=ticks;
            var angle:Number=ShootingAngleCalculator.calculate(data,u)*Math.PI/180;
            var point:MovieClip=world.createEmptyMovieClip("pressureProjectile"+world.getNextHighestDepth(),world.getNextHighestDepth());
            point._x=data.shootX;point._y=data.shootY;point.Z轴坐标=data.shootZ;
            point.xmov=data.子弹速度*Math.cos(angle);point.ymov=data.子弹速度*Math.sin(angle);
            pending.push({data:data,actor:u,target:target,point:point,age:0});return;
        }
        if(rec.firstMelee<0)rec.firstMelee=ticks;
        if(data.区域定位area==null)return;
        var bounds:Object=data.区域定位area.getBounds(world);
        var sourceBox:AABBCollider=new AABBCollider(0,0,0,0);
        sourceBox.left=bounds.xMin;sourceBox.right=bounds.xMax;sourceBox.top=bounds.yMin;sourceBox.bottom=bounds.yMax;
        target.aabbCollider.updateFromUnitArea(target);
        var dz:Number=data.shootZ-target.Z轴坐标;
        if(Math.abs(dz)<data.Z轴攻击范围 && sourceBox.checkCollision(target.aabbCollider,dz).isColliding)settle(data,u,target,rec);
    }
    private static function settle(data:Object,u:MovieClip,target:MovieClip,rec:Object):Void {
        data.固伤=0;data.flags=256;data.hitCount=0;data.伤害加成=0;
        data.damageManager=DamageManagerFactory.resolveForBullet(data);
        var impact:Object=DamageResult.getIMPACT(),display:Function=impact.triggerDisplay;
        impact.triggerDisplay=function():Void {};
        var hp:Number=target.hp,queue:Object=BulletQueueProcessor;
        var result:Object=queue.settleHit({bullet:data,shooter:u,Damage:DamageCalculator,flags:256,meleeMask:768},
            target,{overlapCenter:{x:target._x,y:target._y}},1,"未躲闪",true);
        impact.triggerDisplay=display;
        if(rec!=null){rec.hits++;rec.damage+=hp-target.hp;if(rec.firstHit<0)rec.firstHit=ticks;}
        var contact:MovieClip=world.createEmptyMovieClip("pressureImpact"+world.getNextHighestDepth(),world.getNextHighestDepth());
        for(var key:String in data)contact[key]=data[key];contact.破坏力=data.子弹威力;
        ImpactStateHandler.handleImpactState(target,contact,DamageResult(result),u.方向,true);contact.removeMovieClip();
    }
    private static function projectiles():Void {
        var movement:LinearBulletMovement=LinearBulletMovement.create(undefined,undefined,undefined);
        for(var i:Number=pending.length-1;i>=0;i--){
            var shot:Object=pending[i],point:MovieClip=shot.point,target:MovieClip=shot.target;
            shot.age++;movement.updateMovement(point);target.aabbCollider.updateFromUnitArea(target);
            var box:AABBCollider=new AABBCollider(0,0,0,0),dz:Number=point.Z轴坐标-target.Z轴坐标;
            box.left=point._x-0.5;box.right=point._x+0.5;box.top=point._y-0.5;box.bottom=point._y+0.5;
            var hit:Boolean=target.hp>0 && Math.abs(dz)<shot.data.Z轴攻击范围 && box.checkCollision(target.aabbCollider,dz).isColliding;
            if(hit)settle(shot.data,shot.actor,target,shot.actor.pressureRecord);
            if(hit || shot.age>=120 || !(target.hp>0)){point.removeMovieClip();pending.splice(i,1);}
        }
    }
    private static function tick():Void {
        if(done)return;ticks++;_root.帧计时器.当前帧数++;
        if(!ready){if(ticks>600){check(false,"load watchdog");finish();}return;}
        var family:Number=Math.floor(stage/2);
        for(var i:Number=0;i<cases.length;i++){
            var c:Object=cases[i],u:MovieClip=c.actor,target:MovieClip=c.target,rec:Object=c.record;
            if(ticks==3){
                u._x=c.originX;u._y=u.Z轴坐标=c.originZ;u.方向改变(c.side==0?"右":"左");
                var distance:Number=family==3?65:family==2?150:300;
                target._x=u._x+(c.side==0?distance:-distance);target._y=target.Z轴坐标=c.originZ;
                u.pressureTarget=target._name;
                check(u.方向==(c.side==0?"右":"左") && Math.abs(target._x-u._x)==distance,"post-initialization player placement "+stage+"/"+i);
                if(c.profile=="wall"){
                    target.Z轴坐标=target._y=220;
                    walls.beginFill(0);walls.moveTo(u._x-700,201);walls.lineTo(u._x+700,201);walls.lineTo(u._x+700,600);walls.lineTo(u._x-700,600);walls.lineTo(u._x-700,201);walls.endFill();
                    check(walls.hitTest(u._x,203,true),"wall fixture blocks intended cell "+i);walls._visible=false;
                }
                u.攻击目标=target._name;
                u.manmanNextWolf=10000;u.headbotNextRetreatBlast=10000;
                u.状态改变(family==0?"空手攻击":family==1?"旋刃冲刺":"近战");
            }
            if(ticks>=24 && ticks<72){
                if(c.profile=="retreat")target._x+=c.side==0?3:-3;
                if(c.profile=="lane"){target.Z轴坐标+=2;target._y=target.Z轴坐标;}
                if(c.profile=="jump")target._y=target.Z轴坐标-Math.sin((ticks-24)/48*Math.PI)*90;
            }else if(c.profile=="jump")target._y=target.Z轴坐标;
            if(family==0 && !rec.pressureApplied && u.man._currentframe==24 && u.manmanAttackOwner!=null){
                rec.pressureApplied=true;
                var before:String=u.状态;
                settle({子弹种类:"近战子弹",子弹威力:100,击倒率:1,水平击退速度:3,垂直击退速度:0,伤害类型:"物理"},target,u,null);
                if(u.状态!=before)rec.interruptions++;
            }
            if(c.profile=="wall" && u.Z轴坐标>201)rec.crossedWall=true;
            u.shield.update(1);
        }
        projectiles();
        if(ticks==180){
            for(i=0;i<cases.length;i++){
                c=cases[i];u=c.actor;rec=c.record;caseCount++;
                check(isFinite(rec.damage) && rec.damage>=0,"finite settled damage "+stage+"/"+i);
                if((stage&1)==1 && c.profile=="wall")check(rec.crossedWall!==true,"after dash respects actual map collision");
                trace('[CF6_PRESSURE] {"variant":"'+((stage&1)==0?"before":"after")+'","family":"'+families[family]+'","profile":"'+c.profile+'","side":'+c.side+',"contacts":'+rec.shots+',"hits":'+rec.hits+',"damage":'+Math.round(rec.damage)+',"firstHit":'+rec.firstHit+',"firstMelee":'+rec.firstMelee+',"firstShot":'+rec.firstShot+',"interruptions":'+rec.interruptions+',"crossedWall":'+(rec.crossedWall===true?'true':'false')+'}');
            }
            loader.removeListener(listener);world.removeMovieClip();walls.removeMovieClip();stage++;
            if(stage<8)loadStage();else finish();
        }
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        if(loader!=null)loader.removeListener(listener);
        trace("Cf6PlayerPressureTest: "+passed+" passed, "+failed+" failed; "+caseCount+" paired player-source cases");
        world.removeMovieClip();walls.removeMovieClip();driver.removeMovieClip();_root.cf6PlayerPressureComplete();
    }
}
