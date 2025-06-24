// org/flashNight/naki/DataStructures/DisjointSet.as

/**
 * 并查集（不相交集合）数据结构
 * ================================
 * 
 * 并查集是一种高效的数据结构，用于处理一些不相交集合的合并及查询问题。
 * 主要支持两种操作：
 * 1. Find(查找)：确定元素属于哪个子集
 * 2. Union(合并)：将两个子集合并成同一个集合
 * 
 * 核心特性：
 * - 路径压缩优化：在查找过程中扁平化树结构，提升后续查找效率
 * - 按秩合并优化：合并时将较小的树连接到较大的树上，保持树的平衡
 * - 摊销时间复杂度：接近O(α(n))，其中α是反阿克曼函数，实际应用中近似常数时间
 * 
 * 典型应用场景：
 * - 网络连通性检测
 * - 图的连通分量计算
 * - Kruskal最小生成树算法
 * - 动态连通性问题
 * - 社交网络朋友关系分析
 * - 图像分割和像素聚类
 * 
 * 性能特征：
 * - 空间复杂度：O(n)
 * - Find操作：摊销O(α(n))
 * - Union操作：摊销O(α(n))
 * - Connected操作：摊销O(α(n))
 * 
 * 实现优化：
 * - 采用分层设计：公共API负责参数验证，内部方法专注核心算法
 * - 避免重复验证：内部调用使用未验证版本，减少不必要开销
 * - 两阶段路径压缩：先定位根节点，再执行路径压缩，逻辑清晰
 * 
 * @since ActionScript 2.0
 */
class org.flashNight.naki.DataStructures.DisjointSet {
    
    /**
     * 父节点数组
     * parent[i] 表示元素 i 的父节点索引
     * 当 parent[i] == i 时，元素 i 是其所在集合的根节点
     * @type Array<Number>
     */
    private var parent:Array;
    
    /**
     * 秩数组（树的高度的上界）
     * rank[i] 表示以元素 i 为根的树的秩
     * 用于按秩合并优化，确保较小的树连接到较大的树上
     * 注意：由于路径压缩的存在，rank 只是高度的上界，不是实际高度
     * @type Array<Number>
     */
    private var rank:Array;
    
    /**
     * 并查集的大小（元素总数）
     * 有效的元素索引范围为 [0, _size-1]
     * @type Number
     */
    private var _size:Number;

    /**
     * 构造函数：创建一个包含 n 个元素的并查集
     * 
     * 初始状态下，每个元素都是一个独立的集合：
     * - 每个元素的父节点是自己（parent[i] = i）
     * - 每个元素的秩为 0（rank[i] = 0）
     * 
     * 时间复杂度：O(n)
     * 空间复杂度：O(n)
     * 
     * @param n 并查集中元素的数量，必须为非负整数
     * 
     * @example
     * // 创建包含5个元素的并查集
     * var ds:DisjointSet = new DisjointSet(5);
     * // 此时有5个独立集合：{0}, {1}, {2}, {3}, {4}
     */
    public function DisjointSet(n:Number) {
        this._size = n;
        parent = [];
        rank = [];
        
        // 初始化：每个元素的父节点是自己，秩为0
        for (var i:Number = 0; i < n; i++) {
            parent[i] = i;    // 自己是自己的父节点
            rank[i] = 0;      // 初始秩为0
        }
    }

    /**
     * 私有方法：验证元素索引的有效性
     * 
     * 检查给定的元素索引是否在有效范围内 [0, _size-1]
     * 如果索引无效，抛出详细的错误信息
     * 
     * 这是一个内部安全检查机制，确保所有公共方法的输入都是有效的
     * 
     * @param x 要验证的元素索引
     * @throws Error 当 x < 0 或 x >= _size 时抛出异常
     * 
     * @example
     * // 在大小为5的并查集中
     * validate(0);   // 通过
     * validate(4);   // 通过
     * validate(-1);  // 抛出异常
     * validate(5);   // 抛出异常
     */
    private function validate(x:Number):Void {
        if (x < 0 || x >= this._size) {
            throw new Error("Element index " + x + " is out of bounds for a set of size " + this._size);
        }
    }

    /**
     * 公共方法：查找元素所属集合的根节点
     * 
     * 这是并查集的核心操作之一。返回元素 x 所属集合的代表元素（根节点）。
     * 相同集合中的所有元素都有相同的根节点。
     * 
     * 实现特点：
     * 1. 先进行参数验证，确保输入安全
     * 2. 委托给内部的 _findUnchecked 方法执行核心逻辑
     * 3. 自动应用路径压缩优化
     * 
     * 摊销时间复杂度：O(α(n))，其中 α 是反阿克曼函数
     * 
     * @param x 要查找的元素索引
     * @return 元素 x 所属集合的根节点索引
     * @throws Error 当 x 不在有效范围内时抛出异常
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * trace(ds.find(0)); // 输出: 0 (初始时每个元素的根是自己)
     * 
     * ds.union(0, 1);
     * trace(ds.find(0)); // 输出: 可能是 0 或 1，取决于按秩合并的结果
     * trace(ds.find(1)); // 输出: 与 ds.find(0) 相同
     */
    public function find(x:Number):Number {
        validate(x);
        return _findUnchecked(x);
    }

