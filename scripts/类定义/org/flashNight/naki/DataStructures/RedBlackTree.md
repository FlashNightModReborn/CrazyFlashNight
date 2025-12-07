import org.flashNight.naki.DataStructures.*;

var rbTreeTest:RedBlackTreeTest = new RedBlackTreeTest();
rbTreeTest.runTests();

开始 RedBlackTree 测试...

测试 add 方法...
PASS: 添加元素后，size 应为4
PASS: RedBlackTree 应包含 10
PASS: RedBlackTree 应包含 20
PASS: RedBlackTree 应包含 5
PASS: RedBlackTree 应包含 15
PASS: 添加后的树应保持红黑树属性

测试 remove 方法...
PASS: 成功移除存在的元素 20
PASS: RedBlackTree 不应包含 20
PASS: 移除不存在的元素 25 应返回 false
PASS: 移除后的树应保持红黑树属性

测试 contains 方法...
PASS: RedBlackTree 应包含 10
PASS: RedBlackTree 不应包含 20
PASS: RedBlackTree 应包含 5
PASS: RedBlackTree 应包含 15
PASS: RedBlackTree 不应包含 25

测试 size 方法...
PASS: 当前 size 应为3
PASS: 添加 25 后，size 应为4
PASS: 移除 5 后，size 应为3
PASS: 添加删除后的树应保持红黑树属性

测试 toArray 方法...
PASS: toArray 返回的数组长度应为3
PASS: 数组元素应为 10，实际为 10
PASS: 数组元素应为 15，实际为 15
PASS: 数组元素应为 25，实际为 25

测试边界情况...
PASS: 初始树应保持红黑树属性
PASS: 成功移除叶子节点 10
PASS: RedBlackTree 不应包含 10
PASS: 删除叶子节点后应保持红黑树属性
PASS: 成功移除有一个子节点的节点 20
PASS: RedBlackTree 不应包含 20
PASS: RedBlackTree 应包含 25
PASS: 删除有一个子节点的节点后应保持红黑树属性
PASS: 成功移除有两个子节点的节点 30
PASS: RedBlackTree 不应包含 30
PASS: RedBlackTree 应包含 25
PASS: RedBlackTree 应包含 35
PASS: 删除有两个子节点的节点后应保持红黑树属性
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
PASS: buildFromArray 后，RedBlackTree 应包含 15
PASS: RedBlackTree 不应包含 999
PASS: buildFromArray 后，RedBlackTree 应保持红黑树属性
PASS: buildFromArray 后，RedBlackTree 的 toArray 应按升序排列

测试 buildFromArray 边界情况...
PASS: 空数组构建后，size 应为 0
PASS: 空数组构建后，根节点应为 null
PASS: 空数组构建后，toArray 应返回空数组
PASS: 单元素数组构建后，size 应为 1
PASS: 单元素数组构建后，应包含 42
PASS: 单元素数组构建后，应保持红黑树属性
PASS: 单元素数组构建后，toArray 应为 [42]
PASS: 两元素数组构建后，size 应为 2
PASS: 两元素数组构建后，应保持红黑树属性
PASS: 两元素数组构建后，toArray 应为 [5, 10]
PASS: 三元素数组构建后，size 应为 3
PASS: 三元素数组构建后，应保持红黑树属性
PASS: 三元素数组构建后，toArray 应为 [10, 20, 30]
PASS: 含重复元素数组构建后，size 应为去重后的 4，而非原数组长度 8
PASS: 含重复元素数组构建后，应保持红黑树属性
PASS: 含重复元素数组构建后，toArray 长度应为 4
PASS: 去重后第 0 个元素应为 3，实际是 3
PASS: 去重后第 1 个元素应为 5，实际是 5
PASS: 去重后第 2 个元素应为 7，实际是 7
PASS: 去重后第 3 个元素应为 9，实际是 9
PASS: 去重后数组应有序
PASS: 全重复元素数组构建后，size 应为 1
PASS: 全重复元素数组构建后，应包含 1
PASS: 全重复元素数组构建后，应保持红黑树属性
PASS: 7 元素数组构建后，size 应为 7
PASS: 7 元素（2^3-1）数组构建后，应保持红黑树属性
PASS: 8 元素数组构建后，size 应为 8
PASS: 8 元素（2^3）数组构建后，应保持红黑树属性
buildFromArray 边界情况测试完成

