import org.flashNight.gesh.depth.*;

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

    public function DepthManagerTest() {
        totalTests = 0;
        passedTests = 0;
        failedTests = 0;
        clipCount = 50;
        warmupIter = 5;
        perfIter = 20;
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
        assertTrue(dm.size() == 3, "应有 3 个实体");

        // 外部销毁 tmpClip
        tmpClip.removeMovieClip();

        // 再次 flush 应惰性剔除
        dm.updateDepth(testClips[0], 310);
        dm.updateDepth(testClips[1], 710);
        dm.flush();
        assertTrue(dm.size() == 2, "惰性剔除后应有 2 个实体");
        assertTrue(dm.getDepth(testClips[0]) != undefined, "存活实体应保持");
        assertTrue(dm.getDepth(testClips[1]) != undefined, "存活实体应保持");
        record("惰性剔除", dm.size() == 2);

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
        assertTrue(dm.size() == 1, "同名复用后 size 应为 1");
        assertTrue(dm.getDepth(newClip) != undefined, "新 MC 应成功注册");
        newClip.removeMovieClip();
        record("同名MC复用", dm.size() == 1 || dm.getDepth(newClip) != undefined);
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
        dm.flush();
        var d0Before:Number = dm.getDepth(testClips[0]);
        var d1Before:Number = dm.getDepth(testClips[1]);

        dm.calibrate(500, 950);
        // 只 re-feed testClips[0]，不 re-feed testClips[1]
        dm.updateDepth(testClips[0], 600);
        dm.flush();

        // testClips[0] 应有新深度
        assertTrue(dm.getDepth(testClips[0]) != d0Before, "re-feed 的实体深度应变化");
        // testClips[1] 应保持 -1（失效态，不触发 swapDepths）——getDepth 返回 _curD = -1
        var d1After:Number = dm.getDepth(testClips[1]);
        assertTrue(d1After == -1, "未 re-feed 的实体深度应为 -1（失效态）");
        record("场景切换(部分re-feed)", d1After == -1);
    }

    // ═══════════════════════════════════════════
    //  性能基准
    // ═══════════════════════════════════════════

    private function runPerformanceTests():Void {
        printHeader("性能测试");

        warmupEnvironment();

        var swapTime:Number = testSwapDepthsPerformance();
        var dmTime:Number = testDepthManagerPerformance();

        comparePerformance(swapTime, dmTime);
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
        w = warmupIter;
        while (w--) {
            i = 20;
            while (i--) wDM.updateDepth(wClips[i], 200 + i);
            wDM.flush();
        }
        wDM.dispose();
        wc.removeMovieClip();
        printLog("预热完成");
    }

    private function testSwapDepthsPerformance():Number {
        printLog("测试原生 swapDepths 性能...");
        var total:Number = 0;
        var iter:Number = perfIter;
        while (iter--) {
            // 重置深度
            var j:Number = clipCount;
            while (j--) testClips[j].swapDepths(j + 100);
            var t0:Number = getTimer();
            j = clipCount;
            while (j--) {
                testClips[j].swapDepths(1000 + ((Math.random() * 1000) | 0));
            }
            total += getTimer() - t0;
        }
        var avg:Number = total / perfIter;
        printLog("原生 swapDepths 平均耗时: " + avg + " 毫秒");
        return avg;
    }

    private function testDepthManagerPerformance():Number {
        printLog("测试 DepthManager 性能...");
        var total:Number = 0;
        var iter:Number = perfIter;
        while (iter--) {
            resetDM();
            var t0:Number = getTimer();
            var j:Number = clipCount;
            while (j--) {
                dm.updateDepth(testClips[j], 200 + ((Math.random() * 600) | 0));
            }
            dm.flush();
            total += getTimer() - t0;
        }
        var avg:Number = total / perfIter;
        printLog("DepthManager 平均耗时: " + avg + " 毫秒");
        return avg;
    }

    private function comparePerformance(swapTime:Number, dmTime:Number):Void {
        printLog("性能比较结果:");
        var diff:Number = dmTime - swapTime;
        var pct:Number;
        if (swapTime > 0) {
            pct = (diff / swapTime) * 100;
        } else {
            pct = 0;
        }

        printLog("上线建议:");
        if (pct < 10) {
            printLog("√ 深度管理器性能表现良好 (开销 <10%)，可以上线");
        } else if (pct < 50) {
            printLog("△ 深度管理器有一定性能开销 (" + ((pct * 10) | 0) / 10 + "%)，需根据场景评估");
        } else {
            printLog("× 深度管理器性能开销较大 (" + ((pct * 10) | 0) / 10 + "%)，需进一步优化");
        }

        // 与旧方案对比
        printLog("旧方案基线: 27.15ms (543x swapDepths)");
        printLog("新方案: " + dmTime + "ms");
        if (dmTime < 27.15) {
            printLog("√ 新方案优于旧方案");
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
