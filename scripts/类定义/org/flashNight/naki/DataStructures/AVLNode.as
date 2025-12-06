import org.flashNight.naki.DataStructures.ITreeNode;

/**
 * AVLNode - AVL树节点类
 * @class AVLNode
 * @package org.flashNight.naki.DataStructures
 * @description AVL (Adelson-Velsky and Landis) 树的节点实现。
 *              使用height来维护平衡，严格保证左右子树高度差不超过1。
 *              AVL树是最早的自平衡二叉搜索树，具有严格的平衡性。
 *
 * @implements ITreeNode
 */
class org.flashNight.naki.DataStructures.AVLNode implements ITreeNode {
    public var value:Object;      // 节点存储的值
    public var left:AVLNode;      // 左子节点
    public var right:AVLNode;     // 右子节点
    public var height:Number;     // 节点的高度值，叶子节点height=1

    /**
     * 构造函数
     * @param value 节点值
     */
    public function AVLNode(value:Object) {
        this.value = value;
        this.left = null;
        this.right = null;
        this.height = 1;  // 新节点（叶子）的height为1
    }

    /**
     * 返回节点值的字符串表示
     * @return 节点值及其高度的字符串 
     */
    public function toString():String {
        return String(this.value) + "[h=" + this.height + "]";
    }
}
