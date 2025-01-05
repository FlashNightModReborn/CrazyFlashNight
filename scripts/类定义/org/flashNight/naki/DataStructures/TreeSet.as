import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.QuickSort;

class org.flashNight.naki.DataStructures.TreeSet {
    private var root:TreeNode;                 // 树的根节点
    private var compareFunction:Function;      // 用于比较元素的函数
    private var treeSize:Number;               // 树中元素的数量

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较逻辑
     */
    public function TreeSet(compareFunction:Function) {
        if (compareFunction == undefined || compareFunction == null) {
            // 默认的比较函数，基于基本的大小比较
            this.compareFunction = function(a, b):Number {
                if (a < b) return -1;
                if (a > b) return 1;
                return 0;
            };
        } else {
            this.compareFunction = compareFunction;
        }
        this.root = null;
        this.treeSize = 0;
    }

    /**
     * [新增 - 静态方法]
     * 从给定数组构建一个新的平衡 AVL 树（TreeSet）。
     * 实现方式：
     *  1. 先对输入数组排序（可自定义快速排序或内建排序）。
     *  2. 使用分治法一次性构建平衡树，避免逐个插入导致的大量旋转。
     * 
     * @param arr 包含元素的数组
     * @param compareFunction 比较函数，可自定义排序规则
     * @return 构建完成的 TreeSet 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):TreeSet {
        // 创建新的 TreeSet
        var treeSet:TreeSet = new TreeSet(compareFunction);

        // 先对数组进行排序
        QuickSort.sort(arr, compareFunction);

        // 平衡构建: 用分治方式将有序数组变为平衡 BST
        treeSet.root = treeSet.buildBalancedTree(arr, 0, arr.length - 1);
        treeSet.treeSize = arr.length;

        return treeSet;
    }

    /**
     * [新增 - 实例方法]
     * 更换当前 TreeSet 的比较函数，并对所有数据重新排序和建树。
     * 
     * 实现流程：
     *  1. 更新 compareFunction
     *  2. 将现有 TreeSet 数据导出为数组
     *  3. 使用快排 (QuickSort.sort) 排序该数组
     *  4. 清空并重新构建平衡 AVL 树
     *  5. 更新 treeSize
     * 
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        // 1. 更新比较函数
        this.compareFunction = newCompareFunction;

        // 2. 导出所有节点到数组
        var arr:Array = toArray();

        // 3. 使用 QuickSort 排序
        QuickSort.sort(arr, newCompareFunction);

        // 4. 使用排序后的数组重建平衡 AVL
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        this.treeSize = arr.length;
    }

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        root = insert(root, element);
    }

    /**
     * 从树中移除元素
     * @param element 要移除的元素
     * @return 如果成功移除则返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        var initialSize:Number = this.treeSize;  // 删除前的大小
        root = deleteNode(root, element);
        return this.treeSize < initialSize;      // 如果大小减少，表示删除成功
    }

    /**
     * 检查树中是否包含某个元素
     * @param element 要检查的元素
     * @return 如果包含返回 true，否则返回 false
     */
    public function contains(element:Object):Boolean {
        var node:TreeNode = search(root, element);
        return node != null;
    }

    /**
     * 获取树的大小
     * @return 树中元素的数量
     */
    public function size():Number {
        return treeSize;
    }

    /**
     * 将树的元素转换为数组（中序遍历）
     * @return 包含树中所有元素的数组
     */
    public function toArray():Array {
        var arr:Array = [];
        inOrderTraversal(root, arr);
        return arr;
    }

    /**
     * 获取树
     * @return 树
     */
    public function getRoot():TreeNode {
        return this.root;
    }

    public function getCompareFunction():Function {
        return this.compareFunction;
    }

    //================== 以下是私有函数 ==================//

    /**
     * 插入元素到AVL树中，并保持树的平衡
     * @param node 当前子树根节点
     * @param element 要插入的元素
     * @return 插入后的子树根节点
     */
    private function insert(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            treeSize++;
            return new TreeNode(element);
        }

