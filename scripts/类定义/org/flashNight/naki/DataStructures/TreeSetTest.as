import org.flashNight.naki.DataStructures.*;

/**
 * TreeSet 测试类
 * 负责测试 TreeSet 基座类的各种功能，包括添加、删除、查找、大小、遍历以及性能表现。
 *
 * 改造后的测试类：
 * - 支持测试多种树类型（AVL/WAVL/RB/LLRB/ZIP）
 * - 不再依赖具体节点类型（TreeNode/AVLNode 等）
 * - 只测试公共 API 行为，不测试内部平衡结构
 */
class org.flashNight.naki.DataStructures.TreeSetTest {
    private var treeSet:org.flashNight.naki.DataStructures.TreeSet; // 测试用的 TreeSet 实例
    private var testPassed:Number;   // 通过的测试数量
    private var testFailed:Number;   // 失败的测试数量
    private var currentType:String;  // 当前测试的树类型

    /**
     * 构造函数
     * 初始化测试统计变量。
     */
    public function TreeSetTest() {
        testPassed = 0;
        testFailed = 0;
        currentType = TreeSet.TYPE_WAVL; // 默认类型（与 TreeSet 本体一致，综合性能最佳）
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
     * 改造后：循环测试所有树类型
     */
    public function runTests():Void {
        trace("开始 TreeSet 基座测试...");

        // 定义要测试的所有树类型
        var types:Array = [
            TreeSet.TYPE_AVL,
            TreeSet.TYPE_WAVL,
            TreeSet.TYPE_RB,
            TreeSet.TYPE_LLRB,
            TreeSet.TYPE_ZIP
        ];

        // 循环测试每种类型
        for (var i:Number = 0; i < types.length; i++) {
            currentType = types[i];
            trace("\n=== 测试 TreeSet@" + currentType + " ===");
            runAllFunctionalTestsForCurrentType();
        }

        // 性能基准测试（使用默认 WAVL，与 TreeSet 本体一致）
        currentType = TreeSet.TYPE_WAVL;
        testPerformance();

        // 跨树类型性能对比测试
        testCrossTypePerformance();

        trace("\n测试完成。通过: " + testPassed + " 个，失败: " + testFailed + " 个。");
    }

    /**
     * 运行当前类型的所有功能测试
     */
    private function runAllFunctionalTestsForCurrentType():Void {
        testAdd();
        testRemove();
        testContains();
        testSize();
        testToArray();
        testEdgeCases();
        testBuildFromArray();
        testChangeCompareFunctionAndResort();
    }

    /**
     * 创建新的 TreeSet 实例（使用当前类型）
     */
    private function newSet():TreeSet {
        return new TreeSet(numberCompare, currentType);
    }

    //====================== 原有正确性测试 ======================//

    /**
     * 测试 add 方法
     * 检查添加元素、重复添加以及树的大小和包含性。
     */
    private function testAdd():Void {
        trace("\n测试 add 方法 [" + currentType + "]...");
        // 使用当前类型创建 TreeSet
        treeSet = newSet();
        treeSet.add(10);
        treeSet.add(20);
        treeSet.add(5);
        treeSet.add(15);
        treeSet.add(10); // 重复添加

        // 期望 size 为4，因为10被重复添加
        assert(treeSet.size() == 4, "[" + currentType + "] 添加元素后，size 应为4");

        // 检查元素是否存在
        assert(treeSet.contains(10), "[" + currentType + "] TreeSet 应包含 10");
        assert(treeSet.contains(20), "[" + currentType + "] TreeSet 应包含 20");
        assert(treeSet.contains(5), "[" + currentType + "] TreeSet 应包含 5");
        assert(treeSet.contains(15), "[" + currentType + "] TreeSet 应包含 15");
    }

    /**
     * 测试 remove 方法
     * 检查移除存在和不存在的元素，以及树的大小和包含性。
     */
    private function testRemove():Void {
        trace("\n测试 remove 方法 [" + currentType + "]...");
        // 移除存在的元素
        var removed:Boolean = treeSet.remove(20);
        assert(removed, "[" + currentType + "] 成功移除存在的元素 20");
        assert(!treeSet.contains(20), "[" + currentType + "] TreeSet 不应包含 20");

        // 尝试移除不存在的元素
        removed = treeSet.remove(25);
        assert(!removed, "[" + currentType + "] 移除不存在的元素 25 应返回 false");
    }

    /**
     * 测试 contains 方法
     * 检查 TreeSet 是否正确包含或不包含特定元素。
     */
    private function testContains():Void {
        trace("\n测试 contains 方法 [" + currentType + "]...");
        assert(treeSet.contains(10), "[" + currentType + "] TreeSet 应包含 10");
        assert(!treeSet.contains(20), "[" + currentType + "] TreeSet 不应包含 20");
        assert(treeSet.contains(5), "[" + currentType + "] TreeSet 应包含 5");
        assert(treeSet.contains(15), "[" + currentType + "] TreeSet 应包含 15");
        assert(!treeSet.contains(25), "[" + currentType + "] TreeSet 不应包含 25");
    }

    /**
     * 测试 size 方法
     * 检查 TreeSet 的大小在添加和删除元素后的变化。
     */
    private function testSize():Void {
        trace("\n测试 size 方法 [" + currentType + "]...");
        assert(treeSet.size() == 3, "[" + currentType + "] 当前 size 应为3");
        treeSet.add(25);
        assert(treeSet.size() == 4, "[" + currentType + "] 添加 25 后，size 应为4");
        treeSet.remove(5);
        assert(treeSet.size() == 3, "[" + currentType + "] 移除 5 后，size 应为3");
    }

    /**
     * 测试 toArray 方法
     * 检查中序遍历后的数组是否按预期排序，并包含正确的元素。
     */
    private function testToArray():Void {
        trace("\n测试 toArray 方法 [" + currentType + "]...");
        var arr:Array = treeSet.toArray();
        var expected:Array = [10, 15, 25]; // 5 已被移除

        // 检查数组长度
        assert(arr.length == expected.length, "[" + currentType + "] toArray 返回的数组长度应为3");

        // 检查数组内容
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "[" + currentType + "] 数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    /**
     * 测试边界情况
     * 包括删除根节点、删除有两个子节点的节点、删除叶子节点等。
     */
    private function testEdgeCases():Void {
        trace("\n测试边界情况 [" + currentType + "]...");
        // 重建 TreeSet（使用当前类型）
        treeSet = newSet();
        treeSet.add(30);
        treeSet.add(20);
        treeSet.add(40);
        treeSet.add(10);
        treeSet.add(25);
        treeSet.add(35);
        treeSet.add(50);

        // 删除叶子节点
        var removed:Boolean = treeSet.remove(10);
        assert(removed, "[" + currentType + "] 成功移除叶子节点 10");
        assert(!treeSet.contains(10), "[" + currentType + "] TreeSet 不应包含 10");

        // 删除有一个子节点的节点
        removed = treeSet.remove(20);
        assert(removed, "[" + currentType + "] 成功移除有一个子节点的节点 20");
        assert(!treeSet.contains(20), "[" + currentType + "] TreeSet 不应包含 20");
        assert(treeSet.contains(25), "[" + currentType + "] TreeSet 应包含 25");

        // 删除有两个子节点的节点（根节点）
        removed = treeSet.remove(30);
        assert(removed, "[" + currentType + "] 成功移除有两个子节点的节点 30");
        assert(!treeSet.contains(30), "[" + currentType + "] TreeSet 不应包含 30");
        assert(treeSet.contains(25), "[" + currentType + "] TreeSet 应包含 25");
        assert(treeSet.contains(35), "[" + currentType + "] TreeSet 应包含 35");

        // 检查有序性（不再检查平衡性，因为不同树类型有不同平衡规则）
        var arr:Array = treeSet.toArray();
        var expected:Array = [25, 35, 40, 50];
        assert(arr.length == expected.length, "[" + currentType + "] 删除节点后，toArray 返回的数组长度应为4");
        for (var i:Number = 0; i < expected.length; i++) {
            assert(arr[i] == expected[i], "[" + currentType + "] 删除节点后，数组元素应为 " + expected[i] + "，实际为 " + arr[i]);
        }
    }

    //====================== 新增测试点 ======================//

    /**
     * 测试通过数组构建 TreeSet (buildFromArray)
     * 1. 使用给定数组和比较函数构建 TreeSet
     * 2. 检查大小、顺序、以及包含性
     * 3. 全面验证有序性（不再检查平衡性，因为不同树类型有不同平衡规则）
     */
    private function testBuildFromArray():Void {
        trace("\n测试 buildFromArray 方法 [" + currentType + "]...");

        // 测试数组
        var arr:Array = [10, 3, 5, 20, 15, 7, 2];
        // 调用静态方法快速构建平衡树（使用当前类型）
        var builtSet:TreeSet = TreeSet.buildFromArray(arr, numberCompare, currentType);

        // 检查大小
        assert(builtSet.size() == arr.length, "[" + currentType + "] buildFromArray 后，size 应该等于数组长度 " + arr.length);

        // 检查是否有序 (调用 toArray)
        var sortedArr:Array = builtSet.toArray();
        // 由于 numberCompare，是升序，所以 toArray() 应该是 [2, 3, 5, 7, 10, 15, 20]
        var expected:Array = [2, 3, 5, 7, 10, 15, 20];
        assert(sortedArr.length == expected.length, "[" + currentType + "] buildFromArray 后，toArray().length 应该为 " + expected.length);

        for (var i:Number = 0; i < expected.length; i++) {
            assert(sortedArr[i] == expected[i], "[" + currentType + "] buildFromArray -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedArr[i]);
        }

        // 再测试一下 contains
        assert(builtSet.contains(15), "[" + currentType + "] buildFromArray 后，TreeSet 应包含 15");
        assert(!builtSet.contains(999), "[" + currentType + "] TreeSet 不应包含 999");

        // 验证树类型正确
        assert(builtSet.getTreeType() == currentType, "[" + currentType + "] buildFromArray 后，树类型应为 " + currentType);

        // 全面验证有序性
        assert(isSorted(sortedArr, numberCompare), "[" + currentType + "] buildFromArray 后，TreeSet 的 toArray 应按升序排列");
    }

    /**
     * 测试动态切换比较函数并重排 (changeCompareFunctionAndResort)
     * 1. 给 TreeSet 添加一些元素
     * 2. 调用 changeCompareFunctionAndResort 换成降序
     * 3. 检查排序结果
     * 4. 全面验证有序性（不再检查平衡性）
     */
    private function testChangeCompareFunctionAndResort():Void {
        trace("\n测试 changeCompareFunctionAndResort 方法 [" + currentType + "]...");

        // 建立一个 TreeSet 并插入元素（使用当前类型）
        treeSet = newSet();
        var elements:Array = [10, 3, 5, 20, 15, 7, 2, 25];
        for (var i:Number = 0; i < elements.length; i++) {
            treeSet.add(elements[i]);
        }
        assert(treeSet.size() == elements.length, "[" + currentType + "] 初始插入后，size 应为 " + elements.length);

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

        assert(sortedDesc.length == expected.length, "[" + currentType + "] changeCompareFunctionAndResort 后，size 不变，依旧为 " + expected.length);

        for (i = 0; i < expected.length; i++) {
            assert(sortedDesc[i] == expected[i],
                "[" + currentType + "] changeCompareFunctionAndResort -> 第 " + i + " 个元素应为 " + expected[i] + "，实际是 " + sortedDesc[i]);
        }

        // 全面验证有序性
        assert(isSorted(sortedDesc, descCompare), "[" + currentType + "] changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列");
    }

    //====================== 性能测试 ======================//

    /**
     * 测试性能表现
     * 分别测试容量为100、1000、10000的情况，每个容量级别执行不同次数的测试。
     * 使用当前类型进行测试（默认 AVL）
     */
    private function testPerformance():Void {
        trace("\n测试性能表现 [" + currentType + "]...");
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
                largeSet = newSet(); // 使用当前类型

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
                var arr:Array = [];
                for (k = 0; k < capacity; k++) {
                    arr.push(k);
                }

                // 计时
                startTime = getTimer();
                // build一个新的TreeSet（使用当前类型）
                var tempSet:TreeSet = TreeSet.buildFromArray(arr, numberCompare, currentType);
                var buildTime:Number = getTimer() - startTime;
                totalBuildTime += buildTime;

                // 简单校验
                if (tempSet.size() != capacity) {
                    trace("FAIL: buildFromArray 后 size 不匹配，期望=" + capacity + " 实际=" + tempSet.size());
                    testFailed++;
                }

                // 额外的全面验证
                var sortedArr:Array = tempSet.toArray();

                // 检查有序性
                if (!isSorted(sortedArr, numberCompare)) {
                    trace("FAIL: buildFromArray 后，toArray() 未按升序排列");
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

                // 检查有序性
                if (!isSorted(descArr, descCompare)) {
                    trace("FAIL: changeCompareFunctionAndResort 后，toArray() 未按降序排列");
                    testFailed++;
                }
            }

            // 最终检查
            assert(largeSet.size() == 0, "[" + currentType + "] 所有元素移除后，size 应为0");
            assert(removeAll, "[" + currentType + "] 所有添加的元素都应成功移除");
            assert(containsAll, "[" + currentType + "] 所有添加的元素都应存在于 TreeSet 中");

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
    //====================== 跨树类型性能对比 ======================//

    /**
     * 跨树类型性能对比测试
     * 统一在 TreeSetTest 中进行所有树类型的性能横向对比
     * 替代原来分散在各个 *TreeTest 中的 testComparison() 方法
     *
     * 测试多个容量级别：1000 / 10000 / 100000
     * 便于观察不同数据规模下各树类型的性能表现和扩展性
     */
    private function testCrossTypePerformance():Void {
        trace("\n########################################");
        trace("## 五种树类型跨容量性能对比测试");
        trace("########################################");

        // 定义所有树类型
        var types:Array = [
            TreeSet.TYPE_AVL,
            TreeSet.TYPE_WAVL,
            TreeSet.TYPE_RB,
            TreeSet.TYPE_LLRB,
            TreeSet.TYPE_ZIP
        ];
        var typeNames:Array = ["AVL", "WAVL", "RB", "LLRB", "Zip"];

        // 定义测试容量级别：1e3, 1e4, 1e5
        var capacities:Array = [1000, 10000, 100000];
        var capacityLabels:Array = ["1K", "10K", "100K"];

        // 遍历每个容量级别
        for (var c:Number = 0; c < capacities.length; c++) {
            var capacity:Number = capacities[c];
            var capacityLabel:String = capacityLabels[c];

            trace("\n========================================");
            trace("容量级别: " + capacityLabel + " (" + capacity + " 元素)");
            trace("========================================");

            // 存储各类型在当前容量下的性能数据
            var addTimes:Array = [];
            var searchTimes:Array = [];
            var removeTimes:Array = [];
            var buildTimes:Array = [];

            // 测试每种树类型
            for (var t:Number = 0; t < types.length; t++) {
                var treeType:String = types[t];
                var typeName:String = typeNames[t];
                trace("\n--- " + typeName + " ---");

                var k:Number;
                var startTime:Number;

                // 创建树
                var tree:TreeSet = new TreeSet(numberCompare, treeType);

                // 1) 添加性能
                startTime = getTimer();
                for (k = 0; k < capacity; k++) {
                    tree.add(k);
                }
                var addTime:Number = getTimer() - startTime;
                addTimes.push(addTime);
                trace("添加: " + addTime + " ms");

                // 2) 搜索性能
                startTime = getTimer();
                for (k = 0; k < capacity; k++) {
                    tree.contains(k);
                }
                var searchTime:Number = getTimer() - startTime;
                searchTimes.push(searchTime);
                trace("搜索: " + searchTime + " ms");

                // 3) 删除性能
                startTime = getTimer();
                for (k = 0; k < capacity; k++) {
                    tree.remove(k);
                }
                var removeTime:Number = getTimer() - startTime;
                removeTimes.push(removeTime);
                trace("删除: " + removeTime + " ms");

                // 4) buildFromArray 性能
                var arr:Array = [];
                for (k = 0; k < capacity; k++) {
                    arr.push(k);
                }
                startTime = getTimer();
                var builtTree:TreeSet = TreeSet.buildFromArray(arr, numberCompare, treeType);
                var buildTime:Number = getTimer() - startTime;
                buildTimes.push(buildTime);
                trace("构建: " + buildTime + " ms");
            }

            // ============ 当前容量汇总对比 ============
            printComparisonTable(capacityLabel, capacity, typeNames, addTimes, searchTimes, removeTimes, buildTimes);
        }

        // ============ 全容量汇总表 ============
        trace("\n########################################");
        trace("## 全容量对比完成");
        trace("########################################");
    }

    /**
     * 打印性能对比汇总表
     */
    private function printComparisonTable(
        capacityLabel:String,
        capacity:Number,
        typeNames:Array,
        addTimes:Array,
        searchTimes:Array,
        removeTimes:Array,
        buildTimes:Array
    ):Void {
        trace("\n----------------------------------------");
        trace("汇总表 [" + capacityLabel + "] (" + capacity + " 元素)");
        trace("----------------------------------------");

        // 构建表头
        var header:String = "操作\t\t";
        for (var h:Number = 0; h < typeNames.length; h++) {
            header += typeNames[h] + "\t";
        }
        trace(header);

        // 添加行
        var addRow:String = "添加\t\t";
        for (var a:Number = 0; a < addTimes.length; a++) {
            addRow += addTimes[a] + "\t";
        }
        trace(addRow);

        // 搜索行
        var searchRow:String = "搜索\t\t";
        for (var s:Number = 0; s < searchTimes.length; s++) {
            searchRow += searchTimes[s] + "\t";
        }
        trace(searchRow);

        // 删除行
        var removeRow:String = "删除\t\t";
        for (var r:Number = 0; r < removeTimes.length; r++) {
            removeRow += removeTimes[r] + "\t";
        }
        trace(removeRow);

        // 构建行
        var buildRow:String = "构建\t\t";
        for (var b:Number = 0; b < buildTimes.length; b++) {
            buildRow += buildTimes[b] + "\t";
        }
        trace(buildRow);

        // 总计行
        var totalRow:String = "总计\t\t";
        for (var i:Number = 0; i < typeNames.length; i++) {
            var total:Number = addTimes[i] + searchTimes[i] + removeTimes[i] + buildTimes[i];
            totalRow += total + "\t";
        }
        trace(totalRow);

        // 计算并显示最优/最差
        trace("");
        printBestWorst("添加", typeNames, addTimes);
        printBestWorst("搜索", typeNames, searchTimes);
        printBestWorst("删除", typeNames, removeTimes);
        printBestWorst("构建", typeNames, buildTimes);
    }

    /**
     * 打印某项操作的最优和最差树类型
     */
    private function printBestWorst(opName:String, typeNames:Array, times:Array):Void {
        var bestIdx:Number = 0;
        var worstIdx:Number = 0;
        for (var i:Number = 1; i < times.length; i++) {
            if (times[i] < times[bestIdx]) {
                bestIdx = i;
            }
            if (times[i] > times[worstIdx]) {
                worstIdx = i;
            }
        }
        trace(opName + " 最优: " + typeNames[bestIdx] + " (" + times[bestIdx] + "ms)" +
              " | 最差: " + typeNames[worstIdx] + " (" + times[worstIdx] + "ms)");
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

    // 注意：isBalanced 函数已移除
    // 平衡性检查（AVL/WAVL/红黑树性质）应在各自的 *TreeTest 类中完成
    // TreeSetTest 只测试公共 API 行为，不测试内部平衡结构
}
