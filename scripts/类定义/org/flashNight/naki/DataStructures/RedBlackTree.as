import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;
 
/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║                           RedBlackTree (红黑树)                               ║
 * ║                    高性能自平衡二叉搜索树 ActionScript 2 实现                    ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 *
 * @class RedBlackTree
 * @package org.flashNight.naki.DataStructures
 * @version 2.0 (优化版)
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                   优化记录
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * 【优化 1: 移除 contains() 预检查】
 * 原实现在 remove() 中先调用 contains() 检查元素是否存在，导致 2 倍搜索开销。
 * 现改用 size 差检测：删除前记录 oldSize，删除后比较 _treeSize 是否减少。
 *
 * 【优化 2: 比较函数参数传递】
 * AS2 的 this.xxx 属性访问涉及作用域链查找，代价远高于局部变量。
 * 将 _compareFunction 缓存并作为参数传递给递归函数。
 *
 * 【优化 3: 分治法 buildFromArray】
 * 原实现使用逐个插入 O(n log n)，现改用分治法 O(n) 直接构建平衡树。
 * 由于红黑树需要满足颜色约束，采用层级着色策略。
 *
 * 【优化 4: 迭代式遍历】
 * toArray 和 contains 使用迭代而非递归，减少函数调用开销。
 *
 * 【优化 5: 减少重复比较】
 * 删除操作中优化控制流，减少不必要的重复 cmp 计算。
 *
 * ════════════════════════════════════════════════════════════════════════════════
 *                                  未采用的优化
 * ════════════════════════════════════════════════════════════════════════════════
 *
 * 【已验证无效: 内联小函数】
 * 尝试将 isRed、rotateLeft、rotateRight、flipColors、moveRedLeft、moveRedRight
 * 等辅助函数内联到 insert 和 deleteNode 中，以减少函数调用开销。
 * 实测结果：性能几乎无变化，但代码可维护性大幅下降。
 * 结论：保留独立函数形式，优先可读性。
 *
 * ════════════════════════════════════════════════════════════════════════════════
 */
