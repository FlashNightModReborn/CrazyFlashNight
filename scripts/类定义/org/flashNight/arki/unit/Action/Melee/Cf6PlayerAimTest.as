import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.Effect.ElderBeamVulnerability;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;

/** Actual resource timelines + canonical player area + production angle/movement/collision/damage. */
class org.flashNight.arki.unit.Action.Melee.Cf6PlayerAimTest {
    private static var world:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var cases:Array,stage:Number,ticks:Number,passed:Number,failed:Number;
    private static var loaded:Boolean,done:Boolean;
    private static var pending:Array,totalCases:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6PlayerAimTest: "+label);}
    }
    public static function runAllTests():Void {
        stage=0;passed=failed=0;done=false;pending=[];totalCases=0;_root.暂停=false;_root.是否阴影=false;
        _root.控制目标="__none";_root.控制目标全自动=false;
        _root.效果=function():Void {};_root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc.stop();mc._visible=false;};
        _root.敌人函数={配置音效:function():Void {},行走:function():Void {}};
        _root.子弹属性初始化=function(point:MovieClip,kind:String,unit:MovieClip):Object {return {子弹种类:kind,霰弹值:1};};
        _root.子弹区域shoot传递=function(data:Object):MovieClip {return Cf6PlayerAimTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.空手攻击力=100;this.等级=50;
            this._x=600;this._y=this.Z轴坐标=200;this.myxscale=100;
            this.状态="空手站立";this.方向="右";this.攻击目标="无";this.攻击模式="空手";
            this.硬直中=this.浮空=this.倒地=false;this.unitAI={data:{}};
            this.方向改变=function(d:String):Void {this.方向=d;this._xscale=(d=="左"?-1:1)*this.myxscale;};
            this.状态改变=function(state:String):Void {this.状态=state;this.gotoAndStop(state);};
            this.动画完毕=function():Void {this.攻击目标="无";this.状态改变("空手站立");};
            this.行走=this.移动=this.swapDepths=this.死亡检测=function():Void {};this.stop();
        };
        DamageManagerFactory.init();PinkNoiseEngine.getInstance();
        driver=_root.createEmptyMovieClip("__playerAimDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {Cf6PlayerAimTest.tick();};
        loadStage();
    }
    private static function loadStage():Void {
        loaded=false;ticks=0;cases=[];
        world=_root.createEmptyMovieClip("__playerAimWorld"+stage,_root.getNextHighestDepth());
        _root.gameworld=world;world._visible=false;
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6PlayerAimTest.onLoaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6PlayerAimTest.check(false,"load "+error);Cf6PlayerAimTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/"+(stage!=1?"Codex老头素材.swf":"Codex大刀机器人素材.swf"),world),"load stage "+stage);
    }
    private static function onLoaded(mc:MovieClip):Void {
        mc.stop();var heights:Array=[160,175,190],distances:Array=[300,500];
        for(var side:Number=0;side<2;side++){
            if(stage==2){
                for(var heightIndex:Number=0;heightIndex<heights.length;heightIndex++){
                    addCase(side,heights[heightIndex],300,"none");
                    addCase(side,heights[heightIndex],300,"afterFirst");
                }
                for(heightIndex=0;heightIndex<heights.length;heightIndex++){
                    addCase(side,heights[heightIndex],750,"none",undefined,undefined,"beam");
                    addCase(side,heights[heightIndex],750,"none");
                    addCase(side,heights[heightIndex],750,"afterFirst");
                }
                addCase(side,175,820,"outside",undefined,undefined,"beam");
                addCase(side,175,820,"outside");
                continue;
            }
            for(var h:Number=0;h<heights.length;h++)for(var d:Number=0;d<distances.length;d++)addCase(side,heights[h],distances[d],"none");
            addCase(side,175,400,"lane");addCase(side,175,400,"jump");
            if(stage==0 && _root.cf6AimBaseline!==true){
                var lanes:Array=[90,-90,180,-180,240,-240];
                for(var z:Number=0;z<lanes.length;z++)for(var x:Number=0;x<distances.length;x++)addCase(side,175,distances[x],"none",lanes[z],200);
                addCase(side,175,400,"crossLane",90,200);
                addCase(side,175,400,"none",180,-200);addCase(side,175,400,"none",180,1000);
            }
        }
        loaded=true;ticks=0;
    }
    private static function addCase(side:Number,height:Number,distance:Number,dodge:String,lane:Number,origin:Number,action:String):Void {
        var index:Number=cases.length,record:Object={shots:0,hits:0,damage:0,angles:[],powers:[],hitPowers:[],trackCalls:0,side:side};
        var actor:MovieClip=world.attachMovie(stage==0?"敌人-CF6老头人形":stage==1?"敌人-CF6大刀机器人":"敌人-CF6老头机器人",
            "aimActor"+index,world.getNextHighestDepth(),{fixtureRecord:record,老头变身:false});
        var target:MovieClip=_root.cf6MakePlayerTarget(world,"aimPlayer"+index,height);
        check(actor!=null && target.area!=null,"attach "+stage+"/"+index);
        cases.push({actor:actor,target:target,height:height,distance:distance,side:side,dodge:dodge,record:record,
            lane:lane==undefined?0:lane,origin:origin==undefined?200:origin,action:action==undefined?"heavyBeam":action});totalCases++;
    }
    private static function capture(data:Object):MovieClip {
        var actor:MovieClip=world[data.发射者],record:Object=actor.fixtureRecord;
        if(record==null)return null;
        var target:MovieClip=world[actor.攻击目标];if(target==null)return null;
        record.shots++;
        if(stage==2){
            record.powers.push(data.子弹威力);
            check(actor.Z轴坐标==200 && actor.方向==(record.side==0?"右":"左") && record.trackCalls==0,"heavy beam keeps its firing lane");
        }
        if(stage==0 && data.速度X!=undefined){
            var emitted:MovieClip=world.createEmptyMovieClip("crossLaneShot"+pending.length+"_"+ticks,world.getNextHighestDepth());
            emitted._x=data.shootX;emitted._y=data.shootY;emitted.Z轴坐标=data.shootZ;
            record.angles.push(data.角度偏移);
            record.cycle=actor.elderNextBurst-(actor.elderClock-actor.man._currentframe+1);
            pending.push({point:emitted,data:data,actor:actor,target:target,record:record});
            return emitted;
        }
        var targetBox:AABBCollider=new AABBCollider(0,0,0,0);targetBox.updateFromUnitArea(target);
        var hitBox:AABBCollider=new AABBCollider(0,0,0,0);
        var dz:Number=data.shootZ-target.Z轴坐标,hit:Boolean=false;
        if(stage==0){
            var angle:Number=ShootingAngleCalculator.calculate(data,actor);
            record.angles.push(angle);
            if(_root.cf6AimBaseline!==true)check(data.子弹种类=="穿刺子弹","human actual emitted kind");
            var point:MovieClip=world.createEmptyMovieClip("trajectory"+ticks,world.getNextHighestDepth());
            point._x=data.shootX;point._y=data.shootY;point.Z轴坐标=data.shootZ;
            point.xmov=data.子弹速度*Math.cos(angle*Math.PI/180);point.ymov=data.子弹速度*Math.sin(angle*Math.PI/180);
            var movement:LinearBulletMovement=LinearBulletMovement.create(undefined,undefined,undefined);
            for(var step:Number=0;step<30;step++){
                // A one-pixel center probe is stricter than the rendered piercing projectile.
                hitBox.left=point._x-0.5;hitBox.right=point._x+0.5;hitBox.top=point._y-0.5;hitBox.bottom=point._y+0.5;
                if(Math.abs(dz)<data.Z轴攻击范围 && hitBox.checkCollision(targetBox,dz).isColliding){hit=true;break;}
                movement.updateMovement(point);
            }
            check(point.Z轴坐标==data.shootZ,"trajectory preserves combat lane");point.removeMovieClip();
        }else{
            hitBox.updateFromBullet(actor.man.攻击点,data.区域定位area);
            hit=Math.abs(dz)<data.Z轴攻击范围 && hitBox.checkCollision(targetBox,dz).isColliding;
            if(stage==1 && _root.cf6AimBaseline!==true){
                var art:MovieClip=actor.man.bladebotBeamVisual;
                var visual:Object=art.getBounds(world),area:Object=data.区域定位area.getBounds(world);
                check(art!=null && Math.abs(art._rotation-actor.man.攻击点._rotation)<0.1,"beam art and contact rotate together");
                check(visual.xMin<=area.xMax && visual.xMax>=area.xMin && visual.yMin<=area.yMax && visual.yMax>=area.yMin,"visible beam overlaps contact volume");
            }
        }
        if(hit){
            if(stage==2)record.hitPowers.push(data.子弹威力);
            record.hits++;data.固伤=0;data.flags=0;data.hitCount=0;data.伤害加成=0;
            data.damageManager=DamageManagerFactory.resolveForBullet(data);
            var before:Number=target.hp;
            DamageCalculator.calculateDamage(data,actor,target,1,"未躲闪");
            check(target.hp<before,"production damage reduces player fixture HP");record.damage+=before-target.hp;
        }
        if(record.shots==1)trace("[CF6_PLAYER_HIT] stage="+stage+" actor="+actor._name+" scale="+actor._xscale
            +" muzzleY="+data.shootY+" targetTop="+targetBox.top+" targetBottom="+targetBox.bottom
            +" angle="+(stage==0?record.angles[0]:stage==1?actor.bladebotAttackOwner.beamAngle:0)+" hit="+hit+" dz="+dz);
        return null;
    }
    private static function evaluateCrossLane():Void {
        while(pending.length>0){
            var shot:Object=pending.shift(),point:MovieClip=shot.point,target:MovieClip=shot.target,actor:MovieClip=shot.actor,data:Object=shot.data;
            var record:Object=shot.record,targetBox:AABBCollider=new AABBCollider(0,0,0,0),hitBox:AABBCollider=new AABBCollider(0,0,0,0);
            check(point.updateMovement===actor.elderCrossLaneMovement && point.cf6LaneVX==data.速度X
                && point.cf6LaneVY==data.速度Y,"actual emitter installs the private linear Z movement");
            targetBox.updateFromUnitArea(target);var hit:Boolean=false,aboveGround:Boolean=true;
            for(var step:Number=0;step<45;step++){
                var dz:Number=point.Z轴坐标-target.Z轴坐标;
                hitBox.left=point._x-0.5;hitBox.right=point._x+0.5;hitBox.top=point._y-0.5;hitBox.bottom=point._y+0.5;
                if(Math.abs(dz)<data.Z轴攻击范围 && hitBox.checkCollision(targetBox,dz).isColliding){hit=true;break;}
                if(point._y>point.Z轴坐标){aboveGround=false;break;}
                point.updateMovement(point);
            }
            check(!hit || aboveGround,"cross-lane hit reaches the player before ground collision");
            if(hit){
                record.hits++;data.固伤=0;data.flags=0;data.hitCount=0;data.伤害加成=0;
                data.damageManager=DamageManagerFactory.resolveForBullet(data);var before:Number=target.hp;
                DamageCalculator.calculateDamage(data,actor,target,1,"未躲闪");
                check(target.hp<before,"cross-lane collision applies real damage");record.damage+=before-target.hp;
            }
            trace("[CF6_CROSS_LANE_HIT] actor="+actor._name+" originZ="+data.shootZ+" targetZ="+target.Z轴坐标
                +" vx="+point.cf6LaneVX+" vy="+point.cf6LaneVY+" vz="+point.cf6LaneVZ+" hit="+hit+" cycle="+record.cycle);
            point.removeMovieClip();
        }
    }
    private static function tick():Void {
        if(done)return;ticks++;
        if(!loaded){if(ticks>300){check(false,"load timeout");finish();}return;}
        evaluateCrossLane();
        if(ticks==3)for(var i:Number=0;i<cases.length;i++){
            var c:Object=cases[i],u:MovieClip=c.actor,t:MovieClip=c.target;
            u.myxscale=UnitUtil.getHeightPercentage(stage==0?180:stage==1?185:190);u._yscale=u.myxscale;u.方向改变(c.side==0?"右":"左");
            u._y=u.Z轴坐标=c.origin;t._y=t.Z轴坐标=c.origin+c.lane;
            t._x=u._x+(c.side==0?1:-1)*c.distance;u.攻击目标=t._name;
            if(stage==2){
                u.移动=function(direction:String,speed:Number):Void {
                    this.fixtureRecord.trackCalls++;
                    this.Z轴坐标+=direction=="上"?-speed:direction=="下"?speed:0;this._y=this.Z轴坐标;
                };
                t.buffManager=new BuffManager(t,{});ElderBeamVulnerability.applyToTarget(t,{peak:0.25,durationFrames:180});
            }
            u.状态改变(stage==0?"空手攻击":stage==1?"激光束":c.action=="beam"?"空手攻击":"蓄能重束");
        }
        if(ticks==7)for(i=0;i<cases.length;i++){
            c=cases[i];t=c.target;
            if(c.dodge=="lane")t._y=t.Z轴坐标=245;
            else if(c.dodge=="jump")t._y=20;
            else if(c.dodge=="crossLane"){t.Z轴坐标+=120;t._y=t.Z轴坐标;}
        }
        if(stage==2)for(i=0;i<cases.length;i++){
            c=cases[i];t=c.target;
            if(c.dodge=="afterFirst" && c.record.shots>0 && t.Z轴坐标<c.origin+64){
                t.Z轴坐标+=8;t._y=t.Z轴坐标;
            }
        }
        if(ticks==(stage==2?120:90)){
            for(i=0;i<cases.length;i++){
                c=cases[i];
                if(stage==2){
                    var normal:Boolean=c.action=="beam";
                    var wantedHits:Number=c.dodge=="outside"?0:c.dodge=="none"?(normal?1:4):1;
                    var declared:String=normal?"300":"50,100,150,200";
                    var landed:String=wantedHits==0?"":normal?"300":wantedHits==4?declared:"50";
                    check(c.record.powers.join(",")==declared,"actual normal or four ramping declarations "+i);
                    check(c.record.hits==wantedHits,"standing, distant or moving player receives expected contacts "+i+" distance="+c.distance+" got "+c.record.hits);
                    check(c.record.hitPowers.join(",")==landed,"range edge and moving after first hit reject the expected pulses "+i);
                    continue;
                }
                var expected:Number=stage==0?4:1;
                var shouldHit:Boolean=c.dodge=="none" && (_root.cf6AimBaseline!==true || c.height==190);
                check(c.record.shots==expected,"single authored action "+stage+"/"+i);
                check(c.record.hits==(shouldHit?expected:0),"player height / dodge "+stage+"/"+i+" height="+c.height+" dodge="+c.dodge+" hits="+c.record.hits);
                if(stage==0 && _root.cf6AimBaseline!==true)check(c.record.angles[0]==c.record.angles[3],"burst keeps initial aim "+i);
                if(stage==0 && Math.abs(c.lane)>30){
                    var expectedCycle:Number=59+Math.ceil((Math.abs(c.lane)-30)*1.5);
                    check(Math.abs(c.record.cycle-expectedCycle)<=2,"cross-lane cadence scales with initial Z distance "+i);
                    var originalClock:Number=c.actor.elderClock;c.actor.elderReadyAt=0;
                    c.actor.elderClock=c.actor.elderNextBurst-1;
                    check(c.actor.elderChooseAttack(400,Math.abs(c.lane),0,false)=="none","harassment cooldown rejects early restart "+i);
                    c.actor.elderClock=c.actor.elderNextBurst;
                    check(c.actor.elderChooseAttack(400,Math.abs(c.lane),0,false)=="burst","harassment resumes at its actual deadline "+i);
                    c.actor.elderClock=originalClock;
                }
            }
            loader.removeListener(listener);world.removeMovieClip();
            if(stage<(_root.cf6AimBaseline===true?1:2)){stage++;loadStage();}else finish();
        }
    }
    private static function finish():Void {
        if(done)return;done=true;delete driver.onEnterFrame;
        loader.removeListener(listener);world.removeMovieClip();driver.removeMovieClip();
        trace("Cf6PlayerAimTest: "+passed+" passed, "+failed+" failed; "+totalCases+" player-source cases; baseline="+(_root.cf6AimBaseline===true));
        _root.cf6PlayerAimComplete();
    }
}
