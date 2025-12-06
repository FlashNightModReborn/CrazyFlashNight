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

测试性能表现 [avl]...

容量: 100，执行次数: 100
PASS: [avl] 所有元素移除后，size 应为0
PASS: [avl] 所有添加的元素都应成功移除
PASS: [avl] 所有添加的元素都应存在于 TreeSet 中
添加 100 个元素平均耗时: 2.03 毫秒
搜索 100 个元素平均耗时: 0.66 毫秒
移除 100 个元素平均耗时: 1.42 毫秒
buildFromArray(100 个元素)平均耗时: 0.47 毫秒
changeCompareFunctionAndResort(100 个元素)平均耗时: 0.66 毫秒

容量: 1000，执行次数: 10
PASS: [avl] 所有元素移除后，size 应为0
PASS: [avl] 所有添加的元素都应成功移除
PASS: [avl] 所有添加的元素都应存在于 TreeSet 中
添加 1000 个元素平均耗时: 27.4 毫秒
搜索 1000 个元素平均耗时: 8.8 毫秒
移除 1000 个元素平均耗时: 19.9 毫秒
buildFromArray(1000 个元素)平均耗时: 4.4 毫秒
changeCompareFunctionAndResort(1000 个元素)平均耗时: 5.9 毫秒

容量: 10000，执行次数: 1
PASS: [avl] 所有元素移除后，size 应为0
PASS: [avl] 所有添加的元素都应成功移除
PASS: [avl] 所有添加的元素都应存在于 TreeSet 中
添加 10000 个元素平均耗时: 361 毫秒
搜索 10000 个元素平均耗时: 118 毫秒
移除 10000 个元素平均耗时: 267 毫秒
buildFromArray(10000 个元素)平均耗时: 45 毫秒
changeCompareFunctionAndResort(10000 个元素)平均耗时: 60 毫秒

########################################
## 五种树类型跨容量性能对比测试
########################################

========================================
容量级别: 1K (1000 元素)
========================================

--- AVL ---
添加: 29 ms
搜索: 9 ms
删除: 19 ms
构建: 5 ms

--- WAVL ---
添加: 20 ms
搜索: 8 ms
删除: 13 ms
构建: 5 ms

--- RB ---
添加: 68 ms
搜索: 10 ms
删除: 140 ms
构建: 68 ms

--- LLRB ---
添加: 68 ms
搜索: 10 ms
删除: 139 ms
构建: 66 ms

--- Zip ---
添加: 15 ms
搜索: 17 ms
删除: 15 ms
构建: 15 ms

----------------------------------------
汇总表 [1K] (1000 元素)
----------------------------------------
操作		AVL	WAVL	RB	LLRB	Zip	
添加		29	20	68	68	15	
搜索		9	8	10	10	17	
删除		19	13	140	139	15	
构建		5	5	68	66	15	
总计		62	46	286	283	62	

添加 最优: Zip (15ms) | 最差: RB (68ms)
搜索 最优: WAVL (8ms) | 最差: Zip (17ms)
删除 最优: WAVL (13ms) | 最差: RB (140ms)
构建 最优: AVL (5ms) | 最差: RB (68ms)

========================================
容量级别: 10K (10000 元素)
========================================

--- AVL ---
添加: 352 ms
搜索: 116 ms
删除: 258 ms
构建: 44 ms

--- WAVL ---
添加: 261 ms
搜索: 115 ms
删除: 186 ms
构建: 42 ms

--- RB ---
添加: 898 ms
搜索: 123 ms
删除: 2044 ms
构建: 894 ms

--- LLRB ---
添加: 872 ms
搜索: 121 ms
删除: 2007 ms
构建: 884 ms

--- Zip ---
添加: 150 ms
搜索: 216 ms
删除: 201 ms
构建: 151 ms

----------------------------------------
汇总表 [10K] (10000 元素)
----------------------------------------
操作		AVL	WAVL	RB	LLRB	Zip	
添加		352	261	898	872	150	
搜索		116	115	123	121	216	
删除		258	186	2044	2007	201	
构建		44	42	894	884	151	
总计		770	604	3959	3884	718	

添加 最优: Zip (150ms) | 最差: RB (898ms)
搜索 最优: WAVL (115ms) | 最差: Zip (216ms)
删除 最优: WAVL (186ms) | 最差: RB (2044ms)
构建 最优: WAVL (42ms) | 最差: RB (894ms)

========================================
容量级别: 100K (100000 元素)
========================================

--- AVL ---
添加: 4358 ms
搜索: 1450 ms
删除: 3264 ms
构建: 439 ms

--- WAVL ---
添加: 3311 ms
搜索: 1426 ms
删除: 2599 ms
构建: 445 ms

--- RB ---
添加: 11170 ms
搜索: 1527 ms
删除: 27125 ms
构建: 11253 ms

--- LLRB ---
添加: 11070 ms
搜索: 1520 ms
删除: 26647 ms
构建: 11263 ms

--- Zip ---
添加: 1548 ms
搜索: 3154 ms
删除: 3133 ms
构建: 1574 ms

----------------------------------------
汇总表 [100K] (100000 元素)
----------------------------------------
操作		AVL	WAVL	RB	LLRB	Zip	
添加		4358	3311	11170	11070	1548	
搜索		1450	1426	1527	1520	3154	
删除		3264	2599	27125	26647	3133	
构建		439	445	11253	11263	1574	
总计		9511	7781	51075	50500	9409	

添加 最优: Zip (1548ms) | 最差: RB (11170ms)
搜索 最优: WAVL (1426ms) | 最差: Zip (3154ms)
删除 最优: WAVL (2599ms) | 最差: RB (27125ms)
构建 最优: AVL (439ms) | 最差: LLRB (11263ms)

########################################
## 全容量对比完成
########################################

测试完成。通过: 299 个，失败: 0 个。
