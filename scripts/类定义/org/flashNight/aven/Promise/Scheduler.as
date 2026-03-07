/**
 * org.flashNight.aven.Promise.Scheduler
 * 
 * 一个内部调度器类，用于管理 Promise 的异步回调执行。
 */
import org.flashNight.neur.Event.*;

class org.flashNight.aven.Promise.Scheduler {
    private static var _instance:Scheduler;
    private var _queue:Array;
    private var _clip:MovieClip;
    
    /**
     * 获取 Scheduler 的单例实例
     */
    public static function getInstance():Scheduler {
        if (_instance == undefined) {
            _instance = new Scheduler();
        }
        return _instance;
    }
    
    /**
     * 构造函数
     */
    private function Scheduler() {
        this._queue = [];
        
        // 创建一个隐藏的影片剪辑来驱动 onEnterFrame
        this._clip = _root.createEmptyMovieClip("_promiseScheduler", _root.getNextHighestDepth());
        this._clip.onEnterFrame = Delegate.create(this, this.processQueue);
    }
    
    /**
     * 添加一个函数到异步调用队列
     * @param fn 要执行的函数
     */
    public function enqueue(fn:Function):Void {
        this._queue.push(fn);
    }
    
    /**
     * 处理函数队列，每帧执行队列中所有函数
     */
    private function processQueue():Void {
        if (this._queue.length == 0) {
            return;
        }
        
        // 复制当前队列，并清空原队列
        var currentQueue:Array = this._queue.slice();
        this._queue = [];
        
        for (var i:Number = 0; i < currentQueue.length; i++) {
            var fn:Function = currentQueue[i];
            fn();
        }
    }
}
