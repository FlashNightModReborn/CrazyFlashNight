// 手动模式（传入 false 禁用自动启动可视化测试）
var tester = new org.flashNight.neur.ScheduleTimer.CerberusSchedulerTest(true);
tester.runAllUnitTests();  // 一键运行所有单元测试（含 FIX v1.2）




testMethodAccuracy: 插入任务 testTask 延迟 100 帧
╔════════════════════════════════════════╗
║  CerberusScheduler 完整测试套件        ║
╚════════════════════════════════════════╝

testMethodAccuracy: 插入任务 testTask 延迟 100 帧
========================================
开始 FIX v1.2 验证测试
========================================
=== [FIX v1.2] 测试节点回收 ===
初始节点池大小: 748
插入后节点池大小: 747
删除后节点池大小: 748
[PASS] removeTaskByNode 正确回收节点到池中
=== 节点回收测试完成 ===

=== [FIX v1.2] 测试重调度返回新节点 ===
原始节点 taskID: rescheduleReturnTestTask
[PASS] rescheduleTaskByNode 返回了新节点，taskID 正确
=== 重调度返回新节点测试完成 ===

=== [FIX v1.2] 测试精度阈值一致性 ===
[PASS] 5秒延迟（单层时间轮边界） 成功插入
[PASS] 10秒延迟（第二级时间轮阈值） 成功插入
[PASS] 60秒延迟（第三级时间轮边界） 成功插入
=== 精度阈值一致性测试完成 ===

========================================
FIX v1.2 验证测试完成
========================================

========================================
开始 FIX v1.4 验证测试
========================================
=== [FIX v1.4] 测试 ownerType 路由 ===
单层时间轮节点 ownerType: 1 (期望: 1)
[PASS] 单层时间轮 ownerType 正确
秒级时间轮节点 ownerType: 2 (期望: 2)
[PASS] 秒级时间轮 ownerType 正确
分钟级时间轮节点 ownerType: 3 (期望: 3)
[PASS] 分钟级时间轮 ownerType 正确
最小堆节点 ownerType: 4 (期望: 4)
[PASS] 最小堆 ownerType 正确
=== ownerType 路由测试完成 ===

=== [FIX v1.4] 测试路由间隙修复 ===
5秒任务(150帧) ownerType: 2
[PASS] 5秒任务路由到时间轮 (ownerType=2)
7秒任务(210帧) ownerType: 2
[PASS] 7秒任务正确路由到二级时间轮
9秒任务(270帧) ownerType: 2
[PASS] 9秒任务正确路由到二级时间轮
=== 路由间隙修复测试完成 ===

=== [FIX v1.4] 测试 taskTable 废弃 ===
[PASS] findTaskInTable 返回 null（已废弃）
调用废弃方法 removeTaskByID（应看到警告）...
[CerberusScheduler] WARNING: removeTaskByID is deprecated. Use TaskManager.removeTask instead.
[PASS] removeTaskByID 已废弃但未崩溃
调用废弃方法 rescheduleTaskByID（应看到警告）...
[CerberusScheduler] WARNING: rescheduleTaskByID is deprecated. Use TaskManager.delayTask instead.
[PASS] rescheduleTaskByID 已废弃但未崩溃
=== taskTable 废弃测试完成 ===

=== [FIX v1.4] 测试 recycleExpiredNode ===
初始节点池大小: 747
插入后节点池大小: 746
原始 taskID: recycleTest, ownerType: 1
[PASS] 节点已正确重置（taskID=null, ownerType=0）
回收后节点池大小: 747
[PASS] 节点已回收到节点池
=== recycleExpiredNode 测试完成 ===

=== [FIX v1.4] 测试堆节点删除 ===
任务已进入最小堆，ownerType=4
删除前堆大小: 1
删除后堆大小: 0
[PASS] 堆节点正确删除，堆大小从 1 减少到 0
=== 堆节点删除测试完成 ===

