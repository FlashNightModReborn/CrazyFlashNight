// org/flashNight/naki/DataStructures/DisjointSet.as
class org.flashNight.naki.DataStructures.DisjointSet {
    // 记录每个元素的父节点
    private var parent:Array;
    // 记录以该节点为根的树的秩（近似高度）
    private var rank:Array;

    /**
     * 构造函数：创建大小为 n 的并查集
     * @param n 元素个数，编号范围为 [0, n-1]
     */
    public function DisjointSet(n:Number) {
        parent = [];
        rank = [];
        for (var i:Number = 0; i < n; i++) {
            parent[i] = i;
            rank[i] = 0;
        }
    }

    /**
     * 查找 x 的根，通过路径压缩优化
     * @param x 元素编号
     * @return 根节点编号
     */
    public function find(x:Number):Number {
        var root:Number = x;
        // 找到根节点
        while (parent[root] != root) {
            root = parent[root];
        }
        // 路径压缩
        var current:Number = x;
        while (parent[current] != root) {
            var next:Number = parent[current];
            parent[current] = root;
            current = next;
        }
        return root;
    }

    /**
     * 合并 x 和 y 所属的集合，使用按秩合并优化
     * @param x 元素编号
     * @param y 元素编号
     */
    public function union(x:Number, y:Number):Void {
        var rootX:Number = find(x);
        var rootY:Number = find(y);
        if (rootX == rootY) {
            return;
        }
        // 按秩合并
        if (rank[rootX] < rank[rootY]) {
            parent[rootX] = rootY;
        } else if (rank[rootX] > rank[rootY]) {
            parent[rootY] = rootX;
        } else {
            parent[rootY] = rootX;
            rank[rootX]++;
        }
    }

    /**
     * 判断 x 和 y 是否属于同一集合
     * @param x 元素编号
     * @param y 元素编号
     * @return 布尔值，true 表示在同一集合
     */
    public function connected(x:Number, y:Number):Boolean {
        return find(x) == find(y);
    }
}
