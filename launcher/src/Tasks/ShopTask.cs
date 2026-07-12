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
    /// 商城面板 WebView↔Flash 双层 callId 桥接 + 写请求可靠性门。
    ///
    /// 既有 shop* wire shape 保持不变：
    ///   Web   -> C#    {type:"panel", cmd, callId, ...}
    ///   C#    -> Flash {task:"cmd", action:"shop"+Cmd, callId:fid, ...}
    ///   Flash -> C#    {task:"shop_response", callId:fid, success, ...}
    ///   C#    -> Web   {type:"panel_resp", callId:webCallId, success, ...}
    ///
    /// saveCart / checkoutCommit / legacy checkout / claim 共享单写 owner。写结果超时、断线、发送失败或畸形时进入
    /// needs_reconcile；此后只允许读请求，且只有进入该状态后新发起并成功的 bulkQuery
    /// 能解除写门。活动/近期 callId 不会再次下发 Flash。
    /// </summary>
    public sealed class ShopTask : IDisposable
    {
        private enum WriteGateState
        {
            Idle,
            WritePending,
            NeedsReconcile
        }

        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public bool IsWrite;
            public bool IsReconcileProbe;
            public int ReconcileEpoch;
        }

        private const int DEFAULT_TIMEOUT_MS = 10000;
        private const int RECENT_CALL_ID_CAPACITY = 256;
        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private readonly Func<bool> _isClientReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private readonly HashSet<string> _activeWebCallIds;
        private readonly HashSet<string> _recentWebCallIds;
        private readonly Queue<string> _recentWebCallIdOrder;
        private int _seq;
        private int _writeOwnerFid;
        private int _reconcileEpoch;
        private WriteGateState _writeGate;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        public ShopTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DEFAULT_TIMEOUT_MS)
        {
        }

        public ShopTask(Func<bool> isClientReady, Func<string, bool> trySend)
            : this(isClientReady, trySend, DEFAULT_TIMEOUT_MS)
        {
        }

        public ShopTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _timeoutMs = Math.Max(1, timeoutMs);
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
            _activeWebCallIds = new HashSet<string>(StringComparer.Ordinal);
            _recentWebCallIds = new HashSet<string>(StringComparer.Ordinal);
            _recentWebCallIdOrder = new Queue<string>();
            _writeGate = WriteGateState.Idle;
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        /// <summary>WebView 侧面板请求入口（UI 线程调用）。</summary>
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[ShopTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[ShopTask] webCallId is empty");
                return;
            }
            if (!ValidCallId.IsMatch(webCallId))
            {
                RespondError(webCallId, "invalid_call_id");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(webCallId, "unsupported_cmd");
                return;
            }

            if (!_isClientReady())
            {
                RejectAndRemember(webCallId, "disconnected");
                return;
            }

            int fid = 0;
            string localError = null;
            lock (_lock)
            {
                if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId))
                {
                    LogManager.Log("[ShopTask] duplicate/replayed callId ignored: " + webCallId);
                    return;
                }

                if (isWrite && _writeGate == WriteGateState.WritePending)
                {
                    RememberRecentLocked(webCallId);
                    localError = "busy";
                }
                else if (isWrite && _writeGate == WriteGateState.NeedsReconcile)
                {
                    RememberRecentLocked(webCallId);
                    localError = "reconcile_required";
                }
                else
                {
                    fid = ++_seq;
                    var entry = new PendingRequest
                    {
                        WebCallId = webCallId,
                        WebCmd = cmd,
                        IsWrite = isWrite,
                        IsReconcileProbe = cmd == "bulkQuery" && _writeGate == WriteGateState.NeedsReconcile,
                        ReconcileEpoch = _reconcileEpoch
                    };
                    _pending[fid] = entry;
                    _activeWebCallIds.Add(webCallId);
                    if (isWrite)
                    {
                        _writeGate = WriteGateState.WritePending;
                        _writeOwnerFid = fid;
                    }
                }
            }

            if (localError != null)
            {
                RespondError(webCallId, localError);
                return;
            }

            var timer = new Timer(delegate { HandleTimeout(fid); }, null, _timeoutMs, Timeout.Infinite);
            lock (_lock)
            {
                if (_pending.ContainsKey(fid)) _timers[fid] = timer;
                else timer.Dispose();
            }

            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);
            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[ShopTask] -> Flash: " + flashJson);
            if (!_trySend(flashJson + "\0"))
            {
                HandleSendFailure(fid);
            }
        }

        /// <summary>Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。</summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[ShopTask] <- Flash response received");
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            bool ambiguousWrite = false;
            bool invalidReadResponse = false;

            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
                CompletePendingLocked(fid, entry);

                if (entry.IsWrite && _writeOwnerFid == fid)
                {
                    if (IsDefinitiveWriteResponse(entry.WebCmd, msg))
                    {
                        _writeGate = WriteGateState.Idle;
                        _writeOwnerFid = 0;
                    }
                    else
                    {
                        EnterNeedsReconcileLocked();
                        ambiguousWrite = true;
                    }
                }
                else if (entry.WebCmd == "bulkQuery" && !IsValidBulkResponse(msg))
                {
                    invalidReadResponse = true;
                }
                else if (entry.WebCmd == "checkoutPreview" && !IsValidCheckoutPreviewResponse(msg))
                {
                    invalidReadResponse = true;
                }
                else if (entry.IsReconcileProbe
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && _writeGate == WriteGateState.NeedsReconcile
                    && IsValidSuccessfulBulkResponse(msg))
                {
                    _writeGate = WriteGateState.Idle;
                }
            }

            JObject webMsg = msg != null ? (JObject)msg.DeepClone() : new JObject();
            webMsg.Remove("task");
            webMsg["type"] = "panel_resp";
            webMsg["callId"] = entry.WebCallId;
            if (ambiguousWrite)
            {
                string originalError = webMsg.Value<string>("error");
                webMsg["success"] = false;
                webMsg["error"] = "reconcile_required";
                webMsg["cause"] = string.IsNullOrEmpty(originalError) ? "invalid_response" : originalError;
            }
            else if (invalidReadResponse)
            {
                webMsg["success"] = false;
                webMsg["error"] = "invalid_response";
            }

            PostToWeb(webMsg.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        /// <summary>
        /// 断连/面板强关时清传输 pending。若有已下发写 owner，必须保留 needs_reconcile；
        /// 清理不会清空近期 callId，迟到/重放请求不会再次下发。
        /// </summary>
        public void ClearPending()
        {
            lock (_lock)
            {
                if (_writeGate == WriteGateState.WritePending)
                    EnterNeedsReconcileLocked();

                foreach (var entry in _pending.Values)
                {
                    _activeWebCallIds.Remove(entry.WebCallId);
                    RememberRecentLocked(entry.WebCallId);
                }
                foreach (var timer in _timers.Values) timer.Dispose();
                _timers.Clear();
                _pending.Clear();
                _writeOwnerFid = 0;
            }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "bulkQuery": action = "shopBulkQuery"; return true;
                case "tooltip": action = "shopTooltip"; return true;
                case "saveCart": action = "shopSaveCart"; isWrite = true; return true;
                case "checkoutPreview": action = "shopCheckoutPreview"; return true;
                case "checkoutCommit": action = "shopCheckoutCommit"; isWrite = true; return true;
                case "checkout": action = "shopCheckout"; isWrite = true; return true;
                case "claim": action = "shopClaim"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool IsBoolean(JToken token)
        {
            return token != null && token.Type == JTokenType.Boolean;
        }

        private static bool IsNumber(JToken token)
        {
            return token != null && (token.Type == JTokenType.Integer || token.Type == JTokenType.Float);
        }

        private static bool IsValidBulkResponse(JObject msg)
        {
            JToken success = msg != null ? msg["success"] : null;
            if (!IsBoolean(success)) return false;
            if (!success.Value<bool>()) return !string.IsNullOrEmpty(msg.Value<string>("error"));
            return IsValidSuccessfulBulkResponse(msg);
        }

        private static bool IsValidSuccessfulBulkResponse(JObject msg)
        {
            JToken success = msg != null ? msg["success"] : null;
            return IsBoolean(success)
                && success.Value<bool>()
                && msg["catalog"] != null && msg["catalog"].Type == JTokenType.Array
                && msg["cart"] != null && msg["cart"].Type == JTokenType.Array
                && msg["purchased"] != null && msg["purchased"].Type == JTokenType.Array
                && !string.IsNullOrEmpty(msg.Value<string>("purchasedToken"))
                && IsNumber(msg["kpoints"])
                && IsNumber(msg["playerLevel"])
                && IsNumber(msg["reverseLevel"]);
        }

        private static bool IsValidCheckoutPreviewResponse(JObject msg)
        {
            JToken success = msg != null ? msg["success"] : null;
            if (!IsBoolean(success)) return false;
            if (!success.Value<bool>()) return !string.IsNullOrEmpty(msg.Value<string>("error"));
            return msg.Value<int?>("v") == 1
                && !string.IsNullOrEmpty(msg.Value<string>("checkoutToken"))
                && msg["purchaseLines"] != null && msg["purchaseLines"].Type == JTokenType.Array
                && IsNumber(msg["total"])
                && IsNumber(msg["balance"])
                && IsNumber(msg["projectedBalance"])
                && IsBoolean(msg["canCommit"])
                && msg["blockingError"] != null && msg["blockingError"].Type == JTokenType.String;
        }

        private static bool IsDefinitiveWriteResponse(string cmd, JObject msg)
        {
            JToken success = msg != null ? msg["success"] : null;
            if (!IsBoolean(success)) return false;
            if (success.Value<bool>())
            {
                if (cmd == "checkout" || cmd == "checkoutCommit")
                    return IsNumber(msg["newBalance"])
                        && (cmd != "checkoutCommit" || (msg.Value<int?>("v") == 1
                            && msg["delivered"] != null && msg["delivered"].Type == JTokenType.Array
                            && msg["cart"] != null && msg["cart"].Type == JTokenType.Array))
                        && msg["purchased"] != null && msg["purchased"].Type == JTokenType.Array
                        && !string.IsNullOrEmpty(msg.Value<string>("purchasedToken"));
                if (cmd == "claim")
                    return msg["purchased"] != null && msg["purchased"].Type == JTokenType.Array
                        && !string.IsNullOrEmpty(msg.Value<string>("purchasedToken"));
                return cmd == "saveCart";
            }

            string error = msg.Value<string>("error") ?? "";
            if (cmd == "checkout") return error == "insufficient_kpoints";
            if (cmd == "checkoutCommit") return error == "insufficient_kpoints"
                || error == "inventory_full" || error == "stale_state";
            if (cmd == "claim")
            {
                return error == "item_not_found"
                    || error == "inventory_full"
                    || error == "acquire_failed"
                    || error == "stale_state";
            }
            return false;
        }

        private void HandleTimeout(int fid)
        {
            if (_disposed) return;
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite && _writeOwnerFid == fid) EnterNeedsReconcileLocked();
            }
            RespondError(entry.WebCallId, "timeout");
        }

        private void HandleSendFailure(int fid)
        {
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry)) return;
                CompletePendingLocked(fid, entry);
                if (entry.IsWrite && _writeOwnerFid == fid) EnterNeedsReconcileLocked();
            }
            RespondError(entry.WebCallId, entry.IsWrite ? "reconcile_required" : "disconnected");
        }

        private void CompletePendingLocked(int fid, PendingRequest entry)
        {
            _pending.Remove(fid);
            Timer timer;
            if (_timers.TryGetValue(fid, out timer))
            {
                timer.Dispose();
                _timers.Remove(fid);
            }
            _activeWebCallIds.Remove(entry.WebCallId);
            RememberRecentLocked(entry.WebCallId);
        }

        private void EnterNeedsReconcileLocked()
        {
            _writeGate = WriteGateState.NeedsReconcile;
            _writeOwnerFid = 0;
            _reconcileEpoch++;
        }

        private void RejectAndRemember(string webCallId, string error)
        {
            lock (_lock)
            {
                if (_activeWebCallIds.Contains(webCallId) || _recentWebCallIds.Contains(webCallId))
                {
                    LogManager.Log("[ShopTask] duplicate/replayed rejected callId ignored: " + webCallId);
                    return;
                }
                RememberRecentLocked(webCallId);
            }
            RespondError(webCallId, error);
        }

        private void RememberRecentLocked(string webCallId)
        {
            if (string.IsNullOrEmpty(webCallId) || !_recentWebCallIds.Add(webCallId)) return;
            _recentWebCallIdOrder.Enqueue(webCallId);
            while (_recentWebCallIdOrder.Count > RECENT_CALL_ID_CAPACITY)
            {
                string evicted = _recentWebCallIdOrder.Dequeue();
                _recentWebCallIds.Remove(evicted);
            }
        }

        private void RespondError(string webCallId, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
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
