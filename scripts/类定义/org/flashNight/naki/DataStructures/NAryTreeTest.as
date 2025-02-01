/*---------------------------------------------------------------------------
    文件: org/flashNight/naki/DataStructures/NAryTreeTest.as
    描述: NAryTree 的测试类，包含内置断言系统和性能测试模块
---------------------------------------------------------------------------*/
import org.flashNight.naki.DataStructures.NAryTree;
import org.flashNight.naki.DataStructures.NAryTreeNode;

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
     * @param message 测试描述
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
     * @param actual 实际值
     * @param expected 预期值
     * @param message 测试描述
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
        testSearch();
        testBoundaryConditions();
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
        
        // 遍历测试：计数节点数
        var count:Number = 0;
        tree.traverse(function(node:NAryTreeNode):Void {
            count++;
        });
        assertEqual(count, 5, "遍历应访问5个节点");
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
     * 测试边界条件：例如，向空节点添加子节点、遍历空树等
     */
    private function testBoundaryConditions():Void {
        trace("---- testBoundaryConditions ----");
        // 测试单节点树的遍历和深度计算
        var tree:NAryTree = new NAryTree("onlyRoot");
        var root:NAryTreeNode = tree.getRoot();
        assertTrue(root.isLeaf(), "只有根节点时，根节点应为叶子节点");
        assertEqual(root.getNumberOfChildren(), 0, "只有根节点时，子节点数量应为0");
        
        // 测试删除不存在的子节点
        var fakeNode:NAryTreeNode = new NAryTreeNode("fake");
        var removed:Boolean = root.removeChild(fakeNode);
        assertTrue(!removed, "删除不存在的子节点应返回 false");
    }
    
    /**
     * 性能测试模块：
     * - 构造一个较大规模的树
     * - 测试添加节点、遍历等操作的耗时
     */
    private function testPerformance():Void {
        trace("---- testPerformance ----");
        var iterations:Number = 1000;
        var tree:NAryTree = new NAryTree("root");
        var root:NAryTreeNode = tree.getRoot();
        
        // 测试添加操作
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var node:NAryTreeNode = new NAryTreeNode("node_" + i);
            root.addChild(node);
        }
        var endTime:Number = getTimer();
        trace("添加 " + iterations + " 个子节点耗时: " + (endTime - startTime) + " 毫秒");
        
        // 测试遍历操作
        startTime = getTimer();
        var count:Number = 0;
        tree.traverse(function(node:NAryTreeNode):Void {
            count++;
        });
        endTime = getTimer();
        trace("遍历 " + count + " 个节点耗时: " + (endTime - startTime) + " 毫秒");
        
        // 测试搜索操作
        // 搜索最后添加的节点
        var target:String = "node_" + (iterations - 1);
        var compareFunction:Function = function(data, target):Boolean {
            return (data == target);
        };
        startTime = getTimer();
        var result:NAryTreeNode = tree.search(target, compareFunction);
        endTime = getTimer();
        trace("搜索节点 " + target + " 耗时: " + (endTime - startTime) + " 毫秒");
        assertTrue(result != null, "搜索性能测试中应能找到目标节点");
    }
    
    /**
     * 静态入口函数，可直接调用 runTests() 来运行所有测试
     */
    public static function runTests():Void {
        var tester:NAryTreeTest = new NAryTreeTest();
        tester.runAllTests();
    }
}
