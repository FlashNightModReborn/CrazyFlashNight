using System;
using System.Collections.Generic;
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

            if (!_socket.IsClientReady)
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
                    WebCmd = cmd
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

            var flashMsg = new JObject();
            flashMsg["task"] = "cmd";
            flashMsg["action"] = action;
            flashMsg["callId"] = fid;
            foreach (var prop in parsed.Properties())
            {
                if (prop.Name != "type" && prop.Name != "panel" && prop.Name != "cmd" && prop.Name != "callId")
                    flashMsg[prop.Name] = prop.Value;
            }

            string flashJson = flashMsg.ToString(Newtonsoft.Json.Formatting.None);
            LogManager.Log("[MapTask] → Flash: " + flashJson);
            _socket.Send(flashJson + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[MapTask] ← Flash response received");
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
            msg["panel"] = "map";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = entry.WebCallId;

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
