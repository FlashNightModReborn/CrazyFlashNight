import org.flashNight.gesh.iterator.*;
import org.flashNight.naki.DataStructures.*;

/**
 * 在平衡搜索树 (TreeSet) 上进行中序遍历的迭代器实现。
 * 只在迭代器中持有「当前节点」和「下一节点」的引用，
 * 无需用栈或数组来缓存大量节点，从而降低额外内存占用。
 *
 * 【兼容性说明】
 * TreeSet 现在是一个 facade，可以使用不同的树实现（AVL/WAVL/RedBlack/Zip）。
 * 所有节点类型都有 left、right、value 属性，因此使用 Object 类型并通过
 * 动态属性访问来保持兼容性。
 */
class org.flashNight.gesh.iterator.TreeSetMinimalIterator extends BaseIterator  implements IIterator
{
    private var _treeSet:TreeSet;        // 要遍历的 TreeSet
    private var _root:Object;            // 记录下的根节点引用（用于查找 successor）
    private var _func:Function;          // 记录比较函数引用
    private var _nextNode:Object;        // 中序遍历中"下一个要访问"的节点
    private var _result:IterationResult; // 复用的结果对象，避免每次 next() 都 new

    /**
     * 构造函数
     * @param treeSet 要进行迭代的 TreeSet
     */
    public function TreeSetMinimalIterator(treeSet:TreeSet)
    {
        this._treeSet = treeSet;
        this._root    = treeSet.getRoot();
        this._func    = treeSet.getCompareFunction();
        // 初始化时，将 _nextNode 设置为整棵树的最小节点
        this._nextNode = findMinNode(this._root);
        // 预创建结果对象，后续复用
        this._result   = new IterationResult(null, false);
    }

    /**
    * 返回迭代的下一个结果 (IterationResult)。
    * 如果没有更多元素，则返回 done=true。
    *
    * 【优化说明】
    * 复用 _result 对象，避免每次调用都 new IterationResult。
    * 将 n 次对象分配减少到 1 次，降低 GC 压力。
    * 注意：调用方不应缓存返回的 IterationResult，因为下次 next() 会覆盖其内容。
    */
    public function next():IterationResult
    {
        var result:IterationResult = this._result;

        // 将 hasNext 内联展开
        if (this._nextNode == null)  // 直接判断是否有下一个节点
        {
            result._value = undefined;
            result._done = true;
            return result;
        }

        // 继续迭代逻辑
        var current:Object = this._nextNode;
        this._nextNode = findSuccessor(current);

        result._value = current.value;
        result._done = false;
        return result;
    }

    /**
     * 是否还有下一个元素可迭代
     */
    public function hasNext():Boolean
    {
        return (this._nextNode != null);
    }

    /**
     * 重置迭代器状态，使其再次从最小节点开始
     */
    public function reset():Void
    {
        this._root     = _treeSet.getRoot();
        this._nextNode = findMinNode(this._root);
        this._func     = _treeSet.getCompareFunction(); 
    }

    /**
     * 显式释放资源（避免循环引用）
     */
    public function dispose():Void
    {
        this._treeSet  = null;
        this._root     = null;
        this._func     = null;
        this._nextNode = null;
        this._result   = null;
    }

    // --------------------- 私有辅助函数 --------------------- //

    /**
     * 找到以 node 为根的子树中，值最小的节点（中序遍历的第一个节点）。
     * 若 node 为 null，则返回 null。
     */
    private function findMinNode(node:Object):Object
    {
        var current:Object = node;
        while (current != null && current.left != null)
        {
            current = current.left;
        }
        return current;
    }

    /**
     * 寻找一个节点 current 在「中序遍历」下的后继节点 (successor)。
     * 若不存在后继，则返回 null。
     *
     * 算法：
     *   1. 若 current 有右子树 => 后继必在右子树中，即：取右子树的最左节点。
     *   2. 否则 => 从根开始往下找「最早大于 current.value」的节点。
     *
     * 【优化说明】
     * 比较函数 _func 在构造时已缓存，此处直接使用成员变量。
     * 由于 findSuccessor 不是递归函数，this._func 的访问开销可接受。
     * 若追求极致性能，可将 _func 作为参数传入，但收益有限。
     */
    private function findSuccessor(current:Object):Object
    {
        if (current == null) return null;

        // 1. 有右子树 => 其后继就是 "右子树的最左节点"
        var rightChild:Object = current.right;
        if (rightChild != null)
        {
            return findMinNode(rightChild);
        }

        // 2. 没有右子树 => 需要从根开始，找到「大于 current.value」的最小节点
        var successor:Object = null;
        var cmpFn:Function   = this._func;   // 缓存比较函数到局部变量
        var node:Object      = this._root;
        var currentValue:Object = current.value; // 缓存当前值，避免重复访问

        while (node != null)
        {
            var cmp:Number = cmpFn(currentValue, node.value);
            if (cmp < 0)
            {
                // node.value > currentValue => 该 node 有可能是后继
                successor = node;
                node = node.left;
            }
            else if (cmp > 0)
            {
                // node.value < currentValue => 后继应在右子树
                node = node.right;
            }
            else
            {
                // 找到 current 自身，不需要再继续
                break;
            }
        }

        return successor;
    }
}
