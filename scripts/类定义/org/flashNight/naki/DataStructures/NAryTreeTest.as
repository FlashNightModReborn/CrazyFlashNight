/*---------------------------------------------------------------------------
    文件: org/flashNight/naki/DataStructures/NAryTreeTest.as
    描述: NAryTree 的测试类（增强版），包含内置断言系统、边界情况、遍历顺序、
         全局索引及性能测试（新增删除性能测试部分）
---------------------------------------------------------------------------*/
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.NAryTreeTest {
    // 用于记录测试通过数和失败数
    private var totalTests:Number;
    private var failedTests:Number;
    
    /**
     * 构造函数
     */
    public function NAryTreeTest() {
        totalTests = 0;
        failedTests = 0;
    }
    
    /**
     * 内置断言函数
     * @param condition 测试条件，布尔值
     * @param message   测试描述
     */
    private function assertTrue(condition:Boolean, message:String):Void {
        totalTests++;
        if (!condition) {
            failedTests++;
            trace("[FAIL] " + message);
        } else {
            trace("[PASS] " + message);
        }
    }
    
    /**
     * 断言两个值相等
     * @param actual   实际值
     * @param expected 预期值
     * @param message  测试描述
     */
    private function assertEqual(actual, expected, message:String):Void {
        totalTests++;
        if (actual != expected) {
            failedTests++;
            trace("[FAIL] " + message + " - expected: " + expected + ", actual: " + actual);
        } else {
            trace("[PASS] " + message);
        }
    }
    
    /**
     * 运行所有测试
     */
    public function runAllTests():Void {
        trace("===== NAryTree 测试开始 =====");
        testAddAndRemove();
        testTraversalAndDepth();
        testTraverseOrder();
        testSearch();
        testBoundaryConditions();
        testAdvancedAddChild();
        testGlobalIndex();
        testPerformance();
        trace("===== 测试结束 =====");
        trace("总测试数: " + totalTests + "，失败数: " + failedTests);
    }
    
    /**
     * 测试添加和删除节点功能
     */
    private function testAddAndRemove():Void {
        trace("---- testAddAndRemove ----");
        var tree:NAryTree = new NAryTree("root");
        var root:NAryTreeNode = tree.getRoot();
        
        // 添加子节点
        var child1:NAryTreeNode = new NAryTreeNode("child1");
        var child2:NAryTreeNode = new NAryTreeNode("child2");
        root.addChild(child1);
        root.addChild(child2);
        
        // 断言根节点子节点数为2
        assertEqual(root.getNumberOfChildren(), 2, "添加两个子节点后，根节点子节点数应为2");
        
        // 删除子节点
        var removed:Boolean = root.removeChild(child1);
        assertTrue(removed, "删除 child1 应返回 true");
        assertEqual(root.getNumberOfChildren(), 1, "删除 child1 后，根节点子节点数应为1");
        
        // 尝试删除不存在的节点
        removed = root.removeChild(child1);
        assertTrue(!removed, "再次删除 child1 应返回 false");
    }
    
    /**
     * 测试遍历以及节点深度计算
     */
    private function testTraversalAndDepth():Void {
        trace("---- testTraversalAndDepth ----");
        var tree:NAryTree = new NAryTree("root");
        var root:NAryTreeNode = tree.getRoot();
        
        // 构建树结构：
        //       root
        //       /   \
        //   child1  child2
        //     /  \
        // child1.1 child1.2
        var child1:NAryTreeNode = new NAryTreeNode("child1");
        var child2:NAryTreeNode = new NAryTreeNode("child2");
        root.addChild(child1);
        root.addChild(child2);
        var child1_1:NAryTreeNode = new NAryTreeNode("child1.1");
        var child1_2:NAryTreeNode = new NAryTreeNode("child1.2");
        child1.addChild(child1_1);
        child1.addChild(child1_2);
        
        // 测试深度
        assertEqual(root.getDepth(), 0, "根节点深度应为0");
        assertEqual(child1.getDepth(), 1, "child1 深度应为1");
        assertEqual(child1_1.getDepth(), 2, "child1.1 深度应为2");
        assertEqual(child2.getDepth(), 1, "child2 深度应为1");
        
        // 遍历测试：计数节点数（前序遍历）
        var count:Number = 0;
        root.traversePreOrder(function(node:NAryTreeNode):Boolean {
            count++;
            return true;
        });
        assertEqual(count, 5, "前序遍历应访问5个节点");
        
        // 后序遍历测试：计数节点数
        count = 0;
        root.traversePostOrder(function(node:NAryTreeNode):Boolean {
            count++;
            return true;
        });
        assertEqual(count, 5, "后序遍历应访问5个节点");
    }
    
    /**
     * 测试遍历顺序：前序与后序遍历输出顺序不同
     */
    private function testTraverseOrder():Void {
        trace("---- testTraverseOrder ----");
        // 构建简单树： A -> [B, C]
        var tree:NAryTree = new NAryTree("A");
        var root:NAryTreeNode = tree.getRoot();
        var nodeB:NAryTreeNode = new NAryTreeNode("B");
        var nodeC:NAryTreeNode = new NAryTreeNode("C");
        root.addChild(nodeB);
        root.addChild(nodeC);
        
        // 前序遍历预期顺序：A, B, C
        var preOrder:Array = [];
        root.traversePreOrder(function(node:NAryTreeNode):Boolean {
            preOrder.push(node.data);
            return true;
        });
        var expectedPreOrder:Array = ["A", "B", "C"];
        assertEqual(preOrder.toString(), expectedPreOrder.toString(), "前序遍历顺序应为 A, B, C");
        
        // 后序遍历预期顺序：B, C, A
        var postOrder:Array = [];
        root.traversePostOrder(function(node:NAryTreeNode):Boolean {
            postOrder.push(node.data);
            return true;
        });
        var expectedPostOrder:Array = ["B", "C", "A"];
        assertEqual(postOrder.toString(), expectedPostOrder.toString(), "后序遍历顺序应为 B, C, A");
    }
    
    /**
     * 测试搜索功能
     */
    private function testSearch():Void {
        trace("---- testSearch ----");
        var tree:NAryTree = new NAryTree("root");
        var root:NAryTreeNode = tree.getRoot();
        var child1:NAryTreeNode = new NAryTreeNode("child1");
        var child2:NAryTreeNode = new NAryTreeNode("child2");
        root.addChild(child1);
        root.addChild(child2);
        var child1_1:NAryTreeNode = new NAryTreeNode("child1.1");
        child1.addChild(child1_1);
        
        // 比较函数：简单比较 data 字符串是否相等
        var compareFunction:Function = function(data, target):Boolean {
            return (data == target);
        };
        
        var result:NAryTreeNode = tree.search("child1.1", compareFunction);
        assertTrue(result != null, "搜索 child1.1 应返回对应节点");
        assertEqual(result.data, "child1.1", "搜索到的节点 data 应为 child1.1");
        
        result = tree.search("不存在的节点", compareFunction);
        assertTrue(result == null, "搜索不存在的节点应返回 null");
    }
    
    /**
     * 测试边界条件及非法参数处理
     */
    private function testBoundaryConditions():Void {
        trace("---- testBoundaryConditions ----");
        // 测试只有根节点的情况
        var tree:NAryTree = new NAryTree("onlyRoot");
        var root:NAryTreeNode = tree.getRoot();
        assertTrue(root.isLeaf(), "只有根节点时，根节点应为叶子节点");
        assertEqual(root.getNumberOfChildren(), 0, "只有根节点时，子节点数量应为0");
        
        // 测试删除不存在的子节点
        var fakeNode:NAryTreeNode = new NAryTreeNode("fake");
        var removed:Boolean = root.removeChild(fakeNode);
        assertTrue(!removed, "删除不存在的子节点应返回 false");
        
        // 测试 getChild 使用非法索引
        var child:NAryTreeNode = root.getChild(-1);
        assertTrue(child == null, "getChild(-1) 应返回 null");
        child = root.getChild(100);
        assertTrue(child == null, "getChild(100) 超出范围应返回 null");
    }
    
    /**
     * 测试增强型 addChild 方法：
     * - 重复添加同一子节点
     * - 子节点从旧父节点转移到新父节点
     * - 循环引用检测
     */
    private function testAdvancedAddChild():Void {
        trace("---- testAdvancedAddChild ----");
        var tree:NAryTree = new NAryTree("root");
        var root:NAryTreeNode = tree.getRoot();
        var child:NAryTreeNode = new NAryTreeNode("child");
        
        // 重复添加同一子节点
        root.addChild(child);
        var initialCount:Number = root.getNumberOfChildren();
        root.addChild(child); // 重复添加应被忽略
        assertEqual(root.getNumberOfChildren(), initialCount, "重复添加同一子节点不应增加子节点数量");
        
        // 子节点转移：将 child 从 root 转移到另一个树
        var tree2:NAryTree = new NAryTree("root2");
        var root2:NAryTreeNode = tree2.getRoot();
        root2.addChild(child); // child 原属于 root
        assertEqual(root.getNumberOfChildren(), initialCount - 1, "子节点转移后，原父节点的子节点数量应减少");
        assertEqual(root2.getNumberOfChildren(), 1, "新父节点应包含转移过来的子节点");
        
        // 循环引用检测：构造 A -> B，试图将 A 添加为 B 的子节点应被拒绝
        var nodeA:NAryTreeNode = new NAryTreeNode("A");
        var nodeB:NAryTreeNode = new NAryTreeNode("B");
        nodeA.addChild(nodeB);
        nodeB.addChild(nodeA);
        assertEqual(nodeB.getNumberOfChildren(), 0, "循环引用添加应被拒绝，B 的子节点数量应为0");
    }
    
    /**
     * 测试全局索引：验证节点注册和注销
     */
    private function testGlobalIndex():Void {
        trace("---- testGlobalIndex ----");
        var tree:NAryTree = new NAryTree("root");
        var root:NAryTreeNode = tree.getRoot();
        var child1:NAryTreeNode = new NAryTreeNode("child1");
        var child2:NAryTreeNode = new NAryTreeNode("child2");
        root.addChild(child1);
        root.addChild(child2);
        
        // 验证全局索引中包含根及所有子节点
        assertTrue(tree.nodeMap[root.uid] != undefined, "全局索引应包含根节点");
        assertTrue(tree.nodeMap[child1.uid] != undefined, "全局索引应包含 child1");
        assertTrue(tree.nodeMap[child2.uid] != undefined, "全局索引应包含 child2");
        
        // 删除 child1 后应从全局索引中注销
        root.removeChild(child1);
        assertTrue(tree.nodeMap[child1.uid] == undefined, "删除后全局索引中应注销 child1");
    }
    
    /**
     * 性能测试模块（拓展版）：
     * - 测试不同数据规模（100、1000、10000、100000）的添加、遍历、搜索和删除性能
     *
     * 说明：
     * 1. 添加测试：在根节点下添加大量子节点，评估添加操作性能。
     * 2. 遍历测试：采用前序遍历统计节点数量。
     * 3. 搜索测试：搜索最后一个添加的节点。
     * 4. 删除测试：循环删除根节点下的所有子节点，评估删除操作性能。
     */
    private function testPerformance():Void {
        trace("---- testPerformance ----");

        // 定义不同数据规模
        var dataSizes:Array = [100, 1000, 10000, 100000];

        // 遍历每个数据规模进行性能测试
        for (var j:Number = 0; j < dataSizes.length; j++) {
            var iterations:Number = dataSizes[j];
            var tree:NAryTree = new NAryTree("root");
            var root:NAryTreeNode = tree.getRoot();

            trace("-- 数据规模: " + iterations + " --");

            // 测试添加操作
            var startTime:Number = getTimer();
            for (var i:Number = 0; i < iterations; i++) {
                var node:NAryTreeNode = new NAryTreeNode("node_" + i);
                root.addChild(node);
            }
            var endTime:Number = getTimer();
            trace("添加 " + iterations + " 个子节点耗时: " + (endTime - startTime) + " 毫秒");

            // 测试遍历操作（前序遍历）
            startTime = getTimer();
            var count:Number = 0;
            tree.traverse("pre", function(node:NAryTreeNode):Boolean {
                count++;
                return true;
            });
            endTime = getTimer();
            trace("前序遍历 " + count + " 个节点耗时: " + (endTime - startTime) + " 毫秒");

            // 测试搜索操作：搜索最后添加的节点
            var target:String = "node_" + (iterations - 1);
            var compareFunction:Function = function(data, target):Boolean {
                return (data == target);
            };
            startTime = getTimer();
            var result:NAryTreeNode = tree.search(target, compareFunction);
            endTime = getTimer();
            trace("搜索节点 " + target + " 耗时: " + (endTime - startTime) + " 毫秒");
            assertTrue(result != null, "搜索性能测试中应能找到目标节点");

            // ---------------------------
            // 新增：测试删除操作性能
            // 说明：循环删除根节点下的所有子节点，并统计耗时
            startTime = getTimer();
            while (root.getNumberOfChildren() > 0) {
                // 每次删除第一个子节点
                var childToRemove:NAryTreeNode = root.getChild(0);
                root.removeChild(childToRemove);
            }
            endTime = getTimer();
            trace("删除所有 " + iterations + " 个子节点耗时: " + (endTime - startTime) + " 毫秒");

            trace(""); // 分隔符，便于阅读
        }
    }

    /**
     * 静态入口函数，可直接调用 runTests() 来运行所有测试
     */
    public static function runTests():Void {
        var tester:NAryTreeTest = new NAryTreeTest();
        tester.runAllTests();
    }
}
