# 性能调度系统重构计划 - PerformanceScheduler

## 一、上次重构失败的根因（必须规避）

上次重构（`PerformanceOptimizer/` 目录 6 个文件）失败的核心原因：**改了算法，不是改了结构**。

| 环节 | 工作版本 | 失败版本 | 破坏点 |
|------|----------|----------|--------|
| **滤波器** | `SimpleKalmanFilter1D` + 自适应Q | EMA（`FPSFilter`） | 完全不同的算法 |
| **PID参数** | kp=0.2, ki=0.5, kd=**-30**（XML加载） | kp=0.6, ki=0.05, kd=0.3（硬编码） | 差了数量级，丢失负微分 |
| **PID时间步** | 传帧数(30-120)，积分放大/微分压制 | 无deltaTime概念 | 丢失关键稳定性机制 |
| **等级判定** | `Math.round(pidOutput)` 直接映射 | Sigmoid+magnitude+stepSize | 完全不同的映射 |
| **采样周期** | `帧率×(1+等级)` = 30/60/90/120 | 固定30帧，后乘0.5 | 自适应采样失效 |
| **前馈接口** | 手动设置/降低/提升性能等级 | 不存在 | 外部调用方断裂 |
| **可视化** | SlidingWindowBuffer+曲线绘制 | 不存在 | UI丢失 |

**本次原则：Copy-paste 提取，不做任何算法改动。**

---

## 二、新类结构（6个类，每个对应控制理论概念）

```
_root.帧计时器
    └── scheduler: PerformanceScheduler （门面/协调器）
            ├── _sampler:   IntervalSampler        ← 变周期采样器
            ├── _kalman:    AdaptiveKalmanStage     ← 自适应卡尔曼滤波（包装现有类）
            ├── _pid:       PIDController           ← 现有类，不重写
            ├── _quantizer: HysteresisQuantizer     ← 量化器+施密特触发器
            ├── _actuator:  PerformanceActuator     ← 执行器/作动器
            └── _viz:       FPSVisualization        ← 可视化/仪表盘
```

---

## 三、逐类设计

### 3.1 `IntervalSampler` — 变周期采样器

**文件:** `org/flashNight/neur/PerformanceOptimizer/IntervalSampler.as`

**控制理论:** 时间尺度分离 (Time-Scale Separation)

**构造:** `IntervalSampler(frameRate:Number)`

**方法:**
```
tick():Boolean                    — 每帧调用，倒计时归零返回true
measure(currentTime, level):Number — 计算区间平均FPS（原公式不变）
getDeltaTimeSec(currentTime):Number — 返回dt秒（给Kalman用）
getPIDDeltaTimeFrames(level):Number — 返回帧数（故意的单位不一致，给PID用）
resetInterval(currentTime, level)  — 重置测量起点和下次间隔
setProtectionWindow(currentTime, holdSec, level) — 前馈保护窗口
```

**提取自:** `通信_fs_帧计时器.as` 行 714, 737-739, 749, 841, 927-928, 1678-1691

---

### 3.2 `AdaptiveKalmanStage` — 自适应卡尔曼滤波

**文件:** `org/flashNight/neur/PerformanceOptimizer/AdaptiveKalmanStage.as`

**控制理论:** 自适应过程噪声的状态估计器

**构造:** `AdaptiveKalmanStage(kalman:SimpleKalmanFilter1D, baseQ, qMin, qMax)`

**默认（与工作版本一致）：**
- `kalman = new SimpleKalmanFilter1D(30, 0.5, 1)`（注意：这里的 `0.5` 是 **初始过程噪声Q**，不是误差协方差P）
- `kalman.reset(30, 1)`（误差协方差P初值=1）
- `baseQ=0.1, qMin=0.01, qMax=2.0`（与 `通信_fs_帧计时器.as` 相同）

**方法:**
```
filter(measuredFPS, dtSeconds):Number — Q=baseQ×dt, predict+update
reset(initialEst, initialErrCov)      — 场景切换时重置
getFilter():SimpleKalmanFilter1D      — 暴露底层对象（测试/日志）
```

**组合:** `SimpleKalmanFilter1D`（现有类，不修改）

**提取自:** 行 229, 775-796, 1412

---

### 3.3 `HysteresisQuantizer` — 迟滞量化器

**文件:** `org/flashNight/neur/PerformanceOptimizer/HysteresisQuantizer.as`

**控制理论:** 量化器 + 施密特触发器（驻留控制）

