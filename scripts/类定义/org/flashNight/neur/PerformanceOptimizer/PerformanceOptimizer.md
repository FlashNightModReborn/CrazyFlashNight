trace(org.flashNight.neur.PerformanceOptimizer.test.PerformanceOptimizerTestSuite.run());


╔══════════════════════════════════════════════════╗
║   PerformanceOptimizer Test Suite                ║
╚══════════════════════════════════════════════════╝

── IntervalSampler ── PASS (8/8, 0ms)
=== IntervalSamplerTest ===
[tick]
  ✓ 倒计时29次不触发，第30次触发
[measure/reset]
  ✓ level0: dt=1s → FPS=30.0
  ✓ dtSec=1.0
  ✓ PID deltaFrames: level3→120
  ✓ resetInterval: frameStartTime更新
  ✓ resetInterval: level2→90帧
  ✓ protection: max(30*1, 30*(1+2))=90
  ✓ protection: max(30*10, 90)=300


── AdaptiveKalmanStage ── PASS (4/4, 0ms)
=== AdaptiveKalmanStageTest ===
[Q scaling]
  ✓ dt=0.5 → Q=0.05
  ✓ dt=0.001 → Q clamp到0.01
  ✓ dt=100 → Q clamp到2.0
[estimate]
  ✓ 估计值向测量值移动（10 < est < 30）


── HysteresisQuantizer ── PASS (26/26, 0ms)
=== HysteresisQuantizerTest ===
[downgrade_2step]
  ✓ 降级第1次：不切换，进入等待
  ✓ 确认计数=1，方向=降级(+1)
  ✓ 降级第2次：达到阈值，切换到1
  ✓ 切换后确认计数归零
  ✓ 候选等于当前：确认状态清空
[upgrade_3step]
  ✓ 升级第1次：不切换，计数=1
  ✓ 升级第2次：不切换（需3次），计数=2
  ✓ 方向=升级(-1)
  ✓ 升级第3次：达到阈值，切换到1
[directionReversal]
  ✓ 升级方向积累2次
  ✓ 方向反转：计数重置为1，方向=降级(+1)
  ✓ 降级第2次（含反转的1次）：达到阈值，切换到3
[clamp]
  ✓ 候选被clamp到minLevel=2（第1次等待）
  ✓ 升级第2次：需3次确认，继续等待
  ✓ 升级第3次：达到阈值，切换到2
[strictEquality]
  ✓ 严格比较: Number(1) !== String('1') 检测为变化
  ✓ Number(1) === Number(1) 不触发变化
[clearConfirmation]
  ✓ process后有待确认
  ✓ clearConfirmation 清空所有状态
  ✓ setConfirmState(2, -1) 精确设置
  ✓ setAwaitingConfirmation(true) 兼容模式：count=1, direction=降级
  ✓ setAwaitingConfirmation(false) 清空
[customThresholds]
  ✓ 自定义阈值：降级=1, 升级=4
  ✓ 降级阈值=1：首次即切换
  ✓ 升级阈值=4：第4次切换
  ✓ 默认阈值：降级=2, 升级=3


── PerformanceActuator ── PASS (47/47, 1ms)
=== PerformanceActuatorTest ===
[apply]
  ✓ L0 maxEffectCount=20
  ✓ L0 maxScreenEffectCount=20
  ✓ L0 isDeathEffect=true
  ✓ L0 面积系数=300000
  ✓ L0 同屏打击数字特效上限=25
  ✓ L0 DeathEffectRenderer启用且不剔除
  ✓ L0 quality恢复预设(HIGH)
  ✓ L0 光照阈值=0.1
  ✓ L0 shellLimit=25
  ✓ L0 发射效果上限=15
  ✓ L0 显示列表继续播放
  ✓ L0 UI动效=true
  ✓ L0 offsetTolerance=10
  ✓ L0 渲染器档位=0
  ✓ L1 maxEffectCount=12
  ✓ L1 maxScreenEffectCount=12
  ✓ L1 isDeathEffect=true
  ✓ L1 面积系数=450000
  ✓ L1 同屏打击数字特效上限=15
  ✓ L1 DeathEffectRenderer启用且剔除
  ✓ L1 quality=MEDIUM(预设非LOW)
  ✓ L1 光照阈值=0.2
  ✓ L1 shellLimit=12
  ✓ L1 发射效果上限=10
  ✓ L1 显示列表继续播放
  ✓ L1 UI动效=true
  ✓ L1 offsetTolerance=30
  ✓ L1 渲染器档位=1
  ✓ L2 maxEffectCount=10
  ✓ L2 isDeathEffect=false
  ✓ L2 面积系数=600000
  ✓ L2 quality=LOW
  ✓ L2 光照阈值=0.5
  ✓ L2 shellLimit=12
  ✓ L2 显示列表暂停播放
  ✓ L2 UI动效=false
  ✓ L2 offsetTolerance=50
  ✓ L2 渲染器档位=2
  ✓ L3 maxEffectCount=0
  ✓ L3 maxScreenEffectCount=5
  ✓ L3 面积系数=3000000
  ✓ L3 光照阈值=1
  ✓ L3 shellLimit=10
  ✓ L3 发射效果上限=0
  ✓ L3 显示列表暂停播放
  ✓ L3 offsetTolerance=80
  ✓ L3 渲染器档位=3


