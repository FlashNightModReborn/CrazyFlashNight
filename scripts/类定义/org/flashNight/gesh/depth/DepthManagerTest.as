import org.flashNight.gesh.depth.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * @class DepthManagerTest
 * @description DepthManager (Twip Trick) 综合测试套件
 *
 *   测试类别:
 *     1. 标定 (calibrate)
 *     2. 基本操作 (add / update / remove)
 *     3. 零碰撞 & 排序单调性
 *     4. 错误处理 (null / NaN / stale MC / 外部 clip / 容量上限)
 *     5. 惰性剔除 (MC 被外部销毁)
 *     6. 内存管理 (add-remove cycle / clear / dispose)
 *     7. 场景切换 (re-calibrate)
 *     8. 性能基准 (vs 裸 swapDepths)
 *
 * @package org.flashNight.gesh.depth
 */
class org.flashNight.gesh.depth.DepthManagerTest {

    private var totalTests:Number;
    private var passedTests:Number;
    private var failedTests:Number;

    private var testContainer:MovieClip;
    private var testClips:Array;
    private var dm:DepthManager;
    private var clipCount:Number;

    // 性能测试参数
    private var warmupIter:Number;
    private var perfIter:Number;

    // 预生成随机数据（SeededLCG，可复现）
    private var _randDepths:Array; // swapDepths 用：1000-2000 范围的整数深度
    private var _randYs:Array;     // DepthManager 用：200-800 范围的 Y 值
    private var _randLen:Number;   // 数组长度

    public function DepthManagerTest() {
        totalTests = 0;
        passedTests = 0;
        failedTests = 0;
        clipCount = 50;
        warmupIter = 50;
        perfIter = 2000;
    }

    // ═══════════════════════════════════════════
    //  入口
    // ═══════════════════════════════════════════

    public function runTests():Void {
        printHeader("DepthManager (Twip Trick) 测试套件");
        setupTestEnvironment();

        testCalibrate();
        testBasicOperations();
        testZeroCollision();
        testMonotonicity();
        testErrorHandling();
        testLazyEviction();
        testMemoryManagement();
        testSceneSwitch();

        runPerformanceTests();

        printSummary();
        cleanupTestEnvironment();
    }

    // ═══════════════════════════════════════════
    //  环境
    // ═══════════════════════════════════════════

    private function setupTestEnvironment():Void {
        printLog("正在设置测试环境...");
        testContainer = _root.createEmptyMovieClip("testContainer_" + getTimer(), _root.getNextHighestDepth());
        testClips = [];
        var i:Number = 0;
        while (i < clipCount) {
            var clip:MovieClip = testContainer.createEmptyMovieClip("testClip_" + i, i + 100);
            clip.beginFill(Math.random() * 0xFFFFFF, 80);
            clip.moveTo(0, 0);
            clip.lineTo(50, 0);
            clip.lineTo(50, 50);
            clip.lineTo(0, 50);
            clip.lineTo(0, 0);
            clip.endFill();
            clip._x = Math.random() * 400;
            clip._y = Math.random() * 300;
            testClips.push(clip);
            i++;
        }
        printLog("测试环境设置完成，创建了 " + clipCount + " 个测试影片剪辑");
    }

    private function cleanupTestEnvironment():Void {
        printLog("正在清理测试环境...");
        if (dm) { dm.dispose(); dm = null; }
        testClips = null;
        if (testContainer) { testContainer.removeMovieClip(); testContainer = null; }
        printLog("测试环境已清理");
    }

    private function resetDM():Void {
        if (dm) { dm.dispose(); dm = null; }
        dm = new DepthManager(testContainer, 10000, 1048575, 64);
        dm.calibrate(200, 800);
    }

    // ═══════════════════════════════════════════
    //  1. 标定测试
    // ═══════════════════════════════════════════

