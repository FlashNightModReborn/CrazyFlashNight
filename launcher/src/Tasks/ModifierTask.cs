using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 修改器 Web Panel 传输边界。AS2 保留四页写权威、目录投影、
    /// dirty/保存语义和一次性操作收据；Host 只做 owner、白名单、
    /// 未知写水位与响应重建。
    /// </summary>
    public sealed class ModifierTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string Cmd, Token, OperationId, Instance;
            public bool IsWrite;
        }

        private static readonly Regex SafeToken = new Regex("^modifier\\.[A-Za-z0-9._~-]{1,80}$", RegexOptions.Compiled);
        private static readonly Regex SafeOperation = new Regex("^mod\\.[A-Za-z0-9._~-]{1,80}$", RegexOptions.Compiled);
        private static readonly Regex SafeId = new Regex("^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);
        private static readonly HashSet<string> DefinitiveErrors = new HashSet<string>(StringComparer.Ordinal)
        {
            "unsupported_cmd", "unsupported_version", "invalid_payload", "stale_token", "stale_revision",
            "context_changed", "invalid_balance", "item_unavailable", "quantity_overflow", "pickup_unavailable",
            "actor_unavailable", "stage_unavailable", "wave_unavailable", "task_unavailable", "unit_unavailable",
            "merc_pool_empty", "merc_pool_invalid", "spawn_unavailable", "spawn_failed", "navigation_unavailable",
            "not_allowed", "challenge_mode", "save_unavailable", "not_applied"
        };
        private static readonly HashSet<string> WriteCommands = new HashSet<string>(StringComparer.Ordinal)
        { "grantMoney", "grantKCoin", "spawnItem", "levelAction", "grantTask", "spawnUnit", "spawnMerc" };
        private static readonly string[] LevelActions =
        { "unlock_stages", "kill_all", "finish_wave", "finish_map", "finish_stage", "test_space" };

        private readonly object _gate = new object();
        private readonly object _webGate = new object();
        private readonly PanelPendingCallTracker<PendingRequest> _pending;
        private Action<string> _post;
        private Action<Action> _invoke;
        private string _unresolvedToken;
        private string _unresolvedOperationId;
        private bool _writePending, _disposed;

        public ModifierTask(XmlSocketServer socket) : this(
            () => socket != null && socket.IsClientReady,
            text => socket != null && socket.TrySend(text)) { }

        public ModifierTask(Func<bool> ready, Func<string, bool> send, int timeoutMs = 12000)
        {
            _pending = new PanelPendingCallTracker<PendingRequest>(ready, text =>
            {
                try { return send != null && send(text); }
                catch (Exception error) { LogManager.Log("[Modifier] delivery unknown: " + error.GetType().Name); return false; }
            }, timeoutMs, OnPendingEnded);
        }

        public bool HasUnresolvedWrite
        {
            get { lock (_gate) return _unresolvedOperationId != null; }
        }

        public string UnresolvedToken
        {
            get { lock (_gate) return _unresolvedToken; }
        }

        public string UnresolvedOperationId
        {
            get { lock (_gate) return _unresolvedOperationId; }
        }

        public void SetPostToWeb(Action<string> post)
        {
            lock (_webGate) _post = post;
        }

        public void SetInvoker(Action<Action> invoke)
        {
            lock (_webGate) _invoke = invoke;
        }

        public void ClearPending()
        {
            lock (_gate) { _writePending = false; }
            _pending.Clear();
        }

        public void Dispose()
        {
            lock (_gate) { _disposed = true; }
            _pending.Dispose();
        }

        internal static JObject BuildOpenData(string source, string extras)
        {
            if (!string.Equals(source, "nativehud_modifier", StringComparison.Ordinal)
                || string.IsNullOrEmpty(extras)) return null;
            JObject data;
            try { data = JObject.Parse(extras); } catch (JsonException) { return null; }
            if (!Exact(data, "token")) return null;
            string token = Text(data["token"]);
            if (!SafeToken.IsMatch(token ?? "")) return null;
            return new JObject
            {
                ["source"] = "nativehud_modifier",
                ["mode"] = "runtime",
                ["token"] = token
            };
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = Text(parsed?["callId"]);
            string instance = Text(parsed?["panelInstanceId"]);
            if (callId == null || !SafeId.IsMatch(callId) || _pending.IsKnownWebCallId(callId)) return;
            if (!string.Equals(Text(parsed?["domain"]), "modifier", StringComparison.Ordinal))
            { RejectAndRemember(callId, cmd, instance, "unsupported_domain"); return; }
            if (!string.Equals(Text(parsed?["panel"]), "modifier", StringComparison.Ordinal)
                || instance == null || !SafeId.IsMatch(instance))
            { RejectAndRemember(callId, cmd, instance, "invalid_owner"); return; }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            { RejectAndRemember(callId, cmd, instance, "unsupported_cmd"); return; }
            if (isWrite != WriteCommands.Contains(cmd))
            { RejectAndRemember(callId, cmd, instance, "unsupported_cmd"); return; }

            JObject payload = parsed["payload"] as JObject;
            string token = Text(payload?["token"]);
            string operationId = Text(payload?["operationId"]);
            int? expectedRevision = null;
            if (!ValidPayload(cmd, payload, out expectedRevision))
            { RejectAndRemember(callId, cmd, instance, "invalid_payload"); return; }
            if (!SafeToken.IsMatch(token ?? ""))
            { RejectAndRemember(callId, cmd, instance, "invalid_payload"); return; }
            if (isWrite && !SafeOperation.IsMatch(operationId ?? ""))
            { RejectAndRemember(callId, cmd, instance, "invalid_payload"); return; }

            if (!_pending.IsReady())
            { RejectAndRemember(callId, cmd, instance, "disconnected"); return; }

            JObject normalized = (JObject)payload.DeepClone();
            int fid = 0;
            string rejection = null;
            lock (_gate)
            {
                if (isWrite && _unresolvedOperationId != null) rejection = "reconcile_required";
                else if (isWrite && _writePending) rejection = "busy";
                else
                {
                    var entry = new PendingRequest
                    {
                        Cmd = cmd,
                        Token = token,
                        OperationId = operationId,
                        Instance = instance,
                        IsWrite = isWrite
                    };
                    if (!_pending.TryBegin(callId, entry, out fid)) return;
                    if (isWrite)
                    {
                        _writePending = true;
                        _unresolvedToken = token;
                        _unresolvedOperationId = operationId;
                    }
                }
            }
            if (rejection != null)
            {
                RejectAndRemember(callId, cmd, instance, rejection);
                return;
            }
            _pending.Send(fid, PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None) + "\0");
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            action = null;
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "modifierSnapshot"; return true;
                case "items": action = "modifierItems"; return true;
                case "units": action = "modifierUnits"; return true;
                case "query": action = "modifierQuery"; return true;
                case "itemTooltip": action = "modifierItemTooltip"; return true;
                case "unitFrame": action = "modifierUnitFrame"; return true;
                case "grantMoney": action = "modifierGrantMoney"; isWrite = true; return true;
                case "grantKCoin": action = "modifierGrantKCoin"; isWrite = true; return true;
                case "spawnItem": action = "modifierSpawnItem"; isWrite = true; return true;
                case "levelAction": action = "modifierLevelAction"; isWrite = true; return true;
                case "grantTask": action = "modifierGrantTask"; isWrite = true; return true;
                case "spawnUnit": action = "modifierSpawnUnit"; isWrite = true; return true;
                case "spawnMerc": action = "modifierSpawnMerc"; isWrite = true; return true;
                default: return false;
            }
        }

        private static bool ValidPayload(string cmd, JObject payload, out int? expectedRevision)
        {
            expectedRevision = null;
            if (payload == null || !Integer(payload["v"], 1, 1)) return false;
            string[] keys;
            switch (cmd)
            {
                case "snapshot": keys = new[] { "v", "token" }; break;
                case "items":
                case "units": keys = new[] { "v", "token", "query", "page" }; break;
                case "query": keys = new[] { "v", "token", "operationId" }; break;
                case "itemTooltip": keys = new[] { "v", "token", "itemName" }; break;
                case "unitFrame": keys = new[] { "v", "token", "spriteName" }; break;
                case "grantMoney":
                case "grantKCoin": keys = new[] { "v", "token", "operationId", "expectedRevision" }; break;
                case "spawnItem": keys = new[] { "v", "token", "operationId", "expectedRevision", "itemName", "quantity" }; break;
                case "levelAction": keys = new[] { "v", "token", "operationId", "expectedRevision", "levelAction" }; break;
                case "grantTask": keys = new[] { "v", "token", "operationId", "expectedRevision", "taskId" }; break;
                case "spawnUnit": keys = new[] { "v", "token", "operationId", "expectedRevision", "unitId", "count", "level", "hostile" }; break;
                case "spawnMerc": keys = new[] { "v", "token", "operationId", "expectedRevision", "unitId", "level", "hostile" }; break;
                default: return false;
            }
            if (!Exact(payload, keys)) return false;
            if (!SafeToken.IsMatch(Text(payload["token"]) ?? "")) return false;
            if (cmd == "items" || cmd == "units")
            {
                string query = Text(payload["query"]);
                if (query == null || query.Length > 64 || !Integer(payload["page"], 1, 9999)) return false;
            }
            if (cmd == "query")
            {
                if (!SafeOperation.IsMatch(Text(payload["operationId"]) ?? "")) return false;
            }
            if (cmd == "itemTooltip")
            {
                string itemName = Text(payload["itemName"]);
                if (itemName == null || itemName.Length < 1 || itemName.Length > 128) return false;
            }
            if (cmd == "unitFrame")
            {
                string spriteName = Text(payload["spriteName"]);
                if (spriteName == null || spriteName.Length < 1 || spriteName.Length > 256) return false;
            }
            if (WriteCommands.Contains(cmd))
            {
                if (!SafeOperation.IsMatch(Text(payload["operationId"]) ?? "")) return false;
                long revision;
                if (!Integer(payload["expectedRevision"], 0, 9007199254740991L, out revision)) return false;
                expectedRevision = (int)Math.Min(revision, int.MaxValue);
            }
            if (cmd == "spawnItem")
            {
                string itemName = Text(payload["itemName"]);
                if (string.IsNullOrEmpty(itemName) || itemName.Length > 64) return false;
                if (!Integer(payload["quantity"], 1, 999999999)) return false;
            }
            if (cmd == "levelAction")
            {
                string action = Text(payload["levelAction"]);
                if (action == null || !LevelActions.Contains(action)) return false;
            }
            if (cmd == "grantTask")
            {
                if (!Integer(payload["taskId"], 1, 999)) return false;
            }
            if (cmd == "spawnUnit" || cmd == "spawnMerc")
            {
                if (!Integer(payload["unitId"], 0, 999999)) return false;
                if (!Integer(payload["level"], 1, 9999)) return false;
                if (payload["hostile"]?.Type != JTokenType.Boolean) return false;
                if (cmd == "spawnUnit" && !Integer(payload["count"], 1, 100)) return false;
            }
            return true;
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            PanelPendingCall<PendingRequest> call;
            JObject response;
            lock (_gate)
            {
                int fid = Integer(message?["callId"], 1, int.MaxValue) ? message.Value<int>("callId") : 0;
                if (!_pending.TryComplete(fid, out call)) { respond?.Invoke(null); return; }
                var entry = call.Context;
                if (entry.IsWrite) _writePending = false;

                bool valid = ValidResponse(message, entry, out bool ambiguous, out bool definitive);
                if (entry.IsWrite)
                {
                    if (valid && (message.Value<bool>("success") || (definitive && !ambiguous)))
                    {
                        if (entry.Token == _unresolvedToken && entry.OperationId == _unresolvedOperationId)
                        { _unresolvedToken = null; _unresolvedOperationId = null; }
                    }
                    else if (!valid || ambiguous)
                    {
                        if (entry.Token == _unresolvedToken && entry.OperationId == _unresolvedOperationId)
                        {
                            // Keep the write watermark; response below reports reconcile.
                        }
                    }
                }
                else if (entry.Cmd == "query" && valid && definitive && !ambiguous)
                {
                    if (entry.Token == _unresolvedToken
                        && (entry.OperationId == _unresolvedOperationId
                            || Text(message["queriedOperation"]) == _unresolvedOperationId))
                    { _unresolvedToken = null; _unresolvedOperationId = null; }
                }
                if (!valid)
                {
                    response = new JObject
                    {
                        ["success"] = false,
                        ["error"] = "malformed_response"
                    };
                }
                else
                {
                    response = (JObject)message.DeepClone();
                }
                response["requiresReconcile"] = _unresolvedOperationId != null;
                if (_unresolvedOperationId != null)
                {
                    response["recoveryToken"] = _unresolvedToken;
                    response["recoveryOperationId"] = _unresolvedOperationId;
                }
                response.Remove("task");
                Envelope(response, call.WebCallId, entry.Cmd, entry.Instance);
            }
            Post(response);
            respond?.Invoke(null);
        }

        private static bool ValidResponse(JObject value, PendingRequest entry, out bool ambiguous, out bool definitive)
        {
            ambiguous = false;
            definitive = false;
            if (value == null) return false;
            if (!Integer(value["v"], 1, 1) || !string.Equals(Text(value["operation"]), entry.Cmd, StringComparison.Ordinal)
                || !string.Equals(Text(value["token"]), entry.Token, StringComparison.Ordinal)
                || value["success"]?.Type != JTokenType.Boolean) return false;
            if (entry.Cmd == "query" && !string.Equals(Text(value["queriedOperation"]), entry.OperationId, StringComparison.Ordinal))
                return false;
            if (WriteCommands.Contains(entry.Cmd))
            {
                if (!string.Equals(Text(value["operationId"]), entry.OperationId, StringComparison.Ordinal)) return false;
                if (!Integer(value["revision"], 0, 9007199254740991L)) return false;
                bool success = value.Value<bool>("success");
                if (success)
                {
                    if (value["error"]?.Type == JTokenType.String && Text(value["error"]) != "") return false;
                    return true;
                }
                string error = Text(value["error"]);
                if (string.IsNullOrEmpty(error)) return false;
                bool reconcile = value["requiresReconcile"]?.Type == JTokenType.Boolean
                    && value.Value<bool>("requiresReconcile");
                ambiguous = reconcile || error == "apply_ambiguous" || error == "apply_failed"
                    || error == "malformed_response" || error == "reconcile_required";
                definitive = DefinitiveErrors.Contains(error);
                return definitive || ambiguous;
            }
            if (entry.Cmd == "query")
            {
                if (!Integer(value["revision"], 0, 9007199254740991L)) return false;
                if (value.Value<bool>("success")) { definitive = true; return true; }
                string error = Text(value["error"]);
                if (string.IsNullOrEmpty(error)) return false;
                ambiguous = error == "apply_ambiguous" || error == "apply_failed";
                definitive = DefinitiveErrors.Contains(error);
                return definitive || ambiguous;
            }
            if (!value.Value<bool>("success"))
            {
                string readError = Text(value["error"]);
                return !string.IsNullOrEmpty(readError)
                    && (DefinitiveErrors.Contains(readError) || readError == "reconcile_required");
            }
            if (entry.Cmd == "snapshot") return ValidSnapshot(value);
            if (entry.Cmd == "items") return ValidItems(value, entry);
            if (entry.Cmd == "units") return ValidUnits(value, entry);
            return false;
        }

        private static bool ValidSnapshot(JObject value)
        {
            if (!Integer(value["revision"], 0, 9007199254740991L)) return false;
            string phase = Text(value["phase"]);
            if (phase != "editing" && phase != "reconcile" && phase != "closed" && phase != "expired") return false;
            if (!Integer(value["itemCount"], 0, 1000000) || !Integer(value["unitCount"], 0, 1000000)
                || !Integer(value["itemPageSize"], 1, 1000) || !Integer(value["unitPageSize"], 1, 1000)) return false;
            JObject state = value["state"] as JObject;
            if (state == null || !Exact(state, "money", "kcoin", "maxLevel", "inWorld", "stageActive", "challengeMode", "saveAvailable"))
                return false;
            if (!Integer(state["money"], 0, 9007199254740991L) || !Integer(state["kcoin"], 0, 9007199254740991L)
                || !Integer(state["maxLevel"], 0, 999999)) return false;
            if (state["inWorld"]?.Type != JTokenType.Boolean || state["challengeMode"]?.Type != JTokenType.Boolean
                || state["saveAvailable"]?.Type != JTokenType.Boolean) return false;
            string stage = Text(state["stageActive"]);
            return stage == "none" || stage == "Active" || stage == "Finished" || stage == "Failed";
        }

        private static bool ValidItems(JObject value, PendingRequest entry)
        {
            if (!Integer(value["revision"], 0, 9007199254740991L)) return false;
            string query = Text(value["query"]);
            if (query == null || query.Length > 64) return false;
            if (!Integer(value["page"], 1, 9999) || !Integer(value["pageSize"], 1, 1000)
                || !Integer(value["total"], 0, 1000000)) return false;
            JArray items = value["items"] as JArray;
            if (items == null || items.Count > value.Value<int>("pageSize")) return false;
            foreach (JToken token in items)
            {
                JObject item = token as JObject;
                if (item == null || !Exact(item, "id", "name", "displayName", "icon", "type", "use")) return false;
                if (!Integer(item["id"], 0, 9007199254740991L)) return false;
                if (!SafeText(item["name"], 1, 128) || !SafeText(item["displayName"], 1, 256)
                    || !SafeText(item["icon"], 1, 256) || !SafeText(item["type"], 0, 64) || !SafeText(item["use"], 0, 64))
                    return false;
            }
            return true;
        }

        private static bool ValidUnits(JObject value, PendingRequest entry)
        {
            if (!Integer(value["revision"], 0, 9007199254740991L)) return false;
            string query = Text(value["query"]);
            if (query == null || query.Length > 64) return false;
            if (!Integer(value["page"], 1, 9999) || !Integer(value["pageSize"], 1, 1000)
                || !Integer(value["total"], 0, 1000000)) return false;
            JArray units = value["units"] as JArray;
            if (units == null || units.Count > value.Value<int>("pageSize")) return false;
            foreach (JToken token in units)
            {
                JObject unit = token as JObject;
                if (unit == null || !Exact(unit, "id", "name", "spriteName", "key", "level", "hostile")) return false;
                if (!Integer(unit["id"], 0, 999999) || !Integer(unit["level"], 0, 999999)) return false;
                if (!SafeText(unit["name"], 0, 128) || !SafeText(unit["spriteName"], 1, 256)
                    || !SafeText(unit["key"], 0, 256) || unit["hostile"]?.Type != JTokenType.Boolean) return false;
            }
            return true;
        }

        private void RejectAndRemember(string callId, string cmd, string instance, string error)
        {
            if (!_pending.TryRememberRejected(callId)) return;
            var result = new JObject
            {
                ["success"] = false,
                ["error"] = error,
                ["requiresReconcile"] = _unresolvedOperationId != null
            };
            if (_unresolvedOperationId != null)
            {
                result["recoveryToken"] = _unresolvedToken;
                result["recoveryOperationId"] = _unresolvedOperationId;
            }
            Envelope(result, callId, cmd, instance);
            Post(result);
        }

        private void OnPendingEnded(PanelPendingCall<PendingRequest> call, PanelPendingCallEndReason reason)
        {
            lock (_gate)
            {
                if (call.Context.IsWrite) _writePending = false;
                if (reason == PanelPendingCallEndReason.Cleared) return;
                var result = new JObject
                {
                    ["success"] = false,
                    ["error"] = reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                    ["requiresReconcile"] = _unresolvedOperationId != null
                };
                if (_unresolvedOperationId != null)
                {
                    result["recoveryToken"] = _unresolvedToken;
                    result["recoveryOperationId"] = _unresolvedOperationId;
                }
                Envelope(result, call.WebCallId, call.Context.Cmd, call.Context.Instance);
                Post(result);
            }
        }

        private static void Envelope(JObject value, string callId, string cmd, string instance)
        {
            value["type"] = "panel_resp";
            value["panel"] = "modifier";
            value["domain"] = "modifier";
            value["cmd"] = cmd;
            value["callId"] = callId;
            value["panelInstanceId"] = instance;
        }

        private void Post(JObject value)
        {
            string text = value.ToString(Formatting.None);
            Action send = () =>
            {
                if (_disposed) return;
                Action<string> post;
                lock (_webGate) post = _post;
                post?.Invoke(text);
            };
            Action<Action> invoke;
            lock (_webGate) invoke = _invoke;
            if (invoke != null) invoke(send); else send();
        }

        private static string Text(JToken value) =>
            value?.Type == JTokenType.String ? value.Value<string>() : null;

        private static bool SafeText(JToken value, int min, int max)
        {
            string text = Text(value);
            return text != null && text.Length >= min && text.Length <= max;
        }

        private static bool Exact(JObject value, params string[] keys) =>
            value != null && value.Properties().Count() == keys.Length
            && keys.All(k => value.Property(k, StringComparison.Ordinal) != null);

        private static bool Integer(JToken value, long min, long max)
        {
            long number;
            return Integer(value, min, max, out number);
        }

        private static bool Integer(JToken value, long min, long max, out long number)
        {
            number = 0;
            if (value?.Type != JTokenType.Integer) return false;
            try { number = value.Value<long>(); return number >= min && number <= max; }
            catch (OverflowException) { return false; }
        }
    }
}
