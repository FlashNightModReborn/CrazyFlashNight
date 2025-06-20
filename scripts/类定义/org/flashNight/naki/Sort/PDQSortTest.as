import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.PDQSortTest {
    
    // 测试统计
    private static var totalTests:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    
    // 保守的测试规模配置
    private static var SMALL_SIZE:Number = 100;      // 小数组测试
    private static var MEDIUM_SIZE:Number = 1000;    // 中等数组测试  
    private static var LARGE_SIZE:Number = 3000;     // 大数组测试
    private static var STRESS_SIZE:Number = 10000;    // 压力测试
    
    // 运行所有测试
    public static function runTests():Void {
        trace("=================================================================");
        trace("Starting AS2-Optimized PDQSort Tests...");
        trace("=================================================================");
        
        // 基础功能测试
        runBasicTests();
        
        // 边界情况测试
        runBoundaryTests();
        
        // 算法特性测试
        runAlgorithmSpecificTests();
        
        // 数据类型测试
        runDataTypeTests();
        
        // 比较函数测试
        runCompareFunctionTests();
        
        // 稳定性测试
        runStabilityTests();
        
        // 轻量压力测试
        runLightStressTests();
        
        // 性能测试
        runPerformanceTests();
        
        // 输出测试总结
        printTestSummary();
    }
    
    // 提供快速测试选项
    public static function runQuickTests():Void {
        trace("=================================================================");
        trace("Starting Quick PDQSort Tests...");
        trace("=================================================================");
        
        runBasicTests();
        runBoundaryTests();
        printTestSummary();
    }
    
    // 基础功能测试
    private static function runBasicTests():Void {
        trace("\n--- Basic Functionality Tests ---");
        testEmptyArray();
        testSingleElement();
        testTwoElements();
        testAlreadySorted();
        testReverseSorted();
        testRandomArray();
        testDuplicateElements();
        testAllSameElements();
    }
    
    // 边界情况测试
    private static function runBoundaryTests():Void {
        trace("\n--- Boundary Case Tests ---");
        testSmallArrays();
        testMixedTypes();
        testModerateArray();
        testExtremeDuplicates();
    }
    
    // 算法特性测试
    private static function runAlgorithmSpecificTests():Void {
        trace("\n--- Algorithm-Specific Tests ---");
        testInsertionSortThreshold();
        testThreeWayPartitioning();
        testOrderedDetection();
        testPivotSelection();
    }
    
    // 数据类型测试
    private static function runDataTypeTests():Void {
        trace("\n--- Data Type Tests ---");
        testStringArray();
        testObjectArray();
        testMixedDataTypes();
        testCustomObjects();
    }
    
    // 比较函数测试
    private static function runCompareFunctionTests():Void {
        trace("\n--- Compare Function Tests ---");
        testCustomCompareFunction();
        testReverseCompareFunction();
        testComplexCompareFunction();
        testNullCompareFunction();
    }
    
    // 稳定性测试
    private static function runStabilityTests():Void {
        trace("\n--- Stability Tests ---");
        testConsistentResults();
        testInPlaceSorting();
        testIdempotency();
    }
    
    // 轻量压力测试
    private static function runLightStressTests():Void {
        trace("\n--- Light Stress Tests ---");
        testMediumSizeArrays();
        testWorstCaseScenarios();
        testRepeatedSorting();
    }
    
    // ============================================================================
    // 基础测试实现
    // ============================================================================
    
    private static function testEmptyArray():Void {
        var arr:Array = [];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals([], sorted, "Empty Array Test");
    }
    
    private static function testSingleElement():Void {
        var arr:Array = [42];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals([42], sorted, "Single Element Test");
    }
    
    private static function testTwoElements():Void {
        var arr1:Array = [2, 1];
        var sorted1:Array = PDQSort.sort(arr1, null);
        assertEquals([1, 2], sorted1, "Two Elements (Reverse) Test");
        
        var arr2:Array = [1, 2];
        var sorted2:Array = PDQSort.sort(arr2, null);
        assertEquals([1, 2], sorted2, "Two Elements (Sorted) Test");
        
        var arr3:Array = [5, 5];
        var sorted3:Array = PDQSort.sort(arr3, null);
        assertEquals([5, 5], sorted3, "Two Elements (Equal) Test");
    }
    
    private static function testAlreadySorted():Void {
        var arr:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        var expected:Array = arr.slice();
        var sorted:Array = PDQSort.sort(arr.slice(), null);
        assertEquals(expected, sorted, "Already Sorted Array Test");
    }
    
    private static function testReverseSorted():Void {
        var arr:Array = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
        var expected:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "Reverse Sorted Array Test");
    }
    
    private static function testRandomArray():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5];
        var expected:Array = [1, 1, 2, 3, 4, 5, 5, 6, 9];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "Random Array Test");
    }
    
    private static function testDuplicateElements():Void {
        var arr:Array = [5, 3, 8, 3, 9, 1, 5, 7, 3];
        var expected:Array = [1, 3, 3, 3, 5, 5, 7, 8, 9];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "Duplicate Elements Test");
    }
    
    private static function testAllSameElements():Void {
        var arr:Array = [7, 7, 7, 7, 7, 7, 7];
        var expected:Array = [7, 7, 7, 7, 7, 7, 7];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "All Same Elements Test");
    }
    
    // ============================================================================
    // 边界情况测试实现
    // ============================================================================
    
    private static function testSmallArrays():Void {
        // 测试各种小数组大小
        for (var size:Number = 3; size <= 35; size++) {
            var arr:Array = generateArray(size, "random");
            var expected:Array = arr.slice();
            expected.sort(Array.NUMERIC);
            var sorted:Array = PDQSort.sort(arr, null);
            
            if (!compareArrays(expected, sorted)) {
                assertTrue(false, "Small Arrays Test (size=" + size + ")", "Failed");
                return;
            }
        }
        assertTrue(true, "Small Arrays Test", "All sizes 3-35 sorted correctly");
    }
    
    private static function testMixedTypes():Void {
        var arr:Array = [1, "2", 3, "1", 4];
        var compareFunc:Function = function(a:Object, b:Object):Number {
            var aNum:Number = Number(a);
            var bNum:Number = Number(b);
            return aNum - bNum;
        };
        var sorted:Array = PDQSort.sort(arr, compareFunc);
        
        // 验证数值顺序
        var isCorrect:Boolean = true;
        for (var i:Number = 1; i < sorted.length; i++) {
            if (Number(sorted[i-1]) > Number(sorted[i])) {
                isCorrect = false;
                break;
            }
        }
        assertTrue(isCorrect, "Mixed Types Test", "Mixed types should sort correctly");
    }
    
    private static function testModerateArray():Void {
        var arr:Array = generateArray(MEDIUM_SIZE, "random");
        var arrCopy:Array = arr.slice();
        
        var startTime:Number = getTimer();
        var sorted:Array = PDQSort.sort(arr, null);
        var endTime:Number = getTimer();
        
        var isCorrect:Boolean = isSorted(sorted, null);
        assertTrue(isCorrect, "Moderate Array Test (" + MEDIUM_SIZE + " elements)", 
                  "Moderate array sorted correctly in " + (endTime - startTime) + "ms");
    }
    
    private static function testExtremeDuplicates():Void {
        // 测试极端重复情况，但规模较小
        var sizes:Array = [50, 200, 500];
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = new Array(size);
            for (var j:Number = 0; j < size; j++) {
                arr[j] = 42; // 所有元素都相同
            }
            
            var startTime:Number = getTimer();
            var sorted:Array = PDQSort.sort(arr, null);
            var endTime:Number = getTimer();
            
            var allSame:Boolean = true;
            for (var k:Number = 0; k < sorted.length; k++) {
                if (sorted[k] !== 42) {
                    allSame = false;
                    break;
                }
            }
            
            if (!allSame) {
                assertTrue(false, "Extreme Duplicates Test (" + size + " elements)", "Failed");
                return;
            }
        }
        assertTrue(true, "Extreme Duplicates Test", "All duplicate arrays handled correctly");
    }
    
    // ============================================================================
    // 算法特性测试实现
    // ============================================================================
    
    private static function testInsertionSortThreshold():Void {
        // 测试插入排序阈值附近的行为
        var sizes:Array = [16, 30, 32, 34, 48];
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            var arr:Array = generateArray(size, "random");
            var sorted:Array = PDQSort.sort(arr, null);
            var isCorrect:Boolean = isSorted(sorted, null);
            if (!isCorrect) {
                assertTrue(false, "Insertion Sort Threshold Test", "Failed at size " + size);
                return;
            }
        }
        assertTrue(true, "Insertion Sort Threshold Test", "Threshold behavior correct");
    }
    
    private static function testThreeWayPartitioning():Void {
        // 测试三路分区效果（较小规模）
        var arr:Array = [];
        for (var i:Number = 0; i < 300; i++) {
            arr.push(Math.floor(Math.random() * 5)); // 只有5种不同值
        }
        var sorted:Array = PDQSort.sort(arr, null);
        var isCorrect:Boolean = isSorted(sorted, null);
        assertTrue(isCorrect, "Three-Way Partitioning Test", "Many duplicates handled correctly");
    }
    
    private static function testOrderedDetection():Void {
        var scenarios:Array = [
            {arr: [1, 2, 3, 4, 5], name: "Fully Sorted"},
            {arr: [5, 4, 3, 2, 1], name: "Fully Reverse"},
            {arr: [1, 2, 3, 5, 4], name: "Nearly Sorted"}
        ];
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var scenario:Object = scenarios[i];
            var sorted:Array = PDQSort.sort(scenario.arr.slice(), null);
            var isCorrect:Boolean = isSorted(sorted, null);
            if (!isCorrect) {
                assertTrue(false, "Ordered Detection Test: " + scenario.name, "Failed");
                return;
            }
        }
        assertTrue(true, "Ordered Detection Test", "All ordered scenarios handled correctly");
    }
    
    private static function testPivotSelection():Void {
        var arr:Array = [9, 1, 8, 2, 7, 3, 6, 4, 5];
        var sorted:Array = PDQSort.sort(arr, null);
        var expected:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9];
        assertEquals(expected, sorted, "Pivot Selection Test");
    }
    
    // ============================================================================
    // 数据类型测试实现
    // ============================================================================
    
    private static function testStringArray():Void {
        var arr:Array = ["banana", "apple", "cherry", "date"];
        var sorted:Array = PDQSort.sort(arr, function(a:String, b:String):Number {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        });
        var expected:Array = ["apple", "banana", "cherry", "date"];
        assertEquals(expected, sorted, "String Array Test");
    }
    
    private static function testObjectArray():Void {
        var arr:Array = [
            {name: "John", age: 30},
            {name: "Jane", age: 25},
            {name: "Bob", age: 35}
        ];
        var sorted:Array = PDQSort.sort(arr, function(a:Object, b:Object):Number {
            return a.age - b.age;
        });
        
        var isCorrect:Boolean = (sorted[0].age === 25 && sorted[1].age === 30 && sorted[2].age === 35);
        assertTrue(isCorrect, "Object Array Test", "Objects sorted by age correctly");
    }
    
    private static function testMixedDataTypes():Void {
        var arr:Array = [3, "2", 1, "4"];
        var compareFunc:Function = function(a:Object, b:Object):Number {
            var aVal:Number = Number(a);
            var bVal:Number = Number(b);
            return aVal - bVal;
        };
        var sorted:Array = PDQSort.sort(arr, compareFunc);
        
        // 验证数值顺序正确
        var isCorrect:Boolean = true;
        for (var i:Number = 1; i < sorted.length; i++) {
            if (Number(sorted[i-1]) > Number(sorted[i])) {
                isCorrect = false;
                break;
            }
        }
        assertTrue(isCorrect, "Mixed Data Types Test", "Mixed types sorted correctly");
    }
    
    private static function testCustomObjects():Void {
        var arr:Array = [
            {priority: 1, name: "Task A"},
            {priority: 3, name: "Task C"},
            {priority: 2, name: "Task B"}
        ];
        var sorted:Array = PDQSort.sort(arr, function(a:Object, b:Object):Number {
            return a.priority - b.priority;
        });
        
        var isCorrect:Boolean = (sorted[0].priority === 1 && 
                               sorted[1].priority === 2 && 
                               sorted[2].priority === 3);
        assertTrue(isCorrect, "Custom Objects Test", "Objects sorted by priority correctly");
    }
    
    // ============================================================================
    // 比较函数测试实现
    // ============================================================================
    
    private static function testCustomCompareFunction():Void {
        var arr:Array = ["apple", "Orange", "banana", "grape", "Cherry"];
        var compareFunc:Function = function(a:String, b:String):Number {
            var aLower:String = a.toLowerCase();
            var bLower:String = b.toLowerCase();
            if (aLower < bLower) return -1;
            if (aLower > bLower) return 1;
            return 0;
        };
        var sorted:Array = PDQSort.sort(arr, compareFunc);
        
        // 验证忽略大小写的排序
        var isCorrect:Boolean = true;
        for (var i:Number = 1; i < sorted.length; i++) {
            if (sorted[i-1].toLowerCase() > sorted[i].toLowerCase()) {
                isCorrect = false;
                break;
            }
        }
        assertTrue(isCorrect, "Custom Compare Function Test", "Case-insensitive sorting works");
    }
    
    private static function testReverseCompareFunction():Void {
        var arr:Array = [1, 2, 3, 4, 5];
        var sorted:Array = PDQSort.sort(arr, function(a:Number, b:Number):Number {
            return b - a; // 反向排序
        });
        var expected:Array = [5, 4, 3, 2, 1];
        assertEquals(expected, sorted, "Reverse Compare Function Test");
    }
    
    private static function testComplexCompareFunction():Void {
        var arr:Array = [
            {value: 5, category: "A"},
            {value: 3, category: "B"},
            {value: 5, category: "B"},
            {value: 3, category: "A"}
        ];
        
        // 多级排序：先按category，再按value
        var sorted:Array = PDQSort.sort(arr, function(a:Object, b:Object):Number {
            if (a.category !== b.category) {
                return (a.category < b.category) ? -1 : 1;
            }
            return a.value - b.value;
        });
        
        var isCorrect:Boolean = (sorted[0].category === "A" && sorted[0].value === 3 &&
                               sorted[1].category === "A" && sorted[1].value === 5 &&
                               sorted[2].category === "B" && sorted[2].value === 3 &&
                               sorted[3].category === "B" && sorted[3].value === 5);
        assertTrue(isCorrect, "Complex Compare Function Test", "Multi-level sorting works");
    }
    
    private static function testNullCompareFunction():Void {
        var arr:Array = [3, 1, 4, 1, 5];
        var sorted:Array = PDQSort.sort(arr, null);
        var expected:Array = [1, 1, 3, 4, 5];
        assertEquals(expected, sorted, "Null Compare Function Test");
    }
    
    // ============================================================================
    // 稳定性测试实现
    // ============================================================================
    
    private static function testConsistentResults():Void {
        var arr:Array = generateArray(200, "random");
        var sorted1:Array = PDQSort.sort(arr.slice(), null);
        var sorted2:Array = PDQSort.sort(arr.slice(), null);
        
        var isConsistent:Boolean = compareArrays(sorted1, sorted2);
        assertTrue(isConsistent, "Consistent Results Test", "Multiple sorts produce identical results");
    }
    
    private static function testInPlaceSorting():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6];
        var originalArr:Array = arr;
        var sorted:Array = PDQSort.sort(arr, null);
        
        var isSameArray:Boolean = (arr === sorted);
        assertTrue(isSameArray, "In-Place Sorting Test", "Sorts in place correctly");
    }
    
    private static function testIdempotency():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6];
        var sorted1:Array = PDQSort.sort(arr.slice(), null);
        var sorted2:Array = PDQSort.sort(sorted1.slice(), null);
        
        var isIdempotent:Boolean = compareArrays(sorted1, sorted2);
        assertTrue(isIdempotent, "Idempotency Test", "Sorting sorted array doesn't change it");
    }
    
    // ============================================================================
    // 轻量压力测试实现
    // ============================================================================
    
    private static function testMediumSizeArrays():Void {
        var distributions:Array = ["random", "sorted", "reverse", "duplicates"];
        
        for (var i:Number = 0; i < distributions.length; i++) {
            var distribution:String = distributions[i];
            var arr:Array = generateArray(STRESS_SIZE, distribution);
            
            var startTime:Number = getTimer();
            var sorted:Array = PDQSort.sort(arr, null);
            var endTime:Number = getTimer();
            
            var isCorrect:Boolean = isSorted(sorted, null);
            if (!isCorrect) {
                assertTrue(false, "Medium Size Test: " + distribution, "Failed");
                return;
            }
        }
        assertTrue(true, "Medium Size Arrays Test", "All distributions handled correctly");
    }
    
    private static function testWorstCaseScenarios():Void {
        // 创建较小的最坏情况数组
        var scenarios:Array = [
            {generator: function():Array { return createBadQuicksortArray(300); }, name: "Bad Quicksort"},
            {generator: function():Array { return createAlternatingArray(300); }, name: "Alternating"}
        ];
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var scenario:Object = scenarios[i];
            var arr:Array = scenario.generator();
            
            var startTime:Number = getTimer();
            var sorted:Array = PDQSort.sort(arr, null);
            var endTime:Number = getTimer();
            
            var isCorrect:Boolean = isSorted(sorted, null);
            if (!isCorrect) {
                assertTrue(false, "Worst Case Test: " + scenario.name, "Failed");
                return;
            }
        }
        assertTrue(true, "Worst Case Scenarios Test", "All worst cases handled correctly");
    }
    
    private static function testRepeatedSorting():Void {
        var arr:Array = generateArray(500, "random");
        var iterations:Number = 5;
        
        for (var i:Number = 0; i < iterations; i++) {
            var testArr:Array = arr.slice();
            var startTime:Number = getTimer();
            PDQSort.sort(testArr, null);
            var endTime:Number = getTimer();
            
            var isCorrect:Boolean = isSorted(testArr, null);
            if (!isCorrect) {
                assertTrue(false, "Repeated Sorting Test", "Failed on iteration " + (i+1));
                return;
            }
        }
        assertTrue(true, "Repeated Sorting Test", iterations + " iterations completed successfully");
    }
    
    // ============================================================================
    // 性能测试实现
    // ============================================================================
    
    private static function runPerformanceTests():Void {
        trace("\n--- Performance Tests ---");
        var sizes:Array = [100, 1000, 3000, 10000];  // 更保守的大小
        var distributions:Array = ["random", "sorted", "reverse", "duplicates"];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            trace("\nTesting size: " + size);
            
            for (var j:Number = 0; j < distributions.length; j++) {
                var distribution:String = distributions[j];
                var arr:Array = generateArray(size, distribution);
                
                // 单次测试（避免多次运行增加内存压力）
                var testArr:Array = arr.slice();
                var startTime:Number = getTimer();
                PDQSort.sort(testArr, null);
                var endTime:Number = getTimer();
                var timeTaken:Number = endTime - startTime;
                
                // 验证正确性
                var isCorrect:Boolean = isSorted(testArr, null);
                
                trace("  " + distribution + ": " + timeTaken + "ms (correct: " + isCorrect + ")");
            }
        }
    }
    
    // ============================================================================
    // 辅助函数
    // ============================================================================
    
    private static function assertEquals(expected:Array, actual:Array, testName:String):Void {
        totalTests++;
        if (expected.length != actual.length) {
            trace("FAIL: " + testName + " - Array lengths differ. Expected: " + expected.length + ", Actual: " + actual.length);
            failedTests++;
            return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                trace("FAIL: " + testName + " - Arrays differ at index " + i + ". Expected: " + expected[i] + ", Actual: " + actual[i]);
                failedTests++;
                return;
            }
        }
        trace("PASS: " + testName);
        passedTests++;
    }
    
    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        totalTests++;
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
            failedTests++;
        } else {
            trace("PASS: " + testName + (message ? " - " + message : ""));
            passedTests++;
        }
    }
    
    private static function compareArrays(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) return false;
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i]) return false;
        }
        return true;
    }
    
    private static function isSorted(arr:Array, compareFunc:Function):Boolean {
        var cmp:Function = compareFunc || function(a:Number, b:Number):Number { return a - b; };
        for (var i:Number = 1; i < arr.length; i++) {
            if (cmp(arr[i-1], arr[i]) > 0) return false;
        }
        return true;
    }
    
    private static function generateArray(size:Number, distribution:String):Array {
        var arr:Array = new Array(size);
        switch (distribution) {
            case "random":
                for (var i:Number = 0; i < size; i++) {
                    arr[i] = Math.floor(Math.random() * size);
                }
                break;
            case "sorted":
                for (var j:Number = 0; j < size; j++) {
                    arr[j] = j;
                }
                break;
            case "reverse":
                for (var k:Number = 0; k < size; k++) {
                    arr[k] = size - k;
                }
                break;
            case "duplicates":
                var duplicatePool:Array = [1, 2, 3, 4, 5];
                for (var l:Number = 0; l < size; l++) {
                    arr[l] = duplicatePool[Math.floor(Math.random() * duplicatePool.length)];
                }
                break;
            case "allSame":
                for (var m:Number = 0; m < size; m++) {
                    arr[m] = 42;
                }
                break;
            default:
                for (var n:Number = 0; n < size; n++) {
                    arr[n] = Math.floor(Math.random() * size);
                }
        }
        return arr;
    }
    
    private static function createBadQuicksortArray(size:Number):Array {
        var arr:Array = new Array(size);
        for (var i:Number = 0; i < size; i++) {
            arr[i] = i % 2; // 交替0和1
        }
        return arr;
    }
    
    private static function createAlternatingArray(size:Number):Array {
        var arr:Array = new Array(size);
        for (var i:Number = 0; i < size; i++) {
            arr[i] = (i % 2 === 0) ? 1 : 100;
        }
        return arr;
    }
    
    private static function printTestSummary():Void {
        trace("\n=================================================================");
        trace("TEST SUMMARY");
        trace("=================================================================");
        trace("Total Tests: " + totalTests);
        trace("Passed: " + passedTests);
        trace("Failed: " + failedTests);
        trace("Success Rate: " + ((passedTests / totalTests * 100)) + "%");
        
        if (failedTests === 0) {
            trace("🎉 ALL TESTS PASSED! 🎉");
        } else {
            trace("⚠️  " + failedTests + " test(s) failed. Please review the failures above.");
        }
        trace("=================================================================");
    }
}