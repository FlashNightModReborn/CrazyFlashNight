import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;

/**
 * @class WAVLTree
 * @package org.flashNight.naki.DataStructures
 * @description 基于 WAVL (Weak AVL) 树实现的集合数据结构。
 *              严格遵循 Haeupler, Sen, Tarjan 2015 论文的 WAVL 规则。
 *
 *              WAVL 不变量：
 *              1. rank差（父rank - 子rank）必须为 1 或 2
 *              2. 外部节点(null)的 rank 定义为 -1
 *              3. 叶子节点的 rank 必须为 0（即 (1,1)-叶子）
 *              4. 内部节点不能是 (2,2)-节点，除非是叶子
 */
class org.flashNight.naki.DataStructures.WAVLTree {
    private var root:WAVLNode;
    private var compareFunction:Function;
    private var treeSize:Number;

    // 删除操作的差分早退出信号：当子树修复后 rank 未变化时设为 false
    private var __needRebalance:Boolean;

    public function WAVLTree(compareFunction:Function) {
        if (compareFunction == undefined || compareFunction == null) {
            this.compareFunction = function(a, b):Number {
                return (a < b) ? -1 : ((a > b) ? 1 : 0);
            };
        } else {
            this.compareFunction = compareFunction;
        }
        this.root = null;
        this.treeSize = 0;
    }