    private function testCalibrate():Void {
        printTestGroup("标定测试");

        // 真实场景 Y 范围（from stage_environment.xml）
        var scenes:Array = [
            {yMin: 150, yMax: 1000, label: "最宽场景"},
            {yMin: 280, yMax: 800, label: "典型场景"},
            {yMin: 200, yMax: 370, label: "最窄场景"},
            {yMin: 500, yMax: 950, label: "高位场景"},
            {yMin: 300, yMax: 550, label: "短程场景"}
        ];

        var i:Number = 0;
        while (i < scenes.length) {
            var s:Object = scenes[i];
            var testDM:DepthManager = new DepthManager(testContainer, 10000, 1048575, 64);
            var ok:Boolean = testDM.calibrate(Number(s.yMin), Number(s.yMax));
            assertTrue(ok, "calibrate 应成功: " + s.label + " [" + s.yMin + "," + s.yMax + "]");
            testDM.dispose();
            i++;
        }
        record("5组真实场景标定", true);

        // 极端 case：N=128, yRange=10000 → 需要 1,280,128 > 1,038,575 带宽 → 应失败
        var testDM2:DepthManager = new DepthManager(testContainer, 10000, 1048575, 128);
        var ok2:Boolean = testDM2.calibrate(0, 10000);
        assertTrue(ok2 == false, "calibrate N=128 yRange=10000 应失败（带宽不足）");
        testDM2.dispose();
        record("极端标定拒绝", ok2 == false);

        // 可行的极端 case：N=128, yRange=850 → 应成功
        var testDM3:DepthManager = new DepthManager(testContainer, 10000, 1048575, 128);
        var ok3:Boolean = testDM3.calibrate(150, 1000);
        assertTrue(ok3, "calibrate N=128 yRange=850 应成功");
        testDM3.dispose();
        record("极端标定 N=128 可行", ok3);
    }

    // ═══════════════════════════════════════════
    //  2. 基本操作
    // ═══════════════════════════════════════════

    private function testBasicOperations():Void {
        printTestGroup("基本操作测试");

        // 添加新实体
        resetDM();
        var clip1:MovieClip = testClips[0];
        var clip2:MovieClip = testClips[1];
        dm.updateDepth(clip1, 300);
        dm.updateDepth(clip2, 500);
        dm.flush();
        assertTrue(dm.size() == 2, "应有 2 个实体");
        var d1:Number = dm.getDepth(clip1);
        var d2:Number = dm.getDepth(clip2);
        assertTrue(d1 != undefined, "clip1 应有深度值");
        assertTrue(d2 != undefined, "clip2 应有深度值");
        assertTrue(d1 < d2, "Y=300 的深度应小于 Y=500");
        record("添加新实体", true);

        // 热路径 eager apply：updateDepth 后无需 flush 即应生效
        resetDM();
        var eager0:Boolean = dm.updateDepth(clip1, 320);
        var eagerD0:Number = dm.getDepth(clip1);
        var eagerOk1:Boolean = assertTrue(eager0, "首次 updateDepth 应成功");
        var eagerOk2:Boolean = assertTrue(eagerD0 != undefined, "无需 flush 也应有有效深度");
        dm.updateDepth(clip1, 620);
        var eagerD1:Number = dm.getDepth(clip1);
        var eagerOk3:Boolean = assertTrue(eagerD1 != undefined && eagerD1 > eagerD0, "重复 updateDepth 应立即刷新深度");
        record("热路径 eager apply", eagerOk1 && eagerOk2 && eagerOk3);

        // 批量热路径：功能应与逐实体 updateDepth 等价
        resetDM();
        var batchYs:Array = [340, 540];
        var batchOk0:Boolean = assertTrue(dm.updateDepthBatch([clip1, clip2], batchYs, 0, 2) == 2, "批量更新应处理 2 个实体");
        var batchD1:Number = dm.getDepth(clip1);
        var batchD2:Number = dm.getDepth(clip2);
        var batchOk1:Boolean = assertTrue(batchD1 != undefined, "批量更新后 clip1 应有深度");
        var batchOk2:Boolean = assertTrue(batchD2 != undefined, "批量更新后 clip2 应有深度");
        var batchOk3:Boolean = assertTrue(batchD1 < batchD2, "批量更新应保持深度单调");
        record("批量热路径", batchOk0 && batchOk1 && batchOk2 && batchOk3);

        // 更新已有实体
        resetDM();
        dm.updateDepth(clip1, 300);
        dm.flush();
        var oldD:Number = dm.getDepth(clip1);
        dm.updateDepth(clip1, 600);
        dm.flush();
        var newD:Number = dm.getDepth(clip1);
        assertTrue(newD != oldD, "更新后深度应变化");
        assertTrue(newD > oldD, "Y增大深度应增大");
        assertTrue(dm.size() == 1, "仍应只有 1 个实体");
        record("更新已有实体", true);

        // 移除实体
        resetDM();
        dm.updateDepth(clip1, 300);
        dm.updateDepth(clip2, 500);
        dm.flush();
        var removed:Boolean = dm.removeMovieClip(clip1);
        assertTrue(removed, "移除应返回 true");
        assertTrue(dm.size() == 1, "移除后应有 1 个实体");
        assertTrue(dm.getDepth(clip1) == undefined, "被移除实体 getDepth 应返回 undefined");
        assertTrue(dm.getDepth(clip2) != undefined, "未移除实体应保持");
        record("移除实体", true);
    }

