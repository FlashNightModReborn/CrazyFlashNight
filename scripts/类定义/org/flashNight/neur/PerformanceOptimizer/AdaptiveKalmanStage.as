import org.flashNight.neur.Controller.SimpleKalmanFilter1D;

/**
 * AdaptiveKalmanStage - 自适应卡尔曼滤波阶段
 *
 * 职责：
 * - 封装现有的 SimpleKalmanFilter1D，不改其实现；
 * - 在每次滤波前根据采样间隔 dt 动态调节过程噪声 Q：
 *     Q(dt) = clamp(baseQ * dtSeconds, qMin, qMax)
 * - 按工作版本顺序执行：setQ → predict() → update()
 *
 * 【数学模型】一维简化卡尔曼滤波器 (SimpleKalmanFilter1D)
 * ───────────────────────────────────────────────────────────
 *   状态方程: x_k = x_{k-1} + w_k      (状态 = FPS，假设恒定 + 过程噪声)
 *   观测方程: z_k = x_k + v_k          (观测 = 测量FPS + 测量噪声)
 *
 *   预测步骤: x⁻_k = x_{k-1}
 *            P⁻_k = P_{k-1} + Q
 *   更新步骤: K_k = P⁻_k / (P⁻_k + R)
 *            x_k = x⁻_k + K_k × (z_k - x⁻_k)
 *            P_k = (1 - K_k) × P⁻_k
 *
 * 【参数说明】
 *   • initialEstimate = 30  : 初始状态估计（标称帧率）
 *   • initialP = 0.5        : 初始估计协方差（对初值的不确定度）
 *   • R = 1                 : 测量噪声协方差（观测噪声强度）
 *     【设计备注】R 为固定值。理论上 R_eff ∝ σ²/N，区间平均的帧数 N 越大
 *     测量方差越小，R 应随 N 缩放。但自适应 Q 已在同方向调节（Q↑ → K↑ → 更信测量），
 *     叠加 R↓ 会导致高等级时 Kalman 几乎直接透传，滤波功能丧失。
 *     在 4 档离散量化 + 迟滞系统中，R 精度不影响最终切档决策。
 *   • Q = 动态调整          : 过程噪声协方差（系统不确定性）
 *
 * 【控制理论】自适应 Q 的物理意义
 * ───────────────────────────────────────────────────────────
 *   Q(dt) = Q₀ × dt，其中 dt 是采样间隔（秒）
 *   • dt 越长 → Q 越大 → 卡尔曼增益 K 越大 → 更信任测量值、少拖尾
 *   • dt 越短 → Q 越小 → 卡尔曼增益 K 越小 → 更信任模型预测、滤波激进
 *
 *   Q 限幅: clamp [qMin=0.01, qMax=2.0]，防止极端值
 *
 * 【本质】自适应 Q 使滤波器在「信任模型」和「信任测量」之间动态切换
 *         长采样 = 系统变化大 = 信测量；短采样 = 系统稳定 = 信模型
 */
class org.flashNight.neur.PerformanceOptimizer.AdaptiveKalmanStage {

    /** 底层一维卡尔曼滤波器（现有类） */
    private var _kalman:SimpleKalmanFilter1D;

    /** 基础过程噪声系数 Q0（与 dt 成正比缩放） */
    private var _baseQ:Number;
    /** Q 下限（防止过小导致跟踪迟钝） */
    private var _qMin:Number;
    /** Q 上限（防止过大导致估计抖动） */
    private var _qMax:Number;

    /**
     * 构造函数
     * @param kalman:SimpleKalmanFilter1D 现有滤波器实例
     * @param baseQ:Number 基础过程噪声系数（工作版本默认0.1）
     * @param qMin:Number Q下限（工作版本默认0.01）
     * @param qMax:Number Q上限（工作版本默认2.0）
     */
    public function AdaptiveKalmanStage(kalman:SimpleKalmanFilter1D, baseQ:Number, qMin:Number, qMax:Number) {
        this._kalman = kalman;
        this._baseQ = (baseQ == undefined) ? 0.1 : baseQ;
        this._qMin = (qMin == undefined) ? 0.01 : qMin;
        this._qMax = (qMax == undefined) ? 2.0 : qMax;
    }

    /**
     * 执行一次自适应滤波
     * @param measuredFPS:Number 测量值（区间平均FPS）
     * @param dtSeconds:Number 采样间隔dt（秒）
     * @return Number 滤波后的FPS估计值
     */
    public function filter(measuredFPS:Number, dtSeconds:Number):Number {
        var scaledQ:Number = this._baseQ * dtSeconds;
        scaledQ = Math.max(this._qMin, Math.min(scaledQ, this._qMax));

        this._kalman.setProcessNoise(scaledQ);
        this._kalman.predict();
        return this._kalman.update(measuredFPS);
    }

    /**
     * 重置滤波器（用于场景切换等）
     * @param initialEstimate:Number 初始估计值
     * @param initialErrorCov:Number 初始误差协方差P
     */
    public function reset(initialEstimate:Number, initialErrorCov:Number):Void {
        this._kalman.reset(initialEstimate, initialErrorCov);
    }

    /**
     * 暴露底层 SimpleKalmanFilter1D（用于日志/测试）
     */
    public function getFilter():SimpleKalmanFilter1D {
        return this._kalman;
    }

    public function getBaseQ():Number { return this._baseQ; }
    public function getQMin():Number { return this._qMin; }
    public function getQMax():Number { return this._qMax; }
}

