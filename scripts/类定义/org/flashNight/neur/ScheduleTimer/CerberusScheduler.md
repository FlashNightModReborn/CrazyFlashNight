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
开始性能测试
========================================
Insertion of 100 tasks took 2 ms
Finding 100 tasks took 0 ms
Rescheduling 100 tasks took 3 ms
Deletion of 100 tasks took 1 ms
Performance test for 100 tasks completed.
Detailed Performance Report:
Insertion Time: 2 ms
Find Time: 0 ms
Reschedule Time: 3 ms
Deletion Time: 1 ms

Starting tick performance test for 100 tasks.
Tick Test - Insertion of 100 tasks took 2 ms
Tick performance for 100 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 100 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 161 tasks took 3 ms
Finding 161 tasks took 0 ms
Rescheduling 161 tasks took 4 ms
Deletion of 161 tasks took 1 ms
Performance test for 161 tasks completed.
Detailed Performance Report:
Insertion Time: 3 ms
Find Time: 0 ms
Reschedule Time: 4 ms
Deletion Time: 1 ms

Starting tick performance test for 161 tasks.
Tick Test - Insertion of 161 tasks took 2 ms
Tick performance for 161 tasks took 0 ms
Average Tick Time per Frame: 0 ms
Tick performance test for 161 tasks completed.
Detailed Tick Performance Report:
Tick Time: 0 ms
Average Tick Time per Frame: 0 ms

Insertion of 260 tasks took 4 ms
Finding 260 tasks took 0 ms
Rescheduling 260 tasks took 6 ms
Deletion of 260 tasks took 2 ms
Performance test for 260 tasks completed.
Detailed Performance Report:
Insertion Time: 4 ms
Find Time: 0 ms
Reschedule Time: 6 ms
Deletion Time: 2 ms

Starting tick performance test for 260 tasks.
Tick Test - Insertion of 260 tasks took 3 ms
Tick performance for 260 tasks took 1 ms
Average Tick Time per Frame: 0.0101010101010101 ms
Tick performance test for 260 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.0101010101010101 ms

Insertion of 420 tasks took 6 ms
Finding 420 tasks took 1 ms
Rescheduling 420 tasks took 11 ms
Deletion of 420 tasks took 3 ms
Performance test for 420 tasks completed.
Detailed Performance Report:
Insertion Time: 6 ms
Find Time: 1 ms
Reschedule Time: 11 ms
Deletion Time: 3 ms

Starting tick performance test for 420 tasks.
Tick Test - Insertion of 420 tasks took 7 ms
Tick performance for 420 tasks took 1 ms
Average Tick Time per Frame: 0.00625 ms
Tick performance test for 420 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.00625 ms

Insertion of 679 tasks took 10 ms
Finding 679 tasks took 1 ms
Rescheduling 679 tasks took 14 ms
Deletion of 679 tasks took 7 ms
Performance test for 679 tasks completed.
Detailed Performance Report:
Insertion Time: 10 ms
Find Time: 1 ms
Reschedule Time: 14 ms
Deletion Time: 7 ms

Starting tick performance test for 679 tasks.
Tick Test - Insertion of 679 tasks took 9 ms
Tick performance for 679 tasks took 3 ms
Average Tick Time per Frame: 0.0115830115830116 ms
Tick performance test for 679 tasks completed.
Detailed Tick Performance Report:
Tick Time: 3 ms
Average Tick Time per Frame: 0.0115830115830116 ms

Insertion of 1098 tasks took 17 ms
Finding 1098 tasks took 1 ms
Rescheduling 1098 tasks took 24 ms
Deletion of 1098 tasks took 9 ms
Performance test for 1098 tasks completed.
Detailed Performance Report:
Insertion Time: 17 ms
Find Time: 1 ms
Reschedule Time: 24 ms
Deletion Time: 9 ms

Starting tick performance test for 1098 tasks.
Tick Test - Insertion of 1098 tasks took 13 ms
Tick performance for 1098 tasks took 2 ms
Average Tick Time per Frame: 0.00477326968973747 ms
Tick performance test for 1098 tasks completed.
Detailed Tick Performance Report:
Tick Time: 2 ms
Average Tick Time per Frame: 0.00477326968973747 ms

