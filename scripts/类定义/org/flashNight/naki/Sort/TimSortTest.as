import org.flashNight.naki.Sort.*;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * TimSortTest 增强版测试类
 *
 * 全面测试 TimSort 的正确性、性能和特殊场景处理能力。
 * 针对 TimSort 的核心特性设计了专项测试，包括：
 * - Galloping Mode 疾速模式测试
 * - 自然 run 检测和处理测试  
 * - 边界优化和堆栈不变量测试
 * - 稳定性深度验证测试
 * - 实际应用场景模拟测试
 * 
 * 改进说明：
 * - 使用 LinearCongruentialEngine 替代 Math.random()，确保测试结果可重现
 * - 通过固定种子消除随机性带来的数据波动
 * - 提高测试的可靠性和一致性
 */
class org.flashNight.naki.Sort.TimSortTest {
    
    // 可控的随机数生成器，确保测试结果可重现
    private static var rng:LinearCongruentialEngine;
    
    // 初始化随机数生成器，设置固定种子以确保可重现性
    private static function initRNG():Void {
        if (rng == null) {
            rng = LinearCongruentialEngine.getInstance();
            rng.init(1664525, 1013904223, 4294967296, 12345); // 设置固定种子12345
        }
    }
    
    // 重置随机数生成器种子，确保每个测试从相同状态开始
    private static function resetRNG(seed:Number):Void {
        if (rng != null) {
            rng.init(1664525, 1013904223, 4294967296, seed);
        }
    }

    public static function runTests():Void {
        trace("Starting Enhanced TimSort Tests...\n");
        
        // 初始化可控随机数生成器
        initRNG();

        // ================================
        // 基础功能测试套件
        // ================================
        trace("=== 基础功能测试 ===");
        testEmptyArray();
        testSingleElement();
        testAlreadySorted();
        testReverseSorted();
        testRandomArray();
        testDuplicateElements();
        testAllSameElements();
        testCustomCompareFunction();
        testTwoElements();
        testThreeElements();
        
        // ================================
        // TimSort 核心特性专项测试
        // ================================
        trace("\n=== TimSort 核心特性测试 ===");
        testGallopingModeActivation();
        testGallopingModeEfficiency();
        testGallopingModeDeactivation();
        testNaturalRunDetection();
        testRunReversalOptimization();
        testMinRunCalculation();
        testBoundaryOptimization();
        testStackInvariantMaintenance();
        
        // ================================
        // 稳定性深度测试
        // ================================
        trace("\n=== 稳定性深度测试 ===");
        testStabilityWithLargeDataset();
        testStabilityUnderGalloping();
        testStabilityWithComplexObjects();
        testStabilityInMultipleRuns();
        
        // ================================
        // 合并策略专项测试（增强版）
        // ================================
        trace("\n=== 合并策略专项测试 ===");
        testForceThreeRunMerge();
        testCascadeMerge();
        testStabilityMerge();
        testMergeBoundaryCondition();
        testMergeWithTinyRuns();
        testAsymmetricRunMerge();
        testMaximalStackDepth();
        
        // ================================
        // 实际应用场景测试
        // ================================
        trace("\n=== 实际应用场景测试 ===");
        testPartiallyOrderedData();
        testAlternatingPatterns();
        testPianoKeyPattern();
        testMostlyDuplicates();
        testOrganPipePattern();
        testRandomWalkPattern();
        testDatabaseStyleData();
        testTimeSeriesData();
        
        // ================================
        // 边界条件和压力测试
        // ================================
        trace("\n=== 边界条件和压力测试 ===");
        testMinRunBoundaries();
        testGallopThresholdBoundaries();
        testLargeArrayStressTest();
        testDeepRecursionAvoidance();
        testMemoryEfficiencyTest();
        
        // ================================
        // 性能测试（增强版）
        // ================================
        trace("\n=== 性能测试 ===");
        runEnhancedPerformanceTests();
        
        trace("\nAll Enhanced TimSort Tests Completed.");
    }