    /**
     * 私有方法：查找根节点的内部实现（无参数验证）
     * 
     * 这是 find 操作的核心工作方法，假设输入参数已经通过验证。
     * 采用两阶段路径压缩算法：
     * 
     * 阶段1：向上查找根节点
     * - 沿着父节点链向上遍历，直到找到根节点（parent[root] == root）
     * 
     * 阶段2：路径压缩优化
     * - 将查找路径上的所有节点直接连接到根节点
     * - 这样可以显著减少后续查找的路径长度
     * 
     * 路径压缩的重要性：
     * - 将树的高度压缩，使后续操作更快
     * - 是实现接近常数时间复杂度的关键优化
     * - 不会影响集合的逻辑结构，只是物理结构的优化
     * 
     * @param x 要查找的元素索引（假设已验证）
     * @return 元素 x 所属集合的根节点索引
     * 
     * @example
     * // 假设有链式结构：0 -> 1 -> 2 -> 3
     * // _findUnchecked(0) 会：
     * // 1. 找到根节点 3
     * // 2. 将路径压缩为：0 -> 3, 1 -> 3, 2 -> 3
     * // 3. 返回 3
     */
    private function _findUnchecked(x:Number):Number {
        var root:Number = x;
        
        // 阶段1：查找根节点
        // 沿着父节点链向上遍历，直到找到根节点
        while (parent[root] != root) {
            root = parent[root];
        }
        
        // 阶段2：路径压缩
        // 将查找路径上的所有节点直接连接到根节点
        var current:Number = x;
        var next:Number;
        while (parent[current] != root) {
            next = parent[current];             // 保存下一个节点
            parent[current] = root;             // 直接连接到根节点
            current = next;                     // 移动到下一个节点
        }
        
        return root;
    }

    /**
     * 公共方法：合并两个元素所属的集合
     * 
     * 这是并查集的另一个核心操作。将元素 x 和元素 y 所属的集合合并为一个集合。
     * 如果两个元素已经在同一个集合中，则操作无效果。
     * 
     * 实现优化：
     * 1. 参数验证：确保两个元素索引都有效
     * 2. 使用 _findUnchecked 避免重复验证开销
     * 3. 按秩合并：将秩小的树连接到秩大的树上，保持平衡
     * 4. 秩相等时，任选一个作为根，并增加其秩
     * 
     * 按秩合并的重要性：
     * - 防止树退化为链表，保持树的平衡性
     * - 与路径压缩结合，实现接近常数的摊销时间复杂度
     * - 确保操作的高效性，即使在最坏情况下也有良好表现
     * 
     * 摊销时间复杂度：O(α(n))
     * 
     * @param x 第一个元素的索引
     * @param y 第二个元素的索引
     * @throws Error 当 x 或 y 不在有效范围内时抛出异常
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * // 初始：{0}, {1}, {2}, {3}, {4}
     * 
     * ds.union(0, 1);
     * // 现在：{0,1}, {2}, {3}, {4}
     * 
     * ds.union(2, 3);
     * // 现在：{0,1}, {2,3}, {4}
     * 
     * ds.union(1, 2);
     * // 现在：{0,1,2,3}, {4}
     */
    public function union(x:Number, y:Number):Void {
        // 验证输入参数
        validate(x);
        validate(y);
        
        // 使用内部方法查找根节点，避免重复验证
        // 这是一个重要的性能优化点
        var rootX:Number = _findUnchecked(x);
        var rootY:Number = _findUnchecked(y);
        
        // 如果已经在同一个集合中，无需操作
        if (rootX == rootY) {
            return;
        }
        
        // 按秩合并：将秩小的树连接到秩大的树上
        if (rank[rootX] < rank[rootY]) {
            // rootX 的秩小，将 rootX 连接到 rootY
            parent[rootX] = rootY;
        } else if (rank[rootX] > rank[rootY]) {
            // rootY 的秩小，将 rootY 连接到 rootX
            parent[rootY] = rootX;
        } else {
            // 秩相等，任选一个作为根，并增加其秩
            parent[rootY] = rootX;
            rank[rootX]++;  // 增加根节点的秩
        }
    }