Insertion of 1776 tasks took 23 ms
Finding 1776 tasks took 3 ms
Rescheduling 1776 tasks took 38 ms
Deletion of 1776 tasks took 14 ms
Performance test for 1776 tasks completed.
Detailed Performance Report:
Insertion Time: 23 ms
Find Time: 3 ms
Reschedule Time: 38 ms
Deletion Time: 14 ms

Starting tick performance test for 1776 tasks.
Tick Test - Insertion of 1776 tasks took 26 ms
Tick performance for 1776 tasks took 5 ms
Average Tick Time per Frame: 0.00737463126843658 ms
Tick performance test for 1776 tasks completed.
Detailed Tick Performance Report:
Tick Time: 5 ms
Average Tick Time per Frame: 0.00737463126843658 ms

Insertion of 2873 tasks took 41 ms
Finding 2873 tasks took 3 ms
Rescheduling 2873 tasks took 61 ms
Deletion of 2873 tasks took 22 ms
Performance test for 2873 tasks completed.
Detailed Performance Report:
Insertion Time: 41 ms
Find Time: 3 ms
Reschedule Time: 61 ms
Deletion Time: 22 ms

Starting tick performance test for 2873 tasks.
Tick Test - Insertion of 2873 tasks took 35 ms
Tick performance for 2873 tasks took 14 ms
Average Tick Time per Frame: 0.0127620783956244 ms
Tick performance test for 2873 tasks completed.
Detailed Tick Performance Report:
Tick Time: 14 ms
Average Tick Time per Frame: 0.0127620783956244 ms

Insertion of 4648 tasks took 64 ms
Finding 4648 tasks took 6 ms
Rescheduling 4648 tasks took 96 ms
Deletion of 4648 tasks took 36 ms
Performance test for 4648 tasks completed.
Detailed Performance Report:
Insertion Time: 64 ms
Find Time: 6 ms
Reschedule Time: 96 ms
Deletion Time: 36 ms

Starting tick performance test for 4648 tasks.
Tick Test - Insertion of 4648 tasks took 50 ms
Tick performance for 4648 tasks took 37 ms
Average Tick Time per Frame: 0.0208450704225352 ms
Tick performance test for 4648 tasks completed.
Detailed Tick Performance Report:
Tick Time: 37 ms
Average Tick Time per Frame: 0.0208450704225352 ms

╔════════════════════════════════════════╗
║  所有测试完成                          ║
╚════════════════════════════════════════╝
测试完成。
性能测试结果总结:
任务数: 100 | 插入耗时: 2ms | 查找耗时: 0ms | 重新调度耗时: 3ms | 删除耗时: 1ms
任务数: 100 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 161 | 插入耗时: 3ms | 查找耗时: 0ms | 重新调度耗时: 4ms | 删除耗时: 1ms
任务数: 161 | Tick耗时: 0 ms | 平均 Tick 耗时: 0 ms
任务数: 260 | 插入耗时: 4ms | 查找耗时: 0ms | 重新调度耗时: 6ms | 删除耗时: 2ms
任务数: 260 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.0101010101010101 ms
任务数: 420 | 插入耗时: 6ms | 查找耗时: 1ms | 重新调度耗时: 11ms | 删除耗时: 3ms
任务数: 420 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.00625 ms
任务数: 679 | 插入耗时: 10ms | 查找耗时: 1ms | 重新调度耗时: 14ms | 删除耗时: 7ms
任务数: 679 | Tick耗时: 3 ms | 平均 Tick 耗时: 0.0115830115830116 ms
任务数: 1098 | 插入耗时: 17ms | 查找耗时: 1ms | 重新调度耗时: 24ms | 删除耗时: 9ms
任务数: 1098 | Tick耗时: 2 ms | 平均 Tick 耗时: 0.00477326968973747 ms
任务数: 1776 | 插入耗时: 23ms | 查找耗时: 3ms | 重新调度耗时: 38ms | 删除耗时: 14ms
任务数: 1776 | Tick耗时: 5 ms | 平均 Tick 耗时: 0.00737463126843658 ms
任务数: 2873 | 插入耗时: 41ms | 查找耗时: 3ms | 重新调度耗时: 61ms | 删除耗时: 22ms
任务数: 2873 | Tick耗时: 14 ms | 平均 Tick 耗时: 0.0127620783956244 ms
任务数: 4648 | 插入耗时: 64ms | 查找耗时: 6ms | 重新调度耗时: 96ms | 删除耗时: 36ms
任务数: 4648 | Tick耗时: 37 ms | 平均 Tick 耗时: 0.0208450704225352 ms

