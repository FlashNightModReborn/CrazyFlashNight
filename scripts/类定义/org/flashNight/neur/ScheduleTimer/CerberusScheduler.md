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
Tick Test - Insertion of 100 tasks took 1 ms
Tick performance for 100 tasks took 1 ms
Average Tick Time per Frame: 0.0099009900990099 ms
Tick performance test for 100 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.0099009900990099 ms

Insertion of 161 tasks took 3 ms
Finding 161 tasks took 0 ms
Rescheduling 161 tasks took 5 ms
Deletion of 161 tasks took 1 ms
Performance test for 161 tasks completed.
Detailed Performance Report:
Insertion Time: 3 ms
Find Time: 0 ms
Reschedule Time: 5 ms
Deletion Time: 1 ms

Starting tick performance test for 161 tasks.
Tick Test - Insertion of 161 tasks took 2 ms
Tick performance for 161 tasks took 1 ms
Average Tick Time per Frame: 0.0163934426229508 ms
Tick performance test for 161 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.0163934426229508 ms

Insertion of 260 tasks took 5 ms
Finding 260 tasks took 0 ms
Rescheduling 260 tasks took 7 ms
Deletion of 260 tasks took 2 ms
Performance test for 260 tasks completed.
Detailed Performance Report:
Insertion Time: 5 ms
Find Time: 0 ms
Reschedule Time: 7 ms
Deletion Time: 2 ms

Starting tick performance test for 260 tasks.
Tick Test - Insertion of 260 tasks took 4 ms
Tick performance for 260 tasks took 1 ms
Average Tick Time per Frame: 0.0101010101010101 ms
Tick performance test for 260 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.0101010101010101 ms

Insertion of 420 tasks took 7 ms
Finding 420 tasks took 2 ms
Rescheduling 420 tasks took 9 ms
Deletion of 420 tasks took 5 ms
Performance test for 420 tasks completed.
Detailed Performance Report:
Insertion Time: 7 ms
Find Time: 2 ms
Reschedule Time: 9 ms
Deletion Time: 5 ms

Starting tick performance test for 420 tasks.
Tick Test - Insertion of 420 tasks took 6 ms
Tick performance for 420 tasks took 1 ms
Average Tick Time per Frame: 0.00625 ms
Tick performance test for 420 tasks completed.
Detailed Tick Performance Report:
Tick Time: 1 ms
Average Tick Time per Frame: 0.00625 ms

Insertion of 679 tasks took 11 ms
Finding 679 tasks took 1 ms
Rescheduling 679 tasks took 17 ms
Deletion of 679 tasks took 7 ms
Performance test for 679 tasks completed.
Detailed Performance Report:
Insertion Time: 11 ms
Find Time: 1 ms
Reschedule Time: 17 ms
Deletion Time: 7 ms

Starting tick performance test for 679 tasks.
Tick Test - Insertion of 679 tasks took 8 ms
Tick performance for 679 tasks took 3 ms
Average Tick Time per Frame: 0.0115830115830116 ms
Tick performance test for 679 tasks completed.
Detailed Tick Performance Report:
Tick Time: 3 ms
Average Tick Time per Frame: 0.0115830115830116 ms

Insertion of 1098 tasks took 19 ms
Finding 1098 tasks took 1 ms
Rescheduling 1098 tasks took 27 ms
Deletion of 1098 tasks took 9 ms
Performance test for 1098 tasks completed.
Detailed Performance Report:
Insertion Time: 19 ms
Find Time: 1 ms
Reschedule Time: 27 ms
Deletion Time: 9 ms

Starting tick performance test for 1098 tasks.
Tick Test - Insertion of 1098 tasks took 15 ms
Tick performance for 1098 tasks took 5 ms
Average Tick Time per Frame: 0.0119331742243437 ms
Tick performance test for 1098 tasks completed.
Detailed Tick Performance Report:
Tick Time: 5 ms
Average Tick Time per Frame: 0.0119331742243437 ms

Insertion of 1776 tasks took 29 ms
Finding 1776 tasks took 3 ms
Rescheduling 1776 tasks took 44 ms
Deletion of 1776 tasks took 16 ms
Performance test for 1776 tasks completed.
Detailed Performance Report:
Insertion Time: 29 ms
Find Time: 3 ms
Reschedule Time: 44 ms
Deletion Time: 16 ms

Starting tick performance test for 1776 tasks.
Tick Test - Insertion of 1776 tasks took 29 ms
Tick performance for 1776 tasks took 7 ms
Average Tick Time per Frame: 0.0103244837758112 ms
Tick performance test for 1776 tasks completed.
Detailed Tick Performance Report:
Tick Time: 7 ms
Average Tick Time per Frame: 0.0103244837758112 ms