── FPSVisualization ── PASS (4/4, 0ms)
=== FPSVisualizationTest ===
[viz]
  ✓ buffer min/max 合法
  ✓ fpsDiff >= 最小差异5
  ✓ level0 线条颜色=0x00FF00
  ✓ level2 线条颜色=0xFFFF00


── PerformanceScheduler ── PASS (53/53, 5ms)
=== PerformanceSchedulerTest ===
[evaluate]
  ✓ 两次确认后只执行一次切档
  ✓ 低FPS下切到level3（clamp后）
  ✓ scheduler.performanceLevel更新为3
  ✓ 切到level3后采样周期=120帧
[onSceneChanged]
  ✓ performanceLevel重置为0
  ✓ 执行器收到apply(0)
  ✓ PID已重置（无异常抛出）
  ✓ 迟滞确认状态已清除
  ✓ 采样周期重置为30帧（level0）
  ✓ frameStartTime更新为当前时间（>0）
[onSceneChanged_levelCap]
  ✓ onSceneChanged尊重性能等级上限: level=2（非0）
  ✓ 执行器收到apply(2)（非0）
  ✓ 采样周期=90帧（level2: 30*(1+2)）
[setPerformanceLevel]
  ✓ performanceLevel设为2
  ✓ 执行器收到apply(2)
  ✓ quantizer确认状态已清除
  ✓ 保护窗口=150帧（max(150,90)）
  ✓ frameStartTime更新为传入时间
  ✓ 估算帧率=26（30-2*2）
  ✓ 相同等级不重复执行
[presetQuality动态同步]
  ✓ 初始presetQuality=HIGH
  ✓ apply前presetQuality同步为LOW
  ✓ L1 在预设为LOW时 quality=LOW（而非MEDIUM）
[logger]
  ✓ 采样点日志 sample 调用2次
  ✓ PID分量日志 pidDetail 调用2次（与sample同步）
  ✓ 切档日志 levelChanged 调用1次
  ✓ 前馈日志 manualSet 调用1次
  ✓ 场景切换日志 sceneChanged 调用1次
  ✓ sceneChanged快照: level=2（重置前）
  ✓ sceneChanged快照: targetFPS=26
  ✓ sceneChanged快照: quality=HIGH
[pidDetail+tag]
  ✓ setLoggerTag设置标签
  ✓ sample携带tag='OL:test'
  ✓ pidDetail被调用
  ✓ 纯比例PID: iTerm=0
  ✓ 纯比例PID: dTerm=0
  ✓ P+I+D=pidOutput（冗余校验通过）
  ✓ setLoggerTag(null)清除标签
  ✓ 无logger时getLoggerTag返回null
  ✓ PIDController.getLastP()可用
  ✓ PIDController.getLastI()可用
  ✓ PIDController.getLastD()可用
  ✓ reset后getLastP()=0
  ✓ reset后getLastI()=0
  ✓ reset后getLastD()=0
[forceLevel]
  ✓ forceLevel(2)设置等级为2
  ✓ 执行器收到apply(2)
  ✓ 采样间隔=90帧（level2），无保护窗口
  ✓ PID已重置（无异常抛出）
  ✓ 迟滞确认状态已清除
  ✓ forceLevel(-1)被clamp到0
  ✓ forceLevel(5)被clamp到3
  ✓ forceLevel(60帧) vs setPerformanceLevel(150帧保护窗口)


── PerformanceHotPathBenchmark ── BENCH (2529ms)
=== PerformanceHotPathBenchmark ===
  note: same-machine comparison only
  IntervalSampler.tick: 159 ms / 100000 (1.59 us/op, checksum=0)
  IntervalSampler.measure+resetInterval: 67 ms / 20000 (3.35 us/op, checksum=83601500)
  AdaptiveKalmanStage.filter: 150 ms / 20000 (7.5 us/op, checksum=459997.492)
  HysteresisQuantizer.process: 457 ms / 100000 (4.57 us/op, checksum=200000)
  PerformanceActuator.apply: 313 ms / 20000 (15.65 us/op, checksum=850000)
  FPSVisualization.updateData+drawCurve: 920 ms / 5000 (184 us/op, checksum=45023)
  PerformanceScheduler.evaluate(fast-path): 327 ms / 100000 (3.27 us/op, checksum=5000050000)
  PerformanceScheduler.evaluate(sample-path): 133 ms / 5000 (26.6 us/op, checksum=0)


══════════════════════════════════════════════════
ALL PASSED
  Total : 142  |  Pass : 142  |  Fail : 0  |  Time : 2535 ms
══════════════════════════════════════════════════

