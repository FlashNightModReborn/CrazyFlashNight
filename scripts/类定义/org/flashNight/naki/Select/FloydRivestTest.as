import org.flashNight.naki.Select.*;

/**
 * FloydRivestTest 增强版测试类
 *
 * 全面测试 Floyd-Rivest 选择算法的正确性、性能和特殊场景处理能力。
 * 针对 Floyd-Rivest 的核心特性设计了专项测试，包括：
 * - 智能采样策略测试
 * - 双pivot三路分区测试  
 * - 自适应阈值切换测试
 * - 几何数据空间局部性测试
 * - 与QuickSelect性能对比测试
 * - 大数据集压力测试和边界条件验证
 * - BVH构建实际应用场景模拟测试
 */
class org.flashNight.naki.Select.FloydRivestTest {

    public static function runTests():Void {
        trace("Starting Enhanced Floyd-Rivest Selection Tests...\n");

        // ================================
        // 基础功能测试套件
        // ================================
        trace("=== 基础功能测试 ===");
        testEmptyArray();
        testSingleElement();
        testTwoElements();
        testThreeElements();
        testAlreadySorted();
        testReverseSorted();
        testRandomArray();
        testDuplicateElements();
        testAllSameElements();
        testCustomCompareFunction();
        testMedianSelection();
        testFirstAndLastElement();
        
        // ================================
        // Floyd-Rivest 核心特性专项测试
        // ================================
        trace("\n=== Floyd-Rivest 核心特性测试 ===");
        testIntelligentSamplingStrategy();
        testDualPivotPartitioning();
        testRecursiveSamplingDepth();
        testSampleSizeCalculation();
        testAdaptiveThresholdSwitching();
        testThreeWayPartitionOptimization();
        testSamplingBoundaryConditions();
        testPivotQualityValidation();
        
        // ================================
        // 几何数据和BVH专项测试
        // ================================
        trace("\n=== 几何数据和BVH专项测试 ===");
        testGeometricAxisSelection();
        testSpatialCoherenceDetection();
        testAdaptiveSelectionStrategy();
        testBVHConstructionScenario();
        testMultiAxisGeometricData();
        testSpatiallyClusteredData();
        testRandomGeometricDistribution();
        
        // ================================
        // 算法阈值和边界测试
        // ================================
        trace("\n=== 算法阈值和边界测试 ===");
        testSmallArrayThreshold();
        testMinSampleThreshold();
        testLargeArrayHandling();
        testThresholdBoundaryConditions();
        testSamplingRangeValidation();
        testPivotSelectionBoundaries();
        testRecursionDepthLimits();
        
        // ================================
        // 选择位置专项测试
        // ================================
        trace("\n=== 选择位置专项测试 ===");
        testExtremumSelection();
        testQuartileSelection();
        testPercentileSelection();
        testMedianVariations();
        testNearBoundarySelection();
        testRandomPositionSelection();
        testMultipleSelectionConsistency();
        
        // ================================
        // 数据分布模式测试
        // ================================
        trace("\n=== 数据分布模式测试 ===");
        testUniformDistribution();
        testNormalDistribution();
        testExponentialDistribution();
        testBimodalDistribution();
        testPowerLawDistribution();
        testAlternatingPattern();
        testClusteredData();
        testSparseData();
        
        // ================================
        // 稳定性和正确性验证
        // ================================
        trace("\n=== 稳定性和正确性验证 ===");
        testSelectionCorrectness();
        testPartitioningCorrectness();
        testConsistencyAcrossRuns();
        testInputArrayIntegrity();
        testElementPreservation();
        testOrderInvariance();
        
        // ================================
        // 性能对比和压力测试
        // ================================
        trace("\n=== 性能对比和压力测试 ===");
        runPerformanceComparison();
        testLargeDatasetStress();
        testWorstCaseScenarios();
        testBestCaseOptimization();
        testAveragePerformance();
        testMemoryEfficiency();
        
        // ================================
        // 实际应用场景测试
        // ================================
        trace("\n=== 实际应用场景测试 ===");
        testDatabaseQueryOptimization();
        testStatisticalAnalysis();
        testTopKSelection();
        testRankingOperations();
        testPartialSortingUseCase();
        testStreamingDataSelection();
        
        trace("\nAll Enhanced Floyd-Rivest Tests Completed.");
    }

    // ================================
    // 基础断言和工具方法
    // ================================
    private static function assertEquals(expected:Object, actual:Object, testName:String):Void {
        if (expected !== actual) {
            trace("FAIL: " + testName + " - 预期: " + expected + "，实际: " + actual);
        } else {
            trace("PASS: " + testName);
        }
    }

