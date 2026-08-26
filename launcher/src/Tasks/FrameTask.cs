using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.V8;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 处理 Flash 每帧发送的 frame 消息。
    /// 包含摄像头状态（cam）、可选的伤害数字数据（hn）和可选的 FPS 数据。
    ///
    /// 快车道路径（主路径）：
    ///   XmlSocketServer 前缀检测 → HandleRaw(cam, hn, fps)
    ///     绕过 MessageRouter / JObject.Parse，零 GC 分配
    ///
    /// JSON 回退路径（兼容）：
    ///   MessageRouter → Handle(JObject)
    ///     Phase 1 期间保留，确认快车道稳定后由 Phase 3 移除
    ///
    /// 伤害数字调用链：C# span parser → bounded-lifetime reducer → latest-wins overlay。
    /// V8 仅保留 GameInput DFA，不再参与伤害数字状态或渲染描述符。
    /// </summary>
    public class FrameTask
    {
        private readonly V8Runtime _v8;
        private readonly HitNumberOverlay _overlay;
        private readonly HitNumberRuntime _hitNumberRuntime;
        private readonly object _hitNumberLock = new object();
        private readonly FpsRingBuffer _fpsBuffer;
        private PerfDecisionEngine _decisionEngine; // 可空，Phase 1 之前为 null
        private CF7Launcher.Bus.XmlSocketServer _socket; // 用于 K 前缀推送
        private Action<string> _uiDataHandler; // combo hints → WebView2
        private volatile bool _stopped;

        public FpsRingBuffer FpsBuffer { get { return _fpsBuffer; } }

        public void SetDecisionEngine(PerfDecisionEngine engine)
        {
            _decisionEngine = engine;
        }

        public void SetSocket(CF7Launcher.Bus.XmlSocketServer socket)
        {
            if (ReferenceEquals(_socket, socket)) return;
            if (_socket != null) _socket.OnClientReady -= PublishHitNumberSourceState;
            _socket = socket;
            if (_socket != null) _socket.OnClientReady += PublishHitNumberSourceState;
        }

        public void SetUiDataHandler(Action<string> handler)
        {
            _uiDataHandler = handler;
        }

        public FrameTask(V8Runtime v8, HitNumberOverlay overlay)
        {
            _v8 = v8;
            _overlay = overlay;
            _hitNumberRuntime = new HitNumberRuntime();
            _fpsBuffer = new FpsRingBuffer(600);
        }

        /// <summary>停止处理帧数据。在退出前调用，防止推送到已 disposed 的 overlay。</summary>
        public void Stop()
        {
            _stopped = true;
            if (_socket != null) _socket.OnClientReady -= PublishHitNumberSourceState;
            _socket = null;
        }

        public void ConfigureHitNumbers(string mode, int worldRowLimit)
        {
            if (_stopped) return;
            HitNumberRuntimeSnapshot snapshot;
            lock (_hitNumberLock)
            {
                snapshot = _hitNumberRuntime.Configure(
                    HitNumberRuntimeOptions.FromPreferences(mode, worldRowLimit));
            }
            _overlay.UpdateFrame(snapshot);
            PublishHitNumberSourceState();
        }

        public void PublishHitNumberSourceState()
        {
            if (_stopped || _socket == null || !_socket.IsClientReady) return;
            bool enabled;
            lock (_hitNumberLock) enabled = _hitNumberRuntime.Options.SourceEnabled;
            _socket.PushToClient(enabled ? "H1" : "H0");
        }

        /// <summary>
        /// 设置 Web 面板按需读取的场景级伤害对账页。读取与帧 reducer 共用同一把锁，
        /// 不让 Web 请求观察到半批次数据；日志分页不经过 Flash，也不占用战斗键。
        /// </summary>
        public JObject BuildHitNumberLedgerPage(int offset, int limit)
        {
            lock (_hitNumberLock)
                return _hitNumberRuntime.BuildLedgerPage(offset, limit);
        }

        /// <summary>
        /// 加载搓招模组 DFA 数据（由 D 前缀触发）。
        /// </summary>
        public void LoadInputModule(string moduleId, string dataJson)
        {
            if (_stopped) return;
            try
            {
                _v8.LoadInputModule(moduleId, dataJson);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] LoadInputModule error: " + ex.Message);
            }
        }

        /// <summary>
        /// 快车道入口：由 XmlSocketServer 前缀检测直接调用，跳过 JObject 构造。
        /// 格式为 F{cam}\x01{hn}\x02{fps}\x04{inputPayload}，后三段均可为空。
        /// </summary>
        public void HandleRaw(string cam, string hn, string fps, string inputPayload)
        {
            if (_stopped) return;
            try
            {
                HitNumberRuntimeSnapshot hitSnapshot;
                lock (_hitNumberLock)
                    hitSnapshot = _hitNumberRuntime.ProcessFrame(
                        cam,
                        hn);
                _overlay.UpdateFrame(hitSnapshot);

                // 搓招输入处理：解析 \x04 payload -> V8 -> K 前缀推送
                if (!string.IsNullOrEmpty(inputPayload) && _socket != null)
                {
                    // \x04 诊断日志已验证，不再输出
                    // 格式: mask|facingBit|moduleId|doubleTapDir
                    string[] inputParts = inputPayload.Split('|');
                    if (inputParts.Length >= 4)
                    {
                        int mask, facingBit, moduleId, doubleTapDir;
                        if (int.TryParse(inputParts[0], out mask) &&
                            int.TryParse(inputParts[1], out facingBit) &&
                            int.TryParse(inputParts[2], out moduleId) &&
                            int.TryParse(inputParts[3], out doubleTapDir))
                        {
                            string kPayload = _v8.ProcessInput(mask, facingBit, moduleId, doubleTapDir);
                            if (!string.IsNullOrEmpty(kPayload))
                            {
                                _socket.PushToClient("K" + kPayload);

                                // 推送 combo 状态到 WebView2 overlay
                                // kPayload v2: chr(cmdId+0x20)[cmdName]\x01{typed}\x02{hints}
                                if (_uiDataHandler != null && kPayload.Length > 0)
                                {
                                    int rawCmdId = (int)kPayload[0] - 0x20;
                                    int sep1 = kPayload.IndexOf('\x01');
                                    int sep2 = kPayload.IndexOf('\x02');
                                    string cmdName = "";
                                    string typed = "";
                                    string hints = "";
                                    if (sep1 >= 0)
                                    {
                                        if (rawCmdId > 0 && sep1 > 1)
                                            cmdName = kPayload.Substring(1, sep1 - 1);
                                        if (sep2 > sep1)
                                        {
                                            typed = kPayload.Substring(sep1 + 1, sep2 - sep1 - 1);
                                            hints = (sep2 < kPayload.Length - 1) ? kPayload.Substring(sep2 + 1) : "";
                                        }
                                        else
                                        {
                                            typed = kPayload.Substring(sep1 + 1);
                                        }
                                    }
                                    // combo|{cmdName}|{typed}|{hints}
                                    _uiDataHandler("combo|" + cmdName + "|" + typed + "|" + hints);
                                }
                            }
                        }
                    }
                }

                if (!string.IsNullOrEmpty(fps))
                {
                    // 格式：fps|hour|level|epoch
                    string[] parts = fps.Split('|');
                    float fpsVal;
                    if (parts.Length > 0 && float.TryParse(parts[0], out fpsVal))
                        _fpsBuffer.Push(fpsVal);
                    if (parts.Length > 1)
                    {
                        float hour;
                        if (float.TryParse(parts[1], out hour))
                            _fpsBuffer.SetGameHour(hour);
                    }
                    if (parts.Length > 2)
                    {
                        int level;
                        if (int.TryParse(parts[2], out level))
                            _fpsBuffer.SetPerfLevel(level);
                    }
                    if (parts.Length > 3)
                    {
                        int epoch;
                        if (int.TryParse(parts[3], out epoch))
                        {
                            if (_fpsBuffer.SetSceneEpoch(epoch))
                            {
                                // epoch 变化 = 场景切换，触发 warmup
                                _fpsBuffer.NotifySceneReset();
                                if (_decisionEngine != null)
                                    _decisionEngine.OnSceneReset();
                            }
                        }
                    }

                    // 决策引擎：影子模式记录对比，主控模式发送 P 指令
                    if (_decisionEngine != null)
                    {
                        PerfDecision? decision = _decisionEngine.Evaluate();
                        if (decision.HasValue)
                        {
                            if (_decisionEngine.IsActive)
                                _decisionEngine.SendCommand(decision.Value);
                            else
                                _decisionEngine.LogShadowComparison(decision.Value);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] HandleRaw error: " + ex.Message);
            }
        }

        /// <summary>
        /// 快车道入口：hn_reset，由前缀 "R" 触发。
        /// </summary>
        public void HandleReset()
        {
            if (_stopped) return;
            try
            {
                HitNumberRuntimeSnapshot snapshot;
                lock (_hitNumberLock) snapshot = _hitNumberRuntime.Reset();
                _overlay.UpdateFrame(snapshot);
                if (_decisionEngine != null)
                    _decisionEngine.OnSceneReset();
                _fpsBuffer.NotifySceneReset();
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] HandleReset error: " + ex.Message);
            }
        }

        /// <summary>
        /// JSON 回退入口：由 MessageRouter 调用（Phase 1 兼容，Phase 3 移除）。
        /// </summary>
        public string Handle(JObject message)
        {
            if (_stopped) return null;
            try
            {
                string cam = message.Value<string>("cam");
                string hn = message.Value<string>("hn");
                HitNumberRuntimeSnapshot snapshot;
                lock (_hitNumberLock)
                    snapshot = _hitNumberRuntime.ProcessFrame(
                        cam,
                        hn);
                _overlay.UpdateFrame(snapshot);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] Error: " + ex.Message);
            }
            return null; // fire-and-forget
        }
    }
}
