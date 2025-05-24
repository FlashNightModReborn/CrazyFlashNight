class org.flashNight.naki.DataStructures.TestAdjacencyListGraph {

    // 构造函数，自动运行测试
    public function TestAdjacencyListGraph() {
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
        trace("===== 运行基本功能测试 =====");
        testUndirectedGraph();
        testDirectedGraph();
        trace("===== 运行边缘行为测试 =====");
        runEdgeTests();
        trace("===== 运行高级行为测试 =====");
        runAdvancedTests();
        trace("===== 运行性能测试 =====");
        runPerformanceTest();
        trace("所有测试执行完毕。");
    }
    
    // 测试无向图基本功能
    private function testUndirectedGraph():Void {
        trace("--- 测试无向图基本功能 ---");
        var graph:org.flashNight.naki.DataStructures.AdjacencyListGraph = new org.flashNight.naki.DataStructures.AdjacencyListGraph(false);
        
        // 添加顶点 A 和 B
        graph.addVertex("A");
        graph.addVertex("B");
        var neighborsA:Array = graph.getNeighbors("A");
        this.assert(neighborsA.length == 0, "顶点 A 初始应无相邻顶点");
        
        // 添加边 A-B，因无向图添加边会在两个方向添加
        graph.addEdge("A", "B");
        neighborsA = graph.getNeighbors("A");
        var neighborsB:Array = graph.getNeighbors("B");
        this.assert(neighborsA.length == 1 && neighborsA[0] == "B", "A 的相邻顶点中应包含 B");
        this.assert(neighborsB.length == 1 && neighborsB[0] == "A", "B 的相邻顶点中应包含 A");
        
        // 检查 toString 方法输出
        var graphStr:String = graph.toString();
        this.assert(graphStr.indexOf("Edge from A to B") != -1, "toString 输出中应包含 'Edge from A to B'");
        
        // 移除边 A-B
        var removed:Boolean = graph.removeEdge("A", "B");
        this.assert(removed, "边 A->B 应能成功移除");
        neighborsA = graph.getNeighbors("A");
        neighborsB = graph.getNeighbors("B");
        this.assert(neighborsA.length == 0, "移除边后 A 应无相邻顶点");
        this.assert(neighborsB.length == 0, "移除边后 B 应无相邻顶点");
        
        // 尝试移除不存在的边
        removed = graph.removeEdge("A", "C");
        this.assert(!removed, "移除不存在的边应返回 false");
        
        trace("--- 无向图基本功能测试通过 ---");
    }
    
    // 测试有向图功能
    private function testDirectedGraph():Void {
        trace("--- 测试有向图功能 ---");
        var directedGraph:org.flashNight.naki.DataStructures.AdjacencyListGraph = new org.flashNight.naki.DataStructures.AdjacencyListGraph(true);
        directedGraph.addEdge("X", "Y");
        var neighborsX:Array = directedGraph.getNeighbors("X");
        var neighborsY:Array = directedGraph.getNeighbors("Y");
        this.assert(neighborsX.length == 1 && neighborsX[0] == "Y", "在有向图中，X 应有 Y 作为相邻顶点");
        this.assert(neighborsY.length == 0, "在有向图中，Y 不应有 X 作为相邻顶点");
        
        // 测试移除边在有向图中的单向作用
        var removed:Boolean = directedGraph.removeEdge("X", "Y");
        this.assert(removed, "有向图中边 X->Y 应能成功移除");
        neighborsX = directedGraph.getNeighbors("X");
        this.assert(neighborsX.length == 0, "移除边后，X 应无相邻顶点");
        
        trace("--- 有向图功能测试通过 ---");
    }
    
    // 边缘情况测试（数字顶点、自环、重复边、重复添加顶点等）
    private function runEdgeTests():Void {
        trace("--- 开始边缘行为测试 ---");
        var graph:org.flashNight.naki.DataStructures.AdjacencyListGraph = new org.flashNight.naki.DataStructures.AdjacencyListGraph(false);
        
        // 测试数字顶点
        graph.addVertex(1);
        graph.addVertex(2);
        graph.addEdge(1, 2);
        var neighbors1:Array = graph.getNeighbors(1);
        var neighbors2:Array = graph.getNeighbors(2);
        // 数字顶点存储时转换为字符串 "1" 和 "2"
        this.assert(neighbors1.length == 1 && neighbors1[0] == "2", "数字顶点 1 的相邻顶点应为 '2'");
        this.assert(neighbors2.length == 1 && neighbors2[0] == "1", "数字顶点 2 的相邻顶点应为 '1'");
        
        // 测试自环：添加从 1 到 1 的边
        graph.addEdge(1, 1);
        neighbors1 = graph.getNeighbors(1);
        // 自环在无向图中会添加两次
        this.assert(neighbors1.length == 3, "添加自环后，顶点 1 的相邻顶点数应为 3");
        
        // 测试重复边：再次添加边 2->1
        graph.addEdge("2", "1");
        neighbors1 = graph.getNeighbors(1);
        neighbors2 = graph.getNeighbors(2);
        // 预期：顶点 1 的邻接表应包含 ["2", "1", "1", "2"]；顶点 2 应包含 ["1", "1"]
        this.assert(neighbors1.length == 4, "重复边添加后，顶点 1 的相邻顶点数应为 4");
        this.assert(neighbors2.length == 2, "重复边添加后，顶点 2 的相邻顶点数应为 2");
        
        // 测试重复添加顶点（不应影响已有数据）
        graph.addVertex("1");
        neighbors1 = graph.getNeighbors(1);
        this.assert(neighbors1.length == 4, "重复添加顶点 '1' 不应改变其相邻顶点数");
        
        // 测试移除自环：应只移除一次调用 removeEdge 会移除单边记录
        var removed:Boolean = graph.removeEdge(1, 1);
        this.assert(removed, "移除自环边 1->1 应返回 true");
        neighbors1 = graph.getNeighbors(1);
        // 移除自环后，原来自环添加了两条记录，此次调用只移除一条，剩余3条记录
        this.assert(neighbors1.length == 3, "移除一次自环后，顶点 1 的相邻顶点数应减少一条");
        
        // 测试移除不存在的边
        removed = graph.removeEdge("nonexistent", "A");
        this.assert(!removed, "移除不存在的边应返回 false");
        
        trace("--- 边缘行为测试通过 ---");
    }
    
    // 高级行为测试：更多组合情况，严格检测内部状态与输出
    private function runAdvancedTests():Void {
        trace("--- 开始高级行为测试 ---");
        var graph:org.flashNight.naki.DataStructures.AdjacencyListGraph = new org.flashNight.naki.DataStructures.AdjacencyListGraph(false);
        
        // 构建一个复杂图：
        // 顶点: A, B, C, D, E
        // 边：A-B, A-C, B-C, C-D, D-E, E-A（形成一个环），以及重复边 A-B
        var vertices:Array = ["A", "B", "C", "D", "E"];
        for (var i:Number = 0; i < vertices.length; i++) {
            graph.addVertex(vertices[i]);
        }
        graph.addEdge("A", "B");
        graph.addEdge("A", "C");
        graph.addEdge("B", "C");
        graph.addEdge("C", "D");
        graph.addEdge("D", "E");
        graph.addEdge("E", "A");
        graph.addEdge("A", "B"); // 重复边
        
        // 检查各顶点相邻情况
        var nA:Array = graph.getNeighbors("A");
        var nB:Array = graph.getNeighbors("B");
        var nC:Array = graph.getNeighbors("C");
        var nD:Array = graph.getNeighbors("D");
        var nE:Array = graph.getNeighbors("E");
        
        trace("A 的邻居: " + nA.join(", "));
        trace("B 的邻居: " + nB.join(", "));
        trace("C 的邻居: " + nC.join(", "));
        trace("D 的邻居: " + nD.join(", "));
        trace("E 的邻居: " + nE.join(", "));
        
        // 断言：检查是否符合无向图的预期
        this.assert(nA.indexOf("B") != -1, "A 应包含 B");
        this.assert(nA.indexOf("C") != -1, "A 应包含 C");
        this.assert(nA.indexOf("E") != -1, "A 应包含 E");
        this.assert(nB.indexOf("A") != -1, "B 应包含 A");
        this.assert(nB.indexOf("C") != -1, "B 应包含 C");
        this.assert(nC.indexOf("A") != -1, "C 应包含 A");
        this.assert(nC.indexOf("B") != -1, "C 应包含 B");
        this.assert(nC.indexOf("D") != -1, "C 应包含 D");
        this.assert(nD.indexOf("C") != -1, "D 应包含 C");
        this.assert(nD.indexOf("E") != -1, "D 应包含 E");
        this.assert(nE.indexOf("D") != -1, "E 应包含 D");
        this.assert(nE.indexOf("A") != -1, "E 应包含 A");
        
        // 检查 toString 输出，确保所有边都被输出（注意重复边和无向图特性）
        var output:String = graph.toString();
        trace("toString 输出：\n" + output);
        this.assert(output.indexOf("Edge from A to B") != -1, "输出中应包含 'Edge from A to B'");
        this.assert(output.indexOf("Edge from A to C") != -1, "输出中应包含 'Edge from A to C'");
        this.assert(output.indexOf("Edge from B to C") != -1, "输出中应包含 'Edge from B to C'");
        this.assert(output.indexOf("Edge from C to D") != -1, "输出中应包含 'Edge from C to D'");
        this.assert(output.indexOf("Edge from D to E") != -1, "输出中应包含 'Edge from D to E'");
        this.assert(output.indexOf("Edge from E to A") != -1, "输出中应包含 'Edge from E to A'");
        
        trace("--- 高级行为测试通过 ---");
    }
    
    // 性能测试模块：随机添加大量顶点和边，并测量所需时间
    private function runPerformanceTest():Void {
        trace("--- 开始性能测试 ---");
        var graph:org.flashNight.naki.DataStructures.AdjacencyListGraph = new org.flashNight.naki.DataStructures.AdjacencyListGraph(false);
        var startTime:Number = getTimer();
        var numVertices:Number = 1000;
        var numEdges:Number = 5000;
        
        // 预先添加顶点
        for (var i:Number = 0; i < numVertices; i++) {
            graph.addVertex(i);
        }
        
        // 随机添加边
        for (var j:Number = 0; j < numEdges; j++) {
            var u:Number = Math.floor(Math.random() * numVertices);
            var v:Number = Math.floor(Math.random() * numVertices);
            graph.addEdge(u, v);
        }
        
        var elapsed:Number = getTimer() - startTime;
        trace("性能测试：在 " + elapsed + " 毫秒内插入 " + numVertices + " 个顶点和 " + numEdges + " 条边。");
        
        // 根据实际情况设定性能阈值，此处设定 500 毫秒内完成
        this.assert(elapsed < 500, "性能测试耗时过长：" + elapsed + " 毫秒");
        trace("--- 性能测试通过 ---");
    }
}
