org.flashNight.naki.Sort.TimSortTest.runTests();


Starting Enhanced TimSort Tests...

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

=== TimSort 核心特性测试 ===
PASS: Galloping Mode 激活测试
PASS: Galloping Mode 效率测试
    Galloping效率测试耗时: 0ms
PASS: Galloping Mode 自适应阈值测试
PASS: 自然run检测测试
PASS: 降序run反转优化测试
PASS: MIN_RUN计算测试 (size=31)
PASS: MIN_RUN计算测试 (size=32)
PASS: MIN_RUN计算测试 (size=63)
PASS: MIN_RUN计算测试 (size=64)
PASS: MIN_RUN计算测试 (size=127)
PASS: MIN_RUN计算测试 (size=128)
PASS: MIN_RUN计算测试 (size=255)
PASS: MIN_RUN计算测试 (size=256)
PASS: 边界优化测试（完全分离的run）
PASS: 边界优化测试（部分重叠的run）
PASS: 堆栈不变量维护测试

=== 稳定性深度测试 ===
PASS: 大数据集稳定性测试
PASS: Galloping模式稳定性测试
PASS: 复杂对象稳定性测试
PASS: 多run稳定性测试

=== 合并策略专项测试 ===
PASS: 强制三路合并测试
PASS: 级联合并测试
PASS: 合并稳定性测试
PASS: 合并边界条件测试
PASS: 极小run合并测试
PASS: 非对称run合并测试
PASS: 最大栈深度测试

=== 实际应用场景测试 ===
PASS: 部分有序数据测试
    部分有序数据排序耗时: 1ms
PASS: 交替模式测试
PASS: 钢琴键模式测试
PASS: 大量重复值测试
    大量重复值排序耗时: 7ms
PASS: 管道模式测试
PASS: 随机游走模式测试
PASS: 数据库风格数据测试
PASS: 时间序列数据测试

=== 边界条件和压力测试 ===
PASS: MIN_RUN边界测试 (length=31)
PASS: MIN_RUN边界测试 (length=32)
PASS: MIN_RUN边界测试 (length=33)
PASS: MIN_RUN边界测试 (length=63)
PASS: MIN_RUN边界测试 (length=64)
PASS: MIN_RUN边界测试 (length=65)
PASS: Gallop阈值边界测试
PASS: 大数组压力测试
    大数组压力测试 (size=50000) 耗时: 780ms
PASS: 深度递归避免测试
PASS: 内存效率测试
    内存效率测试耗时: 1ms

=== 性能测试 ===

开始增强版性能测试（3次取中位数）...
  测试数组大小: 1000
    random: 13ms
    sorted: 1ms
    reverse: 1ms
    partiallyOrdered: 11ms
    manyDuplicates: 12ms
    pianoKeys: 4ms
    organPipe: 4ms
    mergeStress: 5ms
    gallopFriendly: 2ms
    gallopUnfriendly: 3ms
  测试数组大小: 5000
    random: 92ms
    sorted: 5ms
    reverse: 8ms
    partiallyOrdered: 58ms
    manyDuplicates: 66ms
    pianoKeys: 18ms
    organPipe: 12ms
    mergeStress: 26ms
    gallopFriendly: 7ms
    gallopUnfriendly: 14ms
  测试数组大小: 10000
    random: 205ms
    sorted: 12ms
    reverse: 14ms
    partiallyOrdered: 127ms
    manyDuplicates: 133ms
    pianoKeys: 38ms
    organPipe: 27ms
    mergeStress: 46ms
    gallopFriendly: 15ms
    gallopUnfriendly: 28ms
增强版性能测试完成

All Enhanced TimSort Tests Completed.
