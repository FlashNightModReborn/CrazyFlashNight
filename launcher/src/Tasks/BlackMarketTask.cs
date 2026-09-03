using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    internal sealed class BlackMarketObservationSnapshot
    {
        public long RouteSequence { get; set; }
        public long LastCompletedRouteSequence { get; set; }
        public int OutstandingCount { get; set; }
        public int BusinessOutstandingCount { get; set; }
        public string OutstandingOwner { get; set; }
        public string As2TupleState { get; set; }
        public string BusinessOwner { get; set; }
        public string PauseOwner { get; set; }
        public string SceneOwner { get; set; }
        public long FrameSequence { get; set; }
    }

    /// <summary>
    /// 黑市鉴定（匿名影子测试）面板的 AS2 权威注释通道。
    /// 产品路径只做 tooltip —— 把 web 的 itemName 透传给 AS2 blackmarketTooltip
    /// （复用 _root.Web物品注释HTML，与商店/情报同一权威注释源），回包包封为
    /// type=panel_resp / panel=blackmarket。不持有物品数据、不落盘、不写游戏状态，
    /// 平衡性调整只改 data/items XML 即可生效，无派生副本漂移。另有一个默认关闭的
    /// O1 临时观测 lane；它只读取有界 owner tuple，不向 Web 暴露、不参与产品状态。
    /// </summary>
    public sealed class BlackMarketTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
            public bool ObservationOnly;
            public long RouteSequence;
        }

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private int _seq;
        private long _routeSequence;
        private long _lastCompletedRouteSequence;
        private string _as2TupleState = "missing";
        private string _businessOwner = "none";
        private string _pauseOwner = "unknown";
        private string _sceneOwner = "unknown";
        private long _frameSequence = -1;
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
                ResetObservationLocked(true);
            }
        }

        /// <summary>
        /// Retires only the temporary O1 observation lane when the exact blackmarket
        /// document closes/rebinds. User tooltip requests keep their existing behavior.
        /// </summary>
        public void RetireObservation()
        {
            lock (_lock)
            {
                var remove = new List<int>();
                foreach (KeyValuePair<int, PendingRequest> pair in _pending)
                {
                    if (pair.Value.ObservationOnly) remove.Add(pair.Key);
                }
                foreach (int fid in remove) _pending.Remove(fid);
                ResetObservationLocked(false);
            }
        }

        /// <summary>
        /// Starts at most one generation-bound, read-only AS2 owner probe. There is
        /// intentionally no timer, retry, repair, socket close or business mutation.
        /// A still-outstanding probe is merely observed by later heartbeats.
        /// </summary>
        internal BlackMarketObservationSnapshot ObserveHeartbeat(
            int socketGeneration,
            Func<string, int, bool> sendIfGeneration)
        {
            int fid = 0;
            string flashJson = null;
            lock (_lock)
            {
                bool hasObservation = false;
                foreach (PendingRequest pending in _pending.Values)
                {
                    if (pending.ObservationOnly)
                    {
                        hasObservation = true;
                        break;
                    }
                }
                if (!_disposed && socketGeneration > 0
                    && sendIfGeneration != null && !hasObservation)
                {
                    fid = ++_seq;
                    long route = ++_routeSequence;
                    _pending[fid] = new PendingRequest
                    {
                        WebCallId = null,
                        WebCmd = "observation",
                        ObservationOnly = true,
                        RouteSequence = route
                    };
                    flashJson = PanelBridge.BuildFlashCommand(
                        "blackmarketObservation", fid, null)
                        .ToString(Formatting.None) + "\0";
                }
            }

            if (fid != 0)
            {
                bool sent = false;
                try { sent = sendIfGeneration(flashJson, socketGeneration); }
                catch { sent = false; }
                if (!sent)
                {
                    lock (_lock)
                    {
                        PendingRequest pending;
                        if (_pending.TryGetValue(fid, out pending)
                            && pending.ObservationOnly)
                        {
                            _pending.Remove(fid);
                        }
                    }
                }
            }

            lock (_lock) return CaptureObservationLocked();
        }

        internal BlackMarketObservationSnapshot CaptureObservation()
        {
            lock (_lock) return CaptureObservationLocked();
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


            if (entry.ObservationOnly)
            {
                lock (_lock)
                {
                    _lastCompletedRouteSequence = entry.RouteSequence;
                    CaptureAs2TupleLocked(msg != null
                        ? msg["observationTuple"] as JObject
                        : null);
                }
                if (respond != null) respond(null);
                return;
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
                long route = ++_routeSequence;
                _pending[fid] = new PendingRequest
                {
                    WebCallId = webCallId,
                    WebCmd = webCmd,
                    ObservationOnly = false,
                    RouteSequence = route
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

        private void ResetObservationLocked(bool resetRouteSequence)
        {
            if (resetRouteSequence) _routeSequence = 0;
            _lastCompletedRouteSequence = 0;
            _as2TupleState = "missing";
            _businessOwner = "none";
            _pauseOwner = "unknown";
            _sceneOwner = "unknown";
            _frameSequence = -1;
        }

        private BlackMarketObservationSnapshot CaptureObservationLocked()
        {
            PendingRequest oldest = null;
            int count = 0;
            int businessCount = 0;
            foreach (PendingRequest pending in _pending.Values)
            {
                count++;
                if (!pending.ObservationOnly) businessCount++;
                if (oldest == null
                    || pending.RouteSequence < oldest.RouteSequence)
                {
                    oldest = pending;
                }
            }
            return new BlackMarketObservationSnapshot
            {
                RouteSequence = _routeSequence,
                LastCompletedRouteSequence = _lastCompletedRouteSequence,
                OutstandingCount = count,
                BusinessOutstandingCount = businessCount,
                OutstandingOwner = oldest == null
                    ? "none"
                    : (oldest.ObservationOnly
                        ? "blackmarket.observation"
                        : "blackmarket.tooltip"),
                As2TupleState = _as2TupleState,
                BusinessOwner = _businessOwner,
                PauseOwner = _pauseOwner,
                SceneOwner = _sceneOwner,
                FrameSequence = _frameSequence
            };
        }

        private void CaptureAs2TupleLocked(JObject tuple)
        {
            if (!IsExactAs2ObservationTuple(tuple))
            {
                _as2TupleState = "invalid";
                _businessOwner = "none";
                _pauseOwner = "unknown";
                _sceneOwner = "unknown";
                _frameSequence = -1;
                return;
            }
            _as2TupleState = "exact";
            _businessOwner = tuple.Value<string>("businessOwner");
            _pauseOwner = tuple.Value<string>("pauseOwner");
            _sceneOwner = tuple.Value<string>("sceneOwner");
            _frameSequence = Convert.ToInt64(tuple.Value<double>("frameSequence"));
        }

        internal static bool IsExactAs2ObservationTuple(JObject tuple)
        {
            if (tuple == null || tuple.Count != 5
                || tuple.Value<int?>("v") != 1
                || !string.Equals(tuple.Value<string>("businessOwner"),
                    "blackmarket.observation", StringComparison.Ordinal))
            {
                return false;
            }
            foreach (JProperty property in tuple.Properties())
            {
                if (property.Name != "v"
                    && property.Name != "businessOwner"
                    && property.Name != "pauseOwner"
                    && property.Name != "sceneOwner"
                    && property.Name != "frameSequence") return false;
            }
            string pause = tuple.Value<string>("pauseOwner");
            string scene = tuple.Value<string>("sceneOwner");
            var pauseOwners = new HashSet<string>(StringComparer.Ordinal)
            {
                "none", "unowned_pause", "shop", "webpanel",
                "multiple_leases", "other_lease"
            };
            var sceneOwners = new HashSet<string>(StringComparer.Ordinal)
            {
                "stage_start_reservation", "stage_settlement", "stage_run",
                "scene_transition", "arena_calibration", "legacy_battle_map",
                "base_scene"
            };
            double frame = tuple.Value<double?>("frameSequence") ?? Double.NaN;
            return pauseOwners.Contains(pause)
                && sceneOwners.Contains(scene)
                && !Double.IsNaN(frame)
                && !Double.IsInfinity(frame)
                && Math.Floor(frame) == frame
                && frame >= -1
                && frame <= 9007199254740991d;
        }
    }
}
