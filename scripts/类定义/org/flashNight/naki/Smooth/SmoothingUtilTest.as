// 文件路径：org/flashNight/naki/Smooth/SmoothingUtilTest.as

import org.flashNight.naki.DataStructures.RingBuffer;
import org.flashNight.naki.Smooth.SmoothingUtil;
import org.flashNight.sara.util.Vector; // 导入 Vector 类

/**
 * SmoothingUtilTest
 * =================
 * SmoothingUtil 工具类的测试类 (Test Class for SmoothingUtil Utility)
 *
 * 负责对 SmoothingUtil 中的公共方法进行功能正确性验证、边界情况测试和基本性能评估。
 * (Responsible for verifying the functional correctness, testing boundary conditions, and basic performance evaluation
 * of the public methods in SmoothingUtil.)
 *
 * 使用内置的简单断言方法 (_assert*) 输出测试结果到 Trace 面板。
 * (Uses built-in simple assertion methods (_assert*) to output test results to the Trace panel.)
 *
 * 测试点数据统一使用 `org.flashNight.sara.util.Vector` 实例。
 * (Test point data uniformly uses `org.flashNight.sara.util.Vector` instances.)
 *
 */
class org.flashNight.naki.Smooth.SmoothingUtilTest
{
    // --------------------------
    // 内部常量 (Internal Constants)
    // --------------------------
    /**
     * @private
     * 用于浮点数比较的容差 (Tolerance for floating-point comparisons)
     */
    private static var FLOAT_TOLERANCE:Number = 0.0001;

    /**
     * @private
     * 性能测试中使用的点数量 (Number of points used in performance tests)
     */
    private static var PERF_TEST_POINTS:Number = 500;
     /**
     * @private
     * 性能测试运行次数 (Number of runs for performance averaging)
     */
    private static var PERF_TEST_RUNS:Number = 10;

    // --------------------------
    // 构造函数 (Constructor)
    // --------------------------
    /**
     * 私有构造函数 —— 测试类通常不需要实例化，使用静态方法运行。
     * (Private constructor - Test classes usually don't need instantiation, run using static methods.)
     */
    private function SmoothingUtilTest() { }

    // --------------------------
    // 测试运行器 (Test Runner)
    // --------------------------

    /**
     * 运行所有测试用例和性能测试。
     * (Runs all test cases and performance tests.)
     */
    public static function runAllTests():Void
    {
        trace("--- 开始运行 SmoothingUtil 测试 (使用 Vector) ---");
        trace("--- (Starting SmoothingUtil Tests (using Vector)) ---\n");

        // --- 功能测试 (Functional Tests) ---
        trace("--- 功能测试: simpleSmooth ---");
        _runTest(testSimpleSmooth_Empty, "testSimpleSmooth_Empty");
        _runTest(testSimpleSmooth_LessThan3, "testSimpleSmooth_LessThan3");
        _runTest(testSimpleSmooth_Basic3Points, "testSimpleSmooth_Basic3Points");
        _runTest(testSimpleSmooth_Basic5Points, "testSimpleSmooth_Basic5Points");
        _runTest(testSimpleSmooth_IdenticalPoints, "testSimpleSmooth_IdenticalPoints"); // 新增: 相同点测试
        _runTest(testSimpleSmooth_CollinearPoints, "testSimpleSmooth_CollinearPoints"); // 新增: 共线点测试
        trace("--- 功能测试: simpleSmooth 完成 ---\n");

        trace("--- 功能测试: catmullRomSmooth ---");
        _runTest(testCatmullRom_Empty, "testCatmullRom_Empty");
        _runTest(testCatmullRom_LessThan4, "testCatmullRom_LessThan4");
        _runTest(testCatmullRom_Basic4Points, "testCatmullRom_Basic4Points");
        _runTest(testCatmullRom_Basic5Points, "testCatmullRom_Basic5Points");
        _runTest(testCatmullRom_TensionEffect, "testCatmullRom_TensionEffect"); // 检查张力影响
        _runTest(testCatmullRom_IdenticalConsecutivePoints, "testCatmullRom_IdenticalConsecutivePoints"); // 新增: 相邻相同点
        _runTest(testCatmullRom_AllIdenticalPoints, "testCatmullRom_AllIdenticalPoints");     // 新增: 所有点相同
        _runTest(testCatmullRom_CollinearPoints, "testCatmullRom_CollinearPoints");     // 新增: 共线点测试
        trace("--- 功能测试: catmullRomSmooth 完成 ---\n");


        // --- 性能测试 (Performance Tests) ---
        trace("--- 性能测试 (Performance Tests) ---");
        trace("--- (点数量 Points: " + PERF_TEST_POINTS + ", 运行次数 Runs: " + PERF_TEST_RUNS + ") ---");
        perfTestSimpleSmooth();
        perfTestCatmullRomSmooth();
        trace("--- 性能测试 完成 ---\n");


        trace("--- SmoothingUtil 测试完成 ---");
        trace("--- (SmoothingUtil Tests Finished) ---");
    }