**构造:** `HysteresisQuantizer(minLevel, maxLevel)`
- 默认: `(0, 3)`

**方法:**
```
process(pidOutput, currentLevel):Object  — 返回 {levelChanged:Boolean, newLevel:Number}
  内部逻辑: Math.round → clamp → 连续2次“候选 != 当前”才执行（与原代码一致：不记忆上一次候选）
clearConfirmation():Void                 — 前馈时清除迟滞状态
setMinLevel(level) / getMinLevel()       — 性能等级上限（存档系统用）
```

**提取自:** 行 856-910, 1655, 1673

---

### 3.4 `PerformanceActuator` — 执行器

**文件:** `org/flashNight/neur/PerformanceOptimizer/PerformanceActuator.as`

**控制理论:** 作动器/植物输入映射器

**构造:** `PerformanceActuator(host:Object, presetQuality:String, env:Object)`

**方法:**
```
apply(level:Number):Void  — 完整的4档switch，逐字复制原代码
  操作: EffectSystem/面积系数/画质/弹壳/天气阈值/显示列表/UI动效/渲染器
```

**注:** 保留对 `_root.帧计时器.offsetTolerance` 的写入（摄像机系统读取）

**提取自:** 行 995-1122（整个switch语句 + 渲染器调用）

---

### 3.5 `FPSVisualization` — 可视化

**文件:** `org/flashNight/neur/PerformanceOptimizer/FPSVisualization.as`

**控制理论:** 观测器输出/仪表盘

**构造:** `FPSVisualization(bufferLength:Number, frameRate:Number)`
- 默认: `(24, 30)`

**方法:**
```
updateData(currentFPS):Void                    — 更新帧率数据（原 更新帧率数据）
drawCurve(canvas:MovieClip, level:Number):Void — 绘制帧率曲线（原 绘制帧率曲线）
getBuffer():SlidingWindowBuffer                — 暴露缓冲区
```

**组合:** `SlidingWindowBuffer`（现有类，不修改）

**提取自:** 行 170-181, 527-638

---

### 3.6 `PerformanceScheduler` — 门面/协调器

**文件:** `org/flashNight/neur/PerformanceOptimizer/PerformanceScheduler.as`

**控制理论:** 闭环反馈 + 前馈调度系统

**构造:** `PerformanceScheduler(host, frameRate, targetFPS, presetQuality, env, pid)`
- 推荐：`new PerformanceScheduler(this, this.帧率, 26, _root._quality, {root:_root}, pid)`

**状态所有权（v2 内化）：**
scheduler 完全拥有以下状态，不再回写到 host：
- `_performanceLevel` — 当前性能等级
- `_actualFPS` — 当前测量帧率
- `_pid` — PID控制器实例（构造注入 + PIDFactory 异步替换）
- `_presetQuality` — 用户预设画质
- 采样器/滤波器/量化器的全部内部状态

host 上仅保留：`性能等级上限`（存档系统读写）、`offsetTolerance`（摄像机读取，由 Actuator 写入）

**反馈控制方法:**
```
evaluate():Void — 每帧调用的主控制循环
  流程: tick→measure→kalman→pid→quantize→confirm→execute→reset→draw
```

**前馈控制方法:**
```
setPerformanceLevel(level, holdSec):Void — 绝对前馈（原 手动设置性能等级）
decreaseLevel(steps, holdSec):Void      — 相对降档（原 降低性能等级）
increaseLevel(steps, holdSec):Void      — 相对升档（原 提升性能等级）
```

**场景切换:**
```
onSceneChanged():Void — kalmanStage.reset + pid.reset + quantizer.clear + apply(0) + _performanceLevel=0 + sampler.resetInterval
```

**访问器:**
```
getPerformanceLevel() / getActualFPS()     — 外部读取性能状态
getPID() / setPID(pid)                     — PIDControllerFactory 异步回调用
setPresetQuality(q) / getPresetQuality()   — 运行时画质变更
getQuantizer()                             — 性能等级上限同步用
getSampler() / getKalmanStage()            — 测试/日志用
```

---

## 四、集成方式（零外部API变更，固化单路径）

### 4.1 初始化接入

