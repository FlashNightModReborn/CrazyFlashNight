/**
 * org.flashNight.aven.Promise.Scheduler
 *
 * Promise 异步回调调度器。
 * 支持两种互斥的驱动模式，以及一个测试用手动排空入口。
 *
 * === 驱动模式（互斥，同一时刻只有一种在工作） ===
 *
 * 1. clip 回退模式（默认）：
 *    构造时自动创建隐藏 MovieClip 的 onEnterFrame 驱动排空。
 *    适用于 TestLoader 等不经过帧计时器的独立环境。
 *
 * 2. 外部驱动模式（生产推荐）：
 *    调用 bindTo(eventBus, "frameUpdate") 切入。
 *    移除独立 clip，Promise 排空由外部事件驱动，在帧更新管线中有确定相位。
 *    enqueue 热路径零额外检查（_externalDriven 短路 clip 存活检测）。
 *
 * === 手动排空（测试专用） ===
 *
 *   tick() 立即执行一次 processQueue，用于单元测试同步验证。
 *   注意：tick() 本身不切换驱动模式。
 *   - clip 模式下调用 tick()：本次手动排空 + 下一帧 clip 空排（无害但冗余）
 *   - 外部驱动模式下调用 tick()：等价于外部事件触发
 *
 * === 冷路径储备 API ===
 *
 *   fallbackToClip()：显式从外部驱动切回 clip 模式。
 *   业务层在检测到外部驱动失效时主动调用，零热路径开销。
 *
 * === 性能优化记录 (2026-03) ===
 *   [PERF] processQueue 从逐项 shift() 改为 head 指针推进 + 尾部压缩
 *         shift() 是 O(n)/次 → 排空 n 项总计 O(n²)；head 指针是 O(1)/次 → 总计 O(n)
 *   [PERF] processQueue 移除逐项 try-catch（H18 热路径禁止 try-catch）
 *   [PERF] 热循环内局部化 _queue / MAX_DRAIN_ITEMS / _head（H01 局部变量直读 0ns）
 *   [PERF] 外部驱动模式下 enqueue 仅 2× push，零额外检查
 *
 * === 中断安全性 ===
 *   _head 是实例变量，每处理一项后立即递增。若 Flash Player 因脚本超时
 *   静默中止 processQueue，已处理的项 _head 已越过，不会重复执行；
 *   未处理的项仍在 _queue[_head..] 中存活，下一帧自动恢复。
 */
import org.flashNight.neur.Event.*;

class org.flashNight.aven.Promise.Scheduler {
    private static var _instance:Scheduler;
    private static var CLIP_NAME:String = "_promiseScheduler";
    private static var NO_ARG:Object = {};
    private var _queue:Array;
    private var _head:Number;
    private var _clip:MovieClip;
    private var _externalDriven:Boolean;

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
     * 构造函数（clip 回退模式）
     */
    private function Scheduler() {
        this._queue = [];
        this._head = 0;
        this._externalDriven = false;
        this.ensureClip();
    }

    // ================================================================
    // 驱动模式 API
    // ================================================================

    /**
     * 切换到外部驱动模式：绑定到 EventBus 事件。
     * 移除独立 clip，后续排空完全由外部事件驱动。
     *
     * @param eventBus  EventBus 实例
     * @param eventName 事件名（通常 "frameUpdate"）
     */
    public function bindTo(eventBus:Object, eventName:String):Void {
        this.removeClip();
        this._externalDriven = true;
        eventBus.subscribe(eventName, this.tick, this);
    }

    /**
     * 从外部驱动模式解绑，但不自动恢复 clip。
     * 解绑后队列暂停排空，直到 fallbackToClip() 或再次 bindTo()。
     */
    public function unbind(eventBus:Object, eventName:String):Void {
        eventBus.unsubscribe(eventName, this.tick, this);
        this._externalDriven = false;
    }

    /**
     * 冷路径储备：显式从外部驱动切回 clip 模式。
     * 业务层在检测到外部驱动失效时主动调用。零热路径开销。
     */
    public function fallbackToClip():Void {
        this._externalDriven = false;
        this.ensureClip();
    }

    /**
     * 当前是否处于外部驱动模式。
     * 业务层或诊断代码可查询，判断是否需要 fallbackToClip()。
     */
    public function isExternalDriven():Boolean {
        return this._externalDriven;
    }

    /**
     * 手动触发一次队列排空。
     *
     * 主要用途：
     * - 单元测试中同步排空，无需等待自然帧
     * - 外部驱动模式下由 EventBus 回调自动调用
     *
     * 注意：此方法不切换驱动模式。clip 模式下手动调用会导致
     * 本次立即排空 + 下一帧 clip 空排（无害但冗余）。
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
        if (!this._externalDriven && this._clip._parent == undefined) {
            this.ensureClip();
        }
    }

    /**
     * 添加一个带单参数的函数到异步调用队列。
     * Promise 的 fulfilled/rejected 分发走这里，避免为每次回调再套一层 async 闭包。
     */
    public function enqueueWithArg(fn:Function, arg:Object):Void {
        this._queue.push(fn);
        this._queue.push(arg);
        if (!this._externalDriven && this._clip._parent == undefined) {
            this.ensureClip();
        }
    }

    // ================================================================
    // 内部实现
    // ================================================================

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
     *
     * 使用实例变量 _head 作为队列消费指针，每处理一项后递增 _head。
     * 对比 shift()（O(n)/次，n 项合计 O(n²)），head 指针为 O(1)/次，合计 O(n)。
     *
     * 处理过程中新入队的回调 push 到队列尾部，本帧继续处理（微任务语义）。
     * 排空后 queue.length=0 + _head=0 快速重置（H21）。
     */
    private function processQueue():Void {
        var q:Array = this._queue;       // H01: 局部化队列引用
        var head:Number = this._head;     // H01: 局部化 head
        var maxDrain:Number = MAX_DRAIN_ITEMS; // H01: 局部化上限
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
            this._head = head;  // 写回实例变量，保证中断安全
            if (arg === NO_ARG) {
                fn();
            } else {
                fn(arg);
            }
        }

        // 排空完毕：快速重置
        if (head >= q.length) {
            q.length = 0;  // H21: 清空数组用 length=0
            this._head = 0;
        } else {
            this._head = head;
            // 已处理区间过长时压缩，防止内存泄漏
            if (head > 1024) {
                q.splice(0, head);
                this._head = 0;
            }
        }
    }
}
