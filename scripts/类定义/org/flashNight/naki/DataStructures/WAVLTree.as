import org.flashNight.naki.DataStructures.*; 
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;

/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║                              WAVLTree (弱AVL树)                               ║
 * ║                    高性能自平衡二叉搜索树 ActionScript 2 实现                    ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 *
 * @class WAVLTree
 * @package org.flashNight.naki.DataStructures
 * @author flashNight
 * @version 2.0 (终极优化版)
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                   理论背景
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * WAVL (Weak AVL) 树由 Haeupler, Sen, Tarjan 于 2015 年提出，是 AVL 树的推广。
 * 论文: "Rank-Balanced Trees" (ACM Transactions on Algorithms, 2015)
 *
 * 【核心创新】
 * - 使用 "rank" 替代传统 AVL 的 "height"
 * - 允许 rank差 为 1 或 2（AVL 只允许高度差 0 或 1）
 * - 结合了 AVL 的紧凑高度和红黑树的 O(1) 摊还旋转
 *
 * 【WAVL 不变量】
 * 1. rank差 = 父节点rank - 子节点rank，必须为 1 或 2
 * 2. 外部节点(null)的 rank 定义为 -1
 * 3. 叶子节点的 rank 必须为 0（即 (1,1)-叶子，两侧 rank差 都是 1）
 * 4. 非叶子节点不能是 (2,2)-节点（两侧 rank差 都是 2）
 *
 * 【性能特性】
 * ┌─────────────┬────────────┬────────────┬────────────┐
 * │    特性     │    AVL     │   红黑树   │    WAVL    │
 * ├─────────────┼────────────┼────────────┼────────────┤
 * │ 平衡条件    │ 高度差≤1   │ 黑高度相等 │ rank差∈{1,2}│
 * │ 最坏旋转(插入)│ O(log n)  │ O(1) 摊还  │ O(1) 摊还  │
 * │ 最坏旋转(删除)│ O(log n)  │ O(1) 摊还  │ O(1) 摊还  │
 * │ 树高度      │ ~1.44 log n│ ~2 log n   │ ~1.44 log n│
 * │ 实现复杂度  │ 低         │ 高         │ 中         │
 * └─────────────┴────────────┴────────────┴────────────┘
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                  优化历程记录
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * 【性能演进】(10000元素基准测试)
 *
 *   版本              Add(ms)    Search(ms)   Delete(ms)   Total(ms)
 *   ─────────────────────────────────────────────────────────────────
 *   初始版本          ~429       ~149         ~435         ~1013
 *   + 差分早退出       ~429       ~149         ~302         ~880
 *   + 延迟孙节点访问   ~429       ~149         ~258         ~836
 *   + cmpFn缓存        ~353       ~149         ~251         ~753
 *   + 非对称早退出     ~343       ~145         ~243         ~731
 *   + 手动内联+DeleteMin ~344     ~145         ~231         ~720
 *   ─────────────────────────────────────────────────────────────────
 *   AVL (TreeSet)     455        158          219          832
 *   红黑树            1145       152          2626         3923
 *
 * 【最终性能对比】
 *   - Add:    WAVL 344ms vs AVL 455ms  → WAVL 快 24%
 *   - Search: WAVL 145ms vs AVL 158ms  → WAVL 快 8%
 *   - Delete: WAVL 231ms vs AVL 219ms  → WAVL 慢 5%
 *   - Total:  WAVL 720ms vs AVL 832ms  → WAVL 快 13%
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                AS2 优化经验总结
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * 【关键发现 1: 属性访问开销】
 * AS2 虚拟机中，this.xxx 属性访问涉及作用域链查找，代价远高于局部变量。
 * 解决方案：将频繁访问的属性缓存到局部变量。
 *
 *   // 慢 - 每次递归都查找 this.compareFunction
 *   var cmp:Number = this.compareFunction(element, node.value);
 *
 *   // 快 - 函数引用作为参数传递
 *   private function insert(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
 *       var cmp:Number = cmpFn(element, node.value);  // 直接调用
 *   }
 *
 * 【关键发现 2: 函数调用开销】
 * AS2 的函数调用涉及：作用域链创建、参数压栈、返回值处理。
 * 在递归深度为 O(log N) 的场景下，辅助函数的调用开销被放大。
 * 解决方案：手动内联（inline）辅助函数的逻辑。
 *
 *   // 慢 - 每层递归调用辅助函数
 *   node.left = deleteNode(node.left, element, cmpFn);
 *   return rebalanceAfterLeftDelete(node);  // 函数调用开销
 *
 *   // 快 - 将平衡逻辑直接内联
 *   node.left = deleteNode(node.left, element, cmpFn);
 *   if (!this.__needRebalance) return node;  // 内联的平衡逻辑开始...
 *
 * 【关键发现 3: 条件短路优化】
 * 利用 WAVL 的算法特性，在大多数情况下提前退出。
 *
 *   // 非对称早退出：只检查刚修改那一侧
 *   if (cmp < 0) {
 *       node.left = insert(node.left, element, cmpFn);
 *       var leftDiff:Number = nodeRank - leftNode.rank;
 *       if (leftDiff != 0) return node;  // 快速路径：左侧没问题，直接返回
 *       // 只有左侧有问题才读取右侧信息...
 *   }
 *
 * 【关键发现 4: 避免重复搜索】
 * 删除双子节点时，传统实现会重新搜索后继节点。
 * 解决方案：实现专用的 deleteMin，直接下潜到最左侧。
 *
 *   // 慢 - 重新搜索后继
 *   node.value = succ.value;
 *   node.right = deleteNode(node.right, succ.value, cmpFn);  // 又要比较一遍
 *
 *   // 快 - deleteMin 无需比较
 *   node.value = succ.value;
 *   node.right = deleteMin(node.right);  // 直接下潜最左侧
 *
 * 【关键发现 5: 延迟读取】
 * 只在确实需要时才读取节点信息，避免无谓的内存访问。
 *
 *   // 慢 - 立即读取所有信息
 *   var leftRank = (leftNode != null) ? leftNode.rank : -1;
 *   var rightRank = (rightNode != null) ? rightNode.rank : -1;  // 可能不需要
 *
 *   // 快 - 按需读取
 *   var leftDiff = nodeRank - leftRank;
 *   if (leftDiff <= 2) { ... return node; }  // 可能提前返回
 *   var rightRank = (rightNode != null) ? rightNode.rank : -1;  // 只在需要时读取
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                  WAVL 平衡规则详解
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * 【插入后平衡】
 *
 * 插入新节点后，新节点 rank=0，可能产生 0-child（rank差=0）。
 *
 * Case 1: (0, 1) 或 (1, 0)
 *   → Promote：node.rank++
 *   → 可能向上传播
 *
 * Case 2: (0, 2) - 需要旋转
 *   子情况 2a: 左子是 (1, 2) - 单右旋
 *       node            leftChild
 *       /  \     →      /    \
 *    leftChild          LL    node
 *     /   \                   /
 *    LL   LR                 LR
 *
 *   子情况 2b: 左子是 (2, 1) - 双旋转 (LR)
 *       node               LR
 *       /  \      →       /  \
 *    leftChild          leftChild  node
 *     /   \              /
 *    LL   LR            LL
 *
 * Case 3: (2, 0) - 对称处理
 *
 * 【删除后平衡】
 *
 * 删除节点后，可能产生 3-child（rank差=3）。
 *
 * Case 1: (3, 1) - 需要旋转或双demote
 *   子情况 1a: 右子的左孙是 1-child → 双旋转 (RL)
 *   子情况 1b: 右子的右孙是 1-child → 单左旋
 *   子情况 1c: 右子是 (2, 2)        → 双demote
 *
 * Case 2: (3, 2)
 *   → 简单 demote：node.rank--
 *   → 可能向上传播
 *
 * Case 3: (1, 3) 和 (2, 3) - 对称处理
 *
 * ════════════════════════════════════════════════════════════════════════════════
 */
