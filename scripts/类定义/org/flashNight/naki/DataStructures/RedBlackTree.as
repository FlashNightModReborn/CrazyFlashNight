import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;

/**
 * @class RedBlackTree
 * @package org.flashNight.naki.DataStructures
 * @description 基于红黑树实现的集合数据结构，支持高效的插入、删除、搜索和遍历操作。
 */
class org.flashNight.naki.DataStructures.RedBlackTree {
    private var root:RedBlackNode; // 树的根节点
    private var compareFunction:Function; // 用于比较元素的函数
    private var treeSize:Number; // 树中元素的数量
    
    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较
     */
    public function RedBlackTree(compareFunction:Function) {
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
     * [静态方法] 从给定数组构建一个新的红黑树。
     *   1. 先对输入数组排序
     *   2. 逐个将元素添加到树中，使用标准的添加方法确保红黑树性质
     * @param arr 输入的元素数组，需为可排序的类型
     * @param compareFunction 用于排序的比较函数
     * @return 新构建的 RedBlackTree 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):RedBlackTree {
        var rbTree:RedBlackTree = new RedBlackTree(compareFunction);
        
        // 使用 TimSort 排序输入数组
        TimSort.sort(arr, compareFunction);
        
        // 去除重复元素（可选）
        var uniqueArr:Array = [];
        if (arr.length > 0) {
            uniqueArr.push(arr[0]);
            for (var i:Number = 1; i < arr.length; i++) {
                if (compareFunction(arr[i], arr[i-1]) != 0) {
                    uniqueArr.push(arr[i]);
                }
            }
        }
        
        // 逐个添加元素，使用标准的添加方法确保红黑树性质
        for (i = 0; i < uniqueArr.length; i++) {
            rbTree.add(uniqueArr[i]);
        }
        
        return rbTree;
    }

    /**
     * [实例方法] 更换当前 RedBlackTree 的比较函数，并对所有数据重新排序和建树。
     * 适用于需要动态更改排序规则的场景。
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        // 1. 导出所有节点到数组
        var arr:Array = this.toArray();
        
        // 2. 更新比较函数
        this.compareFunction = newCompareFunction;
        
        // 3. 清空当前树
        this.root = null;
        this.treeSize = 0;
        
        // 4. 使用新的比较函数对数组进行排序
        TimSort.sort(arr, newCompareFunction);
        
        // 5. 逐个添加元素，使用标准的添加方法确保红黑树性质
        for (var i:Number = 0; i < arr.length; i++) {
            this.add(arr[i]);
        }
    }

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        this.root = insert(this.root, element);
        // 确保根节点为黑色
        this.root.color = RedBlackNode.BLACK;
    }

    /**
     * 移除元素
     * @param element 要移除的元素
     * @return 如果成功移除元素则返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        if (!contains(element)) {
            return false;
        }
        
        // 特殊情况: 如果根节点是唯一节点且要删除它
        if (this.treeSize == 1 && this.compareFunction(this.root.value, element) == 0) {
            this.root = null;
            this.treeSize = 0;
            return true;
        }
        
        // 一般情况: 将根处的节点设为红色以便删除操作
        if (!isRed(this.root.left) && !isRed(this.root.right)) {
            this.root.color = RedBlackNode.RED;
        }
        
        this.root = deleteNode(this.root, element);
        
        // 确保根节点为黑色
        if (this.root != null) {
            this.root.color = RedBlackNode.BLACK;
        }
        
        return true;
    }

    /**
     * 检查树中是否包含某个元素
     * @param element 要检查的元素
     * @return 如果树中包含该元素则返回 true，否则返回 false
     */
    public function contains(element:Object):Boolean {
        var node:RedBlackNode = search(this.root, element);
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
        inorderTraversal(this.root, arr);  // 使用递归进行中序遍历
        return arr;
    }
    
    /**
     * 递归进行中序遍历，并将结果添加到数组中
     * @param node 当前节点
     * @param arr 结果数组
     */
    private function inorderTraversal(node:RedBlackNode, arr:Array):Void {
        if (node == null) {
            return;
        }
        
        // 先遍历左子树
        inorderTraversal(node.left, arr);
        
        // 访问当前节点
        arr.push(node.value);
        
        // 再遍历右子树
        inorderTraversal(node.right, arr);
    }

