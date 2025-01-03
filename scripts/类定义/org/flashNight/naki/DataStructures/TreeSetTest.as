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

        // 新增测试
        testBuildFromArray();
        testChangeCompareFunctionAndResort();

        testPerformance();

        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    //====================== 原有正确性测试 ======================//

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

        // 检查平衡性和有序性
        var arr:Array = treeSet.toArray();
        var expected:Array = [25, 35, 40, 50];
        assert(arr.length == expected.length, "删除节点后，toArray 返回的数组长度应为4");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "删除节点后，数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }

    }

    //====================== 新增测试点 ======================//

    /**
     * 测试通过数组构建 TreeSet (buildFromArray)
     * 1. 使用给定数组和比较函数构建 TreeSet
     * 2. 检查大小、顺序、以及包含性
     * 3. 进行全面的平衡性和有序性验证
     */
    private function testBuildFromArray():Void {
        trace("\n测试 buildFromArray 方法...");

        // 测试数组
        var arr:Array = [10, 3, 5, 20, 15, 7, 2];
        // 调用静态方法快速构建平衡树
        var newSet:TreeSet = TreeSet.buildFromArray(arr, numberCompare);

        // 检查大小
        assert(newSet.size() == arr.length, "buildFromArray 后，size 应该等于数组长度 " + arr.length);

        // 检查是否有序 (调用 toArray)
        var sortedArr:Array = newSet.toArray();
        // 由于 numberCompare，是升序，所以 toArray() 应该是 [2, 3, 5, 7, 10, 15, 20]
        var expected:Array = [2, 3, 5, 7, 10, 15, 20];
        assert(sortedArr.length == expected.length, "buildFromArray 后，toArray().length 应该为 " + expected.length);

        for (var i:Number = 0; i < expected.length; i++) {
            assert(sortedArr[i] == expected[i], "buildFromArray -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedArr[i]);
        }

        // 再测试一下 contains
        assert(newSet.contains(15), "buildFromArray 后，TreeSet 应包含 15");
        assert(!newSet.contains(999), "TreeSet 不应包含 999");

        // 全面验证 AVL 树的平衡性
        assert(isBalanced(newSet.getRoot()), "buildFromArray 后，TreeSet 应保持平衡");

        // 全面验证有序性
        assert(isSorted(sortedArr, numberCompare), "buildFromArray 后，TreeSet 的 toArray 应按升序排列");
    }

    /**
     * 测试动态切换比较函数并重排 (changeCompareFunctionAndResort)
     * 1. 给 TreeSet 添加一些元素
     * 2. 调用 changeCompareFunctionAndResort 换成降序
     * 3. 检查排序结果
     * 4. 进行全面的平衡性和有序性验证
     */
    private function testChangeCompareFunctionAndResort():Void {
        trace("\n测试 changeCompareFunctionAndResort 方法...");

        // 建立一个 TreeSet 并插入元素
        treeSet = new TreeSet(numberCompare);
        var elements:Array = [10, 3, 5, 20, 15, 7, 2, 25];
        for (var i:Number = 0; i < elements.length; i++) {
            treeSet.add(elements[i]);
        }
        assert(treeSet.size() == elements.length, "初始插入后，size 应为 " + elements.length);

        // 定义降序比较函数
        var descCompare:Function = function(a, b):Number {
            return b - a; // 反向比较
        };

        // 调用 changeCompareFunctionAndResort
        treeSet.changeCompareFunctionAndResort(descCompare);

        // 检查是否按降序输出
        var sortedDesc:Array = treeSet.toArray();
        // 期望：[25, 20, 15, 10, 7, 5, 3, 2]
        var expected:Array = [25, 20, 15, 10, 7, 5, 3, 2];

        assert(sortedDesc.length == expected.length, "changeCompareFunctionAndResort 后，size 不变，依旧为 " + expected.length);

        for (i = 0; i < expected.length; i++) {
            assert(sortedDesc[i] == expected[i], 
                "changeCompareFunctionAndResort -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedDesc[i]);
        }

        // 全面验证 AVL 树的平衡性
        assert(isBalanced(treeSet.getRoot()), "changeCompareFunctionAndResort 后，TreeSet 应保持平衡");

        // 全面验证有序性
        assert(isSorted(sortedDesc, descCompare), "changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列");
    }

    //====================== 性能测试 ======================//

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

            // [新增加的计时变量]
            var totalBuildTime:Number = 0;
            var totalReSortTime:Number = 0;

            // 定义在循环外以便最后做断言
            var removeAll:Boolean = true;
            var containsAll:Boolean = true;
            var largeSet:TreeSet = null;

            for (var i:Number = 0; i < iteration; i++) {
                //------------------ 1) 测试添加性能 ------------------//
                largeSet = new org.flashNight.naki.DataStructures.TreeSet(numberCompare);

                // 添加元素
                var startTime:Number = getTimer();
                for (var k:Number = 0; k < capacity; k++) {
                    largeSet.add(k);
                }
                var addTime:Number = getTimer() - startTime;
                totalAddTime += addTime;

                //--------------- 2) 测试搜索性能 -------------------//
                startTime = getTimer();
                containsAll = true;
                for (k = 0; k < capacity; k++) {
                    if (!largeSet.contains(k)) {
                        containsAll = false;
                        break;
                    }
                }
                var searchTime:Number = getTimer() - startTime;
                totalSearchTime += searchTime;

                //--------------- 3) 测试移除性能 -------------------//
                startTime = getTimer();
                removeAll = true;
                for (k = 0; k < capacity; k++) {
                    if (!largeSet.remove(k)) {
                        removeAll = false;
                        break;
                    }
                }
                var removeTime:Number = getTimer() - startTime;
                totalRemoveTime += removeTime;

                //----------------- 4) 测试 buildFromArray ----------------//
                // 重新生成一个数组 [0, 1, 2, ... capacity-1]
                // 或者使用随机数数组以模拟更真实场景
                var arr:Array = [];
                for (k = 0; k < capacity; k++) {
                    arr.push(k);
                }

                // 打乱或保持顺序均可
                // arr.sort(function() { return Math.random() - 0.5; });

                // 计时
                startTime = getTimer();
                // build一个新的TreeSet
                var tempSet:TreeSet = TreeSet.buildFromArray(arr, numberCompare);
                var buildTime:Number = getTimer() - startTime;
                totalBuildTime += buildTime;

                // 简单校验
                if (tempSet.size() != capacity) {
                    trace("FAIL: buildFromArray 后 size 不匹配，期望=" + capacity + " 实际=" + tempSet.size());
                    testFailed++;
                }

                // 额外的全面验证
                var sortedArr:Array = tempSet.toArray();
                var expectedSortedArr:Array = arr.slice(); // 复制数组
                expectedSortedArr.sort(numberCompare); // 排序为升序

                // 检查有序性
                if (!isSorted(sortedArr, numberCompare)) {
                    trace("FAIL: buildFromArray 后，toArray() 未按升序排列");
                    testFailed++;
                }

                // 检查 AVL 平衡性
                if (!isBalanced(tempSet.getRoot())) {
                    trace("FAIL: buildFromArray 后，TreeSet 未保持平衡");
                    testFailed++;
                }

                //----------------- 5) 测试 changeCompareFunctionAndResort --------------//
                // 给新构建的树，换成降序比较函数
                var descCompare:Function = function(a, b):Number {
                    return b - a;
                };

                startTime = getTimer();
                tempSet.changeCompareFunctionAndResort(descCompare);
                var reSortTime:Number = getTimer() - startTime;
                totalReSortTime += reSortTime;

                // 再做一次简单校验（降序）
                var descArr:Array = tempSet.toArray();
                // 检查首尾是否符合降序（快速检测）
                if (descArr[0] < descArr[descArr.length - 1]) {
                    trace("FAIL: changeCompareFunctionAndResort 未生效，数组似乎不是降序");
                    testFailed++;
                }

                // 额外的全面验证
                var expectedDescArr:Array = arr.slice();
                expectedDescArr.sort(descCompare); // 排序为降序

                // 检查有序性
                if (!isSorted(descArr, descCompare)) {
                    trace("FAIL: changeCompareFunctionAndResort 后，toArray() 未按降序排列");
                    testFailed++;
                }

                // 检查 AVL 平衡性
                if (!isBalanced(tempSet.getRoot())) {
                    trace("FAIL: changeCompareFunctionAndResort 后，TreeSet 未保持平衡");
                    testFailed++;
                }
            }

            // 最终检查
            assert(largeSet.size() == 0, "所有元素移除后，size 应为0");
            assert(removeAll, "所有添加的元素都应成功移除");
            assert(containsAll, "所有添加的元素都应存在于 TreeSet 中");

            // 计算平均时间
            var avgAddTime:Number = totalAddTime / iteration;
            var avgSearchTime:Number = totalSearchTime / iteration;
            var avgRemoveTime:Number = totalRemoveTime / iteration;

            // [新增] 计算 buildFromArray 与 changeCompareFunctionAndResort 的平均耗时
            var avgBuildTime:Number = totalBuildTime / iteration;
            var avgReSortTime:Number = totalReSortTime / iteration;

            // 输出性能结果
            trace("添加 " + capacity + " 个元素平均耗时: " + avgAddTime + " 毫秒");
            trace("搜索 " + capacity + " 个元素平均耗时: " + avgSearchTime + " 毫秒");
            trace("移除 " + capacity + " 个元素平均耗时: " + avgRemoveTime + " 毫秒");

            // 输出新增方法的测试结果
            trace("buildFromArray(" + capacity + " 个元素)平均耗时: " + avgBuildTime + " 毫秒");
            trace("changeCompareFunctionAndResort(" + capacity + " 个元素)平均耗时: " + avgReSortTime + " 毫秒");
        }
    }
    //====================== 性能测试 ======================//

    /**
     * 比较函数，用于数字比较 (升序)
     * @param a 第一个数字
     * @param b 第二个数字
     * @return a - b
     */
    private function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }

    //====================== 辅助验证方法 ======================//

    /**
     * 检查 AVL 树是否平衡
     * 递归检查每个节点的平衡因子是否在 [-1, 1] 范围内。
     * @param node 当前子树根节点
     * @return 如果树平衡，返回 true；否则返回 false
     */
    private function isBalanced(node:TreeNode):Boolean {
        if (node == null) {
            return true;
        }

        var leftHeight:Number = (node.left != null) ? node.left.height : 0;
        var rightHeight:Number = (node.right != null) ? node.right.height : 0;

        var balanceFactor:Number = leftHeight - rightHeight;

        if (balanceFactor > 1 || balanceFactor < -1) {
            return false;
        }

        // 递归检查子树
        return isBalanced(node.left) && isBalanced(node.right);
    }

    /**
     * 检查数组是否按指定的比较函数排序
     * @param arr 待检查的数组
     * @param compare 比较函数
     * @return 如果数组按 compare 排序，返回 true；否则返回 false
     */
    private function isSorted(arr:Array, compare:Function):Boolean {
        for (var i:Number = 0; i < arr.length - 1; i++) {
            if (compare(arr[i], arr[i + 1]) > 0) {
                return false;
            }
        }
        return true;
    }
}
