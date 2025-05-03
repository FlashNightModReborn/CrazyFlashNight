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
     *   2. 使用分治法一次性构建平衡二叉查找树
     *   3. 修复红黑树属性
     * @param arr 输入的元素数组，需为可排序的类型
     * @param compareFunction 用于排序的比较函数
     * @return 新构建的 RedBlackTree 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):RedBlackTree {
        var rbTree:RedBlackTree = new RedBlackTree(compareFunction);
        // 使用 TimSort 排序输入数组，确保数组有序以便分治法构建平衡树
        TimSort.sort(arr, compareFunction);
        
        // 使用分治法构建平衡二叉查找树
        rbTree.root = rbTree.buildBalancedTree(arr, 0, arr.length - 1);
        
        // 修复红黑树属性
        rbTree.fixRedBlackProperties();
        
        // 设置树的大小为数组长度
        rbTree.treeSize = arr.length;
        
        return rbTree;
    }

    /**
     * [实例方法] 更换当前 RedBlackTree 的比较函数，并对所有数据重新排序和建树。
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

        // 4. 使用分治法重建平衡二叉查找树
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        
        // 5. 修复红黑树属性
        fixRedBlackProperties();
        
        this.treeSize = arr.length;
    }

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        this.root = insert(this.root, null, element);
        // 确保根节点为黑色
        this.root.color = RedBlackNode.BLACK;
    }

    /**
     * 移除元素
     * @param element 要移除的元素
     * @return 如果成功移除元素则返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = this.treeSize;
        this.root = deleteNode(this.root, element);
        if (this.root != null) {
            this.root.color = RedBlackNode.BLACK;
        }
        return (this.treeSize < oldSize);
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
        var stack:Array = [];              // 模拟堆栈
        var index:Number = 0;              // 堆栈索引
        var node:RedBlackNode = this.root; // 当前节点

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
     * @param parent 当前节点的父节点
     * @param element 要插入的元素
     * @return 插入后的节点
     */
    private function insert(node:RedBlackNode, parent:RedBlackNode, element:Object):RedBlackNode {
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
            node.left = insert(node.left, node, element);
        } else if (cmp > 0) {
            // 元素大于当前节点，递归插入右子树
            node.right = insert(node.right, node, element);
        } else {
            // 元素已存在，直接返回当前节点
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

        var cmp:Number = this.compareFunction(element, node.value);
        
        if (cmp < 0) {
            // 要删除的元素在左子树
            if (!isRed(node.left) && node.left != null && !isRed(node.left.left)) {
                // 如果左子节点和左子节点的左子节点都是黑色，移动红色到左边
                node = moveRedLeft(node);
            }
            node.left = deleteNode(node.left, element);
        } else {
            // 如果左子节点是红色，右旋以保持删除操作的不变性
            if (isRed(node.left)) {
                node = rotateRight(node);
            }
            
            // 找到要删除的节点且没有左子节点，直接删除
            if (cmp == 0 && node.right == null) {
                this.treeSize--;
                return null;
            }
            
            // 确保右子树有足够的红色节点用于删除操作
            if (!isRed(node.right) && node.right != null && !isRed(node.right.left)) {
                node = moveRedRight(node);
            }
            
            if (cmp == 0) {
                // 找到要删除的元素，使用右子树中的最小节点替换它
                var minNode:RedBlackNode = findMin(node.right);
                node.value = minNode.value;
                // 删除用于替换的最小节点
                node.right = deleteMin(node.right);
                this.treeSize--;
            } else {
                // 要删除的元素在右子树
                node.right = deleteNode(node.right, element);
            }
        }
        
        // 修复红黑树性质
        return balanceAfterDelete(node);
    }

    /**
     * 删除子树中的最小节点
     * @param node 子树的根节点
     * @return 删除最小节点后的子树
     */
    private function deleteMin(node:RedBlackNode):RedBlackNode {
        // 达到最左端，删除最小节点
        if (node.left == null) {
            return null;
        }
        
        // 确保左侧路径上有红色节点，以便删除黑色节点
        if (!isRed(node.left) && !isRed(node.left.left)) {
            node = moveRedLeft(node);
        }
        
        // 递归向左查找最小节点
        node.left = deleteMin(node.left);
        
        // 修复红黑树性质
        return balanceAfterDelete(node);
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
        
        // 左子节点为红色，左子节点的左子节点也为红色 -> 右旋
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
     * 向左移动红色节点（用于删除操作）
     * @param node 当前节点
     * @return 移动后的节点
     */
    private function moveRedLeft(node:RedBlackNode):RedBlackNode {
        // 颜色翻转，尝试从右子树借一个红色节点
        flipColors(node);
        
        // 如果右子节点的左子节点为红色，通过旋转使红色节点下移到左边
        if (node.right != null && isRed(node.right.left)) {
            node.right = rotateRight(node.right);
            node = rotateLeft(node);
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
        // 颜色翻转，尝试从左子树借一个红色节点
        flipColors(node);
        
        // 如果左子节点的左子节点为红色，通过旋转使红色节点下移到右边
        if (node.left != null && isRed(node.left.left)) {
            node = rotateRight(node);
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

    /**
     * [辅助函数] 使用分治法，从已排序数组中构建平衡二叉查找树
     * @param sortedArr 已排序的元素数组
     * @param start 构建子树的起始索引
     * @param end 构建子树的结束索引
     * @return 构建好的子树根节点
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):RedBlackNode {
        if (start > end) {
            // 子数组为空，返回 null
            return null;
        }
        // 选择中间元素作为当前子树的根节点，确保平衡
        var mid:Number = (start + end) >> 1; // 等同于 Math.floor((start + end) / 2)
        var newNode:RedBlackNode = new RedBlackNode(sortedArr[mid]);

        // 递归构建左子树和右子树
        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        return newNode;
    }

    /**
     * [辅助函数] 修复整个树的红黑属性，自顶向下修复
     */
    private function fixRedBlackProperties():Void {
        if (this.root == null) return;
        
        // 确保根节点为黑色
        this.root.color = RedBlackNode.BLACK;
        
        // 修复每个节点的红黑树属性
        fixNodeColors(this.root);
    }
    
    /**
     * [辅助函数] 递归修复节点的颜色属性
     * @param node 当前处理的节点
     */
    private function fixNodeColors(node:RedBlackNode):Void {
        if (node == null) return;
        
        // 如果有连续的红色节点，需要通过旋转和颜色翻转修复
        if (isRed(node) && (isRed(node.left) || isRed(node.right))) {
            // 左右子节点都为红色，执行颜色翻转
            if (isRed(node.left) && isRed(node.right)) {
                flipColors(node);
            }
            // 左子节点为红色，左子节点的左子节点也为红色，需要右旋
            else if (isRed(node.left) && isRed(node.left.left)) {
                node = rotateRight(node);
                flipColors(node);
            }
            // 右子节点为红色，需要左旋
            else if (isRed(node.right)) {
                node = rotateLeft(node);
                flipColors(node);
            }
        }
        
        // 递归修复左右子树
        fixNodeColors(node.left);
        fixNodeColors(node.right);
    }
}