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

测试性能表现...

容量: 100，执行次数: 100
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 RedBlackTree 中
添加 100 个元素平均耗时: 4.16 毫秒
搜索 100 个元素平均耗时: 0.61 毫秒
移除 100 个元素平均耗时: 7.22 毫秒
buildFromArray(100 个元素)平均耗时: 0.65 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.56 毫秒

容量: 1000，执行次数: 10
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 RedBlackTree 中
添加 1000 个元素平均耗时: 63.6 毫秒
搜索 1000 个元素平均耗时: 8.5 毫秒
移除 1000 个元素平均耗时: 127.9 毫秒
buildFromArray(1000 个元素)平均耗时: 6.2 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 6.5 毫秒

容量: 10000，执行次数: 1
PASS: 所有元素移除后，size 应为0
PASS: 所有添加的元素都应成功移除
PASS: 所有添加的元素都应存在于 RedBlackTree 中
添加 10000 个元素平均耗时: 870 毫秒
搜索 10000 个元素平均耗时: 118 毫秒
移除 10000 个元素平均耗时: 1876 毫秒
buildFromArray(10000 个元素)平均耗时: 59 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 65 毫秒
测试完成。通过: 102 个，失败: 0 个。