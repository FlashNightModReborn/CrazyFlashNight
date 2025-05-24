import org.flashNight.gesh.iterator.*;
import org.flashNight.naki.DataStructures.*;
import flash.utils.getTimer;

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
        testDuplicateElements();
        testAscendingOrderInsertion();
        testDescendingOrderInsertion();
        testStringElements();
        testNegativeAndFloatingNumbers();
        testModificationDuringIteration();
        testMultipleIterators();
        testMultipleTraversals();
        testDeletionDuringTraversal();
        testDifferentTypesSameValue();
        testPerformance(10000);
        testPerformance(100000); // 增加更大规模的性能测试
        testIteratorStability();
        trace("All tests completed successfully!");
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
     * 4) 测试插入重复元素的 TreeSet
     */
    private static function testDuplicateElements():Void
    {
        trace("=== testDuplicateElements ===");
        var treeSet:TreeSet = new TreeSet(); 
        treeSet.add(10);
        treeSet.add(20);
        treeSet.add(30);
        treeSet.add(20); // Duplicate
        treeSet.add(10); // Duplicate
        treeSet.add(40);

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        
        var expectedValues:Array = [10, 20, 30, 40];
        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与中序遍历结果一致");
            index++;
        }
        
        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        assertEquals(treeSet.size(), expectedValues.length, 
                     "TreeSet size 应与唯一元素数量一致");
        
        it.dispose();
        trace("");
    }

    /**
     * 5) 测试升序插入
     */
    private static function testAscendingOrderInsertion():Void
    {
        trace("=== testAscendingOrderInsertion ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= 10; i++) {
            treeSet.add(i);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [];
        for (i = 1; i <=10; i++) {
            expectedValues.push(i);
        }

        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与升序插入结果一致");
            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 6) 测试降序插入
     */
    private static function testDescendingOrderInsertion():Void
    {
        trace("=== testDescendingOrderInsertion ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 10; i >= 1; i--) {
            treeSet.add(i);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [];
        for (i = 1; i <=10; i++) {
            expectedValues.push(i);
        }

        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与降序插入结果一致");
            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 7) 测试字符串类型元素
     */
    private static function testStringElements():Void
    {
        trace("=== testStringElements ===");
        var treeSet:TreeSet = new TreeSet(function(a:String, b:String):Number {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        });

        var elements:Array = ["apple", "banana", "cherry", "date", "elderberry"];
        for (var i:Number = 0; i < elements.length; i++) {
            treeSet.add(elements[i]);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = ["apple", "banana", "cherry", "date", "elderberry"];
        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与字符串中序遍历结果一致");
            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 8) 测试负数和浮点数
     */
    private static function testNegativeAndFloatingNumbers():Void
    {
        trace("=== testNegativeAndFloatingNumbers ===");
        var treeSet:TreeSet = new TreeSet();
        var elements:Array = [-10, -5.5, 0, 3.14, 2.718, -2.718, 5];
        for (var i:Number = 0; i < elements.length; i++) {
            treeSet.add(elements[i]);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [-10, -5.5, -2.718, 0, 2.718, 3.14, 5];
        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与负数和浮点数中序遍历结果一致");
            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 9) 测试在迭代过程中修改 TreeSet
     * 注意：根据 TreeSet 实现的具体行为，此测试可能会抛出异常或导致未定义行为
     */
    private static function testModificationDuringIteration():Void
    {
        trace("=== testModificationDuringIteration ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= 5; i++) {
            treeSet.add(i);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [1, 2, 3, 4, 5];
        var index:Number = 0;

        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与中序遍历结果一致");
            
            // 在迭代过程中插入新元素
            if (result.getValue() == 2) {
                treeSet.add(6); // 插入新元素
                trace("Inserted 6 into TreeSet during iteration.");
            }

            // 在迭代过程中删除元素
            if (result.getValue() == 3) {
                treeSet.remove(1); // 删除元素
                trace("Removed 1 from TreeSet during iteration.");
            }

            index++;
        }

        // 迭代完成后，验证 TreeSet 的最终状态
        var finalArray:Array = treeSet.toArray();
        var expectedFinal:Array = [2, 3, 4, 5, 6];
        assertEquals(finalArray.length, expectedFinal.length, "TreeSet 最终长度应为 " + expectedFinal.length);
        for (i = 0; i < expectedFinal.length; i++) {
            assertEquals(finalArray[i], expectedFinal[i], "TreeSet 最终元素应为 " + expectedFinal[i]);
        }

        it.dispose();
        trace("");
    }

    /**
     * 10) 测试多个迭代器同时遍历同一个 TreeSet
     */
    private static function testMultipleIterators():Void
    {
        trace("=== testMultipleIterators ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= 10; i++) {
            treeSet.add(i);
        }

        var it1:IIterator = new TreeSetMinimalIterator(treeSet);
        var it2:IIterator = new TreeSetMinimalIterator(treeSet);

        var expectedValues:Array = [1,2,3,4,5,6,7,8,9,10];
        var index1:Number = 0;
        var index2:Number = 0;

        while (it1.hasNext() && it2.hasNext()) {
            var result1:IterationResult = it1.next();
            var result2:IterationResult = it2.next();

            assertFalse(result1.isDone(), "it1 应在最后一次返回 done=false (迭代未结束)");
            assertFalse(result2.isDone(), "it2 应在最后一次返回 done=false (迭代未结束)");

            assertEquals(result1.getValue(), expectedValues[index1], "it1 迭代获取值应与预期一致");
            assertEquals(result2.getValue(), expectedValues[index2], "it2 迭代获取值应与预期一致");

            index1++;
            index2++;
        }

        var finalResult1:IterationResult = it1.next();
        var finalResult2:IterationResult = it2.next();

        assertTrue(finalResult1.isDone(), "it1 迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult1.getValue(), undefined, "it1 迭代结束后，value 应为 undefined");

        assertTrue(finalResult2.isDone(), "it2 迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult2.getValue(), undefined, "it2 迭代结束后，value 应为 undefined");

        it1.dispose();
        it2.dispose();
        trace("");
    }

    /**
     * 11) 测试迭代器的多次遍历
     */
    private static function testMultipleTraversals():Void
    {
        trace("=== testMultipleTraversals ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= 5; i++) {
            treeSet.add(i);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [1,2,3,4,5];

        // 第一次遍历
        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "第一次遍历中，应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "第一次遍历获取值应与预期一致");
            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "第一次遍历结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "第一次遍历结束后，value 应为 undefined");

        // 第二次遍历
        it.reset();
        index = 0;
        while (it.hasNext()) {
            var result2:IterationResult = it.next();
            assertFalse(result2.isDone(), "第二次遍历中，应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result2.getValue(), expectedValues[index], 
                         "第二次遍历获取值应与预期一致");
            index++;
        }

        var finalResult2:IterationResult = it.next();
        assertTrue(finalResult2.isDone(), "第二次遍历结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult2.getValue(), undefined, "第二次遍历结束后，value 应为 undefined");

        it.dispose();
        trace("");
    }

    /**
     * 12) 测试树中删除元素后的迭代器行为
     */
    private static function testDeletionDuringTraversal():Void
    {
        trace("=== testDeletionDuringTraversal ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= 5; i++) {
            treeSet.add(i);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [1, 2, 3, 4, 5];
        var index:Number = 0;

        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与中序遍历结果一致");
            
            // 在迭代过程中删除元素
            if (result.getValue() == 4) {
                treeSet.remove(4);
                trace("Removed 4 from TreeSet during iteration.");
            }


            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        // 验证树中元素的最终状态
        var finalArray:Array = treeSet.toArray();
        var expectedFinal:Array = [1, 2, 3, 5];
        assertEquals(finalArray.length, expectedFinal.length, "TreeSet 最终长度应为 " + expectedFinal.length);
        for (i = 0; i < expectedFinal.length; i++) {
            assertEquals(finalArray[i], expectedFinal[i], "TreeSet 最终元素应为 " + expectedFinal[i]);
        }

        it.dispose();
        trace("");
    }

    /**
     * 13) 测试插入不同类型但相同值的元素
     * 假设 compareFunction 能正确比较不同类型的相同值
     */
    private static function testDifferentTypesSameValue():Void
    {
        trace("=== testDifferentTypesSameValue ===");
        var treeSet:TreeSet = new TreeSet(function(a, b):Number {
            var aVal:Number = Number(a);
            var bVal:Number = Number(b);
            if (aVal < bVal) return -1;
            if (aVal > bVal) return 1;
            return 0;
        });

        treeSet.add(10);
        treeSet.add("10"); // Same numerical value as 10
        treeSet.add(20);
        treeSet.add("20"); // Same numerical value as 20

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var expectedValues:Array = [10, 20];
        var index:Number = 0;
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            assertFalse(result.isDone(), "应在最后一次返回 done=false (迭代未结束)");
            assertEquals(result.getValue(), expectedValues[index], 
                         "迭代获取值应与中序遍历结果一致，处理不同类型的相同值");
            index++;
        }

        var finalResult:IterationResult = it.next();
        assertTrue(finalResult.isDone(), "迭代结束后，next() 返回的 done 应为 true");
        assertEquals(finalResult.getValue(), undefined, "迭代结束后，value 应为 undefined");

        // 验证树中元素的最终状态
        assertEquals(treeSet.size(), expectedValues.length, 
                     "TreeSet size 应与唯一元素数量一致");

        it.dispose();
        trace("");
    }

    /**
     * 14) 测试迭代器的稳定性与一致性
     */
    private static function testIteratorStability():Void
    {
        trace("=== testIteratorStability ===");
        var treeSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= 100; i++) {
            treeSet.add(i);
        }

        var it:IIterator = new TreeSetMinimalIterator(treeSet);
        var firstHalf:Array = [];
        var secondHalf:Array = [];

        // 获取前50个元素
        for (var j:Number = 0; j < 50 && it.hasNext(); j++) {
            firstHalf.push(it.next().getValue());
        }

        // 再获取后50个元素
        while (it.hasNext()) {
            secondHalf.push(it.next().getValue());
        }

        // 验证前半部分
        for (j = 0; j < 50; j++) {
            assertEquals(firstHalf[j], j + 1, "前半部分第 " + (j+1) + " 个元素应为 " + (j+1));
        }

        // 验证后半部分
        for (j = 0; j < 50; j++) {
            assertEquals(secondHalf[j], 51 + j, "后半部分第 " + (j+1) + " 个元素应为 " + (51 + j));
        }

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
