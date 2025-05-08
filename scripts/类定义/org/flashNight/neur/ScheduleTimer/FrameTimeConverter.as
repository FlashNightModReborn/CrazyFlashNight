/**
 * FrameTimeConverter.as
 * -----------------------------------------------------------------------------
 * 提供帧数与毫秒数的相互转换方法，用于在帧计数与时间计数之间进行精确换算。
 * 路径: org/flashNight/neur/ScheduleTimer/
 */
class org.flashNight.neur.ScheduleTimer.FrameTimeConverter {
    
    /**
     * 将给定的帧数转换为毫秒数
     * @param frames      帧数
     * @param frameRate   帧率（每秒帧数）
     * @param roundUp     是否向上取整返回整数毫秒，默认 true
     * @return            对应的毫秒数
     */
    public static function framesToMilliseconds(frames:Number, frameRate:Number, roundUp:Boolean):Number {
        // 默认向上取整
        if (roundUp === undefined) {
            roundUp = true;
        }
        
        // 参数校验
        if (frames === undefined || isNaN(frames)) {
            throw new Error("FrameTimeConverter.framesToMilliseconds: invalid frames: " + frames);
        }
        if (frameRate === undefined || isNaN(frameRate) || frameRate <= 0) {
            throw new Error("FrameTimeConverter.framesToMilliseconds: invalid frameRate: " + frameRate);
        }
        
        // 计算：ms = (frames * 1000) / frameRate
        var ms:Number = (frames * 1000) / frameRate;
        return roundUp ? Math.ceil(ms) : ms;
    }
    
    /**
     * 将毫秒数转换为帧数
     * @param milliseconds  毫秒数
     * @param frameRate     帧率（每秒帧数）
     * @param roundUp       是否向上取整返回整数帧数，默认 true
     * @return              对应的帧数
     */
    public static function millisecondsToFrames(milliseconds:Number, frameRate:Number, roundUp:Boolean):Number {
        // 默认向上取整
        if (roundUp === undefined) {
            roundUp = true;
        }
        
        // 参数校验
        if (milliseconds === undefined || isNaN(milliseconds)) {
            throw new Error("FrameTimeConverter.millisecondsToFrames: invalid milliseconds: " + milliseconds);
        }
        if (frameRate === undefined || isNaN(frameRate) || frameRate <= 0) {
            throw new Error("FrameTimeConverter.millisecondsToFrames: invalid frameRate: " + frameRate);
        }
        
        // 计算：frames = (milliseconds * frameRate) / 1000
        var frames:Number = (milliseconds * frameRate) / 1000;
        return roundUp ? Math.ceil(frames) : frames;
    }
}