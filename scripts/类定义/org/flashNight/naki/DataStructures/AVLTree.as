import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;


/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║                              AVLTree (AVL树)                                 ║
 * ║                    经典自平衡二叉搜索树 ActionScript 2 实现                    ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 *
 * @class AVLTree
 * @package org.flashNight.naki.DataStructures
 * @author flashNight
 * @version 1.0
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                   理论背景
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * AVL 树由 Adelson-Velsky 和 Landis 于 1962 年提出，是最早的自平衡二叉搜索树。
 *
 * 【核心特性】
 * - 使用 "height" 维护平衡 
 * - 任意节点的左右子树高度差（平衡因子）不超过 1
 * - 最坏情况树高约 1.44 log(n)，保证 O(log n) 操作
 *
 * 【AVL 不变量】
 * 1. 平衡因子 = 左子树高度 - 右子树高度
 * 2. 平衡因子 ∈ {-1, 0, 1}
 * 3. 空节点高度为 0，叶子节点高度为 1
 *
 * 【性能特性】
 * ┌─────────────┬────────────┬────────────┐
 * │    操作     │  平均复杂度 │  最坏复杂度 │
 * ├─────────────┼────────────┼────────────┤
 * │ 查找        │ O(log n)   │ O(log n)   │
 * │ 插入        │ O(log n)   │ O(log n)   │
 * │ 删除        │ O(log n)   │ O(log n)   │
 * │ 旋转(插入)  │ O(1) 摊还  │ O(log n)   │
 * │ 旋转(删除)  │ O(log n)   │ O(log n)   │
 * └─────────────┴────────────┴────────────┘
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                AS2 优化技术
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * 【优化 1: 比较函数缓存】
 * 将 this.compareFunction 缓存到局部变量，避免递归中反复的作用域链查找。
 *
 * 【优化 2: 差分高度更新】
 * 记录旧高度，若更新后高度未变则可提前退出，无需继续回溯检查平衡。
 *
 * 【优化 3: deleteMin 专用函数】
 * 删除双子节点时，使用 deleteMin 直接下潜最左侧，避免二次搜索比较。
 *
 * 【优化 4: 迭代式遍历】
 * toArray/toString 使用显式栈代替递归，减少函数调用开销。
 *
 * ════════════════════════════════════════════════════════════════════════════════
 */
