import org.flashNight.neur.ScheduleTimer.*;
// 运行测试
var tester:CooldownWheelTests = new CooldownWheelTests();
tester.runAllTests();




────────── CooldownWheel 单元&性能测试 开始 ──────────

【功能正确性测试】
  测试1: 单技能冷却
    添加延迟5帧的任务，开始tick循环...
    第1帧 tick后，executed=false
    第2帧 tick后，executed=false
    第3帧 tick后，executed=false
    第4帧 tick后，executed=false
    任务执行！
    第5帧 tick后，executed=true
  ✅ testSingleSkillCooldown - 通过
  测试2: 多技能并发冷却
  ✅ testMultipleSkillsConcurrent - 通过
  测试3: 立即执行测试
    添加delay=0的任务
    添加delay=-5的任务
    添加delay=-1的任务
    执行第1次tick...
    delay=-1任务执行，negativeCount=1
    delay=-5任务执行，negativeCount=2
    delay=0任务执行，zeroCount=1
    tick后：zeroCount=1, negativeCount=2
  ✅ testImmediateExecution - 通过
  测试4: 长延迟环绕测试
  ✅ testLongDelayWrapping - 通过
  测试5: 负延迟处理
  ✅ testNegativeDelay - 通过
  测试6: 零帧处理
  ✅ testZeroFrameHandling - 通过
  测试7: 性能压力测试
  ✅ testPerformanceStress - 通过
  测试8: 时间轮完整性测试
  ✅ testTimeWheelIntegrity - 通过
  测试9: 游戏场景模拟
    初始化技能冷却时间：火球术30帧, 治疗术60帧, 终极技能200帧
    第29次tick后状态检查：火球术ready=false (应该为false)
    火球术就绪！
    第30次tick后状态检查：火球术ready=true (应该为true)
    治疗术就绪！
    第60次tick后状态检查：治疗术ready=true (应该为true)
    第61次tick后状态检查：终极技能ready=false (应该为false)
  ✅ testGameScenarios - 通过
  测试10: 边界情况测试
  ✅ testEdgeCases - 通过
  测试11: 重置功能测试
    添加延迟5帧的任务
    执行2次tick...
    2次tick后，executed=false
    执行reset()...
    reset后继续执行3次tick...
    3次tick后，executed=false
  ✅ testResetFunctionality - 通过

【性能基准测试】
  Add‑Sparse (20000)  总耗时: 69ms  |  扣除基线: 69ms
  ✅ testAddSparse - 通过
  Add‑Dense (20000)  总耗时: 72ms  |  扣除基线: 72ms
  ✅ testAddDense - 通过
  Tick‑Sparse (240f)  总耗时: 0ms  |  扣除基线: 0ms
  ✅ testTickSparse - 通过
  Tick‑Dense‑8x (240f)  总耗时: 0ms  |  扣除基线: 0ms
  ✅ testTickDense8x - 通过
  Tick‑Dense‑32x (240f)  总耗时: 0ms  |  扣除基线: 0ms
  ✅ testTickDense32x - 通过

【性能测试汇总】
标签	raw(ms)	baseline(ms)	pure(ms)	per10k(ms)
Tick‑Dense‑32x (240f)	0	0	0	0.000
Tick‑Dense‑8x (240f)	0	0	0	0.000
Tick‑Sparse (240f)	0	0	0	0.000
Add‑Dense (20000)	72	0	72	36.000
Add‑Sparse (20000)	69	0	69	34.500

【测试结果汇总】
通过: 16 个
失败: 0 个
总计: 16 个
🎉 所有功能测试通过！
────────── 测试结束 ──────────