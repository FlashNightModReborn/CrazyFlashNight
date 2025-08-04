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
  测试4: 长延迟环绕测试
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
  测试13: 错误处理测试
任务执行错误: 测试错误
  ✅ testErrorHandling - 通过
  测试14: 资源清理测试
  ✅ testResourceCleanup - 通过
  测试15: 游戏场景模拟
    持续伤害tick
    急速BUFF结束
    持续伤害tick
    持续伤害tick
    火球术冷却完成
  ✅ testGameScenarioSimulation - 通过
  测试16: 重置功能测试
  ✅ testResetFunctionality - 通过

【性能基准测试】
  Add‑Sparse (15000)  总耗时: 121ms  |  净耗时: 121ms
  ✅ benchAddSparse - 通过
  Add‑Dense (15000)  总耗时: 100ms  |  净耗时: 100ms
  ✅ benchAddDense - 通过
  Repeating‑Tasks (5000)  总耗时: 35ms  |  净耗时: 35ms
  ✅ benchRepeatingTasks - 通过
  Task‑Cancellation (2250/7500)  总耗时: 2ms  |  净耗时: 2ms
  ✅ benchTaskCancellation - 通过
  Tick‑Sparse (200f)  总耗时: 0ms  |  净耗时: 0ms
  ✅ benchTickSparse - 通过
  Tick‑Dense (200f×20)  总耗时: 0ms  |  净耗时: 0ms
  ✅ benchTickDense - 通过
  Mixed‑Operations  总耗时: 11ms  |  净耗时: 11ms
  ✅ benchMixedOperations - 通过

【性能测试汇总】
标签	raw(ms)	baseline(ms)	pure(ms)
Mixed‑Operations	11	0	11
Tick‑Dense (200f×20)	0	0	0
Tick‑Sparse (200f)	0	0	0
Task‑Cancellation (2250/7500)	2	0	2
Repeating‑Tasks (5000)	35	0	35
Add‑Dense (15000)	100	0	100
Add‑Sparse (15000)	121	0	121

【测试结果汇总】
通过: 23 个
失败: 0 个
总计: 23 个
🎉 所有测试通过！
────────── 测试结束 ──────────
