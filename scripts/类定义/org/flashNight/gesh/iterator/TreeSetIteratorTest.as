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
        runPerformanceTests();
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
     * 15) 测试在大规模数据下的性能（基础版）
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

    // ======================= 详细性能测试 =======================

    /**
     * 运行详细的性能测试套件
     * 对比 TreeSetMinimalIterator 与 toArray 的遍历性能
     */
    public static function runPerformanceTests():Void
    {
        trace("╔══════════════════════════════════════════════════════════════╗");
        trace("║           TreeSetMinimalIterator 性能测试套件                 ║");
        trace("╚══════════════════════════════════════════════════════════════╝");
        trace("");

        // 不同规模的测试
        var sizes:Array = [1000, 5000, 10000, 50000];

        for (var i:Number = 0; i < sizes.length; i++) {
            runDetailedPerformanceTest(sizes[i]);
        }

        trace("═══════════════════ 性能测试完成 ═══════════════════");
    }

    /**
     * 详细性能测试：对比迭代器与 toArray 的遍历性能
     * @param numElements 元素数量
     */
    private static function runDetailedPerformanceTest(numElements:Number):Void
    {
        trace("────────────────────────────────────────────────────────────────");
        trace("测试规模: " + numElements + " 个元素");
        trace("────────────────────────────────────────────────────────────────");

        // 1. 构建测试数据（随机顺序插入，更接近真实场景）
        var buildStart:Number = getTimer();
        var testSet:TreeSet = new TreeSet();

        // 生成随机顺序的数组
        var elements:Array = [];
        for (var i:Number = 1; i <= numElements; i++) {
            elements.push(i);
        }
        // Fisher-Yates 洗牌
        for (i = elements.length - 1; i > 0; i--) {
            var j:Number = Math.floor(Math.random() * (i + 1));
            var temp:Number = elements[i];
            elements[i] = elements[j];
            elements[j] = temp;
        }
        // 插入 TreeSet
        for (i = 0; i < elements.length; i++) {
            testSet.add(elements[i]);
        }
        var buildEnd:Number = getTimer();
        trace("  构建 TreeSet 耗时: " + (buildEnd - buildStart) + " ms");

        // 2. 测试 TreeSetMinimalIterator 遍历性能
        var iteratorTime:Number = testIteratorTraversal(testSet, numElements);

        // 3. 测试 toArray 遍历性能
        var toArrayTime:Number = testToArrayTraversal(testSet, numElements);

        // 4. 测试 findSuccessor 搜索性能（无右子树场景）
        var successorTime:Number = testSuccessorSearchPerformance(testSet, numElements);

        // 5. 输出对比结果
        trace("");
        trace("  ┌─────────────────────────────────────────┐");
        trace("  │ 性能对比结果 (" + numElements + " 元素)");
        trace("  ├─────────────────────────────────────────┤");
        trace("  │ 迭代器遍历:     " + padLeft(String(iteratorTime), 6) + " ms");
        trace("  │ toArray遍历:    " + padLeft(String(toArrayTime), 6) + " ms");
        trace("  │ 后继搜索测试:   " + padLeft(String(successorTime), 6) + " ms");
        trace("  │ 迭代器/toArray: " + padLeft(String(Math.round(iteratorTime / toArrayTime * 100) / 100), 6) + " x");
        trace("  └─────────────────────────────────────────┘");
        trace("");
    }

    /**
     * 测试迭代器遍历性能
     */
    private static function testIteratorTraversal(testSet:TreeSet, numElements:Number):Number
    {
        var startTime:Number = getTimer();
        var it:IIterator = new TreeSetMinimalIterator(testSet);

        var count:Number = 0;
        var sum:Number = 0;  // 累加以防止编译器优化
        while (it.hasNext()) {
            var result:IterationResult = it.next();
            sum += Number(result.getValue());
            count++;
        }
        it.dispose();

        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        // 验证正确性
        var expectedSum:Number = (1 + numElements) * numElements / 2;
        if (sum != expectedSum) {
            trace("  ⚠ 迭代器累加和错误: 期望 " + expectedSum + ", 实际 " + sum);
        }
        if (count != numElements) {
            trace("  ⚠ 迭代器计数错误: 期望 " + numElements + ", 实际 " + count);
        }

        trace("  迭代器遍历: " + elapsed + " ms (count=" + count + ")");
        return elapsed;
    }

    /**
     * 测试 toArray 遍历性能
     */
    private static function testToArrayTraversal(testSet:TreeSet, numElements:Number):Number
    {
        var startTime:Number = getTimer();
        var arr:Array = testSet.toArray();

        var sum:Number = 0;
        for (var i:Number = 0; i < arr.length; i++) {
            sum += Number(arr[i]);
        }

        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        // 验证正确性
        var expectedSum:Number = (1 + numElements) * numElements / 2;
        if (sum != expectedSum) {
            trace("  ⚠ toArray 累加和错误: 期望 " + expectedSum + ", 实际 " + sum);
        }

        trace("  toArray遍历: " + elapsed + " ms (length=" + arr.length + ")");
        return elapsed;
    }

    /**
     * 测试后继搜索性能（findSuccessor 无右子树场景）
     * 这是 TreeSetMinimalIterator 的核心开销所在
     */
    private static function testSuccessorSearchPerformance(testSet:TreeSet, numElements:Number):Number
    {
        // 多次创建迭代器并只遍历前半部分，测试 findSuccessor 性能
        var iterations:Number = 3;
        var totalTime:Number = 0;

        for (var round:Number = 0; round < iterations; round++) {
            var startTime:Number = getTimer();
            var it:IIterator = new TreeSetMinimalIterator(testSet);

            // 只遍历一半元素
            var halfCount:Number = Math.floor(numElements / 2);
            for (var i:Number = 0; i < halfCount && it.hasNext(); i++) {
                it.next();
            }
            it.dispose();

            var endTime:Number = getTimer();
            totalTime += (endTime - startTime);
        }

        var avgTime:Number = Math.round(totalTime / iterations);
        trace("  后继搜索(" + iterations + "轮半遍历): " + avgTime + " ms (avg)");
        return avgTime;
    }

    /**
     * 左填充字符串
     */
    private static function padLeft(str:String, len:Number):String
    {
        while (str.length < len) {
            str = " " + str;
        }
        return str;
    }

    /**
     * 运行内存效率对比测试
     * 对比迭代器（O(1)空间）与 toArray（O(n)空间）的场景
     */
    public static function runMemoryEfficiencyTest():Void
    {
        trace("╔══════════════════════════════════════════════════════════════╗");
        trace("║           内存效率对比测试                                    ║");
        trace("╚══════════════════════════════════════════════════════════════╝");
        trace("");
        trace("说明: TreeSetMinimalIterator 使用 O(1) 额外空间");
        trace("      toArray 需要 O(n) 额外空间存储数组");
        trace("");

        var numElements:Number = 10000;
        var testSet:TreeSet = new TreeSet();
        for (var i:Number = 1; i <= numElements; i++) {
            testSet.add(i);
        }

        // 测试场景：只需要前 N 个元素时的性能
        var needed:Array = [10, 100, 1000, 5000];

        trace("场景: 只需要获取前 N 个元素 (总共 " + numElements + " 个)");
        trace("────────────────────────────────────────────────────────────────");

        for (i = 0; i < needed.length; i++) {
            var n:Number = needed[i];

            // 迭代器方式
            var itStart:Number = getTimer();
            var it:IIterator = new TreeSetMinimalIterator(testSet);
            var itResults:Array = [];
            for (var j:Number = 0; j < n && it.hasNext(); j++) {
                itResults.push(it.next().getValue());
            }
            it.dispose();
            var itEnd:Number = getTimer();

            // toArray 方式
            var arrStart:Number = getTimer();
            var arr:Array = testSet.toArray();
            var arrResults:Array = [];
            for (j = 0; j < n && j < arr.length; j++) {
                arrResults.push(arr[j]);
            }
            var arrEnd:Number = getTimer();

            trace("  获取前 " + padLeft(String(n), 5) + " 个: 迭代器 " +
                  padLeft(String(itEnd - itStart), 4) + " ms vs toArray " +
                  padLeft(String(arrEnd - arrStart), 4) + " ms");
        }

        trace("");
        trace("结论: 当只需要部分元素时，迭代器更高效（无需构建完整数组）");
        trace("");
    }
}
