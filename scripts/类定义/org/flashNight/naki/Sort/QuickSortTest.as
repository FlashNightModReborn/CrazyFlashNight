import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.QuickSortTest {
    
    // 运行所有测试的入口
    public static function runTests():Void {
        trace("Starting QuickSort Tests...");

        // 1. 功能性测试（正确性验证）
        QuickSortTest.testEmptyArray();
        QuickSortTest.testSingleElement();
        QuickSortTest.testAlreadySorted();
        QuickSortTest.testReverseSorted();
        QuickSortTest.testRandomArray();
        QuickSortTest.testDuplicateElements();
        QuickSortTest.testAllSameElements();
        QuickSortTest.testCustomCompareFunction();

        // 2. 性能测试
        QuickSortTest.runPerformanceTests();

        trace("All QuickSort Tests Completed.\n");
    }

    // =========== 以下是功能性测试部分 ===========

    // 测试空数组
    private static function testEmptyArray():Void {
        var arr:Array = [];
        // 我们将同一个测试用例给四种排序函数测试
        testAllQuickSortMethods(arr, null, [], "Empty Array Test");
    }

    // 测试单元素数组
    private static function testSingleElement():Void {
        var arr:Array = [42];
        testAllQuickSortMethods(arr, null, [42], "Single Element Array Test");
    }

    // 测试已排序数组
    private static function testAlreadySorted():Void {
        var arr:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        var expected:Array = arr.slice(); // 已排序
        testAllQuickSortMethods(arr, null, expected, "Already Sorted Array Test");
    }

    // 测试逆序数组
    private static function testReverseSorted():Void {
        var arr:Array = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
        var expected:Array = arr.slice();
        expected.reverse(); // 手动逆转得到正确的排序结果
        testAllQuickSortMethods(arr, null, expected, "Reverse Sorted Array Test");
    }

    // 测试随机数组
    private static function testRandomArray():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5];
        // 用内置数值排序产生期望结果
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC);
        testAllQuickSortMethods(arr, null, expected, "Random Array Test");
    }

    // 测试包含重复元素的数组
    private static function testDuplicateElements():Void {
        var arr:Array = [5, 3, 8, 3, 9, 1, 5, 7, 3];
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC);
        testAllQuickSortMethods(arr, null, expected, "Duplicate Elements Array Test");
    }

    // 测试全部相同元素的数组
    private static function testAllSameElements():Void {
        var arr:Array = [7, 7, 7, 7, 7, 7, 7];
        // 全部相同，排序后与原数组一致
        testAllQuickSortMethods(arr, null, arr, "All Same Elements Array Test");
    }

    // 测试自定义比较函数
    private static function testCustomCompareFunction():Void {
        var arr:Array = ["apple", "Orange", "banana", "grape", "Cherry"];
        // 自定义比较（忽略大小写）
        var compareFunc:Function = function(a:String, b:String):Number {
            var aLower:String = a.toLowerCase();
            var bLower:String = b.toLowerCase();
            if (aLower < bLower) return -1;
            if (aLower > bLower) return 1;
            return 0;
        };
        // 用内置 sort() + 自定义比较函数 获得期望结果
        var expected:Array = arr.slice();
        expected.sort(compareFunc);
        testAllQuickSortMethods(arr, compareFunc, expected, "Custom Compare Function Test");
    }

    /**
     * 针对同一个测试用例，对 QuickSort 的四种函数逐一排序并验证结果。
     * 
     * @param arr 原始数组
     * @param compareFunction 自定义比较函数
     * @param expected 期望结果（已排序）
     * @param testName 用于 trace 输出的测试名称
     */
    private static function testAllQuickSortMethods(arr:Array, compareFunction:Function, expected:Array, testName:String):Void {
        // 原数组可能在排序过程中被修改，因此每次都要 slice() 出一个副本
        var arr1:Array = arr.slice();
        var arr2:Array = arr.slice();
        var arr3:Array = arr.slice();
        var arr4:Array = arr.slice();

        // 1) 测试标准 sort
        var sorted1:Array = QuickSort.sort(arr1, compareFunction);
        assertEquals(expected, sorted1, testName + " - QuickSort.sort()");

        // 2) 测试 adaptiveSort
        var sorted2:Array = QuickSort.adaptiveSort(arr2, compareFunction);
        assertEquals(expected, sorted2, testName + " - QuickSort.adaptiveSort()");

        // 3) 测试 threeWaySort
        var sorted3:Array = QuickSort.threeWaySort(arr3, compareFunction);
        assertEquals(expected, sorted3, testName + " - QuickSort.threeWaySort()");

        // 4) 测试 enhancedQuickSort
        //   注意：enhancedQuickSort 有4个参数 (arr, compareFunc, useDualPivot, pivotStrategy)
        //   这里举例使用 双轴分区=true, pivotStrategy="median3"，你也可根据需要替换
        var sorted4:Array = QuickSort.enhancedQuickSort(arr4, compareFunction, true, "median3");
        assertEquals(expected, sorted4, testName + " - QuickSort.enhancedQuickSort()");
    }

    // =========== 以下是性能测试部分 ===========

    private static function runPerformanceTests():Void {
        trace("\nStarting QuickSort Performance Tests...");

        // 测试数据规模
        var sizes:Array = [1000, 10000, 50000];
        // 测试分布
        var distributions:Array = ["random", "sorted", "reverse", "duplicates", "allSame"];

        // 用于循环测试四种方法
        // 注意：AS2 里可以用对象存函数引用 {name: "sort", func: QuickSort.sort} 等
        var methods:Array = [
            {name: "sort",             func: QuickSort.sort},
            {name: "adaptiveSort",     func: QuickSort.adaptiveSort},
            {name: "threeWaySort",     func: QuickSort.threeWaySort},
            {name: "enhancedQuickSort",func: enhancedQuickSortWrapper}
        ];

        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            
            for (var j:Number = 0; j < distributions.length; j++) {
                var distribution:String = distributions[j];
                
                // 为提高测试稳定性，可多次运行取平均(此示例仅单次)
                for (var m:Number = 0; m < methods.length; m++) {
                    var methodObj = methods[m];
                    var methodName:String = methodObj.name;
                    var sortFunc:Function = methodObj.func;

                    // 生成指定分布的数组
                    var arr:Array = generateArray(size, distribution);
                    var arrCopy:Array = arr.slice();
                    
                    // 记录开始时间
                    var startTime:Number = getTimer();
                    
                    // 调用对应的排序函数
                    var sorted:Array = sortFunc(arrCopy, null);
                    
                    // 记录结束时间
                    var endTime:Number = getTimer();
                    var timeTaken:Number = endTime - startTime;

                    // 验证结果正确性
                    var expected:Array = getExpectedSorted(arr, distribution);
                    var isCorrect:Boolean = compareArrays(expected, sorted);

                    // 输出测试结果
                    trace("Method: " + methodName + 
                          ", Size: " + size + 
                          ", Dist: " + distribution + 
                          ", Time: " + timeTaken + "ms" + 
                          ", Correct: " + isCorrect);
                }
            }
        }

        trace("Performance Tests Completed.\n");
    }

    /**
     * 在 AS2 中无法直接将 enhancedQuickSort(...) 存为 func引用再带多参数，
     * 因此这里封装一下，保持与其他函数签名一致 (arr, compareFunction)。
     * 你可以在此函数内自由设置 useDualPivot, pivotStrategy 等。
     */
    private static function enhancedQuickSortWrapper(arr:Array, compareFunction:Function):Array {
        // 示例：使用 双轴分区=true, pivotStrategy="random"
        return QuickSort.enhancedQuickSort(arr, compareFunction, true, "random");
    }

    /**
     * 根据分布类型，给出正确排序后的期望结果。
     * - 对于完全随机或有重复的，一般用内置数值排序 sort(Array.NUMERIC)
     * - 对于已排序/逆序/全相同，可以直接构造或做相应操作
     */
    private static function getExpectedSorted(original:Array, distribution:String):Array {
        var expected:Array = original.slice();
        switch (distribution) {
            case "random":
            case "duplicates":
                expected.sort(Array.NUMERIC);
                break;
            case "allSame":
                // 跟原数组一样，因为全相同
                break;
            case "sorted":
                // 已经是升序
                break;
            case "reverse":
                // 需要将 reverse() 后得到升序
                expected.reverse();
                break;
            default:
                // 默认用 sort(Array.NUMERIC)
                expected.sort(Array.NUMERIC);
        }
        return expected;
    }

    /**
     * 生成不同分布的数组
     */
    private static function generateArray(size:Number, distribution:String):Array {
        var arr:Array = [];
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
                // 使它在原始时就降序
                for (var k:Number = 0; k < size; k++) {
                    arr[k] = size - k;
                }
                break;
            case "duplicates":
                // 取少量元素反复放进数组
                var duplicatePool:Array = [1, 2, 3, 4, 5];
                for (var l:Number = 0; l < size; l++) {
                    arr[l] = duplicatePool[Math.floor(Math.random() * duplicatePool.length)];
                }
                break;
            case "allSame":
                // 全部都相同
                for (var m:Number = 0; m < size; m++) {
                    arr[m] = 42;
                }
                break;
            default:
                // 如果分布值不在上面范围，就随机
                for (var n:Number = 0; n < size; n++) {
                    arr[n] = Math.floor(Math.random() * size);
                }
        }
        return arr;
    }

    /**
     * 简易比较：判断两个数组是否相同
     */
    private static function compareArrays(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) return false;
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i]) {
                return false;
            }
        }
        return true;
    }

    // =========== 以下是辅助的断言方法，与 PDQSortTest 类似 ===========

    // 简单断言，检查排序结果是否与预期相符
    private static function assertEquals(expected:Array, actual:Array, testName:String):Void {
        if (expected.length != actual.length) {
            trace("FAIL: " + testName + " - Array lengths differ. " + 
                  "Expected: " + expected.length + ", Actual: " + actual.length);
            return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                trace("FAIL: " + testName + " - Arrays differ at index " + i + 
                      ". Expected: " + expected[i] + ", Actual: " + actual[i]);
                return;
            }
        }
        trace("PASS: " + testName);
    }

    // 简易断言布尔条件
    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
        } else {
            trace("PASS: " + testName);
        }
    }
}
