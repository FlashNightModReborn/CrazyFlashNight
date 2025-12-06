/**
 * 平衡搜索树节点公共接口
 * @interface ITreeNode
 * @package org.flashNight.naki.DataStructures
 * @description 定义所有平衡搜索树节点（AVLNode、WAVLNode、RedBlackNode、ZipNode）的统一契约。
 *              此接口用于文档目的和编译时类型约束，不改变运行时行为。 
 *
 * 【设计说明】
 * AS2 接口不支持属性声明，只能声明方法。
 * 但所有节点类都必须具备以下公共字段：
 *
 *   public var value:Object;     // 节点存储的值
 *   public var left:ITreeNode;   // 左子节点（实际类型为具体节点类）
 *   public var right:ITreeNode;  // 右子节点（实际类型为具体节点类）
 *
 * 这些字段由 TreeSetMinimalIterator 等迭代器在运行时通过动态属性访问使用。
 * 节点类实现此接口表明它们遵守这一契约。
 *
 * 【使用方式】
 * 迭代器继续将节点当作 Object 使用（依赖字段名），
 * 而「节点类实现接口」提供额外的编译期约束和文档说明。
 *
 * 【当前实现类】
 * - AVLNode    (value, left, right, height)
 * - WAVLNode   (value, left, right, rank)
 * - RedBlackNode (value, left, right, color)
 * - ZipNode    (value, left, right, rank)
 *
 * 【扩展说明】
 * 各节点类可拥有额外的平衡信息字段（height/rank/color），
 * 这些字段不在接口中定义，由具体树算法自行使用。
 */
interface org.flashNight.naki.DataStructures.ITreeNode {

    /**
     * 获取节点值的字符串表示
     * @return 节点的字符串描述
     */
    function toString():String;
}
