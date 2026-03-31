/**
 * org.flashNight.aven.Promise.Scheduler
 *
 * Promise 异步回调调度器。使用 onEnterFrame 驱动，
 * 每帧排空整个队列（包括处理过程中新入队的项目），
 * 模拟 JavaScript 的微任务队列行为。
 *
 * 性能优化记录 (2026-03):
 *   [PERF] processQueue 从逐项 shift() 改为 head 指针推进 + 尾部压缩
 *         shift() 是 O(n)/次 → 排空 n 项总计 O(n²)；head 指针是 O(1)/次 → 总计 O(n)
 *         基准实测：10000 项 drain 从 4201ms 降至预期 <200ms
 *   [PERF] processQueue 移除逐项 try-catch（H18 热路径禁止 try-catch）
 *         回调由 Promise.then() 内部包装器保证异常安全，Scheduler 无需重复捕获
 *   [PERF] 热循环内局部化 _queue / MAX_DRAIN_ITEMS / _head（H01 局部变量直读 0ns）
 *   [PERF] enqueue 存活检查从 isClipUsable() 方法调用(1340ns)
 *         降级为内联 _clip._parent 单次 native 属性读(~170ns)
 *
 * 中断安全性:
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
     * 构造函数
     */
    private function Scheduler() {
        this._queue = [];
        this._head = 0;
        this.ensureClip();
    }

    /**
     * 添加一个函数到异步调用队列
     * @param fn 要执行的函数
     */
    public function enqueue(fn:Function):Void {
        this.enqueueWithArg(fn, NO_ARG);
    }

    /**
     * 添加一个带单参数的函数到异步调用队列。
     * Promise 的 fulfilled/rejected 分发走这里，避免为每次回调再套一层 async 闭包。
     *
     * 热路径优化（H01/S01）：
     *   - 移除冗余的 head-reset 检查（processQueue 末尾已做 q.length=0 + _head=0）
     *   - clip 存活检查从 isClipUsable() 方法调用(1340ns) 降级为
     *     内联 _clip._parent 单次 native 属性读(~170ns)
     *     clip 被 removeMovieClip() 后 _parent 变 undefined，一次读取即可捕获
     */
    public function enqueueWithArg(fn:Function, arg:Object):Void {
        this._queue.push(fn);
        this._queue.push(arg);
        // 内联 clip 存活检查：native 属性读 ~170ns vs isClipUsable() 方法调用 ~1850ns
        if (this._clip._parent == undefined) {
            this.ensureClip();
        }
    }

    /** 确保驱动 onEnterFrame 的隐藏 clip 始终存在 */
    private function ensureClip():Void {
        var clip:MovieClip = _root[CLIP_NAME];
        if (typeof(clip) != "movieclip" || clip._parent == undefined) {
            clip = _root.createEmptyMovieClip(CLIP_NAME, _root.getNextHighestDepth());
        }
        clip._visible = false;
        clip.onEnterFrame = Delegate.create(this, this.processQueue);
        this._clip = clip;
    }

    /**
     * 排空队列：head 指针推进模式。
     *
     * 使用实例变量 _head 作为队列消费指针，每处理一项后递增 _head。
     * 对比 shift()（O(n)/次，n 项合计 O(n²)），head 指针为 O(1)/次，合计 O(n)。
     *
     * 处理过程中新入队的回调 push 到队列尾部，本帧继续处理（微任务语义）。
     * 排空后 queue.length=0 + _head=0 快速重置（H21）。
     *
     * 中断安全：_head 在 fn() 调用前递增，Flash 超时中止后
     * 已处理项不会重复执行，未处理项下一帧自动恢复。
     */
    private function processQueue():Void {
        // 检测 clip 是否被外部移除（内联检查，避免方法调用开销）
        if (this._clip._parent == undefined) {
            this.ensureClip();
        }

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
