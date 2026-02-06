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
 *                                     6.迟滞确认   ← 非对称施密特触发器: 降级2次/升级3次
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
 *   • Kd (微分增益): 控制对误差变化率的响应
 *
 *   【工程实态】PID 在本系统中退化为「PD + 方向偏置」的阈值生成器
 *   ───────────────────────────────────────────────────────────
 *   由于 deltaTime 传入帧数（30~120）而非秒（详见 IntervalSampler.getPIDDeltaTimeFrames）：
 *
 *   积分项: integral += error × 30~120 → 首拍即 clamp 到 integralMax=3
 *           iTerm = Ki × integral = 0.5 × (±3) = ±1.5（常量方向偏置）
 *           实际作用: 帧率低于目标→+1.5, 高于目标→-1.5, 加速跨越量化边界
 *
 *   微分项: errorDiff = Δerror / 30~120（缩小30-120倍）
 *           有效增益 ≈ Kd/deltaTime = -30/30~120 ≈ -1.0 ~ -0.25
 *           实际作用: 中等强度的阻尼项（详见下文 Kd 分析）
 *
 *   比例项: 唯一真正随误差连续变化的分量
 *           P = 0.2 × error = 0.2 × (26 - filteredFPS)
 *
 *   合计: pidOutput ≈ 0.2×error ± 1.5 + D_damping
 *   经 round()→clamp[0,3]→迟滞确认 后，只剩下「跨没跨过量化边界」这一位信息
 *   因此 PID 参数精度对最终切档决策的影响极小，系统稳定性由迟滞量化器主导
 *
 *   【Kd = -30 的实际工程效果】阻尼器，而非预见性控制
 *   ───────────────────────────────────────────────────────────
 *   误差定义: e = targetFPS - denoisedFPS
 *
 *   帧率下降时: e 增大 → de/dt > 0 → D = kd × de/dt = -30 × 正 = 负
 *     → D 抵消 P，减缓 PID 输出上升 → 不急于降级，过滤瞬时帧率跌落
 *     实测: FPS 骤降时 D ≈ -0.8 ~ -1.3，部分抵消 P ≈ +1.0 ~ +2.0
 *
 *   帧率上升时: e 减小 → de/dt < 0 → D = kd × de/dt = -30 × 负 = 正
 *     → D 拉住 P，减缓 PID 输出下降 → 不急于恢复，防止刚升回就被打回
 *     实测: FPS 回升时 D ≈ +0.05 ~ +0.3，延缓恢复
 *
 *   稳态时: de/dt ≈ 0 → D ≈ 0，微分项退场
 *
 *   |Kd|=30 远大于 Kp=0.2（150倍），但 deltaTime=帧数 将其缩小30-120倍，
 *   最终有效增益 ≈ -1.0 ~ -0.25，与 P 项同量级，形成有意义但不主导的阻尼。
 *   若 deltaTime 为秒（~1s），D 将达到 ±30~60，远超 P+I，系统会发散。
 *   因此帧数单位不是 bug，而是让 |Kd|=30 工作在合理范围的必要条件。
 *
 *   【控制目标】targetFPS = 26（而非30）— 死区/裕度设计
 *     Flash 帧率硬上限 = 30 FPS，系统饱和在30时控制器「不可控」。
 *     目标26预留4FPS裕度，避免在 29~30 FPS 区间被噪声频繁踢导致切档。
 *
 * 组件：
 * - IntervalSampler        变周期采样器（区间平均测量 + 窗口重置）
 * - AdaptiveKalmanStage    自适应卡尔曼滤波（包装 SimpleKalmanFilter1D）
 * - PIDController          现有PID（由 PIDControllerFactory 异步加载参数）
 * - HysteresisQuantizer    非对称迟滞量化器（降级2次/升级3次确认）
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
    private var _actuator:Object;  // 非空：默认 PerformanceActuator，允许测试注入 mock
    private var _viz:Object;       // 非空：默认 FPSVisualization，允许测试注入 mock
    private var _logger:Object;    // 唯一可空模块：性能日志器（默认 null，运行时热拔插）
    private var _holdUntilMs:Number;  // 保持窗口结束时间戳（ms），hold 期间抑制切档但不阻断观测
    private var _panicFPS:Number;     // 紧急降级阈值（FPS），低于此值绕过迟滞直接降级

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
        // NullPID: Kp=0 → update() 恒返回 0，行为等价于无控制器；
        // PIDControllerFactory 异步加载完成后通过 setPID() 替换为真实实例
        this._pid = (pid != undefined) ? pid : new PIDController(0, 0, 0, 0, 0);

        // --- Sampler ---
        this._sampler = new org.flashNight.neur.PerformanceOptimizer.IntervalSampler(this._frameRate);

        // --- Kalman ---
        var kalman:SimpleKalmanFilter1D = new SimpleKalmanFilter1D(this._frameRate, 0.5, 1);
        this._kalmanStage = new org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage(kalman, 0.1, 0.01, 2.0);

        // --- Quantizer ---
        var levelCap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : 0;
        // 非对称迟滞：降级（level↑）2次确认快速响应，升级（level↓）3次确认谨慎恢复
        this._quantizer = new org.flashNight.neur.PerformanceOptimizer.HysteresisQuantizer(levelCap, 3, 2, 3);

        // --- Actuator ---
        this._actuator = new org.flashNight.neur.PerformanceOptimizer.PerformanceActuator(host, this._presetQuality, this._env);

        // --- Visualization（可选）---
        var weather:Object = (this._env.root && this._env.root.天气系统 != undefined) ? this._env.root.天气系统 : null;
        this._viz = new org.flashNight.neur.PerformanceOptimizer.FPSVisualization(24, this._frameRate, weather);

        this._holdUntilMs = 0;
        this._panicFPS = 5;  // 极保守: 仅在游戏接近冻结时触发，不干扰迟滞量化器的正常抖动吸收
    }

    /**
     * 每帧调用的反馈控制主循环（行为等价于 _root.帧计时器.性能评估优化）
     * @param currentTime:Number （可选）测试用时间戳（ms），未提供则使用 getTimer()
     */
    public function evaluate(currentTime:Number):Void {
        // P0: 内联 tick() — 消除每帧方法调用开销（T4+T1）
        var sampler:Object = this._sampler;
        if (--sampler._framesLeft !== 0) {
            return;
        }

        if (currentTime == undefined) {
            currentTime = getTimer();
        }

        // P1: 采样点路径局部变量缓存（T1）— 将 this.* 哈希查找降为寄存器/栈读取
        var root:Object = this._env.root;
        var currentLevel:Number = this._performanceLevel;
        var kalmanStage:Object = this._kalmanStage;
        var pid:PIDController = this._pid;
        var logger:Object = this._logger;

        // 2) 测量：区间平均 FPS（原公式）
        var actualFPS:Number = sampler.measure(currentTime, currentLevel);
        this._actualFPS = actualFPS;

        // UI数字显示（观测输出，不参与控制）
        root.玩家信息界面.性能帧率显示器.帧率数字.text = actualFPS;

        // ── 紧急降级旁路（pre-Kalman, 使用原始区间平均 FPS）──────────
        // 阈值极保守（默认 5 FPS），仅在游戏接近冻结时触发。
        // 正常帧率抖动（10~20 FPS 区间）由迟滞量化器吸收，此处不干预。
        if (actualFPS < this._panicFPS && currentLevel < 3) {
            var panicLevel:Number = currentLevel + 1;
            this._actuator.setPresetQuality(this._presetQuality);
            this._actuator.apply(panicLevel);
            this._performanceLevel = panicLevel;

            // 从实际 FPS 重新建立状态估计，避免 Kalman 残留旧估计拖累恢复
            kalmanStage.reset(actualFPS, 1);
            pid.reset();
            this._quantizer.clearConfirmation();
            this._holdUntilMs = 0;

            root.发布消息("紧急降级: [" + panicLevel + " : " + actualFPS + " FPS] " + root._quality);
            if (logger != null) {
                logger.levelChanged(currentTime, currentLevel, panicLevel, actualFPS, root._quality);
            }

            currentLevel = panicLevel;
            sampler.resetInterval(currentTime, currentLevel);
            // → 跳过 Kalman/PID/量化，直接到可视化

        } else {
            // 3) 自适应卡尔曼：Q = baseQ * dt
            var dtSeconds:Number = sampler.getDeltaTimeSec(currentTime);
            var denoisedFPS:Number = kalmanStage.filter(actualFPS, dtSeconds);

            // 4) PID：保持与工作版本一致，deltaTime 传"帧数"
            var pidDeltaFrames:Number = sampler.getPIDDeltaTimeFrames(currentLevel);
            var pidOutput:Number = pid.update(this._targetFPS, denoisedFPS, pidDeltaFrames);

            // 可插拔日志：采样点 + PID 分量详细记录（默认关闭）
            if (logger != null) {
                logger.sample(currentTime, currentLevel, actualFPS, denoisedFPS, pidOutput);
                logger.pidDetail(currentTime, pid.getLastP(), pid.getLastI(), pid.getLastD(), pidOutput);
            }

            // ── 保持窗口检查（方案 B: 测量与保持解耦）──────────────
            // hold 期间继续 Kalman/PID/日志观测，仅抑制量化器+执行器输出，
            // 确保 Kalman 估计在 hold 结束时已收敛到真实帧率。
            if (currentTime >= this._holdUntilMs) {
                // 5) 量化 + 6) 迟滞确认
                var host:Object = this._host;
                var quantizer:Object = this._quantizer;
                var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : quantizer.getMinLevel();
                quantizer.setMinLevel(cap);

                var qResult:Number = quantizer.process(pidOutput, currentLevel);

                if (qResult >= 0) {
                    var oldLevel:Number = currentLevel;
                    var newLevel:Number = qResult;

                    this._actuator.setPresetQuality(this._presetQuality);
                    this._actuator.apply(newLevel);
                    this._performanceLevel = newLevel;
                    currentLevel = newLevel;

                    root.发布消息("性能等级: [" + currentLevel + " : " + actualFPS + " FPS] " + root._quality);

                    if (logger != null) {
                        logger.levelChanged(currentTime, oldLevel, newLevel, actualFPS, root._quality);
                    }
                }
            }

            // 7) 重置采样窗口（基于当前性能等级）
            sampler.resetInterval(currentTime, currentLevel);
        }

        // 8) 数据记录与可视化（所有路径共用）
        var viz:Object = this._viz;
        if (viz.setWeatherSystem != undefined && root.天气系统 != undefined) {
            viz.setWeatherSystem(root.天气系统);
        }
        viz.updateData(actualFPS);
        var canvas:MovieClip = root.玩家信息界面.性能帧率显示器.画布;
        viz.drawCurve(canvas, currentLevel);
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
        this._pid.reset();
        this._quantizer.clearConfirmation();
        // 【设计备注】此处未重置 KalmanStage：
        // hold 窗口期间 Kalman 持续接收真实测量值（方案 B），
        // hold 结束时估计已收敛，无需手动重置。

        if (currentTime == undefined) {
            currentTime = getTimer();
        }

        // hold 窗口：继续观测但抑制切档（方案 B — 测量与保持解耦）
        // 修复: 旧 setProtectionWindow 导致 measure() 分子分母不匹配 → 虚假低 FPS
        this._sampler.resetInterval(currentTime, level);
        this._holdUntilMs = currentTime + holdSec * 1000;

        // UI显示：用估算帧率填充（与工作版本一致）
        var estimatedFPS:Number = this._frameRate - level * 2;
        this._actualFPS = estimatedFPS;
        root.玩家信息界面.性能帧率显示器.帧率数字.text = estimatedFPS;

        if (this._viz.setWeatherSystem != undefined && root.天气系统 != undefined) {
            this._viz.setWeatherSystem(root.天气系统);
        }
        this._viz.updateData(estimatedFPS);
        var canvas:MovieClip = root.玩家信息界面.性能帧率显示器.画布;
        this._viz.drawCurve(canvas, level);

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
     * 开环测试用：强制设置性能等级，不创建保护窗口。
     *
     * 与 setPerformanceLevel 的区别：
     * - 不创建保护窗口 → evaluate() 的采样不会被阻塞
     * - 不估算/填充帧率 → 等待真实测量数据
     *
     * 配合量化器锁定（minLevel = maxLevel = targetLevel）使用，
     * PID 输出经量化后始终被 clamp 到当前等级，实现开环条件。
     * 用于系统辨识时的开环阶跃响应测试。
     *
     * 【采样间隔必须与目标等级一致】
     *   measure() 分子 = frameRate×(1+level)，分母 = 实际经过时间；
     *   若 resetInterval 使用不同的 level，首样本 FPS 会被放大 (1+level) 倍。
     *   因此 resetInterval 必须传入目标 level，而非 0。
     *
     * @param level:Number 目标性能等级（0-3）
     */
    public function forceLevel(level:Number):Void {
        level = Math.round(level);
        level = Math.max(0, Math.min(level, 3));

        // 应用新等级（不创建保护窗口）
        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(level);
        this._performanceLevel = level;

        // 重置 PID 和迟滞状态（避免旧积分/确认状态影响）
        this._pid.reset();
        this._quantizer.clearConfirmation();
        this._holdUntilMs = 0;

        // 采样间隔使用目标等级，确保 measure() 分子分母一致
        this._sampler.resetInterval(getTimer(), level);
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
        this._pid.reset();

        // 3) 重置迟滞状态
        this._quantizer.clearConfirmation();

        // 3.5) 清除保持窗口（场景切换后不应延续旧 hold）
        this._holdUntilMs = 0;

        // 4) 执行器重置 + 同步性能等级（尊重性能等级上限，避免低配机器场景切换时冻屏）
        var host:Object = this._host;
        var cap:Number = (host && !isNaN(host.性能等级上限)) ? host.性能等级上限 : 0;
        var resetLevel:Number = Math.max(cap, 0);
        this._actuator.setPresetQuality(this._presetQuality);
        this._actuator.apply(resetLevel);
        this._performanceLevel = resetLevel;

        // 5) 重置采样窗口（使用重置后的等级，确保采样间隔与等级匹配）
        this._sampler.resetInterval(now, resetLevel);
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
    public function setVisualization(viz:Object):Void {
        // NullViz: viz 为空时注入空操作对象，与 NullPID 同理，
        // 保证 evaluate()/setPerformanceLevel() 无需 null 检查
        if (viz == null || viz == undefined) {
            viz = {
                updateData: function():Void {},
                drawCurve: function():Void {},
                setWeatherSystem: function():Void {}
            };
        }
        this._viz = viz;
    }

    public function getLogger():Object { return this._logger; }
    public function setLogger(logger:Object):Void { this._logger = logger; }

    public function getPerformanceLevel():Number { return this._performanceLevel; }
    public function getActualFPS():Number { return this._actualFPS; }
    public function getTargetFPS():Number { return this._targetFPS; }

    public function getPanicFPS():Number { return this._panicFPS; }
    public function setPanicFPS(fps:Number):Void {
        // 钳制: isNaN 或 <=0 回退到默认值 5，防止无意关闭紧急旁路
        this._panicFPS = (isNaN(fps) || fps <= 0) ? 5 : fps;
    }
    public function getHoldUntilMs():Number { return this._holdUntilMs; }

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
