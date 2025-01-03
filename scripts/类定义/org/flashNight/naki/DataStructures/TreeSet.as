import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TreeSet {
    private var root:TreeNode;                 // 树的根节点
    private var compareFunction:Function;      // 用于比较元素的函数
    private var treeSize:Number;               // 树中元素的数量

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的比较逻辑
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
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        root = insert(root, element);
    }

    /**
     * 从树中移除元素
     * @param element 要移除的元素
     * @return 如果移除成功返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        var initialSize:Number = this.treeSize;  // 记录删除前的大小
        root = deleteNode(root, element);
        return this.treeSize < initialSize;       // 如果大小减少，表示成功删除
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

    //====================== 以下是私有函数 ======================//

    /**
     * 插入元素到AVL树中，并保持树的平衡
     * @param node 当前子树的根节点
     * @param element 要插入的元素
     * @return 插入后的子树根节点
     */
    private function insert(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            // 找到插入位置，创建新节点并增加树的大小
            treeSize++;
            return new TreeNode(element);
        }

        var cmp:Number = compareFunction(element, node.value);  // 比较元素与当前节点值
        if (cmp < 0) {
            // 插入到左子树
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            // 插入到右子树
            node.right = insert(node.right, element);
        } else {
            // 元素已存在，不进行插入
            return node;
        }

        // 更新当前节点的高度
        var leftHeight:Number = (node.left != null) ? node.left.height : 0;
        var rightHeight:Number = (node.right != null) ? node.right.height : 0;
        node.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        // 计算平衡因子
        var balance:Number = leftHeight - rightHeight;

        // 平衡调整（内联旋转）
        if (balance > 1) {
            // 左侧过高，检查 LL 或 LR 情况
            var leftNode:TreeNode = node.left;
            var leftBalance:Number = (leftNode.left != null ? leftNode.left.height : 0) - 
                                      (leftNode.right != null ? leftNode.right.height : 0);

            if (leftBalance >= 0) {
                // LL 场景：单右旋
                node = rotateRightInline(node);
            } else {
                // LR 场景：先左旋左子节点，再右旋当前节点
                node.left = rotateLeftInline(leftNode);
                node = rotateRightInline(node);
            }
        } 
        else if (balance < -1) {
            // 右侧过高，检查 RR 或 RL 情况
            var rightNode:TreeNode = node.right;
            var rightBalance:Number = (rightNode.left != null ? rightNode.left.height : 0) - 
                                       (rightNode.right != null ? rightNode.right.height : 0);

            if (rightBalance <= 0) {
                // RR 场景：单左旋
                node = rotateLeftInline(node);
            } else {
                // RL 场景：先右旋右子节点，再左旋当前节点
                node.right = rotateRightInline(rightNode);
                node = rotateLeftInline(node);
            }
        }

        return node;
    }

    /**
     * 删除AVL树中的元素，并保持树的平衡
     * @param node 当前子树的根节点
     * @param element 要删除的元素
     * @return 删除后的子树根节点
     */
    private function deleteNode(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            // 未找到要删除的元素
            return node;
        }

        // 比较目标元素与当前节点的值
        var cmp:Number = compareFunction(element, node.value);
        if (cmp < 0) {
            // 在左子树中删除
            node.left = deleteNode(node.left, element);
        } else if (cmp > 0) {
            // 在右子树中删除
            node.right = deleteNode(node.right, element);
        } else {
            // 找到目标节点，进行删除
            treeSize--;
            if (node.left == null || node.right == null) {
                // 节点有一个或没有子节点
                node = (node.left != null) ? node.left : node.right;
            } else {
                // 节点有两个子节点：找到右子树的最小节点（中序后继）
                var temp:TreeNode = node.right;
                while (temp.left != null) {
                    temp = temp.left;
                }
                // 用中序后继的值替换当前节点的值
                node.value = temp.value;
                // 删除中序后继节点
                node.right = deleteNode(node.right, temp.value);
            }
        }

        // 如果删除后节点为空，直接返回
        if (node == null) {
            return node;
        }

        // 更新当前节点的高度
        var leftHeight:Number = (node.left != null) ? node.left.height : 0;
        var rightHeight:Number = (node.right != null) ? node.right.height : 0;
        node.height = 1 + ((leftHeight > rightHeight) ? leftHeight : rightHeight);

        // 计算平衡因子
        var balance:Number = leftHeight - rightHeight;

        // 平衡调整（内联旋转）
        if (balance > 1) {
            // 左侧过高，检查 LL 或 LR 情况
            var leftNode:TreeNode = node.left;
            var leftBalance:Number = (leftNode.left != null ? leftNode.left.height : 0) - 
                                      (leftNode.right != null ? leftNode.right.height : 0);

            if (leftBalance >= 0) {
                // LL 场景：单右旋
                node = rotateRightInline(node);
            } else {
                // LR 场景：先左旋左子节点，再右旋当前节点
                node.left = rotateLeftInline(leftNode);
                node = rotateRightInline(node);
            }
        } 
        else if (balance < -1) {
            // 右侧过高，检查 RR 或 RL 情况
            var rightNode:TreeNode = node.right;
            var rightBalance:Number = (rightNode.left != null ? rightNode.left.height : 0) - 
                                       (rightNode.right != null ? rightNode.right.height : 0);

            if (rightBalance <= 0) {
                // RR 场景：单左旋
                node = rotateLeftInline(node);
            } else {
                // RL 场景：先右旋右子节点，再左旋当前节点
                node.right = rotateRightInline(rightNode);
                node = rotateLeftInline(node);
            }
        }

        return node;
    }

    /**
     * 右旋操作（内联实现），并更新相关节点的高度
     * @param y 需要右旋的节点
     * @return 旋转后的新根节点
     */
    private function rotateRightInline(y:TreeNode):TreeNode {
        var x:TreeNode = y.left;    // y 的左子节点
        var T2:TreeNode = x.right; // x 的右子节点

        // 执行右旋
        x.right = y;
        y.left = T2;

        // 更新 y 的高度
        var yLeftHeight:Number = (T2 != null) ? T2.height : 0;               // y 左子节点（原 x 的右子节点）的高度
        var yRightHeight:Number = (y.right != null) ? y.right.height : 0;    // y 右子节点的高度
        y.height = 1 + ((yLeftHeight > yRightHeight) ? yLeftHeight : yRightHeight);

        // 更新 x 的高度
        var xLeftHeight:Number = (x.left != null) ? x.left.height : 0;        // x 左子节点的高度
        var xRightHeight:Number = y.height; // y 已经更新过高度
        x.height = 1 + ((xLeftHeight > xRightHeight) ? xLeftHeight : xRightHeight);

        return x; // 返回新的根节点 x
    }

    /**
     * 左旋操作（内联实现），并更新相关节点的高度
     * @param x 需要左旋的节点
     * @return 旋转后的新根节点
     */
    private function rotateLeftInline(x:TreeNode):TreeNode {
        var y:TreeNode = x.right;   // x 的右子节点
        var T2:TreeNode = y.left;  // y 的左子节点

        // 执行左旋
        y.left = x;
        x.right = T2;

        // 更新 x 的高度
        var xLeftHeight:Number = (x.left != null) ? x.left.height : 0;     // x 左子节点的高度
        var xRightHeight:Number = (T2 != null) ? T2.height : 0;          // x 右子节点（原 y 的左子节点）的高度
        x.height = 1 + ((xLeftHeight > xRightHeight) ? xLeftHeight : xRightHeight);

        // 更新 y 的高度
        var yRightHeight:Number = (y.right != null) ? y.right.height : 0;  // y 右子节点的高度
        y.height = 1 + ((x.height > yRightHeight) ? x.height : yRightHeight);

        return y; // 返回新的根节点 y
    }

    /**
     * 在树中搜索指定元素
     * @param node 当前子树的根节点
     * @param element 要搜索的元素
     * @return 如果找到，返回对应的节点；否则返回 null
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
                return current;
            }
        }
        return null;
    }

    /**
     * 中序遍历树，并将元素添加到数组中
     * @param node 当前子树的根节点
     * @param arr 用于存储遍历结果的数组
     */
    private function inOrderTraversal(node:TreeNode, arr:Array):Void {
        if (node != null) {
            inOrderTraversal(node.left, arr);
            arr.push(node.value);
            inOrderTraversal(node.right, arr);
        }
    }
}
