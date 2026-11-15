import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.MovementSystem;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;

/**
 * 爆炸中心散射测试套件：覆盖 XML 解析与校验、真实 3XD的素材 / 原版素材库-子弹 联调、
 * NA45 母弹单位/撞墙/落地散射、天然最大射程不散射、Boss Lady 爆炸狙击子弹回归、
 * 0~360 随机散射与跟随母弹飞行方向、次级穿刺子弹穿透、毫秒暂停隔离计时与幂等防嵌套。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.ExplosionScatterTest {
    private static var passed:Number, failed:Number, ticks:Number, loaded:Number, phase:Number;
    private static var done:Boolean, xmlReady:Boolean;
    private static var mapWallActive:Boolean, mapWallX:Number, rngCursor:Number, mockClockMs:Number;
    private static var world:MovieClip, xdLib:MovieClip, stockLib:MovieClip, fxLayer:MovieClip, driver:MovieClip;
    private static var shooter:MovieClip;
    private static var targets:Array, spawned:Array, records:Array, cache:Object;
    private static var loader:MovieClipLoader, listener:Object, saved:Object;
    private static var configured:ExplosionScatterProfile;
    private static var tag:String, live:Object, bornAt:Number, phaseFrames:Number;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[TEST_FAIL] ExplosionScatterTest: " + name);
        }
    }

    private static function close(a:Number, b:Number, eps:Number):Boolean {
        var tol:Number = (eps > 0) ? eps : 0.001;
        return Math.abs(a - b) < tol;
    }

    private static function noop():Void {}

    private static function shallow(source:Object):Object {
        var result:Object = {};
        for (var key:String in source) {
            result[key] = source[key];
        }
        return result;
    }

    private static function acquire(unit:Object, interval:Number):Object {
        return cache;
    }

    private static function hitDodge():String {
        return "未躲闪";
    }

    private static function dodgeResult():Object {
        return {};
    }

    public static function mapHitAt(x:Number, y:Number):Boolean {
        return mapWallActive && x >= mapWallX;
    }

    private static function mockedNow():Number {
        return mockClockMs;
    }

    private static function makeSeqRng(values:Array):Function {
        rngCursor = 0;
        return function():Number {
            var idx:Number = rngCursor % values.length;
            rngCursor++;
            return values[idx];
        };
    }

    public static function runAllTests():Void {
        passed = failed = ticks = loaded = phase = 0;
        done = xmlReady = mapWallActive = false;
        mapWallX = 999999;
        mockClockMs = 1000;
        targets = [];
        spawned = [];
        records = [];
        tag = "load";

        var tc:Object = TargetCacheManager;
        var dodge:Object = DodgeHandler;
        saved = {
            world: _root.gameworld,
            clock: _root.帧计时器,
            paused: _root.暂停,
            collision: _root.collisionLayer,
            gravity: _root.重力加速度,
            xmin: _root.Xmin,
            xmax: _root.Xmax,
            ymin: _root.Ymin,
            ymax: _root.Ymax,
            copy: _root.对象浅拷贝,
            sound: _root.播放音效,
            soundMgr: _root.soundEffectManager,
            message: _root.发布消息,
            fx: _root.效果,
            depth: DepthManager.instance,
            shoot: _root.子弹区域shoot传递,
            acquire: tc.acquireEnemyCache,
            dodge: dodge.calculateDodgeState,
            dodgeResult: dodge.calcDodgeResult
        };

        _root.暂停 = false;
        _root.重力加速度 = 0.5;
        _root.帧计时器 = {当前帧数: 0, 帧率: 30, unitUpdateWheel: {add: function():Number { return 1; }, remove: noop}};
        _root.Xmin = -10000;
        _root.Xmax = 10000;
        _root.Ymin = -10000;
        _root.Ymax = 10000;
        _root.对象浅拷贝 = shallow;
        _root.播放音效 = _root.发布消息 = _root.效果 = noop;
        _root.soundEffectManager = {playSound: noop};
        _root.collisionLayer = {hitTest: function(x:Number, y:Number, flag:Boolean):Boolean {
            return ExplosionScatterTest.mapHitAt(x, y);
        }};
        tc.acquireEnemyCache = acquire;
        dodge.calculateDodgeState = hitDodge;
        dodge.calcDodgeResult = dodgeResult;

        ColliderFactoryRegistry.init();
        FactionManager.initialize();
        PinkNoiseEngine.getInstance();
        StaticInitializer.factory = new AABBColliderFactory(32);
        MovementSystem.initialize();

        InfoLoader.getInstance().onLoad(function(data:Object):Void {
            var attr:Object = data.attributeData["爆炸集束子弹"];
            ExplosionScatterTest.configured = (attr != null) ? attr.explosionScatter : null;
            ExplosionScatterTest.xmlReady = (ExplosionScatterTest.configured != null);
        });

        cache = {data: [], leftValues: [], rightValues: [], rightMaxValues: []};
        xdLib = _root.createEmptyMovieClip("__scatterXdLib", _root.getNextHighestDepth());
        xdLib._x = 0;
        xdLib._y = 0;
        xdLib._visible = false;

        stockLib = _root.createEmptyMovieClip("__scatterStockLib", _root.getNextHighestDepth());
        stockLib._x = 0;
        stockLib._y = 0;
        stockLib._visible = false;

        driver = _root.createEmptyMovieClip("__scatterDriver", _root.getNextHighestDepth());
        driver.onEnterFrame = function():Void {
            try {
                ExplosionScatterTest.tick();
            } catch (e) {
                ExplosionScatterTest.check(false, "native tick exception: " + e);
                ExplosionScatterTest.finish();
            }
        };

        listener = {
            onLoadInit: function(mc:MovieClip):Void {
                mc.stop();
                mc._x = 0;
                mc._y = 0;
                ExplosionScatterTest.loaded++;
            },
            onLoadError: function(mc:MovieClip, code:String):Void {
                ExplosionScatterTest.check(false, "published swf load failed: " + code);
                ExplosionScatterTest.finish();
            }
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/3XD的素材.swf", xdLib), "request published 3XD的素材.swf");
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf", stockLib), "request published 原版素材库-子弹.swf");
    }

    private static function initializeWorld():Void {
        world = _root.createEmptyMovieClip("__scatterWorld", _root.getNextHighestDepth());
        world._x = 0;
        world._y = 0;
        world._visible = false;
        _root.gameworld = world;
        world.子弹区域 = xdLib;
        world.dispatcher = new EventDispatcher();
        world.地图 = {僵尸型敌人总个数: 0, 僵尸型敌人场上实际人数: 0};
        fxLayer = world.createEmptyMovieClip("效果", 900003);
        DepthManager.instance = new DepthManager(world, 0, 870655, 128);
        DepthManager.instance.calibrate(-1000, 1000);
        createShooter("右");
        _root.子弹区域shoot传递 = recordShot;
        BulletQueueProcessor.reset();
        BulletQueueProcessor.initialize();
    }

    private static function createShooter(dir:String):Void {
        if (shooter != null && shooter._parent != null) {
            shooter.dispatcher.destroy();
            shooter.removeMovieClip();
        }
        shooter = world.createEmptyMovieClip("scatterShooter", 900001);
        shooter.hp = 1000;
        shooter.是否为敌人 = false;
        shooter.命中率 = 10000;
        shooter.伤害加成 = 0;
        shooter.等级 = 35;
        shooter.方向 = dir;
        shooter.Z轴坐标 = 0;
        shooter.伤害类型 = "魔法";
        shooter.魔法伤害属性 = "热";
        shooter.毒 = 7;
        shooter.淬毒 = 19;
        shooter.暴击 = 10;
        shooter.dispatcher = new EventDispatcher();
    }

    private static function recordShot(props:Object):Object {
        var previous:Object = world.子弹区域;
        var btype:String = props.子弹种类;
        world.子弹区域 = (btype == "爆炸集束子弹" || btype == "爆炸狙击子弹" || btype == "小火焰爆炸") ? xdLib : stockLib;
        var result:Object = saved.shoot(props);
        world.子弹区域 = previous;
        records.push({tag: tag, type: btype, props: shallow(props), clip: result, time: getTimer()});
        if (result != null) spawned.push(result);
        return result;
    }

    private static function fireBullet(bulletType:String, x:Number, y:Number, z:Number, speed:Number, power:Number, angleOffset:Number):MovieClip {
        return MovieClip(_root.子弹区域shoot传递({
            子弹种类: bulletType,
            发射者: shooter._name,
            shootX: x,
            shootY: y,
            shootZ: z,
            子弹威力: (power == undefined) ? 200 : power,
            子弹速度: (speed == undefined) ? 50 : speed,
            子弹散射度: 0,
            霰弹值: 1,
            Z轴攻击范围: 40,
            击倒率: 0,
            伤害类型: "魔法",
            魔法伤害属性: "热",
            命中率: 10000,
            水平击退速度: 0,
            垂直击退速度: 0,
            角度偏移: (angleOffset == undefined) ? 0 : angleOffset
        }));
    }

    private static function recordsFor(btype:String):Array {
        var list:Array = [];
        for (var i:Number = 0; i < records.length; i++) {
            if (records[i].tag == tag && records[i].type == btype) {
                list.push(records[i]);
            }
        }
        return list;
    }

    private static function countType(btype:String):Number {
        return recordsFor(btype).length;
    }

    private static function rebuildTargetCache():Void {
        if (targets.length == 0) {
            cache = {data: [], leftValues: [], rightValues: [], rightMaxValues: []};
            return;
        }
        var ordered:Array = targets.concat();
        ordered.sort(function(a:Object, b:Object):Number {
            return a.aabbCollider.left - b.aabbCollider.left;
        });
        cache = {data: ordered, leftValues: [], rightValues: [], rightMaxValues: []};
        var rightMax:Number = -Infinity;
        for (var i:Number = 0; i < ordered.length; i++) {
            var box:Object = ordered[i].aabbCollider;
            rightMax = Math.max(rightMax, box.right);
            cache.leftValues.push(box.left);
            cache.rightValues.push(box.right);
            cache.rightMaxValues.push(rightMax);
        }
    }

    private static function addEnemy(x:Number, z:Number, halfW:Number, yTop:Number, yBottom:Number):MovieClip {
        var idx:Number = targets.length;
        var unit:MovieClip = world.createEmptyMovieClip("scatterEnemy" + idx, 900100 + idx);
        unit._x = x;
        unit._y = z;
        unit.Z轴坐标 = z;
        unit.hp = unit.hp满血值 = 100000;
        unit.等级 = 35;
        unit.防御力 = 0;
        unit.是否为敌人 = true;
        unit.躲闪率 = 1;
        unit.damageTakenMultiplier = 1;
        unit.魔法抗性 = {基础: 0, 热: 0};
        unit.shield = AdaptiveShield.createDormant("scatter-fixture-" + idx);
        unit.dispatcher = new EventDispatcher();
        var hw:Number = (halfW > 0) ? halfW : 25;
        var yt:Number = (yTop != undefined) ? yTop : -100;
        var yb:Number = (yBottom != undefined) ? yBottom : 20;
        var area:MovieClip = unit.createEmptyMovieClip("area", 1);
        area.beginFill(0xff0000);
        area.moveTo(-hw, yt);
        area.lineTo(hw, yt);
        area.lineTo(hw, yb);
        area.lineTo(-hw, yb);
        area.endFill();
        unit.aabbCollider = new AABBCollider(0, 0, 0, 0);
        unit.aabbCollider.updateFromUnitArea(unit);
        targets.push(unit);
        rebuildTargetCache();
        return unit;
    }

    private static function cleanup():Void {
        ExplosionScatter.clockOverride = null;
        ExplosionScatter.rngOverride = null;
        _root.暂停 = false;
        mapWallActive = false;
        mapWallX = 999999;

        for (var i:Number = 0; i < spawned.length; i++) {
            if (spawned[i]._parent) spawned[i].removeMovieClip();
        }
        spawned = [];
        for (i = 0; i < targets.length; i++) {
            if (targets[i]._parent) {
                targets[i].dispatcher.destroy();
                targets[i].removeMovieClip();
            }
        }
        targets = [];
        rebuildTargetCache();
        BulletQueueProcessor.reset();
        BulletQueueProcessor.initialize();
    }

    private static function stepBullet(projectile:MovieClip):Void {
        _root.帧计时器.当前帧数++;
        projectile.onEnterFrame();
        BulletQueueProcessor.processQueue();
    }

    private static function stepMany(clips:Array):Void {
        _root.帧计时器.当前帧数++;
        for (var i:Number = 0; i < clips.length; i++) {
            var c:MovieClip = clips[i];
            if (c != null && c._parent != null && typeof c.onEnterFrame == "function") {
                c.onEnterFrame();
            }
        }
        BulletQueueProcessor.processQueue();
    }

    // 1. ExplosionScatterProfile.fromXml + XMLParser + AttributeLoader 校验与别名测试
    private static function testProfileValidation():Void {
        var defProf:ExplosionScatterProfile = ExplosionScatterProfile.fromXml({});
        check(defProf != null
            && defProf.bulletType == "次级穿刺子弹"
            && defProf.count == 5
            && defProf.speed == 25
            && defProf.lifetimeMs == 320
            && close(defProf.powerScale, 0.2, 0.0001)
            && isNaN(defProf.fixedPower)
            && defProf.fallbackPower == 100
            && defProf.minAngle == 0
            && defProf.maxAngle == 360,
            "default profile populates firework scatter defaults");

        var xmlA:XML = new XML('<bullet><name>pA</name><attribute><explosionScatter><type>蓝紫穿刺子弹</type><count>8</count><speed>30</speed><lifetimeMs>450</lifetimeMs><power>150</power><zRange>55</zRange><minAngle>-30</minAngle><maxAngle>30</maxAngle></explosionScatter></attribute></bullet>');
        xmlA.ignoreWhite = true;
        var loadA:Object = new AttributeLoader().load(XMLParser.parseXMLNode(xmlA.firstChild));
        var pA:ExplosionScatterProfile = loadA.explosionScatter;
        check(pA != null && pA.bulletType == "蓝紫穿刺子弹" && pA.count == 8 && pA.speed == 30
            && pA.lifetimeMs == 450 && pA.fixedPower == 150 && pA.zRange == 55
            && pA.minAngle == -30 && pA.maxAngle == 30,
            "AttributeLoader parses explicit explosionScatter overrides");

        var xmlB:XML = new XML('<bullet><name>pB</name><attribute><clusterScatter><count>3</count><lifetimeMs>200</lifetimeMs></clusterScatter></attribute></bullet>');
        xmlB.ignoreWhite = true;
        var loadB:Object = new AttributeLoader().load(XMLParser.parseXMLNode(xmlB.firstChild));
        check(loadB.explosionScatter != null && loadB.explosionScatter.count == 3 && loadB.explosionScatter.lifetimeMs == 200,
            "AttributeLoader accepts clusterScatter alias");

        check(ExplosionScatterProfile.fromXml(null) == null, "null raw rejects");
        check(ExplosionScatterProfile.fromXml({count: 0}) == null, "count=0 rejected");
        check(ExplosionScatterProfile.fromXml({count: 33}) == null, "count=33 rejected");
        check(ExplosionScatterProfile.fromXml({count: 2.5}) == null, "fractional count rejected");
        check(ExplosionScatterProfile.fromXml({lifetimeMs: 0}) == null, "lifetimeMs=0 rejected");
        check(ExplosionScatterProfile.fromXml({speed: -1}) == null, "negative speed rejected");
        check(ExplosionScatterProfile.fromXml({minAngle: 45, maxAngle: -45}) == null, "minAngle > maxAngle rejected");
        check(ExplosionScatterProfile.fromXml({type: ""}) == null, "empty type rejected");
    }

    // 2. 真实 bullets_cases.xml -> InfoLoader 配置校验
    private static function testInfoLoaderConfig():Void {
        check(xmlReady && configured != null, "real bullets_cases.xml loaded 爆炸集束子弹.explosionScatter");
        check(configured.bulletType == "次级穿刺子弹"
            && configured.count == 5
            && configured.speed == 25
            && configured.lifetimeMs == 320
            && close(configured.powerScale, 0.2, 0.0001)
            && isNaN(configured.fixedPower)
            && configured.fallbackPower == 100
            && configured.minAngle == 0
            && configured.maxAngle == 360,
            "production InfoLoader config matches issue 263 defaults");
    }

    // 3. 真实发布素材命中敌方单位 + 属性快照/noShell/淬毒不重扣 + 爆炸移除
    private static function testUnitHitAndToxicity():Void {
        tag = "unit-hit";
        createShooter("右");
        shooter.淬毒 = 19;
        var enemy:MovieClip = addEnemy(50, 0, 25, -100, 20);
        var b:MovieClip = fireBullet("爆炸集束子弹", 0, -40, 0, 50, 200, 0);
        check(b != null && b._parent === xdLib && b.__explosionScatter != null,
            "爆炸集束子弹 attaches from 3XD的素材.swf and binds ExplosionScatter");
        check(shooter.淬毒 == 18, "parent birth decrements shooter.淬毒 exactly once");

        var shellBefore:Number = fxLayer.getNextHighestDepth();
        stepBullet(b);
        stepBullet(b);
        var children:Array = recordsFor("次级穿刺子弹");
        check(b.__explosionScatter.triggered === true, "enemy contact triggers ExplosionScatter state on 爆炸集束子弹");
        check(children.length == 5, "enemy contact emits exactly 5 次级穿刺子弹");
        check(enemy.hp < enemy.hp满血值, "enemy took damage on parent contact/blast");
        check(shooter.淬毒 == 18, "5 scattered children do not re-decrement shooter.淬毒");

        for (var i:Number = 0; i < children.length; i++) {
            var rec:Object = children[i];
            check(rec.clip._parent === stockLib, "child attaches from 原版素材库-子弹 " + i);
            check(rec.props.noShell === true && rec.clip.noShell === true, "child suppresses shell casing " + i);
            check(rec.props.lockShooterAttributes === true && rec.clip.lockShooterAttributes === true, "child locks shooter attributes " + i);
            check(close(rec.clip.子弹威力, 40, 0.01), "child power = 200 * 0.2 = 40 (" + i + ")");
        }
        check(fxLayer.getNextHighestDepth() == shellBefore, "no shell casings emitted in mid-air during scatter");
        cleanup();
    }

    // 4. 撞墙消失与撞地消失（表面二分回退使向外子弹出墙、向内子弹帧1撞墙消失）
    private static function testWallAndGroundScatter():Void {
        // 4a. 垂直墙面 x >= 200
        tag = "wall-hit";
        createShooter("右");
        mapWallActive = true;
        mapWallX = 200;
        // 角度 0, 180, 0, 180, 0 => 3 颗向右(向墙内)，2 颗向左(向墙外)
        ExplosionScatter.rngOverride = makeSeqRng([0, 0.5, 0, 0.5, 0]);
        var bWall:MovieClip = fireBullet("爆炸集束子弹", 150, -200, 0, 50, 200, 0);
        stepBullet(bWall);
        stepBullet(bWall);

        var wallChildren:Array = recordsFor("次级穿刺子弹");
        check(bWall.__explosionScatter.triggered === true, "wall impact triggers ExplosionScatter state on 爆炸集束子弹");
        check(wallChildren.length == 5, "wall impact spawns 5 次级穿刺子弹");

        var spawnX:Number = wallChildren[0].props.shootX;
        check(spawnX < 200 && spawnX > 195, "wall explosion origin snaps cleanly outside wall: " + spawnX);
        var outwardClips:Array = [];
        var inwardClips:Array = [];
        for (var i:Number = 0; i < wallChildren.length; i++) {
            var cc:MovieClip = MovieClip(wallChildren[i].clip);
            check(cc._parent === stockLib, "all 5 wall children survive birth frame " + i);
            if (cc.xmov > 0) inwardClips.push(cc);
            else outwardClips.push(cc);
        }
        check(inwardClips.length == 3 && outwardClips.length == 2, "expected 3 inward and 2 outward wall children");

        var allWallKids:Array = inwardClips.concat(outwardClips);
        stepMany(allWallKids);
        stepMany(allWallKids);
        for (i = 0; i < inwardClips.length; i++) {
            check(inwardClips[i]._parent == undefined, "inward child vanishes on wall hit frame 1: " + i);
        }
        for (i = 0; i < outwardClips.length; i++) {
            check(outwardClips[i]._parent != null && outwardClips[i]._x < spawnX, "outward child survives and moves away from wall " + i);
        }
        cleanup();

        // 4b. 地面碰撞 (_y > Z轴坐标)
        tag = "ground-hit";
        createShooter("右");
        mapWallActive = false;
        // 向下 90 度射向地面：baseAngle=90, rng=[0,0.5,0,0.5,0] => 90度向下(3)与 -90度向上(2)
        ExplosionScatter.rngOverride = makeSeqRng([0, 0.5, 0, 0.5, 0]);
        var bGround:MovieClip = fireBullet("爆炸集束子弹", 0, -10, 0, 50, 200, 90);
        stepBullet(bGround);
        stepBullet(bGround);

        var groundChildren:Array = recordsFor("次级穿刺子弹");
        check(bGround.__explosionScatter.triggered === true, "ground impact triggers ExplosionScatter state on 爆炸集束子弹");
        check(groundChildren.length == 5, "ground impact spawns 5 次级穿刺子弹");
        var spawnY:Number = groundChildren[0].props.shootY;
        check(spawnY <= 0 && spawnY >= -5, "ground explosion origin snaps near ground y<=0: " + spawnY);

        var downKids:Array = [];
        var upKids:Array = [];
        for (i = 0; i < groundChildren.length; i++) {
            var gc:MovieClip = MovieClip(groundChildren[i].clip);
            if (gc.ymov > 0) downKids.push(gc);
            else upKids.push(gc);
        }
        check(downKids.length == 3 && upKids.length == 2, "expected 3 downward and 2 upward ground children");
        var allGroundKids:Array = downKids.concat(upKids);
        stepMany(allGroundKids);
        stepMany(allGroundKids);
        for (i = 0; i < downKids.length; i++) {
            check(downKids[i]._parent == undefined, "downward child vanishes on ground impact " + i);
        }
        for (i = 0; i < upKids.length; i++) {
            check(upKids[i]._parent != null && upKids[i]._y < spawnY, "upward child survives above ground " + i);
        }
        cleanup();
    }

    // 6. Boss Lady 原弹 (爆炸狙击子弹) 回归验证：仅 1 小火焰爆炸，0 次级散射
    private static function testLadyRegression():Void {
        tag = "lady-regression";
        createShooter("右");
        var enemy:MovieClip = addEnemy(50, 0, 25, -100, 20);
        var bLady:MovieClip = fireBullet("爆炸狙击子弹", 0, -40, 0, 50, 200, 0);
        check(bLady != null && bLady.__explosionScatter == undefined, "Lady original 爆炸狙击子弹 does not bind ExplosionScatter");
        stepBullet(bLady);
        stepBullet(bLady);
        check(countType("次级穿刺子弹") == 0, "Lady bullet emits 0 次级穿刺子弹");
        check(enemy.hp < enemy.hp满血值, "Lady bullet still damages enemy");
        cleanup();
    }

    // 7. 真实 Math.random 0~360 全象限随机分布 + 跟随母弹飞行方向 (不受发射者后续转向或销毁影响)
    private static function testDistributionAndDirection():Void {
        // 7a. 0~360 随机四象限分布
        tag = "random-dist";
        createShooter("右");
        ExplosionScatter.rngOverride = null;
        var q1:Boolean = false, q2:Boolean = false, q3:Boolean = false, q4:Boolean = false;
        var firstBurstAngles:Array = [];
        var differsFromFirst:Boolean = false;
        for (var burst:Number = 0; burst < 6; burst++) {
            var e:MovieClip = addEnemy(50, 0, 25, -100, 20);
            var bx:MovieClip = fireBullet("爆炸集束子弹", 0, -40, 0, 50, 200, 0);
            stepBullet(bx);
            stepBullet(bx);
            e.dispatcher.destroy();
            e.removeMovieClip();
            targets = [];
            rebuildTargetCache();
        }
        var randKids:Array = recordsFor("次级穿刺子弹");
        check(randKids.length == 30, "6 bursts generated 30 random children");
        for (var i:Number = 0; i < randKids.length; i++) {
            var kc:MovieClip = MovieClip(randKids[i].clip);
            var vx:Number = kc.xmov;
            var vy:Number = kc.ymov;
            if (vx > 0 && vy > 0) q1 = true;
            if (vx < 0 && vy > 0) q2 = true;
            if (vx < 0 && vy < 0) q3 = true;
            if (vx > 0 && vy < 0) q4 = true;
            if (i < 5) {
                firstBurstAngles.push(randKids[i].props.fixedRotation);
            } else if (!close(randKids[i].props.fixedRotation, firstBurstAngles[i % 5], 0.001)) {
                differsFromFirst = true;
            }
        }
        check(q1 && q2 && q3 && q4, "real Math.random 0~360 scatters across all 4 quadrants");
        check(differsFromFirst, "repeated bursts produce genuinely random angles");
        cleanup();

        // 7b. 扇区跟随母弹方向：向左发射后翻转 shooter.方向 并删掉 shooter，散射仍向左且无 NaN
        tag = "follow-parent-dir";
        var sectorProfile:ExplosionScatterProfile = ExplosionScatterProfile.fromXml({
            type: "次级穿刺子弹", count: 4, speed: 25, lifetimeMs: 320,
            powerScale: 0.2, fallbackPower: 100, minAngle: -20, maxAngle: 20
        });
        createShooter("左");
        var bLeft:MovieClip = fireBullet("爆炸狙击子弹", 200, -40, 0, 50, 200, 0);
        check(bLeft.xmov < 0, "leftward parent flies left (xmov < 0)");
        ExplosionScatter.bind(bLeft, sectorProfile);
        ExplosionScatter.rngOverride = makeSeqRng([0, 0.33, 0.67, 0.99]);
        addEnemy(150, 0, 25, -100, 20);
        // 在飞行中途故意改变发射者朝向甚至销毁发射者
        stepBullet(bLeft);
        shooter.方向 = "右";
        shooter.dispatcher.destroy();
        shooter.removeMovieClip();
        shooter = null;
        stepBullet(bLeft);
        var secKids:Array = recordsFor("次级穿刺子弹");
        check(secKids.length == 4, "sector burst spawned 4 children after shooter flipped and removed");
        for (i = 0; i < secKids.length; i++) {
            var sc:MovieClip = MovieClip(secKids[i].clip);
            check(sc.xmov < 0 && isFinite(sc._rotation), "child follows leftward parent velocity without NaN " + i);
            check(Math.abs(sc.ymov / sc.xmov) <= Math.tan(21 * Math.PI / 180), "child lies inside +-20 deg parent cone " + i);
        }
        createShooter("右");
        cleanup();
    }

    // 8. 真实 次级穿刺子弹 穿透能力验证 (pierceLimit=3，前3敌受创、第4敌耗尽移除)
    private static function testPiercingChildren():Void {
        tag = "pierce-children";
        createShooter("右");
        mapWallActive = true;
        mapWallX = 200;
        ExplosionScatter.rngOverride = makeSeqRng([0.5]);
        var b:MovieClip = fireBullet("爆炸集束子弹", 150, -40, 0, 50, 200, 0);
        stepBullet(b);
        stepBullet(b);
        mapWallActive = false;
        var kids:Array = recordsFor("次级穿刺子弹");
        check(kids.length == 5, "wall burst created 5 piercing children flying left");
        var probe:MovieClip = MovieClip(kids[0].clip);
        for (var i:Number = 1; i < kids.length; i++) {
            MovieClip(kids[i].clip).removeMovieClip();
        }
        check(probe.xmov < -24 && probe.pierceLimit == 3, "probe 次级穿刺子弹 flies left at speed 25 with pierceLimit=3");

        // 次级穿刺子弹第 1 帧有 area；命中第 1 个敌人后播 "爆炸"(帧2)，后续第 3、6、9 帧各有 area。
        var hitDamaged:Array = [];
        var e1:MovieClip = addEnemy(probe._x - 2, 0, 25, -100, 20);
        stepBullet(probe);
        hitDamaged.push(e1.hp < e1.hp满血值);
        e1.dispatcher.destroy();
        e1.removeMovieClip();
        targets = [];
        rebuildTargetCache();

        for (var f:Number = 2; f <= 9 && probe._parent != null; f++) {
            probe.gotoAndStop(f);
            if (probe.area != null) {
                addEnemy(probe._x - 2, 0, 25, -100, 20);
            }
            stepBullet(probe);
            for (var tIdx:Number = 0; tIdx < targets.length; tIdx++) {
                hitDamaged.push(targets[tIdx].hp < targets[tIdx].hp满血值);
                targets[tIdx].dispatcher.destroy();
                targets[tIdx].removeMovieClip();
            }
            targets = [];
            rebuildTargetCache();
        }
        check(hitDamaged.length == 4, "次级穿刺子弹 contacted 4 targets across frames 1,3,6,9");
        check(hitDamaged[0] && hitDamaged[1] && hitDamaged[2],
            "次级穿刺子弹 pierced and damaged 3 distinct enemies");
        check(probe._parent == undefined, "4th hit exceeds pierceLimit=3 and removes 次级穿刺子弹");
        cleanup();
    }

    // 9a. 确定性毫秒时钟测试（含 _root.暂停 冻结与命中首敌后无 area 帧毫秒过期）
    private static function testLifetimeAndPause():Void {
        tag = "lifetime-mock";
        createShooter("右");
        mockClockMs = 1000;
        ExplosionScatter.clockOverride = mockedNow;
        var enemy:MovieClip = addEnemy(50, 0, 25, -100, 20);
        var b:MovieClip = fireBullet("爆炸集束子弹", 0, -40, 0, 50, 200, 0);
        stepBullet(b);
        stepBullet(b);
        // 清掉敌人与墙，纯测计时与无 area 帧
        enemy.dispatcher.destroy();
        enemy.removeMovieClip();
        targets = [];
        rebuildTargetCache();

        var recs:Array = recordsFor("次级穿刺子弹");
        check(recs.length == 5, "mock clock burst spawns 5 children");
        var kids:Array = [];
        for (var i:Number = 0; i < recs.length; i++) {
            kids.push(recs[i].clip);
        }

        // 让其中一颗先进入“爆炸”帧（无 area 帧）验证无 area 时也能按毫秒销毁
        MovieClip(kids[0]).gotoAndStop(2);
        check(MovieClip(kids[0]).area == undefined, "frame 2 of 次级穿刺子弹 has no area");

        // 暂停期间推进 5000ms，elapsedMs 不增长
        _root.暂停 = true;
        mockClockMs = 6000;
        stepMany(kids);
        for (i = 0; i < kids.length; i++) {
            check(MovieClip(kids[i])._parent != null && kids[i].__scatterLifetime.elapsedMs == 0,
                "paused ms do not advance lifetime " + i);
        }

        // 解除暂停，推进到 319ms：仍存活
        _root.暂停 = false;
        mockClockMs = 6319;
        stepMany(kids);
        for (i = 0; i < kids.length; i++) {
            check(MovieClip(kids[i])._parent != null && kids[i].__scatterLifetime.elapsedMs == 319,
                "child survives at 319ms < 320ms " + i);
        }

        // 到达 320ms：包括无 area 的 kids[0] 在内全部销毁
        mockClockMs = 6320;
        stepMany(kids);
        for (i = 0; i < kids.length; i++) {
            check(MovieClip(kids[i])._parent == undefined, "child expires at 320ms (" + i + ")");
        }
        cleanup();
    }

    // 10. 同帧多目标+撞墙幂等一次性 + 自循环/嵌套防护
    private static function testIdempotencyAndRecursion():Void {
        tag = "idempotent";
        createShooter("右");
        addEnemy(50, 0, 25, -100, 20);
        addEnemy(55, 0, 25, -100, 20);
        mapWallActive = true;
        mapWallX = 40;
        var b:MovieClip = fireBullet("爆炸集束子弹", 35, -40, 0, 50, 200, 0);
        stepBullet(b);

        var recs:Array = recordsFor("次级穿刺子弹");
        check(recs.length == 5, "multi-enemy + wall hit same frame triggers scatter exactly once");
        check(ExplosionScatter.trigger(b) == false, "repeated trigger returns false");
        check(countType("次级穿刺子弹") == 5, "no extra children on duplicate trigger");

        var childClip:MovieClip = MovieClip(recs[0].clip);
        var anyProfile:ExplosionScatterProfile = ExplosionScatterProfile.fromXml({});
        check(childClip.__scatterDepth == 1, "child carries scatter depth 1");
        check(ExplosionScatter.bind(childClip, anyProfile) == false, "child with depth>=1 cannot bind scatter");
        cleanup();

        tag = "self-loop-guard";
        var selfProfile:ExplosionScatterProfile = ExplosionScatterProfile.fromXml({
            type: "普通子弹", count: 5, speed: 20, lifetimeMs: 300
        });
        var selfDummy:Object = {
            _x: 0, _y: -40, Z轴坐标: 0, 子弹种类: "普通子弹", 子弹威力: 100,
            发射者名: shooter._name, 是否为敌人: false, Z轴攻击范围: 20, xmov: 10, ymov: 0
        };
        check(ExplosionScatter.bind(selfDummy, selfProfile) == true, "bind selfDummy succeeded");
        check(ExplosionScatter.trigger(selfDummy) == false && countType("普通子弹") == 0,
            "bulletType == parentType is refused to block self-recursion");
        cleanup();
    }

    // 原生时间轴 async 阶段：phase 1 测天然最大射程飞完 14 帧不爆炸不散射；phase 2 测真 getTimer() 320ms 过期
    private static function tick():Void {
        if (done) return;
        ticks++;
        _root.帧计时器.当前帧数++;

        if (phase == 0) {
            if (loaded == 2 && xmlReady) {
                initializeWorld();
                testProfileValidation();
                testInfoLoaderConfig();
                testUnitHitAndToxicity();
                testWallAndGroundScatter();
                testLadyRegression();
                testDistributionAndDirection();
                testPiercingChildren();
                testLifetimeAndPause();
                testIdempotencyAndRecursion();

                // 进入 phase 1：原生播放 爆炸集束子弹 至第14帧天然消失，无敌无墙，不应爆炸散射
                tag = "natural-range-end";
                cleanup();
                createShooter("右");
                var bFly:MovieClip = fireBullet("爆炸集束子弹", 0, -200, 0, 50, 200, 0);
                live = {clip: bFly, name: bFly._name, startFrame: _root.帧计时器.当前帧数};
                phaseFrames = 0;
                phase = 1;
            } else if (ticks > 300) {
                check(false, "asset/XML readiness watchdog loaded=" + loaded + " xmlReady=" + xmlReady);
                finish();
            }
            return;
        }

        if (phase == 1) {
            BulletQueueProcessor.processQueue();
            phaseFrames++;
            var fc:MovieClip = live.clip;
            if (fc._parent == undefined || phaseFrames > 25) {
                check(fc._parent == undefined, "unhit 爆炸集束子弹 naturally removes itself by max-range frame");
                check(countType("小火焰爆炸") == 0, "natural max-range end spawns 0 小火焰爆炸");
                check(countType("次级穿刺子弹") == 0, "natural max-range end spawns 0 次级穿刺子弹");
                trace("ExplosionScatterCase natural-end frames=" + phaseFrames + " blasts=0 children=0");

                // 进入 phase 2：原生时间轴验证撞墙实弹发射小火焰爆炸并移除母弹
                tag = "native-wall-blast";
                cleanup();
                createShooter("右");
                mapWallActive = true;
                mapWallX = 80;
                var bWallNative:MovieClip = fireBullet("爆炸集束子弹", 50, -200, 0, 50, 200, 0);
                live = {clip: bWallNative};
                phaseFrames = 0;
                phase = 2;
            }
            return;
        }

        if (phase == 2) {
            BulletQueueProcessor.processQueue();
            phaseFrames++;
            var wallNative:MovieClip = live.clip;
            if ((wallNative._parent == undefined && countType("小火焰爆炸") == 1) || phaseFrames > 12) {
                check(wallNative._parent == undefined, "native wall hit removes parent 爆炸集束子弹 after explosion frame");
                var nativeWallBlasts:Array = recordsFor("小火焰爆炸");
                check(nativeWallBlasts.length == 1 && nativeWallBlasts[0].clip._parent === xdLib, "native wall hit emits 1 小火焰爆炸 from 3XD的素材");
                check(countType("次级穿刺子弹") == 5, "native wall hit emits 5 次级穿刺子弹");

                // 进入 phase 3：原生时间轴验证落地实弹发射小火焰爆炸并移除母弹
                tag = "native-ground-blast";
                cleanup();
                createShooter("右");
                mapWallActive = false;
                var bGroundNative:MovieClip = fireBullet("爆炸集束子弹", 0, -10, 0, 50, 200, 90);
                live = {clip: bGroundNative};
                phaseFrames = 0;
                phase = 3;
            }
            return;
        }

        if (phase == 3) {
            BulletQueueProcessor.processQueue();
            phaseFrames++;
            var groundNative:MovieClip = live.clip;
            if ((groundNative._parent == undefined && countType("小火焰爆炸") == 1) || phaseFrames > 12) {
                check(groundNative._parent == undefined, "native ground hit removes parent 爆炸集束子弹 after explosion frame");
                var nativeGroundBlasts:Array = recordsFor("小火焰爆炸");
                check(nativeGroundBlasts.length == 1 && nativeGroundBlasts[0].clip._parent === xdLib, "native ground hit emits 1 小火焰爆炸 from 3XD的素材");
                check(countType("次级穿刺子弹") == 5, "native ground hit emits 5 次级穿刺子弹");

                // 进入 phase 4：原生时间轴验证 Boss Lady 原弹 (爆炸狙击子弹) 发射小火焰爆炸、0 散射并自毁
                tag = "native-lady-blast";
                cleanup();
                createShooter("右");
                addEnemy(50, 0, 25, -100, 20);
                var bLadyNative:MovieClip = fireBullet("爆炸狙击子弹", 0, -40, 0, 50, 200, 0);
                live = {clip: bLadyNative};
                phaseFrames = 0;
                phase = 4;
            }
            return;
        }

        if (phase == 4) {
            BulletQueueProcessor.processQueue();
            phaseFrames++;
            var ladyNative:MovieClip = live.clip;
            if ((ladyNative._parent == undefined && countType("小火焰爆炸") == 1) || phaseFrames > 12) {
                check(ladyNative._parent == undefined, "native Lady 爆炸狙击子弹 removes itself after explosion");
                check(countType("小火焰爆炸") == 1, "native Lady 爆炸狙击子弹 emits 1 小火焰爆炸");
                check(countType("次级穿刺子弹") == 0, "native Lady 爆炸狙击子弹 emits 0 次级穿刺子弹");

                // 进入 phase 5：真实墙钟 getTimer() 320ms 散射生命周期与单位命中原生爆炸
                tag = "live-clock";
                cleanup();
                createShooter("右");
                ExplosionScatter.clockOverride = null;
                ExplosionScatter.rngOverride = null;
                addEnemy(50, 0, 25, -100, 20);
                bornAt = getTimer();
                var bLive:MovieClip = fireBullet("爆炸集束子弹", 0, -40, 0, 50, 200, 0);
                live = {parent: bLive, children: null, spawnMs: -1};
                phaseFrames = 0;
                phase = 5;
            }
            return;
        }

        if (phase == 5) {
            BulletQueueProcessor.processQueue();
            if (live.children == null) {
                var spawnedKids:Array = recordsFor("次级穿刺子弹");
                if (spawnedKids.length == 5) {
                    live.children = spawnedKids;
                    live.spawnMs = getTimer();
                } else if (getTimer() - bornAt > 2000) {
                    check(false, "live scatter birth watchdog");
                    finish();
                }
                return;
            }

            var alive:Number = 0;
            for (var i:Number = 0; i < live.children.length; i++) {
                if (MovieClip(live.children[i].clip)._parent != null) alive++;
            }
            var elapsed:Number = getTimer() - live.spawnMs;
            if (alive == 0) {
                var liveBlasts:Array = recordsFor("小火焰爆炸");
                check(liveBlasts.length == 1 && liveBlasts[0].clip._parent === xdLib, "live native unit-hit burst spawned 1 小火焰爆炸 from 3XD的素材");
                check(MovieClip(live.parent)._parent == undefined, "live native unit-hit parent 爆炸集束子弹 removed itself");
                check(elapsed >= 300 && elapsed <= 1000, "live getTimer() expired all 5 children near 320ms: " + elapsed + "ms");
                trace("ExplosionScatterCase live-clock elapsedMs=" + elapsed + " blasts=" + liveBlasts.length + " children=" + live.children.length);
                finish();
            } else if (elapsed > 2000) {
                check(false, "live wall-clock expiry watchdog alive=" + alive + " elapsed=" + elapsed);
                finish();
            }
        }
    }

    public static function finish():Void {
        if (done) return;
        done = true;
        delete driver.onEnterFrame;
        cleanup();
        if (world != null && world._parent != null) {
            world.dispatcher.destroy();
            world.removeMovieClip();
        }
        if (xdLib != null && xdLib._parent != null) xdLib.removeMovieClip();
        if (stockLib != null && stockLib._parent != null) stockLib.removeMovieClip();
        if (driver != null && driver._parent != null) driver.removeMovieClip();

        var tc:Object = TargetCacheManager;
        var dodge:Object = DodgeHandler;
        tc.acquireEnemyCache = saved.acquire;
        dodge.calculateDodgeState = saved.dodge;
        dodge.calcDodgeResult = saved.dodgeResult;
        _root.gameworld = saved.world;
        _root.帧计时器 = saved.clock;
        _root.暂停 = saved.paused;
        _root.collisionLayer = saved.collision;
        _root.重力加速度 = saved.gravity;
        _root.Xmin = saved.xmin;
        _root.Xmax = saved.xmax;
        _root.Ymin = saved.ymin;
        _root.Ymax = saved.ymax;
        _root.对象浅拷贝 = saved.copy;
        _root.播放音效 = saved.sound;
        _root.soundEffectManager = saved.soundMgr;
        _root.发布消息 = saved.message;
        _root.效果 = saved.fx;
        _root.子弹区域shoot传递 = saved.shoot;
        DepthManager.instance = saved.depth;

        trace("ExplosionScatterTest Tests Passed: " + passed);
        trace("ExplosionScatterTest Tests Failed: " + failed);
        _root.explosionScatterComplete();
    }
}
