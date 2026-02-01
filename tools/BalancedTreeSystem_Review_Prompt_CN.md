# ActionScript 2.0 平衡树系统 - 架构与算法审查

## 审查请求

请对附件中的**平衡二叉搜索树系统**进行全面的架构级和算法级评审。该系统实现了五种自平衡BST变体（AVL、WAVL、红黑树、左偏红黑树、Zip树），需要专家级意见来验证：
1. **算法正确性**：各树的不变量是否正确维护
2. **性能优化**：AS2特定的优化是否合理有效
3. **架构设计**：接口抽象和门面模式的设计质量

---

## 技术背景

**语言：** ActionScript 2.0 (Flash Player 32)

### AS2语言特性（重要认知校正）

**性能约束（核心设计原则）：**
- AS2的执行性能**仅为AS3或现代JavaScript的约1/10**
- **任何设计决策都必须将性能作为最高优先级**
- 函数调用开销极高（作用域链创建、参数压栈）
- `this.xxx` 属性访问涉及作用域链查找，代价远高于局部变量

**关键语言限制：**
- 无原生`Map`、`Set`——只有`Object`（哈希表）和`Array`
- 无泛型、无`const`、无块级作用域
- 接口不支持属性声明，只能声明方法
- 无`protected`关键字，子类通过命名约定（`_`前缀）访问父类字段
- 单线程、帧驱动游戏循环（通常30 FPS）

**容错机制：**
- AS2对无效引用**极其宽容**，访问`null`的属性不会抛出异常，只会静默返回`undefined`

---

## 系统架构概述

### 三层设计架构

```
┌─────────────────────────────────────────────────────────────┐
│                     应用层 (Application)                      │
│         TreeSet (门面类)  ←→  OrderedMap (有序映射)            │
└─────────────────────────────────────────────────────────────┘
                              ↓ 委托
┌─────────────────────────────────────────────────────────────┐
│                     抽象层 (Abstraction)                      │
│   IBalancedSearchTree (接口)  ←  AbstractBalancedSearchTree   │
│            ↑ implements                  ↑ extends            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     实现层 (Implementation)                   │
│   AVLTree    WAVLTree    RedBlackTree    LLRedBlackTree      │
│                          ZipTree                              │
│      ↓           ↓           ↓              ↓           ↓     │
│   AVLNode   WAVLNode   RedBlackNode      (共用)     ZipNode   │
└─────────────────────────────────────────────────────────────┘
```

### 核心接口设计

```actionscript
interface IBalancedSearchTree {
    // 核心操作
    function add(element:Object):Void;
    function remove(element:Object):Boolean;
    function contains(element:Object):Boolean;

    // 容量查询
    function size():Number;
    function isEmpty():Boolean;

    // 遍历与转换
    function toArray():Array;
    function toString():String;

    // 比较函数管理
    function changeCompareFunctionAndResort(newCompareFunction:Function):Void;
    function getCompareFunction():Function;

    // 节点访问
    function getRoot():ITreeNode;

    // 有序搜索 (C++ STL风格)
    function lowerBound(element:Object):ITreeNode;  // 第一个 >= element
    function upperBound(element:Object):ITreeNode;  // 第一个 > element
}
```

---

## 五种树实现对比

### 理论特性对比

| 特性 | AVL | WAVL | RedBlack | LLRedBlack | Zip |
|------|-----|------|----------|------------|-----|
| **平衡机制** | 高度差≤1 | rank差∈{1,2} | 黑高度相等 | 左偏红黑 | 随机rank堆序 |
| **树高度** | ~1.44logn | ~1.44logn | ~2logn | ~2logn | ~2logn期望 |
| **插入旋转** | O(logn)最坏 | O(1)摊还 | O(1)摊还 | O(1)摊还 | 0次(期望) |
| **删除旋转** | O(logn)最坏 | O(1)摊还 | O(1)摊还 | O(1)摊还 | O(logn)期望 |
| **实现复杂度** | 低 | 中 | 高 | 中 | 中 |

