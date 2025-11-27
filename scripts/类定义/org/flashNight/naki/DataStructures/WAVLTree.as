import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;

/**
 * @class WAVLTree
 * @package org.flashNight.naki.DataStructures
 * @description 基于 WAVL (Weak AVL) 树实现的集合数据结构。
 *              WAVL树是AVL树的推广，具有以下特性：
 *              1. 保持AVL树的紧凑高度 (~1.44 log n)
 *              2. 插入和删除操作的摊还旋转次数为O(1)
 *              3. 使用rank差而非高度差来维护平衡
 *
 *              WAVL规则：
 *              - 每个节点与其子节点的rank差可以是1或2
 *              - 叶子节点的rank为0，外部节点(null)的rank为-1
 *              - 不允许出现(0,0)-节点（两个子节点的rank差都为0）
 *              - 不允许出现(2,2)-叶子（叶子节点不能是2,2节点）
 */
class org.flashNight.naki.DataStructures.WAVLTree {
    private var root:WAVLNode;           // 树的根节点
    private var compareFunction:Function; // 用于比较元素的函数
    private var treeSize:Number;          // 树中元素的数量

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较
     */
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

    /**
     * [静态方法] 从给定数组构建一个新的 WAVL 树
     * @param arr 输入的元素数组
     * @param compareFunction 用于排序的比较函数
     * @return 新构建的 WAVLTree 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):WAVLTree {
        var tree:WAVLTree = new WAVLTree(compareFunction);
        TimSort.sort(arr, compareFunction);
        tree.root = tree.buildBalancedTree(arr, 0, arr.length - 1);
        tree.treeSize = arr.length;
        return tree;
    }

    /**
     * 更换比较函数并重新排序建树
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        this.compareFunction = newCompareFunction;
        var arr:Array = this.toArray();
        TimSort.sort(arr, newCompareFunction);
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        this.treeSize = arr.length;
    }

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        this.root = insert(this.root, element);
    }

    /**
     * 移除元素
     * @param element 要移除的元素
     * @return 如果成功移除返回true
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        this.root = deleteNode(this.root, element);
        return (this.treeSize < oldSize);
    }

    /**
     * 检查树中是否包含某个元素
     * @param element 要检查的元素
     * @return 如果包含返回true
     */
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

    /**
     * 获取树大小
     * @return 树中元素的数量
     */
    public function size():Number {
        return this.treeSize;
    }

    /**
     * 中序遍历转换为数组
     * @return 按升序排列的元素数组
     */
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

    /**
     * 返回根节点
     */
    public function getRoot():WAVLNode {
        return this.root;
    }

    /**
     * 返回当前的比较函数
     */
    public function getCompareFunction():Function {
        return this.compareFunction;
    }

    /**
     * 返回树的字符串表示
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

    //======================== 私有辅助函数 ========================//

    /**
     * 计算节点与子节点的rank差
     * 外部节点(null)的rank定义为-1
     */
    private function rankDiff(parent:WAVLNode, child:WAVLNode):Number {
        var childRank:Number = (child != null) ? child.rank : -1;
        return parent.rank - childRank;
    }

    /**
     * 递归插入新元素
     * WAVL插入规则：
     * 1. 插入新叶子节点（rank=0）
     * 2. 如果产生0-child，需要promote或旋转
     */
    private function insert(node:WAVLNode, element:Object):WAVLNode {
        if (node == null) {
            this.treeSize++;
            return new WAVLNode(element);
        }

        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            node.right = insert(node.right, element);
        } else {
            // 元素已存在
            return node;
        }

