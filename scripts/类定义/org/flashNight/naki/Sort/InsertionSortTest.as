import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.InsertionSortTest {

    public static function runTests():Void {
        testCorrectness();
        testPerformance();
    }

    private static function testCorrectness():Void {
        // 测试用例1：空数组
        var arr1:Array = [];
        var sortedArr1:Array = InsertionSort.sort(arr1);
        trace("Test Case 1 (Empty Array): " + (sortedArr1.join(", ") === "" ? "Passed" : "Failed"));

        // 测试用例2：单元素数组
        var arr2:Array = [1];
        var sortedArr2:Array = InsertionSort.sort(arr2);
        trace("Test Case 2 (Single Element Array): " + (sortedArr2.join(", ") === "1" ? "Passed" : "Failed"));

        // 测试用例3：已排序数组
        var arr3:Array = [1, 2, 3, 4, 5];
        var sortedArr3:Array = InsertionSort.sort(arr3);
        trace("Test Case 3 (Already Sorted Array): " + (sortedArr3.join(", ") === "1, 2, 3, 4, 5" ? "Passed" : "Failed"));

        // 测试用例4：逆序数组
        var arr4:Array = [5, 4, 3, 2, 1];
        var sortedArr4:Array = InsertionSort.sort(arr4);
        trace("Test Case 4 (Reverse Sorted Array): " + (sortedArr4.join(", ") === "1, 2, 3, 4, 5" ? "Passed" : "Failed"));

        // 测试用例5：随机数组
        var arr5:Array = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
        var sortedArr5:Array = InsertionSort.sort(arr5);
        var expectedSortedArr5:Array = [1, 1, 2, 3, 3, 4, 5, 5, 5, 6, 9];
        trace("Test Case 5 (Random Array): " + (arraysEqual(sortedArr5, expectedSortedArr5) ? "Passed" : "Failed"));
    }

    private static function testPerformance():Void {
        var arraySize:Number = 50; // 小规模数组大小
        var iterations:Number = 1000; // 重复实验次数
        var totalTime:Number = 0;

        for (var k:Number = 0; k < iterations; k++) {
            // 生成小规模随机数组
            var smallArr:Array = [];
            for (var i:Number = 0; i < arraySize; i++) {
                smallArr.push(Math.floor(Math.random() * 1000));
            }

            var startTime:Number = getTimer();
            InsertionSort.sort(smallArr);
            var endTime:Number = getTimer();

            totalTime += (endTime - startTime);
        }

        var averageTime:Number = totalTime / iterations;
        trace("Performance Test: Average time to sort " + arraySize + " elements over " + iterations + " iterations is " + averageTime + " ms.");
    }

    private static function arraysEqual(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) {
            return false;
        }
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] != arr2[i]) {
                return false;
            }
        }
        return true;
    }
}