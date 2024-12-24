import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TreeSetTest {
    private var treeSet:org.flashNight.naki.DataStructures.TreeSet;
    private var testPassed:Number;
    private var testFailed:Number;

    public function TreeSetTest() {
        testPassed = 0;
        testFailed = 0;
    }

    // 简单的断言函数
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            testFailed++;
        }
    }

    // 运行所有测试
    public function runTests():Void {
        trace("开始 TreeSet 测试...");
        testAdd();
        testRemove();
        testContains();
        testSize();
        testToArray();
        testPerformance();
        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    // 测试 add 方法
    private function testAdd():Void {
        trace("\n测试 add 方法...");
        // 使用数字比较函数
        treeSet = new org.flashNight.naki.DataStructures.TreeSet(numberCompare);
        treeSet.add(10);
        treeSet.add(20);
        treeSet.add(5);
        treeSet.add(15);
        treeSet.add(10); // 重复添加

        // 期望 size 为4，因为10被重复添加
        assert(treeSet.size() == 4, "添加元素后，size 应为4");

        // 检查元素是否存在
        assert(treeSet.contains(10), "TreeSet 应包含 10");
        assert(treeSet.contains(20), "TreeSet 应包含 20");
        assert(treeSet.contains(5), "TreeSet 应包含 5");
        assert(treeSet.contains(15), "TreeSet 应包含 15");
    }

    // 测试 remove 方法
    private function testRemove():Void {
        trace("\n测试 remove 方法...");
        // 移除存在的元素
        var removed:Boolean = treeSet.remove(20);
        assert(removed, "成功移除存在的元素 20");
        assert(!treeSet.contains(20), "TreeSet 不应包含 20");

        // 尝试移除不存在的元素
        removed = treeSet.remove(25);
        assert(!removed, "移除不存在的元素 25 应返回 false");
    }

    // 测试 contains 方法
    private function testContains():Void {
        trace("\n测试 contains 方法...");
        assert(treeSet.contains(10), "TreeSet 应包含 10");
        assert(!treeSet.contains(20), "TreeSet 不应包含 20");
        assert(treeSet.contains(5), "TreeSet 应包含 5");
        assert(treeSet.contains(15), "TreeSet 应包含 15");
        assert(!treeSet.contains(25), "TreeSet 不应包含 25");
    }

    // 测试 size 方法
    private function testSize():Void {
        trace("\n测试 size 方法...");
        assert(treeSet.size() == 3, "当前 size 应为3");
        treeSet.add(25);
        assert(treeSet.size() == 4, "添加 25 后，size 应为4");
        treeSet.remove(5);
        assert(treeSet.size() == 3, "移除 5 后，size 应为3");
    }

    // 测试 toArray 方法
    private function testToArray():Void {
        trace("\n测试 toArray 方法...");
        var arr:Array = treeSet.toArray();
        var expected:Array = [10, 15, 25]; // 5 已被移除

        // 检查数组长度
        assert(arr.length == expected.length, "toArray 返回的数组长度应为3");

        // 检查数组内容
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    // 测试性能表现
    private function testPerformance():Void {
        trace("\n测试性能表现...");
        var largeSet:org.flashNight.naki.DataStructures.TreeSet = new org.flashNight.naki.DataStructures.TreeSet(numberCompare);
        var numElements:Number = 1000;
        var startTime:Number = getTimer();

        // 添加大量元素
        for (var i:Number = 0; i < numElements; i++) {
            largeSet.add(i);
        }
        var addTime:Number = getTimer() - startTime;
        trace("添加 " + numElements + " 个元素耗时: " + addTime + " 毫秒");

        // 搜索元素
        startTime = getTimer();
        var containsAll:Boolean = true;
        for (i = 0; i < numElements; i++) {
            if (!largeSet.contains(i)) {
                containsAll = false;
                break;
            }
        }
        var searchTime:Number = getTimer() - startTime;
        assert(containsAll, "所有添加的元素都应存在于 TreeSet 中");
        trace("搜索 " + numElements + " 个元素耗时: " + searchTime + " 毫秒");

        // 移除元素
        startTime = getTimer();
        var removeAll:Boolean = true;
        for (i = 0; i < numElements; i++) {
            if (!largeSet.remove(i)) {
                removeAll = false;
                break;
            }
        }
        var removeTime:Number = getTimer() - startTime;
        assert(removeAll, "所有添加的元素都应成功移除");
        trace("移除 " + numElements + " 个元素耗时: " + removeTime + " 毫秒");

        // 最终检查
        assert(largeSet.size() == 0, "所有元素移除后，size 应为0");
    }

    // 比较函数，用于数字比较
    private function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }
}
