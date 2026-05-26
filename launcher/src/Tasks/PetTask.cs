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
    /// 战宠面板 WebView ↔ Flash 双层 callId 桥接。
    /// 与 ArenaTask / ShopTask 同构：
    ///   Web → C#   {type:"panel", panel:"pets", cmd, callId, ...}
    ///   C# → Flash {task:"cmd", action:"petSnapshot/petAdopt/...", callId:fid, ...}
    ///   Flash → C# {task:"pet_response", callId:fid, success, ...}
    ///   C# → Web   {type:"panel_resp", panel:"pets", cmd, callId, success, ...}
    ///
    /// 注意：close 不走本桥。Web 关闭面板时 WebOverlayForm.HandlePanelMessage 直接
    /// 切 _activePanel = null + ClosePanel()。
    /// </summary>
    public sealed class PetTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
        }

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private int _seq;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        public PetTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); })
        {
        }

        public PetTask(Func<bool> isClientReady, Action<string> send)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        /// <summary>
        /// WebView 侧面板请求入口（UI 线程调用）。
        /// </summary>
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[PetTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[PetTask] webCallId is empty");
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
                    action = "petSnapshot";
                    break;
                case "adopt_list":
                    action = "petAdoptList";
                    break;
                case "adopt":
                    action = "petAdopt";
                    break;
                case "deploy":
                    action = "petDeploy";
                    break;
                case "advance":
                    action = "petAdvance";
                    break;
                case "preview_advance":
                    action = "petPreviewAdvance";
                    break;
                case "expand_slot":
                    action = "petExpandSlot";
                    break;
                case "rename":
                    action = "petRename";
                    break;
                case "pet_tooltip":
                    action = "petTooltip";
                    break;
                case "restore_stamina":
                    action = "petRestoreStamina";
                    break;
                case "level_up":
                    action = "petLevelUp";
                    break;
                case "delete":
                    action = "petDelete";
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

            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[PetTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        /// <summary>
        /// Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。
        /// </summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[PetTask] <- Flash response received");
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
            msg["panel"] = "pets";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = entry.WebCallId;

            string json = msg.ToString(Formatting.None);
            PostToWeb(json);
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
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "pets";
            resp["cmd"] = cmd;
            resp["callId"] = webCallId;
            resp["success"] = false;
            resp["error"] = error;
            PostToWeb(resp.ToString(Formatting.None));
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
