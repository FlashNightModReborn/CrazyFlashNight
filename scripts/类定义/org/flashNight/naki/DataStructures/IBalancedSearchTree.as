import org.flashNight.naki.DataStructures.ITreeNode;

/**
 * 平衡二叉搜索树公共接口
 * @interface IBalancedSearchTree
 * @package org.flashNight.naki.DataStructures
 * @description 定义所有平衡二叉搜索树（AVL、WAVL、红黑树、Zip树等）的统一 API。
 *              实现此接口的类可被 TreeSet、OrderedMap 等容器统一使用。
 *
 * 【设计原则】
 * - 包含核心操作方法和迭代器所需的访问方法
 * - buildFromArray 等静态方法无法放入接口，由各类自行实现
 * - getRoot() 返回 ITreeNode，配合迭代器使用
 *
 * 【节点契约】
 * 所有树实现返回的节点必须实现 ITreeNode 接口，并具备以下公共字段：
 *   - value:Object   - 节点存储的值
 *   - left:ITreeNode - 左子节点引用
 *   - right:ITreeNode - 右子节点引用
 *
 * TreeSetMinimalIterator 通过动态属性访问这些字段进行中序遍历。
 *
 * 【当前实现】
 * - TreeSet (门面类)
 * - AVLTree / AVLNode
 * - WAVLTree / WAVLNode
 * - RedBlackTree / RedBlackNode
 * - LLRedBlackTree / RedBlackNode
 * - ZipTree / ZipNode
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

    //==================== 节点访问 ====================//

    /**
     * 获取树的根节点
     * @return 根节点，实现 ITreeNode 接口；空树返回 null
     */
    function getRoot():ITreeNode;
}
