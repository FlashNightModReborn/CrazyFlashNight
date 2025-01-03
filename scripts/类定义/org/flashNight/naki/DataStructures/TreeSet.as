import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.TreeSet {
    private var root:TreeNode;
    private var compareFunction:Function;

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
    }

    public function add(element:Object):Void {
        root = insert(root, element);
    }

    public function remove(element:Object):Boolean {
        var initialSize:Number = size();
        root = deleteNode(root, element);
        return size() < initialSize;
    }

    public function contains(element:Object):Boolean {
        var node:TreeNode = search(root, element);
        return node != null;
    }

    public function size():Number {
        return getSize(root);
    }

    public function toArray():Array {
        var arr:Array = [];
        inOrderTraversal(root, arr);
        return arr;
    }

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
            return node;
        }

        var leftChild:TreeNode = node.left;
        var rightChild:TreeNode = node.right;
        var leftHeight:Number = leftChild != null ? leftChild.height : 0;
        var rightHeight:Number = rightChild != null ? rightChild.height : 0;
        node.height = 1 + (leftHeight > rightHeight ? leftHeight : rightHeight);

        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            var leftChild2:TreeNode = node.left;
            if (leftChild2 != null) {
                var cmpLeft:Number = compareFunction(element, leftChild2.value);
                if (cmpLeft < 0) {
                    return rightRotate(node);
                } else {
                    node.left = leftRotate(node.left);
                    return rightRotate(node);
                }
            }
        }

        if (balance < -1) {
            var rightChild2:TreeNode = node.right;
            if (rightChild2 != null) {
                var cmpRight:Number = compareFunction(element, rightChild2.value);
                if (cmpRight > 0) {
                    return leftRotate(node);
                } else {
                    node.right = rightRotate(node.right);
                    return leftRotate(node);
                }
            }
        }

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
            if (node.left == null || node.right == null) {
                var temp:TreeNode = node.left != null ? node.left : node.right;
                if (temp == null) {
                    temp = node;
                    node = null;
                } else {
                    node = temp;
                }
            } else {
                var temp:TreeNode = node.right;
                while (temp.left != null) {
                    temp = temp.left;
                }
                node.value = temp.value;
                node.right = deleteNode(node.right, temp.value);
            }
        }

        if (node == null) {
            return node;
        }

        var leftChild:TreeNode = node.left;
        var rightChild:TreeNode = node.right;
        var leftHeight:Number = leftChild != null ? leftChild.height : 0;
        var rightHeight:Number = rightChild != null ? rightChild.height : 0;
        node.height = 1 + (leftHeight > rightHeight ? leftHeight : rightHeight);

        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            var leftChild2:TreeNode = node.left;
            var leftLeftHeight:Number = leftChild2 != null && leftChild2.left != null ? leftChild2.left.height : 0;
            var leftRightHeight:Number = leftChild2 != null && leftChild2.right != null ? leftChild2.right.height : 0;
            var leftBalance:Number = leftLeftHeight - leftRightHeight;
            if (leftBalance >= 0) {
                return rightRotate(node);
            } else {
                node.left = leftRotate(node.left);
                return rightRotate(node);
            }
        }

        if (balance < -1) {
            var rightChild2:TreeNode = node.right;
            var rightLeftHeight:Number = rightChild2 != null && rightChild2.left != null ? rightChild2.left.height : 0;
            var rightRightHeight:Number = rightChild2 != null && rightChild2.right != null ? rightChild2.right.height : 0;
            var rightBalance:Number = rightLeftHeight - rightRightHeight;
            if (rightBalance <= 0) {
                return leftRotate(node);
            } else {
                node.right = rightRotate(node.right);
                return leftRotate(node);
            }
        }

        return node;
    }

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

    private function rightRotate(y:TreeNode):TreeNode {
        var x:TreeNode = y.left;
        var T2:TreeNode = x.right;

        x.right = y;
        y.left = T2;

        var yLeft:TreeNode = y.left;
        var yRight:TreeNode = y.right;
        var yLeftHeight:Number = yLeft != null ? yLeft.height : 0;
        var yRightHeight:Number = yRight != null ? yRight.height : 0;
        y.height = 1 + (yLeftHeight > yRightHeight ? yLeftHeight : yRightHeight);

        var xLeft:TreeNode = x.left;
        var xRight:TreeNode = x.right;
        var xLeftHeight:Number = xLeft != null ? xLeft.height : 0;
        var xRightHeight:Number = xRight != null ? xRight.height : 0;
        x.height = 1 + (xLeftHeight > xRightHeight ? xLeftHeight : xRightHeight);

        return x;
    }

    private function leftRotate(x:TreeNode):TreeNode {
        var y:TreeNode = x.right;
        var T2:TreeNode = y.left;

        y.left = x;
        x.right = T2;

        var xLeft:TreeNode = x.left;
        var xRight:TreeNode = x.right;
        var xLeftHeight:Number = xLeft != null ? xLeft.height : 0;
        var xRightHeight:Number = xRight != null ? xRight.height : 0;
        x.height = 1 + (xLeftHeight > xRightHeight ? xLeftHeight : xRightHeight);

        var yLeft:TreeNode = y.left;
        var yRight:TreeNode = y.right;
        var yLeftHeight:Number = yLeft != null ? yLeft.height : 0;
        var yRightHeight:Number = yRight != null ? yRight.height : 0;
        y.height = 1 + (yLeftHeight > yRightHeight ? yLeftHeight : yRightHeight);

        return y;
    }
}