### 实测性能对比 (10000元素)

| 操作 | AVL | WAVL | RedBlack | Zip |
|------|-----|------|----------|-----|
| 添加 | 376ms | 271ms | 688ms | 207ms |
| 搜索 | 128ms | 117ms | 115ms | 221ms |
| 删除 | 277ms | 185ms | 1285ms | 210ms |
| **总计** | 1120ms | **885ms** | 2426ms | 1364ms |

**结论：WAVL综合性能最优，作为默认选择**

---

## 各树实现详解

### 1. AVLTree (经典AVL树)

**核心不变量：**
- 平衡因子 = 左子树高度 - 右子树高度
- 平衡因子 ∈ {-1, 0, 1}
- 空节点高度为0，叶子节点高度为1

**关键实现：**
```actionscript
// AVLNode.as
public var height:Number;  // 高度值，叶子节点height=1

// AVLTree.as - 插入后平衡
var balance:Number = leftHeight - rightHeight;
if (balance > 1) {
    // 左侧高，判断 LL 或 LR
    node = leftBalance >= 0 ? rotateLL(node) : rotateLR(node);
} else if (balance < -1) {
    // 右侧高，判断 RR 或 RL
    node = rightBalance <= 0 ? rotateRR(node) : rotateRL(node);
}
```

**优化技术：**
- 差分高度早退出：高度未变则无需继续回溯
- deleteMin专用函数：避免双子节点删除时的二次搜索

### 2. WAVLTree (弱AVL树) ⭐ 默认选择

**核心不变量：**
1. rank差 = 父节点rank - 子节点rank，必须为1或2
2. 外部节点(null)的rank定义为-1
3. 叶子节点的rank必须为0（即(1,1)-叶子）
4. **非叶子节点不能是(2,2)-节点**（两侧rank差都是2）

**关键实现（已修复Bug）：**
```actionscript
// WAVLTree.as - 删除后检测 (2,2) 非叶子节点
// 【Bug修复 2024-11】原代码遗漏了此检查
if (leftDiff <= 2) {
    // [修复] 检查是否产生了违规的 (2,2) 非叶子节点
    if (leftDiff == 2 && rightDiff == 2) {
        // (2,2) 非叶子节点需要 demote
        node.rank = nodeRank - 1;
        return node;
    }
    this.__needRebalance = false;
    return node;
}
```

**优化技术（性能演进）：**

| 版本 | Delete耗时 | 优化内容 |
|------|-----------|---------|
| 初始版本 | 435ms | 基础实现 |
| +差分早退出 | 302ms | `__needRebalance`信号 |
| +延迟孙节点访问 | 258ms | 按需读取 |
| +cmpFn缓存 | 251ms | 参数传递 |
| +deleteMin | 231ms | 避免二次搜索 |

### 3. RedBlackTree (红黑树)

**核心不变量：**
1. 每个节点是红色或黑色
2. 根节点是黑色
3. 红色节点的子节点必须是黑色
4. 从任一节点到其所有叶子的路径包含相同数目的黑色节点
5. 空节点(NIL)是黑色

**关键实现（迭代式）：**
```actionscript
// RedBlackTree.as - 使用显式栈替代递归
private function insert(node:RedBlackNode, element:Object, cmpFn:Function):RedBlackNode {
    // 阶段1: 向下搜索，记录路径
    var stack:Array = [];
    var dirs:Array = [];  // 0=左，1=右

    // 阶段2: 创建新节点并链接
    // 阶段3: 向上回溯修复
    while (stackIdx > 0) {
        // 内联修复逻辑
        if (isRed(rightChild) && !isRed(leftChild)) rotateLeft;
        if (isRed(leftChild) && isRed(leftChild.left)) rotateRight;
        if (isRed(leftChild) && isRed(rightChild)) flipColors;
    }
}
```

**buildFromArray优化：**
- 使用分治法O(n)构建，而非逐个插入O(n log n)
- 深度着色策略：最深层着红色，其余着黑色

### 4. LLRedBlackTree (左偏红黑树)

