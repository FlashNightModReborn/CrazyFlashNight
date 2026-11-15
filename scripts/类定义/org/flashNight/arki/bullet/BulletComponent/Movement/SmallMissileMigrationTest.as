// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/SmallMissileMigrationTest.as

import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.UnitBulletLifecycle;
import org.flashNight.arki.bullet.BulletComponent.Loader.InfoLoader;
import org.flashNight.arki.bullet.BulletComponent.Movement.LoiteringMissileMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.MissileMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.MovementSystem;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.MissileConfig;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.neur.Event.EventDispatcher;

/**
 * Issue #258 专项回归测试：
 *  - 加载真实发布的『原版素材库-子弹.swf』与『公共素材位0.swf』；
 *  - 验证『小型导弹』与『毒刺』旧 area 子元件脚本已彻底剥离；
 *  - 加载真实 bullets_cases.xml 与 missileConfigs.xml；
 *  - 验证『毒刺』走 AcceleratedMovement + UnitBulletLifecycle（左右齐射加速、1击拦截、消失爆炸、TargetCache 清理）；
 *  - 验证『小型导弹』走 LoiteringMissileMovement（多初速 8/16/20 比例缩放、Z 加权优先、排除可拦截单位子弹、
 *    单次快照 + 18帧有限转向燃料 + 玩家走位可躲避巡飞弹特性、无目标/死亡发射者/NaN 兜底、150帧毁灭、跨 Z 命中与接地爆炸）。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.SmallMissileMigrationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var finished:Boolean;
    private static var bulletLib:MovieClip;
    private static var stingerLib:MovieClip;
    private static var driver:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var swfLoaded:Number;
    private static var infoReady:Boolean;
    private static var missileCfgReady:Boolean;
    private static var suitesStarted:Boolean;
    private static var saved:Object;
    private static var mapHit:Boolean;
    private static var fixtureEnemies:Array;
    private static var fixtureCacheObj:Object;
    private static var searchCalls:Number;
    private static var explosions:Array;
    private static var spawnedClips:Array;
    private static var waited:Number;
    private static var phase:Number;
    private static var vanishWait:Number;
    private static var activeShooter:MovieClip;
    private static var activeEnemy:MovieClip;
    private static var combatCases:Array;
    private static var combatIndex:Number;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[TEST_FAIL] SmallMissileMigrationTest: " + label);
        }
    }

    private static function noop():Void {
    }

    private static function shallowCopy(src:Object):Object {
        var res:Object = {};
        for (var k:String in src) {
            res[k] = src[k];
        }
        return res;
    }

    private static function halfRand():Number {
        return 0.5;
    }

    private static function shape(parent:MovieClip, name:String, x:Number, y:Number, w:Number, h:Number):MovieClip {
        var mc:MovieClip = parent.createEmptyMovieClip(name, parent.getNextHighestDepth());
        mc.beginFill(0xffffff);
        mc.moveTo(x, y);
        mc.lineTo(x + w, y);
        mc.lineTo(x + w, y + h);
        mc.lineTo(x, y + h);
        mc.lineTo(x, y);
        mc.endFill();
        return mc;
    }

    private static function acquireEnemyArr(shooter:MovieClip, interval:Number):Array {
        searchCalls++;
        return fixtureEnemies;
    }

    private static function acquireQueueCache(unit:Object, interval:Number):Object {
        return fixtureCacheObj;
    }

    private static function fixedDamage(bullet:Object, shooter:Object, target:Object, mult:Number, dodge:String):Object {
        target.hp -= 1;
        bullet.fixtureHitCount = (bullet.fixtureHitCount | 0) + 1;
        return {
            actualScatterUsed: 1,
            dodgeStatus: "HIT",
            scatterModelEnabled: false,
            triggerDisplay: noop
        };
    }

    private static function recordShoot(props:Object):Object {
        if (props.子弹种类 == "普通爆炸") {
            explosions.push({
                type: props.子弹种类,
                power: props.子弹威力,
                x: props.shootX,
                y: props.shootY,
                z: props.shootZ
            });
            var prevZone:MovieClip = _root.gameworld.子弹区域;
            _root.gameworld.子弹区域 = bulletLib;
            var expClip:Object = saved.shoot(props);
            _root.gameworld.子弹区域 = prevZone;
            if (expClip != null) spawnedClips.push(expClip);
            return expClip;
        }
        var bClip:Object = saved.shoot(props);
        if (bClip != null) spawnedClips.push(bClip);
        return bClip;
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        finished = false;
        swfLoaded = 0;
        infoReady = false;
        missileCfgReady = false;
        suitesStarted = false;
        mapHit = false;
        fixtureEnemies = [];
        fixtureCacheObj = {data: [], leftValues: [], rightValues: [], rightMaxValues: []};
        searchCalls = 0;
        explosions = [];
        spawnedClips = [];
        waited = 0;
        phase = 0;
        vanishWait = 0;
        activeShooter = null;
        activeEnemy = null;
        combatCases = [];
        combatIndex = 0;

        var tc:Object = TargetCacheManager;
        var queue:Object = BulletQueueProcessor;
        var dmg:Object = DamageCalculator;
        var dodge:Object = DodgeHandler;
        var movSys:Object = MovementSystem;
        var bInit:Object = BulletInitializer;

        saved = {
            world: _root.gameworld,
            clock: _root.帧计时器,
            paused: _root.暂停,
            target: _root.控制目标,
            collision: _root.collisionLayer,
            gravity: _root.重力加速度,
            xmin: _root.Xmin,
            xmax: _root.Xmax,
            ymin: _root.Ymin,
            ymax: _root.Ymax,
            random: _root.随机偏移,
            basicRand: _root.basic_random,
            copy: _root.对象浅拷贝,
            shoot: _root.子弹区域shoot传递,
            sound: _root.播放音效,
            msg: _root.发布消息,
            fx: _root.效果,
            client: _root.client,
            me: _root.me,
            depth: DepthManager.instance,
            staticFactory: StaticInitializer.factory,
            queues: queue.activeQueues,
            fake: queue.fakeUnits,
            uids: queue.queueUIDs,
            acquireQueue: tc.acquireEnemyCache,
            calcDamage: dmg.calculateDamage,
            calcDodge: dodge.calculateDodgeState,
            calcDodgeRes: dodge.calcDodgeResult,
            movMap: movSys.movementMap,
            movInit: movSys.initialized,
            attrMap: bInit.attributeMap,
            seed: LinearCongruentialEngine.getInstance().captureState()
        };

        _root.暂停 = false;
        _root.重力加速度 = 0.5;
        _root.Xmin = -5000;
        _root.Xmax = 5000;
        _root.Ymin = -2000;
        _root.Ymax = 2000;
        _root.随机偏移 = function(span:Number):Number {
            return LinearCongruentialEngine.getInstance().randomOffset(span);
        };
        _root.对象浅拷贝 = shallowCopy;
        _root.播放音效 = noop;
        _root.发布消息 = noop;
        _root.效果 = noop;
        _root.client = null;
        _root.me = null;
        _root.collisionLayer = {
            hitTest: function(x:Number, y:Number, precise:Boolean):Boolean {
                return SmallMissileMigrationTest.mapHit;
            }
        };
        _root.帧计时器 = {
            当前帧数: 0,
            帧率: 30,
            eventBus: new EventDispatcher(),
            获取敌人缓存: acquireEnemyArr,
            unitUpdateWheel: {
                add: function():Number { return 1; },
                remove: noop
            }
        };
        tc.acquireEnemyCache = acquireQueueCache;
        dmg.calculateDamage = fixedDamage;
        dodge.calculateDodgeState = function():String { return "未躲闪"; };
        dodge.calcDodgeResult = function():Object { return {}; };
        ColliderFactoryRegistry.init();
        if (DamageManagerFactory.Basic == null) {
            DamageManagerFactory.init();
        }
        FactionManager.initialize();
        StaticInitializer.factory = new AABBColliderFactory(32);

        MovementSystem.initialize();
        BulletInitializer.initializeAttributes();
        InfoLoader.getInstance().onLoad(function(data:Object):Void {
            SmallMissileMigrationTest.checkInfoData(data);
        });
        MissileConfig.getInstance().loadConfigs(
            function(configs:Object):Void {
                SmallMissileMigrationTest.checkMissileConfig(configs);
            },
            function():Void {
                SmallMissileMigrationTest.check(false, "missileConfigs.xml load failed");
                SmallMissileMigrationTest.missileCfgReady = true;
            }
        );

        bulletLib = _root.createEmptyMovieClip("__smallMissileLib", _root.getNextHighestDepth());
        stingerLib = _root.createEmptyMovieClip("__stingerLib", _root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__smallMissileDriver", _root.getNextHighestDepth());
        bulletLib._visible = false;
        stingerLib._visible = false;

        driver.onEnterFrame = function():Void {
            SmallMissileMigrationTest.tick();
        };

        listener = {
            onLoadInit: function(mc:MovieClip):Void {
                mc.stop();
                SmallMissileMigrationTest.swfLoaded++;
            },
            onLoadError: function(mc:MovieClip, code:String):Void {
                SmallMissileMigrationTest.check(false, "SWF load error: " + code);
                SmallMissileMigrationTest.finish();
            }
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf", bulletLib), "load published 原版素材库-子弹.swf");
        check(loader.loadClip("../flashswf/arts/new/公共素材位0.swf", stingerLib), "load published 公共素材位0.swf");
    }

    public static function checkInfoData(data:Object):Void {
        var mov:Object = (data != null) ? data.movementData : null;
        var attr:Object = (data != null) ? data.attributeData : null;
        check(mov != null && mov["毒刺"] != null && mov["毒刺"].func == "accelerated",
            "bullets_cases.xml parses 毒刺 movement.func=accelerated");
        check(attr != null && attr["毒刺"] != null && attr["毒刺"].unitBulletConfig != null
            && attr["毒刺"].unitBulletConfig.hitPoint == 1,
            "bullets_cases.xml keeps 毒刺 unitBullet hitPoint=1");
        check(mov != null && mov["小型导弹"] != null && mov["小型导弹"].func == "DefaultMissile"
            && mov["小型导弹"].param != null && mov["小型导弹"].param.missileConfig == "smallMissile"
            && mov["小型导弹"].param.usePreLaunch === false,
            "bullets_cases.xml parses 小型导弹 movement DefaultMissile/smallMissile/usePreLaunch=false");
        check(attr == null || attr["小型导弹"] == null || attr["小型导弹"].unitBulletConfig == undefined,
            "小型导弹 remains non-interceptable without unitBullet");
        infoReady = true;
    }

    public static function checkMissileConfig(configs:Object):Void {
        var cfg:Object = (configs != null) ? configs["smallMissile"] : null;
        check(cfg != null && cfg.mode == "loitering", "missileConfigs.xml parses smallMissile mode=loitering");
        check(cfg != null && cfg.baseVelocity == 20 && cfg.turnFrames == 18 && cfg.zDistanceWeight == 5
            && cfg.aimYOffset == -30 && cfg.reTossOnLock === true,
            "missileConfigs.xml smallMissile preserves loitering constants");
        missileCfgReady = true;
    }

    private static function makeWorldShooter(world:MovieClip, name:String, left:Boolean):MovieClip {
        var u:MovieClip = world.createEmptyMovieClip(name, world.getNextHighestDepth());
        u._x = left ? 800 : 100;
        u._y = 200;
        u.Z轴坐标 = 200;
        u._xscale = left ? -100 : 100;
        u.方向 = left ? "左" : "右";
        u.hp = 1000;
        u.hp满血值 = 1000;
        u.是否为敌人 = false;
        u.攻击目标 = "无";
        u.命中率 = 10000;
        u.等级 = 35;
        u.dispatcher = new EventDispatcher();
        return u;
    }

    private static function makeWorldEnemy(world:MovieClip, name:String, x:Number, z:Number, flags:Number):MovieClip {
        var e:MovieClip = world.createEmptyMovieClip(name, world.getNextHighestDepth());
        e._x = x;
        e._y = z;
        e.Z轴坐标 = z;
        e.hp = 10000;
        e.hp满血值 = 10000;
        e.等级 = 35;
        e.防御力 = 0;
        e.躲闪率 = 1;
        e.damageTakenMultiplier = 1;
        e.是否为敌人 = true;
        e.flags = flags;
        e.中心高度 = 75;
        e.area = shape(e, "area", -28, -160, 56, 165);
        e.aabbCollider = ColliderFactoryRegistry.getFactory("AABB").createFromUnitArea(e);
        e.dispatcher = new EventDispatcher();
        e.fixtureHits = 0;
        e.dispatcher.subscribe("hit", function(t:Object):Void { t.fixtureHits++; }, e);
        return e;
    }

    private static function setupWorldFor(lib:MovieClip):Void {
        _root.gameworld = lib;
        lib.子弹区域 = lib;
        lib.dispatcher = new EventDispatcher();
        lib.地图 = {僵尸型敌人总个数: 0, 僵尸型敌人场上实际人数: 0};
        DepthManager.instance = new DepthManager(lib, 0, 870655, 128);
        DepthManager.instance.calibrate(-2000, 2000);
        _root.子弹区域shoot传递 = recordShoot;
        BulletQueueProcessor.reset();
        BulletQueueProcessor.initialize();
    }

    private static function fireBullet(type:String, shooter:MovieClip, x:Number, y:Number, z:Number, vel:Number, diff:Number):MovieClip {
        var props:Object = {
            子弹种类: type,
            发射者: shooter._name,
            shootX: x,
            shootY: y,
            shootZ: z,
            子弹威力: 100,
            子弹速度: vel,
            子弹散射度: diff,
            霰弹值: 1,
            Z轴攻击范围: 50,
            击倒率: 0,
            伤害类型: "真伤",
            命中率: 10000,
            角度偏移: 0
        };
        return MovieClip(_root.子弹区域shoot传递(props));
    }

    private static function cleanupSpawned():Void {
        for (var i:Number = 0; i < spawnedClips.length; i++) {
            var c:Object = spawnedClips[i];
            if (c != null && c._parent != undefined) {
                c.removeMovieClip();
            }
        }
        spawnedClips = [];
        if (BulletQueueProcessor.activeQueues != null) {
            BulletQueueProcessor.reset();
        }
    }

    public static function tick():Void {
        if (finished) return;
        if (++waited > 600) {
            check(false, "async watchdog timeout phase=" + phase + " swf=" + swfLoaded + " info=" + infoReady + " cfg=" + missileCfgReady);
            finish();
            return;
        }
        try {
            if (phase == 0) {
                if (!suitesStarted && swfLoaded >= 2 && infoReady && missileCfgReady) {
                    suitesStarted = true;
                    testSwfAreaScriptsRemoved();
                    startStingerPhase();
                }
                return;
            }
            if (phase == 1) {
                vanishWait++;
                if (explosions.length >= 1 || vanishWait >= 8) {
                    check(explosions.length == 1 && explosions[0].type == "普通爆炸",
                        "毒刺 vanish frame emits 普通爆炸 once on interception");
                    cleanupSpawned();
                    if (activeShooter != null) {
                        activeShooter.dispatcher.destroy();
                        activeShooter.removeMovieClip();
                        activeShooter = null;
                    }
                    testSmallMissileSpeedScaling();
                    testSmallMissileTargetSelection();
                    combatCases = [
                        {label: "right_v20", shooterX: 100, shooterLeft: false, enemyX: 420, enemyZ: 200, vel: 20},
                        {label: "left_v20", shooterX: 800, shooterLeft: true, enemyX: 480, enemyZ: 200, vel: 20},
                        {label: "right_v8", shooterX: 100, shooterLeft: false, enemyX: 360, enemyZ: 200, vel: 8},
                        {label: "crossZ_v20", shooterX: 100, shooterLeft: false, enemyX: 400, enemyZ: 300, vel: 20}
                    ];
                    combatIndex = 0;
                    startNextCombatCase();
                }
                return;
            }
            if (phase == 2) {
                vanishWait++;
                if (explosions.length >= 1 || vanishWait >= 8) {
                    var c:Object = combatCases[combatIndex];
                    check(explosions.length == 1 && explosions[0].type == "普通爆炸",
                        c.label + " emits single 普通爆炸 on hit");
                    cleanupSpawned();
                    if (activeEnemy != null) {
                        activeEnemy.dispatcher.destroy();
                        activeEnemy.removeMovieClip();
                        activeEnemy = null;
                    }
                    if (activeShooter != null) {
                        activeShooter.dispatcher.destroy();
                        activeShooter.removeMovieClip();
                        activeShooter = null;
                    }
                    combatIndex++;
                    if (combatIndex < combatCases.length) {
                        startNextCombatCase();
                    } else {
                        testSmallMissileLoiteringDodge();
                        testSmallMissileEdgeAndNaNGuards();
                        finish();
                    }
                }
            }
        } catch (err:Error) {
            check(false, "tick exception: " + err);
            finish();
        }
    }

    private static function testSwfAreaScriptsRemoved():Void {
        var smProbe:MovieClip = bulletLib.attachMovie("小型导弹", "__smAreaProbe", bulletLib.getNextHighestDepth());
        check(smProbe != null && smProbe.area != undefined, "原版素材库-子弹.swf attaches 小型导弹 with area");
        check(smProbe.area.寻找攻击目标 == undefined && smProbe.area.基准速度 == undefined && smProbe.area.onEnterFrame == undefined,
            "小型导弹.area has no legacy onClipEvent(load)/onEnterFrame homing script");
        smProbe.removeMovieClip();

        var stProbe:MovieClip = stingerLib.attachMovie("毒刺", "__stAreaProbe", stingerLib.getNextHighestDepth());
        check(stProbe != null && stProbe.area != undefined, "公共素材位0.swf attaches 毒刺 with area");
        check(stProbe.area.横向加速度 == undefined && stProbe.area.onEnterFrame == undefined,
            "毒刺.area has no legacy onClipEvent(load)/onEnterFrame acceleration script");
        stProbe.removeMovieClip();
    }

    private static function startStingerPhase():Void {
        setupWorldFor(stingerLib);
        explosions = [];
        mapHit = false;
        fixtureEnemies = [];
        fixtureCacheObj = {data: [], leftValues: [], rightValues: [], rightMaxValues: []};

        var sL:MovieClip = makeWorldShooter(stingerLib, "stingerShooterL", true);
        var bL:MovieClip = fireBullet("毒刺", sL, 800, 125, 200, 8, 0);
        check(bL != null, "left-facing 毒刺 spawns");
        var lx0:Number = bL._x;
        bL.onEnterFrame();
        BulletQueueProcessor.processQueue();
        var ldx1:Number = bL._x - lx0;
        bL.onEnterFrame();
        BulletQueueProcessor.processQueue();
        var ldx2:Number = (bL._x - lx0) - ldx1;
        check(ldx1 < -8.5 && ldx1 > -9.5 && ldx2 < ldx1,
            "left-facing 毒刺 accelerates strictly left without double script");
        bL._y = 210;
        check(bL.shouldDestroy(bL) === true, "毒刺 triggers map/ground destroy when _y > Z");
        cleanupSpawned();
        sL.dispatcher.destroy();
        sL.removeMovieClip();

        explosions = [];
        _root.控制目标 = "stingerShooterR";
        var sR:MovieClip = makeWorldShooter(stingerLib, "stingerShooterR", false);
        var bR:MovieClip = fireBullet("毒刺", sR, 100, 125, 200, 8, 0);
        check(bR != null && bR._parent === stingerLib, "毒刺 attaches directly onto gameworld as UnitBullet");
        check((bR.flags & 512) != 0 && bR.NPC === true && bR.hitPoint == 1 && bR.unitBulletZTolerance == 25,
            "毒刺 preserves UnitBullet attributes and FLAG_UNIT_BULLET");

        var x0:Number = bR._x;
        bR.onEnterFrame();
        BulletQueueProcessor.processQueue();
        var dx1:Number = bR._x - x0;
        bR.onEnterFrame();
        BulletQueueProcessor.processQueue();
        var dx2:Number = (bR._x - x0) - dx1;
        bR.onEnterFrame();
        BulletQueueProcessor.processQueue();
        var dx3:Number = (bR._x - x0) - dx1 - dx2;
        check(dx1 > 8.5 && dx1 < 9.5 && dx2 > 9.5 && dx2 < 10.5 && dx3 > dx2,
            "right-facing 毒刺 accelerates monotonically at +1/frame without double script (dx=" + dx1 + "," + dx2 + "," + dx3 + ")");

        var deathEvents:Number = 0;
        bR.dispatcher.subscribe("death", function(u:MovieClip):Void {
            if (u._killed) deathEvents++;
        }, bR);
        UnitBulletLifecycle.onHit(bR, sR, null);
        delete bR.onEnterFrame;
        check(bR._killed === true && bR.hitPoint <= 0 && deathEvents == 1,
            "毒刺 1-hit interception kills cleanly and publishes death once");

        // 等待原生 Flash 帧推进进入第 3 帧 "消失" 执行普通爆炸与自毁
        activeShooter = sR;
        vanishWait = 0;
        phase = 1;
    }

    private static function testSmallMissileSpeedScaling():Void {
        setupWorldFor(bulletLib);
        _root.basic_random = halfRand;
        fixtureEnemies = [];
        fixtureCacheObj = {data: [], leftValues: [], rightValues: [], rightMaxValues: []};
        var s:MovieClip = makeWorldShooter(bulletLib, "scaleShooter", false);
        var mv:Object = MovementSystem.createMovementForBullet("小型导弹", s, 20, 0, 0, 20, 0);
        check(mv instanceof LoiteringMissileMovement && mv instanceof MissileMovement,
            "MovementSystem creates LoiteringMissileMovement subclass of MissileMovement for 小型导弹");

        var speeds:Array = [8, 16, 20];
        var stepX:Array = [];
        for (var i:Number = 0; i < speeds.length; i++) {
            var b:MovieClip = fireBullet("小型导弹", s, 100, 125, 200, speeds[i], 0);
            check(b != null && b._parent === bulletLib, "小型导弹 v=" + speeds[i] + " attaches");
            for (var t:Number = 0; t < 10; t++) {
                b.onEnterFrame();
                BulletQueueProcessor.processQueue();
            }
            var xBefore:Number = b._x;
            b.onEnterFrame();
            BulletQueueProcessor.processQueue();
            stepX.push(b._x - xBefore);
            b.removeMovieClip();
            BulletQueueProcessor.reset();
        }
        check(Math.abs(stepX[1] / stepX[0] - 2.0) < 0.05 && Math.abs(stepX[2] / stepX[0] - 2.5) < 0.05,
            "小型导弹 velocity scaling preserves 8:16:20 consumer speeds (" + stepX.join(",") + ")");
        cleanupSpawned();
        s.dispatcher.destroy();
        s.removeMovieClip();
    }

    private static function testSmallMissileTargetSelection():Void {
        setupWorldFor(bulletLib);
        _root.basic_random = halfRand;
        var s:MovieClip = makeWorldShooter(bulletLib, "selectShooter", false);
        var diffLane:MovieClip = makeWorldEnemy(bulletLib, "enemyDiffLane", 220, 110, 0);
        var sameLane:MovieClip = makeWorldEnemy(bulletLib, "enemySameLane", 300, 200, 0);
        var unitBulletEnemy:MovieClip = makeWorldEnemy(bulletLib, "enemyUnitBullet", 130, 200, 512);
        fixtureEnemies = [unitBulletEnemy, diffLane, sameLane];
        searchCalls = 0;

        var loiter:LoiteringMissileMovement = LoiteringMissileMovement.create(s, 20, 0, MissileConfig.getInstance().getConfig("smallMissile"), false);
        var probe:MovieClip = bulletLib.createEmptyMovieClip("selectProbe", bulletLib.getNextHighestDepth());
        probe._x = 100;
        probe._y = 125;
        probe.Z轴坐标 = 200;
        probe._rotation = 0;
        loiter.updateMovement(probe);
        check(loiter.hasTarget && loiter.target === sameLane && searchCalls > 0,
            "小型导弹 excludes FLAG_UNIT_BULLET and prefers same-Z lane via zDistanceWeight=5");

        probe.removeMovieClip();
        diffLane.dispatcher.destroy(); diffLane.removeMovieClip();
        sameLane.dispatcher.destroy(); sameLane.removeMovieClip();
        unitBulletEnemy.dispatcher.destroy(); unitBulletEnemy.removeMovieClip();
        cleanupSpawned();
        s.dispatcher.destroy(); s.removeMovieClip();
    }

    private static function startNextCombatCase():Void {
        var c:Object = combatCases[combatIndex];
        setupWorldFor(bulletLib);
        _root.basic_random = halfRand;
        explosions = [];
        var s:MovieClip = makeWorldShooter(bulletLib, "combatS_" + c.label, c.shooterLeft);
        s._x = c.shooterX;
        var e:MovieClip = makeWorldEnemy(bulletLib, "combatE_" + c.label, c.enemyX, c.enemyZ, 0);
        fixtureEnemies = [e];
        fixtureCacheObj = {
            data: [e],
            leftValues: [e.aabbCollider.left],
            rightValues: [e.aabbCollider.right],
            rightMaxValues: [e.aabbCollider.right]
        };

        var b:MovieClip = fireBullet("小型导弹", s, c.shooterX, 125, 200, c.vel, 0);
        var hitObserved:Boolean = false;
        for (var f:Number = 0; f < 130; f++) {
            _root.帧计时器.当前帧数++;
            if (b._parent != undefined && typeof(b.onEnterFrame) == "function") {
                b.onEnterFrame();
            }
            BulletQueueProcessor.processQueue();
            if (e.fixtureHits > 0) {
                hitObserved = true;
                delete b.onEnterFrame;
                break;
            }
        }
        check(hitObserved, c.label + " stationary target hit succeeds (hits=" + e.fixtureHits + ")");
        activeShooter = s;
        activeEnemy = e;
        vanishWait = 0;
        phase = 2;
    }

    private static function testSmallMissileLoiteringDodge():Void {
        // 专项验证巡飞弹『导引性能差 + 快照锁定 + 18帧有限转向 + 玩家走位可躲避』
        setupWorldFor(bulletLib);
        _root.basic_random = halfRand;
        explosions = [];
        var s:MovieClip = makeWorldShooter(bulletLib, "dodgeShooter", false);
        var playerTarget:MovieClip = makeWorldEnemy(bulletLib, "dodgeTarget", 380, 200, 0);
        fixtureEnemies = [playerTarget];
        fixtureCacheObj = {data: [], leftValues: [], rightValues: [], rightMaxValues: []};

        var mv:LoiteringMissileMovement = LoiteringMissileMovement.create(s, 20, 0, MissileConfig.getInstance().getConfig("smallMissile"), false);
        var mc:MovieClip = bulletLib.createEmptyMovieClip("dodgeClip", bulletLib.getNextHighestDepth());
        mc._x = 100;
        mc._y = 125;
        mc.shootX = 100;
        mc.shootY = 125;
        mc.shootZ = 200;
        mc.Z轴坐标 = 200;
        mc._rotation = 0;

        // Tick 1: locks snapshot at (380, 170)
        mv.updateMovement(mc);
        check(mv._lockedOnce === true && mv._lockX == 380 && mv._lockY == 170,
            "loitering missile locks initial snapshot once");

        // Player dodges far away immediately after lock
        playerTarget._x = 760;
        playerTarget._y = 320;
        playerTarget.Z轴坐标 = 320;

        for (var f:Number = 2; f <= 20; f++) {
            mv.updateMovement(mc);
        }
        check(mv._lockX == 380 && mv._lockY == 170 && mv._turnFramesLeft == 0 && !mv.hasTarget,
            "steering budget exhausts after 18 tracking frames without chasing moved target");

        var frozenRot:Number = mc._rotation;
        var reLocked:Boolean = false;
        for (var g:Number = 21; g <= 36; g++) {
            mv.updateMovement(mc);
            if (mv.hasTarget || Math.abs(mc._rotation - frozenRot) > 0.001) {
                reLocked = true;
            }
        }
        check(!reLocked, "loitering missile enters FreeFly without re-locking or cornering player");

        mc.removeMovieClip();
        playerTarget.dispatcher.destroy(); playerTarget.removeMovieClip();
        s.dispatcher.destroy(); s.removeMovieClip();
    }

    private static function testSmallMissileEdgeAndNaNGuards():Void {
        setupWorldFor(bulletLib);
        _root.basic_random = halfRand;
        fixtureEnemies = [];
        var s:MovieClip = makeWorldShooter(bulletLib, "edgeShooter", false);

        var mv:LoiteringMissileMovement = LoiteringMissileMovement.create(s, 20, 0, MissileConfig.getInstance().getConfig("smallMissile"), false);
        var mc:MovieClip = bulletLib.createEmptyMovieClip("edgeClip", bulletLib.getNextHighestDepth());
        mc._x = 100;
        mc._y = 125;
        mc.Z轴坐标 = 200;
        mc._rotation = 0;

        // NaN injection
        mv.updateMovement(mc);
        mc._x = NaN;
        mc._y = NaN;
        mc._rotation = NaN;
        mc.Z轴坐标 = NaN;
        mv.updateMovement(mc);
        check(isFinite(mc._x) && isFinite(mc._y) && isFinite(mc._rotation) && isFinite(mc.Z轴坐标),
            "LoiteringMissileMovement recovers from NaN coordinates");

        // Dead shooter & empty cache -> finishes 150-frame lifetime cleanly
        s.hp = 0;
        while (mv.frame < 150) {
            mv.updateMovement(mc);
        }
        check(mv.frame == 150 && !mv.hasTarget && mc.shouldDestroy(mc) === true,
            "no-target / dead-shooter loitering missile terminates at frame 150");

        mc.removeMovieClip();
        s.dispatcher.destroy(); s.removeMovieClip();
    }

    public static function finish():Void {
        if (finished) return;
        finished = true;
        cleanupSpawned();
        if (activeEnemy != null) {
            if (activeEnemy.dispatcher != null) activeEnemy.dispatcher.destroy();
            if (activeEnemy._parent != undefined) activeEnemy.removeMovieClip();
            activeEnemy = null;
        }
        if (activeShooter != null) {
            if (activeShooter.dispatcher != null) activeShooter.dispatcher.destroy();
            if (activeShooter._parent != undefined) activeShooter.removeMovieClip();
            activeShooter = null;
        }
        if (saved != null) {
            BulletQueueProcessor.activeQueues = saved.queues;
            BulletQueueProcessor.fakeUnits = saved.fake;
            BulletQueueProcessor.queueUIDs = saved.uids;
            TargetCacheManager.acquireEnemyCache = saved.acquireQueue;
            DamageCalculator.calculateDamage = saved.calcDamage;
            DodgeHandler.calculateDodgeState = saved.calcDodge;
            DodgeHandler.calcDodgeResult = saved.calcDodgeRes;
            var movSys:Object = MovementSystem;
            var bInit:Object = BulletInitializer;
            movSys.movementMap = saved.movMap;
            movSys.initialized = saved.movInit;
            bInit.attributeMap = saved.attrMap;
            StaticInitializer.factory = saved.staticFactory;
            DepthManager.instance = saved.depth;
            LinearCongruentialEngine.getInstance().restoreState(saved.seed);
            if (_root.帧计时器 && _root.帧计时器.eventBus) {
                _root.帧计时器.eventBus.destroy();
            }
            _root.gameworld = saved.world;
            _root.帧计时器 = saved.clock;
            _root.暂停 = saved.paused;
            _root.控制目标 = saved.target;
            _root.collisionLayer = saved.collision;
            _root.重力加速度 = saved.gravity;
            _root.Xmin = saved.xmin;
            _root.Xmax = saved.xmax;
            _root.Ymin = saved.ymin;
            _root.Ymax = saved.ymax;
            _root.随机偏移 = saved.random;
            _root.basic_random = saved.basicRand;
            _root.对象浅拷贝 = saved.copy;
            _root.子弹区域shoot传递 = saved.shoot;
            _root.播放音效 = saved.sound;
            _root.发布消息 = saved.msg;
            _root.效果 = saved.fx;
            _root.client = saved.client;
            _root.me = saved.me;
        }
        if (loader != null) loader.removeListener(listener);
        if (bulletLib != null) bulletLib.removeMovieClip();
        if (stingerLib != null) stingerLib.removeMovieClip();
        if (driver != null) {
            driver.onEnterFrame = null;
            driver.removeMovieClip();
        }
        trace("SmallMissileMigrationTest Tests Passed: " + passed);
        trace("SmallMissileMigrationTest Tests Failed: " + failed);
        if (typeof(_root.smallMissileMigrationComplete) == "function") {
            _root.smallMissileMigrationComplete();
        }
    }
}
