using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 选关面板 WebView<->Flash 双层 callId 桥接。
    /// Stage 2 覆盖 runtime snapshot/enter 与页内 frame 同步。
    ///
    /// P3 协议加固（只加守卫，不改协议语义；AS2 侧零改动）：
    ///   - panelInstanceId：绑定 Host 权威面板实例（SkillTask.BindPanelInstance 同模式），
    ///     路由层（WebOverlayForm）先做 active+instance 校验，本任务内再做兜底；
    ///     换绑 / 关闭即清 pending，旧实例的迟到回包无处可投。
    ///   - sessionGeneration / catalogVersion：Web 请求携带，C# 代封回显进 panel_resp
    ///     （AS2 不回显请求字段，故不回传 Flash，保持 AS2 输入与 P3 前逐字节一致）。
    ///   - stateRevision：snapshot 回包的 C# 侧单调序号，Web 只应用大于已应用值的快照，
    ///     防乱序/迟到 snapshot 覆盖更新状态。
    /// </summary>
    public sealed class StageSelectTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public string PanelInstanceId;
            public long SessionGeneration;   // 0 = Web 未携带（旧客户端，守卫退化关闭）
            public long? CatalogVersion;     // snapshot 请求携带的 manifest version；null = 未携带
        }

        private static readonly Regex ValidOpaque = new Regex("^[A-Za-z0-9._~-]{1,160}$", RegexOptions.Compiled);

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private int _seq;
        private long _stateRevision;
        private string _panelInstanceId;
        private string _lastClosedPanelInstanceId;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        public StageSelectTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); })
        {
        }

        public StageSelectTask(Func<bool> isClientReady, Action<string> send)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        /// <summary>当前绑定的 Host 权威面板实例；null = 未绑定（尚未路由过请求 / 已关闭 / 断线）。</summary>
        public string PanelInstanceId { get { lock (_lock) return _panelInstanceId; } }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        /// <summary>
        /// 绑定 Host 权威 panelInstanceId（SkillTask.BindPanelInstance 同模式）。
        /// 换绑即清旧实例在途请求：其迟到回包随之无处投递，自然失效。
        /// </summary>
        public bool BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            lock (_lock)
            {
                if (string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal)) return true;
                ClearPendingLocked();
                _panelInstanceId = panelInstanceId;
            }
            return true;
        }

        /// <summary>精确实例关闭：仅匹配当前绑定才清 pending 并解绑，旧实例关闭事件不得误清新实例。</summary>
        public bool HandlePanelClosed(string panelInstanceId)
        {
            lock (_lock)
            {
                if (!IsOpaque(panelInstanceId)
                    || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return false;
                ClearPendingLocked();
                _panelInstanceId = null;
                _lastClosedPanelInstanceId = panelInstanceId;
            }
            return true;
        }

        /// <summary>Host 关闭观察器入口（Program.cs SetPanelCloseObserver）：重复事件按 lastClosed 幂等。</summary>
        public bool HandleAuthoritativePanelClosed(string panelInstanceId)
        {
            lock (_lock)
            {
                if (IsOpaque(panelInstanceId)
                    && string.Equals(_lastClosedPanelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return true;
            }
            BindPanelInstance(panelInstanceId);
            return HandlePanelClosed(panelInstanceId);
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[StageSelectTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[StageSelectTask] webCallId is empty");
                return;
            }

            if (!_isClientReady())
            {
                RespondError(webCallId, cmd, "disconnected");
                return;
            }

            string action;
            switch (cmd)
            {
                case "snapshot":
                    action = "stageSelectSnapshot";
                    break;
                case "enter":
                    action = "stageSelectEnter";
                    break;
                case "jump_frame":
                    action = "stageSelectJumpFrame";
                    break;
                case "return_frame":
                    action = "stageSelectReturnFrame";
                    break;
                default:
                    RespondError(webCallId, cmd, "unsupported_cmd");
                    return;
            }

            string requestedInstance = parsed.Value<string>("panelInstanceId");
            string boundInstance;
            lock (_lock) { boundInstance = _panelInstanceId; }
            // 已绑定实例时，请求必须来自同一实例（路由层已校验 active+instance，此处为任务内兜底，
            // 与 SkillTask.HandleWebRequest 的 requestedInstance 检查同位）。未绑定（旧客户端/dev）
            // 不强制，保持 P3 前行为。
            if (IsOpaque(boundInstance)
                && (!IsOpaque(requestedInstance)
                    || !string.Equals(requestedInstance, boundInstance, StringComparison.Ordinal)))
            {
                LogManager.Log("[StageSelectTask] rejected request with stale/missing panelInstanceId: cmd=" + cmd);
                RespondError(webCallId, cmd, "panel_instance_expired");
                return;
            }

            long sessionGeneration = ReadNonNegativeInt64(parsed["sessionGeneration"]);
            long? catalogVersion = cmd == "snapshot" ? ReadOptionalInt64(parsed["catalogVersion"]) : null;

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                _pending[fid] = new PendingRequest
                {
                    WebCallId = webCallId,
                    WebCmd = cmd,
                    PanelInstanceId = boundInstance,
                    SessionGeneration = sessionGeneration,
                    CatalogVersion = catalogVersion
                };
            }

            var timer = new Timer(delegate
            {
                if (_disposed) return;

                PendingRequest entry;
                lock (_lock)
                {
                    if (!_pending.TryGetValue(fid, out entry)) return;
                    _pending.Remove(fid);
                    _timers.Remove(fid);
                }

                RespondError(entry.WebCallId, entry.WebCmd, "timeout", entry.PanelInstanceId);
            }, null, 10000, Timeout.Infinite);

            lock (_lock) { _timers[fid] = timer; }

            // 信封构造 + 安全参数透传统一走 PanelBridge（含 action/task 保留键守卫，杜绝各桥漏抄）。
            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);
            // 会话守卫键不进入 AS2 面：AS2 不回显未知字段，透传只是噪声；剥除后 AS2 输入与 P3 前逐字节一致。
            flashMsg.Remove("panelInstanceId");
            flashMsg.Remove("sessionGeneration");
            flashMsg.Remove("catalogVersion");
            flashMsg.Remove("catalogSchema");

            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[StageSelectTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[StageSelectTask] <- Flash response received");
            int fid = msg.Value<int>("callId");
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    respond(null);
                    return;
                }
                _pending.Remove(fid);
                Timer t;
                if (_timers.TryGetValue(fid, out t))
                {
                    t.Dispose();
                    _timers.Remove(fid);
                }
            }

            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "stage-select";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = entry.WebCallId;
            // C# 代封会话守卫回显（AS2 不回显请求字段）：Web 据此校验 instance+session。
            if (IsOpaque(entry.PanelInstanceId)) msg["panelInstanceId"] = entry.PanelInstanceId;
            if (entry.SessionGeneration > 0) msg["sessionGeneration"] = entry.SessionGeneration;
            if (entry.WebCmd == "snapshot")
            {
                // stateRevision：C# 侧单调序号（跨实例不回退），Web 侧按打开重置比较基准。
                lock (_lock) { msg["stateRevision"] = ++_stateRevision; }
                if (entry.CatalogVersion.HasValue) msg["catalogVersion"] = entry.CatalogVersion.Value;
            }

            string json = msg.ToString(Formatting.None);
            PostToWeb(json);
            respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                ClearPendingLocked();
                // socket 断线 / Dispose：绑定一并复位，重连后由新实例 rebind（SkillTask.ClearPending 同模式）。
                _panelInstanceId = null;
            }
        }

        private void ClearPendingLocked()
        {
            foreach (var t in _timers.Values) t.Dispose();
            _timers.Clear();
            _pending.Clear();
        }

        private void RespondError(string webCallId, string cmd, string error, string panelInstanceId = null)
        {
            string bound = panelInstanceId;
            if (bound == null) { lock (_lock) { bound = _panelInstanceId; } }
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "stage-select";
            resp["cmd"] = cmd;
            resp["callId"] = webCallId;
            if (IsOpaque(bound)) resp["panelInstanceId"] = bound;
            resp["success"] = false;
            resp["error"] = error;
            PostToWeb(resp.ToString(Formatting.None));
        }

        private static bool IsOpaque(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value);
        }

        private static long ReadNonNegativeInt64(JToken token)
        {
            long? value = ReadOptionalInt64(token);
            return value.HasValue && value.Value >= 0 ? value.Value : 0;
        }

        private static long? ReadOptionalInt64(JToken token)
        {
            if (token == null || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) return null;
            double value = token.Value<double>();
            if (double.IsNaN(value) || double.IsInfinity(value) || value > long.MaxValue || value < long.MinValue) return null;
            return (long)value;
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null)
                _postToWeb(json);
        }
    }
}
