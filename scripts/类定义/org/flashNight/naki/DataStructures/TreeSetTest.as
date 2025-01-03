import org.flashNight.naki.DataStructures.*;

/**
 * TreeSet 测试类
 * 负责测试 TreeSet 类的各种功能，包括添加、删除、查找、大小、遍历以及性能表现。
 */
class org.flashNight.naki.DataStructures.TreeSetTest {
    private var treeSet:org.flashNight.naki.DataStructures.TreeSet; // 测试用的 TreeSet 实例
    private var testPassed:Number;   // 通过的测试数量
    private var testFailed:Number;   // 失败的测试数量

    /**
     * 构造函数
     * 初始化测试统计变量。
     */
    public function TreeSetTest() {
        testPassed = 0;
        testFailed = 0;
    }

    /**
     * 简单的断言函数
     * 根据条件判断测试是否通过，并记录结果。
     * @param condition 条件表达式
     * @param message 测试描述信息
     */
    private function assert(condition:Boolean, message:String):Void {
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            testFailed++;
        }
    }

    /**
     * 运行所有测试
     * 包括正确性测试和性能测试。
     */
    public function runTests():Void {
        trace("开始 TreeSet 测试...");
        testAdd();
        testRemove();
        testContains();
        testSize();
        testToArray();
        testEdgeCases();
        testPerformance();
        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    /**
     * 测试 add 方法
     * 检查添加元素、重复添加以及树的大小和包含性。
     */
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

    /**
     * 测试 remove 方法
     * 检查移除存在和不存在的元素，以及树的大小和包含性。
     */
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

    /**
     * 测试 contains 方法
     * 检查 TreeSet 是否正确包含或不包含特定元素。
     */
    private function testContains():Void {
        trace("\n测试 contains 方法...");
        assert(treeSet.contains(10), "TreeSet 应包含 10");
        assert(!treeSet.contains(20), "TreeSet 不应包含 20");
        assert(treeSet.contains(5), "TreeSet 应包含 5");
        assert(treeSet.contains(15), "TreeSet 应包含 15");
        assert(!treeSet.contains(25), "TreeSet 不应包含 25");
    }

    /**
     * 测试 size 方法
     * 检查 TreeSet 的大小在添加和删除元素后的变化。
     */
    private function testSize():Void {
        trace("\n测试 size 方法...");
        assert(treeSet.size() == 3, "当前 size 应为3");
        treeSet.add(25);
        assert(treeSet.size() == 4, "添加 25 后，size 应为4");
        treeSet.remove(5);
        assert(treeSet.size() == 3, "移除 5 后，size 应为3");
    }

    /**
     * 测试 toArray 方法
     * 检查中序遍历后的数组是否按预期排序，并包含正确的元素。
     */
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

    /**
     * 测试边界情况
     * 包括删除根节点、删除有两个子节点的节点、删除叶子节点等。
     */
    private function testEdgeCases():Void {
        trace("\n测试边界情况...");
        // 重建 TreeSet
        treeSet = new org.flashNight.naki.DataStructures.TreeSet(numberCompare);
        treeSet.add(30);
        treeSet.add(20);
        treeSet.add(40);
        treeSet.add(10);
        treeSet.add(25);
        treeSet.add(35);
        treeSet.add(50);

        // 删除叶子节点
        var removed:Boolean = treeSet.remove(10);
        assert(removed, "成功移除叶子节点 10");
        assert(!treeSet.contains(10), "TreeSet 不应包含 10");

        // 删除有一个子节点的节点
        removed = treeSet.remove(20);
        assert(removed, "成功移除有一个子节点的节点 20");
        assert(!treeSet.contains(20), "TreeSet 不应包含 20");
        assert(treeSet.contains(25), "TreeSet 应包含 25");

        // 删除有两个子节点的节点（根节点）
        removed = treeSet.remove(30);
        assert(removed, "成功移除有两个子节点的节点 30");
        assert(!treeSet.contains(30), "TreeSet 不应包含 30");
        assert(treeSet.contains(25), "TreeSet 应包含 25");
        assert(treeSet.contains(35), "TreeSet 应包含 35");

        // 检查平衡性
        var arr:Array = treeSet.toArray();
        var expected:Array = [25, 35, 40, 50];
        assert(arr.length == expected.length, "删除节点后，toArray 返回的数组长度应为4");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "删除节点后，数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    /**
     * 测试性能表现
     * 分别测试容量为100、1000、10000的情况，每个容量级别执行不同次数的测试。
     */
    private function testPerformance():Void {
        trace("\n测试性能表现...");
        var capacities:Array = [100, 1000, 10000];
        var iterations:Array = [100, 10, 1]; // 分别对应容量100、1000、10000执行的次数

        for (var j:Number = 0; j < capacities.length; j++) {
            var capacity:Number = capacities[j];
            var iteration:Number = iterations[j];
            trace("\n容量: " + capacity + "，执行次数: " + iteration);

            var totalAddTime:Number = 0;
            var totalSearchTime:Number = 0;
            var totalRemoveTime:Number = 0;

            for (var i:Number = 0; i < iteration; i++) {
                // 创建新的 TreeSet 实例
                var largeSet:org.flashNight.naki.DataStructures.TreeSet = new org.flashNight.naki.DataStructures.TreeSet(numberCompare);

                // 添加元素
                var startTime:Number = getTimer();
                for (var k:Number = 0; k < capacity; k++) {
                    largeSet.add(k);
                }
                var addTime:Number = getTimer() - startTime;
                totalAddTime += addTime;

                // 搜索元素
                startTime = getTimer();
                var containsAll:Boolean = true;
                for (k = 0; k < capacity; k++) {
                    if (!largeSet.contains(k)) {
                        containsAll = false;
                        break;
                    }
                }
                var searchTime:Number = getTimer() - startTime;
                totalSearchTime += searchTime;

                // 移除元素
                startTime = getTimer();
                var removeAll:Boolean = true;
                for (k = 0; k < capacity; k++) {
                    if (!largeSet.remove(k)) {
                        removeAll = false;
                        break;
                    }
                }
                var removeTime:Number = getTimer() - startTime;
                totalRemoveTime += removeTime;

            }

            // 最终检查
            assert(largeSet.size() == 0, "所有元素移除后，size 应为0");
            assert(removeAll, "所有添加的元素都应成功移除");
            assert(containsAll, "所有添加的元素都应存在于 TreeSet 中");

            // 计算平均时间
            var avgAddTime:Number = totalAddTime / iteration;
            var avgSearchTime:Number = totalSearchTime / iteration;
            var avgRemoveTime:Number = totalRemoveTime / iteration;

            trace("添加 " + capacity + " 个元素平均耗时: " + avgAddTime + " 毫秒");
            trace("搜索 " + capacity + " 个元素平均耗时: " + avgSearchTime + " 毫秒");
            trace("移除 " + capacity + " 个元素平均耗时: " + avgRemoveTime + " 毫秒");
        }
    }

    /**
     * 比较函数，用于数字比较
     * @param a 第一个数字
     * @param b 第二个数字
     * @return a - b
     */
    private function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }
}