    // --------------------------
    // simpleSmooth 测试用例
    // --------------------------

    /** @private 测试 simpleSmooth 处理空 RingBuffer */
    private static function testSimpleSmooth_Empty():Void {
        var ring:RingBuffer = new RingBuffer(5);
        SmoothingUtil.simpleSmooth(ring);
        _assertEqual(0, ring.size, "处理空 RingBuffer 后大小应为 0");
        _assertEqual(0, ring.toArray().length, "处理空 RingBuffer 后 toArray 长度应为 0");
    }

    /** @private 测试 simpleSmooth 处理少于 3 个点的 RingBuffer */
    private static function testSimpleSmooth_LessThan3():Void {
        // Case 1: 1 point
        var ring1:RingBuffer = new RingBuffer(5, null, [new Vector(1, 1)]);
        var originalPts1:Array = ring1.toArray();
        SmoothingUtil.simpleSmooth(ring1);
        _assertEqual(1, ring1.size, "处理 1 个点后大小应为 1");
        _assertPointsEqual(originalPts1, ring1.toArray(), "处理 1 个点后数据应不变", false);

        // Case 2: 2 points
        var ring2:RingBuffer = new RingBuffer(5, null, [new Vector(1, 1), new Vector(2, 2)]);
        var originalPts2:Array = ring2.toArray();
        SmoothingUtil.simpleSmooth(ring2);
        _assertEqual(2, ring2.size, "处理 2 个点后大小应为 2");
        _assertPointsEqual(originalPts2, ring2.toArray(), "处理 2 个点后数据应不变", false);
    }

    /** @private 测试 simpleSmooth 处理刚好 3 个点 */
    private static function testSimpleSmooth_Basic3Points():Void {
        var ptsIn:Array = [new Vector(0, 0), new Vector(3, 6), new Vector(6, 0)];
        var ring:RingBuffer = new RingBuffer(3, null, ptsIn);
        SmoothingUtil.simpleSmooth(ring);
        var ptsOut:Array = ring.toArray();

        _assertEqual(3, ring.size, "处理 3 个点后大小应为 3");
        // 预期结果: 第一个点不变, 中间点平均, 第三个点不变
        // Expected: First point unchanged, middle point averaged, last point unchanged
        var expectedPts:Array = [
            new Vector(0, 0),             // 不变 (Unchanged)
            new Vector((0+3+6)/3, (0+6+0)/3), // 平均 (Averaged) => Vector(3, 2)
            new Vector(6, 0)              // 不变 (Unchanged)
        ];
        _assertPointsEqual(expectedPts, ptsOut, "处理 3 个点后的结果不正确", true); // 使用容差比较
    }

     /** @private 测试 simpleSmooth 处理超过 3 个点 (例如 5 个) */
    private static function testSimpleSmooth_Basic5Points():Void {
        var ptsIn:Array = [
            new Vector(0, 0), new Vector(1, 1), new Vector(3, 3), new Vector(5, 1), new Vector(6, 0)
        ];
        var ring:RingBuffer = new RingBuffer(5, null, ptsIn);
        SmoothingUtil.simpleSmooth(ring);
        var ptsOut:Array = ring.toArray();

        _assertEqual(5, ring.size, "处理 5 个点后大小应为 5");
        // 预期结果: 首尾不变，中间 3 个点被平滑
        // Expected: First/last unchanged, middle 3 points smoothed
        var expectedPts:Array = [
            new Vector(0, 0),                             // 不变 (Unchanged)
            new Vector((0+1+3)/3, (0+1+3)/3),             // (ptsIn[0]+ptsIn[1]+ptsIn[2])/3 => Vector(1.333, 1.333)
            new Vector((1+3+5)/3, (1+3+1)/3),             // (ptsIn[1]+ptsIn[2]+ptsIn[3])/3 => Vector(3, 1.666)
            new Vector((3+5+6)/3, (3+1+0)/3),             // (ptsIn[2]+ptsIn[3]+ptsIn[4])/3 => Vector(4.666, 1.333)
            new Vector(6, 0)                              // 不变 (Unchanged)
        ];
         _assertPointsEqual(expectedPts, ptsOut, "处理 5 个点后的结果不正确", true); // 使用容差比较
    }

