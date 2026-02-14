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
    部分有序数据排序耗时: 0ms
PASS: 交替模式测试
PASS: 钢琴键模式测试
PASS: 大量重复值测试
    大量重复值排序耗时: 9ms
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
    大数组压力测试 (size=50000) 耗时: 761ms
PASS: 深度递归避免测试
PASS: 内存效率测试
    内存效率测试耗时: 1ms

=== 性能测试 ===

开始增强版性能测试（3次取中位数）...
  测试数组大小: 1000
    random: 14ms
    sorted: 1ms
    reverse: 1ms
    partiallyOrdered: 12ms
    manyDuplicates: 11ms
    pianoKeys: 4ms
    organPipe: 3ms
    mergeStress: 4ms
    gallopFriendly: 2ms
    gallopUnfriendly: 3ms
  测试数组大小: 5000
    random: 88ms
    sorted: 5ms
    reverse: 8ms
    partiallyOrdered: 56ms
    manyDuplicates: 69ms
    pianoKeys: 19ms
    organPipe: 15ms
    mergeStress: 23ms
    gallopFriendly: 7ms
    gallopUnfriendly: 13ms
  测试数组大小: 10000
    random: 195ms
    sorted: 13ms
    reverse: 16ms
    partiallyOrdered: 143ms
    manyDuplicates: 160ms
    pianoKeys: 42ms
    organPipe: 34ms
    mergeStress: 53ms
    gallopFriendly: 17ms
    gallopUnfriendly: 31ms
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
    random: sort=20ms  indirect=12ms  提升=40%
    sorted: sort=3ms  indirect=2ms  提升=33%
    reverse: sort=3ms  indirect=1ms  提升=67%
    partiallyOrdered: sort=15ms  indirect=9ms  提升=40%
    manyDuplicates: sort=19ms  indirect=11ms  提升=42%
    gallopFriendly: sort=2ms  indirect=1ms  提升=50%
    gallopUnfriendly: sort=4ms  indirect=3ms  提升=25%
  数组大小: 5000
    random: sort=131ms  indirect=72ms  提升=45%
    sorted: sort=8ms  indirect=4ms  提升=50%
    reverse: sort=9ms  indirect=6ms  提升=33%
    partiallyOrdered: sort=84ms  indirect=52ms  提升=38%
    manyDuplicates: sort=95ms  indirect=58ms  提升=39%
    gallopFriendly: sort=10ms  indirect=6ms  提升=40%
    gallopUnfriendly: sort=20ms  indirect=11ms  提升=45%
  数组大小: 10000
    random: sort=287ms  indirect=173ms  提升=40%
    sorted: sort=18ms  indirect=9ms  提升=50%
    reverse: sort=21ms  indirect=13ms  提升=38%
    partiallyOrdered: sort=193ms  indirect=117ms  提升=39%
    manyDuplicates: sort=197ms  indirect=121ms  提升=39%
    gallopFriendly: sort=22ms  indirect=13ms  提升=41%
    gallopUnfriendly: sort=41ms  indirect=23ms  提升=44%
sort vs sortIndirect 性能对比完成

All Enhanced TimSort Tests Completed.
