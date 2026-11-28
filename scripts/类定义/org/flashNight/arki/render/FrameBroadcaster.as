/**
 * FrameBroadcaster - 帧末统一广播器
 *
 * 职责：收集摄像头数据 + 读取各子系统数据槽 → 发送单条 frame 消息到 C# 启动器。
 * 在 frameEnd 管线中作为最后一步调用，确保每帧恰好发送一条 frame 消息。
 *
 * 传输协议（快车道）：
 *   send() 使用前缀协议 "F{cam}\x01{hn}[\x05{bulletVisual}]" 直达 C# 端 FrameTask.HandleRaw()，
 *   绕过 MessageRouter 的 JObject.Parse，消除每帧 JSON 解析开销。
 *   - 前缀 "F" 标识 frame 快车道消息（C# 按首字节分发）
 *   - cam 格式: "gw._x|gw._y|scale"（管道符分隔）
 *   - \x01 (SOH) 分隔 cam 与 hn（cam/hn 内容只含 |;数字文本，不含 \x01）
 *   - hn 格式: "value|x|y|packed|efText|efEmoji|lifeSteal|shieldAbsorb|unitId|burstId|expectedHitCount;..."
 *     （分号分条目；C# 按严格 11 字段解析）
 *   - bulletVisual 为配套 Host 协商后才发送的有界影子快照，旧 Host 无此段
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
    // Bounded latest HUD state, independent of the append-only legacy UI slot.
    private static var _playerHudPayload:String = null;
    private static var _playerHudCapture:Function;
    public static function setPlayerHudPayload(value:String):Void { _playerHudPayload = value; }
    public static function hasPlayerHudPending():Boolean { return _playerHudPayload != null; }
    public static function retireWorkerProjectionSlots():Void {
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("playerHud")) _playerHudPayload = null;
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("ordinaryBullet")) _bulletVisualPayload = null;
    }
    public static function setPlayerHudCapture(callback:Function):Void { _playerHudCapture = callback; }


    /** 首批普通/枪式联弹影子视觉快照；仅在配套 Host 明确协商后填充。 */
    private static var _bulletVisualPayload:String = null;
    public static function setBulletVisualPayload(value:String):Void { _bulletVisualPayload = value; }
    private static var _combatFxPayload:String = null;
    public static function setCombatFxPayload(value:String):Void { _combatFxPayload = value; }

    // Frame origins and K queues use the versioned input frame identity.
    private static var _versionedInput:Object;
    private static var _versionedOrigins:Array = [];
    private static var _versionedCommands:Array = [];
    private static var _versionedHead:Number = 0;
    private static var _versionedCount:Number = 0;
    private static var _versionedSeq:Number = 0;
    private static var _versionedCommandFrame:Number = 0;
    private static var _versionedHints:Object;

    /** Launcher 返回的搓招可视化提示 */
    private static var _comboHints:String = "";

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
        org.flashNight.neur.Server.Issue205SourceProbe.mark(8);
    }

    public static function setVersionedInput(sample:Object):Void {
        _versionedInput = sample;
    }

    public static function clearVersionedScope():Void {
        _versionedInput = null;
        // Keep bounded provenance for already-sent results: Host commandSeq
        // still advances in this epoch, but an old scope can no longer import.
        for (var i:Number = 0; i < _versionedOrigins.length; ++i) {
            var origin:Object = _versionedOrigins[i];
            if (origin != null) origin.retired = true;
        }
        _versionedCommands.length = 0;
        _versionedHead = 0;
        _versionedCount = 0;
        _versionedHints = null;
        _comboHints = "";
    }

    public static function advanceVersionedConfig():Boolean {
        clearVersionedScope();
        var cell:Object = _root.GameInput;
        if (cell.configInc == 2147483647) {
            cell.configExhausted = true;
            _root.server.faultPassiveCombo("input_config_exhausted");
            return false;
        }
        ++cell.configInc;
        return true;
    }

    public static function cancelVersionedInput():Void {
        clearVersionedScope();
    }

    public static function beginVersionedInputEpoch():Void {
        cancelVersionedInput();
        _versionedOrigins.length = 0;
        _versionedSeq = 0;
        _versionedCommandFrame = 0;
        var cell:Object = _root.GameInput;
        cell.lastCommandSeq = 0;
        cell.lastImportedCommandSeq = 0;
    }

    private static function sameVersionedOrigin(a:Object, b:Object):Boolean {
        return a != null && b != null && a.epoch === b.epoch
            && a.actorInc === b.actorInc && a.moduleId === b.moduleId
            && a.moduleInc === b.moduleInc && a.configInc === b.configInc;
    }

    public static function stageVersionedResult(result:Object):String {
        var cell:Object = _root.GameInput;
        var origin:Object = _versionedOrigins[result.inputFrameSeq & 63];
        if (origin == null || origin.inputFrameSeq !== result.inputFrameSeq || !sameVersionedOrigin(origin, result)) {
            cell.lastRejectedComboSeq = result.commandSeq;
            return null;
        }
        if (result.cmdId > 0) {
            if (result.commandSeq <= _versionedSeq) return null;
            if (result.commandSeq !== _versionedSeq + 1) return origin.retired === true ? null : "combo_sequence";
            // Host sequences commands across config/module switches within the same epoch.
            // Account for an in-order stale result without admitting it to the gameplay queue.
            _versionedSeq = result.commandSeq;
            cell.lastCommandSeq = _versionedSeq;
        }

        if (origin.retired === true) {
            cell.lastRejectedComboSeq = result.commandSeq;
            return null;
        }
        if (origin.pulse) {
            cell.lastPulseFrame = origin.wire;
            cell.lastPulseResult = result.wire;
        }
        delete result.wire;
        if (result.cmdId == 0) {
            if (_versionedHints == null || result.inputFrameSeq >= _versionedHints.inputFrameSeq)
                _versionedHints = result;
            return null;
        }
        if (result.inputFrameSeq < _versionedCommandFrame) return "combo_frame_order";
        if (_versionedCount == 32) return "combo_queue_overflow";
        _versionedCommandFrame = result.inputFrameSeq;
        result.origin = origin;
        _versionedCommands[(_versionedHead + _versionedCount) & 31] = result;
        ++_versionedCount;
        return null;
    }

    public static function takeVersionedCommand(scope:Object, bufferReady:Boolean):Object {
        if (_versionedHints != null) {
            if (sameVersionedOrigin(_versionedHints, scope)) _comboHints = _versionedHints.hintsJson;
            _versionedHints = null;
        }
        if (!bufferReady) return null;
        var cell:Object = _root.GameInput;
        while (_versionedCount > 0) {
            var result:Object = _versionedCommands[_versionedHead];
            _versionedCommands[_versionedHead] = null;
            _versionedHead = (_versionedHead + 1) & 31;
            --_versionedCount;
            if (sameVersionedOrigin(result, scope)
                    && _versionedOrigins[result.inputFrameSeq & 63] === result.origin) {
                cell.lastImportedCommandSeq = result.commandSeq;
                cell.comboImportCount = (cell.comboImportCount | 0) + 1;
                return result;
            }
            cell.lastRejectedComboSeq = result.commandSeq;
        }
        return null;
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
     * 每帧无条件调用（只要 socket 连接），保证 C# reducer 的自然寿命动画持续推进。
     */
    public static function send():Void {
        org.flashNight.neur.Server.Issue205SourceProbe.mark(4);
        org.flashNight.arki.weather.NightVisionUnitTint.tick();
        var sm:Object = _root.server;
        var cell:Object = _root.GameInput;
        if (cell.passiveActive === true) cell.recordPhase("frameEnd", sm.currentFrame);
        if (!sm.isSocketConnected) {
            org.flashNight.neur.Server.Issue205SourceProbe.mark(9);
            _hnPayload = null;
            _playerHudPayload = null;
            _bulletVisualPayload = null;
            _combatFxPayload = null;
            org.flashNight.arki.render.NativeFrameTag.hide();
            return;
        }

        // 实时采集摄像头数据（不缓存，消除 _camStr 状态管理复杂性）
        var gw:MovieClip = _root.gameworld;
        if (!gw) {
            org.flashNight.neur.Server.Issue205SourceProbe.mark(10);
            // gameworld 不存在 → 无法构造有效 frame 消息
            _hnPayload = null;
            _playerHudPayload = null;
            _bulletVisualPayload = null;
            _combatFxPayload = null;
            org.flashNight.arki.render.NativeFrameTag.hide();
            return;
        }

        // Capture after this frame's domain updates, immediately before consuming the bounded slot.
        // Installed from BootSequencer to avoid a class-registration dependency cycle.
        if (_playerHudCapture != undefined) _playerHudCapture();
        var cam:String = gw._x + "|" + gw._y + "|" + (gw._xscale * 0.01);

        // 快车道前缀协议：F{cam}\x01{hn}[\x02{fps}]，绕过 C# 端 JObject.Parse
        var hn:String = (_hnPayload != null) ? _hnPayload : "";
        var msg:String = "F" + cam + "\x01" + hn;
        org.flashNight.neur.Server.Issue205SourceProbe.mark(5);
        if (_fpsPayload != null) {
            msg += "\x02" + _fpsPayload;
            _fpsPayload = null;
        }
        // UI 状态数据：pushUiState 可能在 send() 之后执行（watch 时序），
        // 因此只在读到数据时才清空，最迟延迟 1 帧到达
        if (_uiPayload != null || _playerHudPayload != null) {
            msg += "\x03";
            if (_uiPayload != null) msg += _uiPayload;
            if (_playerHudPayload != null) msg += (_uiPayload != null ? "|" : "") + _playerHudPayload;
            _uiPayload = null;
            _playerHudPayload = null;
        }
        var inputOrigin:Object = null;
        var sample:Object = _versionedInput;
        _versionedInput = null;
        if (cell.passiveActive === true && cell.bound === true && cell.gateOpen === true && sample != null) {
            var snapshot:Object = cell.snapshot;
            if (sample.systemFrame === sm.currentFrame && sample.systemFrame === snapshot.systemFrame
                    && sample.actorInc === cell.actorInc && sample.moduleInc === cell.moduleInc
                    && sample.configInc === cell.configInc && sample.inputFrameSeq === snapshot.inputFrameSeq
                    && sample.epoch === snapshot.keyboardEpoch) {
                var inputWire:String = "I1|" + cell.sessionId + "|" + cell.connectionIncarnation + "|" + sample.epoch
                    + "|" + sample.inputFrameSeq + "|" + sample.actorInc + "|" + sample.moduleId
                    + "|" + sample.moduleInc + "|" + sample.configInc + "|" + sample.mask + "|" + sample.facingBit
                    + "|" + sample.doubleTapDir + "|" + sample.atomCount + "|" + sample.atoms;
                msg += "\x04" + inputWire;
                if (sample.pulse) sample.wire = inputWire;
                inputOrigin = sample;
            }
        }
        if (_bulletVisualPayload != null) {
            msg += "\x05" + _bulletVisualPayload;
            _bulletVisualPayload = null;
        }
        if (_combatFxPayload != null) {
            msg += "\x06" + _combatFxPayload;
            _combatFxPayload = null;
        }
        // Ordered visual events are consumed exactly once after all game updates.
        var rayPayload:String = org.flashNight.arki.render.RayVisualBridge.flush();
        if (rayPayload != null) msg += "\x07" + rayPayload;
        var chainPayload:String = org.flashNight.arki.render.ChainVisualBridge.flush();
        if (chainPayload != null) msg += "\x08" + chainPayload;
        var sceneLightPayload:String = org.flashNight.arki.render.SceneLightBridge.flush();
        if (sceneLightPayload != null) msg += "\x09" + sceneLightPayload;
        // SFX 优先发送：音效对延迟敏感，必须在 F 消息（含伤害 reducer/绘制）之前到达 C# 端。
        org.flashNight.arki.audio.AudioBridge.flush();
        org.flashNight.arki.render.NativeFrameTag.update(_root,
            chainPayload != null ? org.flashNight.arki.render.BulletVisualProbe.nativeEpoch() : -1,
            Number(_root.帧计时器.当前帧数));

        org.flashNight.neur.Server.Issue205SourceProbe.mark(6);
        if (sm.sendSocketMessage(msg) && inputOrigin != null) {
            _versionedOrigins[inputOrigin.inputFrameSeq & 63] = inputOrigin;
            cell.recordPhase("comboSent", sm.currentFrame);
        }
        org.flashNight.neur.Server.Issue205SourceProbe.mark(7);

        // 消费后清空所有数据槽
        _hnPayload = null;
    }

    // Hooked by protocol_latency_cycle.ps1 in its standalone benchmark VM.
    // The default callback carries no command or hint state.
    public static function receiveK(payload:String):Void {
    }

    /** 获取 Launcher 返回的搓招可视化提示 */
    public static function getComboHints():String {
        return _comboHints;
    }

    /**
     * 场景切换时重置所有数据槽。
     * 在 SceneChanged 回调中调用，位于 HitNumberBatchProcessor.clear() 之后。
     */
    public static function reset():Void {
        org.flashNight.arki.render.CombatFxBridge.resetScene();
        if (_root.GameInput.passiveActive === true) clearVersionedScope();
        _hnPayload = null;
        _playerHudPayload = null;
        _fpsPayload = null;
        _bulletVisualPayload = null;
        _combatFxPayload = null;
        org.flashNight.arki.render.BulletVisualProbe.resetScene();
        org.flashNight.arki.render.RayVisualBridge.resetScene();
        org.flashNight.arki.render.ChainVisualBridge.resetScene();
        // 注意：不清空 _uiPayload，场景切换时 UI 快照需要保留到下一帧 send()
        _comboHints = "";
        org.flashNight.arki.audio.AudioBridge.reset();
        org.flashNight.arki.render.NativeFrameTag.reset();
    }
}