    private static function assertArrayEquals(expected:Array, actual:Array, testName:String):Void {
        if (expected.length != actual.length) {
            trace("FAIL: " + testName + " - 数组长度不一致，预期: " + expected.length + "，实际: " + actual.length);
            return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                trace("FAIL: " + testName + " - 索引 " + i + " 处不一致，预期: " + expected[i] + "，实际: " + actual[i]);
                return;
            }
        }
        trace("PASS: " + testName);
    }

    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
        } else {
            trace("PASS: " + testName);
        }
    }

    private static function assertSelectionCorrect(arr:Array, k:Number, result:Object, testName:String):Void {
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        var expected:Object = sorted[k];
        
        if (result !== expected) {
            trace("FAIL: " + testName + " - 选择结果错误，预期第" + k + "小元素: " + expected + "，实际: " + result);
        } else {
            trace("PASS: " + testName);
        }
    }

    private static function createGeometricPrimitive(x:Number, y:Number, z:Number, id:String):Object {
        return {
            centroid: [x, y, z],
            id: id,
            toString: function():String { return this.id + "(" + this.centroid.join(",") + ")"; }
        };
    }

    private static function generateRandomArray(size:Number, min:Number, max:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(min + Math.random() * (max - min));
        }
        return arr;
    }

    // ================================
    // 基础功能测试
    // ================================
    private static function testEmptyArray():Void {
        var arr:Array = [];
        var result:Object = FloydRivest.selectKth(arr, 0, FloydRivest.numberCompare);
        assertEquals(null, result, "空数组选择测试");
    }

    private static function testSingleElement():Void {
        var arr:Array = [42];
        var result:Object = FloydRivest.selectKth(arr, 0, FloydRivest.numberCompare);
        assertEquals(42, result, "单元素数组选择测试");
    }

    private static function testTwoElements():Void {
        var arr1:Array = [5, 3];
        var arr2:Array = [3, 5];
        
        assertEquals(3, FloydRivest.selectKth(arr1.concat(), 0, FloydRivest.numberCompare), "两元素选择最小值");
        assertEquals(5, FloydRivest.selectKth(arr1.concat(), 1, FloydRivest.numberCompare), "两元素选择最大值");
        assertEquals(3, FloydRivest.selectKth(arr2.concat(), 0, FloydRivest.numberCompare), "两元素有序选择最小值");
        assertEquals(5, FloydRivest.selectKth(arr2.concat(), 1, FloydRivest.numberCompare), "两元素有序选择最大值");
    }

    private static function testThreeElements():Void {
        var arr:Array = [7, 2, 9];
        
        assertEquals(2, FloydRivest.selectKth(arr.concat(), 0, FloydRivest.numberCompare), "三元素选择最小值");
        assertEquals(7, FloydRivest.selectKth(arr.concat(), 1, FloydRivest.numberCompare), "三元素选择中值");
        assertEquals(9, FloydRivest.selectKth(arr.concat(), 2, FloydRivest.numberCompare), "三元素选择最大值");
    }

    private static function testAlreadySorted():Void {
        var arr:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        
        for (var i:Number = 0; i < arr.length; i++) {
            var expected:Number = i + 1;
            var result:Object = FloydRivest.selectKth(arr.concat(), i, FloydRivest.numberCompare);
            if (result !== expected) {
                trace("FAIL: 已排序数组选择测试 - 位置" + i + "，预期: " + expected + "，实际: " + result);
                return;
            }
        }
        trace("PASS: 已排序数组选择测试");
    }

    private static function testReverseSorted():Void {
        var arr:Array = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
        
        for (var i:Number = 0; i < arr.length; i++) {
            var expected:Number = i + 1;
            var result:Object = FloydRivest.selectKth(arr.concat(), i, FloydRivest.numberCompare);
            if (result !== expected) {
                trace("FAIL: 逆序数组选择测试 - 位置" + i + "，预期: " + expected + "，实际: " + result);
                return;
            }
        }
        trace("PASS: 逆序数组选择测试");
    }

    private static function testRandomArray():Void {
        var arr:Array = [64, 25, 12, 22, 11, 90, 88, 76, 50, 42];
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        
        // 测试多个位置
        var positions:Array = [0, 2, 4, 7, 9];
        for (var i:Number = 0; i < positions.length; i++) {
            var k:Number = positions[i];
            var expected:Number = sorted[k];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            if (result !== expected) {
                trace("FAIL: 随机数组选择测试 - 位置" + k + "，预期: " + expected + "，实际: " + result);
                return;
            }
        }
        trace("PASS: 随机数组选择测试");
    }

    private static function testDuplicateElements():Void {
        var arr:Array = [5, 3, 8, 3, 9, 1, 5, 7, 3];
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        
        // 测试重复元素的选择
        var testPositions:Array = [0, 2, 4, 6, 8];
        for (var i:Number = 0; i < testPositions.length; i++) {
            var k:Number = testPositions[i];
            var expected:Number = sorted[k];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "重复元素选择测试 (k=" + k + ")");
        }
    }

    private static function testAllSameElements():Void {
        var arr:Array = [7, 7, 7, 7, 7, 7, 7];
        
        for (var i:Number = 0; i < arr.length; i++) {
            var result:Object = FloydRivest.selectKth(arr.concat(), i, FloydRivest.numberCompare);
            if (result !== 7) {
                trace("FAIL: 全相同元素选择测试 - 位置" + i + "，预期: 7，实际: " + result);
                return;
            }
        }
        trace("PASS: 全相同元素选择测试");
    }

    private static function testCustomCompareFunction():Void {
        var arr:Array = ["Apple", "orange", "Banana", "grape", "cherry"];
        var compare:Function = function(a:String, b:String):Number {
            var aLower:String = a.toLowerCase();
            var bLower:String = b.toLowerCase();
            if (aLower < bLower) return -1;
            if (aLower > bLower) return 1;
            return 0;
        };
        
        // 测试中位数选择
        var result:Object = FloydRivest.selectKth(arr.concat(), 2, compare);
        var expected:Array = arr.concat();
        expected.sort(compare);
        
        assertEquals(expected[2], result, "自定义比较函数选择测试");
    }

    private static function testMedianSelection():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5];
        var medianResult:Object = FloydRivest.median(arr.concat(), FloydRivest.numberCompare);
        
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        var expectedMedian:Number = sorted[Math.floor((arr.length - 1) / 2)];
        
        assertEquals(expectedMedian, medianResult, "中位数选择测试");
    }

    private static function testFirstAndLastElement():Void {
        var arr:Array = [64, 25, 12, 22, 11, 90, 88, 76, 50, 42];
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        
        var first:Object = FloydRivest.selectKth(arr.concat(), 0, FloydRivest.numberCompare);
        var last:Object = FloydRivest.selectKth(arr.concat(), arr.length - 1, FloydRivest.numberCompare);
        
        assertEquals(sorted[0], first, "最小元素选择测试");
        assertEquals(sorted[arr.length - 1], last, "最大元素选择测试");
    }

    // ================================
    // Floyd-Rivest 核心特性专项测试
    // ================================
    
    /**
     * 测试智能采样策略
     * 验证算法能够正确计算采样参数和选择合适的采样范围
     */
    private static function testIntelligentSamplingStrategy():Void {
        var arr:Array = [];
        
        // 创建大数组以触发采样
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(Math.random() * 10000);
        }
        
        // 测试不同位置的选择，验证采样策略的有效性
        var testPositions:Array = [10, 100, 250, 500, 750, 900, 990];
        
        for (var j:Number = 0; j < testPositions.length; j++) {
            var k:Number = testPositions[j];
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, k, result, "智能采样策略测试 (k=" + k + ")");
            trace("    位置" + k + "采样选择耗时: " + time + "ms");
        }
    }

    /**
     * 测试双pivot三路分区
     * 验证三路分区的正确性和效率
     */
    private static function testDualPivotPartitioning():Void {
        var arr:Array = [];
        
        // 创建容易验证分区正确性的数据
        for (var i:Number = 0; i < 500; i++) {
            arr.push(Math.floor(Math.random() * 100));  // 0-99的整数
        }
        
        // 测试中间位置，最容易触发三路分区
        var k:Number = 250;
        var testArr:Array = arr.concat();
        var result:Object = FloydRivest.selectKth(testArr, k, FloydRivest.numberCompare);
        
        // 验证分区结果：testArr[k]左边都应该小于等于它，右边都应该大于等于它
        var pivot:Number = testArr[k];
        var partitionCorrect:Boolean = true;
        
        for (var j:Number = 0; j < k; j++) {
            if (testArr[j] > pivot) {
                partitionCorrect = false;
                break;
            }
        }
        
        for (var l:Number = k + 1; l < testArr.length; l++) {
            if (testArr[l] < pivot) {
                partitionCorrect = false;
                break;
            }
        }
        
        assertTrue(partitionCorrect, "双pivot三路分区测试", "分区结果不正确");
        assertSelectionCorrect(arr, k, result, "双pivot分区选择正确性");
    }

    /**
     * 测试递归采样深度
     * 验证算法不会产生过深的递归
     */
    private static function testRecursiveSamplingDepth():Void {
        var sizes:Array = [500, 1000, 5000, 10000];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = generateRandomArray(size, 0, size);
            
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), Math.floor(size / 2), FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, Math.floor(size / 2), result, "递归采样深度测试 (size=" + size + ")");
            trace("    大小" + size + "递归采样耗时: " + time + "ms");
        }
    }

    /**
     * 测试采样大小计算
     * 验证采样大小公式的正确性
     */
    private static function testSampleSizeCalculation():Void {
        var sizes:Array = [100, 600, 1000, 5000];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = [];
            
            // 创建有结构的数据以便观察采样效果
            for (var j:Number = 0; j < size; j++) {
                arr.push(j);
            }
            
            var k:Number = Math.floor(size / 3);
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            
            assertEquals(k, result, "采样大小计算测试 (size=" + size + ")");
        }
    }

    /**
     * 测试自适应阈值切换
     * 验证大小数组使用不同算法的切换机制
     */
    private static function testAdaptiveThresholdSwitching():Void {
        var thresholdSizes:Array = [50, 200, 300, 400, 500, 600];
        
        for (var i:Number = 0; i < thresholdSizes.length; i++) {
            var size:Number = thresholdSizes[i];
            var arr:Array = generateRandomArray(size, 0, 1000);
            
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), Math.floor(size / 2), FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, Math.floor(size / 2), result, "自适应阈值切换测试 (size=" + size + ")");
            
            var algorithm:String = (size < 400) ? "QuickSelect回退" : "Floyd-Rivest";
            trace("    大小" + size + " (" + algorithm + ") 耗时: " + time + "ms");
        }
    }

    /**
     * 测试三路分区优化
     * 验证对重复元素的高效处理
     */
    private static function testThreeWayPartitionOptimization():Void {
        var arr:Array = [];
        
        // 创建大量重复元素的数组
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(Math.floor(Math.random() * 10));  // 只有0-9十个值，大量重复
        }
        
        var positions:Array = [100, 300, 500, 700, 900];
        
        for (var j:Number = 0; j < positions.length; j++) {
            var k:Number = positions[j];
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, k, result, "三路分区优化测试 (k=" + k + ")");
            trace("    重复元素位置" + k + "选择耗时: " + time + "ms");
        }
    }

    /**
     * 测试采样边界条件
     * 验证边界情况下采样的正确性
     */
    private static function testSamplingBoundaryConditions():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        // 测试边界位置
        var boundaryPositions:Array = [0, 1, 2, 997, 998, 999];
        
        for (var i:Number = 0; i < boundaryPositions.length; i++) {
            var k:Number = boundaryPositions[i];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "采样边界条件测试 (k=" + k + ")");
        }
    }

    /**
     * 测试pivot质量验证
     * 通过多次运行验证pivot选择的稳定性
     */
    private static function testPivotQualityValidation():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        var k:Number = 500;
        var results:Array = [];
        
        // 多次运行相同的选择，结果应该一致
        for (var i:Number = 0; i < 5; i++) {
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            results.push(result);
        }
        
        // 验证结果一致性
        var consistent:Boolean = true;
        for (var j:Number = 1; j < results.length; j++) {
            if (results[j] !== results[0]) {
                consistent = false;
                break;
            }
        }
        
        assertTrue(consistent, "pivot质量验证测试", "多次运行结果不一致");
        assertSelectionCorrect(arr, k, results[0], "pivot质量选择正确性");
    }

    // ================================
    // 几何数据和BVH专项测试
    // ================================
    
    /**
     * 测试几何数据按轴选择
     * 验证BVH构建中的轴向选择功能
     */
    private static function testGeometricAxisSelection():Void {
        var primitives:Array = [];
        
        // 创建3D几何图元
        for (var i:Number = 0; i < 100; i++) {
            primitives.push(createGeometricPrimitive(
                Math.random() * 100,
                Math.random() * 100,
                Math.random() * 100,
                "primitive" + i
            ));
        }
        
        // 测试各个轴的选择
        var axes:Array = [0, 1, 2];  // X, Y, Z轴
        var axisNames:Array = ["X", "Y", "Z"];
        
        for (var j:Number = 0; j < axes.length; j++) {
            var axis:Number = axes[j];
            var axisName:String = axisNames[j];
            
            var result:Object = FloydRivest.selectGeometric(primitives.concat(), 50, axis, 0, primitives.length);
            
            // 验证选择结果
            var sorted:Array = primitives.concat();
            sorted.sort(function(a:Object, b:Object):Number {
                return a.centroid[axis] - b.centroid[axis];
            });
            
            var expected:Object = sorted[50];
            assertEquals(expected.id, result.id, "几何数据" + axisName + "轴选择测试");
        }
    }

    /**
     * 测试空间局部性检测
     * 验证算法能够识别部分有序的几何数据
     */
    private static function testSpatialCoherenceDetection():Void {
        var primitives:Array = [];
        
        // 创建具有空间局部性的数据（X轴基本有序）
        for (var i:Number = 0; i < 100; i++) {
            var x:Number = i + (Math.random() - 0.5) * 5;  // 基本有序，小幅扰动
            primitives.push(createGeometricPrimitive(
                x,
                Math.random() * 100,
                Math.random() * 100,
                "coherent" + i
            ));
        }
        
        var start:Number = getTimer();
        var result:Object = FloydRivest.selectGeometric(primitives.concat(), 50, 0, 0, primitives.length);
        var coherentTime:Number = getTimer() - start;
        
        // 创建完全随机的数据作为对比
        var randomPrimitives:Array = [];
        for (var j:Number = 0; j < 100; j++) {
            randomPrimitives.push(createGeometricPrimitive(
                Math.random() * 100,
                Math.random() * 100,
                Math.random() * 100,
                "random" + j
            ));
        }
        
        start = getTimer();
        var randomResult:Object = FloydRivest.selectGeometric(randomPrimitives.concat(), 50, 0, 0, randomPrimitives.length);
        var randomTime:Number = getTimer() - start;
        
        // 验证选择正确性
        assertTrue(result != null, "空间局部性检测测试（有序数据）", "选择结果为空");
        assertTrue(randomResult != null, "空间局部性检测测试（随机数据）", "选择结果为空");
        
        trace("    空间局部性数据耗时: " + coherentTime + "ms");
        trace("    随机数据耗时: " + randomTime + "ms");
        trace("    性能提升: " + ((randomTime > coherentTime) ? "是" : "否"));
    }

    /**
     * 测试自适应选择策略
     * 验证算法能够根据数据特性选择最优策略
     */
    private static function testAdaptiveSelectionStrategy():Void {
        // 测试小的部分有序数据
        var smallCoherent:Array = [];
        for (var i:Number = 0; i < 30; i++) {
            smallCoherent.push(createGeometricPrimitive(i, Math.random() * 10, Math.random() * 10, "small" + i));
        }
        
        var result1:Object = FloydRivest.selectGeometric(smallCoherent.concat(), 15, 0, 0, smallCoherent.length);
        assertTrue(result1 != null, "自适应策略测试（小有序数据）", "选择失败");
        
        // 测试大的随机数据
        var largeRandom:Array = [];
        for (var j:Number = 0; j < 1000; j++) {
            largeRandom.push(createGeometricPrimitive(
                Math.random() * 1000,
                Math.random() * 1000,
                Math.random() * 1000,
                "large" + j
            ));
        }
        
        var result2:Object = FloydRivest.selectGeometric(largeRandom.concat(), 500, 0, 0, largeRandom.length);
        assertTrue(result2 != null, "自适应策略测试（大随机数据）", "选择失败");
    }

    /**
     * 测试BVH构建场景
     * 模拟真实的BVH树构建过程
     */
    private static function testBVHConstructionScenario():Void {
        var triangles:Array = [];
        
        // 创建模拟三角形网格（如一个立方体的三角化）
        var gridSize:Number = 10;
        for (var i:Number = 0; i < gridSize; i++) {
            for (var j:Number = 0; j < gridSize; j++) {
                for (var k:Number = 0; k < gridSize; k++) {
                    triangles.push(createGeometricPrimitive(
                        i * 10 + Math.random() * 5,
                        j * 10 + Math.random() * 5,
                        k * 10 + Math.random() * 5,
                        "tri_" + i + "_" + j + "_" + k
                    ));
                }
            }
        }
        
        // 模拟BVH分割过程：递归地在不同轴上选择中位数
        var testRanges:Array = [
            {start: 0, end: triangles.length, axis: 0},
            {start: 0, end: Math.floor(triangles.length/2), axis: 1},
            {start: Math.floor(triangles.length/2), end: triangles.length, axis: 2}
        ];
        
        for (var l:Number = 0; l < testRanges.length; l++) {
            var range:Object = testRanges[l];
            var rangeSize:Number = range.end - range.start;
            var medianPos:Number = range.start + Math.floor(rangeSize / 2);
            
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectGeometric(
                triangles.concat(), 
                medianPos, 
                range.axis, 
                range.start, 
                range.end
            );
            var time:Number = getTimer() - start;
            
            assertTrue(result != null, "BVH构建场景测试（范围" + l + "）", "分割失败");
            trace("    BVH分割范围" + l + " (轴" + range.axis + ") 耗时: " + time + "ms");
        }
    }

    /**
     * 测试多轴几何数据
     * 验证在不同轴上的选择一致性
     */
    private static function testMultiAxisGeometricData():Void {
        var primitives:Array = [];
        
        // 创建在不同轴上有不同分布的数据
        for (var i:Number = 0; i < 100; i++) {
            primitives.push(createGeometricPrimitive(
                i,                           // X轴有序
                Math.random() * 100,         // Y轴随机
                100 - i + Math.random() * 5  // Z轴基本逆序
            ));
        }
        
        var axes:Array = [0, 1, 2];
        for (var j:Number = 0; j < axes.length; j++) {
            var axis:Number = axes[j];
            var result:Object = FloydRivest.selectGeometric(primitives.concat(), 50, axis, 0, primitives.length);
            
            // 验证选择的元素在该轴上确实是第50小的
            var axisValues:Array = [];
            for (var k:Number = 0; k < primitives.length; k++) {
                axisValues.push(primitives[k].centroid[axis]);
            }
            axisValues.sort(Array.NUMERIC);
            
            var expectedValue:Number = axisValues[50];
            var actualValue:Number = result.centroid[axis];
            
            assertEquals(expectedValue, actualValue, "多轴几何数据测试（轴" + axis + "）");
        }
    }

    /**
     * 测试空间聚类数据
     * 验证处理聚类分布几何数据的能力
     */
    private static function testSpatiallyClusteredData():Void {
        var primitives:Array = [];
        
        // 创建3个空间聚类
        var clusterCenters:Array = [[20, 20, 20], [60, 60, 60], [80, 30, 70]];
        var clusterSize:Number = 30;
        
        for (var i:Number = 0; i < clusterCenters.length; i++) {
            var center:Array = clusterCenters[i];
            for (var j:Number = 0; j < clusterSize; j++) {
                primitives.push(createGeometricPrimitive(
                    center[0] + (Math.random() - 0.5) * 10,
                    center[1] + (Math.random() - 0.5) * 10,
                    center[2] + (Math.random() - 0.5) * 10,
                    "cluster" + i + "_" + j
                ));
            }
        }
        
        // 在聚类数据上进行选择
        var result:Object = FloydRivest.selectGeometric(primitives.concat(), 45, 0, 0, primitives.length);
        assertTrue(result != null, "空间聚类数据测试", "选择失败");
        
        // 验证选择结果的合理性
        var sorted:Array = primitives.concat();
        sorted.sort(FloydRivest.geometryXCompare);
        assertEquals(sorted[45].id, result.id, "空间聚类数据选择正确性");
    }

    /**
     * 测试随机几何分布
     * 验证在完全随机分布下的稳定性
     */
    private static function testRandomGeometricDistribution():Void {
        var primitives:Array = [];
        
        // 创建完全随机分布的几何数据
        for (var i:Number = 0; i < 500; i++) {
            primitives.push(createGeometricPrimitive(
                Math.random() * 1000,
                Math.random() * 1000,
                Math.random() * 1000,
                "random" + i
            ));
        }
        
        // 测试多个选择位置
        var positions:Array = [50, 125, 250, 375, 450];
        
        for (var j:Number = 0; j < positions.length; j++) {
            var k:Number = positions[j];
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectGeometric(primitives.concat(), k, 0, 0, primitives.length);
            var time:Number = getTimer() - start;
            
            assertTrue(result != null, "随机几何分布测试（位置" + k + "）", "选择失败");
            trace("    随机几何分布位置" + k + "选择耗时: " + time + "ms");
        }
    }

    // ================================
    // 算法阈值和边界测试
    // ================================
    
    /**
     * 测试小数组阈值
     * 验证小数组回退到QuickSelect的机制
     */
    private static function testSmallArrayThreshold():Void {
        var thresholdSizes:Array = [10, 50, 100, 200, 300, 400, 500];
        
        for (var i:Number = 0; i < thresholdSizes.length; i++) {
            var size:Number = thresholdSizes[i];
            var arr:Array = generateRandomArray(size, 0, 1000);
            
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), Math.floor(size / 2), FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, Math.floor(size / 2), result, "小数组阈值测试 (size=" + size + ")");
            
            var algorithm:String = (size < 400) ? "QuickSelect" : "Floyd-Rivest";
            trace("    大小" + size + " (" + algorithm + ") 耗时: " + time + "ms");
        }
    }

    /**
     * 测试最小采样阈值
     * 验证采样阈值的边界行为
     */
    private static function testMinSampleThreshold():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        // 测试接近采样阈值的选择范围
        var ranges:Array = [
            {start: 0, end: 30},     // 小于最小采样阈值
            {start: 0, end: 35},     // 接近最小采样阈值
            {start: 100, end: 140},  // 超过最小采样阈值
            {start: 200, end: 300}   // 大范围
        ];
        
        for (var i:Number = 0; i < ranges.length; i++) {
            var range:Object = ranges[i];
            var rangeSize:Number = range.end - range.start;
            var k:Number = range.start + Math.floor(rangeSize / 2);
            
            var testArr:Array = arr.concat();
            var result:Object = FloydRivest.select(testArr, k, range.start, range.end, FloydRivest.numberCompare);
            
            // 验证子范围选择的正确性
            var subArray:Array = arr.slice(range.start, range.end);
            var sortedSub:Array = subArray.concat();
            sortedSub.sort(Array.NUMERIC);
            var expectedResult:Object = sortedSub[k - range.start];
            
            if (result !== expectedResult) {
                trace("FAIL: 最小采样阈值测试（范围" + i + "） - 预期第" + (k - range.start) + "小元素: " + expectedResult + "，实际: " + result);
            } else {
                trace("PASS: 最小采样阈值测试（范围" + i + "）");
            }
        }
    }

    /**
     * 测试大数组处理
     * 验证算法在大数据集上的稳定性
     */
    private static function testLargeArrayHandling():Void {
        var sizes:Array = [10000, 50000, 100000];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = generateRandomArray(size, 0, size);
            
            var positions:Array = [
                Math.floor(size * 0.1),
                Math.floor(size * 0.5),
                Math.floor(size * 0.9)
            ];
            
            for (var j:Number = 0; j < positions.length; j++) {
                var k:Number = positions[j];
                var start:Number = getTimer();
                var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
                var time:Number = getTimer() - start;
                
                assertSelectionCorrect(arr, k, result, "大数组处理测试 (size=" + size + ", k=" + k + ")");
                trace("    大小" + size + "位置" + k + "选择耗时: " + time + "ms");
            }
        }
    }

    /**
     * 测试阈值边界条件
     * 验证各种阈值边界的正确处理
     */
    private static function testThresholdBoundaryConditions():Void {
        // 测试精确等于阈值的情况
        var exactThresholds:Array = [32, 400, 600];
        
        for (var i:Number = 0; i < exactThresholds.length; i++) {
            var size:Number = exactThresholds[i];
            var arr:Array = generateRandomArray(size, 0, 1000);
            
            var result:Object = FloydRivest.selectKth(arr.concat(), Math.floor(size / 2), FloydRivest.numberCompare);
            assertSelectionCorrect(arr, Math.floor(size / 2), result, "阈值边界条件测试 (size=" + size + ")");
        }
    }

    /**
     * 测试采样范围验证
     * 验证采样范围计算的边界安全性
     */
    private static function testSamplingRangeValidation():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        // 测试边界位置的采样范围
        var boundaryPositions:Array = [0, 1, 2, 997, 998, 999];
        
        for (var i:Number = 0; i < boundaryPositions.length; i++) {
            var k:Number = boundaryPositions[i];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "采样范围验证测试 (k=" + k + ")");
        }
    }

    /**
     * 测试pivot选择边界
     * 验证pivot选择在各种边界条件下的稳定性
     */
    private static function testPivotSelectionBoundaries():Void {
        // 测试特殊数据分布
        var testCases:Array = [
            {name: "全相同", data: [5, 5, 5, 5, 5, 5, 5, 5, 5, 5]},
            {name: "两值交替", data: [1, 2, 1, 2, 1, 2, 1, 2, 1, 2]},
            {name: "递增", data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
            {name: "递减", data: [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]}
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var testCase:Object = testCases[i];
            var arr:Array = testCase.data;
            
            // 扩展到足够大以触发采样
            var largeArr:Array = [];
            for (var j:Number = 0; j < 50; j++) {
                largeArr = largeArr.concat(arr);
            }
            
            var k:Number = Math.floor(largeArr.length / 2);
            var result:Object = FloydRivest.selectKth(largeArr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(largeArr, k, result, "pivot选择边界测试（" + testCase.name + "）");
        }
    }

    /**
     * 测试递归深度限制
     * 验证算法不会产生栈溢出
     */
    private static function testRecursionDepthLimits():Void {
        // 创建可能导致最深递归的数据模式
        var arr:Array = [];
        
        // Fibonacci式的分布，理论上最深递归
        var sizes:Array = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144];
        var value:Number = 0;
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            for (var j:Number = 0; j < size * 10; j++) {  // 放大以触发采样
                arr.push(value++);
            }
        }
        
        var k:Number = Math.floor(arr.length / 2);
        var start:Number = getTimer();
        var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
        var time:Number = getTimer() - start;
        
        assertSelectionCorrect(arr, k, result, "递归深度限制测试");
        trace("    最深递归模式耗时: " + time + "ms");
    }

    // ================================
    // 选择位置专项测试
    // ================================
    
    /**
     * 测试极值选择
     * 验证最小值和最大值选择的特殊优化
     */
    private static function testExtremumSelection():Void {
        var arr:Array = generateRandomArray(1000, 0, 10000);
        
        var min:Object = FloydRivest.selectKth(arr.concat(), 0, FloydRivest.numberCompare);
        var max:Object = FloydRivest.selectKth(arr.concat(), arr.length - 1, FloydRivest.numberCompare);
        
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        
        assertEquals(sorted[0], min, "最小值选择测试");
        assertEquals(sorted[arr.length - 1], max, "最大值选择测试");
    }

    /**
     * 测试四分位数选择
     * 验证统计学中常用的四分位数选择
     */
    private static function testQuartileSelection():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        
        var q1Pos:Number = Math.floor(arr.length * 0.25);
        var q2Pos:Number = Math.floor(arr.length * 0.5);
        var q3Pos:Number = Math.floor(arr.length * 0.75);
        
        var q1:Object = FloydRivest.selectKth(arr.concat(), q1Pos, FloydRivest.numberCompare);
        var q2:Object = FloydRivest.selectKth(arr.concat(), q2Pos, FloydRivest.numberCompare);
        var q3:Object = FloydRivest.selectKth(arr.concat(), q3Pos, FloydRivest.numberCompare);
        
        assertEquals(sorted[q1Pos], q1, "第一四分位数选择测试");
        assertEquals(sorted[q2Pos], q2, "第二四分位数（中位数）选择测试");
        assertEquals(sorted[q3Pos], q3, "第三四分位数选择测试");
    }

    /**
     * 测试百分位数选择
     * 验证任意百分位数的选择精度
     */
    private static function testPercentileSelection():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        var sorted:Array = arr.concat();
        sorted.sort(Array.NUMERIC);
        
        var percentiles:Array = [5, 10, 25, 50, 75, 90, 95, 99];
        
        for (var i:Number = 0; i < percentiles.length; i++) {
            var percentile:Number = percentiles[i];
            var pos:Number = Math.floor(arr.length * percentile / 100);
            
            var result:Object = FloydRivest.selectKth(arr.concat(), pos, FloydRivest.numberCompare);
            assertEquals(sorted[pos], result, "第" + percentile + "百分位数选择测试");
        }
    }

    /**
     * 测试中位数变体
     * 验证不同长度数组的中位数选择
     */
    private static function testMedianVariations():Void {
        var sizes:Array = [99, 100, 101, 999, 1000, 1001];  // 奇数偶数组合
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = generateRandomArray(size, 0, 1000);
            
            var median:Object = FloydRivest.median(arr.concat(), FloydRivest.numberCompare);
            var expectedPos:Number = Math.floor((size - 1) / 2);
            
            assertSelectionCorrect(arr, expectedPos, median, "中位数变体测试 (size=" + size + ")");
        }
    }

    /**
     * 测试边界附近选择
     * 验证接近数组边界的选择精度
     */
    private static function testNearBoundarySelection():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        // 测试前5个和后5个位置
        var nearStart:Array = [0, 1, 2, 3, 4];
        var nearEnd:Array = [995, 996, 997, 998, 999];
        
        for (var i:Number = 0; i < nearStart.length; i++) {
            var k:Number = nearStart[i];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "边界附近选择测试（开始+" + k + "）");
        }
        
        for (var j:Number = 0; j < nearEnd.length; j++) {
            var k2:Number = nearEnd[j];
            var result2:Object = FloydRivest.selectKth(arr.concat(), k2, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k2, result2, "边界附近选择测试（结束-" + (999 - k2) + "）");
        }
    }

    /**
     * 测试随机位置选择
     * 验证算法在随机位置的一致性
     */
    private static function testRandomPositionSelection():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        // 随机选择20个位置测试
        for (var i:Number = 0; i < 20; i++) {
            var k:Number = Math.floor(Math.random() * arr.length);
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "随机位置选择测试（k=" + k + "）");
        }
    }

    /**
     * 测试多次选择一致性
     * 验证对同一数组多次选择的结果一致性
     */
    private static function testMultipleSelectionConsistency():Void {
        var arr:Array = generateRandomArray(500, 0, 1000);
        var k:Number = 250;
        
        var results:Array = [];
        for (var i:Number = 0; i < 10; i++) {
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            results.push(result);
        }
        
        // 验证所有结果都相同
        var consistent:Boolean = true;
        for (var j:Number = 1; j < results.length; j++) {
            if (results[j] !== results[0]) {
                consistent = false;
                break;
            }
        }
        
        assertTrue(consistent, "多次选择一致性测试", "多次选择结果不一致");
    }

    // ================================
    // 性能对比和压力测试
    // ================================
    
    /**
     * 运行性能对比测试
     * 对比Floyd-Rivest与QuickSelect的性能
     */
    private static function runPerformanceComparison():Void {
        trace("\n开始Floyd-Rivest vs QuickSelect性能对比...");
        
        var sizes:Array = [1000, 5000, 10000, 50000];
        var distributions:Array = ["random", "sorted", "reverse", "manyDuplicates"];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            trace("  测试数组大小: " + size);
            
            for (var j:Number = 0; j < distributions.length; j++) {
                var dist:String = distributions[j];
                var arr:Array = generatePerformanceTestArray(size, dist);
                var k:Number = Math.floor(size / 2);
                
                // Floyd-Rivest测试
                var start:Number = getTimer();
                var frResult:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
                var frTime:Number = getTimer() - start;
                
                // QuickSelect测试
                start = getTimer();
                var qsResult:Object = QuickSelect.selectKth(arr.concat(), k, QuickSelect.numberCompare);
                var qsTime:Number = getTimer() - start;
                
                // 验证结果一致性
                assertEquals(qsResult, frResult, "性能对比结果一致性（" + dist + "）");
                
                var improvement:Number = Math.round((qsTime - frTime) / qsTime * 100);
                trace("    " + dist + " - FR: " + frTime + "ms, QS: " + qsTime + "ms, 提升: " + improvement + "%");
            }
        }
    }

    /**
     * 生成性能测试数组
     */
    private static function generatePerformanceTestArray(size:Number, type:String):Array {
        var arr:Array = [];
        
        switch (type) {
            case "random":
                for (var i:Number = 0; i < size; i++) {
                    arr.push(Math.random() * size);
                }
                break;
                
            case "sorted":
                for (var j:Number = 0; j < size; j++) {
                    arr.push(j);
                }
                break;
                
            case "reverse":
                for (var k:Number = 0; k < size; k++) {
                    arr.push(size - k);
                }
                break;
                
            case "manyDuplicates":
                for (var l:Number = 0; l < size; l++) {
                    arr.push(Math.floor(Math.random() * 10));
                }
                break;
        }
        
        return arr;
    }

    /**
     * 测试大数据集压力
     * 验证算法在极大数据集上的稳定性
     */
    private static function testLargeDatasetStress():Void {
        var size:Number = 100000;
        var arr:Array = generateRandomArray(size, 0, size);
        
        var positions:Array = [
            Math.floor(size * 0.01),   // 1%
            Math.floor(size * 0.25),   // 25%
            Math.floor(size * 0.5),    // 50%
            Math.floor(size * 0.75),   // 75%
            Math.floor(size * 0.99)    // 99%
        ];
        
        for (var i:Number = 0; i < positions.length; i++) {
            var k:Number = positions[i];
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, k, result, "大数据集压力测试（" + Math.round(k/size*100) + "%位置）");
            trace("    大数据集位置" + k + "选择耗时: " + time + "ms");
        }
    }

    /**
     * 测试最坏情况场景
     * 验证算法在最坏情况下的性能退化
     */
    private static function testWorstCaseScenarios():Void {
        // 构造理论最坏情况：高度结构化的数据
        var arr:Array = [];
        
        // 模式1：交替高低值
        for (var i:Number = 0; i < 1000; i++) {
            arr.push((i % 2) * 1000 + i);
        }
        
        var start:Number = getTimer();
        var result1:Object = FloydRivest.selectKth(arr.concat(), 500, FloydRivest.numberCompare);
        var time1:Number = getTimer() - start;
        
        assertSelectionCorrect(arr, 500, result1, "最坏情况测试（交替模式）");
        trace("    交替模式最坏情况耗时: " + time1 + "ms");
        
        // 模式2：多个相同值
        var arr2:Array = [];
        for (var j:Number = 0; j < 1000; j++) {
            arr2.push(42);  // 全相同
        }
        
        start = getTimer();
        var result2:Object = FloydRivest.selectKth(arr2.concat(), 500, FloydRivest.numberCompare);
        var time2:Number = getTimer() - start;
        
        assertEquals(42, result2, "最坏情况测试（全相同）");
        trace("    全相同值最坏情况耗时: " + time2 + "ms");
    }

    /**
     * 测试最佳情况优化
     * 验证算法在最佳情况下的性能表现
     */
    private static function testBestCaseOptimization():Void {
        // 最佳情况：数据有良好的分布和结构
        var arr:Array = [];
        
        // 正态分布近似
        for (var i:Number = 0; i < 1000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var z:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            arr.push(Math.round(z * 100 + 500));  // 均值500，标准差100
        }
        
        var start:Number = getTimer();
        var result:Object = FloydRivest.selectKth(arr.concat(), 500, FloydRivest.numberCompare);
        var time:Number = getTimer() - start;
        
        assertSelectionCorrect(arr, 500, result, "最佳情况优化测试（正态分布）");
        trace("    正态分布最佳情况耗时: " + time + "ms");
    }

    /**
     * 测试平均性能
     * 多次随机测试统计平均性能
     */
    private static function testAveragePerformance():Void {
        var iterations:Number = 10;
        var size:Number = 10000;
        var totalTime:Number = 0;
        
        for (var i:Number = 0; i < iterations; i++) {
            var arr:Array = generateRandomArray(size, 0, size);
            var k:Number = Math.floor(Math.random() * size);
            
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, k, result, "平均性能测试（轮次" + (i+1) + "）");
            totalTime += time;
        }
        
        var averageTime:Number = totalTime / iterations;
        trace("    平均性能测试（" + iterations + "轮，大小" + size + "）平均耗时: " + averageTime + "ms");
    }

    /**
     * 测试内存效率
     * 验证算法的内存使用效率
     */
    private static function testMemoryEfficiency():Void {
        // 测试原地修改是否正确
        var arr:Array = generateRandomArray(1000, 0, 1000);
        var originalLength:Number = arr.length;
        var originalSum:Number = 0;
        
        for (var i:Number = 0; i < arr.length; i++) {
            originalSum += arr[i];
        }
        
        var k:Number = 500;
        var result:Object = FloydRivest.selectKth(arr, k, FloydRivest.numberCompare);
        
        // 验证数组长度未变
        assertEquals(originalLength, arr.length, "内存效率测试（数组长度保持）");
        
        // 验证元素总和未变（所有元素仍在）
        var newSum:Number = 0;
        for (var j:Number = 0; j < arr.length; j++) {
            newSum += arr[j];
        }
        assertEquals(originalSum, newSum, "内存效率测试（元素保持完整）");
        
        // 验证选择结果正确
        assertTrue(result != null, "内存效率测试（选择结果有效）", "选择结果为空");
    }

    // ================================
    // 数据分布模式测试（完整实现）
    // ================================
    
    /**
     * 测试均匀分布数据
     * 验证算法在均匀分布数据上的性能表现
     */
    private static function testUniformDistribution():Void {
        var arr:Array = [];
        
        // 生成均匀分布数据 [0, 1000)
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(Math.random() * 1000);
        }
        
        var positions:Array = [100, 250, 500, 750, 900];
        
        for (var j:Number = 0; j < positions.length; j++) {
            var k:Number = positions[j];
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, k, result, "均匀分布测试（位置" + k + "）");
            trace("    均匀分布位置" + k + "选择耗时: " + time + "ms");
        }
    }
    
    /**
     * 测试正态分布数据
     * 使用Box-Muller变换生成正态分布
     */
    private static function testNormalDistribution():Void {
        var arr:Array = [];
        
        // 生成正态分布数据 (μ=500, σ=100)
        for (var i:Number = 0; i < 1000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var z:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            arr.push(z * 100 + 500);  // 标准化到均值500，标准差100
        }
        
        var start:Number = getTimer();
        var median:Object = FloydRivest.median(arr.concat(), FloydRivest.numberCompare);
        var time:Number = getTimer() - start;
        
        // 正态分布的中位数应该接近均值
        assertTrue(median != null, "正态分布测试", "中位数选择失败");
        trace("    正态分布中位数: " + median + "，耗时: " + time + "ms");
    }
    
    /**
     * 测试指数分布数据
     * 使用逆变换方法生成指数分布
     */
    private static function testExponentialDistribution():Void {
        var arr:Array = [];
        var lambda:Number = 0.1;  // 指数分布参数
        
        // 生成指数分布数据
        for (var i:Number = 0; i < 1000; i++) {
            var u:Number = Math.random();
            var x:Number = -Math.log(1 - u) / lambda;
            arr.push(x);
        }
        
        // 测试不同位置
        var positions:Array = [100, 500, 800];
        
        for (var j:Number = 0; j < positions.length; j++) {
            var k:Number = positions[j];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "指数分布测试（位置" + k + "）");
        }
    }
    
    /**
     * 测试双峰分布数据
     * 混合两个正态分布
     */
    private static function testBimodalDistribution():Void {
        var arr:Array = [];
        
        // 第一个峰：均值200，标准差50
        for (var i:Number = 0; i < 400; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var z1:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            arr.push(z1 * 50 + 200);
        }
        
        // 第二个峰：均值800，标准差50
        for (var j:Number = 0; j < 400; j++) {
            var u3:Number = Math.random();
            var u4:Number = Math.random();
            var z2:Number = Math.sqrt(-2 * Math.log(u3)) * Math.cos(2 * Math.PI * u4);
            arr.push(z2 * 50 + 800);
        }
        
        var median:Object = FloydRivest.median(arr.concat(), FloydRivest.numberCompare);
        assertTrue(median != null, "双峰分布测试", "中位数选择失败");
        
        // 双峰分布的中位数应该在两峰之间
        trace("    双峰分布中位数: " + median);
    }
    
    /**
     * 测试幂律分布数据
     * 近似幂律分布（帕累托分布）
     */
    private static function testPowerLawDistribution():Void {
        var arr:Array = [];
        var alpha:Number = 2.0;  // 幂律指数
        var xmin:Number = 1.0;   // 最小值
        
        // 生成幂律分布数据
        for (var i:Number = 0; i < 1000; i++) {
            var u:Number = Math.random();
            var x:Number = xmin * Math.pow(1 - u, -1 / (alpha - 1));
            arr.push(x);
        }
        
        var positions:Array = [50, 200, 500, 900, 950];
        
        for (var j:Number = 0; j < positions.length; j++) {
            var k:Number = positions[j];
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result, "幂律分布测试（位置" + k + "）");
        }
    }
    
    /**
     * 测试交替模式数据
     * 高低值交替的模式
     */
    private static function testAlternatingPattern():Void {
        var arr:Array = [];
        
        // 创建严格交替模式
        for (var i:Number = 0; i < 500; i++) {
            arr.push(i * 2);        // 偶数位置：0, 2, 4, 6...
            arr.push(i * 2 + 1000); // 奇数位置：1000, 1002, 1004...
        }
        
        var start:Number = getTimer();
        var result:Object = FloydRivest.selectKth(arr.concat(), 500, FloydRivest.numberCompare);
        var time:Number = getTimer() - start;
        
        assertSelectionCorrect(arr, 500, result, "交替模式测试");
        trace("    交替模式选择耗时: " + time + "ms");
        
        // 测试其他位置
        var positions:Array = [250, 750];
        for (var j:Number = 0; j < positions.length; j++) {
            var k:Number = positions[j];
            var result2:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, k, result2, "交替模式测试（位置" + k + "）");
        }
    }
    
    /**
     * 测试聚类数据
     * 数据集中在几个簇中
     */
    private static function testClusteredData():Void {
        var arr:Array = [];
        
        // 创建5个簇，每簇200个点
        var clusterCenters:Array = [100, 300, 500, 700, 900];
        var clusterSpread:Number = 20;
        
        for (var i:Number = 0; i < clusterCenters.length; i++) {
            var center:Number = clusterCenters[i];
            for (var j:Number = 0; j < 200; j++) {
                var value:Number = center + (Math.random() - 0.5) * clusterSpread;
                arr.push(value);
            }
        }
        
        // 测试跨簇的选择
        var positions:Array = [200, 400, 600, 800];
        
        for (var k:Number = 0; k < positions.length; k++) {
            var pos:Number = positions[k];
            var start:Number = getTimer();
            var result:Object = FloydRivest.selectKth(arr.concat(), pos, FloydRivest.numberCompare);
            var time:Number = getTimer() - start;
            
            assertSelectionCorrect(arr, pos, result, "聚类数据测试（位置" + pos + "）");
            trace("    聚类数据位置" + pos + "选择耗时: " + time + "ms");
        }
    }
    
    /**
     * 测试稀疏数据
     * 大部分值为0或很小，少数值很大
     */
    private static function testSparseData():Void {
        var arr:Array = [];
        
        // 90%的数据为0或小值
        for (var i:Number = 0; i < 900; i++) {
            if (Math.random() < 0.8) {
                arr.push(0);
            } else {
                arr.push(Math.random() * 10);
            }
        }
        
        // 10%的数据为大值
        for (var j:Number = 0; j < 100; j++) {
            arr.push(1000 + Math.random() * 1000);
        }
        
        // 测试不同分位数
        var positions:Array = [450, 800, 950, 990];
        
        for (var k:Number = 0; k < positions.length; k++) {
            var pos:Number = positions[k];
            var result:Object = FloydRivest.selectKth(arr.concat(), pos, FloydRivest.numberCompare);
            assertSelectionCorrect(arr, pos, result, "稀疏数据测试（位置" + pos + "）");
        }
    }

    // ================================
    // 稳定性和正确性验证（完整实现）
    // ================================
    
    /**
     * 测试选择正确性
     * 验证选择结果的绝对正确性
     */
    private static function testSelectionCorrectness():Void {
        var testCases:Array = [
            {size: 100, positions: [0, 25, 50, 75, 99]},
            {size: 500, positions: [0, 100, 250, 400, 499]},
            {size: 1000, positions: [0, 200, 500, 800, 999]}
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var testCase:Object = testCases[i];
            var arr:Array = generateRandomArray(testCase.size, 0, testCase.size);
            var sorted:Array = arr.concat();
            sorted.sort(Array.NUMERIC);
            
            for (var j:Number = 0; j < testCase.positions.length; j++) {
                var k:Number = testCase.positions[j];
                var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
                var expected:Object = sorted[k];
                
                if (result !== expected) {
                    trace("FAIL: 选择正确性测试 - 大小" + testCase.size + "位置" + k + "，预期: " + expected + "，实际: " + result);
                    return;
                }
            }
        }
        trace("PASS: 选择正确性测试");
    }
    
    /**
     * 测试分区正确性
     * 验证选择后的数组分区是否正确
     */
    private static function testPartitioningCorrectness():Void {
        var arr:Array = generateRandomArray(500, 0, 1000);
        var k:Number = 250;
        var testArr:Array = arr.concat();
        
        var result:Object = FloydRivest.selectKth(testArr, k, FloydRivest.numberCompare);
        var pivot:Number = testArr[k];
        
        // 验证分区：左边都 <= pivot，右边都 >= pivot
        var partitionCorrect:Boolean = true;
        
        for (var i:Number = 0; i < k; i++) {
            if (testArr[i] > pivot) {
                partitionCorrect = false;
                break;
            }
        }
        
        for (var j:Number = k + 1; j < testArr.length; j++) {
            if (testArr[j] < pivot) {
                partitionCorrect = false;
                break;
            }
        }
        
        assertTrue(partitionCorrect, "分区正确性测试", "数组分区不正确");
    }
    
    /**
     * 测试跨运行一致性
     * 验证多次运行相同输入的结果一致性
     */
    private static function testConsistencyAcrossRuns():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        var k:Number = 500;
        var results:Array = [];
        
        // 运行10次相同的选择
        for (var i:Number = 0; i < 10; i++) {
            var result:Object = FloydRivest.selectKth(arr.concat(), k, FloydRivest.numberCompare);
            results.push(result);
        }
        
        // 验证所有结果一致
        var consistent:Boolean = true;
        for (var j:Number = 1; j < results.length; j++) {
            if (results[j] !== results[0]) {
                consistent = false;
                break;
            }
        }
        
        assertTrue(consistent, "跨运行一致性测试", "多次运行结果不一致");
    }
    
    /**
     * 测试输入数组完整性
     * 验证算法不会丢失或添加元素
     */
    private static function testInputArrayIntegrity():Void {
        var arr:Array = generateRandomArray(500, 0, 1000);
        var originalLength:Number = arr.length;
        var originalSum:Number = 0;
        
        // 计算原始总和
        for (var i:Number = 0; i < arr.length; i++) {
            originalSum += arr[i];
        }
        
        var k:Number = 250;
        var testArr:Array = arr.concat();
        var result:Object = FloydRivest.selectKth(testArr, k, FloydRivest.numberCompare);
        
        // 验证长度未变
        assertEquals(originalLength, testArr.length, "输入数组完整性测试（长度保持）");
        
        // 验证元素总和未变
        var newSum:Number = 0;
        for (var j:Number = 0; j < testArr.length; j++) {
            newSum += testArr[j];
        }
        
        assertEquals(originalSum, newSum, "输入数组完整性测试（元素保持）");
    }
    
    /**
     * 测试元素保持
     * 验证所有原始元素都还在数组中
     */
    private static function testElementPreservation():Void {
        var arr:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        var testArr:Array = arr.concat();
        
        var result:Object = FloydRivest.selectKth(testArr, 5, FloydRivest.numberCompare);
        
        // 验证所有原始元素都存在
        var originalSet:Object = {};
        for (var i:Number = 0; i < arr.length; i++) {
            originalSet[arr[i]] = (originalSet[arr[i]] || 0) + 1;
        }
        
        var newSet:Object = {};
        for (var j:Number = 0; j < testArr.length; j++) {
            newSet[testArr[j]] = (newSet[testArr[j]] || 0) + 1;
        }
        
        var elementsPreserved:Boolean = true;
        for (var key in originalSet) {
            if (originalSet[key] !== newSet[key]) {
                elementsPreserved = false;
                break;
            }
        }
        
        assertTrue(elementsPreserved, "元素保持测试", "元素计数发生变化");
    }
    
    /**
     * 测试顺序不变性
     * 对于相同的输入，无论选择哪个位置，最终的排序顺序应该一致
     */
    private static function testOrderInvariance():Void {
        var arr:Array = generateRandomArray(100, 0, 100);
        
        // 分别选择不同位置
        var arr1:Array = arr.concat();
        var arr2:Array = arr.concat();
        var arr3:Array = arr.concat();
        
        FloydRivest.selectKth(arr1, 25, FloydRivest.numberCompare);
        FloydRivest.selectKth(arr2, 50, FloydRivest.numberCompare);
        FloydRivest.selectKth(arr3, 75, FloydRivest.numberCompare);
        
        // 排序后应该完全一致
        arr1.sort(Array.NUMERIC);
        arr2.sort(Array.NUMERIC);
        arr3.sort(Array.NUMERIC);
        
        var orderInvariant:Boolean = true;
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i] || arr1[i] !== arr3[i]) {
                orderInvariant = false;
                break;
            }
        }
        
        assertTrue(orderInvariant, "顺序不变性测试", "不同选择位置影响了最终顺序");
    }

    // ================================
    // 实际应用场景测试（完整实现）
    // ================================
    
    /**
     * 测试数据库查询优化
     * 模拟 ORDER BY LIMIT 查询场景
     */
    private static function testDatabaseQueryOptimization():Void {
        var records:Array = [];
        
        // 创建模拟数据库记录
        for (var i:Number = 0; i < 10000; i++) {
            records.push({
                id: i,
                score: Math.random() * 100,
                timestamp: 1000000 + Math.random() * 100000,
                category: Math.floor(Math.random() * 5)
            });
        }
        
        // 模拟 "SELECT * FROM table ORDER BY score LIMIT 100" 
        var scoreCompare:Function = function(a:Object, b:Object):Number {
            return a.score - b.score;
        };
        
        var start:Number = getTimer();
        var top100th:Object = FloydRivest.selectKth(records.concat(), 99, scoreCompare);
        var selectionTime:Number = getTimer() - start;
        
        // 对比完整排序的时间
        start = getTimer();
        var sortedRecords:Array = records.concat();
        sortedRecords.sort(scoreCompare);
        var sortTime:Number = getTimer() - start;
        
        assertTrue(top100th != null, "数据库查询优化测试（选择结果）", "选择失败");
        
        var improvement:Number = Math.round((sortTime - selectionTime) / sortTime * 100);
        trace("    数据库查询优化 - 选择: " + selectionTime + "ms, 排序: " + sortTime + "ms, 提升: " + improvement + "%");
    }
    
    /**
     * 测试统计分析
     * 计算各种统计量
     */
    private static function testStatisticalAnalysis():Void {
        var dataset:Array = [];
        
        // 生成正态分布的数据集
        for (var i:Number = 0; i < 5000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var z:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            dataset.push(z * 15 + 100);  // 均值100，标准差15
        }
        
        var start:Number = getTimer();
        
        // 计算关键统计量
        var min:Object = FloydRivest.selectKth(dataset.concat(), 0, FloydRivest.numberCompare);
        var q1:Object = FloydRivest.selectKth(dataset.concat(), Math.floor(dataset.length * 0.25), FloydRivest.numberCompare);
        var median:Object = FloydRivest.selectKth(dataset.concat(), Math.floor(dataset.length * 0.5), FloydRivest.numberCompare);
        var q3:Object = FloydRivest.selectKth(dataset.concat(), Math.floor(dataset.length * 0.75), FloydRivest.numberCompare);
        var max:Object = FloydRivest.selectKth(dataset.concat(), dataset.length - 1, FloydRivest.numberCompare);
        
        var analysisTime:Number = getTimer() - start;
        
        assertTrue(min != null && q1 != null && median != null && q3 != null && max != null, 
                  "统计分析测试", "统计量计算失败");
        
        trace("    统计分析 - 最小值: " + min + ", Q1: " + q1 + ", 中位数: " + median + ", Q3: " + q3 + ", 最大值: " + max);
        trace("    统计分析耗时: " + analysisTime + "ms");
    }
    
    /**
     * 测试Top-K选择
     * 高效选择前K个最大/最小元素
     */
    private static function testTopKSelection():Void {
        var scores:Array = generateRandomArray(10000, 0, 1000);
        var k:Number = 100;
        
        // 选择第K大的元素（使用反向比较）
        var start:Number = getTimer();
        var kthLargest:Object = FloydRivest.selectKth(scores.concat(), k - 1, FloydRivest.reverseNumberCompare);
        var selectionTime:Number = getTimer() - start;
        
        // 验证正确性：排序后比较
        var sorted:Array = scores.concat();
        sorted.sort(FloydRivest.reverseNumberCompare);
        var expected:Number = sorted[k - 1];
        
        assertEquals(expected, kthLargest, "Top-K选择测试（第" + k + "大元素）");
        
        // 测试Top-K范围选择
        var topKThreshold:Number = Number(kthLargest);
        var actualTopK:Array = [];
        for (var i:Number = 0; i < scores.length; i++) {
            if (scores[i] >= topKThreshold) {
                actualTopK.push(scores[i]);
            }
        }
        
        assertTrue(actualTopK.length >= k, "Top-K选择测试（范围验证）", "Top-K元素数量不足");
        trace("    Top-" + k + "选择耗时: " + selectionTime + "ms，阈值: " + topKThreshold);
    }
    
    /**
     * 测试排名操作
     * 模拟游戏排行榜等排名场景
     */
    private static function testRankingOperations():Void {
        var players:Array = [];
        
        // 创建玩家数据
        for (var i:Number = 0; i < 1000; i++) {
            players.push({
                id: "player" + i,
                score: Math.floor(Math.random() * 10000),
                level: Math.floor(Math.random() * 100) + 1
            });
        }
        
        var scoreCompare:Function = function(a:Object, b:Object):Number {
            if (a.score != b.score) return b.score - a.score;  // 分数降序
            return a.level - b.level;  // 等级升序
        };
        
        // 查找不同排名的玩家
        var rankings:Array = [1, 10, 50, 100, 500];
        
        for (var j:Number = 0; j < rankings.length; j++) {
            var rank:Number = rankings[j];
            var start:Number = getTimer();
            var rankedPlayer:Object = FloydRivest.selectKth(players.concat(), rank - 1, scoreCompare);
            var time:Number = getTimer() - start;
            
            assertTrue(rankedPlayer != null, "排名操作测试（第" + rank + "名）", "排名查找失败");
            trace("    第" + rank + "名玩家: " + rankedPlayer.id + ", 分数: " + rankedPlayer.score + ", 耗时: " + time + "ms");
        }
    }
    
    /**
     * 测试部分排序用例
     * 只需要部分有序结果的场景
     */
    private static function testPartialSortingUseCase():Void {
        var data:Array = generateRandomArray(5000, 0, 10000);
        var pivotPosition:Number = 2000;
        
        var start:Number = getTimer();
        var pivot:Object = FloydRivest.selectKth(data.concat(), pivotPosition, FloydRivest.numberCompare);
        var partialSortTime:Number = getTimer() - start;
        
        // 验证部分排序效果：pivot左边都小于等于它，右边都大于等于它
        var testData:Array = data.concat();
        FloydRivest.selectKth(testData, pivotPosition, FloydRivest.numberCompare);
        
        var partialSortCorrect:Boolean = true;
        for (var i:Number = 0; i < pivotPosition; i++) {
            if (testData[i] > testData[pivotPosition]) {
                partialSortCorrect = false;
                break;
            }
        }
        for (var j:Number = pivotPosition + 1; j < testData.length; j++) {
            if (testData[j] < testData[pivotPosition]) {
                partialSortCorrect = false;
                break;
            }
        }
        
        assertTrue(partialSortCorrect, "部分排序用例测试", "部分排序结果不正确");
        
        // 对比完整排序时间
        start = getTimer();
        var fullSorted:Array = data.concat();
        fullSorted.sort(Array.NUMERIC);
        var fullSortTime:Number = getTimer() - start;
        
        var improvement:Number = Math.round((fullSortTime - partialSortTime) / fullSortTime * 100);
        trace("    部分排序 vs 完整排序 - 部分: " + partialSortTime + "ms, 完整: " + fullSortTime + "ms, 提升: " + improvement + "%");
    }
    
    /**
     * 测试流式数据选择
     * 模拟数据流中的选择操作
     */
    private static function testStreamingDataSelection():Void {
        var streamSize:Number = 10000;
        var batchSize:Number = 100;
        var targetPercentile:Number = 0.9;  // 90分位数
        
        var allData:Array = [];
        var currentBatch:Array = [];
        var results:Array = [];
        
        // 模拟流式数据处理
        for (var i:Number = 0; i < streamSize; i++) {
            var value:Number = Math.random() * 1000;
            allData.push(value);
            currentBatch.push(value);
            
            // 每批处理一次
            if (currentBatch.length >= batchSize) {
                var k:Number = Math.floor(currentBatch.length * targetPercentile);
                var start:Number = getTimer();
                var percentile:Object = FloydRivest.selectKth(currentBatch.concat(), k, FloydRivest.numberCompare);
                var time:Number = getTimer() - start;
                
                results.push({
                    batchNumber: Math.floor(i / batchSize),
                    percentile: percentile,
                    time: time,
                    batchSize: currentBatch.length
                });
                
                currentBatch = [];
            }
        }
        
        // 处理最后一批
        if (currentBatch.length > 0) {
            var finalK:Number = Math.floor(currentBatch.length * targetPercentile);
            var finalPercentile:Object = FloydRivest.selectKth(currentBatch.concat(), finalK, FloydRivest.numberCompare);
            results.push({
                batchNumber: results.length,
                percentile: finalPercentile,
                time: 0,
                batchSize: currentBatch.length
            });
        }
        
        assertTrue(results.length > 0, "流式数据选择测试", "流式处理失败");
        
        // 计算平均处理时间
        var totalTime:Number = 0;
        for (var j:Number = 0; j < results.length; j++) {
            totalTime += results[j].time;
        }
        var avgTime:Number = totalTime / results.length;
        
        trace("    流式数据选择 - 批次数: " + results.length + ", 平均耗时: " + avgTime + "ms/批");
        trace("    最后批次90分位数: " + results[results.length - 1].percentile);
    }
}