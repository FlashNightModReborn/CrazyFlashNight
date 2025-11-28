import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*; 
import org.flashNight.gesh.string.*;

/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║                              ZipTree (Zip树)                                 ║
 * ║                    随机化自平衡二叉搜索树 ActionScript 2 实现                  ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 *
 * @class ZipTree
 * @package org.flashNight.naki.DataStructures
 * @author flashNight
 * @version 2.0
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                   理论背景
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * Zip Tree 由 Tarjan, Levy, Timmel 于 2019 年提出。
 * 论文: "Zip Trees" (arXiv:1806.06726)
 *
 * 【核心创新】
 * - 每个节点持有一个服从几何分布的随机 rank
 * - 使用简洁的 zip/unzip 操作替代复杂的旋转
 * - 期望树高 O(log n)，操作期望 O(log n)
 *
 * 【Zip Tree 不变量】
 * 1. BST 性质: 左子树所有值 < 当前值 < 右子树所有值
 * 2. 堆序性质: 父节点的 rank >= 左子节点的 rank
 * 3. 严格堆序: 父节点的 rank > 右子节点的 rank
 *    (相同 rank 时，键值较小者优先成为父节点)
 *
 * 【插入算法】
 * 递归下降找到插入位置，当新节点的 rank 足够高时：
 * - 使用 unzip 操作将当前子树按新键值分割为左右两部分
 * - 新节点成为根，分割后的两部分成为其左右子树
 *
 * 【删除算法】
 * 找到要删除的节点后：
 * - 使用 zip 操作合并其左右子树
 * - 合并结果替换被删除节点
 *
 * ════════════════════════════════════════════════════════════════════════════════
 */
class org.flashNight.naki.DataStructures.ZipTree {

    // ════════════════════════════════════════════════════════════════════════════
    //                                  成员变量
    // ════════════════════════════════════════════════════════════════════════════

    /** 树的根节点 */
    private var root:ZipNode;

    /**
     * 比较函数
     * 函数签名: function(a:Object, b:Object):Number
     * 返回值:   负数 (a<b), 0 (a==b), 正数 (a>b)
     */
    private var compareFunction:Function;

    /** 树中元素的数量 */
    private var treeSize:Number;

    /**
     * 随机数生成器状态 (Linear Congruential Generator)
     */
    private var randomSeed:Number;

    // ════════════════════════════════════════════════════════════════════════════
    //                                  构造函数
    // ════════════════════════════════════════════════════════════════════════════

