/**
 * IntervalSampler - 变周期采样器（区间平均帧率测量）
 *
 * 【控制理论】自适应采样周期 (Adaptive Sampling Period)
 * ───────────────────────────────────────────────────────
 *   采样周期 N_k = frameRate × (1 + performanceLevel)
 *     • 性能等级0（流畅）: N = 30帧 ≈ 1秒
 *     • 性能等级1: N = 60帧 ≈ 2秒
 *     • 性能等级2: N = 90帧 ≈ 3秒
 *     • 性能等级3（卡顿）: N = 120帧 ≈ 4秒
 *
 * 【设计原理】时间尺度分离 (Time-Scale Separation)
 *   被控对象（Flash渲染器）的时间常数 τ ≈ 2-5秒（从改变参数到FPS稳定）
 *   采样周期必须满足 T_sample ≈ τ，否则：
 *     • T_sample << τ: 过采样，观测到的是暂态而非稳态，导致频繁误调整
 *     • T_sample >> τ: 欠采样，响应太慢，无法及时跟踪负载变化
 *   自适应机制：系统越慢（性能等级越高），τ 越大，采样周期 N ∝ (1+等级) 自动匹配。
 *
 * 【帧率测量】区间平均采样器 (Interval-Average Sampler)
 * ───────────────────────────────────────────────────────
 *   测量公式: ȳ_k = N_k / Δt_k × 1000
 *     其中 N_k = frameRate × (1 + performanceLevel) 是期望帧数
 *          Δt_k = currentTime - frameStartTime 是实际耗时 (ms)
 *
 *   N帧平均本身就是一个强低通滤波器，截止频率 f_c ≈ frameRate/(2πN)
 *     • N=30:  f_c ≈ 0.16 Hz，滤除 > 6秒 周期的波动
 *     • N=120: f_c ≈ 0.04 Hz，滤除 > 25秒 周期的波动
 *   这是系统稳定性的第一道防线：把瞬时噪声（爆炸、弹幕峰值）挡在闭环带宽之外。
 *
 * 【自适应采样的正反馈特性】
 *   性能等级高（卡）→ 采样周期长 → 下次评估更晚 → 系统有更多时间稳定
 *   性能等级低（流畅）→ 采样周期短 → 响应更快 → 能及时检测到性能下降
 *   虽然是正反馈，但有界（性能等级 ∈ [0,3]），不会发散。
 *
 * 职责边界：
 * - 本类只负责采样"窗口"的计数、区间平均 FPS 的计算、以及窗口重置；
 * - 不包含 Kalman / PID / 量化 / 执行器等控制策略逻辑。
 */
class org.flashNight.neur.PerformanceOptimizer.IntervalSampler {

    /** 标称帧率（Hz） */
    private var _frameRate:Number;
    /** 距离下一次测量还剩多少帧（tick时递减，public 允许 evaluate() 内联） */
    public var _framesLeft:Number;
    /** 上次测量起点时间戳（ms） */
    private var _frameStartTime:Number;

    /**
     * 构造函数
     * @param frameRate:Number 标称帧率（通常为30）
     */
    public function IntervalSampler(frameRate:Number) {
        this._frameRate = (isNaN(frameRate) || frameRate <= 0) ? 30 : frameRate;
        this._framesLeft = this._frameRate;
        this._frameStartTime = getTimer();
    }

    /**
     * 每帧调用一次，递减倒计时。
     * @return Boolean 当倒计时从1递减到0时返回true（到达采样点）
     */
    public function tick():Boolean {
        return (--this._framesLeft === 0);
    }

    /**
     * 计算区间平均 FPS（公式需与工作版本完全一致）
     * @param currentTime:Number 当前时间戳（ms）
     * @param level:Number 当前性能等级 u_k
     * @return Number 区间平均FPS（保留1位小数）
     */
    public function measure(currentTime:Number, level:Number):Number {
        // 【不变量】dt > 0 — 由采样间隔机制保证（生产路径 getTimer() 单调 + ≥30帧间隔）
        // 防御非单调时间戳（测试注入/极端情况），返回标称帧率避免 Infinity 污染 Kalman
        var fr:Number = this._frameRate;
        var dt:Number = currentTime - this._frameStartTime;
        if (dt <= 0) return fr;
        // 位运算四舍五入（T2）替代 Math.ceil，消除全局对象查找 + 动态方法调用
        // 【语义变更】ceil → round: 消除系统性偏高（≤0.1 FPS），改为无偏估计
        // 在 targetFPS=26 的 4FPS 死区裕度下，最大差异 ±0.05 FPS 可忽略
        return ((fr * (1 + level) * 10000 / dt + 0.5) >> 0) / 10;
    }

