/**
 * org.flashNight.aven.Promise.Scheduler
 *
 * Promise 异步回调调度器。使用 onEnterFrame 驱动，
 * 每帧排空整个队列（包括处理过程中新入队的项目），
 * 模拟 JavaScript 的微任务队列行为。
 *
 * 修复记录 (2026-03):
 *   [FIX] processQueue 改为排空模式 — 处理过程中新入队的回调
 *         在同一帧内继续处理，使 Promise 链在单帧内解析完毕
 *   [SAFETY] 添加每帧最大迭代次数限制，防止无限循环
 *   [FIX] 改用逐项 shift() 出队 — 批处理(batch swap)模式下 Flash Player
 *         静默中止脚本会导致局部 batch 变量中未处理的回调永久丢失；
 *         逐项出队保证中断后剩余项仍在 _queue 中存活到下一帧
 */
import org.flashNight.neur.Event.*;

class org.flashNight.aven.Promise.Scheduler {
    private static var _instance:Scheduler;
    private static var CLIP_NAME:String = "_promiseScheduler";
    private var _queue:Array;
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
        this.ensureClip();
    }

    /**
     * 添加一个函数到异步调用队列
     * @param fn 要执行的函数
     */
    public function enqueue(fn:Function):Void {
        this.ensureClip();
        this._queue.push(fn);
    }

    /** 确保驱动 onEnterFrame 的隐藏 clip 始终存在 */
    private function ensureClip():Void {
        var needsClip:Boolean = false;

        if (typeof(this._clip) != "movieclip") {
            needsClip = true;
        } else if (this._clip._parent == undefined) {
            needsClip = true;
        } else if (typeof(this._clip.onEnterFrame) != "function") {
            needsClip = true;
        }

        if (!needsClip) {
            return;
        }

        var clip:MovieClip = _root[CLIP_NAME];
        if (typeof(clip) != "movieclip") {
            clip = _root.createEmptyMovieClip(CLIP_NAME, _root.getNextHighestDepth());
        }

        clip._visible = false;
        clip.onEnterFrame = Delegate.create(this, this.processQueue);
        this._clip = clip;
    }

    /**
     * 排空队列：逐项从队列头部取出并执行。
     *
     * 使用 shift() 逐项出队而非 batch swap，确保即使 Flash Player
     * 因脚本超时静默中止 processQueue，未处理的回调仍保留在 _queue 中，
     * 下一帧自动恢复处理。
     *
     * 处理过程中新入队的回调 push 到队列尾部，在同一帧内继续处理，
     * 实现类似微任务的语义。
     */
    private function processQueue():Void {
        var processed:Number = 0;
        while (this._queue.length > 0) {
            processed++;
            if (processed > MAX_DRAIN_ITEMS) {
                trace("[Scheduler] WARNING: exceeded " + MAX_DRAIN_ITEMS
                      + " items in one frame, deferring rest to next frame");
                break;
            }

            var fn:Function = Function(this._queue.shift());
            try {
                fn();
            } catch (e:Object) {
                trace("[Scheduler] ERROR: " + e);
            }
        }
    }
}