**核心不变量：**
- 所有红色链接都向左倾斜
- 简化了红黑树的实现复杂度

**关键实现：**
```actionscript
// LLRedBlackTree.as - 统一平衡函数
private function balance(h:RedBlackNode):RedBlackNode {
    // 1. 右红链接 → 左旋
    if (isRed(h.right) && !isRed(h.left)) h = rotateLeft(h);
    // 2. 连续左红链接 → 右旋
    if (isRed(h.left) && isRed(h.left.left)) h = rotateRight(h);
    // 3. 左右都红 → 颜色翻转
    if (isRed(h.left) && isRed(h.right)) flipColors(h);
    return h;
}
```

**⚠️ 待优化问题：**
- `remove`方法先调用`contains`再删除，导致两次搜索
- `contains`使用递归`search`函数，有额外函数调用开销
- `toArray`使用递归遍历，未采用迭代式优化

### 5. ZipTree (Zip树)

**核心不变量：**
1. BST性质：左子树所有值 < 当前值 < 右子树所有值
2. 堆序性质：父节点rank ≥ 左子节点rank
3. 严格堆序：父节点rank > 右子节点rank

**关键实现：**
```actionscript
// ZipTree.as - 几何分布rank生成
private function generateRank():Number {
    this.randomSeed = (this.randomSeed * 1103515245 + 12345) & 0x7FFFFFFF;
    var rand:Number = this.randomSeed;
    var rank:Number = 1;
    // 计算尾部连续0的个数+1
    while ((rand & 1) == 0 && rank < 32) {
        rank++;
        rand = rand >> 1;
    }
    return rank;  // P(rank=k) = (1/2)^k
}

// 迭代式unzip (add操作)
while (current != null) {
    if (cmp < 0) {
        // current属于right部分
        rightTail.left = current;
        rightTail = current;
        current = current.left;
        current.left = null;
    } else {
        // current属于left部分
        leftTail.right = current;
        leftTail = current;
        current = current.right;
        current.right = null;
    }
}
```

---

## AS2 特定优化技术汇总

### 1. 比较函数缓存

```actionscript
// ❌ 慢 - 每次递归都查找 this._compareFunction
var cmp:Number = this._compareFunction(element, node.value);

// ✅ 快 - 函数引用作为参数传递
private function insert(node, element, cmpFn:Function):Node {
    var cmp:Number = cmpFn(element, node.value);  // 直接调用
}

public function add(element:Object):Void {
    var cmpFn:Function = _compareFunction;  // 缓存一次
    this.root = insert(this.root, element, cmpFn);
}
```

### 2. 迭代式遍历（避免递归）

```actionscript
// toArray - 显式栈实现中序遍历
public function toArray():Array {
    var arr:Array = new Array(_treeSize);  // 预分配
    var arrIdx:Number = 0;                  // 独立索引
    var stack:Array = [];
    var stackIdx:Number = 0;
    var node = this.root;

    while (node != null || stackIdx > 0) {
        while (node != null) {
            stack[stackIdx++] = node;
            node = node.left;
        }
        node = stack[--stackIdx];
        arr[arrIdx++] = node.value;  // 避免arr.length读取
        node = node.right;
    }
    return arr;
}
```

### 3. 差分早退出

```actionscript
// WAVL删除 - __needRebalance信号
private var __needRebalance:Boolean;

private function deleteNode(node, element, cmpFn):Node {
    node.left = deleteNode(node.left, element, cmpFn);

    // 子树已稳定，无需检查平衡
    if (!this.__needRebalance) return node;

    // 只在需要时进行平衡检查...
}
```

### 4. deleteMin优化

```actionscript
// 避免双子节点删除时的二次搜索
private var __tempMinValue:Object;

// deleteMin同时完成"查找最小值"和"删除节点"
private function deleteMin(node):Node {
    if (node.left == null) {
        this.__tempMinValue = node.value;  // 捕获值
        _treeSize--;
        this.__needRebalance = true;
        return node.right;
    }
    // ...
}

// deleteNode使用
node.right = this.deleteMin(nodeRight);
node.value = this.__tempMinValue;  // 直接使用，无需再搜索
```

