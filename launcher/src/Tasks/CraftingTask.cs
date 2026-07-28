using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>crafting domain 的严格 WebView↔Flash callId 桥与提交对账门。</summary>
    public sealed class CraftingTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public bool IsWrite;
        }

        private const int DefaultTimeoutMs = 10000;
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidToken = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);
        private static readonly HashSet<string> Categories = new HashSet<string>(StringComparer.Ordinal)
        {
            "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
            "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
        };
        private static readonly HashSet<string> AvailabilityCodes = new HashSet<string>(StringComparer.Ordinal)
        {
            "ready", "level_locked", "material_missing", "insufficient_money",
            "insufficient_kpoint", "inventory_full"
        };

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        public CraftingTask(XmlSocketServer socket)
            : this(delegate { return socket != null && socket.IsClientReady; },
                   delegate(string payload) { return socket != null && socket.TrySend(payload); }, DefaultTimeoutMs) { }

        public CraftingTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                timeoutMs,
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        internal string WriteState { get { lock (_lock) return _writeState; } }
        public void Dispose()
        {
            lock (_lock) { _pendingCalls.Dispose(); }
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null ? parsed.Value<string>("callId") : null;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId)) { RespondError(callId, cmd, "invalid_call_id"); return; }
            if (!string.Equals(parsed.Value<string>("domain"), "crafting", StringComparison.Ordinal))
            { RejectAndRemember(callId, cmd, "unsupported_domain"); return; }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            { RejectAndRemember(callId, cmd, "unsupported_cmd"); return; }
            JObject payload = parsed["payload"] as JObject;
            JObject normalized;
            if (payload == null || !HasProtocolVersion(payload) || !TryNormalizePayload(cmd, payload, out normalized))
            { RejectAndRemember(callId, cmd, "invalid_payload"); return; }
            if (!_pendingCalls.IsReady()) { RejectAndRemember(callId, cmd, "disconnected"); return; }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (isWrite && _writeState != "idle")
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest { WebCmd = cmd, IsWrite = isWrite },
                    out fid)) return;
                if (isWrite) _writeState = "write_pending";
            }

            string json = PanelBridge.BuildFlashCommand(action, fid, normalized).ToString(Formatting.None);
            LogManager.Log("[CraftingTask] -> Flash: " + json);
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid = msg != null ? msg.Value<int>("callId") : 0;
            PendingRequest entry;
            PanelPendingCall<PendingRequest> pendingCall;
            bool malformed;
            bool definitiveWrite;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }
                entry = pendingCall.Context;
                malformed = IsMalformedResponse(msg, entry);
                definitiveWrite = entry.IsWrite && !malformed && IsDefinitiveWriteResponse(msg);
                if (entry.IsWrite) _writeState = definitiveWrite ? "idle" : "needs_reconcile";
                else if (entry.WebCmd == "preview" && !malformed && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile") _writeState = "idle";
            }
            JObject web = malformed
                ? new JObject { ["success"] = false, ["error"] = "malformed_response" }
                : (JObject)msg.DeepClone();
            web.Remove("task");
            web["type"] = "panel_resp";
            web["domain"] = "crafting";
            web["cmd"] = entry.WebCmd;
            web["callId"] = pendingCall.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock) { _pendingCalls.Clear(); }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "craftingSnapshot"; return true;
                case "materials": action = "craftingMaterials"; return true;
                case "materialDetail": action = "craftingMaterialDetail"; return true;
                case "preview": action = "craftingPreview"; return true;
                case "tooltip": action = "craftingTooltip"; return true;
                case "commit": action = "craftingCommit"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = new JObject { ["v"] = 1 };
            if (cmd == "materials") return true;
            if (cmd == "tooltip" || cmd == "materialDetail")
            {
                string itemName = payload.Value<string>("itemName");
                if (!IsSafeText(itemName, 128)) return false;
                normalized["itemName"] = itemName;
                return true;
            }
            string category = payload.Value<string>("category");
            if (!Categories.Contains(category)) return false;
            normalized["category"] = category;
            if (cmd == "snapshot") return true;
            if (cmd == "preview")
            {
                int recipeIndex;
                int craftCount;
                if (!TryReadInteger(payload["recipeIndex"], 0, 999, out recipeIndex)) return false;
                if (!TryReadInteger(payload["craftCount"], 1, 99, out craftCount)) return false;
                normalized["recipeIndex"] = recipeIndex;
                normalized["craftCount"] = craftCount;
                return true;
            }
            if (cmd == "commit")
            {
                string token = payload.Value<string>("expectedCraftToken");
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)) return false;
                normalized["expectedCraftToken"] = token;
                return true;
            }
            return false;
        }

        private static bool TryReadInteger(JToken token, int min, int max, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            if (candidate < min || candidate > max) return false;
            value = (int)candidate;
            return true;
        }

        private static bool IsSafeText(string value, int max)
        {
            if (string.IsNullOrEmpty(value) || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool IsMalformedResponse(JObject msg, PendingRequest entry)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return true;
            if (msg.Value<bool>("success"))
            {
                if (entry.WebCmd == "snapshot") return !IsAuthoritativeSnapshot(msg);
                if (entry.WebCmd == "materials") return !IsAuthoritativeMaterials(msg);
                if (entry.WebCmd == "materialDetail") return !IsAuthoritativeMaterialDetail(msg);
                if (entry.WebCmd == "preview") return !IsAuthoritativePreview(msg);
                if (entry.WebCmd == "commit") return !IsAuthoritativeCommit(msg);
                return !HasProtocolVersion(msg) || !IsSafeText(msg.Value<string>("itemName"), 128);
            }
            return string.IsNullOrEmpty(msg.Value<string>("error"));
        }

        private static bool IsAuthoritativeSnapshot(JObject msg)
        {
            var recipes = msg["recipes"] as JArray;
            string gender = msg.Value<string>("gender");
            if (!CommonState(msg) || recipes == null || !(msg["skills"] is JObject)
                || (gender != "男" && gender != "女")) return false;
            var seenIndexes = new HashSet<int>();
            foreach (JToken token in recipes)
            {
                var recipe = token as JObject;
                var output = recipe != null ? recipe["output"] as JObject : null;
                var baseCost = recipe != null ? recipe["baseCost"] as JObject : null;
                int recipeIndex;
                int materialCount;
                if (recipe == null || output == null || baseCost == null
                    || !TryReadInteger(recipe["recipeIndex"], 0, 999, out recipeIndex)
                    || !seenIndexes.Add(recipeIndex)
                    || !TryReadInteger(recipe["materialCount"], 0, 999, out materialCount)
                    || recipe["batchEligible"] == null || recipe["batchEligible"].Type != JTokenType.Boolean
                    || recipe["canCraftOne"] == null || recipe["canCraftOne"].Type != JTokenType.Boolean
                    || !IsSafeText(recipe.Value<string>("title"), 256)
                    || !IsSafeText(output.Value<string>("name"), 128)
                    || !IsNumber(baseCost["money"]) || !IsNumber(baseCost["kpoints"])) return false;
                string availability = recipe.Value<string>("availability");
                bool canCraftOne = recipe.Value<bool>("canCraftOne");
                if (!AvailabilityCodes.Contains(availability)
                    || canCraftOne != string.Equals(availability, "ready", StringComparison.Ordinal)) return false;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterials(JObject msg)
        {
            var materials = msg["materials"] as JArray;
            if (!HasProtocolVersion(msg)
                || msg.Value<string>("view") != "materials"
                || materials == null) return false;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in materials)
            {
                var material = token as JObject;
                int sourceCount;
                int useCount;
                if (material == null
                    || !IsSafeText(material.Value<string>("name"), 128)
                    || !names.Add(material.Value<string>("name"))
                    || !IsSafeText(material.Value<string>("displayName"), 256)
                    || !IsSafeText(material.Value<string>("icon"), 256)
                    || !IsNonNegativeNumber(material["owned"])
                    || !TryReadInteger(material["sourceCount"], 0, 100000, out sourceCount)
                    || !TryReadInteger(material["useCount"], 0, 100000, out useCount)
                    || material["hasSourceSummary"] == null
                    || material["hasSourceSummary"].Type != JTokenType.Boolean) return false;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterialDetail(JObject msg)
        {
            var material = msg["material"] as JObject;
            var sources = msg["sources"] as JArray;
            var uses = msg["uses"] as JArray;
            if (!HasProtocolVersion(msg)
                || msg.Value<string>("view") != "materials"
                || material == null || sources == null || uses == null
                || !IsSafeText(material.Value<string>("name"), 128)
                || !IsSafeText(material.Value<string>("displayName"), 256)
                || !IsSafeText(material.Value<string>("icon"), 256)
                || !IsSafeMultilineText(material.Value<string>("description"), 12000)
                || !IsSafeMultilineText(material.Value<string>("sourceSummary"), 20000)
                || !IsNonNegativeNumber(material["owned"])) return false;
            foreach (JToken token in sources)
            {
                var source = token as JObject;
                string kind = source != null ? source.Value<string>("kind") : null;
                if (source == null
                    || (kind != "craft" && kind != "shop" && kind != "kshop"
                        && kind != "quest" && kind != "stage" && kind != "enemy")
                    || !SafeOptionalFields(source, new[]
                        {
                            "category", "npc", "requirement", "questId", "title",
                            "stageName", "enemyType", "displayName"
                        })) return false;
                foreach (string field in new[]
                    {
                        "price", "kpoints", "priceK", "quantity", "probability",
                        "quantityMax", "minLevel", "maxLevel"
                    })
                {
                    if (source[field] != null && !IsNumber(source[field])) return false;
                }
            }
            foreach (JToken token in uses)
            {
                var use = token as JObject;
                if (use == null
                    || !IsSafeText(use.Value<string>("name"), 128)
                    || !IsSafeText(use.Value<string>("displayName"), 256)
                    || !IsSafeText(use.Value<string>("icon"), 256)
                    || !IsSafeText(use.Value<string>("itemKind"), 32)
                    || !IsSafeOptionalText(use.Value<string>("category"), 128)
                    || !IsNonNegativeNumber(use["required"])) return false;
            }
            return true;
        }

        private static bool SafeOptionalFields(JObject value, IEnumerable<string> fields)
        {
            foreach (string field in fields)
            {
                if (value[field] != null
                    && !IsSafeOptionalText(value.Value<string>(field), 512)) return false;
            }
            return true;
        }

        private static bool IsSafeOptionalText(string value, int max)
        {
            if (value == null || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool IsSafeMultilineText(string value, int max)
        {
            if (value == null || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char current = value[i];
                if (char.IsControl(current)
                    && current != '\r' && current != '\n' && current != '\t') return false;
            }
            return true;
        }

        private static bool IsNonNegativeNumber(JToken value)
        {
            return IsNumber(value) && value.Value<double>() >= 0;
        }

        private static bool IsAuthoritativePreview(JObject msg)
        {
            int recipeIndex;
            int craftCount;
            int maxCraftCount;
            if (!CommonState(msg) || !TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                || !TryReadInteger(msg["maxCraftCount"], 0, 99, out maxCraftCount)
                || !(msg["output"] is JObject) || !(msg["materials"] is JArray) || !(msg["cost"] is JObject)
                || msg["batchEligible"] == null || msg["batchEligible"].Type != JTokenType.Boolean
                || msg["canCommit"] == null || msg["canCommit"].Type != JTokenType.Boolean) return false;
            var cost = msg["cost"] as JObject;
            if (cost == null || !IsNumber(cost["money"]) || !IsNumber(cost["kpoints"])) return false;
            bool batchEligible = msg.Value<bool>("batchEligible");
            bool canCommit = msg.Value<bool>("canCommit");
            if (!batchEligible && (craftCount != 1 || maxCraftCount > 1)) return false;
            if (canCommit)
            {
                if (maxCraftCount < craftCount) return false;
                string token = msg.Value<string>("craftToken");
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)) return false;
            }
            else if (msg["craftToken"] != null) return false;
            return msg["output"] is JObject && msg["materials"] is JArray
                && msg["canCommit"] != null && msg["canCommit"].Type == JTokenType.Boolean;
        }

        private static bool IsAuthoritativeCommit(JObject msg)
        {
            int recipeIndex;
            int craftCount;
            var crafted = msg["crafted"] as JObject;
            return CommonState(msg) && msg.Value<string>("operation") == "commit"
                && TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex) && crafted != null
                && TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                && IsSafeText(crafted.Value<string>("name"), 128);
        }

        private static bool CommonState(JObject msg)
        {
            var balance = msg["balance"] as JObject;
            return HasProtocolVersion(msg) && Categories.Contains(msg.Value<string>("category"))
                && balance != null && IsNumber(balance["money"]) && IsNumber(balance["kpoints"]);
        }

        private static bool HasProtocolVersion(JObject value)
        {
            return value != null && value["v"] != null && value["v"].Type == JTokenType.Integer
                && value.Value<int>("v") == 1;
        }

        private static bool IsNumber(JToken value)
        {
            return value != null && (value.Type == JTokenType.Integer || value.Type == JTokenType.Float);
        }

        private static bool IsDefinitiveWriteResponse(JObject msg)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (msg.Value<bool>("success")) return IsAuthoritativeCommit(msg);
            switch (msg.Value<string>("error"))
            {
                case "invalid_payload": case "category_not_found": case "recipe_not_found":
                case "batch_not_supported":
                case "stale_state": case "material_missing": case "insufficient_money":
                case "insufficient_kpoint": case "inventory_full": case "level_locked": case "busy": return true;
                default: return false;
            }
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = pendingCall.Context;
            lock (_lock)
            {
                if (entry.IsWrite) _writeState = "needs_reconcile";
            }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                entry.IsWrite);
        }

        private void RejectAndRemember(string callId, string cmd, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(callId, cmd, error, false);
        }

        private void RespondError(string callId, string cmd, string error, bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "crafting", ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "", ["success"] = false, ["error"] = error
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null) _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }
    }
}