在 `初始化任务栈()` 中创建 PID 并注入 `scheduler`（无热切换开关）：
```actionscript
var pid:PIDController = new PIDController(0.2, 0.5, -30, 3, 0.2);
var pidFactory:PIDControllerFactory = PIDControllerFactory.getInstance();
function onPIDSuccess(newPID:PIDController):Void {
    _root.帧计时器.scheduler.setPID(newPID);
}
pidFactory.createPIDController(onPIDSuccess, onPIDFailure);

this.scheduler = new PerformanceScheduler(this, this.帧率, 26, _root._quality, {root:_root}, pid);
// PID 构造注入，PIDControllerFactory 异步加载后通过 scheduler.setPID() 替换
```

### 4.2 API兼容层（保持外部调用点不变）

`通信_fs_帧计时器.as` 中保留原函数签名，但实现固化为直接委托到 `scheduler`：

- `_root.帧计时器.性能评估优化` → `scheduler.evaluate()`
- `_root.帧计时器.执行性能调整` → `scheduler.getActuator().apply(level)`
- `_root.帧计时器.手动设置性能等级` → `scheduler.setPerformanceLevel(...)`
- `_root.帧计时器.降低性能等级` → `scheduler.decreaseLevel(...)`
- `_root.帧计时器.提升性能等级` → `scheduler.increaseLevel(...)`

### 4.3 状态所有权（v2 内化模型）

**scheduler 内部持有**（不回写到 host）：
- `performanceLevel` — 通过 `scheduler.getPerformanceLevel()` 读取
- `actualFPS` — 通过 `scheduler.getActualFPS()` 读取
- `pid` — 通过 `scheduler.setPID()/getPID()` 管理
- `presetQuality` — 通过 `scheduler.setPresetQuality()` 管理
- `kalmanFilter / sampler / quantizer` — 全部内化

**host 上仅保留两个 LIVE 字段**：
- `_root.帧计时器.性能等级上限` — 存档系统读写；每次 `evaluate()` 同步到 `HysteresisQuantizer`
- `_root.帧计时器.offsetTolerance` — 由 `PerformanceActuator` 写入，摄像机读取

**外部读取性能等级的调用方需改用 `scheduler.getPerformanceLevel()`**：
- 天气系统：`this.scheduler.getPerformanceLevel()` 替代原 `this.性能等级`
- UI显示：FPS 数字由 `evaluate()` 直接写入 `root.玩家信息界面`

`预设画质` 不再每帧同步：仅在 `apply()` 之前同步到 `PerformanceActuator`。

### 4.4 可插拔性能日志（默认关闭，零开销）

`PerformanceScheduler` 支持挂载日志器（默认 `null`），用于离线分析与后续自优化模块：
- `scheduler.setLogger(logger)` / `scheduler.getLogger()`
- 内置实现：`org.flashNight.neur.PerformanceOptimizer.PerformanceLogger`（环形缓冲区，结构化记录）

在 `_root.帧计时器` 侧提供轻量包装：
- `_root.帧计时器.启用性能日志(capacity)`
- `_root.帧计时器.禁用性能日志()`
- `_root.帧计时器.导出性能日志CSV(maxRows)`

### 4.5 外部调用方验证清单

| 调用方 | 文件 | API | 变更 |
|--------|------|-----|------|
| 关卡事件 | StageEvent.as | 手动设置/降低/提升性能等级 | 无需改动 |
| 存档系统 | 通信_lsy_原版存档系统.as | 性能等级上限 (读/写) | 无需改动 |
| 摄像机 | HorizontalScroller.as | offsetTolerance (读) | 无需改动 |
| 天气系统 | 帧计时器.定期更新天气 | 性能等级 (读) | `this.scheduler.getPerformanceLevel()` |
| 场景切换 | EventBus SceneChanged | reset逻辑 | 固化为 scheduler.onSceneChanged() |

---

## 五、实施步骤（严格顺序）

### Step 1: 创建新类文件（不接入）
- 创建6个新类文件
- 每个类的方法体从工作代码逐字复制
- （可选）先不接入，单独编译验证类可用

### Step 2: 编写单元测试
- 为每个类编写独立测试（见下方测试用例）
- 通过注入模拟输入验证输出
- （可选）先不接入，先把单测跑通

### Step 3: 接入（固化单路径）
- 在 `通信_fs_帧计时器.as` 中创建 `scheduler` 实例
- 原有函数入口改为直接委托到 scheduler（保持外部API不变）
- 使用版本控制作为回滚机制：上线验证以场景/负载维度逐步扩大覆盖

### Step 4: 切换完成后删除旧代码
- 确认所有场景测试通过
- 若确定不再回退：移除旧函数体（或保留但不再调用）
- 删除失败重构的6个旧文件

