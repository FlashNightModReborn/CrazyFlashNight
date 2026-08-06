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
            public string OwnerPanel;
            public string OwnerPanelInstanceId;
            public JObject NormalizedPayload;
            public bool IsWrite;
            public bool IsReconcileProbe;
            public int ReconcileEpoch;
            public int PreviewEpoch;
            public PreviewAuthority ExpectedPreview;
        }

        private sealed class PreviewAuthority
        {
            public string OwnerPanelInstanceId;
            public string Token;
            public string Category;
            public int RecipeIndex;
            public int CraftCount;
            public JObject Output;
            public JObject AcceptedPlan;
        }

        private const int DefaultTimeoutMs = 10000;
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidPanelInstanceId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidToken = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);
        private static readonly HashSet<string> Categories = new HashSet<string>(StringComparer.Ordinal)
        {
            "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
            "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
        };
        private static readonly HashSet<string> AvailabilityCodes = new HashSet<string>(StringComparer.Ordinal)
        {
            "ready", "level_locked", "material_missing", "insufficient_money",
            "insufficient_kpoint", "inventory_full", "output_projection_failed"
        };
        private static readonly HashSet<string> StorageKinds = new HashSet<string>(StringComparer.Ordinal)
        {
            "bag", "drug", "bag_and_drug", "material_collection",
            "information_collection", "unavailable"
        };

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        private int _reconcileEpoch;
        private int _previewEpoch;
        private PreviewAuthority _previewAuthority;
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
            string callId = parsed != null ? ReadExactString(parsed["callId"]) : null;
            string ownerPanel = parsed != null ? ReadExactString(parsed["panel"]) : null;
            string ownerPanelInstanceId = parsed != null
                ? ReadExactString(parsed["panelInstanceId"]) : null;
            if (!string.Equals(ownerPanel, "crafting", StringComparison.Ordinal)
                || string.IsNullOrEmpty(ownerPanelInstanceId)
                || !ValidPanelInstanceId.IsMatch(ownerPanelInstanceId)) return;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId))
            {
                RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_call_id");
                return;
            }
            if (!string.Equals(ReadExactString(parsed["domain"]), "crafting", StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_domain");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_cmd");
                return;
            }
            JObject payload = parsed["payload"] as JObject;
            JObject normalized;
            if (payload == null || !HasProtocolVersion(payload) || !TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }
            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (isWrite && _writeState != "idle")
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId,
                        _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }
                PreviewAuthority expectedPreview = null;
                if (cmd == "commit")
                {
                    if (!TryConsumePreviewAuthorityLocked(
                            ownerPanelInstanceId, normalized, out expectedPreview))
                    {
                        if (!_pendingCalls.TryRememberRejected(callId)) return;
                        RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "stale_state");
                        return;
                    }
                }
                else if (cmd == "preview" || cmd == "snapshot")
                {
                    _previewEpoch++;
                    _previewAuthority = null;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        OwnerPanel = ownerPanel,
                        OwnerPanelInstanceId = ownerPanelInstanceId,
                        NormalizedPayload = (JObject)normalized.DeepClone(),
                        IsWrite = isWrite,
                        IsReconcileProbe = cmd == "preview"
                            && _writeState == "needs_reconcile",
                        ReconcileEpoch = _reconcileEpoch,
                        PreviewEpoch = _previewEpoch,
                        ExpectedPreview = expectedPreview
                    },
                    out fid)) return;
                if (isWrite) _writeState = "write_pending";
            }

            JObject flash = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string json = flash.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "CraftingTask", callId, fid, ownerPanel, ownerPanelInstanceId,
                cmd, action));
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "CraftingTask", flash));
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid;
            if (msg == null || !TryReadInteger(msg["callId"], 1, int.MaxValue, out fid))
            {
                if (respond != null) respond(null);
                return;
            }
            PendingRequest entry;
            PanelPendingCall<PendingRequest> pendingCall;
            bool valid;
            bool definitiveWrite;
            JObject authority;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }
                entry = pendingCall.Context;
                valid = TrySanitizeResponse(msg, entry, out authority);
                if (entry.WebCmd == "preview" && entry.PreviewEpoch == _previewEpoch)
                    UpdatePreviewAuthorityLocked(msg, entry, valid);
                definitiveWrite = entry.IsWrite && valid && IsDefinitiveWriteResponse(msg);
                if (entry.IsWrite)
                {
                    if (definitiveWrite) _writeState = "idle";
                    else EnterNeedsReconcileLocked();
                }
                else if (entry.IsReconcileProbe
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && entry.WebCmd == "preview" && valid && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile") _writeState = "idle";
            }
            JObject web = valid
                ? authority
                : new JObject { ["success"] = false, ["error"] = "malformed_response" };
            web["type"] = "panel_resp";
            web["domain"] = "crafting";
            web["panel"] = entry.OwnerPanel;
            web["panelInstanceId"] = entry.OwnerPanelInstanceId;
            web["cmd"] = entry.WebCmd;
            web["callId"] = pendingCall.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                _previewEpoch++;
                _previewAuthority = null;
                _pendingCalls.Clear();
            }
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
            if (cmd == "materials") return HasExactKeys(payload, "v");
            if (cmd == "tooltip" || cmd == "materialDetail")
            {
                if (!HasExactKeys(payload, "v", "itemName")) return false;
                string itemName = ReadExactString(payload["itemName"]);
                if (!IsIdentityText(itemName, 128)) return false;
                normalized["itemName"] = itemName;
                return true;
            }
            if (cmd == "snapshot" && !HasExactKeys(payload, "v", "category")) return false;
            if (cmd == "preview" && !HasExactKeys(
                    payload, "v", "category", "recipeIndex", "craftCount")) return false;
            if (cmd == "commit" && !HasExactKeys(
                    payload, "v", "category", "expectedCraftToken")) return false;
            string category = ReadExactString(payload["category"]);
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
                string token = ReadExactString(payload["expectedCraftToken"]);
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
            if (string.IsNullOrWhiteSpace(value) || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool TryReadLongInteger(
            JToken token, long min, long max, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.ToObject<long>(); }
            catch { return false; }
            return value >= min && value <= max;
        }

        private static bool IsIdentityText(string value, int max)
        {
            return IsSafeText(value, max)
                && !string.Equals(value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }

        private bool TryConsumePreviewAuthorityLocked(
            string ownerPanelInstanceId, JObject normalized, out PreviewAuthority authority)
        {
            authority = _previewAuthority;
            if (authority == null || normalized == null
                || !string.Equals(authority.OwnerPanelInstanceId, ownerPanelInstanceId, StringComparison.Ordinal)
                || !string.Equals(authority.Category,
                    ReadExactString(normalized["category"]), StringComparison.Ordinal)
                || !string.Equals(authority.Token,
                    ReadExactString(normalized["expectedCraftToken"]), StringComparison.Ordinal))
            {
                authority = null;
                return false;
            }
            _previewAuthority = null;
            return true;
        }

        private void UpdatePreviewAuthorityLocked(JObject msg, PendingRequest entry, bool valid)
        {
            _previewAuthority = null;
            if (!valid || msg.Value<bool?>("success") != true
                || msg.Value<bool?>("canCommit") != true) return;
            int recipeIndex;
            int craftCount;
            if (!TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)) return;
            _previewAuthority = new PreviewAuthority
            {
                OwnerPanelInstanceId = entry.OwnerPanelInstanceId,
                Token = ReadExactString(msg["craftToken"]),
                Category = ReadExactString(msg["category"]),
                RecipeIndex = recipeIndex,
                CraftCount = craftCount,
                Output = (JObject)msg["output"].DeepClone(),
                AcceptedPlan = (JObject)msg["acceptedPlan"].DeepClone()
            };
        }

        private static bool TrySanitizeResponse(
            JObject msg, PendingRequest entry, out JObject sanitized)
        {
            sanitized = null;
            if (msg == null
                || !string.Equals(ReadExactString(msg["task"]), "crafting_response", StringComparison.Ordinal)
                || msg["callId"] == null || msg["callId"].Type != JTokenType.Integer
                || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (!msg.Value<bool>("success"))
            {
                string error = ReadExactString(msg["error"]);
                if (!HasExactKeys(msg, "task", "callId", "success", "error")
                    || !IsSafeText(error, 128)) return false;
                sanitized = new JObject { ["success"] = false, ["error"] = error };
                return true;
            }

            bool authoritative;
            switch (entry.WebCmd)
            {
                case "snapshot": authoritative = IsAuthoritativeSnapshot(msg, entry); break;
                case "materials": authoritative = IsAuthoritativeMaterials(msg); break;
                case "materialDetail": authoritative = IsAuthoritativeMaterialDetail(msg, entry); break;
                case "preview": authoritative = IsAuthoritativePreview(msg, entry); break;
                case "tooltip": authoritative = IsAuthoritativeTooltip(msg, entry); break;
                case "commit": authoritative = IsAuthoritativeCommit(msg, entry); break;
                default: authoritative = false; break;
            }
            if (!authoritative) return false;

            sanitized = (JObject)msg.DeepClone();
            sanitized.Remove("task");
            sanitized.Remove("callId");
            if (entry.WebCmd == "tooltip")
            {
                // AS2 的 tooltip profile 仍使用历史 displayname；只在这一条 Host
                // 边界翻译，Web 不再猜测多种展示字段。
                sanitized["displayName"] = sanitized["displayname"];
                sanitized.Remove("displayname");
            }
            return true;
        }

        private static bool IsAuthoritativeSnapshot(JObject msg, PendingRequest entry)
        {
            var recipes = msg["recipes"] as JArray;
            string gender = ReadExactString(msg["gender"]);
            if (!HasExactResponseKeys(msg, "v", "category", "gender", "recipes",
                    "balance", "skills", "note")
                || !HasProtocolVersion(msg)
                || !MatchesSelector(msg, entry, "category")
                || recipes == null || !IsBalance(msg["balance"] as JObject)
                || !IsSkills(msg["skills"] as JObject)
                || !IsSafeOptionalText(ReadExactString(msg["note"]), 2000)
                || (gender != "男" && gender != "女")) return false;
            var seenIndexes = new HashSet<int>();
            foreach (JToken token in recipes)
            {
                var recipe = token as JObject;
                var output = recipe != null ? recipe["output"] as JObject : null;
                var baseCost = recipe != null ? recipe["baseCost"] as JObject : null;
                int recipeIndex;
                int materialCount;
                if (recipe == null
                    || !HasExactKeys(recipe, "recipeIndex", "title", "output", "baseCost",
                        "materialCount", "batchEligible", "canCraftOne", "availability")
                    || !TryReadInteger(recipe["recipeIndex"], 0, 999, out recipeIndex)
                    || !seenIndexes.Add(recipeIndex)
                    || !TryReadInteger(recipe["materialCount"], 0, 999, out materialCount)
                    || recipe["batchEligible"] == null || recipe["batchEligible"].Type != JTokenType.Boolean
                    || recipe["canCraftOne"] == null || recipe["canCraftOne"].Type != JTokenType.Boolean
                    || !IsIdentityText(ReadExactString(recipe["title"]), 256)
                    || !IsProjectedItem(output, false)
                    || !IsCost(baseCost)) return false;
                string availability = ReadExactString(recipe["availability"]);
                bool canCraftOne = recipe.Value<bool>("canCraftOne");
                if (!AvailabilityCodes.Contains(availability)
                    || canCraftOne != string.Equals(availability, "ready", StringComparison.Ordinal)) return false;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterials(JObject msg)
        {
            var materials = msg["materials"] as JArray;
            if (!HasExactResponseKeys(msg, "v", "view", "materials")
                || !HasProtocolVersion(msg)
                || !string.Equals(ReadExactString(msg["view"]), "materials", StringComparison.Ordinal)
                || materials == null) return false;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in materials)
            {
                var material = token as JObject;
                int sourceCount;
                int useCount;
                string name = material != null ? ReadExactString(material["name"]) : null;
                if (material == null
                    || !HasExactKeys(material, "name", "displayName", "icon", "owned",
                        "sourceCount", "useCount", "hasSourceSummary")
                    || !IsIdentityTriple(material) || !names.Add(name)
                    || !IsNonNegativeNumber(material["owned"])
                    || !TryReadInteger(material["sourceCount"], 0, 100000, out sourceCount)
                    || !TryReadInteger(material["useCount"], 0, 100000, out useCount)
                    || material["hasSourceSummary"] == null
                    || material["hasSourceSummary"].Type != JTokenType.Boolean) return false;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterialDetail(JObject msg, PendingRequest entry)
        {
            var material = msg["material"] as JObject;
            var sources = msg["sources"] as JArray;
            var uses = msg["uses"] as JArray;
            if (!HasExactResponseKeys(msg, "v", "view", "material", "sources", "uses")
                || !HasProtocolVersion(msg)
                || !string.Equals(ReadExactString(msg["view"]), "materials", StringComparison.Ordinal)
                || material == null || sources == null || uses == null
                || !HasExactKeys(material, "name", "displayName", "icon", "description",
                    "owned", "sourceSummary")
                || !IsIdentityTriple(material)
                || !string.Equals(ReadExactString(material["name"]),
                    ReadExactString(entry.NormalizedPayload["itemName"]), StringComparison.Ordinal)
                || !IsSafeMultilineText(ReadExactString(material["description"]), 12000)
                || !IsSafeMultilineText(ReadExactString(material["sourceSummary"]), 20000)
                || !IsNonNegativeNumber(material["owned"])) return false;
            foreach (JToken token in sources)
            {
                if (!IsMaterialSource(token as JObject)) return false;
            }
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in uses)
            {
                var use = token as JObject;
                string name = use != null ? ReadExactString(use["name"]) : null;
                if (use == null
                    || !HasExactKeys(use, "name", "displayName", "icon", "itemKind", "category", "required")
                    || !IsIdentityTriple(use) || !names.Add(name)
                    || !IsItemKind(ReadExactString(use["itemKind"]))
                    || !IsSafeOptionalText(ReadExactString(use["category"]), 128)
                    || !IsNonNegativeNumber(use["required"])) return false;
            }
            return true;
        }

        private static bool IsMaterialSource(JObject source)
        {
            string kind = source != null ? ReadExactString(source["kind"]) : null;
            if (source == null || string.IsNullOrEmpty(kind)) return false;
            switch (kind)
            {
                case "craft":
                    return HasExactKeys(source, "kind", "category", "price", "kpoints")
                        && IsSafeOptionalText(ReadExactString(source["category"]), 512)
                        && IsNonNegativeNumber(source["price"]) && IsNonNegativeNumber(source["kpoints"]);
                case "shop":
                    return HasExactKeys(source, "kind", "npc", "requirement")
                        && IsSafeOptionalText(ReadExactString(source["npc"]), 512)
                        && IsSafeOptionalText(ReadExactString(source["requirement"]), 512);
                case "kshop":
                    return HasExactKeys(source, "kind", "category", "priceK")
                        && IsSafeOptionalText(ReadExactString(source["category"]), 512)
                        && IsNonNegativeNumber(source["priceK"]);
                case "quest":
                    return HasExactKeys(source, "kind", "questId", "title", "quantity")
                        && IsSafeOptionalText(ReadExactString(source["questId"]), 512)
                        && IsIdentityText(ReadExactString(source["title"]), 512)
                        && IsNonNegativeNumber(source["quantity"]);
                case "stage":
                    return HasExactKeys(source, "kind", "stageName", "probability", "quantityMax")
                        && IsSafeOptionalText(ReadExactString(source["stageName"]), 512)
                        && IsNonNegativeNumber(source["probability"])
                        && IsNonNegativeNumber(source["quantityMax"]);
                case "enemy":
                    return HasExactKeys(source, "kind", "enemyType", "displayName", "probability",
                            "minLevel", "maxLevel")
                        && IsSafeOptionalText(ReadExactString(source["enemyType"]), 512)
                        && IsIdentityText(ReadExactString(source["displayName"]), 512)
                        && IsNonNegativeNumber(source["probability"])
                        && IsNonNegativeNumber(source["minLevel"])
                        && IsNonNegativeNumber(source["maxLevel"]);
                default:
                    return false;
            }
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

        private static bool IsAuthoritativePreview(JObject msg, PendingRequest entry)
        {
            int recipeIndex;
            int craftCount;
            int maxCraftCount;
            bool canCommit = msg.Value<bool?>("canCommit") == true;
            string[] responseKeys = canCommit
                ? new[] { "v", "category", "recipeIndex", "craftCount", "batchEligible",
                    "maxCraftCount", "output", "materials", "cost", "balance", "skills",
                    "levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints",
                    "enoughSpace", "canCommit", "blockingError", "outputDelivery",
                    "craftToken", "acceptedPlan" }
                : new[] { "v", "category", "recipeIndex", "craftCount", "batchEligible",
                    "maxCraftCount", "output", "materials", "cost", "balance", "skills",
                    "levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints",
                    "enoughSpace", "canCommit", "blockingError", "outputDelivery" };
            if (!HasExactResponseKeys(msg, responseKeys)
                || !HasProtocolVersion(msg)
                || !MatchesSelector(msg, entry, "category", "recipeIndex", "craftCount")
                || !TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                || !TryReadInteger(msg["maxCraftCount"], 0, 99, out maxCraftCount)
                || !IsProjectedItem(msg["output"] as JObject, true)
                || !(msg["materials"] is JArray) || !IsCost(msg["cost"] as JObject)
                || !IsOutputDelivery(msg["outputDelivery"] as JObject, msg["output"] as JObject)
                || !IsBalance(msg["balance"] as JObject) || !IsSkills(msg["skills"] as JObject)
                || msg["batchEligible"] == null || msg["batchEligible"].Type != JTokenType.Boolean
                || msg["canCommit"] == null || msg["canCommit"].Type != JTokenType.Boolean
                || !HasExactBooleanFields(msg, "levelAllowed", "enoughMaterials", "enoughMoney",
                    "enoughKpoints", "enoughSpace")) return false;
            if (((JObject)msg["outputDelivery"]).Value<bool>("available")
                != msg.Value<bool>("enoughSpace")) return false;
            foreach (JToken materialToken in (JArray)msg["materials"])
            {
                if (!IsRequirement(materialToken as JObject)) return false;
                if (canCommit && string.Equals(ReadExactString(materialToken["storageKind"]),
                    "unavailable", StringComparison.Ordinal)) return false;
            }
            bool batchEligible = msg.Value<bool>("batchEligible");
            if (!batchEligible && (craftCount != 1 || maxCraftCount > 1)) return false;
            bool allConditions = msg.Value<bool>("levelAllowed")
                && msg.Value<bool>("enoughMaterials")
                && msg.Value<bool>("enoughMoney")
                && msg.Value<bool>("enoughKpoints")
                && msg.Value<bool>("enoughSpace");
            if (canCommit != allConditions) return false;
            if (canCommit)
            {
                if (maxCraftCount < craftCount) return false;
                if (!string.IsNullOrEmpty(ReadExactString(msg["blockingError"]))) return false;
                string token = ReadExactString(msg["craftToken"]);
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)
                    || !IsAcceptedPlan(msg["acceptedPlan"] as JObject, msg)) return false;
            }
            else if (!AvailabilityCodes.Contains(ReadExactString(msg["blockingError"]))) return false;
            return true;
        }

        private static bool IsAuthoritativeTooltip(JObject msg, PendingRequest entry)
        {
            return HasExactResponseKeys(msg, "v", "itemName", "displayname", "descHTML", "introHTML")
                && HasProtocolVersion(msg)
                && string.Equals(ReadExactString(msg["itemName"]),
                    ReadExactString(entry.NormalizedPayload["itemName"]), StringComparison.Ordinal)
                && IsIdentityText(ReadExactString(msg["displayname"]), 256)
                && IsSafeMultilineText(ReadExactString(msg["descHTML"]), 20000)
                && IsSafeMultilineText(ReadExactString(msg["introHTML"]), 20000);
        }

        private static bool IsAuthoritativeCommit(JObject msg, PendingRequest entry)
        {
            int recipeIndex;
            int craftCount;
            var crafted = msg["crafted"] as JObject;
            if (!HasExactResponseKeys(msg, "v", "operation", "category", "recipeIndex",
                    "craftCount", "crafted", "acceptedPlan", "outputReceipt", "balance")
                || !HasProtocolVersion(msg)
                || !string.Equals(ReadExactString(msg["operation"]), "commit", StringComparison.Ordinal)
                || !MatchesSelector(msg, entry, "category")
                || entry.ExpectedPreview == null) return false;
            if (!TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                || !IsProjectedItem(crafted, true)
                || !IsBalance(msg["balance"] as JObject)
                || recipeIndex != entry.ExpectedPreview.RecipeIndex
                || craftCount != entry.ExpectedPreview.CraftCount
                || !string.Equals(ReadExactString(msg["category"]),
                    entry.ExpectedPreview.Category, StringComparison.Ordinal)
                || !JToken.DeepEquals(crafted, entry.ExpectedPreview.Output)
                || !JToken.DeepEquals(msg["acceptedPlan"], entry.ExpectedPreview.AcceptedPlan)
                || !IsOutputReceipt(msg["outputReceipt"],
                    msg["acceptedPlan"] as JObject, crafted)) return false;
            string itemKind = ReadExactString(crafted["itemKind"]);
            double value = crafted["value"].Value<double>();
            double quantity = crafted["quantity"].Value<double>();
            double enhancementLevel = crafted["enhancementLevel"].Value<double>();
            return itemKind == "equipment"
                ? craftCount == 1 && quantity == 1 && enhancementLevel == value
                : enhancementLevel == 0 && quantity == value && quantity >= craftCount;
        }

        private static bool IsProjectedItem(JObject item, bool withRequiredLevel)
        {
            if (item == null) return false;
            string[] keys = withRequiredLevel
                ? new[] { "name", "displayName", "icon", "itemKind", "value", "quantity",
                    "enhancementLevel", "majorType", "use", "actionType", "weaponType",
                    "setId", "setName", "setOrder", "requiredLevel" }
                : new[] { "name", "displayName", "icon", "itemKind", "value", "quantity",
                    "enhancementLevel", "majorType", "use", "actionType", "weaponType",
                    "setId", "setName", "setOrder" };
            int setOrder;
            if (!HasExactKeys(item, keys) || !IsIdentityTriple(item)
                || !IsItemKind(ReadExactString(item["itemKind"]))
                || !IsNonNegativeNumber(item["value"]) || !IsNonNegativeNumber(item["quantity"])
                || !IsNonNegativeNumber(item["enhancementLevel"])
                || !IsSafeOptionalText(ReadExactString(item["majorType"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["use"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["actionType"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["weaponType"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["setId"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["setName"]), 256)
                || !TryReadInteger(item["setOrder"], 0, 100000, out setOrder)
                || (withRequiredLevel && !IsNonNegativeNumber(item["requiredLevel"]))) return false;
            string kind = ReadExactString(item["itemKind"]);
            double value = item["value"].Value<double>();
            double quantity = item["quantity"].Value<double>();
            double enhancement = item["enhancementLevel"].Value<double>();
            if (value <= 0 || quantity <= 0
                || Math.Truncate(value) != value
                || Math.Truncate(quantity) != quantity
                || Math.Truncate(enhancement) != enhancement) return false;
            return kind == "equipment"
                ? quantity == 1 && enhancement == value
                : enhancement == 0 && quantity == value;
        }

        private static bool IsRequirement(JObject requirement)
        {
            return requirement != null
                && HasExactKeys(requirement, "name", "displayName", "icon", "itemKind", "required",
                    "owned", "maxEnhancement", "isQuantity", "tier", "consumed", "enough",
                    "storageKind")
                && IsIdentityTriple(requirement)
                && IsItemKind(ReadExactString(requirement["itemKind"]))
                && IsNonNegativeNumber(requirement["required"])
                && IsNonNegativeNumber(requirement["owned"])
                && IsNonNegativeNumber(requirement["maxEnhancement"])
                && IsSafeOptionalText(ReadExactString(requirement["tier"]), 128)
                && StorageKinds.Contains(ReadExactString(requirement["storageKind"]))
                && HasExactBooleanFields(requirement, "isQuantity", "consumed", "enough");
        }

        private static bool IsOutputDelivery(JObject delivery, JObject output)
        {
            int physicalSlot;
            if (delivery == null || output == null
                || !HasExactKeys(delivery, "available", "storageKind", "mode", "physicalSlot", "quantity")
                || delivery["available"] == null || delivery["available"].Type != JTokenType.Boolean
                || !StorageKinds.Contains(ReadExactString(delivery["storageKind"]))
                || !TryReadInteger(delivery["physicalSlot"], -1, 999, out physicalSlot)
                || !IsNonNegativeNumber(delivery["quantity"])
                || !JToken.DeepEquals(delivery["quantity"], output["quantity"])) return false;
            bool available = delivery.Value<bool>("available");
            string storageKind = ReadExactString(delivery["storageKind"]);
            string mode = ReadExactString(delivery["mode"]);
            string itemKind = ReadExactString(output["itemKind"]);
            if (!available) return storageKind == "unavailable" && mode == "none" && physicalSlot == -1;
            if (storageKind == "bag") return (mode == "insert"
                    || mode == "merge" && itemKind == "stack")
                && physicalSlot >= 0 && physicalSlot < 50;
            if (storageKind == "drug") return itemKind == "stack"
                && mode == "merge" && physicalSlot >= 0;
            if (storageKind == "material_collection" || storageKind == "information_collection")
                return itemKind == "stack" && mode == "increment" && physicalSlot == -1;
            return false;
        }

        private static bool IsAcceptedPlan(JObject plan, JObject preview)
        {
            int recipeIndex;
            int craftCount;
            return plan != null
                && HasExactKeys(plan, "category", "recipeIndex", "craftCount", "output",
                    "materials", "outputDelivery", "outputPrototype", "cost")
                && TryReadInteger(plan["recipeIndex"], 0, 999, out recipeIndex)
                && TryReadInteger(plan["craftCount"], 1, 99, out craftCount)
                && string.Equals(ReadExactString(plan["category"]),
                    ReadExactString(preview["category"]), StringComparison.Ordinal)
                && recipeIndex == preview.Value<int>("recipeIndex")
                && craftCount == preview.Value<int>("craftCount")
                && JToken.DeepEquals(plan["output"], preview["output"])
                && JToken.DeepEquals(plan["materials"], preview["materials"])
                && JToken.DeepEquals(plan["outputDelivery"], preview["outputDelivery"])
                && JToken.DeepEquals(plan["cost"], preview["cost"])
                && IsOutputPrototype(plan["outputPrototype"],
                    plan["output"] as JObject, plan["outputDelivery"] as JObject);
        }

        private static bool IsOutputPrototype(
            JToken token,
            JObject output,
            JObject delivery)
        {
            if (output == null || delivery == null) return false;
            string storageKind = ReadExactString(delivery["storageKind"]);
            bool physical = storageKind == "bag" || storageKind == "drug";
            if (!physical) return token != null && token.Type == JTokenType.Null
                && (storageKind == "material_collection"
                    || storageKind == "information_collection");
            var prototype = token as JObject;
            if (prototype == null || !HasExactKeys(prototype, "item", "confirmProjection")) return false;
            JObject item;
            JObject confirm;
            if (!InventoryTask.TrySanitizeItem(prototype["item"] as JObject, out item)
                || !InventoryTask.TrySanitizeStableConfirm(
                    prototype["confirmProjection"] as JObject, item, out confirm)
                || !JToken.DeepEquals(item, prototype["item"])
                || !JToken.DeepEquals(confirm, prototype["confirmProjection"])) return false;
            return string.Equals(ReadExactString(item["name"]),
                    ReadExactString(output["name"]), StringComparison.Ordinal)
                && string.Equals(ReadExactString(item["displayName"]),
                    ReadExactString(output["displayName"]), StringComparison.Ordinal)
                && string.Equals(ReadExactString(item["icon"]),
                    ReadExactString(output["icon"]), StringComparison.Ordinal)
                && string.Equals(ReadExactString(item["itemKind"]),
                    ReadExactString(output["itemKind"]), StringComparison.Ordinal)
                && JToken.DeepEquals(item["quantity"], output["quantity"])
                && JToken.DeepEquals(item["enhancementLevel"], output["enhancementLevel"])
                && JToken.DeepEquals(item["quantity"], delivery["quantity"]);
        }

        private static bool IsOutputReceipt(
            JToken token,
            JObject acceptedPlan,
            JObject crafted)
        {
            if (acceptedPlan == null || crafted == null) return false;
            var delivery = acceptedPlan["outputDelivery"] as JObject;
            string storageKind = delivery != null
                ? ReadExactString(delivery["storageKind"]) : null;
            bool physical = storageKind == "bag" || storageKind == "drug";
            if (!physical) return token != null && token.Type == JTokenType.Null
                && (storageKind == "material_collection"
                    || storageKind == "information_collection");
            var receipt = token as JObject;
            var prototype = acceptedPlan["outputPrototype"] as JObject;
            if (receipt == null || prototype == null
                || !HasExactKeys(receipt, "item", "confirmProjection")) return false;
            JObject item;
            JObject confirm;
            if (!InventoryTask.TrySanitizeItem(receipt["item"] as JObject, out item)
                || !InventoryTask.TrySanitizeConfirm(
                    receipt["confirmProjection"] as JObject, item, out confirm)
                || !JToken.DeepEquals(item, receipt["item"])
                || !JToken.DeepEquals(confirm, receipt["confirmProjection"])) return false;
            var prototypeItem = prototype["item"] as JObject;
            var prototypeConfirm = prototype["confirmProjection"] as JObject;
            if (prototypeItem == null || prototypeConfirm == null) return false;
            long outputQuantity;
            long receiptQuantity;
            if (!TryReadLongInteger(crafted["quantity"], 1, 9007199254740991L,
                    out outputQuantity)
                || !TryReadLongInteger(item["quantity"], 1, 9007199254740991L,
                    out receiptQuantity)
                || (ReadExactString(delivery["mode"]) == "insert"
                    ? receiptQuantity != outputQuantity
                    : receiptQuantity < outputQuantity)) return false;

            JObject normalizedItem = (JObject)item.DeepClone();
            normalizedItem["quantity"] = prototypeItem["quantity"].DeepClone();
            JObject normalizedConfirm = (JObject)confirm.DeepClone();
            normalizedConfirm.Remove("lastUpdate");
            normalizedConfirm["quantity"] = prototypeConfirm["quantity"].DeepClone();
            return JToken.DeepEquals(normalizedItem, prototypeItem)
                && JToken.DeepEquals(normalizedConfirm, prototypeConfirm);
        }

        private static bool IsIdentityTriple(JObject value)
        {
            return value != null
                && IsIdentityText(ReadExactString(value["name"]), 128)
                && IsIdentityText(ReadExactString(value["displayName"]), 256)
                && IsIdentityText(ReadExactString(value["icon"]), 256);
        }

        private static bool IsItemKind(string value)
        {
            return value == "equipment" || value == "stack";
        }

        private static bool IsBalance(JObject balance)
        {
            return balance != null && HasExactKeys(balance, "money", "kpoints")
                && IsNonNegativeNumber(balance["money"]) && IsNonNegativeNumber(balance["kpoints"]);
        }

        private static bool IsSkills(JObject skills)
        {
            return skills != null && HasExactKeys(skills, "reverseLevel", "smithEnabled", "smithLevel")
                && IsNonNegativeNumber(skills["reverseLevel"])
                && skills["smithEnabled"] != null && skills["smithEnabled"].Type == JTokenType.Boolean
                && IsNonNegativeNumber(skills["smithLevel"]);
        }

        private static bool IsCost(JObject cost)
        {
            return cost != null && HasExactKeys(cost, "money", "kpoints")
                && IsNonNegativeNumber(cost["money"]) && IsNonNegativeNumber(cost["kpoints"]);
        }

        private static bool HasExactBooleanFields(JObject value, params string[] fields)
        {
            foreach (string field in fields)
            {
                if (value[field] == null || value[field].Type != JTokenType.Boolean) return false;
            }
            return true;
        }

        private static bool MatchesSelector(JObject msg, PendingRequest entry, params string[] fields)
        {
            if (entry == null || entry.NormalizedPayload == null) return false;
            foreach (string field in fields)
            {
                if (!JToken.DeepEquals(msg[field], entry.NormalizedPayload[field])) return false;
            }
            return true;
        }

        private static bool HasExactResponseKeys(JObject value, params string[] bodyKeys)
        {
            var expected = new string[bodyKeys.Length + 3];
            expected[0] = "task";
            expected[1] = "callId";
            expected[2] = "success";
            Array.Copy(bodyKeys, 0, expected, 3, bodyKeys.Length);
            return HasExactKeys(value, expected);
        }

        private static bool HasExactKeys(JObject value, params string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            var names = new HashSet<string>(expected, StringComparer.Ordinal);
            if (names.Count != expected.Length) return false;
            foreach (JProperty property in value.Properties())
            {
                if (!names.Contains(property.Name)) return false;
            }
            return true;
        }

        private static string ReadExactString(JToken token)
        {
            return token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
        }

        private static bool HasProtocolVersion(JObject value)
        {
            return value != null && value["v"] != null && value["v"].Type == JTokenType.Integer
                && value.Value<int>("v") == 1;
        }

        private static bool IsNumber(JToken value)
        {
            if (value == null || (value.Type != JTokenType.Integer && value.Type != JTokenType.Float)) return false;
            double candidate = value.Value<double>();
            return !double.IsNaN(candidate) && !double.IsInfinity(candidate);
        }

        private static bool IsDefinitiveWriteResponse(JObject msg)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            // Caller invokes this only after TrySanitizeResponse accepted the
            // command-specific success shape and postcondition.
            if (msg.Value<bool>("success")) return true;
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
                if (entry.IsWrite) EnterNeedsReconcileLocked();
            }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                entry.OwnerPanel,
                entry.OwnerPanelInstanceId,
                reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                entry.IsWrite);
        }

        private void EnterNeedsReconcileLocked()
        {
            _writeState = "needs_reconcile";
            _reconcileEpoch++;
        }

        private void RejectAndRemember(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            if (!_pendingCalls.TryRememberRejected(callId)) return;
            RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, error, false);
        }

        private void RespondError(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId,
            string error, bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "crafting", ["cmd"] = cmd ?? "",
                ["panel"] = ownerPanel, ["panelInstanceId"] = ownerPanelInstanceId,
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