---

## 门面类设计

### TreeSet (统一API)

```actionscript
class TreeSet implements IBalancedSearchTree {
    // 树类型常量
    public static var TYPE_AVL:String  = "avl";
    public static var TYPE_WAVL:String = "wavl";   // 默认
    public static var TYPE_RB:String   = "rb";
    public static var TYPE_LLRB:String = "llrb";
    public static var TYPE_ZIP:String  = "zip";

    private var _impl:IBalancedSearchTree;  // 内部实现

    // 构造时选择实现
    public function TreeSet(compareFunction:Function, treeType:String) {
        if (treeType == TYPE_AVL) {
            _impl = new AVLTree(cmpFn);
        } else if (treeType == TYPE_WAVL) {
            _impl = new WAVLTree(cmpFn);  // 默认
        } // ...
    }

    // 所有方法委托给_impl
    public function add(element:Object):Void {
        _impl.add(element);
    }
}
```

### OrderedMap (有序映射)

```actionscript
class OrderedMap {
    private var keySet:TreeSet;    // 有序键集合
    private var valueMap:Object;   // 键值存储
    private var version:Number;    // 结构修改版本号（并发检测）

    // O(log n) 首尾键访问
    public function firstKey():String {
        var node:Object = keySet.getRoot();
        while (node.left != null) node = node.left;
        return node.value;
    }
}
```

---

## 代码结构

```
DataStructures/
├── Core/                          # 接口与抽象基类
│   ├── IBalancedSearchTree.as     # 平衡树统一接口
│   ├── ITreeNode.as               # 节点接口（契约）
│   └── AbstractBalancedSearchTree.as  # 抽象基类（size/lowerBound/upperBound）
│
├── Trees/                         # 树实现
│   ├── AVLTree.as                 # 经典AVL树
│   ├── WAVLTree.as                # 弱AVL树（默认选择）
│   ├── RedBlackTree.as            # 红黑树（迭代式）
│   ├── LLRedBlackTree.as          # 左偏红黑树
│   └── ZipTree.as                 # Zip树（随机化）
│
├── Nodes/                         # 节点类
│   ├── AVLNode.as                 # height字段
│   ├── WAVLNode.as                # rank字段
│   ├── RedBlackNode.as            # color字段（共用）
│   └── ZipNode.as                 # rank字段（随机）
│
├── Application/                   # 应用层
│   ├── TreeSet.as                 # 门面类（统一API）
│   └── OrderedMap.as              # 有序映射
│
├── Docs/                          # 文档
│   ├── AVLTree.md
│   ├── WAVLTree.md
│   ├── RedBlackTree.md
│   ├── ZipTree.md
│   ├── TreeSet.md
│   └── OrderedMap.md
│
└── Tests/                         # 测试
    ├── AVLTreeTest.as             # 145个测试用例
    ├── WAVLTreeTest.as            # 145个测试用例
    ├── RedBlackTreeTest.as        # 176个测试用例
    ├── ZipTreeTest.as             # 151个测试用例
    ├── TreeSetTest.as             # 539个测试用例
    └── OrderedMapTest.as          # 28个测试用例
```

---

## 已知问题与待验证项

### 1. WAVL (2,2)非叶子节点Bug修复验证

**问题描述：**
原代码在删除操作后，只检查 `leftDiff <= 2` 就直接返回，遗漏了 `(2,2)` 非叶子节点的情况。

**修复位置：**
- `WAVLTree.as:804-816` - 左侧删除后检测
- `WAVLTree.as:950-958` - 右侧删除后检测
- `WAVLTree.as:1083-1092` - deleteMin后检测
- `WAVLTree.as:1200-1209` - deleteMin内部检测

**验证请求：** 请确认修复逻辑是否完整覆盖所有场景。

### 2. 红黑树buildFromArray着色策略