    /** @private 测试 simpleSmooth 处理包含相同连续点的输入 */
    private static function testSimpleSmooth_IdenticalPoints():Void {
        var ptsIn:Array = [
            new Vector(0, 0), new Vector(1, 1), new Vector(1, 1), new Vector(3, 0), new Vector(4, 0)
        ];
        var ring:RingBuffer = new RingBuffer(5, null, ptsIn);
        SmoothingUtil.simpleSmooth(ring);
        var ptsOut:Array = ring.toArray();

        _assertEqual(5, ring.size, "处理含相同点的 5 个点后大小应为 5");
        var expectedPts:Array = [
            new Vector(0, 0),              // 不变
            new Vector((0+1+1)/3, (0+1+1)/3), // (0,0)+(1,1)+(1,1) / 3 => Vector(0.666, 0.666)
            new Vector((1+1+3)/3, (1+1+0)/3), // (1,1)+(1,1)+(3,0) / 3 => Vector(1.666, 0.666)
            new Vector((1+3+4)/3, (1+0+0)/3), // (1,1)+(3,0)+(4,0) / 3 => Vector(2.666, 0.333)
            new Vector(4, 0)               // 不变
        ];
        _assertPointsEqual(expectedPts, ptsOut, "处理含相同点的 5 个点后的结果不正确", true);
    }

    /** @private 测试 simpleSmooth 处理共线点 */
    private static function testSimpleSmooth_CollinearPoints():Void {
        var ptsIn:Array = [
            new Vector(0, 0), new Vector(1, 1), new Vector(2, 2), new Vector(3, 3), new Vector(4, 4)
        ];
        var ring:RingBuffer = new RingBuffer(5, null, ptsIn);
        SmoothingUtil.simpleSmooth(ring);
        var ptsOut:Array = ring.toArray();

        _assertEqual(5, ring.size, "处理共线点后大小应为 5");
        // 预期结果: 所有点仍应在 y=x 这条线上
        var expectedPts:Array = [
            new Vector(0, 0),              // 不变
            new Vector((0+1+2)/3, (0+1+2)/3), // => Vector(1, 1)
            new Vector((1+2+3)/3, (1+2+3)/3), // => Vector(2, 2)
            new Vector((2+3+4)/3, (2+3+4)/3), // => Vector(3, 3)
            new Vector(4, 4)               // 不变
        ];
        _assertPointsEqual(expectedPts, ptsOut, "处理共线点后的结果不正确", true);

        // 额外检查: 所有输出点是否仍然共线
        for (var i:Number = 1; i < ptsOut.length - 1; i++) {
            _assertTrue(_areCollinear(ptsOut[i-1], ptsOut[i], ptsOut[i+1], FLOAT_TOLERANCE),
                        "SimpleSmooth 共线测试: 点 " + (i-1) + ", " + i + ", " + (i+1) + " 应保持共线");
        }
    }


    // --------------------------
    // catmullRomSmooth 测试用例
    // --------------------------

    /** @private 测试 catmullRomSmooth 处理空 RingBuffer */
    private static function testCatmullRom_Empty():Void {
        var ring:RingBuffer = new RingBuffer(5);
        SmoothingUtil.catmullRomSmooth(ring, 0.5);
        _assertEqual(0, ring.size, "Catmull 处理空 RingBuffer 后大小应为 0");
        _assertEqual(0, ring.toArray().length, "Catmull 处理空 RingBuffer 后 toArray 长度应为 0");
    }

    /** @private 测试 catmullRomSmooth 处理少于 4 个点的 RingBuffer */
    private static function testCatmullRom_LessThan4():Void {
        // Case 1: 1 point
        var ring1:RingBuffer = new RingBuffer(5, null, [new Vector(1, 1)]);
        var originalPts1:Array = ring1.toArray();
        SmoothingUtil.catmullRomSmooth(ring1, 0.5);
        _assertEqual(1, ring1.size, "Catmull 处理 1 个点后大小应为 1");
        _assertPointsEqual(originalPts1, ring1.toArray(), "Catmull 处理 1 个点后数据应不变", false);

        // Case 2: 2 points
        var ring2:RingBuffer = new RingBuffer(5, null, [new Vector(1, 1), new Vector(2, 2)]);
        var originalPts2:Array = ring2.toArray();
        SmoothingUtil.catmullRomSmooth(ring2, 0.5);
        _assertEqual(2, ring2.size, "Catmull 处理 2 个点后大小应为 2");
        _assertPointsEqual(originalPts2, ring2.toArray(), "Catmull 处理 2 个点后数据应不变", false);

        // Case 3: 3 points
        var ring3:RingBuffer = new RingBuffer(5, null, [new Vector(1, 1), new Vector(2, 2), new Vector(3, 1)]);
        var originalPts3:Array = ring3.toArray();
        SmoothingUtil.catmullRomSmooth(ring3, 0.5);
        _assertEqual(3, ring3.size, "Catmull 处理 3 个点后大小应为 3");
        _assertPointsEqual(originalPts3, ring3.toArray(), "Catmull 处理 3 个点后数据应不变", false);
    }

