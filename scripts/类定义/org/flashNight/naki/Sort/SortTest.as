/**
 * SortTest 类
 * 位于 org.flashNight.naki.Sort 包下
 * 用于测试和评估不同排序算法在各种场景下的表现
 */
class org.flashNight.naki.Sort.SortTest {
    
    /**
     * 构造函数
     */
    public function SortTest() {
        // 可以在此初始化测试参数或配置
    }
    
    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("Starting Sort Tests...\n");
        
        // 功能性测试
        trace("=== 功能性测试 ===");
        testEmptyArray();
        testSingleElementArray();
        testAlreadySortedArray();
        testReverseSortedArray();
        testRandomArray();
        testDuplicateElementsArray();
        testAllSameElementsArray();
        testCustomCompareFunction();
        
        // 性能测试
        trace("\n=== 性能测试 ===");
        performPerformanceTests();
        
        trace("\nAll Sort Tests Completed.");
    }
    
    /**
     * 定义要测试的排序方法
     */
    private var sortMethods:Array = [
        { name: "InsertionSort", sort: org.flashNight.naki.Sort.InsertionSort.sort },
        { name: "PDQSort", sort: org.flashNight.naki.Sort.PDQSort.sort },
        { name: "QuickSort", sort: org.flashNight.naki.Sort.QuickSort.sort },
        { name: "AdaptiveSort", sort: org.flashNight.naki.Sort.QuickSort.adaptiveSort },
        { name: "TimSort", sort: org.flashNight.naki.Sort.TimSort.sort },
        // 新增内建排序
        { name: "BuiltInSort", sort: builtInSort }
    ];
    
    /**
     * 内建排序方法
     * @param arr 要排序的数组
     * @param compareFunction 可选的比较函数
     * @return 排序后的数组
     */
    private function builtInSort(arr:Array, compareFunction:Function):Array {
        if (compareFunction != null) {
            arr.sort(compareFunction);
        } else {
            arr.sort(Array.NUMERIC);
        }
        return arr;
    }
    
    /**
     * 测试空数组
     */
    private function testEmptyArray():Void {
        var testName:String = "Empty Array Test";
        var testArray:Array = [];
        var expected:Array = [];
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试单元素数组
     */
    private function testSingleElementArray():Void {
        var testName:String = "Single Element Array Test";
        var testArray:Array = [42];
        var expected:Array = [42];
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试已排序数组
     */
    private function testAlreadySortedArray():Void {
        var testName:String = "Already Sorted Array Test";
        var testArray:Array = [1, 2, 3, 4, 5];
        var expected:Array = [1, 2, 3, 4, 5];
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试逆序数组
     */
    private function testReverseSortedArray():Void {
        var testName:String = "Reverse Sorted Array Test";
        var testArray:Array = [5, 4, 3, 2, 1];
        var expected:Array = [1, 2, 3, 4, 5];
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试随机数组
     */
    private function testRandomArray():Void {
        var testName:String = "Random Array Test";
        var testArray:Array = generateRandomArray(100);
        var expected:Array = copyArray(testArray);
        expected.sort(Array.NUMERIC); // 使用默认排序作为期望结果
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试重复元素数组
     */
    private function testDuplicateElementsArray():Void {
        var testName:String = "Duplicate Elements Array Test";
        var testArray:Array = [3, 1, 2, 3, 1, 2, 3, 1, 2];
        var expected:Array = [1, 1, 1, 2, 2, 2, 3, 3, 3];
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试全相同元素数组
     */
    private function testAllSameElementsArray():Void {
        var testName:String = "All Same Elements Array Test";
        var testArray:Array = [7, 7, 7, 7, 7, 7];
        var expected:Array = [7, 7, 7, 7, 7, 7];
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, null);
            if (!arraysEqual(sortedArray, expected, null)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 测试自定义比较函数
     */
    private function testCustomCompareFunction():Void {
        var testName:String = "Custom Compare Function Test";
        var testArray:Array = [{val: 3}, {val: 1}, {val: 2}];
        var expected:Array = [{val: 1}, {val: 2}, {val: 3}];
        
        // 自定义比较函数，根据对象的 val 属性排序
        var compareFunction:Function = function(a:Object, b:Object):Number {
            if (a.val < b.val) return -1;
            if (a.val > b.val) return 1;
            return 0;
        };
        
        var passed:Boolean = true;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var sortMethod = sortMethods[i];
            var sortedArray:Array = copyArray(testArray);
            sortedArray = sortMethod.sort(sortedArray, compareFunction);
            if (!arraysEqual(sortedArray, expected, compareFunction)) {
                passed = false;
                trace("FAIL: " + sortMethod.name + " failed " + testName);
            }
        }
        
        if (passed) {
            trace("PASS: " + testName);
        }
    }
    
    /**
     * 进行性能测试
     */
    private function performPerformanceTests():Void {
        var dataSizes:Array = [100, 300, 1000, 3000, 10000]; // 可根据需要调整数据规模
        var distributions:Array = ["random", "sorted", "reverse", "duplicates", "allSame", "partiallySorted"]; // 新增 "partiallySorted"
        
        for (var i:Number = 0; i < dataSizes.length; i++) {
            var size:Number = dataSizes[i];
            for (var j:Number = 0; j < distributions.length; j++) {
                var distribution:String = distributions[j];
                var testArray:Array = generateArray(size, distribution);
                var expected:Array;
                
                if (distribution == "customObject") {
                    // 如果需要测试对象数组，可以在这里定义
                    expected = copyArray(testArray);
                    // 自定义排序
                    var compareFunction:Function = function(a:Object, b:Object):Number {
                        if (a.val < b.val) return -1;
                        if (a.val > b.val) return 1;
                        return 0;
                    };
                    // 使用自定义比较函数排序期望数组
                    for (var m:Number =1; m < expected.length; m++) {
                        var key:Object = expected[m];
                        var left:Number = 0;
                        var right:Number = m;
                        while (left < right) {
                            var mid:Number = (left + right) >> 1;
                            if (compareFunction(expected[mid], key) > 0) {
                                right = mid;
                            } else {
                                left = mid + 1;
                            }
                        }
                        for (var k:Number = m; k > left; k--) {
                            expected[k] = expected[k -1];
                        }
                        expected[left] = key;
                    }
                } else {
                    expected = copyArray(testArray);
                    if (distribution == "partiallySorted") {
                        // 部分有序数组的期望结果
                        expected.sort(Array.NUMERIC);
                    } else {
                        expected.sort(Array.NUMERIC); // 使用默认排序作为期望结果
                    }
                }
                
                trace("\nSize: " + size + ", Distribution: " + distribution);
                
                for (var k:Number = 0; k < sortMethods.length; k++) {
                    var sortMethod = sortMethods[k];
                    var arrayToSort:Array = copyArray(testArray);
                    var startTime:Number = getTimer();
                    if (distribution == "customObject") {
                        // 使用自定义比较函数
                        var compareFuncForSort:Function = function(a:Object, b:Object):Number {
                            if (a.val < b.val) return -1;
                            if (a.val > b.val) return 1;
                            return 0;
                        };
                        arrayToSort = sortMethod.sort(arrayToSort, compareFuncForSort);
                    } else {
                        arrayToSort = sortMethod.sort(arrayToSort, null);
                    }
                    var endTime:Number = getTimer();
                    var timeTaken:Number = endTime - startTime;
                    var correct:Boolean;
                    
                    if (distribution == "customObject") {
                        var compareFuncForExpected:Function = function(a:Object, b:Object):Number {
                            if (a.val < b.val) return -1;
                            if (a.val > b.val) return 1;
                            return 0;
                        };
                        correct = arraysEqual(arrayToSort, expected, compareFuncForExpected);
                    } else {
                        correct = arraysEqual(arrayToSort, expected, null);
                    }
                    
                    trace("Sort: " + sortMethod.name + ", Time: " + timeTaken + "ms, Correct: " + correct);
                }
            }
        }
        
        trace("Performance Tests Completed.");
    }
    
    /**
     * 生成不同分布的数组
     * @param size 数组大小
     * @param distribution 分布类型：random, sorted, reverse, duplicates, allSame, partiallySorted
     * @return 生成的数组
     */
    private function generateArray(size:Number, distribution:String):Array {
        switch (distribution) {
            case "random":
                return generateRandomArray(size);
            case "sorted":
                return generateSortedArray(size);
            case "reverse":
                return generateReverseSortedArray(size);
            case "duplicates":
                return generateDuplicateElementsArray(size);
            case "allSame":
                return generateAllSameElementsArray(size);
            case "partiallySorted":
                return generatePartiallySortedArray(size);
            default:
                return generateRandomArray(size);
        }
    }
    
    /**
     * 生成部分有序数组
     * @param size 数组大小
     * @return 部分有序数组
     */
    private function generatePartiallySortedArray(size:Number):Array {
        var arr:Array = generateSortedArray(size);
        // 随机打乱数组中的一部分元素，例如 10%
        var shuffleCount:Number = Math.floor(size * 0.1);
        for (var i:Number = 0; i < shuffleCount; i++) {
            var index1:Number = Math.floor(Math.random() * size);
            var index2:Number = Math.floor(Math.random() * size);
            var temp = arr[index1];
            arr[index1] = arr[index2];
            arr[index2] = temp;
        }
        return arr;
    }
    
    /**
     * 生成随机数组
     * @param size 数组大小
     * @return 随机数组
     */
    private function generateRandomArray(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.floor(Math.random() * size));
        }
        return arr;
    }
    
    /**
     * 生成已排序数组
     * @param size 数组大小
     * @return 已排序数组
     */
    private function generateSortedArray(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i);
        }
        return arr;
    }
    
    /**
     * 生成逆序数组
     * @param size 数组大小
     * @return 逆序数组
     */
    private function generateReverseSortedArray(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = size; i > 0; i--) {
            arr.push(i);
        }
        return arr;
    }
    
    /**
     * 生成重复元素数组
     * @param size 数组大小
     * @return 重复元素数组
     */
    private function generateDuplicateElementsArray(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.floor(Math.random() * 10)); // 10个不同的值
        }
        return arr;
    }
    
    /**
     * 生成全相同元素数组
     * @param size 数组大小
     * @return 全相同元素数组
     */
    private function generateAllSameElementsArray(size:Number):Array {
        var arr:Array = [];
        var value:Number = Math.floor(Math.random() * 100);
        for (var i:Number = 0; i < size; i++) {
            arr.push(value);
        }
        return arr;
    }
    
    /**
     * 复制数组
     * @param arr 原数组
     * @return 复制后的数组
     */
    private function copyArray(arr:Array):Array {
        var newArr:Array = [];
        for (var i:Number = 0; i < arr.length; i++) {
            // 深度复制对象元素
            if (typeof(arr[i]) == "object" && arr[i] != null) {
                newArr.push(copyObject(arr[i]));
            } else {
                newArr.push(arr[i]);
            }
        }
        return newArr;
    }
    
    /**
     * 复制对象
     * @param obj 原对象
     * @return 复制后的对象
     */
    private function copyObject(obj:Object):Object {
        var newObj:Object = {};
        for (var key:String in obj) {
            newObj[key] = obj[key];
        }
        return newObj;
    }
    
    /**
     * 比较两个数组是否相等
     * @param arr1 第一个数组
     * @param arr2 第二个数组
     * @param compareFunction 可选的比较函数，用于自定义元素比较
     * @return 是否相等
     */
    private function arraysEqual(arr1:Array, arr2:Array, compareFunction:Function):Boolean {
        if (arr1.length != arr2.length) {
            return false;
        }
        for (var i:Number = 0; i < arr1.length; i++) {
            if (compareFunction != null) {
                if (compareFunction(arr1[i], arr2[i]) !== 0) {
                    return false;
                }
            } else {
                if (arr1[i] !== arr2[i]) {
                    return false;
                }
            }
        }
        return true;
    }
}
