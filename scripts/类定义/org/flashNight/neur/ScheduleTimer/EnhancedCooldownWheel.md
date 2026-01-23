import org.flashNight.neur.ScheduleTimer.*;
// 运行测试
var tester:EnhancedCooldownWheelTests = new EnhancedCooldownWheelTests();
tester.runAllTests();


────────── EnhancedCooldownWheel 测试套件开始 ──────────

【功能正确性测试】
  测试1: 基础兼容性
    添加延迟5帧的任务...
    兼容性任务执行！
  ✅ testBasicCompatibility - 通过
  测试2: addDelayedTask方法
  ✅ testAddDelayedTask - 通过
  测试3: 立即执行测试
  ✅ testImmediateExecution - 通过
  测试4: 长延迟环绕行为验证（契约行为）
    任务在第 71 帧执行（契约：200 帧被回环）
  ✅ testLongDelayWrapping - 通过
  测试5: 重复任务测试
    添加重复3次的任务，间隔100ms...
    重复任务执行第1次
    重复任务执行第2次
    重复任务执行第3次
  ✅ testRepeatingTasks - 通过
  测试6: 任务取消测试
    添加300ms延迟任务，任务ID=1
    取消任务...
  ✅ testTaskCancellation - 通过
  测试7: 参数传递测试
  ✅ testParameterPassing - 通过
  测试8: 任务ID管理测试
  ✅ testTaskIdManagement - 通过
  测试9: 帧计时器兼容性测试
    模拟渐隐任务，间隔100ms，重复5次...
    渐隐回调执行，cycleCount=1
    渐隐回调执行，cycleCount=2
    渐隐回调执行，cycleCount=3
    渐隐回调执行，cycleCount=4
    渐隐回调执行，cycleCount=5
  ✅ testFrameTimerCompatibility - 通过
  测试10: 混合任务类型测试
  ✅ testMixedTaskTypes - 通过
  测试11: 大量取消测试
  ✅ testMassiveCancellation - 通过
  测试12: 重复任务限制测试
  ✅ testRepeatingTaskLimits - 通过
  测试13: 任务执行顺序测试
  ✅ testErrorHandling - 通过
  测试14: 资源清理测试
  ✅ testResourceCleanup - 通过
  测试15: 游戏场景模拟
    急速BUFF结束
    持续伤害tick
    持续伤害tick
    持续伤害tick
    火球术冷却完成
  ✅ testGameScenarioSimulation - 通过
  测试16: 重置功能测试
  ✅ testResetFunctionality - 通过

【v1.3 生命周期 API 测试】
  测试 v1.3-1: addOrUpdateTask 基本功能
  ✅ testAddOrUpdateTask_Basic - 通过
  测试 v1.3-2: addOrUpdateTask 替换旧任务
  ✅ testAddOrUpdateTask_Replace - 通过
  测试 v1.3-3: removeTaskByLabel 基本功能
  ✅ testRemoveTaskByLabel_Basic - 通过
  测试 v1.3-4: removeTaskByLabel 任务不存在
  ✅ testRemoveTaskByLabel_NotExist - 通过
  测试 v1.3-5: 任务完成后 taskLabel 自动清理
  ✅ testTaskLabelAutoCleanup - 通过
  测试 v1.3-6: 重复任务带标签
  ✅ testRepeatingTaskWithLabel - 通过
  测试 v1.3-7: 同一对象多个标签
  ✅ testMultipleLabelsOnSameObject - 通过
  测试 v1.3-8: 模拟 ShootCore 射击后摇场景
  ✅ testShootCoreScenario - 通过

【v1.8 Never-Early 修复测试】
  测试 v1.8: Never-Early ceiling bit-op
  每帧毫秒 = 33.3333333333333
  Never-Early ceiling bit-op: 全部验证通过
  ✅ testNeverEarlyCeilBitOp_v1_8 - 通过

【性能基准测试】
  Add‑Sparse (15000)  总耗时: 943ms  |  净耗时: 943ms
  ✅ benchAddSparse - 通过
  Add‑Dense (15000)  总耗时: 2553ms  |  净耗时: 2553ms
  ✅ benchAddDense - 通过
  Repeating‑Tasks (5000)  总耗时: 441ms  |  净耗时: 441ms
  ✅ benchRepeatingTasks - 通过
  Task‑Cancellation (2250/7500)  总耗时: 4ms  |  净耗时: 4ms
  ✅ benchTaskCancellation - 通过
  Tick‑Sparse (200f)  总耗时: 0ms  |  净耗时: 0ms
  ✅ benchTickSparse - 通过
  Tick‑Dense (200f×20)  总耗时: 0ms  |  净耗时: 0ms
  ✅ benchTickDense - 通过
  Mixed‑Operations  总耗时: 82ms  |  净耗时: 82ms
  ✅ benchMixedOperations - 通过

【性能测试汇总】
标签	raw(ms)	baseline(ms)	pure(ms)
Mixed‑Operations	82	0	82
Tick‑Dense (200f×20)	0	0	0
Tick‑Sparse (200f)	0	0	0
Task‑Cancellation (2250/7500)	4	0	4
Repeating‑Tasks (5000)	441	0	441
Add‑Dense (15000)	2553	0	2553
Add‑Sparse (15000)	943	0	943

【测试结果汇总】
通过: 32 个
失败: 0 个
总计: 32 个
🎉 所有测试通过！
────────── 测试结束 ──────────
