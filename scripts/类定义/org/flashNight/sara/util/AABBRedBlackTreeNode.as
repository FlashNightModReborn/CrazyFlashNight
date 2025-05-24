import org.flashNight.sara.util.*;

class org.flashNight.sara.util.AABBRedBlackTreeNode {
    public var aabb:AABB;
    public var color:Boolean;  // true for Red, false for Black
    public var left:AABBRedBlackTreeNode;
    public var right:AABBRedBlackTreeNode;
    public var parent:AABBRedBlackTreeNode;

    public function AABBRedBlackTreeNode(aabb:AABB) {
        this.aabb = aabb;
        this.color = true; // 新节点默认为红色
        this.left = null;
        this.right = null;
        this.parent = null;
    }

    public function toggleColor():Void {
        this.color = !this.color;
    }

    public function toString():String {
        var colorDesc:String = this.color ? "红" : "黑";
        var leftDesc:String = this.left ? "左子存在" : "无左子";
        var rightDesc:String = this.right ? "右子存在" : "无右子";
        return "节点颜色: " + colorDesc + ", AABB: [" + this.aabb.toString() + "], " + leftDesc + ", " + rightDesc;
    }


    public function clone():AABBRedBlackTreeNode {
        var cloneNode:AABBRedBlackTreeNode = new AABBRedBlackTreeNode(new AABB(this.aabb.left, this.aabb.right, this.aabb.top, this.aabb.bottom));
        cloneNode.color = this.color;
        return cloneNode;
    }

    public function isValidRBNode():Boolean {
    // 验证红色节点是否有红色子节点
    if (this.color) { // 如果当前节点是红色
        if ((this.left != null && this.left.color) || (this.right != null && this.right.color)) {
            return false; // 红色节点有红色子节点
        }
    }

    // 验证黑色路径长度
    if (!validateBlackHeight(this)) {
        return false;
    }

    return true; // 如果以上检查都通过，返回真
}

    private function validateBlackHeight(node:AABBRedBlackTreeNode):Boolean {
        var leftBlackHeight:Number = 0;
        var rightBlackHeight:Number = 0;

        if (node.left != null) {
            leftBlackHeight = getBlackHeight(node.left);
        }

        if (node.right != null) {
            rightBlackHeight = getBlackHeight(node.right);
        }

        // 验证左右子树的黑高度是否相等
        if (leftBlackHeight != rightBlackHeight || leftBlackHeight == -1 || rightBlackHeight == -1) {
            return false;
        }

        return true;
    }

    private function getBlackHeight(node:AABBRedBlackTreeNode):Number {
        if (node == null) {
            return 1; // NIL节点被视为黑色
        }

        var leftHeight:Number = getBlackHeight(node.left);
        var rightHeight:Number = getBlackHeight(node.right);

        if (leftHeight != rightHeight || leftHeight == -1) {
            return -1; // 不平衡或错误
        }

        return node.color ? leftHeight : leftHeight + 1;
    }



    public function intersects(other:AABB):Boolean {
        return this.aabb.intersects(other);
    }

    public function mergeWith(other:AABBRedBlackTreeNode):Void {
        this.aabb = this.aabb.merge(other.aabb);
    }

    public function draw(dmc:MovieClip):Void {
        this.aabb.draw(dmc);
    }

}
