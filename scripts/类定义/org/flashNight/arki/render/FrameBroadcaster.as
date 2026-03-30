/**
 * FrameBroadcaster - 帧末统一广播器
 *
 * 职责：收集摄像头数据 + 读取各子系统数据槽 → 发送单条 frame 消息到 C# 启动器。
 * 在 frameEnd 管线中作为最后一步调用，确保每帧恰好发送一条 frame 消息。
 *
 * 传输协议（快车道）：
 *   send() 使用前缀协议 "F{cam}\x01{hn}" 直达 C# 端 FrameTask.HandleRaw()，
 *   绕过 MessageRouter 的 JObject.Parse，消除每帧 JSON 解析开销。
 *   - 前缀 "F" 标识 frame 快车道消息（C# 按首字节分发）
 *   - cam 格式: "gw._x|gw._y|scale"（管道符分隔）
 *   - \x01 (SOH) 分隔 cam 与 hn（cam/hn 内容只含 |;数字文本，不含 \x01）
 *   - hn 格式: "value|x|y|packed|efText|efEmoji|lifeSteal|shieldAbsorb;..." (分号分条目)
 *
 * 架构：
 *   frameEnd pipeline:
 *     HitNumberBatchProcessor.flush()  -> setHnPayload(buf)
 *     RayVfxManager.update()           -> 将来可增加 setRayPayload()
 *     FrameBroadcaster.send()          -> 收集 cam + 消费数据槽 -> sendSocketMessage
 *
 * @author FlashNight
 * @version 2.0
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

        // 快车道前缀协议：F{cam}\x01{hn}，绕过 C# 端 JObject.Parse
        var hn:String = (_hnPayload != null) ? _hnPayload : "";
        sm.sendSocketMessage("F" + cam + "\x01" + hn);

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
