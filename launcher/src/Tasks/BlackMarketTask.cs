using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 黑市鉴定（匿名影子测试）面板的 AS2 权威注释通道。
    /// 只做一件事：tooltip —— 把 web 的 itemName 透传给 AS2 blackmarketTooltip
    /// （复用 _root.Web物品注释HTML，与商店/情报同一权威注释源），回包包封为
    /// type=panel_resp / panel=blackmarket。不持有物品数据、不落盘、不写游戏状态，
    /// 平衡性调整只改 data/items XML 即可生效，无派生副本漂移。
    /// </summary>
    public sealed class BlackMarketTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
        }

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private int _seq;
        private volatile bool _disposed;

        public BlackMarketTask()
            : this((Func<bool>)null, null)
        {
        }

        public BlackMarketTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); })
        {
        }

        public BlackMarketTask(Func<bool> isClientReady, Action<string> send)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
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

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[BlackMarketTask] webCallId is empty");
                return;
            }

            try
            {
                if (cmd == "tooltip")
                {
                    // 只透传 itemName；身份校验由面板实例绑定（HasExactActivePanelOwnerBinding）
                    // 与 AS2 侧 Web物品注释HTML 的 item_not_found 共同兜底。
                    string itemName = parsed.Value<string>("itemName") ?? "";
                    if (itemName.Length == 0 || itemName.Length > 128)
                    {
                        RespondError(webCallId, cmd, "invalid_item_name");
                        return;
                    }
                    RequestFlash(webCallId, cmd, "blackmarketTooltip", parsed);
                    return;
                }
                RespondError(webCallId, cmd, "unsupported_cmd");
            }
            catch (Exception ex)
            {
                LogManager.Log("[BlackMarketTask] failed: " + ex.Message);
                RespondError(webCallId, cmd, "internal_error");
            }
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null && msg["callId"] != null ? msg.Value<int>("callId") : 0;
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

            try
            {
                ForwardPassThroughResponse(entry.WebCallId, entry.WebCmd, msg);
            }
            catch (Exception ex)
            {
                LogManager.Log("[BlackMarketTask] flash response failed: " + ex.Message);
                RespondError(entry.WebCallId, entry.WebCmd, "internal_error");
            }

            if (respond != null) respond(null);
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
                    WebCmd = webCmd
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

            // 信封构造 + 安全参数透传统一走 PanelBridge（含 action/task 保留键守卫）。
            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);

            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[BlackMarketTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        private void ForwardPassThroughResponse(string webCallId, string webCmd, JObject msg)
        {
            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "blackmarket";
            msg["cmd"] = webCmd;
            msg["callId"] = webCallId;
            PostToWeb(msg.ToString(Formatting.None));
        }

        private JObject BaseResponse(string cmd, string callId, bool success)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "blackmarket";
            resp["cmd"] = cmd;
            resp["callId"] = callId;
            resp["success"] = success;
            return resp;
        }

        private void RespondError(string webCallId, string cmd, string error)
        {
            var resp = BaseResponse(cmd, webCallId, false);
            resp["error"] = error;
            PostToWeb(resp.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_disposed) return;
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_disposed) return; if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null)
                _postToWeb(json);
        }
    }
}
