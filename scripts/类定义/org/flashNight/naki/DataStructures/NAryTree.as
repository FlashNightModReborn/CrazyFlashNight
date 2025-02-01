import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.NAryTree {
    // 树的根节点
    public var root:NAryTreeNode;
    
    /**
     * 构造函数：通过传入的根数据构造树，并创建根节点
     * @param rootData 根节点所保存的数据
     */
    public function NAryTree(rootData:Object) {
        this.root = new NAryTreeNode(rootData);
    }
    
    /**
     * 获取根节点
     * @return NAryTreeNode 返回树的根节点
     */
    public function getRoot():NAryTreeNode {
        return root;
    }
    
    /**
     * 遍历整个树，并对每个节点执行回调函数
     * @param callback 回调函数，形如：function(node:NAryTreeNode):Void {...}
     */
    public function traverse(callback:Function):Void {
        if (root != null) {
            root.traverse(callback);
        }
    }
    
    /**
     * 搜索树中满足条件的节点
     * @param target 搜索目标，可以是任意数据
     * @param compareFunction 比较函数，形如：
     *        function(data:Object, target:Object):Boolean { ... }
     *        当节点数据与目标匹配时应返回 true
     * @return NAryTreeNode 如果找到符合条件的节点则返回该节点，否则返回 null
     */
    public function search(target:Object, compareFunction:Function):NAryTreeNode {
        var result:NAryTreeNode = null;
        // 利用 traverse 方法递归查找
        root.traverse(function(node:NAryTreeNode) {
            if (result == null && compareFunction(node.data, target)) {
                result = node;
            }
        });
        return result;
    }
}
