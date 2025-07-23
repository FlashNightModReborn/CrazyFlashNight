/**
 * 帧率采集器
 * 负责采集当前的实际帧率
 */
class org.flashNight.neur.PerformanceOptimizer.FrameProbe {
    private var _lastTime:Number;
    private var _frameCount:Number;
    private var _measurementFrames:Number;
    private var _totalTime:Number;
    private var _targetFPS:Number;
    
    /**
     * 构造函数
     * @param targetFPS 目标帧率，用于确定测量间隔
     */
    public function FrameProbe(targetFPS:Number) {
        _targetFPS = targetFPS || 30;
        _measurementFrames = _targetFPS; // 每秒测量一次
        reset();
    }
    
    /**
     * 采集当前帧率
     * @return 当前测量到的帧率，如果还未到测量间隔则返回null
     */
    public function capture():Number {
        var currentTime:Number = getTimer();
        
        if (_frameCount == 0) {
            _lastTime = currentTime;
        }
        
        _frameCount++;
        _totalTime = currentTime - _lastTime;
        
        // 达到测量间隔或超过预期时间太多时进行计算
        if (_frameCount >= _measurementFrames || _totalTime > (_measurementFrames * 1000 / _targetFPS * 1.5)) {
            var fps:Number = Math.ceil(_frameCount * 10000 / _totalTime) / 10;
            
            // 重置计数器
            _frameCount = 0;
            _lastTime = currentTime;
            
            return fps;
        }
        
        return null; // 还未到测量时间
    }
    
    /**
     * 获取当前测量进度 (0-1)
     */
    public function getMeasurementProgress():Number {
        return Math.min(_frameCount / _measurementFrames, 1.0);
    }
    
    /**
     * 重置采集器状态
     */
    public function reset():Void {
        _lastTime = getTimer();
        _frameCount = 0;
        _totalTime = 0;
    }
    
    /**
     * 设置测量间隔帧数
     * @param frames 测量间隔的帧数
     */
    public function setMeasurementFrames(frames:Number):Void {
        _measurementFrames = Math.max(frames, 10); // 最少10帧
    }
    
    /**
     * 获取当前测量间隔
     */
    public function getMeasurementFrames():Number {
        return _measurementFrames;
    }
}