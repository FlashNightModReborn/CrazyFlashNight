/*---------------------------------------------------------------------------
    文件: org/flashNight/naki/DataStructures/NAryTreeNode.as
    描述: n 叉树节点类（进一步优化版）
          支持任意子节点，使用散列表存储子节点（加 childOrder 数组维护顺序），
          仅在 addChild 时通过向上检查祖先防止循环引用，
          并提供前序与后序遍历实现。
---------------------------------------------------------------------------*/
class org.flashNight.naki.DataStructures.NAryTreeNode {
    // 节点所保存的数据，可存储任意数据
    public var data:Object;
    // 父节点引用（根节点则为 null）
    public var parent:NAryTreeNode;
    // 子节点散列表：键为子节点的 uid，值为对应节点
    private var children:Object;
    // 记录子节点插入顺序的数组，存放子节点的 uid
    private var childOrder:Array;
    // 唯一标识，每个节点均分配唯一 id
    public var uid:Number;
    // 对应的树引用（由 NAryTree 在添加时传入）
    public var tree:org.flashNight.naki.DataStructures.NAryTree;
    
    // 静态变量：用于生成唯一 id
    private static var _nextId:Number = 0;
    
    /**
     * 构造函数
     * @param data 节点数据
     */
    public function NAryTreeNode(data:Object) {
        this.data = data;
        this.parent = null;
        this.children = {};       // 使用 Object 存储子节点
        this.childOrder = new Array();
        this.uid = org.flashNight.naki.DataStructures.NAryTreeNode._nextId++;
        this.tree = null;
    }
    
    /**
     * 添加子节点
     * @param child 要添加的子节点（NAryTreeNode 对象）
     */
    public function addChild(child:NAryTreeNode):Void {
        if(child == null) {
            trace("[ERROR] 不能添加 null 子节点。");
            return;
        }
        
        // 防止重复添加：若已在 children 中，则直接返回
        if(this.children[child.uid] != undefined) {
            trace("[WARN] 子节点 '" + child.data + "' 已存在，重复添加将被忽略。");
            return;
        }
        
        // 防止跨层循环引用：检查自身的祖先链中是否出现待添加的节点
        var temp:NAryTreeNode = this;
        while(temp != null) {
            if(temp == child) {
                trace("[ERROR] 添加子节点失败：跨层循环引用检测不通过（child.data=" + child.data + " 是当前节点的祖先）。");
                return;
            }
            temp = temp.parent;
        }
        
        // 如果 child 已有父节点，则先将其从原父节点中移除
        if(child.parent != null) {
            child.parent.removeChild(child);
        }
        
        // 建立关联：设置 child 的 parent 为当前节点
        child.parent = this;
        // 将本节点的 tree 传递给 child（若本节点已有 tree）
        if(this.tree != null) {
            child.setTree(this.tree);
            // 注册 child 到全局索引中
            this.tree.registerNode(child);
        }
        
        // 添加 child 到 children 散列表和 childOrder 数组中
        this.children[child.uid] = child;
        this.childOrder.push(child.uid);
    }
    
    /**
     * 移除指定的子节点
     * @param child 要删除的子节点
     * @return Boolean 如果找到并删除则返回 true，否则返回 false
     */
    public function removeChild(child:NAryTreeNode):Boolean {
        if(this.children[child.uid] == undefined) {
            return false;
        }
        // 从 children 散列表中删除
        delete this.children[child.uid];
        // 从 childOrder 数组中删除对应 uid
        for(var i:Number = 0; i < this.childOrder.length; i++){
            if(this.childOrder[i] == child.uid) {
                this.childOrder.splice(i,1);
                break;
            }
        }
        // 若当前节点所属树存在，则注销 child 及其子孙节点
        if(this.tree != null) {
            this.tree.unregisterNode(child);
        }
        child.parent = null;
        child.tree = null;
        return true;
    }
    
    /**
     * 根据索引返回子节点（按照 childOrder 顺序）
     * @param index 子节点索引（从 0 开始）
     * @return NAryTreeNode 如果索引合法，则返回对应的子节点，否则返回 null
     */
    public function getChild(index:Number):NAryTreeNode {
        if(typeof(index) != "number" || index < 0 || index >= this.childOrder.length) {
            trace("[WARN] getChild: 索引 " + index + " 非法。");
            return null;
        }
        var uid:Number = this.childOrder[index];
        return this.children[uid];
    }
    
    /**
     * 获取子节点数量
     * @return Number 子节点总数
     */
    public function getNumberOfChildren():Number {
        return this.childOrder.length;
    }
    
    /**
     * 设置当前节点及其所有后代的 tree 引用
     * @param tree 全局树对象
     */
    public function setTree(tree:org.flashNight.naki.DataStructures.NAryTree):Void {
        this.tree = tree;
        // 递归为所有子节点设置 tree
        for(var i:Number = 0; i < this.childOrder.length; i++){
            var child:NAryTreeNode = this.children[this.childOrder[i]];
            child.setTree(tree);
        }
    }
    
    /**
     * 前序遍历：先访问自身，再依照 childOrder 顺序遍历子节点。
     * 回调函数形如：function(node:NAryTreeNode):Boolean { ... }，
     * 若回调返回 false，则提前中断遍历。
     * @param callback 回调函数
     * @return Boolean 如果完整遍历返回 true；若提前终止返回 false。
     */
    public function traversePreOrder(callback:Function):Boolean {
        if(callback(this) === false) {
            return false;
        }
        for(var i:Number = 0; i < this.childOrder.length; i++){
            var child:NAryTreeNode = this.children[this.childOrder[i]];
            if(child.traversePreOrder(callback) === false) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 后序遍历：先遍历所有子节点，再访问自身。
     * 回调函数形如：function(node:NAryTreeNode):Boolean { ... }，
     * 若回调返回 false，则提前中断遍历。
     * @param callback 回调函数
     * @return Boolean 如果完整遍历返回 true；若提前终止返回 false。
     */
    public function traversePostOrder(callback:Function):Boolean {
        for(var i:Number = 0; i < this.childOrder.length; i++){
            var child:NAryTreeNode = this.children[this.childOrder[i]];
            if(child.traversePostOrder(callback) === false) {
                return false;
            }
        }
        if(callback(this) === false) {
            return false;
        }
        return true;
    }
    
    /**
     * 判断当前节点是否为叶子节点（没有子节点）
     * @return Boolean 若没有子节点则返回 true，否则返回 false
     */
    public function isLeaf():Boolean {
        return (this.childOrder.length == 0);
    }
    
    /**
     * 获取当前节点在树中的深度（根节点深度为 0）
     * @return Number 当前节点的深度
     */
    public function getDepth():Number {
        var depth:Number = 0;
        var node:NAryTreeNode = this;
        while (node.parent != null) {
            depth++;
            node = node.parent;
        }
        return depth;
    }
}
