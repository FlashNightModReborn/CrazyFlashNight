import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.bullet.BulletComponent.Movement.MovementSystem;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue;
import org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.neur.Event.EventDispatcher;

/**
 * 现役素材的纵向对象/MC回退、真实副武器提交->枪口转换->工厂->寻的->碰撞队列->清理。
 * 缓存使用已排序敌人夹具，伤害公式/表现为确定性边界；不加载游戏或真实库存/存档。
 * 不直接指定导弹目标，也不手工替换其运动、碰撞器或消失帧。
 */
class org.flashNight.arki.unit.Action.Shoot.WeaponProjectileFlightTest {
    private static var passed:Number, failed:Number, ticks:Number, phase:Number, finished:Boolean;
    private static var library:MovieClip, driver:MovieClip, loader:MovieClipLoader, listener:Object;
    private static var saved:Object, records:Array, fixtureCache:Object, captured:Object;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[TEST_FAIL] WeaponProjectileFlightTest: " + label); }
    }
    private static function shape(parent:MovieClip, name:String, x:Number, y:Number, w:Number, h:Number):MovieClip {
        var mc:MovieClip = parent.createEmptyMovieClip(name,parent.getNextHighestDepth());
        mc.beginFill(0xffffff); mc.moveTo(x,y); mc.lineTo(x+w,y); mc.lineTo(x+w,y+h);
        mc.lineTo(x,y+h); mc.lineTo(x,y); mc.endFill(); return mc;
    }
    private static function shallow(source:Object):Object {
        var result:Object = {}; for (var key:String in source) result[key] = source[key]; return result;
    }
    private static function spread(span:Number):Number { return LinearCongruentialEngine.getInstance().randomOffset(span); }
    private static function noMap(x:Number,y:Number,precise:Boolean):Boolean { return false; }
    private static function enemies(unit:Object,interval:Number):Object { return fixtureCache; }
    private static function search(unit:Object,interval:Number):Array { unit.fixtureSearchCalls++; return unit.fixtureEnemies; }
    private static function fixedDamage(bullet:Object,shooter:Object,target:Object,mult:Number,dodge:String):Object {
        var used:Number = 1;
        if ((bullet.flags & 2) != 0 && bullet.霰弹值 < -65535) {
            used = Math.min(1,(-bullet.霰弹值) & 0xffff); bullet.霰弹值 += used;
        }
        target.hp -= used; bullet.fixtureRecord.settlements++;
        return {actualScatterUsed:used,dodgeStatus:"HIT",scatterModelEnabled:false,triggerDisplay:function():Void {}};
    }
    // 与正式入口相同的初始化/工厂调用；音效、弹壳与伤害显示不属于本套件边界。
    private static function shoot(props:Object):Object {
        var unit:MovieClip = _root.gameworld[props.发射者];
        var angle:Number = ShootingAngleCalculator.calculate(props,unit);
        BulletFactory.prepareBulletData(props,unit);
        captured = BulletFactory.createBullet(props,unit,angle); return captured;
    }
    public static function runAllTests():Void {
        trace("[PROJECTILE_BEGIN] independent actual source load");
        passed = failed = ticks = phase = 0; finished = false; records = [];
        library = _root.createEmptyMovieClip("__projectileSourceLibrary",_root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__projectileFlightDriver",_root.getNextHighestDepth());
        driver.waited = 0;
        driver.onEnterFrame = function():Void {
            if (++this.waited > 240) { WeaponProjectileFlightTest.check(false,"source load timeout"); WeaponProjectileFlightTest.finish(); }
        };
        listener = {onLoadInit:function(mc:MovieClip):Void { WeaponProjectileFlightTest.loaded(); },
            onLoadError:function(mc:MovieClip,code:String):Void { WeaponProjectileFlightTest.check(false,"source library "+code); WeaponProjectileFlightTest.finish(); }};
        loader = new MovieClipLoader(); loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf",library),"load actual published bullet library");
    }
    private static function loaded():Void {
        if (finished) return;
        trace("[PROJECTILE_SETUP] library="+library+" driver="+driver);
        try {
            var queue:Object = BulletQueueProcessor, cache:Object = TargetCacheManager, movement:Object = MovementSystem, damage:Object = DamageCalculator;
            saved = {world:_root.gameworld,clock:_root.帧计时器,paused:_root.暂停,target:_root.控制目标,
                collision:_root.collisionLayer,xmin:_root.Xmin,xmax:_root.Xmax,ymin:_root.Ymin,ymax:_root.Ymax,
                random:_root.随机偏移,copy:_root.对象浅拷贝,shoot:_root.子弹区域shoot传递,
                queues:queue.activeQueues,fake:queue.fakeUnits,uids:queue.queueUIDs,probe:queue._raySettleProbe,
                acquireEnemy:cache.acquireEnemyCache,movementMap:movement.movementMap,initialized:movement.initialized,
                damage:damage.calculateDamage,seed:LinearCongruentialEngine.getInstance().captureState()};
            _root.gameworld = library; library.子弹区域 = library;
            library._x = 37; library._y = 23; library._xscale = 110; library._yscale = 90;
            _root.帧计时器 = {当前帧数:0,eventBus:new EventDispatcher(),获取敌人缓存:search}; _root.暂停 = false;
            _root.Xmin = -2000; _root.Xmax = 2000; _root.Ymin = -1000; _root.Ymax = 1000; _root.collisionLayer = {hitTest:noMap};
            _root.随机偏移 = spread; _root.对象浅拷贝 = shallow; _root.子弹区域shoot传递 = shoot;
            cache.acquireEnemyCache = enemies; damage.calculateDamage = fixedDamage; queue._raySettleProbe = null;
            // 对应现役 bullets_cases.xml 的同名条目；显式配置、不走手工绑定运动的快路。
            movement.movementMap = {}; movement.movementMap["横向拖尾追踪联弹-普通无壳子弹"] = {func:"DefaultMissile",param:{missileConfig:"default",usePreLaunch:false}};
            movement.initialized = true;
            FactionManager.initialize(); BulletQueueProcessor.initialize(); ColliderFactoryRegistry.init(); DamageManagerFactory.init();
            ChainUnitManager.getLayer().onEnterFrame = null;
            trace("[PROJECTILE_SETUP] factories ready");
            spawnVertical("纵向机枪联弹",false,0.6,0.75,"vertical-object");
            spawnVertical("纵向机枪联弹",true,0.6,0.75,"vertical-mc");
            spawnVertical("纵向联弹",false,0.6,-0.75,"pierce-object");
            spawnVertical("纵向联弹",true,1,-0.75,"pierce-mc-full");
            driver.onEnterFrame = function():Void { WeaponProjectileFlightTest.tick(); };
        } catch(error:Error) { check(false,"setup exception "+error); finish(); }
    }
    private static function target(name:String,x:Number,z:Number):MovieClip {
        var unit:MovieClip = library.createEmptyMovieClip(name,library.getNextHighestDepth());
        unit._x = x; unit._y = unit.Z轴坐标 = z; unit.hp = 100000; unit.是否为敌人 = true; unit.flags = 0; unit.中心高度 = 75;
        unit.area = shape(unit,"area",-27.5,-158.8,55,160);
        unit.aabbCollider = ColliderFactoryRegistry.getFactory("AABB").createFromUnitArea(unit);
        unit.dispatcher = new EventDispatcher(); unit.fixtureHitEvents = 0;
        unit.dispatcher.subscribe("hit",function(t:Object):Void { t.fixtureHitEvents++; },unit);
        return unit;
    }
    private static function owner(name:String,left:Boolean):MovieClip {
        var unit:MovieClip = library.createEmptyMovieClip(name,library.getNextHighestDepth());
        unit._y = unit.Z轴坐标 = 200; unit._xscale = left ? -100 : 100; unit.方向 = left ? "左" : "右"; unit.hp = 1000; unit.mp = 1000;
        unit.是否为敌人 = false; unit.攻击目标 = "无"; unit.fixtureSearchCalls = 0; unit.状态 = "长枪站立"; unit.攻击模式 = "长枪";
        unit.man = unit.createEmptyMovieClip("man",1); unit.dispatcher = new EventDispatcher();
        unit.dispatcher.subscribe("processShot",FireEventComponent.processShot,unit);
        unit.长枪 = {value:{shot:0,reloadCount:0}}; return unit;
    }
    private static function cacheFor(unit:MovieClip):Void {
        var a:Object = unit.aabbCollider;
        fixtureCache = {data:[unit],leftValues:[a.left],rightValues:[a.right],rightMaxValues:[a.right]};
    }
    private static function containsUnit(units:Array,mc:MovieClip):Boolean {
        for (var i:Number=0;i<units.length;i++) if (units[i]===mc) return true; return false;
    }
    private static function add(bullet:Object,unit:MovieClip,enemy:MovieClip,label:String,isObject:Boolean,vertical:Boolean,muzzle:MovieClip):Void {
        check(bullet != null && typeof(bullet.updateMovement)=="function",label+" production factory and lifecycle");
        var precheck:Function = bullet.onEnterFrame; if (!isObject) bullet.onEnterFrame = null;
        records.push({bullet:bullet,owner:unit,enemy:enemy,label:label,isObject:isObject,vertical:vertical,muzzle:muzzle,
            precheck:precheck,moved:false,broad:false,queued:true,finite:true,maxUnits:0,units:[],closest:Infinity,settlements:0,ownNarrow:false,spread:bullet.武器扩散倍率,externalArea:bullet.子弹区域area});
        bullet.fixtureRecord = records[records.length-1];
    }
    private static function spawnVertical(prefix:String,mc:Boolean,scale:Number,angle:Number,label:String):Void {
        var unit:MovieClip = owner("owner"+records.length,false);
        var enemy:MovieClip = records.length==0 ? target("verticalEnemy",260,200) : records[0].enemy;
        unit._rotation = angle;
        var unitType:String = label.indexOf("pierce")==0 ? "穿刺子弹" : "普通子弹";
        var props:Object = {子弹种类:prefix+"-"+unitType,发射者:unit._name,shootX:0,shootY:125,shootZ:200,
            子弹速度:20,子弹威力:1,子弹散射度:7,武器扩散倍率:scale,发射间隔毫秒:100,霰弹值:12,Z轴攻击范围:50,伤害类型:"真伤",角度偏移:0};
        var tpl:Object = _root.联弹系统.对象化模板[prefix]; if (mc) delete _root.联弹系统.对象化模板[prefix];
        var b:Object = shoot(props); if (mc) _root.联弹系统.对象化模板[prefix] = tpl;
        add(b,unit,enemy,label,!mc,true,null);
    }
    private static function spawnMissile(x:Number,z:Number,left:Boolean,label:String,moving:Boolean):Void {
        var unit:MovieClip = owner("missileOwner"+records.length,left);
        var enemy:MovieClip = target("missileEnemy"+records.length,x,z); unit.fixtureEnemies = [enemy];
        var muzzle:MovieClip = shape(unit.man,"muzzle",-4,-4,8,8); muzzle._y = -75;
        LongGunSubWeaponCore.configureUnit(unit,{weapontype:"突击步枪",subweapon:{name:"导弹飞行夹具",cd:1000,
            consumeMode:"onLoadGroup",consumeTiming:"onReloadCommit",capacity:4,initialLoaded:4,power:1,
            bullet:"横向拖尾追踪联弹-普通无壳子弹",split:4,diffusion:15,velocity:25,range:50,damageType:"真伤"}});
        if (moving) { unit.移动射击 = true; unit.状态 = "长枪行走"; }
        var props:Object = LongGunSubWeaponCore.prepareManBulletProps(unit,unit.man);
        props.角度偏移 = 1;
        _root.控制目标 = unit._name; captured = null;
        check(LongGunSubWeaponCore.executeShot(unit,muzzle,props),label+" actual subweapon commit");
        var b:Object = captured;
        check(Math.abs(b._x)<0.11 && Math.abs(b._y-125)<0.11 && b.Z轴坐标==200,label+" actual muzzle converts to world coordinates");
        check(unit.长枪副武器.value.shot==1 && unit.长枪.value.shot==0,label+" subweapon ammunition lane");
        trace("[PROJECTILE_BIRTH] "+label+" name="+b._name+" rotation="+b._rotation+" externalArea="+b.子弹区域area+" muzzle="+muzzle);
        add(b,unit,enemy,label,false,false,muzzle);
    }
    private static function live(r:Object):Boolean {
        return r.isObject ? !r.bullet.__chainDead : r.bullet._parent != undefined;
    }
    private static function observe(r:Object):Void {
        var b:Object = r.bullet;
        if (!live(r)) return;
        var a:Object = b.aabbCollider;
        if (!isFinite(a.left+a.right+a.top+a.bottom)) r.finite = false;
        var z:Number = b.Z轴坐标-r.enemy.Z轴坐标;
        if (z<50 && z>-50 && a.checkCollision(r.enemy.aabbCollider,z).isColliding) {
            r.broad = true;
            var geometry:Object = r.geometry;
            if (!geometry) geometry = r.geometry = new PolygonCollider();
            if (r.isObject) geometry.updateFromChainObject(b); else geometry.updateFromBullet(b,b.area);
            if (geometry.checkCollision(r.enemy.aabbCollider,z).isColliding) r.ownNarrow = true;
        }
        var dx:Number = b._x-r.enemy._x, dy:Number = b._y-(r.enemy._y-75);
        var dist:Number = Math.sqrt(dx*dx+dy*dy); if (dist<r.closest) r.closest = dist;
        var g:ChainGroup = ChainUnitManager.findGroupByBullet(b);
        if (g) {
            if (g.单元体列表.length>r.maxUnits) r.maxUnits = g.单元体列表.length;
            for (var u:Number=0;u<g.单元体列表.length;u++) {
                var mc:MovieClip = g.单元体列表[u].mc;
                if (mc && !containsUnit(r.units,mc)) r.units.push(mc);
            }
            if (r.vertical) {
                if (Math.abs(g.武器扩散倍率-r.spread)>0.0001) r.finite = false;
            }
        }
    }
    private static function tick():Void {
        if (finished) return;
        try {
            _root.帧计时器.当前帧数++;
            ++ticks;
            if (phase==0) {
                ChainUnitManager.tick(); cacheFor(records[0].enemy);
                for (var i:Number=0;i<records.length;i++) if (live(records[i]) && !records[i].isObject) records[i].precheck.call(records[i].bullet);
                var q:BulletQueue = BulletQueueProcessor.activeQueues["PLAYER"], list:Array = q.getBulletsReference();
                for (i=0;i<list.length;i++) list[i].fixtureQueuedFrame = ticks;
                for (i=0;i<records.length;i++) {
                    var r:Object = records[i]; observe(r);
                    if (ticks==2 && ChainUnitManager.findGroupByBullet(r.bullet)) r.bullet.武器扩散倍率 = 0.95;
                    if (live(r) && (r.isObject || r.bullet.area) && r.bullet.fixtureQueuedFrame!=ticks) r.queued = false;
                }
                BulletQueueProcessor.processQueue();
                for (i=0;i<records.length;i++) if (records[i].bullet._x>5) records[i].moved = true;
                // 联弹射程终态仍让剩余单元飞行；覆盖真实世界边界退场及下一帧组回收。
                if (ticks==160) {
                    verifyRecords(); cleanupRecords(); records = []; phase = 1; ticks = 0;
                    spawnMissile(12,200,false,"near-right",false); spawnMissile(350,200,false,"far-right",false);
                    spawnMissile(-12,200,true,"near-left",false); spawnMissile(-350,200,true,"far-left",false);
                    spawnMissile(350,280,false,"far-moving-depth-right",true); spawnMissile(-350,160,true,"far-moving-depth-left",true);
                }
            } else {
                ChainUnitManager.tick();
                for (i=0;i<records.length;i++) {
                    r = records[i]; if (!live(r)) continue;
                    var beforeX:Number = r.bullet._x; cacheFor(r.enemy); r.precheck.call(r.bullet);
                    q = BulletQueueProcessor.activeQueues["PLAYER"];
                    if (r.bullet.area && q.getCount()==0) r.queued = false;
                    observe(r); BulletQueueProcessor.processQueue();
                    if (live(r) && Math.abs(r.bullet._x-beforeX)>0.1) r.moved = true;
                }
                if (ticks>=180) finish();
            }
        } catch(error:Error) { check(false,"flight exception "+error); finish(); }
    }
    private static function verifyRecords():Void {
        for (var i:Number=0;i<records.length;i++) {
            var r:Object = records[i], b:Object = r.bullet;
            trace("[PROJECTILE_RESULT] "+r.label+" moved="+r.moved+" broad="+r.broad+" ownNarrow="+r.ownNarrow+" settlements="+r.settlements+" events="+r.enemy.fixtureHitEvents+" closest="+r.closest+" maxUnits="+r.maxUnits+" alive="+live(r));
            check(r.moved,r.label+" follows real production flight"); check(r.finite,r.label+" finite collider and frozen spread");
            check(r.queued,r.label+" enters actual collision queue"); check(r.broad,r.label+" reaches target through depth and broad phase");
            check(r.ownNarrow,r.label+" travelling geometry reaches target in narrow phase");
            check(r.settlements>0 && r.enemy.fixtureHitEvents>0,r.label+" passes actual queue narrow phase and publishes a hit");
            check(!live(r),r.label+" actual lifecycle removes host"); check(ChainUnitManager.findGroupByBullet(b)==null,r.label+" group unregisters");
            var hidden:Boolean = true; for (var u:Number=0;u<r.units.length;u++) if (r.units[u]._visible) hidden = false;
            check(r.units.length>0 && hidden,r.label+" all tracked visual units leave view");
            if (r.vertical) check(r.maxUnits==12,r.label+" production replenishment reaches configured twelve units");
            else {
                check(r.maxUnits==4 && r.spread==1,r.label+" preserves four trail units and excludes gun-spread reduction");
                check(r.externalArea!=r.muzzle,r.label+" travelling collision region belongs to bullet");
                check(r.owner.fixtureSearchCalls>0,r.label+" acquires through default search rather than designated target");
            }
        }
    }
    private static function cleanupRecords():Void {
        for (var i:Number=0;i<records.length;i++) {
            var r:Object = records[i]; if (live(r)) r.bullet.removeMovieClip();
            r.owner.dispatcher.destroy(); r.owner.removeMovieClip();
            if (r.enemy._parent) { r.enemy.dispatcher.destroy(); r.enemy.removeMovieClip(); }
        }
    }
    private static function finish():Void {
        if (finished) return; finished = true; verifyRecords(); cleanupRecords();
        if (saved) {
            ChainUnitManager.resetAll(); var queue:Object = BulletQueueProcessor, cache:Object = TargetCacheManager, movement:Object = MovementSystem, damage:Object = DamageCalculator;
            queue.activeQueues=saved.queues; queue.fakeUnits=saved.fake; queue.queueUIDs=saved.uids; queue._raySettleProbe=saved.probe;
            cache.acquireEnemyCache=saved.acquireEnemy; movement.movementMap=saved.movementMap; movement.initialized=saved.initialized; damage.calculateDamage=saved.damage;
            LinearCongruentialEngine.getInstance().restoreState(saved.seed); _root.帧计时器.eventBus.destroy();
            _root.gameworld=saved.world; _root.帧计时器=saved.clock; _root.暂停=saved.paused; _root.控制目标=saved.target;
            _root.collisionLayer=saved.collision; _root.Xmin=saved.xmin; _root.Xmax=saved.xmax; _root.Ymin=saved.ymin; _root.Ymax=saved.ymax;
            _root.随机偏移=saved.random; _root.对象浅拷贝=saved.copy; _root.子弹区域shoot传递=saved.shoot;
        }
        if(loader) loader.removeListener(listener); if(driver) driver.onEnterFrame = null; if(library) library.removeMovieClip();
        trace("WeaponProjectileFlightTest Tests Passed: "+passed); trace("WeaponProjectileFlightTest Tests Failed: "+failed);
        _root.weaponProjectileFlightComplete();
        if(driver) driver.removeMovieClip();
    }
}
