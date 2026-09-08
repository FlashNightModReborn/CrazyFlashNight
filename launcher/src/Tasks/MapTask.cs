using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 地图面板 WebView↔Flash 双层 callId 桥接。
    /// 语义与 ShopTask 对齐，但附带 panel/cmd 元数据，便于 Web 端按命令分流。
    /// </summary>
    public sealed class MapTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public string PanelInstanceId;
        }

        private readonly XmlSocketServer _socket;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private int _seq;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        public MapTask(XmlSocketServer socket)
        {
            _socket = socket;
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            lock (_lock)
            {
                foreach (var t in _timers.Values) t.Dispose();
                _timers.Clear();
                _pending.Clear();
            }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[MapTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[MapTask] webCallId is empty");
                return;
            }

            if (cmd == "return_base" && !IsValidReturnBaseRequest(parsed))
            {
                RespondError(webCallId, cmd, "invalid_payload");
                return;
            }
            if (!_socket.TryGetReadyGeneration(out int generation))
            {
                RespondError(webCallId, cmd, "disconnected");
                return;
            }

            string action;
            switch (cmd)
            {
                case "snapshot":
                case "refresh":
                    action = "mapPanelSnapshot";
                    break;
                case "navigate":
                    action = "mapPanelNavigate";
                    break;
                case "return_base":
                    action = "mapPanelReturnBase";
                    break;
                default:
                    RespondError(webCallId, cmd, "unsupported_cmd");
                    return;
            }

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                _pending[fid] = new PendingRequest
                {
                    WebCallId = webCallId,
                    WebCmd = cmd,
                    PanelInstanceId = parsed.Value<string>("panelInstanceId")
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

                RespondError(entry.WebCallId, entry.WebCmd, "timeout");
            }, null, 10000, Timeout.Infinite);

            lock (_lock) { _timers[fid] = timer; }

            // 信封构造 + 安全参数透传统一走 PanelBridge（含 action/task 保留键守卫，杜绝各桥漏抄）。
            var flashMsg = cmd == "return_base"
                ? new JObject { ["task"] = "cmd", ["action"] = action, ["callId"] = fid,
                    ["v"] = 1, ["token"] = parsed["token"] }
                : PanelBridge.BuildFlashCommand(action, fid, parsed);

            string flashJson = flashMsg.ToString(Newtonsoft.Json.Formatting.None);
            LogManager.Log("[MapTask] → Flash: " + flashJson);
            if (!_socket.TrySendIfGen(flashJson + "\0", generation))
            {
                lock (_lock)
                {
                    _pending.Remove(fid);
                    if (_timers.Remove(fid, out var failedTimer)) failedTimer.Dispose();
                }
                RespondError(webCallId, cmd, "disconnected");
            }
        }

        internal static bool IsValidReturnBaseRequest(JObject request)
        {
            string[] keys = { "type", "panel", "cmd", "callId", "panelInstanceId", "v", "token" };
            return request != null && request.Properties().All(p => keys.Contains(p.Name))
                && request["type"]?.Type == JTokenType.String && (string)request["type"] == "panel"
                && request["panel"]?.Type == JTokenType.String && (string)request["panel"] == "map"
                && request["cmd"]?.Type == JTokenType.String && (string)request["cmd"] == "return_base"
                && request["v"]?.Type == JTokenType.Integer && (long)request["v"] == 1
                && request["panelInstanceId"]?.Type == JTokenType.String
                && !string.IsNullOrEmpty((string)request["panelInstanceId"])
                && request["token"]?.Type == JTokenType.String
                && System.Text.RegularExpressions.Regex.IsMatch((string)request["token"], @"\Amap-return-[1-9][0-9]{0,14}\z");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[MapTask] ← Flash response received");
            if (msg?["callId"]?.Type != JTokenType.Integer
                    || (long)msg["callId"] <= 0 || (long)msg["callId"] > int.MaxValue)
            { respond(null); return; }
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

            if (entry.WebCmd == "return_base" && (msg["success"]?.Type != JTokenType.Boolean
                    || (msg.Value<bool>("success") && (msg["closePanel"]?.Type != JTokenType.Boolean
                        || !msg.Value<bool>("closePanel")))))
                msg = new JObject { ["success"] = false, ["error"] = "outcome_unknown" };
            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "map";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = entry.WebCallId;
            if (!string.IsNullOrEmpty(entry.PanelInstanceId)) msg["panelInstanceId"] = entry.PanelInstanceId;

            string json = msg.ToString(Newtonsoft.Json.Formatting.None);
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (var t in _timers.Values) t.Dispose();
                _timers.Clear();
                _pending.Clear();
            }
        }

        private void RespondError(string webCallId, string cmd, string error)
        {
            string json = "{\"type\":\"panel_resp\",\"panel\":\"map\",\"cmd\":\"" + cmd
                        + "\",\"callId\":\"" + webCallId
                        + "\",\"success\":false,\"error\":\"" + error + "\"}";
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
        }
    }
}
