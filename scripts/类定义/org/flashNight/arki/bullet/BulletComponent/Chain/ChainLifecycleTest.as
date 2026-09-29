import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.render.ChainVisualBridge;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/**
 * 真实 CS6 生命周期 focused：三种模式从出生到销毁逐 tick 对照。
 *   A = 旧 AS2 直接模拟 + 真实 MC 单元体（非 native，渲染写每个子剪辑）；
 *   B = 原生显示但直接计算（nativeGroupOwned，强制 aggregate=false，无懒历史）；
 *   C = 生产选路（nativeGroupOwned，aggregate 由纵向联弹组装按出生预期
 *       单元数决定：≤64 直算、>64 聚合；大组聚合另由 ChainAggregateTest 回归）。
 * 相同种子/RNG/补弹/运动/霰弹调整/销毁时序下比较每 tick 碰撞盒、存活顺序
 * （出生序逐单元坐标抽查于稀疏检查点物化比对）、补弹计数与 RNG；
 * 计时轮与 oracle 分离，多轮交替次序、先两轮预热。原生 C# 图像成本
 * 不在 AS2 计时内：wire 只计量 flush 字符串字节与其生成耗时。
 * 武器参数来自真实加特林数据（溯源见 tmp/ray-closeout-0929/chain-report.md）：
 *   M134 / XM214-CageFrame 峰值 / M134暴力版PIG / XM556-Preview+磁稳贯穿弹
 *   （均 ≤12 单元，生产应选直算）；big64 为合成 64 单元聚合回归锚点。
 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ChainLifecycleTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var seed:Number;
    private static var randomCalls:Number;
    private static var createdClips:Number;
    private static var clipId:Number;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] ChainLifecycleTest: " + name); }
    }

    private static function randomOffset(span:Number):Number {
        seed = (seed * 1664525 + 1013904223) | 0;
        var unsigned:Number = seed < 0 ? seed + 4294967296 : seed;
        randomCalls++;
        return (unsigned / 4294967296 * 2 - 1) * span;
    }

    private static function acquireClip(type:String):MovieClip {
        createdClips++;
        var zone:MovieClip = _root.gameworld.子弹区域;
        return zone.createEmptyMovieClip("lcUnit" + (++clipId), zone.getNextHighestDepth());
    }

    private static function releaseClip(clip:MovieClip):Void { clip.removeMovieClip(); }

    private static function capabilities(capacity:Number):Object {
        return {version:1, mode:"native", maxUnits:15360,
            styles:[{gunChainUnitLinkage:"单元体-普通子弹"}, {gunChainUnitLinkage:"单元体-加强普通子弹"},
                {gunChainUnitLinkage:null}, {gunChainUnitLinkage:null}, {gunChainUnitLinkage:null},
                {gunChainUnitLinkage:"单元体-穿刺子弹"}, {gunChainUnitLinkage:"单元体-次级穿刺子弹"},
                {gunChainUnitLinkage:"单元体-无壳穿刺子弹"}],
            gunChainPrefixes:["横向联弹", "横向机枪联弹", "横向手枪联弹",
                "纵向联弹", "纵向机枪联弹", "纵向手枪联弹"]};
    }

    /** 真实武器参数（data/items/武器_长枪_压制机枪.xml + 改装合成公式）。 */
    private static function weaponTable():Array {
        return [
            // M134：split5 diffusion7 interval150 velocity50 bullet 纵向机枪联弹-加强普通子弹
            {key:"M134", prefix:"纵向机枪联弹", bullet:"纵向机枪联弹-加强普通子弹",
                count:5, spread:7, speed:50, intervalMs:150},
            // XM214-CageFrame 峰值：XML split1 diffusion7 interval15 velocity50，
            // 生命周期 XM214初始化 置 长枪属性.interval=150（weaponAttributeValue），
            // 射击事件 prop.霰弹值 由 5 逐发爬升至 maxShotgunVal=12。
            {key:"XM214peak", prefix:"纵向机枪联弹", bullet:"纵向机枪联弹-加强普通子弹",
                count:12, spread:7, speed:50, intervalMs:150},
            // M134暴力版PIG：split6 diffusion8 velocity65 interval180 bullet 纵向机枪联弹-穿刺子弹
            {key:"M134pig", prefix:"纵向机枪联弹", bullet:"纵向机枪联弹-穿刺子弹",
                count:6, spread:8, speed:65, intervalMs:180},
            // XM556-Preview + 磁稳贯穿弹：interval (235*1.8)-50=373ms（先百分比后flat），
            // bullet merge 保前缀 → 纵向机枪联弹-次级穿刺子弹；split5 diffusion8 velocity35。
            {key:"XM556mod", prefix:"纵向机枪联弹", bullet:"纵向机枪联弹-次级穿刺子弹",
                count:5, spread:8, speed:35, intervalMs:373},
            // 合成聚合回归锚点：>12 单元时生产选路保留 aggregate=true，
            // 证明大组聚合经组装选路后仍逐 tick 精确（B 强制直算作对照）。
            {key:"big64", prefix:"纵向机枪联弹", bullet:"纵向机枪联弹-加强普通子弹",
                count:64, spread:8, speed:50, intervalMs:150}
        ];
    }

    /**
     * 生命周期场景（ticks/killTick 含销毁帧；dropTick 将霰弹值压到当前 count
     * 使补弹提前结束，raiseTick 回升触发补弹重开；overReserve 越过出生预留
     * 检验原生预留增长——三路仍维持相同逻辑，B/C 不创建回退 MC）。
     */
    private static function scenarios(weapon:Object):Array {
        var fillD:Number = Math.ceil(weapon.intervalMs / EnhancedCooldownWheel.I().每帧毫秒);
        var early:Number = fillD > 4 ? fillD - 2 : 2;
        return [
            {key:"cutInFill", groups:1, stagger:0, ticks:early + 1, killTick:early},
            {key:"justFilled", groups:1, stagger:0, ticks:fillD + 3, killTick:fillD + 2},
            {key:"longFlight", groups:1, stagger:0, ticks:96, killTick:95},
            {key:"burst", groups:8, stagger:1, ticks:64, killTick:63},
            {key:"refill", groups:1, stagger:0, ticks:fillD + 18, killTick:fillD + 17,
                dropTick:3, raiseTick:fillD + 5, raiseBy:1},
            {key:"overReserve", groups:1, stagger:0, ticks:fillD + 8, killTick:fillD + 7,
                raiseTick:fillD + 2, raiseBy:3}
        ];
    }

    /** mode 0=A 旧路径(真实MC)，1=B 原生显示强制直算，2=C 生产选路（组装决定 aggregate）。 */
    private static function makeChain(weapon:Object, mode:Number):ChainGroup {
        var b:Object = {子弹种类:weapon.bullet, baseAsset:weapon.prefix,
            霰弹值:weapon.count, 子弹散射度:weapon.spread, xmov:weapon.speed, ymov:0,
            _x:0, _y:-100, _rotation:0, _xscale:100, _yscale:100,
            _alpha:100, _visible:true, Z轴坐标:1000000,
            发射间隔毫秒:weapon.intervalMs};
        var group:ChainGroup = new ChainGroup(null, b,
            _root.联弹系统.纵向联弹更新, _root.联弹系统.渲染组);
        group.isObject = true;
        group.盒x = 7;
        group.盒y = -5;
        group.盒宽 = 10;
        group.盒高 = 10;
        group.盒固有半宽 = 12.5;
        group.盒固有半高 = 12.5;
        if (mode > 0) {
            ChainVisualBridge.reserveGroup(group);
            if (mode == 1) group.aggregate = false;
        }
        _root.联弹系统.纵向联弹组装(group);
        return group;
    }

    /**
     * 每 tick 对照：碰撞盒/补弹计数/存活数/霰弹值/锚点。
     * deep=true 时物化 C 懒历史后逐单元比对 x/y/rot（出生序=存活序）。
     * 检查点稀疏安排使 C 内部单元在两个检查点间保持≥2步欠账，
     * 强制走 materializeUnit 补算路径而非只验证快径。
     */
    private static function compareChains(a:ChainGroup, b:ChainGroup, c:ChainGroup,
                                          label:String, deep:Boolean):Void {
        check(a.盒x === b.盒x && a.盒x === c.盒x
            && a.盒y === b.盒y && a.盒y === c.盒y
            && a.盒宽 === b.盒宽 && a.盒宽 === c.盒宽
            && a.盒高 === b.盒高 && a.盒高 === c.盒高, label + " box");
        check(a.count === b.count && a.count === c.count, label + " fillCount");
        check(a.单元体列表.length === b.单元体列表.length
            && a.单元体列表.length === c.单元体列表.length, label + " aliveOrder");
        check(a.bullet.霰弹值 === b.bullet.霰弹值
            && a.bullet.霰弹值 === c.bullet.霰弹值, label + " shotgun");
        check(a.bullet._x === b.bullet._x && a.bullet._x === c.bullet._x
            && a.bullet._y === b.bullet._y && a.bullet._y === c.bullet._y, label + " anchor");
        if (!deep) return;
        var same:Boolean = true;
        var la:Array = a.单元体列表;
        var lb:Array = b.单元体列表;
        var lc:Array = c.单元体列表;
        var n:Number = la.length;
        for (var i:Number = 0; i < n; i++) {
            var ua:ChainUnitData = la[i];
            var ub:ChainUnitData = lb[i];
            var uc:ChainUnitData = lc[i];
            if (c.aggregate) ChainUnitManager.materializeUnit(c, uc);
            if (ua.x !== ub.x || ua.x !== uc.x || ua.y !== ub.y || ua.y !== uc.y
                || ua.rot !== ub.rot || ua.rot !== uc.rot) same = false;
        }
        check(same, label + " exactUnits");
    }

    private static function killIfAlive(g:ChainGroup):Void {
        if (g.__removed) return;
        g.bullet.__chainDead = true;
        ChainUnitManager.removeGroup(g);
    }

    private static function runCorrectness(weapon:Object, scenario:Object):Void {
        ChainVisualBridge.configure(capabilities(4096));
        var G:Number = scenario.groups;
        var groups:Array = [];
        var birthCalls:Number = -1;
        var m:Number, k:Number, t:Number;
        for (m = 0; m < 3; m++) {
            for (k = 0; k < G; k++) {
                seed = 19471 + k * 97;
                randomCalls = 0;
                var g:ChainGroup = makeChain(weapon, m);
                // 生产选路断言：出生一次决定，不随霰弹调整/补弹重开中途切换。
                check(g.nativeGroupOwned === (m > 0),
                    weapon.key + " " + scenario.key + " native owner m" + m + " g" + k);
                check(g.aggregate === (m == 2 && weapon.count > 64),
                    weapon.key + " " + scenario.key + " path selection m" + m
                    + " g" + k + " (aggregate=" + g.aggregate + ")");
                if (birthCalls < 0) birthCalls = randomCalls;
                check(randomCalls === birthCalls,
                    weapon.key + " " + scenario.key + " birth RNG m" + m + " g" + k);
                groups[m * G + k] = g;
            }
        }
        for (t = 0; t < scenario.ticks; t++) {
            for (k = 0; k < G; k++) {
                if (k * scenario.stagger > t) continue;
                var ga:ChainGroup = groups[k];
                var gb:ChainGroup = groups[G + k];
                var gc:ChainGroup = groups[2 * G + k];
                if (ga.__removed) continue;
                if (t == scenario.dropTick) {
                    var svNow:Number = ga.count;
                    ga.bullet.霰弹值 = svNow;
                    gb.bullet.霰弹值 = svNow;
                    gc.bullet.霰弹值 = svNow;
                }
                if (t == scenario.raiseTick) {
                    ga.bullet.霰弹值 += scenario.raiseBy;
                    gb.bullet.霰弹值 += scenario.raiseBy;
                    gc.bullet.霰弹值 += scenario.raiseBy;
                }
                ga.bullet._x += ga.bullet.xmov;
                gb.bullet._x += gb.bullet.xmov;
                gc.bullet._x += gc.bullet.xmov;
                var expSeed:Number = -1;
                var expCalls:Number = -1;
                for (m = 0; m < 3; m++) {
                    var grp:ChainGroup = groups[m * G + k];
                    seed = 1103 + t * 17 + k * 31;
                    randomCalls = 0;
                    var upd:Function = grp.update;
                    upd(grp);
                    if (expCalls < 0) { expCalls = randomCalls; expSeed = seed; }
                    check(randomCalls === expCalls && seed === expSeed,
                        weapon.key + " " + scenario.key + " t" + t + " g" + k + " RNG");
                }
                compareChains(ga, gb, gc,
                    weapon.key + " " + scenario.key + " t" + t + " g" + k,
                    (t % 6 == 0) || t == scenario.ticks - 1);
                if (t == scenario.killTick) {
                    killIfAlive(ga);
                    killIfAlive(gb);
                    killIfAlive(gc);
                }
            }
            ChainVisualBridge.flush();
        }
        for (m = 0; m < 3; m++) {
            for (k = 0; k < G; k++) {
                var rg:ChainGroup = groups[m * G + k];
                if (!rg.__removed) ChainUnitManager.removeGroup(rg);
            }
        }
        ChainVisualBridge.disconnect();
    }

    private static function newStats():Object {
        return {rounds:0, updMs:0, fillMs:0, flushMs:0, wireB:0,
            clips:0, adds:0, visits:0, fillTicks:0, liveTicks:0, roundTimes:[]};
    }

    /** 单轮整场景计时：updMs 只含 update()；flush 与 wire 单列；不计 oracle/trace。 */
    private static function runTimingRound(weapon:Object, scenario:Object,
                                           mode:Number, st:Object):Void {
        var G:Number = scenario.groups;
        var gs:Array = [];
        var clipsBefore:Number = createdClips;
        var addsBefore:Number = ChainUnitManager.aggregateAddOperations;
        var k:Number, t:Number;
        for (k = 0; k < G; k++) {
            seed = 19471 + k * 97;
            gs[k] = makeChain(weapon, mode);
        }
        var updMs:Number = 0, fillMs:Number = 0, flushMs:Number = 0, wireB:Number = 0;
        var fillTicks:Number = 0, liveTicks:Number = 0;
        var roundStart:Number = getTimer();
        for (t = 0; t < scenario.ticks; t++) {
            var s0:Number = getTimer();
            var filling:Boolean = false;
            var active:Number = 0;
            for (k = 0; k < G; k++) {
                var g:ChainGroup = gs[k];
                if (g.__removed || k * scenario.stagger > t) continue;
                if (t == scenario.dropTick) g.bullet.霰弹值 = g.count;
                if (t == scenario.raiseTick) g.bullet.霰弹值 += scenario.raiseBy;
                g.bullet._x += g.bullet.xmov;
                if (g.count < g.bullet.霰弹值) { filling = true; fillTicks++; }
                seed = 1103 + t * 17 + k * 31;
                var upd:Function = g.update;
                upd(g);
                active++;
            }
            var dt:Number = getTimer() - s0;
            updMs += dt;
            liveTicks += active;
            if (filling) fillMs += dt;
            if (mode > 0) {
                s0 = getTimer();
                var p:String = ChainVisualBridge.flush();
                flushMs += getTimer() - s0;
                if (p != null) wireB += length(p);
            }
            if (t == scenario.killTick) {
                for (k = 0; k < G; k++) killIfAlive(gs[k]);
            }
        }
        var roundMs:Number = getTimer() - roundStart;
        var visits:Number = 0;
        for (k = 0; k < G; k++) {
            visits += gs[k].aggregateVisits;
            if (!gs[k].__removed) ChainUnitManager.removeGroup(gs[k]);
        }
        if (st == null) return;
        st.rounds++;
        st.updMs += updMs;
        st.fillMs += fillMs;
        st.flushMs += flushMs;
        st.wireB += wireB;
        st.clips += createdClips - clipsBefore;
        st.adds += ChainUnitManager.aggregateAddOperations - addsBefore;
        st.visits += visits;
        st.fillTicks += fillTicks;
        st.liveTicks += liveTicks;
        st.roundTimes.push(roundMs);
    }

    private static function p95(times:Array):Number {
        var n:Number = times.length;
        if (n == 0) return 0;
        var sorted:Array = times.slice();
        sorted.sort(function(a:Number, b:Number):Number { return a - b; });
        var idx:Number = Math.ceil(n * 0.95) - 1;
        if (idx < 0) idx = 0;
        if (idx >= n) idx = n - 1;
        return sorted[idx];
    }

    /**
     * 每场景：先 2 轮旋转次序预热（丢弃统计），再 R 轮交替 A/B/C 次序计时。
     * 结构化成本行：模式/武器/场景、总 update ms、整轮 P95、补弹 tick 占比
     * （时间%|tick数/活跃tick数）、创建 MC、wire 字节与 flush ms、聚合访问与标量加法。
     */
    private static function timeAll(weapon:Object, scenario:Object):Void {
        ChainVisualBridge.configure(capabilities(4096));
        var R:Number = 18;
        var order:Array = [0, 1, 2];
        var stats:Array = [newStats(), newStats(), newStats()];
        var w:Number, s:Number;
        for (w = 0; w < 2; w++) {
            for (s = 0; s < 3; s++) {
                runTimingRound(weapon, scenario, order[(w + s) % 3], null);
            }
        }
        for (var r:Number = 0; r < R; r++) {
            for (s = 0; s < 3; s++) {
                var mode:Number = order[(r + s) % 3];
                runTimingRound(weapon, scenario, mode, stats[mode]);
            }
        }
        var modeNames:Array = ["A", "B", "C"];
        for (s = 0; s < 3; s++) {
            var st:Object = stats[s];
            var fillPct:Number = st.updMs > 0 ? st.fillMs * 100 / st.updMs : 0;
            trace("[LIFECYCLE_COST] w=" + weapon.key + " s=" + scenario.key
                + " m=" + modeNames[s] + " updMs=" + st.updMs
                + " roundP95=" + p95(st.roundTimes)
                + " fillPct=" + (Math.round(fillPct * 10) / 10)
                + " fillTks=" + st.fillTicks + "/" + st.liveTicks
                + " mc=" + st.clips + " wireB=" + st.wireB
                + " flushMs=" + st.flushMs
                + " visits=" + st.visits + " adds=" + st.adds);
        }
        ChainVisualBridge.disconnect();
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0; createdClips = 0; clipId = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var oldTimer:Object = _root.帧计时器;
        var oldRandom:Function = _root.随机偏移;
        var manager:Object = ChainUnitManager;
        var oldAcquire:Function = manager.acquireUnit;
        var oldRelease:Function = manager.releaseUnit;
        var world:MovieClip = _root.createEmptyMovieClip("chainLifecycleTestWorld", 76546);
        world.createEmptyMovieClip("子弹区域", 1);
        _root.gameworld = world;
        _root.帧计时器 = {当前帧数:1};
        _root.随机偏移 = randomOffset;
        manager.acquireUnit = acquireClip;
        manager.releaseUnit = releaseClip;

        var ws:Array = weaponTable();
        var caseCount:Number = 0;
        for (var wi:Number = 0; wi < ws.length; wi++) {
            var ss:Array = scenarios(ws[wi]);
            for (var si:Number = 0; si < ss.length; si++) {
                runCorrectness(ws[wi], ss[si]);
                caseCount++;
            }
        }
        for (wi = 0; wi < ws.length; wi++) {
            ss = scenarios(ws[wi]);
            for (si = 0; si < ss.length; si++) {
                timeAll(ws[wi], ss[si]);
            }
        }
        trace("[LIFECYCLE_MATRIX] weapons=" + ws.length + " scenarios=6 modes=3 cases=" + caseCount);
        trace("[LIFECYCLE_TIMING] rounds=18 warmup=2 order=rotated");

        ChainVisualBridge.disconnect();
        manager.acquireUnit = oldAcquire;
        manager.releaseUnit = oldRelease;
        _root.随机偏移 = oldRandom;
        _root.帧计时器 = oldTimer;
        _root.gameworld = oldWorld;
        world.removeMovieClip();
        trace("ChainLifecycleTest Tests Passed: " + passed);
        trace("ChainLifecycleTest Tests Failed: " + failed);
    }
}
