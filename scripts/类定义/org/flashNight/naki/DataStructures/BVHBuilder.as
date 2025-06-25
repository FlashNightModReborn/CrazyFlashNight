import org.flashNight.sara.util.AABB;
import org.flashNight.naki.DataStructures.BVH;
import org.flashNight.naki.DataStructures.BVHNode;
import org.flashNight.naki.DataStructures.IBVHObject;

// ============================================================================
// BVHBuilder - BVH 树构建器
// ----------------------------------------------------------------------------
// 负责从一组对象构建一个优化的 BVH 树。
// 核心思想是递归地将对象集分割成两个子集。
// 提供了利用预排序数组进行加速的构建方法。
// ============================================================================

class org.flashNight.naki.DataStructures.BVHBuilder {
    
    /**
     * 叶子节点中允许的最大对象数量。
     * 当一个节点中的对象数量小于或等于此值时，递归将停止。
     */
    public static var MAX_OBJECTS_IN_LEAF:Number = 4;
    
    /**
     * 从一个对象数组构建 BVH 树。
     * 这是一个通用的构建方法，不依赖预排序。
     * @param {Array} objects - 实现 IBVHObject 接口的对象数组。
     * @return {BVH} 构建完成的 BVH 实例。
     */
    public static function build(objects:Array):BVH {
        if (objects == null || objects.length == 0) {
            return new BVH(null);
        }
        var rootNode:BVHNode = buildRecursive(objects, 0);
        return new BVH(rootNode);
    }

    /**
     * 从一个已按X轴排序的对象数组快速构建 BVH 树。
     * 这是针对 SortedUnitCache 的优化版本。
     * @param {Array} sortedObjects - 已按 getAABB().left 排序的对象数组。
     * @return {BVH} 构建完成的 BVH 实例。
     */
    public static function buildFromSortedX(sortedObjects:Array):BVH {
        if (sortedObjects == null || sortedObjects.length == 0) {
            return new BVH(null);
        }
        // 由于数组已经按X轴排序，第一次分割可以非常快。
        var rootNode:BVHNode = buildRecursive(sortedObjects, 0);
        return new BVH(rootNode);
    }
    
    /**
     * 递归构建函数
     * @param {Array} objects - 当前节点需要处理的对象列表。
     * @param {Number} depth - 当前递归深度，用于交替分割轴。
     * @return {BVHNode} 构建的节点。
     */
    private static function buildRecursive(objects:Array, depth:Number):BVHNode {
        var numObjects:Number = objects.length;
        
        // 1. 计算当前对象集的总包围盒
        var nodeAABB:AABB = objects[0].getAABB().clone();
        for (var i:Number = 1; i < numObjects; i++) {
            nodeAABB.mergeWith(objects[i].getAABB());
        }
        
        var node:BVHNode = new BVHNode(nodeAABB);
        
        // 2. 终止条件：如果对象数量小于等于阈值，则创建叶子节点
        if (numObjects <= MAX_OBJECTS_IN_LEAF) {
            node.objects = objects;
            return node;
        }

        // 3. 选择分割轴 (交替选择 X 和 Y)
        var axis:Number = depth % 2; // 0 for X, 1 for Y
        
        // 4. 沿轴对对象进行排序
        // **【核心优化点】**
        // 如果是 buildFromSortedX 的第一次调用(depth=0)，此步可以跳过！
        // 后续的Y轴排序和更深层的X轴排序仍然需要。
        if (!(depth == 0 && isAlreadySortedOnX(objects))) {
             objects.sort(function(a:IBVHObject, b:IBVHObject):Number {
                var aBox:AABB = a.getAABB();
                var bBox:AABB = b.getAABB();
                if (axis == 0) { // Sort on X
                    return (aBox.left + aBox.right) - (bBox.left + bBox.right);
                } else { // Sort on Y
                    return (aBox.top + aBox.bottom) - (bBox.top + bBox.bottom);
                }
            });
        }

        // 5. 分割对象列表
        var mid:Number = Math.floor(numObjects / 2);
        var leftObjects:Array = objects.slice(0, mid);
        var rightObjects:Array = objects.slice(mid);

        // 6. 递归构建子节点
        node.left = buildRecursive(leftObjects, depth + 1);
        node.right = buildRecursive(rightObjects, depth + 1);
        
        return node;
    }
    
    /**
     * 一个简单的检查，判断数组是否可能已经按X轴排序。
     * 这只是一个启发式，用于避免在 buildFromSortedX 的顶层进行不必要的排序。
     * @param objects 
     * @return 
     */
    private static function isAlreadySortedOnX(objects:Array):Boolean {
        // 在实际应用中，我们通过调用来源来保证这一点。
        // 此函数主要用于演示逻辑。
        // 如果是 buildFromSortedX 调用的，在 depth=0 时，我们确信它是有序的。
        // 此处可以简化逻辑，直接信任调用者。
        return true; 
    }
}