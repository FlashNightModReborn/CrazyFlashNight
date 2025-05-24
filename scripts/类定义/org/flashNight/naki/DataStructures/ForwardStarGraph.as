class org.flashNight.naki.DataStructures.ForwardStarGraph {
    private var head:Array;        // 每个顶点的第一条出边的索引
    private var next:Array;        // 每条边的下一条出边的索引
    private var to:Array;          // 每条边的目标顶点
    private var edgeCount:Number;  // 当前边的数量
    private var numVertices:Number; // 顶点数量
    private var isDirected:Boolean; // 是否为有向图

    /**
     * 构造函数，初始化前向星图
     * @param numVertices 顶点的数量
     * @param isDirected 是否为有向图
     */
    public function ForwardStarGraph(numVertices:Number, isDirected:Boolean) {
        this.numVertices = numVertices;
        this.isDirected = isDirected;
        this.head = new Array(numVertices);
        this.next = [];
        this.to = [];
        this.edgeCount = 0;

        // 初始化 head 数组为 -1，表示每个顶点暂时没有出边
        for (var i:Number = 0; i < numVertices; i++) {
            this.head[i] = -1;
        }
    }

    /**
     * 添加边
     * @param u 起点
     * @param v 终点
     */
    public function addEdge(u:Number, v:Number):Void {
        if (u < 0 || u >= this.numVertices || v < 0 || v >= this.numVertices) {
            trace("添加边失败：顶点编号超出范围");
            return;
        }

        // 记录目标顶点
        this.to[this.edgeCount] = v;

        // 将新边插入到顶点 u 的出边链表中
        this.next[this.edgeCount] = this.head[u];
        this.head[u] = this.edgeCount;

        this.edgeCount++;

        // 如果是无向图，则添加反向边
        if (!this.isDirected) {
            this.to[this.edgeCount] = u;
            this.next[this.edgeCount] = this.head[v];
            this.head[v] = this.edgeCount;
            this.edgeCount++;
        }
    }

    /**
     * 移除边
     * @param u 起点
     * @param v 终点
     * @return 如果成功移除，返回 true；否则返回 false
     */
    public function removeEdge(u:Number, v:Number):Boolean {
        var removed:Boolean = false;

        // 移除从 u 到 v 的边
        var prev:Number = -1;
        var current:Number = this.head[u];
        while (current != -1) {
            if (this.to[current] == v) {
                if (prev == -1) {
                    this.head[u] = this.next[current];
                } else {
                    this.next[prev] = this.next[current];
                }
                removed = true;
                break;
            }
            prev = current;
            current = this.next[current];
        }

        // 如果是无向图，则移除从 v 到 u 的边
        if (!this.isDirected && removed) {
            prev = -1;
            current = this.head[v];
            while (current != -1) {
                if (this.to[current] == u) {
                    if (prev == -1) {
                        this.head[v] = this.next[current];
                    } else {
                        this.next[prev] = this.next[current];
                    }
                    break;
                }
                prev = current;
                current = this.next[current];
            }
        }

        return removed;
    }

    /**
     * 获取顶点 u 的所有相邻顶点
     * @param u 顶点编号
     * @return 相邻顶点的数组
     */
    public function getNeighbors(u:Number):Array {
        var neighbors:Array = [];
        if (u < 0 || u >= this.numVertices) {
            trace("获取邻居失败：顶点编号超出范围");
            return neighbors;
        }

        var current:Number = this.head[u];
        while (current != -1) {
            neighbors.push(this.to[current]);
            current = this.next[current];
        }
        return neighbors;
    }

    /**
     * 将图转换为字符串表示
     * @return 图的字符串表示
     */
    public function toString():String {
        var result:String = "";
        for (var u:Number = 0; u < this.numVertices; u++) {
            var neighbors:Array = this.getNeighbors(u);
            for (var i:Number = 0; i < neighbors.length; i++) {
                result += "Edge from " + u + " to " + neighbors[i] + "\n";
            }
        }
        return result;
    }
}