### Step 5: 添加优化钩子（不改控制行为）
- 添加可选的日志记录器（`PerformanceLogger` + `scheduler.setLogger`）
- 添加增益调度表接口（注释状态）
- 添加执行器参数表外置接口

---

## 六、测试方案

### 6.1 各模块单元测试要点

**IntervalSampler:**
- 倒计时29次返回false，第30次返回true
- FPS计算公式验证：已知dt和level，验证输出
- getPIDDeltaTimeFrames: level0→30, level3→120

**AdaptiveKalmanStage:**
- 短dt(0.5s)时滤波值更接近上次估计（信模型）
- 长dt(5s)时滤波值更接近测量值（信测量）
- reset后estimate=30

**HysteresisQuantizer:**
- 首次检测到变化→不触发
- 连续第二次→触发
- 等级相同→重置确认状态
- clamp到[minLevel, 3]

**PerformanceActuator:**
- 每档的15个参数值与原代码逐字一致

**FPSVisualization:**
- 插入数据后buffer内容正确
- min/max/average计算正确

### 6.2 回归测试（A/B对比）

在原代码中添加日志记录：
```
{timestamp, rawFPS, denoisedFPS, pidOutput, candidateLevel, confirmedLevel}
```

将相同的 `(timestamp, rawFPS)` 序列喂入新系统，验证所有中间值和最终输出完全一致。

---

## 七、文件清单

### 新建（6个类 + 测试套件）
```
org/flashNight/neur/PerformanceOptimizer/
    IntervalSampler.as          ← 变周期采样器
    AdaptiveKalmanStage.as      ← 自适应卡尔曼
    HysteresisQuantizer.as      ← 迟滞量化器
    PerformanceActuator.as      ← 执行器
    FPSVisualization.as         ← 可视化
    PerformanceScheduler.as     ← 门面协调器
    test/
        PerformanceOptimizerTestSuite.as
        IntervalSamplerTest.as
        AdaptiveKalmanStageTest.as
        HysteresisQuantizerTest.as
        PerformanceActuatorTest.as
        FPSVisualizationTest.as
        PerformanceSchedulerTest.as
```

### 复用（不修改）
```
org/flashNight/neur/Controller/
    SimpleKalmanFilter1D.as     ← 由 AdaptiveKalmanStage 组合
    PIDController.as            ← 由 PerformanceScheduler 组合
    PIDControllerFactory.as     ← 初始化时异步加载
org/flashNight/naki/DataStructures/
    SlidingWindowBuffer.as      ← 由 FPSVisualization 组合
config/
    PIDControllerConfig.xml     ← PID参数配置
```

### 修改
```
scripts/通信/通信_fs_帧计时器.as  ← 固化单路径接入，状态内化到 scheduler
```

### 删除（失败的旧重构）
```
org/flashNight/neur/PerformanceOptimizer/
    FrameProbe.as               ← 错误的算法
    FPSFilter.as                ← EMA替代了Kalman
    PerformanceController.as    ← 错误的PID参数
    PerformanceAction.as        ← 不必要的DTO
    QualityApplier.as           ← 多余的cooldown/stepSize
    PerformanceOptimizer.as     ← 错误的编排
```

---

## 八、行为等价性验证清单

| 项目 | 工作版本的值 | 新代码必须产出 |
|------|-------------|---------------|
| Level 0 采样间隔 | 30帧 | 30帧 |
| Level 3 采样间隔 | 120帧 | 120帧 |
| FPS公式 | `ceil(帧率*(1+lv)*10000/dt)/10` | 完全一致 |
| Kalman初态 | est=30, P=1, Q_init=0.5, R=1 | 完全一致 |
| 自适应Q | `0.1*dt`, clamp [0.01, 2.0] | 完全一致 |
| PID参数 | kp=0.2, ki=0.5, kd=-30 | 完全一致（XML加载） |
| PID deltaTime | 帧数(30-120)，不是秒 | 帧数(30-120) |
| 量化 | `round(pidOutput)`, clamp [上限, 3] | 完全一致 |
| 迟滞 | 布尔确认，连续2次 | 完全一致 |
| 执行器参数 | 每档15个参数，精确值 | 逐字一致 |
| 前馈保护窗口 | `max(帧率*holdSec, 帧率*(1+level))` | 完全一致 |
| 场景切换 | `kalman.reset(30,1); PID.reset(); apply(0)` | 增强版：kalmanStage.reset + pid.reset + quantizer.clear + apply(0) + _performanceLevel=0 + sampler.resetInterval |
