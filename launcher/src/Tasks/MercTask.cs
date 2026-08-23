using System;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 佣兵面板 WebView <-> Flash 双层 callId 桥接。
    /// 与 PetTask / ArenaTask 同构：
    ///   Web   -> C#   {type:"panel", panel:"mercs", cmd, callId, panelInstanceId, ...}
    ///   C#    -> Flash {task:"cmd", action:"mercSnapshot/mercHireList/...", callId:fid, ...}
    ///   Flash -> C#   {task:"merc_response", callId:fid, success, ...}
    ///   C#    -> Web   {type:"panel_resp", panel:"mercs", cmd, callId, panelInstanceId, success, ...}
    /// </summary>
    public sealed class MercTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public string PanelInstanceId;
        }

        private const int DefaultTimeoutMs = 10000;
        private static readonly Regex ValidOpaque =
            new Regex("^[A-Za-z0-9._~-]{1,160}$", RegexOptions.Compiled);

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly object _lock = new object();
        private string _panelInstanceId;
        private bool _disposed;

        public MercTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload)
                {
                    return socket != null && socket.TrySend(payload);
                },
                DefaultTimeoutMs)
        {
        }

        public MercTask(Func<bool> isClientReady, Action<string> send)
            : this(isClientReady, AdaptSend(send), DefaultTimeoutMs)
        {
        }

        internal MercTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            int timeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                timeoutMs,
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public string PanelInstanceId
        {
            get { lock (_lock) return _panelInstanceId; }
        }

        public bool BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            lock (_lock)
            {
                if (_disposed) return false;
                if (string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return true;
                _pendingCalls.Clear();
                _panelInstanceId = panelInstanceId;
                return true;
            }
        }

        public void ClearPanelInstance()
        {
            lock (_lock)
            {
                _pendingCalls.Clear();
                _panelInstanceId = null;
            }
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                _panelInstanceId = null;
                _pendingCalls.Dispose();
            }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[MercTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            string requestedInstance = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (!IsOpaque(webCallId))
            {
                LogManager.Log("[MercTask] webCallId is empty");
                return;
            }
            string boundInstance;
            lock (_lock) boundInstance = _disposed ? null : _panelInstanceId;
            if (!IsOpaque(boundInstance)
                || !string.Equals(boundInstance, requestedInstance, StringComparison.Ordinal))
            {
                RespondError(webCallId, cmd, requestedInstance, "panel_instance_expired");
                return;
            }

            if (!_pendingCalls.IsReady())
            {
                RespondError(webCallId, cmd, requestedInstance, "disconnected");
                return;
            }

            string action;
            switch (cmd)
            {
                case "snapshot":
                    action = "mercSnapshot";
                    break;
                case "hire_list":
                    action = "mercHireList";
                    break;
                case "deploy":
                    action = "mercDeploy";
                    break;
                case "dismiss":
                    action = "mercDismiss";
                    break;
                case "hire":
                    action = "mercHire";
                    break;
                case "world_hire":
                    // 世界内雇佣（NPC 处确认）：转发 mercWorldHire；AS2 用 _pendingHireNpc 读权威，
                    // web 不传金额/数据。回 hired:true（前端关面板）。见 设计 §3.3。
                    action = "mercWorldHire";
                    break;
                case "revive":
                    action = "mercRevive";
                    break;
                case "equip_tooltip":
                    action = "mercEquipTooltip";
                    break;
                default:
                    RespondError(webCallId, cmd, requestedInstance, "unsupported_cmd");
                    return;
            }

            int fid;
            bool ownerExpired;
            lock (_lock)
            {
                ownerExpired = _disposed
                    || !string.Equals(
                        _panelInstanceId,
                        requestedInstance,
                        StringComparison.Ordinal);
                if (ownerExpired)
                {
                    fid = 0;
                }
                else if (!_pendingCalls.TryBegin(
                    webCallId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        PanelInstanceId = requestedInstance
                    },
                    out fid)) return;
                else
                {
                    JObject flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);
                    string flashJson = flashMsg.ToString(Formatting.None);
                    LogManager.Log("[MercTask] -> Flash: " + flashJson);
                    _pendingCalls.Send(fid, flashJson + "\0");
                }
            }
            if (ownerExpired)
                RespondError(webCallId, cmd, requestedInstance, "panel_instance_expired");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[MercTask] <- Flash response received");
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PanelPendingCall<PendingRequest> pendingCall;
            if (!_pendingCalls.TryComplete(fid, out pendingCall))
            {
                if (respond != null) respond(null);
                return;
            }
            PendingRequest entry = pendingCall.Context;

            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "mercs";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = pendingCall.WebCallId;
            msg["panelInstanceId"] = entry.PanelInstanceId;

            string json = msg.ToString(Formatting.None);
            PostToWeb(json);
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock) _pendingCalls.Clear();
        }

        internal int PendingCountForTest
        {
            get { return _pendingCalls.PendingCount; }
        }

        private void RespondError(
            string webCallId, string cmd, string panelInstanceId, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "mercs";
            resp["cmd"] = cmd;
            resp["callId"] = webCallId;
            resp["panelInstanceId"] = panelInstanceId ?? "";
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

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            if (reason == PanelPendingCallEndReason.Cleared) return;
            PendingRequest entry = pendingCall.Context;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                entry.PanelInstanceId,
                reason == PanelPendingCallEndReason.Timeout
                    ? "timeout"
                    : "delivery_unknown");
        }

        private static Func<string, bool> AdaptSend(Action<string> send)
        {
            return delegate(string payload)
            {
                if (send == null) return false;
                send(payload);
                return true;
            };
        }

        private static bool IsOpaque(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value);
        }
    }
}
