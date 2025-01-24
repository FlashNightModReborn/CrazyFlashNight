// 文件路径: org/flashNight/neur/Timer/FrameTimer.as

import org.flashNight.gesh.symbol.Symbol;
import org.flashNight.neur.Event.Delegate;

class org.flashNight.neur.Timer.FrameTimer {
    // 公共属性
    public var counter:Number = 0;
    
    // 私有属性
    private var _clip:MovieClip;
    private var _tasks:Array;
    private static var _instance:FrameTimer = getInstance();
    
    /**
     * 构造函数（私有化）
     */
    private function FrameTimer() {
        this._tasks = new Array();
        var insName:String = "__FRAME_TIMER_INSTANCE__";
        // 直接在_root创建控制影片剪辑
        this._clip = _root.createEmptyMovieClip(
            insName, 
            _root.getNextHighestDepth()
        );
        // trace("创建FrameTimer控制影片剪辑：" + this._clip + " " + insName);
        // 绑定ENTER_FRAME事件
        this._clip.onEnterFrame = Delegate.create(this, this.update);
    }
    
    /**
     * 获取全局唯一实例
     * @return FrameTimer实例
     */
    public static function getInstance():FrameTimer {
        if (!_instance) {
            _instance = new FrameTimer();
        }
        return _instance;
    }
    
    /**
     * 添加定时任务（极简版）
     * @param handler 处理函数 (参数格式: function():Void)
     */
    public function addTask(handler:Function):Void {
        // trace("addTask");
        _tasks[_tasks.length] = handler;
    }
    
    /**
     * 移除定时任务
     * @param handler 要移除的处理函数
     */
    public function removeTask(handler:Function):Void {
        for (var i:Number = this._tasks.length-1; i >= 0; i--) {
            if (this._tasks[i] === handler) {
                this._tasks.splice(i, 1);
            }
        }
    }
    
    /**
     * 核心更新方法
     */
    public function update():Void {
        this.counter++;
        // trace("update: " + this.toString());
        // 直接遍历执行（最快执行速度）
        var tasks:Array = this._tasks;
        var len:Number = tasks.length;
        for (var i:Number = 0, len:Number = len; i < len; i++) {
            tasks[i]();
        }
    }
    
    /**
     * 销毁定时器（非必要不建议调用）
     */
    public function destroy():Void {
        this._clip.onEnterFrame = null;
        this._clip.removeMovieClip();
        _instance = null;
        this._tasks = null;
    }


    public function toString():String
    {
        var str:String = "FrameTimer: counter=" + this.counter + ", tasks=" + this._tasks.length;
        return str;
    }
}