    public static function buildFromArray(arr:Array, compareFunction:Function):WAVLTree {
        var tree:WAVLTree = new WAVLTree(compareFunction);
        TimSort.sort(arr, compareFunction);
        tree.root = tree.buildBalancedTree(arr, 0, arr.length - 1);
        tree.treeSize = arr.length;
        return tree;
    }

    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        this.compareFunction = newCompareFunction;
        var arr:Array = this.toArray();
        TimSort.sort(arr, newCompareFunction);
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        this.treeSize = arr.length;
    }

    public function add(element:Object):Void {
        // [优化] 传入缓存的比较函数
        this.root = insert(this.root, element, this.compareFunction);
    }

    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        // [优化] 传入缓存的比较函数
        this.root = deleteNode(this.root, element, this.compareFunction);
        return (this.treeSize < oldSize);
    }

    public function contains(element:Object):Boolean {
        var current:WAVLNode = this.root;
        var cmpFn:Function = this.compareFunction;  // [优化] 缓存函数引用到局部变量
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

    public function size():Number {
        return this.treeSize;
    }

    public function toArray():Array {
        var arr:Array = [];
        var stack:Array = [];
        var index:Number = 0;
        var node:WAVLNode = this.root;
        while (node != null || index > 0) {
            while (node != null) {
                stack[index++] = node;
                node = node.left;
            }
            node = stack[--index];
            arr[arr.length] = node.value;
            node = node.right;
        }
        return arr;
    }

    public function getRoot():WAVLNode {
        return this.root;
    }

    public function getCompareFunction():Function {
        return this.compareFunction;
    }

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

    //======================== 插入操作 ========================//

    // [优化1] cmpFn 作为参数传递，避免每次递归都查找 this.compareFunction
    // [优化2] 非对称早退出：只检查刚插入那一侧的 diff
    private function insert(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
        if (node == null) {
            this.treeSize++;
            return new WAVLNode(element);  // 新叶子 rank=0
        }

        var cmp:Number = cmpFn(element, node.value);  // [优化1] 使用参数调用

        // [优化2] 非对称早退出 - 从左侧递归回来
        if (cmp < 0) {
            node.left = insert(node.left, element, cmpFn);

            var leftNode:WAVLNode = node.left;
            var leftRank:Number = leftNode.rank;  // 刚插入，leftNode 必存在
            var nodeRank:Number = node.rank;
            var leftDiff:Number = nodeRank - leftRank;

            // 快速检查：左侧 diff 不为 0，说明平衡（1或2），直接返回
            if (leftDiff != 0) {
                return node;
            }

            // 左侧出问题(diff=0)，才去读右侧
            var rightNode:WAVLNode = node.right;
            var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
            var rightDiff:Number = nodeRank - rightRank;

            // Case: (0, 1) -> Promote
            if (rightDiff == 1) {
                node.rank = nodeRank + 1;
                return node;
            }

            // Case: (0, 2) -> 需要旋转
            var lrNode:WAVLNode = leftNode.right;
            var leftNodeRank:Number = leftRank;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;
            var lrDiff:Number = leftNodeRank - lrRank;

            if (lrDiff == 2) {
                // 左子是 (1,2) - 单右旋
                node.left = lrNode;
                leftNode.right = node;
                node.rank = nodeRank - 1;
                return leftNode;
            }
            // 左子是 (2,1) - 双旋转 (LR)
            leftNode.right = lrNode.left;
            node.left = lrNode.right;
            lrNode.left = leftNode;
            lrNode.right = node;
            lrNode.rank++;
            leftNode.rank = leftNodeRank - 1;
            node.rank = nodeRank - 1;
            return lrNode;
        }

        // [优化2] 非对称早退出 - 从右侧递归回来
        if (cmp > 0) {
            node.right = insert(node.right, element, cmpFn);

            var rightNode:WAVLNode = node.right;
            var rightRank:Number = rightNode.rank;  // 刚插入，rightNode 必存在
            var nodeRank:Number = node.rank;
            var rightDiff:Number = nodeRank - rightRank;

            // 快速检查：右侧 diff 不为 0，说明平衡（1或2），直接返回
            if (rightDiff != 0) {
                return node;
            }

            // 右侧出问题(diff=0)，才去读左侧
            var leftNode:WAVLNode = node.left;
            var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
            var leftDiff:Number = nodeRank - leftRank;

            // Case: (1, 0) -> Promote
            if (leftDiff == 1) {
                node.rank = nodeRank + 1;
                return node;
            }

            // Case: (2, 0) -> 需要旋转
            var rlNode:WAVLNode = rightNode.left;
            var rightNodeRank:Number = rightRank;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;
            var rlDiff:Number = rightNodeRank - rlRank;

            if (rlDiff == 2) {
                // 右子是 (2,1) - 单左旋
                node.right = rlNode;
                rightNode.left = node;
                node.rank = nodeRank - 1;
                return rightNode;
            }
            // 右子是 (1,2) - 双旋转 (RL)
            rightNode.left = rlNode.right;
            node.right = rlNode.left;
            rlNode.right = rightNode;
            rlNode.left = node;
            rlNode.rank++;
            node.rank = nodeRank - 1;
            rightNode.rank = rightNodeRank - 1;
            return rlNode;
        }

        // cmp == 0: 元素已存在
        return node;
    }

    //======================== 删除操作 ========================//

    // [优化] 删除操作 - 非对称惰性平衡
    // 1. cmpFn 作为参数传递
    // 2. 只检查刚删除那一侧的 diff，大部分情况无需读取另一侧
    private function deleteNode(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
        if (node == null) {
            this.__needRebalance = false;
            return null;
        }

        var cmp:Number = cmpFn(element, node.value);

        // ==================== 左侧分支 ====================
        if (cmp < 0) {
            node.left = deleteNode(node.left, element, cmpFn);
            if (!this.__needRebalance) return node;

            return this.rebalanceAfterLeftDelete(node);
        }

        // ==================== 右侧分支 ====================
        if (cmp > 0) {
            node.right = deleteNode(node.right, element, cmpFn);
            if (!this.__needRebalance) return node;

            return this.rebalanceAfterRightDelete(node);
        }

        // ==================== 找到节点并删除 ====================
        var nodeLeft:WAVLNode = node.left;
        var nodeRight:WAVLNode = node.right;

        if (nodeLeft == null && nodeRight == null) {
            this.treeSize--;
            this.__needRebalance = true;
            return null;
        }
        if (nodeLeft == null) {
            this.treeSize--;
            this.__needRebalance = true;
            return nodeRight;
        }
        if (nodeRight == null) {
            this.treeSize--;
            this.__needRebalance = true;
            return nodeLeft;
        }

        // 双子节点：找后继
        var succ:WAVLNode = nodeRight;
        while (succ.left != null) succ = succ.left;
        node.value = succ.value;
        node.right = deleteNode(nodeRight, succ.value, cmpFn);
        if (!this.__needRebalance) return node;

        return this.rebalanceAfterRightDelete(node);
    }

    // 从左侧删除后的再平衡
    private function rebalanceAfterLeftDelete(node:WAVLNode):WAVLNode {
        var leftNode:WAVLNode = node.left;
        var nodeRank:Number = node.rank;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var leftDiff:Number = nodeRank - leftRank;

        // 非对称早退出：左侧 diff 正常 (1或2)
        if (leftDiff <= 2) {
            // 短路检查：如果 leftNode 存在，肯定不是叶子
            if (leftNode != null || node.right != null) {
                this.__needRebalance = false;
                return node;
            }
            // 是叶子，检查 rank
            if (nodeRank == 0) {
                this.__needRebalance = false;
                return node;
            }
            // 非法叶子 (rank > 0)，继续降级
        }

        // 左侧出问题，才读取右侧
        var rightNode:WAVLNode = node.right;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var rightDiff:Number = nodeRank - rightRank;

        // Case: (3, 1)
        if (leftDiff == 3 && rightDiff == 1) {
            var rightNodeRank:Number = rightRank;
            var rlNode:WAVLNode = rightNode.left;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;

            // 双旋转 (RL)
            if (rightNodeRank - rlRank == 1) {
                var pivotLeft:WAVLNode = rlNode.left;
                var pivotRight:WAVLNode = rlNode.right;
                rightNode.left = pivotRight;
                node.right = pivotLeft;
                rlNode.right = rightNode;
                rlNode.left = node;
                rlNode.rank += 2;
                rightNode.rank = rightNodeRank - 1;
                node.rank = nodeRank - 2;
                if (leftNode == null && pivotLeft == null) node.rank = 0;
                this.__needRebalance = false;
                return rlNode;
            }

            // 单左旋
            var rrNode:WAVLNode = rightNode.right;
            var rrRank:Number = (rrNode != null) ? rrNode.rank : -1;
            if (rightNodeRank - rrRank == 1) {
                node.right = rlNode;
                rightNode.left = node;
                rightNode.rank = rightNodeRank + 1;
                node.rank = nodeRank - 2;
                if (leftNode == null && rlNode == null) node.rank = 0;
                this.__needRebalance = false;
                return rightNode;
            }

            // 双降级
            node.rank = nodeRank - 1;
            rightNode.rank = rightNodeRank - 1;
            return node;
        }

        // 简单降级
        node.rank = nodeRank - 1;
        return node;
    }

    // 从右侧删除后的再平衡
    private function rebalanceAfterRightDelete(node:WAVLNode):WAVLNode {
        var rightNode:WAVLNode = node.right;
        var nodeRank:Number = node.rank;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var rightDiff:Number = nodeRank - rightRank;

        // 非对称早退出：右侧 diff 正常 (1或2)
        if (rightDiff <= 2) {
            // 短路检查
            if (rightNode != null || node.left != null) {
                this.__needRebalance = false;
                return node;
            }
            if (nodeRank == 0) {
                this.__needRebalance = false;
                return node;
            }
        }

        // 右侧出问题，才读取左侧
        var leftNode:WAVLNode = node.left;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var leftDiff:Number = nodeRank - leftRank;

        // Case: (1, 3)
        if (leftDiff == 1 && rightDiff == 3) {
            var leftNodeRank:Number = leftRank;
            var lrNode:WAVLNode = leftNode.right;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;

            // 双旋转 (LR)
            if (leftNodeRank - lrRank == 1) {
                var pivot2Left:WAVLNode = lrNode.left;
                var pivot2Right:WAVLNode = lrNode.right;
                leftNode.right = pivot2Left;
                node.left = pivot2Right;
                lrNode.left = leftNode;
                lrNode.right = node;
                lrNode.rank += 2;
                leftNode.rank = leftNodeRank - 1;
                node.rank = nodeRank - 2;
                if (pivot2Right == null && rightNode == null) node.rank = 0;
                this.__needRebalance = false;
                return lrNode;
            }

            // 单右旋
            var llNode:WAVLNode = leftNode.left;
            var llRank:Number = (llNode != null) ? llNode.rank : -1;
            if (leftNodeRank - llRank == 1) {
                node.left = lrNode;
                leftNode.right = node;
                leftNode.rank = leftNodeRank + 1;
                node.rank = nodeRank - 2;
                if (lrNode == null && rightNode == null) node.rank = 0;
                this.__needRebalance = false;
                return leftNode;
            }

            // 双降级
            node.rank = nodeRank - 1;
            leftNode.rank = leftNodeRank - 1;
            return node;
        }

        // 简单降级
        node.rank = nodeRank - 1;
        return node;
    }

    //======================== 构建操作 ========================//

    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):WAVLNode {
        if (start > end) {
            return null;
        }

        var mid:Number = (start + end) >> 1;
        var newNode:WAVLNode = new WAVLNode(sortedArr[mid]);

        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 计算 rank：基于子节点的 rank（内联）
        var leftNode:WAVLNode = newNode.left;
        var rightNode:WAVLNode = newNode.right;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        newNode.rank = ((leftRank > rightRank) ? leftRank : rightRank) + 1;

        return newNode;
    }
}
