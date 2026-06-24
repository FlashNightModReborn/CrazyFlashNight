import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.component.Effect.*;

/**
 * RayPipelineEquivalenceTest —— 射线 batch vs greedy(deferral=B 持久化) 的【no-death 等价】Gate。
 *
 * 目的（用户提案）：在"敌人不死"前提下，逐帧贪心 greedy 的命中集应与旧批量 batch 一致。
 * 若不一致 = greedy 的 selection 算法与 batch 分叉（与 N/timing 无关 —— N 在 no-death 下只改时序）。
 * 预期：pierce/chain/含 pierce combo 等价；fork/no-pierce combo 走批量两侧恒等（sanity）；
 *       纯 pierce 持久路径还要保留批量路的尾段 VFX 元数据；
 *       N>1（每帧多命中）与 budget-tight（预算<目标数）下命中集/衰减仍恒等 batch（budget 按命中递减、N-无关）。
 *
 * 机制：
 *  - `BulletQueueProcessor._raySettleProbe` 探针在 settleHit（batch settleRayHit 与 greedy injectHit
 *    的唯一汇聚点）录 (target, dmgMult) 并短路 —— 纯比对 selection，不跑真伤/事件/几何依赖。
 *  - `BulletQueueProcessor._rayPersistent` 开关 A/B 同一场景跑 batch / greedy。
 *  - mock cache + scripted checkCollision（几何抽象成"目标在 tEntry 处碰撞/离束不碰撞"）；
 *    目标 hp 拉满不死；stub TargetCacheManager.acquireAllCache / RayVfxManager.spawn / EffectSystem.Effect。
 *    VFX stub 只记录 segmentKind/hitPoints 尾段摘要，不做视觉等价断言。
 *  - 经 Object 引用绕编译期 private 检查直调 BulletQueueProcessor 私有静态成员（AVM1 运行期不强制）。
 *
 * 除 batch/greedy 等价（runMode）外，本套件还含三类【非等价】确定性自检（各自硬断言 expected）：
 *  - runPausePreserveCase：暂停只冻结不清空/不销毁持久射线（rays=1 removed=0）。
 *  - runResetReclaimCase：过场 reset() removeMovieClip 每条持久射线再清空（removed=N rays=0）。
 *  - runDeathSkipCase：序列内死亡时 greedy 动态跳过暴毙目标、falloff 只按真实命中累乘（T0@1,T2@0.85）。
 * 任一断言失败 → _fail++ → 末尾发 `[TEST_FAIL]`（compile_test 直接判红，闭环可机判）。
 *
 * 【常驻套件 · 扩展方式】
 *  - 加场景：在 buildScenario(name) 加分支（on-beam=scripted 碰撞，tEntry 决定 pierce 序；
 *           off-beam=isColliding:false，仅 chain/fork 半径可达），在 runTests() 加 runMode(场景,模式,mask,budget)。
 *  - 加 lockon 反例（未来对齐 lockon-combo 用）：makeBullet 里设 b.lockonTarget=某目标（并给其 aabbCollider）。
 *  - ⚠ 陷阱：config 必须 new TeslaRayConfig()（普通 mock Object 会被 processRayBullets 的 TeslaRayConfig(x)
 *           cast 成 null → rayMode 退化 single）；目标 hp 拉满=no-death；stateFlags=4(FRIENDLY_FIRE) 跳
 *           FactionManager、伤害类型="真伤" 跳 DodgeHandler。详见施工 doc §8.5。
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.RayPipelineEquivalenceTest {

    // 当前录制的命中序列 [{name, mult}]
    private static var _rec:Array;
    // 当前录制的 VFX 摘要 [{kind, hitPoints, isHit, endX, endY}]
    private static var _vfx:Array;
    // 自门控计数：_fail>0 时末尾发 [TEST_FAIL]（compile_test 失败判据），让闭环编译可直接判绿/红
    private static var _fail:Number;
    private static var _checks:Number;

    public static function runTests():Void {
        trace("=== RayPipelineEquivalenceTest start ===");
        _fail = 0;
        _checks = 0;

        var BQP:Object = BulletQueueProcessor;
        var TCM:Object = TargetCacheManager;
        var RVM:Object = RayVfxManager;
        var ESY:Object = EffectSystem;

        // ---- 保存原值 ----
        var savedGW       = _root.gameworld;
        var savedDbg      = _root.调试模式;
        var savedPause    = _root.暂停;
        var savedAcqAll   = TCM.acquireAllCache;
        var savedAcqEnemy = TCM.acquireEnemyCache;
        var savedSpawn    = RVM.spawn;
        var savedEffect   = ESY.Effect;
        var savedPersist  = BQP._rayPersistent;
        var savedProbe    = BQP._raySettleProbe;

        // ---- 安装 stub ----
        _root.调试模式 = false;
        _root.gameworld = { S: { _x: 0, _y: 0, _xscale: 100 } };  // gameWorld[发射者名] = shooter
        RVM.spawn  = function(x1:Number, y1:Number, x2:Number, y2:Number, cfg:Object, meta:Object):Void {
            if (_vfx != null) {
                var hp:Number = (meta != null && meta.hitPoints != null) ? meta.hitPoints.length : 0;
                _vfx[_vfx.length] = {
                    kind: (meta == null ? "" : meta.segmentKind),
                    hitPoints: hp,
                    isHit: (meta != null && meta.isHit == true),
                    endX: Math.round(x2),
                    endY: Math.round(y2)
                };
            }
        };
        ESY.Effect = function() { return null; };
        BQP._raySettleProbe = function(t, m):Void {
            _rec[_rec.length] = { name: t._name, mult: Math.round(m * 1000) / 1000 };
        };

        // 各场景 × 各模式：no-death 下 greedy 应与 batch 命中同集（同 dmgMult、同序）
        runMode("cluster", "pierce",            1, 4);
        runMode("cluster", "chain",             2, 5);
        runMode("cluster", "fork",              4, 5);
        runMode("cluster", "chain,fork",        6, 5);
        runMode("cluster", "chain,fork,pierce", 7, 6);
        runMode("sparse",  "pierce",            1, 4);
        runMode("sparse",  "chain",             2, 5);
        runMode("sparse",  "fork",              4, 5);
        runMode("sparse",  "chain,fork",        6, 5);
        runMode("sparse",  "chain,fork,pierce", 7, 6);
        // ── N>1：no-death 下 N 只改帧分布、不改命中集（验 hitsPerFrame + 游标每帧多次 resume）。
        //    budget-per-hit 递减 + fork maxCount 同源（batch cfMaxCount=budget / greedy collectForkList=_rayBudget）
        //    → fork 采集时刻预算 N-无关 → 命中序与衰减恒等 batch。
        runMode("cluster", "chain,fork,pierce", 7, 6, 2);
        runMode("sparse",  "chain,fork,pierce", 7, 6, 3);
        runMode("cluster", "pierce",            1, 4, 2);
        // ── budget-tight：预算 < 可达目标 → 两侧须在同一处耗尽（验 budget 封顶 + fork maxCount 同源）──
        runMode("cluster", "chain,fork,pierce", 7, 3);
        runMode("cluster", "chain",             2, 2);
        runPausePreserveCase();
        runResetReclaimCase();
        runDeathSkipCase();

        // ---- 恢复 ----
        _root.gameworld       = savedGW;
        _root.调试模式        = savedDbg;
        _root.暂停            = savedPause;
        TCM.acquireAllCache   = savedAcqAll;
        TCM.acquireEnemyCache = savedAcqEnemy;
        RVM.spawn             = savedSpawn;
        ESY.Effect            = savedEffect;
        BQP._rayPersistent    = savedPersist;
        BQP._raySettleProbe   = savedProbe;

        if (_fail > 0) trace("[TEST_FAIL] RayPipelineEquivalenceTest: " + _fail + "/" + _checks + " checks FAILED");
        else trace("[RayEq] PASS: all " + _checks + " checks equal");
        trace("=== RayPipelineEquivalenceTest end ===");
    }

    // 目标布局：on-beam(scripted 碰撞，tEntry 决定 pierce 序) + off-beam(只能被 chain/fork 半径捞到)
    private static function buildScenario(name:String):Array {
        var arr:Array = [];
        if (name == "sparse") {
            // 稀疏：链会断 → 逼出 fork + 跨节点（cluster 场景未覆盖的 combo 路径）
            arr[arr.length] = makeTarget("T0", 100,    0, true,  100);  // 节点0
            arr[arr.length] = makeTarget("T3", 120,  100, false,   0);  // 近 T0（链弹1）
            arr[arr.length] = makeTarget("T4", 100, -150, false,   0);  // 近 T0、远 T3 → 链断后由 fork 捞
            arr[arr.length] = makeTarget("T1", 600,    0, true,  600);  // 孤立节点1（远超 chainRadius）
        } else {
            // cluster：紧密簇，combo 退化为从节点0 起的一条长链
            arr[arr.length] = makeTarget("T0", 100,   0, true,  100);
            arr[arr.length] = makeTarget("T3", 130,  90, false,   0);
            arr[arr.length] = makeTarget("T1", 200,   0, true,  200);
            arr[arr.length] = makeTarget("T4", 240, -90, false,   0);
            arr[arr.length] = makeTarget("T2", 300,   0, true,  300);
            arr[arr.length] = makeTarget("T5", 330,  80, false,   0);
        }
        return arr;
    }

    private static function makeTarget(name:String, cx:Number, cy:Number, onBeam:Boolean, tEntry:Number):Object {
        var aabb:Object = {};
        aabb.left = cx - 20; aabb.right = cx + 20;
        aabb.top  = cy - 20; aabb.bottom = cy + 20;
        // scripted checkCollision 结果（在束=碰撞，离束=不碰撞 → 只能 chain/fork 半径捞）
        aabb._coll = { isColliding: onBeam, tEntry: tEntry, overlapCenter: { x: cx, y: cy } };
        var t:Object = {};
        t._name = name;
        t.hp = 99999;          // no-death
        t.Z轴坐标 = 0;
        t.防止无限飞 = false;
        t.aabbCollider = aabb;
        return t;
    }

    // 由目标构造 cache（按 aabbCollider.left 升序 + rightMaxValues 前缀最大），与 acquireEnemyCache 同构
    private static function buildCache(targets:Array):Object {
        var sorted:Array = targets.concat();
        sorted.sort(function(a, b):Number { return a.aabbCollider.left - b.aabbCollider.left; });
        var leftValues:Array = [];
        var rightMaxValues:Array = [];
        var maxR:Number = -1000000;
        for (var i:Number = 0; i < sorted.length; i++) {
            leftValues[i] = sorted[i].aabbCollider.left;
            if (sorted[i].aabbCollider.right > maxR) maxR = sorted[i].aabbCollider.right;
            rightMaxValues[i] = maxR;
        }
        var cache:Object = {};
        cache.data = sorted;
        cache.leftValues = leftValues;
        cache.rightMaxValues = rightMaxValues;
        return cache;
    }

    // 必须返回【真】TeslaRayConfig 实例 —— processRayBullets 用 TeslaRayConfig(bullet.rayConfig)
    // 做类型转换，普通 Object 会被转成 null（导致 config=null→rayMode 退化 single）。
    private static function makeConfig(rayMode:String, mask:Number):TeslaRayConfig {
        var c:TeslaRayConfig = new TeslaRayConfig();
        c.rayMode = rayMode;
        c.rayModeMask = mask;        // isCombo()/hasPierce()/hasChain()/hasFork() 由它真实计算
        c.chainRadius = 200;
        c.damageFalloff = 0.85;
        c.rayLength = 1000;
        // 可选 N=每帧命中数（arguments[2]）：hitsPerFrame 非 TeslaRayConfig 声明字段，
        // 经无类型引用赋值（AVM1 运行期不强制 sealed）；不传=undefined → processPersistentRay N=1。
        var nPerFrame:Number = (arguments.length >= 3) ? Number(arguments[2]) : 1;
        if (nPerFrame > 1) { var cAny:Object = c; cAny.hitsPerFrame = nPerFrame; }
        return c;
    }

    private static function makeBullet(config:Object, budget:Number):Object {
        // 射线几何 mock（areaAABB 运行期实为 RayCollider；窗口设大覆盖所有目标）
        var ray:Object = {};
        ray.left = -2000; ray.right = 2000; ray.top = -2000; ray.bottom = 2000;
        ray.checkCollision = function(targetAABB:Object, zOff:Number):Object { return targetAABB._coll; };
        ray.setRayFast = function():Void {};

        var b:Object = {};
        b.发射者名 = "S";
        b.aabbCollider = ray;
        b.rayConfig = config;
        b.pierceLimit = budget;
        b.flags = 0;
        b.stateFlags = 4;          // STATE_FRIENDLY_FIRE → 走 acquireAllCache，跳过 FactionManager
        b._x = 0; b._y = 0; b._rotation = 0;
        b.Z轴坐标 = 0; b.Z轴攻击范围 = 50;
        b.伤害类型 = "真伤";        // settleRayHit 跳过 DodgeHandler
        b.命中率 = 100;
        b.击中地图效果 = "";
        b.击中后子弹的效果 = "";
        b.shouldGeneratePostHitEffect = true;
        b.lockonTarget = null;
        b.hitCount = 0;
        b.附加层伤害计算 = 0;
        b.击中时触发函数 = null;
        b.removeMovieClip = function():Void {};
        return b;
    }

    private static function runMode(scenario:String, rayMode:String, mask:Number, budget:Number):Void {
        var BQP:Object = BulletQueueProcessor;
        var TCM:Object = TargetCacheManager;
        var nPerFrame:Number = (arguments.length >= 5) ? Number(arguments[4]) : 1;

        var config:Object = makeConfig(rayMode, mask, nPerFrame);
        var targets:Array = buildScenario(scenario);   // no-death，batch/greedy 共用同一布局
        var cache:Object  = buildCache(targets);
        TCM.acquireAllCache   = function(u, n):Object { return cache; };  // 闭包捕获本 run 的 cache
        TCM.acquireEnemyCache = function(u, n):Object { return cache; };

        // ===== batch（_rayPersistent=false，单帧批量）=====
        BQP._rayPersistent = false;
        _rec = [];
        _vfx = [];
        BQP._rayBullets.push(makeBullet(config, budget));
        BQP.processRayBullets();
        var batchRec:Array = _rec;
        var batchVfx:Array = _vfx;

        // ===== greedy（_rayPersistent=true，逐帧贪心，跑足 budget+3 帧抽干）=====
        BQP._rayPersistent = true;
        _rec = [];
        _vfx = [];
        BQP._rayBullets.push(makeBullet(config, budget));
        for (var f:Number = 0; f < budget + 3; f++) BQP.processRayBullets();
        var greedyRec:Array = _rec;
        var greedyVfx:Array = _vfx;

        var label:String = scenario + ":" + rayMode + ":b" + budget + (nPerFrame > 1 ? (":N" + nPerFrame) : "");
        report(label, batchRec, greedyRec, batchVfx, greedyVfx);
    }

    private static function runPausePreserveCase():Void {
        var BQP:Object = BulletQueueProcessor;
        var savedQueues:Object = BQP.activeQueues;
        var savedPause = _root.暂停;
        var removed:Number = 0;
        var ray:Object = {};
        ray.removeMovieClip = function():Void { removed++; };

        BQP.activeQueues = {};
        BQP._rayBullets.length = 0;
        BQP._rayBullets.push(ray);
        _root.暂停 = true;
        BQP.processQueue();

        var pausePass:Boolean = (BQP._rayBullets.length == 1 && removed == 0);
        trace("-- pause:persistent-ray-state --");
        trace("  rays=" + BQP._rayBullets.length + " removed=" + removed + " (expect rays=1 removed=0)");
        _checks++;
        if (!pausePass) { _fail++; trace("  [TEST_FAIL] 暂停误清空/误销毁持久射线"); }

        BQP._rayBullets.length = 0;
        BQP.activeQueues = savedQueues;
        _root.暂停 = savedPause;
    }

    /**
     * reset() 回收持久射线 MC（pause-preserve 的对称面：过场必须 removeMovieClip 每条持久射线再清空，
     * 防 RayCollider 泄漏）。push 3 条带 removeMovieClip 计数的 mock ray → reset() → 期望 removed=3 / rays=0。
     */
    private static function runResetReclaimCase():Void {
        var BQP:Object = BulletQueueProcessor;
        var savedQueues:Object = BQP.activeQueues;
        var removed:Number = 0;
        BQP.activeQueues = {};
        BQP._rayBullets.length = 0;
        for (var i:Number = 0; i < 3; i++) {
            var r:Object = {};
            r.removeMovieClip = function():Void { removed++; };
            BQP._rayBullets.push(r);
        }
        BQP.reset();

        var pass:Boolean = (removed == 3 && BQP._rayBullets.length == 0);
        trace("-- reset:reclaim-persistent-rays --");
        trace("  removed=" + removed + " rays=" + BQP._rayBullets.length + " (expect removed=3 rays=0)");
        _checks++;
        if (!pass) { _fail++; trace("  [TEST_FAIL] reset 未回收持久射线 MC 或未清空"); }

        BQP._rayBullets.length = 0;
        BQP.activeQueues = savedQueues;
    }

    /**
     * 序列内死亡 → greedy 动态跳过（greedy 选 batch 而否决 batch-then-defer 的【立身之本】，此前 0 自动化覆盖）。
     * 场景：3 个 on-beam pierce 节点 T0(tEntry100)/T1(200)/T2(300)；probe 在 T0 命中后立刻杀死 T1（hp=0）。
     * 期望：greedy 每帧重扫 findAlongRay 的 hp>0 过滤跳过暴毙的 T1 → 命中序 = T0@1, T2@0.85
     *       （falloff 只按【真实命中】累乘：T1 未命中故不消耗衰减档，T2 = 1×0.85 而非 0.85²）。
     * 这是 greedy 独立正确性断言（非 batch 等价 —— 死亡正是两者按设计发散处）。
     */
    private static function runDeathSkipCase():Void {
        var BQP:Object = BulletQueueProcessor;
        var TCM:Object = TargetCacheManager;

        var targets:Array = [];
        targets[0] = makeTarget("T0", 100, 0, true, 100);
        targets[1] = makeTarget("T1", 200, 0, true, 200);
        targets[2] = makeTarget("T2", 300, 0, true, 300);
        var victim:Object = targets[1];
        var cache:Object = buildCache(targets);
        TCM.acquireAllCache   = function(u, n):Object { return cache; };
        TCM.acquireEnemyCache = function(u, n):Object { return cache; };

        var config:Object = makeConfig("pierce", 1);
        var savedProbe = BQP._raySettleProbe;
        _rec = [];
        _vfx = [];
        BQP._raySettleProbe = function(t, m):Void {
            _rec[_rec.length] = { name: t._name, mult: Math.round(m * 1000) / 1000 };
            if (t._name == "T0") victim.hp = 0;   // T0 命中即令 T1 暴毙（序列内死亡）
        };

        BQP._rayPersistent = true;
        BQP._rayBullets.length = 0;
        BQP._rayBullets.push(makeBullet(config, 4));
        for (var f:Number = 0; f < 7; f++) BQP.processRayBullets();
        BQP._raySettleProbe = savedProbe;

        var got:String = orderStr(_rec);
        var want:String = "T0:1,T2:0.85";
        var pass:Boolean = (got == want);
        trace("-- death:greedy-skips-mid-sequence-kill --");
        trace("  got=" + got + " (expect " + want + ")");
        _checks++;
        if (!pass) { _fail++; trace("  [TEST_FAIL] greedy 未正确跳过序列内暴毙目标 / falloff 计法错"); }

        BQP._rayBullets.length = 0;
    }

    private static function keyList(rec:Array):Array {
        var a:Array = [];
        for (var i:Number = 0; i < rec.length; i++) a[i] = rec[i].name + ":" + rec[i].mult;
        return a;
    }
    private static function orderStr(rec:Array):String { return keyList(rec).join(","); }
    private static function sortedStr(rec:Array):String {
        var a:Array = keyList(rec); a.sort(); return a.join(",");
    }

    private static function pierceTailStr(vfx:Array):String {
        var tail:Object = null;
        for (var i:Number = 0; i < vfx.length; i++) {
            if (vfx[i].kind == "pierce") tail = vfx[i];
        }
        if (tail == null) return "none";
        return "hitPoints=" + tail.hitPoints + ",end=" + tail.endX + "," + tail.endY + ",isHit=" + tail.isHit;
    }

    private static function report(mode:String, batchRec:Array, greedyRec:Array,
                                   batchVfx:Array, greedyVfx:Array):Void {
        var bSet:String = sortedStr(batchRec), gSet:String = sortedStr(greedyRec);
        var bOrd:String = orderStr(batchRec),  gOrd:String = orderStr(greedyRec);
        var setEq:Boolean = (bSet == gSet);
        var ordEq:Boolean = (bOrd == gOrd);
        _checks++;
        if (!setEq) _fail++;   // no-death 下 greedy SET 必须 == batch；不等=selection 分叉（真失败）
        trace("-- mode=" + mode + " --");
        trace("  batch  (" + batchRec.length + "): " + bOrd);
        trace("  greedy (" + greedyRec.length + "): " + gOrd);
        trace("  SET   " + (setEq ? "EQUAL" : "DIVERGE"));
        if (!setEq) {
            trace("    batch-set : " + bSet);
            trace("    greedy-set: " + gSet);
        }
        trace("  ORDER " + (ordEq ? "EQUAL" : (setEq ? "differ(timing-ok)" : "differ")));
        if (mode.indexOf(":pierce") >= 0 && mode.indexOf(",") < 0) {
            trace("  PIERCE-VFX batch=" + pierceTailStr(batchVfx) +
                  " greedy=" + pierceTailStr(greedyVfx));
        }
    }
}