    /**
     * 返回本次采样窗口的Δt（秒），用于自适应Q等连续时间尺度计算
     * @param currentTime:Number 当前时间戳（ms）
     * @return Number dt（秒）
     */
    public function getDeltaTimeSec(currentTime:Number):Number {
        return (currentTime - this._frameStartTime) / 1000;
    }

    /**
     * 返回给 PID.update() 的 deltaTime（帧数，不是秒）
     *
     * 【工程实态】deltaTime = 帧数 是系统设计的一部分，不是 bug
     * ───────────────────────────────────────────────────────────
     *   传入帧数 (30~120) 而非秒 (~1~4)，产生两个关键的缩放效应：
     *
     *   1. 积分项: integral += error × 30~120
     *      → integralMax=3 时，任何 error > 0.025 都在首拍饱和
     *      → iTerm = Ki × (±3) = 0.5 × (±3) = ±1.5（退化为方向偏置）
     *      → 在4档离散系统中，渐进积累无意义（round+迟滞会抹平精度）
     *         因此积分退化为方向偏置不构成实际损失
     *
     *   2. 微分项: errorDiff = Δerror / 30~120
     *      → 有效增益 Kd/deltaTime = -30/30~120 ≈ -1.0 ~ -0.25
     *      → 这是让 |Kd|=30 工作在合理范围的必要条件
     *         若传入秒(~1s)，D项将达到 ±30~60，远超P+I，系统发散
     *      → 当前量级下 D 提供中等强度阻尼（与 P 项同量级）
     *
     *   综合: PID 退化为「P + 方向偏置 + 阻尼」的阈值生成器，
     *   稳定性由后级迟滞量化器保证。修改 deltaTime 单位需要同步重调
     *   Kd/Ki/integralMax，无独立收益，不宜单独修改。
     *
     * @param level:Number 当前性能等级
     * @return Number 帧数（30/60/90/120...）
     */
    public function getPIDDeltaTimeFrames(level:Number):Number {
        return this._frameRate * (1 + level);
    }

    /**
     * 重置测量窗口：更新起点时间戳，并设置下一次采样间隔
     * @param currentTime:Number 当前时间戳（ms）
     * @param level:Number 当前性能等级（可能已在本次评估中更新）
     */
    public function resetInterval(currentTime:Number, level:Number):Void {
        this._frameStartTime = currentTime;
        this._framesLeft = this._frameRate * (1 + level);
    }

    /**
     * 设置"保护窗口"（前馈控制用）：推迟下一次反馈评估
     * protection = max(frameRate * holdSec, frameRate * (1 + level))
     *
     * 【已弃用 — 2026-02】PerformanceScheduler 不再调用此方法。
     * 原因: 当 holdSec > (1+level) 时，_framesLeft 与 measure() 分子不匹配，
     * 导致 FPS 被系统性低估（缩放因子 = (1+level)/holdSec），
     * 污染 Kalman 估计并触发误切档。
     * 替代方案: PerformanceScheduler 使用 resetInterval() + _holdUntilMs
     * 实现「测量与保持解耦」（方案 B），hold 期间继续正常测量，
     * 仅抑制量化器+执行器输出。
     * 保留此方法以兼容外部调用者。
     *
     * @param currentTime:Number 当前时间戳（ms）
     * @param holdSec:Number 保护时间（秒）
     * @param level:Number 当前性能等级
     */
    public function setProtectionWindow(currentTime:Number, holdSec:Number, level:Number):Void {
        this._frameStartTime = currentTime;
        this._framesLeft = Math.max(
            this._frameRate * holdSec,
            this._frameRate * (1 + level)
        );
    }

    // -----------------------------
    // Accessors（主要用于测试/桥接）
    // -----------------------------

    public function setFramesLeft(frames:Number):Void {
        this._framesLeft = frames;
    }

    public function getFramesLeft():Number {
        return this._framesLeft;
    }

    public function setFrameStartTime(timeMs:Number):Void {
        this._frameStartTime = timeMs;
    }

    public function getFrameStartTime():Number {
        return this._frameStartTime;
    }

    public function getFrameRate():Number {
        return this._frameRate;
    }
}

