class org.flashNight.naki.DataStructures.TreeNode {
    public var value:Object;
    public var left:TreeNode;
    public var right:TreeNode;
    public var height:Number;

    public function TreeNode(value:Object) {
        this.value = value;
        this.left = null;
        this.right = null;
        this.height = 1;
    }

    /**
     * 返回节点值的字符串表示
     * @return 节点值的字符串
     */
    public function toString():String {
        return String(this.value);
    }
}