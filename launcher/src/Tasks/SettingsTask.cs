using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// settings domain 的严格 WebView2↔Flash 桥。游戏设置与键位仍由 AS2 判定；
    /// Launcher 偏好由本任务本地落盘，并按精确 panel instance 回包。
    /// </summary>
    public sealed class SettingsTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public string PanelInstanceId;
            public bool IsWrite;
            public int ReconcileEpoch;
        }

        private const int DefaultTimeoutMs = 10000;
        private static readonly Regex ValidOpaque =
            new Regex("^[A-Za-z0-9._~-]{1,160}$", RegexOptions.Compiled);
        private static readonly string[] KeyIds = new[]
        {
            "上键", "下键", "左键", "右键", "A键", "B键", "C键",
            "键1", "键2", "键3", "键4", "键5",
            "药剂组切换键",
            "快捷物品栏键1", "快捷物品栏键2", "快捷物品栏键3", "快捷物品栏键4",
            "快捷技能栏键1", "快捷技能栏键2", "快捷技能栏键3", "快捷技能栏键4",
            "快捷技能栏键5", "快捷技能栏键6", "快捷技能栏键7", "快捷技能栏键8",
            "快捷技能栏键9", "快捷技能栏键10", "快捷技能栏键11", "快捷技能栏键12",
            "切换武器键", "互动键", "武器技能键", "飞行键", "武器变形键", "奔跑键", "组合键"
        };

        private readonly Func<string, bool> _trySend;
        private readonly UserPrefs _userPrefs;
        private readonly Func<bool> _savePrefs;
        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Action<string, JToken> _hostPreferenceApplied;
        private Func<int, int, JObject> _hitNumberLedgerProvider;
        private string _panelInstanceId;
        private string _lastClosedPanelInstanceId;
        private bool _nonPreviewWritePending;
        private bool _requiresReconcile;
        private int _reconcileEpoch;
        private bool _disposed;

        public SettingsTask(XmlSocketServer socket, UserPrefs userPrefs)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                userPrefs,
                delegate { return userPrefs != null && userPrefs.Save(); })
        {
        }

        public SettingsTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            UserPrefs userPrefs,
            Func<bool> savePrefs,
            int timeoutMs = DefaultTimeoutMs)
        {
            _trySend = trySend ?? delegate { return false; };
            _userPrefs = userPrefs;
            _savePrefs = savePrefs ?? delegate { return false; };
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                _trySend,
                timeoutMs,
                HandlePendingEnded);
        }

        public string PanelInstanceId
        {
            get { lock (_lock) return _panelInstanceId; }
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void SetHostPreferenceApplied(Action<string, JToken> callback)
        {
            _hostPreferenceApplied = callback;
        }

        public void SetHitNumberLedgerProvider(Func<int, int, JObject> provider)
        {
            _hitNumberLedgerProvider = provider;
        }

        public bool BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            string previousInstance;
            lock (_lock)
            {
                if (string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return true;
                previousInstance = _panelInstanceId;
                _pendingCalls.Clear();
                _panelInstanceId = panelInstanceId;
                _lastClosedPanelInstanceId = null;
                _nonPreviewWritePending = false;
            }
            if (IsOpaque(previousInstance) && _pendingCalls.IsReady())
                SendPanelClosedToFlash();
            return true;
        }

        public bool HandleAuthoritativePanelClosed(string panelInstanceId)
        {
            bool shouldRestorePreview = false;
            lock (_lock)
            {
                if (IsOpaque(panelInstanceId)
                    && string.Equals(_lastClosedPanelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return true;
                if (!IsOpaque(panelInstanceId)
                    || !string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return false;
                _pendingCalls.Clear();
                _panelInstanceId = null;
                _lastClosedPanelInstanceId = panelInstanceId;
                _nonPreviewWritePending = false;
                shouldRestorePreview = true;
            }
            if (shouldRestorePreview && _pendingCalls.IsReady()) SendPanelClosedToFlash();
            return true;
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null ? parsed.Value<string>("callId") : null;
            string requestedInstance = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (!IsOpaque(callId)) return;
            if (!string.Equals(
                parsed.Value<string>("domain"), "settings", StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, requestedInstance, "unsupported_domain");
                return;
            }
            string bound;
            lock (_lock) bound = _panelInstanceId;
            if (!IsOpaque(bound)
                || !string.Equals(bound, requestedInstance, StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, requestedInstance, "panel_instance_expired");
                return;
            }
            JObject payload = parsed["payload"] as JObject;
            if (string.Equals(cmd, "hit_number_ledger", StringComparison.Ordinal))
            {
                if (!_pendingCalls.TryRememberRejected(callId)) return;
                HandleHitNumberLedger(callId, requestedInstance, payload);
                return;
            }
            if (string.Equals(cmd, "host_set", StringComparison.Ordinal))
            {
                if (!_pendingCalls.TryRememberRejected(callId)) return;
                HandleHostSet(callId, requestedInstance, payload);
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, requestedInstance, "unsupported_cmd");
                return;
            }
            JObject normalized;
            if (!TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(callId, cmd, requestedInstance, "invalid_payload");
                return;
            }
            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(callId, cmd, requestedInstance, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (isWrite && cmd != "preview" && _requiresReconcile)
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    JObject response = BuildError(callId, cmd, requestedInstance,
                        "reconcile_required");
                    response["requiresReconcile"] = true;
                    PostToWeb(response.ToString(Formatting.None));
                    return;
                }
                if (isWrite && cmd != "preview" && _nonPreviewWritePending)
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, requestedInstance, "busy");
                    return;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        PanelInstanceId = requestedInstance,
                        IsWrite = isWrite,
                        ReconcileEpoch = _reconcileEpoch
                    },
                    out fid)) return;
                if (isWrite && cmd != "preview")
                {
                    _nonPreviewWritePending = true;
                }
            }

            JObject flashMessage = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string json = flashMessage.ToString(Formatting.None);
            LogManager.Log("[SettingsTask] -> Flash cmd=" + cmd + " fid=" + fid);
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = ReadPositiveInt(msg != null ? msg["callId"] : null);
            PanelPendingCall<PendingRequest> pendingCall;
            PendingRequest entry;
            bool malformed;
            bool authoritativeRequiresReconcile;
            bool snapshotStillRequiresReconcile;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }
                entry = pendingCall.Context;
                if (entry.IsWrite && entry.WebCmd != "preview")
                    _nonPreviewWritePending = false;
                malformed = IsMalformedFlashResponse(msg, entry.WebCmd);
                authoritativeRequiresReconcile = !malformed
                    && IsReconcileRequiredWrite(entry)
                    && msg.Value<bool?>("requiresReconcile") == true;
                if ((malformed || authoritativeRequiresReconcile)
                    && IsReconcileRequiredWrite(entry))
                    EnterRequiresReconcileLocked();
                else if (!malformed && entry.WebCmd == "snapshot"
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && msg.Value<bool?>("success") == true
                    && _requiresReconcile)
                    _requiresReconcile = false;
                snapshotStillRequiresReconcile = entry.WebCmd == "snapshot"
                    && _requiresReconcile;
            }

            JObject web;
            if (malformed)
            {
                web = BuildError(pendingCall.WebCallId, entry.WebCmd,
                    entry.PanelInstanceId, "malformed_response");
                if (IsReconcileRequiredWrite(entry))
                {
                    web["requiresReconcile"] = true;
                }
            }
            else
            {
                web = (JObject)msg.DeepClone();
                web.Remove("task");
                web["type"] = "panel_resp";
                web["panel"] = "settings";
                web["domain"] = "settings";
                web["cmd"] = entry.WebCmd;
                web["callId"] = pendingCall.WebCallId;
                web["panelInstanceId"] = entry.PanelInstanceId;
                if (entry.WebCmd == "snapshot" && web.Value<bool?>("success") == true)
                {
                    web["hostPrefs"] = BuildHostPrefs();
                }
            }
            // A snapshot issued before the current unknown-write epoch is useful only as
            // diagnostics.  Tell the current/replacement Web document that it must not
            // unlock or present the write controls until a later snapshot crosses the
            // Host epoch gate.
            if (snapshotStillRequiresReconcile)
                web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                _pendingCalls.Clear();
                _panelInstanceId = null;
                _nonPreviewWritePending = false;
            }
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                _pendingCalls.Dispose();
                _panelInstanceId = null;
                _nonPreviewWritePending = false;
                _requiresReconcile = false;
                _reconcileEpoch = 0;
            }
        }

        private void HandleHostSet(string callId, string instanceId, JObject payload)
        {
            string key;
            JToken value;
            if (_userPrefs == null || payload == null
                || !HasExactProperties(payload, "v", "key", "value")
                || !IsVersionOne(payload["v"])
                || payload["key"].Type != JTokenType.String)
            {
                RespondError(callId, "host_set", instanceId,
                    _userPrefs == null ? "host_prefs_unavailable" : "invalid_payload");
                return;
            }
            key = payload.Value<string>("key");
            value = payload["value"];

            bool oldIntro = _userPrefs.IntroEnabled;
            bool oldSfx = _userPrefs.SfxEnabled;
            bool oldAmbient = _userPrefs.AmbientEnabled;
            double oldScale = _userPrefs.UiFontScale;
            string oldMap = _userPrefs.MapDisplayPreference;
            string oldHitNumberMode = _userPrefs.HitNumberMode;
            int oldHitNumberWorldRowLimit = _userPrefs.HitNumberWorldRowLimit;
            JToken normalized;
            if (!TryApplyHostPreference(key, value, out normalized))
            {
                RespondError(callId, "host_set", instanceId, "bad_value");
                return;
            }
            bool saved = false;
            try { saved = _savePrefs(); } catch { saved = false; }
            if (!saved)
            {
                _userPrefs.IntroEnabled = oldIntro;
                _userPrefs.SfxEnabled = oldSfx;
                _userPrefs.AmbientEnabled = oldAmbient;
                _userPrefs.UiFontScale = oldScale;
                _userPrefs.MapDisplayPreference = oldMap;
                _userPrefs.HitNumberMode = oldHitNumberMode;
                _userPrefs.HitNumberWorldRowLimit = oldHitNumberWorldRowLimit;
                RespondError(callId, "host_set", instanceId, "save_failed",
                    CurrentHostPreference(key));
                return;
            }

            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "settings",
                ["domain"] = "settings",
                ["cmd"] = "host_set",
                ["callId"] = callId,
                ["panelInstanceId"] = instanceId,
                ["success"] = true,
                ["v"] = 1,
                ["key"] = key,
                ["currentValue"] = normalized.DeepClone()
            };
            PostToWeb(response.ToString(Formatting.None));
            try
            {
                if (_hostPreferenceApplied != null)
                    _hostPreferenceApplied(key, normalized.DeepClone());
            }
            catch (Exception error)
            {
                LogManager.Log("[SettingsTask] host preference observer failed key="
                    + key + " error=" + error.Message);
            }
        }

        private void HandleHitNumberLedger(
            string callId,
            string instanceId,
            JObject payload)
        {
            long offset;
            long limit;
            if (_hitNumberLedgerProvider == null)
            {
                RespondError(callId, "hit_number_ledger", instanceId,
                    "hit_number_ledger_unavailable");
                return;
            }
            if (!HasExactProperties(payload, "v", "offset", "limit")
                || !IsVersionOne(payload["v"])
                || !TryInteger(payload["offset"], 0, int.MaxValue, out offset)
                || !TryInteger(payload["limit"], 1, 100, out limit))
            {
                RespondError(callId, "hit_number_ledger", instanceId, "invalid_payload");
                return;
            }

            try
            {
                JObject ledger = _hitNumberLedgerProvider((int)offset, (int)limit);
                if (ledger == null)
                {
                    RespondError(callId, "hit_number_ledger", instanceId,
                        "hit_number_ledger_unavailable");
                    return;
                }
                var response = new JObject
                {
                    ["type"] = "panel_resp",
                    ["panel"] = "settings",
                    ["domain"] = "settings",
                    ["cmd"] = "hit_number_ledger",
                    ["callId"] = callId,
                    ["panelInstanceId"] = instanceId,
                    ["success"] = true,
                    ["v"] = 1,
                    ["ledger"] = ledger.DeepClone()
                };
                PostToWeb(response.ToString(Formatting.None));
            }
            catch (Exception error)
            {
                LogManager.Log("[SettingsTask] hit-number ledger failed: " + error.Message);
                RespondError(callId, "hit_number_ledger", instanceId,
                    "hit_number_ledger_unavailable");
            }
        }

        private bool TryApplyHostPreference(string key, JToken value, out JToken normalized)
        {
            normalized = null;
            switch (key)
            {
                case "introEnabled":
                    if (value == null || value.Type != JTokenType.Boolean) return false;
                    _userPrefs.IntroEnabled = value.Value<bool>();
                    normalized = new JValue(_userPrefs.IntroEnabled);
                    return true;
                case "sfxEnabled":
                    if (value == null || value.Type != JTokenType.Boolean) return false;
                    _userPrefs.SfxEnabled = value.Value<bool>();
                    normalized = new JValue(_userPrefs.SfxEnabled);
                    return true;
                case "ambientEnabled":
                    if (value == null || value.Type != JTokenType.Boolean) return false;
                    _userPrefs.AmbientEnabled = value.Value<bool>();
                    normalized = new JValue(_userPrefs.AmbientEnabled);
                    return true;
                case "uiFontScale":
                    double scale;
                    if (!TryFiniteNumber(value, out scale)
                        || scale < UserPrefs.FontScaleMin || scale > UserPrefs.FontScaleMax)
                        return false;
                    _userPrefs.UiFontScale = Math.Round(scale, 2);
                    normalized = new JValue(_userPrefs.UiFontScale);
                    return true;
                case "mapDisplayPreference":
                    if (value == null || value.Type != JTokenType.String) return false;
                    string raw = value.Value<string>();
                    string map = UserPrefs.NormalizeMapDisplayPreference(raw);
                    if (!string.Equals(raw, map, StringComparison.Ordinal)) return false;
                    _userPrefs.MapDisplayPreference = map;
                    normalized = new JValue(map);
                    return true;
                case "hitNumberMode":
                    if (value == null || value.Type != JTokenType.String) return false;
                    string rawMode = value.Value<string>();
                    string hitNumberMode = UserPrefs.NormalizeHitNumberMode(rawMode);
                    if (!string.Equals(rawMode, hitNumberMode, StringComparison.Ordinal)) return false;
                    _userPrefs.HitNumberMode = hitNumberMode;
                    normalized = new JValue(hitNumberMode);
                    return true;
                case "hitNumberWorldRowLimit":
                    long hitNumberLimit;
                    if (!TryInteger(value, 0, UserPrefs.HitNumberWorldRowLimitMax,
                        out hitNumberLimit)) return false;
                    _userPrefs.HitNumberWorldRowLimit = (int)hitNumberLimit;
                    normalized = new JValue(_userPrefs.HitNumberWorldRowLimit);
                    return true;
                default:
                    return false;
            }
        }

        private JObject BuildHostPrefs()
        {
            if (_userPrefs == null) return null;
            return new JObject
            {
                ["introEnabled"] = _userPrefs.IntroEnabled,
                ["sfxEnabled"] = _userPrefs.SfxEnabled,
                ["ambientEnabled"] = _userPrefs.AmbientEnabled,
                ["uiFontScale"] = _userPrefs.UiFontScale,
                ["mapDisplayPreference"] =
                    UserPrefs.NormalizeMapDisplayPreference(_userPrefs.MapDisplayPreference),
                ["hitNumberMode"] =
                    UserPrefs.NormalizeHitNumberMode(_userPrefs.HitNumberMode),
                ["hitNumberWorldRowLimit"] =
                    UserPrefs.NormalizeHitNumberWorldRowLimit(
                        _userPrefs.HitNumberWorldRowLimit)
            };
        }

        private JToken CurrentHostPreference(string key)
        {
            JObject prefs = BuildHostPrefs();
            return prefs != null && prefs[key] != null
                ? prefs[key].DeepClone() : JValue.CreateNull();
        }

        private static bool TryResolveCommand(
            string cmd, out string action, out bool isWrite)
        {
            action = null;
            isWrite = false;
            switch (cmd)
            {
                case "snapshot":
                    action = "settingsSnapshot";
                    return true;
                case "preview":
                    action = "settingsPreviewAudio";
                    isWrite = true;
                    return true;
                case "apply":
                    action = "settingsApply";
                    isWrite = true;
                    return true;
                case "cancel":
                    action = "settingsCancel";
                    isWrite = true;
                    return true;
                case "save":
                    action = "settingsSave";
                    isWrite = true;
                    return true;
                case "cheat":
                    action = "settingsCheat";
                    isWrite = true;
                    return true;
                case "return_base":
                    action = "settingsReturnBase";
                    isWrite = true;
                    return true;
                case "try_revive":
                    action = "settingsTryRevive";
                    isWrite = true;
                    return true;
                default:
                    return false;
            }
        }

        private static bool TryNormalizePayload(
            string cmd, JObject payload, out JObject normalized)
        {
            normalized = null;
            if (payload == null || !IsVersionOne(payload["v"])) return false;
            switch (cmd)
            {
                case "snapshot":
                case "cancel":
                case "save":
                    if (!HasExactProperties(payload, "v")) return false;
                    normalized = new JObject { ["v"] = 1 };
                    return true;
                case "preview": return NormalizePreview(payload, out normalized);
                case "apply": return NormalizeApply(payload, out normalized);
                case "cheat": return NormalizeCheat(payload, out normalized);
                case "return_base":
                case "try_revive": return NormalizeForceControl(payload, out normalized);
                default: return false;
            }
        }

        private static bool NormalizePreview(JObject payload, out JObject normalized)
        {
            normalized = null;
            if (!HasExactProperties(payload, "v", "globalVolume", "bgmVolume", "sample"))
                return false;
            long global;
            long bgm;
            string sample = payload.Value<string>("sample");
            if (!TryInteger(payload["globalVolume"], 0, 100, out global)
                || !TryInteger(payload["bgmVolume"], 0, 100, out bgm)
                || (sample != "none" && sample != "sfx")) return false;
            normalized = new JObject
            {
                ["v"] = 1,
                ["globalVolume"] = global,
                ["bgmVolume"] = bgm,
                ["sample"] = sample
            };
            return true;
        }

        private static bool NormalizeApply(JObject payload, out JObject normalized)
        {
            normalized = null;
            if (!HasExactProperties(
                    payload,
                    "v",
                    "keySchemaVersion",
                    "expectedRevision",
                    "settings",
                    "keys"))
                return false;
            long revision;
            long keySchemaVersion;
            JObject settings = payload["settings"] as JObject;
            JArray keys = payload["keys"] as JArray;
            JObject normalizedSettings;
            JArray normalizedKeys;
            if (!TryInteger(
                    payload["keySchemaVersion"], 2, 2, out keySchemaVersion)
                || !TryInteger(payload["expectedRevision"], 0, int.MaxValue, out revision)
                || !NormalizeSettings(settings, out normalizedSettings)
                || !NormalizeKeys(keys, out normalizedKeys)) return false;
            normalized = new JObject
            {
                ["v"] = 1,
                ["keySchemaVersion"] = 2,
                ["expectedRevision"] = revision,
                ["settings"] = normalizedSettings,
                ["keys"] = normalizedKeys
            };
            return true;
        }

        private static bool NormalizeSettings(JObject value, out JObject normalized)
        {
            normalized = null;
            string[] names = {
                "setGlobalVolume", "setBGMVolume", "性能等级上限", "是否阴影",
                "是否视觉元素", "cameraZoomToggle", "basicZoomScale",
                "开启昼夜系统", "暂停昼夜系统", "使用滤镜渲染", "立绘类型",
                "jukeboxOverride", "jukeboxTrueRandom", "jukeboxPlayMode"
            };
            if (!HasExactProperties(value, names)) return false;
            long global, bgm, performance, portrait;
            double zoom;
            string mode = value.Value<string>("jukeboxPlayMode");
            if (!TryInteger(value["setGlobalVolume"], 0, 100, out global)
                || !TryInteger(value["setBGMVolume"], 0, 100, out bgm)
                || !TryInteger(value["性能等级上限"], 0, 1, out performance)
                || !TryInteger(value["立绘类型"], 1, 2, out portrait)
                || !TryFiniteNumber(value["basicZoomScale"], out zoom)
                || zoom < 0.5 || zoom > 3.0
                || !IsBoolean(value["是否阴影"])
                || !IsBoolean(value["是否视觉元素"])
                || !IsBoolean(value["cameraZoomToggle"])
                || !IsBoolean(value["开启昼夜系统"])
                || !IsBoolean(value["暂停昼夜系统"])
                || !IsBoolean(value["使用滤镜渲染"])
                || !IsBoolean(value["jukeboxOverride"])
                || !IsBoolean(value["jukeboxTrueRandom"])
                || (mode != "singleLoop" && mode != "albumLoop" && mode != "playOnce"))
                return false;
            normalized = (JObject)value.DeepClone();
            normalized["setGlobalVolume"] = global;
            normalized["setBGMVolume"] = bgm;
            normalized["性能等级上限"] = performance;
            normalized["立绘类型"] = portrait;
            normalized["basicZoomScale"] = Math.Round(zoom, 1);
            return true;
        }

        private static bool NormalizeKeys(JArray value, out JArray normalized)
        {
            normalized = null;
            if (value == null || value.Count != KeyIds.Length) return false;
            var seen = new HashSet<long>();
            var result = new JArray();
            for (int i = 0; i < KeyIds.Length; i++)
            {
                JObject row = value[i] as JObject;
                long code;
                if (!HasExactProperties(row, "id", "keyCode")
                    || row["id"].Type != JTokenType.String
                    || !string.Equals(row.Value<string>("id"), KeyIds[i], StringComparison.Ordinal)
                    || !TryInteger(row["keyCode"], 0, 255, out code)
                    || code == 27 || (code >= 112 && code <= 123)
                    || !seen.Add(code)) return false;
                result.Add(new JObject { ["id"] = KeyIds[i], ["keyCode"] = code });
            }
            normalized = result;
            return true;
        }

        private static bool NormalizeCheat(JObject payload, out JObject normalized)
        {
            normalized = null;
            if (!HasExactProperties(payload, "v", "command", "confirmed")
                || payload["command"].Type != JTokenType.String
                || payload["confirmed"].Type != JTokenType.Boolean
                || payload.Value<bool>("confirmed") != true) return false;
            string command = payload.Value<string>("command");
            if (string.IsNullOrWhiteSpace(command) || command.Length > 240
                || ContainsControl(command)) return false;
            normalized = new JObject
            {
                ["v"] = 1,
                ["command"] = command.Trim(),
                ["confirmed"] = true
            };
            return true;
        }

        private static bool NormalizeForceControl(JObject payload, out JObject normalized)
        {
            normalized = null;
            if (!HasExactProperties(payload, "v")) return false;
            normalized = new JObject { ["v"] = 1 };
            return true;
        }

        private static bool IsMalformedFlashResponse(JObject msg, string cmd)
        {
            if (msg == null
                || !string.Equals(msg.Value<string>("task"), "settings_response", StringComparison.Ordinal)
                || !IsVersionOne(msg["v"])
                || msg["success"] == null || msg["success"].Type != JTokenType.Boolean)
                return true;
            bool success = msg.Value<bool>("success");
            if (!success)
            {
                if (!IsCleanString(msg["error"], 80)) return true;
                if (cmd == "apply" && (msg["keys"] != null
                        || msg["keySchemaVersion"] != null))
                {
                    return !IsValidAuthoritySnapshot(msg);
                }
                return cmd == "apply" && msg.Value<bool?>("applied") == true
                    ? !IsValidApplyResponse(msg)
                    : false;
            }

            if (!string.Equals(msg.Value<string>("operation"), cmd, StringComparison.Ordinal))
                return true;
            switch (cmd)
            {
                case "snapshot":
                    return !IsValidAuthoritySnapshot(msg);
                case "preview":
                    long globalVolume;
                    long bgmVolume;
                    return msg.Value<bool?>("previewActive") != true
                        || !TryInteger(msg["globalVolume"], 0, 100, out globalVolume)
                        || !TryInteger(msg["bgmVolume"], 0, 100, out bgmVolume)
                        || !IsBoolean(msg["samplePlayed"]);
                case "cancel":
                    return !IsBoolean(msg["previewRestored"])
                        || msg.Value<bool?>("previewActive") != false;
                case "apply":
                    return !IsValidApplyResponse(msg);
                case "save":
                    long revision;
                    return msg.Value<bool?>("durable") != true
                        || msg.Value<bool?>("needsSaveRetry") != false
                        || !TryInteger(msg["revision"], 0, int.MaxValue, out revision)
                        || !IsBoolean(msg["migrationPending"]);
                case "cheat":
                    return msg.Value<bool?>("accepted") != true
                        || !IsCleanString(msg["command"], 240)
                        || !IsEffectScope(msg.Value<string>("effectScope"))
                        || !IsBoolean(msg["dirty"])
                        || !IsBoolean(msg["challengeMode"])
                        || !IsCleanString(msg["modeLabel"], 24)
                        || !IsValidCheatHelp(msg["cheatHelp"] as JArray)
                        || !IsCleanString(msg["message"], 240);
                case "return_base":
                    return msg.Value<bool?>("closePanel") != true;
                case "try_revive":
                    long reviveCoins;
                    return msg.Value<bool?>("revived") != true
                        || !TryInteger(
                            msg["reviveCoins"],
                            0,
                            int.MaxValue,
                            out reviveCoins)
                        || msg.Value<bool?>("closePanel") != true;
                default:
                    return true;
            }
        }

        private static bool IsValidApplyResponse(JObject msg)
        {
            bool success = msg.Value<bool?>("success") == true;
            bool durable = msg.Value<bool?>("durable") == true;
            if (msg.Value<bool?>("applied") != true
                || !IsBoolean(msg["durable"])
                || success != durable
                || !IsBoolean(msg["migrationPending"])
                || !IsValidAuthoritySnapshot(msg)) return false;
            if (!durable)
            {
                return msg.Value<bool?>("needsSaveRetry") == true
                    && string.Equals(msg.Value<string>("error"), "save_failed", StringComparison.Ordinal);
            }
            return true;
        }

        private static bool IsValidAuthoritySnapshot(JObject msg)
        {
            long revision;
            long keySchemaVersion;
            JObject normalizedSettings;
            return TryInteger(
                    msg["keySchemaVersion"], 2, 2, out keySchemaVersion)
                && TryInteger(msg["revision"], 0, int.MaxValue, out revision)
                && NormalizeSettings(msg["settings"] as JObject, out normalizedSettings)
                && IsValidProjectedKeys(msg["keys"] as JArray)
                && IsValidDefaultKeys(msg["defaultKeys"] as JArray)
                && IsValidAllowedKeyCodes(msg["allowedKeyCodes"] as JArray)
                && IsBoolean(msg["challengeMode"])
                && IsCleanString(msg["modeLabel"], 24)
                && IsValidCheatHelp(msg["cheatHelp"] as JArray)
                && IsValidForceControls(msg["forceControls"] as JObject)
                && IsBoolean(msg["previewActive"])
                && IsBoolean(msg["migrationPending"])
                && IsBoundedString(
                    msg["keyMigrationNotice"], 160, true);
        }

        private static bool IsValidProjectedKeys(JArray rows)
        {
            if (rows == null || rows.Count != KeyIds.Length) return false;
            for (int i = 0; i < KeyIds.Length; i++)
            {
                JObject row = rows[i] as JObject;
                long index;
                long code;
                string label = row == null ? null : row.Value<string>("label");
                if (!HasExactProperties(row, "index", "label", "id", "keyCode", "keyName")
                    || !TryInteger(row["index"], i, i, out index)
                    || !string.Equals(row.Value<string>("id"), KeyIds[i], StringComparison.Ordinal)
                    || !IsCleanString(row["label"], 80)
                    || string.Equals(label, "undefined", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(label, "null", StringComparison.OrdinalIgnoreCase)
                    || !TryInteger(row["keyCode"], 0, 255, out code)
                    || !IsCleanString(row["keyName"], 40)) return false;
            }
            return true;
        }

        private static bool IsValidDefaultKeys(JArray rows)
        {
            if (rows == null || rows.Count != KeyIds.Length) return false;
            var seen = new HashSet<long>();
            for (int i = 0; i < KeyIds.Length; i++)
            {
                JObject row = rows[i] as JObject;
                long code;
                if (!HasExactProperties(row, "id", "keyCode")
                    || !string.Equals(row.Value<string>("id"), KeyIds[i], StringComparison.Ordinal)
                    || !TryInteger(row["keyCode"], 0, 255, out code)
                    || code == 27 || (code >= 112 && code <= 123)
                    || !seen.Add(code)) return false;
            }
            return true;
        }

        private static bool IsValidAllowedKeyCodes(JArray rows)
        {
            if (rows == null || rows.Count == 0 || rows.Count > 256) return false;
            var seen = new HashSet<long>();
            foreach (JToken token in rows)
            {
                JObject row = token as JObject;
                long code;
                if (!HasExactProperties(row, "code", "name")
                    || !TryInteger(row["code"], 0, 255, out code)
                    || code == 27 || (code >= 112 && code <= 123)
                    || !seen.Add(code)
                    || !IsCleanString(row["name"], 40)) return false;
            }
            return true;
        }

        private static bool IsValidCheatHelp(JArray rows)
        {
            if (rows == null || rows.Count > 32) return false;
            foreach (JToken token in rows)
            {
                JObject row = token as JObject;
                if (!HasExactProperties(row, "command", "description", "effectScope")
                    || !IsCleanString(row["command"], 160)
                    || !IsCleanString(row["description"], 240)
                    || !IsEffectScope(row.Value<string>("effectScope"))) return false;
            }
            return true;
        }

        private static bool IsValidForceControls(JObject value)
        {
            return HasExactProperties(value,
                    "returnBaseAvailable", "tryReviveAvailable", "resurrectionRestricted")
                && IsBoolean(value["returnBaseAvailable"])
                && IsBoolean(value["tryReviveAvailable"])
                && IsBoolean(value["resurrectionRestricted"]);
        }

        private static bool IsEffectScope(string value)
        {
            return value == "read" || value == "session" || value == "save"
                || value == "unknown";
        }

        private static bool IsCleanString(JToken token, int maximumLength)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            return !string.IsNullOrWhiteSpace(value)
                && value.Length <= maximumLength && !ContainsControl(value);
        }

        private static bool IsBoundedString(
            JToken token,
            int maximumLength,
            bool allowEmpty)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            return value != null
                && value.Length <= maximumLength
                && (allowEmpty || !string.IsNullOrWhiteSpace(value))
                && !ContainsControl(value);
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = pendingCall.Context;
            lock (_lock)
            {
                if (entry.IsWrite && entry.WebCmd != "preview")
                    _nonPreviewWritePending = false;
                // A lifecycle clear can race a write already accepted by Flash just as
                // readily as a timeout or a transport-level unknown delivery.  Keep the
                // process-wide reconcile latch until a valid authoritative snapshot; a
                // close/rebind or socket detach must never turn that write into replayable
                // work for the replacement panel.
                if (IsReconcileRequiredWrite(entry))
                    EnterRequiresReconcileLocked();
            }
            if (reason == PanelPendingCallEndReason.Cleared || _disposed) return;

            JObject response = BuildError(
                pendingCall.WebCallId,
                entry.WebCmd,
                entry.PanelInstanceId,
                reason == PanelPendingCallEndReason.Timeout
                    ? "timeout"
                    : "delivery_unknown");
            if ((reason == PanelPendingCallEndReason.Timeout
                    || reason == PanelPendingCallEndReason.DeliveryUnknown)
                && IsReconcileRequiredWrite(entry))
            {
                response["requiresReconcile"] = true;
            }
            PostToWeb(response.ToString(Formatting.None));
        }

        private static bool IsReconcileRequiredWrite(PendingRequest entry)
        {
            return entry != null && entry.IsWrite
                && !string.Equals(entry.WebCmd, "preview", StringComparison.Ordinal);
        }

        private void EnterRequiresReconcileLocked()
        {
            _requiresReconcile = true;
            _reconcileEpoch++;
        }

        private void SendPanelClosedToFlash()
        {
            JObject flash = PanelBridge.BuildFlashCommand(
                "settingsPanelClosed", 0, new JObject { ["v"] = 1 });
            _trySend(flash.ToString(Formatting.None) + "\0");
        }

        private void RespondError(
            string callId, string cmd, string panelInstanceId, string error,
            JToken currentValue = null)
        {
            JObject response = BuildError(callId, cmd, panelInstanceId, error);
            if (currentValue != null) response["currentValue"] = currentValue;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void RejectAndRemember(
            string callId, string cmd, string panelInstanceId, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(callId, cmd, panelInstanceId, error);
        }

        private static JObject BuildError(
            string callId, string cmd, string panelInstanceId, string error)
        {
            return new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "settings",
                ["domain"] = "settings",
                ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "",
                ["panelInstanceId"] = panelInstanceId ?? "",
                ["success"] = false,
                ["error"] = error
            };
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null)
                _postToWeb(json);
        }

        private static bool HasExactProperties(JObject value, params string[] names)
        {
            if (value == null || value.Count != names.Length) return false;
            foreach (string name in names)
                if (value.Property(name) == null) return false;
            return true;
        }

        private static bool IsOpaque(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value);
        }

        private static bool IsVersionOne(JToken token)
        {
            return token != null && token.Type == JTokenType.Integer
                && token.Value<long>() == 1;
        }

        private static bool IsBoolean(JToken token)
        {
            return token != null && token.Type == JTokenType.Boolean;
        }

        private static bool TryInteger(JToken token, long minimum, long maximum, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            value = token.Value<long>();
            return value >= minimum && value <= maximum;
        }

        private static bool TryFiniteNumber(JToken token, out double value)
        {
            value = 0;
            if (token == null
                || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) return false;
            value = token.Value<double>();
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }

        private static int ReadPositiveInt(JToken token)
        {
            long value;
            return TryInteger(token, 1, int.MaxValue, out value) ? (int)value : 0;
        }

        private static bool ContainsControl(string value)
        {
            if (value == null) return true;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return true;
            return false;
        }
    }
}