========================================
FIX v1.4 验证测试完成
========================================

========================================
开始 FIX v1.5 验证测试
========================================
=== [FIX v1.5] 测试统一节点池 ===
单层时间轮节点池大小: 746
二级时间轮节点池大小: 746
三级时间轮节点池大小: 746
[PASS] 所有时间轮共享同一节点池，大小一致: 746
从二级时间轮获取节点后，单层池大小: 745 (期望: 745)
[PASS] 二级时间轮的 acquireNode 正确影响统一池
回收到三级时间轮后，单层池大小: 746 (期望: 746)
[PASS] 三级时间轮的 releaseNode 正确影响统一池
=== 统一节点池测试完成 ===

=== [FIX v1.5] 测试防重复回收 ===
原始 ownerType: 1
第一次回收后池大小: 746 (之前: 745)
[PASS] 第一次回收后 ownerType 正确设为 0
第二次回收后池大小: 746 (应与第一次相同: 746)
[PASS] 重复回收被正确阻止，池大小未变化
=== 防重复回收测试完成 ===

=== [FIX v1.5] 测试节点池委托 ===
初始节点池大小: 746
通过二级时间轮填充10个节点后: 756
[PASS] fillNodePool 委托正确工作
通过三级时间轮裁剪到 751 后: 751
[PASS] trimNodePool 委托正确工作
=== 节点池委托测试完成 ===

========================================
FIX v1.5 验证测试完成
========================================

========================================
开始 FIX v1.6 验证测试
========================================
=== [FIX v1.6] 测试高精度 API ===
[PASS] addToMinHeapByID 正确将任务插入最小堆 (ownerType=4)
[PASS] 高精度任务帧索引精确: 12345
=== 高精度 API 测试完成 ===

=== [FIX v1.6] 测试 precisionThreshold 弃用 ===
[PASS] precisionThreshold 不影响任务路由，两者 ownerType=2
[INFO] precisionThreshold 参数已标记为 @deprecated
[INFO] 对于高精度需求，建议使用 addToMinHeapByID() API
=== precisionThreshold 弃用测试完成 ===

=== [FIX v1.6] 测试 off-by-one 语义 ===
起始帧: 0
任务已插入，延迟: 10 帧
[INFO] 时间轮语义说明：
[INFO]   - 使用 Math.ceil 计算槽位
[INFO]   - 任务在第 N 帧的 tick 开始时触发
[INFO]   - 对于 delay=10，任务将在 currentFrame+10 的 tick 中执行
[PASS] 短延迟任务正确进入单层时间轮
=== off-by-one 语义测试完成 ===

=== [FIX v1.6] 测试最小堆回调自删除 ===
已插入 5 个任务到最小堆
删除前堆大小: 5
删除后堆大小: 0
[PASS] 所有节点成功删除，无异常
=== 最小堆回调自删除测试完成 ===

========================================
FIX v1.6 验证测试完成
========================================

========================================
开始性能测试
========================================
Insertion of 100 tasks took 1 ms
Finding 100 tasks took 1 ms
Rescheduling 100 tasks took 2 ms
Deletion of 100 tasks took 1 ms
Performance test for 100 tasks completed.
Detailed Performance Report:
Insertion Time: 1 ms
Find Time: 1 ms
Reschedule Time: 2 ms
Deletion Time: 1 ms

Starting tick performance test for 100 tasks.
Tick Test - Insertion of 100 tasks took 1 ms
Tick performance for 100 tasks took 1 ms
Average Tick Time per Frame: 0.0099009900990099 ms
Tick performance test for 100 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.0099009900990099 ms

Insertion of 161 tasks took 3 ms
Finding 161 tasks took 0 ms
Rescheduling 161 tasks took 3 ms
Deletion of 161 tasks took 2 ms
Performance test for 161 tasks completed.
Detailed Performance Report:
Insertion Time: 3 ms
Find Time: 0 ms
Reschedule Time: 3 ms
Deletion Time: 2 ms

