using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 商城面板 WebView↔Flash 双层 callId 桥接。
    /// JS 发 panel 消息 → C# 分配 flash callId → 转发 Flash → Flash 回包 → 匹配 web callId → PostToWeb。
    /// 10s 超时兜底。全部经 BeginInvoke marshal 到 UI 线程。
    /// </summary>
    public sealed class ShopTask : IDisposable
    {
        private readonly XmlSocketServer _socket;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, string> _pending;   // flash callId → web callId
        private readonly Dictionary<int, Timer> _timers;
        private int _seq;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        public ShopTask(XmlSocketServer socket)
        {
            _socket = socket;
            _pending = new Dictionary<int, string>();
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

        /// <summary>
        /// WebView 侧面板请求入口（UI 线程调用）。
        /// </summary>
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[ShopTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId)) { LogManager.Log("[ShopTask] webCallId is empty"); return; }

            // 断连检测
            if (!_socket.IsClientReady)
            {
                RespondError(webCallId, "disconnected");
                return;
            }

            int fid;
            lock (_lock) { fid = ++_seq; _pending[fid] = webCallId; }

            // 超时 Timer（10s）
            var timer = new Timer(delegate
            {
                if (_disposed) return;
                string wid;
                lock (_lock)
                {
                    if (!_pending.TryGetValue(fid, out wid)) return;
                    _pending.Remove(fid);
                    _timers.Remove(fid);
                }
                RespondError(wid, "timeout");
            }, null, 10000, Timeout.Infinite);
            lock (_lock) { _timers[fid] = timer; }

            // 构造 Flash 命令
            string action = "shop" + char.ToUpper(cmd[0]) + cmd.Substring(1);
            var flashMsg = new JObject();
            flashMsg["task"] = "cmd";
            flashMsg["action"] = action;
            flashMsg["callId"] = fid;
            foreach (var prop in parsed.Properties())
            {
                if (prop.Name != "type" && prop.Name != "cmd" && prop.Name != "callId")
                    flashMsg[prop.Name] = prop.Value;
            }
            string flashJson = flashMsg.ToString(Newtonsoft.Json.Formatting.None);
            LogManager.Log("[ShopTask] → Flash: " + flashJson);
            _socket.Send(flashJson + "\0");
        }

        /// <summary>
        /// Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。
        /// </summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[ShopTask] ← Flash response received");
            int fid = msg.Value<int>("callId");
            string wid;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out wid)) { respond(null); return; }
                _pending.Remove(fid);
                Timer t;
                if (_timers.TryGetValue(fid, out t)) { t.Dispose(); _timers.Remove(fid); }
            }
            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["callId"] = wid;
            string json = msg.ToString(Newtonsoft.Json.Formatting.None);
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            respond(null);
        }

        /// <summary>清除所有 pending 请求（断连时调用）。</summary>
        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (var t in _timers.Values) t.Dispose();
                _timers.Clear();
                _pending.Clear();
            }
        }

        private void RespondError(string webCallId, string error)
        {
            string json = "{\"type\":\"panel_resp\",\"callId\":\"" + webCallId
                        + "\",\"success\":false,\"error\":\"" + error + "\"}";
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
        }
    }
}
