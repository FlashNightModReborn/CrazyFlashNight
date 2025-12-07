短评：在你现在这套结构下，把 lowerBound/upperBound 做成“接口级能力”的成本是中等偏低的，主要工作量集中在接口签名更新、抽象基类实现、TreeSet 门面转发和测试/文档补齐，不需要给每棵树分别写一份算法。

1. 结构现状对成本的影响

现在的层次是：
接口：IBalancedSearchTree scripts/类定义/org/flashNight/naki/DataStructures/IBalancedSearchTree.as:1
抽象基类：AbstractBalancedSearchTree 实现了通用字段 + size/isEmpty/getCompareFunction scripts/类定义/org/flashNight/naki/DataStructures/AbstractBalancedSearchTree.as:20
各树：AVLTree/WAVLTree/RedBlackTree/LLRedBlackTree/ZipTree 都 extends AbstractBalancedSearchTree implements IBalancedSearchTree。
门面：TreeSet implements IBalancedSearchTree，内部持有 _impl:IBalancedSearchTree 并做转发 scripts/类定义/org/flashNight/naki/DataStructures/TreeSet.as:23–33。
所有节点类都遵守 ITreeNode 协议（value/left/right），TreeSetMinimalIterator 也是靠这个做中序遍历的 scripts/类定义/org/flashNight/naki/DataStructures/ITreeNode.as:1–27。
→ 也就是说：“只依赖 getRoot() + _compareFunction 的通用 BST 搜索逻辑，放在 AbstractBalancedSearchTree 里实现一次就能复用所有树类型。

2. 代码层面的改动范围

如果你选择把这两个方法作为“接口能力”来加，大致步骤是：

扩展接口签名（一次）
在 IBalancedSearchTree 里添加类似声明 scripts/类定义/org/flashNight/naki/DataStructures/IBalancedSearchTree.as:63 之后位置合适处：

// 新增：有序搜索
function lowerBound(element:Object):ITreeNode;  // 第一个 >= element 的节点，找不到返回 null
function upperBound(element:Object):ITreeNode;  // 第一个 >  element 的节点，找不到返回 null
选择返回 ITreeNode 而不是 Object 的好处是：
与现有 getRoot():ITreeNode 一致；
方便将来做“从某个 bound 开始用后继遍历”的范围扫描。
外部如果只需要值，可以用 node ? node.value : null。
在抽象基类里提供通用实现（一次，最关键）
在 AbstractBalancedSearchTree 中新增方法 scripts/类定义/org/flashNight/naki/DataStructures/AbstractBalancedSearchTree.as:60 之后，例如：

public function lowerBound(element:Object):ITreeNode {
    var current:ITreeNode = getRoot();
    var candidate:ITreeNode = null;
    var cmpFn:Function = _compareFunction;

    while (current != null) {
        var cmp:Number = cmpFn(element, current.value);
        if (cmp <= 0) {
            candidate = current;
            current = current.left;
        } else {
            current = current.right;
        }
    }
    return candidate;
}

public function upperBound(element:Object):ITreeNode {
    var current:ITreeNode = getRoot();
    var candidate:ITreeNode = null;
    var cmpFn:Function = _compareFunction;

    while (current != null) {
        var cmp:Number = cmpFn(element, current.value);
        if (cmp < 0) {
            candidate = current;
            current = current.left;
        } else {
            current = current.right;
        }
    }
    return candidate;
}
复杂度 O(log n)，不依赖父指针，只依赖 value/left/right。
所有 extends AbstractBalancedSearchTree 的树都自动获得这两个实现，无需单独写。
TreeSet 门面添加转发（一次）
在 TreeSet 里补两个简单转发 scripts/类定义/org/flashNight/naki/DataStructures/TreeSet.as:

public function lowerBound(element:Object):ITreeNode {
    return _impl.lowerBound(element);
}

public function upperBound(element:Object):ITreeNode {
    return _impl.upperBound(element);
}
编译器兼容性考虑

AS2 的接口一旦新增方法，所有 implements IBalancedSearchTree 的类都必须提供实现，否则 Flash 编译期报错。
这里我们通过在 AbstractBalancedSearchTree 中提供默认实现，避免对 AVLTree/WAVLTree/... 做任何改动；它们会自动满足接口。
唯一必须手写的是 TreeSet（因为它没继承基类，只是门面）。
→ 代码改动的“散布范围”不大：3 个核心文件（接口 + 抽象基类 + TreeSet），其它树类不用动。

3. 测试与文档成本

这部分才是主要的人力时间：

测试：

建议在现有 TreeSetTest.as 里加一组 testLowerUpperBound()，复用那套“对所有 treeType 做横向测试”的框架 scripts/类定义/org/flashNight/naki/DataStructures/TreeSetTest.as:459–544。
覆盖点包括：
空树返回 null；
key 比最小值小/比最大值大；
恰好命中现有值 / 落在两个值之间；
TreeSet 默认“去重”语义下 lower/upper 的行为。
因为是门面测试，一套用例自动覆盖全部底层树实现。
文档：

IBalancedSearchTree.as 上的接口注释需要同步说明“有序搜索”能力。
TreeSet.md 建议在“2.2 扩展方法”中加入这两个 API 的说明和简单示例。
如果你打算用它来服务新的迭代器或范围查询，可以在 TreeSetMinimalIterator.md 里补一段“未来可以基于 lowerBound 做范围遍历”的说明（可选）。
→ 整体来看，实现难度低，验证与文档工作中等，主要精力在“定义清晰的语义 + 写一套不漏边界的测试”。

4. 风险与注意点

语义要一次性想清楚：

约定严格采用 C++ 风格：
lowerBound(x) = 第一个 >= x 的节点；
upperBound(x) = 第一个 > x 的节点。
这一定要写进注释，否则后面容易出现“有人当成第一个 == x 的节点”来用。
TreeSet 是集合语义：

由于 TreeSet 本身去重，lowerBound(key) 和 contains(key) 的关系就很简单：
var n = lowerBound(key);
n == null → 一定是不存在；
n != null && compareFn(key, n.value) == 0 → 存在；
否则是“比 key 大的第一个元素”。
这为你后面用 TreeSet 直接做“按 name/复合键 range 搜索”打下基础。
ZipTree / 红黑树等实现差异不影响算法：

只要它们都维持“中序有序 + compareFunction 一致”的 BST 性质，lower/upperBound 的逻辑对所有实现都是正确的，不需要针对某种树做特例。
5. 总体评价

纯工程角度：

改动面：小（3 个核心文件 + 1 套测试 + 适量文档）。
算法复杂度：低（标准 BST 搜索套路，没有 tricky 旋转逻辑）。
风险：主要是接口签名变更带来的编译器强制要求，但我们用抽象基类兜底基本可以控制在安全范围内。
如果你后面确定要做“复合键 TreeSet + 范围查询（按 name、按标签等）”，先把 lowerBound/upperBound 作为接口能力加进去是值得的，投入产出比是合算的。