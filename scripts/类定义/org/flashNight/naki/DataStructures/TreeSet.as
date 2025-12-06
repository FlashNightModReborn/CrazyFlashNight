import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.string.*;


/**
 * @class TreeSet
 * @package org.flashNight.naki.DataStructures
 * @description 统一的平衡搜索树基座/外观类（门面模式）。
 *              内部持有一个 IBalancedSearchTree 实现，构造时决定使用 AVL / WAVL / RedBlack / Zip 中的哪一种。
 *              对外 API 保持不变，实现多种平衡树的透明切换。
 *
 * 【设计说明】
 * TreeSet 实现 IBalancedSearchTree 接口，使其可以：
 * 1. 与具体树实现（AVLTree、WAVLTree 等）互换使用，提供多态性
 * 2. 在需要 IBalancedSearchTree 的场景中直接传入 TreeSet
 * 3. 获得编译时接口方法一致性检查
 *
 * 【扩展方法】
 * 除接口方法外，TreeSet 还提供以下扩展方法：
 * - getTreeType(): 返回当前使用的树类型（TreeSet 特有）
 */
class org.flashNight.naki.DataStructures.TreeSet implements IBalancedSearchTree {

    //======================== 树类型常量 ========================//

    /** AVL 树类型 */
    public static var TYPE_AVL:String  = "avl";
    /** WAVL 树类型 */
    public static var TYPE_WAVL:String = "wavl";
    /** 红黑树类型 */
    public static var TYPE_RB:String   = "rb";
    /** 左偏红黑树类型 */
    public static var TYPE_LLRB:String = "llrb";
    /** Zip 树类型 */
    public static var TYPE_ZIP:String  = "zip";

    //======================== 私有字段 ========================//

    /** 内部平衡搜索树实现 */
    private var _impl:IBalancedSearchTree;
    /** 当前使用的树类型（用于调试/测试） */
    private var _treeType:String;

    /**
     * 构造函数
     * @param compareFunction 可选的比较函数，如果未提供，则使用默认的大小比较
     * @param treeType 可选的树类型，如果未提供，则默认使用 AVL 树
     * @param __impl 内部参数，用于 buildFromArray 直接注入已构建的树实现，外部调用请勿使用
     */
    public function TreeSet(compareFunction:Function, treeType:String, __impl:IBalancedSearchTree) {
        // 处理树类型，默认使用 AVL
        if (treeType == undefined || treeType == null) {
            treeType = TreeSet.TYPE_AVL;
        }
        _treeType = treeType;

        // 如果外部传入了已构建的树实现，直接使用（用于 buildFromArray 优化）
        if (__impl != null && __impl != undefined) {
            _impl = __impl;
            return;
        }

        // 处理比较函数
        var cmpFn:Function;
        if (compareFunction == undefined || compareFunction == null) {
            // 默认的比较函数，适用于可比较的基本类型（如数字、字符串）
            cmpFn = function(a, b):Number {
                return (a < b) ? -1 : ((a > b) ? 1 : 0);
            };
        } else {
            cmpFn = compareFunction;
        }

        // 根据类型创建对应的树实现
        if (treeType == TYPE_AVL) {
            _impl = new AVLTree(cmpFn);
        } else if (treeType == TYPE_WAVL) {
            _impl = new WAVLTree(cmpFn);
        } else if (treeType == TYPE_RB) {
            _impl = new RedBlackTree(cmpFn);
        } else if (treeType == TYPE_LLRB) {
            _impl = new LLRedBlackTree(cmpFn);
        } else if (treeType == TYPE_ZIP) {
            _impl = new ZipTree(cmpFn);
        } else {
            throw new Error("Unknown TreeSet type: " + treeType);
        }
    }

    /**
     * [静态方法] 从给定数组构建一个新的平衡树（TreeSet）。
     *   根据 treeType 调用对应实现的 buildFromArray，直接挂载构建好的树。
     * @param arr 输入的元素数组，需为可排序的类型
     * @param compareFunction 用于排序的比较函数
     * @param treeType 可选的树类型，默认使用 AVL
     * @return 新构建的 TreeSet 实例
     */
    public static function buildFromArray(arr:Array, compareFunction:Function, treeType:String):TreeSet {
        // 处理树类型，默认使用 AVL
        if (treeType == undefined || treeType == null) {
            treeType = TYPE_AVL;
        }

        // 处理比较函数
        var cmpFn:Function;
        if (compareFunction == undefined || compareFunction == null) {
            cmpFn = function(a, b):Number {
                return (a < b) ? -1 : ((a > b) ? 1 : 0);
            };
        } else {
            cmpFn = compareFunction;
        }

        // 根据类型调用对应实现的 buildFromArray
        var impl:IBalancedSearchTree;
        if (treeType == TYPE_AVL) {
            impl = AVLTree.buildFromArray(arr, cmpFn);
        } else if (treeType == TYPE_WAVL) {
            impl = WAVLTree.buildFromArray(arr, cmpFn);
        } else if (treeType == TYPE_RB) {
            impl = RedBlackTree.buildFromArray(arr, cmpFn);
        } else if (treeType == TYPE_LLRB) {
            impl = LLRedBlackTree.buildFromArray(arr, cmpFn);
        } else if (treeType == TYPE_ZIP) {
            impl = ZipTree.buildFromArray(arr, cmpFn);
        } else {
            throw new Error("Unknown TreeSet type: " + treeType);
        }

        // 创建 TreeSet 包装器，直接传入已构建的树实现，避免创建多余的空树
        return new TreeSet(cmpFn, treeType, impl);
    }

    /**
     * [实例方法] 更换当前 TreeSet 的比较函数，并对所有数据重新排序和建树。
     * 适用于需要动态更改排序规则的场景。
     * @param newCompareFunction 新的比较函数
     */
    public function changeCompareFunctionAndResort(newCompareFunction:Function):Void {
        _impl.changeCompareFunctionAndResort(newCompareFunction);
    }

    /**
     * 添加元素到树中
     * @param element 要添加的元素
     */
    public function add(element:Object):Void {
        _impl.add(element);
    }

    /**
     * 移除元素
     * @param element 要移除的元素
     * @return 如果成功移除元素则返回 true，否则返回 false
     */
    public function remove(element:Object):Boolean {
        return _impl.remove(element);
    }

    /**
     * 检查树中是否包含某个元素
     * @param element 要检查的元素
     * @return 如果树中包含该元素则返回 true，否则返回 false
     */
    public function contains(element:Object):Boolean {
        return _impl.contains(element);
    }

    /**
     * 获取树大小
     * @return 树中元素的数量
     */
    public function size():Number {
        return _impl.size();
    }

    /**
     * 判断树是否为空
     * @return 如果树为空则返回 true，否则返回 false
     */
    public function isEmpty():Boolean {
        return _impl.isEmpty();
    }

    /**
     * 中序遍历转换为数组
     * @return 一个按升序排列的元素数组
     */
    public function toArray():Array {
        return _impl.toArray();
    }


    /**
     * 返回根节点
     * @return 树的根节点，实现 ITreeNode 接口；空树返回 null
     */
    public function getRoot():ITreeNode {
        return _impl.getRoot();
    }

    /**
     * 返回当前的比较函数
     * @return 当前使用的比较函数
     */
    public function getCompareFunction():Function {
        return _impl.getCompareFunction();
    }

    /**
     * 返回当前使用的树类型
     * @return 树类型字符串
     */
    public function getTreeType():String {
        return _treeType;
    }

    /**
     * 返回树的字符串表示，基于前序遍历
     * @return 树的前序遍历字符串
     */
    public function toString():String {
        return _impl.toString();
    }

}
