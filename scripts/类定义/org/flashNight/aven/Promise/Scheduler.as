/**
 * org.flashNight.aven.Promise.Scheduler
 *
 * Promise 异步回调调度器。
 * 支持三种驱动状态和一个手动排空入口。
 *
 * === 驱动状态（三态，互斥） ===
 *
 *   _driveMode == 0  CLIP 模式（默认）
 *     隐藏 MovieClip 的 onEnterFrame 驱动排空。
 *     enqueue 时若 clip 死亡则自愈。
 *
 *   _driveMode == 1  EXTERNAL 模式
 *     由 bindTo() 切入。移除 clip，记忆绑定源(eventBus + eventName)。
 *     排空完全由外部事件回调驱动。enqueue 零额外检查。
 *
 *   _driveMode == 2  SUSPENDED 模式
 *     由 unbind() 切入。退订外部源并清除绑定记忆，不建 clip。
 *     队列持续累积但无自动排空。tick() 可手动排空。
 *     调用 fallbackToClip() 或 bindTo() 退出此状态。
 *
 * === 手动排空 ===
 *
 *   tick() 立即执行一次 processQueue。任何驱动状态下均可调用。
 *   不切换状态。CLIP 模式下手动 tick 后下一帧 clip 空排（无害但冗余）。
 *
 * === 绑定源记忆 ===
 *
 *   bindTo() 保存当前 eventBus + eventName。
 *   unbind() / fallbackToClip() 使用保存的绑定源自动退订。
 *   再次 bindTo() 到新源时先自动退订旧源，保证互斥。
 *
 * === 性能优化记录 (2026-03) ===
 *   [PERF] processQueue: shift() O(n²) → head 指针 O(n)
 *   [PERF] processQueue: 移除逐项 try-catch（H18）
 *   [PERF] 热循环内局部化 _queue / MAX_DRAIN_ITEMS / _head（H01）
 *   [PERF] EXTERNAL 模式下 enqueue 仅 2× push，零额外检查
 *
 * === 中断安全性 ===
 *   _head 每处理一项后立即递增。Flash 超时中止后
 *   已处理项不会重复执行，未处理项下一帧自动恢复。
 */
import org.flashNight.neur.Event.*;

class org.flashNight.aven.Promise.Scheduler {
    private static var _instance:Scheduler;
    private static var CLIP_NAME:String = "_promiseScheduler";
    private static var NO_ARG:Object = {};

    // 驱动状态常量
    private static var DRIVE_CLIP:Number      = 0;
    private static var DRIVE_EXTERNAL:Number   = 1;
    private static var DRIVE_SUSPENDED:Number  = 2;

    private var _queue:Array;
    private var _head:Number;
    private var _clip:MovieClip;
    private var _driveMode:Number;

    // 绑定源记忆
    private var _boundBus:Object;
    private var _boundEvent:String;

    /** 每帧最大处理项数，防止无限循环 */
    private static var MAX_DRAIN_ITEMS:Number = 10000;

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
     * 构造函数（CLIP 模式）
     */
    private function Scheduler() {
        this._queue = [];
        this._head = 0;
        this._driveMode = 0; // DRIVE_CLIP
        this._boundBus = null;
        this._boundEvent = null;
        this.ensureClip();
    }

    // ================================================================
    // 驱动模式 API
    // ================================================================

    /**
     * 切换到 EXTERNAL 模式：绑定到 EventBus 事件。
     * 若当前已绑定其他源，先自动退订旧源再绑定新源，保证互斥。
     * 移除 clip，后续排空由外部事件驱动。
     *
     * @param eventBus  EventBus 实例
     * @param eventName 事件名（通常 "frameUpdate"）
     */
    public function bindTo(eventBus:Object, eventName:String):Void {
        // 先清理当前状态
        this.cleanupCurrentDrive();

        // 建立新绑定
        this._boundBus = eventBus;
        this._boundEvent = eventName;
        this._driveMode = 1; // DRIVE_EXTERNAL
        eventBus.subscribe(eventName, this.tick, this);
    }

