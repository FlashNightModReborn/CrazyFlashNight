/**
 * TweenCore 是所有补间类的基础类，提供时间和状态管理功能。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */
class org.flashNight.neur.Tween.TweenCore {
    // 状态常量
    public static var ACTIVE:Number = 1;
    public static var PAUSED:Number = 2;
    public static var COMPLETED:Number = 3;
    
    // 内部变量
    private var _startTime:Number;
    private var _time:Number;
    private var _duration:Number;
    private var _state:Number;
    private var _useFrames:Boolean;
    
    // 管理链表指针
    private var _next:TweenCore;
    private var _prev:TweenCore;
    
    /**
     * 构造函数
     * @param duration 持续时间（秒）
     * @param useFrames 是否基于帧而非时间
     */
    public function TweenCore(duration:Number, useFrames:Boolean) {
        _duration = (isNaN(duration)) ? 0 : duration;
        _useFrames = Boolean(useFrames);
        _startTime = _time = 0;
        _state = TweenCore.ACTIVE;
    }
    
    /**
     * 更新补间状态 - 子类必须重写此方法
     * @param timeDiff 时间差值
     * @return Boolean 是否继续活跃
     */
    public function update(timeDiff:Number):Boolean {
        // 抽象方法，子类需要实现
        return false;
    }
    
    /**
     * 暂停补间
     */
    public function pause():TweenCore {
        _state = TweenCore.PAUSED;
        return this;
    }
    
    /**
     * 继续播放补间
     */
    public function resume():TweenCore {
        _state = TweenCore.ACTIVE;
        return this;
    }
    
    /**
     * 重置补间
     */
    public function reset():TweenCore {
        _time = 0;
        _state = TweenCore.ACTIVE;
        return this;
    }
    
    /**
     * 完成补间
     */
    public function complete():TweenCore {
        _time = _duration;
        _state = TweenCore.COMPLETED;
        return this;
    }
    
    // Getter 和 Setter 方法
    public function get duration():Number { return _duration; }
    public function get time():Number { return _time; }
    public function set time(value:Number):Void { _time = value; }
    public function get state():Number { return _state; }
    public function get useFrames():Boolean { return _useFrames; }
    public function get startTime():Number { return _startTime; }
    public function set startTime(value:Number):Void { _startTime = value; }
    public function get isActive():Boolean { return _state == TweenCore.ACTIVE; }
    public function get isComplete():Boolean { return _state == TweenCore.COMPLETED; }
    
    // 链表管理
    public function get next():TweenCore { return _next; }
    public function set next(value:TweenCore):Void { _next = value; }
    public function get prev():TweenCore { return _prev; }
    public function set prev(value:TweenCore):Void { _prev = value; }
}