class org.flashNight.naki.DataStructures.RedBlackTree
        extends AbstractBalancedSearchTree
        implements IBalancedSearchTree {

    private var root:RedBlackNode; // 树的根节点

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较
     */
    public function RedBlackTree(compareFunction:Function) {
        super(compareFunction); // 调用基类构造函数，初始化 _compareFunction 和 _treeSize
        this.root = null; // 初始化根节点为空
    }

    /**
     * [静态方法] 从给定数组构建一个新的红黑树。
     * 【优化】使用分治法 O(n) 直接构建，而非逐个插入 O(n log n)
     *
     * 【注意】此方法将数组视为集合，会自动去除重复元素。
     * 返回的树的 size() 等于去重后的元素数量，可能小于原数组长度。
     *
     * @param arr 输入的元素数组，需为可排序的类型（会被原地排序）
     * @param compareFunction 用于排序和去重的比较函数
     * @return 新构建的 RedBlackTree 实例，包含去重后的元素
     */
    public static function buildFromArray(arr:Array, compareFunction:Function):RedBlackTree {
        var rbTree:RedBlackTree = new RedBlackTree(compareFunction);

        if (arr.length == 0) {
            return rbTree;
        }

        // 使用 TimSort 排序输入数组
        TimSort.sort(arr, compareFunction);

        // 去除重复元素
        var uniqueArr:Array = [arr[0]];
        for (var i:Number = 1; i < arr.length; i++) {
            if (compareFunction(arr[i], arr[i-1]) != 0) {
                uniqueArr.push(arr[i]);
            }
        }

        // 【优化】使用分治法构建平衡红黑树
        var maxDepth:Number = rbTree.calculateMaxDepth(uniqueArr.length);
        rbTree.root = rbTree.buildBalancedTree(uniqueArr, 0, uniqueArr.length - 1, 0, maxDepth);
        rbTree._treeSize = uniqueArr.length;

        // 确保根节点为黑色
        if (rbTree.root != null) {
            rbTree.root.color = RedBlackNode.BLACK;
        }

        return rbTree;
    }

    /**
     * [实例方法] 更换当前 RedBlackTree 的比较函数，并对所有数据重新排序和建树。
     * 【优化】使用分治法重建，而非逐个插入
     *
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        // 1. 导出所有节点到数组
        var arr:Array = this.toArray();

        // 2. 更新比较函数
        _compareFunction = newCompareFunction;

        // 3. 使用新的比较函数对数组进行排序
        TimSort.sort(arr, newCompareFunction);

        // 4. 【优化】使用分治法重建树
        var maxDepth:Number = calculateMaxDepth(arr.length);
        this.root = buildBalancedTree(arr, 0, arr.length - 1, 0, maxDepth);
        _treeSize = arr.length;

        // 确保根节点为黑色
        if (this.root != null) {
            this.root.color = RedBlackNode.BLACK;
        }
    }

    /**
     * 添加元素到树中
     * 【优化】使用参数传递比较函数
     *
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        this.root = insert(this.root, element, _compareFunction);
        // 确保根节点为黑色
        this.root.color = RedBlackNode.BLACK;
    }

    /**
     * 移除元素
     * 【优化】移除 contains() 预检查，改用 size 差检测
     *
     * @param element 要移除的元素
     * @return 如果成功移除元素则返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        // 空树直接返回
        if (this.root == null) {
            return false;
        }

        // 【优化】记录旧 size，用于判断是否删除成功
        var oldSize:Number = _treeSize;

        // 特殊情况: 如果根节点是唯一节点
        if (_treeSize == 1) {
            if (_compareFunction(this.root.value, element) == 0) {
                this.root = null;
                _treeSize = 0;
                return true;
            }
            return false;
        }

        // 一般情况: 将根处的节点设为红色以便删除操作
        if (!isRed(this.root.left) && !isRed(this.root.right)) {
            this.root.color = RedBlackNode.RED;
        }

        // 【优化】传递比较函数参数
        this.root = deleteNode(this.root, element, _compareFunction);

        // 确保根节点为黑色
        if (this.root != null) {
            this.root.color = RedBlackNode.BLACK;
        }

        // 【优化】通过 size 变化判断是否删除成功
        return (_treeSize < oldSize);
    }

    /**
     * 检查树中是否包含某个元素
     * 【优化】内联搜索 + 缓存比较函数到局部变量
     *
     * @param element 要检查的元素
     * @return 如果树中包含该元素则返回 true，否则返回 false
     */
    public function contains(element:Object):Boolean {
        var current:RedBlackNode = this.root;
        var cmpFn:Function = _compareFunction;  // 【优化】缓存到局部变量

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
     * 【优化】使用迭代式遍历 + 预分配数组
     *
     * @return 一个按升序排列的元素数组
     */
    public function toArray():Array {
        // 【优化】预分配数组空间
        var arr:Array = new Array(_treeSize);
        var arrIdx:Number = 0;

        var stack:Array = [];
        var stackIdx:Number = 0;
        var node:RedBlackNode = this.root;

        // 迭代式中序遍历
        while (node != null || stackIdx > 0) {
            while (node != null) {
                stack[stackIdx++] = node;
                node = node.left;
            }
            node = stack[--stackIdx];
            arr[arrIdx++] = node.value;
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
     * 返回红黑树的字符串表示，基于前序遍历
     * @return 树的前序遍历字符串
     */
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

    //======================== 私有辅助函数 ========================//

    /**
     * 【优化】迭代式插入新元素，并保持红黑树性质
     * 使用显式栈替代递归，减少函数调用开销
     *
     * @param node 树的根节点
     * @param element 要插入的元素
     * @param cmpFn 比较函数
     * @return 插入后的新根节点
     */
    private function insert(node:RedBlackNode, element:Object, cmpFn:Function):RedBlackNode {
        // 空树，直接创建根节点
        if (node == null) {
            _treeSize++;
            return new RedBlackNode(element);
        }

        // ============ 阶段1: 向下搜索插入位置，记录路径 ============
        var stack:Array = [];      // 父节点栈
        var dirs:Array = [];       // 方向栈：0=左，1=右
        var stackIdx:Number = 0;
        var current:RedBlackNode = node;
        var cmp:Number;

        while (current != null) {
            cmp = cmpFn(element, current.value);

            if (cmp == 0) {
                // 元素已存在，不插入
                return node;
            }

            // 记录当前节点和方向
            stack[stackIdx] = current;

            if (cmp < 0) {
                dirs[stackIdx] = 0;  // 左
                stackIdx++;
                current = current.left;
            } else {
                dirs[stackIdx] = 1;  // 右
                stackIdx++;
                current = current.right;
            }
        }

        // ============ 阶段2: 创建新节点并链接到父节点 ============
        var newNode:RedBlackNode = new RedBlackNode(element);
        _treeSize++;

        // 链接到父节点
        var parent:RedBlackNode = stack[stackIdx - 1];
        if (dirs[stackIdx - 1] == 0) {
            parent.left = newNode;
        } else {
            parent.right = newNode;
        }

        // ============ 阶段3: 向上回溯修复红黑树性质 ============
        // 从新节点的父节点开始向上修复
        var child:RedBlackNode;
        var fixedNode:RedBlackNode;
        var leftChild:RedBlackNode;
        var rightChild:RedBlackNode;

        while (stackIdx > 0) {
            stackIdx--;
            current = stack[stackIdx];

            // 内联修复逻辑（避免函数调用）
            leftChild = current.left;
            rightChild = current.right;

            // 情况1：右子节点为红色，左子节点为黑色 - 左旋转
            if (rightChild != null && rightChild.color == RedBlackNode.RED &&
                (leftChild == null || leftChild.color == RedBlackNode.BLACK)) {
                // 内联 rotateLeft
                current.right = rightChild.left;
                rightChild.left = current;
                rightChild.color = current.color;
                current.color = RedBlackNode.RED;
                current = rightChild;
                // 更新引用
                leftChild = current.left;
                rightChild = current.right;
            }

            // 情况2：连续两个左红子节点 - 右旋转
            leftChild = current.left;
            if (leftChild != null && leftChild.color == RedBlackNode.RED &&
                leftChild.left != null && leftChild.left.color == RedBlackNode.RED) {
                // 内联 rotateRight
                current.left = leftChild.right;
                leftChild.right = current;
                leftChild.color = current.color;
                current.color = RedBlackNode.RED;
                current = leftChild;
                // 更新引用
                leftChild = current.left;
                rightChild = current.right;
            }

            // 情况3：左右子节点都为红色 - 颜色翻转
            leftChild = current.left;
            rightChild = current.right;
            if (leftChild != null && leftChild.color == RedBlackNode.RED &&
                rightChild != null && rightChild.color == RedBlackNode.RED) {
                // 内联 flipColors
                current.color = !current.color;
                leftChild.color = !leftChild.color;
                rightChild.color = !rightChild.color;
            }

            // 更新父节点的子链接
            if (stackIdx > 0) {
                parent = stack[stackIdx - 1];
                if (dirs[stackIdx - 1] == 0) {
                    parent.left = current;
                } else {
                    parent.right = current;
                }
            } else {
                // 到达根节点
                node = current;
            }
        }

        return node;
    }

    /**
     * 【优化】迭代式删除元素，并保持红黑树性质
     * 使用显式栈替代递归，减少函数调用开销
     *
     * @param node 树的根节点
     * @param element 要删除的元素
     * @param cmpFn 比较函数
     * @return 删除后的新根节点
     */
    private function deleteNode(node:RedBlackNode, element:Object, cmpFn:Function):RedBlackNode {
        if (node == null) {
            return null;
        }

        // ============ 阶段1: 向下搜索，记录路径，沿途进行变换 ============
        var stack:Array = [];      // 节点栈
        var dirs:Array = [];       // 方向栈：0=左，1=右
        var stackIdx:Number = 0;
        var current:RedBlackNode = node;
        var cmp:Number;
        var found:Boolean = false;
        var x:RedBlackNode;        // 临时变量用于旋转

        while (current != null) {
            cmp = cmpFn(element, current.value);

            if (cmp < 0) {
                // 目标在左子树
                if (current.left == null) {
                    // 未找到目标，退出
                    break;
                }

                // moveRedLeft 变换（内联）
                if (current.left.color != RedBlackNode.RED) {
                    var leftLeft:RedBlackNode = current.left.left;
                    if (leftLeft == null || leftLeft.color != RedBlackNode.RED) {
                        // flipColors
                        current.color = !current.color;
                        current.left.color = !current.left.color;
                        if (current.right != null) current.right.color = !current.right.color;

                        if (current.right != null && current.right.left != null &&
                            current.right.left.color == RedBlackNode.RED) {
                            // rotateRight(current.right)
                            x = current.right.left;
                            current.right.left = x.right;
                            x.right = current.right;
                            x.color = current.right.color;
                            current.right.color = RedBlackNode.RED;
                            current.right = x;

                            // rotateLeft(current)
                            x = current.right;
                            current.right = x.left;
                            x.left = current;
                            x.color = current.color;
                            current.color = RedBlackNode.RED;
                            current = x;

                            // flipColors
                            current.color = !current.color;
                            if (current.left != null) current.left.color = !current.left.color;
                            if (current.right != null) current.right.color = !current.right.color;
                        }
                    }
                }

                stack[stackIdx] = current;
                dirs[stackIdx] = 0;
                stackIdx++;
                current = current.left;

            } else {
                // cmp >= 0，目标可能在当前节点或右子树

                // 如果左孩子是红的，先右旋
                if (current.left != null && current.left.color == RedBlackNode.RED) {
                    x = current.left;
                    current.left = x.right;
                    x.right = current;
                    x.color = current.color;
                    current.color = RedBlackNode.RED;
                    current = x;
                    // 旋转后重新计算 cmp
                    cmp = cmpFn(element, current.value);
                }

                // cmp == 0 并且没有右子：直接删
                if (cmp == 0 && current.right == null) {
                    _treeSize--;
                    found = true;
                    current = null;  // 标记为删除
                    break;
                }

                // 需要继续向右
                if (current.right == null) {
                    // 未找到目标
                    break;
                }

                // moveRedRight 变换（内联）
                if (current.right.color != RedBlackNode.RED) {
                    var rightLeft:RedBlackNode = current.right.left;
                    if (rightLeft == null || rightLeft.color != RedBlackNode.RED) {
                        // flipColors
                        current.color = !current.color;
                        if (current.left != null) current.left.color = !current.left.color;
                        current.right.color = !current.right.color;

                        if (current.left != null && current.left.left != null &&
                            current.left.left.color == RedBlackNode.RED) {
                            // rotateRight(current)
                            x = current.left;
                            current.left = x.right;
                            x.right = current;
                            x.color = current.color;
                            current.color = RedBlackNode.RED;
                            current = x;

                            // flipColors
                            current.color = !current.color;
                            if (current.left != null) current.left.color = !current.left.color;
                            if (current.right != null) current.right.color = !current.right.color;
                        }
                        // 变换后重新计算 cmp
                        cmp = cmpFn(element, current.value);
                    }
                }

                if (cmp == 0) {
                    // 找到目标节点，用后继替换
                    var successor:RedBlackNode = current.right;
                    while (successor.left != null) {
                        successor = successor.left;
                    }
                    current.value = successor.value;
                    // 切换为删除后继（右子树的最小值）
                    element = successor.value;
                    found = true;

                    stack[stackIdx] = current;
                    dirs[stackIdx] = 1;
                    stackIdx++;
                    current = current.right;

                    // 现在需要删除右子树的最小节点（deleteMin）
                    while (current.left != null) {
                        // moveRedLeft 变换（内联）
                        if (current.left.color != RedBlackNode.RED) {
                            leftLeft = current.left.left;
                            if (leftLeft == null || leftLeft.color != RedBlackNode.RED) {
                                // flipColors
                                current.color = !current.color;
                                current.left.color = !current.left.color;
                                if (current.right != null) current.right.color = !current.right.color;

                                if (current.right != null && current.right.left != null &&
                                    current.right.left.color == RedBlackNode.RED) {
                                    // rotateRight(current.right)
                                    x = current.right.left;
                                    current.right.left = x.right;
                                    x.right = current.right;
                                    x.color = current.right.color;
                                    current.right.color = RedBlackNode.RED;
                                    current.right = x;

                                    // rotateLeft(current)
                                    x = current.right;
                                    current.right = x.left;
                                    x.left = current;
                                    x.color = current.color;
                                    current.color = RedBlackNode.RED;
                                    current = x;

                                    // flipColors
                                    current.color = !current.color;
                                    if (current.left != null) current.left.color = !current.left.color;
                                    if (current.right != null) current.right.color = !current.right.color;
                                }
                            }
                        }

                        stack[stackIdx] = current;
                        dirs[stackIdx] = 0;
                        stackIdx++;
                        current = current.left;
                    }
                    // 到达最小节点，删除它
                    _treeSize--;
                    current = null;
                    break;
                } else {
                    // 继续向右搜索
                    stack[stackIdx] = current;
                    dirs[stackIdx] = 1;
                    stackIdx++;
                    current = current.right;
                }
            }
        }

        // ============ 阶段2: 向上回溯修复红黑树性质 ============
        var child:RedBlackNode = current;
        var parent:RedBlackNode;
        var leftChild:RedBlackNode;
        var rightChild:RedBlackNode;

        while (stackIdx > 0) {
            stackIdx--;
            current = stack[stackIdx];

            // 重新链接子节点
            if (dirs[stackIdx] == 0) {
                current.left = child;
            } else {
                current.right = child;
            }

            // 修复平衡（内联）
            // rotateLeft if right is red
            rightChild = current.right;
            if (rightChild != null && rightChild.color == RedBlackNode.RED) {
                current.right = rightChild.left;
                rightChild.left = current;
                rightChild.color = current.color;
                current.color = RedBlackNode.RED;
                current = rightChild;
            }

            // rotateRight if left and left.left are both red
            leftChild = current.left;
            if (leftChild != null && leftChild.color == RedBlackNode.RED &&
                leftChild.left != null && leftChild.left.color == RedBlackNode.RED) {
                current.left = leftChild.right;
                leftChild.right = current;
                leftChild.color = current.color;
                current.color = RedBlackNode.RED;
                current = leftChild;
            }

            // flipColors if both children are red
            leftChild = current.left;
            rightChild = current.right;
            if (leftChild != null && leftChild.color == RedBlackNode.RED &&
                rightChild != null && rightChild.color == RedBlackNode.RED) {
                current.color = !current.color;
                leftChild.color = !leftChild.color;
                rightChild.color = !rightChild.color;
            }

            child = current;
        }

        return child;
    }

    /**
     * 删除子树中的最小节点（保留用于特殊情况）
     * @param node 子树的根节点
     * @return 删除最小节点后的子树
     */
    private function deleteMin(node:RedBlackNode):RedBlackNode {
        // 已经到最左端 - 这是最小节点，删除它
        if (node.left == null) {
            return null;
        }

        // 确保沿路径的节点有足够的红色节点
        if (!isRed(node.left) && !isRed(node.left.left)) {
            node = moveRedLeft(node);
        }

        node.left = deleteMin(node.left);

        // 修复平衡（内联）
        if (isRed(node.right)) {
            node = rotateLeft(node);
        }
        if (isRed(node.left) && isRed(node.left.left)) {
            node = rotateRight(node);
        }
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
        flipColors(node);

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
        flipColors(node);

        if (node.left != null && isRed(node.left.left)) {
            node = rotateRight(node);
            flipColors(node);
        }

        return node;
    }

    /**
     * 【新增】分治法构建平衡红黑树
     * 从已排序数组递归构建，使用深度着色策略确保红黑树性质
     *
     * 着色原理：
     * - 在平衡二叉树中，叶子深度差异最大为 1
     * - 将最深层节点设为红色，其余设为黑色
     * - 这样无论路径走到深度 d（红）还是 d-1（黑），黑色节点数相同
     *
     * @param sortedArr 已排序的数组
     * @param start 起始索引
     * @param end 结束索引
     * @param depth 当前递归深度
     * @param maxDepth 树的最大深度
     * @return 构建的子树根节点
     */
    private function buildBalancedTree(sortedArr:Array, start:Number, end:Number, depth:Number, maxDepth:Number):RedBlackNode {
        if (start > end) {
            return null;
        }

        // 取中间元素作为根
        var mid:Number = (start + end) >> 1;
        var newNode:RedBlackNode = new RedBlackNode(sortedArr[mid]);

        // 递归构建子树
        newNode.left = buildBalancedTree(sortedArr, start, mid - 1, depth + 1, maxDepth);
        newNode.right = buildBalancedTree(sortedArr, mid + 1, end, depth + 1, maxDepth);

        // 着色策略：最深层节点设为红色，其余设为黑色
        // 这保证了所有路径的黑色节点数相同
        if (depth == maxDepth) {
            newNode.color = RedBlackNode.RED;
        } else {
            newNode.color = RedBlackNode.BLACK;
        }

        return newNode;
    }

    /**
     * 计算平衡二叉树的最大深度
     * 对于 n 个节点的完全平衡二叉树，最大深度 = floor(log2(n))
     *
     * @param n 节点数量
     * @return 最大深度（从 0 开始计数）
     */
    private function calculateMaxDepth(n:Number):Number {
        if (n <= 0) return -1;
        var depth:Number = 0;
        var count:Number = 1;
        while (count <= n) {
            count = count << 1;  // count *= 2
            depth++;
        }
        return depth - 1;
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
}
