# 性能自适应子系统 — 重构计划书

（ActionScript 2 / 帧计时器模块）

---

## 0 目标纲要

| 目标            | 说明                                          |
| ------------- | ------------------------------------------- |
| **高内聚 / 低耦合** | 把 *采集‑平滑‑评估‑执行* 全链路封装，`_root.帧计时器` 仅保留调度职责。 |
| **可测试 / 可插拔** | 任意阶段可替换算法并做单元或离线验证。                         |
| **可横向扩展**     | 性能策略未来可同时管控音效复杂度、AI 更新频率等，而不改核心逻辑。          |
| **一步可落地**     | 提供完整文件结构、类骨架、集成钩子与回滚方案；正常情况下 ≈2‑3 人/日 可完成。  |

---

## 1 最终架构 & 职责

```
_root.帧计时器   ──┐  (EnterFrame / SceneChanged)
                   │  update() / reset()
                   ▼
┌──────────────────────────────┐
│ PerformanceOptimizer (门面) │
└─┬──────────────┬────────────┘
  │              │
  ▼              ▼
FrameProbe    FPSFilter
 (采集)        (平滑)         ──► smoothFPS
                                  │
                                  ▼
                           PerformanceController
                                  │    ▲
                                  │ DTO│
                                  ▼    │
                            PerformanceAction
                                  │
                                  ▼
                           QualityApplier
                           (具体执行)
```

### 1.1 数据传输对象（DTO）

```actionscript
class PerformanceAction {
    public var trend:String;     // "UP"|"DOWN"|"STABLE"
    public var magnitude:Number; // 0–1, 建议归一化
    function PerformanceAction(t:String, m:Number) {
        trend = t; magnitude = m;
    }
}
```

> **解释**
>
> * `trend` 仅表示“性能压力趋势”。
> * `magnitude` 表示强度（PID 误差经 Sigmoid/Clamp 到 0–1）。
> * `QualityApplier` 决定这一强度如何映射到 `_quality`、粒子数量、LOD 表等。

---

## 2 文件结构

```
/org/flashNight/neur/
│─ PerformanceOptimizer.as     （门面 + 组合四子模块）
│─ FrameProbe.as               （采集）
│─ FPSFilter.as                （平滑）
│─ PerformanceController.as    （PID / 策略）
│─ PerformanceAction.as        （DTO）
│─ QualityApplier.as           （执行）
└─ tests/                      （可选，脚本化单元测试）
```

> **AS2 特殊说明**
>
> * 所有类须放在 `org.flashNight.neur.PerformanceOptimizer.*`

---

## 3 关键类骨架（可直接复制）

### 3.1 `FrameProbe.as`

```actionscript
class org.flashNight.neur.PerformanceOptimizer.FrameProbe {
    private var _lastTime:Number;
    function FrameProbe() { _lastTime = getTimer(); }
    public function capture():Number {
        var now:Number = getTimer();
        var fps:Number = 1000 / (now - _lastTime);
        _lastTime = now;
        return fps;
    }
    public function reset():Void { _lastTime = getTimer(); }
}
```

### 3.2 `FPSFilter.as`

```actionscript
class org.flashNight.neur.PerformanceOptimizer.FPSFilter {
    private var _alpha:Number = 0.15;   // EMA 系数
    private var _smooth:Number = 30;    // 初值
    public function process(raw:Number):Number {
        _smooth = _alpha * raw + (1 - _alpha) * _smooth;
        return _smooth;
    }
    public function reset():Void { _smooth = 30; }
}
```

### 3.3 `PerformanceController.as`

```actionscript
class org.flashNight.neur.PerformanceOptimizer.PerformanceController {
    private var _target:Number;
    private var kp:Number = 0.6, ki:Number = 0.05, kd:Number = 0.3;
    private var _prevErr:Number = 0, _integral:Number = 0;
    function PerformanceController(target:Number) { _target = target; }
    public function compute(fps:Number):PerformanceAction {
        var err:Number = _target - fps;
        _integral += err;
        var deriv:Number = err - _prevErr;
        _prevErr = err;
        var output:Number = kp*err + ki*_integral + kd*deriv; // >0 表示性能不足
        // Sigmoid 压缩到 -1~1
        var mag:Number = 1 / (1 + Math.exp(-output)) * 2 - 1;
        var trend:String = mag > 0.05 ? "UP" : (mag < -0.05 ? "DOWN" : "STABLE");
        return new PerformanceAction(trend, Math.abs(mag));
    }
    public function reset():Void { _prevErr = _integral = 0; }
}
```

### 3.4 `QualityApplier.as`

```actionscript
class org.flashNight.neur.PerformanceOptimizer.QualityApplier {
    private var _perfLevel:Number = 2;          // 0=低 1=中 2=高
    private var _min:Number = 0, _max:Number = 2;
    function apply(action:PerformanceAction):Void {
        if(action.trend == "UP")   _perfLevel = Math.max(_min,  _perfLevel - action.magnitude);
        if(action.trend == "DOWN") _perfLevel = Math.min(_max,  _perfLevel + action.magnitude);
        _perfLevel = Math.round(_perfLevel);    // 离散化

        // === 映射到游戏具体设置 ===
        _quality = _perfLevel;                  // Flash 全局画质
        _root.粒子系统开关 = (_perfLevel >= 1);
        // …可再挂更多 LOD/阴影/后效
    }
    public function reset():Void { _perfLevel = 2; }
}
```

