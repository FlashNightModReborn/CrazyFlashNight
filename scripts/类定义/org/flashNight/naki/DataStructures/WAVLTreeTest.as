import org.flashNight.naki.DataStructures.*;

/**
 * WAVLTree 测试类
 * 负责测试 WAVLTree 类的各种功能，包括添加、删除、查找、大小、遍历以及性能表现。
 * 同时与 AVL树(TreeSet) 和 红黑树(RedBlackTree) 进行性能对比。
 */
class org.flashNight.naki.DataStructures.WAVLTreeTest {
    private var wavlTree:org.flashNight.naki.DataStructures.WAVLTree;
    private var testPassed:Number;
    private var testFailed:Number;

    public function WAVLTreeTest() {
        testPassed = 0;
        testFailed = 0;
    }

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
     */
    public function runTests():Void {
        trace("========================================");
        trace("开始 WAVLTree 测试...");
        trace("========================================");

        testAdd();
        testRemove();
        testContains();
        testSize();
        testToArray();
        testEdgeCases();
        testBuildFromArray();
        testChangeCompareFunctionAndResort();
        testWAVLProperties();
        testPerformance();
        testComparison();

        trace("\n========================================");
        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
        trace("========================================");
    }

    //====================== 基本操作测试 ======================//

    private function testAdd():Void {
        trace("\n测试 add 方法...");
        wavlTree = new org.flashNight.naki.DataStructures.WAVLTree(numberCompare);
        wavlTree.add(10);
        wavlTree.add(20);
        wavlTree.add(5);
        wavlTree.add(15);
        wavlTree.add(10); // 重复添加

        assert(wavlTree.size() == 4, "添加元素后，size 应为4");
        assert(wavlTree.contains(10), "WAVLTree 应包含 10");
        assert(wavlTree.contains(20), "WAVLTree 应包含 20");
        assert(wavlTree.contains(5), "WAVLTree 应包含 5");
        assert(wavlTree.contains(15), "WAVLTree 应包含 15");
        assert(validateWAVLProperties(wavlTree.getRoot()), "添加后的树应保持WAVL属性");
    }

    private function testRemove():Void {
        trace("\n测试 remove 方法...");
        var removed:Boolean = wavlTree.remove(20);
        assert(removed, "成功移除存在的元素 20");
        assert(!wavlTree.contains(20), "WAVLTree 不应包含 20");

        removed = wavlTree.remove(25);
        assert(!removed, "移除不存在的元素 25 应返回 false");
        assert(validateWAVLProperties(wavlTree.getRoot()), "移除后的树应保持WAVL属性");
    }

    private function testContains():Void {
        trace("\n测试 contains 方法...");
        assert(wavlTree.contains(10), "WAVLTree 应包含 10");
        assert(!wavlTree.contains(20), "WAVLTree 不应包含 20");
        assert(wavlTree.contains(5), "WAVLTree 应包含 5");
        assert(wavlTree.contains(15), "WAVLTree 应包含 15");
        assert(!wavlTree.contains(25), "WAVLTree 不应包含 25");
    }

    private function testSize():Void {
        trace("\n测试 size 方法...");
        assert(wavlTree.size() == 3, "当前 size 应为3");
        wavlTree.add(25);
        assert(wavlTree.size() == 4, "添加 25 后，size 应为4");
        wavlTree.remove(5);
        assert(wavlTree.size() == 3, "移除 5 后，size 应为3");
        assert(validateWAVLProperties(wavlTree.getRoot()), "添加删除后的树应保持WAVL属性");
    }

