org.flashNight.naki.Sort.NaturalMergeSortTest.runTests();


Starting Enhanced NaturalMergeSort Tests...

=== 基础功能测试 ===
PASS: 空数组测试
PASS: 单元素数组测试
PASS: 已排序数组测试
PASS: 逆序数组测试
PASS: 随机数组测试
PASS: 重复元素测试
PASS: 全相同元素测试
PASS: 自定义比较函数测试
PASS: 两元素数组测试（需要交换）
PASS: 两元素数组测试（已有序）
PASS: 三元素数组测试（随机）
PASS: 三元素数组测试（部分有序）
PASS: 三元素数组测试（完全逆序）

=== NaturalMergeSort 核心特性测试 ===
PASS: 自然 run 识别和合并测试
PASS: 高效合并测试
    高效合并测试耗时: 1ms
PASS: 交替模式处理测试
PASS: 自然run检测测试
PASS: 降序run反转优化测试
PASS: 不同大小处理测试 (size=31)
PASS: 不同大小处理测试 (size=32)
PASS: 不同大小处理测试 (size=63)
PASS: 不同大小处理测试 (size=64)
PASS: 不同大小处理测试 (size=127)
PASS: 不同大小处理测试 (size=128)
PASS: 不同大小处理测试 (size=255)
PASS: 不同大小处理测试 (size=256)
PASS: 边界优化测试（完全分离的run）
PASS: 边界优化测试（部分重叠的run）
PASS: 合并策略维护测试

=== 稳定性深度测试 ===
PASS: 大数据集稳定性测试
PASS: 大块合并稳定性测试
PASS: 复杂对象稳定性测试
PASS: 多run稳定性测试

=== 合并策略专项测试 ===
PASS: 三路合并测试
PASS: 级联合并测试
PASS: 合并稳定性测试
PASS: 合并边界条件测试
PASS: 极小run合并测试
PASS: 非对称run合并测试
PASS: 多轮合并测试

=== 实际应用场景测试 ===
PASS: 部分有序数据测试
    部分有序数据排序耗时: 1ms
PASS: 交替模式测试
PASS: 钢琴键模式测试
PASS: 大量重复值测试
    大量重复值排序耗时: 15ms
PASS: 管道模式测试
PASS: 随机游走模式测试
PASS: 数据库风格数据测试
PASS: 时间序列数据测试

=== 边界条件和压力测试 ===
PASS: 边界长度测试 (length=31)
PASS: 边界长度测试 (length=32)
PASS: 边界长度测试 (length=33)
PASS: 边界长度测试 (length=63)
PASS: 边界长度测试 (length=64)
PASS: 边界长度测试 (length=65)
PASS: 合并阈值边界测试
PASS: 大数组压力测试
    大数组压力测试 (size=50000) 耗时: 1082ms
PASS: 迭代式合并测试
PASS: 内存效率测试
    内存效率测试耗时: 2ms

=== 性能测试 ===

开始增强版性能测试...
  测试数组大小: 1000
    random: 18ms
    sorted: 0ms
    reverse: 1ms
    partiallyOrdered: 15ms
    manyDuplicates: 18ms
    pianoKeys: 8ms
    organPipe: 2ms
    mergeStress: 8ms
    gallopFriendly: 2ms
    gallopUnfriendly: 14ms
  测试数组大小: 5000
    random: 105ms
    sorted: 7ms
    reverse: 9ms
    partiallyOrdered: 76ms
    manyDuplicates: 94ms
    pianoKeys: 54ms
    organPipe: 18ms
    mergeStress: 52ms
    gallopFriendly: 13ms
    gallopUnfriendly: 84ms
  测试数组大小: 10000
    random: 226ms
    sorted: 14ms
    reverse: 15ms
    partiallyOrdered: 166ms
    manyDuplicates: 218ms
    pianoKeys: 115ms
    organPipe: 31ms
    mergeStress: 117ms
    gallopFriendly: 26ms
    gallopUnfriendly: 196ms
增强版性能测试完成

All Enhanced NaturalMergeSort Tests Completed.
