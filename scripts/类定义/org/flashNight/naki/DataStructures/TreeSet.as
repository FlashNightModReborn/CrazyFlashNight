import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;

class org.flashNight.naki.DataStructures.TreeSet {
    private var root:TreeNode; // 树的根节点
    private var compareFunction:Function; // 用于比较元素的函数
    private var treeSize:Number; // 树中元素的数量

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较
     */
    public function TreeSet(compareFunction:Function) {
        if (compareFunction == undefined || compareFunction == null) {
            // 默认的比较函数
            this.compareFunction = function(a, b):Number {
                if (a < b)
                    return -1;
                if (a > b)
                    return 1;
                return 0;
            };
        } else {
            this.compareFunction = compareFunction;
        }
        this.root = null;
        this.treeSize = 0;
    }

    /**
     * [静态方法] 从给定数组构建一个新的平衡 AVL 树（TreeSet）。
     *   1. 先对输入数组排序
     *   2. 使用分治法一次性构建平衡树，避免逐个插入导致的大量旋转
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):TreeSet {
        var treeSet:TreeSet = new TreeSet(compareFunction);
        PDQSort.sort(arr, compareFunction);
        treeSet.root = treeSet.buildBalancedTree(arr, 0, arr.length - 1);
        treeSet.treeSize = arr.length;
        return treeSet;
    }

    /**
     * [实例方法] 更换当前 TreeSet 的比较函数，并对所有数据重新排序和建树。
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        // 1. 更新比较函数
        this.compareFunction = newCompareFunction;

        // 2. 导出所有节点到数组
        var arr:Array = this.toArray();

        // 3. 排序
        PDQSort.sort(arr, newCompareFunction);

        // 4. 重建平衡AVL
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        this.treeSize = arr.length;
    }

    /**
     * 添加元素到树中
     */
    public function add(element:Object):Void {
        this.root = insert(this.root, element);
    }

    /**
     * 移除元素
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        this.root = deleteNode(this.root, element);
        return (this.treeSize < oldSize);
    }

    /**
     * 检查树中是否包含某个元素
     */
    public function contains(element:Object):Boolean {
        var node:TreeNode = search(this.root, element);
        return (node != null);
    }

    /**
     * 获取树大小
     */
    public function size():Number {
        return this.treeSize;
    }

    /**
     * 中序遍历转换为数组
     */
    public function toArray():Array {
        var arr:Array = [];
        inOrderTraversal(this.root, arr);
        return arr;
    }

    /**
     * 返回根节点
     */
    public function getRoot():TreeNode {
        return this.root;
    }

    /**
     * 返回当前的比较函数
     */
    public function getCompareFunction():Function {
        return this.compareFunction;
    }

    //======================== 私有辅助函数 ========================//

    /**
    * 递归插入新元素，并保持AVL平衡（差分高度更新）
    */
    private function insert(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            this.treeSize++;
            return new TreeNode(element);
        }