    /**
     * 返回根节点
     * @return 树的根节点
     */
    public function getRoot():RedBlackNode {
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
     * 返回红黑树的字符串表示，基于前序遍历
     * @return 树的前序遍历字符串
     */
    public function toString():String {
        var str:String = "";
        var stack:Array = [];    // 模拟堆栈
        var index:Number = 0;    // 堆栈索引
        var node:RedBlackNode = this.root; // 当前节点

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
     * 递归插入新元素，并保持红黑树性质
     * @param node 当前递归到的节点
     * @param element 要插入的元素
     * @return 插入后的节点
     */
    private function insert(node:RedBlackNode, element:Object):RedBlackNode {
        // 标准BST插入
        if (node == null) {
            // 找到插入位置，创建新节点
            this.treeSize++;
            return new RedBlackNode(element);
        }

        // 递归插入
        var cmp:Number = this.compareFunction(element, node.value);
        if (cmp < 0) {
            // 元素小于当前节点，递归插入左子树
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            // 元素大于当前节点，递归插入右子树
            node.right = insert(node.right, element);
        } else {
            // 元素已存在，直接返回当前节点（不更新值）
            return node;
        }

        // 修复红黑树性质
        return balanceAfterInsert(node);
    }

    /**
     * 平衡插入后的红黑树
     * @param node 当前节点
     * @return 平衡后的节点
     */
    private function balanceAfterInsert(node:RedBlackNode):RedBlackNode {
        // 情况1：右子节点为红色，左子节点为黑色 - 左旋转
        if (isRed(node.right) && !isRed(node.left)) {
            node = rotateLeft(node);
        }

        // 情况2：连续两个左红子节点 - 右旋转
        if (isRed(node.left) && isRed(node.left.left)) {
            node = rotateRight(node);
        }

        // 情况3：左右子节点都为红色 - 颜色翻转
        if (isRed(node.left) && isRed(node.right)) {
            flipColors(node);
        }

        return node;
    }

    /**
     * 递归删除元素，并保持红黑树性质
     * @param node 当前递归到的节点
     * @param element 要删除的元素
     * @return 删除后的节点
     */
    private function deleteNode(node:RedBlackNode, element:Object):RedBlackNode {
        if (node == null) {
            return null;
        }

        // 1. 先比较方向
        var cmp:Number = this.compareFunction(element, node.value);

        // 2. 如果要删除的值在左子树
        if (cmp < 0) {
            // 确保左边有红色，方便下钻删除
            if (!isRed(node.left) && node.left != null && !isRed(node.left.left)) {
                node = moveRedLeft(node);
            }
            node.left = deleteNode(node.left, element);

        } else {
            // 如果左孩子是红的，先右旋以标准化形态
            if (isRed(node.left)) {
                node = rotateRight(node);
                // 旋转后 node.value 改变，必须重算 cmp
                cmp = this.compareFunction(element, node.value);
            }

            // cmp == 0 并且没有右子：直接删
            if (cmp == 0 && node.right == null) {
                this.treeSize--;
                return null;
            }

            // 确保右边有红色，方便下钻删除
            if (!isRed(node.right) && node.right != null && !isRed(node.right.left)) {
                node = moveRedRight(node);
            }

            // 重新比较一次（防止上述旋转/moveRedRight 改变了 node.value）
            cmp = this.compareFunction(element, node.value);

            if (cmp == 0) {
                // 找到待删节点，用右子树最小节点替换
                var successor:RedBlackNode = findMin(node.right);
                node.value = successor.value;
                // 删除右子树的最小节点
                node.right = deleteMin(node.right);
                this.treeSize--;
            } else {
                // 继续在右子树删除
                node.right = deleteNode(node.right, element);
            }
        }

        // 最后修复本层平衡
        return balanceAfterDelete(node);
    }


    /**
     * 删除子树中的最小节点
     * @param node 子树的根节点
     * @return 删除最小节点后的子树
     */
    private function deleteMin(node:RedBlackNode):RedBlackNode {
        // 已经到最左端 - 这是最小节点，删除它
        if (node.left == null) {
            return null;
        }
        
        // 确保沿路径的节点有足够的红色节点（红色节点更易删除）
        if (!isRed(node.left) && !isRed(node.left.left)) {
            node = moveRedLeft(node);
        }
        
        // 继续往左找最小节点
        node.left = deleteMin(node.left);
        
        // 维持平衡
        return balanceAfterDelete(node);
    }

    /**
     * 向左移动红色节点（用于删除操作）
     * @param node 当前节点
     * @return 移动后的节点
     */
    private function moveRedLeft(node:RedBlackNode):RedBlackNode {
        // 先翻转颜色，尝试"借"红色节点
        flipColors(node);
        
        // 如果右子节点的左子节点为红色，可以通过旋转将红色节点向左移
        if (node.right != null && isRed(node.right.left)) {
            // 先右旋右子节点
            node.right = rotateRight(node.right);
            // 然后左旋当前节点
            node = rotateLeft(node);
            // 最后再次翻转颜色
            flipColors(node);
        }
        
        return node;
    }

    /**
     * 向右移动红色节点（用于删除操作）
     * @param node 当前节点
     * @return 移动后的节点
     */
    private function moveRedRight(node:RedBlackNode):RedBlackNode {
        // 先翻转颜色，尝试"借"红色节点
        flipColors(node);
        
        // 如果左子节点的左子节点为红色，可以通过旋转将红色向右移
        if (node.left != null && isRed(node.left.left)) {
            // 右旋当前节点
            node = rotateRight(node);
            // 再翻转颜色
            flipColors(node);
        }
        
        return node;
    }

    /**
     * 平衡删除后的红黑树
     * @param node 当前节点
     * @return 平衡后的节点
     */
    private function balanceAfterDelete(node:RedBlackNode):RedBlackNode {
        // 右子节点为红色 -> 左旋
        if (isRed(node.right)) {
            node = rotateLeft(node);
        }
        
        // 左子节点为红色，且左子节点的左子节点也为红色 -> 右旋
        if (isRed(node.left) && isRed(node.left.left)) {
            node = rotateRight(node);
        }
        
        // 左右子节点都为红色 -> 颜色翻转
        if (isRed(node.left) && isRed(node.right)) {
            flipColors(node);
        }
        
        return node;
    }

    /**
     * 左旋转
     * @param node 要旋转的节点
     * @return 旋转后的新根节点
     */
    private function rotateLeft(node:RedBlackNode):RedBlackNode {
        var x:RedBlackNode = node.right;
        node.right = x.left;
        x.left = node;
        x.color = node.color;
        node.color = RedBlackNode.RED;
        return x;
    }

    /**
     * 右旋转
     * @param node 要旋转的节点
     * @return 旋转后的新根节点
     */
    private function rotateRight(node:RedBlackNode):RedBlackNode {
        var x:RedBlackNode = node.left;
        node.left = x.right;
        x.right = node;
        x.color = node.color;
        node.color = RedBlackNode.RED;
        return x;
    }

    /**
     * 颜色翻转
     * @param node 要翻转颜色的节点及其子节点
     */
    private function flipColors(node:RedBlackNode):Void {
        node.color = !node.color;
        if (node.left != null) node.left.color = !node.left.color;
        if (node.right != null) node.right.color = !node.right.color;
    }

    /**
     * 检查节点是否为红色
     * @param node 要检查的节点
     * @return 如果节点为红色则返回 true，否则返回 false
     */
    private function isRed(node:RedBlackNode):Boolean {
        if (node == null) return false;
        return node.color == RedBlackNode.RED;
    }

    /**
     * 找到子树中的最小节点
     * @param node 子树的根节点
     * @return 最小值的节点
     */
    private function findMin(node:RedBlackNode):RedBlackNode {
        var current:RedBlackNode = node;
        while (current.left != null) {
            current = current.left;
        }
        return current;
    }

    /**
     * 在树中搜索指定元素
     * @param node 当前递归到的节点
     * @param element 要搜索的元素
     * @return 如果找到元素则返回对应的节点，否则返回 null
     */
    private function search(node:RedBlackNode, element:Object):RedBlackNode {
        var current:RedBlackNode = node;
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
}