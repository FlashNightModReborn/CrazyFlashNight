import org.flashNight.naki.DataStructures.ITreeNode;

/**
 * WAVLNode - WAVL树节点类
 * @class WAVLNode
 * @package org.flashNight.naki.DataStructures
 * @description WAVL (Weak AVL) 树的节点实现。
 *              使用rank而非height来维护平衡，稳定状态下rank差只允许1或2。
 *              （注：0-child 仅在插入过程中作为中间态出现，会被立即修复）
 *              WAVL树是AVL树的推广，具有O(1)摊还旋转的特性。
 *
 * @implements ITreeNode
 */
class org.flashNight.naki.DataStructures.WAVLNode implements ITreeNode {
    public var value:Object;      // 节点存储的值
    public var left:WAVLNode;     // 左子节点
    public var right:WAVLNode;    // 右子节点
    public var rank:Number;       // 节点的rank值，叶子节点rank=0

    /**
     * 构造函数
     * @param value 节点值
     */
    public function WAVLNode(value:Object) {
        this.value = value;
        this.left = null;
        this.right = null;
        this.rank = 0;  // 新节点（叶子）的rank为0
    }

    /**
     * 返回节点值的字符串表示
     * @return 节点值及其rank的字符串
     */
    public function toString():String {
        return String(this.value) + "[r=" + this.rank + "]";
    }
}
