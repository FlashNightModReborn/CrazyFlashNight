/**
 * FrameBroadcaster - 帧末统一广播器
 *
 * 职责：收集摄像头数据 + 读取各子系统数据槽 → 发送单条 frame 消息到 C# 启动器。
 * 在 frameEnd 管线中作为最后一步调用，确保每帧恰好发送一条 task:frame 消息。
 *
 * 架构：
 *   frameEnd pipeline:
 *     HitNumberBatchProcessor.flush()  -> setHnPayload(buf)
 *     RayVfxManager.update()           -> 将来可增加 setRayPayload()
 *     FrameBroadcaster.send()          -> 收集 cam + 消费数据槽 -> sendSocketMessage
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.FrameBroadcaster {

    /** hn 数据槽（由 HitNumberBatchProcessor.flush() 写入，send() 消费后清空） */
    private static var _hnPayload:String = null;

    // 未来扩展槽位（如 ray vfx 数据）
    // private static var _rayPayload:String = null;

    /**
     * 写入 hn 数据槽。
     * 由 HitNumberBatchProcessor.flush() 在 C# overlay 路径中调用。
     * @param payload 序列化后的 hn 条目字符串（分号分隔），可为空串
     */
    public static function setHnPayload(payload:String):Void {
        _hnPayload = payload;
    }

    /**
     * frameEnd 管线最后一步调用。
     * 收集摄像头数据 + 读取各子系统数据槽 → 发送单条 frame 消息。
     * 每帧无条件调用（只要 socket 连接），保证 V8 侧活跃动画持续收到 tick 驱动。
     */
    public static function send():Void {
        var sm:Object = _root.server;
        if (!sm.isSocketConnected) {
            _hnPayload = null;
            return;
        }

        // 实时采集摄像头数据（不缓存，消除 _camStr 状态管理复杂性）
        var gw:MovieClip = _root.gameworld;
        if (!gw) {
            // gameworld 不存在 → 无法构造有效 frame 消息
            _hnPayload = null;
            return;
        }

        var cam:String = gw._x + "|" + gw._y + "|" + (gw._xscale * 0.01);

        // 组装 JSON（hn 可能为 null/空串）
        var hn:String = (_hnPayload != null) ? _hnPayload : "";
        sm.sendSocketMessage('{"task":"frame","cam":"' + cam + '","hn":"' + hn + '"}');

        // 消费后清空所有数据槽
        _hnPayload = null;
    }

    /**
     * 场景切换时重置所有数据槽。
     * 在 SceneChanged 回调中调用，位于 HitNumberBatchProcessor.clear() 之后。
     */
    public static function reset():Void {
        _hnPayload = null;
    }
}
