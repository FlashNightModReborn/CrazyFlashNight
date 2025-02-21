import org.flashNight.naki.Sort.*;

/**
 * TimSortTest 类
 * 
 * 这是 TimSort 的测试类，包含多种测试方法来验证 TimSort 的正确性和性能。
 * 与 PDQSortTest 类似，所有测试方法都内联展开，旨在保持一致的代码风格。
 */
class org.flashNight.naki.Sort.TimSortTest {
    
    /**
     * 运行所有测试
     */
    public static function runTests():Void {
        trace("Starting TimSort Tests...");
        // 基础测试
        TimSortTest.testEmptyArray();
        TimSortTest.testSingleElement();
        TimSortTest.testAlreadySorted();
        TimSortTest.testReverseSorted();
        TimSortTest.testRandomArray();
        TimSortTest.testDuplicateElements();
        TimSortTest.testAllSameElements();
        TimSortTest.testCustomCompareFunction();
        
        // 增强测试
        TimSortTest.testForceMergeNonAdjacentRuns();
        TimSortTest.testForceMergeComplexNonAdjacentRuns(); // 新增复杂场景测试
        TimSortTest.testStability();
        TimSortTest.testLargeScaleStability(); // 新增大规模稳定性测试
        TimSortTest.testStackInvariantViolation();
        TimSortTest.testCustomCompareEdgeCases();
        TimSortTest.testLargeReversedRunMerge();
        
        // 性能测试
        TimSortTest.runPerformanceTests();
        trace("All TimSort Tests Completed.");
    }
    
    /**
     * 简单断言实现，用于比较预期结果与实际结果
     * 
     * @param expected 预期的数组
     * @param actual 实际排序后的数组
     * @param testName 测试名称
     */
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
    