    private function testToArray():Void {
        trace("\n测试 toArray 方法...");
        var arr:Array = wavlTree.toArray();
        var expected:Array = [10, 15, 25];

        assert(arr.length == expected.length, "toArray 返回的数组长度应为3");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    private function testEdgeCases():Void {
        trace("\n测试边界情况...");
        wavlTree = new org.flashNight.naki.DataStructures.WAVLTree(numberCompare);
        wavlTree.add(30);
        wavlTree.add(20);
        wavlTree.add(40);
        wavlTree.add(10);
        wavlTree.add(25);
        wavlTree.add(35);
        wavlTree.add(50);

        assert(validateWAVLProperties(wavlTree.getRoot()), "初始树应保持WAVL属性");

        // 删除叶子节点
        var removed:Boolean = wavlTree.remove(10);
        assert(removed, "成功移除叶子节点 10");
        assert(!wavlTree.contains(10), "WAVLTree 不应包含 10");
        assert(validateWAVLProperties(wavlTree.getRoot()), "删除叶子节点后应保持WAVL属性");

        // 删除有一个子节点的节点
        removed = wavlTree.remove(20);
        assert(removed, "成功移除有一个子节点的节点 20");
        assert(!wavlTree.contains(20), "WAVLTree 不应包含 20");
        assert(wavlTree.contains(25), "WAVLTree 应包含 25");
        assert(validateWAVLProperties(wavlTree.getRoot()), "删除有一个子节点的节点后应保持WAVL属性");

        // 删除有两个子节点的节点
        removed = wavlTree.remove(30);
        assert(removed, "成功移除有两个子节点的节点 30");
        assert(!wavlTree.contains(30), "WAVLTree 不应包含 30");
        assert(wavlTree.contains(25), "WAVLTree 应包含 25");
        assert(wavlTree.contains(35), "WAVLTree 应包含 35");
        assert(validateWAVLProperties(wavlTree.getRoot()), "删除有两个子节点的节点后应保持WAVL属性");

        var arr:Array = wavlTree.toArray();
        var expected:Array = [25, 35, 40, 50];
        assert(arr.length == expected.length, "删除节点后，toArray 返回的数组长度应为4");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "删除节点后，数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    private function testBuildFromArray():Void {
        trace("\n测试 buildFromArray 方法...");

        var arr:Array = [10, 3, 5, 20, 15, 7, 2];
        var newTree:WAVLTree = WAVLTree.buildFromArray(arr, numberCompare);

        assert(newTree.size() == arr.length, "buildFromArray 后，size 应该等于数组长度 " + arr.length);

        var sortedArr:Array = newTree.toArray();
        var expected:Array = [2, 3, 5, 7, 10, 15, 20];
        assert(sortedArr.length == expected.length, "buildFromArray 后，toArray().length 应该为 " + expected.length);

        for (var i:Number = 0; i < expected.length; i++) {
            assert(sortedArr[i] == expected[i], "buildFromArray -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedArr[i]);
        }

        assert(newTree.contains(15), "buildFromArray 后，WAVLTree 应包含 15");
        assert(!newTree.contains(999), "WAVLTree 不应包含 999");
        assert(validateWAVLProperties(newTree.getRoot()), "buildFromArray 后，WAVLTree 应保持WAVL属性");
        assert(isSorted(sortedArr, numberCompare), "buildFromArray 后，WAVLTree 的 toArray 应按升序排列");
    }

    private function testChangeCompareFunctionAndResort():Void {
        trace("\n测试 changeCompareFunctionAndResort 方法...");

        wavlTree = new WAVLTree(numberCompare);
        var elements:Array = [10, 3, 5, 20, 15, 7, 2, 25];
        for (var i:Number = 0; i < elements.length; i++) {
            wavlTree.add(elements[i]);
        }
        assert(wavlTree.size() == elements.length, "初始插入后，size 应为 " + elements.length);
        assert(validateWAVLProperties(wavlTree.getRoot()), "插入元素后，WAVLTree 应保持WAVL属性");

        var descCompare:Function = function(a, b):Number {
            return b - a;
        };

        wavlTree.changeCompareFunctionAndResort(descCompare);

        var sortedDesc:Array = wavlTree.toArray();
        var expected:Array = [25, 20, 15, 10, 7, 5, 3, 2];

        assert(sortedDesc.length == expected.length, "changeCompareFunctionAndResort 后，size 不变，依旧为 " + expected.length);

        for (i = 0; i < expected.length; i++) {
            assert(sortedDesc[i] == expected[i],
                "changeCompareFunctionAndResort -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedDesc[i]);
        }

        assert(validateWAVLProperties(wavlTree.getRoot()), "changeCompareFunctionAndResort 后，WAVLTree 应保持WAVL属性");
        assert(isSorted(sortedDesc, descCompare), "changeCompareFunctionAndResort 后，WAVLTree 的 toArray 应按降序排列");
    }

    /**
     * 测试WAVL树特有属性
     */
    private function testWAVLProperties():Void {
        trace("\n测试WAVL树特有属性...");

        var tree:WAVLTree = new WAVLTree(numberCompare);
        var elements:Array = [50, 30, 70, 20, 40, 60, 80, 15, 25, 35, 45, 55, 65, 75, 85];

        for (var i:Number = 0; i < elements.length; i++) {
            tree.add(elements[i]);
            assert(validateWAVLProperties(tree.getRoot()),
                   "添加元素 " + elements[i] + " 后，树应保持WAVL属性");
        }

        // 删除测试
        var nodesToRemove:Array = [30, 60, 25, 75];
        for (i = 0; i < nodesToRemove.length; i++) {
            tree.remove(nodesToRemove[i]);
            assert(validateWAVLProperties(tree.getRoot()),
                   "删除元素 " + nodesToRemove[i] + " 后，树应保持WAVL属性");
        }

        // 添加新节点
        var newNodes:Array = [22, 33, 66, 77];
        for (i = 0; i < newNodes.length; i++) {
            tree.add(newNodes[i]);
            assert(validateWAVLProperties(tree.getRoot()),
                   "添加元素 " + newNodes[i] + " 后，树应保持WAVL属性");
        }
    }

    //====================== 性能测试 ======================//

    private function testPerformance():Void {
        trace("\n测试性能表现...");
        var capacities:Array = [100, 1000, 10000];
        var iterations:Array = [100, 10, 1];

        for (var j:Number = 0; j < capacities.length; j++) {
            var capacity:Number = capacities[j];
            var iteration:Number = iterations[j];
            trace("\n容量: " + capacity + "，执行次数: " + iteration);

            var totalAddTime:Number = 0;
            var totalSearchTime:Number = 0;
            var totalRemoveTime:Number = 0;
            var totalBuildTime:Number = 0;
            var totalReSortTime:Number = 0;

            var removeAll:Boolean = true;
            var containsAll:Boolean = true;
            var largeTree:WAVLTree = null;

            for (var i:Number = 0; i < iteration; i++) {
                // 1) 测试添加性能
                largeTree = new org.flashNight.naki.DataStructures.WAVLTree(numberCompare);

                var startTime:Number = getTimer();
                for (var k:Number = 0; k < capacity; k++) {
                    largeTree.add(k);
                }
                var addTime:Number = getTimer() - startTime;
                totalAddTime += addTime;

                // 2) 测试搜索性能
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

                // 3) 测试移除性能
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

                // 4) 测试 buildFromArray
                var arr:Array = [];
                for (k = 0; k < capacity; k++) {
                    arr.push(k);
                }

                startTime = getTimer();
                var tempTree:WAVLTree = WAVLTree.buildFromArray(arr, numberCompare);
                var buildTime:Number = getTimer() - startTime;
                totalBuildTime += buildTime;

                if (tempTree.size() != capacity) {
                    trace("FAIL: buildFromArray 后 size 不匹配");
                    testFailed++;
                }

                // WAVL属性验证（仅小规模）
                if (capacity <= 1000 && !validateWAVLProperties(tempTree.getRoot())) {
                    trace("FAIL: buildFromArray 后，WAVLTree 未保持WAVL属性");
                    testFailed++;
                }

                // 5) 测试 changeCompareFunctionAndResort
                var descCompare:Function = function(a, b):Number {
                    return b - a;
                };

                startTime = getTimer();
                tempTree.changeCompareFunctionAndResort(descCompare);
                var reSortTime:Number = getTimer() - startTime;
                totalReSortTime += reSortTime;

                var descArr:Array = tempTree.toArray();
                if (descArr[0] < descArr[descArr.length - 1]) {
                    trace("FAIL: changeCompareFunctionAndResort 未生效");
                    testFailed++;
                }

                if (capacity <= 1000 && !validateWAVLProperties(tempTree.getRoot())) {
                    trace("FAIL: changeCompareFunctionAndResort 后，WAVLTree 未保持WAVL属性");
                    testFailed++;
                }
            }

            assert(largeTree.size() == 0, "所有元素移除后，size 应为0");
            assert(removeAll, "所有添加的元素都应成功移除");
            assert(containsAll, "所有添加的元素都应存在于 WAVLTree 中");

            var avgAddTime:Number = totalAddTime / iteration;
            var avgSearchTime:Number = totalSearchTime / iteration;
            var avgRemoveTime:Number = totalRemoveTime / iteration;
            var avgBuildTime:Number = totalBuildTime / iteration;
            var avgReSortTime:Number = totalReSortTime / iteration;

            trace("添加 " + capacity + " 个元素平均耗时: " + avgAddTime + " 毫秒");
            trace("搜索 " + capacity + " 个元素平均耗时: " + avgSearchTime + " 毫秒");
            trace("移除 " + capacity + " 个元素平均耗时: " + avgRemoveTime + " 毫秒");
            trace("buildFromArray(" + capacity + " 个元素)平均耗时: " + avgBuildTime + " 毫秒");
            trace("changeCompareFunctionAndResort(" + capacity + " 个元素)平均耗时: " + avgReSortTime + " 毫秒");
        }
    }

    /**
     * 三种树的性能对比测试
     */
    private function testComparison():Void {
        trace("\n========================================");
        trace("三种树性能对比测试 (10000元素)");
        trace("========================================");

        var capacity:Number = 10000;
        var k:Number;
        var startTime:Number;

        // ============ AVL树 (TreeSet) ============
        trace("\n--- AVL树 (TreeSet) ---");
        var avlTree:TreeSet = new TreeSet(numberCompare);

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            avlTree.add(k);
        }
        var avlAddTime:Number = getTimer() - startTime;
        trace("添加: " + avlAddTime + " ms");

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            avlTree.contains(k);
        }
        var avlSearchTime:Number = getTimer() - startTime;
        trace("搜索: " + avlSearchTime + " ms");

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            avlTree.remove(k);
        }
        var avlRemoveTime:Number = getTimer() - startTime;
        trace("删除: " + avlRemoveTime + " ms");

        // ============ 红黑树 (RedBlackTree) ============
        trace("\n--- 红黑树 (RedBlackTree) ---");
        var rbTree:RedBlackTree = new RedBlackTree(numberCompare);

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            rbTree.add(k);
        }
        var rbAddTime:Number = getTimer() - startTime;
        trace("添加: " + rbAddTime + " ms");

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            rbTree.contains(k);
        }
        var rbSearchTime:Number = getTimer() - startTime;
        trace("搜索: " + rbSearchTime + " ms");

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            rbTree.remove(k);
        }
        var rbRemoveTime:Number = getTimer() - startTime;
        trace("删除: " + rbRemoveTime + " ms");

        // ============ WAVL树 ============
        trace("\n--- WAVL树 ---");
        var wavl:WAVLTree = new WAVLTree(numberCompare);

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            wavl.add(k);
        }
        var wavlAddTime:Number = getTimer() - startTime;
        trace("添加: " + wavlAddTime + " ms");

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            wavl.contains(k);
        }
        var wavlSearchTime:Number = getTimer() - startTime;
        trace("搜索: " + wavlSearchTime + " ms");

        startTime = getTimer();
        for (k = 0; k < capacity; k++) {
            wavl.remove(k);
        }
        var wavlRemoveTime:Number = getTimer() - startTime;
        trace("删除: " + wavlRemoveTime + " ms");

        // ============ 汇总对比 ============
        trace("\n========================================");
        trace("性能对比汇总 (" + capacity + " 元素)");
        trace("========================================");
        trace("操作\t\tAVL\tRB\tWAVL");
        trace("添加\t\t" + avlAddTime + "\t" + rbAddTime + "\t" + wavlAddTime);
        trace("搜索\t\t" + avlSearchTime + "\t" + rbSearchTime + "\t" + wavlSearchTime);
        trace("删除\t\t" + avlRemoveTime + "\t" + rbRemoveTime + "\t" + wavlRemoveTime);
        trace("总计\t\t" + (avlAddTime+avlSearchTime+avlRemoveTime) + "\t" +
              (rbAddTime+rbSearchTime+rbRemoveTime) + "\t" +
              (wavlAddTime+wavlSearchTime+wavlRemoveTime));
    }

    //====================== 辅助方法 ======================//

    private function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }

    /**
     * 验证WAVL树属性（完整的四条不变量）
     *
     * WAVL 不变量：
     * 1. rank差 = 父rank - 子rank，必须为 1 或 2
     * 2. 外部节点(null)的 rank 定义为 -1
     * 3. 叶子节点的 rank 必须为 0（即 (1,1)-叶子）
     * 4. 非叶子的内部节点不能是 (2,2)-节点
     */
    private function validateWAVLProperties(node:WAVLNode):Boolean {
        if (node == null) {
            return true;
        }

        var leftRank:Number = (node.left != null) ? node.left.rank : -1;
        var rightRank:Number = (node.right != null) ? node.right.rank : -1;

        var leftDiff:Number = node.rank - leftRank;
        var rightDiff:Number = node.rank - rightRank;

        // 不变量 1: rank差必须在有效范围 [1,2]
        // 注意：对于外部节点(null)，rank=-1，所以叶子节点的rank差是 0 - (-1) = 1
        if (leftDiff < 1 || leftDiff > 2) {
            trace("WAVL违规[不变量1]: 节点 " + node.value + " 左rank差=" + leftDiff + " (应为1或2)");
            return false;
        }
        if (rightDiff < 1 || rightDiff > 2) {
            trace("WAVL违规[不变量1]: 节点 " + node.value + " 右rank差=" + rightDiff + " (应为1或2)");
            return false;
        }

        // 不变量 3: 叶子节点的rank必须是0
        var isLeaf:Boolean = (node.left == null && node.right == null);
        if (isLeaf && node.rank != 0) {
            trace("WAVL违规[不变量3]: 叶子节点 " + node.value + " 的rank应为0，实际为 " + node.rank);
            return false;
        }

        // 不变量 4: 非叶子的内部节点不能是 (2,2)-节点
        // (2,2)-节点意味着两个子节点的rank差都是2
        if (!isLeaf && leftDiff == 2 && rightDiff == 2) {
            trace("WAVL违规[不变量4]: 非叶子节点 " + node.value + " 是违规的(2,2)-节点");
            return false;
        }

        // 递归检查子树
        return validateWAVLProperties(node.left) && validateWAVLProperties(node.right);
    }

    private function isSorted(arr:Array, compare:Function):Boolean {
        for (var i:Number = 0; i < arr.length - 1; i++) {
            if (compare(arr[i], arr[i + 1]) > 0) {
                return false;
            }
        }
        return true;
    }
}
