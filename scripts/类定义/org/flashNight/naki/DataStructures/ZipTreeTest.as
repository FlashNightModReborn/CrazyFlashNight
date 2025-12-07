import org.flashNight.naki.DataStructures.*; 

/**
 * ZipTree 测试类
 * 负责测试 ZipTree 类的各种功能，包括添加、删除、查找、大小、遍历以及性能表现。
 *
 * 【Zip Tree 不变量验证】
 * 1. BST 性质: 左子树所有值 < 当前值 < 右子树所有值
 * 2. 堆序性质: 父节点的 rank >= 左子节点的 rank
 * 3. 严格堆序: 父节点的 rank > 右子节点的 rank
 *
 * 注：多树性能对比测试已迁移至 TreeSetTest.testCrossTypePerformance()
 */
class org.flashNight.naki.DataStructures.ZipTreeTest {
    private var zipTree:org.flashNight.naki.DataStructures.ZipTree;
    private var testPassed:Number;
    private var testFailed:Number;

    public function ZipTreeTest() {
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
        trace("开始 ZipTree 测试...");
        trace("========================================");

        testAdd();
        testRemove();
        testContains();
        testSize();
        testToArray();
        testEdgeCases();
        testBuildFromArray();
        testChangeCompareFunctionAndResort();
        testZipTreeProperties();
        testRandomOperations();
        testLowerBound();
        testUpperBound();
        testLowerUpperBoundEdgeCases();
        testPerformance();

        trace("\n========================================");
        trace("测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
        trace("========================================");
    }

    //====================== 基本操作测试 ======================//

    private function testAdd():Void {
        trace("\n测试 add 方法...");
        zipTree = new org.flashNight.naki.DataStructures.ZipTree(numberCompare);
        zipTree.add(10);
        zipTree.add(20);
        zipTree.add(5);
        zipTree.add(15);
        zipTree.add(10); // 重复添加

        assert(zipTree.size() == 4, "添加元素后，size 应为4");
        assert(zipTree.contains(10), "ZipTree 应包含 10");
        assert(zipTree.contains(20), "ZipTree 应包含 20");
        assert(zipTree.contains(5), "ZipTree 应包含 5");
        assert(zipTree.contains(15), "ZipTree 应包含 15");
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "添加后的树应保持Zip Tree属性");
    }