    /** @private 测试 catmullRomSmooth 处理刚好 4 个点 */
    private static function testCatmullRom_Basic4Points():Void {
        var ptsIn:Array = [
            new Vector(0, 0), new Vector(10, 10), new Vector(20, 0), new Vector(30, 10)
        ];
        var ring:RingBuffer = new RingBuffer(10, null, ptsIn); // 容量足够大
        var originalSize:Number = ring.size;
        SmoothingUtil.catmullRomSmooth(ring, 0.5); // 使用默认张力
        var ptsOut:Array = ring.toArray();

        // 原始 n 个点，会生成 2 * n 个新点 (因为在每对原始点之间插值2个点)
        // n original points generate 2 * n new points (2 points interpolated between each original pair)
        var expectedSize:Number = 2 * originalSize; // 2 * 4 = 8
        _assertEqual(expectedSize, ring.size, "Catmull 处理 4 个点后的大小应为 " + expectedSize);
        _assertEqual(expectedSize, ptsOut.length, "Catmull 处理 4 个点后 toArray 长度应为 " + expectedSize);

        // 检查所有输出点是否有效 (非 NaN 或 Infinity)
        for (var i:Number = 0; i < ptsOut.length; i++) {
            var p:Vector = ptsOut[i]; // 类型改为 Vector
            _assertTrue(p != null, "Catmull 点 " + i + " 不应为 null");
            _assertTrue(!isNaN(p.x) && isFinite(p.x), "Catmull 点 " + i + " 的 x 坐标无效: " + p.x);
            _assertTrue(!isNaN(p.y) && isFinite(p.y), "Catmull 点 " + i + " 的 y 坐标无效: " + p.y);
        }

        // 可选抽样检查: 第一个插值点应在 p0 和 p1 附近
        if (ptsOut.length > 1) {
             var p_int0:Vector = ptsOut[0];
             _assertTrue(p_int0.x >= 0 && p_int0.x <= 10, "第一个插值点 x(" + p_int0.x + ") 大致应在 0 和 10 之间");
             _assertTrue(p_int0.y >= 0 && p_int0.y <= 10, "第一个插值点 y(" + p_int0.y + ") 大致应在 0 和 10 之间");
        }
    }

    /** @private 测试 catmullRomSmooth 处理超过 4 个点 (例如 5 个) */
     private static function testCatmullRom_Basic5Points():Void {
        var ptsIn:Array = [
            new Vector(0, 0), new Vector(10, 10), new Vector(20, 0), new Vector(30, 10), new Vector(40, 0)
        ];
        var ring:RingBuffer = new RingBuffer(15, null, ptsIn); // 容量足够大
        var originalSize:Number = ring.size;
        SmoothingUtil.catmullRomSmooth(ring, 0.5);
        var ptsOut:Array = ring.toArray();

        var expectedSize:Number = 2 * originalSize; // 2 * 5 = 10
        _assertEqual(expectedSize, ring.size, "Catmull 处理 5 个点后的大小应为 " + expectedSize);
        _assertEqual(expectedSize, ptsOut.length, "Catmull 处理 5 个点后 toArray 长度应为 " + expectedSize);

        // 检查所有输出点是否有效
        for (var i:Number = 0; i < ptsOut.length; i++) {
            var p:Vector = ptsOut[i]; // 类型改为 Vector
            _assertTrue(p != null, "Catmull 5点测试 点 " + i + " 不应为 null");
            _assertTrue(!isNaN(p.x) && isFinite(p.x), "Catmull 5点测试 点 " + i + " 的 x 坐标无效: " + p.x);
            _assertTrue(!isNaN(p.y) && isFinite(p.y), "Catmull 5点测试 点 " + i + " 的 y 坐标无效: " + p.y);
        }
    }

