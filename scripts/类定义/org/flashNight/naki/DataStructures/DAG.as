import org.flashNight.naki.DataStructures.*;
class org.flashNight.naki.DataStructures.DAG extends AdjacencyListGraph {
    public function DAG() {
        super(true);
    }

    public function addEdge(u:Object, v:Object):Void {
        if (this.existsPath(v, u)) {
            trace("错误：添加边 " + u + " -> " + v + " 会形成环路，操作被拒绝。");
            return;
        }
        super.addEdge(u, v);
    }

    public function existsPath(start:Object, target:Object):Boolean {
        var visited:Object = {};
        return this._dfsExistsPath(String(start), String(target), visited);
    }

    private function _dfsExistsPath(current:String, target:String, visited:Object):Boolean {
        if (current == target) return true;
        visited[current] = true;
        
        var neighbors:Array = this.getNeighbors(current);
        for (var i:Number = 0; i < neighbors.length; i++) {
            var neighbor:String = neighbors[i];
            if (!visited.hasOwnProperty(neighbor)) {
                if (this._dfsExistsPath(neighbor, target, visited)) {
                    return true;
                }
            }
        }
        return false;
    }

    public function topologicalSort():Array {
        var inDegree:Object = {};
        var result:Array = [];
        var queue:Array = [];
        
        for (var key:String in this.adjacencyList) {
            inDegree[key] = 0;
        }
        for (key in this.adjacencyList) {
            var neighbors:Array = this.adjacencyList[key];
            for (var i:Number = 0; i < neighbors.length; i++) {
                var neighbor:String = neighbors[i];
                inDegree[neighbor]++;
            }
        }
        
        for (key in inDegree) {
            if (inDegree[key] == 0) queue.push(key);
        }
        
        while (queue.length > 0) {
            var vertex:String = String(queue.shift());
            result.push(vertex);
            var nbrs:Array = this.adjacencyList[vertex];
            for (var j:Number = 0; j < nbrs.length; j++) {
                var nbr:String = nbrs[j];
                inDegree[nbr]--;
                if (inDegree[nbr] == 0) queue.push(nbr);
            }
        }
        
        var totalVertices:Number = 0;
        for (key in this.adjacencyList) totalVertices++;
        if (result.length != totalVertices) {
            trace("错误：图中存在环，无法进行拓扑排序。");
            return [];
        }
        return result;
    }
}