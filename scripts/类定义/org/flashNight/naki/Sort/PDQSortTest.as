import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.PDQSortTest {
    
    // 运行所有测试
    public static function runTests():Void {
        trace("Starting PDQSort Tests...");
        PDQSortTest.testEmptyArray();
        PDQSortTest.testSingleElement();
        PDQSortTest.testAlreadySorted();
        PDQSortTest.testReverseSorted();
        PDQSortTest.testRandomArray();
        PDQSortTest.testDuplicateElements();
        PDQSortTest.testAllSameElements();
        PDQSortTest.testCustomCompareFunction();
        PDQSortTest.runPerformanceTests();
        trace("All PDQSort Tests Completed.");
    }
    
    // 简单断言实现
    private static function assertEquals(expected:Array, actual:Array, testName:String):Void {
        if (expected.length != actual.length) {
            trace("FAIL: " + testName + " - Array lengths differ. Expected: " + expected.length + ", Actual: " + actual.length);
            return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                trace("FAIL: " + testName + " - Arrays differ at index " + i + ". Expected: " + expected[i] + ", Actual: " + actual[i]);
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
    
    // 测试空数组
    private static function testEmptyArray():Void {
        var arr:Array = [];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals([], sorted, "Empty Array Test");
    }
    
    // 测试单元素数组
    private static function testSingleElement():Void {
        var arr:Array = [42];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals([42], sorted, "Single Element Array Test");
    }
    
    // 测试已排序数组
    private static function testAlreadySorted():Void {
        var arr:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        var sortedCopy:Array = arr.slice(); // 使用 slice 复制数组
        var sorted:Array = PDQSort.sort(arr.slice(), null);
        assertEquals(sortedCopy, sorted, "Already Sorted Array Test");
    }
    
    // 测试逆序数组
    private static function testReverseSorted():Void {
        var arr:Array = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
        var expected:Array = arr.slice();
        expected.reverse(); // 分开调用 reverse()
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "Reverse Sorted Array Test");
    }
    
    // 测试随机数组
    private static function testRandomArray():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5];
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC); // 使用内置排序进行比较
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "Random Array Test");
    }
    
    // 测试包含重复元素的数组
    private static function testDuplicateElements():Void {
        var arr:Array = [5, 3, 8, 3, 9, 1, 5, 7, 3];
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC); // 使用内置排序进行比较
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(expected, sorted, "Duplicate Elements Array Test");
    }
    
    // 测试全部相同元素的数组
    private static function testAllSameElements():Void {
        var arr:Array = [7, 7, 7, 7, 7, 7, 7];
        var sorted:Array = PDQSort.sort(arr, null);
        assertEquals(arr, sorted, "All Same Elements Array Test");
    }
    
    // 测试自定义比较函数
    private static function testCustomCompareFunction():Void {
        var arr:Array = ["apple", "Orange", "banana", "grape", "Cherry"];
        // 自定义比较函数（忽略大小写）
        var compareFunc:Function = function(a:String, b:String):Number {
            var aLower:String = a.toLowerCase();
            var bLower:String = b.toLowerCase();
            if (aLower < bLower) return -1;
            if (aLower > bLower) return 1;
            return 0;
        };
        var expected:Array = arr.slice();
        expected.sort(compareFunc); // 使用自定义比较函数进行排序
        var sorted:Array = PDQSort.sort(arr, compareFunc);
        assertEquals(expected, sorted, "Custom Compare Function Test");
    }
    
    // 性能评估模块
    private static function runPerformanceTests():Void {
        trace("\nStarting Performance Tests...");
        var sizes:Array = [1000, 10000, 100000];
        var distributions:Array = ["random", "sorted", "reverse", "duplicates", "allSame"];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            for (var j:Number = 0; j < distributions.length; j++) {
                var distribution:String = distributions[j];
                var arr:Array = generateArray(size, distribution);
                var arrCopy:Array = arr.slice();
                var compareFunc:Function = null; // 使用默认比较
                
                // 测量执行时间
                var startTime:Number = getTimer();
                PDQSort.sort(arrCopy, compareFunc);
                var endTime:Number = getTimer();
                var timeTaken:Number = endTime - startTime;
                
                // 验证排序正确性
                var expected:Array;
                switch (distribution) {
                    case "random":
                    case "duplicates":
                        expected = arr.slice();
                        expected.sort(Array.NUMERIC);
                        break;
                    case "allSame":
                        expected = arr.slice();
                        break;
                    case "sorted":
                        expected = arr.slice();
                        break;
                    case "reverse":
                        expected = arr.slice();
                        expected.reverse(); // 分开调用 reverse()
                        break;
                    default:
                        expected = arr.slice();
                        expected.sort(Array.NUMERIC);
                }
                var isCorrect:Boolean = compareArrays(expected, arrCopy);
                
                // 输出结果
                trace("Size: " + size + ", Distribution: " + distribution + ", Time: " + timeTaken + "ms, Correct: " + isCorrect);
            }
        }
        trace("Performance Tests Completed.\n");
    }
    
    // 生成不同分布的数组
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
    
    // 比较两个数组是否相同
    private static function compareArrays(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) return false;
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i]) return false;
        }
        return true;
    }
    
}
