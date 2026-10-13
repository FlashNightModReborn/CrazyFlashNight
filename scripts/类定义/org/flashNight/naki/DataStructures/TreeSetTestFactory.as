import org.flashNight.naki.DataStructures.*;

/** 独立测试根：生产 TreeSet 不引用本类。 */
class org.flashNight.naki.DataStructures.TreeSetTestFactory {
    public static function create(cmp:Function, kind:String):TreeSet {
        if (kind == undefined || kind == null) kind = TreeSet.TYPE_WAVL;
        if (kind == TreeSet.TYPE_WAVL) return new TreeSet(cmp);
        var impl:IBalancedSearchTree;
        if (kind == TreeSet.TYPE_AVL) impl = new AVLTree(cmp);
        else if (kind == TreeSet.TYPE_RB) impl = new RedBlackTree(cmp);
        else if (kind == TreeSet.TYPE_LLRB) impl = new LLRedBlackTree(cmp);
        else if (kind == TreeSet.TYPE_ZIP) impl = new ZipTree(cmp);
        else throw new Error("Unknown test TreeSet backend: " + kind);
        return new TreeSet(cmp, kind, impl);
    }

    public static function buildFromArray(values:Array, cmp:Function, kind:String):TreeSet {
        if (kind == undefined || kind == null) kind = TreeSet.TYPE_WAVL;
        if (kind == TreeSet.TYPE_WAVL) return TreeSet.buildFromArray(values, cmp);
        var impl:IBalancedSearchTree;
        if (kind == TreeSet.TYPE_AVL) impl = AVLTree.buildFromArray(values, cmp);
        else if (kind == TreeSet.TYPE_RB) impl = RedBlackTree.buildFromArray(values, cmp);
        else if (kind == TreeSet.TYPE_LLRB) impl = LLRedBlackTree.buildFromArray(values, cmp);
        else if (kind == TreeSet.TYPE_ZIP) impl = ZipTree.buildFromArray(values, cmp);
        else throw new Error("Unknown test TreeSet backend: " + kind);
        return new TreeSet(cmp, kind, impl);
    }
}
