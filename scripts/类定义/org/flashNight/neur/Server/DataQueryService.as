import org.flashNight.neur.Server.ServerManager;

/**
 * Flash 端数据查询服务 — 封装 ServerManager.sendTaskWithCallback，
 * 向 Launcher 的 DataQueryTask 发起 data_query 请求。
 *
 * 用法：
 *   DataQueryService.query("npc_dialogue", {key: npcName, taskProgress: progress}, callback);
 *   DataQueryService.query("merc_bundle", null, callback);
 *
 * callback 签名：function(response:Object):Void
 *   response.success : Boolean
 *   response.result  : 查询结果（success 时）
 *   response.error   : 错误信息（success 为 false 时）
 *
 * 注意：socket 断连时 callback 会被 ServerManager 同步调用 {success:false}。
 */
class org.flashNight.neur.Server.DataQueryService {

    /**
     * 向 Launcher 发起数据查询。
     * @param dataType  查询类型（"npc_dialogue" | "merc_bundle"）
     * @param params    附加参数对象（会被展开合并到 payload），可为 null
     * @param callback  结果回调
     */
    public static function query(
        dataType:String, params:Object, callback:Function
    ):Void {
        var payload:Object = {dataType: dataType};
        if (params != null) {
            for (var k:String in params) payload[k] = params[k];
        }
        ServerManager.getInstance().sendTaskWithCallback(
            "data_query", payload, null, callback
        );
    }

    /**
     * Socket 是否已连接（可走 primary path）。
     */
    public static function isAvailable():Boolean {
        return ServerManager.getInstance().isSocketConnected;
    }

    // 多个并发等待门各自独立 tick clip，避免命名/状态互相覆盖。
    private static var _gateSeq:Number = 0;

    /**
     * 等待 socket 就绪后再执行 onReady；若已就绪则立即同步执行。
     *
     * 生命周期安全（这正是本方法存在的理由）：tick 用 **_root 上的 empty movie clip**（不随调用方
     * 时间轴卸载而消失），等待状态存在 **本方法的 activation（函数局部变量）** 里（不是调用方的帧本地
     * 时间轴变量）。因此即使调用方所在影片剪辑（如 asLoader 帧 64）在等待期间 removeMovieClip 自卸载，
     * 等待门与回调依旧存活、照常触发——与 BootstrapWait 同款模式。
     *
     * ⚠ 历史坑：早期 asLoader 帧 64 用 `setInterval(帧本地闭包)` 轮询 isAvailable，但帧 91 会自卸载，
     *   闭包捕获的 `_mapCatalogTries/_mapCatalogPoll/doMapCatalogQuery` 随时间轴销毁 → interval 泄漏且
     *   永不触发 query（静默击穿 catalog 的“硬报错”设计）。本方法即为根治。
     *
     * 超时语义：到点仍未就绪也会执行 onReady（让其内部 query 自己走 {success:false} 失败路径并报错），
     * 绝不静默吞掉——保持“绝不静默降级”的契约。
     *
     * @param timeoutMs 最长等待毫秒（如 10000）。<=0 视为只尝试一次（不等待）。
     * @param onReady   就绪（或超时兜底）时执行一次的回调；不接收参数。
     */
    public static function whenAvailable(timeoutMs:Number, onReady:Function):Void {
        if (isAvailable()) {
            if (onReady != null) onReady();
            return;
        }

        var holder:MovieClip = _root;
        if (timeoutMs <= 0 || holder == null || holder.createEmptyMovieClip == null) {
            // 无法挂 tick（或不等待）：退化为立即执行，让 onReady 内部 query 走失败报错路径。
            if (onReady != null) onReady();
            return;
        }

        var deadline:Number = getTimer() + timeoutMs;
        var tick:MovieClip = holder.createEmptyMovieClip(
            "__dataQueryReadyTick" + (_gateSeq++), holder.getNextHighestDepth()
        );
        tick.onEnterFrame = function():Void {
            // isAvailable / getTimer / 本闭包局部均与调用方时间轴无关，调用方卸载后仍可安全运行。
            var ready:Boolean = org.flashNight.neur.Server.DataQueryService.isAvailable();
            if (ready || getTimer() >= deadline) {
                this.onEnterFrame = null;
                this.removeMovieClip();
                if (onReady != null) onReady();
            }
        };
    }
}
