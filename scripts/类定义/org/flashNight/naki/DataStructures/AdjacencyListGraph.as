class org.flashNight.naki.DataStructures.AdjacencyListGraph {
    private var adjacencyList:Object; // 存储图的邻接表
    private var isDirected:Boolean;    // 是否为有向图

    /**
     * 构造函数，初始化邻接表图
     * @param isDirected 是否为有向图
     */
    public function AdjacencyListGraph(isDirected:Boolean) {
        this.adjacencyList = {};
        this.isDirected = isDirected;
    }

    private function _addDirectedEdge(u:Object, v:Object):Void {
        var keyU:String = String(u);
        var keyV:String = String(v);

        // ensure the vertices exist
        this.addVertex(keyU);
        this.addVertex(keyV);

        // add the edge
        this.adjacencyList[keyU].push(keyV);

        // if undirected, also add the reverse
        if (!this.isDirected) {
            this.adjacencyList[keyV].push(keyU);
        }
    }

    /**
     * 添加顶点
     * @param vertex 顶点名称（字符串或数字）
     */
    public function addVertex(vertex:Object):Void {
        var key:String = String(vertex);
        if (!this.adjacencyList.hasOwnProperty(key)) {
            this.adjacencyList[key] = [];
        }
    }
    

    /**
     * 添加边
     * @param u 起点
     * @param v 终点
     */
    public function addEdge(u:Object, v:Object):Void {
        var keyU:String = String(u);
        var keyV:String = String(v);

        // 确保两个顶点都存在
        this.addVertex(keyU);
        this.addVertex(keyV);

        // 添加边，存储时使用字符串类型
        this.adjacencyList[keyU].push(keyV);

        // 如果是无向图，则添加反向边
        if (!this.isDirected) {
            this.adjacencyList[keyV].push(keyU);
        }
    }

    /**
     * 移除边
     * @param u 起点
     * @param v 终点
     * @return 如果成功移除，返回 true；否则返回 false
     */
    public function removeEdge(u:Object, v:Object):Boolean {
        var keyU:String = String(u);
        var keyV:String = String(v);
        var removed:Boolean = false;

        // 检查并移除从 u 到 v 的边
        if (this.adjacencyList.hasOwnProperty(keyU)) {
            var index:Number = this.arrayIndexOf(this.adjacencyList[keyU], keyV);
            if (index != -1) {
                this.adjacencyList[keyU].splice(index, 1);
                removed = true;
            }
        }

        // 如果是无向图且 u 和 v 不相同，并且成功移除 u 到 v 的边，则移除 v 到 u 的边
        if (!this.isDirected && removed && keyU != keyV) {
            if (this.adjacencyList.hasOwnProperty(keyV)) {
                var reverseIndex:Number = this.arrayIndexOf(this.adjacencyList[keyV], keyU);
                if (reverseIndex != -1) {
                    this.adjacencyList[keyV].splice(reverseIndex, 1);
                }
            }
        }

        return removed;
    }

    /**
     * 获取顶点的所有相邻顶点
     * @param vertex 顶点名称
     * @return 相邻顶点的数组
     */
    public function getNeighbors(vertex:Object):Array {
        var key:String = String(vertex);
        if (this.adjacencyList.hasOwnProperty(key)) {
            return this.adjacencyList[key];
        }
        return [];
    }

    /**
     * 将图转换为字符串表示
     * @return 图的字符串表示
     */
    public function toString():String {
        var result:String = "";
        for (var key:String in this.adjacencyList) {
            var neighbors:Array = this.adjacencyList[key];
            for (var i:Number = 0; i < neighbors.length; i++) {
                result += "Edge from " + key + " to " + neighbors[i] + "\n";
            }
        }
        return result;
    }

    /**
     * 自定义的 arrayIndexOf 方法，用于在数组中查找元素的位置
     * @param arr 要查找的数组
     * @param item 要查找的元素
     * @return 元素在数组中的索引，如果未找到则返回 -1
     */
    private function arrayIndexOf(arr:Array, item:Object):Number {
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] == item) {
                return i;
            }
        }
        return -1;
    }
}