    private function testRemove():Void {
        trace("\n测试 remove 方法...");
        var removed:Boolean = zipTree.remove(20);
        assert(removed, "成功移除存在的元素 20");
        assert(!zipTree.contains(20), "ZipTree 不应包含 20");

        removed = zipTree.remove(25);
        assert(!removed, "移除不存在的元素 25 应返回 false");
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "移除后的树应保持Zip Tree属性");
    }

    private function testContains():Void {
        trace("\n测试 contains 方法...");
        assert(zipTree.contains(10), "ZipTree 应包含 10");
        assert(!zipTree.contains(20), "ZipTree 不应包含 20");
        assert(zipTree.contains(5), "ZipTree 应包含 5");
        assert(zipTree.contains(15), "ZipTree 应包含 15");
        assert(!zipTree.contains(25), "ZipTree 不应包含 25");
    }

    private function testSize():Void {
        trace("\n测试 size 方法...");
        assert(zipTree.size() == 3, "当前 size 应为3");
        zipTree.add(25);
        assert(zipTree.size() == 4, "添加 25 后，size 应为4");
        zipTree.remove(5);
        assert(zipTree.size() == 3, "移除 5 后，size 应为3");
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "添加删除后的树应保持Zip Tree属性");
    }

    private function testToArray():Void {
        trace("\n测试 toArray 方法...");
        var arr:Array = zipTree.toArray();
        var expected:Array = [10, 15, 25];

        assert(arr.length == expected.length, "toArray 返回的数组长度应为3");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    private function testEdgeCases():Void {
        trace("\n测试边界情况...");
        zipTree = new org.flashNight.naki.DataStructures.ZipTree(numberCompare);
        zipTree.add(30);
        zipTree.add(20);
        zipTree.add(40);
        zipTree.add(10);
        zipTree.add(25);
        zipTree.add(35);
        zipTree.add(50);

        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "初始树应保持Zip Tree属性");

        // 删除叶子节点
        var removed:Boolean = zipTree.remove(10);
        assert(removed, "成功移除叶子节点 10");
        assert(!zipTree.contains(10), "ZipTree 不应包含 10");
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "删除叶子节点后应保持Zip Tree属性");

        // 删除有一个子节点的节点
        removed = zipTree.remove(20);
        assert(removed, "成功移除有一个子节点的节点 20");
        assert(!zipTree.contains(20), "ZipTree 不应包含 20");
        assert(zipTree.contains(25), "ZipTree 应包含 25");
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "删除有一个子节点的节点后应保持Zip Tree属性");

        // 删除有两个子节点的节点
        removed = zipTree.remove(30);
        assert(removed, "成功移除有两个子节点的节点 30");
        assert(!zipTree.contains(30), "ZipTree 不应包含 30");
        assert(zipTree.contains(25), "ZipTree 应包含 25");
        assert(zipTree.contains(35), "ZipTree 应包含 35");
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "删除有两个子节点的节点后应保持Zip Tree属性");

        var arr:Array = zipTree.toArray();
        var expected:Array = [25, 35, 40, 50];
        assert(arr.length == expected.length, "删除节点后，toArray 返回的数组长度应为4");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "删除节点后，数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    private function testBuildFromArray():Void {
        trace("\n测试 buildFromArray 方法...");

        var arr:Array = [10, 3, 5, 20, 15, 7, 2];
        var newTree:ZipTree = ZipTree.buildFromArray(arr, numberCompare);

        assert(newTree.size() == arr.length, "buildFromArray 后，size 应该等于数组长度 " + arr.length);

        var sortedArr:Array = newTree.toArray();
        var expected:Array = [2, 3, 5, 7, 10, 15, 20];
        assert(sortedArr.length == expected.length, "buildFromArray 后，toArray().length 应该为 " + expected.length);

        for (var i:Number = 0; i < expected.length; i++) {
            assert(sortedArr[i] == expected[i], "buildFromArray -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedArr[i]);
        }

        assert(newTree.contains(15), "buildFromArray 后，ZipTree 应包含 15");
        assert(!newTree.contains(999), "ZipTree 不应包含 999");
        assert(validateZipTreeProperties(ZipNode(newTree.getRoot())), "buildFromArray 后，ZipTree 应保持Zip Tree属性");
        assert(isSorted(sortedArr, numberCompare), "buildFromArray 后，ZipTree 的 toArray 应按升序排列");
    }

    private function testChangeCompareFunctionAndResort():Void {
        trace("\n测试 changeCompareFunctionAndResort 方法...");

        zipTree = new ZipTree(numberCompare);
        var elements:Array = [10, 3, 5, 20, 15, 7, 2, 25];
        for (var i:Number = 0; i < elements.length; i++) {
            zipTree.add(elements[i]);
        }
        assert(zipTree.size() == elements.length, "初始插入后，size 应为 " + elements.length);
        assert(validateZipTreeProperties(ZipNode(zipTree.getRoot())), "插入元素后，ZipTree 应保持Zip Tree属性");

        var descCompare:Function = function(a, b):Number {
            return b - a;
        };

        zipTree.changeCompareFunctionAndResort(descCompare);

        var sortedDesc:Array = zipTree.toArray();
        var expected:Array = [25, 20, 15, 10, 7, 5, 3, 2];

        assert(sortedDesc.length == expected.length, "changeCompareFunctionAndResort 后，size 不变，依旧为 " + expected.length);

        for (i = 0; i < expected.length; i++) {
            assert(sortedDesc[i] == expected[i],
                "changeCompareFunctionAndResort -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedDesc[i]);
        }

        assert(validateZipTreePropertiesWithCompare(ZipNode(zipTree.getRoot()), descCompare), "changeCompareFunctionAndResort 后，ZipTree 应保持Zip Tree属性");
        assert(isSorted(sortedDesc, descCompare), "changeCompareFunctionAndResort 后，ZipTree 的 toArray 应按降序排列");
    }

    /**
     * 测试 Zip Tree 特有属性
     */
    private function testZipTreeProperties():Void {
        trace("\n测试 Zip Tree 特有属性...");

        var tree:ZipTree = new ZipTree(numberCompare);
        var elements:Array = [50, 30, 70, 20, 40, 60, 80, 15, 25, 35, 45, 55, 65, 75, 85];

        for (var i:Number = 0; i < elements.length; i++) {
            tree.add(elements[i]);
            assert(validateZipTreeProperties(ZipNode(tree.getRoot())),
                   "添加元素 " + elements[i] + " 后，树应保持Zip Tree属性");
        }

        // 删除测试
        var nodesToRemove:Array = [30, 60, 25, 75];
        for (i = 0; i < nodesToRemove.length; i++) {
            tree.remove(nodesToRemove[i]);
            assert(validateZipTreeProperties(ZipNode(tree.getRoot())),
                   "删除元素 " + nodesToRemove[i] + " 后，树应保持Zip Tree属性");
        }

        // 添加新节点
        var newNodes:Array = [22, 33, 66, 77];
        for (i = 0; i < newNodes.length; i++) {
            tree.add(newNodes[i]);
            assert(validateZipTreeProperties(ZipNode(tree.getRoot())),
                   "添加元素 " + newNodes[i] + " 后，树应保持Zip Tree属性");
        }
    }

    /**
     * 测试随机操作序列
     */
    private function testRandomOperations():Void {
        trace("\n测试随机操作序列...");

        var tree:ZipTree = new ZipTree(numberCompare);
        tree.setSeed(12345);  // 固定种子以确保可重复性

        // 随机插入 100 个数
        var inserted:Array = [];
        for (var i:Number = 0; i < 100; i++) {
            var val:Number = Math.floor(Math.random() * 1000);
            if (!tree.contains(val)) {
                tree.add(val);
                inserted.push(val);
            }
        }

        assert(validateZipTreeProperties(ZipNode(tree.getRoot())), "随机插入后，树应保持Zip Tree属性");
        assert(tree.size() == inserted.length, "size 应等于实际插入的元素数量");

        // 验证所有插入的元素都存在
        var allFound:Boolean = true;
        for (i = 0; i < inserted.length; i++) {
            if (!tree.contains(inserted[i])) {
                allFound = false;
                break;
            }
        }
        assert(allFound, "所有插入的元素都应存在于树中");

        // 随机删除一半
        var halfSize:Number = Math.floor(inserted.length / 2);
        for (i = 0; i < halfSize; i++) {
            tree.remove(inserted[i]);
        }

        assert(validateZipTreeProperties(ZipNode(tree.getRoot())), "随机删除后，树应保持Zip Tree属性");
        assert(tree.size() == inserted.length - halfSize, "删除后 size 应正确");

        // 验证中序遍历有序
        var arr:Array = tree.toArray();
        assert(isSorted(arr, numberCompare), "中序遍历结果应有序");
    }

    //====================== 有序搜索测试 (lowerBound/upperBound) ======================//

    /**
     * 辅助函数：从 ITreeNode 获取 value 属性
     * AS2 接口不支持属性声明，需要通过 Object 类型动态访问
     */
    private function getNodeValue(node:ITreeNode):Object {
        if (node == null) return undefined;
        return Object(node).value;
    }

    /**
     * 测试 lowerBound 方法
     * lowerBound(x) 返回第一个 >= x 的节点
     */
    private function testLowerBound():Void {
        trace("\n测试 lowerBound 方法...");

        // 创建测试集合: [10, 20, 30, 40, 50]
        var tree:ZipTree = new ZipTree(numberCompare);
        tree.add(30);
        tree.add(10);
        tree.add(50);
        tree.add(20);
        tree.add(40);

        var node:ITreeNode;

        // 测试1: 查找存在的元素
        node = tree.lowerBound(30);
        assert(node != null && getNodeValue(node) == 30, "lowerBound(30) 应返回 30");

        // 测试2: 查找不存在的元素，应返回第一个更大的
        node = tree.lowerBound(25);
        assert(node != null && getNodeValue(node) == 30, "lowerBound(25) 应返回 30（第一个 >= 25）");

        // 测试3: 查找最小值
        node = tree.lowerBound(10);
        assert(node != null && getNodeValue(node) == 10, "lowerBound(10) 应返回 10");

        // 测试4: 查找比最小值还小的值
        node = tree.lowerBound(5);
        assert(node != null && getNodeValue(node) == 10, "lowerBound(5) 应返回 10（第一个 >= 5）");

        // 测试5: 查找最大值
        node = tree.lowerBound(50);
        assert(node != null && getNodeValue(node) == 50, "lowerBound(50) 应返回 50");

        // 测试6: 查找比最大值还大的值
        node = tree.lowerBound(100);
        assert(node == null, "lowerBound(100) 应返回 null（没有 >= 100 的元素）");

        // 测试7: 精确边界
        node = tree.lowerBound(35);
        assert(node != null && getNodeValue(node) == 40, "lowerBound(35) 应返回 40（第一个 >= 35）");

        // 验证 Zip Tree 属性保持
        assert(validateZipTreeProperties(ZipNode(tree.getRoot())), "lowerBound 测试后，树应保持 Zip Tree 属性");
    }

    /**
     * 测试 upperBound 方法
     * upperBound(x) 返回第一个 > x 的节点
     */
    private function testUpperBound():Void {
        trace("\n测试 upperBound 方法...");

        // 创建测试集合: [10, 20, 30, 40, 50]
        var tree:ZipTree = new ZipTree(numberCompare);
        tree.add(30);
        tree.add(10);
        tree.add(50);
        tree.add(20);
        tree.add(40);

        var node:ITreeNode;

        // 测试1: 查找存在的元素，应返回下一个更大的
        node = tree.upperBound(30);
        assert(node != null && getNodeValue(node) == 40, "upperBound(30) 应返回 40（第一个 > 30）");

        // 测试2: 查找不存在的元素
        node = tree.upperBound(25);
        assert(node != null && getNodeValue(node) == 30, "upperBound(25) 应返回 30（第一个 > 25）");

        // 测试3: 查找最小值，应返回第二小的
        node = tree.upperBound(10);
        assert(node != null && getNodeValue(node) == 20, "upperBound(10) 应返回 20（第一个 > 10）");

        // 测试4: 查找比最小值还小的值
        node = tree.upperBound(5);
        assert(node != null && getNodeValue(node) == 10, "upperBound(5) 应返回 10（第一个 > 5）");

        // 测试5: 查找最大值
        node = tree.upperBound(50);
        assert(node == null, "upperBound(50) 应返回 null（没有 > 50 的元素）");

        // 测试6: 查找比最大值还大的值
        node = tree.upperBound(100);
        assert(node == null, "upperBound(100) 应返回 null（没有 > 100 的元素）");

        // 测试7: 精确边界
        node = tree.upperBound(35);
        assert(node != null && getNodeValue(node) == 40, "upperBound(35) 应返回 40（第一个 > 35）");

        // 测试8: upperBound 与 lowerBound 的区别验证
        var lb:ITreeNode = tree.lowerBound(20);
        var ub:ITreeNode = tree.upperBound(20);
        assert(lb != null && getNodeValue(lb) == 20, "lowerBound(20) == 20");
        assert(ub != null && getNodeValue(ub) == 30, "upperBound(20) == 30");

        // 验证 Zip Tree 属性保持
        assert(validateZipTreeProperties(ZipNode(tree.getRoot())), "upperBound 测试后，树应保持 Zip Tree 属性");
    }

    /**
     * 测试 lowerBound/upperBound 边界情况
     */
    private function testLowerUpperBoundEdgeCases():Void {
        trace("\n测试 lowerBound/upperBound 边界情况...");

        var node:ITreeNode;

        // ============ 测试空树 ============
        var emptyTree:ZipTree = new ZipTree(numberCompare);

        node = emptyTree.lowerBound(10);
        assert(node == null, "空树 lowerBound(10) 应返回 null");

        node = emptyTree.upperBound(10);
        assert(node == null, "空树 upperBound(10) 应返回 null");

        // ============ 测试单元素树 ============
        var singleTree:ZipTree = new ZipTree(numberCompare);
        singleTree.add(50);

        node = singleTree.lowerBound(50);
        assert(node != null && getNodeValue(node) == 50, "单元素树 lowerBound(50) 应返回 50");

        node = singleTree.lowerBound(30);
        assert(node != null && getNodeValue(node) == 50, "单元素树 lowerBound(30) 应返回 50");

        node = singleTree.lowerBound(70);
        assert(node == null, "单元素树 lowerBound(70) 应返回 null");

        node = singleTree.upperBound(50);
        assert(node == null, "单元素树 upperBound(50) 应返回 null");

        node = singleTree.upperBound(30);
        assert(node != null && getNodeValue(node) == 50, "单元素树 upperBound(30) 应返回 50");

        // ============ 测试连续值 ============
        var seqTree:ZipTree = new ZipTree(numberCompare);
        for (var i:Number = 1; i <= 10; i++) {
            seqTree.add(i);
        }

        // 验证所有元素的 lowerBound
        for (i = 1; i <= 10; i++) {
            node = seqTree.lowerBound(i);
            assert(node != null && getNodeValue(node) == i, "lowerBound(" + i + ") 应返回 " + i);
        }

        // 验证所有元素的 upperBound
        for (i = 1; i <= 9; i++) {
            node = seqTree.upperBound(i);
            assert(node != null && getNodeValue(node) == (i + 1), "upperBound(" + i + ") 应返回 " + (i + 1));
        }
        node = seqTree.upperBound(10);
        assert(node == null, "upperBound(10) 应返回 null");

        // 验证 Zip Tree 属性保持
        assert(validateZipTreeProperties(ZipNode(seqTree.getRoot())), "边界测试后，树应保持 Zip Tree 属性");
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
            var largeTree:ZipTree = null;

            for (var i:Number = 0; i < iteration; i++) {
                // 1) 测试添加性能
                largeTree = new org.flashNight.naki.DataStructures.ZipTree(numberCompare);

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
                var tempTree:ZipTree = ZipTree.buildFromArray(arr, numberCompare);
                var buildTime:Number = getTimer() - startTime;
                totalBuildTime += buildTime;

                if (tempTree.size() != capacity) {
                    trace("FAIL: buildFromArray 后 size 不匹配");
                    testFailed++;
                }

                // Zip Tree 属性验证（仅小规模）
                if (capacity <= 1000 && !validateZipTreeProperties(ZipNode(tempTree.getRoot()))) {
                    trace("FAIL: buildFromArray 后，ZipTree 未保持Zip Tree属性");
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

                if (capacity <= 1000 && !validateZipTreePropertiesWithCompare(ZipNode(tempTree.getRoot()), descCompare)) {
                    trace("FAIL: changeCompareFunctionAndResort 后，ZipTree 未保持Zip Tree属性");
                    testFailed++;
                }
            }

            assert(largeTree.size() == 0, "所有元素移除后，size 应为0");
            assert(removeAll, "所有添加的元素都应成功移除");
            assert(containsAll, "所有添加的元素都应存在于 ZipTree 中");

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

    //====================== 辅助方法 ======================//

    private function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }

    /**
     * 验证 Zip Tree 属性（三条不变量）- 默认使用升序比较
     *
     * Zip Tree 不变量（来自 Tarjan, Levy, Timmel 2019 "Zip Trees"）：
     * 1. BST 性质: 按比较函数定义的顺序
     * 2. 堆序性质: 父节点的 rank >= 左子节点的 rank
     * 3. 严格堆序: 父节点的 rank > 右子节点的 rank
     *
     * @param node 要验证的节点
     * @return 是否满足所有不变量
     */
    private function validateZipTreeProperties(node:ZipNode):Boolean {
        return validateZipTreePropertiesWithCompare(node, numberCompare);
    }

    /**
     * 验证 Zip Tree 属性（使用指定比较函数）
     *
     * @param node 要验证的节点
     * @param compare 比较函数
     * @return 是否满足所有不变量
     */
    private function validateZipTreePropertiesWithCompare(node:ZipNode, compare:Function):Boolean {
        return validateZipTreePropertiesHelper(node, null, null, compare);
    }

    /**
     * 递归验证 Zip Tree 属性
     *
     * @param node 当前节点
     * @param minVal 最小值边界（null 表示无限制）
     * @param maxVal 最大值边界（null 表示无限制）
     * @param compare 比较函数
     */
    private function validateZipTreePropertiesHelper(node:ZipNode, minVal:Object, maxVal:Object, compare:Function):Boolean {
        if (node == null) {
            return true;
        }

        var nodeVal:Object = node.value;
        var nodeRank:Number = node.rank;

        // 不变量 1: BST 性质（使用比较函数）
        // compare(a, b) < 0 表示 a 在 b 之前（即 a "小于" b）
        if (minVal != null && compare(nodeVal, minVal) <= 0) {
            trace("ZipTree违规[BST]: 节点 " + nodeVal + " 应在 " + minVal + " 之后（按比较函数）");
            return false;
        }
        if (maxVal != null && compare(nodeVal, maxVal) >= 0) {
            trace("ZipTree违规[BST]: 节点 " + nodeVal + " 应在 " + maxVal + " 之前（按比较函数）");
            return false;
        }

        // 不变量 2 & 3: 堆序性质
        // 检查左子节点: parent.rank >= left.rank
        if (node.left != null) {
            if (nodeRank < node.left.rank) {
                trace("ZipTree违规[堆序-左]: 节点 " + nodeVal + " (rank=" + nodeRank +
                      ") 应 >= 左子 " + node.left.value + " (rank=" + node.left.rank + ")");
                return false;
            }
        }

        // 检查右子节点: parent.rank > right.rank (严格大于)
        if (node.right != null) {
            if (nodeRank <= node.right.rank) {
                trace("ZipTree违规[堆序-右]: 节点 " + nodeVal + " (rank=" + nodeRank +
                      ") 应 > 右子 " + node.right.value + " (rank=" + node.right.rank + ")");
                return false;
            }
        }

        // 递归检查子树
        return validateZipTreePropertiesHelper(node.left, minVal, nodeVal, compare) &&
               validateZipTreePropertiesHelper(node.right, nodeVal, maxVal, compare);
    }

    /**
     * 检查数组是否按指定比较函数排序
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
