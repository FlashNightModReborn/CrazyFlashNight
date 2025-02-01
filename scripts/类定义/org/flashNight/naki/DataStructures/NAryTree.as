import org.flashNight.naki.DataStructures.*;

/*---------------------------------------------------------------------------
    文件: org/flashNight/naki/DataStructures/NAryTree.as
    描述: n 叉树整体封装类（优化版）
          包含根节点，并维护全局索引（nodeMap），
          提供迭代式深度优先搜索（避免递归栈溢出），
          以及支持前序和后序遍历。
---------------------------------------------------------------------------*/
class org.flashNight.naki.DataStructures.NAryTree {
    // 树的根节点
    public var root:NAryTreeNode;
    // 全局索引：将节点 uid 映射到节点对象
    public var nodeMap:Object;
    
    /**
     * 构造函数：通过传入的根数据构造树，并创建根节点
     * @param rootData 根节点所保存的数据
     */
    public function NAryTree(rootData:Object) {
        this.root = new org.flashNight.naki.DataStructures.NAryTreeNode(rootData);
        // 将树引用赋给根节点
        this.root.tree = this;
        // 初始化全局索引，并注册根节点
        this.nodeMap = {};
        this.nodeMap[this.root.uid] = this.root;
    }
    
    /**
     * 注册节点到全局索引中，连同其所有后代一起注册
     * @param node 待注册节点
     */
    public function registerNode(node:NAryTreeNode):Void {
        var tree:org.flashNight.naki.DataStructures.NAryTree = this;
        var regFunc:Function = function(n:NAryTreeNode):Boolean {
            tree.nodeMap[n.uid] = n;
            return true;
        };
        node.traversePreOrder(regFunc);
    }
    
    /**
     * 注销节点：从全局索引中删除该节点及其所有后代
     * @param node 待注销节点
     */
    public function unregisterNode(node:NAryTreeNode):Void {
        var tree:org.flashNight.naki.DataStructures.NAryTree = this;
        var unregFunc:Function = function(n:NAryTreeNode):Boolean {
            delete tree.nodeMap[n.uid];
            return true;
        };
        node.traversePreOrder(unregFunc);
    }
    
    /**
     * 获取根节点
     * @return NAryTreeNode 返回树的根节点
     */
    public function getRoot():NAryTreeNode {
        return this.root;
    }
    
    /**
     * 遍历整棵树，并对每个节点执行回调函数
     * @param order 遍历顺序：传入 "post" 表示后序遍历，其他或不传均为前序遍历
     * @param callback 回调函数，形如：function(node:NAryTreeNode):Boolean { ... }
     */
    public function traverse(order:String, callback:Function):Void {
        if(this.root == null) {
            return;
        }
        if(order == "post") {
            this.root.traversePostOrder(callback);
        } else {
            this.root.traversePreOrder(callback);
        }
    }
    
    /**
     * 搜索树中满足条件的节点（采用迭代式深度优先搜索，前序遍历）
     * @param target 搜索目标，可以是任意数据
     * @param compareFunction 比较函数，形如：
     *        function(data:Object, target:Object):Boolean { ... }
     *        当节点数据与目标匹配时应返回 true
     * @return NAryTreeNode 如果找到符合条件的节点则返回该节点，否则返回 null
     */
    public function search(target:Object, compareFunction:Function):NAryTreeNode {
        if(this.root == null) {
            return null;
        }
        var stack:Array = new Array();
        stack.push(this.root);
        while(stack.length > 0) {
            var node = stack.pop();
            if(compareFunction(node.data, target)) {
                return node;
            }
            // 对于前序遍历：将子节点按逆序入栈以保证插入顺序
            for(var i:Number = node.getNumberOfChildren() - 1; i >= 0; i--){
                stack.push(node.getChild(i));
            }
        }
        return null;
    }
}
