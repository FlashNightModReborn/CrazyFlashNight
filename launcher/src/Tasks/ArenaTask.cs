using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 竞技场（DEATH MATCH 角斗场）面板 WebView ↔ Flash 双层 callId 桥接。
    /// 与 StageSelectTask / MapTask 同构：
    ///   Web → C#   {type:"panel", panel:"arena", cmd, callId, ...}
    ///   C# → Flash {task:"cmd", action:"arenaSnapshot/arenaEnter", callId:fid, ...}
    ///   Flash → C# {task:"arena_response", callId:fid, success, ...}
    ///   C# → Web   {type:"panel_resp", panel:"arena", cmd, callId, success, ...}
    ///
    /// 注意：普通 close 不走本桥。Web 关闭面板时 WebOverlayForm.HandlePanelMessage 直接
    /// 切 _activePanel = null + ClosePanel()，无需通知 AS2（角斗场进场链尚未触发，
    /// 没有需要清理的状态）。ResolvePanelCloseGameCommand("arena") 也因此返回 null。
    /// 定制赛 custom_result 结算页例外：close 消息携带 returnBase=true 时，Host 会直接
    /// 下发 arenaReturnBase 让 AS2 离开竞技场场景。
    /// </summary>
    public sealed class ArenaTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
        }

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly ArenaAuthorityCatalog _authorityCatalog;
        private ArenaAuthoritySession _authoritySession;
        private ArenaCalibrationTask _calibrationTask;
        private Action<JObject> _openCustomResultPanel;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private readonly HashSet<string> _customBatchIds;
        private readonly Dictionary<string, string> _customMatchCodes;
        private int _seq;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        public ArenaTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); },
                null)
        {
        }

        public ArenaTask(XmlSocketServer socket, string projectRoot)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); },
                ArenaAuthorityCatalog.Load(projectRoot))
        {
        }

        public ArenaTask(Func<bool> isClientReady, Action<string> send)
            : this(isClientReady, send, null)
        {
        }

        internal ArenaTask(
            Func<bool> isClientReady,
            Action<string> send,
            ArenaAuthorityCatalog authorityCatalog)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _authorityCatalog = authorityCatalog;
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
            _customBatchIds = new HashSet<string>(StringComparer.Ordinal);
            _customMatchCodes = new Dictionary<string, string>(StringComparer.Ordinal);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void SetCustomResultOpenHandler(Action<JObject> handler) { _openCustomResultPanel = handler; }

        public void SetCalibrationTask(ArenaCalibrationTask task)
        {
            _calibrationTask = task;
            if (_calibrationTask != null)
                _calibrationTask.SetBatchCompletedHandler(OnCalibrationBatchCompleted);
        }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[ArenaTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[ArenaTask] webCallId is empty");
                return;
            }

            if (cmd == "custom_start" || cmd == "custom_status" || cmd == "custom_abort")
            {
                HandleCustomMatchRequest(cmd, webCallId, parsed);
                return;
            }

            if (!_isClientReady())
            {
                RespondError(webCallId, cmd, "disconnected");
                return;
            }

            string action;
            JObject trustedFields = null;
            switch (cmd)
            {
                case "snapshot":
                    if (_authorityCatalog == null)
                    {
                        RespondError(webCallId, cmd, "arena_authority_unavailable");
                        return;
                    }
                    _authoritySession = null;
                    action = "arenaSnapshot";
                    break;
                case "preview":
                    action = "arenaRollPreview";
                    if (!TryBuildPreviewFields(parsed, out trustedFields, out string previewError))
                    {
                        RespondError(webCallId, cmd, previewError);
                        return;
                    }
                    break;
                case "equip_tooltip":
                    action = "arenaEquipTooltip";
                    break;
                case "enter":
                    action = "arenaEnter";
                    if (!TryBuildEnterFields(parsed, out trustedFields, out string enterError))
                    {
                        RespondError(webCallId, cmd, enterError);
                        return;
                    }
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

            // P5：preview/enter 只复制上面由 C# 权威目录重建的字段；客户端经济与 expr 永不透传。
            // snapshot/equip_tooltip 仍走通用安全信封（它们不含写入经济）。
            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, trustedFields ?? parsed);

            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[ArenaTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        private bool TryBuildPreviewFields(JObject parsed, out JObject fields, out string error)
        {
            fields = null;
            if (!TryResolveCard(parsed, out ArenaAuthorityCard card, out error)) return false;
            if (card.Mode != "standard" && card.Mode != "hidden")
            {
                error = "preview_not_supported";
                return false;
            }
            JToken indexToken = parsed["cardIndex"];
            if (indexToken?.Type != JTokenType.Integer || indexToken.Value<int>() != card.PreviewIndex)
            {
                error = "stale_authority";
                return false;
            }
            fields = new JObject { ["cardIndex"] = card.PreviewIndex };
            card.WriteAuthorityFields(fields);
            fields["authoritySourceDigest"] = _authoritySession.SourceDigest;
            return true;
        }

        private bool TryBuildEnterFields(JObject parsed, out JObject fields, out string error)
        {
            fields = null;
            error = null;
            if (_authoritySession == null)
            {
                error = "authority_snapshot_required";
                return false;
            }

            string requestedMode = parsed.Value<string>("mode") ?? string.Empty;
            if (requestedMode == "custom_pve")
            {
                if (!_authoritySession.TrySanitizeRoster(
                        parsed["roster"], null, true, out JArray customRoster, out error))
                {
                    return false;
                }
                if (customRoster == null || customRoster.Count == 0)
                {
                    error = "roster_required";
                    return false;
                }
                fields = new JObject
                {
                    ["mode"] = "custom_pve",
                    ["authorityId"] = "custom-pve",
                    ["authorityMode"] = "custom_pve",
                    ["authoritySourceDigest"] = _authoritySession.SourceDigest,
                    ["levelMin"] = 1,
                    ["levelMax"] = 1,
                    ["opponentCount"] = 1,
                    ["economyMultiplier"] = 1,
                    ["benchLevel"] = 1,
                    ["expr"] = "#0@1-1%1",
                    ["deposit"] = 0,
                    ["reward"] = 0,
                    ["roster"] = customRoster,
                    ["difficulty"] = ReadDifficulty(parsed)
                };
                return true;
            }

            if (!TryResolveCard(parsed, out ArenaAuthorityCard card, out error)) return false;
            JArray roster;
            JToken calibratedRosterToken = parsed["calibratedRosterId"];
            bool usesCalibratedRoster = calibratedRosterToken != null
                && calibratedRosterToken.Type != JTokenType.Null;
            if (usesCalibratedRoster)
            {
                if (calibratedRosterToken.Type != JTokenType.String
                        || (parsed["roster"] != null && parsed["roster"].Type != JTokenType.Null))
                {
                    error = "invalid_calibrated_roster_payload";
                    return false;
                }
                if (!_authoritySession.TryResolveCalibratedRoster(
                        calibratedRosterToken.Value<string>(), card, out roster, out error))
                {
                    return false;
                }
            }
            else if (!_authoritySession.TrySanitizeRoster(
                parsed["roster"], card, false, out roster, out error))
            {
                return false;
            }
            if (card.Mode == "escalation" && roster != null)
            {
                error = "invalid_roster";
                return false;
            }

            fields = new JObject
            {
                ["cardIndex"] = card.Mode == "standard" || card.Mode == "hidden"
                    ? card.PreviewIndex
                    : ReadNonNegativeIndex(parsed["cardIndex"]),
                ["difficulty"] = ReadDifficulty(parsed)
            };
            card.WriteAuthorityFields(fields);
            fields["authoritySourceDigest"] = _authoritySession.SourceDigest;
            if (roster != null) fields["roster"] = roster;
            if (card.Mode == "escalation")
            {
                fields["mode"] = "escalation";
                fields["faction"] = card.Faction;
                fields["baseCount"] = card.OpponentCount;
                fields["baseLevelMin"] = card.LevelMin;
                fields["baseLevelMax"] = card.LevelMax;
                fields["maxWaves"] = card.MaxWaves;
                fields["pool"] = card.Pool.DeepClone();
            }
            return true;
        }

        private bool TryResolveCard(JObject parsed, out ArenaAuthorityCard card, out string error)
        {
            card = null;
            if (_authoritySession == null)
            {
                error = "authority_snapshot_required";
                return false;
            }
            JToken token = parsed["cardId"];
            if (token?.Type != JTokenType.String
                    || !_authoritySession.TryGetCard(token.Value<string>(), out card))
            {
                error = "stale_authority";
                return false;
            }
            error = null;
            return true;
        }

        private static int ReadNonNegativeIndex(JToken token)
        {
            return token?.Type == JTokenType.Integer && token.Value<long>() >= 0
                    && token.Value<long>() <= 10000
                ? token.Value<int>()
                : 0;
        }

        private static string ReadDifficulty(JObject parsed)
        {
            JToken token = parsed["difficulty"];
            if (token?.Type != JTokenType.String) return string.Empty;
            string value = token.Value<string>() ?? string.Empty;
            return value.Length <= 64 ? value : string.Empty;
        }

        private void HandleCustomMatchRequest(string cmd, string webCallId, JObject parsed)
        {
            if (_calibrationTask == null)
            {
                RespondError(webCallId, cmd, "calibration_task_unavailable");
                return;
            }

            JObject control = new JObject();
            if (cmd == "custom_start")
            {
                control["action"] = "startSingle";
                CopyIfPresent(parsed, control, "batchId");
                CopyIfPresent(parsed, control, "matchCode");
                CopyIfPresent(parsed, control, "repeat");
                CopyIfPresent(parsed, control, "timeoutFrames");
                CopyIfPresent(parsed, control, "spawnDistance");
                CopyIfPresent(parsed, control, "blueFormation");
                CopyIfPresent(parsed, control, "redFormation");
                CopyIfPresent(parsed, control, "formationSpacing");
                if (parsed["calibrationCase"] != null)
                    control["calibrationCase"] = parsed["calibrationCase"].DeepClone();
            }
            else if (cmd == "custom_status")
            {
                control["action"] = "status";
            }
            else
            {
                control["action"] = "abort";
                CopyIfPresent(parsed, control, "batchId");
            }

            JObject result;
            Action startWorker = null;
            if (cmd == "custom_start")
            {
                string matchCode = parsed.Value<string>("matchCode") ?? "";
                result = _calibrationTask.StartSingleDeferred(control, delegate(JObject started)
                {
                    string batchId = started != null ? started.Value<string>("batchId") : null;
                    RegisterCustomBatch(batchId, matchCode);
                }, out startWorker);
            }
            else
            {
                result = JObject.Parse(_calibrationTask.HandleControl(control));
            }

            if (cmd == "custom_start" && result.Value<bool?>("success") != false)
            {
                result["closePanel"] = true;
            }

            result["type"] = "panel_resp";
            result["panel"] = "arena";
            result["cmd"] = cmd;
            result["callId"] = webCallId;
            try
            {
                PostToWeb(result.ToString(Formatting.None));
            }
            finally
            {
                if (startWorker != null)
                    startWorker();
            }
        }

        private void RegisterCustomBatch(string batchId, string matchCode)
        {
            if (string.IsNullOrEmpty(batchId))
                return;

            lock (_lock)
            {
                _customBatchIds.Add(batchId);
                _customMatchCodes[batchId] = matchCode ?? "";
            }
        }

        private void OnCalibrationBatchCompleted(JObject status)
        {
            string batchId = status != null ? status.Value<string>("batchId") : null;
            bool shouldOpen = false;
            string matchCode = null;
            if (!string.IsNullOrEmpty(batchId))
            {
                lock (_lock)
                {
                    shouldOpen = _customBatchIds.Remove(batchId);
                    if (_customMatchCodes.TryGetValue(batchId, out matchCode))
                        _customMatchCodes.Remove(batchId);
                }
            }
            if (!shouldOpen)
                return;

            JObject initData = BuildCustomResultInitData(status, matchCode);
            Action<JObject> opener = _openCustomResultPanel;
            if (opener == null)
                return;

            Action open = delegate { opener(initData); };
            if (_invokeOnUI != null)
                _invokeOnUI(open);
            else
                open();
        }

        private static JObject BuildCustomResultInitData(JObject status, string matchCode)
        {
            JObject initData = new JObject();
            initData["mode"] = "custom_result";
            initData["source"] = "arena_custom_match_result";
            initData["debug"] = false;
            if (!string.IsNullOrEmpty(matchCode))
                initData["matchCode"] = matchCode;
            if (status == null)
                return initData;

            CopyIfPresent(status, initData, "state");
            CopyIfPresent(status, initData, "batchId");
            CopyIfPresent(status, initData, "resultPath");
            CopyIfPresent(status, initData, "manifestPath");
            CopyIfPresent(status, initData, "frozenManifestPath");
            CopyIfPresent(status, initData, "totalRuns");
            CopyIfPresent(status, initData, "completedRuns");
            CopyIfPresent(status, initData, "lastError");
            if (status["lastResult"] != null && status["lastResult"].Type != JTokenType.Null)
                initData["lastResult"] = status["lastResult"].DeepClone();
            return initData;
        }

        private static void CopyIfPresent(JObject source, JObject target, string fieldName)
        {
            if (source[fieldName] != null)
                target[fieldName] = source[fieldName].DeepClone();
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[ArenaTask] <- Flash response received");
            int fid;
            string invalidReason;
            if (!TryReadBackendCallId(msg, out fid, out invalidReason))
            {
                int pendingCount;
                lock (_lock) { pendingCount = _pending.Count; }
                LogManager.Log("event=arena_response_dropped"
                    + " reason=" + invalidReason
                    + " pending_count=" + pendingCount);
                respond(null);
                return;
            }
            PendingRequest entry;
            int unmatchedPendingCount = 0;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    unmatchedPendingCount = _pending.Count;
                }
                else
                {
                    _pending.Remove(fid);
                    Timer t;
                    if (_timers.TryGetValue(fid, out t))
                    {
                        t.Dispose();
                        _timers.Remove(fid);
                    }
                }
            }

            if (entry == null)
            {
                LogManager.Log("event=arena_response_dropped"
                    + " reason=unknown_backend_call_id"
                    + " backend_call_id=" + fid
                    + " pending_count=" + unmatchedPendingCount);
                respond(null);
                return;
            }

            if (entry.WebCmd == "snapshot")
            {
                if (!TryAttachAuthoritySnapshot(msg, out string authorityError))
                {
                    _authoritySession = null;
                    msg["success"] = false;
                    msg["error"] = authorityError;
                    msg.Remove("snapshot");
                }
            }

            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "arena";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = entry.WebCallId;

            string json = msg.ToString(Formatting.None);
            PostToWeb(json);
            respond(null);
        }

        private static bool TryReadBackendCallId(
            JObject msg, out int backendCallId, out string reason)
        {
            backendCallId = 0;
            reason = "missing_backend_call_id";
            JToken token = msg != null ? msg["callId"] : null;
            if (token == null || token.Type == JTokenType.Null) return false;
            reason = "invalid_backend_call_id";
            if (token.Type != JTokenType.Integer) return false;
            long value;
            try { value = token.Value<long>(); }
            catch (Exception) { return false; }
            if (value <= 0 || value > int.MaxValue) return false;
            backendCallId = (int)value;
            reason = null;
            return true;
        }

        private bool TryAttachAuthoritySnapshot(JObject msg, out string error)
        {
            error = "invalid_authority_snapshot";
            if (_authorityCatalog == null || msg.Value<bool?>("success") != true
                    || msg["snapshot"] is not JObject snapshot)
            {
                return false;
            }
            JToken levelToken = snapshot["playerLevel"];
            JToken enemiesToken = snapshot["knownEnemies"];
            if ((levelToken?.Type != JTokenType.Integer && levelToken?.Type != JTokenType.Float)
                    || enemiesToken is not JArray enemies
                    || enemies.Any(token => token.Type != JTokenType.String))
            {
                return false;
            }
            double levelNumber = levelToken.Value<double>();
            if (double.IsNaN(levelNumber) || double.IsInfinity(levelNumber)
                    || levelNumber < 1 || levelNumber > int.MaxValue)
            {
                return false;
            }
            _authoritySession = _authorityCatalog.CreateSession(
                checked((int)Math.Floor(levelNumber)),
                enemies.Values<string>());
            snapshot["arenaAuthority"] = _authoritySession.ToSnapshot();
            error = null;
            return true;
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (var t in _timers.Values) t.Dispose();
                _timers.Clear();
                _pending.Clear();
                _authoritySession = null;
            }
        }

        private void RespondError(string webCallId, string cmd, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "arena";
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
