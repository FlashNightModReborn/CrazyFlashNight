import org.flashNight.gesh.iterator.*;
import org.flashNight.naki.DataStructures.*;
 
/**
 * 用于测试 TreeSetIteratorTest 功能与性能的示例类。
 * 
 * 运行测试方法:
 *   TreeSetIteratorTest.runAllTests();
 */
class org.flashNight.gesh.iterator.TreeSetIteratorTest
{
    // 内置断言: 断言失败会抛出异常或打印错误
    private static function assertEquals(actual:Object, expected:Object, message:String):Void {
        if (actual !== expected) {
            var err:String = "Assertion Failed: " + message + 
                             " (expected=" + expected + ", actual=" + actual + ")";
            trace(err);
            throw new Error(err);
        } else {
            trace("✔ " + message + " => PASS");
        }
    }

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            var err:String = "Assertion Failed: " + message + " (condition is false)";
            trace(err);
            throw new Error(err);
        } else {
            trace("✔ " + message + " => PASS");
        }
    }

    private static function assertFalse(condition:Boolean, message:String):Void {
        if (condition) {
            var err:String = "Assertion Failed: " + message + " (condition is true)";
            trace(err);
            throw new Error(err);
        } else {
            trace("✔ " + message + " => PASS");
        }
    }

    /**
     * 运行所有测试
     */
    public static function runAllTests():Void
    {
        trace("start");
        testEmptyTree();
        testSingleElement();
        testMultipleElements();
        testResetFunction();
        testPerformance(10000);
        // 视需求可再添加其他测试...
    }

    /**
     * 1) 测试空树遍历
     */
    private static function testEmptyTree():Void
    {
        trace("=== testEmptyTree ===");
        var emptySet:TreeSet = new TreeSet();
        var it:IIterator = new TreeSetMinimalIterator(emptySet);

        assertFalse(it.hasNext(), "空树中，迭代器 hasNext() 应该为 false");

        var result:IterationResult = it.next();
        assertTrue(result.isDone(), "空树的 next() 结果应为 done=true");
        assertEquals(result.getValue(), undefined, "空树的 next() 的 value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 2) 测试单个元素的 TreeSet
     */
    private static function testSingleElement():Void
    {
        trace("=== testSingleElement ===");
        var singleSet:TreeSet = new TreeSet();
        singleSet.add(42);

        var it:IIterator = new TreeSetMinimalIterator(singleSet);
        assertTrue(it.hasNext(), "单元素时，迭代器 hasNext() 应该为 true");

        var result:IterationResult = it.next();
        assertFalse(result.isDone(), "获取到第一个元素时，应 done=false");
        assertEquals(result.getValue(), 42, "返回的元素值应为 42");

        // 再次调用 next()
        var result2:IterationResult = it.next();
        assertTrue(result2.isDone(), "已经没有更多元素了，应 done=true");
        assertEquals(result2.getValue(), undefined, "应返回 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 3) 测试多个元素的 TreeSet (手动插入)
     */
    private static function testMultipleElements():Void
    {
        trace("=== testMultipleElements ===");
        var treeSet:TreeSet = new TreeSet(); 
        // 添加一些无序元素
        treeSet.add(30);
        treeSet.add(10);
        treeSet.add(20);
        treeSet.add(35);
        treeSet.add(40);
        treeSet.add(50);

        var it:IIterator = new TreeSetMinimalIterator(treeSet);

        // 中序遍历应返回从小到大的序列: 10, 20, 30, 35, 40, 50
        var expectedValues:Array = [10, 20, 30, 35, 40, 50];
        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            // 每次拿到的元素不能是 done
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与中序遍历结果一致");
            index++;
        }

        // 确认已经遍历完
        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 4) 测试 reset 功能
     */
    private static function testResetFunction():Void
    {
        trace("=== testResetFunction ===");
        var treeSet:TreeSet = new TreeSet();
        treeSet.add(1);
        treeSet.add(2);
        treeSet.add(3);

        var it:IIterator = new TreeSetMinimalIterator(treeSet);

        // 先消耗一部分迭代
        var part1:IterationResult = it.next(); // 应该是 1
        assertEquals(part1.getValue(), 1, "第一次迭代应返回 1");

        // reset
        it.reset();

        // reset 后，应再次从第一个(最小值)开始
        var rePart1:IterationResult = it.next();
        assertEquals(rePart1.getValue(), 1, "重置后，第一个迭代值应再次是 1");

        it.dispose();
        trace("");
    }

    /**
     * 5) 测试在大规模数据下的性能
     * @param numElements 测试插入的元素总量
     */
    private static function testPerformance(numElements:Number):Void
    {
        trace("=== testPerformance (numElements=" + numElements + ") ===");

        // 构建一个包含 [1..numElements] 的 TreeSet
        var testSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= numElements; i++) {
            testSet.add(i);
        }

        // 创建迭代器，并计时
        var startTime:Number = getTimer();
        var it:IIterator = new TreeSetMinimalIterator(testSet);

        var count:Number = 0;
        while (it.hasNext()) {
            it.next();
            count++;
        }
        it.dispose();

        var endTime:Number = getTimer();
        trace("迭代完成，耗时: " + (endTime - startTime) + " ms, 计数: " + count);

        // 验证遍历到的元素数量是否与 numElements 相匹配
        assertEquals(count, numElements, 
            "遍历计数应与插入数相同, count=" + count + " vs numElements=" + numElements);

        trace("");
    }
}
