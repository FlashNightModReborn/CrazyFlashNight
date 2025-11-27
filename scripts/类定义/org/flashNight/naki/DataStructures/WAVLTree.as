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
        this.root = insert(this.root, element);
    }

    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        this.root = deleteNode(this.root, element);
        return (this.treeSize < oldSize);
    }

    public function contains(element:Object):Boolean {
        var current:WAVLNode = this.root;
        while (current != null) {
            var cmp:Number = this.compareFunction(element, current.value);
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

    private function insert(node:WAVLNode, element:Object):WAVLNode {
        if (node == null) {
            this.treeSize++;
            return new WAVLNode(element);  // 新叶子 rank=0
        }

        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            node.right = insert(node.right, element);
        } else {
            return node;  // 元素已存在
        }

        // 插入后平衡修复 - 内联优化版本
        var leftNode:WAVLNode = node.left;
        var rightNode:WAVLNode = node.right;
        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var leftDiff:Number = node.rank - leftRank;
        var rightDiff:Number = node.rank - rightRank;

        // 早退出：无 0-child，直接返回（最常见路径）
        if (leftDiff != 0 && rightDiff != 0) {
            return node;
        }

        // 情况1: (0,1) 或 (1,0) - 简单 promote
        if ((leftDiff == 0 && rightDiff == 1) || (leftDiff == 1 && rightDiff == 0)) {
            node.rank++;
            return node;
        }

        // 情况2: (0,2) - 左边是 0-child，需要旋转
        if (leftDiff == 0) {
            var llNode:WAVLNode = leftNode.left;
            var lrNode:WAVLNode = leftNode.right;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;
            var lrDiff:Number = leftNode.rank - lrRank;

            if (lrDiff == 2) {
                // Case: 左子是 (1,2) - 单右旋
                node.left = leftNode.right;
                leftNode.right = node;
                node.rank--;  // 原根 demote
                return leftNode;
            } else {
                // Case: 左子是 (2,1) - 双旋转 (LR)
                var pivot:WAVLNode = lrNode;
                leftNode.right = pivot.left;
                node.left = pivot.right;
                pivot.left = leftNode;
                pivot.right = node;
                pivot.rank++;       // pivot promote
                leftNode.rank--;    // 原左子 demote
                node.rank--;        // 原根 demote
                return pivot;
            }
        }

        // 情况3: (2,0) - 右边是 0-child，需要旋转
        if (rightDiff == 0) {
            var rlNode:WAVLNode = rightNode.left;
            var rrNode:WAVLNode = rightNode.right;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;
            var rlDiff:Number = rightNode.rank - rlRank;

            if (rlDiff == 2) {
                // Case: 右子是 (2,1) - 单左旋
                node.right = rightNode.left;
                rightNode.left = node;
                node.rank--;  // 原根 demote
                return rightNode;
            } else {
                // Case: 右子是 (1,2) - 双旋转 (RL)
                var pivot2:WAVLNode = rlNode;
                rightNode.left = pivot2.right;
                node.right = pivot2.left;
                pivot2.right = rightNode;
                pivot2.left = node;
                pivot2.rank++;      // pivot promote
                node.rank--;        // 原根 demote
                rightNode.rank--;   // 原右子 demote
                return pivot2;
            }
        }

        return node;
    }

    //======================== 删除操作 ========================//

    private function deleteNode(node:WAVLNode, element:Object):WAVLNode {
        if (node == null) {
            return null;
        }

        var cmp:Number = this.compareFunction(element, node.value);

        if (cmp < 0) {
            node.left = deleteNode(node.left, element);
        } else if (cmp > 0) {
            node.right = deleteNode(node.right, element);
        } else {
            // 找到要删除的节点
            var nodeLeft:WAVLNode = node.left;
            var nodeRight:WAVLNode = node.right;
            if (nodeLeft == null && nodeRight == null) {
                // 叶子节点：直接删除
                this.treeSize--;
                return null;
            } else if (nodeLeft == null) {
                // 只有右子节点
                this.treeSize--;
                return nodeRight;
            } else if (nodeRight == null) {
                // 只有左子节点
                this.treeSize--;
                return nodeLeft;
            } else {
                // 两个子节点：找后继值，然后统一用 deleteNode 删除
                var succ:WAVLNode = nodeRight;
                while (succ.left != null) succ = succ.left;
                var succValue:Object = succ.value;
                node.value = succValue;
                node.right = deleteNode(nodeRight, succValue);
            }
        }

        // 删除后平衡修复 - 全局部变量缓存版本
        var leftNode:WAVLNode = node.left;
        var rightNode:WAVLNode = node.right;

        // 叶子节点提前处理
        if (leftNode == null && rightNode == null) {
            if (node.rank > 0) node.rank = 0;
            return node;
        }

        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var leftDiff:Number = node.rank - leftRank;
        var rightDiff:Number = node.rank - rightRank;

        // 早退出：没有 3-child，不需要修复
        if (leftDiff <= 2 && rightDiff <= 2) {
            return node;
        }

        // 情况1: (3,1) - 左边是 3-child
        if (leftDiff == 3 && rightDiff == 1) {
            // 缓存所有参与节点
            var rlNode:WAVLNode = rightNode.left;
            var rrNode:WAVLNode = rightNode.right;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;
            var rrRank:Number = (rrNode != null) ? rrNode.rank : -1;
            var rlDiff:Number = rightNode.rank - rlRank;
            var rrDiff:Number = rightNode.rank - rrRank;

            if (rlDiff == 2 && rrDiff == 2) {
                // 右子是 (2,2)：双 demote
                node.rank--;
                rightNode.rank--;
                return node;
            }

            if (rrDiff == 1) {
                // 单左旋：缓存 rlNode 的子节点（如果需要）
                // node.right = rlNode 已在上面缓存
                node.right = rlNode;
                rightNode.left = node;
                rightNode.rank++;
                node.rank -= 2;
                // 检查叶子：此时 node.left 仍是原 leftNode(null)，node.right 是 rlNode
                if (leftNode == null && rlNode == null) node.rank = 0;
                return rightNode;
            }

            // 双旋转 (RL)：缓存 pivot 的子节点
            var pivotLeft:WAVLNode = rlNode.left;
            var pivotRight:WAVLNode = rlNode.right;
            rightNode.left = pivotRight;
            node.right = pivotLeft;
            rlNode.right = rightNode;
            rlNode.left = node;
            rlNode.rank += 2;
            node.rank -= 2;
            rightNode.rank--;
            // 检查叶子：node.left 是原 leftNode(null)，node.right 是 pivotLeft
            if (leftNode == null && pivotLeft == null) node.rank = 0;
            return rlNode;
        }

        // 情况2: (1,3) - 右边是 3-child
        if (leftDiff == 1 && rightDiff == 3) {
            // 缓存所有参与节点
            var llNode:WAVLNode = leftNode.left;
            var lrNode:WAVLNode = leftNode.right;
            var llRank:Number = (llNode != null) ? llNode.rank : -1;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;
            var llDiff:Number = leftNode.rank - llRank;
            var lrDiff:Number = leftNode.rank - lrRank;

            if (llDiff == 2 && lrDiff == 2) {
                // 左子是 (2,2)：双 demote
                node.rank--;
                leftNode.rank--;
                return node;
            }

            if (llDiff == 1) {
                // 单右旋
                node.left = lrNode;
                leftNode.right = node;
                leftNode.rank++;
                node.rank -= 2;
                // 检查叶子：node.right 仍是原 rightNode(null)，node.left 是 lrNode
                if (lrNode == null && rightNode == null) node.rank = 0;
                return leftNode;
            }

            // 双旋转 (LR)：缓存 pivot 的子节点
            var pivot2Left:WAVLNode = lrNode.left;
            var pivot2Right:WAVLNode = lrNode.right;
            leftNode.right = pivot2Left;
            node.left = pivot2Right;
            lrNode.left = leftNode;
            lrNode.right = node;
            lrNode.rank += 2;
            node.rank -= 2;
            leftNode.rank--;
            // 检查叶子：node.left 是 pivot2Right，node.right 是原 rightNode(null)
            if (pivot2Right == null && rightNode == null) node.rank = 0;
            return lrNode;
        }

        // 情况3: (3,2) - 单 demote
        if (leftDiff == 3) {
            node.rank--;
            return node;
        }

        // 情况4: (2,3) - 单 demote
        if (rightDiff == 3) {
            node.rank--;
            return node;
        }

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