    /** @private 测试不同张力对 Catmull-Rom 结果的影响 (结果应不同) */
    private static function testCatmullRom_TensionEffect(): Void {
        var ptsIn:Array = [
            new Vector(0, 0), new Vector(10, 10), new Vector(20, 0), new Vector(30, 10)
        ];
        var n:Number = ptsIn.length;
        var expectedSize:Number = 2 * n;

        // Tension 0.5 (Centripetal)
        var ring1:RingBuffer = new RingBuffer(expectedSize + 2, null, ptsIn);
        SmoothingUtil.catmullRomSmooth(ring1, 0.5);
        var ptsOut1:Array = ring1.toArray();
        _assertEqual(expectedSize, ptsOut1.length, "Catmull (tension 0.5) 输出点数应为 " + expectedSize);


        // Tension 0.1 (接近 Chordal)
        var ring2:RingBuffer = new RingBuffer(expectedSize + 2, null, ptsIn);
        SmoothingUtil.catmullRomSmooth(ring2, 0.1);
        var ptsOut2:Array = ring2.toArray();
        _assertEqual(expectedSize, ptsOut2.length, "Catmull (tension 0.1) 输出点数应为 " + expectedSize);


        // Tension 1.0 (通常更紧)
        var ring3:RingBuffer = new RingBuffer(expectedSize + 2, null, ptsIn);
        SmoothingUtil.catmullRomSmooth(ring3, 1.0);
        var ptsOut3:Array = ring3.toArray();
        _assertEqual(expectedSize, ptsOut3.length, "Catmull (tension 1.0) 输出点数应为 " + expectedSize);


        // 比较不同张力下的第一个插值点，它们应该不同 (使用容差比较是否 *不* 相等)
        _assertNotClose(ptsOut1[0].x, ptsOut2[0].x, FLOAT_TOLERANCE, "张力 0.5 vs 0.1 的第一个点 x 坐标应不同");
        _assertNotClose(ptsOut1[0].y, ptsOut2[0].y, FLOAT_TOLERANCE, "张力 0.5 vs 0.1 的第一个点 y 坐标应不同");

        _assertNotClose(ptsOut1[0].x, ptsOut3[0].x, FLOAT_TOLERANCE, "张力 0.5 vs 1.0 的第一个点 x 坐标应不同");
        _assertNotClose(ptsOut1[0].y, ptsOut3[0].y, FLOAT_TOLERANCE, "张力 0.5 vs 1.0 的第一个点 y 坐标应不同");

         _assertNotClose(ptsOut2[0].x, ptsOut3[0].x, FLOAT_TOLERANCE, "张力 0.1 vs 1.0 的第一个点 x 坐标应不同");
         _assertNotClose(ptsOut2[0].y, ptsOut3[0].y, FLOAT_TOLERANCE, "张力 0.1 vs 1.0 的第一个点 y 坐标应不同");
    }

    /** @private 测试 Catmull-Rom 处理包含相邻相同点的情况 */
    private static function testCatmullRom_IdenticalConsecutivePoints(): Void {
        var ptsIn:Array = [
            new Vector(0, 0),
            new Vector(10, 10),
            new Vector(10, 10), // 相同点 (Identical point)
            new Vector(30, 0)
        ];
        var ring:RingBuffer = new RingBuffer(10, null, ptsIn);
        var originalSize:Number = ring.size; // 4
        var expectedSize:Number = 2 * originalSize; // 8

        // 目标：确保算法不会因为距离为零而出错 (例如除零)
        // Goal: Ensure the algorithm doesn't fail (e.g., division by zero) due to zero distance
        try {
            SmoothingUtil.catmullRomSmooth(ring, 0.5);
            var ptsOut:Array = ring.toArray();

            _assertEqual(expectedSize, ring.size, "Catmull 处理相邻相同点后的大小应为 " + expectedSize);

            // 检查所有输出点是否有效
            for (var i:Number = 0; i < ptsOut.length; i++) {
                var p:Vector = ptsOut[i];
                _assertTrue(p != null, "Catmull 相邻相同点测试: 点 " + i + " 不应为 null");
                _assertTrue(!isNaN(p.x) && isFinite(p.x), "Catmull 相邻相同点测试: 点 " + i + " 的 x 坐标无效: " + p.x);
                _assertTrue(!isNaN(p.y) && isFinite(p.y), "Catmull 相邻相同点测试: 点 " + i + " 的 y 坐标无效: " + p.y);
            }
            // 可以在此添加更具体的检查，例如插值出的点是否接近 (10, 10)
            // More specific checks could be added, e.g., if interpolated points near (10, 10) are close to it.

        } catch (e:Error) {
            _assertTrue(false, "Catmull 处理相邻相同点时不应抛出异常: " + e.toString());
        }
    }

    /** @private 测试 Catmull-Rom 处理所有输入点都相同的情况 */
    private static function testCatmullRom_AllIdenticalPoints(): Void {
        var identicalPoint:Vector = new Vector(5, 5);
        var ptsIn:Array = [
            identicalPoint, identicalPoint, identicalPoint, identicalPoint
        ];
        var ring:RingBuffer = new RingBuffer(10, null, ptsIn);
        var originalSize:Number = ring.size; // 4
        var expectedSize:Number = 2 * originalSize; // 8

        // 目标：确保算法在这种退化情况下能正常工作并产生有效输出
        // Goal: Ensure the algorithm works and produces valid output in this degenerate case
         try {
            SmoothingUtil.catmullRomSmooth(ring, 0.5);
            var ptsOut:Array = ring.toArray();

            _assertEqual(expectedSize, ring.size, "Catmull 处理所有相同点后的大小应为 " + expectedSize);

            // 检查所有输出点是否有效，并且应该非常接近原始点
            for (var i:Number = 0; i < ptsOut.length; i++) {
                var p:Vector = ptsOut[i];
                _assertTrue(p != null, "Catmull 全相同点测试: 点 " + i + " 不应为 null");
                _assertTrue(!isNaN(p.x) && isFinite(p.x), "Catmull 全相同点测试: 点 " + i + " 的 x 坐标无效: " + p.x);
                _assertTrue(!isNaN(p.y) && isFinite(p.y), "Catmull 全相同点测试: 点 " + i + " 的 y 坐标无效: " + p.y);
                // 检查输出点是否接近原始点
                _assertClose(identicalPoint.x, p.x, FLOAT_TOLERANCE * 10, "Catmull 全相同点测试: 点 " + i + " 的 x 坐标 (" + p.x + ") 应接近 " + identicalPoint.x);
                _assertClose(identicalPoint.y, p.y, FLOAT_TOLERANCE * 10, "Catmull 全相同点测试: 点 " + i + " 的 y 坐标 (" + p.y + ") 应接近 " + identicalPoint.y);
            }
        } catch (e:Error) {
            _assertTrue(false, "Catmull 处理所有相同点时不应抛出异常: " + e.toString());
        }
    }