Starting tick performance test for 161 tasks.
Tick Test - Insertion of 161 tasks took 2 ms
Tick performance for 161 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 161 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 260 tasks took 3 ms
Finding 260 tasks took 0 ms
Rescheduling 260 tasks took 6 ms
Deletion of 260 tasks took 2 ms
Performance test for 260 tasks completed.
Detailed Performance Report:
Insertion Time: 3 ms
Find Time: 0 ms
Reschedule Time: 6 ms
Deletion Time: 2 ms

Starting tick performance test for 260 tasks.
Tick Test - Insertion of 260 tasks took 4 ms
Tick performance for 260 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 260 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 420 tasks took 6 ms
Finding 420 tasks took 0 ms
Rescheduling 420 tasks took 9 ms
Deletion of 420 tasks took 5 ms
Performance test for 420 tasks completed.
Detailed Performance Report:
Insertion Time: 6 ms
Find Time: 0 ms
Reschedule Time: 9 ms
Deletion Time: 5 ms

Starting tick performance test for 420 tasks.
Tick Test - Insertion of 420 tasks took 5 ms
Tick performance for 420 tasks took 1 ms
Average Tick Time per Frame: 0.00625 ms
Tick performance test for 420 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.00625 ms

Insertion of 679 tasks took 9 ms
Finding 679 tasks took 1 ms
Rescheduling 679 tasks took 14 ms
Deletion of 679 tasks took 6 ms
Performance test for 679 tasks completed.
Detailed Performance Report:
Insertion Time: 9 ms
Find Time: 1 ms
Reschedule Time: 14 ms
Deletion Time: 6 ms

Starting tick performance test for 679 tasks.
Tick Test - Insertion of 679 tasks took 8 ms
Tick performance for 679 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 679 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 1098 tasks took 16 ms
Finding 1098 tasks took 2 ms
Rescheduling 1098 tasks took 24 ms
Deletion of 1098 tasks took 9 ms
Performance test for 1098 tasks completed.
Detailed Performance Report:
Insertion Time: 16 ms
Find Time: 2 ms
Reschedule Time: 24 ms
Deletion Time: 9 ms

Starting tick performance test for 1098 tasks.
Tick Test - Insertion of 1098 tasks took 11 ms
Tick performance for 1098 tasks took 1 ms
Average Tick Time per Frame: 0.00238663484486874 ms
Tick performance test for 1098 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.00238663484486874 ms

Insertion of 1776 tasks took 28 ms
Finding 1776 tasks took 2 ms
Rescheduling 1776 tasks took 37 ms
Deletion of 1776 tasks took 15 ms
Performance test for 1776 tasks completed.
Detailed Performance Report:
Insertion Time: 28 ms
Find Time: 2 ms
Reschedule Time: 37 ms
Deletion Time: 15 ms

Starting tick performance test for 1776 tasks.
Tick Test - Insertion of 1776 tasks took 19 ms
Tick performance for 1776 tasks took 2 ms
Average Tick Time per Frame: 0.00294985250737463 ms
Tick performance test for 1776 tasks completed.
Detailed Tick Performance Report:
Tick Time: 2 ms
Average Tick Time per Frame: 0.00294985250737463 ms

Insertion of 2873 tasks took 37 ms
Finding 2873 tasks took 5 ms
Rescheduling 2873 tasks took 56 ms
Deletion of 2873 tasks took 22 ms
Performance test for 2873 tasks completed.
Detailed Performance Report:
Insertion Time: 37 ms
Find Time: 5 ms
Reschedule Time: 56 ms
Deletion Time: 22 ms

Starting tick performance test for 2873 tasks.
Tick Test - Insertion of 2873 tasks took 31 ms
Tick performance for 2873 tasks took 2 ms
Average Tick Time per Frame: 0.00182315405651778 ms
Tick performance test for 2873 tasks completed.
Detailed Tick Performance Report:
Tick Time: 2 ms
Average Tick Time per Frame: 0.00182315405651778 ms

