/**
 * IntervalSampler - 变周期采样器（区间平均帧率测量）
 *
 * 采样周期 N_k = frameRate × (1 + performanceLevel)
 *   • 性能等级0: N = 30帧 ≈ 1秒
 *   • 性能等级1: N = 60帧 ≈ 2秒
 *
 * 测量公式: ȳ_k = N_k / Δt_k × 1000
 *
 * 职责边界：只负责采样窗口计数、区间平均 FPS 计算、窗口重置。
 * 决策逻辑已迁移到 C# PerfDecisionEngine。
 */
class org.flashNight.neur.PerformanceOptimizer.IntervalSampler {

    private var _frameRate:Number;
    /** 距下次测量剩余帧数（public 允许 evaluate() 内联）*/
    public var _framesLeft:Number;
    private var _frameStartTime:Number;

    public function IntervalSampler(frameRate:Number) {
        this._frameRate = (isNaN(frameRate) || frameRate <= 0) ? 30 : frameRate;
        this._framesLeft = this._frameRate;
        this._frameStartTime = getTimer();
    }

    /**
     * 每帧调用，递减倒计时。
     * @return Boolean 到达采样点时返回 true
     */
    public function tick():Boolean {
        return (--this._framesLeft === 0);
    }

    /**
     * 区间平均 FPS
     */
    public function measure(currentTime:Number, level:Number):Number {
        var fr:Number = this._frameRate;
        var dt:Number = currentTime - this._frameStartTime;
        if (dt <= 0) return fr;
        return ((fr * (1 + level) * 10000 / dt + 0.5) >> 0) / 10;
    }

    /**
     * Δt（秒）
     */
    public function getDeltaTimeSec(currentTime:Number):Number {
        return (currentTime - this._frameStartTime) / 1000;
    }

    /**
     * 重置采样窗口
     */
    public function resetInterval(currentTime:Number, level:Number):Void {
        this._frameStartTime = currentTime;
        this._framesLeft = this._frameRate * (1 + level);
    }

    // --- Accessors ---

    public function setFramesLeft(frames:Number):Void { this._framesLeft = frames; }
    public function getFramesLeft():Number { return this._framesLeft; }
    public function setFrameStartTime(timeMs:Number):Void { this._frameStartTime = timeMs; }
    public function getFrameStartTime():Number { return this._frameStartTime; }
    public function getFrameRate():Number { return this._frameRate; }
}
