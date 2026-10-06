import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.neur.Event.EventDispatcher;

/** 加载现役素材SWF；经过真实工厂、运动委托、AABB、队列与消失帧，隔离于游戏及存档。 */
class org.flashNight.arki.unit.Action.Shoot.WeaponSpreadLifecycleTest {
    private static var passed:Number, failed:Number, ticks:Number, finished:Boolean;
    private static var library:MovieClip, driver:MovieClip, shooter:MovieClip, enemy:MovieClip;
    private static var loader:MovieClipLoader, listener:Object, saved:Object, records:Array;
    private static var fixtureCache:Object, emptyFixture:Object, hitFixture:Object;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[TEST_FAIL] WeaponSpreadLifecycleTest: " + label); }
    }
    private static function emptyCache(unit:Object, interval:Number):Object { return fixtureCache; }
    private static function noMap(x:Number, y:Number, precise:Boolean):Boolean { return false; }
    private static function hitMap(x:Number, y:Number, precise:Boolean):Boolean { return true; }
    private static function fixedDamage(bullet:Object, owner:Object, target:Object, multiplier:Number, dodge:String):Object {
        target.hp--; bullet.fixtureRecord.settlements++;
        return {actualScatterUsed:1,dodgeStatus:"HIT",scatterModelEnabled:false,triggerDisplay:function():Void {}};
    }
    private static function shape(parent:MovieClip, name:String, x:Number, y:Number, w:Number, h:Number):MovieClip {
        var mc:MovieClip = parent.createEmptyMovieClip(name, parent.getNextHighestDepth());
        mc.beginFill(0xffffff); mc.moveTo(x,y); mc.lineTo(x+w,y); mc.lineTo(x+w,y+h);
        mc.lineTo(x,y+h); mc.lineTo(x,y); mc.endFill(); return mc;
    }
    public static function runAllTests():Void {
        passed = failed = ticks = 0; finished = false; records = [];
        library = _root.createEmptyMovieClip("__spreadLifecycleLibrary", _root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__spreadLifecycleDriver", _root.getNextHighestDepth());
        driver.waited = 0;
        driver.onEnterFrame = function():Void {
            if (++this.waited > 240) { WeaponSpreadLifecycleTest.check(false,"source load timeout"); WeaponSpreadLifecycleTest.finish(); }
        };
        listener = {onLoadInit:function(loaded:MovieClip):Void { WeaponSpreadLifecycleTest.loaded(); },
            onLoadError:function(loaded:MovieClip, code:String):Void {
                WeaponSpreadLifecycleTest.check(false,"source SWF load " + code); WeaponSpreadLifecycleTest.finish();
            }};
        loader = new MovieClipLoader(); loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf", library), "request actual published source library");
    }
    private static function loaded():Void {
        try {
            var queue:Object = BulletQueueProcessor;
            var cache:Object = TargetCacheManager, damage:Object = DamageCalculator;
            saved = {world:_root.gameworld, clock:_root.帧计时器, paused:_root.暂停, target:_root.控制目标,
                collision:_root.collisionLayer, xmin:_root.Xmin, xmax:_root.Xmax, ymin:_root.Ymin, ymax:_root.Ymax,
                queues:queue.activeQueues, fake:queue.fakeUnits, uids:queue.queueUIDs,
                acquireEnemy:cache.acquireEnemyCache, damage:damage.calculateDamage, seed:LinearCongruentialEngine.getInstance().captureState()};
            _root.gameworld = library; library.子弹区域 = library;
            _root.帧计时器 = {当前帧数:0,eventBus:new EventDispatcher()}; _root.暂停 = false;
            _root.Xmin = -2000; _root.Xmax = 2000; _root.Ymin = -1000; _root.Ymax = 1000;
            _root.collisionLayer = {hitTest:noMap};
            emptyFixture = fixtureCache = {data:[],leftValues:[],rightValues:[],rightMaxValues:[]}; cache.acquireEnemyCache = emptyCache;
            damage.calculateDamage = fixedDamage;
            FactionManager.initialize(); BulletQueueProcessor.initialize();
            ColliderFactoryRegistry.init(); DamageManagerFactory.init();
            shooter = library.createEmptyMovieClip("fixtureShooter", 1000001);
            shooter.hp = 100; shooter.是否为敌人 = false; shooter.Z轴坐标 = 200; _root.控制目标 = shooter._name;
            enemy = library.createEmptyMovieClip("fixtureEnemy", 1000002);
            enemy._x = 260; enemy._y = enemy.Z轴坐标 = 200; enemy.hp = 100; enemy.是否为敌人 = true;
            enemy.area = shape(enemy,"area",-20,-130,40,140);
            enemy.aabbCollider = ColliderFactoryRegistry.getFactory("AABB").createFromUnitArea(enemy);
            enemy.flags = 0; enemy.中心高度 = 75; enemy.dispatcher = new EventDispatcher(); enemy.fixtureHitEvents = 0;
            enemy.dispatcher.subscribe("hit",function(target:Object):Void { target.fixtureHitEvents++; },enemy);
            var bounds:Object = enemy.aabbCollider;
            hitFixture = {data:[enemy],leftValues:[bounds.left],rightValues:[bounds.right],rightMaxValues:[bounds.right]};
            spawn("普通子弹", 0.6, 0, 0, "first-contracted");
            spawn("普通子弹", 1, 0, 0, "full-spread");
            spawn("普通子弹", undefined, 0.75, 0, "fractional-aim");
            spawn("穿刺子弹", 0.6, 0, 4, "pierce-contracted");
            for (var i:Number = 0; i < 36; i++) spawn("普通子弹", 0.6, 0, 0, "rapid-" + i);
            spawn("普通子弹",0.6,0,0,"contracted-hit"); records[records.length-1].collision = true;
            spawn("普通子弹",1,0,0,"full-spread-hit"); records[records.length-1].collision = true;
            verifyPierceRetirement();
            driver.onEnterFrame = function():Void { WeaponSpreadLifecycleTest.tick(); };
        } catch (error:Error) { check(false,"setup exception " + error); finish(); }
    }
    private static function verifyPierceRetirement():Void {
        var source:Object = {子弹种类:"穿刺子弹",baseAsset:"穿刺子弹",flags:4,stateFlags:0,
            _x:1000,_y:120,shootX:0,shootY:120,shootZ:200,Z轴坐标:200,霰弹值:1,
            发射者名:shooter._name,子弹速度:20,子弹散射度:0,hitCount:0,Z轴攻击范围:50};
        var probe:MovieClip = BulletFactory.createBulletInstance(source,shooter,0);
        probe.onEnterFrame = null; probe.gotoAndStop("消失");
        check(probe._parent===library && probe._currentframe>1,"pierce map probe uses actual retiring asset");
        check(!probe.shouldDestroy(probe),"pierce retiring frames do not restart from exceeded range");
        _root.collisionLayer.hitTest = hitMap;
        check(probe.shouldDestroy(probe),"pierce retiring frames still detect map");
        check((probe.stateFlags & 32)!=0,"pierce map detection writes STATE_HIT_MAP authority bit");
        _root.collisionLayer.hitTest = noMap; probe.removeMovieClip();
    }
    private static function spawn(type:String, scale:Number, aim:Number, flags:Number, label:String):Void {
        var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        // 避免零偏移/整数乘积遮掉问题；仍使用生产LCG，每发一次随机消耗。
        var seed:Number, offset:Number;
        do { seed = rng.captureState(); offset = rng.randomOffset(7); }
        while (offset == 0 || Math.abs(offset) == 5);
        rng.restoreState(seed);
        var source:Object = {子弹种类:type,baseAsset:type,flags:flags,stateFlags:0,
            _x:0,_y:120,shootX:0,shootY:120,shootZ:200,Z轴坐标:200,霰弹值:1,
            发射者名:shooter._name,子弹速度:20,子弹散射度:7,武器扩散倍率:scale,hitCount:0,Z轴攻击范围:50,伤害类型:"真伤",子弹威力:1};
        var bullet:MovieClip = BulletFactory.createBulletInstance(source,shooter,aim);
        var actualName:String = bullet._name;
        trace("[SPREAD_SPAWN] " + label + " name=" + actualName + " angle=" + bullet._rotation
            + " xy=" + bullet._x + "," + bullet._y + " velocity=" + bullet.xmov + "," + bullet.ymov
            + " box=" + bullet.aabbCollider.left + "," + bullet.aabbCollider.right);
        check(bullet._parent === library, label + " factory returns live actual clip");
        check(actualName.indexOf(".") < 0,label + " clip name is safe for Flash target paths");
        check(typeof(bullet.updateMovement) == "function" && typeof(bullet.onEnterFrame) == "function",label + " lifecycle is bound");
        check(isFinite(bullet.xmov + bullet.ymov) && bullet.xmov > 0,label + " finite flight velocity");
        check(isFinite(bullet.aabbCollider.left + bullet.aabbCollider.right + bullet.aabbCollider.top + bullet.aabbCollider.bottom),label + " finite generated collider");
        var expected:Number = aim + offset * ((scale > 0 && !(scale > 1)) ? scale : 1);
        check(Math.abs(bullet._rotation - expected) < 0.02,label + " retains fractional sampled angle");
        var precheck:Function = bullet.onEnterFrame; bullet.onEnterFrame = null;
        records[records.length] = {bullet:bullet,label:label,precheck:precheck,hit:false,moved:false,removed:false,allQueued:true,settlements:0};
        bullet.fixtureRecord = records[records.length-1];
    }
    private static function tick():Void {
        if (finished) return;
        try {
            _root.帧计时器.当前帧数 = ++ticks;
            for (var i:Number = 0; i < records.length; i++) {
                var r:Object = records[i]; var b:MovieClip = r.bullet;
                if (!b._parent) { r.removed = true; continue; }
                var beforeX:Number = b._x;
                fixtureCache = r.collision ? hitFixture : emptyFixture;
                r.precheck.call(b);
                var q:BulletQueue = BulletQueueProcessor.activeQueues["PLAYER"];
                if (b.area && !(q.getCount() > 0)) r.allQueued = false;
                if (Math.abs(b.Z轴坐标 - enemy.Z轴坐标) < b.Z轴攻击范围
                    && b.aabbCollider.checkCollision(enemy.aabbCollider,0).isColliding) r.hit = true;
                BulletQueueProcessor.processQueue();
                if (b._parent && b._x > beforeX) r.moved = true;
            }
            if (ticks >= 80) finish();
        } catch (error:Error) { check(false,"flight exception " + error); finish(); }
    }
    private static function finish():Void {
        if (finished) return; finished = true;
        for (var i:Number = 0; i < records.length; i++) {
            var r:Object = records[i]; var b:MovieClip = r.bullet;
            if (r.label=="pierce-contracted") trace("[PIERCE_RETIRE] tick="+ticks+" x="+b._x+" frame="+b._currentframe+" parent="+b._parent+" area="+b.area);
            check(r.allQueued,r.label + " enters real collision queue throughout flight");
            check(r.moved,r.label + " moved after generation");
            check(r.hit,r.label + " reaches distant real target AABB through depth gate");
            check(!b._parent,r.label + (r.collision ? " impact cleanup removes actual clip" : " range cleanup removes actual clip"));
            if (r.collision) check(r.settlements>0 && enemy.fixtureHitEvents>0,r.label+" actual collision queue settles and publishes hit");
            if (b._parent) b.removeMovieClip();
        }
        if (saved) {
            var queue:Object = BulletQueueProcessor; var cache:Object = TargetCacheManager, damage:Object = DamageCalculator;
            ChainUnitManager.resetAll(); queue.activeQueues = saved.queues; queue.fakeUnits = saved.fake; queue.queueUIDs = saved.uids;
            cache.acquireEnemyCache = saved.acquireEnemy; damage.calculateDamage = saved.damage; LinearCongruentialEngine.getInstance().restoreState(saved.seed);
            _root.帧计时器.eventBus.destroy();
            _root.gameworld = saved.world; _root.帧计时器 = saved.clock; _root.暂停 = saved.paused; _root.控制目标 = saved.target;
            _root.collisionLayer = saved.collision; _root.Xmin = saved.xmin; _root.Xmax = saved.xmax; _root.Ymin = saved.ymin; _root.Ymax = saved.ymax;
        }
        if (loader) loader.removeListener(listener); if (driver) driver.onEnterFrame = null;
        if (shooter) shooter.removeMovieClip(); if (enemy) { enemy.dispatcher.destroy(); enemy.removeMovieClip(); }
        trace("WeaponSpreadLifecycleTest Tests Passed: " + passed); trace("WeaponSpreadLifecycleTest Tests Failed: " + failed);
        if (library) library.removeMovieClip();
        _root.weaponSpreadLifecycleComplete();
        if (driver) driver.removeMovieClip();
    }
}
