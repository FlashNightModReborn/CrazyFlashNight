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
开始性能测试
========================================
Insertion of 100 tasks took 2 ms
Finding 100 tasks took 0 ms
Rescheduling 100 tasks took 1 ms
Deletion of 100 tasks took 1 ms
Performance test for 100 tasks completed.
Detailed Performance Report:
Insertion Time: 2 ms
Find Time: 0 ms
Reschedule Time: 1 ms
Deletion Time: 1 ms

Starting tick performance test for 100 tasks.
Tick Test - Insertion of 100 tasks took 1 ms
Tick performance for 100 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 100 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 161 tasks took 1 ms
Finding 161 tasks took 0 ms
Rescheduling 161 tasks took 3 ms
Deletion of 161 tasks took 1 ms
Performance test for 161 tasks completed.
Detailed Performance Report:
Insertion Time: 1 ms
Find Time: 0 ms
Reschedule Time: 3 ms
Deletion Time: 1 ms

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
Rescheduling 260 tasks took 5 ms
Deletion of 260 tasks took 1 ms
Performance test for 260 tasks completed.
Detailed Performance Report:
Insertion Time: 3 ms
Find Time: 0 ms
Reschedule Time: 5 ms
Deletion Time: 1 ms

Starting tick performance test for 260 tasks.
Tick Test - Insertion of 260 tasks took 3 ms
Tick performance for 260 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 260 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 420 tasks took 5 ms
Finding 420 tasks took 1 ms
Rescheduling 420 tasks took 7 ms
Deletion of 420 tasks took 3 ms
Performance test for 420 tasks completed.
Detailed Performance Report:
Insertion Time: 5 ms
Find Time: 1 ms
Reschedule Time: 7 ms
Deletion Time: 3 ms

Starting tick performance test for 420 tasks.
Tick Test - Insertion of 420 tasks took 4 ms
Tick performance for 420 tasks took 1 ms
Average Tick Time per Frame: 0.00625 ms
Tick performance test for 420 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.00625 ms

Insertion of 679 tasks took 9 ms
Finding 679 tasks took 1 ms
Rescheduling 679 tasks took 12 ms
Deletion of 679 tasks took 6 ms
Performance test for 679 tasks completed.
Detailed Performance Report:
Insertion Time: 9 ms
Find Time: 1 ms
Reschedule Time: 12 ms
Deletion Time: 6 ms

Starting tick performance test for 679 tasks.
Tick Test - Insertion of 679 tasks took 7 ms
Tick performance for 679 tasks took 1 ms
Average Tick Time per Frame: 0.00386100386100386 ms
Tick performance test for 679 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.00386100386100386 ms

Insertion of 1098 tasks took 15 ms
Finding 1098 tasks took 1 ms
Rescheduling 1098 tasks took 21 ms
Deletion of 1098 tasks took 7 ms
Performance test for 1098 tasks completed.
Detailed Performance Report:
Insertion Time: 15 ms
Find Time: 1 ms
Reschedule Time: 21 ms
Deletion Time: 7 ms

Starting tick performance test for 1098 tasks.
Tick Test - Insertion of 1098 tasks took 11 ms
Tick performance for 1098 tasks took 2 ms
Average Tick Time per Frame: 0.00477326968973747 ms
Tick performance test for 1098 tasks completed.
Detailed Tick Performance Report:
Tick Time: 2 ms
Average Tick Time per Frame: 0.00477326968973747 ms

Insertion of 1776 tasks took 21 ms
Finding 1776 tasks took 1 ms
Rescheduling 1776 tasks took 31 ms
Deletion of 1776 tasks took 13 ms
Performance test for 1776 tasks completed.
Detailed Performance Report:
Insertion Time: 21 ms
Find Time: 1 ms
Reschedule Time: 31 ms
Deletion Time: 13 ms

Starting tick performance test for 1776 tasks.
Tick Test - Insertion of 1776 tasks took 16 ms
Tick performance for 1776 tasks took 2 ms
Average Tick Time per Frame: 0.00294985250737463 ms
Tick performance test for 1776 tasks completed.
Detailed Tick Performance Report:
Tick Time: 2 ms
Average Tick Time per Frame: 0.00294985250737463 ms

Insertion of 2873 tasks took 33 ms
Finding 2873 tasks took 4 ms
Rescheduling 2873 tasks took 51 ms
Deletion of 2873 tasks took 18 ms
Performance test for 2873 tasks completed.
Detailed Performance Report:
Insertion Time: 33 ms
Find Time: 4 ms
Reschedule Time: 51 ms
Deletion Time: 18 ms

