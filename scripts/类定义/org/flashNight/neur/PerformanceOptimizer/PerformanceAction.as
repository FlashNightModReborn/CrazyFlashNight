/**
 * 性能调整动作数据传输对象
 * 用于在PerformanceController和QualityApplier之间传递性能调整信息
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceAction {
    /**
     * 性能趋势：
     * "UP" - 需要降低画质/效果以提升性能
     * "DOWN" - 可以提升画质/效果
     * "STABLE" - 保持当前设置
     */
    public var trend:String;
    
    /**
     * 调整强度，范围 0-1
     * 0 表示无需调整，1 表示需要最大幅度调整
     */
    public var magnitude:Number;
    
    /**
     * 当前滤波后的FPS值，用于调试和显示
     */
    public var currentFPS:Number;
    
    /**
     * 目标FPS值
     */
    public var targetFPS:Number;
    
    /**
     * 构造函数
     * @param t 趋势字符串
     * @param m 调整强度
     * @param current 当前FPS
     * @param target 目标FPS
     */
    public function PerformanceAction(t:String, m:Number, current:Number, target:Number) {
        trend = t;
        magnitude = m;
        currentFPS = current;
        targetFPS = target;
    }
    
    /**
     * 返回动作的字符串表示，用于调试
     */
    public function toString():String {
        return "[PerformanceAction trend:" + trend + " magnitude:" + magnitude + 
               " fps:" + currentFPS + "/" + targetFPS + "]";
    }
    
    /**
     * 判断是否需要执行调整
     */
    public function shouldAdjust():Boolean {
        return trend != "STABLE" && magnitude > 0.05;
    }
}