**实现方式：**
```actionscript
// 最深层节点着红色，其余着黑色
if (depth == maxDepth) {
    newNode.color = RED;
} else {
    newNode.color = BLACK;
}
```

**验证请求：** 请确认此着色策略在所有节点数n的情况下都能满足红黑树的五条不变量。

### 3. LLRedBlackTree性能优化一致性

**待优化项：**
- `remove`方法的双重搜索问题
- `contains`方法的递归调用
- `toArray`方法的递归遍历
- `buildFromArray`未使用分治法

**验证请求：** 请评估这些优化的必要性和实现建议。

### 4. ZipTree堆序不变量

**不变量定义：**
- 左子：parent.rank >= left.rank
- 右子：parent.rank > right.rank（严格大于）

**验证请求：** 请确认add和remove操作在所有情况下都正确维护这两个不变量。

---

## 审查重点

请**独立评估**以下方面：

### 1. 算法正确性

- 各树的不变量是否在所有操作后正确维护？
- 旋转/promote/demote操作的正确性？
- 边界情况处理（空树、单节点、满二叉树）？

### 2. 性能优化评估

- AS2特定优化是否合理有效？
- 是否存在遗漏的优化机会？
- 各树实现的优化水平是否一致？

### 3. 架构设计评审

- 接口抽象是否合理？
- 门面模式的运用是否恰当？
- 代码复用与可维护性？

### 4. 代码质量

- 命名规范与一致性
- 注释与文档质量
- 测试覆盖度评估

### 5. 改进建议

- 具体的代码改进建议（引用行号）
- 潜在的Bug或风险点
- 性能进一步优化的可能性

---

## 输出格式

请按以下结构组织你的评审意见：

```
## 算法正确性评估
[各树的不变量维护情况、边界情况处理]

## 性能优化评审
[AS2优化技术的有效性、遗漏的优化机会]

## 架构设计评审
[接口设计、模式运用、代码复用]

## 具体问题与建议
[引用具体代码行号的问题和改进建议]

## 风险与注意事项
[潜在风险点及其规避措施]

## 总体评价
[系统整体质量评估和主要改进方向]
```

---

## 审查原则

- **深入细致：** 仔细阅读代码，验证算法正确性
- **具体明确：** 引用实际代码行号，而非泛泛而谈
- **务实导向：** 关注在AS2约束下真正可行的优化
- **性能意识：** 任何建议都要考虑AS2的性能约束

**请特别注意：**
1. AS2性能约束是硬性限制，必须优先考虑
2. 函数调用开销在AS2中极高，内联优化是有效的
3. 递归深度O(log n)意味着每层的微小开销都会累积
4. 该系统已在游戏中实际运行，追求的是"验证正确+发现遗漏"

---

## 附件清单

| 目录 | 文件数 | 说明 |
|------|--------|------|
| DataStructures/Core/ | 3个 | 接口与抽象基类 |
| DataStructures/Trees/ | 5个 | 五种树实现 |
| DataStructures/Nodes/ | 4个 | 节点类 |
| DataStructures/Application/ | 2个 | TreeSet门面、OrderedMap |
| DataStructures/Docs/ | ~6个 | 设计文档 |
| DataStructures/Tests/ | ~6个 | 测试文件 |
| Dependencies/ | ~3个 | TimSort、StringUtils等依赖 |

**总计约30个文件**

---

## 背景补充：为什么需要这套系统

游戏中存在大量需要有序数据结构的场景：

1. **优先级队列**：伤害计算、事件调度
2. **范围查询**：碰撞检测预筛选、AOE范围单位查找
3. **有序遍历**：排行榜、Buff优先级排序
4. **动态插入/删除**：实时变化的游戏实体集合

之前使用Array+排序的方式性能不佳，特别是频繁插入删除场景。
这套平衡树系统提供了O(log n)的增删查改，显著提升了性能。

**实际收益：**
- 碰撞检测预筛选：从O(n²)降至O(n log n)
- Buff优先级排序：从每次O(n log n)排序降至O(log n)插入
- 事件调度器：从O(n)查找降至O(log n)
