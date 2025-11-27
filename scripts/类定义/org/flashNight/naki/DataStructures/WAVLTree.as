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

    /**
     * 删除子树中的最小节点，并将其值写入 target 节点
     * 返回删除最小节点后经过平衡的子树根
     */
    private function deleteMinAndGetValue(node:WAVLNode, target:WAVLNode):WAVLNode {
        // 递归找到最左节点
        if (node.left == null) {
            // 找到最小节点，将值写入 target
            target.value = node.value;
            this.treeSize--;
            return node.right;  // 返回右子树（可能为 null）
        }

        // 继续向左递归
        node.left = deleteMinAndGetValue(node.left, target);

        // 删除后平衡修复（复用 deleteNode 的平衡逻辑）
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

        // 早退出：没有 3-child
        if (leftDiff <= 2 && rightDiff <= 2) {
            return node;
        }

        // (3,1) - 左边是 3-child（deleteMin 后最常见情况）
        if (leftDiff == 3 && rightDiff == 1) {
            var rlNode:WAVLNode = rightNode.left;
            var rrNode:WAVLNode = rightNode.right;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;
            var rrRank:Number = (rrNode != null) ? rrNode.rank : -1;
            var rlDiff:Number = rightNode.rank - rlRank;
            var rrDiff:Number = rightNode.rank - rrRank;

            if (rlDiff == 2 && rrDiff == 2) {
                node.rank--;
                rightNode.rank--;
            } else if (rrDiff == 1) {
                node.right = rlNode;
                rightNode.left = node;
                rightNode.rank++;
                node.rank -= 2;
                if (node.left == null && node.right == null) {
                    node.rank = 0;
                }
                return rightNode;
            } else {
                var pivot:WAVLNode = rlNode;
                rightNode.left = pivot.right;
                node.right = pivot.left;
                pivot.right = rightNode;
                pivot.left = node;
                pivot.rank += 2;
                node.rank -= 2;
                rightNode.rank--;
                if (node.left == null && node.right == null) {
                    node.rank = 0;
                }
                return pivot;
            }
            return node;
        }

        // (3,2) - 单 demote
        if (leftDiff == 3) {
            node.rank--;
            return node;
        }

        // (1,3) 和 (2,3) 在 deleteMin 路径上不太可能出现，但保留兜底
        if (rightDiff == 3) {
            node.rank--;
        }

        return node;
    }

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
                // 两个子节点：找后继并删除，用栈记录路径避免二次搜索
                node.right = deleteMinAndGetValue(nodeRight, node);
            }
        }

        // 删除后平衡修复 - 内联优化版本
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
            } else if (rrDiff == 1) {
                // 右子的右子是 1-child：单左旋（内联）
                node.right = rlNode;
                rightNode.left = node;
                rightNode.rank++;    // 新根 promote
                node.rank -= 2;      // 原根 双 demote
                // 检查原根是否变成叶子
                if (node.left == null && node.right == null) {
                    node.rank = 0;
                }
                return rightNode;
            } else {
                // rlDiff == 1：双旋转 (RL) - 内联
                var pivot:WAVLNode = rlNode;
                rightNode.left = pivot.right;
                node.right = pivot.left;
                pivot.right = rightNode;
                pivot.left = node;
                pivot.rank += 2;     // 新根 双 promote
                node.rank -= 2;      // 原根 双 demote
                rightNode.rank--;    // 原右子 demote
                // 检查原根是否变成叶子
                if (node.left == null && node.right == null) {
                    node.rank = 0;
                }
                return pivot;
            }
            return node;
        }

        // 情况2: (1,3) - 右边是 3-child
        if (leftDiff == 1 && rightDiff == 3) {
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
            } else if (llDiff == 1) {
                // 左子的左子是 1-child：单右旋（内联）
                node.left = lrNode;
                leftNode.right = node;
                leftNode.rank++;     // 新根 promote
                node.rank -= 2;      // 原根 双 demote
                // 检查原根是否变成叶子
                if (node.left == null && node.right == null) {
                    node.rank = 0;
                }
                return leftNode;
            } else {
                // lrDiff == 1：双旋转 (LR) - 内联
                var pivot2:WAVLNode = lrNode;
                leftNode.right = pivot2.left;
                node.left = pivot2.right;
                pivot2.left = leftNode;
                pivot2.right = node;
                pivot2.rank += 2;    // 新根 双 promote
                node.rank -= 2;      // 原根 双 demote
                leftNode.rank--;     // 原左子 demote
                // 检查原根是否变成叶子
                if (node.left == null && node.right == null) {
                    node.rank = 0;
                }
                return pivot2;
            }
            return node;
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
