import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.item.equipment.PropertyOperators;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
import org.flashNight.naki.RandomNumberEngine.SeededLinearCongruentialEngine;

/**
 * Issue #195 P1/P2 手枪弹武器击退增强真实战斗对照实验套件
 * 真实加载子弹素材库 + 真实 RSL 敌人素材（光头保安 / 蛮蛮 / 大刀机器人），
 * 走真实 BulletFactory -> BulletQueueProcessor -> DamageCalculator -> HitUpdater -> ImpactStateHandler ->
 * _root.敌人函数.被击移动 -> _root.主角函数.移动钝感硬直 -> Mover.move2D 全链路。
 */
class org.flashNight.arki.unit.Action.Shoot.HandgunKnockbackCombatTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var caseCount:Number;
    private static var stage:Number;
    private static var ticks:Number;
    private static var loadStep:Number;
    private static var ready:Boolean;
    private static var finished:Boolean;

    private static var world:MovieClip;
    private static var bulletArea:MovieClip;
    private static var walls:MovieClip;
    private static var driver:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;

    private static var saved:Object;
    private static var fixtureCache:Object;
    private static var friendlyFixtureCache:Object;
    private static var mathStream:SeededLinearCongruentialEngine;
    private static var authoredHurtSamples:Array;
    private static var cases:Array;
    private static var activeBullets:Array;
    private static var currentBatchSpecs:Array;
    private static var batches:Array;
    private static var weaponCatalog:Object;
    private static var modCatalog:Object;

    private static var prodKnockbackMove:Function;
    private static var prodHitstop:Function;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[TEST_FAIL] HandgunKnockbackCombatTest: " + label);
        }
    }

    private static function shallow(source:Object):Object {
        var result:Object = {};
        for (var key:String in source) {
            result[key] = source[key];
        }
        return result;
    }

    private static function sampleMath():Number { return mathStream.nextFloat(); }

    private static function spread(span:Number):Number {
        return LinearCongruentialEngine.getInstance().randomOffset(span);
    }

    private static function acquireFixtureEnemies(unit:Object, interval:Number):Object {
        if (measureCounterattacks && unit.faction == FactionManager.FACTION_ENEMY) return friendlyFixtureCache;
        return fixtureCache;
    }

    private static function shoot(props:Object):Object {
        var unit:MovieClip = _root.gameworld[props.发射者];
        var angle:Number = ShootingAngleCalculator.calculate(props, unit);
        BulletFactory.prepareBulletData(props, unit);
        var b:Object = BulletFactory.createBullet(props, unit, angle);
        if (b != null && typeof(b.onEnterFrame) == "function") {
            b.__precheck = b.onEnterFrame;
            b.onEnterFrame = null;
            activeBullets.push(b);
        }
        return b;
    }

    /** Load the three authored shotguns through Flash, then drive the ordinary queue and hit reactions. */
    public static var loadAuthoredShotguns:Boolean = false;
    public static var measureCounterattacks:Boolean = false;
    private static function runShotguns():Void {
        var xml:XML = new XML();
        xml.ignoreWhite = true;
        xml.onLoad = function(ok:Boolean):Void {
            var guns:Array = [];
            if (ok) {
                for (var item:XMLNode = this.firstChild.firstChild; item != null; item = item.nextSibling) {
                    var name:String = "";
                    var data:Object = {};
                    for (var part:XMLNode = item.firstChild; part != null; part = part.nextSibling) {
                        if (part.nodeName == "name") name = String(part.firstChild.nodeValue);
                        if (part.nodeName == "data") for (var stat:XMLNode = part.firstChild; stat != null; stat = stat.nextSibling)
                            data[stat.nodeName] = stat.firstChild.nodeValue;
                    }
                    if (name == "AA12" || name == "SPAS12" || name == "雷明登870") {
                        guns.push({id:name, mode:"长枪", intervalMs:Number(data.interval), frameInterval:Math.ceil(Number(data.interval)*.03),
                            bullet:data.bullet, power:Number(data.power), split:Number(data.split), speed:Number(data.velocity),
                            spread:Number(data.diffusion), zRange:Number(data.bulletsize), knockdown:Number(data.impact), authoredKnockback:ShootInitCore.calculateWeaponKnockback(null, "长枪", Number(data.knockback), "霰弹枪"),
                            hitEffect:data.bullethit, damageType:"物理", magCapacity:Number(data.capacity)});
                    }
                }
            }
            HandgunKnockbackCombatTest.runAllTests(guns);
        };
        xml.load("../data/items/武器_长枪_霰弹枪.xml");
    }

    private static function buildShotgunBatches(guns:Array):Void {
        batches = [];
        var strengths:Array = [8, 10, 12, 14, 16];
        var layouts:Array = [
            {name:"贴脸单人", distance:58, count:1, chase:0, gap:0},
            {name:"中距追击", distance:166, count:2, chase:3, gap:46},
            {name:"三人追击", distance:166, count:3, chase:3, gap:40},
            {name:"近敌阵亡", distance:130, count:2, chase:3, gap:48, frail:true}
        ];
        if (measureCounterattacks) {
            layouts = [
                {name:"双方就绪", distance:58},
                {name:"枪托已起", distance:58, winding:true},
                {name:"低血枪托已起", distance:58, winding:true, frail:true},
                {name:"近身不射对照", distance:58, winding:true, holdFire:true},
                {name:"界外不射对照", distance:240, winding:true, holdFire:true}
            ];
        }
        var formations:Array = [layouts];
        if (!measureCounterattacks) {
            formations.push([
                {name:"后排入线向右", distance:166, count:2, chase:3, gap:46, entering:true},
                {name:"后排入线向左", distance:166, count:2, chase:3, gap:46, entering:true, leftDir:true}
            ]);
        }
        for (var g:Number = 0; g < guns.length; g++) {
            var w:Object = guns[g];
            weaponCatalog[w.id] = w;
            check(w.authoredKnockback === 10, w.id + " live weapon XML resolves to the selected shotgun knockback of 10");
            // Each run begins from the same random state for all five settings of one gun.
            // The candidate and baseline share the first contact. Later trajectories may diverge.
            for (var sample:Number = 0; sample < 3; sample++) for (var k:Number = 0; k < strengths.length; k++) {
                var seed:Number = 42013 + sample * 17107;
                for (var f:Number = 0; f < formations.length; f++) {
                    var formation:Array = formations[f];
                    var specs:Array = [];
                    for (var l:Number = 0; l < formation.length; l++) {
                        var layout:Object = formation[l];
                        specs.push({shotgun:true, scenario:layout.name, weaponId:w.id, kb:strengths[k], sample:sample,
                            enemyCount:layout.count || 1, forcedRegime:"STD_TOUGH", chaseSpeed:layout.chase || 0,
                            maxShots:measureCounterattacks ? (layout.holdFire ? 0 : 1) : 3,
                            startDist:layout.distance, enemySpacing:layout.gap, frail:layout.frail,
                            winding:layout.winding, holdFire:layout.holdFire, entering:layout.entering, leftDir:layout.leftDir});
                    }
                    batches.push({enemySwf:"../flashswf/arts/new/Codex光头保安素材.swf", linkage:"敌人-CF6光头保安",
                        seed:seed, maxTicks:measureCounterattacks ? 7 + w.frameInterval : 4 + w.frameInterval * 2 + 35, specs:specs});
                }
            }
        }
    }

    public static function runAllTests(shotguns:Array):Void {
        if (loadAuthoredShotguns) {
            loadAuthoredShotguns = false;
            runShotguns();
            return;
        }
        passed = 0;
        failed = 0;
        caseCount = 0;
        stage = 0;
        ticks = 0;
        ready = false;
        finished = false;
        activeBullets = [];
        authoredHurtSamples = shotguns != null && !measureCounterattacks ? [0, 0] : null;

        // Use the shipped enemy impulse. The fixture advances its callback exactly once per
        // simulation tick so the Flash stage cannot apply a second movement on the same frame.
        prodKnockbackMove = function(dir:String, speed:Number, friction:Number):Void {
            if (this.免疫击退) return;
            this.移动钝感硬直(_root.钝感硬直时间);
            Mover.beginEnemyHitMove(this, dir, speed, friction);
            delete this.onEnterFrame;
        };

        prodHitstop = function(durationMs:Number):Void {
            if (this.knockStiffID != null) {
                return;
            }
            var self:MovieClip = this;
            this.硬直中 = true;
            this.knockStiffID = EnhancedCooldownWheel.I().addTask(function():Void {
                self.knockStiffID = null;
                self.硬直中 = false;
            }, durationMs, 1);
        };

        initCatalogs();
        if (shotguns != null) {
            check(shotguns.length == 3, "all three shotgun profiles loaded from live XML");
            if (shotguns.length != 3) { finish(); return; }
            buildShotgunBatches(shotguns);
        } else buildBatches();

        var queue:Object = BulletQueueProcessor;
        var cache:Object = TargetCacheManager;
        saved = {
            world: _root.gameworld,
            clock: _root.帧计时器,
            paused: _root.暂停,
            target: _root.控制目标,
            collision: _root.collisionLayer,
            xmin: _root.Xmin,
            xmax: _root.Xmax,
            ymin: _root.Ymin,
            ymax: _root.Ymax,
            random: _root.随机偏移,
            copy: _root.对象浅拷贝,
            shoot: _root.子弹区域shoot传递,
            hitstopTime: _root.钝感硬直时间,
            queues: queue.activeQueues,
            fake: queue.fakeUnits,
            uids: queue.queueUIDs,
            probe: queue._raySettleProbe,
            acquireEnemy: cache.acquireEnemyCache,
            seed: LinearCongruentialEngine.getInstance().captureState()
        };

        _root.暂停 = false;
        _root.是否阴影 = false;
        _root.控制目标 = "__handgun_kb_no_manual";
        _root.控制目标全自动 = false;
        _root.钝感硬直时间 = 70;
        _root.帧计时器 = {
            当前帧数: 0,
            帧率: 30,
            毫秒每帧: 1000 / 30,
            eventBus: new EventDispatcher(),
            添加或更新任务: function(target:Object, label:String, cb:Function, delayMs:Number):Number {
                return EnhancedCooldownWheel.I().addOrUpdateTask(target, label, cb, delayMs, false, 1, null);
            }
        };
        _root.效果 = _root.播放音效 = _root.发布消息 = _root.add2map = _root.add2map2 = function():Void {};
        _root.初始化思考标签 = function(mc:MovieClip):Void { mc.stop(); mc._visible = false; };
        if (_root.敌人函数 == undefined) _root.敌人函数 = {};
        _root.敌人函数.配置音效 = function():Void {};
        _root.敌人函数.行走 = function():Void {};
        _root.敌人函数.被击移动 = prodKnockbackMove;
        if (_root.主角函数 == undefined) _root.主角函数 = {};
        _root.主角函数.移动钝感硬直 = prodHitstop;
        _root.敌人二级函数 = {
            攻击时移动: function():Void {},
            X轴追踪移动: function():Void {},
            Z轴追踪移动: function():Void {},
            计算攻击角度: function():Void {},
            固定角度移动: function():Void {}
        };
        _root.初始化敌人模板 = function():Void { HandgunKnockbackCombatTest.initEnemyActor(this); };
        _root.随机偏移 = spread;
        _root.对象浅拷贝 = shallow;
        _root.子弹区域shoot传递 = shoot;

        cache.acquireEnemyCache = acquireFixtureEnemies;
        queue._raySettleProbe = null;

        EnhancedCooldownWheel.I().reset();
        saved.cdWheelEnterFrame = _root._cdWheel != undefined ? _root._cdWheel.onEnterFrame : undefined;
        if (_root._cdWheel != undefined) {
            delete _root._cdWheel.onEnterFrame;
        }
        FactionManager.initialize();
        BulletQueueProcessor.initialize();
        ColliderFactoryRegistry.init();
        DamageManagerFactory.init();
        var pink:Object = PinkNoiseEngine.getInstance();
        if (shotguns != null) {
            // DamageCalculator draws from a separate, layered PinkNoiseEngine.
            // Preserve the live streams before fixing the same starting conditions for every kb.
            saved.pinkState = {seed:pink.seed, counter:pink.counter, s0:pink.s0, s1:pink.s1, s2:pink.s2, s3:pink.s3, s4:pink.s4};
            saved.nativeMath = Math.random;
            mathStream = new SeededLinearCongruentialEngine(42013);
            Math.random = sampleMath;
            saved.mathReadOnly = Math.random !== sampleMath;
            if (saved.mathReadOnly) {
                _global.ASSetPropFlags(Math, "random", 0, 4);
                Math.random = sampleMath;
            }
            check(Math.random === sampleMath, "seeded fixture math stream installed");
        }
        Mover.init();

        if (shotguns == null) verifyModFormula();

        driver = _root.createEmptyMovieClip("__handgunKbDriver", _root.getNextHighestDepth());
        driver.onEnterFrame = function():Void {
            HandgunKnockbackCombatTest.tick();
        };
        startBatch();
    }

    private static function initCatalogs():Void {
        // 严格对齐 weapon XML 真实属性（PPK, WaltherP99, Glock18, Glock18战术版, 钛合金P90, UMP, AK47）
        weaponCatalog = {
            PPK: {
                id: "PPK", mode: "手枪", dual: false, intervalMs: 225, frameInterval: 7,
                bullet: "普通子弹", power: 40, speed: 25, spread: 3, zRange: 30,
                knockdown: 35, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 15
            },
            WaltherP99: {
                id: "WaltherP99", mode: "手枪", dual: false, intervalMs: 257, frameInterval: 8,
                bullet: "普通子弹", power: 70, speed: 25, spread: 3, zRange: 30,
                knockdown: 30, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 15
            },
            Glock18_Single: {
                id: "Glock18_Single", mode: "手枪", dual: false, intervalMs: 80, frameInterval: 3,
                bullet: "普通子弹", power: 38, speed: 25, spread: 4, zRange: 30,
                knockdown: 50, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 30
            },
            Glock18_Dual: {
                id: "Glock18_Dual", mode: "双枪", dual: true, intervalMs: 80, frameInterval: 3,
                bullet: "普通子弹", power: 38, speed: 25, spread: 4, zRange: 30,
                knockdown: 50, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 30
            },
            Glock18_Tac: {
                id: "Glock18_Tac", mode: "手枪", dual: false, intervalMs: 75, frameInterval: 3,
                bullet: "次级穿刺子弹", pierceLimit: 3, power: 135, speed: 30, spread: 5, zRange: 30,
                knockdown: 45, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 50
            },
            TiP90: {
                id: "TiP90", mode: "手枪", dual: false, intervalMs: 75, frameInterval: 3,
                bullet: "穿刺子弹", power: 300, speed: 20, spread: 5, zRange: 30,
                knockdown: 45, kb: 10, hitEffect: "飙血", damageType: "破击", magicAttr: "钢", magCapacity: 50
            },
            UMP: {
                id: "UMP", mode: "长枪", dual: false, intervalMs: 112, frameInterval: 4,
                bullet: "普通子弹", power: 50, speed: 30, spread: 3.5, zRange: 30,
                knockdown: 35, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 30
            },
            AK47: {
                id: "AK47", mode: "长枪", dual: false, intervalMs: 112, frameInterval: 4,
                bullet: "普通子弹", power: 120, speed: 32, spread: 2, zRange: 30,
                knockdown: 20, kb: 10, hitEffect: "飙血", damageType: "物理", magCapacity: 35
            }
        };

        // 严格对齐 data/items/equipment_mods/高等材料_枪械专用.xml 中 黑爪扩张弹 / 灰蛊裂隙弹 的真实属性运算配置
        // 注意：XML 中 <impact> 对应武器的 击倒率(knockdown)，sqrtScale(coeff=1.4, min=20) 将高击倒率(30~50)压缩至 20，从而大幅提升单发冲击力！
        modCatalog = {
            BlackClaw: {
                id: "BlackClaw",
                curve: { impact: { type: "sqrtScale", coefficient: 1.4, min: 20 } },
                overrideProps: { damagetype: "破击", magictype: "精英" }
            },
            GrayGoo: {
                id: "GrayGoo",
                curve: { impact: { type: "sqrtScale", coefficient: 1.4, min: 20 } },
                overrideProps: {}
            }
        };
    }

    private static function computeModdedProps(w:Object, modId:String, baseKb:Number):Object {
        var res:Object = shallow(w);
        res.kb = baseKb;
        res.modId = modId == undefined ? "none" : modId;
        if (modId == undefined || modId == "none") {
            return res;
        }
        var mod:Object = modCatalog[modId];
        var statProp:Object = {
            power: w.power,
            impact: w.knockdown,
            bullet: w.bullet,
            damagetype: w.damageType,
            magictype: w.magicAttr
        };
        PropertyOperators.applyCurve(statProp, mod.curve);
        PropertyOperators.override(statProp, mod.overrideProps);
        res.power = statProp.power;
        res.knockdown = statProp.impact;
        res.bullet = statProp.bullet;
        res.damageType = statProp.damagetype;
        res.magicAttr = statProp.magictype;
        return res;
    }

    private static function verifyModFormula():Void {
        // 验证 PropertyOperators.applyCurve 对黑爪扩张弹/灰蛊裂隙弹的 <impact>（击倒率）sqrtScale 压缩计算
        var g18:Object = computeModdedProps(weaponCatalog.Glock18_Single, "BlackClaw", 14);
        check(g18.knockdown == 20, "BlackClaw compresses Glock18 impact(knockdown) 50 -> 20 got=" + g18.knockdown);
        check(g18.damageType == "破击" && g18.magicAttr == "精英", "BlackClaw overrides damageType=破击/精英");
        var ppk:Object = computeModdedProps(weaponCatalog.PPK, "GrayGoo", 14);
        check(ppk.knockdown == 20, "GrayGoo compresses PPK impact(knockdown) 35 -> 20 got=" + ppk.knockdown);

        // 验证 ShootInitCore P3 方案 A1 生产参数接线与边界保护
        var dummyActor:Object = {
            _name: "p3VerifyActor",
            被动技能: {},
            是否为敌人: false,
            基础命中率: 20,
            手枪数据: { weapontype: "手枪" },
            手枪2数据: { weapontype: "冲锋枪" },
            长枪数据: { weapontype: "冲锋枪" }
        };
        var baseWd:Array = [];
        baseWd.split = 1; baseWd.diffusion = 3; baseWd.sound = ""; baseWd.muzzle = "";
        baseWd.bullet = "普通子弹"; baseWd.velocity = 25; baseWd.bullethit = "火花";
        baseWd.power = 50; baseWd.bulletsize = 30; baseWd.impact = 35; baseWd.targethit = "飙血";

        var pistolProps:Object = ShootInitCore.generateBulletProps(dummyActor, "手枪", baseWd, {});
        BulletInitializer.calculateKnockback(pistolProps);
        check(pistolProps.水平击退速度 == 14, "P3 Option A1: pistol (weapontype=手枪) defaults to kb=14 got=" + pistolProps.水平击退速度);

        var offhandSmgProps:Object = ShootInitCore.generateBulletProps(dummyActor, "手枪2", baseWd, {});
        BulletInitializer.calculateKnockback(offhandSmgProps);
        check(offhandSmgProps.水平击退速度 == 14, "P3 Option A1: offhand machine pistol (weapontype=冲锋枪) defaults to kb=14 got=" + offhandSmgProps.水平击退速度);

        dummyActor.手枪数据.weapontype = "大威力手枪";
        var magnumProps:Object = ShootInitCore.generateBulletProps(dummyActor, "手枪", baseWd, {});
        check(magnumProps.水平击退速度 == 14, "P3 Option A1: magnum pistol (weapontype=大威力手枪) defaults to kb=14 got=" + magnumProps.水平击退速度);

        dummyActor.手枪数据.weapontype = "霰弹枪";
        var pistolShotgunProps:Object = ShootInitCore.generateBulletProps(dummyActor, "手枪", baseWd, {});
        check(pistolShotgunProps.水平击退速度 == 10, "P3 Option A1: pistol-slot shotgun (weapontype=霰弹枪) stays kb=10 got=" + pistolShotgunProps.水平击退速度);

        dummyActor.手枪数据.weapontype = "突击步枪";
        var pistolArProps:Object = ShootInitCore.generateBulletProps(dummyActor, "手枪", baseWd, {});
        check(pistolArProps.水平击退速度 == 10, "P3 Option A1: pistol-slot AR (weapontype=突击步枪) stays kb=10 got=" + pistolArProps.水平击退速度);

        var smgLongProps:Object = ShootInitCore.generateBulletProps(dummyActor, "长枪", baseWd, {});
        BulletInitializer.calculateKnockback(smgLongProps);
        check(smgLongProps.水平击退速度 == 12, "P3 Option A1: long-gun SMG (weapontype=冲锋枪) defaults to kb=12 got=" + smgLongProps.水平击退速度);

        dummyActor.长枪数据.weapontype = "突击步枪";
        var rifleProps:Object = ShootInitCore.generateBulletProps(dummyActor, "长枪", baseWd, {});
        check(rifleProps.水平击退速度 == 10, "P3 Option A1: assault rifle (weapontype=突击步枪) stays kb=10 got=" + rifleProps.水平击退速度);

        baseWd.knockback = 16;
        dummyActor.手枪数据.weapontype = "手枪";
        var explicitXmlKbProps:Object = ShootInitCore.generateBulletProps(dummyActor, "手枪", baseWd, {});
        check(explicitXmlKbProps.水平击退速度 == 16, "P3 Option A1: explicit weaponData.knockback=16 overrides category default got=" + explicitXmlKbProps.水平击退速度);
        delete baseWd.knockback;
    }

    private static function buildBatches():Void {
        batches = [];
        var kbs:Array = [10, 12, 14, 16, 18];
        var weapons:Array = ["PPK", "WaltherP99", "Glock18_Single", "Glock18_Dual", "Glock18_Tac", "TiP90", "UMP", "AK47"];
        var i:Number;
        var wId:String;
        var kb:Number;

        // Batch 0: 单发物理验证 (MOVE / STAGGER / TOUGH_BREAK) 在 kb=10,12,14,16,18 下的逐帧位移与硬直帧数
        var b0:Array = [];
        var states:Array = ["MOVE", "STAGGER", "TOUGH_BREAK"];
        for (var sIdx:Number = 0; sIdx < states.length; sIdx++) {
            for (i = 0; i < kbs.length; i++) {
                kb = kbs[i];
                b0.push({
                    scenario: "single_" + states[sIdx],
                    weaponId: "PPK",
                    kb: kb,
                    modId: "none",
                    enemyCount: 1,
                    forcedRegime: states[sIdx],
                    chaseSpeed: 0,
                    maxShots: 1,
                    startDist: 160
                });
            }
        }
        batches.push({ enemySwf: "../flashswf/arts/new/Codex光头保安素材.swf", linkage: "敌人-CF6光头保安", maxTicks: 50, specs: b0 });

        // Batch 1: 1v1 持续射击压制（高韧性纯被击移动 MOVE 态 vs 标准韧性 MOVE->STAGGER->TOUGH_BREAK 态）
        var b1:Array = [];
        for (var wIdx:Number = 0; wIdx < weapons.length; wIdx++) {
            wId = weapons[wIdx];
            var wKbList:Array = (wId == "AK47") ? [10, 14] : kbs;
            for (i = 0; i < wKbList.length; i++) {
                kb = wKbList[i];
                b1.push({
                    scenario: "chase_1v1_move",
                    weaponId: wId,
                    kb: kb,
                    modId: "none",
                    enemyCount: 1,
                    forcedRegime: "HIGH_TOUGH",
                    chaseSpeed: 5,
                    maxShots: 999,
                    startDist: 220
                });
                b1.push({
                    scenario: "chase_1v1_std",
                    weaponId: wId,
                    kb: kb,
                    modId: "none",
                    enemyCount: 1,
                    forcedRegime: "STD_TOUGH",
                    chaseSpeed: 5,
                    maxShots: 999,
                    startDist: 220
                });
            }
        }
        batches.push({ enemySwf: "../flashswf/arts/new/Codex光头保安素材.swf", linkage: "敌人-CF6光头保安", maxTicks: 90, specs: b1 });

        // Batch 2: 1v3 复数追击挤压共线多判 & 穿刺顺风车多判
        var b2:Array = [];
        var squishWeapons:Array = ["PPK", "WaltherP99", "Glock18_Single", "Glock18_Dual", "Glock18_Tac", "TiP90", "UMP", "AK47"];
        for (wIdx = 0; wIdx < squishWeapons.length; wIdx++) {
            wId = squishWeapons[wIdx];
            wKbList = (wId == "AK47") ? [10, 14] : kbs;
            for (i = 0; i < wKbList.length; i++) {
                kb = wKbList[i];
                b2.push({
                    scenario: "squish_1v3_move",
                    weaponId: wId,
                    kb: kb,
                    modId: "none",
                    enemyCount: 3,
                    enemySpacing: 42,
                    forcedRegime: "HIGH_TOUGH",
                    chaseSpeed: 5,
                    maxShots: 999,
                    startDist: 180
                });
                b2.push({
                    scenario: "squish_1v3_std",
                    weaponId: wId,
                    kb: kb,
                    modId: "none",
                    enemyCount: 3,
                    enemySpacing: 42,
                    forcedRegime: "STD_TOUGH",
                    chaseSpeed: 5,
                    maxShots: 999,
                    startDist: 180
                });
            }
        }
        // 单目标穿刺顺风车专项（检验击退过快是否导致穿刺弹同帧/跨帧对同一目标二次命中）
        var pierceWeapons:Array = ["Glock18_Tac", "TiP90"];
        for (wIdx = 0; wIdx < pierceWeapons.length; wIdx++) {
            wId = pierceWeapons[wIdx];
            for (i = 0; i < kbs.length; i++) {
                kb = kbs[i];
                b2.push({
                    scenario: "pierce_ride_1v1",
                    weaponId: wId,
                    kb: kb,
                    modId: "none",
                    enemyCount: 1,
                    forcedRegime: "STD_TOUGH",
                    chaseSpeed: 5,
                    maxShots: 999,
                    startDist: 180
                });
            }
        }
        batches.push({ enemySwf: "../flashswf/arts/new/Codex蛮蛮素材.swf", linkage: "敌人-CF6蛮蛮", maxTicks: 90, specs: b2 });

        // Batch 3: 配件耦合（黑爪扩张弹 / 灰蛊裂隙弹）与边界工况（左向、刚体、免疫击退、版边夹紧、换弹断档、跨Z轴）
        var b3:Array = [];
        var modWeapons:Array = ["PPK", "WaltherP99", "Glock18_Single", "Glock18_Dual", "Glock18_Tac", "TiP90", "UMP"];
        for (wIdx = 0; wIdx < modWeapons.length; wIdx++) {
            wId = modWeapons[wIdx];
            for (i = 0; i < kbs.length; i++) {
                kb = kbs[i];
                b3.push({
                    scenario: "mod_blackclaw_1v1",
                    weaponId: wId,
                    kb: kb,
                    modId: "BlackClaw",
                    enemyCount: 1,
                    forcedRegime: "STD_TOUGH",
                    chaseSpeed: 5,
                    maxShots: 999,
                    startDist: 220
                });
                // 灰蛊裂隙弹排除原生穿刺武器（excludeBulletTypes=pierce）
                if (wId != "Glock18_Tac" && wId != "TiP90") {
                    b3.push({
                        scenario: "mod_graygoo_1v3",
                        weaponId: wId,
                        kb: kb,
                        modId: "GrayGoo",
                        enemyCount: 3,
                        enemySpacing: 42,
                        forcedRegime: "STD_TOUGH",
                        chaseSpeed: 5,
                        maxShots: 999,
                        startDist: 180
                    });
                }
            }
        }
        // 边界工况
        b3.push({ scenario: "edge_left_dir", weaponId: "Glock18_Single", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "HIGH_TOUGH", chaseSpeed: 5, maxShots: 999, startDist: 220, leftDir: true });
        b3.push({ scenario: "edge_rigid_chase", weaponId: "Glock18_Single", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "RIGID", chaseSpeed: 5, maxShots: 999, startDist: 220 });
        b3.push({ scenario: "edge_rigid_dash", weaponId: "Glock18_Single", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "RIGID", chaseSpeed: 9, maxShots: 999, startDist: 220 });
        b3.push({ scenario: "edge_immune_kb", weaponId: "Glock18_Single", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "IMMUNE_KB", chaseSpeed: 5, maxShots: 999, startDist: 220 });
        b3.push({ scenario: "edge_wall_clamp", weaponId: "Glock18_Single", kb: 16, modId: "none", enemyCount: 1, forcedRegime: "STD_TOUGH", chaseSpeed: 5, maxShots: 999, startDist: 180, wallOffset: 240 });
        b3.push({ scenario: "edge_reload_gap", weaponId: "PPK", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "HIGH_TOUGH", chaseSpeed: 5, maxShots: 999, startDist: 220, enforceReload: true, reloadFrames: 36 });
        b3.push({ scenario: "edge_cross_z_hit", weaponId: "Glock18_Single", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "HIGH_TOUGH", chaseSpeed: 5, maxShots: 999, startDist: 220, zDelta: 22 });
        b3.push({ scenario: "edge_cross_z_miss", weaponId: "Glock18_Single", kb: 14, modId: "none", enemyCount: 1, forcedRegime: "HIGH_TOUGH", chaseSpeed: 5, maxShots: 999, startDist: 220, zDelta: 38 });
        batches.push({ enemySwf: "../flashswf/arts/new/Codex大刀机器人素材.swf", linkage: "敌人-CF6大刀机器人", maxTicks: 90, specs: b3 });
    }

    private static function initEnemyActor(u:MovieClip):Void {
        u.hp = u.hp满血值 = 30000;
        u.等级 = 50;
        u.空手攻击力 = 100;
        u.防御力 = 100;
        u.damageTakenMultiplier = 1;
        u.躲闪率 = 8;
        u.韧性系数 = 0.03;
        u.remainingImpactForce = 0;
        u.ti61CrumbleTakenMultiplier = 1;
        u.魔法抗性 = { 波: 0, 钢: 0, 精英: 0 };
        u.dispatcher = new EventDispatcher();
        u.shield = AdaptiveShield.createDormant("hkb-actor");
        u.shield.setOwner(u);
        u._x = 200;
        u._y = u.Z轴坐标 = 200;
        u.myxscale = 100;
        u.中心高度 = 75;
        u.是否为敌人 = true;
        u.状态 = "空手站立";
        u.攻击模式 = "空手";
        u.方向 = "左";
        u.攻击目标 = "无";
        u.刚体 = false;
        u.免疫击退 = false;
        u.硬直中 = false;
        u.浮空 = false;
        u.倒地 = false;
        u.受击反制 = false;
        u.unitAI = { data: {} };
        u.行走X速度 = 3;
        u.行走Y速度 = 1.5;
        u.跑X速度 = 5;
        u.跑Y速度 = 2.5;
        u.起跳速度 = -10;
        u.垂直速度 = 0;
        u.起始Y = 200;
        u.方向改变 = function(direction:String):Void {
            this.方向 = direction;
            this._xscale = direction == "左" ? -100 : 100;
        };
        u.状态改变 = function(state:String):Void {
            if (this.状态 == state) return;
            this.状态 = state;
            if (state == "被击" && this.__fixtureHurtPose != undefined) {
                this.__fixtureHurtFrame = _root.帧计时器.当前帧数;
            } else {
                delete this.__fixtureHurtFrame;
            }
            this.gotoAndStop(state);
        };
        u.动画完毕 = function():Void {
            this.倒地 = false;
            this.浮空 = false;
            this.状态改变("空手站立");
        };
        u.移动 = function(direction:String, speed:Number):Void {
            Mover.move2D(this, direction, speed);
            if (this.wallMaxX != undefined && this._x > this.wallMaxX) {
                this._x = this.wallMaxX;
            }
            if (this.wallMinX != undefined && this._x < this.wallMinX) {
                this._x = this.wallMinX;
            }
        };
        u.移动钝感硬直 = prodHitstop;
        u.被击移动 = prodKnockbackMove;
        u.死亡检测 = function():Void {};
        u.击飞浮空 = function():Void {
            this.浮空 = true;
            this.状态改变("被击");
        };
        u.击飞倒地 = function():Void {
            this.倒地 = true;
            this.浮空 = false;
        };
        u.硬直 = function(mc:MovieClip, time:Number):Void {
            this.移动钝感硬直(time);
        };
        u.aabbCollider = new AABBCollider(0, 0, 0, 0);
        u.stop();
    }

    private static function startBatch():Void {
        ready = false;
        ticks = 0;
        loadStep = 0;
        cases = [];
        activeBullets = [];
        currentBatchSpecs = batches[stage].specs;

        world = _root.createEmptyMovieClip("__hkbWorld" + stage, _root.getNextHighestDepth());
        _root.gameworld = world;
        world._visible = false;
        walls = _root.createEmptyMovieClip("__hkbWalls" + stage, _root.getNextHighestDepth());
        _root.collisionLayer = walls;
        walls.hitTest = function(x:Number, y:Number, precise:Boolean):Boolean { return false; };

        listener = {
            onLoadInit: function(mc:MovieClip):Void {
                HandgunKnockbackCombatTest.onClipLoaded(mc);
            },
            onLoadError: function(mc:MovieClip, code:String):Void {
                HandgunKnockbackCombatTest.check(false, "load clip error stage=" + stage + " step=" + loadStep + " code=" + code);
                HandgunKnockbackCombatTest.finish();
            }
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        check(loader.loadClip(batches[stage].enemySwf, world), "load enemy swf stage " + stage);
    }

    private static function onClipLoaded(mc:MovieClip):Void {
        if (finished) return;
        mc.stop();
        if (loadStep == 0) {
            loadStep = 1;
            bulletArea = world.createEmptyMovieClip("子弹区域", world.getNextHighestDepth());
            check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf", bulletArea), "load bullet swf stage " + stage);
            return;
        }
        setupBatchCases();
    }

    private static function setupBatchCases():Void {
        world.createEmptyMovieClip("地图", world.getNextHighestDepth());
        _root.Xmin = world.Xmin = -5000;
        _root.Xmax = world.Xmax = 50000;
        _root.Ymin = world.Ymin = -2000;
        _root.Ymax = world.Ymax = 300000;
        DepthManager.instance = new DepthManager(world, 100000, 1000000, 64);
        DepthManager.instance.calibrate(-2000, 300000);

        if (batches[stage].seed != undefined) {
            var seed:Number = batches[stage].seed;
            LinearCongruentialEngine.getInstance().restoreState(seed);
            var pink:Object = PinkNoiseEngine.getInstance();
            pink.seed = seed + 314159; pink.reset();
            mathStream = new SeededLinearCongruentialEngine(seed + 161803);
        }
        var linkage:String = batches[stage].linkage;
        for (var i:Number = 0; i < currentBatchSpecs.length; i++) {
            var spec:Object = currentBatchSpecs[i];
            var laneZ:Number = 300 + i * 350;
            var originX:Number = 1000;
            var leftDir:Boolean = (spec.leftDir === true);
            var wProps:Object = computeModdedProps(weaponCatalog[spec.weaponId], spec.modId, spec.kb);

            var player:MovieClip = world.createEmptyMovieClip("hkbPlayer_" + i, world.getNextHighestDepth());
            player._x = originX;
            player._y = player.Z轴坐标 = laneZ;
            player._xscale = leftDir ? -100 : 100;
            player.方向 = leftDir ? "左" : "右";
            player.hp = player.hp满血值 = 10000;
            player.是否为敌人 = false;
            player.基础命中率 = 10000;
            player.命中率 = 10000;
            player.状态 = wProps.mode + "站立";
            player.攻击模式 = wProps.mode;
            player.dispatcher = new EventDispatcher();

            var enemies:Array = [];
            var eCount:Number = spec.enemyCount || 1;
            var spacing:Number = spec.enemySpacing || 42;
            for (var eIdx:Number = 0; eIdx < eCount; eIdx++) {
                var u:MovieClip = world.attachMovie(linkage, "hkbEnemy_" + i + "_" + eIdx, world.getNextHighestDepth(), { 光头保安变身: false });
                check(u != null, "attach enemy stage=" + stage + " case=" + i + " idx=" + eIdx);
                initEnemyActor(u);
                enemies.push(u);
            }

            var rec:Object = {
                shotgunHits:[{}, {}, {}], positions:[],
                shotsFired: 0,
                bulletsSpawned: 0,
                totalHits: 0,
                multiHitShots: 0,
                sameTargetMultiHits: 0,
                moveHits: 0,
                staggerHits: 0,
                toughBreakHits: 0,
                launchHits: 0,
                totalDamage: 0,
                hitstopFrames: 0,
                slideFrames: 0,
                breachFrame: -1,
                coLinearFrame: -1,
                minDistX: 99999,
                maxPushX: 0,
                frameDeltas: [],
                reloadingUntil: -1,
                magRemaining: wProps.magCapacity
            };

            cases.push({
                index: i,
                spec: spec,
                wProps: wProps,
                player: player,
                enemies: enemies,
                record: rec,
                originX: originX,
                laneZ: laneZ,
                leftDir: leftDir,
                placed: false
            });
        }
        ready = true;
        ticks = 0;
    }

    private static function configureEnemyRegime(u:MovieClip, spec:Object, c:Object, eIdx:Number):Void {
        var dirSign:Number = c.leftDir ? -1 : 1;
        var spacing:Number = spec.enemySpacing || 42;
        var startX:Number = c.originX + dirSign * (spec.startDist + eIdx * spacing);
        var zDelta:Number = spec.zDelta || 0;
        if (spec.entering && eIdx == 1) {
            // The rear target starts outside the first shot's depth band and pursues at its authored test speed.
            var arrivalFrames:Number = Math.ceil((spec.startDist + spacing - 30) / (c.wProps.speed + spec.chaseSpeed)) + 2;
            zDelta = c.wProps.zRange + u.跑Y速度 * arrivalFrames;
            u.__testEnterLane = true;
        }
        u._x = startX;
        u._y = u.Z轴坐标 = c.laneZ + zDelta;
        u.起始Y = u.Z轴坐标;
        u.方向改变(c.leftDir ? "右" : "左");
        u.跑X速度 = spec.chaseSpeed != undefined ? spec.chaseSpeed : 5;
        u.状态 = "空手站立";
        u.硬直中 = false;
        u.浮空 = false;
        u.倒地 = false;
        u.刚体 = false;
        u.免疫击退 = false;
        u.remainingImpactForce = 0;
        u.lastHitBulletName = "";
        delete u.onEnterFrame;
        delete u.__enemyHitMoveDriver;
        if (u.knockStiffID != null) {
            EnhancedCooldownWheel.I().removeTask(u.knockStiffID);
            u.knockStiffID = null;
        }
        if (spec.wallOffset != undefined) {
            if (c.leftDir) u.wallMinX = c.originX - spec.wallOffset;
            else u.wallMaxX = c.originX + spec.wallOffset;
        }

        // ImpactHandler.calculateImpactCap: cap = toughness * hp / damageRatio
        // 防御力=100 => damageRatio = 300/400 = 0.75, hp=30000 => cap = toughness * 40000
        // ImpactHandler.calculateStaggerFromCap: staggerBoundary = cap / 2 / 躲闪率 (躲闪率=8 => cap / 16)
        var regime:String = spec.forcedRegime;
        if (regime == "MOVE" || regime == "HIGH_TOUGH") {
            u.韧性系数 = 0.5; // cap=20000, stagger=1250 -> 纯被击移动(摩擦力3)
        } else if (regime == "STAGGER") {
            u.韧性系数 = 0.03; // cap=1200, stagger=75
            u.remainingImpactForce = 85; // 命中后 > 75 且 < 1200 -> 被击硬直(摩擦力2)
        } else if (regime == "TOUGH_BREAK") {
            u.韧性系数 = 0.03; // cap=1200
            u.remainingImpactForce = 1250; // 命中后 > 1200 -> 韧性击穿(摩擦力0.5)
        } else if (regime == "RIGID") {
            u.韧性系数 = 0.03;
            u.刚体 = true;
        } else if (regime == "IMMUNE_KB") {
            u.韧性系数 = 0.03;
            u.免疫击退 = true;
        } else {
            // STD_TOUGH: cap=1200, stagger=75 -> 真实经历 MOVE -> STAGGER -> TOUGH_BREAK 递进
            u.韧性系数 = 0.03;
        }

        if (spec.shotgun && !measureCounterattacks) u.__fixtureHurtPose = (spec.sample + eIdx) % 2;
        if (spec.frail && eIdx == 0) u.hp = 1;
        u.aabbCollider.updateFromUnitArea(u);

        // 重置并包裹真实 HitUpdater.getUpdater(u)，确保先完成 ImpactStateHandler 状态/摩擦力结算，再统计命中分类
        if (u.dispatcher != undefined) {
            u.dispatcher.destroy();
        }
        u.dispatcher = new EventDispatcher();
        var baseHitUpdater:Function = HitUpdater.getUpdater(u);
        u.dispatcher.subscribe("hit", function(target:MovieClip, shooter:MovieClip, bullet:MovieClip, collisionResult:Object, damageResult:Object):Void {
            baseHitUpdater(target, shooter, bullet, collisionResult, damageResult);
            var rec:Object = c.record;
            rec.totalHits++;
            if (c.spec.shotgun && bullet.testShotNumber > 0) {
                var segments:Number = Number(damageResult.actualScatterUsed) - Number(damageResult.scatterMissCount);
                if (segments > 0 && damageResult.damageSize > 0) {
                    var map:Object = rec.shotgunHits[bullet.testShotNumber - 1];
                    map[eIdx] = (Number(map[eIdx]) || 0) + segments;
                }
            }
            if (bullet.hkbHitTargets == undefined) {
                bullet.hkbHitTargets = {};
                bullet.hkbHitTargetCount = 0;
            }
            if (bullet.hkbHitTargets[target._name] == true) {
                rec.sameTargetMultiHits++;
            } else {
                bullet.hkbHitTargets[target._name] = true;
                bullet.hkbHitTargetCount++;
                if (bullet.hkbHitTargetCount == 2) {
                    rec.multiHitShots++;
                }
            }
            if (target.浮空) {
                rec.launchHits++;
            } else if (!target.刚体 && target.减速度 == 0.5) {
                rec.toughBreakHits++;
            } else if (!target.刚体 && target.减速度 == 2) {
                rec.staggerHits++;
            } else {
                rec.moveHits++;
            }
        }, u);
    }

    /** The opposing actor's authored guardDriver owns attack timing, reach, stance and release.
     * Give the stationary shooter the standing guard's measured hurtbox for this controlled matchup. */
    private static function setupCounterattack(c:Object):Void {
        var u:MovieClip = c.enemies[0];
        var p:MovieClip = c.player;
        var bounds:Object = u.area.getBounds(u);
        initEnemyActor(p);
        p._x = c.originX; p._y = p.Z轴坐标 = c.laneZ;
        p.hp = p.hp满血值 = 10000;
        p.是否为敌人 = false; p.攻击模式 = "长枪"; p.方向改变("右");
        p.命中率 = p.基础命中率 = 10000;
        var area:MovieClip = p.createEmptyMovieClip("area", p.getNextHighestDepth());
        area.beginFill(0, 0);
        area.moveTo(bounds.xMin, bounds.yMin); area.lineTo(bounds.xMax, bounds.yMin);
        area.lineTo(bounds.xMax, bounds.yMax); area.lineTo(bounds.xMin, bounds.yMax);
        area.lineTo(bounds.xMin, bounds.yMin); area.endFill();
        p.aabbCollider.updateFromUnitArea(p);
        var update:Function = HitUpdater.getUpdater(p);
        c.record.firstIncoming = -1;
        c.record.incomingDamage = 0;
        p.dispatcher.subscribe("hit", function(target:MovieClip, shooter:MovieClip, bullet:MovieClip, collision:Object, result:Object):Void {
            update(target, shooter, bullet, collision, result);
            var frame:Number = HandgunKnockbackCombatTest.ticks - 5;
            if (target !== p || shooter !== u || frame < 0 || !(result.damageSize > 0)
                || !(result.actualScatterUsed > result.scatterMissCount)) return;
            if (c.record.firstIncoming < 0) c.record.firstIncoming = frame;
            if (frame < c.wProps.frameInterval) c.record.incomingDamage += result.damageSize;
        }, p);
        u.攻击目标 = p._name;
        u.命中率 = u.基础命中率 = 10000;
        if (c.spec.winding) u.状态改变("近战");
    }

    private static function rebuildTargetCache():Void {
        var allEnemies:Array = [];
        var i:Number;
        var eIdx:Number;
        for (i = 0; i < cases.length; i++) {
            var c:Object = cases[i];
            if (!c.placed) continue;
            for (eIdx = 0; eIdx < c.enemies.length; eIdx++) {
                var u:MovieClip = c.enemies[eIdx];
                if (u.hp > 0) {
                    u.aabbCollider.updateFromUnitArea(u);
                    allEnemies.push(u);
                }
            }
        }
        fixtureCache = makeFixtureCache(allEnemies);
        if (measureCounterattacks) {
            var friendly:Array = [];
            for (i = 0; i < cases.length; i++) {
                var player:MovieClip = cases[i].player;
                if (cases[i].placed && player.hp > 0) {
                    player.aabbCollider.updateFromUnitArea(player);
                    friendly.push(player);
                }
            }
            friendlyFixtureCache = makeFixtureCache(friendly);
        }
    }

    private static function makeFixtureCache(allEnemies:Array):Object {
        var i:Number;
        // 按 aabbCollider.left 升序排列以满足 BulletQueueProcessor 扫描线契约
        for (i = 1; i < allEnemies.length; i++) {
            var cur:MovieClip = allEnemies[i];
            var curL:Number = cur.aabbCollider.left;
            var j:Number = i - 1;
            while (j >= 0 && allEnemies[j].aabbCollider.left > curL) {
                allEnemies[j + 1] = allEnemies[j];
                j--;
            }
            allEnemies[j + 1] = cur;
        }
        var lefts:Array = [];
        var rights:Array = [];
        var rightMax:Array = [];
        var runMax:Number = -Infinity;
        for (i = 0; i < allEnemies.length; i++) {
            var a:AABBCollider = allEnemies[i].aabbCollider;
            lefts[i] = a.left;
            rights[i] = a.right;
            if (a.right > runMax) runMax = a.right;
            rightMax[i] = runMax;
        }
        return {
            data: allEnemies,
            leftValues: lefts,
            rightValues: rights,
            rightMaxValues: rightMax
        };
    }

    private static function fireBullet(c:Object, offsetY:Number):Void {
        var w:Object = c.wProps;
        var p:MovieClip = c.player;
        var dirSign:Number = c.leftDir ? -1 : 1;
        var props:Object = {
            子弹种类: w.bullet,
            发射者: p._name,
            shootX: p._x + dirSign * 30,
            shootY: p._y - 75 + offsetY,
            shootZ: p.Z轴坐标,
            子弹速度: w.speed,
            子弹威力: w.power,
            子弹散射度: 0,
            武器扩散倍率: 0,
            发射间隔毫秒: w.intervalMs,
            霰弹值: 1,
            Z轴攻击范围: w.zRange,
            击倒率: w.knockdown,
            水平击退速度: w.kb,
            垂直击退速度: 0,
            击中后子弹的效果: w.hitEffect,
            伤害类型: w.damageType,
            魔法伤害属性: w.magicAttr,
            角度偏移: 0,
            命中率: 10000
        };
        if (c.spec.shotgun) {
            props.霰弹值 = w.split;
            props.子弹散射度 = props.站立子弹散射度 = w.spread;
            props.武器扩散倍率 = 1;
            props.霰弹分配模式 = 1;
            props.testShotNumber = c.record.shotsFired;
            var positions:Array = [];
            for (var pos:Number = 0; pos < c.enemies.length; pos++) {
                var actor:MovieClip = c.enemies[pos];
                positions.push(Math.round(actor._x - p._x) + "/" + Math.ceil(actor.hp) + "/" + (actor.硬直中 ? "stun" : actor.状态));
            }
            c.record.positions.push(positions.join(","));
        }
        if (w.pierceLimit != undefined) {
            props.pierceLimit = w.pierceLimit;
        }
        var b:Object = shoot(props);
        check(b != null, "spawn bullet case=" + c.index);
        if (c.spec.shotgun && b != null) {
            b.testShotNumber = c.record.shotsFired;
            delete ChainUnitManager.getLayer().onEnterFrame;
        }
        c.record.bulletsSpawned++;
    }

    private static function stepEnemyAI(u:MovieClip, c:Object):Void {
        // The native guard uses AVM1 random(2) on clip load. Both original reactions are
        // sampled, at the same animation age for all kb settings. The selected clip's own
        // frame action still owns recovery. Frame 1 starts a0 and frame 13 starts a1.
        if (u.__fixtureHurtFrame != undefined) {
            var age:Number = _root.帧计时器.当前帧数 - u.__fixtureHurtFrame;
            if (age >= 2) {
                var pose:Number = u.__fixtureHurtPose;
                var lastAge:Number = pose == 0 ? 7 : 6;
                if (age <= lastAge) {
                    var frame:Number = (pose == 0 ? 1 : 13) + age;
                    var hurtBody:MovieClip = u.man;
                    hurtBody.gotoAndStop(frame);
                    if (age == 2 && hurtBody._currentframe == frame) authoredHurtSamples[pose]++;
                } else {
                    check(false, "authored hurt timeline did not release its actor at the sampled end frame");
                    delete u.__fixtureHurtFrame;
                }
            }
        }
        if (u.__enemyHitMoveDriver != undefined) {
            u.__enemyHitMoveDriver();
        }
        if (u.跑X速度 <= 0 || u.hp <= 0) return;
        // 真实硬直/被击/浮空/倒地门控：硬直中或处于被击/击倒状态时无法主动追击
        if (u.硬直中 || u.浮空 || u.倒地 || u.状态 == "被击" || u.状态 == "击倒") {
            return;
        }
        var chaseDir:String = c.leftDir ? "右" : "左";
        u.方向改变(chaseDir);
        u.移动(chaseDir, u.跑X速度);
        if (u.__testEnterLane && u.Z轴坐标 > c.laneZ) {
            u.移动("上", Math.min(u.跑Y速度, u.Z轴坐标 - c.laneZ));
        }
    }

    private static function tick():Void {
        if (finished) return;
        ticks++;
        _root.帧计时器.当前帧数++;
        if (!ready) {
            if (ticks > 600) {
                check(false, "load timeout stage=" + stage);
                finish();
            }
            return;
        }

        // 在冷却轮 tick 解除到期硬直前，记录当前帧处于硬直中的状态（对齐 u.onEnterFrame 看到的真实硬直帧数）
        var i:Number;
        var c0:Object;
        for (i = 0; i < cases.length; i++) {
            c0 = cases[i];
            if (c0.placed && c0.enemies[0].硬直中 === true) {
                c0.record.hitstopFrames++;
            }
        }
        EnhancedCooldownWheel.I().tick();

        var eIdx:Number;
        var u:MovieClip;

        // Tick 3: 完成元件首帧脚本初始化后放置单位并启动战斗
        if (ticks == 3) {
            for (i = 0; i < cases.length; i++) {
                var cInit:Object = cases[i];
                for (eIdx = 0; eIdx < cInit.enemies.length; eIdx++) {
                    configureEnemyRegime(cInit.enemies[eIdx], cInit.spec, cInit, eIdx);
                }
                if (measureCounterattacks) setupCounterattack(cInit);
                cInit.placed = true;
            }
        }

        if (measureCounterattacks && ticks == 4) {
            for (i = 0; i < cases.length; i++) {
                var trial:Object = cases[i];
                if (trial.spec.winding) {
                    var guard:MovieClip = trial.enemies[0];
                    check(guard.guardAttackOwner.mode == "melee", "authored wind-up armed " + trial.spec.scenario);
                    guard.man.gotoAndStop(18 + trial.spec.sample);
                }
            }
        }
        var firstShotTick:Number = measureCounterattacks ? 5 : 4;
        if (ticks >= firstShotTick) {
            var combatTick:Number = ticks - firstShotTick;
            for (i = 0; i < cases.length; i++) {
                var c:Object = cases[i];
                var spec:Object = c.spec;
                var rec:Object = c.record;
                var w:Object = c.wProps;
                var primary:MovieClip = c.enemies[0];
                var beforeX:Number = primary._x;

                // 1. 推进敌人被击位移与追击 AI
                for (eIdx = 0; eIdx < c.enemies.length; eIdx++) {
                    stepEnemyAI(c.enemies[eIdx], c);
                }

                var deltaX:Number = (primary._x - beforeX) * (c.leftDir ? -1 : 1);
                if (combatTick < 25) {
                    rec.frameDeltas.push(Math.round(deltaX * 10) / 10);
                }
                if (deltaX > 0.01) rec.slideFrames++;

                // 2. 射击调度（支持单枪、双枪同帧双弹、换弹窗口）
                if (rec.shotsFired < spec.maxShots && combatTick >= rec.reloadingUntil) {
                    if (combatTick % w.frameInterval == 0) {
                        rec.shotsFired++;
                        fireBullet(c, 0);
                        if (w.dual) {
                            fireBullet(c, -6);
                        }
                        if (spec.enforceReload === true) {
                            rec.magRemaining--;
                            if (rec.magRemaining <= 0) {
                                rec.reloadingUntil = combatTick + (spec.reloadFrames || 36);
                                rec.magRemaining = w.magCapacity;
                            }
                        }
                    }
                }
            }

            // 3. 推进所有在飞子弹的 precheck 入队与全队列扫描线碰撞结算
            for (var bi:Number = activeBullets.length - 1; bi >= 0; bi--) {
                var b:MovieClip = activeBullets[bi];
                if (b == null || b._parent == undefined) {
                    activeBullets.splice(bi, 1);
                } else {
                    b.__precheck.call(b);
                }
            }
            rebuildTargetCache();
            if (cases[0].spec.shotgun) ChainUnitManager.tick();
            BulletQueueProcessor.processQueue();

            // 4. 采样距离、共线挤压与突围帧
            for (i = 0; i < cases.length; i++) {
                c = cases[i];
                rec = c.record;
                var dirSign:Number = c.leftDir ? -1 : 1;
                var minE:Number = 99999;
                var maxE:Number = -99999;
                for (eIdx = 0; eIdx < c.enemies.length; eIdx++) {
                    u = c.enemies[eIdx];
                    var relX:Number = (u._x - c.originX) * dirSign;
                    if (relX < minE) minE = relX;
                    if (relX > maxE) maxE = relX;
                }
                if (minE < rec.minDistX) rec.minDistX = minE;
                var pushFromStart:Number = minE - c.spec.startDist;
                if (pushFromStart > rec.maxPushX) rec.maxPushX = pushFromStart;
                if (minE <= 45 && rec.breachFrame < 0) {
                    rec.breachFrame = combatTick;
                }
                if (c.enemies.length > 1 && (maxE - minE) <= 28 && rec.coLinearFrame < 0) {
                    rec.coLinearFrame = combatTick;
                }
            }
        }

        if (ticks >= batches[stage].maxTicks) {
            finalizeBatch();
        }
    }

    private static function finalizeBatch():Void {
        for (var i:Number = 0; i < cases.length; i++) {
            var c:Object = cases[i];
            var spec:Object = c.spec;
            var rec:Object = c.record;
            var w:Object = c.wProps;
            var dirSign:Number = c.leftDir ? -1 : 1;

            var totalDmg:Number = 0;
            var minRelX:Number = 99999;
            var maxRelX:Number = -99999;
            for (var eIdx:Number = 0; eIdx < c.enemies.length; eIdx++) {
                var u:MovieClip = c.enemies[eIdx];
                totalDmg += (30000 - u.hp);
                var relX:Number = (u._x - c.originX) * dirSign;
                if (relX < minRelX) minRelX = relX;
                if (relX > maxRelX) maxRelX = relX;
            }
            rec.totalDamage = Math.round(totalDmg);
            var netPush:Number = Math.round((minRelX - spec.startDist) * 10) / 10;
            var spanX:Number = Math.round((maxRelX - minRelX) * 10) / 10;
            var hps:Number = rec.bulletsSpawned > 0 ? Math.round((rec.totalHits / rec.bulletsSpawned) * 100) : 0;

            caseCount++;
            if (measureCounterattacks) {
                var deadline:Number = w.frameInterval;
                var incoming:Boolean = rec.firstIncoming >= 0 && rec.firstIncoming < deadline;
                check(rec.shotsFired === spec.maxShots, "one authored shot or held fire " + spec.scenario);
                if (!spec.holdFire) check(rec.shotgunHits[0][0] > 0, "outgoing real hit " + spec.scenario);
                if (spec.scenario == "近身不射对照") check(incoming && c.player.hp < 10000, "positive return-fire control");
                if (spec.scenario == "界外不射对照") check(!incoming && c.player.hp == 10000, "out-of-reach return-fire control");
                trace("[SHOTGUN_THREAT] " + w.id + "|" + spec.scenario + "|" + spec.kb + "|" + spec.sample
                    + "|" + deadline + "|" + rec.firstIncoming + "|" + rec.incomingDamage + "|" + c.player.hp
                    + "|" + c.enemies[0].hp + "|" + c.enemies[0].guardMeleeCount);
                continue;
            }
            if (spec.shotgun) {
                var detail:Array = [];
                for (var shot:Number = 0; shot < 3; shot++) {
                    var applied:Array = [];
                    for (var enemy:Number = 0; enemy < c.enemies.length; enemy++) applied.push(rec.shotgunHits[shot][enemy] || 0);
                    detail.push(applied.join(","));
                }
                check(rec.shotsFired == 3 && rec.shotgunHits[0][0] > 0, "first real non-MISS hit " + w.id + "/" + spec.scenario + "/" + spec.kb);
                if (spec.entering) {
                    check(!rec.shotgunHits[0][1] && c.enemies[1].Z轴坐标 - c.laneZ < w.zRange,
                        "first shot hits only front and the rear chaser reaches the lane " + w.id + "/" + spec.scenario);
                }
                trace("[SHOTGUN_CONTACT] " + w.id + "|" + spec.scenario + "|" + spec.kb + "|" + detail.join(";") + "|" + rec.positions.join(";") + "|" + spec.sample);
                continue;
            }
            verifyCaseAssertions(c, netPush, spanX);

            trace('[HKB_METRIC] {"scenario":"' + spec.scenario
                + '","weapon":"' + spec.weaponId
                + '","mod":"' + (spec.modId || "none")
                + '","baseKb":' + spec.kb
                + ',"effKb":' + w.kb
                + ',"effImpact":' + w.knockdown
                + ',"shots":' + rec.shotsFired
                + ',"bullets":' + rec.bulletsSpawned
                + ',"hits":' + rec.totalHits
                + ',"hps100":' + hps
                + ',"multiHitShots":' + rec.multiHitShots
                + ',"sameTargetMulti":' + rec.sameTargetMultiHits
                + ',"moveHits":' + rec.moveHits
                + ',"staggerHits":' + rec.staggerHits
                + ',"breakHits":' + rec.toughBreakHits
                + ',"launchHits":' + rec.launchHits
                + ',"hitstopFrames":' + rec.hitstopFrames
                + ',"slideFrames":' + rec.slideFrames
                + ',"netPushX":' + netPush
                + ',"minDistX":' + Math.round(rec.minDistX * 10) / 10
                + ',"spanX":' + spanX
                + ',"coLinearFrame":' + rec.coLinearFrame
                + ',"breachFrame":' + rec.breachFrame
                + ',"dmg":' + rec.totalDamage
                + ',"deltas":"' + rec.frameDeltas.slice(0, 12).join(",") + '"}');
        }

        loader.removeListener(listener);
        world.removeMovieClip();
        walls.removeMovieClip();
        stage++;
        if (stage < batches.length) {
            startBatch();
        } else {
            finish();
        }
    }

    private static function verifyCaseAssertions(c:Object, netPush:Number, spanX:Number):Void {
        var spec:Object = c.spec;
        var rec:Object = c.record;
        var kb:Number = spec.kb;

        if (spec.scenario == "single_MOVE") {
            // 理论公式验证：摩擦力=3，v1=kb-3, v2=kb-6...
            var expMove:Number = 0;
            var spd:Number = kb;
            while ((spd -= 3) > 0) expMove += spd;
            check(Math.abs(netPush - expMove) < 0.5, "single_MOVE exact displacement kb=" + kb + " got=" + netPush + " exp=" + expMove);
            check(rec.hitstopFrames == 3, "single_MOVE 70ms hitstop equals 3 frames at 30fps got=" + rec.hitstopFrames);
        } else if (spec.scenario == "single_STAGGER") {
            var expStagger:Number = 0;
            spd = kb;
            while ((spd -= 2) > 0) expStagger += spd;
            check(Math.abs(netPush - expStagger) < 0.5, "single_STAGGER exact displacement kb=" + kb + " got=" + netPush + " exp=" + expStagger);
        } else if (spec.scenario == "single_TOUGH_BREAK") {
            var expBreak:Number = 0;
            spd = kb;
            while ((spd -= 0.5) > 0) expBreak += spd;
            check(Math.abs(netPush - expBreak) < 0.5, "single_TOUGH_BREAK exact displacement kb=" + kb + " got=" + netPush + " exp=" + expBreak);
        } else if (spec.scenario == "edge_immune_kb") {
            check(rec.totalHits > 0 && rec.slideFrames == 0, "edge_immune_kb takes hits but zero knockback slide");
        } else if (spec.scenario == "edge_rigid_chase") {
            check(rec.totalHits > 0 && rec.staggerHits == 0 && rec.toughBreakHits == 0, "edge_rigid_chase never enters stagger/break");
        } else if (spec.scenario == "edge_wall_clamp") {
            check(netPush <= (spec.wallOffset - spec.startDist + 0.5), "edge_wall_clamp respects map boundary");
        } else if (spec.scenario == "edge_cross_z_hit") {
            check(rec.totalHits > 0, "edge_cross_z_hit within zRange=30 hits enemy");
        } else if (spec.scenario == "edge_cross_z_miss") {
            check(rec.totalHits == 0, "edge_cross_z_miss outside zRange=30 misses enemy");
        } else {
            check(rec.totalHits > 0 && isFinite(netPush), "combat case valid hits " + spec.scenario + "/" + spec.weaponId + "/kb=" + kb);
        }
    }

    private static function finish():Void {
        if (finished) return;
        finished = true;
        if (driver != null) delete driver.onEnterFrame;
        if (loader != null) loader.removeListener(listener);
        if (world != null) world.removeMovieClip();
        if (walls != null) walls.removeMovieClip();

        if (saved != null) {
            var queue:Object = BulletQueueProcessor;
            var cache:Object = TargetCacheManager;
            queue.activeQueues = saved.queues;
            queue.fakeUnits = saved.fake;
            queue.queueUIDs = saved.uids;
            queue._raySettleProbe = saved.probe;
            cache.acquireEnemyCache = saved.acquireEnemy;
            LinearCongruentialEngine.getInstance().restoreState(saved.seed);
            if (saved.pinkState != null) {
                var pink:Object = PinkNoiseEngine.getInstance();
                for (var key:String in saved.pinkState) pink[key] = saved.pinkState[key];
                Math.random = saved.nativeMath;
                if (saved.mathReadOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
                mathStream = null;
            }
            _root.帧计时器.eventBus.destroy();
            _root.gameworld = saved.world;
            _root.帧计时器 = saved.clock;
            _root.暂停 = saved.paused;
            _root.控制目标 = saved.target;
            _root.collisionLayer = saved.collision;
            _root.Xmin = saved.xmin;
            _root.Xmax = saved.xmax;
            _root.Ymin = saved.ymin;
            _root.Ymax = saved.ymax;
            _root.随机偏移 = saved.random;
            _root.对象浅拷贝 = saved.copy;
            _root.子弹区域shoot传递 = saved.shoot;
            _root.钝感硬直时间 = saved.hitstopTime;
            if (_root._cdWheel != undefined && saved.cdWheelEnterFrame != undefined) {
                _root._cdWheel.onEnterFrame = saved.cdWheelEnterFrame;
            }
        }

        if (authoredHurtSamples != null) {
            check(authoredHurtSamples[0] > 0 && authoredHurtSamples[1] > 0, "both authored guard hit reactions were sampled");
            trace("[SHOTGUN_HURT_POSES] a0=" + authoredHurtSamples[0] + " a1=" + authoredHurtSamples[1]);
        }
        trace("HandgunKnockbackCombatTest: " + passed + " passed, " + failed + " failed; " + caseCount + " combat cases");
        trace("HandgunKnockbackCombatTest Tests Passed: " + passed);
        trace("HandgunKnockbackCombatTest Tests Failed: " + failed);
        if (_root.handgunKnockbackCombatComplete != undefined) {
            _root.handgunKnockbackCombatComplete();
        }
        if (driver != null) driver.removeMovieClip();
    }
}