        // 平衡修复
        return balanceAfterInsert(node);
    }

    /**
     * 插入后平衡修复
     * 检测0-child情况并修复
     */
    private function balanceAfterInsert(node:WAVLNode):WAVLNode {
        var leftNode:WAVLNode = node.left;
        var rightNode:WAVLNode = node.right;

        // 计算rank差
        var leftDiff:Number = node.rank - ((leftNode != null) ? leftNode.rank : -1);
        var rightDiff:Number = node.rank - ((rightNode != null) ? rightNode.rank : -1);

        // 检测是否有0-child（rank差为0）
        if (leftDiff == 0) {
            // 左子节点是0-child
            if (rightDiff == 1) {
                // (0,1)-节点：promote
                node.rank++;
            } else if (rightDiff == 2) {
                // (0,2)-节点：需要旋转
                // 检查左子节点的子节点rank差来决定旋转类型
                var llDiff:Number = leftNode.rank - ((leftNode.left != null) ? leftNode.left.rank : -1);
                var lrDiff:Number = leftNode.rank - ((leftNode.right != null) ? leftNode.right.rank : -1);

                if (llDiff == 1) {
                    // 左-左情况：单右旋 + demote
                    node = rotateRight(node);
                    node.right.rank--;  // demote原根节点
                } else {
                    // 左-右情况：双旋转
                    node.left = rotateLeft(leftNode);
                    node = rotateRight(node);
                    node.rank++;         // promote新根
                    node.left.rank--;    // demote左子
                    node.right.rank--;   // demote右子
                }
            }
        } else if (rightDiff == 0) {
            // 右子节点是0-child
            if (leftDiff == 1) {
                // (1,0)-节点：promote
                node.rank++;
            } else if (leftDiff == 2) {
                // (2,0)-节点：需要旋转
                var rlDiff:Number = rightNode.rank - ((rightNode.left != null) ? rightNode.left.rank : -1);
                var rrDiff:Number = rightNode.rank - ((rightNode.right != null) ? rightNode.right.rank : -1);

                if (rrDiff == 1) {
                    // 右-右情况：单左旋 + demote
                    node = rotateLeft(node);
                    node.left.rank--;   // demote原根节点
                } else {
                    // 右-左情况：双旋转
                    node.right = rotateRight(rightNode);
                    node = rotateLeft(node);
                    node.rank++;         // promote新根
                    node.left.rank--;    // demote左子
                    node.right.rank--;   // demote右子
                }
            }
        }

        return node;
    }

    /**
     * 递归删除元素
     */
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
            if (node.left == null || node.right == null) {
                // 0个或1个子节点
                this.treeSize--;
                var child:WAVLNode = (node.left != null) ? node.left : node.right;
                return child;  // 直接返回子节点，在上层处理平衡
            } else {
                // 2个子节点：找后继
                var successor:WAVLNode = node.right;
                while (successor.left != null) {
                    successor = successor.left;
                }
                node.value = successor.value;
                node.right = deleteNode(node.right, successor.value);
            }
        }

        // 如果节点被删空
        if (node == null) {
            return null;
        }

        // 平衡修复
        return balanceAfterDelete(node);
    }

    /**
     * 删除后平衡修复
     * 检测3-child情况并修复
     */
    private function balanceAfterDelete(node:WAVLNode):WAVLNode {
        var leftNode:WAVLNode = node.left;
        var rightNode:WAVLNode = node.right;

        var leftDiff:Number = node.rank - ((leftNode != null) ? leftNode.rank : -1);
        var rightDiff:Number = node.rank - ((rightNode != null) ? rightNode.rank : -1);

        // 检测3-child（rank差为3）
        if (leftDiff == 3) {
            // 左边是3-child
            if (rightDiff == 2) {
                // (3,2)-节点：demote
                node.rank--;
            } else if (rightDiff == 1) {
                // (3,1)-节点：需要旋转
                // 检查右子节点的子节点
                var rlDiff:Number = rightNode.rank - ((rightNode.left != null) ? rightNode.left.rank : -1);
                var rrDiff:Number = rightNode.rank - ((rightNode.right != null) ? rightNode.right.rank : -1);

                if (rrDiff == 1) {
                    // 单左旋
                    node = rotateLeft(node);
                    node.left.rank--;    // demote原根
                    node.rank++;         // promote新根
                } else if (rlDiff == 1 && rrDiff == 2) {
                    // 双旋转
                    node.right = rotateRight(rightNode);
                    node = rotateLeft(node);
                    node.rank += 2;      // 双promote新根
                    node.left.rank--;    // demote左子
                    node.right.rank--;   // demote右子
                } else {
                    // (2,2) 情况：demote + demote右子
                    node.rank--;
                    rightNode.rank--;
                }
            }
        } else if (rightDiff == 3) {
            // 右边是3-child
            if (leftDiff == 2) {
                // (2,3)-节点：demote
                node.rank--;
            } else if (leftDiff == 1) {
                // (1,3)-节点：需要旋转
                var llDiff:Number = leftNode.rank - ((leftNode.left != null) ? leftNode.left.rank : -1);
                var lrDiff:Number = leftNode.rank - ((leftNode.right != null) ? leftNode.right.rank : -1);

                if (llDiff == 1) {
                    // 单右旋
                    node = rotateRight(node);
                    node.right.rank--;   // demote原根
                    node.rank++;         // promote新根
                } else if (lrDiff == 1 && llDiff == 2) {
                    // 双旋转
                    node.left = rotateLeft(leftNode);
                    node = rotateRight(node);
                    node.rank += 2;      // 双promote新根
                    node.left.rank--;    // demote左子
                    node.right.rank--;   // demote右子
                } else {
                    // (2,2) 情况：demote + demote左子
                    node.rank--;
                    leftNode.rank--;
                }
            }
        }

        // 检查是否为(2,2)-叶子，需要demote
        if (leftNode == null && rightNode == null && node.rank > 0) {
            node.rank = 0;
        }

        return node;
    }

    /**
     * 左旋转
     */
    private function rotateLeft(node:WAVLNode):WAVLNode {
        var rightNode:WAVLNode = node.right;
        node.right = rightNode.left;
        rightNode.left = node;
        return rightNode;
    }

    /**
     * 右旋转
     */
    private function rotateRight(node:WAVLNode):WAVLNode {
        var leftNode:WAVLNode = node.left;
        node.left = leftNode.right;
        leftNode.right = node;
        return leftNode;
    }

    /**
     * 从已排序数组构建平衡树
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):WAVLNode {
        if (start > end) {
            return null;
        }

        var mid:Number = (start + end) >> 1;
        var newNode:WAVLNode = new WAVLNode(sortedArr[mid]);

        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 计算rank：基于子节点的rank
        var leftRank:Number = (newNode.left != null) ? newNode.left.rank : -1;
        var rightRank:Number = (newNode.right != null) ? newNode.right.rank : -1;
        // 取较大的子节点rank + 1
        newNode.rank = ((leftRank > rightRank) ? leftRank : rightRank) + 1;

        return newNode;
    }
}
