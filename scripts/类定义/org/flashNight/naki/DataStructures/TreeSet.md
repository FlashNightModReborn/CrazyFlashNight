# TreeSet - 平衡搜索树门面类

## 1. 概述与定位

### 1.1 TreeSet 是什么

`TreeSet` 是一个**有序集合** + **平衡搜索树门面（Facade）**，实现 `IBalancedSearchTree` 接口。

- **有序集合语义**：元素按 `compareFunction` 定义的顺序排列，自动去重
- **门面模式**：内部持有具体的树实现，对外提供统一 API，支持透明切换底层算法

### 1.2 支持的树类型

| 常量 | 值 | 算法 | 特点 |
|------|-----|------|------|
| `TYPE_AVL` | `"avl"` | AVL 树 | 最严格平衡，查找最优 |
| `TYPE_WAVL` | `"wavl"` | 弱 AVL 树 | 平衡宽松，删除旋转少，**综合性能最佳，默认选择** |
| `TYPE_RB` | `"rb"` | 红黑树 | 经典实现，平衡中等 |
| `TYPE_LLRB` | `"llrb"` | 左偏红黑树 | 红黑树简化版 |
| `TYPE_ZIP` | `"zip"` | Zip 树 | 随机化平衡，插入最快，查找较慢 |

### 1.3 典型使用场景

| 使用方 | 用途 | 文件 |
|--------|------|------|
| `OrderedMap` | 维护有序键集合 (`keySet`) | `OrderedMap.as` |
| `DepthManager` | MovieClip 深度排序 (`depthTree`) | `DepthManager.as` |
| `ArrayInventory` | 物品栏索引管理 (`indexes`) | `ArrayInventory.as` |
| `TreeSetMinimalIterator` | 中序遍历迭代 | `TreeSetMinimalIterator.as` |

---

## 2. API 总览

### 2.1 基础操作（来自 IBalancedSearchTree）

```actionscript
// 增删查
function add(element:Object):Void;              // 添加元素（重复则忽略）
function remove(element:Object):Boolean;        // 移除元素，返回是否成功
function contains(element:Object):Boolean;      // 检查元素是否存在

// 容量查询
function size():Number;                         // 元素数量
function isEmpty():Boolean;                     // 是否为空

// 遍历与转换
function toArray():Array;                       // 中序遍历导出有序数组
function toString():String;                     // 字符串表示（前序遍历）

// 比较函数
function getCompareFunction():Function;         // 获取当前比较函数
function changeCompareFunctionAndResort(newCompareFunction:Function):Void;  // 更换比较函数并重排

// 节点访问
function getRoot():ITreeNode;                   // 获取根节点（供迭代器使用）
```

### 2.2 TreeSet 扩展方法

```actionscript
// 获取当前树类型
function getTreeType():String;

// 静态工厂方法：从数组批量构建（O(n) 分治构建，避免逐个插入的 O(n log n)）
static function buildFromArray(arr:Array, compareFunction:Function, treeType:String):TreeSet;
```

### 2.3 语义说明

| 特性 | 说明 |
|------|------|
| **集合语义** | 按 `compareFunction` 去重，相同元素只保留一个 |
| **有序输出** | `toArray()` 始终按比较函数的「升序」产出 |
| **重复插入** | 不会增加 `size`，静默忽略 |
| **比较函数** | `function(a, b):Number`，返回负数(a<b) / 0(a==b) / 正数(a>b) |

---

## 3. 使用示例

### 3.1 基本用法

```actionscript
import org.flashNight.naki.DataStructures.*;

// 默认 WAVL 树（综合性能最佳），使用默认比较函数（适用于数字/字符串）
var set:TreeSet = new TreeSet(null);
set.add(10);
set.add(5);
set.add(15);
set.add(10);  // 重复，忽略

trace(set.size());       // 3
trace(set.toArray());    // [5, 10, 15]
trace(set.contains(10)); // true
```

### 3.2 自定义比较函数

```actionscript
// 数字降序
function descCompare(a:Number, b:Number):Number {
    return b - a;
}

var set:TreeSet = new TreeSet(descCompare);
set.add(10);
set.add(5);
set.add(15);

trace(set.toArray());  // [15, 10, 5]
```

### 3.3 指定树类型

```actionscript
// 使用 AVL 树（查找性能最稳定）
var set:TreeSet = new TreeSet(numberCompare, TreeSet.TYPE_AVL);

// 使用 Zip 树（插入最快）
var set:TreeSet = new TreeSet(numberCompare, TreeSet.TYPE_ZIP);
```

### 3.4 从数组批量构建

```actionscript
var arr:Array = [10, 3, 5, 20, 15, 7, 2];

// 使用 buildFromArray 批量构建（比逐个 add 快得多）
var set:TreeSet = TreeSet.buildFromArray(arr, numberCompare, TreeSet.TYPE_AVL);

trace(set.toArray());  // [2, 3, 5, 7, 10, 15, 20]
```

### 3.5 动态更换排序规则

```actionscript
var set:TreeSet = new TreeSet(ascCompare);  // 升序
set.add(10);
set.add(5);
set.add(15);

trace(set.toArray());  // [5, 10, 15]

// 更换为降序
set.changeCompareFunctionAndResort(descCompare);

trace(set.toArray());  // [15, 10, 5]
```

---

## 4. 内部设计与扩展点

### 4.1 门面模式

```
TreeSet
   │
   ├── _impl:IBalancedSearchTree  ←─ 具体树实现
   │       ├── AVLTree
   │       ├── WAVLTree
   │       ├── RedBlackTree
   │       ├── LLRedBlackTree
   │       └── ZipTree
   │
   └── _treeType:String  ←─ 当前类型标识
```

构造时根据 `treeType` 选择具体实现，所有 API 调用委托给 `_impl`。

### 4.2 协议约束

#### IBalancedSearchTree（树接口）

所有树实现必须提供的 API：
- `add` / `remove` / `contains` / `size` / `isEmpty`
- `toArray` / `toString`
- `getCompareFunction` / `changeCompareFunctionAndResort`
- `getRoot():ITreeNode`

#### ITreeNode（节点接口）

所有节点类必须提供的公共字段：
```actionscript
public var value:Object;   // 节点存储的值
public var left:XXXNode;   // 左子节点
public var right:XXXNode;  // 右子节点
```

### 4.3 与迭代器的关系

`TreeSetMinimalIterator` 依赖：
1. `treeSet.getRoot():ITreeNode` - 获取根节点
2. `treeSet.getCompareFunction()` - 获取比较函数（用于查找后继）
3. 节点的 `left` / `right` / `value` 字段