    /** @private 测试 Catmull-Rom 处理共线点 */
    private static function testCatmullRom_CollinearPoints(): Void {
         var ptsIn:Array = [
            new Vector(0, 0), new Vector(10, 5), new Vector(20, 10), new Vector(30, 15), new Vector(40, 20) // y = 0.5x
        ];
        var ring:RingBuffer = new RingBuffer(15, null, ptsIn);
        var originalSize:Number = ring.size; // 5
        var expectedSize:Number = 2 * originalSize; // 10

        SmoothingUtil.catmullRomSmooth(ring, 0.5); // 使用 Centripetal Catmull-Rom
        var ptsOut:Array = ring.toArray();

        _assertEqual(expectedSize, ring.size, "Catmull 处理共线点后的大小应为 " + expectedSize);

        // 检查所有输出点是否有效
        for (var i:Number = 0; i < ptsOut.length; i++) {
            var p:Vector = ptsOut[i];
            _assertTrue(p != null, "Catmull 共线测试: 点 " + i + " 不应为 null");
            _assertTrue(!isNaN(p.x) && isFinite(p.x), "Catmull 共线测试: 点 " + i + " 的 x 坐标无效: " + p.x);
            _assertTrue(!isNaN(p.y) && isFinite(p.y), "Catmull 共线测试: 点 " + i + " 的 y 坐标无效: " + p.y);
        }

        // Catmull-Rom 通常会保持共线性（在数值精度范围内）
        // Check if the interpolated points stay on the line y = 0.5x
        // We check collinearity between segments involving original and interpolated points
        // 例如，检查 P0, Interp0, Interp1, P1 是否大致共线
        // Example: Check if P0, Interp0, Interp1, P1 are roughly collinear

        // 检查 P0, Interp0, P1
        _assertTrue(_areCollinear(ptsIn[0], ptsOut[0], ptsIn[1], FLOAT_TOLERANCE * 10),
                    "Catmull 共线测试: P0, 插值点0, P1 应大致共线");
        // 检查 P0, Interp1, P1
         _assertTrue(_areCollinear(ptsIn[0], ptsOut[1], ptsIn[1], FLOAT_TOLERANCE * 10),
                    "Catmull 共线测试: P0, 插值点1, P1 应大致共线");

        // 检查 P1, Interp2, P2 (索引对应 ptsOut[2], ptsOut[3])
         if (ptsIn.length > 2 && ptsOut.length > 3) {
             _assertTrue(_areCollinear(ptsIn[1], ptsOut[2], ptsIn[2], FLOAT_TOLERANCE * 10),
                         "Catmull 共线测试: P1, 插值点2, P2 应大致共线");
             _assertTrue(_areCollinear(ptsIn[1], ptsOut[3], ptsIn[2], FLOAT_TOLERANCE * 10),
                         "Catmull 共线测试: P1, 插值点3, P2 应大致共线");
         }
         // 可以继续检查后续线段...
    }

    // --------------------------
    // 性能测试方法
    // --------------------------

    /** @private 性能测试 simpleSmooth */
    private static function perfTestSimpleSmooth():Void {
        var ring:RingBuffer; // 声明在循环外
        var totalTime:Number = 0;
        var startTime:Number;
        var i:Number;

        for (i = 0; i < PERF_TEST_RUNS; i++) {
            // 每次测试前创建新的 Vector 数据
            ring = _createTestData(PERF_TEST_POINTS);
            startTime = getTimer();
            SmoothingUtil.simpleSmooth(ring);
            totalTime += (getTimer() - startTime);
        }
        var avgTime:Number = totalTime / PERF_TEST_RUNS;
        trace("性能 - simpleSmooth (" + PERF_TEST_POINTS + " Vector pts): 平均 " + Math.round(avgTime*100)/100 + " ms");
        trace("Perf - simpleSmooth (" + PERF_TEST_POINTS + " Vector pts): Avg " + Math.round(avgTime*100)/100 + " ms");
    }