        // 1. 递归插入
        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            node.right = insert(node.right, element);
        } else {
            // 已存在，直接返回
            return node;
        }

        // 2. 更新高度前，记录旧高度
        var oldHeight:Number = node.height;

        // 3. 计算左右子树高度并更新当前节点高度
        var leftNode:TreeNode   = node.left;
        var rightNode:TreeNode  = node.right;
        var leftHeight:Number   = (leftNode != null) ? leftNode.height : 0;
        var rightHeight:Number  = (rightNode != null) ? rightNode.height : 0;
        node.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        // ------------------- 差分高度更新的关键：早退出 -------------------
        if (node.height == oldHeight) {
            // 如果高度没有变化，不必继续回溯，也不用检查平衡
            return node;
        }

        // 4. 检查平衡因子并作旋转
        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            // 左侧高: 判断是 LL 还是 LR
            var childLeftNode:TreeNode   = leftNode.left;
            var childRightNode:TreeNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;

            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高: 判断是 RR 还是 RL
            var rLeftNode:TreeNode       = rightNode.left;
            var rRightNode:TreeNode      = rightNode.right;
            var rLeftHeight:Number       = (rLeftNode  != null) ? rLeftNode.height  : 0;
            var rRightHeight:Number      = (rRightNode != null) ? rRightNode.height : 0;
            var rightBalance:Number      = rLeftHeight - rRightHeight;

            node = rightBalance <= 0 ? rotateRR(node) : rotateRL(node);
        }

        return node;
    }

    /**
    * 递归删除元素，并保持AVL平衡（差分高度更新）
    */
    private function deleteNode(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            return null;
        }

        // 1. 递归删除
        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = deleteNode(node.left, element);
        } else if (cmp > 0) {
            node.right = deleteNode(node.right, element);
        } else {
            // 找到要删除的节点
            this.treeSize--;
            // 1. 无子节点 or 单子节点
            if (node.left == null || node.right == null) {
                node = (node.left != null) ? node.left : node.right;
            } else {
                // 2. 有两个子节点：寻找中序后继（右子树最左侧节点）
                var temp:TreeNode = node.right;
                while (temp.left != null) {
                    temp = temp.left;
                }
                // 用后继的值覆盖当前节点
                node.value = temp.value;
                // 删除后继节点
                node.right = deleteNode(node.right, temp.value);
            }
        }

        // 2. 如果当前子树已被删空，无需再平衡
        if (node == null) {
            return null;
        }

        // 3. 更新高度前，记录旧高度
        var oldHeight:Number = node.height;

        // 4. 计算左右子树高度并更新当前节点高度
        var leftNode:TreeNode   = node.left;
        var rightNode:TreeNode  = node.right;
        var leftHeight:Number   = (leftNode != null) ? leftNode.height : 0;
        var rightHeight:Number  = (rightNode != null) ? rightNode.height : 0;
        node.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        // ------------------- 差分高度更新的关键：早退出 -------------------
        if (node.height == oldHeight) {
            // 高度没变，不必再检查平衡
            return node;
        }

        // 5. 重新检查平衡
        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            // 左侧高
            var childLeftNode:TreeNode   = leftNode.left;
            var childRightNode:TreeNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;

            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高
            var rLeftNode:TreeNode       = rightNode.left;
            var rRightNode:TreeNode      = rightNode.right;
            var rLeftHeight:Number       = (rLeftNode  != null) ? rLeftNode.height  : 0;
            var rRightHeight:Number      = (rRightNode != null) ? rRightNode.height : 0;
            var rightBalance:Number      = rLeftHeight - rRightHeight;

            node = rightBalance <= 0 ? rotateRR(node) : rotateRL(node);
        }

        return node;
    }


    /**
     * 在树中搜索指定元素
     */
    private function search(node:TreeNode, element:Object):TreeNode {
        var current:TreeNode = node;
        while (current != null) {
            var cmp:Number = this.compareFunction(element, current.value);
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
     * 中序遍历，将节点依次添加到数组 arr 中
     */
    private function inOrderTraversal(node:TreeNode, arr:Array):Void {
        if (node != null) {
            inOrderTraversal(node.left, arr);
            arr.push(node.value);
            inOrderTraversal(node.right, arr);
        }
    }

    /**
     * [辅助函数] 使用分治法，从已排序数组中构建平衡 AVL
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):TreeNode {
        if (start > end) {
            return null;
        }
        var mid:Number = (start + end) >> 1;
        var newNode:TreeNode = new TreeNode(sortedArr[mid]);

        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 更新高度
        var leftNode:TreeNode = newNode.left;
        var rightNode:TreeNode = newNode.right;
        var leftHeight:Number = (leftNode != null) ? leftNode.height : 0;
        var rightHeight:Number = (rightNode != null) ? rightNode.height : 0;
        newNode.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        return newNode;
    }

    //======================== 旋转函数：LL, LR, RR, RL ========================//

    /**
     * 处理 LL 型失衡：对 node 进行右旋
     * (因为 node.left 子树高度过高，且 node.left.left 也更高)
     */
    private function rotateLL(node:TreeNode):TreeNode {
        var leftNode:TreeNode = node.left;
        // 右旋
        node.left = leftNode.right;
        leftNode.right = node;

        // 局部化变量以减少属性解引用
        var nodeLeft:TreeNode = node.left;
        var nodeRight:TreeNode = node.right; // 这里其实就是 leftNode.right => node
        var leftLeft:TreeNode = leftNode.left;
        var leftRight:TreeNode = leftNode.right;

        // 更新 node 高度
        var leftH:Number = (nodeLeft != null) ? nodeLeft.height : 0;
        var rightH:Number = (nodeRight != null) ? nodeRight.height : 0;
        node.height = 1 + ((leftH > rightH) ? leftH : rightH);

        // 更新 leftNode 高度
        var leftNodeLeftH:Number = (leftLeft != null) ? leftLeft.height : 0;
        var leftNodeRightH:Number = (leftRight != null) ? leftRight.height : 0;
        leftNode.height = 1 + ((leftNodeLeftH > node.height) ? leftNodeLeftH : node.height);

        return leftNode;
    }

    /**
     * 处理 RR 型失衡：对 node 进行左旋
     * (因为 node.right 子树高度过高，且 node.right.right 也更高)
     */
    private function rotateRR(node:TreeNode):TreeNode {
        var rightNode:TreeNode = node.right;
        // 左旋
        node.right = rightNode.left;
        rightNode.left = node;

        // 局部化变量
        var nodeLeft:TreeNode = node.left;
        var nodeRight:TreeNode = node.right; // rightNode.left => node
        var rightLeft:TreeNode = rightNode.left;
        var rightRight:TreeNode = rightNode.right;

        // 更新 node 高度
        var leftH:Number = (nodeLeft != null) ? nodeLeft.height : 0;
        var rightH:Number = (nodeRight != null) ? nodeRight.height : 0;
        node.height = 1 + ((leftH > rightH) ? leftH : rightH);

        // 更新 rightNode 高度
        var rightNodeLeftH:Number = (rightLeft != null) ? rightLeft.height : 0;
        var rightNodeRightH:Number = (rightRight != null) ? rightRight.height : 0;
        rightNode.height = 1 + ((node.height > rightNodeRightH) ? node.height : rightNodeRightH);

        return rightNode;
    }

    /**
     * 处理 LR 型失衡：先对 node.left 进行左旋，再对 node 进行右旋
     */
    private function rotateLR(node:TreeNode):TreeNode {
        // 先对左子树做 RR 旋转
        node.left = rotateRR(node.left);
        // 再对自己做 LL 旋转
        return rotateLL(node);
    }

    /**
     * 处理 RL 型失衡：先对 node.right 进行右旋，再对 node 进行左旋
     */
    private function rotateRL(node:TreeNode):TreeNode {
        // 先对右子树做 LL 旋转
        node.right = rotateLL(node.right);
        // 再对自己做 RR 旋转
        return rotateRR(node);
    }
}