    /**
     * 切换到 SUSPENDED 模式：退订外部源，不建 clip。
     * 队列持续累积但无自动排空。tick() 仍可手动排空。
     * 调用 fallbackToClip() 或 bindTo() 退出此状态。
     */
    public function unbind():Void {
        this.cleanupCurrentDrive();
        this._driveMode = 2; // DRIVE_SUSPENDED
    }

    /**
     * 切换到 CLIP 模式：恢复隐藏 clip 驱动。
     * 若当前有外部绑定，先自动退订。
     */
    public function fallbackToClip():Void {
        this.cleanupCurrentDrive();
        this._driveMode = 0; // DRIVE_CLIP
        this.ensureClip();
    }

    /**
     * 当前驱动模式。0=CLIP, 1=EXTERNAL, 2=SUSPENDED。
     */
    public function getDriveMode():Number {
        return this._driveMode;
    }

    /**
     * 当前是否处于外部驱动模式。
     */
    public function isExternalDriven():Boolean {
        return this._driveMode === 1;
    }

    /**
     * 手动触发一次队列排空。任何驱动状态下均可调用。
     * 不切换状态。
     */
    public function tick():Void {
        this.processQueue();
    }

    // ================================================================
    // 入队 API
    // ================================================================

    /**
     * 添加一个无参函数到异步调用队列
     */
    public function enqueue(fn:Function):Void {
        this._queue.push(fn);
        this._queue.push(NO_ARG);
        // 仅 CLIP 模式需要自愈检查；EXTERNAL/SUSPENDED 不建 clip
        if (this._driveMode === 0 && this._clip._parent == undefined) {
            this.ensureClip();
        }
    }

    /**
     * 添加一个带单参数的函数到异步调用队列。
     */
    public function enqueueWithArg(fn:Function, arg:Object):Void {
        this._queue.push(fn);
        this._queue.push(arg);
        if (this._driveMode === 0 && this._clip._parent == undefined) {
            this.ensureClip();
        }
    }

    // ================================================================
    // 内部实现
    // ================================================================

    /**
     * 清理当前驱动状态：退订外部源 + 移除 clip。
     * bindTo / unbind / fallbackToClip 切换前统一调用。
     */
    private function cleanupCurrentDrive():Void {
        // 退订外部源（若有）
        if (this._boundBus != null && this._boundEvent != null) {
            this._boundBus.unsubscribe(this._boundEvent, this.tick, this);
            this._boundBus = null;
            this._boundEvent = null;
        }
        // 移除 clip（若有）
        this.removeClip();
    }

    /** 创建/恢复回退用的隐藏 clip */
    private function ensureClip():Void {
        var clip:MovieClip = _root[CLIP_NAME];
        if (typeof(clip) != "movieclip" || clip._parent == undefined) {
            clip = _root.createEmptyMovieClip(CLIP_NAME, _root.getNextHighestDepth());
        }
        clip._visible = false;
        clip.onEnterFrame = Delegate.create(this, this.processQueue);
        this._clip = clip;
    }

    /** 移除回退 clip */
    private function removeClip():Void {
        if (typeof(this._clip) == "movieclip") {
            delete this._clip.onEnterFrame;
            this._clip.removeMovieClip();
        }
        this._clip = undefined;
    }

    /**
     * 排空队列：head 指针推进模式。
     */
    private function processQueue():Void {
        var q:Array = this._queue;
        var head:Number = this._head;
        var maxDrain:Number = MAX_DRAIN_ITEMS;
        var processed:Number = 0;

        while (head < q.length) {
            processed++;
            if (processed > maxDrain) {
                trace("[Scheduler] WARNING: exceeded " + maxDrain
                      + " items in one frame, deferring rest to next frame");
                break;
            }

            var fn:Function = Function(q[head]);
            var arg:Object = q[head + 1];
            head += 2;
            this._head = head;
            if (arg === NO_ARG) {
                fn();
            } else {
                fn(arg);
            }
        }

        if (head >= q.length) {
            q.length = 0;
            this._head = 0;
        } else {
            this._head = head;
            if (head > 1024) {
                q.splice(0, head);
                this._head = 0;
            }
        }
    }
}
