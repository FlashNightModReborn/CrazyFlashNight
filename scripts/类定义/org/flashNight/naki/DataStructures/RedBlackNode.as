import org.flashNight.naki.DataStructures.ITreeNode;

/**
 * RedBlackNode - 红黑树节点类
 * @class RedBlackNode
 * @package org.flashNight.naki.DataStructures
 * @description 红黑树的节点实现。
 *              使用颜色（红/黑）来维护平衡，保证从根到叶的最长路径不超过最短路径的两倍。
 *              同时被 RedBlackTree 和 LLRedBlackTree 使用。
 *
 * @implements ITreeNode
 */
class org.flashNight.naki.DataStructures.RedBlackNode implements ITreeNode {
    public var value:Object;
    public var left:RedBlackNode;
    public var right:RedBlackNode;
    public var color:Boolean; // true 表示红色, false 表示黑色

    // 颜色常量
    public static var RED:Boolean = true;
    public static var BLACK:Boolean = false;

    /**
     * 构造函数
     * @param value 节点值
     */
    public function RedBlackNode(value:Object) {
        this.value = value;
        this.left = null;
        this.right = null;
        this.color = RED; // 新节点默认为红色
    }

    /**
     * 返回节点值的字符串表示
     * @return 节点值的字符串
     */
    public function toString():String {
        return String(this.value) + (this.color == RED ? "[R]" : "[B]");
    }
}