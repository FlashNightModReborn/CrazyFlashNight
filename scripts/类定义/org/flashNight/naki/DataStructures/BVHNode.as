import org.flashNight.sara.util.*;
import org.flashNight.naki.DataStructures.*;

// ============================================================================
// BVHNode - BVH树节点 (极限优化版)
// ----------------------------------------------------------------------------
// BVH 树的基本构建块。
//
// 极限优化说明:
// - 查询方法 (query, queryCircle) 使用循环和手动管理的堆栈。
// - 通过手动管理数组索引 (stackIndex) 来代替 Array.push/pop 方法，
//   彻底消除堆栈操作的函数调用开销。
// - isLeaf() 方法调用被替换为更快的直接属性检查 (left == null)。
// - 所有循环内使用的变量都已在外部局部化，以达到最高性能。
// ============================================================================

class org.flashNight.naki.DataStructures.BVHNode {
    /**
     * 该节点所包围的空间范围。
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
     */
    public var objects:Array; // Array of IBVHObject

    /**
     * 构造函数
     */
    public function BVHNode(bounds:AABB) {
        this.bounds = bounds;
        this.left = null;
        this.right = null;
        this.objects = [];
    }

    /**
     * 检查当前节点是否为叶子节点。
     * (在优化后的查询中，此方法被直接属性访问取代以提高性能)
     */
    public function isLeaf():Boolean {
        return this.left == null;
    }


    /**
     * 对给定的 AABB 进行 BVH 查询，返回所有与之相交的对象。
     * 
     * [性能优化说明]
     * - 采用手动栈管理，避免递归带来的调用栈开销。
     * - 使用 do...while 结构代替 while 循环，减少循环判定分支指令。
     * - 所有循环内变量进行局部声明，避免重复访问属性或堆分配。
     * - 直接比较属性，避免使用 isLeaf() 等额外函数调用。
     * 
     * @param queryAABB 查询使用的 AABB 区域。
     * @param result    结果数组，查询命中的对象将被 push 进该数组。
     */
    public function query(queryAABB:AABB, result:Array):Void {
        // 手动栈用于替代递归：存储待处理的节点
        var stack:Array = [];
        var stackIndex:Number = 0;

        // 局部变量声明以减少重复构造和属性访问开销
        var currentNode:BVHNode;   // 当前处理的节点
        var i:Number;              // 遍历索引
        var len:Number;            // 对象数组长度缓存
        var obj:IBVHObject;        // 当前遍历的对象
        var leafObjects:Array;     // 叶子节点中的对象数组
        var leftNode:BVHNode;      // 当前节点的左子节点

        // 初始化：将根节点压入栈中
        stack[stackIndex++] = this;

        // 使用 do...while 替代 while，提高循环效率
        do {
            // 从栈中弹出一个节点
            currentNode = stack[--stackIndex];

            // 剪枝：若当前节点的包围盒与查询区域不相交，跳过
            if (!currentNode.bounds.intersects(queryAABB)) {
                continue;
            }

            // 判断是否为叶子节点（无左子节点）
            leftNode = currentNode.left;
            if (leftNode == null) {
                // 叶子节点：遍历其所有对象
                leafObjects = currentNode.objects;
                len = leafObjects.length;
                for (i = 0; i < len; i++) {
                    obj = leafObjects[i];
                    if (obj.getAABB().intersects(queryAABB)) {
                        result[result.length] = obj; // 命中对象加入结果列表
                    }
                }
            } else {
                // 非叶子节点：将左右子节点压入栈中以备后续处理
                stack[stackIndex++] = currentNode.right;
                stack[stackIndex++] = leftNode;
            }

        } while (stackIndex > 0);
    }

    
    /**
     * [极限优化版] 查询所有与圆形区域相交的对象（使用手动栈避免递归）。
     *
     * @param center 圆心坐标向量。
     * @param radius 查询半径。
     * @param result 存放相交对象的输出数组。
     */
    public function queryCircle(center:Vector, radius:Number, result:Array):Void {
        var stack:Array = [];
        var stackIndex:Number = 0;

        var currentNode:BVHNode;
        var i:Number;
        var len:Number;
        var obj:IBVHObject;
        var leafObjects:Array;
        var leftNode:BVHNode;

        stack[stackIndex++] = this;

        do {
            currentNode = stack[--stackIndex];

            // 剪枝：当前节点与查询圆不相交，跳过
            if (!currentNode.bounds.intersectsCircleV(center, radius)) {
                continue;
            }

            leftNode = currentNode.left;
            if (leftNode == null) {
                // 叶子节点：遍历其对象数组
                leafObjects = currentNode.objects;
                len = leafObjects.length;
                for (i = 0; i < len; i++) {
                    obj = leafObjects[i];
                    // 若对象包围盒与查询圆相交，则加入结果
                    if (obj.getAABB().intersectsCircleV(center, radius)) {
                        result.push(obj);
                    }
                }
            } else {
                // 内部节点：压入左右子节点
                stack[stackIndex++] = currentNode.right;
                stack[stackIndex++] = leftNode;
            }

        } while (stackIndex > 0);
    }

}