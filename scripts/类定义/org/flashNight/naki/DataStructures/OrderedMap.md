# OrderedMap 深度解析与使用指南

---

## 目录
1. **概述与核心特性**  
2. **核心结构与实现原理**  
3. **基础操作详解**  
4. **批量操作与数据转换**  
5. **遍历与迭代器**  
6. **动态排序与比较函数**  
7. **边界场景与异常处理**  
8. **性能分析与优化建议**  
9. **代码示例**  
10. **应用场景与最佳实践**  

---

## 1. 概述与核心特性

**OrderedMap** 是一种基于 AVL 树实现的有序键值映射结构，提供以下核心能力：

- **严格有序性**：键按自定义比较规则排序，默认支持字典序。
- **高效操作**：插入、删除、查找时间复杂度稳定在 **O(log n)**。
- **动态重排**：支持运行时更换比较函数，自动重建有序结构。
- **批量处理**：支持数组、对象等多种格式的批量导入导出。
- **强一致性**：迭代期间检测并发修改，避免数据不一致。

---

## 2. 核心结构与实现原理

### 2.1 内部组件
- **TreeSet (keySet)**：存储有序键集合，依赖 AVL 树维护排序。
- **Object (valueMap)**：哈希结构存储键值对，实现快速存取。
- **版本号 (version)**：用于迭代器并发修改检测。

### 2.2 数据排序流程
1. **插入键**：通过 `keySet.add(key)` 插入并平衡 AVL 树。
2. **存储值**：在 `valueMap` 中关联键与值。
3. **删除键**：从 `keySet` 移除并同步删除 `valueMap` 中的值。

---

## 3. 基础操作详解

### 3.1 插入/更新键值对
```actionscript
public function put(key:String, value:Object):Void
```
- **功能**：插入新键或更新现有键的值。
- **特性**：仅当添加新键时触发树结构调整。

### 3.2 获取值
```actionscript
public function get(key:String):Object
```
- **返回值**：存在返回对应值，否则返回 `null`。

### 3.3 删除键值对
```actionscript
public function remove(key:String):Boolean
```
- **返回值**：成功删除返回 `true`，键不存在返回 `false`。

### 3.4 映射大小
```actionscript
public function size():Number
```
- **返回值**：当前键值对数量。

---

## 4. 批量操作与数据转换

### 4.1 批量插入
```actionscript
public function putAll(input:Object):Void
```
- **支持格式**：  
  - **数组**：`[{key:"k1", value:"v1"}, ...]`  
  - **对象**：`{k1: "v1", k2: "v2"}`  
- **流程**：合并新旧键，排序后重建 AVL 树。

### 4.2 清空映射
```actionscript
public function clear():Void
```

### 4.3 数据导出
```actionscript
public function toObject():Object
```
- **返回值**：标准对象，键按当前顺序排列。

### 4.4 数据导入
```actionscript
public function loadFromObject(obj:Object):Void
```

---

## 5. 遍历与迭代器

### 5.1 遍历方法
| 方法名       | 返回值                      | 描述                     |
|--------------|-----------------------------|--------------------------|
| `keys()`     | `Array` (有序键数组)        | 返回所有键的有序列表     |
| `values()`   | `Array` (有序值数组)        | 返回按键序排列的值列表   |
| `entries()`  | `Array` (键值对对象数组)    | 返回 `{key, value}` 列表 |

### 5.2 迭代器
```actionscript
public function iterator():IIterator
```
- **特性**：  
  - 支持 `hasNext()`, `next()`, `reset()` 方法。  
  - 检测并发修改，抛出 `ConcurrentModificationError`。

---

## 6. 动态排序与比较函数

### 6.1 更换比较函数
```actionscript
public function changeCompareFunction(newCompare:Function):Void
```
- **流程**：  
  1. 导出所有条目。  
  2. 清空并重建键集合。  
  3. 重新插入数据，按新规则排序。

### 6.2 自定义比较示例
```actionscript
// 按字符串长度排序
map.changeCompareFunction(function(a:String, b:String):Number {
    return a.length - b.length;
});
```

---

## 7. 边界场景与异常处理

