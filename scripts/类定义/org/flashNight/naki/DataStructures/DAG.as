// 有向无环图（DAG）实现
class org.flashNight.naki.DataStructures.DAG extends org.flashNight.naki.DataStructures.AdjacencyListGraph {
    
    public function DAG() {
        // 必须强制为有向图
        super(true);
    }

    /**
     * 覆盖添加边方法，添加前进行环检测
     * @throws Error 如果添加边会导致环则抛出异常
     */
    public function addEdge(u:Object, v:Object):Void {
        var keyU:String = String(u);
        var keyV:String = String(v);
        
        // 预检查是否形成环
        if (this.willCreateCycle(keyU, keyV)) {
            throw new Error("添加边 " + keyU + "->" + keyV + " 会导致环");
        }
        
        // 调用父类方法添加边
        super.addEdge(u, v);
    }

    /**
     * 判断添加边是否会创建环（DFS实现）
     */
    private function willCreateCycle(start:String, target:String):Boolean {
        var visited:Object = {};
        var stack:Array = [target]; // 从目标节点开始搜索能否回到起点
        
        while (stack.length > 0) {
            var current:String = String(stack.pop());
            
            if (current == start) {
                return true; // 存在环
            }
            
            if (!visited[current]) {
                visited[current] = true;
                var neighbors:Array = getNeighbors(current);
                // 将未访问的相邻节点加入栈
                for (var i:Number = 0; i < neighbors.length; i++) {
                    var neighbor:String = String(neighbors[i]);
                    if (!visited[neighbor]) {
                        stack.push(neighbor);
                    }
                }
            }
        }
        return false;
    }

    private function getObjectKeys(obj:Object):Array {
        var keys:Array = [];
        for (var key:String in obj) {
            keys.push(key);
        }
        return keys;
    }



    /**
     * 拓扑排序（Kahn算法实现）
     * @return 拓扑排序结果数组，若存在环返回null
     */
    public function topologicalSort():Array {
        var inDegree:Object = {};
        var queue:Array = [];
        var result:Array = [];
        
        // 获取所有顶点键
        var vertices:Array = this.getObjectKeys(adjacencyList);
        var vertexCount:Number = vertices.length;
        
        // 初始化入度表
        for (var i:Number = 0; i < vertexCount; i++) {
            inDegree[vertices[i]] = 0;
        }
        
        // 计算入度
        for (var src:String in adjacencyList) {
            var neighbors:Array = adjacencyList[src];
            for (var j:Number = 0; j < neighbors.length; j++) {
                var dest:String = String(neighbors[j]);
                inDegree[dest]++;
            }
        }
        
        // 入队入度为0的节点
        for (var v:String in inDegree) {
            if (inDegree[v] == 0) {
                queue.push(v);
            }
        }
        
        // 处理队列
        var count:Number = 0;
        while (queue.length > 0) {
            var u:String = String(queue.shift());
            result.push(u);
            
            // 减少相邻节点的入度
            var neighbors:Array = adjacencyList[u];
            for (var k:Number = 0; k < neighbors.length; k++) {
                var neighbor:String = String(neighbors[k]);
                if (--inDegree[neighbor] == 0) {
                    queue.push(neighbor);
                }
            }
            count++;
        }
        
        // 检查是否存在环（比较处理过的节点数和总节点数）
        if (count != vertexCount) {
            return null;
        }
        return result;
    }

    /**
     * 获取所有源节点（入度为0的节点）
     */
    public function getSourceNodes():Array {
        var inDegree:Object = {};
        var vertices:Array = this.getObjectKeys(adjacencyList);
        
        // 初始化入度
        for (var i:Number = 0; i < vertices.length; i++) {
            inDegree[vertices[i]] = 0;
        }
        
        // 计算入度
        for (var src:String in adjacencyList) {
            var neighbors:Array = adjacencyList[src];
            for (var j:Number = 0; j < neighbors.length; j++) {
                var dest:String = String(neighbors[j]);
                inDegree[dest]++;
            }
        }
        
        // 收集入度为0的节点
        var sources:Array = [];
        for (var v:String in inDegree) {
            if (inDegree[v] == 0) {
                sources.push(v);
            }
        }
        return sources;
    }

    /**
     * 寻找所有从u到v的路径（DFS实现）
     */
    public function findAllPaths(u:Object, v:Object):Array {
        var start:String = String(u);
        var end:String = String(v);

        var visited:Object = {};
        var paths:Array = [];
        var currentPath:Array = [];

        // Capture a reference to the DAG instance in a local variable:
        var self:DAG = this;

        function dfs(current:String):Void {
            visited[current] = true;
            currentPath.push(current);

            if (current == end) {
                // We found a path from u to v
                paths.push(currentPath.slice());
            } else {
                // Use self.getNeighbors(...) instead of getNeighbors(...)
                var neighbors:Array = self.getNeighbors(current);
                for (var i:Number = 0; i < neighbors.length; i++) {
                    var neighbor:String = String(neighbors[i]);
                    if (!visited[neighbor]) {
                        dfs(neighbor);
                    }
                }
            }

            // Backtrack
            currentPath.pop();
            visited[current] = false;
        }

        // Kick off DFS
        dfs(start);
        return paths;
    }

}