    // ================================
    // 基础断言和工具方法
    // ================================
    private static function assertEquals(expected:Array, actual:Array, testName:String):Void {
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

    private static function isSorted(arr:Array, compare:Function):Boolean {
        if (compare == null) {
            compare = function(a, b):Number { return a - b; };
        }
        for (var i:Number = 1; i < arr.length; i++) {
            if (compare(arr[i-1], arr[i]) > 0) {
                return false;
            }
        }
        return true;
    }

    private static function createStableObject(key:Number, id:String):Object {
        return {key: key, id: id, toString: function():String { return this.id + ":" + this.key; }};
    }

    // ================================
    // 基础功能测试
    // ================================
    private static function testEmptyArray():Void {
        var arr:Array = [];
        assertEquals(arr, TimSort.sort(arr, null), "空数组测试");
    }

    private static function testSingleElement():Void {
        var arr:Array = [42];
        assertEquals(arr, TimSort.sort(arr, null), "单元素数组测试");
    }

    private static function testTwoElements():Void {
        var arr1:Array = [2, 1];
        var arr2:Array = [1, 2];
        assertEquals([1, 2], TimSort.sort(arr1, null), "两元素数组测试（需要交换）");
        assertEquals([1, 2], TimSort.sort(arr2, null), "两元素数组测试（已有序）");
    }

    private static function testThreeElements():Void {
        var arr1:Array = [3, 1, 2];
        var arr2:Array = [1, 3, 2];
        var arr3:Array = [3, 2, 1];
        assertEquals([1, 2, 3], TimSort.sort(arr1, null), "三元素数组测试（随机）");
        assertEquals([1, 2, 3], TimSort.sort(arr2, null), "三元素数组测试（部分有序）");
        assertEquals([1, 2, 3], TimSort.sort(arr3, null), "三元素数组测试（完全逆序）");
    }

    private static function testAlreadySorted():Void {
        var arr:Array = [1,2,3,4,5,6,7,8,9,10];
        assertEquals(arr.concat(), TimSort.sort(arr.concat(), null), "已排序数组测试");
    }

    private static function testReverseSorted():Void {
        var arr:Array = [10,9,8,7,6,5,4,3,2,1];
        var expected:Array = arr.concat();
        expected.reverse();
        assertEquals(expected, TimSort.sort(arr, null), "逆序数组测试");
    }

    private static function testRandomArray():Void {
        var arr:Array = [3,1,4,1,5,9,2,6,5];
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        assertEquals(expected, TimSort.sort(arr, null), "随机数组测试");
    }

    private static function testDuplicateElements():Void {
        var arr:Array = [5,3,8,3,9,1,5,7,3];
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        assertEquals(expected, TimSort.sort(arr, null), "重复元素测试");
    }

    private static function testAllSameElements():Void {
        var arr:Array = [7,7,7,7,7,7,7];
        assertEquals(arr, TimSort.sort(arr, null), "全相同元素测试");
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
        
        var expected:Array = arr.concat();
        expected.sort(compare);
        assertEquals(expected, TimSort.sort(arr, compare), "自定义比较函数测试");
    }

    // ================================
    // TimSort 核心特性专项测试
    // ================================
    
    /**
     * 测试 Galloping Mode 的激活条件
     * 构造一个run A中有很多连续小元素，run B中有很多连续大元素的场景
     */
    private static function testGallopingModeActivation():Void {
        var arr:Array = [];
        // Run A: 1-20 (升序)
        for (var i:Number = 1; i <= 20; i++) {
            arr.push(i);
        }
        // Run B: 21-40 (降序，会被反转)
        for (var j:Number = 40; j >= 21; j--) {
            arr.push(j);
        }
        
        var expected:Array = [];
        for (var k:Number = 1; k <= 40; k++) {
            expected.push(k);
        }
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Galloping Mode 激活测试");
    }

    /**
     * 测试 Galloping Mode 在高度结构化数据上的效率
     */
    private static function testGallopingModeEfficiency():Void {
        var arr:Array = [];
        // 创建交替的大块run，应该触发galloping
        for (var block:Number = 0; block < 5; block++) {
            var base:Number = block * 100;
            // 每个块内部有序，块间有序
            for (var i:Number = 0; i < 50; i++) {
                arr.push(base + i);
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var start:Number = getTimer();
        var sorted:Array = TimSort.sort(arr, null);
        var time:Number = getTimer() - start;
        
        assertEquals(expected, sorted, "Galloping Mode 效率测试");
        trace("    Galloping效率测试耗时: " + time + "ms");
    }

    /**
     * 测试 Galloping Mode 的动态阈值调整
     */
    private static function testGallopingModeDeactivation():Void {
        var arr:Array = [];
        // 创建不利于galloping的交替模式
        for (var i:Number = 0; i < 50; i++) {
            arr.push(i * 2);      // 偶数
            arr.push(i * 2 + 1);  // 奇数
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Galloping Mode 自适应阈值测试");
    }

    /**
     * 测试自然run的检测能力
     */
    private static function testNaturalRunDetection():Void {
        var arr:Array = [];
        // 多个自然有序的片段
        arr = arr.concat([1,2,3,4,5]);           // 升序run
        arr = arr.concat([10,9,8,7,6]);          // 降序run（会被反转）
        arr = arr.concat([15,16,17,18,19,20]);   // 升序run
        arr = arr.concat([30,25,20]);            // 降序run（会被反转）
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "自然run检测测试");
    }

    /**
     * 测试降序run的反转优化
     */
    private static function testRunReversalOptimization():Void {
        var arr:Array = [];
        // 构造多个降序run
        for (var i:Number = 0; i < 5; i++) {
            var base:Number = i * 10;
            for (var j:Number = 9; j >= 0; j--) {
                arr.push(base + j);
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "降序run反转优化测试");
    }

    /**
     * 测试MIN_RUN的动态计算
     */
    private static function testMinRunCalculation():Void {
        // 测试不同大小数组的MIN_RUN计算是否合理
        var sizes:Array = [31, 32, 63, 64, 127, 128, 255, 256];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = [];
            
            // 创建随机数组
            for (var j:Number = 0; j < size; j++) {
                arr.push(rng.nextFloat() * 1000);
            }
            
            var expected:Array = arr.concat();
            expected.sort(Array.NUMERIC);
            
            var sorted:Array = TimSort.sort(arr.concat(), null);
            assertEquals(expected, sorted, "MIN_RUN计算测试 (size=" + size + ")");
        }
    }

    /**
     * 测试二分搜索边界优化
     */
    private static function testBoundaryOptimization():Void {
        var arr:Array = [];
        // Run A: 1-100
        for (var i:Number = 1; i <= 100; i++) {
            arr.push(i);
        }
        // Run B: 150-200（与A完全分离，应该触发边界优化）
        for (var j:Number = 150; j <= 200; j++) {
            arr.push(j);
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "边界优化测试（完全分离的run）");
        
        // 测试部分重叠的情况
        var arr2:Array = [];
        // Run A: 1-100
        for (var k:Number = 1; k <= 100; k++) {
            arr2.push(k);
        }
        // Run B: 50-150（与A部分重叠）
        for (var l:Number = 50; l <= 150; l++) {
            arr2.push(l);
        }
        
        var expected2:Array = arr2.concat();
        expected2.sort(Array.NUMERIC);
        
        var sorted2:Array = TimSort.sort(arr2, null);
        assertEquals(expected2, sorted2, "边界优化测试（部分重叠的run）");
    }

    /**
     * 测试堆栈不变量的维护
     */
    private static function testStackInvariantMaintenance():Void {
        var arr:Array = [];
        // 构造会产生多层嵌套合并的数据
        var runSizes:Array = [4, 8, 16, 32, 2, 4, 8];  // 故意设计的不平衡run大小
        
        var value:Number = 0;
        for (var i:Number = 0; i < runSizes.length; i++) {
            var runSize:Number = runSizes[i];
            var runStart:Number = value;
            
            if (i % 2 == 0) {
                // 升序run
                for (var j:Number = 0; j < runSize; j++) {
                    arr.push(value++);
                }
            } else {
                // 降序run
                value += runSize;
                for (var k:Number = 0; k < runSize; k++) {
                    arr.push(--value);
                }
                value += runSize;
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "堆栈不变量维护测试");
    }

    // ================================
    // 稳定性深度测试
    // ================================
    
    /**
     * 大数据集稳定性测试
     */
    private static function testStabilityWithLargeDataset():Void {
        var arr:Array = [];
        var compare:Function = function(a:Object, b:Object):Number {
            return a.key - b.key;
        };
        
        // 创建1000个对象，键值重复，但id不同
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(createStableObject(i % 10, "obj" + i));
        }
        
        var originalOrder:Array = arr.concat();
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 验证稳定性：相同键值的元素应保持原有相对顺序
        var keyGroups:Object = {};
        for (var j:Number = 0; j < originalOrder.length; j++) {
            var key:Number = originalOrder[j].key;
            if (!keyGroups[key]) keyGroups[key] = [];
            keyGroups[key].push(originalOrder[j].id);
        }
        
        var sortedKeyGroups:Object = {};
        for (var k:Number = 0; k < sorted.length; k++) {
            var sortedKey:Number = sorted[k].key;
            if (!sortedKeyGroups[sortedKey]) sortedKeyGroups[sortedKey] = [];
            sortedKeyGroups[sortedKey].push(sorted[k].id);
        }
        
        var stabilityMaintained:Boolean = true;
        for (var key in keyGroups) {
            var original:Array = keyGroups[key];
            var sortedGroup:Array = sortedKeyGroups[key];
            
            for (var l:Number = 0; l < original.length; l++) {
                if (original[l] !== sortedGroup[l]) {
                    stabilityMaintained = false;
                    break;
                }
            }
            if (!stabilityMaintained) break;
        }
        
        assertTrue(stabilityMaintained, "大数据集稳定性测试", "稳定性未保持");
    }

    /**
     * Galloping模式下的稳定性测试
     */
    private static function testStabilityUnderGalloping():Void {
        var arr:Array = [];
        var compare:Function = function(a:Object, b:Object):Number {
            return a.key - b.key;
        };
        
        // 构造容易触发galloping的数据，但键值相同
        for (var i:Number = 0; i < 50; i++) {
            arr.push(createStableObject(1, "A" + i));
        }
        for (var j:Number = 0; j < 50; j++) {
            arr.push(createStableObject(1, "B" + j));
        }
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 验证A组应该在B组前面（稳定性）
        var aCount:Number = 0;
        var bStarted:Boolean = false;
        
        for (var k:Number = 0; k < sorted.length; k++) {
            var id:String = sorted[k].id;
            if (id.charAt(0) == "A") {
                if (bStarted) {
                    assertTrue(false, "Galloping模式稳定性测试", "A组元素出现在B组元素之后");
                    return;
                }
                aCount++;
            } else {
                bStarted = true;
            }
        }
        
        assertTrue(aCount == 50 && bStarted, "Galloping模式稳定性测试", "稳定性验证");
    }

    /**
     * 复杂对象稳定性测试
     */
    private static function testStabilityWithComplexObjects():Void {
        var arr:Array = [];
        var compare:Function = function(a:Object, b:Object):Number {
            if (a.priority != b.priority) return a.priority - b.priority;
            return a.timestamp - b.timestamp;
        };
        
        // 创建复杂对象：优先级相同但时间戳不同
        var baseTime:Number = 1000000;
        for (var i:Number = 0; i < 20; i++) {
            arr.push({
                priority: 1,
                timestamp: baseTime + i,
                id: "task" + i,
                data: "some data " + i
            });
        }
        
        // 再添加一些不同优先级的
        for (var j:Number = 0; j < 10; j++) {
            arr.push({
                priority: 0,
                timestamp: baseTime + j,
                id: "urgent" + j,
                data: "urgent data " + j
            });
        }
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 验证排序正确性和稳定性
        var isCorrectlySorted:Boolean = true;
        for (var k:Number = 1; k < sorted.length; k++) {
            if (compare(sorted[k-1], sorted[k]) > 0) {
                isCorrectlySorted = false;
                break;
            }
        }
        
        assertTrue(isCorrectlySorted, "复杂对象稳定性测试", "排序不正确或稳定性未保持");
    }

    /**
     * 多run稳定性测试
     */
    private static function testStabilityInMultipleRuns():Void {
        var arr:Array = [];
        var compare:Function = function(a:Object, b:Object):Number {
            return a.key - b.key;
        };
        
        // 创建多个run，每个run内有重复键值
        for (var run:Number = 0; run < 5; run++) {
            for (var i:Number = 0; i < 10; i++) {
                arr.push(createStableObject(i % 3, "run" + run + "_" + i));
            }
        }
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 检查相同键值的元素是否保持了原有的相对顺序
        var groups:Object = {};
        
        // 按键值分组，记录原始顺序
        for (var j:Number = 0; j < arr.length; j++) {
            var key:Number = arr[j].key;
            if (!groups[key]) groups[key] = [];
            groups[key].push(arr[j].id);
        }
        
        // 检查排序后的顺序
        var sortedGroups:Object = {};
        for (var k:Number = 0; k < sorted.length; k++) {
            var sortedKey:Number = sorted[k].key;
            if (!sortedGroups[sortedKey]) sortedGroups[sortedKey] = [];
            sortedGroups[sortedKey].push(sorted[k].id);
        }
        
        var stabilityOk:Boolean = true;
        for (var key in groups) {
            var orig:Array = groups[key];
            var sortedGroup:Array = sortedGroups[key];
            
            for (var l:Number = 0; l < orig.length; l++) {
                if (orig[l] !== sortedGroup[l]) {
                    stabilityOk = false;
                    break;
                }
            }
        }
        
        assertTrue(stabilityOk, "多run稳定性测试", "多个run合并后稳定性未保持");
    }

    // ================================
    // 合并策略专项测试（从原版保留+增强）
    // ================================
    private static function testForceThreeRunMerge():Void {
        var arr:Array = [
            5,4,3,                    // 降序 run1 (会被反转)
            6,7,8,9,10,              // 升序 run2
            18,17,16,15,14,13,12,11  // 降序 run3 (会被反转)
        ];
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "强制三路合并测试");
    }

    private static function testCascadeMerge():Void {
        var arr:Array = [];
        for(var i:Number=0; i<4; i++){ // 4个降序 run
            var start:Number = i*10 + 10;
            arr.push(start+3, start+2, start+1, start);
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "级联合并测试");
    }

    private static function testStabilityMerge():Void {
        var createObj = function(key:Number, id:String):Object { return {key:key, id:id}; };
        
        var objA1:Object = createObj(1, "A1");
        var objA2:Object = createObj(1, "A2");
        var objA3:Object = createObj(1, "A3");
        var objB1:Object = createObj(1, "B1");
        var objB2:Object = createObj(1, "B2");
        var objB3:Object = createObj(1, "B3");
        
        var arr:Array = [objA1, objA2, objA3, objB3, objB2, objB1];
        var compare:Function = function(a:Object, b:Object):Number {
            return a.key - b.key;
        };
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        var stabilityPassed:Boolean = (sorted[0].id == "A1") 
                    && (sorted[1].id == "A2")
                    && (sorted[2].id == "A3")
                    && (sorted[3].id == "B3")
                    && (sorted[4].id == "B2")
                    && (sorted[5].id == "B1");
        
        assertTrue(stabilityPassed, "合并稳定性测试", "相同键值的元素顺序在合并后发生改变");
    }

    private static function testMergeBoundaryCondition():Void {
        var arr:Array = [];
        // Run1: 32元素升序
        for(var i:Number=0; i<32; i++) arr.push(i);
        // Run2: 16元素降序
        for(var j:Number=47; j>=32; j--) arr.push(j);
        // Run3: 15元素升序
        for(var k:Number=48; k<63; k++) arr.push(k);
        
        var sorted:Array = TimSort.sort(arr, null);
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        assertEquals(expected, sorted, "合并边界条件测试");
    }

    private static function testMergeWithTinyRuns():Void {
        var arr:Array = [];
        for(var i:Number=0; i<100; i++){
            if(i%2 == 0){
                arr.push(i+1, i);
            }else{
                arr.push(i, i+1);
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "极小run合并测试");
    }

    /**
     * 测试非对称run合并（一个很大，一个很小）
     */
    private static function testAsymmetricRunMerge():Void {
        var arr:Array = [];
        
        // 大run: 1000个元素
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(i * 2);  // 偶数
        }
        
        // 小run: 10个元素，插入其中
        for (var j:Number = 0; j < 10; j++) {
            arr.push(j * 200 + 1);  // 奇数，分散插入
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "非对称run合并测试");
    }

    /**
     * 测试最大栈深度场景
     */
    private static function testMaximalStackDepth():Void {
        var arr:Array = [];
        
        // 创建fibonacci式的run长度序列，这是最坏情况
        var runLengths:Array = [2, 3, 5, 8, 13, 21, 34, 55];
        var value:Number = 0;
        
        for (var i:Number = 0; i < runLengths.length; i++) {
            var runLength:Number = runLengths[i];
            for (var j:Number = 0; j < runLength; j++) {
                arr.push(value++);
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "最大栈深度测试");
    }

    // ================================
    // 实际应用场景测试
    // ================================
    
    /**
     * 部分有序数据测试（常见于实际应用）
     */
    private static function testPartiallyOrderedData():Void {
        // 为部分有序数据测试重置种子
        resetRNG(11111);
        
        var arr:Array = [];
        
        // 大部分有序，少量乱序
        for (var i:Number = 0; i < 100; i++) {
            arr.push(i);
        }
        
        // 随机交换10%的元素
        for (var j:Number = 0; j < 10; j++) {
            var pos1:Number = rng.randomInteger(0, 99);
            var pos2:Number = rng.randomInteger(0, 99);
            var temp:Number = arr[pos1];
            arr[pos1] = arr[pos2];
            arr[pos2] = temp;
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var start:Number = getTimer();
        var sorted:Array = TimSort.sort(arr, null);
        var time:Number = getTimer() - start;
        
        assertEquals(expected, sorted, "部分有序数据测试");
        trace("    部分有序数据排序耗时: " + time + "ms");
    }

    /**
     * 交替模式测试
     */
    private static function testAlternatingPatterns():Void {
        var arr:Array = [];
        
        // 创建高低交替模式
        for (var i:Number = 0; i < 50; i++) {
            arr.push(i);      // 低值
            arr.push(i + 100); // 高值
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "交替模式测试");
    }

    /**
     * 钢琴键模式测试（经典的困难模式）
     */
    private static function testPianoKeyPattern():Void {
        var arr:Array = [];
        
        // 钢琴键模式：小段升序和降序交替
        for (var i:Number = 0; i < 20; i++) {
            if (i % 2 == 0) {
                // 升序段
                for (var j:Number = 0; j < 5; j++) {
                    arr.push(i * 10 + j);
                }
            } else {
                // 降序段
                for (var k:Number = 4; k >= 0; k--) {
                    arr.push(i * 10 + k);
                }
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "钢琴键模式测试");
    }

    /**
     * 大量重复值测试
     */
    private static function testMostlyDuplicates():Void {
        // 为大量重复值测试重置种子
        resetRNG(22222);
        
        var arr:Array = [];
        
        // 90%的元素是重复的
        for (var i:Number = 0; i < 1000; i++) {
            if (i % 10 == 0) {
                arr.push(rng.nextFloat() * 1000);  // 10%随机值
            } else {
                arr.push(42);  // 90%重复值
            }
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var start:Number = getTimer();
        var sorted:Array = TimSort.sort(arr, null);
        var time:Number = getTimer() - start;
        
        assertEquals(expected, sorted, "大量重复值测试");
        trace("    大量重复值排序耗时: " + time + "ms");
    }

    /**
     * 管道模式测试（中间大，两端小）
     */
    private static function testOrganPipePattern():Void {
        var arr:Array = [];
        
        // 先升序到中点，再降序
        var mid:Number = 50;
        for (var i:Number = 0; i < mid; i++) {
            arr.push(i);
        }
        for (var j:Number = mid - 1; j >= 0; j--) {
            arr.push(j);
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "管道模式测试");
    }

    /**
     * 随机游走模式测试
     */
    private static function testRandomWalkPattern():Void {
        var arr:Array = [];
        var current:Number = 500;
        
        // 随机游走：每步随机上升或下降
        for (var i:Number = 0; i < 100; i++) {
            arr.push(current);
            current += rng.randomCheckHalf() ? 1 : -1;
            if (current < 0) current = 0;
            if (current > 1000) current = 1000;
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "随机游走模式测试");
    }

    /**
     * 数据库风格数据测试（常见业务场景）
     */
    private static function testDatabaseStyleData():Void {
        var arr:Array = [];
        var compare:Function = function(a:Object, b:Object):Number {
            // 先按状态排序，再按时间戳排序
            if (a.status != b.status) {
                return a.status - b.status;
            }
            return a.timestamp - b.timestamp;
        };
        
        var statuses:Array = [1, 2, 3]; // 三种状态
        var baseTime:Number = 1000000;
        
        // 创建模拟数据库记录
        for (var i:Number = 0; i < 300; i++) {
            arr.push({
                id: i,
                status: statuses[i % 3],
                timestamp: baseTime + rng.nextFloat() * 10000,
                data: "record_" + i
            });
        }
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 验证排序正确性
        var isCorrect:Boolean = true;
        for (var j:Number = 1; j < sorted.length; j++) {
            if (compare(sorted[j-1], sorted[j]) > 0) {
                isCorrect = false;
                break;
            }
        }
        
        assertTrue(isCorrect, "数据库风格数据测试", "多字段排序失败");
    }

    /**
     * 时间序列数据测试
     */
    private static function testTimeSeriesData():Void {
        var arr:Array = [];
        
        // 模拟时间序列数据：大部分按时间有序，但有一些乱序的迟到数据
        var baseTime:Number = 1000000;
        for (var i:Number = 0; i < 200; i++) {
            var timestamp:Number = baseTime + i * 1000;
            
            // 5%的概率是"迟到"的数据
            if (rng.nextFloat() < 0.05) {
                timestamp -= rng.nextFloat() * 50000; // 迟到数据
            }
            
            arr.push({
                timestamp: timestamp,
                value: rng.nextFloat() * 100,
                id: "data_" + i
            });
        }
        
        var compare:Function = function(a:Object, b:Object):Number {
            return a.timestamp - b.timestamp;
        };
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 验证时间戳有序
        var isTimeOrdered:Boolean = true;
        for (var j:Number = 1; j < sorted.length; j++) {
            if (sorted[j-1].timestamp > sorted[j].timestamp) {
                isTimeOrdered = false;
                break;
            }
        }
        
        assertTrue(isTimeOrdered, "时间序列数据测试", "时间戳排序失败");
    }

    // ================================
    // 边界条件和压力测试
    // ================================
    
    /**
     * MIN_RUN边界测试
     */
    private static function testMinRunBoundaries():Void {
        // 测试各种边界长度
        var boundaryLengths:Array = [31, 32, 33, 63, 64, 65];
        
        for (var i:Number = 0; i < boundaryLengths.length; i++) {
            var length:Number = boundaryLengths[i];
            var arr:Array = [];
            
            // 创建完全随机数组
            for (var j:Number = 0; j < length; j++) {
                arr.push(rng.nextFloat() * 1000);
            }
            
            var expected:Array = arr.concat();
            expected.sort(Array.NUMERIC);
            
            var sorted:Array = TimSort.sort(arr.concat(), null);
            assertEquals(expected, sorted, "MIN_RUN边界测试 (length=" + length + ")");
        }
    }

    /**
     * Gallop阈值边界测试
     */
    private static function testGallopThresholdBoundaries():Void {
        var arr:Array = [];
        
        // 构造恰好触发gallop阈值的场景
        // Run A: 7个小元素（应该触发gallop）
        for (var i:Number = 0; i < 7; i++) {
            arr.push(i);
        }
        // Run B: 大量大元素
        for (var j:Number = 100; j < 200; j++) {
            arr.push(j);
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Gallop阈值边界测试");
    }

    /**
     * 大数组压力测试
     */
    private static function testLargeArrayStressTest():Void {
        // 为大数组测试重置种子
        resetRNG(99999);
        
        var size:Number = 50000;  // 大数组
        var arr:Array = [];
        
        // 创建混合模式的大数组
        for (var i:Number = 0; i < size; i++) {
            if (i % 1000 < 500) {
                arr.push(i);  // 有序部分
            } else {
                arr.push(rng.nextFloat() * size);  // 随机部分
            }
        }
        
        var start:Number = getTimer();
        var sorted:Array = TimSort.sort(arr, null);
        var time:Number = getTimer() - start;
        
        var isCorrect:Boolean = isSorted(sorted, null);
        assertTrue(isCorrect, "大数组压力测试", "大数组排序失败");
        trace("    大数组压力测试 (size=" + size + ") 耗时: " + time + "ms");
    }

    /**
     * 深度递归避免测试
     */
    private static function testDeepRecursionAvoidance():Void {
        var arr:Array = [];
        
        // 创建容易导致深度递归的最坏情况数据
        // Fibonacci式的run长度
        var runLengths:Array = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144];
        var value:Number = 0;
        
        for (var i:Number = 0; i < runLengths.length; i++) {
            var runLength:Number = runLengths[i];
            for (var j:Number = 0; j < runLength; j++) {
                arr.push(value + runLength - j - 1);  // 降序run
            }
            value += runLength;
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "深度递归避免测试");
    }

    /**
     * 内存效率测试
     */
    private static function testMemoryEfficiencyTest():Void {
        // 创建需要大量临时空间的数据
        var arr:Array = [];
        
        // 两个大run，一个小一个大，测试智能空间分配
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(i * 2);  // 大run：偶数
        }
        for (var j:Number = 0; j < 10; j++) {
            arr.push(j * 2 + 1);  // 小run：少量奇数
        }
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var start:Number = getTimer();
        var sorted:Array = TimSort.sort(arr, null);
        var time:Number = getTimer() - start;
        
        assertEquals(expected, sorted, "内存效率测试");
        trace("    内存效率测试耗时: " + time + "ms");
    }

    // ================================
    // 增强版性能测试
    // ================================
    private static function runEnhancedPerformanceTests():Void {
        trace("\n开始增强版性能测试...");
        
        // 重置随机数种子以确保性能测试结果可重现
        resetRNG(54321);
        var sizes:Array = [1000, 5000, 10000];
        var distributions:Array = [
            "random", 
            "sorted", 
            "reverse", 
            "partiallyOrdered",
            "manyDuplicates",
            "pianoKeys",
            "organPipe",
            "mergeStress",
            "gallopFriendly",
            "gallopUnfriendly"
        ];
        
        for(var i:Number=0; i<sizes.length; i++){
            var size:Number = sizes[i];
            trace("  测试数组大小: " + size);
            
            for(var j:Number=0; j<distributions.length; j++){
                var dist:String = distributions[j];
                var arr:Array = generateEnhancedTestArray(size, dist);
                
                var start:Number = getTimer();
                var sorted:Array = TimSort.sort(arr.concat(), null);
                var time:Number = getTimer() - start;
                
                verifySorted(arr, sorted, dist);
                trace("    " + dist + ": " + time + "ms");
            }
        }
        trace("增强版性能测试完成");
    }

    private static function generateEnhancedTestArray(size:Number, type:String):Array {
        var arr:Array = [];
        switch(type){
            case "random":
                for(var i:Number=0; i<size; i++) arr.push(rng.nextFloat()*size);
                break;
            case "sorted":
                for(var j:Number=0; j<size; j++) arr.push(j);
                break;
            case "reverse":
                for(var k:Number=0; k<size; k++) arr.push(size - k);
                break;
            case "partiallyOrdered":
                // 90%有序，10%随机交换
                for(var l:Number=0; l<size; l++) arr.push(l);
                for(var m:Number=0; m<size/10; m++){
                    var pos1:Number = rng.randomInteger(0, size - 1);
                    var pos2:Number = rng.randomInteger(0, size - 1);
                    var temp:Number = arr[pos1];
                    arr[pos1] = arr[pos2];
                    arr[pos2] = temp;
                }
                break;
            case "manyDuplicates":
                // 大量重复值
                for(var n:Number=0; n<size; n++) arr.push(rng.randomInteger(0, 9));
                break;
            case "pianoKeys":
                // 钢琴键模式
                for(var p:Number=0; p<size/10; p++){
                    for(var q:Number=0; q<5 && p*10+q<size; q++){
                        arr.push(p*10 + q);
                    }
                    for(var r:Number=4; r>=0 && p*10+5+4-r<size; r--){
                        arr.push(p*10 + 5 + r);
                    }
                }
                break;
            case "organPipe":
                // 管道模式
                var mid:Number = size / 2;
                for(var s:Number=0; s<mid && s<size; s++) arr.push(s);
                for(var t:Number=mid-1; t>=0 && mid+(mid-1-t)<size; t--) arr.push(t);
                break;
            case "mergeStress":
                // 合并压力测试
                for(var u:Number=0; u<size; u++){
                    if(u%4 == 0 && u+3 < size){
                        arr.push(u+3, u+2, u+1, u);
                        u += 3;
                    }else{
                        arr.push(rng.nextFloat()*size);
                    }
                }
                break;
            case "gallopFriendly":
                // Gallop友好数据
                for(var v:Number=0; v<size/2; v++) arr.push(v);
                for(var w:Number=size; w>size/2; w--) arr.push(w);
                break;
            case "gallopUnfriendly":
                // Gallop不友好数据
                for(var x:Number=0; x<size; x++){
                    arr.push(x % 2);  // 大量交替
                }
                break;
        }
        return arr;
    }

    private static function verifySorted(original:Array, sorted:Array, testName:String):Void {
        var expected:Array = original.concat();
        expected.sort(Array.NUMERIC);
        
        if(expected.length != sorted.length){
            trace("      验证失败 - " + testName + ": 数组长度改变");
            return;
        }
        
        for(var i:Number=0; i<expected.length; i++){
            if(expected[i] !== sorted[i]){
                trace("      验证失败 - " + testName + ": 错误索引 " + i);
                return;
            }
        }
    }
}