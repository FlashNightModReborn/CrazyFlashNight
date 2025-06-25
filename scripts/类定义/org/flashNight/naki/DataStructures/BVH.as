import org.flashNight.sara.util.AABB;
import org.flashNight.sara.util.Vector;
import org.flashNight.naki.DataStructures.BVHNode;
import org.flashNight.naki.DataStructures.IBVHObject;

// ============================================================================
// BVH - 包围体层次结构树
// ----------------------------------------------------------------------------
// BVH 树的顶层容器。封装了根节点，并提供对外的查询接口。
// 它本身不包含构建逻辑，构建过程由 BVHBuilder 完成。
// ============================================================================

class org.flashNight.naki.DataStructures.BVH {
    /**
     * BVH 树的根节点。
     */
    public var root:BVHNode;

    /**
     * 构造函数
     * @param {BVHNode} rootNode - BVH 树的根节点。
     */
    public function BVH(rootNode:BVHNode) {
        this.root = rootNode;
    }

    /**
     * 查询与指定 AABB 相交的所有对象。
     * @param {AABB} queryAABB - 用于查询的 AABB。
     * @return {Array} 与查询 AABB 相交的对象列表。
     */
    public function query(queryAABB:AABB):Array {
        var result:Array = [];
        if (this.root != null) {
            this.root.query(queryAABB, result);
        }
        return result;
    }

    /**
     * 查询与指定圆形范围相交的所有对象。
     * @param {Vector} center - 圆心。
     * @param {Number} radius - 半径。
     * @return {Array} 与圆形范围相交的对象列表。
     */
    public function queryCircle(center:Vector, radius:Number):Array {
        var result:Array = [];
        if (this.root != null) {
            this.root.queryCircle(center, radius, result);
        }
        return result;
    }
}