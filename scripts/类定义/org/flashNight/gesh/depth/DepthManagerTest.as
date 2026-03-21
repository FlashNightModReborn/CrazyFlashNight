import org.flashNight.gesh.depth.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * @class DepthManagerTest
 * @description DepthManager (Twip Trick) 综合测试套件 v2
 *
 *   测试原则:
 *     - assertTrue 失败直接累计到当前 case 的 passed 变量
 *     - record(name, passed) 只吃聚合后的布尔结果，禁止 record(..., true)
 *     - 行为断言同时验证 dm.getDepth()（管理器缓存）和 mc.getDepth()（Flash 显示列表真实状态）
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

    private var warmupIter:Number;
    private var perfIter:Number;

    private var _randDepths:Array;
    private var _randYs:Array;
    private var _randLen:Number;

    public function DepthManagerTest() {
        totalTests = 0;
        passedTests = 0;
        failedTests = 0;
        clipCount = 256;
        warmupIter = 50;
        perfIter = 2000;
    }

    // ═══════════════════════════════════════════
    //  入口
    // ═══════════════════════════════════════════

    public function runTests():Void {
        printHeader("DepthManager (Twip Trick) 测试套件 v2");
        setupTestEnvironment();

        testCalibrate();
        testBasicOperations();
        testZeroCollision();
        testMonotonicity();
        testErrorHandling();
        testLazyEviction();
        testStaleReference();
        testSameNameExternalClip();
        testBatchStaleDmIdx();
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
        dm = new DepthManager(testContainer, 10000, 1048575, 256);
        dm.calibrate(200, 800);
    }

    // ═══════════════════════════════════════════
    //  1. 标定测试
    // ═══════════════════════════════════════════

    private function testCalibrate():Void {
        printTestGroup("标定测试");

        // 真实场景 Y 范围
        var scenes:Array = [
            {yMin: 150, yMax: 1000, label: "最宽场景"},
            {yMin: 280, yMax: 800,  label: "典型场景"},
            {yMin: 200, yMax: 370,  label: "最窄场景"},
            {yMin: 500, yMax: 950,  label: "高位场景"},
            {yMin: 300, yMax: 550,  label: "短程场景"}
        ];
        var p:Boolean = true;
        var i:Number = 0;
        while (i < scenes.length) {
            var s:Object = scenes[i];
            var td:DepthManager = new DepthManager(testContainer, 10000, 1048575, 64);
            p = assertTrue(td.calibrate(Number(s.yMin), Number(s.yMax)),
                "calibrate 应成功: " + s.label) && p;
            td.dispose();
            i++;
        }
        record("5组真实场景标定", p);

        // 极端：N=128 yRange=10000 应失败
        var td2:DepthManager = new DepthManager(testContainer, 10000, 1048575, 128);
        var ok2:Boolean = td2.calibrate(0, 10000);
        td2.dispose();
        record("极端标定拒绝", assertTrue(ok2 == false, "N=128 yRange=10000 应失败") && (ok2 == false));

        // 可行：N=128 yRange=850
        var td3:DepthManager = new DepthManager(testContainer, 10000, 1048575, 128);
        var ok3:Boolean = td3.calibrate(150, 1000);
        td3.dispose();
        record("极端标定 N=128 可行", assertTrue(ok3, "N=128 yRange=850 应成功") && ok3);

        // 生产容量：N=256 yRange=850（bandLow=0 → S=4）
        var td3b:DepthManager = new DepthManager(testContainer, 0, 1048575, 256);
        var ok3b:Boolean = td3b.calibrate(150, 1000);
        td3b.dispose();
        record("生产容量 N=256 可行", assertTrue(ok3b, "N=256 bandLow=0 yRange=850 应成功") && ok3b);

        // 反向 calibrate(800, 200) — yRange 为负，应当退化为 yRange=1 后仍成功
        var td4:DepthManager = new DepthManager(testContainer, 10000, 1048575, 256);
        var ok4:Boolean = td4.calibrate(800, 200);
        // calibrate 内部 yRange = yMax - yMin，若 <1 则 clamp 到 1
        // S = floor((bandSpan - N + 1) / (1 * N)) 必定 >> 1，应成功
        td4.dispose();
        record("反向calibrate(800,200)", assertTrue(ok4, "反向 calibrate 应成功（yRange clamp 到 1）") && ok4);
    }

    // ═══════════════════════════════════════════
    //  2. 基本操作
    // ═══════════════════════════════════════════

    private function testBasicOperations():Void {
        printTestGroup("基本操作测试");

        // 添加新实体 — 同时验证管理器缓存和显示列表真实状态
        resetDM();
        var clip1:MovieClip = testClips[0];
        var clip2:MovieClip = testClips[1];
        dm.updateDepth(clip1, 300);
        dm.updateDepth(clip2, 500);
        var p:Boolean = true;
        p = assertTrue(dm.size() == 2, "应有 2 个实体") && p;
        var d1:Number = dm.getDepth(clip1);
        var d2:Number = dm.getDepth(clip2);
        p = assertTrue(d1 != undefined, "clip1 应有深度值") && p;
        p = assertTrue(d2 != undefined, "clip2 应有深度值") && p;
        p = assertTrue(d1 < d2, "Y=300 的深度应小于 Y=500") && p;
        // 验证显示列表真实状态
        p = assertTrue(clip1.getDepth() == d1, "clip1 显示列表深度应与管理器一致: Flash=" + clip1.getDepth() + " DM=" + d1) && p;
        p = assertTrue(clip2.getDepth() == d2, "clip2 显示列表深度应与管理器一致: Flash=" + clip2.getDepth() + " DM=" + d2) && p;
        record("添加新实体", p);

        // 热路径 eager apply
        resetDM();
        var eager0:Boolean = dm.updateDepth(clip1, 320);
        var eagerD0:Number = dm.getDepth(clip1);
        p = assertTrue(eager0, "首次 updateDepth 应成功");
        p = assertTrue(eagerD0 != undefined, "无需 flush 也应有有效深度") && p;
        p = assertTrue(clip1.getDepth() == eagerD0, "eager apply 应立即写入显示列表") && p;
        dm.updateDepth(clip1, 620);
        var eagerD1:Number = dm.getDepth(clip1);
        p = assertTrue(eagerD1 != undefined && eagerD1 > eagerD0, "重复 updateDepth 应立即刷新深度") && p;
        p = assertTrue(clip1.getDepth() == eagerD1, "第二次 eager apply 也应立即写入显示列表") && p;
        record("热路径 eager apply", p);

        // 批量热路径
        resetDM();
        var batchYs:Array = [340, 540];
        p = assertTrue(dm.updateDepthBatch([clip1, clip2], batchYs, 0, 2) == 2, "批量更新应处理 2 个实体");
        var batchD1:Number = dm.getDepth(clip1);
        var batchD2:Number = dm.getDepth(clip2);
        p = assertTrue(batchD1 != undefined, "批量更新后 clip1 应有深度") && p;
        p = assertTrue(batchD2 != undefined, "批量更新后 clip2 应有深度") && p;
        p = assertTrue(batchD1 < batchD2, "批量更新应保持深度单调") && p;
        p = assertTrue(clip1.getDepth() == batchD1, "批量 clip1 显示列表一致") && p;
        p = assertTrue(clip2.getDepth() == batchD2, "批量 clip2 显示列表一致") && p;
        record("批量热路径", p);

        // 更新已有实体
        resetDM();
        dm.updateDepth(clip1, 300);
        var oldD:Number = dm.getDepth(clip1);
        dm.updateDepth(clip1, 600);
        var newD:Number = dm.getDepth(clip1);
        p = assertTrue(newD != oldD, "更新后深度应变化");
        p = assertTrue(newD > oldD, "Y增大深度应增大") && p;
        p = assertTrue(dm.size() == 1, "仍应只有 1 个实体") && p;
        p = assertTrue(clip1.getDepth() == newD, "更新后显示列表应同步") && p;
        record("更新已有实体", p);

        // 移除实体
        resetDM();
        dm.updateDepth(clip1, 300);
        dm.updateDepth(clip2, 500);
        var removed:Boolean = dm.removeMovieClip(clip1);
        p = assertTrue(removed, "移除应返回 true");
        p = assertTrue(dm.size() == 1, "移除后应有 1 个实体") && p;
        p = assertTrue(dm.getDepth(clip1) == undefined, "被移除实体 getDepth 应返回 undefined") && p;
        p = assertTrue(dm.getDepth(clip2) != undefined, "未移除实体应保持") && p;
        record("移除实体", p);
    }

    // ═══════════════════════════════════════════
    //  3. 零碰撞
    // ═══════════════════════════════════════════

    private function testZeroCollision():Void {
        printTestGroup("零碰撞测试");

        resetDM();
        var sameY:Number = 500;
        var i:Number = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], sameY);
            i++;
        }

        // 同时验证管理器和显示列表
        var depthSet:Object = {};
        depthSet.__proto__ = null;
        var flashDepthSet:Object = {};
        flashDepthSet.__proto__ = null;
        var collisions:Number = 0;
        var flashCollisions:Number = 0;
        i = 0;
        while (i < clipCount) {
            var d:Number = dm.getDepth(testClips[i]);
            var fd:Number = testClips[i].getDepth();
            if (depthSet[String(d)] !== undefined) collisions++;
            depthSet[String(d)] = i;
            if (flashDepthSet[String(fd)] !== undefined) flashCollisions++;
            flashDepthSet[String(fd)] = i;
            i++;
        }
        var p:Boolean = assertTrue(collisions == 0, "管理器零碰撞，实际碰撞: " + collisions);
        p = assertTrue(flashCollisions == 0, "显示列表零碰撞，实际碰撞: " + flashCollisions) && p;
        record("50实体同Y零碰撞", p);
    }

    // ═══════════════════════════════════════════
    //  4. 排序单调性
    // ═══════════════════════════════════════════

    private function testMonotonicity():Void {
        printTestGroup("排序单调性测试");

        resetDM();
        var i:Number = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i * 10);
            i++;
        }

        // 验证显示列表深度严格递增
        var monotone:Boolean = true;
        i = 1;
        while (i < clipCount) {
            var prevFlash:Number = testClips[i - 1].getDepth();
            var curFlash:Number = testClips[i].getDepth();
            if (curFlash <= prevFlash) {
                monotone = false;
                printLog("显示列表单调性破坏: clip" + (i-1) + "=" + prevFlash + " >= clip" + i + "=" + curFlash);
            }
            i++;
        }
        record("排序单调性(显示列表)", assertTrue(monotone, "递增 Y 应产生显示列表严格递增 depth") && monotone);

        // 同 Y 稳定性
        resetDM();
        i = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 500);
            i++;
        }
        var depths1:Array = [];
        i = 0;
        while (i < 10) {
            depths1.push(testClips[i].getDepth());
            i++;
        }
        // 再次 updateDepth 同一 Y
        i = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 500);
            i++;
        }
        var stable:Boolean = true;
        i = 0;
        while (i < 10) {
            if (testClips[i].getDepth() !== depths1[i]) stable = false;
            i++;
        }
        record("同Y稳定性(显示列表)", assertTrue(stable, "同 Y 实体连续更新显示列表深度应稳定") && stable);
    }

    // ═══════════════════════════════════════════
    //  5. 错误处理
    // ═══════════════════════════════════════════

    private function testErrorHandling():Void {
        printTestGroup("错误处理测试");
        resetDM();

        record("null MC 处理", assertTrue(dm.updateDepth(null, 100) == false, "null MC 应返回 false"));

        record("NaN targetY 处理", assertTrue(dm.updateDepth(testClips[0], Number.NaN) == false, "NaN 应返回 false"));

        var p:Boolean = assertTrue(dm.removeMovieClip(null) == false, "null 移除应返回 false");
        p = assertTrue(dm.getDepth(testClips[49]) == undefined, "未注册实体 getDepth 应返回 undefined") && p;
        record("未注册/null 查询", p);

        // 容量上限
        var smallDM:DepthManager = new DepthManager(testContainer, 10000, 1048575, 5);
        smallDM.calibrate(200, 800);
        var i:Number = 0;
        while (i < 5) {
            smallDM.updateDepth(testClips[i], 300 + i * 10);
            i++;
        }
        var overCap:Boolean = smallDM.updateDepth(testClips[5], 400);
        p = assertTrue(overCap == false, "超容量应返回 false");
        p = assertTrue(smallDM.size() == 5, "容量应保持 5") && p;
        smallDM.dispose();
        record("容量上限", p);

        // 外部 clip
        var extClip:MovieClip = _root.createEmptyMovieClip("extClip_test", _root.getNextHighestDepth());
        p = assertTrue(dm.getDepth(extClip) == undefined, "外部 clip getDepth 应返回 undefined");
        p = assertTrue(dm.removeMovieClip(extClip) == false, "外部 clip 移除应返回 false") && p;
        extClip.removeMovieClip();
        record("外部clip查询", p);
    }

    // ═══════════════════════════════════════════
    //  6. 惰性剔除
    // ═══════════════════════════════════════════

    private function testLazyEviction():Void {
        printTestGroup("惰性剔除测试");

        var tmpClip:MovieClip = testContainer.createEmptyMovieClip("tmpClip_evict", testContainer.getNextHighestDepth());
        resetDM();
        dm.updateDepth(testClips[0], 300);
        dm.updateDepth(tmpClip, 500);
        dm.updateDepth(testClips[1], 700);

        tmpClip.removeMovieClip();
        dm.updateDepth(testClips[0], 310);
        dm.updateDepth(testClips[1], 710);
        dm.sweepDead();

        var p:Boolean = assertTrue(dm.size() == 2, "惰性剔除后应有 2 个实体");
        p = assertTrue(dm.getDepth(testClips[0]) != undefined, "存活实体0应保持") && p;
        p = assertTrue(dm.getDepth(testClips[1]) != undefined, "存活实体1应保持") && p;
        record("惰性剔除", p);

        // 容量压力兜底
        var capDM:DepthManager = new DepthManager(testContainer, 10000, 1048575, 2);
        capDM.calibrate(200, 800);
        var capOld0:MovieClip = testContainer.createEmptyMovieClip("cap_old_0", testContainer.getNextHighestDepth());
        var capOld1:MovieClip = testContainer.createEmptyMovieClip("cap_old_1", testContainer.getNextHighestDepth());
        var capNew:MovieClip = testContainer.createEmptyMovieClip("cap_new", testContainer.getNextHighestDepth());
        capDM.updateDepth(capOld0, 260);
        capDM.updateDepth(capOld1, 360);
        capOld0.removeMovieClip();
        p = assertTrue(capDM.updateDepth(capNew, 460), "容量满时应先回收死对象再注册新实体");
        p = assertTrue(capDM.size() == 2, "兜底回收后 size=2") && p;
        p = assertTrue(capDM.getDepth(capNew) != undefined, "新实体应成功获得深度") && p;
        capOld1.removeMovieClip();
        capNew.removeMovieClip();
        capDM.dispose();
        record("容量压力兜底回收", p);

        // 同名 MC 复用
        resetDM();
        var poolName:String = "pooled_unit";
        var oldClip:MovieClip = testContainer.createEmptyMovieClip(poolName, testContainer.getNextHighestDepth());
        dm.updateDepth(oldClip, 400);
        oldClip.removeMovieClip();
        var newClip:MovieClip = testContainer.createEmptyMovieClip(poolName, testContainer.getNextHighestDepth());
        dm.updateDepth(newClip, 600);
        p = assertTrue(dm.size() == 1, "同名复用后 size 应为 1");
        p = assertTrue(dm.getDepth(newClip) != undefined, "新 MC 应成功注册") && p;
        newClip.removeMovieClip();
        record("同名MC复用", p);
    }

    // ═══════════════════════════════════════════
    //  7. stale old reference 不得影响 new clip
    // ═══════════════════════════════════════════

    private function testStaleReference():Void {
        printTestGroup("stale 引用隔离测试");

        // AS2 MC 引用模型：变量是基于显示列表路径的软引用。
        // 同容器内 removeMovieClip + 同名 createEmptyMovieClip 后，
        // 旧变量自动指向新 MC（路径解析）。因此"同容器同名 stale 引用"在 AS2 中不存在。
        //
        // 真正的 stale 场景是：MC 被 removeMovieClip 后不重建，旧变量成为 dead reference。
        // 此时 mc._name = undefined，DM 应安全处理。

        resetDM();

        // 场景 A：MC 销毁后不重建 → dead reference 安全
        var deadName:String = "dead_ref_unit";
        var deadClip:MovieClip = testContainer.createEmptyMovieClip(deadName, testContainer.getNextHighestDepth());
        dm.updateDepth(deadClip, 400);
        var p:Boolean = assertTrue(dm.getDepth(deadClip) != undefined, "deadClip 注册后应有深度");
        deadClip.removeMovieClip();
        // deadClip 现在是 dead reference，_name = undefined
        // sweepDead 或容量压力时回收
        dm.sweepDead();
        p = assertTrue(dm.size() == 0, "sweepDead 后 dead clip 应被回收") && p;
        record("dead引用sweepDead回收", p);

        // 场景 B：同名重建 → AS2 路径解析使 oldVar === newClip
        resetDM();
        var poolName:String = "stale_pool_unit";
        var oldRef:MovieClip = testContainer.createEmptyMovieClip(poolName, testContainer.getNextHighestDepth());
        dm.updateDepth(oldRef, 400);
        var oldD:Number = dm.getDepth(oldRef);
        oldRef.removeMovieClip();
        var newRef:MovieClip = testContainer.createEmptyMovieClip(poolName, testContainer.getNextHighestDepth());
        // AS2 路径解析：oldRef 现在应该 === newRef
        dm.updateDepth(newRef, 600);
        p = assertTrue(dm.size() == 1, "同名重建后 size=1");
        p = assertTrue(dm.getDepth(newRef) != undefined, "newRef 应有深度") && p;
        var newFlashD:Number = newRef.getDepth();
        var newDmD:Number = dm.getDepth(newRef);
        p = assertTrue(newFlashD == newDmD, "重建后显示列表与 DM 一致: Flash=" + newFlashD + " DM=" + newDmD) && p;
        // 新深度应与旧深度不同（Y 从 400 变为 600）
        p = assertTrue(dm.getDepth(newRef) != oldD, "重建后深度应反映新 Y 值") && p;
        newRef.removeMovieClip();
        record("同名重建路径解析安全", p);
    }

    // ═══════════════════════════════════════════
    //  8. 同名 external clip 不得误删受管对象
    // ═══════════════════════════════════════════

    private function testSameNameExternalClip():Void {
        printTestGroup("同名外部clip隔离测试");

        resetDM();
        var sharedName:String = "u_1";

        // managedClip 在 testContainer 中
        var managedClip:MovieClip = testContainer.createEmptyMovieClip(sharedName, testContainer.getNextHighestDepth());
        dm.updateDepth(managedClip, 400);

        // externalClip 在 _root 中（不同容器，同名）
        var externalClip:MovieClip = _root.createEmptyMovieClip(sharedName, _root.getNextHighestDepth());

        // 对 externalClip 调 getDepth/removeMovieClip — 因为 externalClip 的 _name 是 "u_1"，
        // 和 managedClip 同名，但 _mcs[idx] !== externalClip，不应影响 managedClip
        var extDepth:Number = dm.getDepth(externalClip);
        // getDepth 查 _idxMap["u_1"] 会命中，但返回的是 managedClip 的深度
        // 这是 name-based lookup 的已知限制：同名异容器会返回被管理对象的深度
        // 但 removeMovieClip 有 _mcs[idx] !== mc 防护

        var removeResult:Boolean = dm.removeMovieClip(externalClip);

        var p:Boolean = true;
        // removeMovieClip 内部查 _idxMap["u_1"] 但 _mcs[idx] 是 managedClip !== externalClip
        // AS2 中 removeMovieClip 通过 mc._name 查找，找到 idx 后检查 _mcs[idx] !== mc
        // 实际上 removeMovieClip 中没有引用比对——它用 mc._name 查 idxMap
        // 如果 managedClip._name == externalClip._name，removeMovieClip 可能误删
        // 这取决于 DepthManager.removeMovieClip 的实现
        p = assertTrue(dm.getDepth(managedClip) != undefined, "managedClip 不应被移除") && p;
        p = assertTrue(dm.size() >= 1, "size 不应减少") && p;
        // 验证显示列表
        p = assertTrue(managedClip.getDepth() == dm.getDepth(managedClip), "managedClip 显示列表应不受影响") && p;

        externalClip.removeMovieClip();
        managedClip.removeMovieClip();
        record("同名外部clip隔离", p);
    }

    // ═══════════════════════════════════════════
    //  9. 批量路径的 stale __dmIdx
    // ═══════════════════════════════════════════

    private function testBatchStaleDmIdx():Void {
        printTestGroup("批量stale __dmIdx测试");

        resetDM();
        var clip0:MovieClip = testClips[0];
        var clip1:MovieClip = testClips[1];
        var clip2:MovieClip = testClips[2];

        // 先通过逐实体注册，建立 __dmIdx 槽位缓存
        dm.updateDepth(clip0, 300);
        dm.updateDepth(clip1, 400);
        dm.updateDepth(clip2, 500);

        // 移除 clip1，使其 __dmIdx 过时
        dm.removeMovieClip(clip1);
        // _evict 会把 clip2 swap-and-pop 到 clip1 原来的槽位
        // clip1 的 __dmIdx 现在指向 clip2 的数据

        // 用批量接口更新 — clip1 的 stale __dmIdx 不应污染 clip2
        var batchYs:Array = [310, 410, 510];
        dm.updateDepthBatch([clip0, clip1, clip2], batchYs, 0, 3);

        var p:Boolean = assertTrue(dm.getDepth(clip0) != undefined, "clip0 应有深度");
        p = assertTrue(dm.getDepth(clip1) != undefined, "clip1 应重新注册") && p;
        p = assertTrue(dm.getDepth(clip2) != undefined, "clip2 不应被破坏") && p;
        // 验证显示列表单调性：Y 310 < 410 < 510 → depth 也应单调
        p = assertTrue(clip0.getDepth() < clip1.getDepth(), "显示列表 clip0 < clip1") && p;
        p = assertTrue(clip1.getDepth() < clip2.getDepth(), "显示列表 clip1 < clip2") && p;
        record("批量stale__dmIdx安全", p);
    }

    // ═══════════════════════════════════════════
    //  10. 内存管理
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
        var p:Boolean = assertTrue(dm.size() == clipCount, "应有 " + clipCount + " 个实体");

        var half:Number = (clipCount / 2) | 0;
        i = 0;
        while (i < half) {
            dm.removeMovieClip(testClips[i]);
            i++;
        }
        p = assertTrue(dm.size() == clipCount - half, "删除后应有 " + (clipCount - half)) && p;

        i = 0;
        while (i < half) {
            dm.updateDepth(testClips[i], 400 + i);
            i++;
        }
        p = assertTrue(dm.size() == clipCount, "重新添加后应有 " + clipCount) && p;
        p = assertTrue(dm.getDepth(testClips[0]) != undefined, "重新添加的实体应有深度") && p;
        p = assertTrue(testClips[0].getDepth() == dm.getDepth(testClips[0]), "重新添加后显示列表一致") && p;
        record("add-remove 循环", p);

        // clear
        resetDM();
        i = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i);
            i++;
        }
        dm.clear();
        p = assertTrue(dm.size() == 0, "clear 后 size 应为 0");
        p = assertTrue(dm.getDepth(testClips[0]) == undefined, "clear 后 getDepth 应返回 undefined") && p;
        record("clear 操作", p);

        // dispose + 重建
        resetDM();
        i = 0;
        while (i < clipCount) {
            dm.updateDepth(testClips[i], 200 + i);
            i++;
        }
        dm.dispose();
        dm = new DepthManager(testContainer, 10000, 1048575, 64);
        dm.calibrate(200, 800);
        p = assertTrue(dm.size() == 0, "dispose 后重建 size 应为 0");
        p = assertTrue(dm.updateDepth(testClips[0], 300), "dispose 后重建应可正常注册") && p;
        p = assertTrue(testClips[0].getDepth() == dm.getDepth(testClips[0]), "重建后显示列表一致") && p;
        record("dispose + 重建", p);
    }

    // ═══════════════════════════════════════════
    //  11. 场景切换
    // ═══════════════════════════════════════════

    private function testSceneSwitch():Void {
        printTestGroup("场景切换测试");

        resetDM();
        var i:Number = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 300 + i * 40);
            i++;
        }
        var dBefore:Number = testClips[0].getDepth();

        var ok:Boolean = dm.calibrate(500, 950);
        i = 0;
        while (i < 10) {
            dm.updateDepth(testClips[i], 550 + i * 30);
            i++;
        }
        var dAfter:Number = testClips[0].getDepth();
        var p:Boolean = assertTrue(ok, "re-calibrate 应成功");
        p = assertTrue(dAfter != dBefore, "场景切换后显示列表深度应变化") && p;

        var monotone:Boolean = true;
        i = 1;
        while (i < 10) {
            if (testClips[i].getDepth() <= testClips[i - 1].getDepth()) monotone = false;
            i++;
        }
        p = assertTrue(monotone, "新场景下显示列表排序应单调") && p;
        record("场景切换(全量re-feed)", p);

        // 部分 re-feed
        resetDM();
        dm.updateDepth(testClips[0], 300);
        dm.updateDepth(testClips[1], 500);
        dm.updateDepth(testClips[2], 700);

        dm.calibrate(500, 950);
        dm.updateDepth(testClips[0], 600);
        dm.updateDepth(testClips[2], 900);

        p = assertTrue(dm.getDepth(testClips[0]) != undefined, "re-feed 实体0应有新深度");
        p = assertTrue(dm.getDepth(testClips[1]) == undefined, "未 re-feed 实体 getDepth 应返回 undefined") && p;
        p = assertTrue(dm.getDepth(testClips[2]) != undefined, "re-feed 实体2不应被跳过") && p;
        record("场景切换(部分re-feed)", p);
    }

    // ═══════════════════════════════════════════
    //  性能基准（参考值，不作为 pass/fail 判据）
    // ═══════════════════════════════════════════

    private function runPerformanceTests():Void {
        printHeader("性能基准（参考值）");

        var rng:SeededLinearCongruentialEngine = new SeededLinearCongruentialEngine(42);
        _randLen = clipCount * perfIter;
        _randDepths = new Array(_randLen);
        _randYs = new Array(_randLen);
        var k:Number = _randLen;
        while (k--) {
            var r:Number = rng.nextFloat();
            _randDepths[k] = 1000 + ((r * 1000) | 0);
            _randYs[k] = 200 + ((r * 600) | 0);
        }
        printLog("预生成随机数据: " + _randLen + " 个 (种子=42, 可复现)");

        warmupEnvironment();

        var swapTime:Number = testSwapDepthsPerformance();
        var dmTime:Number = testDepthManagerPerformance();
        var dmBatchTime:Number = testDepthManagerBatchPerformance();

        comparePerformance("逐实体 updateDepth", swapTime, dmTime);
        comparePerformance("批量 updateDepthBatch", swapTime, dmBatchTime);

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
        var w:Number = warmupIter;
        while (w--) {
            i = 20;
            while (i--) wClips[i].swapDepths(200 + i);
        }
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
        var j:Number = clipCount;
        while (j--) testClips[j].swapDepths(j + 100);
        var randDepths:Array = _randDepths;
        var clips:Array = testClips;
        var n:Number = clipCount;
        var t0:Number = getTimer();
        var iter:Number = perfIter;
        var ri:Number = 0;
        while (iter--) {
            j = n;
            while (j--) clips[j].swapDepths(randDepths[ri++]);
        }
        var total:Number = getTimer() - t0;
        printLog("原生 swapDepths: 总 " + total + "ms / " + perfIter + " 迭代 = " + Math.round(total * 1000 / perfIter) + " μs/帧");
        return total;
    }

    private function testDepthManagerPerformance():Number {
        printLog("测试 DepthManager 性能（稳态，" + perfIter + " 迭代）...");
        resetDM();
        var j:Number = clipCount;
        while (j--) dm.updateDepth(testClips[j], 200 + j * 10);

        var randYs:Array = _randYs;
        var clips:Array = testClips;
        var n:Number = clipCount;
        var t0:Number = getTimer();
        var iter:Number = perfIter;
        var ri:Number = 0;
        while (iter--) {
            j = n;
            while (j--) {
                dm.updateDepth(clips[j], randYs[ri++]);
                if (ri >= _randLen) ri = 0;
            }
        }
        var total:Number = getTimer() - t0;
        printLog("DepthManager(逐实体): 总 " + total + "ms / " + perfIter + " 迭代 = " + Math.round(total * 1000 / perfIter) + " μs/帧（稳态）");
        return total;
    }

    private function testDepthManagerBatchPerformance():Number {
        printLog("测试 DepthManager 批量性能（稳态，" + perfIter + " 迭代）...");
        resetDM();
        var j:Number = clipCount;
        while (j--) dm.updateDepth(testClips[j], 200 + j * 10);

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
        printLog("DepthManager(批量): 总 " + total + "ms / " + perfIter + " 迭代 = " + Math.round(total * 1000 / perfIter) + " μs/帧（稳态）");
        return total;
    }

    private function comparePerformance(label:String, swapTotal:Number, dmTotal:Number):Void {
        var swapUs:Number = Math.round(swapTotal * 1000 / perfIter);
        var dmUs:Number = Math.round(dmTotal * 1000 / perfIter);
        var ratio:Number = Math.round(dmUs * 100 / swapUs) / 100;
        var overhead:Number = Math.round((dmTotal - swapTotal) * 1000 / swapTotal) / 10;

        printLog("────── " + label + "（" + perfIter + " 迭代，" + clipCount + " 实体） ──────");
        printLog("  裸 swapDepths : " + swapUs + " μs/帧（理论下界，无 lookup/clamp/注册/stale 检测）");
        printLog("  DepthManager  : " + dmUs + " μs/帧");
        printLog("  倍率          : " + ratio + "x");
        printLog("  管理层开销    : " + overhead + "%");
        printLog("  旧方案基线    : 1358 μs/帧（WAVL 树）→ 当前 " + Math.round(1358 / dmUs) + "x 加速");
    }

    // ═══════════════════════════════════════════
    //  辅助
    // ═══════════════════════════════════════════

    private function assertTrue(cond:Boolean, msg:String):Boolean {
        if (!cond) {
            printLog("  ✗ 断言失败: " + msg);
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

    private function printHeader(title:String):Void {
        trace("[DepthManagerTest] ");
        trace("[DepthManagerTest] ==================================================");
        trace("[DepthManagerTest]  " + title);
        trace("[DepthManagerTest] ==================================================");
    }

    private function printTestGroup(name:String):Void {
        trace("[DepthManagerTest] ");
        trace("[DepthManagerTest] ----- " + name + " -----");
    }

    private function printLog(msg:String):Void {
        trace("[DepthManagerTest] " + msg);
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
}
