import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.TimSort;
import org.flashNight.gesh.string.StringUtils;

/**
 * @class LLRedBlackTree
 * @package org.flashNight.naki.DataStructures
 * @description 基于【左偏红黑树 (LLRBT)】实现的集合数据结构。
 *              LLRBT 是一种简化的红黑树，通过强制所有红色链接都向左倾斜，
 *              大大减少了实现复杂性，同时保持了高效的性能。
 */
class org.flashNight.naki.DataStructures.LLRedBlackTree
        extends AbstractBalancedSearchTree
        implements IBalancedSearchTree {

    private var root:RedBlackNode; // 树的根节点

    public function LLRedBlackTree(compareFunction:Function) {
        super(compareFunction); // 调用基类构造函数，初始化 _compareFunction 和 _treeSize
        this.root = null;
    }

    public static function buildFromArray(arr:Array, compareFunction:Function):LLRedBlackTree {
        var rbTree:LLRedBlackTree = new LLRedBlackTree(compareFunction);
        TimSort.sort(arr, compareFunction);
        var uniqueArr:Array = [];
        if (arr.length > 0) {
            uniqueArr.push(arr[0]);
            for (var i:Number = 1; i < arr.length; i++) {
                if (compareFunction(arr[i], arr[i-1]) != 0) {
                    uniqueArr.push(arr[i]);
                }
            }
        }
        for (i = 0; i < uniqueArr.length; i++) {
            rbTree.add(uniqueArr[i]);
        }
        return rbTree;
    }

    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        var arr:Array = this.toArray();
        _compareFunction = newCompareFunction;
        this.root = null;
        _treeSize = 0;
        TimSort.sort(arr, newCompareFunction);
        for (var i:Number = 0; i < arr.length; i++) {
            this.add(arr[i]);
        }
    }
    
    public function contains(element:Object):Boolean {
        return (search(this.root, element) != null);
    }

    // size() 和 isEmpty() 由基类 AbstractBalancedSearchTree 提供

    public function toArray():Array {
        var arr:Array = [];
        inorderTraversal(this.root, arr);
        return arr;
    }

    /**
     * 返回根节点
     * @return 树的根节点，实现 ITreeNode 接口；空树返回 null
     */
    public function getRoot():ITreeNode {
        return this.root;
    }

    // getCompareFunction() 由基类 AbstractBalancedSearchTree 提供

    private function inorderTraversal(node:RedBlackNode, arr:Array):Void {
        if (node == null) return;
        inorderTraversal(node.left, arr);
        arr.push(node.value);
        inorderTraversal(node.right, arr);
    }

    public function toString():String {
        var str:String = "";
        var stack:Array = [];
        var index:Number = 0;
        var node:RedBlackNode = this.root;
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
    
    //======================== LLRBT 核心实现 ========================//

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        this.root = insert(this.root, element);
        // 根节点永远是黑色
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

        // 如果根的左右子节点都不是红色，将根设为红色
        // 这是为了确保在删除过程中，根节点有红色节点可以“下放”
        if (!isRed(this.root.left) && !isRed(this.root.right)) {
            this.root.color = RedBlackNode.RED;
        }

        this.root = deleteNode(this.root, element);
        _treeSize--;

        // 如果树不为空，则确保根节点为黑色
        if (this.root != null) {
            this.root.color = RedBlackNode.BLACK;
        }
        
        return true;
    }

    //======================== LLRBT 私有辅助函数 (全新重写) ========================//

    /**
     * LLRBT 递归插入
     * @param h 当前节点
     * @param element 要插入的元素
     * @return 插入并平衡后的新子树根节点
     */
    private function insert(h:RedBlackNode, element:Object):RedBlackNode {
        // 标准BST插入，新节点总是红色
        if (h == null) {
            _treeSize++;
            return new RedBlackNode(element);
        }

        var cmp:Number = _compareFunction(element, h.value);
        if (cmp < 0) {
            h.left = insert(h.left, element);
        } else if (cmp > 0) {
            h.right = insert(h.right, element);
        }
        // 如果值已存在，不做任何操作

        // 核心：在递归返回时，修复所有违反 LLRBT 规则的情况
        return balance(h);
    }

    /**
     * LLRBT 递归删除
     * @param h 当前节点
     * @param element 要删除的元素
     * @return 删除并平衡后的新子树根节点
     */
    private function deleteNode(h:RedBlackNode, element:Object):RedBlackNode {
        if (h == null) return null;

        if (_compareFunction(element, h.value) < 0) {
            // 要删除的元素在左子树
            // 如果 h.left 和 h.left.left 都是黑色，从 h 或其兄弟节点借一个红色
            if (h.left != null && !isRed(h.left) && !isRed(h.left.left)) {
                h = moveRedLeft(h);
            }
            h.left = deleteNode(h.left, element);
        } else {
            // 如果 h.left 是红色，先右旋，将红色链接移到右边，方便处理
            if (isRed(h.left)) {
                h = rotateRight(h);
            }
            // 找到要删除的节点，并且它没有右子节点 (即它是叶子节点或只有一个左子节点)
            if (_compareFunction(element, h.value) == 0 && h.right == null) {
                // 因为我们保证了路径上总有红色，所以可以直接删除
                return null; // 返回 null 将其从树中移除
            }
            // 要删除的元素在右子树或当前节点
            if (h.right != null && !isRed(h.right) && !isRed(h.right.left)) {
                h = moveRedRight(h);
            }
            // 找到要删除的节点，用其后继节点替换
            if (_compareFunction(element, h.value) == 0) {
                var successor:RedBlackNode = findMin(h.right);
                h.value = successor.value;
                h.right = deleteMin(h.right);
            } else {
                // 继续在右子树中寻找
                h.right = deleteNode(h.right, element);
            }
        }

        // 核心：在递归返回时，修复所有违反 LLRBT 规则的情况
        return balance(h);
    }

    /**
     * 删除子树中的最小节点 (LLRBT 版本)
     */
    private function deleteMin(h:RedBlackNode):RedBlackNode {
        if (h.left == null) {
            return null; // 找到最小节点，删除它
        }
        // 如果 h.left 和 h.left.left 都是黑色，从 h 或其兄弟节点借一个红色
        if (!isRed(h.left) && !isRed(h.left.left)) {
            h = moveRedLeft(h);
        }
        h.left = deleteMin(h.left);

        // 修复平衡
        return balance(h);
    }

    /**
     * LLRBT 统一的平衡函数
     * 在递归返回时按顺序修复所有 LLRBT 违规
     * @param h 当前节点
     * @return 平衡后的节点
     */
    private function balance(h:RedBlackNode):RedBlackNode {
        // 1. 如果右链接是红色 (而左链接是黑色)，则左旋
        if (isRed(h.right) && !isRed(h.left)) h = rotateLeft(h);
        // 2. 如果出现连续的左红链接，则右旋
        if (isRed(h.left) && isRed(h.left.left)) h = rotateRight(h);
        // 3. 如果左右链接都是红色，则进行颜色翻转
        if (isRed(h.left) && isRed(h.right)) flipColors(h);
        
        return h;
    }
    
    /**
     * 向左移动红色节点（用于删除操作）
     * 假设 h 是红色，h.left 和 h.left.left 是黑色。
     * 将 h 的红色“下放”到 h.left 或 h.left 的子节点。
     */
    private function moveRedLeft(h:RedBlackNode):RedBlackNode {
        flipColors(h); // 将 h 变黑，两个子节点变红
        // 如果 h.right.left 是红色，从右子树“借”一个节点过来
        if (h.right != null && isRed(h.right.left)) {
            h.right = rotateRight(h.right);
            h = rotateLeft(h);
            flipColors(h); // 恢复颜色
        }
        return h;
    }

    /**
     * 向右移动红色节点（用于删除操作）
     * 假设 h 是红色，h.right 和 h.right.left 是黑色。
     * 将 h 的红色“下放”到 h.right 或 h.right 的子节点。
     */
    private function moveRedRight(h:RedBlackNode):RedBlackNode {
        flipColors(h); // 将 h 变黑，两个子节点变红
        // 如果 h.left.left 是红色，直接右旋即可
        if (h.left != null && isRed(h.left.left)) {
            h = rotateRight(h);
            flipColors(h); // 恢复颜色
        }
        return h;
    }

    // LLRBT 的基础操作: isRed, rotateLeft, rotateRight, flipColors, findMin, search
    // 这些与原版几乎一样，但为了完整性，在此列出

    private function isRed(node:RedBlackNode):Boolean {
        if (node == null) return false;
        return node.color == RedBlackNode.RED;
    }

    private function rotateLeft(h:RedBlackNode):RedBlackNode {
        var x:RedBlackNode = h.right;
        h.right = x.left;
        x.left = h;
        x.color = h.color;
        h.color = RedBlackNode.RED;
        return x;
    }

    private function rotateRight(h:RedBlackNode):RedBlackNode {
        var x:RedBlackNode = h.left;
        h.left = x.right;
        x.right = h;
        x.color = h.color;
        h.color = RedBlackNode.RED;
        return x;
    }

    private function flipColors(h:RedBlackNode):Void {
        h.color = !h.color;
        if (h.left != null) h.left.color = !h.left.color;
        if (h.right != null) h.right.color = !h.right.color;
    }

    private function findMin(node:RedBlackNode):RedBlackNode {
        var current:RedBlackNode = node;
        while (current.left != null) {
            current = current.left;
        }
        return current;
    }

    private function search(node:RedBlackNode, element:Object):RedBlackNode {
        var current:RedBlackNode = node;
        while (current != null) {
            var cmp:Number = _compareFunction(element, current.value);
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
}