    /**
     * 简单断言实现，用于验证布尔条件
     * 
     * @param condition 条件是否为真
     * @param testName 测试名称
     * @param message 失败时的提示信息
     */
    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
        } else {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试空数组排序
     */
    private static function testEmptyArray():Void {
        var arr:Array = [];
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals([], sorted, "Empty Array Test");
    }
    
    /**
     * 测试单元素数组排序
     */
    private static function testSingleElement():Void {
        var arr:Array = [42];
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals([42], sorted, "Single Element Array Test");
    }
    
    /**
     * 测试已排序数组排序
     */
    private static function testAlreadySorted():Void {
        var arr:Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        var sortedCopy:Array = arr.slice(); // 使用 slice 复制数组
        var sorted:Array = TimSort.sort(arr.slice(), null);
        assertEquals(sortedCopy, sorted, "Already Sorted Array Test");
    }
    
    /**
     * 测试逆序数组排序
     */
    private static function testReverseSorted():Void {
        var arr:Array = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
        var expected:Array = arr.slice();
        expected.reverse(); // 分开调用 reverse()
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Reverse Sorted Array Test");
    }
    
    /**
     * 测试随机数组排序
     */
    private static function testRandomArray():Void {
        var arr:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5];
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC); // 使用内置排序进行比较
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Random Array Test");
    }
    
    /**
     * 测试包含重复元素的数组排序
     */
    private static function testDuplicateElements():Void {
        var arr:Array = [5, 3, 8, 3, 9, 1, 5, 7, 3];
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC); // 使用内置排序进行比较
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Duplicate Elements Array Test");
    }
    
    /**
     * 测试全部相同元素的数组排序
     */
    private static function testAllSameElements():Void {
        var arr:Array = [7, 7, 7, 7, 7, 7, 7];
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(arr, sorted, "All Same Elements Array Test");
    }
    
    /**
     * 测试自定义比较函数排序
     */
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
        var sorted:Array = TimSort.sort(arr, compareFunc);
        assertEquals(expected, sorted, "Custom Compare Function Test");
    }

    // 新增测试方法 ================================================

    /**
     * 测试强制合并非相邻 Run 的情况（检测合并逻辑错误）
     */
    private static function testForceMergeNonAdjacentRuns():Void {
        // 构造数组：前半部分降序，后半部分升序
        var arr:Array = [5,4,3,2,1,6,7,8,9,10];
        var expected:Array = [1,2,3,4,5,6,7,8,9,10];
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Force Merge Non-Adjacent Runs Test");
    }

    /**
     * 测试排序稳定性（相等元素保持原始顺序）
     */
    private static function testStability():Void {
        // 构造包含相同键值的对象数组
        var obj1 = {key:2, id:1};
        var obj2 = {key:1, id:2};
        var obj3 = {key:2, id:3};
        var arr:Array = [obj1, obj2, obj3];
        // 自定义比较函数只比较 key
        var compare:Function = function(a,b):Number { return a.key - b.key; };
        var sorted:Array = TimSort.sort(arr, compare);                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
        // 验证：相同 key 的元素应保持原始顺序（obj1 在 obj3 前）
        var stabilityPassed:Boolean = 
            (sorted[0] === obj2) && 
            (sorted[1] === obj1) && 
            (sorted[2] === obj3);
        assertTrue(
            stabilityPassed,
            "Stability Test",
            "Equal elements order not preserved"
        );
    }

    /**
     * 测试堆栈不变性违反时的合并顺序
     */
    private static function testStackInvariantViolation():Void {
        // 构造特殊数组触发堆栈合并条件
        var arr:Array = [1,3,5,7,9,2,4,6,8,10,12,14,16,11,13,15,17];
        var expected:Array = arr.slice();
        expected.sort(Array.NUMERIC);
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Stack Invariant Violation Test");
    }

    /**
     * 测试自定义比较函数的边界情况
     */
    private static function testCustomCompareEdgeCases():Void {
        // 测试比较函数返回 0 的情况
        var arr:Array = [{v:2}, {v:2}, {v:2}];
        var compare:Function = function(a,b):Number { return 0; };
        var sorted:Array = TimSort.sort(arr, compare);
        assertTrue(
            compareArrays(arr, sorted),
            "Custom Compare Edge Cases - Zero Result",
            "Array modified when all comparisons return 0"
        );

        // 测试非数值比较
        var arr2:Array = [new Date(2023,1,1), new Date(2022,1,1), new Date(2024,1,1)];
        var compare2:Function = function(a:Date,b:Date):Number { 
            return a.getTime() - b.getTime(); 
        };
        var expected2:Array = [arr2[1], arr2[0], arr2[2]];
        var sorted2:Array = TimSort.sort(arr2, compare2);
        assertEquals(expected2, sorted2, "Custom Compare Edge Cases - Date Objects");
    }

    /**
     * 测试长逆序 Run 的合并（检测反转逻辑）
     */
    private static function testLargeReversedRunMerge():Void {
        // 构造 64 元素的完全逆序数组（超过 MIN_RUN）
        var arr:Array = [];
        for(var i:Number=64; i>0; i--) arr.push(i);
        var expected:Array = arr.slice();
        expected.reverse();
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "Large Reversed Run Merge Test");
    }

    /**
     * 测试复杂非相邻 Run 合并（三明治结构）
     */
    private static function testForceMergeComplexNonAdjacentRuns():Void {
        // 结构：降序1 | 升序1 | 降序2 | 升序2 | 降序3
        var arr:Array = [5,4,3,  6,7,8,  2,1,0,  9,10,11,  15,14,13];
        var expected:Array = [0,1,2,3,4,5,6,7,8,9,10,11,13,14,15];
        var sorted:Array = TimSort.sort(arr.concat(), null); // 使用concat防止原数组被修改
        assertEquals(expected, sorted, "Complex Non-Adjacent Runs Test");
    }

    /**
     * 大规模稳定性测试（1000元素）
     */
    private static function testLargeScaleStability():Void {
        // 生成含重复键值的大数组
        var arr:Array = [];
        for(var i:Number=0; i<1000; i++){
            arr.push({key:i%10, id:i}); // 每10个元素有相同key
        }
        
        // 打乱数组顺序（保留稳定性验证条件）
        arr.sort(function():Number { return Math.random() > 0.5 ? 1 : -1; });
        
        // 自定义比较函数
        var compare:Function = function(a,b):Number { return a.key - b.key; };
        var sorted:Array = TimSort.sort(arr.concat(), compare);
        
        // 验证稳定性
        var stabilityPassed:Boolean = true;
        var lastIDMap:Object = {};
        for(var j:Number=0; j<sorted.length; j++){
            var currentKey:Number = sorted[j].key;
            if(lastIDMap[currentKey] != undefined){
                if(sorted[j].id < lastIDMap[currentKey]){
                    stabilityPassed = false;
                    break;
                }
            }
            lastIDMap[currentKey] = sorted[j].id;
        }
        assertTrue(stabilityPassed, "Large Scale Stability Test", "Order of equal elements disrupted");
    }
    
    /**
     * 性能评估模块
     */
    private static function runPerformanceTests():Void {
        trace("\nStarting Performance Tests...");
        var sizes:Array = [1000, 10000, 50000];
        var distributions:Array = [
            "random", "sorted", "reverse", 
            "duplicates", "allSame", 
            "mergeStress", "gallopingFriendly" // 新增Galloping优化测试场景
        ];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            for (var j:Number = 0; j < distributions.length; j++) {
                var distribution:String = distributions[j];
                var arr:Array = generateArray(size, distribution);
                
                // 重置计数器
                TimSort.mergeCount = 0;
                TimSort.gallopingCount = 0; // 需要TimSort类暴露此变量
                
                // 执行排序
                var arrCopy:Array = arr.concat();
                var startTime:Number = getTimer();
                TimSort.sort(arrCopy, null);
                var endTime:Number = getTimer();
                
                // 验证正确性
                var expected:Array = getExpectedSortedArray(arr, distribution);
                var isCorrect:Boolean = compareArrays(expected, arrCopy);
                
                // 输出详细指标
        trace("Size: " + size + 
            " | Dist: " + padRight(distribution, 14) + 
            " | Time: " + padLeft(String(endTime - startTime), 4) + "ms" +
            " | Merges: " + padLeft(String(TimSort.mergeCount), 3) +
            " | Gallops: " + padLeft(String(TimSort.gallopingCount), 4) +
            " | Correct: " + (isCorrect ? "✓" : "✗"));
            }
        }
        trace("Performance Tests Completed.\n");
    }
    
    /**
     * 生成不同分布的数组
     * 
     * @param size 数组大小
     * @param distribution 分布类型 ("random", "sorted", "reverse", "duplicates", "allSame")
     * @return 生成的数组
     */
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
            case "mergeStress": // 新增专门测试合并压力的分布
                // 生成交替的升序/降序片段
                var segmentSize:Number = 16;
                var isAscending:Boolean = true;
                for (var i:Number = 0; i < size; i++) {
                    if(i % segmentSize == 0) isAscending = !isAscending;
                    arr[i] = isAscending ? i : segmentSize - (i % segmentSize);
                }
                break;
            case "gallopingFriendly":
                // 生成适合Galloping模式的长有序序列
                var current:Number = 0;
                for(var i:Number=0; i<size; i++){
                    if(Math.random() < 0.8){
                        current += Math.floor(Math.random()*3);
                    }else{
                        current -= Math.floor(Math.random()*50);
                    }
                    arr[i] = current;
                }
                break;
            case "mergeStress":
                // 增强压力测试：随机片段长度
                var isAscending:Boolean = true;
                var pos:Number = 0;
                while(pos < size){
                    var segmentSize:Number = 16 + Math.floor(Math.random()*16);
                    var startValue:Number = Math.floor(Math.random()*100);
                    for(var j:Number=0; j<segmentSize && pos<size; j++){
                        arr[pos] = isAscending ? startValue+j : startValue+segmentSize-j;
                        pos++;
                    }
                    isAscending = !isAscending;
                }
                break;
            default:
                for (var n:Number = 0; n < size; n++) {
                    arr[n] = Math.floor(Math.random() * size);
                }
        }
        return arr;
    }

    /**
     * 模拟访问原 TimSort 类的栈指针用于性能统计
     * （注：实际需根据实现调整，此处为测试用模拟）
     */
    private static function sp():Number {
        // 此方法需要根据实际实现访问私有变量，
        // 此处仅为示意，假设通过某种方式获取了栈指针值
        return 0; // 实际应返回 TimSort 内部栈指针
    }

    /**
     * 生成预期排序结果（分离逻辑便于维护）
     */
    private static function getExpectedSortedArray(arr:Array, distribution:String):Array {
        var expected:Array = arr.concat();
        switch(distribution) {
            case "reverse": 
                expected.sort(Array.NUMERIC);
                break;
            case "gallopingFriendly":
                // 特殊处理有序数据的预期结果
                expected.sort(Array.NUMERIC);
                break;
            default:
                expected.sort(Array.NUMERIC);
        }
        return expected;
    }

    /**
     * 字符串对齐辅助方法
     */
    private static function padLeft(str:String, length:Number, char:String):String {
        char = char || " ";
        while(str.length < length) str = char + str;
        return str;
    }
    
    private static function padRight(str:String, length:Number, char:String):String {
        char = char || " ";
        while(str.length < length) str += char;
        return str;
    }
    
    /**
     * 比较两个数组是否相同
     * 
     * @param arr1 第一个数组
     * @param arr2 第二个数组
     * @return 两个数组是否相同
     */
    private static function compareArrays(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) return false;
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i]) return false;
        }
        return true;
    }
    
}