### 3.5 `PerformanceOptimizer.as`

```actionscript
import org.flashNight.neur.PerformanceOptimizer.FrameProbe;
import org.flashNight.neur.PerformanceOptimizer.FPSFilter;
import org.flashNight.neur.PerformanceOptimizer.PerformanceController;
import org.flashNight.neur.PerformanceOptimizer.QualityApplier;

class org.flashNight.neur.PerformanceOptimizer.PerformanceOptimizer {
    private var probe:FrameProbe;
    private var filter:FPSFilter;
    private var controller:PerformanceController;
    private var applier:QualityApplier;

    function PerformanceOptimizer(targetFPS:Number) {
        probe      = new FrameProbe();
        filter     = new FPSFilter();
        controller = new PerformanceController(targetFPS);
        applier    = new QualityApplier();
    }
    public function update():Void {
        var rawFPS:Number     = probe.capture();
        var smoothFPS:Number  = filter.process(rawFPS);
        var action:PerformanceAction = controller.compute(smoothFPS);
        applier.apply(action);
    }
    public function reset():Void {
        probe.reset(); filter.reset(); controller.reset(); applier.reset();
    }
}
```

---

## 4 集成步骤（1‑Day Playbook）

| 时间         | 步骤                      | 操作                                                                                                                                                                                              |
| ---------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **上午**     | **(1) 复制骨架文件**          | 放入 `org/flashNight/neur/`；确保编译路径正确。                                                                                                                                                             |
|            | **(2) 替换 `_root.帧计时器`** | `var optimizer = new org.flashNight.neur.PerformanceOptimizer.PerformanceOptimizer(30); this.onEnterFrame = function(){ optimizer.update(); /* 其他逻辑 */}; SceneManager.onChanged = function(){ optimizer.reset(); };` |
| **下午**     | **(3) 注释 / 删除旧性能代码**    | 删除原 Kalman/PID/画质调整逻辑，保留 `trace` 观测点用于对比。                                                                                                                                                       |
|            | **(4) 手动测试三场景**         | ① 主菜单 ② 战斗密集场面 ③ 场景切换；观察 `_quality` 等是否随 FPS 波动。                                                                                                                                                |
| **↓若无回归↓** | **(5) 清理日志 & 提交 PR**    | 保留 `#ifdef DEBUG` 形式 FPS 日志；文档化变更。                                                                                                                                                              |

> **回滚**：若出现异常卡顿，注释掉 optimizer 调用、恢复旧逻辑即可（仅 2 行差异）。

---

## 5 验证与调参

1. **基线记录**

   * 用旧逻辑跑 5 分钟战斗场景，记录平均 FPS。
2. **新逻辑对比**

   * 打开 debug overlay (`trace('[FPS] '+smoothFPS)`)；确认波动 < ±3 FPS，且 `_quality` 自动降/升。
3. **PID 调参指引**

   * 若出现过度震荡：降低 `kp` 或增大 `alpha`。
   * 若收敛慢：微增 `kp` 或 `kd`。
4. **扩展监控**（可选）

   * `System.totalMemory` > 阈值时，附加 `MemoryProbe` 并在 `PerformanceAction` 增加 `memoryPressure` 字段。

---

## 6 风险 & 缓解

| 风险               | 缓解                                                 |
| ---------------- | -------------------------------------------------- |
| AS2 无命名空间冲突      | 每个类完整包名 `org.flashNight.neur.PerformanceOptimizer.*`；避免 `_global.*` 引用。 |
| FPSFilter α 设置不当 | 先用 0.15 (≈ 6 帧半衰)，再根据实际帧率曲线调整。                     |
| Applier 调整过猛     | `magnitude` 做 Clamp(0,0.5)；或强制每帧最大只变动 1 级。         |
| Scene 切换时状态残留    | 必须调用 `optimizer.reset()`；放在统一 `SceneManager` 事件中。  |

---

## 7 后续演进路线

1. **MemoryProbe + GC 高潮检测**
2. **QualityApplier 策略表外置**（XML/TOML/FNTL），运行期热加载。
3. **在加载界面重用 Optimizer**（统一逻辑，避免白屏时 *quality* 降得过低后不回升）。
4. **控制 AI Tick 频率 / 声音 Channel 数** —— 仅需新增 `AITickApplier`、`AudioApplier`，同样接收 `PerformanceAction`。

---

## 8 结语

此计划书旨在 **一天内即可落地** 的最小可行重构；同时确保未来加探针、换算法、扩品类都无需再碰 `_root.帧计时器`。
按表执行即可立即获得 **更清晰的代码结构 + 快速可调的性能自适应**。祝实施顺利！🛠️