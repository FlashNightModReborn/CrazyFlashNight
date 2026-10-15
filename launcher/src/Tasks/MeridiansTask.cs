using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 经脉 Web 面板的 AS2 权威桥。
    /// 配置、点亮集、K点余额与情报门槛全部由 Flash（MeridianPanelService）裁决；
    /// C# 只做 cmd→action 映射、fid↔webCallId 转发与超时，不本地判定任何业务结果。
    /// </summary>
    public sealed class MeridiansTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public Action<string> ResponseSink;
        }

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private Action<string> _postToWeb;
        private int _seq;
        private volatile bool _disposed;

        public MeridiansTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); })
        {
        }

        public MeridiansTask(Func<bool> isClientReady, Action<string> send)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string webCallId = parsed == null ? null : parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[MeridiansTask] webCallId is empty");
                return;
            }
            try
            {
                switch (cmd)
                {
                    case "state":
                        RequestFlash(webCallId, cmd, "meridiansState", parsed);
                        break;
                    case "light":
                        RequestFlash(webCallId, cmd, "meridianLight", parsed);
                        break;
                    default:
                        RespondError(webCallId, cmd, "unsupported_cmd");
                        break;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[MeridiansTask] failed: " + ex.Message);
                RespondError(webCallId, cmd, "internal_error");
            }
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg == null ? 0 : msg.Value<int>("callId");
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
                _pending.Remove(fid);
                Timer timer;
                if (_timers.TryGetValue(fid, out timer))
                {
                    timer.Dispose();
                    _timers.Remove(fid);
                }
            }

            Action<string> sink = entry.ResponseSink ?? _postToWeb;
            if (sink != null)
            {
                try
                {
                    ForwardPassThroughResponse(entry.WebCallId, entry.WebCmd, msg);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[MeridiansTask] flash response failed: " + ex.Message);
                    RespondError(entry.WebCallId, entry.WebCmd, "internal_error");
                }
            }
            if (respond != null) respond(null);
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

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        private void RequestFlash(string webCallId, string webCmd, string action, JObject parsed)
        {
            if (!_isClientReady())
            {
                RespondError(webCallId, webCmd, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                _pending[fid] = new PendingRequest
                {
                    WebCallId = webCallId,
                    WebCmd = webCmd,
                    ResponseSink = _postToWeb
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

            // 信封构造走 PanelBridge 单一实现：保留键（action/task 等）不透传，
            // Web 不可覆盖 C# 由 cmd 派生的可信 action。
            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);
            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[MeridiansTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        private void ForwardPassThroughResponse(string webCallId, string webCmd, JObject msg)
        {
            if (msg == null) msg = new JObject();
            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "meridians";
            msg["cmd"] = webCmd;
            msg["callId"] = webCallId;
            PostToWeb(msg.ToString(Formatting.None));
        }

        private void RespondError(string webCallId, string webCmd, string error)
        {
            var resp = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "meridians",
                ["cmd"] = webCmd,
                ["callId"] = webCallId,
                ["success"] = false,
                ["v"] = 1,
                ["error"] = error
            };
            PostToWeb(resp.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            Action<string> post = _postToWeb;
            if (post == null) return;
            post(json);
        }
    }
}
