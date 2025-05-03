import org.flashNight.naki.DataStructures.*;

/**
 * RedBlackTree 测试类
 * 负责测试 RedBlackTree 类的各种功能，包括添加、删除、查找、大小、遍历以及性能表现。
 */
class org.flashNight.naki.DataStructures.RedBlackTreeTest {
    private var rbTree:org.flashNight.naki.DataStructures.RedBlackTree; // 测试用的 RedBlackTree 实例
    private var testPassed:Number;   // 通过的测试数量
    private var testFailed:Number;   // 失败的测试数量

    /**
     * 构造函数
     * 初始化测试统计变量。
     */
    public function RedBlackTreeTest() {
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
        trace("开始 RedBlackTree 测试...");
        testAdd();
        testRemove();
        testContains();
        testSize();
        testToArray();
        testEdgeCases();

        // 新增测试
        testBuildFromArray();
        testChangeCompareFunctionAndResort();
        testRedBlackProperties();

        testPerformance();

        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    //====================== 基本操作测试 ======================//

    /**
     * 测试 add 方法
     * 检查添加元素、重复添加以及树的大小和包含性。
     */
    private function testAdd():Void {
        trace("\n测试 add 方法...");
        // 使用数字比较函数
        rbTree = new org.flashNight.naki.DataStructures.RedBlackTree(numberCompare);
        rbTree.add(10);
        rbTree.add(20);
        rbTree.add(5);
        rbTree.add(15);
        rbTree.add(10); // 重复添加

        // 期望 size 为4，因为10被重复添加
        assert(rbTree.size() == 4, "添加元素后，size 应为4");

        // 检查元素是否存在
        assert(rbTree.contains(10), "RedBlackTree 应包含 10");
        assert(rbTree.contains(20), "RedBlackTree 应包含 20");
        assert(rbTree.contains(5), "RedBlackTree 应包含 5");
        assert(rbTree.contains(15), "RedBlackTree 应包含 15");

        // 验证红黑树属性
        assert(validateRedBlackProperties(rbTree.getRoot()), "添加后的树应保持红黑树属性");
    }

    /**
     * 测试 remove 方法
     * 检查移除存在和不存在的元素，以及树的大小和包含性。
     */
    private function testRemove():Void {
        trace("\n测试 remove 方法...");
        // 移除存在的元素
        var removed:Boolean = rbTree.remove(20);
        assert(removed, "成功移除存在的元素 20");
        assert(!rbTree.contains(20), "RedBlackTree 不应包含 20");

        // 尝试移除不存在的元素
        removed = rbTree.remove(25);
        assert(!removed, "移除不存在的元素 25 应返回 false");

        // 验证红黑树属性
        assert(validateRedBlackProperties(rbTree.getRoot()), "移除后的树应保持红黑树属性");
    }

    /**
     * 测试 contains 方法
     * 检查 RedBlackTree 是否正确包含或不包含特定元素。
     */
    private function testContains():Void {
        trace("\n测试 contains 方法...");
        assert(rbTree.contains(10), "RedBlackTree 应包含 10");
        assert(!rbTree.contains(20), "RedBlackTree 不应包含 20");
        assert(rbTree.contains(5), "RedBlackTree 应包含 5");
        assert(rbTree.contains(15), "RedBlackTree 应包含 15");
        assert(!rbTree.contains(25), "RedBlackTree 不应包含 25");
    }

    /**
     * 测试 size 方法
     * 检查 RedBlackTree 的大小在添加和删除元素后的变化。
     */
    private function testSize():Void {
        trace("\n测试 size 方法...");
        assert(rbTree.size() == 3, "当前 size 应为3");
        rbTree.add(25);
        assert(rbTree.size() == 4, "添加 25 后，size 应为4");
        rbTree.remove(5);
        assert(rbTree.size() == 3, "移除 5 后，size 应为3");

        // 验证红黑树属性
        assert(validateRedBlackProperties(rbTree.getRoot()), "添加删除后的树应保持红黑树属性");
    }

    /**
     * 测试 toArray 方法
     * 检查中序遍历后的数组是否按预期排序，并包含正确的元素。
     */
    private function testToArray():Void {
        trace("\n测试 toArray 方法...");
        var arr:Array = rbTree.toArray();
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
        // 重建 RedBlackTree
        rbTree = new org.flashNight.naki.DataStructures.RedBlackTree(numberCompare);
        rbTree.add(30);
        rbTree.add(20);
        rbTree.add(40);
        rbTree.add(10);
        rbTree.add(25);
        rbTree.add(35);
        rbTree.add(50);

        // 验证红黑树属性
        assert(validateRedBlackProperties(rbTree.getRoot()), "初始树应保持红黑树属性");

        // 删除叶子节点
        var removed:Boolean = rbTree.remove(10);
        assert(removed, "成功移除叶子节点 10");
        assert(!rbTree.contains(10), "RedBlackTree 不应包含 10");
        assert(validateRedBlackProperties(rbTree.getRoot()), "删除叶子节点后应保持红黑树属性");

        // 删除有一个子节点的节点
        removed = rbTree.remove(20);
        assert(removed, "成功移除有一个子节点的节点 20");
        assert(!rbTree.contains(20), "RedBlackTree 不应包含 20");
        assert(rbTree.contains(25), "RedBlackTree 应包含 25");
        assert(validateRedBlackProperties(rbTree.getRoot()), "删除有一个子节点的节点后应保持红黑树属性");

        // 删除有两个子节点的节点（根节点）
        removed = rbTree.remove(30);
        assert(removed, "成功移除有两个子节点的节点 30");
        assert(!rbTree.contains(30), "RedBlackTree 不应包含 30");
        assert(rbTree.contains(25), "RedBlackTree 应包含 25");
        assert(rbTree.contains(35), "RedBlackTree 应包含 35");
        assert(validateRedBlackProperties(rbTree.getRoot()), "删除有两个子节点的节点后应保持红黑树属性");

        // 检查有序性
        var arr:Array = rbTree.toArray();
        var expected:Array = [25, 35, 40, 50];
        assert(arr.length == expected.length, "删除节点后，toArray 返回的数组长度应为4");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "删除节点后，数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    //====================== 新增测试点 ======================//

    /**
     * 测试通过数组构建 RedBlackTree (buildFromArray)
     * 1. 使用给定数组和比较函数构建 RedBlackTree
     * 2. 检查大小、顺序、以及包含性
     * 3. 进行全面的红黑树属性和有序性验证
     */
    private function testBuildFromArray():Void {
        trace("\n测试 buildFromArray 方法...");

        // 测试数组
        var arr:Array = [10, 3, 5, 20, 15, 7, 2];
        // 调用静态方法快速构建红黑树
        var newTree:RedBlackTree = RedBlackTree.buildFromArray(arr, numberCompare);

        // 检查大小
        assert(newTree.size() == arr.length, "buildFromArray 后，size 应该等于数组长度 " + arr.length);

        // 检查是否有序 (调用 toArray)
        var sortedArr:Array = newTree.toArray();
        // 由于 numberCompare，是升序，所以 toArray() 应该是 [2, 3, 5, 7, 10, 15, 20]
        var expected:Array = [2, 3, 5, 7, 10, 15, 20];
        assert(sortedArr.length == expected.length, "buildFromArray 后，toArray().length 应该为 " + expected.length);

        for (var i:Number = 0; i < expected.length; i++) {
            assert(sortedArr[i] == expected[i], "buildFromArray -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedArr[i]);
        }

        // 再测试一下 contains
        assert(newTree.contains(15), "buildFromArray 后，RedBlackTree 应包含 15");
        assert(!newTree.contains(999), "RedBlackTree 不应包含 999");

        // 全面验证红黑树属性
        assert(validateRedBlackProperties(newTree.getRoot()), "buildFromArray 后，RedBlackTree 应保持红黑树属性");

        // 全面验证有序性
        assert(isSorted(sortedArr, numberCompare), "buildFromArray 后，RedBlackTree 的 toArray 应按升序排列");
    }

    /**
     * 测试动态切换比较函数并重排 (changeCompareFunctionAndResort)
     * 1. 给 RedBlackTree 添加一些元素
     * 2. 调用 changeCompareFunctionAndResort 换成降序
     * 3. 检查排序结果
     * 4. 进行全面的红黑树属性和有序性验证
     */
    private function testChangeCompareFunctionAndResort():Void {
        trace("\n测试 changeCompareFunctionAndResort 方法...");

        // 建立一个 RedBlackTree 并插入元素
        rbTree = new RedBlackTree(numberCompare);
        var elements:Array = [10, 3, 5, 20, 15, 7, 2, 25];
        for (var i:Number = 0; i < elements.length; i++) {
            rbTree.add(elements[i]);
        }
        assert(rbTree.size() == elements.length, "初始插入后，size 应为 " + elements.length);
        assert(validateRedBlackProperties(rbTree.getRoot()), "插入元素后，RedBlackTree 应保持红黑树属性");

        // 定义降序比较函数
        var descCompare:Function = function(a, b):Number {
            return b - a; // 反向比较
        };

        // 调用 changeCompareFunctionAndResort
        rbTree.changeCompareFunctionAndResort(descCompare);

        // 检查是否按降序输出
        var sortedDesc:Array = rbTree.toArray();
        // 期望：[25, 20, 15, 10, 7, 5, 3, 2]
        var expected:Array = [25, 20, 15, 10, 7, 5, 3, 2];

        assert(sortedDesc.length == expected.length, "changeCompareFunctionAndResort 后，size 不变，依旧为 " + expected.length);

        for (i = 0; i < expected.length; i++) {
            assert(sortedDesc[i] == expected[i], 
                "changeCompareFunctionAndResort -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedDesc[i]);
        }

        // 全面验证红黑树属性
        assert(validateRedBlackProperties(rbTree.getRoot()), "changeCompareFunctionAndResort 后，RedBlackTree 应保持红黑树属性");

        // 全面验证有序性
        assert(isSorted(sortedDesc, descCompare), "changeCompareFunctionAndResort 后，RedBlackTree 的 toArray 应按降序排列");
    }

    /**
     * 专门测试红黑树特有的属性
     * 1. 根节点必须是黑色
     * 2. 红色节点的子节点必须是黑色（没有连续的红色节点）
     * 3. 从根到所有叶子的黑色节点数量相同（黑色高度一致）
     */
    private function testRedBlackProperties():Void {
        trace("\n测试红黑树特有属性...");
        
        // 创建一个新的红黑树并添加多个元素
        var tree:RedBlackTree = new RedBlackTree(numberCompare);
        var elements:Array = [50, 30, 70, 20, 40, 60, 80, 15, 25, 35, 45, 55, 65, 75, 85];
        
        for (var i:Number = 0; i < elements.length; i++) {
            tree.add(elements[i]);
            // 每添加一个元素就验证一次红黑树性质
            assert(validateRedBlackProperties(tree.getRoot()), 
                   "添加元素 " + elements[i] + " 后，树应保持红黑树属性");
        }
        
        // 特别验证根节点为黑色
        var root:RedBlackNode = tree.getRoot();
        assert(root != null && root.color == RedBlackNode.BLACK, 
               "根节点应为黑色");
        
        // 验证没有连续的红色节点
        assert(noAdjacentRedNodes(root), 
               "红色节点的子节点应为黑色（不存在连续的红色节点）");
        
        // 验证从根到所有叶子的黑色节点数量相同
        var blackHeight:Number = getBlackHeight(root);
        assert(blackHeight > 0, 
               "黑色高度应大于0，实际为: " + blackHeight);
        
        // 使用一系列的插入和删除操作来测试树的动态平衡
        // 删除一些节点
        var nodesToRemove:Array = [30, 60, 25, 75];
        for (i = 0; i < nodesToRemove.length; i++) {
            tree.remove(nodesToRemove[i]);
            assert(validateRedBlackProperties(tree.getRoot()),
                   "删除元素 " + nodesToRemove[i] + " 后，树应保持红黑树属性");
        }
        
        // 添加一些新节点
        var newNodes:Array = [22, 33, 66, 77];
        for (i = 0; i < newNodes.length; i++) {
            tree.add(newNodes[i]);
            assert(validateRedBlackProperties(tree.getRoot()),
                   "添加元素 " + newNodes[i] + " 后，树应保持红黑树属性");
        }
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
            var largeTree:RedBlackTree = null;

            for (var i:Number = 0; i < iteration; i++) {
                //------------------ 1) 测试添加性能 ------------------//
                largeTree = new org.flashNight.naki.DataStructures.RedBlackTree(numberCompare);

                // 添加元素
                var startTime:Number = getTimer();
                for (var k:Number = 0; k < capacity; k++) {
                    largeTree.add(k);
                }
                var addTime:Number = getTimer() - startTime;
                totalAddTime += addTime;

                //--------------- 2) 测试搜索性能 -------------------//
                startTime = getTimer();
                containsAll = true;
                for (k = 0; k < capacity; k++) {
                    if (!largeTree.contains(k)) {
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
                    if (!largeTree.remove(k)) {
                        removeAll = false;
                        break;
                    }
                }
                var removeTime:Number = getTimer() - startTime;
                totalRemoveTime += removeTime;

                //----------------- 4) 测试 buildFromArray ----------------//
                // 重新生成一个数组 [0, 1, 2, ... capacity-1]
                var arr:Array = [];
                for (k = 0; k < capacity; k++) {
                    arr.push(k);
                }

                // 打乱或保持顺序均可
                // arr.sort(function() { return Math.random() - 0.5; });

                // 计时
                startTime = getTimer();
                // build一个新的RedBlackTree
                var tempTree:RedBlackTree = RedBlackTree.buildFromArray(arr, numberCompare);
                var buildTime:Number = getTimer() - startTime;
                totalBuildTime += buildTime;

                // 简单校验
                if (tempTree.size() != capacity) {
                    trace("FAIL: buildFromArray 后 size 不匹配，期望=" + capacity + " 实际=" + tempTree.size());
                    testFailed++;
                }

                // 检查红黑树属性（仅对小规模树进行全面验证，避免性能测试过慢）
                if (capacity <= 1000 && !validateRedBlackProperties(tempTree.getRoot())) {
                    trace("FAIL: buildFromArray 后，RedBlackTree 未保持红黑树属性");
                    testFailed++;
                }

                //----------------- 5) 测试 changeCompareFunctionAndResort --------------//
                // 给新构建的树，换成降序比较函数
                var descCompare:Function = function(a, b):Number {
                    return b - a;
                };

                startTime = getTimer();
                tempTree.changeCompareFunctionAndResort(descCompare);
                var reSortTime:Number = getTimer() - startTime;
                totalReSortTime += reSortTime;

                // 再做一次简单校验（降序）
                var descArr:Array = tempTree.toArray();
                // 检查首尾是否符合降序（快速检测）
                if (descArr[0] < descArr[descArr.length - 1]) {
                    trace("FAIL: changeCompareFunctionAndResort 未生效，数组似乎不是降序");
                    testFailed++;
                }

                // 检查红黑树属性（仅对小规模树进行全面验证，避免性能测试过慢）
                if (capacity <= 1000 && !validateRedBlackProperties(tempTree.getRoot())) {
                    trace("FAIL: changeCompareFunctionAndResort 后，RedBlackTree 未保持红黑树属性");
                    testFailed++;
                }
            }

            // 最终检查
            assert(largeTree.size() == 0, "所有元素移除后，size 应为0");
            assert(removeAll, "所有添加的元素都应成功移除");
            assert(containsAll, "所有添加的元素都应存在于 RedBlackTree 中");

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
     * 验证红黑树属性
     * 1. 根节点必须是黑色
     * 2. 没有连续的红色节点
     * 3. 从根到每个叶子节点的黑色节点数量相同
     * @param node 当前子树根节点
     * @return 如果满足红黑树性质，返回 true；否则返回 false
     */
    private function validateRedBlackProperties(node:RedBlackNode):Boolean {
        if (node == null) {
            return true;
        }

        // 属性1: 根节点必须是黑色
        if (node == rbTree.getRoot() && node.color != RedBlackNode.BLACK) {
            return false;
        }

        // 属性2: 没有连续的红色节点
        if (!noAdjacentRedNodes(node)) {
            return false;
        }

        // 属性3: 从根到每个叶子节点的黑色节点数量相同
        var blackHeight:Number = getBlackHeight(node);
        if (blackHeight == -1) {
            return false;
        }

        return true;
    }

    /**
     * 检查是否没有连续的红色节点
     * @param node 当前子树根节点
     * @return 如果没有连续的红色节点，返回 true；否则返回 false
     */
    private function noAdjacentRedNodes(node:RedBlackNode):Boolean {
        if (node == null) {
            return true;
        }

        // 检查当前节点是否为红色
        if (node.color == RedBlackNode.RED) {
            // 如果当前节点为红色，其子节点必须为黑色
            if (node.left != null && node.left.color == RedBlackNode.RED) {
                return false;
            }
            if (node.right != null && node.right.color == RedBlackNode.RED) {
                return false;
            }
        }

        // 递归检查子树
        return noAdjacentRedNodes(node.left) && noAdjacentRedNodes(node.right);
    }

    /**
     * 获取黑色高度
     * 从当前节点到任意叶子节点路径上的黑色节点数量
     * @param node 当前子树根节点
     * @return 黑色高度，如果不一致则返回 -1
     */
    private function getBlackHeight(node:RedBlackNode):Number {
        if (node == null) {
            return 0; // 空节点（叶子节点）计为黑色
        }

        var leftHeight:Number = getBlackHeight(node.left);
        var rightHeight:Number = getBlackHeight(node.right);

        // 如果子树的黑色高度不一致，返回 -1
        if (leftHeight == -1 || rightHeight == -1 || leftHeight != rightHeight) {
            return -1;
        }

        // 计算当前节点的黑色高度
        return leftHeight + (node.color == RedBlackNode.BLACK ? 1 : 0);
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