迭代器使用动态属性访问这些字段，因此与具体节点类型解耦。

### 4.4 如何接入新树实现

1. **创建节点类**（如 `NewTreeNode`）
   - 实现 `ITreeNode` 接口
   - 提供 `value` / `left` / `right` 公共字段

2. **创建树类**（如 `NewTree`）
   - 继承 `AbstractBalancedSearchTree`
   - 实现所有抽象方法
   - 提供 `getRoot():ITreeNode`

3. **在 TreeSet 中注册**
   ```actionscript
   public static var TYPE_NEW:String = "new";

   // 构造函数中添加分支
   } else if (treeType == TYPE_NEW) {
       _impl = new NewTree(cmpFn);
   }

   // buildFromArray 中同样添加分支
   ```

---

## 5. 性能特性与选择建议

### 5.1 性能对比汇总

基于 TreeSetTest 的测试数据（单位：毫秒）：

#### 1K 元素

| 操作 | AVL | WAVL | RB | LLRB | Zip |
|------|-----|------|-----|------|-----|
| 添加 | 29 | 20 | 50 | 66 | **15** |
| 搜索 | **8** | 8 | 9 | 9 | 15 |
| 删除 | 20 | **13** | 85 | 135 | 14 |
| 构建 | **5** | 5 | 5 | 68 | 14 |
| **总计** | 62 | **46** | 149 | 278 | 58 |

#### 10K 元素

| 操作 | AVL | WAVL | RB | LLRB | Zip |
|------|-----|------|-----|------|-----|
| 添加 | 353 | 265 | 693 | 904 | **156** |
| 搜索 | **114** | 115 | 116 | 132 | 222 |
| 删除 | 258 | **186** | 1281 | 2055 | 206 |
| 构建 | **44** | 45 | 62 | 920 | 153 |
| **总计** | 769 | **611** | 2152 | 4011 | 737 |

#### 100K 元素

| 操作 | AVL | WAVL | RB | LLRB | Zip |
|------|-----|------|-----|------|-----|
| 添加 | 4320 | 3324 | 8886 | 11104 | **1639** |
| 搜索 | 1438 | 1448 | **1426** | 1518 | 3262 |
| 删除 | 3277 | **2605** | 17015 | 26740 | 3215 |
| 构建 | **436** | 452 | 629 | 11248 | 1552 |
| **总计** | 9471 | **7829** | 27956 | 50610 | 9668 |

### 5.2 性能规律总结

| 操作 | 最优 | 说明 |
|------|------|------|
| **搜索** | AVL ≈ WAVL ≈ RB | 三者搜索性能接近，Zip 较慢 |
| **添加** | Zip > WAVL > AVL > RB >> LLRB | Zip 无旋转最快，WAVL 明显优于 AVL |
| **删除** | WAVL > Zip ≈ AVL >> RB >> LLRB | WAVL 删除旋转 O(1) 摊还，RB 系较慢 |
| **构建** | AVL ≈ WAVL ≈ RB >> LLRB | RB 已优化为 O(n) 分治构建，与 AVL/WAVL 接近 |

### 5.3 选择建议

| 场景 | 推荐类型 | 理由 |
|------|----------|------|
| **通用读写** | `TYPE_WAVL`（默认） | 添加/删除/搜索综合最优 |
| **批量构建 + 多读** | `TYPE_AVL` | 构建最快，搜索最稳定 |
| **大量插入 + 少量读** | `TYPE_ZIP` | 插入最快，但搜索较慢 |
| **需要稳定性保证** | `TYPE_AVL` | 最严格平衡，性能可预测 |
| **算法学习/对比** | `TYPE_RB` / `TYPE_LLRB` | 经典实现，适合教学，不推荐生产环境大数据量 |

**默认推荐**：如果不确定，保持默认 `TYPE_WAVL`（综合性能最佳）。

### 5.4 红黑树系优化状态

RedBlackTree 已完成以下优化：
- **移除 contains() 预检查**：删除操作不再 2 倍搜索
- **比较函数参数传递**：避免 AS2 作用域链查找开销
- **O(n) 分治构建**：buildFromArray 从逐个插入优化为分治法
- **迭代式 insert**：使用显式栈替代递归

**已验证无效的优化**（保持当前实现）：
- 内联小函数（isRed、rotateLeft 等）：性能无变化，可维护性下降
- 迭代式 deleteNode：复杂度高，收益不明显

**结论**：RB/LLRB 作为经典实现保留，但在 AS2 环境下删除性能仍显著落后于 WAVL/AVL，
不建议在大数据量场景使用。后续不再进行结构性优化。

---

## 6. 测试与调试

### 6.1 运行测试

```actionscript
var test = new org.flashNight.naki.DataStructures.TreeSetTest();
test.runTests();
```

### 6.2 测试覆盖

- **功能测试**：五种树类型全覆盖（AVL/WAVL/RB/LLRB/Zip）
  - add / remove / contains / size / toArray
  - 边界情况（删除根节点、叶子节点、双子节点）
  - buildFromArray / changeCompareFunctionAndResort

- **性能测试**：
  - 单类型性能（100 / 1000 / 10000 元素）
  - 跨类型对比（1K / 10K / 100K 元素）

### 6.3 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `contains` 返回 false 但元素已添加 | 比较函数不一致或有 bug | 检查比较函数逻辑 |
| `toArray` 顺序不对 | 比较函数返回值符号错误 | 确保 a<b 返回负数，a>b 返回正数 |
| 重复元素被添加多次 | 比较函数对相同元素返回非 0 | 确保相同元素返回 0 |
| 性能异常慢 | 使用了 RB/LLRB 处理大数据量 | 换用 AVL/WAVL/Zip |

---

## 7. 测试日志

以下是 `TreeSetTest.runTests()` 的完整输出：

