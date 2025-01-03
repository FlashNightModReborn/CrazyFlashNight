import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TreeSet {
    private var root:TreeNode;
    private var compareFunction:Function;
    private var treeSize:Number;

    public function TreeSet(compareFunction:Function) {
        if (compareFunction == undefined || compareFunction == null) {
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

    public function add(element:Object):Void {
        root = insert(root, element);
    }

    public function remove(element:Object):Boolean {
        var initialSize:Number = this.treeSize;
        root = deleteNode(root, element);
        return this.treeSize < initialSize;
    }

    public function contains(element:Object):Boolean {
        var node:TreeNode = search(root, element);
        return node != null;
    }

    public function size():Number {
        return treeSize;
    }

    public function toArray():Array {
        var arr:Array = [];
        inOrderTraversal(root, arr);
        return arr;
    }

    //====================== 以下是私有函数 ======================//

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
            // 等于 0 表示已存在，不做插入
            return node;
        }

        // 更新当前 node 的 height
        var leftChild:TreeNode = node.left;
        var rightChild:TreeNode = node.right;
        var leftHeight:Number = (leftChild != null) ? leftChild.height : 0;
        var rightHeight:Number = (rightChild != null) ? rightChild.height : 0;
        node.height = 1 + (leftHeight > rightHeight ? leftHeight : rightHeight);

        // 平衡因子
        var balance:Number = leftHeight - rightHeight;

        // ------------------ 平衡调整（内联旋转） ------------------
        if (balance > 1) {
            // 左侧过高
            var leftNode:TreeNode = node.left;
            if (leftNode != null) {
                // 比较 element 和左子节点的值，决定是“单旋转”还是“双旋转”
                var cmpLeft:Number = compareFunction(element, leftNode.value);

                // ===== [1] LL 场景 (单右旋) =====
                if (cmpLeft < 0) {
                    // 相当于 rightRotate(node)
                    node = rotateRightInline(node);

                // ===== [2] LR 场景 (双旋转) =====
                } else {
                    // 先左旋左子节点（局部）
                    node.left = rotateLeftInline(leftNode);
                    // 再右旋当前节点
                    node = rotateRightInline(node);
                }
            }
        } 
        else if (balance < -1) {
            // 右侧过高
            var rightNode:TreeNode = node.right;
            if (rightNode != null) {
                var cmpRight:Number = compareFunction(element, rightNode.value);

                // ===== [1] RR 场景 (单左旋) =====
                if (cmpRight > 0) {
                    // 相当于 leftRotate(node)
                    node = rotateLeftInline(node);

                // ===== [2] RL 场景 (双旋转) =====
                } else {
                    // 先右旋右子节点
                    node.right = rotateRightInline(rightNode);
                    // 再左旋当前节点
                    node = rotateLeftInline(node);
                }
            }
        }
        // -------------------------------------------------------

        return node;
    }

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
            // 找到目标节点，删除
            treeSize--;
            if (node.left == null || node.right == null) {
                var temp:TreeNode = (node.left != null) ? node.left : node.right;
                if (temp == null) {
                    // 没有子节点
                    node = null;
                } else {
                    // 有一个子节点
                    node = temp;
                }
            } else {
                // 有两个子节点
                var temp:TreeNode = node.right;
                while (temp.left != null) {
                    temp = temp.left;
                }
                // 用右子树的最小节点替换当前节点
                node.value = temp.value;
                node.right = deleteNode(node.right, temp.value);
            }
        }

        // 如果删除后节点为空，直接返回
        if (node == null) {
            return node;
        }

        // 更新当前 node 的 height
        var leftChild:TreeNode = node.left;
        var rightChild:TreeNode = node.right;
        var leftHeight:Number = (leftChild != null) ? leftChild.height : 0;
        var rightHeight:Number = (rightChild != null) ? rightChild.height : 0;
        node.height = 1 + (leftHeight > rightHeight ? leftHeight : rightHeight);

        // 平衡因子
        var balance:Number = leftHeight - rightHeight;

        // ------------------ 平衡调整（内联旋转） ------------------
        if (balance > 1) {
            var leftNode:TreeNode = node.left;
            // 计算左子树的平衡因子
            var leftLeftHeight:Number = (leftNode != null && leftNode.left != null)
                ? leftNode.left.height : 0;
            var leftRightHeight:Number = (leftNode != null && leftNode.right != null)
                ? leftNode.right.height : 0;
            var leftBalance:Number = leftLeftHeight - leftRightHeight;

            // ===== [1] LL 场景 (单右旋) =====
            if (leftBalance >= 0) {
                node = rotateRightInline(node);
            }
            // ===== [2] LR 场景 (双旋转) =====
            else {
                node.left = rotateLeftInline(leftNode);
                node = rotateRightInline(node);
            }
        } 
        else if (balance < -1) {
            var rightNode:TreeNode = node.right;
            var rightLeftHeight:Number = (rightNode != null && rightNode.left != null)
                ? rightNode.left.height : 0;
            var rightRightHeight:Number = (rightNode != null && rightNode.right != null)
                ? rightNode.right.height : 0;
            var rightBalance:Number = rightLeftHeight - rightRightHeight;

            // ===== [1] RR 场景 (单左旋) =====
            if (rightBalance <= 0) {
                node = rotateLeftInline(node);
            }
            // ===== [2] RL 场景 (双旋转) =====
            else {
                node.right = rotateRightInline(rightNode);
                node = rotateLeftInline(node);
            }
        }
        // -------------------------------------------------------

        return node;
    }

    //==================== 内联旋转相关函数(精简) ====================//
    // 下面两个函数依旧“内联”地做旋转，并把“更新高度”合并在里面
    private function rotateRightInline(y:TreeNode):TreeNode {
        var x:TreeNode = y.left;
        var T2:TreeNode = x.right;

        // 执行右旋
        x.right = y;
        y.left = T2;

        // 更新 y 的高度
        var yLeft:TreeNode = y.left;
        var yRight:TreeNode = y.right; // 其实就是 x, 但为了保持一致性
        var yLeftHeight:Number = (yLeft != null) ? yLeft.height : 0;
        var yRightHeight:Number = (yRight != null) ? yRight.height : 0;
        y.height = 1 + ((yLeftHeight > yRightHeight) ? yLeftHeight : yRightHeight);

        // 更新 x 的高度
        var xLeft:TreeNode = x.left;
        var xRight:TreeNode = x.right;
        var xLeftHeight:Number = (xLeft != null) ? xLeft.height : 0;
        var xRightHeight:Number = (xRight != null) ? xRight.height : 0;
        x.height = 1 + ((xLeftHeight > xRightHeight) ? xLeftHeight : xRightHeight);

        return x;
    }

    private function rotateLeftInline(x:TreeNode):TreeNode {
        var y:TreeNode = x.right;
        var T2:TreeNode = y.left;

        // 执行左旋
        y.left = x;
        x.right = T2;

        // 更新 x 的高度
        var xLeft:TreeNode = x.left;
        var xRight:TreeNode = x.right;  // 其实就是 T2
        var xLeftHeight:Number = (xLeft != null) ? xLeft.height : 0;
        var xRightHeight:Number = (xRight != null) ? xRight.height : 0;
        x.height = 1 + ((xLeftHeight > xRightHeight) ? xLeftHeight : xRightHeight);

        // 更新 y 的高度
        var yLeft:TreeNode = y.left;
        var yRight:TreeNode = y.right;
        var yLeftHeight:Number = (yLeft != null) ? yLeft.height : 0;
        var yRightHeight:Number = (yRight != null) ? yRight.height : 0;
        y.height = 1 + ((yLeftHeight > yRightHeight) ? yLeftHeight : yRightHeight);

        return y;
    }

    //==================== 搜索 & 中序遍历 ====================//
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

    private function inOrderTraversal(node:TreeNode, arr:Array):Void {
        if (node != null) {
            inOrderTraversal(node.left, arr);
            arr.push(node.value);
            inOrderTraversal(node.right, arr);
        }
    }
}
