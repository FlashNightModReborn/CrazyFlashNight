import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;


/**
 * @class TreeSet
 * @package org.flashNight.naki.DataStructures
 * @description 基于 AVL 树实现的集合数据结构，支持高效的插入、删除、搜索和遍历操作。
 */
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
            // 默认的比较函数，适用于可比较的基本类型（如数字、字符串）
            this.compareFunction = function(a, b):Number {
                return (a < b) ? -1 : ((a > b) ? 1 : 0);
            };
        } else {
            // 用户自定义的比较函数，允许根据特定需求排序
            this.compareFunction = compareFunction;
        }
        this.root = null; // 初始化根节点为空
        this.treeSize = 0; // 初始化树的大小为0
    }

    /**
     * [静态方法] 从给定数组构建一个新的平衡 AVL 树（TreeSet）。
     *   1. 先对输入数组排序
     *   2. 使用分治法一次性构建平衡树，避免逐个插入导致的大量旋转
     * @param arr 输入的元素数组，需为可排序的类型
     * @param compareFunction 用于排序的比较函数
     * @return 新构建的 TreeSet 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):TreeSet {
        var treeSet:TreeSet = new TreeSet(compareFunction);
        // 使用 TimSort 排序输入数组，确保数组有序以便分治法构建平衡树
        TimSort.sort(arr, compareFunction);
        // 使用分治法构建平衡 AVL 树
        treeSet.root = treeSet.buildBalancedTree(arr, 0, arr.length - 1);
        // 设置树的大小为数组长度
        treeSet.treeSize = arr.length;
        return treeSet;
    }

    /**
     * [实例方法] 更换当前 TreeSet 的比较函数，并对所有数据重新排序和建树。
     * 适用于需要动态更改排序规则的场景。
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        // 1. 更新比较函数
        this.compareFunction = newCompareFunction;

        // 2. 导出所有节点到数组，准备重新排序
        var arr:Array = this.toArray();

        // 3. 使用新的比较函数对数组进行排序
        TimSort.sort(arr, newCompareFunction);

        // 4. 使用分治法重建平衡 AVL 树
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
     * @return 如果成功移除元素则返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        this.root = deleteNode(this.root, element);
        return (this.treeSize < oldSize);
    }

    /**
     * 检查树中是否包含某个元素
     * @param element 要检查的元素
     * @return 如果树中包含该元素则返回 true，否则返回 false
     */
    public function contains(element:Object):Boolean {
        var node:TreeNode = search(this.root, element);
        return (node != null);
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
     * @return 一个按升序排列的元素数组
     */
    public function toArray():Array {
        var arr:Array = [];                // 存储遍历结果
        var stack:Array = [];              // 模拟堆栈
        var index:Number = 0;              // 堆栈索引
        var node:TreeNode = this.root;     // 当前节点

        while (node != null || index > 0) {
            // 模拟递归，处理左子树
            while (node != null) {
                stack[index++] = node;     // 将当前节点压入堆栈
                node = node.left;          // 移动到左子树
            }

            // 取出堆栈中的节点
            node = stack[--index];         // 弹出栈顶节点
            arr[arr.length] = node.value;  // 访问当前节点值

            // 移动到右子树继续处理
            node = node.right;
        }

        return arr;
    }


    /**
     * 返回根节点
     * @return 树的根节点
     */
    public function getRoot():TreeNode {
        return this.root;
    }

    /**
     * 返回当前的比较函数
     * @return 当前使用的比较函数
     */
    public function getCompareFunction():Function {
        return this.compareFunction;
    }

    /**
     * 返回 AVL 树的字符串表示，基于前序遍历
     * @return 树的前序遍历字符串
     */
    public function toString():String {
        var str:String = "";
        var stack:Array = [];    // 模拟堆栈
        var index:Number = 0;    // 堆栈索引
        var node:TreeNode = this.root; // 当前节点

        while (node != null || index > 0) {
            // 遍历左子树，同时将右子节点压入堆栈
            while (node != null) {
                str += node.toString() + " "; // 访问当前节点
                stack[index++] = node.right;   // 压入右子节点
                node = node.left;              // 移动到左子节点
            }

            // 弹出堆栈中的下一个节点
            if (index > 0) {
                node = stack[--index];
            }
        }

        return StringUtils.trim(str); // 去除末尾的空格
    }

    //======================== 私有辅助函数 ========================//

    /**
     * 递归插入新元素，并保持 AVL 平衡（差分高度更新）
     * @param node 当前递归到的节点
     * @param element 要插入的元素
     * @return 插入后的节点
     */
    private function insert(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            // 找到插入位置，创建新节点
            this.treeSize++;
            return new TreeNode(element);
        }

        // 1. 递归插入
        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            // 元素小于当前节点，递归插入左子树
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            // 元素大于当前节点，递归插入右子树
            node.right = insert(node.right, element);
        } else {
            // 元素已存在，直接返回当前节点
            return node;
        }

        // 2. 更新高度前，记录旧高度
        var oldHeight:Number = node.height;

        // 3. 计算左右子树高度并更新当前节点高度
        var leftNode:TreeNode   = node.left;
        var rightNode:TreeNode  = node.right;
        var leftHeight:Number   = (leftNode != null) ? leftNode.height : 0;
        var rightHeight:Number  = (rightNode != null) ? rightNode.height : 0;
        var newHeight:Number    = (leftHeight > rightHeight) ? leftHeight : rightHeight;

        // ------------------- 差分高度更新的关键：早退出 -------------------
        if (++newHeight == oldHeight) {
            // 如果高度没有变化，不必继续回溯，也不用检查平衡
            return node;
        }

        // 更新节点高度
        node.height = newHeight;

        // 4. 检查平衡因子并作旋转
        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            // 左侧高，需要判断是 LL 型还是 LR 型
            var childLeftNode:TreeNode   = leftNode.left;
            var childRightNode:TreeNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;

            // 根据子树平衡因子决定旋转类型
            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高，需要判断是 RR 型还是 RL 型
            var rLeftNode:TreeNode       = rightNode.left;
            var rRightNode:TreeNode      = rightNode.right;
            var rLeftHeight:Number       = (rLeftNode  != null) ? rLeftNode.height  : 0;
            var rRightHeight:Number      = (rRightNode != null) ? rRightNode.height : 0;
            var rightBalance:Number      = rLeftHeight - rRightHeight;

            // 根据子树平衡因子决定旋转类型
            node = rightBalance <= 0 ? rotateRR(node) : rotateRL(node);
        }

        return node;
    }

    /**
     * 递归删除元素，并保持 AVL 平衡（差分高度更新）
     * @param node 当前递归到的节点
     * @param element 要删除的元素
     * @return 删除后的节点
     */
    private function deleteNode(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            // 元素不存在于树中，直接返回 null
            return null;
        }

        // 1. 递归删除
        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            // 元素小于当前节点，递归删除左子树
            node.left = deleteNode(node.left, element);
        } else if (cmp > 0) {
            // 元素大于当前节点，递归删除右子树
            node.right = deleteNode(node.right, element);
        } else {
            // 找到要删除的节点
            if (node.left == null || node.right == null) {
                // 处理无子节点或单子节点情况
                this.treeSize--;
                node = (node.left != null) ? node.left : node.right;
            } else {
                // 处理双子节点情况
                var temp:TreeNode = node.right;
                while (temp.left != null) {
                    temp = temp.left;
                }
                node.value = temp.value;
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
        var newHeight:Number    = (leftHeight > rightHeight) ? leftHeight : rightHeight;

        // ------------------- 差分高度更新的关键：早退出 -------------------
        if (++newHeight == oldHeight) {
            // 高度没变，不必再检查平衡
            return node;
        }

        // 更新节点高度
        node.height = newHeight;

        // 5. 重新检查平衡
        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            // 左侧高，需要判断是 LL 型还是 LR 型
            var childLeftNode:TreeNode   = leftNode.left;
            var childRightNode:TreeNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;

            // 根据子树平衡因子决定旋转类型
            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高，需要判断是 RR 型还是 RL 型
            var rLeftNode:TreeNode       = rightNode.left;
            var rRightNode:TreeNode      = rightNode.right;
            var rLeftHeight:Number       = (rLeftNode  != null) ? rLeftNode.height  : 0;
            var rRightHeight:Number      = (rRightNode != null) ? rRightNode.height : 0;
            var rightBalance:Number      = rLeftHeight - rRightHeight;

            // 根据子树平衡因子决定旋转类型
            node = rightBalance <= 0 ? rotateRR(node) : rotateRL(node);
        }

        return node;
    }

    /**
     * 在树中搜索指定元素
     * @param node 当前递归到的节点
     * @param element 要搜索的元素
     * @return 如果找到元素则返回对应的节点，否则返回 null
     */
    private function search(node:TreeNode, element:Object):TreeNode {
        var current:TreeNode = node;
        while (current != null) {
            var cmp:Number = this.compareFunction(element, current.value);
            if (cmp < 0) {
                // 元素小于当前节点，向左子树搜索
                current = current.left;
            } else if (cmp > 0) {
                // 元素大于当前节点，向右子树搜索
                current = current.right;
            } else {
                // 找到元素，返回当前节点
                return current;
            }
        }
        // 未找到元素
        return null;
    }

    /**
     * 中序遍历，将节点依次添加到数组 arr 中
     * @param node 当前递归到的节点
     * @param arr 存储遍历结果的数组
     */
    private function inOrderTraversal(node:TreeNode, arr:Array):Void {
        if (node != null) {
            // 先遍历左子树
            inOrderTraversal(node.left, arr);
            // 访问当前节点
            arr[arr.length] = node.value;
            // 再遍历右子树
            inOrderTraversal(node.right, arr);
        }
    }

    /**
     * [辅助函数] 使用分治法，从已排序数组中构建平衡 AVL 树
     * @param sortedArr 已排序的元素数组
     * @param start 构建子树的起始索引
     * @param end 构建子树的结束索引
     * @return 构建好的子树根节点
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):TreeNode {
        if (start > end) {
            // 子数组为空，返回 null
            return null;
        }
        // 选择中间元素作为当前子树的根节点，确保平衡
        var mid:Number = (start + end) >> 1; // 等同于 Math.floor((start + end) / 2)
        var newNode:TreeNode = new TreeNode(sortedArr[mid]);

        // 递归构建左子树和右子树
        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 更新当前节点的高度，根据左右子树高度决定
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
     * @param node 失衡的节点
     * @return 右旋后的新根节点
     */
    private function rotateLL(node:TreeNode):TreeNode {
        var leftNode:TreeNode = node.left;
        // 右旋操作
        node.left = leftNode.right;
        leftNode.right = node;

        // 局部化变量以减少属性解引用，提高访问速度
        var nodeLeft:TreeNode = node.left;
        var nodeRight:TreeNode = node.right; // 右旋后，node.right 即为 leftNode.right => node
        var leftLeft:TreeNode = leftNode.left;
        var leftRight:TreeNode = leftNode.right;

        // 更新 node 的高度
        var leftH:Number = (nodeLeft != null) ? nodeLeft.height : 0;
        var rightH:Number = (nodeRight != null) ? nodeRight.height : 0;
        node.height = 1 + ((leftH > rightH) ? leftH : rightH);

        // 更新 leftNode 的高度
        var leftNodeLeftH:Number = (leftLeft != null) ? leftLeft.height : 0;
        var leftNodeRightH:Number = (leftRight != null) ? leftRight.height : 0;
        leftNode.height = 1 + ((leftNodeLeftH > node.height) ? leftNodeLeftH : node.height);

        return leftNode;
    }

    /**
     * 处理 RR 型失衡：对 node 进行左旋
     * (因为 node.right 子树高度过高，且 node.right.right 也更高)
     * @param node 失衡的节点
     * @return 左旋后的新根节点
     */
    private function rotateRR(node:TreeNode):TreeNode {
        var rightNode:TreeNode = node.right;
        // 左旋操作
        node.right = rightNode.left;
        rightNode.left = node;

        // 局部化变量以减少属性解引用，提高访问速度
        var nodeLeft:TreeNode = node.left;
        var nodeRight:TreeNode = node.right; // 左旋后，node.right 即为 rightNode.left => node
        var rightLeft:TreeNode = rightNode.left;
        var rightRight:TreeNode = rightNode.right;

        // 更新 node 的高度
        var leftH:Number = (nodeLeft != null) ? nodeLeft.height : 0;
        var rightH:Number = (nodeRight != null) ? nodeRight.height : 0;
        node.height = 1 + ((leftH > rightH) ? leftH : rightH);

        // 更新 rightNode 的高度
        var rightNodeLeftH:Number = (rightLeft != null) ? rightLeft.height : 0;
        var rightNodeRightH:Number = (rightRight != null) ? rightRight.height : 0;
        rightNode.height = 1 + ((node.height > rightNodeRightH) ? node.height : rightNodeRightH);

        return rightNode;
    }

    /**
     * 处理 LR 型失衡：先对 node.left 进行左旋，再对 node 进行右旋
     * @param node 失衡的节点
     * @return 旋转后的新根节点
     */
    private function rotateLR(node:TreeNode):TreeNode {
        // 先对左子树做 RR 旋转
        node.left = rotateRR(node.left);
        // 再对当前节点做 LL 旋转
        return rotateLL(node);
    }

    /**
     * 处理 RL 型失衡：先对 node.right 进行右旋，再对 node 进行左旋
     * @param node 失衡的节点
     * @return 旋转后的新根节点
     */
    private function rotateRL(node:TreeNode):TreeNode {
        // 先对右子树做 LL 旋转
        node.right = rotateLL(node.right);
        // 再对当前节点做 RR 旋转
        return rotateRR(node);
    }
}
