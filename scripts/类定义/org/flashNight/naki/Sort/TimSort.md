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
    部分有序数据排序耗时: 2ms
PASS: 交替模式测试
PASS: 钢琴键模式测试
PASS: 大量重复值测试
    大量重复值排序耗时: 8ms
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
    大数组压力测试 (size=50000) 耗时: 779ms
PASS: 深度递归避免测试
PASS: 内存效率测试
    内存效率测试耗时: 1ms

=== 性能测试 ===

开始增强版性能测试（3次取中位数）...
  测试数组大小: 1000
    random: 15ms
    sorted: 1ms
    reverse: 2ms
    partiallyOrdered: 11ms
    manyDuplicates: 13ms
    pianoKeys: 4ms
    organPipe: 3ms
    mergeStress: 5ms
    gallopFriendly: 2ms
    gallopUnfriendly: 3ms
  测试数组大小: 5000
    random: 103ms
    sorted: 6ms
    reverse: 7ms
    partiallyOrdered: 62ms
    manyDuplicates: 71ms
    pianoKeys: 20ms
    organPipe: 14ms
    mergeStress: 25ms
    gallopFriendly: 7ms
    gallopUnfriendly: 14ms
  测试数组大小: 10000
    random: 205ms
    sorted: 12ms
    reverse: 14ms
    partiallyOrdered: 135ms
    manyDuplicates: 148ms
    pianoKeys: 38ms
    organPipe: 28ms
    mergeStress: 49ms
    gallopFriendly: 14ms
    gallopUnfriendly: 28ms
增强版性能测试完成

=== sortIndirect 正确性与稳定性测试 ===
PASS: sortIndirect 空数组
PASS: sortIndirect 单元素
PASS: sortIndirect 正确性 (50 组合全通过)
PASS: sortIndirect 稳定性 (4 sizes × 5-duplicate keys)
PASS: sortIndirect 与 sort 结果一致 (4 sizes)

=== sortIndirect vs sort 性能对比 ===
sort vs sortIndirect 性能对比（3次取中位数）...
  数组大小: 1000
    random: sort=20ms  indirect=10ms  提升=50%
    sorted: sort=1ms  indirect=0ms  提升=100%
    reverse: sort=2ms  indirect=1ms  提升=50%
    partiallyOrdered: sort=13ms  indirect=8ms  提升=38%
    manyDuplicates: sort=16ms  indirect=10ms  提升=38%
    gallopFriendly: sort=2ms  indirect=1ms  提升=50%
    gallopUnfriendly: sort=4ms  indirect=2ms  提升=50%
  数组大小: 5000
    random: sort=123ms  indirect=65ms  提升=47%
    sorted: sort=8ms  indirect=3ms  提升=63%
    reverse: sort=9ms  indirect=4ms  提升=56%
    partiallyOrdered: sort=79ms  indirect=48ms  提升=39%
    manyDuplicates: sort=89ms  indirect=54ms  提升=39%
    gallopFriendly: sort=9ms  indirect=4ms  提升=56%
    gallopUnfriendly: sort=19ms  indirect=9ms  提升=53%
  数组大小: 10000
    random: sort=272ms  indirect=149ms  提升=45%
    sorted: sort=15ms  indirect=5ms  提升=67%
    reverse: sort=19ms  indirect=9ms  提升=53%
    partiallyOrdered: sort=173ms  indirect=108ms  提升=38%
    manyDuplicates: sort=185ms  indirect=116ms  提升=37%
    gallopFriendly: sort=18ms  indirect=8ms  提升=56%
    gallopUnfriendly: sort=37ms  indirect=17ms  提升=54%
sort vs sortIndirect 性能对比完成

All Enhanced TimSort Tests Completed.