    /** @private 性能测试 catmullRomSmooth */
    private static function perfTestCatmullRomSmooth():Void {
        var ring:RingBuffer; // 声明在循环外
        var totalTime:Number = 0;
        var startTime:Number;
        var i:Number;

        for (i = 0; i < PERF_TEST_RUNS; i++) {
            // 每次测试前创建新的 Vector 数据
            ring = _createTestData(PERF_TEST_POINTS);
            startTime = getTimer();
            SmoothingUtil.catmullRomSmooth(ring, 0.5); // 使用默认张力
            totalTime += (getTimer() - startTime);
        }
        var avgTime:Number = totalTime / PERF_TEST_RUNS;
        trace("性能 - catmullRomSmooth (" + PERF_TEST_POINTS + " Vector pts): 平均 " + Math.round(avgTime*100)/100 + " ms");
        trace("Perf - catmullRomSmooth (" + PERF_TEST_POINTS + " Vector pts): Avg " + Math.round(avgTime*100)/100 + " ms");
    }


    // --------------------------
    // 测试辅助方法 (Test Helper Methods)
    // --------------------------

    /**
     * @private
     * 创建包含指定数量 Vector 点的测试 RingBuffer
     * (Creates a test RingBuffer containing the specified number of Vector points)
     */
    private static function _createTestData(numPoints:Number):RingBuffer {
        var pts:Array = [];
        for (var i:Number = 0; i < numPoints; i++) {
            // 创建一些变化的测试数据，例如正弦波，使用 Vector
            // Create some varying test data, e.g., a sine wave, using Vector
            pts.push(new Vector(i * 2, 50 + Math.sin(i * 0.1) * 40));
        }
        // 容量设为点数，避免在测试前发生覆盖
        // Capacity set to number of points to avoid overwrites before testing
        // Catmull-Rom 会增加点数，测试中 RingBuffer 容量已设得足够大
        // Catmull-Rom increases points, RingBuffer capacity is set large enough in tests
        return new RingBuffer(numPoints * 2 + 10, null, pts); // 保证容量充足
    }

    /**
     * @private
     * 运行单个测试函数并报告结果
     * (Runs a single test function and reports the result)
     */
    private static function _runTest(testFunc:Function, testName:String):Void {
        var startTime:Number = getTimer();
        var success:Boolean = true;
        var errorMsg:String = "";
        try {
            testFunc();
            // 如果内部断言失败会打印信息，但这里不自动捕获断言失败的 "throw"（如果使用的话）
            // Internal assertions print messages on failure, but this doesn't auto-catch assertion 'throws' (if used)
        } catch (e:Error) {
            success = false;
            errorMsg = "发生异常 (Exception): " + e.toString();
            // 确保即使有异常，失败信息也能打印
             trace("  -> Test Error: " + errorMsg);
        }
        var duration:Number = getTimer() - startTime;

        // 通过检查日志输出判断是否真的成功（因为断言可能只打印不抛出）
        // We infer actual success by checking trace logs (since assertions might just print, not throw)
        // 这是一个简化的测试框架，更复杂的框架会显式记录失败状态
        // This is a simplified test framework; more complex ones explicitly track failure status

        // 修正：如果发生异常，明确标记为失败
        if (!success) { // Check if exception occurred
             trace(" [FAIL] " + testName + " (" + duration + " ms) " + errorMsg);
        } else {
             // 假设没有异常且断言未打印失败信息，则认为通过
             // Assume pass if no exception and no assertion failure messages were printed (check trace output)
             trace(" [PASS] " + testName + " (" + duration + " ms)");
        }
    }

