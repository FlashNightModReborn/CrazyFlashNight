import org.flashNight.arki.scene.*;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.bullet.BulletComponent.Movement.MovementSystem;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Loader.InfoLoader;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.neur.Event.EventDispatcher;

/** Test-only adapter: real factory/configuration/flight/collision/retirement.
 * Damage magnitude and target cache are explicit controlled boundaries. */
class org.flashNight.arki.scene.Cf6FixedProjectileHarness {
    private static var waiting:MovieClip,ready:Boolean=false,installed:Boolean=false;
    private static var saved:Object,world:MovieClip,samples:Array=[],groups:Array=[],cache:Object;
    private static var births:Number=0,hits:Number=0,errors:Number=0,searches:Number=0;
    private static var flightMutation:Object;
    private static function check(ok:Boolean,label:String):Void {
        if(!ok){errors++;trace("[FAIL] Cf6FixedProjectileHarness "+label);}
    }
    public static function run():Void {
        _root.cf6RealProjectile=true;ready=false;births=hits=errors=searches=0;
        waiting=_root.createEmptyMovieClip("cf6ProjectileConfigWait",_root.getNextHighestDepth());waiting.age=0;
        waiting.onEnterFrame=function():Void {
            if(++this.age>300){
                Cf6FixedProjectileHarness.check(false,"canonical bullet configuration load timeout");
                this.removeMovieClip();trace("FocusedTestRunId cf6-fixed-projectiles Complete: "+_root.cf6FixedNativeRunId);
            }
        };
        BulletInitializer.initializeAttributes();MovementSystem.initialize();
        InfoLoader.getInstance().onLoad(loaded);
    }
    private static function loaded(data:Object):Void {
        if(ready)return;ready=true;waiting.removeMovieClip();
        check(data.attributeData!=null && data.movementData!=null,"actual bullets_cases.xml parsed");
        check(BulletInitializer.getAttributeData("喷火束")!=null,"canonical flame ray configuration");
        _root.cf6FixedProjectileReady();
    }
    public static function install():Void {
        if(installed)return;installed=true;
        var targets:Object=TargetCacheManager,damage:Object=DamageCalculator;
        saved={enemyCache:targets.acquireEnemyCache,damage:damage.calculateDamage,random:_root.随机偏移,
            search:_root.帧计时器.获取敌人缓存,eventBus:_root.帧计时器.eventBus};
        saved.randomState=LinearCongruentialEngine.getInstance().captureState();
        LinearCongruentialEngine.getInstance().restoreState(20261107);
        trace("CF6_PROJECTILE_RANDOM seed=20261107; native LCG, original target geometry and hit assertions");
        targets.acquireEnemyCache=enemyCache;damage.calculateDamage=damageOnce;
        _root.随机偏移=function(span:Number):Number {return LinearCongruentialEngine.getInstance().randomOffset(span);};
        _root.帧计时器.获取敌人缓存=search;
        _root.帧计时器.eventBus=new EventDispatcher();
        FactionManager.initialize();ColliderFactoryRegistry.init();DamageManagerFactory.init();BulletQueueProcessor.initialize();
    }
    private static function enemyCache(unit:Object,interval:Number):Object {return cache;}
    private static function search(unit:Object,interval:Number):Array {
        searches++;var target:MovieClip=world.fixedTarget;
        return target.hp>0?[target]:[];
    }
    private static function damageOnce(bullet:Object,shooter:Object,target:Object,mult:Number,dodge:String):Object {
        var used:Number=1;
        if((bullet.flags&2)!=0 && bullet.霰弹值 < -65535){used=Math.min(1,(-bullet.霰弹值)&0xffff);bullet.霰弹值+=used;}
        target.hp-=used;hits++;
        var group:Object=bullet.__cf6DamageMember.group;
        if(group!=null){if(!isFinite(group.fixtureHits))group.fixtureHits=0;group.fixtureHits++;}
        return {actualScatterUsed:used,dodgeStatus:"HIT",scatterModelEnabled:false,triggerDisplay:function():Void {}};
    }
    public static function beginWorld(value:MovieClip):Void {
        if(!installed)return;
        BulletQueueProcessor.reset();ChainUnitManager.resetAll();
        world=value;samples=[];groups=[];flightMutation=null;cache={data:[],leftValues:[],rightValues:[],rightMaxValues:[]};
        ChainUnitManager.getLayer().onEnterFrame=null;
    }
    private static function syncTarget():Void {
        var target:MovieClip=world.fixedTarget;
        if(!(target.hp>0) || target.area==null){cache={data:[],leftValues:[],rightValues:[],rightMaxValues:[]};return;}
        target.flags=0;target.中心高度=75;
        if(target.aabbCollider==null)target.aabbCollider=ColliderFactoryRegistry.getFactory("AABB").createFromUnitArea(target);
        else target.aabbCollider.updateFromUnitArea(target);
        var a:Object=target.aabbCollider;
        cache={data:[target],leftValues:[a.left],rightValues:[a.right],rightMaxValues:[a.right]};
    }
    private static function groupRow(group:Object,props:Object,actor:Object):Object {
        for(var i:Number=0;i<groups.length;i++)if(groups[i].group===group)return groups[i];
        var bit:Number=actor.cf6CurrentFireBit;
        if(bit==0 && actor.cf6ActionState.variant=="grenade")bit=16;
        var slot:String=bit==1?"长枪":bit==2?"手枪":bit==4?"手枪2":"长枪副武器";
        var ceiling:Number=bit==16?2:actor.cf6FixedUnits(slot,props);
        var row:Object={group:group,type:props.子弹种类,identity:actor.cf6UnitIdentity,
            units:0,ceiling:ceiling,moved:false,maxLinked:0,frame:_root.帧计时器.当前帧数,bit:bit};
        groups.push(row);return row;
    }
    private static function captureBirths():Void {
        var api:Object=Cf6DamageGroups,members:Array=api.members;
        for(var i:Number=0;i<members.length;i++){
            var m:Object=members[i],bullet:Object=m.object;
            if(m.fixtureCaptured || m.retired)continue;m.fixtureCaptured=true;
            var row:Object=null;
            for(var g:Number=0;g<groups.length;g++)if(groups[g].group===m.group){row=groups[g];break;}
            if(row==null){check(false,"factory member lacks emission record");continue;}
            var units:Number=(bullet.flags&2)!=0?Number(bullet.联弹霰弹值):1;
            check(isFinite(units) && units>0,"actual born damage units are finite");
            row.units+=units;births++;
            // Exclude melee(1), chain(2), transparent/ray(8), unit projectile(512).
            if((bullet.flags&(1|2|8|512))==0 && bullet.速度Y===0 && isFinite(bullet.速度X)
                    && bullet.速度X!=0 && !bullet.ZY比例) {
                var heading:Number=bullet.速度X<0?180:0;
                check(Math.abs((bullet._rotation-heading+360)%360)<0.001,"fixed straight projectile art follows actual horizontal flight");
            }
            var sample:Object={member:m,row:row,object:bullet,startX:bullet._x,startY:bullet._y,
                precheck:bullet.onEnterFrame,clip:typeof bullet=="movieclip"};
            if(sample.clip)bullet.onEnterFrame=null;
            samples.push(sample);
        }
    }
    public static function emit(props:Object):Object {
        var actor:MovieClip=world[props.发射者],group:Object=props.cf6DamageGroup;
        check(group!=null,"every fixed root or descendant keeps its damage group");
        groupRow(group,props,actor);syncTarget();
        if(String(props.子弹种类).indexOf("横向联弹-")==0)trace("CF6_SHOT_STATE identity="+actor.cf6UnitIdentity
            +" seed="+LinearCongruentialEngine.getInstance().captureState()+" xyz="+props.shootX+","+props.shootY+","+props.shootZ
            +" velocity="+props.子弹速度+" diffusion="+props.子弹散射度+" target="+world.fixedTarget._x+","+world.fixedTarget._y);
        var angle:Number=ShootingAngleCalculator.calculate(props,actor);
        BulletFactory.prepareBulletData(props,actor);
        var bullet:Object=BulletFactory.createBullet(props,actor,angle);
        captureBirths();return bullet;
    }
    private static function mutateFlightTarget():Void {
        var suite:Object=Cf6FixedSoldierNativeTest,scenario:Object=suite.currentScenario;
        if(flightMutation!=null || scenario.flightMode==undefined)return;
        for(var i:Number=0;i<groups.length;i++){
            var row:Object=groups[i];
            if(row.type!="横向拖尾追踪联弹-普通无壳子弹" || !row.moved || row.maxLinked!=6
                || _root.帧计时器.当前帧数-row.frame<2 || row.group.ended)continue;
            var target:MovieClip=world.fixedTarget;
            flightMutation={group:row.group,mode:scenario.flightMode,searches:searches,hits:row.group.fixtureHits|0,
                oldKey:Cf6SoldierSignals.identity(target),oldVersion:target.version};
            if(scenario.flightMode=="loss")target.hp=0;
            else {
                var x:Number=target._x,z:Number=target.Z轴坐标;target.removeMovieClip();
                target=world.createEmptyMovieClip("fixedTarget",world.getNextHighestDepth());
                target._x=x;target._y=target.Z轴坐标=z;target.version=flightMutation.oldVersion;target.hp=100000;
                target.是否为敌人=false;target.dispatcher=new EventDispatcher();
                target.createEmptyMovieClip("area",target.getNextHighestDepth());
                target.area.beginFill(1);target.area.moveTo(-20,-120);target.area.lineTo(20,-120);
                target.area.lineTo(20,0);target.area.lineTo(-20,0);target.area.endFill();
                flightMutation.replacement=target;flightMutation.replacementHp=target.hp;
                check(Cf6SoldierSignals.identity(target)!==flightMutation.oldKey,"same path/version has a new target identity during actual flight");
            }
            trace("[CF6_PROJECTILE_TARGET_MUTATION] "+scenario.flightMode+" live="+row.group.live+" linked="+row.maxLinked+" moved="+row.moved);return;
        }
    }
    public static function pump():Void {
        if(!installed || world!==_root.gameworld || _root.暂停)return;
        mutateFlightTarget();syncTarget();ChainUnitManager.tick();
        for(var i:Number=0;i<samples.length;i++){
            var sample:Object=samples[i],bullet:Object=sample.object;
            if(sample.member.retired || bullet.__cf6DamageMember!==sample.member)continue;
            if(sample.clip && typeof sample.precheck=="function")sample.precheck.call(bullet);
            if(sample.member.retired)continue;
            if(Math.abs(bullet._x-sample.startX)+Math.abs(bullet._y-sample.startY)>.1)sample.row.moved=true;
            var chain:ChainGroup=ChainUnitManager.findGroupByBullet(bullet);
            if(chain!=null)sample.row.maxLinked=Math.max(sample.row.maxLinked,chain.单元体列表.length);
        }
        BulletQueueProcessor.processQueue();Cf6DamageGroups.observe();captureBirths();
    }
    public static function terminal(actor:Object):Boolean {return !Cf6DamageGroups.live(actor.cf6ActionRecord,-1);}
    private static function verifySingleFrameMiss(actor:MovieClip,paused:Boolean):Void {
        var group:Object=Cf6DamageGroups.begin(actor.cf6ActionRecord,-7);
        var props:Object={发射者:actor._name,子弹种类:"近战子弹",声音:"",霰弹值:1,子弹散射度:0,子弹威力:1,子弹速度:0,
            shootX:actor._x,shootY:actor._y,shootZ:actor.Z轴坐标,Z轴攻击范围:1,区域定位area:actor.area,cf6DamageGroup:group};
        BulletFactory.prepareBulletData(props,actor);
        var bullet:Object=BulletFactory.createBullet(props,actor,0);
        Cf6DamageGroups.seal(group);
        check(typeof bullet=="object" && typeof bullet.shouldDestroy=="function" && bullet.shouldDestroy(bullet)
            && group.born==1 && group.live==1 && !group.ended,"actual single-frame melee birth, paused="+paused);
        Cf6DamageGroups.observe();
        check(!group.ended,"a queued melee miss still owns its collision before drain");
        var prior:Boolean=_root.暂停;_root.暂停=paused;
        BulletQueueProcessor.processQueue();_root.暂停=prior;Cf6DamageGroups.observe();
        check(group.ended && group.live==0 && !group.unknown && bullet.aabbCollider==null
            && !(group.fixtureHits>0),"miss or pause drops the last real collider and releases its group, paused="+paused);
        trace("[CF6_ONE_FRAME_MELEE] paused="+paused+" born="+group.born+" live="+group.live+" ended="+group.ended+" colliderReleased="+(bullet.aabbCollider==null));
    }
    public static function verify(actor:MovieClip,label:String):Boolean {
        var before:Number=errors,owned:Number=0;
        if(label=="ordinary_line"){verifySingleFrameMiss(actor,false);verifySingleFrameMiss(actor,true);}
        for(var i:Number=0;i<groups.length;i++){
            var row:Object=groups[i],group:Object=row.group;
            if(row.identity!==actor.cf6UnitIdentity)continue;owned++;
            check(group.ended && !group.unknown && group.live==0,label+" actual group ended "+group.id);
            check(row.units<=row.ceiling,label+" descendant/linked units stay within reserved budget "+row.units+"/"+row.ceiling);
            if(row.type=="fsc7炮弹")check(group.born==2 && row.units==2,label+" carrier and child explosion share retirement");
            if(row.type=="横向拖尾追踪联弹-普通无壳子弹")check(row.maxLinked==6 && row.moved,label+" actual six-unit carrier follows bound target");
            trace("[CF6_PROJECTILE_GROUP] "+label+" type="+row.type+" born="+group.born+" units="+row.units
                +" ceiling="+row.ceiling+" hits="+(group.fixtureHits|0)+" moved="+row.moved+" maxLinked="+row.maxLinked+" ended="+group.ended);
        }
        var requiredHits:Boolean=label=="ordinary_line" || label=="primary_then_subweapon" || label=="real_launcher_load"
            || label=="g1111_rifle_fallback" || label=="g1111_rocket_fallback" || label=="bright_burst"
            || label=="reserve_gate" || label=="threshold_flush" || label=="finite_grenade";
        if(label.indexOf("admission_")==0)requiredHits=true;
        if(requiredHits){
            var contacts:Number=0;
            for(i=0;i<groups.length;i++)if(groups[i].identity===actor.cf6UnitIdentity)contacts+=groups[i].group.fixtureHits|0;
            check(contacts>0,label+" actual collision queue produces at least one controlled settlement");
        }
        if(label=="g1111_rocket_target_loss" || label=="g1111_rocket_target_replacement"){
            check(flightMutation!=null && flightMutation.group.ended && flightMutation.group.live==0,label+" actual carrier retires on target lifetime loss");
            check(searches===flightMutation.searches,label+" fixed carrier never enters generic target search");
            check((flightMutation.group.fixtureHits|0)===flightMutation.hits,label+" no post-loss collision settlement");
            if(flightMutation.mode=="replacement")check(flightMutation.replacement.hp===flightMutation.replacementHp,label+" same-path replacement remains unharmed");
        }
        check(Cf6DamageGroups.counts().unknown==0,label+" no unresolved creation");
        return before==errors;
    }
    public static function finish():Void {
        trace("Cf6FixedProjectileHarness: "+births+" actual births, "+hits+" collision settlements, "+errors+" failed");
        if(installed){
            BulletQueueProcessor.reset();ChainUnitManager.resetAll();
            var target:Object=TargetCacheManager,damage:Object=DamageCalculator;
            target.acquireEnemyCache=saved.enemyCache;damage.calculateDamage=saved.damage;
            _root.随机偏移=saved.random;
            LinearCongruentialEngine.getInstance().restoreState(saved.randomState);_root.帧计时器.获取敌人缓存=saved.search;_root.帧计时器.eventBus=saved.eventBus;
            installed=false;
        }
    }
}
