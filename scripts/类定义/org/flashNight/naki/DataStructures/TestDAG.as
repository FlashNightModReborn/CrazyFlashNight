
// 测试类
class org.flashNight.naki.DataStructures.TestDAG {

    public function TestDAG() {
        runTests();
    }
    
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("[Assertion Failed] " + message);
        }
    }
    
    public function runTests():Void {
        trace("===== 测试DAG基础功能 =====");
        testAddEdgeValidation();
        testTopologicalSort();
        testPathFinding();
        trace("===== 所有测试完成 =====");
    }

    private function testAddEdgeValidation():Void {
        trace("-- 测试边添加验证 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        // 构建合法DAG
        dag.addEdge("A", "B");
        dag.addEdge("B", "C");
        dag.addEdge("A", "D");
        
        // 尝试添加环
        try {
            dag.addEdge("C", "A"); // 应该抛出错误
            this.assert(false, "添加C->A应该抛出错误");
        } catch (e:Error) {
            this.assert(true, "正确捕获环异常");
        }
        
        trace("-- 边添加验证测试通过 --");
    }

    private function testTopologicalSort():Void {
        trace("-- 测试拓扑排序 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        // 构建DAG
        dag.addEdge("A", "B");
        dag.addEdge("A", "C");
        dag.addEdge("B", "D");
        dag.addEdge("C", "D");
        
        var sorted:Array = dag.topologicalSort();
        trace("拓扑排序结果: " + sorted.join(" -> "));
        
        // 验证排序顺序
        var idxA:Number = sorted.indexOf("A");
        var idxB:Number = sorted.indexOf("B");
        var idxC:Number = sorted.indexOf("C");
        var idxD:Number = sorted.indexOf("D");
        
        this.assert(idxA < idxB, "A应该在B之前");
        this.assert(idxA < idxC, "A应该在C之前");
        this.assert(idxB < idxD, "B应该在D之前");
        this.assert(idxC < idxD, "C应该在D之前");
        
        trace("-- 拓扑排序测试通过 --");
    }

    private function testPathFinding():Void {
        trace("-- 测试路径查找 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        // 构建DAG
        dag.addEdge("A", "B");
        dag.addEdge("A", "C");
        dag.addEdge("B", "D");
        dag.addEdge("C", "D");
        dag.addEdge("D", "E");
        
        var paths:Array = dag.findAllPaths("A", "E");
        trace("找到路径数: " + paths.length);
        for (var i:Number = 0; i < paths.length; i++) {
            trace("路径 " + (i+1) + ": " + paths[i].join(" -> "));
        }
        
        this.assert(paths.length == 2, "应该找到2条路径");
        this.assert(
            paths.some(function(p:Array):Boolean { return p.join() == "A,B,D,E"; }) &&
            paths.some(function(p:Array):Boolean { return p.join() == "A,C,D,E"; }),
            "路径验证失败"
        );
        
        trace("-- 路径查找测试通过 --");
    }
}