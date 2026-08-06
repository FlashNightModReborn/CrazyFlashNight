using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Fail-closed diagnostic projection for authority-bearing JSON envelopes.
    ///
    /// Logs are not a protocol surface: they retain only fixed routing metadata and
    /// deterministic references for one-time authority values.  Raw payloads, malformed
    /// envelopes, near-match families, and attacker-controlled sensitive field names never
    /// cross this boundary.
    /// </summary>
    internal static class AuthorityLogFormatter
    {
        private static readonly JsonLoadSettings StrictJsonSettings =
            new JsonLoadSettings
            {
                DuplicatePropertyNameHandling =
                    DuplicatePropertyNameHandling.Error
            };

        private static readonly HashSet<string> ExactResponseTasks =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "equipment_tuning_response",
                "loot_response",
                "shop_response",
                "crafting_response",
                "npcshop_response",
                "skill_response",
                "inventory_response",
                "loadout_response"
            };

        private static readonly string[] ResponseFamilyPrefixes =
        {
            "equipment_tuning_",
            "loot_",
            "shop_",
            "crafting_",
            "npcshop_",
            "skill_",
            "inventory_",
            "loadout_"
        };

        private static readonly HashSet<string> AuthorityPanels =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "workbench", "kshop", "crafting", "npcshop", "skills", "loot"
            };

        private static readonly HashSet<string> AuthorityDomains =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "inventory", "npcshop", "crafting", "equipment_tuning",
                "tuning", "loadout", "skills"
            };

        private static readonly HashSet<string> SafeOperations =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "close", "snapshot", "candidates", "preview", "commit", "tooltip", "detach",
                "bulkQuery", "saveCart", "checkoutPreview", "checkoutCommit",
                "checkout", "claim", "materials", "materialDetail",
                "batchPreview", "tradePreview", "buy", "batchSell", "tradeCommit",
                "discard", "move", "merge", "swap", "autoTransfer", "sortAndMerge",
                "learnPreview", "learnCommit", "equip", "unequip", "moveSlot",
                "setPassive", "reorder",
                "equipmentTuningSnapshot", "equipmentTuningPreview",
                "equipmentTuningCommit", "equipmentTuningTooltip",
                "equipmentTuningDetach",
                "shopBulkQuery", "shopTooltip", "shopSaveCart",
                "shopCheckoutPreview", "shopCheckoutCommit", "shopCheckout", "shopClaim",
                "craftingSnapshot", "craftingMaterials", "craftingMaterialDetail",
                "craftingPreview", "craftingTooltip", "craftingCommit",
                "npcShopSnapshot", "npcShopTooltip", "npcShopBatchPreview",
                "npcShopTradePreview", "npcShopBuy", "npcShopBatchSell",
                "npcShopTradeCommit",
                "inventorySnapshot", "inventoryTooltip", "inventoryDiscard",
                "inventoryMove", "inventoryMerge", "inventorySwap",
                "inventoryAutoTransfer", "inventorySortAndMerge",
                "skillSnapshot", "skillLearnPreview", "skillLearnCommit",
                "skillEquip", "skillUnequip", "skillMoveSlot", "skillSetPassive",
                "skillReorder"
            };

        private static readonly Dictionary<string, string> KnownSensitiveKeys =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["expectedTuningToken"] = "expectedTuningToken",
                ["tuningToken"] = "tuningToken",
                ["expectedCheckoutToken"] = "expectedCheckoutToken",
                ["checkoutToken"] = "checkoutToken",
                ["expectedPurchasedToken"] = "expectedPurchasedToken",
                ["purchasedToken"] = "purchasedToken",
                ["expectedCraftToken"] = "expectedCraftToken",
                ["craftToken"] = "craftToken",
                ["expectedBatchToken"] = "expectedBatchToken",
                ["batchToken"] = "batchToken",
                ["expectedTradeToken"] = "expectedTradeToken",
                ["tradeToken"] = "tradeToken",
                ["expectedLearnToken"] = "expectedLearnToken",
                ["learnToken"] = "learnToken",
                ["expectedLease"] = "expectedLease",
                ["slotLease"] = "slotLease",
                ["closeLease"] = "closeLease",
                ["transactionId"] = "transactionId"
            };

        private static readonly string[] KnownSensitiveKeyOrder =
        {
            "expectedTuningToken", "tuningToken", "expectedCheckoutToken",
            "checkoutToken", "expectedPurchasedToken", "purchasedToken",
            "expectedCraftToken", "craftToken", "expectedBatchToken", "batchToken",
            "expectedTradeToken", "tradeToken", "expectedLearnToken", "learnToken",
            "expectedLease", "slotLease", "closeLease", "transactionId"
        };

        private sealed class SensitiveEvidence
        {
            public int FieldCount;
            public int UnknownFieldCount;
            public readonly Dictionary<string, SortedSet<string>> KnownRefs =
                new Dictionary<string, SortedSet<string>>(StringComparer.Ordinal);
            public readonly HashSet<string> KnownPresent =
                new HashSet<string>(StringComparer.Ordinal);
            public readonly SortedSet<string> UnknownRefs =
                new SortedSet<string>(StringComparer.Ordinal);
        }

        internal static bool TryFormatPanelEnvelope(
            string cmdHint,
            string json,
            out string line)
        {
            line = null;
            JObject envelope;
            if (!TryParseStrict(json, out envelope))
            {
                line = "[Panel] HandlePanelMessage: envelope=malformed"
                    + " payload=redacted len=" + SafeLength(json);
                return true;
            }

            string cmd = ReadString(envelope["cmd"]) ?? cmdHint;
            if (string.Equals(cmd, "minigame_session", StringComparison.Ordinal))
            {
                line = "[Panel] HandlePanelMessage: cmd=minigame_session payload=redacted";
                return true;
            }

            SensitiveEvidence evidence = CollectSensitiveEvidence(envelope);
            string panel = ReadString(envelope["panel"]);
            string domain = ReadString(envelope["domain"]);
            bool exactAuthority = AuthorityPanels.Contains(panel ?? "")
                || AuthorityDomains.Contains(domain ?? "");
            bool nearMatch = IsAuthorityPanelNearMatch(panel)
                || IsAuthorityDomainNearMatch(domain);
            if (!exactAuthority && !nearMatch && evidence.FieldCount == 0)
                return false;

            var value = new StringBuilder();
            value.Append("[Panel] HandlePanelMessage: task=panel");
            value.Append(" panel=").Append(FormatAuthorityName(
                panel, AuthorityPanels, nearMatch));
            value.Append(" domain=").Append(FormatAuthorityName(
                domain, AuthorityDomains, nearMatch));
            value.Append(" cmd=").Append(FormatOperation(cmd));
            value.Append(" callId=").Append(FormatWebCallId(envelope["callId"]));
            if (nearMatch) value.Append(" envelope=near_match");
            value.Append(" payload=redacted len=").Append(SafeLength(json));
            AppendSensitiveEvidence(value, evidence);
            line = value.ToString();
            return true;
        }

        internal static string FormatFlashCommand(
            string component,
            JObject envelope)
        {
            string json = envelope != null
                ? envelope.ToString(Formatting.None)
                : "";
            SensitiveEvidence evidence = CollectSensitiveEvidence(envelope);
            var value = new StringBuilder();
            value.Append("[").Append(FormatComponent(component)).Append("] -> Flash:");
            value.Append(" task=").Append(
                string.Equals(ReadString(envelope != null ? envelope["task"] : null),
                    "cmd", StringComparison.Ordinal) ? "cmd" : "other");
            value.Append(" cmd=").Append(FormatOperation(
                ReadString(envelope != null ? envelope["action"] : null)));
            value.Append(" callId=").Append(FormatNumericCallId(
                envelope != null ? envelope["callId"] : null));
            value.Append(" payload=redacted len=").Append(json.Length);
            AppendSensitiveEvidence(value, evidence);
            return value.ToString();
        }

        /// <summary>
        /// Records the exact Host-side Web callId to Flash fid binding after the pending
        /// entry exists and before transport is attempted.  This is deliberately not a
        /// delivery receipt: a same-fid response or terminal event must close delivery.
        ///
        /// The formatter accepts no business payload or authority-bearing values.  Every
        /// emitted field is derived from a closed component contract or an ASCII identifier
        /// grammar; invalid input is projected as "other" instead of being echoed.
        /// </summary>
        internal static string FormatAuthorityFlashCallBound(
            string component,
            string webCallId,
            int flashCallId,
            string panel,
            string panelInstanceId,
            string cmd,
            string action,
            string viewSessionId = null)
        {
            string expectedAction = ResolveExpectedDispatchAction(component, cmd);
            string safeCmd = expectedAction != null
                && SafeOperations.Contains(cmd ?? "")
                    ? cmd
                    : "other";
            string safeAction = expectedAction != null
                && string.Equals(action, expectedAction, StringComparison.Ordinal)
                && SafeOperations.Contains(action ?? "")
                    ? action
                    : "other";

            var value = new StringBuilder();
            value.Append("event=authority_flash_call_bound");
            value.Append(" domain=").Append(FormatDispatchDomain(component));
            value.Append(" webCallId=").Append(FormatDispatchCallId(webCallId));
            value.Append(" flashCallId=").Append(flashCallId > 0
                ? flashCallId.ToString(System.Globalization.CultureInfo.InvariantCulture)
                : "other");
            value.Append(" panel=").Append(FormatDispatchPanel(component, panel));
            value.Append(" panelInstanceId=").Append(
                FormatDispatchOpaqueId(panelInstanceId));
            value.Append(" cmd=").Append(safeCmd);
            value.Append(" action=").Append(safeAction);
            if (string.Equals(component, "EquipmentTuningTask", StringComparison.Ordinal))
            {
                value.Append(" viewSessionId=").Append(
                    FormatDispatchOpaqueId(viewSessionId));
            }
            return value.ToString();
        }

        /// <summary>
        /// Records that the Host completed an exact owner close for the named panel
        /// instance.  The caller must emit this only after the active name and instance
        /// match and the close operation has completed successfully.
        /// </summary>
        internal static string FormatPanelExactCloseCompleted(
            string panel,
            string panelInstanceId)
        {
            var value = new StringBuilder();
            value.Append("event=panel_exact_close_completed");
            value.Append(" panel=").Append(
                AuthorityPanels.Contains(panel ?? "") ? panel : "other");
            value.Append(" panelInstanceId=").Append(
                FormatDispatchOpaqueId(panelInstanceId));
            return value.ToString();
        }

        internal static bool TryFormatTransportEnvelope(
            string message,
            out string line)
        {
            line = null;
            JObject envelope;
            if (!TryParseStrict(message, out envelope))
            {
                line = FormatMalformedTransportEnvelope(message);
                return true;
            }

            string task = ReadString(envelope["task"]);
            bool exactTask = ExactResponseTasks.Contains(task ?? "");
            bool nearTask = IsResponseFamilyNearMatch(task);
            JObject callbackPayload = envelope["payload"] as JObject;
            string callbackPanel = ReadString(callbackPayload != null
                ? callbackPayload["panel"] : null)
                ?? ReadString(envelope["panel"]);
            bool lootPanelRequest = string.Equals(task, "panel_request",
                    StringComparison.Ordinal)
                && string.Equals(callbackPanel, "loot", StringComparison.Ordinal);
            SensitiveEvidence evidence = CollectSensitiveEvidence(envelope);
            if (!exactTask && !nearTask && !lootPanelRequest
                && evidence.FieldCount == 0)
            {
                return false;
            }

            // Preserve the established compact tuning/loot transport diagnostics while moving
            // their fail-closed classification into this shared boundary.
            if (string.Equals(task, "equipment_tuning_response", StringComparison.Ordinal))
            {
                var summary = new StringBuilder();
                summary.Append("[XmlSocket:JSON] task=equipment_tuning_response command=")
                    .Append(FormatOperation(ReadString(envelope["command"])))
                    .Append(" callId=")
                    .Append(FormatNumericCallId(envelope["callId"]))
                    .Append(" success=").Append(FormatSuccess(envelope["success"]))
                    .Append(" payload=redacted len=").Append(SafeLength(message));
                AppendSensitiveEvidence(summary, evidence);
                line = summary.ToString();
                return true;
            }
            if (string.Equals(task, "loot_response", StringComparison.Ordinal))
            {
                line = "[XmlSocket:JSON] task=loot_response payload=redacted len="
                    + SafeLength(message);
                return true;
            }
            if (lootPanelRequest)
            {
                line = "[XmlSocket:JSON] task=panel_request panel=loot"
                    + " payload=redacted len=" + SafeLength(message);
                return true;
            }
            if (nearTask)
            {
                string family = task != null
                    && task.StartsWith("equipment_tuning_",
                        StringComparison.OrdinalIgnoreCase)
                        ? "equipment_tuning_response_family"
                        : "authority_response_family";
                line = "[XmlSocket:JSON] task=" + family
                    + " envelope=near_match payload=redacted len="
                    + SafeLength(message);
                return true;
            }

            var value = new StringBuilder();
            value.Append("[XmlSocket:JSON] task=").Append(
                exactTask ? task : "other");
            value.Append(" cmd=").Append(FormatOperation(
                ReadString(envelope["command"])
                    ?? ReadString(envelope["operation"])
                    ?? ReadString(envelope["action"])));
            value.Append(" callId=").Append(FormatNumericCallId(envelope["callId"]));
            value.Append(" success=").Append(FormatSuccess(envelope["success"]));
            value.Append(" payload=redacted len=").Append(SafeLength(message));
            AppendSensitiveEvidence(value, evidence);
            line = value.ToString();
            return true;
        }

        internal static string FormatOperation(string operation)
        {
            return operation != null && SafeOperations.Contains(operation)
                ? operation
                : "other";
        }

        private static string FormatDispatchDomain(string component)
        {
            switch (component)
            {
                case "EquipmentTuningTask": return "equipment_tuning";
                case "ShopTask": return "shop";
                case "CraftingTask": return "crafting";
                case "NpcShopTask": return "npcshop";
                case "InventoryTask": return "inventory";
                case "SkillTask": return "skills";
                default: return "other";
            }
        }

        private static string FormatDispatchPanel(string component, string panel)
        {
            switch (component)
            {
                case "EquipmentTuningTask":
                    return string.Equals(panel, "workbench", StringComparison.Ordinal)
                        ? panel : "other";
                case "ShopTask":
                    return string.Equals(panel, "kshop", StringComparison.Ordinal)
                        ? panel : "other";
                case "CraftingTask":
                    return string.Equals(panel, "crafting", StringComparison.Ordinal)
                        ? panel : "other";
                case "NpcShopTask":
                    return string.Equals(panel, "npcshop", StringComparison.Ordinal)
                        ? panel : "other";
                case "SkillTask":
                    return string.Equals(panel, "skills", StringComparison.Ordinal)
                        ? panel : "other";
                case "InventoryTask":
                    switch (panel)
                    {
                        case "workbench":
                        case "kshop":
                        case "npcshop":
                        case "crafting":
                        case "loot":
                            return panel;
                        default:
                            return "other";
                    }
                default:
                    return "other";
            }
        }

        private static string ResolveExpectedDispatchAction(
            string component,
            string cmd)
        {
            switch (component)
            {
                case "EquipmentTuningTask":
                    switch (cmd)
                    {
                        case "snapshot": return "equipmentTuningSnapshot";
                        case "preview": return "equipmentTuningPreview";
                        case "commit": return "equipmentTuningCommit";
                        case "tooltip": return "equipmentTuningTooltip";
                        case "detach": return "equipmentTuningDetach";
                        default: return null;
                    }
                case "ShopTask":
                    switch (cmd)
                    {
                        case "bulkQuery": return "shopBulkQuery";
                        case "tooltip": return "shopTooltip";
                        case "saveCart": return "shopSaveCart";
                        case "checkoutPreview": return "shopCheckoutPreview";
                        case "checkoutCommit": return "shopCheckoutCommit";
                        case "checkout": return "shopCheckout";
                        case "claim": return "shopClaim";
                        default: return null;
                    }
                case "CraftingTask":
                    switch (cmd)
                    {
                        case "snapshot": return "craftingSnapshot";
                        case "materials": return "craftingMaterials";
                        case "materialDetail": return "craftingMaterialDetail";
                        case "preview": return "craftingPreview";
                        case "tooltip": return "craftingTooltip";
                        case "commit": return "craftingCommit";
                        default: return null;
                    }
                case "NpcShopTask":
                    switch (cmd)
                    {
                        case "snapshot": return "npcShopSnapshot";
                        case "tooltip": return "npcShopTooltip";
                        case "batchPreview": return "npcShopBatchPreview";
                        case "tradePreview": return "npcShopTradePreview";
                        case "buy": return "npcShopBuy";
                        case "batchSell": return "npcShopBatchSell";
                        case "tradeCommit": return "npcShopTradeCommit";
                        default: return null;
                    }
                case "InventoryTask":
                    switch (cmd)
                    {
                        case "snapshot": return "inventorySnapshot";
                        case "tooltip": return "inventoryTooltip";
                        case "discard": return "inventoryDiscard";
                        case "move": return "inventoryMove";
                        case "merge": return "inventoryMerge";
                        case "swap": return "inventorySwap";
                        case "autoTransfer": return "inventoryAutoTransfer";
                        case "sortAndMerge": return "inventorySortAndMerge";
                        default: return null;
                    }
                case "SkillTask":
                    switch (cmd)
                    {
                        case "snapshot": return "skillSnapshot";
                        case "learnPreview": return "skillLearnPreview";
                        case "learnCommit": return "skillLearnCommit";
                        case "equip": return "skillEquip";
                        case "unequip": return "skillUnequip";
                        case "moveSlot": return "skillMoveSlot";
                        case "setPassive": return "skillSetPassive";
                        case "reorder": return "skillReorder";
                        default: return null;
                    }
                default:
                    return null;
            }
        }

        private static string FormatDispatchCallId(string value)
        {
            return IsSafeDispatchIdentifier(value, 96, false) ? value : "other";
        }

        private static string FormatDispatchOpaqueId(string value)
        {
            return IsSafeDispatchIdentifier(value, 160, true) ? value : "other";
        }

        private static bool IsSafeDispatchIdentifier(
            string value,
            int maxLength,
            bool allowTilde)
        {
            if (string.IsNullOrEmpty(value) || value.Length > maxLength) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool asciiLetter = (c >= 'A' && c <= 'Z')
                    || (c >= 'a' && c <= 'z');
                bool asciiDigit = c >= '0' && c <= '9';
                if (!asciiLetter && !asciiDigit && c != '.' && c != '_'
                    && c != '-' && (!allowTilde || c != '~'))
                    return false;
            }
            return true;
        }

        internal static string CreateReference(string authorityValue)
        {
            if (string.IsNullOrEmpty(authorityValue)) return null;
            using (SHA256 sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(
                    Encoding.UTF8.GetBytes(authorityValue));
                var value = new StringBuilder(31);
                value.Append("sha256_");
                for (int i = 0; i < 12; i++)
                    value.Append(digest[i].ToString("x2",
                        System.Globalization.CultureInfo.InvariantCulture));
                return value.ToString();
            }
        }

        private static string FormatMalformedTransportEnvelope(string message)
        {
            if (ContainsLexicalJsonValue(message, "task", "equipment_tuning_"))
            {
                return "[XmlSocket:JSON] task=equipment_tuning_response_family"
                    + " envelope=malformed payload=redacted len=" + SafeLength(message);
            }
            if (ContainsLexicalJsonValue(message, "task", "loot_response"))
            {
                return "[XmlSocket:JSON] task=loot_response payload=redacted len="
                    + SafeLength(message);
            }
            if (ContainsLexicalJsonValue(message, "task", "panel_request")
                && ContainsLexicalJsonValue(message, "panel", "loot"))
            {
                return "[XmlSocket:JSON] task=panel_request panel=loot"
                    + " payload=redacted len=" + SafeLength(message);
            }
            return "[XmlSocket:JSON] envelope=malformed payload=redacted len="
                + SafeLength(message);
        }

        private static bool TryParseStrict(string json, out JObject envelope)
        {
            envelope = null;
            if (string.IsNullOrEmpty(json)) return false;
            try
            {
                envelope = JObject.Parse(json, StrictJsonSettings);
                return envelope != null;
            }
            catch
            {
                return false;
            }
        }

        private static SensitiveEvidence CollectSensitiveEvidence(JToken root)
        {
            var evidence = new SensitiveEvidence();
            CollectSensitiveEvidence(root, evidence);
            return evidence;
        }

        private static void CollectSensitiveEvidence(
            JToken token,
            SensitiveEvidence evidence)
        {
            JObject obj = token as JObject;
            if (obj != null)
            {
                foreach (JProperty property in obj.Properties())
                {
                    string canonical;
                    if (IsSensitiveKey(property.Name, out canonical))
                    {
                        evidence.FieldCount++;
                        string reference = ReferenceToken(property.Value);
                        if (canonical != null)
                        {
                            evidence.KnownPresent.Add(canonical);
                            if (reference != null)
                            {
                                SortedSet<string> refs;
                                if (!evidence.KnownRefs.TryGetValue(canonical, out refs))
                                {
                                    refs = new SortedSet<string>(StringComparer.Ordinal);
                                    evidence.KnownRefs[canonical] = refs;
                                }
                                refs.Add(reference);
                            }
                        }
                        else
                        {
                            evidence.UnknownFieldCount++;
                            if (reference != null) evidence.UnknownRefs.Add(reference);
                        }
                        // Sensitive values are opaque. Do not recursively inspect their shape;
                        // the single deterministic reference already binds the whole value.
                        continue;
                    }
                    CollectSensitiveEvidence(property.Value, evidence);
                }
                return;
            }
            JArray array = token as JArray;
            if (array == null) return;
            foreach (JToken item in array)
                CollectSensitiveEvidence(item, evidence);
        }

        private static bool IsSensitiveKey(string key, out string canonical)
        {
            canonical = null;
            if (string.IsNullOrEmpty(key)) return false;
            if (KnownSensitiveKeys.TryGetValue(key, out canonical)) return true;
            return key.IndexOf("token", StringComparison.OrdinalIgnoreCase) >= 0
                || key.IndexOf("lease", StringComparison.OrdinalIgnoreCase) >= 0
                || key.IndexOf("transaction", StringComparison.OrdinalIgnoreCase) >= 0
                || key.IndexOf("secret", StringComparison.OrdinalIgnoreCase) >= 0
                || key.IndexOf("capability", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static string ReferenceToken(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return null;
            string value = token.Type == JTokenType.String
                ? token.Value<string>()
                : token.ToString(Formatting.None);
            return CreateReference(value);
        }

        private static void AppendSensitiveEvidence(
            StringBuilder value,
            SensitiveEvidence evidence)
        {
            if (evidence == null || evidence.FieldCount == 0) return;
            value.Append(" authorityFieldCount=").Append(evidence.FieldCount);
            foreach (string key in KnownSensitiveKeyOrder)
            {
                if (!evidence.KnownPresent.Contains(key)) continue;
                SortedSet<string> refs;
                if (!evidence.KnownRefs.TryGetValue(key, out refs)
                    || refs.Count == 0)
                {
                    value.Append(' ').Append(key).Append("Present=true");
                    continue;
                }
                value.Append(' ').Append(key)
                    .Append(refs.Count == 1 ? "Ref=" : "Refs=");
                AppendBoundedRefs(value, refs);
                if (refs.Count > 4)
                    value.Append(' ').Append(key).Append("RefCount=").Append(refs.Count);
            }
            if (evidence.UnknownFieldCount <= 0) return;
            value.Append(" unknownAuthorityFieldCount=")
                .Append(evidence.UnknownFieldCount);
            if (evidence.UnknownRefs.Count > 0)
            {
                value.Append(" unknownAuthorityRefs=");
                AppendBoundedRefs(value, evidence.UnknownRefs);
                if (evidence.UnknownRefs.Count > 4)
                    value.Append(" unknownAuthorityRefCount=")
                        .Append(evidence.UnknownRefs.Count);
            }
        }

        private static void AppendBoundedRefs(
            StringBuilder value,
            IEnumerable<string> refs)
        {
            int count = 0;
            foreach (string reference in refs)
            {
                if (count >= 4) break;
                if (count > 0) value.Append(',');
                value.Append(reference);
                count++;
            }
        }

        private static bool IsResponseFamilyNearMatch(string task)
        {
            if (string.IsNullOrEmpty(task) || ExactResponseTasks.Contains(task))
                return false;
            foreach (string prefix in ResponseFamilyPrefixes)
            {
                if (task.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        private static bool IsAuthorityPanelNearMatch(string panel)
        {
            return IsAuthorityNameNearMatch(panel, AuthorityPanels);
        }

        private static bool IsAuthorityDomainNearMatch(string domain)
        {
            return IsAuthorityNameNearMatch(domain, AuthorityDomains);
        }

        private static bool IsAuthorityNameNearMatch(
            string value,
            HashSet<string> exact)
        {
            if (string.IsNullOrEmpty(value) || exact.Contains(value)) return false;
            foreach (string candidate in exact)
            {
                if (value.StartsWith(candidate, StringComparison.OrdinalIgnoreCase)
                    || candidate.StartsWith(value, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        private static string FormatAuthorityName(
            string value,
            HashSet<string> exact,
            bool anyNearMatch)
        {
            if (value != null && exact.Contains(value)) return value;
            return anyNearMatch ? "authority_family" : "other";
        }

        private static string FormatNumericCallId(JToken token)
        {
            if (token == null || token.Type != JTokenType.Integer) return "other";
            try
            {
                long value = token.Value<long>();
                return value >= 0
                    ? value.ToString(System.Globalization.CultureInfo.InvariantCulture)
                    : "other";
            }
            catch
            {
                return "other";
            }
        }

        private static string FormatWebCallId(JToken token)
        {
            string value = ReadString(token);
            if (string.IsNullOrEmpty(value) || value.Length > 96) return "other";
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                if (!(char.IsLetterOrDigit(c) || c == '.' || c == '_' || c == ':' || c == '-'))
                    return "other";
            }
            return value;
        }

        private static string FormatSuccess(JToken token)
        {
            return token != null && token.Type == JTokenType.Boolean
                ? (token.Value<bool>() ? "true" : "false")
                : "unknown";
        }

        private static string FormatComponent(string component)
        {
            switch (component)
            {
                case "ShopTask":
                case "CraftingTask":
                case "NpcShopTask":
                case "InventoryTask":
                case "SkillTask":
                case "EquipmentTuningTask":
                    return component;
                default:
                    return "AuthorityTask";
            }
        }

        private static string ReadString(JToken token)
        {
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>()
                : null;
        }

        /// <summary>
        /// Produces a diagnostic-only JSON projection for legacy consumers that still need
        /// non-sensitive envelope fields (for example EquipmentTuning's requestCallId-to-fid
        /// evidence). Every authority-looking property is replaced in place by a deterministic
        /// reference or a presence bit; unknown sensitive property names are not copied.
        /// </summary>
        internal static JObject SanitizeAuthorityEnvelope(JObject envelope)
        {
            return SanitizeAuthorityToken(envelope) as JObject ?? new JObject();
        }

        internal static bool TryFormatEquipmentTuningDebug(
            string json,
            out string line)
        {
            line = null;
            JObject envelope;
            if (!TryParseStrict(json, out envelope))
            {
                if (ContainsLexicalJsonValue(
                        json, "scope", "equipment_tuning"))
                {
                    line = "[WebDebug] scope=equipment_tuning"
                        + " envelope=malformed payload=redacted len="
                        + SafeLength(json);
                    return true;
                }
                return false;
            }

            string scope = ReadString(envelope["scope"]);
            bool exact = string.Equals(
                scope, "equipment_tuning", StringComparison.Ordinal);
            bool near = !exact && scope != null
                && scope.StartsWith(
                    "equipment_tuning", StringComparison.OrdinalIgnoreCase);
            SensitiveEvidence evidence = CollectSensitiveEvidence(envelope);
            if (!exact && !near && evidence.FieldCount == 0) return false;

            var value = new StringBuilder();
            value.Append("[WebDebug] scope=")
                .Append(exact ? "equipment_tuning" : "authority_family");
            value.Append(" event=").Append(FormatEquipmentDebugEvent(
                ReadString(envelope["event"])));
            value.Append(" cmd=").Append(FormatOperation(
                ReadString(envelope["cmd"])));
            value.Append(" callId=").Append(FormatWebCallId(
                envelope["webCallId"]));
            AppendStringReference(value, "sourceKey",
                ReadString(envelope["sourceKey"]));
            AppendStringReference(value, "intentKey",
                ReadString(envelope["intentKey"]));
            AppendBooleanIfPresent(value, "tokenPresent",
                envelope["tokenPresent"]);
            AppendBooleanIfPresent(value, "transactionIdPresent",
                envelope["transactionIdPresent"]);
            AppendBooleanIfPresent(value, "requiresReconcile",
                envelope["requiresReconcile"]);
            if (near) value.Append(" envelope=near_match");
            value.Append(" payload=redacted len=").Append(SafeLength(json));
            AppendSensitiveEvidence(value, evidence);
            line = value.ToString();
            return true;
        }

        private static JToken SanitizeAuthorityToken(JToken token)
        {
            JObject obj = token as JObject;
            if (obj != null)
            {
                var result = new JObject();
                int unknownSensitive = 0;
                var unknownRefs = new SortedSet<string>(StringComparer.Ordinal);
                foreach (JProperty property in obj.Properties())
                {
                    string canonical;
                    if (IsSensitiveKey(property.Name, out canonical))
                    {
                        string reference = ReferenceToken(property.Value);
                        if (canonical == null)
                        {
                            unknownSensitive++;
                            if (reference != null) unknownRefs.Add(reference);
                        }
                        else if (reference != null)
                        {
                            result[canonical + "Ref"] = reference;
                        }
                        else
                        {
                            result[canonical + "Present"] = true;
                        }
                        continue;
                    }
                    result[property.Name] = SanitizeAuthorityToken(property.Value);
                }
                if (unknownSensitive > 0)
                {
                    result["unknownAuthorityFieldCount"] = unknownSensitive;
                    if (unknownRefs.Count > 0)
                    {
                        var refs = new JArray();
                        int count = 0;
                        foreach (string reference in unknownRefs)
                        {
                            if (count >= 4) break;
                            refs.Add(reference);
                            count++;
                        }
                        result["unknownAuthorityRefs"] = refs;
                        if (unknownRefs.Count > 4)
                            result["unknownAuthorityRefCount"] = unknownRefs.Count;
                    }
                }
                return result;
            }
            JArray array = token as JArray;
            if (array != null)
            {
                var result = new JArray();
                foreach (JToken item in array)
                    result.Add(SanitizeAuthorityToken(item));
                return result;
            }
            return token != null ? token.DeepClone() : JValue.CreateNull();
        }

        private static string FormatEquipmentDebugEvent(string value)
        {
            switch (value)
            {
                case "candidate_hit":
                case "lock_denied":
                case "intrinsic_unavailable":
                case "preview_issued":
                case "response_tuple_mismatch":
                case "preview_adopted":
                case "commit_issued":
                case "commit_adopted":
                case "inventory_refresh_settled":
                case "reconcile_issued":
                case "reconcile_adopted":
                    return value;
                default:
                    return "other";
            }
        }

        private static void AppendStringReference(
            StringBuilder value,
            string label,
            string raw)
        {
            string reference = CreateReference(raw);
            if (reference != null)
                value.Append(' ').Append(label).Append("Ref=").Append(reference);
            else
                value.Append(' ').Append(label).Append("Present=false");
        }

        private static void AppendBooleanIfPresent(
            StringBuilder value,
            string label,
            JToken token)
        {
            if (token == null || token.Type != JTokenType.Boolean) return;
            value.Append(' ').Append(label).Append('=')
                .Append(token.Value<bool>() ? "true" : "false");
        }

        private static int SafeLength(string value)
        {
            return value != null ? value.Length : 0;
        }

        // Used only after strict JSON parsing failed. The returned line never includes the
        // matched value, so a false positive merely redacts more diagnostics.
        private static bool ContainsLexicalJsonValue(
            string json,
            string field,
            string valuePrefix)
        {
            if (string.IsNullOrEmpty(json)) return false;
            string key = "\"" + field + "\"";
            int from = 0;
            while (from < json.Length)
            {
                int at = json.IndexOf(key, from, StringComparison.Ordinal);
                if (at < 0) return false;
                int cursor = at + key.Length;
                while (cursor < json.Length && char.IsWhiteSpace(json[cursor])) cursor++;
                if (cursor >= json.Length || json[cursor] != ':')
                {
                    from = at + key.Length;
                    continue;
                }
                cursor++;
                while (cursor < json.Length && char.IsWhiteSpace(json[cursor])) cursor++;
                if (cursor >= json.Length || json[cursor] != '"')
                {
                    from = at + key.Length;
                    continue;
                }
                cursor++;
                if (cursor + valuePrefix.Length <= json.Length
                    && string.Compare(json, cursor, valuePrefix, 0,
                        valuePrefix.Length, StringComparison.OrdinalIgnoreCase) == 0)
                {
                    return true;
                }
                from = at + key.Length;
            }
            return false;
        }
    }
}