        var cmp:Number = compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            node.right = insert(node.right, element);
        } else {
            // 元素已存在，不插入
            return node;
        }

        // 更新高度
        var leftHeight:Number = (node.left != null) ? node.left.height : 0;
        var rightHeight:Number = (node.right != null) ? node.right.height : 0;
        node.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        // 检查平衡因子
        var balance:Number = leftHeight - rightHeight;

        // 失衡时进行相应旋转
        if (balance > 1) {
            // 左侧过高
            var leftNode:TreeNode = node.left;
            var leftBalance:Number = (leftNode.left != null ? leftNode.left.height : 0) -
                                     (leftNode.right != null ? leftNode.right.height : 0);
            if (leftBalance >= 0) {
                // LL 场景: 单右旋
                node = rotateRightInline(node);
            } else {
                // LR 场景: 先左旋左子节点，再右旋自己
                node.left = rotateLeftInline(leftNode);
                node = rotateRightInline(node);
            }
        } 
        else if (balance < -1) {
            // 右侧过高
            var rightNode:TreeNode = node.right;
            var rightBalance:Number = (rightNode.left != null ? rightNode.left.height : 0) -
                                      (rightNode.right != null ? rightNode.right.height : 0);
            if (rightBalance <= 0) {
                // RR 场景: 单左旋
                node = rotateLeftInline(node);
            } else {
                // RL 场景: 先右旋右子节点，再左旋自己
                node.right = rotateRightInline(rightNode);
                node = rotateLeftInline(node);
            }
        }

        return node;
    }

    /**
     * 删除元素并保持AVL平衡
     * @param node 当前子树根节点
     * @param element 要删除的元素
     * @return 删除后的子树根节点
     */
    private function deleteNode(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            return node;
        }

        var cmp:Number = compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = deleteNode(node.left, element);
        } else if (cmp > 0) {
            node.right = deleteNode(node.right, element);
        } else {
            // 找到要删除的节点
            treeSize--;
            if (node.left == null || node.right == null) {
                // 一个子节点或无子节点
                node = (node.left != null) ? node.left : node.right;
            } else {
                // 两个子节点: 用中序后继替换
                var temp:TreeNode = node.right;
                while (temp.left != null) {
                    temp = temp.left;
                }
                node.value = temp.value;
                node.right = deleteNode(node.right, temp.value);
            }
        }

        if (node == null) {
            return node; // 删除后整棵子树为空
        }

        // 更新高度
        var leftHeight:Number = (node.left != null) ? node.left.height : 0;
        var rightHeight:Number = (node.right != null) ? node.right.height : 0;
        node.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        // 检查平衡因子
        var balance:Number = leftHeight - rightHeight;

        // 失衡时进行相应旋转
        if (balance > 1) {
            var leftNode:TreeNode = node.left;
            var leftBalance:Number = (leftNode.left != null ? leftNode.left.height : 0) -
                                     (leftNode.right != null ? leftNode.right.height : 0);
            if (leftBalance >= 0) {
                // LL 场景
                node = rotateRightInline(node);
            } else {
                // LR 场景
                node.left = rotateLeftInline(leftNode);
                node = rotateRightInline(node);
            }
        } 
        else if (balance < -1) {
            var rightNode:TreeNode = node.right;
            var rightBalance:Number = (rightNode.left != null ? rightNode.left.height : 0) -
                                      (rightNode.right != null ? rightNode.right.height : 0);
            if (rightBalance <= 0) {
                // RR 场景
                node = rotateLeftInline(node);
            } else {
                // RL 场景
                node.right = rotateRightInline(rightNode);
                node = rotateLeftInline(node);
            }
        }

        return node;
    }

    /**
     * 右旋操作（内联实现）并更新节点高度
     * @param y 需要右旋的节点
     * @return 旋转后的新根节点
     */
    private function rotateRightInline(y:TreeNode):TreeNode {
        var x:TreeNode = y.left;
        var T2:TreeNode = x.right;

        // 右旋
        x.right = y;
        y.left = T2;

        // 更新 y 的高度
        var yLeftHeight:Number = (T2 != null) ? T2.height : 0;
        var yRightHeight:Number = (y.right != null) ? y.right.height : 0;
        y.height = 1 + ((yLeftHeight > yRightHeight) ? yLeftHeight : yRightHeight);

        // 更新 x 的高度
        var xLeftHeight:Number = (x.left != null) ? x.left.height : 0;
        var xRightHeight:Number = y.height; 
        x.height = 1 + ((xLeftHeight > xRightHeight) ? xLeftHeight : xRightHeight);

        return x;
    }

    /**
     * 左旋操作（内联实现）并更新节点高度
     * @param x 需要左旋的节点
     * @return 旋转后的新根节点
     */
    private function rotateLeftInline(x:TreeNode):TreeNode {
        var y:TreeNode = x.right;
        var T2:TreeNode = y.left;

        // 左旋
        y.left = x;
        x.right = T2;

        // 更新 x 的高度
        var xLeftHeight:Number = (x.left != null) ? x.left.height : 0;
        var xRightHeight:Number = (T2 != null) ? T2.height : 0;
        x.height = 1 + ((xLeftHeight > xRightHeight) ? xLeftHeight : xRightHeight);

        // 更新 y 的高度
        var yRightHeight:Number = (y.right != null) ? y.right.height : 0;
        y.height = 1 + ((x.height > yRightHeight) ? x.height : yRightHeight);

        return y;
    }

    /**
     * 在树中搜索指定元素
     * @param node 当前子树根节点
     * @param element 要搜索的元素
     * @return 如果找到则返回对应节点，否则返回 null
     */
    private function search(node:TreeNode, element:Object):TreeNode {
        var current:TreeNode = node;
        while (current != null) {
            var cmp:Number = compareFunction(element, current.value);
            if (cmp < 0) {
                current = current.left;
            } else if (cmp > 0) {
                current = current.right;
            } else {
                return current; // 找到目标
            }
        }
        return null;
    }

    /**
     * 中序遍历，将节点依次添加到数组 arr 中
     * @param node 当前子树根节点
     * @param arr 存储遍历结果的数组
     */
    private function inOrderTraversal(node:TreeNode, arr:Array):Void {
        if (node != null) {
            inOrderTraversal(node.left, arr);
            arr[arr.length] = node.value;
            inOrderTraversal(node.right, arr);
        }
    }

    /**
     * [辅助函数] 使用分治法，从已排序数组中构建平衡 AVL。
     * 可被 buildFromArray 和 changeCompareFunctionAndResort 内部使用。
     *
     * @param sortedArr 已排好序的数组
     * @param start 起始下标
     * @param end 结束下标
     * @return 构建后的子树根节点
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):TreeNode {
        if (start > end) {
            return null;
        }
        var mid:Number = (start + end) >> 1;
        var newNode:TreeNode = new TreeNode(sortedArr[mid]);

        // 递归构建左右子树
        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 更新节点高度
        var leftHeight:Number = (newNode.left != null) ? newNode.left.height : 0;
        var rightHeight:Number = (newNode.right != null) ? newNode.right.height : 0;
        newNode.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        return newNode;
    }
}
