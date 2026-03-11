import org.flashNight.arki.render.RayVfxManager;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;

/**
 * RayVfxManager 全面回归测试套件
 *
 * 覆盖范围：
 * 1. 配置辅助工具 (cfgNum, cfgArr, cfgIntensity)
 * 2. 段延迟策略 (chain, fork, pierce, 边界输入)
 * 3. 对象池 (pt, poolArr, pd, resetPools, 容量限制)
 * 4. 路径生成 (straightPath, generateSinePath)
 * 5. 生命周期 (spawn → update → 过期销毁)
 * 6. LOD 管理 (阈值升/降级)
 * 7. 延迟队列 (chainDelay 分帧推进)
 * 8. reset 全量清理
 * 9. API 便利性 (initWithContainer, getDelayedCount)
 */
class org.flashNight.arki.render.RayVfxManagerTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    // ════════════════════════════════════════════════════════════════════
    // 断言工具
    // ════════════════════════════════════════════════════════════════════

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) {
            testsPassed++;
            trace("[PASS] " + msg);
        } else {
            testsFailed++;
            trace("[FAIL] " + msg);
        }
    }

    private static function assertEq(expected:Number, actual:Number, msg:String):Void {
        testsRun++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff < 0.0001) {
            testsPassed++;
            trace("[PASS] " + msg);
        } else {
            testsFailed++;
            trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual);
        }
    }

    private static function assertTrue(cond:Boolean, msg:String):Void {
        assert(cond, msg);
    }

    // ════════════════════════════════════════════════════════════════════
    // 1. 配置辅助工具测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_cfgNum():Void {
        trace("--- cfgNum ---");
        // 正常读取
        assertEq(42, RayVfxManager.cfgNum({val: 42}, "val", 0), "cfgNum 正常读取");
        // 读取 0（不应被当作无效值）
        assertEq(0, RayVfxManager.cfgNum({val: 0}, "val", 99), "cfgNum 读取 0 不回退");
        // 负数
        assertEq(-5, RayVfxManager.cfgNum({val: -5}, "val", 0), "cfgNum 读取负数");
        // 字段不存在 → 默认值
        assertEq(10, RayVfxManager.cfgNum({other: 1}, "val", 10), "cfgNum 字段不存在");
        // config 为 null → 默认值
        assertEq(7, RayVfxManager.cfgNum(null, "val", 7), "cfgNum null config");
        // 字段为 undefined → 默认值（AS2: Number(undefined) = NaN, NaN != NaN... 但 AS2 中 NaN==NaN=true）
        // 实际 cfgNum 用 v == v 检查，AS2 中 NaN==NaN 为 true，所以 NaN 会通过
        // 但 config["missing"] 返回 undefined，Number(undefined) 在 AS2 中是 NaN
        // cfgNum 的 (v == v) 在 AS2 中对 NaN 返回 true（因为 AS2 NaN==NaN=true）
        // 所以 undefined 字段会返回 NaN 而不是默认值... 让我们验证实际行为
        assertEq(55, RayVfxManager.cfgNum({}, "missing", 55), "cfgNum 空对象字段缺失");
        // 字符串数值应被强转为 Number（外部系统可能传字符串）
        assertEq(42, RayVfxManager.cfgNum({val: "42"}, "val", 0), "cfgNum 字符串强转");
        assertEq(3.14, RayVfxManager.cfgNum({val: "3.14"}, "val", 0), "cfgNum 浮点字符串强转");
    }

    private static function test_cfgArr():Void {
        trace("--- cfgArr ---");
        var arr:Array = [1, 2, 3];
        var def:Array = [0];
        // 正常读取
        var r:Array = RayVfxManager.cfgArr({colors: arr}, "colors", def);
        assertTrue(r === arr, "cfgArr 正常读取返回原数组引用");
        // 空数组也是有效值
        var empty:Array = [];
        assertTrue(RayVfxManager.cfgArr({a: empty}, "a", def) === empty, "cfgArr 空数组不回退");
        // 字段不存在
        assertTrue(RayVfxManager.cfgArr({}, "colors", def) === def, "cfgArr 字段不存在");
        // config 为 null
        assertTrue(RayVfxManager.cfgArr(null, "colors", def) === def, "cfgArr null config");
    }

    private static function test_cfgIntensity():Void {
        trace("--- cfgIntensity ---");
        assertEq(0.5, RayVfxManager.cfgIntensity({intensity: 0.5}), "cfgIntensity 正常值");
        assertEq(0, RayVfxManager.cfgIntensity({intensity: 0}), "cfgIntensity 零值不回退");
        assertEq(1.0, RayVfxManager.cfgIntensity(null), "cfgIntensity null meta");
        assertEq(1.0, RayVfxManager.cfgIntensity({}), "cfgIntensity 字段不存在");
    }

    // ════════════════════════════════════════════════════════════════════
    // 2. 段延迟策略测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_chainDelay():Void {
        trace("--- chainDelay ---");
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 2;

        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 0}),
            "chain hitIndex=0 不延迟");
        assertEq(2, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 1}),
            "chain hitIndex=1 延迟=2");
        assertEq(6, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 3}),
            "chain hitIndex=3 延迟=6");
    }

    private static function test_forkDelay():Void {
        trace("--- forkDelay ---");
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 3;

        assertEq(1, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "fork", hitIndex: 0}),
            "fork hitIndex=0 延迟 1 帧");
        assertEq(1, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "fork", hitIndex: 5}),
            "fork hitIndex=5 延迟 1 帧");
    }

    private static function test_disableDelay():Void {
        trace("--- disableDelay ---");
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;

        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 2}),
            "chainDelay=0 chain 不延迟");
        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "fork", hitIndex: 0}),
            "chainDelay=0 fork 不延迟");
        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "pierce", hitIndex: 0}),
            "pierce 不延迟");
    }

    private static function test_delayEdgeCases():Void {
        trace("--- delay edge cases ---");
        // null meta
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 5;
        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, null), "null meta 不延迟");
        // null config (cfgNum 对 null 返回默认值 0)
        assertEq(0, RayVfxManager.computeSegmentDelay(null, {segmentKind: "chain", hitIndex: 2}),
            "null config 不延迟");
        // main 类型不延迟
        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "main", hitIndex: 0}),
            "main 不延迟");
        // 负 chainDelay 视为禁用
        cfg.chainDelay = -1;
        assertEq(0, RayVfxManager.computeSegmentDelay(cfg, {segmentKind: "chain", hitIndex: 3}),
            "负 chainDelay 不延迟");
    }

    // ════════════════════════════════════════════════════════════════════
    // 3. 对象池测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_ptPool():Void {
        trace("--- pt pool ---");
        RayVfxManager.resetPools();

        var p1:Object = RayVfxManager.pt(10, 20, 0.5);
        assertEq(10, p1.x, "pt.x 赋值正确");
        assertEq(20, p1.y, "pt.y 赋值正确");
        assertEq(0.5, p1.t, "pt.t 赋值正确");

        // 重置后复用同一个对象
        RayVfxManager.resetPools();
        var p2:Object = RayVfxManager.pt(30, 40, 0.9);
        assertTrue(p1 === p2, "pt 池复用同一对象引用");
        assertEq(30, p2.x, "pt 复用后 x 更新");
        assertEq(40, p2.y, "pt 复用后 y 更新");
    }

    private static function test_arrPool():Void {
        trace("--- arr pool ---");
        RayVfxManager.resetPools();

        var a1:Array = RayVfxManager.poolArr();
        assertTrue(a1 != null, "poolArr 返回非 null");
        assertEq(0, a1.length, "poolArr 返回空数组");

        a1.push(1);
        a1.push(2);
        assertEq(2, a1.length, "push 后长度正确");

        // 重置后复用，长度应清零
        RayVfxManager.resetPools();
        var a2:Array = RayVfxManager.poolArr();
        assertTrue(a1 === a2, "poolArr 池复用同一数组引用");
        assertEq(0, a2.length, "poolArr 复用后长度清零");
    }

    private static function test_pdPool():Void {
        trace("--- pd pool ---");
        RayVfxManager.resetPools();

        var path:Array = [1, 2, 3];
        var d1:Object = RayVfxManager.pd(path, true, false);
        assertTrue(d1.path === path, "pd.path 引用正确");
        assertTrue(d1.isMain === true, "pd.isMain 正确");
        assertTrue(d1.isFork === false, "pd.isFork 正确");

        // 重置后复用
        RayVfxManager.resetPools();
        var path2:Array = [4, 5];
        var d2:Object = RayVfxManager.pd(path2, false, true);
        assertTrue(d1 === d2, "pd 池复用同一对象引用");
        assertTrue(d2.path === path2, "pd 复用后 path 更新");
    }

    private static function test_poolMultipleAllocations():Void {
        trace("--- pool multiple allocations ---");
        RayVfxManager.resetPools();

        // 分配多个不同对象
        var p1:Object = RayVfxManager.pt(1, 1, 0);
        var p2:Object = RayVfxManager.pt(2, 2, 0);
        assertTrue(p1 !== p2, "连续 pt 分配返回不同对象");
        assertEq(1, p1.x, "第一个 pt 保持独立");
        assertEq(2, p2.x, "第二个 pt 保持独立");

        var a1:Array = RayVfxManager.poolArr();
        var a2:Array = RayVfxManager.poolArr();
        assertTrue(a1 !== a2, "连续 poolArr 分配返回不同数组");
    }

    // ════════════════════════════════════════════════════════════════════
    // 4. 路径生成测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_straightPath():Void {
        trace("--- straightPath ---");
        RayVfxManager.resetPools();

        var path:Array = RayVfxManager.straightPath(0, 0, 100, 200);
        assertEq(2, path.length, "straightPath 生成 2 个点");
        assertEq(0, path[0].x, "起点 x");
        assertEq(0, path[0].y, "起点 y");
        assertEq(0.0, path[0].t, "起点 t=0");
        assertEq(100, path[1].x, "终点 x");
        assertEq(200, path[1].y, "终点 y");
        assertEq(1.0, path[1].t, "终点 t=1");
    }

    private static function test_generateSinePath():Void {
        trace("--- generateSinePath ---");
        RayVfxManager.resetPools();

        var arc:Object = {startX: 0, startY: 0, endX: 200, endY: 0};
        var dist:Number = 200;

        // perpX=0, perpY=1: 波动方向为 Y 轴
        var path:Array = RayVfxManager.generateSinePath(
            arc, 0, 1, dist,
            20,   // waveAmp
            50,   // waveLen
            0.1,  // waveSpeed
            0,    // age
            0,    // phaseOffset
            24,   // ptsPerWave
            250,  // maxSegments
            0     // noiseRatio
        );

        // 基本属性验证
        assertTrue(path.length >= 12, "generateSinePath 至少 12 个点, 实际=" + path.length);

        // 起点精确匹配
        assertEq(0, path[0].x, "sinePath 起点 x");
        assertEq(0, path[0].y, "sinePath 起点 y");
        assertEq(0.0, path[0].t, "sinePath 起点 t=0");

        // 终点精确匹配
        var last:Object = path[path.length - 1];
        assertEq(200, last.x, "sinePath 终点 x");
        assertEq(0, last.y, "sinePath 终点 y");
        assertEq(1.0, last.t, "sinePath 终点 t=1");

        // t 值单调递增
        var monotonic:Boolean = true;
        for (var i:Number = 1; i < path.length; i++) {
            if (path[i].t <= path[i - 1].t) {
                monotonic = false;
                break;
            }
        }
        assertTrue(monotonic, "sinePath t 值严格单调递增");

        // x 值大致单调递增（沿射线方向, perpX=0 所以 x 应完全单调）
        var xMono:Boolean = true;
        for (var j:Number = 1; j < path.length; j++) {
            if (path[j].x < path[j - 1].x - 0.01) {
                xMono = false;
                break;
            }
        }
        assertTrue(xMono, "sinePath x 沿射线方向单调");

        // 中间点应有 Y 偏移（波动效果）
        var hasYOffset:Boolean = false;
        for (var k:Number = 1; k < path.length - 1; k++) {
            var yOff:Number = path[k].y;
            if (yOff > 0.1 || yOff < -0.1) {
                hasYOffset = true;
                break;
            }
        }
        assertTrue(hasYOffset, "sinePath 中间点有 Y 偏移");
    }

    private static function test_generateSinePath_noise():Void {
        trace("--- generateSinePath noise ---");
        RayVfxManager.resetPools();

        var arc:Object = {startX: 0, startY: 0, endX: 100, endY: 0};

        // 只变 noiseRatio（其他参数完全相同），隔离噪声分支
        var pathClean:Array = RayVfxManager.generateSinePath(
            arc, 0, 1, 100, 15, 30, 0.1, 5, 0, 24, 250, 0);

        // 在 resetPools 前捕获 clean 中点（池化对象会被后续调用覆盖）
        var cleanLen:Number = pathClean.length;
        var midIdx:Number = (cleanLen / 2) | 0;
        var midCleanY:Number = pathClean[midIdx].y;

        assertEq(0, pathClean[0].x, "clean 起点 x");

        RayVfxManager.resetPools();
        var pathNoisy:Array = RayVfxManager.generateSinePath(
            arc, 0, 1, 100, 15, 30, 0.1, 5, 0, 24, 250, 0.3);

        assertEq(0, pathNoisy[0].x, "noisy 起点 x");

        // 相同采样参数 → 相同点数
        assertEq(cleanLen, pathNoisy.length, "noise 不改变点数");

        // 噪声叠加应导致中点 Y 值不同
        var midNoisyY:Number = pathNoisy[midIdx].y;
        var yDiff:Number = midCleanY - midNoisyY;
        if (yDiff < 0) yDiff = -yDiff;
        assertTrue(yDiff > 0.01,
            "noise 改变中点 Y: clean=" + midCleanY + " noisy=" + midNoisyY + " diff=" + yDiff);
    }

    private static function test_generateSinePath_shortRay():Void {
        trace("--- generateSinePath short ray ---");
        RayVfxManager.resetPools();

        // 极短射线（dist < waveLen）
        var arc:Object = {startX: 0, startY: 0, endX: 3, endY: 0};
        var path:Array = RayVfxManager.generateSinePath(
            arc, 0, 1, 3, 10, 50, 0.1, 0, 0, 24, 250, 0);

        assertTrue(path.length >= 2, "短射线至少 2 个点");
        assertEq(0, path[0].x, "短射线起点 x");
        assertEq(3, path[path.length - 1].x, "短射线终点 x");
    }

    // ════════════════════════════════════════════════════════════════════
    // 5. 生命周期测试（需 MovieClip 容器）
    // ════════════════════════════════════════════════════════════════════

    private static function test_lifecycle():Void {
        trace("--- lifecycle ---");
        // 使用 _root 作为容器
        RayVfxManager.initWithContainer(_root);
        assertEq(0, RayVfxManager.getActiveCount(), "初始活跃数=0");
        assertEq(0, RayVfxManager.getDelayedCount(), "初始延迟数=0");

        // spawn 一条无延迟的射线
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;
        cfg.visualDuration = 3;
        cfg.fadeOutDuration = 2;
        cfg.vfxStyle = "tesla";

        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        assertEq(1, RayVfxManager.getActiveCount(), "spawn 后活跃数=1");

        // 连续 update 直到过期
        var totalFrames:Number = 3 + 2 + 1; // visual + fade + 1
        for (var i:Number = 0; i < totalFrames; i++) {
            RayVfxManager.update();
        }
        assertEq(0, RayVfxManager.getActiveCount(), "过期后活跃数=0");

        RayVfxManager.reset();
    }

    private static function test_multipleArcs():Void {
        trace("--- multiple arcs ---");
        RayVfxManager.initWithContainer(_root);

        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;
        cfg.visualDuration = 2;
        cfg.fadeOutDuration = 1;
        cfg.vfxStyle = "tesla";

        // spawn 3 条射线
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        RayVfxManager.spawn(0, 0, 200, 0, cfg, null);
        RayVfxManager.spawn(0, 0, 300, 0, cfg, null);
        assertEq(3, RayVfxManager.getActiveCount(), "3 条射线活跃");

        // 全部过期
        for (var i:Number = 0; i < 5; i++) {
            RayVfxManager.update();
        }
        assertEq(0, RayVfxManager.getActiveCount(), "全部过期后活跃数=0");

        RayVfxManager.reset();
    }

    private static function test_fadeAlpha():Void {
        trace("--- fade alpha ---");
        RayVfxManager.initWithContainer(_root);

        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;
        cfg.visualDuration = 1;
        cfg.fadeOutDuration = 4;
        cfg.vfxStyle = "prism"; // 非 flicker 风格

        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);

        // frame 1: age=1, still in visual phase
        RayVfxManager.update();
        assertEq(1, RayVfxManager.getActiveCount(), "visual phase 活跃");

        // frame 2: age=2, fade phase starts, fadeProgress = 1/4 = 0.25, alpha = 75
        RayVfxManager.update();
        assertEq(1, RayVfxManager.getActiveCount(), "fade phase 仍活跃");

        // frame 3-5: 继续 fade
        RayVfxManager.update();
        RayVfxManager.update();
        RayVfxManager.update();

        // frame 6: age=6 > totalDuration(5), 应该被销毁
        RayVfxManager.update();
        assertEq(0, RayVfxManager.getActiveCount(), "fade 结束后销毁");

        RayVfxManager.reset();
    }

    // ════════════════════════════════════════════════════════════════════
    // 6. LOD 管理测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_LOD():Void {
        trace("--- LOD ---");
        RayVfxManager.initWithContainer(_root);

        assertEq(0, RayVfxManager.getCurrentLOD(), "初始 LOD=0");

        // 大量 spawn 触发 LOD 升级
        // spectrum cost=2.5, 需要 >=8 才到 LOD 1 → 4 条 spectrum
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;
        cfg.visualDuration = 10;
        cfg.fadeOutDuration = 2;
        cfg.vfxStyle = "spectrum";

        for (var i:Number = 0; i < 4; i++) {
            RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        }
        RayVfxManager.update();
        // 4 * 2.5 = 10 >= 8 → LOD 1
        assertTrue(RayVfxManager.getCurrentLOD() >= 1,
            "4 条 spectrum LOD>=1, cost=" + RayVfxManager.getRenderCost());

        // 继续 spawn 到 LOD 2（需 >=25）
        // 再加 6 条: (4+6) * 2.5 = 25 → LOD 2
        for (var j:Number = 0; j < 6; j++) {
            RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        }
        RayVfxManager.update();
        assertEq(2, RayVfxManager.getCurrentLOD(),
            "10 条 spectrum LOD=2, cost=" + RayVfxManager.getRenderCost());

        RayVfxManager.reset();

        // reset 后 LOD 归零
        assertEq(0, RayVfxManager.getCurrentLOD(), "reset 后 LOD=0");
    }

    // ════════════════════════════════════════════════════════════════════
    // 7. 延迟队列测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_delayedQueue():Void {
        trace("--- delayed queue ---");
        RayVfxManager.initWithContainer(_root);

        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 3;
        cfg.visualDuration = 5;
        cfg.fadeOutDuration = 2;
        cfg.vfxStyle = "tesla";

        // spawn chain hitIndex=2 → delay = 3*2 = 6 帧
        var meta:Object = {segmentKind: "chain", hitIndex: 2, intensity: 1.0, isHit: true};
        RayVfxManager.spawn(0, 0, 100, 0, cfg, meta);
        assertEq(0, RayVfxManager.getActiveCount(), "延迟段不立即活跃");
        assertEq(1, RayVfxManager.getDelayedCount(), "延迟队列有 1 条");

        // 经过 5 帧，还在延迟中
        for (var i:Number = 0; i < 5; i++) {
            RayVfxManager.update();
        }
        assertEq(0, RayVfxManager.getActiveCount(), "5 帧后仍在延迟");
        assertEq(1, RayVfxManager.getDelayedCount(), "延迟队列仍有 1 条");

        // 第 6 帧，延迟到期，转为活跃
        RayVfxManager.update();
        assertEq(1, RayVfxManager.getActiveCount(), "6 帧后转为活跃");
        assertEq(0, RayVfxManager.getDelayedCount(), "延迟队列清空");

        RayVfxManager.reset();
    }

    private static function test_forkDelayedQueue():Void {
        trace("--- fork delayed queue ---");
        RayVfxManager.initWithContainer(_root);

        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 5;
        cfg.visualDuration = 3;
        cfg.fadeOutDuration = 1;
        cfg.vfxStyle = "tesla";

        // fork 始终延迟 1 帧
        var meta:Object = {segmentKind: "fork", hitIndex: 0, intensity: 1.0, isHit: true};
        RayVfxManager.spawn(0, 0, 100, 0, cfg, meta);
        assertEq(0, RayVfxManager.getActiveCount(), "fork 延迟不立即活跃");

        RayVfxManager.update();
        assertEq(1, RayVfxManager.getActiveCount(), "fork 1 帧后活跃");

        RayVfxManager.reset();
    }

    // ════════════════════════════════════════════════════════════════════
    // 8. reset 测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_reset():Void {
        trace("--- reset ---");
        RayVfxManager.initWithContainer(_root);

        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 2;
        cfg.visualDuration = 10;
        cfg.fadeOutDuration = 5;
        cfg.vfxStyle = "tesla";

        // 活跃 + 延迟
        RayVfxManager.spawn(0, 0, 100, 0, cfg, null);
        RayVfxManager.spawn(0, 0, 200, 0, cfg, {segmentKind: "chain", hitIndex: 3, intensity: 1.0, isHit: true});

        assertTrue(RayVfxManager.getActiveCount() > 0 || RayVfxManager.getDelayedCount() > 0,
            "reset 前有活跃或延迟");

        RayVfxManager.reset();
        assertEq(0, RayVfxManager.getActiveCount(), "reset 后活跃数=0");
        assertEq(0, RayVfxManager.getDelayedCount(), "reset 后延迟数=0");
        assertEq(0, RayVfxManager.getCurrentLOD(), "reset 后 LOD=0");
        assertEq(0, RayVfxManager.getRenderCost(), "reset 后 renderCost=0");
    }

    // ════════════════════════════════════════════════════════════════════
    // 9. initWithContainer 测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_initWithContainer():Void {
        trace("--- initWithContainer ---");
        // 创建专用测试容器
        var testMc:MovieClip = _root.createEmptyMovieClip("testVfxContainer", _root.getNextHighestDepth());

        RayVfxManager.initWithContainer(testMc);
        assertEq(0, RayVfxManager.getActiveCount(), "initWithContainer 后活跃数=0");

        // spawn 应该工作
        var cfg:TeslaRayConfig = new TeslaRayConfig();
        cfg.chainDelay = 0;
        cfg.visualDuration = 2;
        cfg.fadeOutDuration = 1;
        cfg.vfxStyle = "prism";

        RayVfxManager.spawn(50, 50, 150, 150, cfg, null);
        assertEq(1, RayVfxManager.getActiveCount(), "initWithContainer 后 spawn 正常");

        // 重复 initWithContainer 应 reset 旧状态
        RayVfxManager.initWithContainer(testMc);
        assertEq(0, RayVfxManager.getActiveCount(), "重复 initWithContainer 清理旧状态");

        RayVfxManager.reset();
        testMc.removeMovieClip();
    }

    // ════════════════════════════════════════════════════════════════════
    // 10. drawPath / drawCircle 鲁棒性测试
    // ════════════════════════════════════════════════════════════════════

    private static function test_drawPathEdgeCases():Void {
        trace("--- drawPath edge cases ---");
        var mc:MovieClip = _root.createEmptyMovieClip("testDraw", _root.getNextHighestDepth());

        // 空路径不崩溃
        RayVfxManager.drawPath(mc, [], 0xFF0000, 2, 100);
        assertTrue(true, "drawPath 空路径不崩溃");

        // 单点路径不崩溃
        RayVfxManager.drawPath(mc, [{x: 0, y: 0}], 0xFF0000, 2, 100);
        assertTrue(true, "drawPath 单点不崩溃");

        // 正常 2 点路径
        RayVfxManager.drawPath(mc, [{x: 0, y: 0}, {x: 100, y: 100}], 0xFF0000, 2, 100);
        assertTrue(true, "drawPath 2 点正常");

        mc.removeMovieClip();
    }

    private static function test_drawCircleEdgeCases():Void {
        trace("--- drawCircle edge cases ---");
        var mc:MovieClip = _root.createEmptyMovieClip("testCircle", _root.getNextHighestDepth());

        // 零半径不绘制
        RayVfxManager.drawCircle(mc, 50, 50, 0, 0xFFFFFF, 100);
        assertTrue(true, "drawCircle 零半径不崩溃");

        // 负半径不绘制
        RayVfxManager.drawCircle(mc, 50, 50, -10, 0xFFFFFF, 100);
        assertTrue(true, "drawCircle 负半径不崩溃");

        // 零 alpha 不绘制
        RayVfxManager.drawCircle(mc, 50, 50, 20, 0xFFFFFF, 0);
        assertTrue(true, "drawCircle 零 alpha 不崩溃");

        // 正常绘制
        RayVfxManager.drawCircle(mc, 50, 50, 20, 0xFFFFFF, 80);
        assertTrue(true, "drawCircle 正常绘制不崩溃");

        mc.removeMovieClip();
    }

    // ════════════════════════════════════════════════════════════════════
    // 11. 性能基准（可选，记录时间但不判定 PASS/FAIL）
    // ════════════════════════════════════════════════════════════════════

    private static function bench_generateSinePath():Void {
        trace("--- bench generateSinePath ---");
        var arc:Object = {startX: 0, startY: 0, endX: 500, endY: 300};
        var dist:Number = Math.sqrt(500 * 500 + 300 * 300);
        var iterations:Number = 100;

        var t0:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            RayVfxManager.resetPools();
            RayVfxManager.generateSinePath(
                arc, -0.5145, 0.8575, dist,
                20, 50, 0.15, i, 0, 24, 250, 0);
        }
        var elapsed:Number = getTimer() - t0;
        trace("  generateSinePath x" + iterations + " = " + elapsed + "ms ("
            + (elapsed / iterations) + "ms/call)");
    }

    private static function bench_poolOperations():Void {
        trace("--- bench pool ops ---");
        var iterations:Number = 1000;

        var t0:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            RayVfxManager.resetPools();
            for (var j:Number = 0; j < 100; j++) {
                RayVfxManager.pt(j, j, j * 0.01);
            }
        }
        var elapsed:Number = getTimer() - t0;
        trace("  pt x" + (iterations * 100) + " = " + elapsed + "ms");
    }

    // ════════════════════════════════════════════════════════════════════
    // 入口
    // ════════════════════════════════════════════════════════════════════

    public static function runAllTests():Void {
        testsRun = 0;
        testsPassed = 0;
        testsFailed = 0;

        trace("===== RayVfxManagerTest 开始 =====");

        // 1. 配置辅助工具
        test_cfgNum();
        test_cfgArr();
        test_cfgIntensity();

        // 2. 段延迟策略
        test_chainDelay();
        test_forkDelay();
        test_disableDelay();
        test_delayEdgeCases();

        // 3. 对象池
        test_ptPool();
        test_arrPool();
        test_pdPool();
        test_poolMultipleAllocations();

        // 4. 路径生成
        test_straightPath();
        test_generateSinePath();
        test_generateSinePath_noise();
        test_generateSinePath_shortRay();

        // 5. 生命周期
        test_lifecycle();
        test_multipleArcs();
        test_fadeAlpha();

        // 6. LOD 管理
        test_LOD();

        // 7. 延迟队列
        test_delayedQueue();
        test_forkDelayedQueue();

        // 8. reset
        test_reset();

        // 9. initWithContainer
        test_initWithContainer();

        // 10. drawPath/drawCircle 鲁棒性
        test_drawPathEdgeCases();
        test_drawCircleEdgeCases();

        // 11. 性能基准
        bench_generateSinePath();
        bench_poolOperations();

        trace("===== RayVfxManagerTest 结束: run=" + testsRun
            + ", pass=" + testsPassed + ", fail=" + testsFailed + " =====");
        if (testsFailed > 0) {
            trace("!!! " + testsFailed + " 个测试失败 !!!");
        }
    }

    public static function main():Void {
        runAllTests();
    }
}
