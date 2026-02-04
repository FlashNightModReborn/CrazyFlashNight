/**
 * IntervalSampler - 变周期采样器（区间平均帧率测量）
 *
 * 控制理论要点：
 * - 时间尺度分离 (Time-Scale Separation)
 * - 采样周期 N_k = frameRate * (1 + performanceLevel)
 *   性能等级越高（越卡），采样周期越长，让系统有更充分的稳定时间再评估。
 *
 * 说明：
 * - 本类只负责采样“窗口”的计数、区间平均 FPS 的计算、以及窗口重置；
 * - 不包含 Kalman / PID / 量化 / 执行器等控制策略逻辑。
 */
class org.flashNight.neur.PerformanceOptimizer.IntervalSampler {

    /** 标称帧率（Hz） */
    private var _frameRate:Number;
    /** 距离下一次测量还剩多少帧（tick时递减） */
    private var _framesLeft:Number;
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
        return Math.ceil(
            this._frameRate * (1 + level) * 10000 / (currentTime - this._frameStartTime)
        ) / 10;
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
     * 返回给 PID.update() 的 deltaTime（工作版本为“帧数”，不是“秒”）
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
     * 设置“保护窗口”（前馈控制用）：推迟下一次反馈评估
     * protection = max(frameRate * holdSec, frameRate * (1 + level))
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

