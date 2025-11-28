/** 
 * ZipNode - Zip Tree 节点类
 * @class ZipNode
 * @package org.flashNight.naki.DataStructures
 * @description Zip Tree 的节点实现。
 *              每个节点持有一个随机生成的 rank 值，用于维护堆序性质。
 *              Zip Tree 是一种随机化的自平衡二叉搜索树，结合了 Treap 和 Skip List 的特性。
 *
 * 【Zip Tree 核心概念】
 * - rank: 服从几何分布的随机整数，期望值为 1
 * - 堆序不变量: 父节点的 rank >= 子节点的 rank
 * - 相同 rank 时: 使用键值打破平局（右子节点 rank 必须严格小于父节点）
 *
 * 【参考文献】
 * Tarjan, Levy, Timmel: "Zip Trees" (2019)
 * https://arxiv.org/abs/1806.06726
 */
class org.flashNight.naki.DataStructures.ZipNode {
    public var value:Object;      // 节点存储的值
    public var left:ZipNode;      // 左子节点
    public var right:ZipNode;     // 右子节点
    public var rank:Number;       // 节点的 rank 值（几何分布随机数）

    /**
     * 构造函数
     * @param value 节点值
     * @param rank 节点的 rank 值（由 ZipTree 生成）
     */
    public function ZipNode(value:Object, rank:Number) {
        this.value = value;
        this.left = null;
        this.right = null;
        this.rank = rank;
    }

    /**
     * 返回节点值的字符串表示
     * @return 节点值及其 rank 的字符串
     */
    public function toString():String {
        return String(this.value) + "[r=" + this.rank + "]";
    }
}