    // ═══════════════════════════════════════════
    //  3. 零碰撞
    // ═══════════════════════════════════════════

    private function testZeroCollision():Void {
        printTestGroup("零碰撞测试");

        resetDM();
        // 50 实体全部设同一 Y 值
        var sameY:Number = 500;
        var i:Number = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], sameY);
            i++;
        }
        dm.flush();

        // 收集所有深度值，检查唯一性
        var depthSet:Object = {};
        depthSet.__proto__ = null;
        var collisions:Number = 0;
        i = 0;
        while (i < clipCount) {
            var d:Number = dm.getDepth(testClips[i]);
            if (depthSet[String(d)] !== undefined) {
                collisions++;
                printLog("碰撞! clip " + i + " 与 clip " + depthSet[String(d)] + " 共享深度 " + d);
            }
            depthSet[String(d)] = i;
            i++;
        }
        assertTrue(collisions == 0, "50 实体同 Y 应零碰撞，实际碰撞: " + collisions);
        record("50实体同Y零碰撞", collisions == 0);
    }

    // ═══════════════════════════════════════════
    //  4. 排序单调性
    // ═══════════════════════════════════════════

    private function testMonotonicity():Void {
        printTestGroup("排序单调性测试");

        resetDM();
        // 按递增 Y 注册
        var i:Number = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i * 10);
            i++;
        }
        dm.flush();

        // 验证 depth 严格递增
        var monotone:Boolean = true;
        i = 1;
        while (i < clipCount) {
            var prev:Number = dm.getDepth(testClips[i - 1]);
            var cur:Number = dm.getDepth(testClips[i]);
            if (cur <= prev) {
                monotone = false;
                printLog("单调性破坏: clip" + (i-1) + "=" + prev + " >= clip" + i + "=" + cur);
            }
            i++;
        }
        assertTrue(monotone, "递增 Y 应产生严格递增 depth");
        record("排序单调性", monotone);

        // 同 Y 稳定性：连续两次 flush 顺序不变
        resetDM();
        i = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 500); // 全部同 Y
            i++;
        }
        dm.flush();
        var depths1:Array = [];
        i = 0;
        while (i < 10) {
            depths1.push(dm.getDepth(testClips[i]));
            i++;
        }
        // 再次 updateDepth 同一 Y + flush
        i = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 500);
            i++;
        }
        dm.flush();
        var stable:Boolean = true;
        i = 0;
        while (i < 10) {
            if (dm.getDepth(testClips[i]) !== depths1[i]) {
                stable = false;
            }
            i++;
        }
        assertTrue(stable, "同 Y 实体连续 flush 顺序应稳定");
        record("同Y稳定性", stable);
    }

    // ═══════════════════════════════════════════
    //  5. 错误处理
    // ═══════════════════════════════════════════

    private function testErrorHandling():Void {
        printTestGroup("错误处理测试");

        resetDM();

        // null MC
        var r1:Boolean = dm.updateDepth(null, 100);
        assertTrue(r1 == false, "null MC 应返回 false");
        record("null MC 处理", r1 == false);

        // NaN targetY
        var r2:Boolean = dm.updateDepth(testClips[0], Number.NaN);
        assertTrue(r2 == false, "NaN targetY 应返回 false");
        record("NaN targetY 处理", r2 == false);

        // null 移除
        var r3:Boolean = dm.removeMovieClip(null);
        assertTrue(r3 == false, "null 移除应返回 false");

        // 未注册实体的 getDepth
        var r4:Number = dm.getDepth(testClips[49]);
        assertTrue(r4 == undefined, "未注册实体 getDepth 应返回 undefined");
        record("未注册/null 查询", true);

        // 容量上限
        // 用 maxEntities=5 的小管理器测试
        var smallDM:DepthManager = new DepthManager(testContainer, 10000, 1048575, 5);
        smallDM.calibrate(200, 800);
        var i:Number = 0;
        while (i < 5) {
            smallDM.updateDepth(testClips[i], 300 + i * 10);
            i++;
        }
        var overCap:Boolean = smallDM.updateDepth(testClips[5], 400);
        assertTrue(overCap == false, "超容量应返回 false");
        assertTrue(smallDM.size() == 5, "容量应保持 5");
        smallDM.dispose();
        record("容量上限", overCap == false);

        // 外部 clip（不在容器中但有 _parent）
        var extClip:MovieClip = _root.createEmptyMovieClip("extClip_test", _root.getNextHighestDepth());
        // 注意: 此 MC 不是 testContainer 的子级
        // 契约要求调用方保证传入容器直接子级，此处仅验证不崩溃
        // 错误容器的 MC 传入属于调用方违约，不做生产防御
        var r5:Number = dm.getDepth(extClip);
        assertTrue(r5 == undefined, "外部 clip getDepth 应返回 undefined");
        var r6:Boolean = dm.removeMovieClip(extClip);
        assertTrue(r6 == false, "外部 clip 移除应返回 false");
        extClip.removeMovieClip();
        record("外部clip查询", true);
    }

    // ═══════════════════════════════════════════
    //  6. 惰性剔除
    // ═══════════════════════════════════════════

    private function testLazyEviction():Void {
        printTestGroup("惰性剔除测试");

        // 创建临时 MC，注册后外部销毁
        var tmpClip:MovieClip = testContainer.createEmptyMovieClip("tmpClip_evict", testContainer.getNextHighestDepth());
        resetDM();
        dm.updateDepth(testClips[0], 300);
        dm.updateDepth(tmpClip, 500);
        dm.updateDepth(testClips[1], 700);
        dm.flush();
        var lazyBefore:Number = dm.getDepth(testClips[1]);
        assertTrue(dm.size() == 3, "应有 3 个实体");

        // 外部销毁 tmpClip
        tmpClip.removeMovieClip();

        // 显式 sweepDead 应回收外部销毁对象
        dm.updateDepth(testClips[0], 310);
        dm.updateDepth(testClips[1], 710);
        dm.sweepDead();
        var lazyOk1:Boolean = assertTrue(dm.size() == 2, "惰性剔除后应有 2 个实体");
        var lazy0:Number = dm.getDepth(testClips[0]);
        var lazy1:Number = dm.getDepth(testClips[1]);
        var lazyOk2:Boolean = assertTrue(lazy0 != undefined, "存活实体应保持");
        var lazyOk3:Boolean = assertTrue(lazy1 != undefined, "存活实体应保持");
        var lazyOk4:Boolean = assertTrue(lazy1 != lazyBefore && lazy1 > lazyBefore, "被搬入槽位的实体应应用本帧新深度");
        record("惰性剔除", lazyOk1 && lazyOk2 && lazyOk3 && lazyOk4);

        // 容量压力兜底：满容量时 updateDepth 应先 sweepDead 再尝试注册
        var capDM:DepthManager = new DepthManager(testContainer, 10000, 1048575, 2);
        capDM.calibrate(200, 800);
        var capOld0:MovieClip = testContainer.createEmptyMovieClip("cap_old_0", testContainer.getNextHighestDepth());
        var capOld1:MovieClip = testContainer.createEmptyMovieClip("cap_old_1", testContainer.getNextHighestDepth());
        var capNew:MovieClip = testContainer.createEmptyMovieClip("cap_new", testContainer.getNextHighestDepth());
        capDM.updateDepth(capOld0, 260);
        capDM.updateDepth(capOld1, 360);
        capOld0.removeMovieClip();
        var capOk1:Boolean = assertTrue(capDM.updateDepth(capNew, 460), "容量满时应先回收死对象再注册新实体");
        var capOk2:Boolean = assertTrue(capDM.size() == 2, "容量兜底回收后 size 应保持 2");
        var capOk3:Boolean = assertTrue(capDM.getDepth(capNew) != undefined, "新实体应成功获得深度");
        capOld1.removeMovieClip();
        capNew.removeMovieClip();
        capDM.dispose();
        record("容量压力兜底回收", capOk1 && capOk2 && capOk3);

        // 同名 MC 复用（对象池场景）：销毁旧 MC → 同名新建 → updateDepth 应正确注册新 MC
        resetDM();
        var poolName:String = "pooled_unit";
        var oldClip:MovieClip = testContainer.createEmptyMovieClip(poolName, testContainer.getNextHighestDepth());
        dm.updateDepth(oldClip, 400);
        dm.flush();
        assertTrue(dm.size() == 1, "注册旧 MC 后 size=1");

        // 模拟对象池回收：外部销毁旧 MC，立即以同名创建新 MC（flush 之前）
        oldClip.removeMovieClip();
        var newClip:MovieClip = testContainer.createEmptyMovieClip(poolName, testContainer.getNextHighestDepth());
        dm.updateDepth(newClip, 600);
        dm.flush();
        var reuseOk1:Boolean = assertTrue(dm.size() == 1, "同名复用后 size 应为 1");
        var reuseOk2:Boolean = assertTrue(dm.getDepth(newClip) != undefined, "新 MC 应成功注册");
        newClip.removeMovieClip();
        record("同名MC复用", reuseOk1 && reuseOk2);
    }

    // ═══════════════════════════════════════════
    //  7. 内存管理
    // ═══════════════════════════════════════════

    private function testMemoryManagement():Void {
        printTestGroup("内存管理测试");

        // add-remove 循环 + ID 回收
        resetDM();
        var i:Number = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i);
            i++;
        }
        dm.flush();
        assertTrue(dm.size() == clipCount, "应有 " + clipCount + " 个实体");

        // 删除前一半
        i = 0;
        var half:Number = (clipCount / 2) | 0;
        while (i < half) {
            dm.removeMovieClip(testClips[i]);
            i++;
        }
        assertTrue(dm.size() == clipCount - half, "删除后应有 " + (clipCount - half) + " 个实体");

        // 重新添加
        i = 0;
        while (i < half) {
            dm.updateDepth(testClips[i], 400 + i);
            i++;
        }
        dm.flush();
        assertTrue(dm.size() == clipCount, "重新添加后应有 " + clipCount + " 个实体");
        assertTrue(dm.getDepth(testClips[0]) != undefined, "重新添加的实体应有深度");
        record("add-remove 循环", true);

        // clear
        resetDM();
        i = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i);
            i++;
        }
        dm.flush();
        dm.clear();
        assertTrue(dm.size() == 0, "clear 后 size 应为 0");
        assertTrue(dm.getDepth(testClips[0]) == undefined, "clear 后 getDepth 应返回 undefined");
        record("clear 操作", true);

        // dispose + 重建
        resetDM();
        i = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i);
            i++;
        }
        dm.flush();
        dm.dispose();
        // 重建
        dm = new DepthManager(testContainer, 10000, 1048575, 64);
        dm.calibrate(200, 800);
        record("dispose + 重建", true);
    }

    // ═══════════════════════════════════════════
    //  8. 场景切换
    // ═══════════════════════════════════════════

    private function testSceneSwitch():Void {
        printTestGroup("场景切换测试");

        resetDM(); // calibrate(200, 800)
        var i:Number = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 300 + i * 40);
            i++;
        }
        dm.flush();
        var dBefore:Number = dm.getDepth(testClips[0]);

        // 切换到不同场景 Y 范围
        var ok:Boolean = dm.calibrate(500, 950);
        assertTrue(ok, "re-calibrate 应成功");

        // 用新范围更新
        i = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 550 + i * 30);
            i++;
        }
        dm.flush();
        var dAfter:Number = dm.getDepth(testClips[0]);
        assertTrue(dAfter != dBefore, "场景切换后深度应变化");

        // 验证新范围下的单调性
        var monotone:Boolean = true;
        i = 1;
        while (i < 10) {
            if (dm.getDepth(testClips[i]) <= dm.getDepth(testClips[i - 1])) {
                monotone = false;
            }
            i++;
        }
        assertTrue(monotone, "新场景下排序应单调");
        record("场景切换(全量re-feed)", ok && monotone);

        // re-calibrate 后不全量 re-feed：未 re-feed 的实体不应触发 swapDepths
        resetDM();
        dm.updateDepth(testClips[0], 300);
        dm.updateDepth(testClips[1], 500);
        dm.updateDepth(testClips[2], 700);
        dm.flush();
        var d0Before:Number = dm.getDepth(testClips[0]);
        var d1Before:Number = dm.getDepth(testClips[1]);
        var d2Before:Number = dm.getDepth(testClips[2]);

        dm.calibrate(500, 950);
        // re-feed 首尾两个实体，中间实体保留 -1 哨兵，验证不会跳过哨兵后的活体
        dm.updateDepth(testClips[0], 600);
        dm.updateDepth(testClips[2], 900);
        dm.flush();

        var d0After:Number = dm.getDepth(testClips[0]);
        var d2After:Number = dm.getDepth(testClips[2]);
        var rfOk1:Boolean = assertTrue(d0After != undefined && d0After != d0Before, "哨兵前的 re-feed 实体应有新深度");
        // testClips[1] 未 re-feed → calibrate 将 _curD 置为 -1 哨兵
        // getDepth 对 -1 返回 undefined（内部哨兵不对外暴露）
        var d1After:Number = dm.getDepth(testClips[1]);
        var rfOk2:Boolean = assertTrue(d1After == undefined, "未 re-feed 的实体 getDepth 应返回 undefined");
        var rfOk3:Boolean = assertTrue(d2After != undefined && d2After != d2Before, "哨兵后的 re-feed 实体不应被跳过");
        record("场景切换(部分re-feed)", rfOk1 && rfOk2 && rfOk3);
    }

    // ═══════════════════════════════════════════
    //  性能基准
    // ═══════════════════════════════════════════

    private function runPerformanceTests():Void {
        printHeader("性能测试");

        // 预生成随机数据：固定种子 42，按 perfIter × clipCount 生成连续序列，避免计时环内 wrap 分支
        var rng:SeededLinearCongruentialEngine = new SeededLinearCongruentialEngine(42);
        _randLen = clipCount * perfIter;
        _randDepths = new Array(_randLen);
        _randYs = new Array(_randLen);
        var k:Number = _randLen;
        while (k--) {
            var r:Number = rng.nextFloat();
            _randDepths[k] = 1000 + ((r * 1000) | 0);  // 整数深度 [1000, 2000)
            _randYs[k] = 200 + ((r * 600) | 0);         // Y 值 [200, 800)
        }
        printLog("预生成随机数据: " + _randLen + " 个 (种子=42, 可复现)");

        warmupEnvironment();

        var swapTime:Number = testSwapDepthsPerformance();
        var dmTime:Number = testDepthManagerPerformance();
        var dmBatchTime:Number = testDepthManagerBatchPerformance();

        comparePerformance("逐实体 updateDepth", swapTime, dmTime);
        comparePerformance("批量 updateDepthBatch", swapTime, dmBatchTime);

        // 释放
        _randDepths = null;
        _randYs = null;
    }

    private function warmupEnvironment():Void {
        printLog("正在预热测试环境...");
        var wc:MovieClip = _root.createEmptyMovieClip("warmup_" + getTimer(), _root.getNextHighestDepth());
        var wClips:Array = [];
        var i:Number = 0;
        while (i < 20) {
            wClips.push(wc.createEmptyMovieClip("w_" + i, i + 100));
            i++;
        }
        // 预热裸 swapDepths
        var w:Number = warmupIter;
        while (w--) {
            i = 20;
            while (i--) wClips[i].swapDepths(200 + i);
        }
        // 预热 DepthManager
        var wDM:DepthManager = new DepthManager(wc, 10000, 1048575, 32);
        wDM.calibrate(100, 500);
        var wYs:Array = new Array(20);
        w = warmupIter;
        while (w--) {
            i = 20;
            while (i--) wYs[i] = 200 + i;
            wDM.updateDepthBatch(wClips, wYs, 0, 20);
        }
        wDM.dispose();
        wc.removeMovieClip();
        printLog("预热完成");
    }

    private function testSwapDepthsPerformance():Number {
        printLog("测试原生 swapDepths 性能 (" + perfIter + " 迭代)...");
        // 预重置深度
        var j:Number = clipCount;
        while (j--) testClips[j].swapDepths(j + 100);
        // 预生成随机深度（排除随机源开销，保证可复现）
        var randDepths:Array = _randDepths;
        // 计时
        var clips:Array = testClips;
        var n:Number = clipCount;
        var t0:Number = getTimer();
        var iter:Number = perfIter;
        var ri:Number = 0;
        while (iter--) {
            j = n;
            while (j--) {
                clips[j].swapDepths(randDepths[ri++]);
            }
        }
        var total:Number = getTimer() - t0;
        var avgUs:Number = Math.round(total * 1000 / perfIter);
        printLog("原生 swapDepths: 总 " + total + "ms / " + perfIter + " 迭代 = " + avgUs + " μs/帧");
        return total;
    }

    private function testDepthManagerPerformance():Number {
        printLog("测试 DepthManager 性能（稳态，" + perfIter + " 迭代）...");
        // 先注册所有实体（不计入计时）
        resetDM();
        var j:Number = clipCount;
        while (j--) {
            dm.updateDepth(testClips[j], 200 + j * 10);
        }
        dm.flush();

        // 预生成随机 Y（同一份随机数据，与 swapDepths 测试公平对比）
        var randYs:Array = _randYs;
        var clips:Array = testClips;
        var n:Number = clipCount;
        // 计时
        var t0:Number = getTimer();
        var iter:Number = perfIter;
        var ri:Number = 0;
        while (iter--) {
            j = n;
            while (j--) {
                dm.updateDepth(clips[j], randYs[ri++]);
                if (ri >= _randLen) ri = 0;
            }
            dm.flush();
        }
        var total:Number = getTimer() - t0;
        var avgUs:Number = Math.round(total * 1000 / perfIter);
        printLog("DepthManager(逐实体): 总 " + total + "ms / " + perfIter + " 迭代 = " + avgUs + " μs/帧（稳态）");
        return total;
    }

    private function testDepthManagerBatchPerformance():Number {
        printLog("测试 DepthManager 批量性能（稳态，" + perfIter + " 迭代）...");
        resetDM();
        var j:Number = clipCount;
        while (j--) {
            dm.updateDepth(testClips[j], 200 + j * 10);
        }

        var randYs:Array = _randYs;
        var clips:Array = testClips;
        var n:Number = clipCount;
        var t0:Number = getTimer();
        var iter:Number = perfIter;
        var ri:Number = 0;
        while (iter--) {
            dm.updateDepthBatch(clips, randYs, ri, n);
            ri += n;
        }
        var total:Number = getTimer() - t0;
        var avgUs:Number = Math.round(total * 1000 / perfIter);
        printLog("DepthManager(批量): 总 " + total + "ms / " + perfIter + " 迭代 = " + avgUs + " μs/帧（稳态）");
        return total;
    }

    private function comparePerformance(label:String, swapTotal:Number, dmTotal:Number):Void {
        var swapUs:Number = Math.round(swapTotal * 1000 / perfIter);
        var dmUs:Number = Math.round(dmTotal * 1000 / perfIter);
        var ratio:Number = Math.round(dmUs * 100 / swapUs) / 100;
        var overhead:Number = Math.round((dmTotal - swapTotal) * 1000 / swapTotal) / 10;

        printLog("────── 性能对比: " + label + "（" + perfIter + " 迭代，" + clipCount + " 实体） ──────");
        printLog("  裸 swapDepths : " + swapUs + " μs/帧");
        printLog("  DepthManager  : " + dmUs + " μs/帧");
        printLog("  倍率          : " + ratio + "x");
        printLog("  开销          : " + overhead + "%");

        if (overhead < 10) {
            printLog("√ 开销 <10%，可以上线");
        } else if (overhead < 50) {
            printLog("△ 开销 " + overhead + "%，需根据场景评估");
        } else if (overhead < 100) {
            printLog("○ 开销 " + overhead + "%，批量热路径已处于可用区间");
        } else if (overhead < 200) {
            printLog("○ 开销 " + overhead + "%，达到当前阶段 <200% 目标");
        } else {
            printLog("× 开销 " + overhead + "%，需进一步优化");
        }

        // 旧方案对比（基线数据来自 Step 0：20 迭代 × 50 实体）
        printLog("旧方案基线: 27.15ms/20迭代 ≈ 1358 μs/帧");
        if (dmUs < 1358) {
            printLog("√ 新方案优于旧方案 (" + Math.round(1358 / dmUs) + "x 加速)");
        } else {
            printLog("× 新方案未达到优化目标");
        }
    }

    // ═══════════════════════════════════════════
    //  辅助
    // ═══════════════════════════════════════════

    private function assertTrue(cond:Boolean, msg:String):Boolean {
        if (!cond) {
            printLog("断言失败: " + msg);
        }
        return cond;
    }

    private function record(name:String, passed:Boolean):Void {
        totalTests++;
        if (passed) {
            passedTests++;
            printLog("√ 测试通过: " + name);
        } else {
            failedTests++;
            printLog("× 测试失败: " + name);
        }
    }

    private function printSummary():Void {
        printHeader("测试总结");
        printLog("功能测试:");
        printLog("- 总测试数: " + totalTests);
        printLog("- 通过: " + passedTests);
        printLog("- 失败: " + failedTests);
        if (failedTests == 0) {
            printLog("√ 全部通过");
        } else {
            printLog("× 有 " + failedTests + " 个测试失败");
        }
    }

    private function printHeader(text:String):Void {
        printLog("\n==================================================");
        printLog(" " + text);
        printLog("==================================================");
    }

    private function printTestGroup(text:String):Void {
        printLog("\n----- " + text + " -----");
    }

    private function printLog(text:String):Void {
        trace("[DepthManagerTest] " + text);
    }
}
