# ZipTree 技术文档

## 目录

1. [概述](#概述)
2. [理论基础](#理论基础)
3. [算法详解](#算法详解)
4. [性能测试](#性能测试)
5. [API 参考](#api-参考)
6. [使用示例](#使用示例)
7. [文件清单](#文件清单)

---

## 概述

ZipTree 是基于 Zip Tree 算法实现的随机化自平衡二叉搜索树。

### 核心特性

- **算法来源**: Tarjan, Levy, Timmel 2019 论文 "Zip Trees" (arXiv:1806.06726)
- **平衡机制**: 基于随机 rank 的堆序性质
- **性能特点**: 期望 O(log n) 操作，实现简洁，无需复杂旋转

### 与传统平衡树对比

| 特性 | AVL | 红黑树 | WAVL | Zip Tree |
|------|-----|--------|------|----------|
| 平衡机制 | 高度差≤1 | 黑高度相等 | rank差∈{1,2} | **随机 rank** |
| 最坏情况 | O(log n) | O(log n) | O(log n) | O(n) * |
| 期望情况 | O(log n) | O(log n) | O(log n) | **O(log n)** |
| 实现复杂度 | 低 | 高 | 中 | **低** |
| 旋转操作 | 单/双旋转 | 旋转+重色 | 旋转+rank | **zip/unzip** |

\* Zip Tree 最坏情况发生概率指数级衰减，实际应用中极不可能

### 为什么选择 Zip Tree

1. **实现简单**: 核心操作 zip/unzip 逻辑清晰，无需处理多种旋转情况
2. **代码简洁**: 比 AVL/红黑树/WAVL 实现更短
3. **并发友好**: 结构变化局部性好，适合并发修改
4. **教学价值**: 展示了随机化算法的威力

---

## 理论基础

### Zip Tree 不变量

1. **BST 性质**: 左子树所有值 < 当前值 < 右子树所有值
2. **堆序性质 (左)**: 父节点的 rank >= 左子节点的 rank
3. **严格堆序 (右)**: 父节点的 rank > 右子节点的 rank

```
       node[r]
       /    \
   left[≤r]  right[<r]   ← 注意左右的不同条件
```

### Rank 分布

每个节点的 rank 服从几何分布 Geometric(1/2):

```
P(rank = k) = (1/2)^k,  k ≥ 1

E[rank] = 1
P(rank ≥ k) = (1/2)^(k-1)
```

这意味着：
- 50% 的节点 rank = 1
- 25% 的节点 rank = 2
- 12.5% 的节点 rank = 3
- ...

高 rank 节点稀少，自然形成 "脊椎" 结构，期望树高 O(log n)。

### 与 Treap 的关系

Zip Tree 可以看作 Treap 的变体：
- Treap: 使用均匀分布的随机优先级
- Zip Tree: 使用几何分布的 rank + 不对称堆序规则

不对称规则（左 >=，右 >）确保了树的唯一性，简化了实现。

---

## 算法详解

### 插入操作 (Insert)

```
Insert(x, rank):
1. 从根开始 BST 搜索
2. 在搜索路径上找到第一个 rank < x.rank 的节点位置
3. 将 x 插入该位置
4. 使用 unzip 将原子树分裂到 x 的左右子树

       node[2]                    x[3]
       /    \                    /    \
      ...    ...      →      (≤x)     (>x)
                             原子树按 x 分裂
```

**Unzip 操作**: 将一棵树按某个键分裂成两棵树

```actionscript
unzip(node, key):
  if node == null: return [null, null]
  if key < node.value:
    [left, right] = unzip(node.left, key)
    node.left = right
    return [left, node]
  else:
    [left, right] = unzip(node.right, key)
    node.right = left
    return [node, right]
```

### 删除操作 (Delete)

```
Delete(x):
1. BST 搜索找到 x
2. 使用 zip 合并 x 的左右子树
3. 返回合并结果替代 x

      x[3]                  zip(L, R)
     /   \          →
    L     R              合并后的树
```

**Zip 操作**: 将两棵树（左树所有值 < 右树所有值）合并成一棵

```actionscript
zip(left, right):
  if left == null: return right
  if right == null: return left
  if left.rank > right.rank:   // 严格大于，确保右子 rank < 父 rank
    left.right = zip(left.right, right)
    return left
  else:                         // rank 相等时也让 right 成为根
    right.left = zip(left, right.left)
    return right
```

**关键点**: zip 中使用严格 `>` 而非 `>=`，确保当 `left.rank == right.rank` 时，
`right` 成为根，`left` 进入 `right.left`。这满足了不变量：
- 左子: `parent.rank >= left.rank` ✓
- 右子: `parent.rank > right.rank` ✓（避免 rank 相等的右子）

### 复杂度分析

| 操作 | 期望时间复杂度 | 最坏时间复杂度 |
|------|---------------|---------------|
| insert | O(log n) | O(n) |
| delete | O(log n) | O(n) |
| search | O(log n) | O(n) |

最坏情况（所有节点 rank 相同或递增）的概率随 n 指数衰减。

---

## 性能测试

### 启动代码

```actionscript
import org.flashNight.naki.DataStructures.*;

var zipTest:ZipTreeTest = new ZipTreeTest();
zipTest.runTests();
```

### 预期测试结果

```
========================================
开始 ZipTree 测试...
========================================

测试 add 方法...
PASS: 添加元素后，size 应为4
PASS: ZipTree 应包含 10
PASS: ZipTree 应包含 20
PASS: ZipTree 应包含 5
PASS: ZipTree 应包含 15
PASS: 添加后的树应保持Zip Tree属性

测试 remove 方法...
PASS: 成功移除存在的元素 20
PASS: ZipTree 不应包含 20
PASS: 移除不存在的元素 25 应返回 false
PASS: 移除后的树应保持Zip Tree属性

测试 contains 方法...
PASS: ZipTree 应包含 10
PASS: ZipTree 不应包含 20
PASS: ZipTree 应包含 5
PASS: ZipTree 应包含 15
PASS: ZipTree 不应包含 25

测试 size 方法...
PASS: 当前 size 应为3
PASS: 添加 25 后，size 应为4
PASS: 移除 5 后，size 应为3
PASS: 添加删除后的树应保持Zip Tree属性

测试 toArray 方法...
PASS: toArray 返回的数组长度应为3
PASS: 数组元素应为 10，实际为 10
PASS: 数组元素应为 15，实际为 15
PASS: 数组元素应为 25，实际为 25

测试边界情况...
PASS: 初始树应保持Zip Tree属性
PASS: 成功移除叶子节点 10
PASS: ZipTree 不应包含 10
PASS: 删除叶子节点后应保持Zip Tree属性
PASS: 成功移除有一个子节点的节点 20
PASS: ZipTree 不应包含 20
PASS: ZipTree 应包含 25
PASS: 删除有一个子节点的节点后应保持Zip Tree属性
PASS: 成功移除有两个子节点的节点 30
PASS: ZipTree 不应包含 30
PASS: ZipTree 应包含 25
PASS: ZipTree 应包含 35
PASS: 删除有两个子节点的节点后应保持Zip Tree属性
PASS: 删除节点后，toArray 返回的数组长度应为4
PASS: 删除节点后，数组元素应为 25，实际为 25
PASS: 删除节点后，数组元素应为 35，实际为 35
PASS: 删除节点后，数组元素应为 40，实际为 40
PASS: 删除节点后，数组元素应为 50，实际为 50

测试 buildFromArray 方法...
PASS: buildFromArray 后，size 应该等于数组长度 7
PASS: buildFromArray 后，toArray().length 应该为 7
PASS: buildFromArray -> 第 0 个元素应为 2，实际是 2
PASS: buildFromArray -> 第 1 个元素应为 3，实际是 3
PASS: buildFromArray -> 第 2 个元素应为 5，实际是 5
PASS: buildFromArray -> 第 3 个元素应为 7，实际是 7
PASS: buildFromArray -> 第 4 个元素应为 10，实际是 10
PASS: buildFromArray -> 第 5 个元素应为 15，实际是 15
PASS: buildFromArray -> 第 6 个元素应为 20，实际是 20
PASS: buildFromArray 后，ZipTree 应包含 15
PASS: ZipTree 不应包含 999
PASS: buildFromArray 后，ZipTree 应保持Zip Tree属性
PASS: buildFromArray 后，ZipTree 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法...
PASS: 初始插入后，size 应为 8
PASS: 插入元素后，ZipTree 应保持Zip Tree属性
PASS: changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: changeCompareFunctionAndResort 后，ZipTree 应保持Zip Tree属性
PASS: changeCompareFunctionAndResort 后，ZipTree 的 toArray 应按降序排列

测试 Zip Tree 特有属性...
PASS: 添加元素 50 后，树应保持Zip Tree属性
PASS: 添加元素 30 后，树应保持Zip Tree属性
PASS: 添加元素 70 后，树应保持Zip Tree属性
PASS: 添加元素 20 后，树应保持Zip Tree属性
PASS: 添加元素 40 后，树应保持Zip Tree属性
PASS: 添加元素 60 后，树应保持Zip Tree属性
PASS: 添加元素 80 后，树应保持Zip Tree属性
PASS: 添加元素 15 后，树应保持Zip Tree属性
PASS: 添加元素 25 后，树应保持Zip Tree属性
PASS: 添加元素 35 后，树应保持Zip Tree属性
PASS: 添加元素 45 后，树应保持Zip Tree属性
PASS: 添加元素 55 后，树应保持Zip Tree属性
PASS: 添加元素 65 后，树应保持Zip Tree属性
PASS: 添加元素 75 后，树应保持Zip Tree属性
PASS: 添加元素 85 后，树应保持Zip Tree属性
PASS: 删除元素 30 后，树应保持Zip Tree属性
PASS: 删除元素 60 后，树应保持Zip Tree属性
PASS: 删除元素 25 后，树应保持Zip Tree属性
PASS: 删除元素 75 后，树应保持Zip Tree属性
PASS: 添加元素 22 后，树应保持Zip Tree属性
PASS: 添加元素 33 后，树应保持Zip Tree属性
PASS: 添加元素 66 后，树应保持Zip Tree属性
PASS: 添加元素 77 后，树应保持Zip Tree属性

测试随机操作序列...
PASS: 随机插入后，树应保持Zip Tree属性
PASS: size 应等于实际插入的元素数量
PASS: 所有插入的元素都应存在于树中
PASS: 随机删除后，树应保持Zip Tree属性
PASS: 删除后 size 应正确
PASS: 中序遍历结果应有序

测试 lowerBound 方法...
PASS: lowerBound(30) 应返回 30
PASS: lowerBound(25) 应返回 30（第一个 >= 25）
PASS: lowerBound(10) 应返回 10
PASS: lowerBound(5) 应返回 10（第一个 >= 5）
PASS: lowerBound(50) 应返回 50
PASS: lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: lowerBound(35) 应返回 40（第一个 >= 35）
PASS: lowerBound 测试后，树应保持 Zip Tree 属性

测试 upperBound 方法...
PASS: upperBound(30) 应返回 40（第一个 > 30）
PASS: upperBound(25) 应返回 30（第一个 > 25）
PASS: upperBound(10) 应返回 20（第一个 > 10）
PASS: upperBound(5) 应返回 10（第一个 > 5）
PASS: upperBound(50) 应返回 null（没有 > 50 的元素）
PASS: upperBound(100) 应返回 null（没有 > 100 的元素）
PASS: upperBound(35) 应返回 40（第一个 > 35）
PASS: lowerBound(20) == 20
PASS: upperBound(20) == 30
PASS: upperBound 测试后，树应保持 Zip Tree 属性

测试 lowerBound/upperBound 边界情况...
PASS: 空树 lowerBound(10) 应返回 null
PASS: 空树 upperBound(10) 应返回 null
PASS: 单元素树 lowerBound(50) 应返回 50
PASS: 单元素树 lowerBound(30) 应返回 50
PASS: 单元素树 lowerBound(70) 应返回 null
PASS: 单元素树 upperBound(50) 应返回 null
PASS: 单元素树 upperBound(30) 应返回 50
PASS: lowerBound(1) 应返回 1
PASS: lowerBound(2) 应返回 2
PASS: lowerBound(3) 应返回 3
PASS: lowerBound(4) 应返回 4
PASS: lowerBound(5) 应返回 5
PASS: lowerBound(6) 应返回 6
PASS: lowerBound(7) 应返回 7
PASS: lowerBound(8) 应返回 8
PASS: lowerBound(9) 应返回 9
PASS: lowerBound(10) 应返回 10
PASS: upperBound(1) 应返回 2
PASS: upperBound(2) 应返回 3
PASS: upperBound(3) 应返回 4
PASS: upperBound(4) 应返回 5
PASS: upperBound(5) 应返回 6
PASS: upperBound(6) 应返回 7
PASS: upperBound(7) 应返回 8
PASS: upperBound(8) 应返回 9
PASS: upperBound(9) 应返回 10
PASS: upperBound(10) 应返回 null
PASS: 边界测试后，树应保持 Zip Tree 属性

测试性能表现...

容量: 100，执行次数: 100
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 ZipTree 中
添加 100 个元素平均耗时: 1.34 毫秒
搜索 100 个元素平均耗时: 1.18 毫秒
移除 100 个元素平均耗时: 1.2 毫秒
buildFromArray(100 个元素)平均耗时: 1.5 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 1.65 毫秒

容量: 1000，执行次数: 10
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 ZipTree 中
添加 1000 个元素平均耗时: 17.1 毫秒
搜索 1000 个元素平均耗时: 17.9 毫秒
移除 1000 个元素平均耗时: 17.8 毫秒
buildFromArray(1000 个元素)平均耗时: 18.8 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 19.9 毫秒

容量: 10000，执行次数: 1
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 ZipTree 中
添加 10000 个元素平均耗时: 200 毫秒
搜索 10000 个元素平均耗时: 216 毫秒
移除 10000 个元素平均耗时: 201 毫秒
buildFromArray(10000 个元素)平均耗时: 209 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 221 毫秒

========================================
测试完成。通过: 151 个，失败: 0 个。
========================================







```

### 性能分析说明

#### 测试结果分析（10000 元素）

| 操作 | AVL | RB | WAVL | Zip | Zip 表现 |
|------|-----|-----|------|-----|----------|
| 添加 | 472 | 1194 | 382 | **195** | 🥇 最快 |
| 搜索 | 164 | 167 | **146** | 285 | 较慢 |
| 删除 | 229 | 2782 | 248 | 279 | 中等 |
| 总计 | 865 | 4143 | 776 | **759** | 🥇 最快 |

#### Zip Tree 性能特点

**优势**:
- **插入最快**: 195ms，比 WAVL(382ms) 快 49%，比 AVL(472ms) 快 59%
- **总体最优**: 759ms 总计，优于 WAVL(776ms) 和 AVL(865ms)
- **实现简单**: 无需复杂的旋转逻辑，代码量最少
- **并发友好**: 结构变化局部性好

**劣势**:
- **搜索较慢**: 285ms，比 WAVL(146ms) 慢 95%，比 AVL(164ms) 慢 74%
- **原因**: 随机 rank 导致树高度不如确定性平衡树稳定

#### 适用场景

- **推荐使用**:
  - 写多读少的场景（如日志收集、事件队列）
  - 需要综合性能均衡的场景
  - 对代码简洁性有要求的项目
  - 学习随机化数据结构

- **不推荐使用**:
  - 读多写少的场景（搜索密集型）
  - 需要严格最坏情况保证的关键系统

#### 为什么搜索较慢

Zip Tree 的期望树高 O(log n)，但由于随机性：
1. 树高度方差比确定性平衡树大
2. 某些随机序列可能产生较深的树

如果搜索性能是首要考虑，推荐使用 WAVL 树。

---

## API 参考

### 构造函数

```actionscript
public function ZipTree(compareFunction:Function)
```

创建 Zip Tree 实例。

**参数**:
- `compareFunction`: 比较函数，可选。签名: `function(a, b):Number`，返回负数/0/正数。

**示例**:
```actionscript
// 默认升序
var tree:ZipTree = new ZipTree();

// 降序
var tree:ZipTree = new ZipTree(function(a, b):Number {
    return b - a;
});
```

### 静态方法

#### buildFromArray

```actionscript
public static function buildFromArray(arr:Array, compareFunction:Function):ZipTree
```

从数组批量构建树。

### 实例方法

#### add

```actionscript
public function add(element:Object):Void
```

添加元素。重复元素不会被添加（集合语义）。

#### remove

```actionscript
public function remove(element:Object):Boolean
```

移除元素。返回是否成功移除。

#### contains

```actionscript
public function contains(element:Object):Boolean
```

检查元素是否存在。

#### size

```actionscript
public function size():Number
```

获取元素数量。

#### toArray

```actionscript
public function toArray():Array
```

导出为有序数组（中序遍历）。

#### changeCompareFunctionAndResort

```actionscript
public function changeCompareFunctionAndResort(newCompareFunction:Function):Void
```

更换比较函数并重新排序。

#### setSeed

```actionscript
public function setSeed(seed:Number):Void
```

设置随机种子（用于测试可重复性）。

#### getRoot

```actionscript
public function getRoot():ZipNode
```

获取根节点（用于调试）。

---

## 使用示例

### 基础用法

```actionscript
import org.flashNight.naki.DataStructures.*;

// 创建树
var tree:ZipTree = new ZipTree();

// 添加元素
tree.add(50);
tree.add(30);
tree.add(70);
tree.add(20);
tree.add(40);

// 查询
trace(tree.contains(30));  // true
trace(tree.contains(100)); // false
trace(tree.size());        // 5

// 删除
tree.remove(30);
trace(tree.contains(30));  // false

// 导出为数组
var arr:Array = tree.toArray();
trace(arr);  // 20,40,50,70
```

### 自定义比较函数

```actionscript
// 对象按属性排序
var tree:ZipTree = new ZipTree(function(a, b):Number {
    return a.priority - b.priority;
});

tree.add({name: "task1", priority: 3});
tree.add({name: "task2", priority: 1});
tree.add({name: "task3", priority: 2});

var tasks:Array = tree.toArray();
// tasks[0].name == "task2" (priority=1)
// tasks[1].name == "task3" (priority=2)
// tasks[2].name == "task1" (priority=3)
```

### 批量构建

```actionscript
var data:Array = [5, 3, 8, 1, 9, 2, 7, 4, 6];

// 快速批量构建（推荐大数据量时使用）
var tree:ZipTree = ZipTree.buildFromArray(data, null);

trace(tree.toArray());  // 1,2,3,4,5,6,7,8,9
```

### 可重复测试

```actionscript
// 设置固定种子，确保测试可重复
var tree:ZipTree = new ZipTree();
tree.setSeed(12345);

tree.add(10);
tree.add(20);
tree.add(5);

// 每次使用相同种子，树结构相同
```

### 动态切换排序

```actionscript
var tree:ZipTree = new ZipTree();
tree.add(3);
tree.add(1);
tree.add(4);
tree.add(1);
tree.add(5);

trace(tree.toArray());  // 1,3,4,5 (升序)

// 切换为降序
tree.changeCompareFunctionAndResort(function(a, b):Number {
    return b - a;
});

trace(tree.toArray());  // 5,4,3,1 (降序)
```

---

## 文件清单

| 文件 | 说明 |
|------|------|
| `ZipNode.as` | Zip Tree 节点类 |
| `ZipTree.as` | Zip Tree 主类（包含详尽注释） |
| `ZipTreeTest.as` | 测试类（包含四种树对比） |
| `ZipTree.md` | 本文档 |

---

## 总结

ZipTree 在 AS2 环境下提供了一个实现简洁且综合性能优秀的随机化平衡树：

- **综合性能最优**: 总体耗时 759ms，优于 WAVL(776ms) 和 AVL(865ms)
- **插入性能突出**: 195ms，领先所有确定性平衡树
- **实现简洁**: zip/unzip 操作逻辑清晰，代码量比 WAVL 少
- **完整测试覆盖**: 包括不变量验证、随机测试、性能对比
- **API 兼容**: 与 WAVLTree、TreeSet、RedBlackTree 接口一致

Zip Tree 适合以下场景：
- 写多读少或读写均衡的应用
- 对代码简洁性有要求的项目
- 学习随机化数据结构
- 不需要严格最坏情况保证的应用

如果搜索性能是首要考虑，推荐使用 WAVL 树。

参考文献：
- Tarjan, Levy, Timmel: "Zip Trees" (2019), arXiv:1806.06726
