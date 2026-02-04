import org.flashNight.neur.Controller.SimpleKalmanFilter1D;

/**
 * AdaptiveKalmanStage - 自适应卡尔曼滤波阶段
 *
 * 职责：
 * - 封装现有的 SimpleKalmanFilter1D，不改其实现；
 * - 在每次滤波前根据采样间隔 dt 动态调节过程噪声 Q：
 *     Q(dt) = clamp(baseQ * dtSeconds, qMin, qMax)
 * - 按工作版本顺序执行：setQ → predict() → update()
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

