/**
 * 平衡二叉搜索树公共接口
 * @interface IBalancedSearchTree
 * @package org.flashNight.naki.DataStructures
 * @description 定义所有平衡二叉搜索树（AVL、WAVL、红黑树、Zip树等）的统一 API。
 *              实现此接口的类可被 OrderedMap 等容器统一使用。
 *
 * 【设计原则】
 * - 只包含核心操作方法，不强制实现特化方法（如 getRoot、getMin 等）
 * - 各树可在自己类中提供额外的特化方法
 * - buildFromArray 等静态方法无法放入接口，由各类自行实现
 *
 * 【扩展契约 - 重要！】
 * 配合 TreeSet / TreeSetMinimalIterator 使用的树实现必须遵守以下约定：
 *
 * 1. **必须提供 getRoot() 方法**
 *    - 签名: function getRoot():XXXNode
 *    - 返回树的根节点，用于迭代器遍历和调试
 *    - 此方法不在接口中定义，但 TreeSet 通过动态属性访问调用
 *
 * 2. **节点类必须具备以下属性**
 *    - left:XXXNode  - 左子节点引用
 *    - right:XXXNode - 右子节点引用
 *    - value:Object  - 节点存储的值
 *    - TreeSetMinimalIterator 依赖这些属性进行中序遍历
 *
 * 3. **当前符合契约的实现**
 *    - AVLTree / AVLNode
 *    - WAVLTree / WAVLNode
 *    - RedBlackTree / RedBlackNode
 *    - LLRedBlackTree / RedBlackNode
 *    - ZipTree / ZipNode
 *
 * 若新增 IBalancedSearchTree 实现但不遵守此契约，
 * TreeSet.getRoot() 和 TreeSetMinimalIterator 将在运行时失败。
 */
interface org.flashNight.naki.DataStructures.IBalancedSearchTree {

    //==================== 核心操作 ====================//

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    function add(element:Object):Void;

    /**
     * 从树中移除元素
     * @param element 要移除的元素
     * @return 如果成功移除返回 true，元素不存在返回 false
     */
    function remove(element:Object):Boolean;

    /**
     * 检查树中是否包含指定元素
     * @param element 要检查的元素
     * @return 如果包含返回 true，否则返回 false
     */
    function contains(element:Object):Boolean;

    //==================== 容量查询 ====================//

    /**
     * 获取树中元素数量
     * @return 元素数量
     */
    function size():Number;

    /**
     * 检查树是否为空
     * @return 如果为空返回 true，否则返回 false
     */
    function isEmpty():Boolean;

    //==================== 遍历与转换 ====================//

    /**
     * 将树中元素按序导出为数组（中序遍历）
     * @return 有序数组
     */
    function toArray():Array;

    /**
     * 获取树的字符串表示
     * @return 字符串表示
     */
    function toString():String;

    //==================== 比较函数管理 ====================//

    /**
     * 更换比较函数并重新排序所有元素
     * @param newCompareFunction 新的比较函数
     */
    function changeCompareFunctionAndResort(newCompareFunction:Function):Void;

    /**
     * 获取当前使用的比较函数
     * @return 比较函数
     */
    function getCompareFunction():Function;
}