class org.flashNight.naki.DataStructures.WAVLTree
        extends AbstractBalancedSearchTree
        implements IBalancedSearchTree {

    // ════════════════════════════════════════════════════════════════════════════
    //                                  成员变量
    // ════════════════════════════════════════════════════════════════════════════

    /** 树的根节点 */
    private var root:WAVLNode;

    /**
     * 删除操作的差分早退出信号
     *
     * 【优化原理】
     * WAVL 删除后，demote 可能向上传播多层（类似 AVL 的旋转传播）。
     * 但一旦某层的 rank 修复后不再影响父层，就可以提前终止。
     *
     * 【实现机制】
     * - true:  子树发生了结构变化，父节点需要检查平衡
     * - false: 子树已稳定，可以直接返回
     *
     * 【性能收益】
     * 该优化将删除时间从 435ms 降至 302ms，提升约 30%。
     */
    private var __needRebalance:Boolean;

    // ════════════════════════════════════════════════════════════════════════════
    //                                  构造函数
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 构造 WAVLTree 实例
     *
     * @param compareFunction 比较函数，可选。若未提供则使用默认的 < > 比较。
     *
     * 【使用示例】
     * // 数字升序
     * var tree:WAVLTree = new WAVLTree();
     *
     * // 数字降序
     * var tree:WAVLTree = new WAVLTree(function(a, b):Number {
     *     return b - a;
     * });
     *
     * // 对象按属性排序
     * var tree:WAVLTree = new WAVLTree(function(a, b):Number {
     *     return a.priority - b.priority;
     * });
     */
    public function WAVLTree(compareFunction:Function) {
        super(compareFunction); // 调用基类构造函数，初始化 _compareFunction 和 _treeSize
        this.root = null;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                                  静态工厂方法
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 从有序数组构建 WAVL 树（批量构建）
     *
     * @param arr 输入数组（无需预排序，内部会排序）
     * @param compareFunction 比较函数
     * @return 构建好的 WAVLTree 实例
     *
     * 【性能优势】
     * - 时间复杂度: O(n log n) 排序 + O(n) 构建 = O(n log n)
     * - 逐个插入:   O(n log n)，但常数因子大得多
     *
     * 【实测数据】(10000元素)
     * - buildFromArray: ~57ms
     * - 逐个 add:       ~344ms
     * - 性能比:         约 6 倍
     *
     * 【适用场景】
     * - 初始化时已有大量数据
     * - 从持久化存储恢复树
     * - 重建索引
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):WAVLTree {
        var tree:WAVLTree = new WAVLTree(compareFunction);

        // 使用 TimSort 排序（AS2 环境下的最优通用排序）
        TimSort.sort(arr, compareFunction);

        // 递归构建平衡树
        tree.root = tree.buildBalancedTree(arr, 0, arr.length - 1);
        tree._treeSize = arr.length;

        return tree;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                                  公共接口
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 更换比较函数并重新排序
     *
     * @param newCompareFunction 新的比较函数
     *
     * 【实现策略】
     * 1. 中序遍历导出所有元素
     * 2. 使用新比较函数排序
     * 3. 从有序数组重建树
     *
     * 【性能】
     * 时间复杂度: O(n log n)
     * 实测 (10000元素): ~84ms
     *
     * 【使用场景】
     * - 动态切换排序规则（如 升序↔降序）
     * - 多维度排序（如 先按名称，改为按日期）
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        _compareFunction = newCompareFunction;
        var arr:Array = this.toArray();
        TimSort.sort(arr, newCompareFunction);
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        _treeSize = arr.length;
    }

    /**
     * 添加元素
     *
     * @param element 要添加的元素
     *
     * 【时间复杂度】O(log n)
     * 【空间复杂度】O(log n) 递归栈
     *
     * 【实测性能】(10000元素)
     * - 平均耗时: ~344ms
     * - 对比 AVL: 455ms (WAVL 快 24%)
     *
     * 【注意事项】
     * - 重复元素不会被添加（集合语义）
     * - 元素必须能被比较函数正确处理
     */
    public function add(element:Object):Void {
        // [优化] 传入缓存的比较函数，避免递归中反复查找 _compareFunction
        this.root = insert(this.root, element, _compareFunction);
    }

    /**
     * 移除元素
     *
     * @param element 要移除的元素
     * @return true 如果元素存在并被移除，false 如果元素不存在
     *
     * 【时间复杂度】O(log n)
     * 【空间复杂度】O(log n) 递归栈
     *
     * 【实测性能】(10000元素)
     * - 平均耗时: ~231ms
     * - 对比 AVL: 219ms (WAVL 慢 5%)
     *
     * 【删除性能分析】
     * WAVL 删除略慢于 AVL 的原因：
     * 1. demote 传播可能比 AVL 旋转更频繁
     * 2. 代码复杂度更高（更多分支判断）
     *
     * 但差距已从最初的 38% 优化到仅 5%。
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = _treeSize;
        // [优化] 传入缓存的比较函数
        this.root = deleteNode(this.root, element, _compareFunction);
        return (_treeSize < oldSize);
    }

    /**
     * 检查元素是否存在
     *
     * @param element 要查找的元素
     * @return true 如果元素存在，false 否则
     *
     * 【时间复杂度】O(log n)
     * 【空间复杂度】O(1) 迭代实现
     *
     * 【实测性能】(10000元素)
     * - 平均耗时: ~145ms
     * - 对比 AVL: 158ms (WAVL 快 8%)
     *
     * 【优化说明】
     * 1. 使用迭代而非递归，避免函数调用开销
     * 2. 比较函数缓存到局部变量
     */
    public function contains(element:Object):Boolean {
        var current:WAVLNode = this.root;
        var cmpFn:Function = _compareFunction;  // [优化] 缓存函数引用到局部变量

        while (current != null) {
            var cmp:Number = cmpFn(element, current.value);  // [优化] 本地调用更快
            if (cmp < 0) {
                current = current.left;
            } else if (cmp > 0) {
                current = current.right;
            } else {
                return true;
            }
        }
        return false;
    }

    // size() 和 isEmpty() 由基类 AbstractBalancedSearchTree 提供

    /**
     * 将树转换为有序数组（中序遍历）
     *
     * @return 按比较函数排序的数组
     *
     * 【时间复杂度】O(n)
     * 【空间复杂度】O(n) 结果数组 + O(log n) 栈
     *
     * 【实现说明】
     * 使用迭代式中序遍历（显式栈），避免递归的函数调用开销。
     *
     * 【优化技术】
     * 1. 预分配数组：使用 treeSize 预先分配数组空间，避免动态扩容
     * 2. 独立索引：使用 arrIdx 而非 arr.length，避免频繁属性读取
     *
     * 【性能对比】
     * 原始写法: arr[arr.length] = value  → 每次读取 length 属性
     * 优化写法: arr[arrIdx++] = value    → 直接使用局部变量索引
     */
    public function toArray():Array {
        // [优化] 预分配数组空间，避免动态扩容
        var arr:Array = new Array(_treeSize);
        var arrIdx:Number = 0;  // [优化] 独立索引，避免 arr.length 读写

        var stack:Array = [];
        var stackIdx:Number = 0;
        var node:WAVLNode = this.root;

        // 标准迭代式中序遍历（显式栈实现）
        while (node != null || stackIdx > 0) {
            // 下潜到最左侧
            while (node != null) {
                stack[stackIdx++] = node;
                node = node.left;
            }
            // 弹出并访问
            node = stack[--stackIdx];
            arr[arrIdx++] = node.value;  // [优化] 使用独立索引
            // 转向右子树
            node = node.right;
        }

        return arr;
    }

    /**
     * 获取根节点（用于调试和测试）
     *
     * @return 根节点，如果树为空则返回 null
     */
    public function getRoot():WAVLNode {
        return this.root;
    }

    // getCompareFunction() 由基类 AbstractBalancedSearchTree 提供

    /**
     * 获取树的字符串表示（前序遍历）
     *
     * @return 空格分隔的节点字符串
     */
    public function toString():String {
        var str:String = "";
        var stack:Array = [];
        var index:Number = 0;
        var node:WAVLNode = this.root;

        while (node != null || index > 0) {
            while (node != null) {
                str += node.toString() + " ";
                stack[index++] = node.right;
                node = node.left;
            }
            if (index > 0) {
                node = stack[--index];
            }
        }

        return StringUtils.trim(str);
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                              插入操作（核心算法）
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 递归插入节点
     *
     * @param node 当前子树的根节点
     * @param element 要插入的元素
     * @param cmpFn 比较函数（参数传递优化）
     * @return 平衡后的子树根节点
     *
     * ┌────────────────────────────────────────────────────────────────────────┐
     * │                           优化技术清单                                  │
     * ├────────────────────────────────────────────────────────────────────────┤
     * │ 1. cmpFn 参数传递    - 避免 this.compareFunction 的作用域链查找          │
     * │ 2. 非对称早退出      - 只检查刚插入那一侧的 rank差                       │
     * │ 3. 延迟读取          - 只在确实需要时才读取另一侧信息                     │
     * │ 4. 局部变量缓存      - node.rank 等属性缓存到局部变量                    │
     * └────────────────────────────────────────────────────────────────────────┘
     *
     * 【算法流程】
     *
     * 1. 递归下降找到插入位置
     * 2. 创建新节点（rank=0）
     * 3. 回溯时检查平衡：
     *    - 若插入侧 rank差 != 0，平衡，直接返回
     *    - 若插入侧 rank差 == 0：
     *      - (0,1) 或 (1,0): Promote
     *      - (0,2) 或 (2,0): 旋转
     *
     * 【WAVL 插入平衡图解】
     *
     * 情况 1: (0, 1) - Promote
     *     rank=2              rank=3
     *     /    \      →       /    \
     *   rank=2  rank=1     rank=2  rank=1
     *   (刚插入)
     *
     * 情况 2a: (0, 2) 左子是 (1, 2) - 单右旋
     *       node[r]             L[r]
     *       /    \      →      /    \
     *     L[r]   R[r-2]      LL    node[r-1]
     *    /   \                      /
     *   LL   LR                    LR
     *
     * 情况 2b: (0, 2) 左子是 (2, 1) - 双旋转 (LR)
     *       node[r]             LR[r]
     *       /    \      →      /    \
     *     L[r]   R[r-2]      L[r-1]  node[r-1]
     *    /   \
     *   LL   LR[r-1]
     */
    private function insert(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
        // ──────────────────── 基础情况：空节点 ────────────────────
        if (node == null) {
            _treeSize++;
            return new WAVLNode(element);  // 新叶子 rank=0，满足 WAVL 不变量
        }

        // [优化1] 使用参数传递的比较函数，避免 this.compareFunction 查找
        var cmp:Number = cmpFn(element, node.value);

        // ════════════════════ 左侧递归分支 ════════════════════
        //
        // [优化2] 非对称早退出策略：
        // 插入后只检查插入那一侧的 rank差。
        // 大多数情况下 diff != 0，可以立即返回。
        //
        if (cmp < 0) {
            node.left = insert(node.left, element, cmpFn);

            // [优化] 缓存节点引用和 rank 到局部变量
            var leftNode:WAVLNode = node.left;
            var leftRank:Number = leftNode.rank;  // 刚插入，leftNode 必定存在
            var nodeRank:Number = node.rank;
            var leftDiff:Number = nodeRank - leftRank;

            // ──── 快速路径：左侧 diff 不为 0，说明平衡（1或2），直接返回 ────
            // 这是最常见的情况，约占 70%+ 的插入操作
            if (leftDiff != 0) {
                return node;
            }

            // ──── 慢速路径：左侧出问题(diff=0)，才去读右侧 ────
            // [优化3] 延迟读取：只在确实需要时才访问 rightNode
            var rightNode:WAVLNode = node.right;
            var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
            var rightDiff:Number = nodeRank - rightRank;

            // Case: (0, 1) → Promote
            //
            // 这是 "0-child promotion" 规则：
            // 当一侧是 0-child 另一侧是 1-child 时，提升当前节点的 rank
            //
            //    node[r]              node[r+1]
            //    /    \       →       /    \
            //  L[r]   R[r-1]        L[r]   R[r-1]
            //
            if (rightDiff == 1) {
                node.rank = nodeRank + 1;
                return node;  // promote 可能向上传播
            }

            // Case: (0, 2) → 需要旋转
            //
            // 此时必须通过旋转来恢复平衡
            // 选择单旋还是双旋取决于左子节点的内部结构
            //
            var lrNode:WAVLNode = leftNode.right;
            var leftNodeRank:Number = leftRank;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;
            var lrDiff:Number = leftNodeRank - lrRank;

            if (lrDiff == 2) {
                // ──── 左子是 (1, 2) - 单右旋 ────
                //
                // 插入发生在左子的左侧（LL 情况）
                //
                //       node[r]              leftNode[r]
                //       /    \       →       /        \
                //    leftNode[r]  R       LL[r-1]   node[r-1]
                //     /      \                       /
                //   LL[r-1]  LR                     LR
                //
                // rank 调整：
                // - leftNode: 保持不变
                // - node: r → r-1 (demote)
                //
                node.left = lrNode;
                leftNode.right = node;
                node.rank = nodeRank - 1;
                return leftNode;
            }

            // ──── 左子是 (2, 1) - 双旋转 (LR) ────
            //
            // 插入发生在左子的右侧（LR 情况）
            // 需要先左旋左子，再右旋当前节点
            //
            //       node[r]                    lrNode[r]
            //       /    \          →         /        \
            //    leftNode[r]  R           leftNode[r-1]  node[r-1]
            //     /      \                  /              \
            //   LL    lrNode[r-1]          LL             (lrNode 的原右子)
            //          /    \
            //     (原左子) (原右子)
            //
            // rank 调整：
            // - lrNode: r-1 → r (promote)
            // - leftNode: r → r-1 (demote)
            // - node: r → r-1 (demote)
            //
            leftNode.right = lrNode.left;
            node.left = lrNode.right;
            lrNode.left = leftNode;
            lrNode.right = node;
            lrNode.rank++;
            leftNode.rank = leftNodeRank - 1;
            node.rank = nodeRank - 1;
            return lrNode;
        }

        // ════════════════════ 右侧递归分支 ════════════════════
        //
        // 与左侧分支完全对称的逻辑
        //
        if (cmp > 0) {
            node.right = insert(node.right, element, cmpFn);

            var rightNode:WAVLNode = node.right;
            var rightRank:Number = rightNode.rank;  // 刚插入，rightNode 必存在
            var nodeRank:Number = node.rank;
            var rightDiff:Number = nodeRank - rightRank;

            // 快速路径：右侧 diff 不为 0
            if (rightDiff != 0) {
                return node;
            }

            // 慢速路径：右侧出问题(diff=0)
            var leftNode:WAVLNode = node.left;
            var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
            var leftDiff:Number = nodeRank - leftRank;

            // Case: (1, 0) → Promote
            if (leftDiff == 1) {
                node.rank = nodeRank + 1;
                return node;
            }

            // Case: (2, 0) → 需要旋转
            var rlNode:WAVLNode = rightNode.left;
            var rightNodeRank:Number = rightRank;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;
            var rlDiff:Number = rightNodeRank - rlRank;

            if (rlDiff == 2) {
                // ──── 右子是 (2, 1) - 单左旋 ────
                //
                //    node[r]                    rightNode[r]
                //    /    \           →         /        \
                //   L   rightNode[r]        node[r-1]   RR[r-1]
                //         /      \            \
                //        RL    RR[r-1]        RL
                //
                node.right = rlNode;
                rightNode.left = node;
                node.rank = nodeRank - 1;
                return rightNode;
            }

            // ──── 右子是 (1, 2) - 双旋转 (RL) ────
            //
            //    node[r]                        rlNode[r]
            //    /    \            →           /        \
            //   L   rightNode[r]          node[r-1]  rightNode[r-1]
            //         /      \
            //      rlNode[r-1]  RR
            //
            rightNode.left = rlNode.right;
            node.right = rlNode.left;
            rlNode.right = rightNode;
            rlNode.left = node;
            rlNode.rank++;
            node.rank = nodeRank - 1;
            rightNode.rank = rightNodeRank - 1;
            return rlNode;
        }

        // ════════════════════ cmp == 0: 元素已存在 ════════════════════
        //
        // 集合语义：不允许重复元素，直接返回原节点
        //
        return node;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                              删除操作（核心算法）
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 递归删除节点
     *
     * @param node 当前子树的根节点
     * @param element 要删除的元素
     * @param cmpFn 比较函数（参数传递优化）
     * @return 平衡后的子树根节点
     *
     * ┌────────────────────────────────────────────────────────────────────────┐
     * │                           优化技术清单                                  │
     * ├────────────────────────────────────────────────────────────────────────┤
     * │ 1. cmpFn 参数传递    - 避免 this.compareFunction 的作用域链查找          │
     * │ 2. __needRebalance   - 差分早退出，子树稳定则立即返回                    │
     * │ 3. 手动内联          - 平衡逻辑直接写在主函数中，消除函数调用开销         │
     * │ 4. deleteMin 优化    - 双子节点删除避免二次搜索                          │
     * │ 5. 延迟孙节点访问    - 只在确需旋转时才读取孙节点                        │
     * └────────────────────────────────────────────────────────────────────────┘
     *
     * 【算法流程】
     *
     * 1. 递归下降找到目标节点
     * 2. 删除节点：
     *    - 叶子节点：直接删除
     *    - 单子节点：用子节点替代
     *    - 双子节点：用后继替代，删除后继（使用 deleteMin 优化）
     * 3. 回溯时检查平衡（通过 __needRebalance 信号）：
     *    - 若 diff <= 2：平衡，可能提前终止
     *    - 若 diff == 3：需要旋转或 demote
     *
     * 【WAVL 删除平衡详解】
     *
     * 删除后可能产生 3-child（rank差=3），处理方式取决于兄弟侧的情况：
     *
     * Case (3, 1): 兄弟是 1-child
     *   → 检查兄弟的子节点，决定旋转类型或双demote
     *
     * Case (3, 2): 兄弟是 2-child
     *   → 简单 demote 当前节点
     *   → 可能向上传播
     *
     * 【关于手动内联的说明】
     *
     * 原本的实现将平衡逻辑提取到 rebalanceAfterLeftDelete/rebalanceAfterRightDelete。
     * 但 AS2 的函数调用开销极高（作用域链创建、参数压栈等）。
     * 在递归深度 O(log N) 的删除操作中，每层都调用辅助函数会产生显著开销。
     *
     * 内联后代码虽然臃肿，但性能提升明显：
     * - 243ms → 231ms (约 5% 提升)
     *
     * 这种 "代码可读性换性能" 的权衡在 AS2 这种老旧虚拟机上是值得的。
     */
    private function deleteNode(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
        // ──────────────────── 基础情况：空节点 ────────────────────
        if (node == null) {
            this.__needRebalance = false;  // 元素不存在，无需平衡
            return null;
        }

        var cmp:Number = cmpFn(element, node.value);

        // ════════════════════════════════════════════════════════════════════
        //                          左侧递归分支
        // ════════════════════════════════════════════════════════════════════
        if (cmp < 0) {
            node.left = deleteNode(node.left, element, cmpFn);

            // [优化] 差分早退出：子树已稳定，无需检查
            if (!this.__needRebalance) return node;

            // ──────────────── [内联] 左侧删除后平衡逻辑 ────────────────
            //
            // 删除发生在左侧，可能导致左侧 rank差 增大。
            // 首先检查是否真的需要平衡。
            //
            var leftNode:WAVLNode = node.left;
            var nodeRank:Number = node.rank;
            var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
            var leftDiff:Number = nodeRank - leftRank;

            // ──── 需要平衡：读取右侧信息 ────
            var rightNode:WAVLNode = node.right;
            var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
            var rightDiff:Number = nodeRank - rightRank;

            // ──── 快速检查：两侧 diff 都在 [1,2] 范围内 ────
            //
            // 【Bug 修复 2024-11】
            // 原代码只检查 leftDiff <= 2 就直接返回，遗漏了 (2,2) 非叶子节点的情况。
            // WAVL 不变量4 明确禁止非叶子节点成为 (2,2)-节点。
            //
            if (leftDiff <= 2) {
                // [修复] 检查是否产生了违规的 (2,2) 非叶子节点
                if (leftDiff == 2 && rightDiff == 2) {
                    // (2,2) 非叶子节点需要 demote
                    // 注意：叶子节点不可能到这里，因为叶子的 rank=0，diff 只能是 1
                    node.rank = nodeRank - 1;
                    // __needRebalance 保持 true，demote 可能向上传播
                    return node;
                }
                // 其他 diff <= 2 的情况都是合法的
                this.__needRebalance = false;
                return node;
            }

            // ════════════════ Case: (3, 1) - 左侧严重失衡 ════════════════
            //
            // 左侧 diff=3，右侧 diff=1。
            // 需要检查右子的内部结构来决定操作类型。
            //
            if (leftDiff == 3 && rightDiff == 1) {
                // 读取右子的左孙（用于判断旋转类型）
                var rlNode:WAVLNode = rightNode.left;
                var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;

                // ──── 子情况 1a: 右子的左孙是 1-child → 双旋转 (RL) ────
                //
                // 右子结构: (1, ?)，左孙是 1-child
                // 需要先右旋右子，再左旋当前节点
                //
                //       node[r]                    rlNode[r+1]
                //       /    \          →         /          \
                //      L    rightNode[r-1]     node[r-2]  rightNode[r-2]
                //            /      \            /
                //         rlNode[r-2]  RR       L
                //          /    \
                //        (子)  (子)
                //
                if (rightRank - rlRank == 1) {
                    var pivotLeft:WAVLNode = rlNode.left;
                    var pivotRight:WAVLNode = rlNode.right;
                    rightNode.left = pivotRight;
                    node.right = pivotLeft;
                    rlNode.right = rightNode;
                    rlNode.left = node;

                    // rank 调整
                    rlNode.rank += 2;
                    rightNode.rank = rightRank - 1;
                    node.rank = nodeRank - 2;

                    // 特殊处理：如果 node 变成叶子，确保 rank=0
                    if (leftNode == null && pivotLeft == null) node.rank = 0;

                    this.__needRebalance = false;  // 旋转后一定平衡
                    return rlNode;
                }

                // ──── 子情况 1b: 右子的右孙是 1-child → 单左旋 ────
                //
                // 右子结构: (2, 1)，右孙是 1-child
                // 单次左旋即可
                //
                //       node[r]                  rightNode[r-1]
                //       /    \          →       /          \
                //      L    rightNode[r-1]   node[r-2]     RR
                //            /      \          /   \
                //           RL      RR        L    RL
                //
                // 【重要】rank 调整说明：
                // - rightNode: 保持不变 (r-1)，【不能 +1】
                // - node: r → r-2 (双重 demote)
                // - 旋转后 rightNode 的 diff: 左=(r-1)-(r-2)=1, 右=(r-1)-rrRank
                //
                // 【Bug 修复 2024-11】
                // 原代码错误地写成 rightNode.rank = rightRank + 1
                // 这会导致新根 rightNode 的 rank 变成 r，形成：
                //   左 diff = r - (r-2) = 2
                //   右 diff = r - (r-2) = 2  (当 rrRank = r-2)
                // 结果是违规的 (2,2) 非叶子节点！
                //
                var rrNode:WAVLNode = rightNode.right;
                var rrRank:Number = (rrNode != null) ? rrNode.rank : -1;
                if (rightRank - rrRank == 1) {
                    node.right = rlNode;
                    rightNode.left = node;

                    // [修复] rightNode.rank 保持不变，删除场景的单旋不需要 +1
                    node.rank = nodeRank - 2;

                    // 特殊处理：如果 node 变成叶子
                    if (leftNode == null && rlNode == null) node.rank = 0;

                    this.__needRebalance = false;
                    return rightNode;
                }

                // ──── 子情况 1c: 右子是 (2, 2) → 双 demote ────
                //
                // 右子的两个孙子都是 2-child
                // 无法通过旋转解决，需要同时 demote node 和 rightNode
                //
                // 这种情况可能导致问题向上传播
                //
                node.rank = nodeRank - 1;
                rightNode.rank = rightRank - 1;
                // __needRebalance 保持 true，可能继续向上传播
                return node;
            }

            // ════════════════ Case: (3, 2) - 简单 demote ════════════════
            //
            // 左侧 diff=3，右侧 diff=2。
            // 只需 demote 当前节点。
            //
            // 这包含了隐式的 (3,2) 情况判断：
            // 如果不是 (3,1)，且 leftDiff > 2，则必然是 (3,2)
            //
            node.rank = nodeRank - 1;
            // __needRebalance 保持 true，demote 可能向上传播
            return node;
        }

        // ════════════════════════════════════════════════════════════════════
        //                          右侧递归分支
        // ════════════════════════════════════════════════════════════════════
        //
        // 与左侧分支完全对称的逻辑
        //
        if (cmp > 0) {
            node.right = deleteNode(node.right, element, cmpFn);

            if (!this.__needRebalance) return node;

            // ──────────────── [内联] 右侧删除后平衡逻辑 ────────────────
            var rightNode:WAVLNode = node.right;
            var nodeRank:Number = node.rank;
            var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
            var rightDiff:Number = nodeRank - rightRank;

            // ──── 需要平衡：读取左侧信息 ────
            var leftNode:WAVLNode = node.left;
            var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
            var leftDiff:Number = nodeRank - leftRank;

            // ──── 快速检查：两侧 diff 都在 [1,2] 范围内 ────
            // 【Bug 修复 2024-11】与左侧删除对称，需要检测 (2,2) 非叶子节点
            if (rightDiff <= 2) {
                // [修复] 检查是否产生了违规的 (2,2) 非叶子节点
                if (leftDiff == 2 && rightDiff == 2) {
                    node.rank = nodeRank - 1;
                    return node;
                }
                this.__needRebalance = false;
                return node;
            }

            // Case: (1, 3) - 右侧严重失衡
            if (leftDiff == 1 && rightDiff == 3) {
                var lrNode:WAVLNode = leftNode.right;
                var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;

                // 子情况: 左子的右孙是 1-child → 双旋转 (LR)
                if (leftRank - lrRank == 1) {
                    var pivot2Left:WAVLNode = lrNode.left;
                    var pivot2Right:WAVLNode = lrNode.right;
                    leftNode.right = pivot2Left;
                    node.left = pivot2Right;
                    lrNode.left = leftNode;
                    lrNode.right = node;

                    lrNode.rank += 2;
                    leftNode.rank = leftRank - 1;
                    node.rank = nodeRank - 2;

                    if (pivot2Right == null && rightNode == null) node.rank = 0;

                    this.__needRebalance = false;
                    return lrNode;
                }

                // 子情况: 左子的左孙是 1-child → 单右旋
                //
                // 【Bug 修复 2024-11】与单左旋对称
                // leftNode.rank 保持不变，不能 +1，否则形成 (2,2) 非叶子节点
                //
                var llNode:WAVLNode = leftNode.left;
                var llRank:Number = (llNode != null) ? llNode.rank : -1;
                if (leftRank - llRank == 1) {
                    node.left = lrNode;
                    leftNode.right = node;

                    // [修复] leftNode.rank 保持不变，删除场景的单旋不需要 +1
                    node.rank = nodeRank - 2;

                    if (lrNode == null && rightNode == null) node.rank = 0;

                    this.__needRebalance = false;
                    return leftNode;
                }

                // 子情况: 左子是 (2, 2) → 双 demote
                node.rank = nodeRank - 1;
                leftNode.rank = leftRank - 1;
                return node;
            }

            // Case: (2, 3) - 简单 demote
            node.rank = nodeRank - 1;
            return node;
        }

        // ════════════════════════════════════════════════════════════════════
        //                        找到节点并执行删除
        // ════════════════════════════════════════════════════════════════════

        var nodeLeft:WAVLNode = node.left;
        var nodeRight:WAVLNode = node.right;

        // ──────────────────── Case 1: 无左子 → 用右子替代 ────────────────────
        if (nodeLeft == null) {
            _treeSize--;
            this.__needRebalance = true;  // 结构变化，需要检查平衡
            return nodeRight;  // 可能为 null（叶子节点情况）
        }

        // ──────────────────── Case 2: 无右子 → 用左子替代 ────────────────────
        if (nodeRight == null) {
            _treeSize--;
            this.__needRebalance = true;
            return nodeLeft;
        }

        // ════════════════════════════════════════════════════════════════════
        //              Case 3: 双子节点 → 用后继替代 + deleteMin 优化
        // ════════════════════════════════════════════════════════════════════
        //
        // 【传统实现的问题】
        //
        //   var succ = findMin(node.right);
        //   node.value = succ.value;
        //   node.right = deleteNode(node.right, succ.value, cmpFn);  // 重新搜索！
        //
        // 这会导致：
        // 1. 第一次：findMin 下潜到右子树最左侧 → O(log n)
        // 2. 第二次：deleteNode 带着 succ.value 重新比较搜索 → 又是 O(log n)
        //
        // 总复杂度变成 1.5 × height，而且比较函数被调用了两遍。
        //
        // 【优化方案】
        //
        // 实现专用的 deleteMin 函数：
        // - 不需要比较：直接一路向左下潜
        // - 只有一次遍历：找到即删除
        //
        //   var succ = findMin(node.right);  // 找到后继
        //   node.value = succ.value;          // 值替换
        //   node.right = deleteMin(node.right);  // 直接删除最小节点
        //
        // 【性能收益】
        // 对于随机数据，约 33% 的节点有两个子节点。
        // 这部分删除操作的性能提升约 50%。
        //
        var succ:WAVLNode = nodeRight;
        while (succ.left != null) succ = succ.left;  // 找到后继（右子树最小节点）
        node.value = succ.value;  // 值替换
        node.right = this.deleteMin(nodeRight);  // [优化] 使用 deleteMin 删除后继

        // ──────────────── 删除后继后的平衡检查 ────────────────
        //
        // 删除后继相当于在右子树中删除，需要执行右侧删除后的平衡逻辑
        //
        if (!this.__needRebalance) return node;

        // [内联] 右侧删除后平衡（复用上面的逻辑）
        var rightNode:WAVLNode = node.right;
        var nodeRank:Number = node.rank;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var rightDiff:Number = nodeRank - rightRank;

        // 读取左侧信息
        var leftNode:WAVLNode = node.left;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var leftDiff:Number = nodeRank - leftRank;

        // 【Bug 修复 2024-11】deleteMin 后也需要检测 (2,2) 非叶子节点
        if (rightDiff <= 2) {
            // [修复] 检查是否产生了违规的 (2,2) 非叶子节点
            if (leftDiff == 2 && rightDiff == 2) {
                node.rank = nodeRank - 1;
                return node;
            }
            this.__needRebalance = false;
            return node;
        }

        if (leftDiff == 1 && rightDiff == 3) {
            var lrNode:WAVLNode = leftNode.right;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;

            // 双旋转 (LR)
            if (leftRank - lrRank == 1) {
                var pivot2Left:WAVLNode = lrNode.left;
                var pivot2Right:WAVLNode = lrNode.right;
                leftNode.right = pivot2Left;
                node.left = pivot2Right;
                lrNode.left = leftNode;
                lrNode.right = node;
                lrNode.rank += 2;
                leftNode.rank = leftRank - 1;
                node.rank = nodeRank - 2;
                if (pivot2Right == null && rightNode == null) node.rank = 0;
                this.__needRebalance = false;
                return lrNode;
            }

            // 单右旋 - 【Bug 修复 2024-11】leftNode.rank 不能 +1
            var llNode:WAVLNode = leftNode.left;
            var llRank:Number = (llNode != null) ? llNode.rank : -1;
            if (leftRank - llRank == 1) {
                node.left = lrNode;
                leftNode.right = node;
                // leftNode.rank 保持不变（删除场景的单旋不需要 +1）
                node.rank = nodeRank - 2;
                if (lrNode == null && rightNode == null) node.rank = 0;
                this.__needRebalance = false;
                return leftNode;
            }

            node.rank = nodeRank - 1;
            leftNode.rank = leftRank - 1;
            return node;
        }

        node.rank = nodeRank - 1;
        return node;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                           删除最小节点（优化辅助函数）
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 删除子树中的最小节点
     *
     * @param node 子树的根节点
     * @return 删除后的子树根节点
     *
     * 【设计目的】
     * 专门用于双子节点删除场景，避免通用 deleteNode 的比较开销。
     *
     * 【算法特点】
     * 1. 无需比较：直接一路向左下潜
     * 2. 路径最短：不走右分支
     * 3. 平衡逻辑内联：避免函数调用开销
     *
     * 【与通用 deleteNode 的对比】
     *
     *   deleteNode(root, min.value, cmpFn):
     *   - 每层需要调用 cmpFn 比较
     *   - 可能走错分支（虽然不会发生，但代码要处理）
     *
     *   deleteMin(root):
     *   - 无比较，直接 node.left
     *   - 代码路径更短
     *
     * 【性能数据】
     * 在双子节点删除场景下（约占 33%），性能提升约 50%。
     */
    private function deleteMin(node:WAVLNode):WAVLNode {
        // ──────────────────── 找到最小节点 ────────────────────
        //
        // 最小节点 = 最左侧节点，其 left 为 null
        //
        if (node.left == null) {
            _treeSize--;
            this.__needRebalance = true;  // 结构变化
            return node.right;  // 用右子替代（可能为 null）
        }

        // 递归下潜
        node.left = this.deleteMin(node.left);

        // 差分早退出
        if (!this.__needRebalance) return node;

        // ──────────────── [内联] 左侧删除后平衡逻辑 ────────────────
        //
        // 这段代码与 deleteNode 中的左侧分支平衡逻辑完全相同。
        // 虽然代码重复，但避免了函数调用开销。
        //
        var leftNode:WAVLNode = node.left;
        var nodeRank:Number = node.rank;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var leftDiff:Number = nodeRank - leftRank;

        // 读取右侧信息
        var rightNode:WAVLNode = node.right;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var rightDiff:Number = nodeRank - rightRank;

        // 【Bug 修复 2024-11】deleteMin 内部同样需要检测 (2,2) 非叶子节点
        if (leftDiff <= 2) {
            // [修复] 检查是否产生了违规的 (2,2) 非叶子节点
            if (leftDiff == 2 && rightDiff == 2) {
                node.rank = nodeRank - 1;
                return node;
            }
            this.__needRebalance = false;
            return node;
        }

        if (leftDiff == 3 && rightDiff == 1) {
            var rlNode:WAVLNode = rightNode.left;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;

            // 双旋转 (RL)
            if (rightRank - rlRank == 1) {
                var pivotLeft:WAVLNode = rlNode.left;
                var pivotRight:WAVLNode = rlNode.right;
                rightNode.left = pivotRight;
                node.right = pivotLeft;
                rlNode.right = rightNode;
                rlNode.left = node;
                rlNode.rank += 2;
                rightNode.rank = rightRank - 1;
                node.rank = nodeRank - 2;
                if (leftNode == null && pivotLeft == null) node.rank = 0;
                this.__needRebalance = false;
                return rlNode;
            }

            // 单左旋 - 【Bug 修复 2024-11】rightNode.rank 不能 +1
            var rrNode:WAVLNode = rightNode.right;
            var rrRank:Number = (rrNode != null) ? rrNode.rank : -1;
            if (rightRank - rrRank == 1) {
                node.right = rlNode;
                rightNode.left = node;
                // [修复] rightNode.rank 保持不变，删除场景的单旋不需要 +1
                node.rank = nodeRank - 2;
                if (leftNode == null && rlNode == null) node.rank = 0;
                this.__needRebalance = false;
                return rightNode;
            }

            // 双 demote
            node.rank = nodeRank - 1;
            rightNode.rank = rightRank - 1;
            return node;
        }

        // 简单 demote
        node.rank = nodeRank - 1;
        return node;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                              树构建操作
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 从有序数组递归构建平衡树
     *
     * @param sortedArr 已排序的数组
     * @param start 起始索引（包含）
     * @param end 结束索引（包含）
     * @return 构建的子树根节点
     *
     * 【算法】
     * 分治法：取中间元素作为根，递归构建左右子树。
     * 这保证了构建出的树是完美平衡的。
     *
     * 【时间复杂度】O(n)
     * 【空间复杂度】O(log n) 递归栈
     *
     * 【rank 计算】
     * 新节点的 rank = max(左子rank, 右子rank) + 1
     * 这满足 WAVL 的 rank差 为 1 的要求（完美平衡树）。
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):WAVLNode {
        // 基础情况：空区间
        if (start > end) {
            return null;
        }

        // 取中间元素作为根
        var mid:Number = (start + end) >> 1;  // 位运算除以2，更快
        var newNode:WAVLNode = new WAVLNode(sortedArr[mid]);

        // 递归构建子树
        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 计算 rank：基于子节点的 rank
        // [优化] 内联计算，避免函数调用
        var leftNode:WAVLNode = newNode.left;
        var rightNode:WAVLNode = newNode.right;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;

        // rank = max(leftRank, rightRank) + 1
        newNode.rank = ((leftRank > rightRank) ? leftRank : rightRank) + 1;

        return newNode;
    }
}
