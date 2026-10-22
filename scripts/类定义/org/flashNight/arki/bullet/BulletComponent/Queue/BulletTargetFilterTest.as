import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue;

/**
 * BulletTargetFilterTest —— 逐弹目标过滤（仅命中目标标记 / 目标标记）的 AVM1 回归套件。
 *
 * injectHit 旁路注入通道（r15，公开入口，主命中循环同款守卫的兜底）：
 *  - 拒绝必须发生在伤害/命中次数/事件/死亡任何副作用之前（无探针实跑，检查零副作用）；
 *  - 接受路径用 _raySettleProbe 短路 settleHit，只证明 selection 到达结算口；
 *  - 开关 targetFilterEnabled !== true 时带标记子弹 fail-closed，匹配也拒绝；
 *  - 不带标记的子弹行为零变化（对无标记/有标记目标都照常命中）。
 *
 * 真实主命中循环最小夹具（r18，testMainLoopFilter）：
 *  - 跑真实 BulletQueueProcessor.processQueue + 真实 BulletQueue 排序/扫描线 + 真实 settleHit；
 *    只替换既有协作边界（TargetCacheManager 缓存 / EffectSystem / DamageCalculator），
 *    夹具模式与 RayPipelineEquivalenceTest、RockQueenBattleSkillTest 相同，不新增生产旁路。
 *  - 覆盖：同地面行+标记匹配才结算（异行匹配目标被 Z 门拒）、无标记/不匹配拒绝且零副作用、
 *    普通无标记子弹照常命中带标记目标、开关断开 fail-closed、无探针实跑下
 *    hit/kill/enemyKilled 仍经目标与发射者 dispatcher 发布（发射者经 gameworld[发射者名] 解析）。
 *
 * 注：settleHit 为 private static —— 探针是既有公开测试口；本测试只调公开 injectHit 与 processQueue。
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletTargetFilterTest {

    private static var passed:Number;
    private static var failed:Number;

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] BulletTargetFilter: " + message); }
    }

    private static function makeDispatcher(log:Array):Object {
        var d:Object = {};
        d.publish = function():Void { log.push(arguments[0]); };
        return d;
    }

    private static function makeBullet(marker:String):Object {
        var b:Object = {};
        b.hitCount = 0;
        b.伤害类型 = "真伤";          // 跳过 DodgeHandler，注入路自算 dodgeState="未躲闪"
        b.命中率 = 100;
        b.flags = 0;
        if (marker != undefined) b.仅命中目标标记 = marker;
        return b;
    }

    private static function makeTarget(marker:String, log:Array):Object {
        var t:Object = {};
        t.hp = 100; t._x = 11; t._y = 22; t._name = "MockEnemy"; t._killed = false;
        t.dispatcher = makeDispatcher(log);
        if (marker != undefined) t.目标标记 = marker;
        return t;
    }

    private static function makeShooter(log:Array):Object {
        var s:Object = {};
        s._x = 0; s._y = 0;
        s.dispatcher = makeDispatcher(log);
        return s;
    }

    // ==================== r18：真实主命中循环最小夹具 ====================
    // 跑真实 processQueue 主碰撞循环；只替换既有协作边界，不新增生产旁路。
    private static var _probeLog:Array;

    private static function makeLoopBullet(marker:String):Object {
        var b:Object = {};
        b._name = "loopBullet";
        b._x = 100; b._y = 200; b._xscale = 100;
        b.flags = 0; b.stateFlags = 0;
        b.aabbCollider = {left: 90, right: 110, top: 190, bottom: 210};
        b.chainGroup = {shotgun: null};
        b.Z轴坐标 = 202.4;
        b.Z轴攻击范围 = 20;
        b.xmov = 20; b.ymov = 0;
        b.发射者名 = "turretA";
        if (marker != undefined) b.仅命中目标标记 = marker;
        b.hitCount = 0;
        b.伤害类型 = "真伤";          // 主循环跳过 DodgeHandler
        b.命中率 = 100000;
        b.霰弹值 = 1;
        b.击中后子弹的效果 = "无";
        b.击中地图效果 = "无声火花";
        b.__moves = 0; b.__vanish = 0; b.__removed = 0;
        b.updateMovement = function(self:Object):Void { self.__moves++; };
        b.shouldDestroy = function(self:Object):Boolean { return false; };
        b.removeMovieClip = function():Void { this.__removed++; };
        b.gotoAndPlay = function(label:String):Void { if (label == "消失") this.__vanish++; };
        return b;
    }

    private static function makeLoopTarget(name:String, marker:String, z:Number, log:Array):Object {
        var t:Object = {};
        t._name = name; t._x = 100; t._y = 200;
        t.hp = 100; t._killed = false;
        t.Z轴坐标 = z;
        t.防止无限飞 = false;
        t.flags = 0;
        t.aabbCollider = {left: 80, right: 120, top: 180, bottom: 220};
        if (marker != undefined) t.目标标记 = marker;
        t.dispatcher = makeDispatcher(log);
        return t;
    }

    // 与 TargetCacheManager 排序缓存同构：data 按左边界升序 + 右边界前缀最大值
    private static function buildLoopCache(targets:Array):Object {
        var sorted:Array = targets.concat();
        sorted.sort(function(a:Object, b:Object):Number { return a.aabbCollider.left - b.aabbCollider.left; });
        var leftValues:Array = [];
        var rightMaxValues:Array = [];
        var maxR:Number = -1000000;
        for (var i:Number = 0; i < sorted.length; i++) {
            leftValues[i] = sorted[i].aabbCollider.left;
            if (sorted[i].aabbCollider.right > maxR) maxR = sorted[i].aabbCollider.right;
            rightMaxValues[i] = maxR;
        }
        return {data: sorted, leftValues: leftValues, rightMaxValues: rightMaxValues};
    }

    private static function makeLoopShooter(log:Array):Object {
        var s:Object = {};
        s._x = 0; s._y = 0; s._xscale = 100;
        s.dispatcher = makeDispatcher(log);
        return s;
    }

    // 类值显式 FQN 解析（as2-anti-hallucination §1）；saved.queue 携带本场景的新队列
    private static function installLoopEnv(cache:Object, shooter:Object):Object {
        var BQP:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var TCM:Object = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var saved:Object = {};
        saved.gameworld = _root.gameworld;
        saved.pause = _root.暂停;
        saved.debug = _root.调试模式;
        saved.timer = _root.帧计时器;
        saved.acqEnemy = TCM.acquireEnemyCache;
        saved.acqAll = TCM.acquireAllCache;
        saved.queues = BQP.activeQueues;
        saved.fakeUnits = BQP.fakeUnits;
        saved.uids = BQP.queueUIDs;
        _root.暂停 = false;
        _root.调试模式 = false;
        _root.帧计时器 = {当前帧数: 1, 毫秒每帧: 0.03};
        var gw:Object = {}; gw.turretA = shooter;
        _root.gameworld = gw;
        TCM.acquireEnemyCache = function(u, n):Object { return cache; };
        TCM.acquireAllCache = function(u, n):Object { return cache; };
        var q:BulletQueue = new BulletQueue();
        var aq:Object = {}; aq.filterTest = q;
        var fu:Object = {}; fu.filterTest = {};
        var uids:Object = {}; uids.filterTest = 7;
        BQP.activeQueues = aq;
        BQP.fakeUnits = fu;
        BQP.queueUIDs = uids;
        saved.queue = q;
        return saved;
    }

    private static function restoreLoopEnv(saved:Object):Void {
        if (saved == null) return;
        var BQP:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var TCM:Object = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        _root.gameworld = saved.gameworld;
        _root.暂停 = saved.pause;
        _root.调试模式 = saved.debug;
        _root.帧计时器 = saved.timer;
        TCM.acquireEnemyCache = saved.acqEnemy;
        TCM.acquireAllCache = saved.acqAll;
        BQP.activeQueues = saved.queues;
        BQP.fakeUnits = saved.fakeUnits;
        BQP.queueUIDs = saved.uids;
    }

    /**
     * 真实主命中循环（processQueue）下的逐弹过滤合同。
     * M1-M4 用 _raySettleProbe 记录到达 settleHit 的 selection；M5 撤探针实跑 settleHit，
     * DamageCalculator/EffectSystem 按合同打桩（同 RockQueenBattleSkillTest 对协作类的桩法），
     * 验证击杀事件仍经目标/发射者 dispatcher 这一现役权威。
     */
    private static function testMainLoopFilter():Void {
        var MARK:String = "cf6-a01-turret-zombie";
        var BQP:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var DC:Object = org.flashNight.arki.component.Damage.DamageCalculator;
        var ESY:Object = org.flashNight.arki.component.Effect.EffectSystem;
        var savedEnv:Object = null;
        var savedCalc:Function = null;
        var savedEffect:Function = null;
        try {
            // ---- M1：同地面行 + 标记匹配才结算；异行匹配目标被 Z 门拒，无标记目标被过滤拒 ----
            var logTM:Array = []; var logTU:Array = []; var logTO:Array = [];
            var targets:Array = [
                makeLoopTarget("TM", MARK, 202.4, logTM),
                makeLoopTarget("TU", undefined, 202.4, logTU),
                makeLoopTarget("TO", MARK, 300, logTO)
            ];
            savedEnv = installLoopEnv(buildLoopCache(targets), makeLoopShooter([]));
            var b:Object = makeLoopBullet(MARK);
            savedEnv.queue.add(b);
            _probeLog = [];
            BQP._raySettleProbe = function(t, m):Void { _probeLog.push(t._name); };
            BQP.processQueue();
            check(_probeLog.length == 1 && _probeLog[0] == "TM",
                "main loop: marked bullet settles only the same-row marked target");
            check(b.__vanish == 1 && logTU.length == 0 && logTO.length == 0,
                "main loop: probe-mode hit vanishes the bullet; filtered and off-row targets see zero side effects");
            restoreLoopEnv(savedEnv); savedEnv = null;

            // ---- M2：无标记 / 标记不匹配目标一律拒绝，拒绝先于一切副作用，子弹照常飞行 ----
            var logA:Array = []; var logB:Array = [];
            targets = [
                makeLoopTarget("TA", undefined, 202.4, logA),
                makeLoopTarget("TB", "other-enemy", 202.4, logB)
            ];
            savedEnv = installLoopEnv(buildLoopCache(targets), makeLoopShooter([]));
            b = makeLoopBullet(MARK);
            savedEnv.queue.add(b);
            _probeLog = [];
            BQP.processQueue();
            check(_probeLog.length == 0 && b.hitCount == 0 && b.hitTarget === undefined
                && b.命中对象 === undefined && logA.length == 0 && logB.length == 0,
                "main loop: unmarked/mismatched targets rejected before any settlement side effect");
            check(b.__vanish == 0 && b.__removed == 0 && b.__moves == 1,
                "main loop: rejected bullet is not terminated and still completes its movement");
            restoreLoopEnv(savedEnv); savedEnv = null;

            // ---- M3：普通无标记子弹不受过滤影响，照常命中带标记目标 ----
            var logM3:Array = [];
            targets = [makeLoopTarget("TM2", MARK, 202.4, logM3)];
            savedEnv = installLoopEnv(buildLoopCache(targets), makeLoopShooter([]));
            b = makeLoopBullet(undefined);
            savedEnv.queue.add(b);
            _probeLog = [];
            BQP.processQueue();
            check(_probeLog.length == 1 && _probeLog[0] == "TM2" && b.__vanish == 1,
                "main loop: unmarked bullet still settles a marked target (no reverse filtering)");
            restoreLoopEnv(savedEnv); savedEnv = null;

            // ---- M4：过滤开关断开时带标记子弹 fail-closed，标记匹配也拒绝 ----
            var logM4:Array = [];
            targets = [makeLoopTarget("TM3", MARK, 202.4, logM4)];
            savedEnv = installLoopEnv(buildLoopCache(targets), makeLoopShooter([]));
            b = makeLoopBullet(MARK);
            savedEnv.queue.add(b);
            _probeLog = [];
            BQP.targetFilterEnabled = false;
            BQP.processQueue();
            BQP.targetFilterEnabled = true;
            check(_probeLog.length == 0 && b.hitTarget === undefined && b.__vanish == 0 && logM4.length == 0,
                "main loop: disconnected filter fails closed even on an exact marker match");
            restoreLoopEnv(savedEnv); savedEnv = null;

            // ---- M5：撤探针实跑 settleHit；致命命中经现役 dispatcher 权威发布 hit/kill/enemyKilled ----
            var tmLog:Array = []; var txLog:Array = []; var shtLog:Array = [];
            var dmgLog:Array = []; var fxLog:Array = []; var dispLog:Array = [];
            var tm:Object = makeLoopTarget("TM", MARK, 202.4, tmLog);
            var tx:Object = makeLoopTarget("TX", "other-enemy", 202.4, txLog);
            targets = [tm, tx];
            savedEnv = installLoopEnv(buildLoopCache(targets), makeLoopShooter(shtLog));
            b = makeLoopBullet(MARK);
            savedEnv.queue.add(b);
            BQP._raySettleProbe = null;
            savedCalc = DC.calculateDamage;
            savedEffect = ESY.Effect;
            DC.calculateDamage = function(bullet:Object, sht:Object, hitTarget:Object, mult:Number, dodge:String):Object {
                dmgLog.push(hitTarget._name);
                hitTarget.hp = 0;        // 致命伤害归 DamageCalculator 权威，此处按合同打桩
                var dr:Object = {actualScatterUsed: 1, dodgeStatus: "未躲闪"};
                dr.triggerDisplay = function(x:Number, y:Number, n:String):Void { dispLog.push(n); };
                return dr;
            };
            ESY.Effect = function():Object { fxLog.push(String(arguments[0])); return null; };
            BQP.processQueue();
            DC.calculateDamage = savedCalc; savedCalc = null;
            ESY.Effect = savedEffect; savedEffect = null;
            check(dmgLog.length == 1 && dmgLog[0] == "TM" && b.hitCount == 1,
                "main loop: real damage settlement reaches exactly the matching target once");
            check(tmLog.join(",") == "hit,kill" && shtLog.join(",") == "enemyKilled",
                "main loop: kill and enemyKilled still publish through the live dispatcher authority");
            check(txLog.length == 0 && tx.hp == 100,
                "main loop: mismatched target untouched by real settlement");
            check(b.__vanish == 1 && fxLog.length == 1 && dispLog.length == 1,
                "main loop: lethal non-pierce hit vanishes the bullet after post-hit FX and display");
            restoreLoopEnv(savedEnv); savedEnv = null;
        } finally {
            if (savedCalc != null) DC.calculateDamage = savedCalc;
            if (savedEffect != null) ESY.Effect = savedEffect;
            restoreLoopEnv(savedEnv);
        }
    }

    public static function runAllTests():Void {
        // Object test doubles intentionally enter the existing API through its dynamic class value.
        var api:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        passed = 0; failed = 0;
        var savedProbe:Function = BulletQueueProcessor._raySettleProbe;
        var savedSwitch:Boolean = BulletQueueProcessor.targetFilterEnabled;
        var probeLog:Array;
        try {
            // ---- 拒绝路径：无探针实跑，必须零副作用 ----
            var tgtLog:Array; var shtLog:Array;
            var bullet:Object; var target:Object; var shooter:Object; var r:Object;

            tgtLog = []; shtLog = [];
            bullet = makeBullet("cf6-a01-turret-zombie");
            target = makeTarget(undefined, tgtLog);
            shooter = makeShooter(shtLog);
            r = api.injectHit(bullet, shooter, target, 11, 22, 1);
            check(r == null && bullet.hitCount == 0 && target.hp == 100 && target._killed == false
                && tgtLog.length == 0 && shtLog.length == 0,
                "marked bullet vs unmarked target rejected before damage/hitCount/events/death");

            tgtLog = []; shtLog = [];
            bullet = makeBullet("cf6-a01-turret-zombie");
            target = makeTarget("other-enemy", tgtLog);
            shooter = makeShooter(shtLog);
            r = api.injectHit(bullet, shooter, target, 11, 22, 1);
            check(r == null && bullet.hitCount == 0 && tgtLog.length == 0,
                "marked bullet vs mismatched marker rejected before any side effect");

            tgtLog = []; shtLog = [];
            BulletQueueProcessor.targetFilterEnabled = false;
            bullet = makeBullet("cf6-a01-turret-zombie");
            target = makeTarget("cf6-a01-turret-zombie", tgtLog);
            shooter = makeShooter(shtLog);
            r = api.injectHit(bullet, shooter, target, 11, 22, 1);
            check(r == null && bullet.hitCount == 0 && tgtLog.length == 0,
                "disconnected filter fails closed even on exact marker match");
            BulletQueueProcessor.targetFilterEnabled = true;

            // 合法性兜底优先于/独立于过滤：标记一致但目标已死仍拒绝。
            tgtLog = []; shtLog = [];
            bullet = makeBullet("cf6-a01-turret-zombie");
            target = makeTarget("cf6-a01-turret-zombie", tgtLog);
            target.hp = 0;
            shooter = makeShooter(shtLog);
            r = api.injectHit(bullet, shooter, target, 11, 22, 1);
            check(r == null && tgtLog.length == 0, "dead target with matching marker still rejected");

            // ---- 接受路径：探针短路 settleHit，只证明 selection 到达结算口 ----
            probeLog = [];
            BulletQueueProcessor._raySettleProbe = function(hitTarget:MovieClip, dmgMult:Number):Void {
                probeLog.push(hitTarget._name + "@" + dmgMult);
            };

            bullet = makeBullet("cf6-a01-turret-zombie");
            target = makeTarget("cf6-a01-turret-zombie", []);
            api.injectHit(bullet, makeShooter([]), target, 11, 22, 1);
            check(probeLog.length == 1 && probeLog[0] == "MockEnemy@1",
                "matching marker reaches settlement exactly once");

            probeLog = [];
            bullet = makeBullet(undefined);
            target = makeTarget(undefined, []);
            api.injectHit(bullet, makeShooter([]), target, 11, 22, 1);
            check(probeLog.length == 1, "unmarked bullet vs unmarked target unchanged (original path)");

            probeLog = [];
            bullet = makeBullet(undefined);
            target = makeTarget("cf6-a01-turret-zombie", []);
            api.injectHit(bullet, makeShooter([]), target, 11, 22, 1);
            check(probeLog.length == 1, "unmarked bullet still hits marked target (no reverse filtering)");

            // ---- 真实主命中循环夹具（r18）----
            testMainLoopFilter();
        } finally {
            BulletQueueProcessor._raySettleProbe = savedProbe;
            BulletQueueProcessor.targetFilterEnabled = savedSwitch;
        }
        trace("BulletTargetFilterTest Tests Passed: " + passed);
        trace("BulletTargetFilterTest Tests Failed: " + failed);
    }
}
