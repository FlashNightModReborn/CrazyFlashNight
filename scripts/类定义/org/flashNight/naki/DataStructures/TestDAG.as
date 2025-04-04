import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TestDAG {
    
    // 构造函数，自动运行测试
    public function TestDAG() {
        runTests();
    }
    
    // 简单的断言方法，断言失败时输出错误信息
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("Assertion failed: " + message);
        }
    }
    
    // 运行所有测试
    public function runTests():Void {
        trace("===== 运行 DAG 测试套件 =====");
        testAddEdgeCycleDetection();
        testTopologicalSort();
        testExistsPath();
        trace("所有 DAG 测试执行完毕。");
    }
    
    // 测试添加边与环路检测
    private function testAddEdgeCycleDetection():Void {
        trace("--- 测试添加边与环路检测 ---");
        var dag:DAG = new DAG();
        
        // 构建简单 DAG：A->B, B->C, C->D
        dag.addEdge("A", "B");
        dag.addEdge("B", "C");
        dag.addEdge("C", "D");
        
        // 尝试添加边 D->A，此操作会形成环，应被拒绝
        dag.addEdge("D", "A");
        
        // 检查 D 的邻居中不应包含 A
        var neighborsD:Array = dag.getNeighbors("D");
        this.assert(neighborsD.indexOf("A") == -1, "D 的邻居不应包含 A (环路检测失败)");
        trace("--- 添加边与环路检测测试通过 ---");
    }
    
    // 测试拓扑排序
    private function testTopologicalSort():Void {
        trace("--- 测试拓扑排序 ---");
        var dag:DAG = new DAG();
        
        // 构建 DAG：A->B, A->C, B->D, C->D, D->E
        dag.addEdge("A", "B");
        dag.addEdge("A", "C");
        dag.addEdge("B", "D");
        dag.addEdge("C", "D");
        dag.addEdge("D", "E");
        
        var topo:Array = dag.topologicalSort();
        trace("拓扑排序结果: " + topo.join(", "));
        
        // 验证排序顺序：要求 A 在 B 和 C 之前，B 和 C 在 D 之前，D 在 E 之前
        this.assert(checkOrder(topo, "A", "B"), "A 应该在 B 之前");
        this.assert(checkOrder(topo, "A", "C"), "A 应该在 C 之前");
        this.assert(checkOrder(topo, "B", "D"), "B 应该在 D 之前");
        this.assert(checkOrder(topo, "C", "D"), "C 应该在 D 之前");
        this.assert(checkOrder(topo, "D", "E"), "D 应该在 E 之前");
        trace("--- 拓扑排序测试通过 ---");
    }
    
    // 测试 existsPath 方法
    private function testExistsPath():Void {
        trace("--- 测试 existsPath 方法 ---");
        var dag:DAG = new DAG();
        
        // 构建 DAG：A->B, B->C, A->D
        dag.addEdge("A", "B");
        dag.addEdge("B", "C");
        dag.addEdge("A", "D");
        
        this.assert(dag.existsPath("A", "C") == true, "应存在从 A 到 C 的路径");
        this.assert(dag.existsPath("B", "D") == false, "不应存在从 B 到 D 的路径");
        this.assert(dag.existsPath("A", "D") == true, "应存在从 A 到 D 的路径");
        
        // 尝试添加环路边：C->A 应该被拒绝，因此不存在从 C 到 A 的路径
        dag.addEdge("C", "A");
        this.assert(dag.existsPath("C", "A") == false, "C 到 A 不应存在路径（环路添加被拒绝）");
        trace("--- existsPath 测试通过 ---");
    }
    
    /**
     * 检查数组中 first 是否出现在 second 之前
     * @param order 拓扑排序结果数组
     * @param first 第一个顶点
     * @param second 第二个顶点
     * @return 如果 first 在 second 之前返回 true，否则返回 false
     */
    private function checkOrder(order:Array, first:String, second:String):Boolean {
        var indexFirst:Number = indexOf(order, first);
        var indexSecond:Number = indexOf(order, second);
        return (indexFirst != -1 && indexSecond != -1 && indexFirst < indexSecond);
    }
    
    /**
     * 自定义的 indexOf 方法，用于查找数组中元素的位置
     * @param arr 要查找的数组
     * @param item 要查找的元素
     * @return 元素在数组中的索引，如果未找到则返回 -1
     */
    private function indexOf(arr:Array, item:String):Number {
        for (var i:Number = 0; i < arr.length; i++) {
            if(arr[i] == item) {
                return i;
            }
        }
        return -1;
    }
}
