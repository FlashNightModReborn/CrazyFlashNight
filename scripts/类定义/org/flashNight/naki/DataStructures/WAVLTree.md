# WAVLTree 测试文档

## 启动代码

```actionscript
import org.flashNight.naki.DataStructures.*;

var wavlTest:WAVLTreeTest = new WAVLTreeTest();
wavlTest.runTests();
```

## 测试日志

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

测试性能表现...

容量: 100，执行次数: 100
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 WAVLTree 中
添加 100 个元素平均耗时: 2.98 毫秒
搜索 100 个元素平均耗时: 0.53 毫秒
移除 100 个元素平均耗时: 1.89 毫秒
buildFromArray(100 个元素)平均耗时: 0.58 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.71 毫秒

容量: 1000，执行次数: 10
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 WAVLTree 中
添加 1000 个元素平均耗时: 41.1 毫秒
搜索 1000 个元素平均耗时: 8.1 毫秒
移除 1000 个元素平均耗时: 26.4 毫秒
buildFromArray(1000 个元素)平均耗时: 5.4 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 6.8 毫秒

容量: 10000，执行次数: 1
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 WAVLTree 中
添加 10000 个元素平均耗时: 564 毫秒
搜索 10000 个元素平均耗时: 122 毫秒
移除 10000 个元素平均耗时: 378 毫秒
buildFromArray(10000 个元素)平均耗时: 59 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 73 毫秒

========================================
三种树性能对比测试 (10000元素)
========================================

--- AVL树 (TreeSet) ---
添加: 371 ms
搜索: 125 ms
删除: 174 ms

--- 红黑树 (RedBlackTree) ---
添加: 902 ms
搜索: 124 ms
删除: 2050 ms

--- WAVL树 ---
添加: 549 ms
搜索: 117 ms
删除: 351 ms

========================================
性能对比汇总 (10000 元素)
========================================
操作		AVL	RB	WAVL
添加		371	902	549
搜索		125	124	117
删除		174	2050	351
总计		670	3076	1017

========================================
测试完成。通过: 99 个，失败: 0 个。
========================================


```

---

## WAVL树简介

WAVL (Weak AVL) 树是由 Haeupler, Sen, Tarjan 于 2015 年提出的自平衡二叉搜索树，是 AVL 树的推广。

### 核心特性

| 特性 | AVL | 红黑树 | WAVL |
|------|-----|--------|------|
| 平衡条件 | 高度差≤1 | 黑高度相等 | rank差∈{1,2} |
| 最坏旋转(插入) | O(log n) | O(1) 摊还 | **O(1) 摊还** |
| 最坏旋转(删除) | O(log n) | O(1) 摊还 | **O(1) 摊还** |
| 树高度 | ~1.44 log n | ~2 log n | **~1.44 log n** |
| 实现复杂度 | 低 | 高 | 中 |

### WAVL规则

1. **rank差定义**：父节点rank - 子节点rank
2. **有效rank差**：1 或 2
3. **外部节点**：null节点的rank定义为-1
4. **叶子节点**：rank必须为0

### 平衡操作

**插入后**：
- 若出现0-child（rank差=0），需要promote或旋转
- promote：节点rank++

**删除后**：
- 若出现3-child（rank差=3），需要demote或旋转
- demote：节点rank--

### 预期性能对比

基于AS2环境的特性分析：

| 操作 | AVL预期 | 红黑树预期 | WAVL预期 |
|------|---------|-----------|---------|
| Add 10000 | ~357ms | ~921ms | ~350ms |
| Search 10000 | ~127ms | ~128ms | ~127ms |
| Remove 10000 | ~174ms | ~2090ms | ~150ms |

WAVL的优势：
1. 无颜色机制，避免红黑树的常数开销
2. demote操作可替代部分旋转，删除更高效
3. 保持AVL的紧凑高度，搜索性能相同

---

## 文件清单

- `WAVLNode.as` - WAVL树节点类
- `WAVLTree.as` - WAVL树主类
- `WAVLTreeTest.as` - 测试类（包含与AVL/红黑树的对比）
- `WAVLTree.md` - 本文档

---

## 测试结果记录区

### 测试日期：____

### 功能测试结果：
```
// 粘贴功能测试日志
```

### 性能对比结果：
```
// 粘贴性能对比日志
```

### 结论：
- [ ] WAVL树功能正确性验证通过
- [ ] WAVL树性能优于AVL树
- [ ] WAVL树性能优于红黑树
