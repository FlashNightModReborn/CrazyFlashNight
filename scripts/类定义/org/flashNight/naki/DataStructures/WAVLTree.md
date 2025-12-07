# WAVLTree 技术文档

## 目录

1. [概述](#概述)
2. [理论基础](#理论基础)
3. [性能测试](#性能测试)
4. [优化历程](#优化历程)
5. [Bug 修复记录](#bug-修复记录)
6. [API 参考](#api-参考)
7. [使用示例](#使用示例)
8. [文件清单](#文件清单)

---

## 概述

WAVLTree 是基于 WAVL (Weak AVL) 树算法实现的高性能自平衡二叉搜索树。

### 核心特性

- **算法来源**: Haeupler, Sen, Tarjan 2015 论文 "Rank-Balanced Trees"
- **平衡机制**: 基于 rank 差而非高度差
- **性能特点**: 结合 AVL 的紧凑高度与红黑树的 O(1) 摊还旋转

### 性能定位

| 操作 | 时间复杂度 | 实测性能 (10000元素) |
|------|-----------|---------------------|
| add | O(log n) | 344ms |
| contains | O(log n) | 145ms |
| remove | O(log n) | 231ms |
| buildFromArray | O(n log n) | 57ms |

---

## 理论基础

### WAVL 不变量

1. **rank差定义**: 父节点 rank - 子节点 rank
2. **有效 rank差**: 必须为 1 或 2
3. **外部节点**: null 节点的 rank 定义为 -1
4. **叶子节点**: rank 必须为 0（即 (1,1)-叶子）
5. **禁止条件**: 非叶子的内部节点不能是 (2,2)-节点

### 与其他平衡树对比

| 特性 | AVL | 红黑树 | WAVL |
|------|-----|--------|------|
| 平衡条件 | 高度差≤1 | 黑高度相等 | rank差∈{1,2} |
| 最坏旋转(插入) | O(log n) | O(1) 摊还 | **O(1) 摊还** |
| 最坏旋转(删除) | O(log n) | O(1) 摊还 | **O(1) 摊还** |
| 树高度 | ~1.44 log n | ~2 log n | **~1.44 log n** |
| 实现复杂度 | 低 | 高 | 中 |

### 平衡操作

#### 插入后平衡

插入新节点（rank=0）后，可能产生 0-child（rank差=0）：

```
Case (0, 1) 或 (1, 0):
  → Promote: node.rank++
  → 可能向上传播

Case (0, 2):
  子情况 a: 左子是 (1, 2) → 单右旋
  子情况 b: 左子是 (2, 1) → 双旋转 (LR)

Case (2, 0):
  → 对称处理
```

#### 删除后平衡

删除节点后，可能产生 3-child（rank差=3）：

```
Case (3, 1):
  子情况 a: 兄弟的近侧孙是 1-child → 双旋转
  子情况 b: 兄弟的远侧孙是 1-child → 单旋转
  子情况 c: 兄弟是 (2, 2)         → 双 demote

Case (3, 2):
  → 简单 demote: node.rank--
  → 可能向上传播
```

---

## 性能测试

### 启动代码

```actionscript
import org.flashNight.naki.DataStructures.*;

var wavlTest:WAVLTreeTest = new WAVLTreeTest();
wavlTest.runTests();
```

### 最新测试结果

```
========================================
开始 WAVLTree 测试...
========================================

测试 add 方法...
PASS: 添加元素后，size 应为4
PASS: WAVLTree 应包含 10
PASS: WAVLTree 应包含 20
PASS: WAVLTree 应包含 5
PASS: WAVLTree 应包含 15
PASS: 添加后的树应保持WAVL属性

测试 remove 方法...
PASS: 成功移除存在的元素 20
PASS: WAVLTree 不应包含 20
PASS: 移除不存在的元素 25 应返回 false
PASS: 移除后的树应保持WAVL属性

测试 contains 方法...
PASS: WAVLTree 应包含 10
PASS: WAVLTree 不应包含 20
PASS: WAVLTree 应包含 5
PASS: WAVLTree 应包含 15
PASS: WAVLTree 不应包含 25

测试 size 方法...
PASS: 当前 size 应为3
PASS: 添加 25 后，size 应为4
PASS: 移除 5 后，size 应为3
PASS: 添加删除后的树应保持WAVL属性

测试 toArray 方法...
PASS: toArray 返回的数组长度应为3
PASS: 数组元素应为 10，实际为 10
PASS: 数组元素应为 15，实际为 15
PASS: 数组元素应为 25，实际为 25

测试边界情况...
PASS: 初始树应保持WAVL属性
PASS: 成功移除叶子节点 10
PASS: WAVLTree 不应包含 10
PASS: 删除叶子节点后应保持WAVL属性
PASS: 成功移除有一个子节点的节点 20
PASS: WAVLTree 不应包含 20
PASS: WAVLTree 应包含 25
PASS: 删除有一个子节点的节点后应保持WAVL属性
PASS: 成功移除有两个子节点的节点 30
PASS: WAVLTree 不应包含 30
PASS: WAVLTree 应包含 25
PASS: WAVLTree 应包含 35
PASS: 删除有两个子节点的节点后应保持WAVL属性
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
PASS: buildFromArray 后，WAVLTree 应包含 15
PASS: WAVLTree 不应包含 999
PASS: buildFromArray 后，WAVLTree 应保持WAVL属性
PASS: buildFromArray 后，WAVLTree 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法...
PASS: 初始插入后，size 应为 8
PASS: 插入元素后，WAVLTree 应保持WAVL属性
PASS: changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: changeCompareFunctionAndResort 后，WAVLTree 应保持WAVL属性
PASS: changeCompareFunctionAndResort 后，WAVLTree 的 toArray 应按降序排列

测试WAVL树特有属性...
PASS: 添加元素 50 后，树应保持WAVL属性
PASS: 添加元素 30 后，树应保持WAVL属性
PASS: 添加元素 70 后，树应保持WAVL属性
PASS: 添加元素 20 后，树应保持WAVL属性
PASS: 添加元素 40 后，树应保持WAVL属性
PASS: 添加元素 60 后，树应保持WAVL属性
PASS: 添加元素 80 后，树应保持WAVL属性
PASS: 添加元素 15 后，树应保持WAVL属性
PASS: 添加元素 25 后，树应保持WAVL属性
PASS: 添加元素 35 后，树应保持WAVL属性
PASS: 添加元素 45 后，树应保持WAVL属性
PASS: 添加元素 55 后，树应保持WAVL属性
PASS: 添加元素 65 后，树应保持WAVL属性
PASS: 添加元素 75 后，树应保持WAVL属性
PASS: 添加元素 85 后，树应保持WAVL属性
PASS: 删除元素 30 后，树应保持WAVL属性
PASS: 删除元素 60 后，树应保持WAVL属性
PASS: 删除元素 25 后，树应保持WAVL属性
PASS: 删除元素 75 后，树应保持WAVL属性
PASS: 添加元素 22 后，树应保持WAVL属性
PASS: 添加元素 33 后，树应保持WAVL属性
PASS: 添加元素 66 后，树应保持WAVL属性
PASS: 添加元素 77 后，树应保持WAVL属性

测试 lowerBound 方法...
PASS: lowerBound(30) 应返回 30
PASS: lowerBound(25) 应返回 30（第一个 >= 25）
PASS: lowerBound(10) 应返回 10
PASS: lowerBound(5) 应返回 10（第一个 >= 5）
PASS: lowerBound(50) 应返回 50
PASS: lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: lowerBound(35) 应返回 40（第一个 >= 35）
PASS: lowerBound 测试后，树应保持 WAVL 属性

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
PASS: upperBound 测试后，树应保持 WAVL 属性

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
PASS: 边界测试后，树应保持 WAVL 属性

测试性能表现...

容量: 100，执行次数: 100
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 WAVLTree 中
添加 100 个元素平均耗时: 1.44 毫秒
搜索 100 个元素平均耗时: 0.59 毫秒
移除 100 个元素平均耗时: 0.99 毫秒
buildFromArray(100 个元素)平均耗时: 0.46 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.6 毫秒

容量: 1000，执行次数: 10
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 WAVLTree 中
添加 1000 个元素平均耗时: 20.4 毫秒
搜索 1000 个元素平均耗时: 8.6 毫秒
移除 1000 个元素平均耗时: 12.8 毫秒
buildFromArray(1000 个元素)平均耗时: 4.5 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 5.7 毫秒

容量: 10000，执行次数: 1
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 WAVLTree 中
添加 10000 个元素平均耗时: 272 毫秒
搜索 10000 个元素平均耗时: 120 毫秒
移除 10000 个元素平均耗时: 189 毫秒
buildFromArray(10000 个元素)平均耗时: 46 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 63 毫秒

========================================
测试完成。通过: 145 个，失败: 0 个。
========================================






```

### 性能分析

| 操作 | AVL (ms) | 红黑树 (ms) | WAVL (ms) | WAVL vs AVL |
|------|----------|-------------|-----------|-------------|
| Add | 455 | 1145 | **344** | 快 24% |
| Search | 158 | 152 | **145** | 快 8% |
| Delete | **219** | 2626 | 231 | 慢 5% |
| **Total** | 832 | 3923 | **720** | **快 13%** |

**结论**: WAVL 树在综合性能上优于 AVL 和红黑树，特别是在插入操作上有显著优势。

---

## 优化历程

### 性能演进表

| 版本 | Add (ms) | Search (ms) | Delete (ms) | Total (ms) | 说明 |
|------|----------|-------------|-------------|------------|------|
| 初始版本 | ~429 | ~149 | ~435 | ~1013 | 基础实现 |
| + 差分早退出 | ~429 | ~149 | ~302 | ~880 | __needRebalance 信号 |
| + 延迟孙节点访问 | ~429 | ~149 | ~258 | ~836 | 按需读取 |
| + cmpFn缓存 | ~353 | ~149 | ~251 | ~753 | 参数传递优化 |
| + 非对称早退出 | ~343 | ~145 | ~243 | ~731 | 只检查修改侧 |
| + 手动内联+DeleteMin | **344** | **145** | **231** | **720** | 终极优化 |

### 优化技术详解

#### 1. 差分早退出 (`__needRebalance`)

**问题**: WAVL 删除后 demote 可能向上传播多层。

**解决方案**: 使用布尔信号标记子树是否需要父节点检查平衡。

```actionscript
// 子树稳定，直接返回
if (!this.__needRebalance) return node;
```

**收益**: Delete 从 435ms 降至 302ms (提升 30%)

#### 2. cmpFn 参数传递

**问题**: AS2 中 `this.compareFunction` 查找涉及作用域链，代价高。

**解决方案**: 将比较函数作为参数传递给递归函数。

```actionscript
// 慢
var cmp:Number = this.compareFunction(element, node.value);

// 快
private function insert(node:WAVLNode, element:Object, cmpFn:Function):WAVLNode {
    var cmp:Number = cmpFn(element, node.value);
}
```

**收益**: Add 从 429ms 降至 353ms (提升 18%)

#### 3. 非对称早退出

**问题**: 传统实现在回溯时检查两侧的 rank差。

**解决方案**: 只检查刚修改那一侧，另一侧按需读取。

```actionscript
// 插入后只检查插入侧
node.left = insert(node.left, element, cmpFn);
var leftDiff:Number = nodeRank - leftNode.rank;
if (leftDiff != 0) return node;  // 快速路径：~70% 的情况
// 只有出问题才读取右侧...
```

**收益**: Add 从 353ms 降至 343ms, Delete 从 251ms 降至 243ms

#### 4. 手动内联

**问题**: AS2 函数调用开销极高（作用域链创建、参数压栈）。

**解决方案**: 将辅助函数（如 `rebalanceAfterLeftDelete`）的逻辑直接写入主函数。

**权衡**: 代码可读性换取性能。在 AS2 这种老旧虚拟机上是值得的。

**收益**: Delete 从 243ms 降至 231ms (提升 5%)

#### 5. DeleteMin 优化

**问题**: 双子节点删除时需要找后继并删除，传统实现会重新搜索。

```actionscript
// 慢 - 搜索两遍
var succ = findMin(node.right);
node.value = succ.value;
node.right = deleteNode(node.right, succ.value, cmpFn);  // 又搜索一遍！
```

**解决方案**: 实现专用的 `deleteMin`，无需比较直接下潜。

```actionscript
// 快 - 只搜索一遍
var succ = findMin(node.right);
node.value = succ.value;
node.right = deleteMin(node.right);  // 直接删除最左节点
```

**收益**: 双子节点删除性能提升约 50%（约占 33% 的删除操作）

---

## Bug 修复记录

### 2024-11: (2,2) 非叶子节点违规修复

#### 问题描述

在删除操作后，某些情况下会产生违规的 (2,2) 非叶子节点，违反 WAVL 不变量 4。

**症状**: 测试失败时输出：
```
WAVL违规[不变量4]: 非叶子节点 15 是违规的(2,2)-节点
```

#### 根本原因

两处代码缺陷：

**缺陷 1: 早退出逻辑未检测 (2,2)**

原始代码在 diff ≤ 2 时直接返回，没有检查是否形成了违规的 (2,2) 非叶子节点：

```actionscript
// 错误代码
if (leftDiff <= 2) {
    this.__needRebalance = false;
    return node;  // 可能返回一个 (2,2) 非叶子节点！
}
```

**缺陷 2: 单旋转后 rank 错误调整**

在 (3,1) 单左旋和 (1,3) 单右旋中，新根节点的 rank 被错误地 +1：

```actionscript
// 错误代码 - 单左旋 (3,1) 场景
rightNode.rank = rightRank + 1;  // ← 错误！导致新根成为 (2,2) 节点

// 错误代码 - 单右旋 (1,3) 场景
leftNode.rank = leftRank + 1;    // ← 错误！同样问题
```

#### 修复方案

**修复 1: 添加 (2,2) 检测和 demote**

```actionscript
if (leftDiff <= 2) {
    // [修复] 检查是否产生了违规的 (2,2) 非叶子节点
    if (leftDiff == 2 && rightDiff == 2) {
        node.rank = nodeRank - 1;  // demote
        return node;  // __needRebalance 保持 true，可能向上传播
    }
    this.__needRebalance = false;
    return node;
}
```

**修复 2: 单旋转不增加新根 rank**

```actionscript
// 正确代码 - 单左旋
// rightNode.rank 保持不变（删除场景的单旋不需要 +1）
node.rank = nodeRank - 2;

// 正确代码 - 单右旋
// leftNode.rank 保持不变（删除场景的单旋不需要 +1）
node.rank = nodeRank - 2;
```

#### 修复位置

| 位置 | 函数 | 场景 | 修复内容 |
|------|------|------|----------|
| ~820行 | deleteNode | 左侧删除后 diff≤2 | 添加 (2,2) 检测 |
| ~903行 | deleteNode | (3,1) 单左旋 | 移除 `rightNode.rank + 1` |
| ~957行 | deleteNode | 右侧删除后 diff≤2 | 添加 (2,2) 检测 |
| ~997行 | deleteNode | (1,3) 单右旋 | 移除 `leftNode.rank + 1` |
| ~1090行 | deleteNode | deleteMin后 diff≤2 | 添加 (2,2) 检测 |
| ~1124行 | deleteNode | deleteMin后 (1,3) 单右旋 | 移除 `leftNode.rank + 1` |
| ~1203行 | deleteMin | 左侧删除后 diff≤2 | 添加 (2,2) 检测 |
| ~1239行 | deleteMin | (3,1) 单左旋 | 移除 `rightNode.rank + 1` |

#### 理论解释

**为什么删除时单旋转不需要 +1？**

在删除的 (3,1) 单左旋场景中：
```
       node[r]                    rightNode[r-1]
       /    \          →         /          \
      L    rightNode[r-1]     node[r-2]      RR
            /      \            /   \
           RL      RR          L    RL
```

旋转后：
- `node` 从 rank=r 降为 rank=r-2（双重 demote）
- `rightNode` 保持 rank=r-1（不变）

此时 `rightNode` 的 rank差：
- 左子 `node`: (r-1) - (r-2) = 1 ✓
- 右子 `RR`: 原本就是 1 或 2 ✓

如果错误地将 `rightNode.rank` 设为 `r`：
- 左子 diff = r - (r-2) = 2
- 右子 diff = r - rrRank = 2（当 rrRank = r-2 时）
- 形成 (2,2) 非叶子节点 ✗

#### 验证结果

修复后所有 99 个测试通过，性能无明显变化：

```
测试完成。通过: 99 个，失败: 0 个。

--- WAVL树 ---
添加: 361 ms
搜索: 148 ms
删除: 240 ms
```

---

## API 参考

### 构造函数

```actionscript
public function WAVLTree(compareFunction:Function)
```

创建 WAVL 树实例。

**参数**:
- `compareFunction`: 比较函数，可选。签名: `function(a, b):Number`，返回负数/0/正数。

**示例**:
```actionscript
// 默认升序
var tree:WAVLTree = new WAVLTree();

// 降序
var tree:WAVLTree = new WAVLTree(function(a, b):Number {
    return b - a;
});
```

### 静态方法

#### buildFromArray

```actionscript
public static function buildFromArray(arr:Array, compareFunction:Function):WAVLTree
```

从数组批量构建树（比逐个 add 快约 6 倍）。

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

导出为有序数组。

#### changeCompareFunctionAndResort

```actionscript
public function changeCompareFunctionAndResort(newCompareFunction:Function):Void
```

更换比较函数并重新排序。

---

## 使用示例

### 基础用法

```actionscript
import org.flashNight.naki.DataStructures.*;

// 创建树
var tree:WAVLTree = new WAVLTree();

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
var tree:WAVLTree = new WAVLTree(function(a, b):Number {
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
var tree:WAVLTree = WAVLTree.buildFromArray(data, null);

trace(tree.toArray());  // 1,2,3,4,5,6,7,8,9
```

### 动态切换排序

```actionscript
var tree:WAVLTree = new WAVLTree();
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
| `WAVLNode.as` | WAVL 树节点类 |
| `WAVLTree.as` | WAVL 树主类（包含详尽注释） |
| `WAVLTreeTest.as` | 测试类（包含三种树对比） |
| `WAVLTree.md` | 本文档 |

---

## 总结

WAVLTree 在 AS2 环境下实现了高性能的自平衡二叉搜索树：

- **综合性能最优**: 总耗时 720ms，比 AVL 快 13%，比红黑树快 81%
- **插入性能卓越**: 比 AVL 快 24%
- **删除性能接近 AVL**: 仅慢 5%（经过大量优化）
- **代码文档完善**: 详尽的中文注释记录了所有优化思路

这些优化经验（cmpFn 缓存、非对称早退出、手动内联、deleteMin 策略）对于在 AS2 等老旧虚拟机上进行性能优化具有参考价值。