```
var a = new org.flashNight.naki.DataStructures.TreeSetTest()
a. runTests();



开始 TreeSet 基座测试...

=== 测试 TreeSet@avl ===

测试 add 方法 [avl]...
PASS: [avl] 添加元素后，size 应为4
PASS: [avl] TreeSet 应包含 10
PASS: [avl] TreeSet 应包含 20
PASS: [avl] TreeSet 应包含 5
PASS: [avl] TreeSet 应包含 15

测试 remove 方法 [avl]...
PASS: [avl] 成功移除存在的元素 20
PASS: [avl] TreeSet 不应包含 20
PASS: [avl] 移除不存在的元素 25 应返回 false

测试 contains 方法 [avl]...
PASS: [avl] TreeSet 应包含 10
PASS: [avl] TreeSet 不应包含 20
PASS: [avl] TreeSet 应包含 5
PASS: [avl] TreeSet 应包含 15
PASS: [avl] TreeSet 不应包含 25

测试 size 方法 [avl]...
PASS: [avl] 当前 size 应为3
PASS: [avl] 添加 25 后，size 应为4
PASS: [avl] 移除 5 后，size 应为3

测试 toArray 方法 [avl]...
PASS: [avl] toArray 返回的数组长度应为3
PASS: [avl] 数组元素应为 10，实际为 10
PASS: [avl] 数组元素应为 15，实际为 15
PASS: [avl] 数组元素应为 25，实际为 25

测试边界情况 [avl]...
PASS: [avl] 成功移除叶子节点 10
PASS: [avl] TreeSet 不应包含 10
PASS: [avl] 成功移除有一个子节点的节点 20
PASS: [avl] TreeSet 不应包含 20
PASS: [avl] TreeSet 应包含 25
PASS: [avl] 成功移除有两个子节点的节点 30
PASS: [avl] TreeSet 不应包含 30
PASS: [avl] TreeSet 应包含 25
PASS: [avl] TreeSet 应包含 35
PASS: [avl] 删除节点后，toArray 返回的数组长度应为4
PASS: [avl] 删除节点后，数组元素应为 25，实际为 25
PASS: [avl] 删除节点后，数组元素应为 35，实际为 35
PASS: [avl] 删除节点后，数组元素应为 40，实际为 40
PASS: [avl] 删除节点后，数组元素应为 50，实际为 50

测试 buildFromArray 方法 [avl]...
PASS: [avl] buildFromArray 后，size 应该等于数组长度 7
PASS: [avl] buildFromArray 后，toArray().length 应该为 7
PASS: [avl] buildFromArray -> 第 0 个元素应为 2，实际是 2
PASS: [avl] buildFromArray -> 第 1 个元素应为 3，实际是 3
PASS: [avl] buildFromArray -> 第 2 个元素应为 5，实际是 5
PASS: [avl] buildFromArray -> 第 3 个元素应为 7，实际是 7
PASS: [avl] buildFromArray -> 第 4 个元素应为 10，实际是 10
PASS: [avl] buildFromArray -> 第 5 个元素应为 15，实际是 15
PASS: [avl] buildFromArray -> 第 6 个元素应为 20，实际是 20
PASS: [avl] buildFromArray 后，TreeSet 应包含 15
PASS: [avl] TreeSet 不应包含 999
PASS: [avl] buildFromArray 后，树类型应为 avl
PASS: [avl] buildFromArray 后，TreeSet 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法 [avl]...
PASS: [avl] 初始插入后，size 应为 8
PASS: [avl] changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: [avl] changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: [avl] changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: [avl] changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: [avl] changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: [avl] changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: [avl] changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: [avl] changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: [avl] changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: [avl] changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列

测试 lowerBound 方法 [avl]...
PASS: [avl] lowerBound(30) 应返回 30
PASS: [avl] lowerBound(25) 应返回 30（第一个 >= 25）
PASS: [avl] lowerBound(10) 应返回 10
PASS: [avl] lowerBound(5) 应返回 10（第一个 >= 5）
PASS: [avl] lowerBound(50) 应返回 50
PASS: [avl] lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: [avl] lowerBound(35) 应返回 40（第一个 >= 35）

测试 upperBound 方法 [avl]...
PASS: [avl] upperBound(30) 应返回 40（第一个 > 30）
PASS: [avl] upperBound(25) 应返回 30（第一个 > 25）
PASS: [avl] upperBound(10) 应返回 20（第一个 > 10）
PASS: [avl] upperBound(5) 应返回 10（第一个 > 5）
PASS: [avl] upperBound(50) 应返回 null（没有 > 50 的元素）
PASS: [avl] upperBound(100) 应返回 null（没有 > 100 的元素）
PASS: [avl] upperBound(35) 应返回 40（第一个 > 35）
PASS: [avl] lowerBound(20) == 20
PASS: [avl] upperBound(20) == 30

测试 lowerBound/upperBound 边界情况 [avl]...
PASS: [avl] 空树 lowerBound(10) 应返回 null
PASS: [avl] 空树 upperBound(10) 应返回 null
PASS: [avl] 单元素树 lowerBound(50) 应返回 50
PASS: [avl] 单元素树 lowerBound(30) 应返回 50
PASS: [avl] 单元素树 lowerBound(70) 应返回 null
PASS: [avl] 单元素树 upperBound(50) 应返回 null
PASS: [avl] 单元素树 upperBound(30) 应返回 50
PASS: [avl] 单元素树 upperBound(70) 应返回 null
PASS: [avl] lowerBound(1) 应返回 1
PASS: [avl] lowerBound(2) 应返回 2
PASS: [avl] lowerBound(3) 应返回 3
PASS: [avl] lowerBound(4) 应返回 4
PASS: [avl] lowerBound(5) 应返回 5
PASS: [avl] lowerBound(6) 应返回 6
PASS: [avl] lowerBound(7) 应返回 7
PASS: [avl] lowerBound(8) 应返回 8
PASS: [avl] lowerBound(9) 应返回 9
PASS: [avl] lowerBound(10) 应返回 10
PASS: [avl] upperBound(1) 应返回 2
PASS: [avl] upperBound(2) 应返回 3
PASS: [avl] upperBound(3) 应返回 4
PASS: [avl] upperBound(4) 应返回 5
PASS: [avl] upperBound(5) 应返回 6
PASS: [avl] upperBound(6) 应返回 7
PASS: [avl] upperBound(7) 应返回 8
PASS: [avl] upperBound(8) 应返回 9
PASS: [avl] upperBound(9) 应返回 10
PASS: [avl] upperBound(10) 应返回 null
PASS: [avl] 使用 lowerBound 判断 30 存在
PASS: [avl] 使用 lowerBound 判断 25 不存在
PASS: [avl] 范围查询 lowerBound(20) == 25
PASS: [avl] 范围查询 upperBound(40) == 50

=== 测试 TreeSet@wavl ===

测试 add 方法 [wavl]...
PASS: [wavl] 添加元素后，size 应为4
PASS: [wavl] TreeSet 应包含 10
PASS: [wavl] TreeSet 应包含 20
PASS: [wavl] TreeSet 应包含 5
PASS: [wavl] TreeSet 应包含 15

测试 remove 方法 [wavl]...
PASS: [wavl] 成功移除存在的元素 20
PASS: [wavl] TreeSet 不应包含 20
PASS: [wavl] 移除不存在的元素 25 应返回 false

测试 contains 方法 [wavl]...
PASS: [wavl] TreeSet 应包含 10
PASS: [wavl] TreeSet 不应包含 20
PASS: [wavl] TreeSet 应包含 5
PASS: [wavl] TreeSet 应包含 15
PASS: [wavl] TreeSet 不应包含 25

测试 size 方法 [wavl]...
PASS: [wavl] 当前 size 应为3
PASS: [wavl] 添加 25 后，size 应为4
PASS: [wavl] 移除 5 后，size 应为3

测试 toArray 方法 [wavl]...
PASS: [wavl] toArray 返回的数组长度应为3
PASS: [wavl] 数组元素应为 10，实际为 10
PASS: [wavl] 数组元素应为 15，实际为 15
PASS: [wavl] 数组元素应为 25，实际为 25

测试边界情况 [wavl]...
PASS: [wavl] 成功移除叶子节点 10
PASS: [wavl] TreeSet 不应包含 10
PASS: [wavl] 成功移除有一个子节点的节点 20
PASS: [wavl] TreeSet 不应包含 20
PASS: [wavl] TreeSet 应包含 25
PASS: [wavl] 成功移除有两个子节点的节点 30
PASS: [wavl] TreeSet 不应包含 30
PASS: [wavl] TreeSet 应包含 25
PASS: [wavl] TreeSet 应包含 35
PASS: [wavl] 删除节点后，toArray 返回的数组长度应为4
PASS: [wavl] 删除节点后，数组元素应为 25，实际为 25
PASS: [wavl] 删除节点后，数组元素应为 35，实际为 35
PASS: [wavl] 删除节点后，数组元素应为 40，实际为 40
PASS: [wavl] 删除节点后，数组元素应为 50，实际为 50

测试 buildFromArray 方法 [wavl]...
PASS: [wavl] buildFromArray 后，size 应该等于数组长度 7
PASS: [wavl] buildFromArray 后，toArray().length 应该为 7
PASS: [wavl] buildFromArray -> 第 0 个元素应为 2，实际是 2
PASS: [wavl] buildFromArray -> 第 1 个元素应为 3，实际是 3
PASS: [wavl] buildFromArray -> 第 2 个元素应为 5，实际是 5
PASS: [wavl] buildFromArray -> 第 3 个元素应为 7，实际是 7
PASS: [wavl] buildFromArray -> 第 4 个元素应为 10，实际是 10
PASS: [wavl] buildFromArray -> 第 5 个元素应为 15，实际是 15
PASS: [wavl] buildFromArray -> 第 6 个元素应为 20，实际是 20
PASS: [wavl] buildFromArray 后，TreeSet 应包含 15
PASS: [wavl] TreeSet 不应包含 999
PASS: [wavl] buildFromArray 后，树类型应为 wavl
PASS: [wavl] buildFromArray 后，TreeSet 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法 [wavl]...
PASS: [wavl] 初始插入后，size 应为 8
PASS: [wavl] changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: [wavl] changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: [wavl] changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: [wavl] changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: [wavl] changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: [wavl] changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: [wavl] changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: [wavl] changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: [wavl] changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: [wavl] changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列

测试 lowerBound 方法 [wavl]...
PASS: [wavl] lowerBound(30) 应返回 30
PASS: [wavl] lowerBound(25) 应返回 30（第一个 >= 25）
PASS: [wavl] lowerBound(10) 应返回 10
PASS: [wavl] lowerBound(5) 应返回 10（第一个 >= 5）
PASS: [wavl] lowerBound(50) 应返回 50
PASS: [wavl] lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: [wavl] lowerBound(35) 应返回 40（第一个 >= 35）

测试 upperBound 方法 [wavl]...
PASS: [wavl] upperBound(30) 应返回 40（第一个 > 30）
PASS: [wavl] upperBound(25) 应返回 30（第一个 > 25）
PASS: [wavl] upperBound(10) 应返回 20（第一个 > 10）
PASS: [wavl] upperBound(5) 应返回 10（第一个 > 5）
PASS: [wavl] upperBound(50) 应返回 null（没有 > 50 的元素）
PASS: [wavl] upperBound(100) 应返回 null（没有 > 100 的元素）
PASS: [wavl] upperBound(35) 应返回 40（第一个 > 35）
PASS: [wavl] lowerBound(20) == 20
PASS: [wavl] upperBound(20) == 30

测试 lowerBound/upperBound 边界情况 [wavl]...
PASS: [wavl] 空树 lowerBound(10) 应返回 null
PASS: [wavl] 空树 upperBound(10) 应返回 null
PASS: [wavl] 单元素树 lowerBound(50) 应返回 50
PASS: [wavl] 单元素树 lowerBound(30) 应返回 50
PASS: [wavl] 单元素树 lowerBound(70) 应返回 null
PASS: [wavl] 单元素树 upperBound(50) 应返回 null
PASS: [wavl] 单元素树 upperBound(30) 应返回 50
PASS: [wavl] 单元素树 upperBound(70) 应返回 null
PASS: [wavl] lowerBound(1) 应返回 1
PASS: [wavl] lowerBound(2) 应返回 2
PASS: [wavl] lowerBound(3) 应返回 3
PASS: [wavl] lowerBound(4) 应返回 4
PASS: [wavl] lowerBound(5) 应返回 5
PASS: [wavl] lowerBound(6) 应返回 6
PASS: [wavl] lowerBound(7) 应返回 7
PASS: [wavl] lowerBound(8) 应返回 8
PASS: [wavl] lowerBound(9) 应返回 9
PASS: [wavl] lowerBound(10) 应返回 10
PASS: [wavl] upperBound(1) 应返回 2
PASS: [wavl] upperBound(2) 应返回 3
PASS: [wavl] upperBound(3) 应返回 4
PASS: [wavl] upperBound(4) 应返回 5
PASS: [wavl] upperBound(5) 应返回 6
PASS: [wavl] upperBound(6) 应返回 7
PASS: [wavl] upperBound(7) 应返回 8
PASS: [wavl] upperBound(8) 应返回 9
PASS: [wavl] upperBound(9) 应返回 10
PASS: [wavl] upperBound(10) 应返回 null
PASS: [wavl] 使用 lowerBound 判断 30 存在
PASS: [wavl] 使用 lowerBound 判断 25 不存在
PASS: [wavl] 范围查询 lowerBound(20) == 25
PASS: [wavl] 范围查询 upperBound(40) == 50

=== 测试 TreeSet@rb ===

测试 add 方法 [rb]...
PASS: [rb] 添加元素后，size 应为4
PASS: [rb] TreeSet 应包含 10
PASS: [rb] TreeSet 应包含 20
PASS: [rb] TreeSet 应包含 5
PASS: [rb] TreeSet 应包含 15

测试 remove 方法 [rb]...
PASS: [rb] 成功移除存在的元素 20
PASS: [rb] TreeSet 不应包含 20
PASS: [rb] 移除不存在的元素 25 应返回 false

测试 contains 方法 [rb]...
PASS: [rb] TreeSet 应包含 10
PASS: [rb] TreeSet 不应包含 20
PASS: [rb] TreeSet 应包含 5
PASS: [rb] TreeSet 应包含 15
PASS: [rb] TreeSet 不应包含 25

测试 size 方法 [rb]...
PASS: [rb] 当前 size 应为3
PASS: [rb] 添加 25 后，size 应为4
PASS: [rb] 移除 5 后，size 应为3

测试 toArray 方法 [rb]...
PASS: [rb] toArray 返回的数组长度应为3
PASS: [rb] 数组元素应为 10，实际为 10
PASS: [rb] 数组元素应为 15，实际为 15
PASS: [rb] 数组元素应为 25，实际为 25

测试边界情况 [rb]...
PASS: [rb] 成功移除叶子节点 10
PASS: [rb] TreeSet 不应包含 10
PASS: [rb] 成功移除有一个子节点的节点 20
PASS: [rb] TreeSet 不应包含 20
PASS: [rb] TreeSet 应包含 25
PASS: [rb] 成功移除有两个子节点的节点 30
PASS: [rb] TreeSet 不应包含 30
PASS: [rb] TreeSet 应包含 25
PASS: [rb] TreeSet 应包含 35
PASS: [rb] 删除节点后，toArray 返回的数组长度应为4
PASS: [rb] 删除节点后，数组元素应为 25，实际为 25
PASS: [rb] 删除节点后，数组元素应为 35，实际为 35
PASS: [rb] 删除节点后，数组元素应为 40，实际为 40
PASS: [rb] 删除节点后，数组元素应为 50，实际为 50

测试 buildFromArray 方法 [rb]...
PASS: [rb] buildFromArray 后，size 应该等于数组长度 7
PASS: [rb] buildFromArray 后，toArray().length 应该为 7
PASS: [rb] buildFromArray -> 第 0 个元素应为 2，实际是 2
PASS: [rb] buildFromArray -> 第 1 个元素应为 3，实际是 3
PASS: [rb] buildFromArray -> 第 2 个元素应为 5，实际是 5
PASS: [rb] buildFromArray -> 第 3 个元素应为 7，实际是 7
PASS: [rb] buildFromArray -> 第 4 个元素应为 10，实际是 10
PASS: [rb] buildFromArray -> 第 5 个元素应为 15，实际是 15
PASS: [rb] buildFromArray -> 第 6 个元素应为 20，实际是 20
PASS: [rb] buildFromArray 后，TreeSet 应包含 15
PASS: [rb] TreeSet 不应包含 999
PASS: [rb] buildFromArray 后，树类型应为 rb
PASS: [rb] buildFromArray 后，TreeSet 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法 [rb]...
PASS: [rb] 初始插入后，size 应为 8
PASS: [rb] changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: [rb] changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: [rb] changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: [rb] changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: [rb] changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: [rb] changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: [rb] changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: [rb] changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: [rb] changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: [rb] changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列

测试 lowerBound 方法 [rb]...
PASS: [rb] lowerBound(30) 应返回 30
PASS: [rb] lowerBound(25) 应返回 30（第一个 >= 25）
PASS: [rb] lowerBound(10) 应返回 10
PASS: [rb] lowerBound(5) 应返回 10（第一个 >= 5）
PASS: [rb] lowerBound(50) 应返回 50
PASS: [rb] lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: [rb] lowerBound(35) 应返回 40（第一个 >= 35）

测试 upperBound 方法 [rb]...
PASS: [rb] upperBound(30) 应返回 40（第一个 > 30）
PASS: [rb] upperBound(25) 应返回 30（第一个 > 25）
PASS: [rb] upperBound(10) 应返回 20（第一个 > 10）
PASS: [rb] upperBound(5) 应返回 10（第一个 > 5）
PASS: [rb] upperBound(50) 应返回 null（没有 > 50 的元素）
PASS: [rb] upperBound(100) 应返回 null（没有 > 100 的元素）
PASS: [rb] upperBound(35) 应返回 40（第一个 > 35）
PASS: [rb] lowerBound(20) == 20
PASS: [rb] upperBound(20) == 30

测试 lowerBound/upperBound 边界情况 [rb]...
PASS: [rb] 空树 lowerBound(10) 应返回 null
PASS: [rb] 空树 upperBound(10) 应返回 null
PASS: [rb] 单元素树 lowerBound(50) 应返回 50
PASS: [rb] 单元素树 lowerBound(30) 应返回 50
PASS: [rb] 单元素树 lowerBound(70) 应返回 null
PASS: [rb] 单元素树 upperBound(50) 应返回 null
PASS: [rb] 单元素树 upperBound(30) 应返回 50
PASS: [rb] 单元素树 upperBound(70) 应返回 null
PASS: [rb] lowerBound(1) 应返回 1
PASS: [rb] lowerBound(2) 应返回 2
PASS: [rb] lowerBound(3) 应返回 3
PASS: [rb] lowerBound(4) 应返回 4
PASS: [rb] lowerBound(5) 应返回 5
PASS: [rb] lowerBound(6) 应返回 6
PASS: [rb] lowerBound(7) 应返回 7
PASS: [rb] lowerBound(8) 应返回 8
PASS: [rb] lowerBound(9) 应返回 9
PASS: [rb] lowerBound(10) 应返回 10
PASS: [rb] upperBound(1) 应返回 2
PASS: [rb] upperBound(2) 应返回 3
PASS: [rb] upperBound(3) 应返回 4
PASS: [rb] upperBound(4) 应返回 5
PASS: [rb] upperBound(5) 应返回 6
PASS: [rb] upperBound(6) 应返回 7
PASS: [rb] upperBound(7) 应返回 8
PASS: [rb] upperBound(8) 应返回 9
PASS: [rb] upperBound(9) 应返回 10
PASS: [rb] upperBound(10) 应返回 null
PASS: [rb] 使用 lowerBound 判断 30 存在
PASS: [rb] 使用 lowerBound 判断 25 不存在
PASS: [rb] 范围查询 lowerBound(20) == 25
PASS: [rb] 范围查询 upperBound(40) == 50

=== 测试 TreeSet@llrb ===

测试 add 方法 [llrb]...
PASS: [llrb] 添加元素后，size 应为4
PASS: [llrb] TreeSet 应包含 10
PASS: [llrb] TreeSet 应包含 20
PASS: [llrb] TreeSet 应包含 5
PASS: [llrb] TreeSet 应包含 15

测试 remove 方法 [llrb]...
PASS: [llrb] 成功移除存在的元素 20
PASS: [llrb] TreeSet 不应包含 20
PASS: [llrb] 移除不存在的元素 25 应返回 false

测试 contains 方法 [llrb]...
PASS: [llrb] TreeSet 应包含 10
PASS: [llrb] TreeSet 不应包含 20
PASS: [llrb] TreeSet 应包含 5
PASS: [llrb] TreeSet 应包含 15
PASS: [llrb] TreeSet 不应包含 25

测试 size 方法 [llrb]...
PASS: [llrb] 当前 size 应为3
PASS: [llrb] 添加 25 后，size 应为4
PASS: [llrb] 移除 5 后，size 应为3

测试 toArray 方法 [llrb]...
PASS: [llrb] toArray 返回的数组长度应为3
PASS: [llrb] 数组元素应为 10，实际为 10
PASS: [llrb] 数组元素应为 15，实际为 15
PASS: [llrb] 数组元素应为 25，实际为 25

测试边界情况 [llrb]...
PASS: [llrb] 成功移除叶子节点 10
PASS: [llrb] TreeSet 不应包含 10
PASS: [llrb] 成功移除有一个子节点的节点 20
PASS: [llrb] TreeSet 不应包含 20
PASS: [llrb] TreeSet 应包含 25
PASS: [llrb] 成功移除有两个子节点的节点 30
PASS: [llrb] TreeSet 不应包含 30
PASS: [llrb] TreeSet 应包含 25
PASS: [llrb] TreeSet 应包含 35
PASS: [llrb] 删除节点后，toArray 返回的数组长度应为4
PASS: [llrb] 删除节点后，数组元素应为 25，实际为 25
PASS: [llrb] 删除节点后，数组元素应为 35，实际为 35
PASS: [llrb] 删除节点后，数组元素应为 40，实际为 40
PASS: [llrb] 删除节点后，数组元素应为 50，实际为 50

测试 buildFromArray 方法 [llrb]...
PASS: [llrb] buildFromArray 后，size 应该等于数组长度 7
PASS: [llrb] buildFromArray 后，toArray().length 应该为 7
PASS: [llrb] buildFromArray -> 第 0 个元素应为 2，实际是 2
PASS: [llrb] buildFromArray -> 第 1 个元素应为 3，实际是 3
PASS: [llrb] buildFromArray -> 第 2 个元素应为 5，实际是 5
PASS: [llrb] buildFromArray -> 第 3 个元素应为 7，实际是 7
PASS: [llrb] buildFromArray -> 第 4 个元素应为 10，实际是 10
PASS: [llrb] buildFromArray -> 第 5 个元素应为 15，实际是 15
PASS: [llrb] buildFromArray -> 第 6 个元素应为 20，实际是 20
PASS: [llrb] buildFromArray 后，TreeSet 应包含 15
PASS: [llrb] TreeSet 不应包含 999
PASS: [llrb] buildFromArray 后，树类型应为 llrb
PASS: [llrb] buildFromArray 后，TreeSet 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法 [llrb]...
PASS: [llrb] 初始插入后，size 应为 8
PASS: [llrb] changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: [llrb] changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: [llrb] changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: [llrb] changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: [llrb] changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: [llrb] changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: [llrb] changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: [llrb] changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: [llrb] changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: [llrb] changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列

测试 lowerBound 方法 [llrb]...
PASS: [llrb] lowerBound(30) 应返回 30
PASS: [llrb] lowerBound(25) 应返回 30（第一个 >= 25）
PASS: [llrb] lowerBound(10) 应返回 10
PASS: [llrb] lowerBound(5) 应返回 10（第一个 >= 5）
PASS: [llrb] lowerBound(50) 应返回 50
PASS: [llrb] lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: [llrb] lowerBound(35) 应返回 40（第一个 >= 35）

测试 upperBound 方法 [llrb]...
PASS: [llrb] upperBound(30) 应返回 40（第一个 > 30）
PASS: [llrb] upperBound(25) 应返回 30（第一个 > 25）
PASS: [llrb] upperBound(10) 应返回 20（第一个 > 10）
PASS: [llrb] upperBound(5) 应返回 10（第一个 > 5）
PASS: [llrb] upperBound(50) 应返回 null（没有 > 50 的元素）
PASS: [llrb] upperBound(100) 应返回 null（没有 > 100 的元素）
PASS: [llrb] upperBound(35) 应返回 40（第一个 > 35）
PASS: [llrb] lowerBound(20) == 20
PASS: [llrb] upperBound(20) == 30

测试 lowerBound/upperBound 边界情况 [llrb]...
PASS: [llrb] 空树 lowerBound(10) 应返回 null
PASS: [llrb] 空树 upperBound(10) 应返回 null
PASS: [llrb] 单元素树 lowerBound(50) 应返回 50
PASS: [llrb] 单元素树 lowerBound(30) 应返回 50
PASS: [llrb] 单元素树 lowerBound(70) 应返回 null
PASS: [llrb] 单元素树 upperBound(50) 应返回 null
PASS: [llrb] 单元素树 upperBound(30) 应返回 50
PASS: [llrb] 单元素树 upperBound(70) 应返回 null
PASS: [llrb] lowerBound(1) 应返回 1
PASS: [llrb] lowerBound(2) 应返回 2
PASS: [llrb] lowerBound(3) 应返回 3
PASS: [llrb] lowerBound(4) 应返回 4
PASS: [llrb] lowerBound(5) 应返回 5
PASS: [llrb] lowerBound(6) 应返回 6
PASS: [llrb] lowerBound(7) 应返回 7
PASS: [llrb] lowerBound(8) 应返回 8
PASS: [llrb] lowerBound(9) 应返回 9
PASS: [llrb] lowerBound(10) 应返回 10
PASS: [llrb] upperBound(1) 应返回 2
PASS: [llrb] upperBound(2) 应返回 3
PASS: [llrb] upperBound(3) 应返回 4
PASS: [llrb] upperBound(4) 应返回 5
PASS: [llrb] upperBound(5) 应返回 6
PASS: [llrb] upperBound(6) 应返回 7
PASS: [llrb] upperBound(7) 应返回 8
PASS: [llrb] upperBound(8) 应返回 9
PASS: [llrb] upperBound(9) 应返回 10
PASS: [llrb] upperBound(10) 应返回 null
PASS: [llrb] 使用 lowerBound 判断 30 存在
PASS: [llrb] 使用 lowerBound 判断 25 不存在
PASS: [llrb] 范围查询 lowerBound(20) == 25
PASS: [llrb] 范围查询 upperBound(40) == 50

=== 测试 TreeSet@zip ===

测试 add 方法 [zip]...
PASS: [zip] 添加元素后，size 应为4
PASS: [zip] TreeSet 应包含 10
PASS: [zip] TreeSet 应包含 20
PASS: [zip] TreeSet 应包含 5
PASS: [zip] TreeSet 应包含 15

测试 remove 方法 [zip]...
PASS: [zip] 成功移除存在的元素 20
PASS: [zip] TreeSet 不应包含 20
PASS: [zip] 移除不存在的元素 25 应返回 false

测试 contains 方法 [zip]...
PASS: [zip] TreeSet 应包含 10
PASS: [zip] TreeSet 不应包含 20
PASS: [zip] TreeSet 应包含 5
PASS: [zip] TreeSet 应包含 15
PASS: [zip] TreeSet 不应包含 25

测试 size 方法 [zip]...
PASS: [zip] 当前 size 应为3
PASS: [zip] 添加 25 后，size 应为4
PASS: [zip] 移除 5 后，size 应为3

测试 toArray 方法 [zip]...
PASS: [zip] toArray 返回的数组长度应为3
PASS: [zip] 数组元素应为 10，实际为 10
PASS: [zip] 数组元素应为 15，实际为 15
PASS: [zip] 数组元素应为 25，实际为 25

测试边界情况 [zip]...
PASS: [zip] 成功移除叶子节点 10
PASS: [zip] TreeSet 不应包含 10
PASS: [zip] 成功移除有一个子节点的节点 20
PASS: [zip] TreeSet 不应包含 20
PASS: [zip] TreeSet 应包含 25
PASS: [zip] 成功移除有两个子节点的节点 30
PASS: [zip] TreeSet 不应包含 30
PASS: [zip] TreeSet 应包含 25
PASS: [zip] TreeSet 应包含 35
PASS: [zip] 删除节点后，toArray 返回的数组长度应为4
PASS: [zip] 删除节点后，数组元素应为 25，实际为 25
PASS: [zip] 删除节点后，数组元素应为 35，实际为 35
PASS: [zip] 删除节点后，数组元素应为 40，实际为 40
PASS: [zip] 删除节点后，数组元素应为 50，实际为 50

测试 buildFromArray 方法 [zip]...
PASS: [zip] buildFromArray 后，size 应该等于数组长度 7
PASS: [zip] buildFromArray 后，toArray().length 应该为 7
PASS: [zip] buildFromArray -> 第 0 个元素应为 2，实际是 2
PASS: [zip] buildFromArray -> 第 1 个元素应为 3，实际是 3
PASS: [zip] buildFromArray -> 第 2 个元素应为 5，实际是 5
PASS: [zip] buildFromArray -> 第 3 个元素应为 7，实际是 7
PASS: [zip] buildFromArray -> 第 4 个元素应为 10，实际是 10
PASS: [zip] buildFromArray -> 第 5 个元素应为 15，实际是 15
PASS: [zip] buildFromArray -> 第 6 个元素应为 20，实际是 20
PASS: [zip] buildFromArray 后，TreeSet 应包含 15
PASS: [zip] TreeSet 不应包含 999
PASS: [zip] buildFromArray 后，树类型应为 zip
PASS: [zip] buildFromArray 后，TreeSet 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法 [zip]...
PASS: [zip] 初始插入后，size 应为 8
PASS: [zip] changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: [zip] changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: [zip] changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: [zip] changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: [zip] changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: [zip] changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: [zip] changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: [zip] changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: [zip] changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: [zip] changeCompareFunctionAndResort 后，TreeSet 的 toArray 应按降序排列

测试 lowerBound 方法 [zip]...
PASS: [zip] lowerBound(30) 应返回 30
PASS: [zip] lowerBound(25) 应返回 30（第一个 >= 25）
PASS: [zip] lowerBound(10) 应返回 10
PASS: [zip] lowerBound(5) 应返回 10（第一个 >= 5）
PASS: [zip] lowerBound(50) 应返回 50
PASS: [zip] lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: [zip] lowerBound(35) 应返回 40（第一个 >= 35）

测试 upperBound 方法 [zip]...
PASS: [zip] upperBound(30) 应返回 40（第一个 > 30）
PASS: [zip] upperBound(25) 应返回 30（第一个 > 25）
PASS: [zip] upperBound(10) 应返回 20（第一个 > 10）
PASS: [zip] upperBound(5) 应返回 10（第一个 > 5）
PASS: [zip] upperBound(50) 应返回 null（没有 > 50 的元素）
PASS: [zip] upperBound(100) 应返回 null（没有 > 100 的元素）
PASS: [zip] upperBound(35) 应返回 40（第一个 > 35）
PASS: [zip] lowerBound(20) == 20
PASS: [zip] upperBound(20) == 30

测试 lowerBound/upperBound 边界情况 [zip]...
PASS: [zip] 空树 lowerBound(10) 应返回 null
PASS: [zip] 空树 upperBound(10) 应返回 null
PASS: [zip] 单元素树 lowerBound(50) 应返回 50
PASS: [zip] 单元素树 lowerBound(30) 应返回 50
PASS: [zip] 单元素树 lowerBound(70) 应返回 null
PASS: [zip] 单元素树 upperBound(50) 应返回 null
PASS: [zip] 单元素树 upperBound(30) 应返回 50
PASS: [zip] 单元素树 upperBound(70) 应返回 null
PASS: [zip] lowerBound(1) 应返回 1
PASS: [zip] lowerBound(2) 应返回 2
PASS: [zip] lowerBound(3) 应返回 3
PASS: [zip] lowerBound(4) 应返回 4
PASS: [zip] lowerBound(5) 应返回 5
PASS: [zip] lowerBound(6) 应返回 6
PASS: [zip] lowerBound(7) 应返回 7
PASS: [zip] lowerBound(8) 应返回 8
PASS: [zip] lowerBound(9) 应返回 9
PASS: [zip] lowerBound(10) 应返回 10
PASS: [zip] upperBound(1) 应返回 2
PASS: [zip] upperBound(2) 应返回 3
PASS: [zip] upperBound(3) 应返回 4
PASS: [zip] upperBound(4) 应返回 5
PASS: [zip] upperBound(5) 应返回 6
PASS: [zip] upperBound(6) 应返回 7
PASS: [zip] upperBound(7) 应返回 8
PASS: [zip] upperBound(8) 应返回 9
PASS: [zip] upperBound(9) 应返回 10
PASS: [zip] upperBound(10) 应返回 null
PASS: [zip] 使用 lowerBound 判断 30 存在
PASS: [zip] 使用 lowerBound 判断 25 不存在
PASS: [zip] 范围查询 lowerBound(20) == 25
PASS: [zip] 范围查询 upperBound(40) == 50

测试性能表现 [wavl]...

容量: 100，执行次数: 100
PASS: [wavl] 所有元素移除后，size 应为0
PASS: [wavl] 所有添加的元素都应成功移除
PASS: [wavl] 所有添加的元素都应存在于 TreeSet 中
添加 100 个元素平均耗时: 1.6 毫秒
搜索 100 个元素平均耗时: 0.57 毫秒
移除 100 个元素平均耗时: 1.06 毫秒
buildFromArray(100 个元素)平均耗时: 0.51 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.66 毫秒

容量: 1000，执行次数: 10
PASS: [wavl] 所有元素移除后，size 应为0
PASS: [wavl] 所有添加的元素都应成功移除
PASS: [wavl] 所有添加的元素都应存在于 TreeSet 中
添加 1000 个元素平均耗时: 21.4 毫秒
搜索 1000 个元素平均耗时: 8.9 毫秒
移除 1000 个元素平均耗时: 13.7 毫秒
buildFromArray(1000 个元素)平均耗时: 4.7 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 5.7 毫秒

容量: 10000，执行次数: 1
PASS: [wavl] 所有元素移除后，size 应为0
PASS: [wavl] 所有添加的元素都应成功移除
PASS: [wavl] 所有添加的元素都应存在于 TreeSet 中
添加 10000 个元素平均耗时: 282 毫秒
搜索 10000 个元素平均耗时: 122 毫秒
移除 10000 个元素平均耗时: 198 毫秒
buildFromArray(10000 个元素)平均耗时: 46 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 60 毫秒

########################################
## 五种树类型跨容量性能对比测试
########################################

========================================
容量级别: 1K (1000 元素)
========================================

--- AVL ---
添加: 30 ms
搜索: 9 ms
删除: 20 ms
构建: 3 ms
边界搜索: 23 ms

--- WAVL ---
添加: 20 ms
搜索: 9 ms
删除: 14 ms
构建: 5 ms
边界搜索: 20 ms

--- RB ---
添加: 51 ms
搜索: 8 ms
删除: 90 ms
构建: 6 ms
边界搜索: 22 ms

--- LLRB ---
添加: 66 ms
搜索: 10 ms
删除: 137 ms
构建: 67 ms
边界搜索: 21 ms

--- Zip ---
添加: 18 ms
搜索: 16 ms
删除: 14 ms
构建: 20 ms
边界搜索: 39 ms

----------------------------------------
汇总表 [1K] (1000 元素)
----------------------------------------
操作		AVL	WAVL	RB	LLRB	Zip	
添加		30	20	51	66	18	
搜索		9	9	8	10	16	
删除		20	14	90	137	14	
构建		3	5	6	67	20	
边界搜索	23	20	22	21	39	
总计		85	68	177	301	107	

添加 最优: Zip (18ms) | 最差: LLRB (66ms)
搜索 最优: RB (8ms) | 最差: Zip (16ms)
删除 最优: WAVL (14ms) | 最差: LLRB (137ms)
构建 最优: AVL (3ms) | 最差: LLRB (67ms)
边界搜索 最优: WAVL (20ms) | 最差: Zip (39ms)

========================================
容量级别: 10K (10000 元素)
========================================

--- AVL ---
添加: 376 ms
搜索: 128 ms
删除: 277 ms
构建: 47 ms
边界搜索: 292 ms

--- WAVL ---
添加: 271 ms
搜索: 117 ms
删除: 185 ms
构建: 44 ms
边界搜索: 268 ms

--- RB ---
添加: 688 ms
搜索: 115 ms
删除: 1285 ms
构建: 60 ms
边界搜索: 278 ms

--- LLRB ---
添加: 912 ms
搜索: 126 ms
删除: 2080 ms
构建: 941 ms
边界搜索: 278 ms

--- Zip ---
添加: 207 ms
搜索: 221 ms
删除: 210 ms
构建: 238 ms
边界搜索: 488 ms

----------------------------------------
汇总表 [10K] (10000 元素)
----------------------------------------
操作		AVL	WAVL	RB	LLRB	Zip	
添加		376	271	688	912	207	
搜索		128	117	115	126	221	
删除		277	185	1285	2080	210	
构建		47	44	60	941	238	
边界搜索	292	268	278	278	488	
总计		1120	885	2426	4337	1364	

添加 最优: Zip (207ms) | 最差: LLRB (912ms)
搜索 最优: RB (115ms) | 最差: Zip (221ms)
删除 最优: WAVL (185ms) | 最差: LLRB (2080ms)
构建 最优: WAVL (44ms) | 最差: LLRB (941ms)
边界搜索 最优: WAVL (268ms) | 最差: Zip (488ms)

========================================
容量级别: 100K (100000 元素)
========================================

--- AVL ---
添加: 4376 ms
搜索: 1442 ms
删除: 3358 ms
构建: 449 ms
边界搜索: 3292 ms

--- WAVL ---
添加: 3361 ms
搜索: 1452 ms
删除: 2654 ms
构建: 451 ms
边界搜索: 3245 ms

--- RB ---
添加: 8840 ms
搜索: 1442 ms
删除: 17142 ms
构建: 633 ms
边界搜索: 3249 ms

--- LLRB ---
添加: 11309 ms
搜索: 1568 ms
删除: 27164 ms
构建: 11449 ms
边界搜索: 3283 ms

--- Zip ---
添加: 2144 ms
搜索: 3221 ms
删除: 3288 ms
构建: 2166 ms
边界搜索: 6950 ms

----------------------------------------
汇总表 [100K] (100000 元素)
----------------------------------------
操作		AVL	WAVL	RB	LLRB	Zip	
添加		4376	3361	8840	11309	2144	
搜索		1442	1452	1442	1568	3221	
删除		3358	2654	17142	27164	3288	
构建		449	451	633	11449	2166	
边界搜索	3292	3245	3249	3283	6950	
总计		12917	11163	31306	54773	17769	

添加 最优: Zip (2144ms) | 最差: LLRB (11309ms)
搜索 最优: AVL (1442ms) | 最差: Zip (3221ms)
删除 最优: WAVL (2654ms) | 最差: LLRB (27164ms)
构建 最优: AVL (449ms) | 最差: LLRB (11449ms)
边界搜索 最优: WAVL (3245ms) | 最差: Zip (6950ms)

########################################
## 全容量对比完成
########################################

测试完成。通过: 539 个，失败: 0 个。


```