### 7.1 空映射行为
- `size()` 返回 `0`，`keys()`/`values()` 返回空数组。
- `firstKey()` 和 `lastKey()` 返回 `null`。

### 7.2 异常类型
- **无效输入**：`putAll` 传入非数组/对象时抛出错误。
- **迭代器并发修改**：检测到结构变化后抛出异常。

---

## 8. 性能分析与优化建议

### 8.1 时间复杂度
| 操作        | 平均复杂度 | 最坏情况   |
|-------------|------------|------------|
| 插入/删除   | O(log n)   | O(log n)   |
| 查找        | O(log n)   | O(log n)   |
| 遍历        | O(n)       | O(n)       |

### 8.2 优化建议
- **批量预排序**：使用 `putAll` 替代多次 `put` 调用。
- **延迟重排**：在非高峰时段执行 `changeCompareFunction`。
- **复用迭代器**：避免频繁创建迭代器对象。

---

## 9. 代码示例

```actionscript
// 创建映射（按字典序）
var map:OrderedMap = new OrderedMap(
    function(a:String, b:String):Number {
        return a.localeCompare(b);
    }
);

// 插入数据
map.put("z", 26);
map.put("a", 1);
map.put("m", 13);

// 遍历输出
map.forEach(function(key:String, value:Number):Void {
    trace(key + " => " + value); // 输出 a =>1, m =>13, z =>26
});

// 动态更换为逆序
map.changeCompareFunction(function(a:String, b:String):Number {
    return b.localeCompare(a);
});
trace(map.keys()); // 输出 ["z","m","a"]
```

---

## 10. 应用场景与最佳实践

### 10.1 典型用例
- **游戏排行榜**：按分数排序，支持动态更新和名次查询。
- **配置管理**：需按固定顺序处理的键值参数。
- **事件调度**：按时间戳排序的待处理事件队列。

### 10.2 最佳实践
- **键设计**：使用不可变类型（如字符串）作为键。
- **比较函数**：确保比较函数与键类型兼容。
- **批量加载**：初始化时优先使用 `putAll` 提升性能。


var a = new org.flashNight.naki.DataStructures.OrderedMapTest()
a. runTests();



开始 OrderedMap 测试...

[基础操作] 测试 put/get/remove...
PASS: Size 应变为 3
PASS: KeySet 大小应为 3
PASS: 更新不应改变 size
PASS: 应返回删除成功
PASS: 删除后 size 应为 2
PASS: KeySet 大小应同步更新

[批量操作] 测试 putAll/loadFromObject...
PASS: 数组输入后 size 应为2
PASS: 应正确解析数组输入
PASS: Object输入后 size 应为4
PASS: 应正确解析Object输入
PASS: toObject 应包含所有键值对

[遍历方法] 测试 keys/values/entries...
PASS: keys 应返回有序键数组
PASS: values 应返回对应值
PASS: entries 应返回完整键值对
PASS: forEach 应遍历所有元素

[比较函数] 测试 changeCompareFunction...
PASS: 初始升序排序
PASS: 更换后降序排序
PASS: 数据完整性检查
PASS: 数据完整性检查
PASS: 平衡性检查

[边界情况] 测试极端场景...
PASS: 空映射 size 应为0
PASS: 空映射 keys 应为空数组
PASS: 删除不存在的键应返回false
PASS: firstKey 应返回最小键
PASS: lastKey 应返回最大键

[迭代器] 测试 OrderedMapMinimalIterator...
PASS: 迭代器应遍历所有元素
PASS: 应检测到并发修改
PASS: 重置后迭代器应重新开始

[性能测试] 评估大规模数据处理...

数据量: 100 元素 | 测试轮次: 100
插入: 14.45ms
查找: 0.08ms
迭代: 5.11ms
转换: 0.15ms

数据量: 1000 元素 | 测试轮次: 10
插入: 245.9ms
查找: 1.4ms
迭代: 75.3ms
转换: 1.7ms

数据量: 5000 元素 | 测试轮次: 2
插入: 1720ms
查找: 6.5ms
迭代: 482ms
转换: 12ms

测试完成。通过: 28 个，失败: 0 个。