class org.flashNight.naki.DataStructures.AVLTree
        extends AbstractBalancedSearchTree
        implements IBalancedSearchTree {

    private var root:AVLNode; // 树的根节点

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较
     */
    public function AVLTree(compareFunction:Function) {
        super(compareFunction); // 调用基类构造函数，初始化 _compareFunction 和 _treeSize
        this.root = null; // 初始化根节点为空
    }

    /**
     * [静态方法] 从给定数组构建一个新的平衡 AVL 树。
     *   1. 先对输入数组排序
     *   2. 使用分治法一次性构建平衡树，避免逐个插入导致的大量旋转
     * @param arr 输入的元素数组，需为可排序的类型
     * @param compareFunction 用于排序的比较函数
     * @return 新构建的 AVLTree 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):AVLTree {
        var tree:AVLTree = new AVLTree(compareFunction);
        // 使用 TimSort 排序输入数组，确保数组有序以便分治法构建平衡树
        TimSort.sort(arr, compareFunction);
        // 使用分治法构建平衡 AVL 树
        tree.root = tree.buildBalancedTree(arr, 0, arr.length - 1);
        // 设置树的大小为数组长度
        tree._treeSize = arr.length;
        return tree;
    }

    /**
     * [实例方法] 更换当前 AVLTree 的比较函数，并对所有数据重新排序和建树。
     * 适用于需要动态更改排序规则的场景。
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        // 1. 更新比较函数
        _compareFunction = newCompareFunction;

        // 2. 导出所有节点到数组，准备重新排序
        var arr:Array = this.toArray();

        // 3. 使用新的比较函数对数组进行排序
        TimSort.sort(arr, newCompareFunction);

        // 4. 使用分治法重建平衡 AVL 树
        this.root = buildBalancedTree(arr, 0, arr.length - 1);
        _treeSize = arr.length;
    }

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     *
     * 【优化】将比较函数缓存到局部变量，避免递归中反复访问 this.compareFunction
     */
    public function add(element:Object):Void {
        var cmpFn:Function = _compareFunction;
        this.root = insert(this.root, element, cmpFn);
    }

    /**
     * 移除元素
     * @param element 要移除的元素
     * @return 如果成功移除元素则返回 true，否则返回 false
     *
     * 【优化】将比较函数缓存到局部变量，避免递归中反复访问 this.compareFunction
     */
    public function remove(element:Object):Boolean {
        var oldSize:Number = _treeSize;
        var cmpFn:Function = _compareFunction;
        this.root = deleteNode(this.root, element, cmpFn);
        return (_treeSize < oldSize);
    }

    /**
     * 检查树中是否包含某个元素
     * @param element 要检查的元素
     * @return 如果树中包含该元素则返回 true，否则返回 false
     *
     * 【优化】内联搜索逻辑 + 缓存比较函数到局部变量，避免函数调用开销
     */
    public function contains(element:Object):Boolean {
        var current:AVLNode = this.root;
        var cmpFn:Function = _compareFunction;

        while (current != null) {
            var cmp:Number = cmpFn(element, current.value);
            if (cmp < 0) {
                current = current.left;
            } else if (cmp > 0) {
                current = current.right;
            } else {
                return true;
            }
        }
        return false;
    }

    // size() 和 isEmpty() 由基类 AbstractBalancedSearchTree 提供

    /**
     * 中序遍历转换为数组
     * @return 一个按升序排列的元素数组
     *
     * 【优化】预分配数组空间 + 使用独立索引，避免动态扩容和 arr.length 读取开销
     */
    public function toArray():Array {
        var arr:Array = new Array(_treeSize);  // 【优化】预分配数组空间
        var arrIdx:Number = 0;                      // 【优化】独立索引，避免 arr.length 读取
        var stack:Array = [];                       // 模拟堆栈
        var stackIdx:Number = 0;                    // 堆栈索引
        var node:AVLNode = this.root;               // 当前节点

        while (node != null || stackIdx > 0) {
            // 模拟递归，处理左子树
            while (node != null) {
                stack[stackIdx++] = node;   // 将当前节点压入堆栈
                node = node.left;           // 移动到左子树
            }

            // 取出堆栈中的节点
            node = stack[--stackIdx];       // 弹出栈顶节点
            arr[arrIdx++] = node.value;     // 【优化】使用独立索引

            // 移动到右子树继续处理
            node = node.right;
        }

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

    /**
     * 返回 AVL 树的字符串表示，基于前序遍历
     * @return 树的前序遍历字符串
     */
    public function toString():String {
        var str:String = "";
        var stack:Array = [];    // 模拟堆栈
        var index:Number = 0;    // 堆栈索引
        var node:AVLNode = this.root; // 当前节点

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
     * @param cmpFn 比较函数（参数传递优化，避免每层递归访问 this.compareFunction）
     * @return 插入后的节点
     */
    private function insert(node:AVLNode, element:Object, cmpFn:Function):AVLNode {
        if (node == null) {
            // 找到插入位置，创建新节点
            _treeSize++;
            return new AVLNode(element);
        }

        // 1. 递归插入（使用传入的 cmpFn 而非 this.compareFunction）
        var cmp:Number = cmpFn(element, node.value);
        if (cmp < 0) {
            // 元素小于当前节点，递归插入左子树
            node.left = insert(node.left, element, cmpFn);
        } else if (cmp > 0) {
            // 元素大于当前节点，递归插入右子树
            node.right = insert(node.right, element, cmpFn);
        } else {
            // 元素已存在，直接返回当前节点
            return node;
        }

        // 2. 更新高度前，记录旧高度
        var oldHeight:Number = node.height;

        // 3. 计算左右子树高度并更新当前节点高度
        var leftNode:AVLNode   = node.left;
        var rightNode:AVLNode  = node.right;
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
            var childLeftNode:AVLNode   = leftNode.left;
            var childRightNode:AVLNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;

            // 根据子树平衡因子决定旋转类型
            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高，需要判断是 RR 型还是 RL 型
            var rLeftNode:AVLNode       = rightNode.left;
            var rRightNode:AVLNode      = rightNode.right;
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
     * @param cmpFn 比较函数（参数传递优化，避免每层递归访问 this.compareFunction）
     * @return 删除后的节点
     */
    private function deleteNode(node:AVLNode, element:Object, cmpFn:Function):AVLNode {
        if (node == null) {
            // 元素不存在于树中，直接返回 null
            return null;
        }

        // 1. 递归删除（使用传入的 cmpFn 而非 this.compareFunction）
        var cmp:Number = cmpFn(element, node.value);
        if (cmp < 0) {
            // 元素小于当前节点，递归删除左子树
            node.left = deleteNode(node.left, element, cmpFn);
        } else if (cmp > 0) {
            // 元素大于当前节点，递归删除右子树
            node.right = deleteNode(node.right, element, cmpFn);
        } else {
            // 找到要删除的节点
            if (node.left == null || node.right == null) {
                // 处理无子节点或单子节点情况
                _treeSize--;
                node = (node.left != null) ? node.left : node.right;
            } else {
                // 处理双子节点情况：使用 deleteMin 优化，避免二次搜索
                var succ:AVLNode = node.right;
                while (succ.left != null) {
                    succ = succ.left;
                }
                node.value = succ.value;
                // 【优化】使用 deleteMin 直接删除最小节点，无需比较
                node.right = deleteMin(node.right);
            }
        }

        // 2. 如果当前子树已被删空，无需再平衡
        if (node == null) {
            return null;
        }

        // 3. 计算左右子树高度并更新当前节点高度
        var leftNode:AVLNode   = node.left;
        var rightNode:AVLNode  = node.right;
        var leftHeight:Number   = (leftNode != null) ? leftNode.height : 0;
        var rightHeight:Number  = (rightNode != null) ? rightNode.height : 0;
        var newHeight:Number    = (leftHeight > rightHeight) ? leftHeight : rightHeight;
        ++newHeight;

        // 更新节点高度
        node.height = newHeight;

        // 4. 检查平衡因子
        // 【注意】删除操作中，即使高度没变，平衡因子也可能变化！
        // 例如：左子树从 h=1 变为 null(h=0)，右子树保持 h=2
        //      高度 max(1,2)+1=3 -> max(0,2)+1=3 不变
        //      但平衡因子从 -1 变为 -2，需要旋转
        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            // 左侧高，需要判断是 LL 型还是 LR 型
            var childLeftNode:AVLNode   = leftNode.left;
            var childRightNode:AVLNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;

            // 根据子树平衡因子决定旋转类型
            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高，需要判断是 RR 型还是 RL 型
            var rLeftNode:AVLNode       = rightNode.left;
            var rRightNode:AVLNode      = rightNode.right;
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
    private function search(node:AVLNode, element:Object):AVLNode {
        var current:AVLNode = node;
        while (current != null) {
            var cmp:Number = _compareFunction(element, current.value);
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
     * 【优化】删除子树中的最小节点（专用于双子节点删除场景）
     *
     * 设计目的：避免 deleteNode 中双子节点删除时的二次搜索
     * - 无需比较函数：直接一路向左下潜
     * - 单次遍历：找到即删除
     *
     * @param node 子树的根节点
     * @return 删除最小节点后的子树根节点
     */
    private function deleteMin(node:AVLNode):AVLNode {
        // 找到最小节点（最左侧节点，其 left 为 null）
        if (node.left == null) {
            _treeSize--;
            return node.right;  // 用右子替代（可能为 null）
        }

        // 递归下潜到最左侧
        node.left = deleteMin(node.left);

        // 计算左右子树高度并更新当前节点高度
        var leftNode:AVLNode   = node.left;
        var rightNode:AVLNode  = node.right;
        var leftHeight:Number   = (leftNode != null) ? leftNode.height : 0;
        var rightHeight:Number  = (rightNode != null) ? rightNode.height : 0;
        var newHeight:Number    = (leftHeight > rightHeight) ? leftHeight : rightHeight;
        ++newHeight;

        // 更新节点高度
        node.height = newHeight;

        // 检查平衡因子并作旋转
        // 【注意】删除操作中必须始终检查平衡因子
        var balance:Number = leftHeight - rightHeight;

        if (balance > 1) {
            // 左侧高
            var childLeftNode:AVLNode   = leftNode.left;
            var childRightNode:AVLNode  = leftNode.right;
            var childLeftHeight:Number   = (childLeftNode  != null) ? childLeftNode.height  : 0;
            var childRightHeight:Number  = (childRightNode != null) ? childRightNode.height : 0;
            var leftBalance:Number       = childLeftHeight - childRightHeight;
            node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
        } else if (balance < -1) {
            // 右侧高
            var rLeftNode:AVLNode       = rightNode.left;
            var rRightNode:AVLNode      = rightNode.right;
            var rLeftHeight:Number       = (rLeftNode  != null) ? rLeftNode.height  : 0;
            var rRightHeight:Number      = (rRightNode != null) ? rRightNode.height : 0;
            var rightBalance:Number      = rLeftHeight - rRightHeight;
            node = rightBalance <= 0 ? rotateRR(node) : rotateRL(node);
        }

        return node;
    }

    /**
     * 中序遍历，将节点依次添加到数组 arr 中
     * @param node 当前递归到的节点
     * @param arr 存储遍历结果的数组
     */
    private function inOrderTraversal(node:AVLNode, arr:Array):Void {
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
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number):AVLNode {
        if (start > end) {
            // 子数组为空，返回 null
            return null;
        }
        // 选择中间元素作为当前子树的根节点，确保平衡
        var mid:Number = (start + end) >> 1; // 等同于 Math.floor((start + end) / 2)
        var newNode:AVLNode = new AVLNode(sortedArr[mid]);

        // 递归构建左子树和右子树
        newNode.left = buildBalancedTree(sortedArr, start, mid - 1);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end);

        // 更新当前节点的高度，根据左右子树高度决定
        var leftNode:AVLNode = newNode.left;
        var rightNode:AVLNode = newNode.right;
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
    private function rotateLL(node:AVLNode):AVLNode {
        var leftNode:AVLNode = node.left;
        // 右旋操作
        node.left = leftNode.right;
        leftNode.right = node;

        // 局部化变量以减少属性解引用，提高访问速度
        var nodeLeft:AVLNode = node.left;
        var nodeRight:AVLNode = node.right; // 右旋后，node.right 即为 leftNode.right => node
        var leftLeft:AVLNode = leftNode.left;
        var leftRight:AVLNode = leftNode.right;

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
    private function rotateRR(node:AVLNode):AVLNode {
        var rightNode:AVLNode = node.right;
        // 左旋操作
        node.right = rightNode.left;
        rightNode.left = node;

        // 局部化变量以减少属性解引用，提高访问速度
        var nodeLeft:AVLNode = node.left;
        var nodeRight:AVLNode = node.right; // 左旋后，node.right 即为 rightNode.left => node
        var rightLeft:AVLNode = rightNode.left;
        var rightRight:AVLNode = rightNode.right;

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
    private function rotateLR(node:AVLNode):AVLNode {
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
    private function rotateRL(node:AVLNode):AVLNode {
        // 先对右子树做 LL 旋转
        node.right = rotateLL(node.right);
        // 再对当前节点做 RR 旋转
        return rotateRR(node);
    }
}
