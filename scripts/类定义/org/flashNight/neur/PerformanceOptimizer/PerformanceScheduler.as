import org.flashNight.neur.Controller.PIDController;
import org.flashNight.neur.Controller.SimpleKalmanFilter1D;

/**
 * PerformanceScheduler - 性能调度门面/协调器
 *
 * 目标：
 * - 将工作版本中位于 `_root.帧计时器` 的过程式性能调度逻辑，拆分为可解释、可测试、可替换模块；
 * - 在行为上保持等价（同输入序列下产生同样的档位切换与副作用）。
 *
 * 【反馈控制主循环 (evaluate)】
 * ───────────────────────────────────────────────────────────
 *   每帧调用 → 采样计数器递减 → 到达采样点？
 *                                     │
 *                               ┌─────┴─────┐
 *                              否           是
 *                               │           │
 *                               ▼           ▼
 *                            返回     1.测量FPS    ← 区间平均: ȳ_k = N_k / Δt_k
 *                                          ↓
 *                                     2.更新Q      ← 自适应: Q = Q₀ × dt
 *                                          ↓
 *                                     3.卡尔曼滤波  ← 状态估计: ŷ_k = Kalman(ȳ_k)
 *                                          ↓
 *                                     4.PID计算    ← 控制律: u*_k = PID(r - ŷ_k)
 *                                          ↓
 *                                     5.量化       ← u_k = round(u*_k) ∈ {0,1,2,3}
 *                                          ↓
 *                                     6.迟滞确认   ← 施密特触发器: 连续2次才执行
 *                                          ↓
 *                                     7.执行调整   ← 修改特效/画质/刷佣兵等参数
 *                                          ↓
 *                                     8.重置采样   ← N_{k+1} = 帧率 × (1 + u_k)
 *
 * 【PID 控制律】
 * ───────────────────────────────────────────────────────────
 *   u*(t) = Kp·e(t) + Ki·∫e(τ)dτ + Kd·de(t)/dt
 *   离散化: u*_k = Kp·e_k + Ki·Σ(e_i·Δt) + Kd·(e_k - e_{k-1})/Δt
 *
 *   参数物理意义：
 *   • Kp (比例增益): 控制响应速度，Kp↑ → 响应快但易超调
 *     经验公式: Kp ≈ 1/ΔFPS，当前 Kp=0.2 等价假设「一档 ≈ 5 FPS」
 *   • Ki (积分增益): 消除稳态误差，Ki↑ → 精度高但易振荡
 *     integralMax 限制积分饱和（Anti-Windup）
 *   • Kd (微分增益): 阻尼超调，Kd↑ → 响应平滑但变慢
 *
 *   【⚠ 特殊设计】负微分系数 Kd = -30
 *     标准 PID 中 Kd > 0 用于阻尼；这里 Kd < 0 是「预见性控制」：
 *     • 帧率下降 (de/dt < 0) → -Kd·(de/dt) > 0 → 输出增大 → 提前降级
 *     • 帧率上升 (de/dt > 0) → -Kd·(de/dt) < 0 → 输出减小 → 提前升级
 *     本质是前馈补偿，预测帧率变化趋势并提前响应。
 *
 *   【控制目标】targetFPS = 26（而非30）— 死区/裕度设计
 *     Flash 帧率硬上限 = 30 FPS，系统饱和在30时控制器「不可控」。
 *     目标26预留4FPS裕度，避免在 29~30 FPS 区间被噪声频繁踢导致切档。
 *
 * 组件：
 * - IntervalSampler        变周期采样器（区间平均测量 + 窗口重置）
 * - AdaptiveKalmanStage    自适应卡尔曼滤波（包装 SimpleKalmanFilter1D）
 * - PIDController          现有PID（由 PIDControllerFactory 异步加载参数）
 * - HysteresisQuantizer    迟滞量化器（两次确认）
 * - PerformanceActuator    执行器（应用具体降载策略）
 * - FPSVisualization       数据记录与曲线绘制（可选）
 *
 * 【状态所有权】
 *   scheduler 完全拥有以下状态（不再回写到 host）：
 *   - performanceLevel, actualFPS, pid, presetQuality
 *   - 采样器/滤波器/量化器的全部内部状态
 *   host 上仅保留 性能等级上限（存档系统读写）和 offsetTolerance（摄像机读取）。
 *
 * 依赖注入（便于测试）：
 * - env.root 提供 _root 等舞台对象访问（默认使用全局 _root）
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler {

    private var _host:Object;  // 宿主（仅用于读取 性能等级上限、写入 offsetTolerance）
    private var _env:Object;

    private var _frameRate:Number;
    private var _targetFPS:Number;
    private var _presetQuality:String;
    private var _performanceLevel:Number;
    private var _actualFPS:Number;
    private var _pid:PIDController;

    private var _sampler:org.flashNight.neur.PerformanceOptimizer.IntervalSampler;
    private var _kalmanStage:org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage;
    private var _quantizer:org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer;
    private var _actuator:Object;  // 默认为 PerformanceActuator，允许测试注入 mock
    private var _viz:Object;       // 默认为 FPSVisualization，允许测试注入 mock/禁用
    private var _logger:Object;    // 可选：性能日志器（默认 null，零开销）

    /**
     * 构造函数
     * @param host:Object       宿主对象（推荐传 _root.帧计时器）
     * @param frameRate:Number  标称帧率（默认30）
     * @param targetFPS:Number  目标帧率（默认26）
     * @param presetQuality:String 预设画质（默认 _root._quality）
     * @param env:Object        （可选）依赖注入，至少应包含 {root}
     * @param pid:PIDController （可选）PID控制器实例
     */
    public function PerformanceScheduler(host:Object, frameRate:Number, targetFPS:Number, presetQuality:String, env:Object, pid:PIDController) {
        this._host = host;

        if (env == undefined) {
            env = { root: _root };
        }
        this._env = env;

        this._frameRate = (frameRate != undefined) ? frameRate : 30;
        this._targetFPS = (targetFPS != undefined) ? targetFPS : 26;
        this._presetQuality = (presetQuality != undefined) ? presetQuality : this._env.root._quality;
        this._performanceLevel = 0;
        this._actualFPS = 0;
        this._pid = (pid != undefined) ? pid : null;

        // --- Sampler ---
        this._sampler = new org.flashNight.neur.PerformanceOptimizer.IntervalSampler(this._frameRate);

        // --- Kalman ---
        var kalman:SimpleKalmanFilter1D = new SimpleKalmanFilter1D(this._frameRate, 0.5, 1);
        this._kalmanStage = new org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage(kalman, 0.1, 0.01, 2.0);

        // --- Quantizer ---
        var levelCap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : 0;
        this._quantizer = new org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer(levelCap, 3);

        // --- Actuator ---
        this._actuator = new org.flashNight.neur.PerformanceOptimizer.PerformanceActuator(host, this._presetQuality, this._env);

        // --- Visualization（可选）---
        var weather:Object = (this._env.root && this._env.root.天气系统 != undefined) ? this._env.root.天气系统 : null;
        this._viz = new org.flashNight.neur.PerformanceOptimizer.FPSVisualization(24, this._frameRate, weather);
    }

    /**
     * 每帧调用的反馈控制主循环（行为等价于 _root.帧计时器.性能评估优化）
     * @param currentTime:Number （可选）测试用时间戳（ms），未提供则使用 getTimer()
     */
    public function evaluate(currentTime:Number):Void {
        // 1) tick：变周期采样触发
        if (!this._sampler.tick()) {
            return;
        }

        if (currentTime == undefined) {
            currentTime = getTimer();
        }

        var root:Object = this._env.root;
        var currentLevel:Number = this._performanceLevel;

        // 2) 测量：区间平均 FPS（原公式）
        var actualFPS:Number = this._sampler.measure(currentTime, currentLevel);
        this._actualFPS = actualFPS;

        // UI数字显示（观测输出，不参与控制）
        root.玩家信息界面.性能帧率显示器.帧率数字.text = actualFPS;

        // 3) 自适应卡尔曼：Q = baseQ * dt
        var dtSeconds:Number = this._sampler.getDeltaTimeSec(currentTime);
        var denoisedFPS:Number = this._kalmanStage.filter(actualFPS, dtSeconds);

        // 4) PID：保持与工作版本一致，deltaTime 传"帧数"
        var pidDeltaFrames:Number = this._sampler.getPIDDeltaTimeFrames(currentLevel);
        var pidOutput:Number = (this._pid != null)
            ? this._pid.update(this._targetFPS, denoisedFPS, pidDeltaFrames)
            : 0;

        // 可插拔日志：采样点 + PID 分量详细记录（默认关闭）
        if (this._logger != null) {
            this._logger.sample(currentTime, currentLevel, actualFPS, denoisedFPS, pidOutput);
            if (this._pid != null) {
                this._logger.pidDetail(currentTime, this._pid.getLastP(), this._pid.getLastI(), this._pid.getLastD(), pidOutput);
            }
        }

        // 5) 量化 + 6) 迟滞确认
        var host:Object = this._host;
        var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : this._quantizer.getMinLevel();
        this._quantizer.setMinLevel(cap);

        var result:Object = this._quantizer.process(pidOutput, currentLevel);

        if (result.levelChanged) {
            var oldLevel:Number = currentLevel;
            var newLevel:Number = result.newLevel;

            this._actuator.setPresetQuality(this._presetQuality);
            this._actuator.apply(newLevel);
            this._performanceLevel = newLevel;
            currentLevel = newLevel;

            root.发布消息("性能等级: [" + currentLevel + " : " + actualFPS + " FPS] " + root._quality);

            if (this._logger != null) {
                this._logger.levelChanged(currentTime, oldLevel, newLevel, actualFPS, root._quality);
            }
        }

        // 7) 重置采样窗口（基于当前性能等级）
        this._sampler.resetInterval(currentTime, currentLevel);

        // 8) 数据记录与可视化（可选）
        if (this._viz != null) {
            if (this._viz.setWeatherSystem != undefined && root.天气系统 != undefined) {
                this._viz.setWeatherSystem(root.天气系统);
            }
            this._viz.updateData(actualFPS);
            var canvas:MovieClip = root.玩家信息界面.性能帧率显示器.画布;
            this._viz.drawCurve(canvas, currentLevel);
        }
    }

    // ------------------------------------------------------------------
    // 前馈控制接口（行为等价于 手动设置/降低/提升性能等级）
    // ------------------------------------------------------------------

    public function setPerformanceLevel(level:Number, holdSec:Number, currentTime:Number):Void {
        var root:Object = this._env.root;

        level = Math.round(level);
        var host:Object = this._host;
        var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : this._quantizer.getMinLevel();
        level = Math.max(cap, Math.min(level, 3));

        if (this._performanceLevel === level) {
            return;
        }

        if (holdSec == undefined || holdSec <= 0) {
            holdSec = 5;
        }

        // 前馈：直接切档并执行
        this._performanceLevel = level;

        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(level);

        // 重置PID与迟滞状态，避免立即被反馈覆盖
        if (this._pid != null) {
            this._pid.reset();
        }
        this._quantizer.clearConfirmation();

        if (currentTime == undefined) {
            currentTime = getTimer();
        }

        // 保护窗口：推迟下一次反馈评估
        this._sampler.setProtectionWindow(currentTime, holdSec, level);

        // UI显示：用估算帧率填充（与工作版本一致）
        var estimatedFPS:Number = this._frameRate - level * 2;
        this._actualFPS = estimatedFPS;
        root.玩家信息界面.性能帧率显示器.帧率数字.text = estimatedFPS;

        if (this._viz != null) {
            if (this._viz.setWeatherSystem != undefined && root.天气系统 != undefined) {
                this._viz.setWeatherSystem(root.天气系统);
            }
            this._viz.updateData(estimatedFPS);
            var canvas:MovieClip = root.玩家信息界面.性能帧率显示器.画布;
            this._viz.drawCurve(canvas, level);
        }

        root.发布消息("手动设置性能等级: [" + level + "] 保持" + holdSec + "秒");

        if (this._logger != null) {
            this._logger.manualSet(currentTime, level, holdSec);
        }
    }

    public function decreaseLevel(steps:Number, holdSec:Number, currentTime:Number):Void {
        steps = steps || 1;
        this.setPerformanceLevel(this._performanceLevel + steps, holdSec, currentTime);
    }

    public function increaseLevel(steps:Number, holdSec:Number, currentTime:Number):Void {
        steps = steps || 1;
        this.setPerformanceLevel(this._performanceLevel - steps, holdSec, currentTime);
    }

    /**
     * 场景切换时的重置入口（对齐既有 SceneChanged 处理）
     *
     * 重置：卡尔曼滤波器、PID、迟滞状态、性能等级→0、采样窗口
     */
    public function onSceneChanged():Void {
        var now:Number = getTimer();

        // 日志：在重置前捕获当前状态快照
        if (this._logger != null) {
            this._logger.sceneChanged(now, this._performanceLevel, this._actualFPS, this._targetFPS, this._env.root._quality);
        }

        // 1) 重置卡尔曼滤波器
        this._kalmanStage.reset(this._frameRate, 1);

        // 2) 重置 PID 控制器
        if (this._pid != null) {
            this._pid.reset();
        }

        // 3) 重置迟滞状态
        this._quantizer.clearConfirmation();

        // 4) 执行器归零 + 同步性能等级
        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(0);
        this._performanceLevel = 0;

        // 5) 重置采样窗口
        this._sampler.resetInterval(now, 0);
    }

    // ------------------------------------------------------------------
    // Accessors / injection helpers
    // ------------------------------------------------------------------

    public function setPID(pid:PIDController):Void { this._pid = pid; }
    public function getPID():PIDController { return this._pid; }

    public function setPresetQuality(q:String):Void { this._presetQuality = q; }
    public function getPresetQuality():String { return this._presetQuality; }

    public function getQuantizer():org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer { return this._quantizer; }
    public function getActuator():Object { return this._actuator; }
    public function setActuator(actuator:Object):Void { this._actuator = actuator; }

    public function getSampler():org.flashNight.neur.PerformanceOptimizer.IntervalSampler { return this._sampler; }
    public function getKalmanStage():org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage { return this._kalmanStage; }

    public function getVisualization():Object { return this._viz; }
    public function setVisualization(viz:Object):Void { this._viz = viz; }

    public function getLogger():Object { return this._logger; }
    public function setLogger(logger:Object):Void { this._logger = logger; }

    public function getPerformanceLevel():Number { return this._performanceLevel; }
    public function getActualFPS():Number { return this._actualFPS; }
    public function getTargetFPS():Number { return this._targetFPS; }

    /**
     * 设置日志标签（委托到 logger.setTag）。
     * 用于系统辨识数据采集时标注当前场景/模式。
     * 如果 logger 未挂载则静默忽略。
     */
    public function setLoggerTag(tag:String):Void {
        if (this._logger != null && this._logger.setTag != undefined) {
            this._logger.setTag(tag);
        }
    }
    public function getLoggerTag():String {
        if (this._logger != null && this._logger.getTag != undefined) {
            return this._logger.getTag();
        }
        return null;
    }
}
