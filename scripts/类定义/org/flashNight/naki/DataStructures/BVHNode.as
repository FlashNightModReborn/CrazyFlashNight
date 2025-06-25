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
     * [极限优化版] 递归地收集与查询 AABB 相交的所有对象。
     *
     * @param {AABB} queryAABB - 用于查询的 AABB。
     * @param {Array} result - 用于存放结果的数组。
     */
    public function query(queryAABB:AABB, result:Array):Void {
        // [极限优化] 手动堆栈管理
        var stack:Array = [];
        var stackIndex:Number = 0;

        // [极限优化] 局部化所有循环内变量
        var currentNode:BVHNode;
        var i:Number;
        var len:Number;
        var obj:IBVHObject;
        var leafObjects:Array;
        var leftNode:BVHNode;

        // 手动 "push" 第一个节点
        stack[stackIndex++] = this;

        // [极限优化] 循环条件基于手动管理的索引
        while (stackIndex > 0) {
            // 手动 "pop" 一个节点
            currentNode = stack[--stackIndex];

            // 核心剪枝
            if (!currentNode.bounds.intersects(queryAABB)) {
                continue;
            }

            // [极限优化] 直接检查属性，避免 isLeaf() 函数调用
            leftNode = currentNode.left;
            if (leftNode == null) {
                // 叶子节点
                leafObjects = currentNode.objects;
                len = leafObjects.length;
                for (i = 0; i < len; i++) {
                    obj = leafObjects[i];
                    if (obj.getAABB().intersects(queryAABB)) {
                        result.push(obj); // result.push 无法避免，但这是最终操作
                    }
                }
            } else {
                // 内部节点，手动 "push" 子节点
                stack[stackIndex++] = currentNode.right;
                stack[stackIndex++] = leftNode;
            }
        }
    }
    
    /**
     * [极限优化版] 递归地收集与查询圆形范围相交的所有对象。
     *
     * @param {Vector} center - 圆心。
     * @param {Number} radius - 半径。
     * @param {Array} result - 用于存放结果的数组。
     */
    public function queryCircle(center:Vector, radius:Number, result:Array):Void {
        // [极限优化] 手动堆栈管理
        var stack:Array = [];
        var stackIndex:Number = 0;

        // [极限优化] 局部化所有循环内变量
        var currentNode:BVHNode;
        var i:Number;
        var len:Number;
        var obj:IBVHObject;
        var leafObjects:Array;
        var leftNode:BVHNode;

        // 手动 "push" 第一个节点
        stack[stackIndex++] = this;

        // [极限优化] 循环条件基于手动管理的索引
        while (stackIndex > 0) {
            // 手动 "pop" 一个节点
            currentNode = stack[--stackIndex];

            // 核心剪枝
            if (!currentNode.bounds.intersectsCircleV(center, radius)) {
                continue;
            }

            // [极限优化] 直接检查属性
            leftNode = currentNode.left;
            if (leftNode == null) {
                // 叶子节点
                leafObjects = currentNode.objects;
                len = leafObjects.length;
                for (i = 0; i < len; i++) {
                    obj = leafObjects[i];
                    if (obj.getAABB().intersectsCircleV(center, radius)) {
                        result.push(obj);
                    }
                }
            } else {
                // 内部节点，手动 "push" 子节点
                stack[stackIndex++] = currentNode.right;
                stack[stackIndex++] = leftNode;
            }
        }
    }
}