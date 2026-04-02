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
 *                                      -> AudioBridge.flush() 合批发送本帧 SFX
 *
 * @author FlashNight
 * @version 2.0
 */
class org.flashNight.arki.render.FrameBroadcaster {

    /** hn 数据槽（由 HitNumberBatchProcessor.flush() 写入，send() 消费后清空） */
    private static var _hnPayload:String = null;

    /** fps 数据槽（由 PerformanceScheduler 写入，send() 消费后清空） */
    private static var _fpsPayload:String = null;

    /** UI 状态数据槽（由 watch 回调写入，send() 消费后清空）*/
    private static var _uiPayload:String = null;

    /**
     * 写入 hn 数据槽。
     * 由 HitNumberBatchProcessor.flush() 在 C# overlay 路径中调用。
     * @param payload 序列化后的 hn 条目字符串（分号分隔），可为空串
     */
    public static function setHnPayload(payload:String):Void {
        _hnPayload = payload;
    }

    /**
     * 写入 fps 数据槽。
     * 由 PerformanceScheduler 在采样后调用。
     * @param payload FPS 值字符串（如 "28"）
     */
    public static function setFpsPayload(payload:String):Void {
        _fpsPayload = payload;
    }

    /**
     * 追加 UI 状态 KV 对到数据槽。
     * 由 watch 回调在值变化时调用，多次调用会拼接（同帧内可能多个变量变化）。
     * @param kv 格式 "key:value"，如 "g:1200690"
     */
    public static function pushUiState(kv:String):Void {
        if (_uiPayload == null) {
            _uiPayload = kv;
        } else {
            _uiPayload += "|" + kv;
        }
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

        // 快车道前缀协议：F{cam}\x01{hn}[\x02{fps}]，绕过 C# 端 JObject.Parse
        var hn:String = (_hnPayload != null) ? _hnPayload : "";
        var msg:String = "F" + cam + "\x01" + hn;
        if (_fpsPayload != null) {
            msg += "\x02" + _fpsPayload;
            _fpsPayload = null;
        }
        // UI 状态数据：pushUiState 可能在 send() 之后执行（watch 时序），
        // 因此只在读到数据时才清空，最迟延迟 1 帧到达
        if (_uiPayload != null) {
            msg += "\x03" + _uiPayload;
            _uiPayload = null;
        }
        sm.sendSocketMessage(msg);

        // 消费后清空所有数据槽
        _hnPayload = null;

        // SFX 合批发送（帧内 AudioBridge.playSound() 累积，此处统一发出）
        org.flashNight.arki.audio.AudioBridge.flush();
    }

    /**
     * 场景切换时重置所有数据槽。
     * 在 SceneChanged 回调中调用，位于 HitNumberBatchProcessor.clear() 之后。
     */
    public static function reset():Void {
        _hnPayload = null;
        _fpsPayload = null;
        // 注意：不清空 _uiPayload，场景切换时 UI 快照需要保留到下一帧 send()
        org.flashNight.arki.audio.AudioBridge.reset();
    }
}
