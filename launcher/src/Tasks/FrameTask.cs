using System;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
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
    /// 共同调用链：
    ///   → V8 updateCamera + spawnBatch + tick（V8 lock 内）
    ///   → overlay.UpdateRender（BeginInvoke → UI 线程）
    /// </summary>
    public class FrameTask
    {
        private readonly V8Runtime _v8;
        private readonly HitNumberOverlay _overlay;
        private readonly FpsRingBuffer _fpsBuffer;
        private PerfDecisionEngine _decisionEngine; // 可空，Phase 1 之前为 null
        private CF7Launcher.Bus.XmlSocketServer _socket; // 用于 K 前缀推送
        private Action<string> _uiDataHandler; // combo hints → WebView2
        private volatile bool _stopped;
        private bool _inputPayloadLogged; // 首次收到 inputPayload 时输出一次日志

        public FpsRingBuffer FpsBuffer { get { return _fpsBuffer; } }

        public void SetDecisionEngine(PerfDecisionEngine engine)
        {
            _decisionEngine = engine;
        }

        public void SetSocket(CF7Launcher.Bus.XmlSocketServer socket)
        {
            _socket = socket;
        }

        public void SetUiDataHandler(Action<string> handler)
        {
            _uiDataHandler = handler;
        }

        public FrameTask(V8Runtime v8, HitNumberOverlay overlay)
        {
            _v8 = v8;
            _overlay = overlay;
            _fpsBuffer = new FpsRingBuffer(600);
        }

        /// <summary>停止处理帧数据。在退出前调用，防止推送到已 disposed 的 overlay。</summary>
        public void Stop() { _stopped = true; }

        /// <summary>
        /// 快车道入口：由 XmlSocketServer 前缀检测直接调用，跳过 JObject 构造。
        /// 前缀协议格式：F{cam}\x01{hn}\x02{fps}
        /// fps 字段可选（仅在有新采样时存在）。
        /// </summary>
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

        public void HandleRaw(string cam, string hn, string fps, string inputPayload)
        {
            if (_stopped) return;
            try
            {
                if (!string.IsNullOrEmpty(cam))
                    _v8.UpdateCamera(cam);

                if (!string.IsNullOrEmpty(hn))
                    _v8.SpawnBatch(hn);

                string renderStr = _v8.Tick();
                _overlay.UpdateRender(renderStr);

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
                _v8.Reset();
                _overlay.NotifyReset();
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
            try
            {
                string cam = message.Value<string>("cam");
                if (!string.IsNullOrEmpty(cam))
                    _v8.UpdateCamera(cam);

                string hn = message.Value<string>("hn");
                if (!string.IsNullOrEmpty(hn))
                    _v8.SpawnBatch(hn);

                string renderStr = _v8.Tick();
                _overlay.UpdateRender(renderStr);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Frame] Error: " + ex.Message);
            }
            return null; // fire-and-forget
        }
    }
}
