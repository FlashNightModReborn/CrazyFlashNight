import org.flashNight.naki.DataStructures.*;

/**
 * NAryTree 类实现了一个 N 叉树的数据结构。
 * 
 * 优化设计思路：
 * 1. **使用非递归遍历（基于栈）**：  
 *    为了避免递归调用可能带来的堆栈溢出问题，同时减少递归函数调用的开销，
 *    采用基于数组模拟栈的方式实现深度优先遍历（DFS），用于节点的注册、注销以及搜索操作。
 *
 * 2. **栈的入栈顺序优化**：  
 *    在将当前节点的子节点入栈时，采用反序入栈方式（即先将子节点数组中的第 0 个节点放在最靠上的位置，
 *    依次类推），从而保证出栈顺序与递归先序遍历保持一致，且减少多次自增操作。
 *
 * 3. **局部变量复用和内存清理**：  
 *    在遍历过程中，复用了局部变量（如 count、newTop）并在结束后清空栈数组，
 *    以帮助垃圾回收，减少内存占用。
 */
class org.flashNight.naki.DataStructures.NAryTree {
    /** 树的根节点 */
    public var root:NAryTreeNode;
    /**
     * 节点映射表，用于快速查找节点，
     * 键为节点的唯一标识 uid，值为对应的 NAryTreeNode 实例
     */
    public var nodeMap:Object;
    
    /**
     * 构造函数
     * @param rootData 根节点的数据对象
     */
    public function NAryTree(rootData:Object) {
        // 初始化根节点，并将当前树对象关联到根节点上
        this.root = new NAryTreeNode(rootData);
        this.root.tree = this;
        
        // 初始化节点映射表，将根节点注册进去
        this.nodeMap = {};
        this.nodeMap[this.root.uid] = this.root;
    }
    
    /**
     * 注册一个节点及其所有子节点到 nodeMap 中。
     * 该方法采用基于栈的非递归深度优先遍历方式，减少函数调用开销。
     * 
     * 优化点：
     * - 使用 do...while 循环减少每次循环的比较次数；
     * - 在入栈时计算新栈顶位置 newTop，并反序入栈，保证出栈顺序与先序遍历一致；
     * - 遍历结束后清空栈数组，帮助垃圾回收。
     * 
     * @param node 要注册的节点，如果传入 null，则直接返回。
     */
    public function registerNode(node:NAryTreeNode):Void {
        if (!node) return;
        
        // 初始化栈，初始只包含传入的 node
        var stack:Array = [node];
        // top 指针，表示当前栈顶索引
        var top:Number = 0;
        // 局部变量，用于保存当前节点的子节点数及新栈顶位置
        var count:Number, newTop:Number;
        
        // 使用 do...while 循环进行深度优先遍历
        do {
            // 弹出栈顶元素
            var n:NAryTreeNode = stack[top--];
            // 将节点注册到 nodeMap 中，使用节点的 uid 作为键
            this.nodeMap[n.uid] = n;
            
            // 获取当前节点的子节点数量
            if ((count = n.getNumberOfChildren()) > 0) {
                // 计算新栈顶位置，新入栈的子节点个数将占用索引区间 (top+1) ~ (top+count)
                newTop = top + count;
                // 将子节点按照反序方式入栈，保证出栈时顺序与递归先序一致
                for (var i:Number = 0; i < count; i++) {
                    // 子节点 i 放入位置 newTop - i
                    stack[newTop - i] = n.getChild(i);
                }
                // 更新栈顶指针
                top = newTop;
            }
        } while (top >= 0);
        
        // 清空栈，协助垃圾回收
        stack.length = 0;
    }
    
    /**
     * 注销一个节点及其所有子节点，从 nodeMap 中删除它们的注册信息。
     * 与 registerNode 类似，采用基于栈的非递归深度优先遍历方式。
     * 
     * 优化点与 registerNode 类似：
     * - 使用 do...while 循环和反序入栈减少不必要的循环判断；
     * - 清理临时栈以帮助垃圾回收。
     *
     * @param node 要注销的节点，如果传入 null，则直接返回。
     */
    public function unregisterNode(node:NAryTreeNode):Void {
        if (!node) return;
        
        var stack:Array = [node];
        var top:Number = 0;
        var count:Number, newTop:Number;
        
        do {
            var n:NAryTreeNode = stack[top--];
            // 从 nodeMap 中删除该节点的注册记录
            delete this.nodeMap[n.uid];
            
            if ((count = n.getNumberOfChildren()) > 0) {
                newTop = top + count;
                for (var i:Number = 0; i < count; i++) {
                    stack[newTop - i] = n.getChild(i);
                }
                top = newTop;
            }
        } while (top >= 0);
        
        // 清空栈数组，释放内存
        stack.length = 0;
    }
    
    /**
     * 获取树的根节点
     * @return 根节点对象
     */
    public function getRoot():NAryTreeNode {
        return this.root;
    }
    
    /**
     * 遍历树，并在遍历过程中对每个节点执行指定的回调函数。
     * 支持前序遍历和后序遍历，通过传入 order 参数决定遍历顺序。
     * 
     * @param order 遍历顺序，传入 "post" 表示后序遍历，其他情况默认为前序遍历
     * @param callback 回调函数，每个节点在遍历时会调用此函数进行处理
     */
    public function traverse(order:String, callback:Function):Void {
        if (!this.root) return;
        // 根据 order 参数选择调用根节点对应的遍历方法
        order == "post" ? 
            this.root.traversePostOrder(callback) : 
            this.root.traversePreOrder(callback);
    }
    
    /**
     * 搜索树中满足条件的节点，并返回该节点对象。
     * 搜索时使用非递归深度优先遍历，传入的 compareFunction 用于比较节点数据是否符合目标条件。
     * 
     * 优化说明：
     * - 使用栈来模拟深度优先遍历，避免递归调用；
     * - 遍历过程中，一旦找到匹配的节点，则立即返回，减少不必要的遍历。
     *
     * @param target 目标数据对象，用于比较匹配条件
     * @param compareFunction 比较函数，接受 (node.data, target) 两个参数，返回布尔值，判断是否匹配
     * @return 符合条件的 NAryTreeNode 对象，如果未找到则返回 null
     */
    public function search(target:Object, compareFunction:Function):NAryTreeNode {
        if (!this.root) return null;
        
        var stack:Array = [this.root];
        var top:Number = 0;
        var count:Number, newTop:Number;
        
        do {
            // 弹出栈顶节点进行比较
            var node:NAryTreeNode = stack[top--];
            // 如果当前节点的数据与目标匹配，则直接返回
            if (compareFunction(node.data, target)) return node;
            
            // 如果有子节点，则将它们按照反序入栈
            if ((count = node.getNumberOfChildren()) > 0) {
                newTop = top + count;
                for (var i:Number = 0; i < count; i++) {
                    stack[newTop - i] = node.getChild(i);
                }
                top = newTop;
            }
        } while (top >= 0);
        
        // 遍历结束后未找到匹配节点，返回 null
        return null;
    }
}