Insertion of 4648 tasks took 64 ms
Finding 4648 tasks took 5 ms
Rescheduling 4648 tasks took 98 ms
Deletion of 4648 tasks took 36 ms
Performance test for 4648 tasks completed.
Detailed Performance Report:
Insertion Time: 64 ms
Find Time: 5 ms
Reschedule Time: 98 ms
Deletion Time: 36 ms

Starting tick performance test for 4648 tasks.
Tick Test - Insertion of 4648 tasks took 55 ms
Tick performance for 4648 tasks took 6 ms
Average Tick Time per Frame: 0.00338028169014085 ms
Tick performance test for 4648 tasks completed.
Detailed Tick Performance Report:
Tick Time: 6 ms
Average Tick Time per Frame: 0.00338028169014085 ms

Insertion of 7520 tasks took 111 ms
Finding 7520 tasks took 10 ms
Rescheduling 7520 tasks took 147 ms
Deletion of 7520 tasks took 53 ms
Performance test for 7520 tasks completed.
Detailed Performance Report:
Insertion Time: 111 ms
Find Time: 10 ms
Reschedule Time: 147 ms
Deletion Time: 53 ms

Starting tick performance test for 7520 tasks.
Tick Test - Insertion of 7520 tasks took 84 ms
Tick performance for 7520 tasks took 10 ms
Average Tick Time per Frame: 0.00348189415041783 ms
Tick performance test for 7520 tasks completed.
Detailed Tick Performance Report:
Tick Time: 10 ms
Average Tick Time per Frame: 0.00348189415041783 ms

╔════════════════════════════════════════╗
║  所有测试完成                          ║
╚════════════════════════════════════════╝
测试完成。
性能测试结果总结:
任务数: 100 | 插入耗时: 1ms | 查找耗时: 1ms | 重新调度耗时: 2ms | 删除耗时: 1ms
任务数: 100 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.0099009900990099 ms
任务数: 161 | 插入耗时: 3ms | 查找耗时: 0ms | 重新调度耗时: 3ms | 删除耗时: 2ms
任务数: 161 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 260 | 插入耗时: 3ms | 查找耗时: 0ms | 重新调度耗时: 6ms | 删除耗时: 2ms
任务数: 260 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 420 | 插入耗时: 6ms | 查找耗时: 0ms | 重新调度耗时: 9ms | 删除耗时: 5ms
任务数: 420 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.00625 ms
任务数: 679 | 插入耗时: 9ms | 查找耗时: 1ms | 重新调度耗时: 14ms | 删除耗时: 6ms
任务数: 679 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 1098 | 插入耗时: 16ms | 查找耗时: 2ms | 重新调度耗时: 24ms | 删除耗时: 9ms
任务数: 1098 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.00238663484486874 ms
任务数: 1776 | 插入耗时: 28ms | 查找耗时: 2ms | 重新调度耗时: 37ms | 删除耗时: 15ms
任务数: 1776 | Tick耗时: 2 ms | 平均 Tick 耗时: 0.00294985250737463 ms
任务数: 2873 | 插入耗时: 37ms | 查找耗时: 5ms | 重新调度耗时: 56ms | 删除耗时: 22ms
任务数: 2873 | Tick耗时: 2 ms | 平均 Tick 耗时: 0.00182315405651778 ms
任务数: 4648 | 插入耗时: 64ms | 查找耗时: 5ms | 重新调度耗时: 98ms | 删除耗时: 36ms
任务数: 4648 | Tick耗时: 6 ms | 平均 Tick 耗时: 0.00338028169014085 ms
任务数: 7520 | 插入耗时: 111ms | 查找耗时: 10ms | 重新调度耗时: 147ms | 删除耗时: 53ms
任务数: 7520 | Tick耗时: 10 ms | 平均 Tick 耗时: 0.00348189415041783 ms

