trace(org.flashNight.neur.PerformanceOptimizer.test.PerformanceOptimizerTestSuite.run());


╔══════════════════════════════════════════════════╗
║   PerformanceOptimizer Test Suite                ║
╚══════════════════════════════════════════════════╝

── IntervalSampler ── PASS (8/8, 1ms)
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


── HysteresisQuantizer ── PASS (8/8, 0ms)
=== HysteresisQuantizerTest ===
[confirm]
  ✓ 第一次检测到变化：不切换，进入等待
  ✓ 第二次检测到变化：执行切换到1
  ✓ 候选等于当前：确认状态清空
[clamp]
  ✓ 候选被clamp到minLevel=2（第一次等待）
  ✓ 第二次确认：切换到2
  ✓ clearConfirmation清空状态
[strictEquality]
  ✓ 严格比较: Number(1) !== String('1') 检测为变化
  ✓ Number(1) === Number(1) 不触发变化


── PerformanceActuator ── PASS (41/41, 1ms)
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
  ✓ L1 maxEffectCount=15
  ✓ L1 面积系数=450000
  ✓ L1 quality=MEDIUM(预设非LOW)
  ✓ L1 光照阈值=0.2
  ✓ L1 shellLimit=18
  ✓ L1 显示列表继续播放
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


── FPSVisualization ── PASS (4/4, 1ms)
=== FPSVisualizationTest ===
[viz]
  ✓ buffer min/max 合法
  ✓ fpsDiff >= 最小差异5
  ✓ level0 线条颜色=0x00FF00
  ✓ level2 线条颜色=0xFFFF00


── PerformanceScheduler ── PASS (22/22, 2ms)
=== PerformanceSchedulerTest ===
[evaluate]
  ✓ 两次确认后只执行一次切档
  ✓ 低FPS下切到level3（clamp后）
  ✓ host.性能等级更新为3
  ✓ 切到level3后采样周期=120帧
[onSceneChanged]
  ✓ host.性能等级重置为0
  ✓ 执行器收到apply(0)
  ✓ PID已重置（无异常抛出）
  ✓ 迟滞确认状态已清除
  ✓ host.awaitConfirmation已清除
  ✓ 采样周期重置为30帧（level0）
  ✓ frameStartTime更新为当前时间（>0）
  ✓ kalmanStage与host共享同一滤波器实例
[setPerformanceLevel]
  ✓ host.性能等级设为2
  ✓ 执行器收到apply(2)
  ✓ 迟滞状态已清除
  ✓ quantizer确认状态已清除
  ✓ 保护窗口=150帧（max(150,90)）
  ✓ frameStartTime更新为传入时间
  ✓ 估算帧率=26（30-2*2）
  ✓ 相同等级不重复执行
[presetQuality动态同步]
  ✓ 初始presetQuality=HIGH
  ✓ evaluate后presetQuality同步为MEDIUM


══════════════════════════════════════════════════
ALL PASSED
  Total : 87  |  Pass : 87  |  Fail : 0  |  Time : 5 ms
══════════════════════════════════════════════════