    /**
     * 公共方法：检查两个元素是否属于同一个集合
     * 
     * 这是一个便利方法，用于快速判断两个元素是否连通。
     * 实现原理：两个元素属于同一集合当且仅当它们有相同的根节点。
     * 
     * 当前实现说明：
     * - 使用公共的 find 方法，会进行参数验证
     * - 优化为使用 _findUnchecked，因为参数已经验证过
     * 
     * 
     * 摊销时间复杂度：O(α(n))
     * 
     * @param x 第一个元素的索引
     * @param y 第二个元素的索引
     * @return 如果两个元素属于同一集合返回 true，否则返回 false
     * @throws Error 当 x 或 y 不在有效范围内时抛出异常
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * trace(ds.connected(0, 1)); // 输出: false (初始时不连通)
     * 
     * ds.union(0, 1);
     * trace(ds.connected(0, 1)); // 输出: true (合并后连通)
     * trace(ds.connected(0, 2)); // 输出: false (0和2仍不连通)
     * 
     * // 传递性测试
     * ds.union(1, 2);
     * trace(ds.connected(0, 2)); // 输出: true (通过1传递连通)
     */
    public function connected(x:Number, y:Number):Boolean {
        // 验证输入参数
        validate(x);
        validate(y);
        
        // 检查两个元素是否有相同的根节点
        // 由于 x 和 y 已经在上面验证过，可以直接使用未验证版本
        // 这样可以避免 find 方法中的重复验证，提升性能
        return _findUnchecked(x) == _findUnchecked(y);
    }
    
    /**
     * 获取并查集的大小
     * 
     * @return 并查集中元素的总数
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(10);
     * trace(ds.size()); // 输出: 10
     */
    public function size():Number {
        return this._size;
    }
    
    /**
     * 获取当前连通分量的数量
     * 
     * 遍历所有元素，统计有多少个不同的根节点。
     * 每个根节点代表一个连通分量。
     * 
     * 时间复杂度：O(n * α(n))
     * 
     * @return 当前连通分量的数量
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * trace(ds.getComponentCount()); // 输出: 5 (初始时5个独立组件)
     * 
     * ds.union(0, 1);
     * ds.union(2, 3);
     * trace(ds.getComponentCount()); // 输出: 3 ({0,1}, {2,3}, {4})
     */
    public function getComponentCount():Number {
        var roots:Object = {};
        var count:Number = 0;
        
        for (var i:Number = 0; i < this._size; i++) {
            var root:Number = find(i);
            if (!roots[root]) {
                roots[root] = true;
                count++;
            }
        }
        
        return count;
    }
    
    /**
     * 获取指定元素所在连通分量的大小
     * 
     * @param x 要查询的元素索引
     * @return 该元素所在连通分量包含的元素数量
     * @throws Error 当 x 不在有效范围内时抛出异常
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * ds.union(0, 1);
     * ds.union(1, 2);
     * trace(ds.getComponentSize(0)); // 输出: 3 (元素0所在组件包含0,1,2)
     * trace(ds.getComponentSize(3)); // 输出: 1 (元素3独立成组件)
     */
    public function getComponentSize(x:Number):Number {
        validate(x);
        var root:Number = _findUnchecked(x);
        var count:Number = 0;
        
        for (var i:Number = 0; i < this._size; i++) {
            if (_findUnchecked(i) == root) {
                count++;
            }
        }
        
        return count;
    }
    
    /**
     * 重置并查集到初始状态
     * 
     * 将所有元素重新设置为独立的集合，
     * 相当于重新调用构造函数的效果。
     * 
     * 时间复杂度：O(n)
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * ds.union(0, 1);
     * ds.union(2, 3);
     * trace(ds.getComponentCount()); // 输出: 3
     * 
     * ds.reset();
     * trace(ds.getComponentCount()); // 输出: 5 (重置后)
     */
    public function reset():Void {
        for (var i:Number = 0; i < this._size; i++) {
            parent[i] = i;
            rank[i] = 0;
        }
    }
    
    /**
     * 获取并查集的字符串表示
     * 
     * 返回一个易读的字符串，显示当前的连通分量结构。
     * 主要用于调试和测试。
     * 
     * @return 描述当前状态的字符串
     * 
     * @example
     * var ds:DisjointSet = new DisjointSet(5);
     * ds.union(0, 1);
     * ds.union(2, 3);
     * trace(ds.toString());
     * // 可能输出: "DisjointSet[size=5, components=3, structure: {0,1} {2,3} {4}]"
     */
    public function toString():String {
        var components:Object = {};
        
        // 按根节点分组
        for (var i:Number = 0; i < this._size; i++) {
            var root:Number = find(i);
            if (!components[root]) {
                components[root] = [];
            }
            components[root].push(i);
        }
        
        var result:String = "DisjointSet[size=" + this._size + 
                           ", components=" + getComponentCount() + 
                           ", structure: ";
        
        var first:Boolean = true;
        for (var rootKey:String in components) {
            if (!first) result += " ";
            result += "{" + components[rootKey].join(",") + "}";
            first = false;
        }
        
        result += "]";
        return result;
    }
}