     /**
     * @private
     * 检查三个点是否共线 (在给定容差范围内)
     * 使用面积法（叉积的两倍）：面积接近零则共线
     * (Checks if three points are collinear (within a given tolerance))
     * (Uses the area method (twice the cross product): collinear if area is near zero)
     * @param p1 第一个点 (First point)
     * @param p2 第二个点 (Second point)
     * @param p3 第三个点 (Third point)
     * @param tolerance 容差 (Tolerance for floating point comparison)
     * @return 如果共线则为 true (True if collinear)
     */
    private static function _areCollinear(p1:Vector, p2:Vector, p3:Vector, tolerance:Number):Boolean {
        if (p1 == null || p2 == null || p3 == null) return false; // 不能有 null 点
        // 计算叉积的两倍: (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
        var area2:Number = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x);
        return Math.abs(area2) < tolerance;
    }


    // --------------------------
    // 简单断言系统 (Simple Assertion System)
    // 注意：这些断言只打印到 trace，不中断执行。
    // Note: These assertions only print to trace, they don't halt execution.
    // --------------------------

    /** @private 断言条件为真 */
    private static function _assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("  -> Assertion Failed: " + message);
            // 在更严格的测试框架中，这里应该抛出错误或记录失败状态
            // In a stricter test framework, this would throw an error or record failure status
        }
    }

    /** @private 断言两个值严格相等 (===) */
    private static function _assertEqual(expected:Object, actual:Object, message:String):Void {
        if (expected !== actual) {
            trace("  -> Assertion Failed: " + message + " (Expected: " + expected + ", Actual: " + actual + ")");
        }
    }

     /** @private 断言两个值不相等 (!==) */
    private static function _assertNotEqual(val1:Object, val2:Object, message:String):Void {
         if (val1 === val2) {
            trace("  -> Assertion Failed: " + message + " (Values were equal: " + val1 + ")");
        }
    }

    /** @private 断言两个数字在容差范围内接近 */
    private static function _assertClose(expected:Number, actual:Number, tolerance:Number, message:String):Void {
        if (isNaN(expected) || isNaN(actual) || !isFinite(expected) || !isFinite(actual)) {
             if (!(isNaN(expected) && isNaN(actual))) { // 两者都是 NaN 时认为接近
                 trace("  -> Assertion Failed: " + message + " (NaN/Infinity mismatch - Expected: " + expected + ", Actual: " + actual + ")");
             }
             return;
        }
        if (Math.abs(expected - actual) > tolerance) {
             trace("  -> Assertion Failed: " + message + " (Expected: " + expected + ", Actual: " + actual + ", Tolerance: " + tolerance + ", Diff: " + Math.abs(expected-actual) + ")");
        }
    }

     /** @private 断言两个数字在容差范围内 *不* 接近 */
    private static function _assertNotClose(val1:Number, val2:Number, tolerance:Number, message:String):Void {
        if (isNaN(val1) || isNaN(val2) || !isFinite(val1) || !isFinite(val2)) {
             // 如果一个 NaN/Infinity 而另一个不是，它们肯定不接近
             if (!((isNaN(val1) && isNaN(val2)) || (val1 == val2))) { // Handles case where both are same infinity or both NaN
                 return; // They are not close, assertion passes
             }
             // 如果两者都是 NaN 或相同的 Infinity，则认为它们接近
             trace("  -> Assertion Failed: " + message + " (Values considered close due to NaN/Infinity match - Value 1: " + val1 + ", Value 2: " + val2 + ")");
             return;
        }
        if (Math.abs(val1 - val2) <= tolerance) {
             trace("  -> Assertion Failed: " + message + " (Values were close: " + val1 + " and " + val2 + ", Tolerance: " + tolerance + ", Diff: " + Math.abs(val1-val2) + ")");
        }
    }

    /**
     * @private
     * 断言两个 Vector 点对象数组内容相等 (或在容差内相等)
     * (Asserts that two arrays of Vector point objects are equal in content (or equal within tolerance))
     * @param expectedPts 预期的 Vector 数组 (Expected array of Vectors)
     * @param actualPts   实际的 Vector 数组 (Actual array of Vectors)
     * @param message     断言失败时的消息 (Message on assertion failure)
     * @param useTolerance 是否使用浮点容差比较坐标 (Whether to use float tolerance for comparing coordinates)
     */
    private static function _assertPointsEqual(expectedPts:Array, actualPts:Array, message:String, useTolerance:Boolean):Void {
        if (expectedPts == null || actualPts == null) {
            if (expectedPts !== actualPts) {
                 trace("  -> Assertion Failed: " + message + " (Point array null mismatch - Expected: " + expectedPts + ", Actual: " + actualPts + ")");
            }
            return; // Both are null, considered equal
        }

        if (expectedPts.length !== actualPts.length) {
             trace("  -> Assertion Failed: " + message + " (Array lengths differ - Expected: " + expectedPts.length + ", Actual: " + actualPts.length + ")");
             return;
        }

        var tolerance:Number = useTolerance ? FLOAT_TOLERANCE : 0;
        for (var i:Number = 0; i < expectedPts.length; i++) {
            var p1:Vector = expectedPts[i]; // 类型为 Vector
            var p2:Vector = actualPts[i];   // 类型为 Vector

            if (p1 == null || p2 == null) {
                 if (p1 !== p2) {
                     trace("  -> Assertion Failed: " + message + " (Point at index " + i + " null mismatch - Expected: " + p1 + ", Actual: " + p2 + ")");
                     // 不再继续比较此数组 (Stop comparing this array)
                     return;
                 }
                 continue; // Both null, continue
            }

            // 比较 x 和 y 坐标 (Compare x and y coordinates)
             var xDiff:Number = Math.abs(p1.x - p2.x);
             var yDiff:Number = Math.abs(p1.y - p2.y);

             if (xDiff > tolerance || yDiff > tolerance) {
                 trace("  -> Assertion Failed: " + message + " (Point at index " + i + " differs - Expected: (" + p1.x + ", " + p1.y + "), Actual: (" + p2.x + ", " + p2.y + "), Tolerance: " + tolerance + ", DiffX: " + xDiff + ", DiffY: " + yDiff + ")");
                 // 不再继续比较此数组 (Stop comparing this array)
                 return;
             }
        }
        // 如果循环完成没有失败，则数组相等 (If loop completes without failures, arrays are equal)
    }

} // End of class SmoothingUtilTest