测试 changeCompareFunctionAndResort 方法...
PASS: 初始插入后，size 应为 8
PASS: 插入元素后，RedBlackTree 应保持红黑树属性
PASS: changeCompareFunctionAndResort 后，size 不变，依旧为 8
PASS: changeCompareFunctionAndResort -> 第 0 个元素应为 25，实际是 25
PASS: changeCompareFunctionAndResort -> 第 1 个元素应为 20，实际是 20
PASS: changeCompareFunctionAndResort -> 第 2 个元素应为 15，实际是 15
PASS: changeCompareFunctionAndResort -> 第 3 个元素应为 10，实际是 10
PASS: changeCompareFunctionAndResort -> 第 4 个元素应为 7，实际是 7
PASS: changeCompareFunctionAndResort -> 第 5 个元素应为 5，实际是 5
PASS: changeCompareFunctionAndResort -> 第 6 个元素应为 3，实际是 3
PASS: changeCompareFunctionAndResort -> 第 7 个元素应为 2，实际是 2
PASS: changeCompareFunctionAndResort 后，RedBlackTree 应保持红黑树属性
PASS: changeCompareFunctionAndResort 后，RedBlackTree 的 toArray 应按降序排列

测试红黑树特有属性...
PASS: 添加元素 50 后，树应保持红黑树属性
PASS: 添加元素 30 后，树应保持红黑树属性
PASS: 添加元素 70 后，树应保持红黑树属性
PASS: 添加元素 20 后，树应保持红黑树属性
PASS: 添加元素 40 后，树应保持红黑树属性
PASS: 添加元素 60 后，树应保持红黑树属性
PASS: 添加元素 80 后，树应保持红黑树属性
PASS: 添加元素 15 后，树应保持红黑树属性
PASS: 添加元素 25 后，树应保持红黑树属性
PASS: 添加元素 35 后，树应保持红黑树属性
PASS: 添加元素 45 后，树应保持红黑树属性
PASS: 添加元素 55 后，树应保持红黑树属性
PASS: 添加元素 65 后，树应保持红黑树属性
PASS: 添加元素 75 后，树应保持红黑树属性
PASS: 添加元素 85 后，树应保持红黑树属性
PASS: 根节点应为黑色
PASS: 红色节点的子节点应为黑色（不存在连续的红色节点）
PASS: 黑色高度应大于0，实际为: 4
PASS: 删除元素 30 后，树应保持红黑树属性
PASS: 删除元素 60 后，树应保持红黑树属性
PASS: 删除元素 25 后，树应保持红黑树属性
PASS: 删除元素 75 后，树应保持红黑树属性
PASS: 添加元素 22 后，树应保持红黑树属性
PASS: 添加元素 33 后，树应保持红黑树属性
PASS: 添加元素 66 后，树应保持红黑树属性
PASS: 添加元素 77 后，树应保持红黑树属性

测试 lowerBound 方法...
PASS: lowerBound(30) 应返回 30
PASS: lowerBound(25) 应返回 30（第一个 >= 25）
PASS: lowerBound(10) 应返回 10
PASS: lowerBound(5) 应返回 10（第一个 >= 5）
PASS: lowerBound(50) 应返回 50
PASS: lowerBound(100) 应返回 null（没有 >= 100 的元素）
PASS: lowerBound(35) 应返回 40（第一个 >= 35）
PASS: lowerBound 测试后，树应保持红黑树属性

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
PASS: upperBound 测试后，树应保持红黑树属性

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
PASS: 边界测试后，树应保持红黑树属性

测试性能表现...

容量: 100，执行次数: 100
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 RedBlackTree 中
添加 100 个元素平均耗时: 3.36 毫秒
搜索 100 个元素平均耗时: 0.55 毫秒
移除 100 个元素平均耗时: 5.13 毫秒
buildFromArray(100 个元素)平均耗时: 0.65 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.62 毫秒

容量: 1000，执行次数: 10
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 RedBlackTree 中
添加 1000 个元素平均耗时: 51.1 毫秒
搜索 1000 个元素平均耗时: 8.5 毫秒
移除 1000 个元素平均耗时: 87.9 毫秒
buildFromArray(1000 个元素)平均耗时: 6.2 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 6.4 毫秒

容量: 10000，执行次数: 1
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 RedBlackTree 中
添加 10000 个元素平均耗时: 687 毫秒
搜索 10000 个元素平均耗时: 108 毫秒
移除 10000 个元素平均耗时: 1267 毫秒
buildFromArray(10000 个元素)平均耗时: 63 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 64 毫秒
测试完成。通过: 176 个，失败: 0 个。
