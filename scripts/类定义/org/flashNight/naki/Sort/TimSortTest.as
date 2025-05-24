import org.flashNight.naki.Sort.*;

/**
 * TimSortTest 类
 *
 * 这是 TimSort 的测试类，包含多种测试方法来验证 TimSort 的正确性和性能。
 * 与 PDQSortTest 类似，所有测试方法都内联展开，旨在保持一致的代码风格。
 */
class org.flashNight.naki.Sort.TimSortTest {

    public static function runTests():Void {
        trace("Starting TimSort Tests...\n");

        // 基础功能测试
        testEmptyArray();
        testSingleElement();
        testAlreadySorted();
        testReverseSorted();
        testRandomArray();
        testDuplicateElements();
        testAllSameElements();
        testCustomCompareFunction();
        
        // 合并策略专项测试
        testForceThreeRunMerge();
        testCascadeMerge();
        testStabilityMerge();
        testMergeBoundaryCondition();
        testMergeWithTinyRuns();
        
        // 性能测试
        runPerformanceTests();
        
        trace("\nAll TimSort Tests Completed.");
    }

    // region 基础断言方法
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
    // endregion

    // region 基础功能测试
    private static function testEmptyArray():Void {
        var arr:Array = [];
        assertEquals(arr, TimSort.sort(arr, null), "空数组测试");
    }

    private static function testSingleElement():Void {
        var arr:Array = [42];
        assertEquals(arr, TimSort.sort(arr, null), "单元素数组测试");
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
            // 手动实现不区分大小写的字符串比较
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

    // endregion

    // region 合并策略专项测试
    private static function testForceThreeRunMerge():Void {
        // 构造三个需要合并的 run (长度分别为3,5,8)
        var arr:Array = [
            // 降序 run1 (会被反转)
            5,4,3,
            // 升序 run2
            6,7,8,9,10,
            // 降序 run3 (会被反转)
            18,17,16,15,14,13,12,11
        ];
        
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        
        var sorted:Array = TimSort.sort(arr, null);
        assertEquals(expected, sorted, "强制三路合并测试");
    }

    private static function testCascadeMerge():Void {
        // 构造需要级联合并的小 run 序列
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
        // 创建带稳定标记的对象
        var createObj = function(key:Number, id:String):Object { return {key:key, id:id}; };
        
        // Run1: 保持顺序 objA1, objA2, objA3
        var objA1:Object = createObj(1, "A1");
        var objA2:Object = createObj(1, "A2");
        var objA3:Object = createObj(1, "A3");
        
        // Run2: 降序排列 (会被反转为 objB3, objB2, objB1)
        var objB1:Object = createObj(1, "B1");
        var objB2:Object = createObj(1, "B2");
        var objB3:Object = createObj(1, "B3");
        
        var arr:Array = [objA1, objA2, objA3, objB3, objB2, objB1];
        var compare:Function = function(a:Object, b:Object):Number {
            return a.key - b.key;
        };
        
        var sorted:Array = TimSort.sort(arr, compare);
        
        // 修改后的稳定性验证
        var stabilityPassed:Boolean = true;
        stabilityPassed = (sorted[0].id == "A1") 
                    && (sorted[1].id == "A2")
                    && (sorted[2].id == "A3")
                    && (sorted[3].id == "B3")
                    && (sorted[4].id == "B2")
                    && (sorted[5].id == "B1");
        
        assertTrue(
            stabilityPassed,
            "合并稳定性测试",
            "相同键值的元素顺序在合并后发生改变"
        );
    }

    private static function testMergeBoundaryCondition():Void {
        // 构造刚好触发合并阈值的边界条件
        var arr:Array = [];
        // Run1: 32元素升序
        for(var i:Number=0; i<32; i++) arr.push(i);
        // Run2: 16元素降序
        for(var j:Number=47; j>=32; j--) arr.push(j);
        // Run3: 15元素升序 (总和刚好超过合并阈值)
        for(var k:Number=48; k<63; k++) arr.push(k);
        
        var sorted:Array = TimSort.sort(arr, null);
        var expected:Array = arr.concat();
        expected.sort(Array.NUMERIC);
        assertEquals(expected, sorted, "合并边界条件测试");
    }

    private static function testMergeWithTinyRuns():Void {
        // 构造大量极小 run 测试合并策略
        var arr:Array = [];
        for(var i:Number=0; i<100; i++){
            // 交替创建升序和降序的2元素run
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
    // endregion

    // region 性能测试
    private static function runPerformanceTests():Void {
        trace("\n开始性能测试...");
        var sizes:Array = [1000, 10000];
        var distributions:Array = [
            "random", 
            "sorted", 
            "reverse", 
            "mergeStress",  // 新增合并压力测试
            "allSame"
        ];
        
        for(var i:Number=0; i<sizes.length; i++){
            var size:Number = sizes[i];
            for(var j:Number=0; j<distributions.length; j++){
                var dist:String = distributions[j];
                var arr:Array = generateTestArray(size, dist);
                
                var start:Number = getTimer();
                var sorted:Array = TimSort.sort(arr.concat(), null);
                var time:Number = getTimer() - start;
                
                verifySorted(arr, sorted, dist);
                trace("性能测试 - 大小: " + size + ", 分布: " + dist + ", 耗时: " + time + "ms");
            }
        }
        trace("性能测试完成\n");
    }

    private static function generateTestArray(size:Number, type:String):Array {
        var arr:Array = [];
        switch(type){
            case "random":
                for(var i:Number=0; i<size; i++) arr.push(Math.random()*size);
                break;
            case "sorted":
                for(var j:Number=0; j<size; j++) arr.push(j);
                break;
            case "reverse":
                for(var k:Number=0; k<size; k++) arr.push(size - k);
                break;
            case "mergeStress": // 合并压力测试数据
                for(var m:Number=0; m<size; m++){
                    if(m%4 == 0 && m+3 < size){ // 每4个元素构造降序run
                        arr.push(m+3, m+2, m+1, m);
                        m += 3;
                    }else{
                        arr.push(Math.random()*size);
                    }
                }
                break;
            case "allSame":
                for(var n:Number=0; n<size; n++) arr.push(42);
                break;
        }
        return arr;
    }

    private static function verifySorted(original:Array, sorted:Array, testName:String):Void {
        var expected:Array = original.concat();
        expected.sort(Array.NUMERIC);
        
        if(expected.length != sorted.length){
            trace("性能测试验证失败 - " + testName + ": 数组长度改变");
            return;
        }
        
        for(var i:Number=0; i<expected.length; i++){
            if(expected[i] !== sorted[i]){
                trace("性能测试验证失败 - " + testName + ": 错误索引 " + i);
                return;
            }
        }
    }
    // endregion
}