    public function ZipTree(compareFunction:Function) {
        if (compareFunction == undefined || compareFunction == null) {
            this.compareFunction = function(a, b):Number {
                return (a < b) ? -1 : ((a > b) ? 1 : 0);
            };
        } else {
            this.compareFunction = compareFunction;
        }
        this.root = null;
        this.treeSize = 0;
        this.randomSeed = (getTimer() * 1103515245 + 12345) & 0x7FFFFFFF;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                                  静态工厂方法
    // ════════════════════════════════════════════════════════════════════════════

    public static function buildFromArray(arr:Array, compareFunction:Function):ZipTree {
        var tree:ZipTree = new ZipTree(compareFunction);
        TimSort.sort(arr, tree.compareFunction);

        for (var i:Number = 0; i < arr.length; i++) {
            tree.add(arr[i]);
        }

        return tree;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                                  公共接口
    // ════════════════════════════════════════════════════════════════════════════

    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        this.compareFunction = newCompareFunction;
        var arr:Array = this.toArray();
        TimSort.sort(arr, newCompareFunction);
        this.root = null;
        this.treeSize = 0;
        for (var i:Number = 0; i < arr.length; i++) {
            this.add(arr[i]);
        }
    }

    /**
     * 添加元素 - 递归实现
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        var newRank:Number = this.generateRank();
        var newNode:ZipNode = new ZipNode(element, newRank);
        this.root = this.insertNode(this.root, newNode);
    }

    /**
     * 递归插入节点
     *
     * 核心逻辑：
     * 1. 如果当前位置为空，直接返回新节点
     * 2. 比较键值决定插入方向
     * 3. 如果新节点 rank 更高（需要上浮），则执行 unzip 分割子树
     * 4. 否则递归到相应子树
     *
     * @param node 当前子树根节点
     * @param newNode 要插入的新节点
     * @return 更新后的子树根节点
     */
    private function insertNode(node:ZipNode, newNode:ZipNode):ZipNode {
        if (node == null) {
            this.treeSize++;
            return newNode;
        }

        var cmp:Number = this.compareFunction(newNode.value, node.value);

        if (cmp == 0) {
            // 重复元素，不插入
            return node;
        }

        if (cmp < 0) {
            // 新节点应在左子树
            // 检查是否需要让新节点成为当前节点的父节点
            // 左子规则: parent.rank >= left.rank
            // 如果 newNode.rank > node.rank，则 newNode 应该成为父节点
            if (newNode.rank > node.rank) {
                // 新节点 rank 更高，执行 unzip 分割
                // unzip 将 node 子树按 newNode.value 分割为两部分
                var result:Object = this.unzip(node, newNode.value);
                newNode.left = result.left;   // 所有 < newNode.value 的节点
                newNode.right = result.right; // 所有 > newNode.value 的节点
                this.treeSize++;
                return newNode;
            } else {
                // rank 不够高，继续递归
                node.left = this.insertNode(node.left, newNode);
                return node;
            }
        } else {
            // 新节点应在右子树
            // 右子规则: parent.rank > right.rank (严格大于)
            // 如果 newNode.rank >= node.rank，则 newNode 应该成为父节点
            if (newNode.rank >= node.rank) {
                // 新节点 rank 足够高（相等时新节点也上浮，因为右子必须严格小于）
                var result:Object = this.unzip(node, newNode.value);
                newNode.left = result.left;
                newNode.right = result.right;
                this.treeSize++;
                return newNode;
            } else {
                // rank 不够高，继续递归
                node.right = this.insertNode(node.right, newNode);
                return node;
            }
        }
    }

    /**
     * Unzip 操作 - 将子树按键值分割
     *
     * 将以 node 为根的子树按 key 分割为两棵子树：
     * - left: 所有值 < key 的节点组成的子树
     * - right: 所有值 > key 的节点组成的子树
     *
     * 关键洞察：由于是 BST，分割操作沿着搜索路径进行
     * - 如果当前节点 < key，则当前节点及其左子树都属于 left 部分
     *   继续在右子树中分割
     * - 如果当前节点 > key，则当前节点及其右子树都属于 right 部分
     *   继续在左子树中分割
     *
     * @param node 要分割的子树根节点
     * @param key 分割键值
     * @return {left: ZipNode, right: ZipNode} 分割后的两棵子树
     */
    private function unzip(node:ZipNode, key:Object):Object {
        if (node == null) {
            return {left: null, right: null};
        }

        var cmp:Number = this.compareFunction(key, node.value);

        if (cmp < 0) {
            // key < node.value
            // node 及其右子树属于 right 部分
            // 继续在 node.left 中分割
            var result:Object = this.unzip(node.left, key);
            node.left = result.right;  // node 的新左子是分割后的右部分
            return {left: result.left, right: node};
        } else {
            // key > node.value (不可能相等，因为我们不插入重复值)
            // node 及其左子树属于 left 部分
            // 继续在 node.right 中分割
            var result:Object = this.unzip(node.right, key);
            node.right = result.left;  // node 的新右子是分割后的左部分
            return {left: node, right: result.right};
        }
    }

    /**
     * 移除元素 - 递归实现
     * @param element 要移除的元素
     * @return 是否成功移除
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        this.root = this.removeNode(this.root, element);
        return this.treeSize < oldSize;
    }

    /**
     * 递归删除节点
     * @param node 当前子树根节点
     * @param element 要删除的元素
     * @return 更新后的子树根节点
     */
    private function removeNode(node:ZipNode, element:Object):ZipNode {
        if (node == null) {
            return null;
        }

        var cmp:Number = this.compareFunction(element, node.value);

        if (cmp < 0) {
            node.left = this.removeNode(node.left, element);
            return node;
        } else if (cmp > 0) {
            node.right = this.removeNode(node.right, element);
            return node;
        } else {
            // 找到要删除的节点
            this.treeSize--;
            // 使用 zip 合并左右子树
            return this.zip(node.left, node.right);
        }
    }

    /**
     * Zip 操作 - 合并两棵子树
     *
     * 前提条件：left 中所有值 < right 中所有值
     *
     * 合并策略基于 rank：
     * - 比较两棵树根的 rank
     * - rank 严格更高者成为合并后的根
     * - 不变量要求：
     *   - 左子: parent.rank >= left.rank (允许相等)
     *   - 右子: parent.rank > right.rank (严格大于)
     *
     * 关键：当 left.rank == right.rank 时，必须让 right 成为根
     * 这样 left 进入 right.left，满足 left.rank <= right.rank
     * 避免 left.right = right 导致 left.rank == right.rank 违反右子严格小于
     *
     * @param left 左子树（所有值较小）
     * @param right 右子树（所有值较大）
     * @return 合并后的子树根节点
     */
    private function zip(left:ZipNode, right:ZipNode):ZipNode {
        if (left == null) {
            return right;
        }
        if (right == null) {
            return left;
        }

        // 比较 rank 决定谁成为根
        // 只有当 left.rank 严格大于 right.rank 时，left 才能成为根
        // 这确保了 left.right 的 rank 严格小于 left.rank
        if (left.rank > right.rank) {
            // left 成为根，其右子树与 right 合并
            left.right = this.zip(left.right, right);
            return left;
        } else {
            // right 成为根（包括 rank 相等的情况）
            // left 进入 right.left，满足 parent.rank >= left.rank
            right.left = this.zip(left, right.left);
            return right;
        }
    }

    /**
     * 检查是否包含元素
     * @param element 要查找的元素
     * @return 是否包含
     */
    public function contains(element:Object):Boolean {
        return this.findNode(this.root, element) != null;
    }

    /**
     * 递归查找节点
     */
    private function findNode(node:ZipNode, element:Object):ZipNode {
        if (node == null) {
            return null;
        }

        var cmp:Number = this.compareFunction(element, node.value);

        if (cmp < 0) {
            return this.findNode(node.left, element);
        } else if (cmp > 0) {
            return this.findNode(node.right, element);
        } else {
            return node;
        }
    }

    /**
     * 返回树中元素数量
     */
    public function size():Number {
        return this.treeSize;
    }

    /**
     * 中序遍历转数组
     */
    public function toArray():Array {
        var arr:Array = [];
        this.inorderTraversal(this.root, arr);
        return arr;
    }

    /**
     * 中序遍历辅助函数
     */
    private function inorderTraversal(node:ZipNode, arr:Array):Void {
        if (node == null) {
            return;
        }
        this.inorderTraversal(node.left, arr);
        arr.push(node.value);
        this.inorderTraversal(node.right, arr);
    }

    /**
     * 获取根节点（用于测试）
     */
    public function getRoot():ZipNode {
        return this.root;
    }

    /**
     * 获取比较函数
     */
    public function getCompareFunction():Function {
        return this.compareFunction;
    }

    /**
     * 前序遍历字符串表示
     */
    public function toString():String {
        var arr:Array = [];
        this.preorderToString(this.root, arr);
        return arr.join(" ");
    }

    /**
     * 前序遍历辅助函数
     */
    private function preorderToString(node:ZipNode, arr:Array):Void {
        if (node == null) {
            return;
        }
        arr.push(node.toString());
        this.preorderToString(node.left, arr);
        this.preorderToString(node.right, arr);
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                              随机数生成
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 生成服从几何分布的随机 rank
     * P(rank = k) = (1/2)^k
     * 期望值 E[rank] = 2
     *
     * 实现：计算随机数尾部连续 0 的个数 + 1
     * - 若最低位是 1，rank = 1 (概率 1/2)
     * - 若最低2位是 10，rank = 2 (概率 1/4)
     * - 若最低3位是 100，rank = 3 (概率 1/8)
     * - ...
     */
    private function generateRank():Number {
        this.randomSeed = (this.randomSeed * 1103515245 + 12345) & 0x7FFFFFFF;

        var rand:Number = this.randomSeed;
        var rank:Number = 1;

        // 计算尾部连续 0 的个数 + 1
        while ((rand & 1) == 0 && rank < 32) {
            rank++;
            rand = rand >> 1;
        }

        return rank;
    }

    /**
     * 设置随机种子（用于测试可重现性）
     */
    public function setSeed(seed:Number):Void {
        this.randomSeed = seed & 0x7FFFFFFF;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                              辅助方法
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * 获取树的高度
     */
    public function getHeight():Number {
        return this.computeHeight(this.root);
    }

    private function computeHeight(node:ZipNode):Number {
        if (node == null) {
            return 0;
        }
        var leftHeight:Number = this.computeHeight(node.left);
        var rightHeight:Number = this.computeHeight(node.right);
        return 1 + (leftHeight > rightHeight ? leftHeight : rightHeight);
    }

    /**
     * 获取最小元素
     */
    public function getMin():Object {
        if (this.root == null) {
            return null;
        }
        var node:ZipNode = this.root;
        while (node.left != null) {
            node = node.left;
        }
        return node.value;
    }

    /**
     * 获取最大元素
     */
    public function getMax():Object {
        if (this.root == null) {
            return null;
        }
        var node:ZipNode = this.root;
        while (node.right != null) {
            node = node.right;
        }
        return node.value;
    }

    /**
     * 清空树
     */
    public function clear():Void {
        this.root = null;
        this.treeSize = 0;
    }

    /**
     * 检查树是否为空
     */
    public function isEmpty():Boolean {
        return this.treeSize == 0;
    }
}
