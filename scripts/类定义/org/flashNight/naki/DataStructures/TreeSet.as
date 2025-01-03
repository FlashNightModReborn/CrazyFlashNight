import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TreeSet {
    private var root:TreeNode;
    private var compareFunction:Function;

    // 构造函数接受一个比较函数
    // compareFunction(a, b) 应返回：
    // - 负数 如果 a < b
    // - 0 如果 a == b
    // - 正数 如果 a > b
    public function TreeSet(compareFunction:Function) {
        if (compareFunction == undefined || compareFunction == null) {
            // 默认比较函数，假设元素具有可比性
            this.compareFunction = function(a, b):Number {
                if (a < b) return -1;
                if (a > b) return 1;
                return 0;
            };
        } else {
            this.compareFunction = compareFunction;
        }
        this.root = null;
    }

    // 添加元素
    public function add(element:Object):Void {
        root = insert(root, element);
    }

    // 移除元素
    public function remove(element:Object):Boolean {
        var initialSize:Number = size();
        root = deleteNode(root, element);
        return size() < initialSize;
    }

    // 是否包含元素
    public function contains(element:Object):Boolean {
        var node:TreeNode = search(root, element);
        return node != null;
    }

    // 获取元素数量
    public function size():Number {
        return getSize(root);
    }

    // 中序遍历，返回一个数组
    public function toArray():Array {
        var arr:Array = [];
        inOrderTraversal(root, arr);
        return arr;
    }

    // 内部方法

    private function insert(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            return new TreeNode(element);
        }

        var cmp:Number = compareFunction(element, node.value);
        if (cmp < 0) {
            node.left = insert(node.left, element);
        } else if (cmp > 0) {
            node.right = insert(node.right, element);
        } else {
            // 元素已存在，忽略或根据需要处理
            return node;
        }

        // 更新高度
        node.height = 1 + Math.max(getHeight(node.left), getHeight(node.right));

        // 获取平衡因子
        var balance:Number = getBalance(node);

        // 检查是否失衡
        if (balance > 1) { // 左子树过高
            if (compareFunction(element, node.left.value) < 0) {
                // 左左情况
                return rightRotate(node);
            } else {
                // 左右情况
                node.left = leftRotate(node.left);
                return rightRotate(node);
            }
        }

        if (balance < -1) { // 右子树过高
            if (compareFunction(element, node.right.value) > 0) {
                // 右右情况
                return leftRotate(node);
            } else {
                // 右左情况
                node.right = rightRotate(node.right);
                return leftRotate(node);
            }
        }

        // 如果节点平衡，无需旋转
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
            // 节点找到
            if (node.left == null || node.right == null) {
                var temp:TreeNode = node.left != null ? node.left : node.right;

                if (temp == null) {
                    // 无子节点
                    temp = node;
                    node = null;
                } else {
                    // 一个子节点
                    node = temp;
                }
            } else {
                // 两个子节点，获取中序后继
                var temp:TreeNode = minValueNode(node.right);
                node.value = temp.value;
                node.right = deleteNode(node.right, temp.value);
            }
        }

        // 如果树只有一个节点
        if (node == null) {
            return node;
        }

        // 更新高度
        node.height = 1 + Math.max(getHeight(node.left), getHeight(node.right));

        // 获取平衡因子
        var balance:Number = getBalance(node);

        // 检查是否失衡
        if (balance > 1) { // 左子树过高
            var leftBalance:Number = getBalance(node.left);
            if (leftBalance >= 0) {
                // 左左情况
                return rightRotate(node);
            } else {
                // 左右情况
                node.left = leftRotate(node.left);
                return rightRotate(node);
            }
        }

        if (balance < -1) { // 右子树过高
            var rightBalance:Number = getBalance(node.right);
            if (rightBalance <= 0) {
                // 右右情况
                return leftRotate(node);
            } else {
                // 右左情况
                node.right = rightRotate(node.right);
                return leftRotate(node);
            }
        }

        // 如果节点平衡，无需旋转
        return node;
}


    private function search(node:TreeNode, element:Object):TreeNode {
        if (node == null) {
            return null;
        }

        var cmp:Number = compareFunction(element, node.value);
        if (cmp < 0) {
            return search(node.left, element);
        } else if (cmp > 0) {
            return search(node.right, element);
        } else {
            return node;
        }
    }

    private function minValueNode(node:TreeNode):TreeNode {
        var current:TreeNode = node;
        while (current.left != null) {
            current = current.left;
        }
        return current;
    }

    private function getHeight(node:TreeNode):Number {
        if (node == null) return 0;
        return node.height;
    }

    private function getBalance(node:TreeNode):Number {
        if (node == null) return 0;
        return getHeight(node.left) - getHeight(node.right);
    }

    private function rightRotate(y:TreeNode):TreeNode {
        var x:TreeNode = y.left;
        var T2:TreeNode = x.right;

        // 旋转
        x.right = y;
        y.left = T2;

        // 更新高度
        y.height = Math.max(getHeight(y.left), getHeight(y.right)) + 1;
        x.height = Math.max(getHeight(x.left), getHeight(x.right)) + 1;

        return x;
    }

    private function leftRotate(x:TreeNode):TreeNode {
        var y:TreeNode = x.right;
        var T2:TreeNode = y.left;

        // 旋转
        y.left = x;
        x.right = T2;

        // 更新高度
        x.height = Math.max(getHeight(x.left), getHeight(x.right)) + 1;
        y.height = Math.max(getHeight(y.left), getHeight(y.right)) + 1;

        return y;
    }

    private function getSize(node:TreeNode):Number {
        if (node == null) return 0;
        return 1 + getSize(node.left) + getSize(node.right);
    }

    private function inOrderTraversal(node:TreeNode, arr:Array):Void {
        if (node != null) {
            inOrderTraversal(node.left, arr);
            arr.push(node.value);
            inOrderTraversal(node.right, arr);
        }
    }
}
