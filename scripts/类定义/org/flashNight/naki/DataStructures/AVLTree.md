# AVLTree 技术文档

## 目录

1. [概述](#概述)
2. [理论基础](#理论基础)
3. [性能测试](#性能测试)
4. [优化技术](#优化技术)
5. [API 参考](#api-参考)
6. [使用示例](#使用示例)
7. [文件清单](#文件清单)
8. [开发日志](#开发日志)

---

## 概述

AVLTree 是经典的 AVL 树算法实现，提供高效的插入、删除、搜索和遍历操作。

### 核心特性

- **算法来源**: Adelson-Velsky 和 Landis (1962) - 最早的自平衡二叉搜索树
- **平衡机制**: 基于 height 高度差
- **性能特点**: 严格平衡，树高约 1.44 log(n)，查询性能稳定

### 性能定位

| 操作 | 时间复杂度 | 实测性能 (10000元素) |
|------|-----------|---------------------|
| add | O(log n) | TODO |
| contains | O(log n) | TODO |
| remove | O(log n) | TODO |
| buildFromArray | O(n log n) | TODO |

---

## 理论基础

### AVL 不变量

1. **平衡因子定义**: 左子树高度 - 右子树高度
2. **有效平衡因子**: 必须为 -1, 0, 或 1
3. **空节点**: 高度定义为 0
4. **叶子节点**: 高度为 1

### 与其他平衡树对比

| 特性 | AVL | 红黑树 | WAVL | Zip |
|------|-----|--------|------|-----|
| 平衡条件 | 高度差≤1 | 黑高度相等 | rank差∈{1,2} | 随机rank堆序 |
| 最坏旋转(插入) | O(log n) | O(1) 摊还 | O(1) 摊还 | O(1) 期望 |
| 最坏旋转(删除) | O(log n) | O(1) 摊还 | O(1) 摊还 | O(1) 期望 |
| 树高度 | **~1.44 log n** | ~2 log n | ~1.44 log n | ~2 log n 期望 |
| 实现复杂度 | **低** | 高 | 中 | 中 |

### 旋转操作

#### LL 型 (右旋)

```
      node                leftNode
      /  \                /      \
   leftNode  R    →      LL      node
    /   \                        /  \
   LL   LR                      LR   R
```

#### RR 型 (左旋)

```
   node                    rightNode
   /  \                    /      \
  L   rightNode    →     node      RR
       /   \             /  \
      RL   RR           L   RL
```

#### LR 型 (先左旋后右旋)

```
      node                  node                  LR
      /  \                  /  \                 /  \
   leftNode  R    →       LR    R    →     leftNode  node
    /   \                 /                  /        \
   LL   LR           leftNode              LL          R
                      /
                     LL
```

#### RL 型 (先右旋后左旋)

```
   node                 node                    RL
   /  \                 /  \                   /  \
  L   rightNode   →    L    RL    →        node  rightNode
       /   \                  \             /         \
      RL   RR             rightNode        L          RR
                               \
                               RR
```

---

## 性能测试

### 启动代码

```actionscript
import org.flashNight.naki.DataStructures.*;

var avlTest:AVLTreeTest = new AVLTreeTest();
avlTest.runTests();
```

### 测试结果

```
========================================
开始 AVLTree 测试...
========================================

测试 add 方法...
PASS: 添加元素后，size 应为4
PASS: AVLTree 应包含 10
PASS: AVLTree 应包含 20
PASS: AVLTree 应包含 5
PASS: AVLTree 应包含 15
PASS: 添加后的树应保持AVL属性

测试 remove 方法...
PASS: 成功移除存在的元素 20
PASS: AVLTree 不应包含 20
PASS: 移除不存在的元素 25 应返回 false
PASS: 移除后的树应保持AVL属性

测试 contains 方法...
PASS: AVLTree 应包含 10
PASS: AVLTree 不应包含 20
PASS: AVLTree 应包含 5
PASS: AVLTree 应包含 15
PASS: AVLTree 不应包含 25

测试 size 方法...
PASS: 当前 size 应为3
PASS: 添加 25 后，size 应为4
PASS: 移除 5 后，size 应为3
PASS: 添加删除后的树应保持AVL属性

测试 toArray 方法...
PASS: toArray 返回的数组长度应为3
PASS: 数组元素应为 10，实际为 10
PASS: 数组元素应为 15，实际为 15
PASS: 数组元素应为 25，实际为 25

测试边界情况...
PASS: 初始树应保持AVL属性
PASS: 成功移除叶子节点 10
PASS: AVLTree 不应包含 10
PASS: 删除叶子节点后应保持AVL属性
PASS: 成功移除有一个子节点的节点 20
PASS: AVLTree 不应包含 20
PASS: AVLTree 应包含 25
PASS: 删除有一个子节点的节点后应保持AVL属性
PASS: 成功移除有两个子节点的节点 30
PASS: AVLTree 不应包含 30
PASS: AVLTree 应包含 25
PASS: AVLTree 应包含 35
PASS: 删除有两个子节点的节点后应保持AVL属性
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
PASS: buildFromArray 后，AVLTree 应包含 15
PASS: AVLTree 不应包含 999
PASS: buildFromArray 后，AVLTree 应保持AVL属性
PASS: buildFromArray 后，AVLTree 的 toArray 应按升序排列

测试 changeCompareFunctionAndResort 方法...
PASS: 初始插入后，size 应为 8
PASS: 插入元素后，AVLTree 应保持AVL属性
PASS: changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: changeCompareFunctionAndResort 后，AVLTree 应保持AVL属性
PASS: changeCompareFunctionAndResort 后，AVLTree 的 toArray 应按降序排列

测试AVL树特有属性...
PASS: 添加元素 50 后，树应保持AVL属性
PASS: 添加元素 30 后，树应保持AVL属性
PASS: 添加元素 70 后，树应保持AVL属性
PASS: 添加元素 20 后，树应保持AVL属性
PASS: 添加元素 40 后，树应保持AVL属性
PASS: 添加元素 60 后，树应保持AVL属性
PASS: 添加元素 80 后，树应保持AVL属性
PASS: 添加元素 15 后，树应保持AVL属性
PASS: 添加元素 25 后，树应保持AVL属性
PASS: 添加元素 35 后，树应保持AVL属性
PASS: 添加元素 45 后，树应保持AVL属性
PASS: 添加元素 55 后，树应保持AVL属性
PASS: 添加元素 65 后，树应保持AVL属性
PASS: 添加元素 75 后，树应保持AVL属性
PASS: 添加元素 85 后，树应保持AVL属性
PASS: 删除元素 30 后，树应保持AVL属性
PASS: 删除元素 60 后，树应保持AVL属性
PASS: 删除元素 25 后，树应保持AVL属性
PASS: 删除元素 75 后，树应保持AVL属性
PASS: 添加元素 22 后，树应保持AVL属性
PASS: 添加元素 33 后，树应保持AVL属性
PASS: 添加元素 66 后，树应保持AVL属性
PASS: 添加元素 77 后，树应保持AVL属性

测试性能表现...

容量: 100，执行次数: 100
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 AVLTree 中
添加 100 个元素平均耗时: 2.01 毫秒
搜索 100 个元素平均耗时: 0.57 毫秒
移除 100 个元素平均耗时: 1.41 毫秒
buildFromArray(100 个元素)平均耗时: 0.36 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.62 毫秒

容量: 1000，执行次数: 10
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 AVLTree 中
添加 1000 个元素平均耗时: 27.2 毫秒
搜索 1000 个元素平均耗时: 8.2 毫秒
移除 1000 个元素平均耗时: 19.6 毫秒
buildFromArray(1000 个元素)平均耗时: 4.3 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 5.5 毫秒

容量: 10000，执行次数: 1
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 AVLTree 中
添加 10000 个元素平均耗时: 350 毫秒
搜索 10000 个元素平均耗时: 113 毫秒
移除 10000 个元素平均耗时: 259 毫秒
buildFromArray(10000 个元素)平均耗时: 44 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 60 毫秒

========================================
测试完成。通过: 99 个，失败: 0 个。
========================================


```

---

## 优化技术

### 1. 比较函数缓存 (cmpFn 参数传递)

**问题**: AS2 中 `this.compareFunction` 查找涉及作用域链，代价高。

**解决方案**: 将比较函数作为参数传递给递归函数。

```actionscript
// 慢
var cmp:Number = this.compareFunction(element, node.value);

// 快
private function insert(node:AVLNode, element:Object, cmpFn:Function):AVLNode {
    var cmp:Number = cmpFn(element, node.value);
}
```

### 2. 差分高度更新 (早退出)

**问题**: 传统实现在每层回溯时都检查平衡。

**解决方案**: 记录旧高度，若更新后高度未变则提前退出。

```actionscript
var oldHeight:Number = node.height;
// ... 更新高度计算 ...
if (++newHeight == oldHeight) {
    return node;  // 高度没变，不必继续检查平衡
}
```

> **重要说明：此优化仅适用于插入操作！**
>
> 在删除操作中，即使高度没有变化，平衡因子也可能发生改变，因此**不能**应用早退出优化。
>
> **反例**：假设左子树从 h=1 变为 null(h=0)，右子树保持 h=2
> - 高度计算: `max(1,2)+1=3` → `max(0,2)+1=3` **不变**
> - 但平衡因子: `1-2=-1` → `0-2=-2` **需要旋转！**
>
> 当前 AVLTree 实现已正确处理：`insert()` 使用早退出，`deleteNode()` 不使用。
> 未来维护者请勿将此优化应用到删除路径。

### 3. DeleteMin 优化

**问题**: 双子节点删除时需要找后继并删除，传统实现会重新搜索比较。

**解决方案**: 实现专用的 `deleteMin`，无需比较直接下潜。

```actionscript
// 慢 - 搜索两遍
var succ = findMin(node.right);
node.value = succ.value;
node.right = deleteNode(node.right, succ.value, cmpFn);  // 又比较搜索！

// 快 - 只搜索一遍
var succ:AVLNode = node.right;
while (succ.left != null) succ = succ.left;
node.value = succ.value;
node.right = deleteMin(node.right);  // 直接删除最左节点
```

### 4. 迭代式遍历

**问题**: 递归遍历有函数调用开销。

**解决方案**: 使用显式栈进行迭代式中序遍历。

```actionscript
public function toArray():Array {
    var arr:Array = new Array(this.treeSize);  // 预分配
    var arrIdx:Number = 0;
    var stack:Array = [];
    var stackIdx:Number = 0;
    var node:AVLNode = this.root;

    while (node != null || stackIdx > 0) {
        while (node != null) {
            stack[stackIdx++] = node;
            node = node.left;
        }
        node = stack[--stackIdx];
        arr[arrIdx++] = node.value;
        node = node.right;
    }
    return arr;
}
```

---

## API 参考

### 构造函数

```actionscript
public function AVLTree(compareFunction:Function)
```

创建 AVL 树实例。

**参数**:
- `compareFunction`: 比较函数，可选。签名: `function(a, b):Number`，返回负数/0/正数。

**示例**:
```actionscript
// 默认升序
var tree:AVLTree = new AVLTree();

// 降序
var tree:AVLTree = new AVLTree(function(a, b):Number {
    return b - a;
});
```

### 静态方法

#### buildFromArray

```actionscript
public static function buildFromArray(arr:Array, compareFunction:Function):AVLTree
```

从数组批量构建树（比逐个 add 快约 6-10 倍）。

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

#### getRoot

```actionscript
public function getRoot():AVLNode
```

获取根节点（用于调试和测试）。

#### getCompareFunction

```actionscript
public function getCompareFunction():Function
```

获取当前比较函数。

#### toString

```actionscript
public function toString():String
```

获取树的字符串表示（前序遍历）。

---

## 使用示例

### 基础用法

```actionscript
import org.flashNight.naki.DataStructures.*;

// 创建树
var tree:AVLTree = new AVLTree();

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
var tree:AVLTree = new AVLTree(function(a, b):Number {
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
var tree:AVLTree = AVLTree.buildFromArray(data, null);

trace(tree.toArray());  // 1,2,3,4,5,6,7,8,9
```

### 动态切换排序

```actionscript
var tree:AVLTree = new AVLTree();
tree.add(3);
tree.add(1);
tree.add(4);
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
| `AVLNode.as` | AVL 树节点类 |
| `AVLTree.as` | AVL 树主类 |
| `AVLTreeTest.as` | 测试类（包含四种树对比） |
| `AVLTree.md` | 本文档 |

---

## 开发日志

### 2024-12-05: 创建 AVLTree

**完成工作**:

1. **创建 AVLNode.as**
   - 节点结构: `value`, `left`, `right`, `height`
   - toString 显示高度: `value[h=height]`

2. **创建 AVLTree.as**
   - 完整的 AVL 树实现
   - 包含所有优化（cmpFn 缓存、差分高度、deleteMin）

3. **创建 AVLTreeTest.as**
   - 包含四种树的性能对比（AVL, WAVL, RB, Zip）
   - AVL 属性验证（平衡因子、高度计算）

**下一步计划**:
- [ ] 运行测试验证正确性
- [ ] 填入实际性能数据
- [ ] 设计统一接口/基类
- [ ] 创建 BalancedTreeFactory 工厂类
