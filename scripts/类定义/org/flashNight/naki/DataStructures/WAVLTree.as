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

    // [优化1] cmpFn 作为参数传递，避免每次递归都查找 this.compareFunction
    private function deleteNode(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
        if (node == null) {
            this.__needRebalance = false;  // 没找到元素，不需要修复
            return null;
        }

        var cmp:Number = cmpFn(element, node.value);  // [优化1] 使用参数调用

        if (cmp < 0) {
            node.left = deleteNode(node.left, element, cmpFn);
            // 差分早退出：子树修复后 rank 未变化，不需要继续向上修复
            if (!this.__needRebalance) {
                return node;
            }
        } else if (cmp > 0) {
            node.right = deleteNode(node.right, element, cmpFn);
            // 差分早退出
            if (!this.__needRebalance) {
                return node;
            }
        } else {
            // 找到要删除的节点
            var nodeLeft:WAVLNode = node.left;
            var nodeRight:WAVLNode = node.right;
            if (nodeLeft == null && nodeRight == null) {
                // 叶子节点：直接删除
                this.treeSize--;
                this.__needRebalance = true;  // 删除叶子会影响父节点
                return null;
            } else if (nodeLeft == null) {
                // 只有右子节点
                this.treeSize--;
                this.__needRebalance = true;
                return nodeRight;
            } else if (nodeRight == null) {
                // 只有左子节点
                this.treeSize--;
                this.__needRebalance = true;
                return nodeLeft;
            } else {
                // 两个子节点：找后继值，然后统一用 deleteNode 删除
                var succ:WAVLNode = nodeRight;
                while (succ.left != null) succ = succ.left;
                var succValue:Object = succ.value;
                node.value = succValue;
                node.right = deleteNode(nodeRight, succValue, cmpFn);
                // 差分早退出
                if (!this.__needRebalance) {
                    return node;
                }
            }
        }

        // 删除后平衡修复 - 差分早退出版本
        var leftNode:WAVLNode = node.left;
        var rightNode:WAVLNode = node.right;
        var nodeRank:Number = node.rank;

        // 叶子节点提前处理
        if (leftNode == null && rightNode == null) {
            if (nodeRank > 0) {
                node.rank = 0;
                // rank 变化了，继续向上传播
            } else {
                this.__needRebalance = false;  // rank 本就是 0，无变化
            }
            return node;
        }

        var leftRank:Number = (leftNode != null) ? leftNode.rank : -1;
        var rightRank:Number = (rightNode != null) ? rightNode.rank : -1;
        var leftDiff:Number = nodeRank - leftRank;
        var rightDiff:Number = nodeRank - rightRank;

        // 早退出：没有 3-child，不需要修复
        if (leftDiff <= 2 && rightDiff <= 2) {
            this.__needRebalance = false;  // 本层无修复，停止向上传播
            return node;
        }

        // 情况1: (3,1) - 左边失衡，右边紧凑
        // 隐含条件：rightDiff == 1 意味着 rightNode 一定存在，无需判空
        if (leftDiff == 3 && rightDiff == 1) {
            var rightNodeRank:Number = rightNode.rank;

            // [优化] 先检查左孙子 (Right-Left)，如果是 RL 型旋转，就不需要读右孙子了
            var rlNode:WAVLNode = rightNode.left;
            var rlRank:Number = (rlNode != null) ? rlNode.rank : -1;
            var rlDiff:Number = rightNodeRank - rlRank;

            // Case: 右子是 (1, ?) -> 双旋转 (RL)
            // 只要 rlDiff 是 1，不论 rrDiff 是多少，都进行 RL 旋转
            if (rlDiff == 1) {
                var pivotLeft:WAVLNode = rlNode.left;
                var pivotRight:WAVLNode = rlNode.right;

                rightNode.left = pivotRight;
                node.right = pivotLeft;
                rlNode.right = rightNode;
                rlNode.left = node;

                rlNode.rank += 2;
                rightNode.rank = rightNodeRank - 1;
                node.rank = nodeRank - 2;

                // 边界修正：如果此时 node 变成了叶子，强制 rank 为 0
                if (leftNode == null && pivotLeft == null) {
                    node.rank = 0;
                }

                this.__needRebalance = false;
                return rlNode;
            }

            // [优化] 此时必须读取右孙子
            var rrNode:WAVLNode = rightNode.right;
            var rrRank:Number = (rrNode != null) ? rrNode.rank : -1;
            var rrDiff:Number = rightNodeRank - rrRank;

            // Case: 右子是 (?, 1) -> 单左旋
            if (rrDiff == 1) {
                node.right = rlNode;
                rightNode.left = node;
                rightNode.rank = rightNodeRank + 1;
                node.rank = nodeRank - 2;

                if (leftNode == null && rlNode == null) {
                    node.rank = 0;
                }

                this.__needRebalance = false;
                return rightNode;
            }

            // Case: 右子是 (2, 2) -> 双 Demote
            // 代码走到这里，说明 rlDiff != 1 且 rrDiff != 1。
            // 在 WAVL 规则下，非叶子节点只能是 (1,1), (1,2), (2,1), (2,2)。
            // 既然都不是 1，那只能都是 2。无需显式判断。
            node.rank = nodeRank - 1;
            rightNode.rank = rightNodeRank - 1;
            return node;
        }

        // 情况2: (1,3) - 左边紧凑，右边失衡
        // 隐含条件：leftDiff == 1 意味着 leftNode 一定存在
        if (leftDiff == 1 && rightDiff == 3) {
            var leftNodeRank:Number = leftNode.rank;

            // [优化] 先检查右孙子 (Left-Right)
            var lrNode:WAVLNode = leftNode.right;
            var lrRank:Number = (lrNode != null) ? lrNode.rank : -1;
            var lrDiff:Number = leftNodeRank - lrRank;

            // Case: 左子是 (?, 1) -> 双旋转 (LR)
            if (lrDiff == 1) {
                var pivot2Left:WAVLNode = lrNode.left;
                var pivot2Right:WAVLNode = lrNode.right;

                leftNode.right = pivot2Left;
                node.left = pivot2Right;
                lrNode.left = leftNode;
                lrNode.right = node;

                lrNode.rank += 2;
                leftNode.rank = leftNodeRank - 1;
                node.rank = nodeRank - 2;

                if (pivot2Right == null && rightNode == null) {
                    node.rank = 0;
                }

                this.__needRebalance = false;
                return lrNode;
            }

            // [优化] 读取左孙子
            var llNode:WAVLNode = leftNode.left;
            var llRank:Number = (llNode != null) ? llNode.rank : -1;
            var llDiff:Number = leftNodeRank - llRank;

            // Case: 左子是 (1, ?) -> 单右旋
            if (llDiff == 1) {
                node.left = lrNode;
                leftNode.right = node;
                leftNode.rank = leftNodeRank + 1;
                node.rank = nodeRank - 2;

                if (lrNode == null && rightNode == null) {
                    node.rank = 0;
                }

                this.__needRebalance = false;
                return leftNode;
            }

            // Case: 左子是 (2, 2) -> 双 Demote
            node.rank = nodeRank - 1;
            leftNode.rank = leftNodeRank - 1;
            return node;
        }

        // 情况3 & 4: 简单的 Demote
        // 只要有一边是 3，且不满足上述 (3,1) 或 (1,3)，说明另一边是 2
        // 即 (3,2) 或 (2,3) 情况
        if (leftDiff == 3 || rightDiff == 3) {
            node.rank = nodeRank - 1;
            return node;
        }

        this.__needRebalance = false;
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
