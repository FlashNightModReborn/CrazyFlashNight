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
        testEmptyGraph();
        testRemoveEdge();
        testDuplicateEdges();
        testSelfLoop();
        testGetSourceNodes();
        testToString();
        testFindAllPathsComplex();
        testGetNeighborsForNonexistentVertex();
        trace("===== 所有测试完成 =====");
    }
    
    // 辅助方法：查找数组中某项的下标
    private function arrayIndexOf(arr:Array, item:Object):Number {
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] == item) {
                return i;
            }
        }
        return -1;
    }
    
    // 测试添加边时的环检测（合法边与非法边）
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
    
    // 测试拓扑排序，检查排序结果中各顶点的相对顺序
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
        var idxA:Number = arrayIndexOf(sorted, "A");
        var idxB:Number = arrayIndexOf(sorted, "B");
        var idxC:Number = arrayIndexOf(sorted, "C");
        var idxD:Number = arrayIndexOf(sorted, "D");

        this.assert(idxA < idxB, "A应该在B之前");
        this.assert(idxA < idxC, "A应该在C之前");
        this.assert(idxB < idxD, "B应该在D之前");
        this.assert(idxC < idxD, "C应该在D之前");
        
        trace("-- 拓扑排序测试通过 --");
    }
    
    // 测试查找从起点到终点的所有路径
    private function testPathFinding():Void {
        trace("-- 测试路径查找 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        // 构建简单DAG
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
        
        // 验证应存在两条路径：A,B,D,E 与 A,C,D,E
        var foundPath1:Boolean = false;
        var foundPath2:Boolean = false;
        for (var j:Number = 0; j < paths.length; j++) {
            var pathStr:String = paths[j].join(",");
            if (pathStr == "A,B,D,E") foundPath1 = true;
            if (pathStr == "A,C,D,E") foundPath2 = true;
        }
        
        this.assert(paths.length == 2, "应该找到2条路径");
        this.assert(foundPath1 && foundPath2, "路径验证失败");
        
        trace("-- 路径查找测试通过 --");
    }
    
    // 测试空图的各种情况
    private function testEmptyGraph():Void {
        trace("-- 测试空图情况 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        // 空图拓扑排序、获取源节点及toString应返回空结果
        var sorted:Array = dag.topologicalSort();
        this.assert(sorted.length == 0, "空图拓扑排序结果应为空数组");
        
        var sources:Array = dag.getSourceNodes();
        this.assert(sources.length == 0, "空图的源节点应为空数组");
        
        var toStringResult:String = dag.toString();
        this.assert(toStringResult == "", "空图的字符串表示应为空字符串");
        trace("-- 空图测试通过 --");
    }
    
    // 测试移除边的功能
    private function testRemoveEdge():Void {
        trace("-- 测试移除边 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        dag.addEdge("A", "B");
        dag.addEdge("B", "C");
        
        // 移除存在的边 A->B
        var removed:Boolean = dag.removeEdge("A", "B");
        this.assert(removed, "应成功移除A->B的边");
        var neighbors:Array = dag.getNeighbors("A");
        this.assert(arrayIndexOf(neighbors, "B") == -1, "A的邻接表中不应包含B");
        
        // 再次移除 A->B 应返回 false
        removed = dag.removeEdge("A", "B");
        this.assert(!removed, "再次移除A->B应返回false");
        
        trace("-- 移除边测试通过 --");
    }
    
    // 测试添加重复边的情况以及单个重复边的移除
    private function testDuplicateEdges():Void {
        trace("-- 测试重复边添加和移除 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        dag.addEdge("A", "B");
        dag.addEdge("A", "B");
        
        var neighbors:Array = dag.getNeighbors("A");
        this.assert(neighbors.length == 2, "A应有两个到B的边");
        
        // 移除一次，A到B剩下一个
        var removed:Boolean = dag.removeEdge("A", "B");
        this.assert(removed, "第一次移除A->B应成功");
        neighbors = dag.getNeighbors("A");
        this.assert(neighbors.length == 1, "A应只剩下一个到B的边");
        
        // 移除第二次，A到B应不存在
        removed = dag.removeEdge("A", "B");
        this.assert(removed, "第二次移除A->B应成功");
        neighbors = dag.getNeighbors("A");
        this.assert(neighbors.length == 0, "A应无到B的边");
        
        // 再次移除应返回false
        removed = dag.removeEdge("A", "B");
        this.assert(!removed, "第三次移除A->B应失败");
        
        trace("-- 重复边测试通过 --");
    }
    
    // 测试添加自环应抛出异常
    private function testSelfLoop():Void {
        trace("-- 测试自环添加 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        try {
            dag.addEdge("A", "A");
            this.assert(false, "添加自环A->A应抛出错误");
        } catch (e:Error) {
            this.assert(true, "正确捕获自环异常");
        }
        trace("-- 自环测试通过 --");
    }
    
    // 测试获取源节点功能
    private function testGetSourceNodes():Void {
        trace("-- 测试源节点获取 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        
        dag.addEdge("A", "B");
        dag.addVertex("C"); // 孤立顶点
        
        var sources:Array = dag.getSourceNodes();
        // 预期源节点为 A 与 C（B有入度）
        var foundA:Boolean = false;
        var foundC:Boolean = false;
        for (var i:Number = 0; i < sources.length; i++) {
            if (sources[i] == "A") foundA = true;
            if (sources[i] == "C") foundC = true;
        }
        this.assert(foundA, "源节点应包含A");
        this.assert(foundC, "源节点应包含C");
        this.assert(sources.length == 2, "应正好有2个源节点");
        trace("-- 源节点测试通过 --");
    }
    
    // 测试图的字符串表示是否包含所有预期的边信息
    private function testToString():Void {
        trace("-- 测试图的字符串表示 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        dag.addEdge("A", "B");
        dag.addEdge("A", "C");
        dag.addEdge("B", "D");
        
        var str:String = dag.toString();
        trace("toString输出:\n" + str);
        this.assert(str.indexOf("Edge from A to B") != -1, "字符串应包含 'Edge from A to B'");
        this.assert(str.indexOf("Edge from A to C") != -1, "字符串应包含 'Edge from A to C'");
        this.assert(str.indexOf("Edge from B to D") != -1, "字符串应包含 'Edge from B to D'");
        trace("-- 字符串表示测试通过 --");
    }
    
    // 测试一个更复杂的路径查找场景
    private function testFindAllPathsComplex():Void {
        trace("-- 测试复杂路径查找 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        // 构建复杂DAG：
        // A -> B, A -> C, B -> D, C -> D, D -> E, B -> E, C -> F, F -> E
        dag.addEdge("A", "B");
        dag.addEdge("A", "C");
        dag.addEdge("B", "D");
        dag.addEdge("C", "D");
        dag.addEdge("D", "E");
        dag.addEdge("B", "E");
        dag.addEdge("C", "F");
        dag.addEdge("F", "E");
        
        var paths:Array = dag.findAllPaths("A", "E");
        trace("复杂路径找到数: " + paths.length);
        // 预期路径：
        // A,B,D,E
        // A,B,E
        // A,C,D,E
        // A,C,F,E
        var expectedPaths:Array = ["A,B,D,E", "A,B,E", "A,C,D,E", "A,C,F,E"];
        for (var i:Number = 0; i < paths.length; i++) {
            trace("复杂路径 " + (i+1) + ": " + paths[i].join(" -> "));
        }
        this.assert(paths.length == expectedPaths.length, "复杂路径数应为" + expectedPaths.length);
        for (var j:Number = 0; j < expectedPaths.length; j++) {
            var found:Boolean = false;
            for (var k:Number = 0; k < paths.length; k++) {
                if (paths[k].join(",") == expectedPaths[j]) {
                    found = true;
                    break;
                }
            }
            this.assert(found, "应包含路径: " + expectedPaths[j]);
        }
        trace("-- 复杂路径查找测试通过 --");
    }
    
    // 测试对不存在顶点调用 getNeighbors 方法应返回空数组
    private function testGetNeighborsForNonexistentVertex():Void {
        trace("-- 测试获取不存在顶点的邻接表 --");
        var dag:org.flashNight.naki.DataStructures.DAG = new org.flashNight.naki.DataStructures.DAG();
        var neighbors:Array = dag.getNeighbors("NonExistent");
        this.assert(neighbors.length == 0, "不存在顶点的邻接表应为空数组");
        trace("-- 不存在顶点测试通过 --");
    }
}