Insertion of 2873 tasks took 47 ms
Finding 2873 tasks took 4 ms
Rescheduling 2873 tasks took 70 ms
Deletion of 2873 tasks took 27 ms
Performance test for 2873 tasks completed.
Detailed Performance Report:
Insertion Time: 47 ms
Find Time: 4 ms
Reschedule Time: 70 ms
Deletion Time: 27 ms

Starting tick performance test for 2873 tasks.
Tick Test - Insertion of 2873 tasks took 42 ms
Tick performance for 2873 tasks took 18 ms
Average Tick Time per Frame: 0.01640838650866 ms
Tick performance test for 2873 tasks completed.
Detailed Tick Performance Report:
Tick Time: 18 ms
Average Tick Time per Frame: 0.01640838650866 ms

Insertion of 4648 tasks took 77 ms
Finding 4648 tasks took 7 ms
Rescheduling 4648 tasks took 112 ms
Deletion of 4648 tasks took 45 ms
Performance test for 4648 tasks completed.
Detailed Performance Report:
Insertion Time: 77 ms
Find Time: 7 ms
Reschedule Time: 112 ms
Deletion Time: 45 ms

Starting tick performance test for 4648 tasks.
Tick Test - Insertion of 4648 tasks took 62 ms
Tick performance for 4648 tasks took 47 ms
Average Tick Time per Frame: 0.0264788732394366 ms
Tick performance test for 4648 tasks completed.
Detailed Tick Performance Report:
Tick Time: 47 ms
Average Tick Time per Frame: 0.0264788732394366 ms

Insertion of 7520 tasks took 132 ms
Finding 7520 tasks took 11 ms
Rescheduling 7520 tasks took 193 ms
Deletion of 7520 tasks took 89 ms
Performance test for 7520 tasks completed.
Detailed Performance Report:
Insertion Time: 132 ms
Find Time: 11 ms
Reschedule Time: 193 ms
Deletion Time: 89 ms

Starting tick performance test for 7520 tasks.
Tick Test - Insertion of 7520 tasks took 113 ms
Tick performance for 7520 tasks took 98 ms
Average Tick Time per Frame: 0.0341225626740947 ms
Tick performance test for 7520 tasks completed.
Detailed Tick Performance Report:
Tick Time: 98 ms
Average Tick Time per Frame: 0.0341225626740947 ms

╔════════════════════════════════════════╗
║  所有测试完成                          ║
╚════════════════════════════════════════╝
执行任务: tickPerfTask1660 在帧: 7522
执行任务: tickPerfTask164 在帧: 7522
执行任务: tickPerfTask3190 在帧: 7522
测试完成。
性能测试结果总结:
任务数: 100 | 插入耗时: 2ms | 查找耗时: 0ms | 重新调度耗时: 3ms | 删除耗时: 1ms
任务数: 100 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.0099009900990099 ms
任务数: 161 | 插入耗时: 3ms | 查找耗时: 0ms | 重新调度耗时: 5ms | 删除耗时: 1ms
任务数: 161 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.0163934426229508 ms
任务数: 260 | 插入耗时: 5ms | 查找耗时: 0ms | 重新调度耗时: 7ms | 删除耗时: 2ms
任务数: 260 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.0101010101010101 ms
任务数: 420 | 插入耗时: 7ms | 查找耗时: 2ms | 重新调度耗时: 9ms | 删除耗时: 5ms
任务数: 420 | Tick耗时: 1 ms | 平均 Tick 耗时: 0.00625 ms
任务数: 679 | 插入耗时: 11ms | 查找耗时: 1ms | 重新调度耗时: 17ms | 删除耗时: 7ms
任务数: 679 | Tick耗时: 3 ms | 平均 Tick 耗时: 0.0115830115830116 ms
任务数: 1098 | 插入耗时: 19ms | 查找耗时: 1ms | 重新调度耗时: 27ms | 删除耗时: 9ms
任务数: 1098 | Tick耗时: 5 ms | 平均 Tick 耗时: 0.0119331742243437 ms
任务数: 1776 | 插入耗时: 29ms | 查找耗时: 3ms | 重新调度耗时: 44ms | 删除耗时: 16ms
任务数: 1776 | Tick耗时: 7 ms | 平均 Tick 耗时: 0.0103244837758112 ms
任务数: 2873 | 插入耗时: 47ms | 查找耗时: 4ms | 重新调度耗时: 70ms | 删除耗时: 27ms
任务数: 2873 | Tick耗时: 18 ms | 平均 Tick 耗时: 0.01640838650866 ms
任务数: 4648 | 插入耗时: 77ms | 查找耗时: 7ms | 重新调度耗时: 112ms | 删除耗时: 45ms
任务数: 4648 | Tick耗时: 47 ms | 平均 Tick 耗时: 0.0264788732394366 ms
任务数: 7520 | 插入耗时: 132ms | 查找耗时: 11ms | 重新调度耗时: 193ms | 删除耗时: 89ms
任务数: 7520 | Tick耗时: 98 ms | 平均 Tick 耗时: 0.0341225626740947 ms

