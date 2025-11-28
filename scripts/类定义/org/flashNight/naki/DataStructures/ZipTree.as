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
 * 【实现特点】
 * 1. 核心操作迭代化: contains、add、remove、toArray 使用 while 循环
 * 2. 迭代式 unzip: add 中内联实现，使用双指针追踪
 * 3. 迭代式 zip: zipIterative 方法，交替选取节点构建脊椎
 * 4. 比较函数缓存到局部变量，减少成员访问开销
 *
 * 【性能特点】(10000 元素基准测试)
 * - 插入最快: 195ms，领先 WAVL(382ms) 和 AVL(472ms)
 * - 搜索较慢: 285ms，略逊于 WAVL(146ms) 和 AVL(164ms)
 * - 删除中等: 279ms，与 WAVL(248ms) 和 AVL(229ms) 相当
 * - 总体: 759ms，与 WAVL(776ms) 接近，优于 AVL(865ms)
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
     * 添加元素 - 迭代实现
     *
     * 算法思路（基于 Tarjan 论文）：
     * 1. 向下搜索找到插入位置，同时判断 rank 条件
     * 2. 找到第一个 rank < newNode.rank 的位置后，执行迭代式 unzip
     * 3. unzip 沿单一路径进行，用双指针完成分裂
     *
     * 实现特点：
     * - 完全迭代，无递归调用
     * - unzip 内联实现，使用 leftTail/rightTail 指针追踪
     * - 比较函数缓存到局部变量
     *
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        var cmpFn:Function = this.compareFunction;
        var newRank:Number = this.generateRank();
        var newNode:ZipNode = new ZipNode(element, newRank);

        // 空树特殊处理
        if (this.root == null) {
            this.root = newNode;
            this.treeSize++;
            return;
        }

        // 阶段1: 向下搜索，找到需要插入的位置
        // 同时判断 newNode 是否需要成为某个子树的根
        var current:ZipNode = this.root;
        var parent:ZipNode = null;
        var isLeftChild:Boolean = false;
        var cmp:Number;

        while (current != null) {
            cmp = cmpFn(element, current.value);

            if (cmp == 0) {
                // 重复元素，不插入
                return;
            }

            // 检查是否需要在此位置插入（newNode 成为 current 的父节点）
            if (cmp < 0) {
                // 向左走，检查左子规则: parent.rank >= left.rank
                // 如果 newNode.rank > current.rank，newNode 应该取代 current
                if (newRank > current.rank) {
                    break;  // 找到插入位置
                }
            } else {
                // 向右走，检查右子规则: parent.rank > right.rank
                // 如果 newNode.rank >= current.rank，newNode 应该取代 current
                if (newRank >= current.rank) {
                    break;  // 找到插入位置
                }
            }

            // 继续向下搜索
            parent = current;
            if (cmp < 0) {
                isLeftChild = true;
                current = current.left;
            } else {
                isLeftChild = false;
                current = current.right;
            }
        }

        // 阶段2: 执行插入
        this.treeSize++;

        if (current == null) {
            // 到达叶子位置，直接插入
            if (isLeftChild) {
                parent.left = newNode;
            } else {
                parent.right = newNode;
            }
            return;
        }

        // 阶段3: 迭代式 Unzip
        // newNode 将取代 current 的位置，current 子树需要按 element 分裂
        // 分裂后：所有 < element 的节点成为 newNode.left
        //         所有 > element 的节点成为 newNode.right

        // 使用两个指针构建分裂后的两棵树
        var leftTail:ZipNode = null;   // left 树的当前"末端"
        var rightTail:ZipNode = null;  // right 树的当前"末端"
        var leftRoot:ZipNode = null;   // left 树的根
        var rightRoot:ZipNode = null;  // right 树的根

        while (current != null) {
            cmp = cmpFn(element, current.value);

            if (cmp < 0) {
                // element < current.value
                // current 及其右子树属于 right 部分
                if (rightRoot == null) {
                    rightRoot = current;
                    rightTail = current;
                } else {
                    rightTail.left = current;
                    rightTail = current;
                }
                // 继续处理 current.left
                var next:ZipNode = current.left;
                current.left = null;  // 断开，稍后重新连接
                current = next;
            } else {
                // element > current.value
                // current 及其左子树属于 left 部分
                if (leftRoot == null) {
                    leftRoot = current;
                    leftTail = current;
                } else {
                    leftTail.right = current;
                    leftTail = current;
                }
                // 继续处理 current.right
                var next:ZipNode = current.right;
                current.right = null;  // 断开，稍后重新连接
                current = next;
            }
        }

        // 连接 newNode 的左右子树
        newNode.left = leftRoot;
        newNode.right = rightRoot;

        // 更新父节点指针
        if (parent == null) {
            this.root = newNode;
        } else if (isLeftChild) {
            parent.left = newNode;
        } else {
            parent.right = newNode;
        }
    }

    /**
     * 移除元素 - 迭代实现
     *
     * 算法思路：
     * 1. BST 搜索找到目标节点
     * 2. 使用 zipIterative 合并左右子树
     * 3. 合并结果替代被删除节点
     *
     * @param element 要移除的元素
     * @return 是否成功移除
     */
    public function remove(element:Object):Boolean {
        var cmpFn:Function = this.compareFunction;

        // 找到要删除的节点及其父节点
        var current:ZipNode = this.root;
        var parent:ZipNode = null;
        var isLeftChild:Boolean = false;
        var cmp:Number;

        while (current != null) {
            cmp = cmpFn(element, current.value);

            if (cmp == 0) {
                // 找到了
                break;
            }

            parent = current;
            if (cmp < 0) {
                current = current.left;
                isLeftChild = true;
            } else {
                current = current.right;
                isLeftChild = false;
            }
        }

        if (current == null) {
            return false;  // 元素不存在
        }

        this.treeSize--;

        // 使用迭代式 zip 合并左右子树
        var merged:ZipNode = this.zipIterative(current.left, current.right);

        // 更新父节点指针
        if (parent == null) {
            this.root = merged;
        } else if (isLeftChild) {
            parent.left = merged;
        } else {
            parent.right = merged;
        }

        return true;
    }

    /**
     * Zip 操作 - 迭代实现
     *
     * 前提条件：left 中所有值 < right 中所有值
     *
     * 合并策略基于 rank：
     * - rank 严格更高者成为合并后的根
     * - left.rank > right.rank 时，left 成为根
     * - left.rank <= right.rank 时，right 成为根
     *
     * 迭代实现思路：
     * 交替从两棵树中选取节点，构建合并后的"脊椎"
     *
     * @param left 左子树（所有值较小）
     * @param right 右子树（所有值较大）
     * @return 合并后的子树根节点
     */
    private function zipIterative(left:ZipNode, right:ZipNode):ZipNode {
        if (left == null) return right;
        if (right == null) return left;

        // 确定根节点
        var root:ZipNode;
        var tail:ZipNode;
        var tailIsFromLeft:Boolean;

        if (left.rank > right.rank) {
            root = left;
            tail = left;
            left = left.right;
            tailIsFromLeft = true;
        } else {
            root = right;
            tail = right;
            right = right.left;
            tailIsFromLeft = false;
        }

        // 迭代合并
        while (left != null && right != null) {
            if (left.rank > right.rank) {
                // left 节点应该更高
                if (tailIsFromLeft) {
                    // tail 来自 left 树，接到 tail.right
                    tail.right = left;
                } else {
                    // tail 来自 right 树，接到 tail.left
                    tail.left = left;
                }
                tail = left;
                left = left.right;
                tailIsFromLeft = true;
            } else {
                // right 节点应该更高（或相等）
                if (tailIsFromLeft) {
                    tail.right = right;
                } else {
                    tail.left = right;
                }
                tail = right;
                right = right.left;
                tailIsFromLeft = false;
            }
        }

        // 处理剩余部分
        var remaining:ZipNode = (left != null) ? left : right;
        if (remaining != null) {
            if (tailIsFromLeft) {
                tail.right = remaining;
            } else {
                tail.left = remaining;
            }
        }

        return root;
    }

    /**
     * 检查是否包含元素 - 迭代实现
     *
     * 标准 BST 搜索，使用 while 循环遍历
     *
     * @param element 要查找的元素
     * @return 是否包含
     */
    public function contains(element:Object):Boolean {
        var current:ZipNode = this.root;
        var cmpFn:Function = this.compareFunction;  // 缓存到局部变量
        var cmp:Number;

        while (current != null) {
            cmp = cmpFn(element, current.value);
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

    /**
     * 查找节点 - 迭代实现
     * @param element 要查找的元素
     * @return 找到的节点，或 null
     */
    private function findNode(element:Object):ZipNode {
        var current:ZipNode = this.root;
        var cmpFn:Function = this.compareFunction;
        var cmp:Number;

        while (current != null) {
            cmp = cmpFn(element, current.value);
            if (cmp < 0) {
                current = current.left;
            } else if (cmp > 0) {
                current = current.right;
            } else {
                return current;
            }
        }
        return null;
    }

    /**
     * 返回树中元素数量
     */
    public function size():Number {
        return this.treeSize;
    }

    /**
     * 中序遍历转数组 - 迭代实现
     *
     * 使用显式栈模拟递归遍历
     */
    public function toArray():Array {
        var arr:Array = new Array(this.treeSize);
        var arrIdx:Number = 0;

        var stack:Array = [];
        var stackIdx:Number = 0;
        var node:ZipNode = this.root;

        while (node != null || stackIdx > 0) {
            // 先走到最左
            while (node != null) {
                stack[stackIdx++] = node;
                node = node.left;
            }
            // 弹出并处理
            node = stack[--stackIdx];
            arr[arrIdx++] = node.value;
            // 转向右子树
            node = node.right;
        }

        return arr;
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
