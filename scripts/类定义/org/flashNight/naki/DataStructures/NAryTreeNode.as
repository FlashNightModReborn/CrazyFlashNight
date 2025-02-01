import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.NAryTreeNode {
    // 节点所保存的数据，类型为 Object，可根据需要存储任意数据
    public var data:Object;
    // 父节点引用（根节点则为 null）
    public var parent:NAryTreeNode;
    // 子节点数组
    public var children:Array;
    
    /**
     * 构造函数
     * @param data 节点数据
     */
    public function NAryTreeNode(data:Object) {
        this.data = data;
        this.parent = null;
        this.children = new Array();
    }
    
    /**
     * 添加子节点
     * @param child 要添加的子节点（NAryTreeNode 对象）
     */
    public function addChild(child:NAryTreeNode):Void {
        child.parent = this;
        this.children.push(child);
    }
    
    /**
     * 删除指定的子节点
     * @param child 要删除的子节点
     * @return Boolean 如果找到并删除则返回 true，否则返回 false
     */
    public function removeChild(child:NAryTreeNode):Boolean {
        for (var i:Number = 0; i < children.length; i++) {
            if (children[i] == child) {
                children.splice(i, 1);
                child.parent = null;
                return true;
            }
        }
        return false;
    }
    
    /**
     * 根据索引返回子节点
     * @param index 子节点索引（从 0 开始）
     * @return NAryTreeNode 如果索引合法，则返回对应的子节点，否则返回 null
     */
    public function getChild(index:Number):NAryTreeNode {
        if (index >= 0 && index < children.length) {
            return children[index];
        }
        return null;
    }
    
    /**
     * 获取子节点数量
     * @return Number 子节点总数
     */
    public function getNumberOfChildren():Number {
        return children.length;
    }
    
    /**
     * 遍历当前节点及其所有子节点，并对每个节点执行回调函数
     * @param callback 传入的回调函数，形如：function(node:NAryTreeNode):Void {...}
     */
    public function traverse(callback:Function):Void {
        callback(this);
        for (var i:Number = 0; i < children.length; i++) {
            children[i].traverse(callback);
        }
    }
    
    /**
     * 判断当前节点是否为叶子节点（没有子节点）
     * @return Boolean 若没有子节点则返回 true，否则返回 false
     */
    public function isLeaf():Boolean {
        return (children.length == 0);
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
