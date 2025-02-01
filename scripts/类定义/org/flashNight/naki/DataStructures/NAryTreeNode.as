import org.flashNight.naki.DataStructures.*; 

/*---------------------------------------------------------------------------
    文件: org/flashNight/naki/DataStructures/NAryTreeNode.as
    描述: n 叉树节点类（合并子节点存储版）
          使用单一数组 childList 保存子节点，同时用 childMap 保存每个子节点在数组中的索引，
          既保证了子节点顺序，又能在添加、删除时达到 O(1) 重复检测和快速定位的效果，
          并且仅在 addChild 时通过向上检查祖先防止循环引用，同时提供前序与后序遍历实现。
---------------------------------------------------------------------------*/
class org.flashNight.naki.DataStructures.NAryTreeNode {
    // 节点所保存的数据，可存储任意数据
    public var data:Object;
    // 父节点引用（根节点则为 null）
    public var parent:NAryTreeNode;
    // 子节点列表（有序保存子节点）
    private var childList:Array;
    // 子节点哈希表：键为子节点的 uid，值为该子节点在 childList 中的索引
    private var childMap:Object;
    // 唯一标识，每个节点均分配唯一 id
    public var uid:Number;
    // 对应的树引用（由 NAryTree 在添加时传入）
    public var tree:NAryTree;
    
    // 静态变量：用于生成唯一 id
    private static var _nextId:Number = 0;
    
    /**
     * 构造函数
     * @param data 节点数据
     */
    public function NAryTreeNode(data:Object) {
        this.data = data;
        this.parent = null;
        this.childList = new Array();
        this.childMap = {}; // 初始化为空哈希表
        this.uid = NAryTreeNode._nextId++;
        this.tree = null;
    }
    
    /**
     * 添加子节点
     * @param child 要添加的子节点（NAryTreeNode 对象）
     */
    public function addChild(child:NAryTreeNode):Void {
        if (child == null) {
            trace("[ERROR] 不能添加 null 子节点。");
            return;
        }

        // 使用局部变量缓存 childMap 与 uid，减少多次属性查找
        var map:Object = this.childMap;
        var uid:Number = child.uid;
        
        // 防止重复添加：检查 childMap 中是否已有该子节点 uid
        if (map[uid] != undefined) {
            trace("[WARN] 子节点 '" + child.data + "' 已存在，重复添加将被忽略。");
            return;
        }
        
        // 防止跨层循环引用：遍历当前节点的祖先链
        var temp:NAryTreeNode = this;
        while (temp != null) {
            if (temp == child) {
                trace("[ERROR] 添加子节点失败：跨层循环引用检测不通过（child.data=" + child.data + " 是当前节点的祖先）。");
                return;
            }
            temp = temp.parent;
        }
        
        // 如果 child 已有父节点，则先将其从原父节点中移除
        if (child.parent != null) {
            child.parent.removeChild(child);
        }
        
        // 建立关联：设置 child 的 parent 为当前节点
        child.parent = this;
        // 若当前节点已有 tree，则传递给子节点，并注册到全局索引中
        if (this.tree != null) {
            child.setTree(this.tree);
            this.tree.registerNode(child);
        }
        
        // 添加 child 到 childList，并在 childMap 中记录其索引
        var list:Array = this.childList;
        var index:Number = list.length;
        list.push(child);
        map[uid] = index;
    }
    
    /**
     * 移除指定的子节点
     * @param child 要删除的子节点
     * @return Boolean 如果找到并删除则返回 true，否则返回 false
     */
    public function removeChild(child:NAryTreeNode):Boolean {
        var map:Object = this.childMap;
        var temp:Number = child.uid;
        var index:Number = map[temp];

        if (index == undefined) {
            return false;
        }

        var list:Array = this.childList;
        
        // 从 childList 中删除该子节点
        list.splice(index, 1);
        // 删除 childMap 中该 uid
        delete map[temp];
        
        // 更新 childMap：由于 childList 删除了一个元素，后续元素的索引都要更新
        var len:Number = list.length;
        for (temp = index; temp < len; temp++) {
            map[list[temp].uid] = temp;
        }
        
        // 若当前节点所属树存在，则注销 child 及其所有后代
        if (this.tree != null) {
            this.tree.unregisterNode(child);
        }
        child.parent = null;
        child.tree = null;
        return true;
    }
    
    /**
     * 根据索引返回子节点（childList 中的顺序即为添加顺序）
     * @param index 子节点索引（从 0 开始）
     * @return NAryTreeNode 如果索引合法，则返回对应的子节点，否则返回 null
     */
    public function getChild(index:Number):NAryTreeNode {
        // 如果可以确保 index 是数字且调用时正确，可考虑省略 typeof 检查
        if (index < 0 || index >= this.childList.length) {
            trace("[WARN] getChild: 索引 " + index + " 非法。");
            return null;
        }
        return this.childList[index];
    }
    
    /**
     * 获取子节点数量
     * @return Number 子节点总数
     */
    public function getNumberOfChildren():Number {
        return this.childList.length;
    }
    
    /**
     * 为当前节点及其所有后代设置 tree 引用
     * 使用迭代方式替代递归，并用 do…while 以及数组索引模拟堆栈操作，
     * 合并自增/自减操作以减少虚拟机指令开销。
     * @param tree 全局树对象
     */
    public function setTree(tree:NAryTree):Void {
        // 初始化栈，至少包含当前节点 this
        var stack:Array = new Array();
        stack[0] = this;
        var top:Number = 0;
        
        do {
            // 处理当前栈顶节点
            var node:NAryTreeNode = stack[top];
            node.tree = tree;
            
            var children:Array = node.childList;
            var n:Number = children.length;
            if (n > 0) {
                var newTop:Number = top + n;
                // 使用 do...while 消除第一次的比较
                do {
                    // 注意这里先递减再使用 n, 保证索引正确
                    stack[newTop - n] = children[--n];
                } while (n > 0);
                top = newTop;
            }
        } while (--top >= 0);
        
        // 清理栈，帮助垃圾回收
        stack.length = 0;
    }



    
    /**
     * 前序遍历：先访问自身，再依照 childList 顺序遍历子节点。
     * 回调函数形如：function(node:NAryTreeNode):Boolean { ... }，
     * 若回调返回 false，则提前中断遍历。
     * @param callback 回调函数
     * @return Boolean 如果完整遍历返回 true；若提前终止返回 false。
     */
    public function traversePreOrder(callback:Function):Boolean {
        if (callback(this) === false) {
            return false;
        }
        
        var list:Array = this.childList;
        var len:Number = list.length;
        for (var i:Number = 0; i < len; i++) {
            // 若子节点的遍历返回 false，提前中断整个遍历
            if (list[i].traversePreOrder(callback) === false) {
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
        var list:Array = this.childList;
        var len:Number = list.length;
        for (var i:Number = 0; i < len; i++) {
            if (list[i].traversePostOrder(callback) === false) {
                return false;
            }
        }
        if (callback(this) === false) {
            return false;
        }
        return true;
    }
    
    /**
     * 判断当前节点是否为叶子节点（没有子节点）
     * @return Boolean 若没有子节点则返回 true，否则返回 false
     */
    public function isLeaf():Boolean {
        return (this.childList.length == 0);
    }
    
    /**
     * 获取当前节点在树中的深度（根节点深度为 0）
     * @return Number 当前节点的深度
     */
    public function getDepth():Number {
        var depth:Number = 0;
        for (var node:NAryTreeNode = this; node.parent != null; node = node.parent) {
            depth++;
        }
        return depth;
    }
}
