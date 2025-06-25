import org.flashNight.sara.util.AABB;
import org.flashNight.naki.DataStructures.IBVHObject;

// ============================================================================
// BVHNode - BVH树节点
// ----------------------------------------------------------------------------
// BVH 树的基本构建块。每个节点都有一个包围盒（AABB），
// 并且可以是包含子节点的内部节点，也可以是包含具体对象的叶子节点。
// ============================================================================

class org.flashNight.naki.DataStructures.BVHNode {
    /**
     * 该节点所包围的空间范围。
     * 对于叶子节点，它包围节点内的所有对象。
     * 对于内部节点，它包围其两个子节点的 AABB。
     */
    public var bounds:AABB;

    /**
     * 左子节点。如果为 null，则此节点为叶子节点。
     */
    public var left:BVHNode;

    /**
     * 右子节点。如果为 null，则此节点为叶子节点。
     */
    public var right:BVHNode;

    /**
     * 存储在叶子节点中的对象列表。
     * 只有当 left 和 right 子节点都为 null 时，此数组才有效。
     */
    public var objects:Array; // Array of IBVHObject

    /**
     * 构造函数
     * @param {AABB} bounds - 节点的包围盒。
     */
    public function BVHNode(bounds:AABB) {
        this.bounds = bounds;
        this.left = null;
        this.right = null;
        this.objects = [];
    }

    /**
     * 检查当前节点是否为叶子节点。
     * @return {Boolean} 如果是叶子节点则返回 true。
     */
    public function isLeaf():Boolean {
        return this.left == null; // 左右子节点总是同时为null或同时不为null
    }

    /**
     * 递归地收集与查询 AABB 相交的所有对象。
     * @param {AABB} queryAABB - 用于查询的 AABB。
     * @param {Array} result - 用于存放结果的数组。
     */
    public function query(queryAABB:AABB, result:Array):Void {
        // 如果查询范围与当前节点的包围盒不相交，则直接返回。
        if (!this.bounds.intersects(queryAABB)) {
            return;
        }

        if (this.isLeaf()) {
            // 如果是叶子节点，检查其中的每个对象是否与查询范围相交。
            var len:Number = this.objects.length;
            for (var i:Number = 0; i < len; i++) {
                var obj:IBVHObject = this.objects[i];
                if (obj.getAABB().intersects(queryAABB)) {
                    result.push(obj);
                }
            }
        } else {
            // 如果是内部节点，递归查询子节点。
            this.left.query(queryAABB, result);
            this.right.query(queryAABB, result);
        }
    }
    
    /**
     * 递归地收集与查询圆形范围相交的所有对象。
     * @param {Vector} center - 圆心。
     * @param {Number} radius - 半径。
     * @param {Array} result - 用于存放结果的数组。
     */
    public function queryCircle(center:Vector, radius:Number, result:Array):Void {
        // 如果查询范围与当前节点的包围盒不相交，则直接返回。
        if (!this.bounds.intersectsCircleV(center, radius)) {
            return;
        }

        if (this.isLeaf()) {
            // 如果是叶子节点，检查其中的每个对象是否与查询范围相交。
            var len:Number = this.objects.length;
            for (var i:Number = 0; i < len; i++) {
                var obj:IBVHObject = this.objects[i];
                if (obj.getAABB().intersectsCircleV(center, radius)) {
                    result.push(obj);
                }
            }
        } else {
            // 如果是内部节点，递归查询子节点。
            this.left.queryCircle(center, radius, result);
            this.right.queryCircle(center, radius, result);
        }
    }
}