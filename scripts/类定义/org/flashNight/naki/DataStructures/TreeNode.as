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
}