Starting tick performance test for 2873 tasks.
Tick Test - Insertion of 2873 tasks took 27 ms
Tick performance for 2873 tasks took 4 ms
Average Tick Time per Frame: 0.00364630811303555 ms
Tick performance test for 2873 tasks completed.
Detailed Tick Performance Report:
Tick Time: 4 ms
Average Tick Time per Frame: 0.00364630811303555 ms

Insertion of 4648 tasks took 57 ms
Finding 4648 tasks took 7 ms
Rescheduling 4648 tasks took 78 ms
Deletion of 4648 tasks took 33 ms
Performance test for 4648 tasks completed.
Detailed Performance Report:
Insertion Time: 57 ms
Find Time: 7 ms
Reschedule Time: 78 ms
Deletion Time: 33 ms

Starting tick performance test for 4648 tasks.
Tick Test - Insertion of 4648 tasks took 48 ms
Tick performance for 4648 tasks took 6 ms
Average Tick Time per Frame: 0.00338028169014085 ms
Tick performance test for 4648 tasks completed.
Detailed Tick Performance Report:
Tick Time: 6 ms
Average Tick Time per Frame: 0.00338028169014085 ms

Insertion of 7520 tasks took 88 ms
Finding 7520 tasks took 12 ms
Rescheduling 7520 tasks took 128 ms
Deletion of 7520 tasks took 48 ms
Performance test for 7520 tasks completed.
Detailed Performance Report:
Insertion Time: 88 ms
Find Time: 12 ms
Reschedule Time: 128 ms
Deletion Time: 48 ms

Starting tick performance test for 7520 tasks.
Tick Test - Insertion of 7520 tasks took 74 ms
Tick performance for 7520 tasks took 12 ms
Average Tick Time per Frame: 0.00417827298050139 ms
Tick performance test for 7520 tasks completed.
Detailed Tick Performance Report:
Tick Time: 12 ms
Average Tick Time per Frame: 0.00417827298050139 ms

╔════════════════════════════════════════╗
║  所有测试完成                          ║
╚════════════════════════════════════════╝
测试完成。
性能测试结果总结:
任务数: 100 | 插入耗时: 2ms | 查找耗时: 0ms | 重新调度耗时: 1ms | 删除耗时: 1ms
任务数: 100 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 161 | 插入耗时: 1ms | 查找耗时: 0ms | 重新调度耗时: 3ms | 删除耗时: 1ms
任务数: 161 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 260 | 插入耗时: 3ms | 查找耗时: 0ms | 重新调度耗时: 5ms | 删除耗时: 1ms
任务数: 260 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 420 | 插入耗时: 5ms | 查找耗时: 1ms | 重新调度耗时: 7ms | 删除耗时: 3ms
任务数: 420 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.00625 ms
任务数: 679 | 插入耗时: 9ms | 查找耗时: 1ms | 重新调度耗时: 12ms | 删除耗时: 6ms
任务数: 679 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.00386100386100386 ms
任务数: 1098 | 插入耗时: 15ms | 查找耗时: 1ms | 重新调度耗时: 21ms | 删除耗时: 7ms
任务数: 1098 | Tick耗时: 2 ms | 平均 Tick 耗时: 0.00477326968973747 ms
任务数: 1776 | 插入耗时: 21ms | 查找耗时: 1ms | 重新调度耗时: 31ms | 删除耗时: 13ms
任务数: 1776 | Tick耗时: 2 ms | 平均 Tick 耗时: 0.00294985250737463 ms
任务数: 2873 | 插入耗时: 33ms | 查找耗时: 4ms | 重新调度耗时: 51ms | 删除耗时: 18ms
任务数: 2873 | Tick耗时: 4 ms | 平均 Tick 耗时: 0.00364630811303555 ms
任务数: 4648 | 插入耗时: 57ms | 查找耗时: 7ms | 重新调度耗时: 78ms | 删除耗时: 33ms
任务数: 4648 | Tick耗时: 6 ms | 平均 Tick 耗时: 0.00338028169014085 ms
任务数: 7520 | 插入耗时: 88ms | 查找耗时: 12ms | 重新调度耗时: 128ms | 删除耗时: 48ms
任务数: 7520 | Tick耗时: 12 ms | 平均 Tick 耗时: 0.00417827298050139 ms
