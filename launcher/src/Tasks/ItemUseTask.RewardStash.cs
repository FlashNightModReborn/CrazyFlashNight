using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public sealed partial class ItemUseTask
    {
        private static bool IsQueryCommand(string command) => command == "query" || command == "stashQuery";
        private static bool IsStashCommand(string command) => command == "stashPage" || command == "stashTooltip"
            || command == "stashTake" || command == "stashQuery" || command == "stashMigrate"
            || command == "stashOpen" || command == "stashOpenMany" || command == "stashResume";

        private static bool TryNormalizeStashPayload(string command, string binding, JObject payload,
            out JObject normalized, out string operationId, out string panelInstanceId, out long generation)
        {
            normalized = null; operationId = null; panelInstanceId = null; generation = 0;
            if (payload == null || !TryReadInteger(payload["v"], 2, 2, out int version)
                || !TryReadToken(payload["panelInstanceId"], out panelInstanceId)
                || panelInstanceId != binding
                || !TryReadLongInteger(payload["sessionGeneration"], 1, int.MaxValue, out generation)) return false;
            var keys = new List<string> { "v", "panelInstanceId", "sessionGeneration" };
            if (command == "stashPage")
            {
                keys.Add("offset");
                if (!TryReadInteger(payload["offset"], 0, int.MaxValue, out int offset)) return false;
            }
            else if (command == "stashTooltip")
            {
                keys.AddRange(new[] { "storeId", "entryId", "revision" });
                if (!TryReadToken(payload["storeId"], out string storeId)
                    || !StashEntryId(payload["entryId"], out string entryId)
                    || !TryReadLongInteger(payload["revision"], 1, MaxSafeInteger, out long revision)) return false;
            }
            else
            {
                keys.Add("operationId");
                if (!TryReadOperationId(payload["operationId"], out operationId)) return false;
                if (command != "stashResume")
                {
                    keys.Add("storeId"); keys.Add("expectedRevision");
                    if (!TryReadSafeText(payload["storeId"], 128, true, out string storeId)
                        || storeId.Length > 0 && !ValidToken.IsMatch(storeId)
                        || !TryReadLongInteger(payload["expectedRevision"], 0, MaxSafeInteger - 1, out long revision)) return false;
                }
                if (command == "stashTake")
                {
                    keys.Add("entries");
                    if (!(payload["entries"] is JArray rows) || rows.Count < 1 || rows.Count > 32) return false;
                    var ids = new HashSet<string>(StringComparer.Ordinal);
                    foreach (JToken token in rows)
                    {
                        var row = token as JObject;
                        if (!IsExactObject(row, "entryId", "revision", "quantity")
                            || !StashEntryId(row["entryId"], out string id) || !ids.Add(id)
                            || !TryReadLongInteger(row["revision"], 1, MaxSafeInteger, out long rowRevision)
                            || !TryReadLongInteger(row["quantity"], 1, MaxSafeInteger, out long quantity)) return false;
                    }
                }
                if (command == "stashOpen" || command == "stashOpenMany")
                {
                    keys.Add("source");
                    if (!TryNormalizeSource(payload["source"] as JObject, out JObject source)) return false;
                    if (command == "stashOpenMany")
                    {
                        keys.Add("count");
                        if (!TryReadInteger(payload["count"], 2, 64, out int count)) return false;
                    }
                }
            }
            if (!IsExactObject(payload, keys.ToArray())) return false;
            normalized = (JObject)payload.DeepClone();
            return true;
        }

        private static bool StashEntryId(JToken value, out string id)
        {
            return TryReadSafeText(value, 160, false, out id)
                && System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9._~-]+$");
        }

        private static bool TrySanitizeStashResponse(JObject message, PendingRequest entry,
            out JObject sanitized, out bool definitive, out bool reconciled)
        {
            sanitized = null; definitive = false; reconciled = false;
            bool hasOperation = entry.WebCommand != "stashPage" && entry.WebCommand != "stashTooltip";
            if (message == null || ReadString(message["task"]) != "item_use_response"
                || !TryReadInteger(message["v"], 2, 2, out int version)
                || ReadString(message["command"]) != entry.WebCommand
                || ReadString(message["panelInstanceId"]) != entry.PanelInstanceId
                || !TryReadLongInteger(message["sessionGeneration"], 1, int.MaxValue, out long generation)
                || generation != entry.SessionGeneration
                || hasOperation && ReadString(message["operationId"]) != entry.OperationId
                || message["success"]?.Type != JTokenType.Boolean) return false;
            bool success = message.Value<bool>("success");
            if (!HasExactResponseKeys(message, hasOperation, success ? "data" : "error")) return false;
            if (!success)
            {
                if (!TryReadSafeText(message["error"], 96, false, out string error)) return false;
                definitive = entry.IsWrite && (DefinitiveWriteErrors.Contains(error)
                    || error == "stale_stash" || error == "stale_entry" || error == "save_not_committed"
                    || error == "legacy_recovery_required" || error == "reward_lane_quarantined"
                    || error == "save_unavailable" || error == "stash_write_failed"
                    || error == "invalid_reward_stash" || error == "invalid_reward_snapshot"
                    || error == "reward_stash_quarantined" || error == "invalid_legacy_purchased"
                    || error == "malformed_legacy_equipment");
                sanitized = new JObject { ["success"] = false, ["error"] = error };
                return true;
            }
            if (!(message["data"] is JObject data) || data["success"]?.Type != JTokenType.Boolean
                || !data.Value<bool>("success")) return false;
            JObject clean;
            if (entry.WebCommand == "stashPage")
            {
                if (!TrySanitizeStashPage(data, out clean)) return false;
                if (clean.Value<int>("offset") != entry.Request.Value<int>("offset")) return false;
            }
            else if (entry.WebCommand == "stashTooltip")
            {
                if (!IsExactObject(data, "success", "tooltip") || !(data["tooltip"] is JObject info)
                    || !TooltipDocumentSanitizer.HasExactKeysAllowingOptionalDocument(
                        info, "itemName", "displayname", "iconName", "itemType", "descHTML", "introHTML")) return false;
                foreach (var field in info.Properties())
                {
                    if (field.Name == TooltipDocumentSanitizer.DocumentKey) continue;
                    if (field.Value.Type != JTokenType.String || field.Value.Value<string>().Length >
                        (field.Name == "descHTML" || field.Name == "introHTML" ? 32768 : 256)) return false;
                }
                clean = (JObject)data.DeepClone();
                var cleanInfo = (JObject)clean["tooltip"];
                cleanInfo.Remove(TooltipDocumentSanitizer.DocumentKey);
                TooltipDocumentSanitizer.ApplyTo(info["document"], cleanInfo);
            }
            else if (entry.WebCommand == "stashResume")
            {
                if (!IsExactObject(data, "success", "state") || ReadString(data["state"]) != "settled") return false;
                clean = (JObject)data.DeepClone();
            }
            else if (entry.WebCommand == "stashQuery")
            {
                string state = ReadString(data["state"]);
                bool committed = state == "committed";
                if (!IsExactObject(data, committed ? new[] { "success", "state", "result" } : new[] { "success", "state" })
                    || state != "committed" && state != "not_committed" && state != "stale") return false;
                clean = new JObject { ["success"] = true, ["state"] = state };
                if (committed)
                {
                    if (!TrySanitizeStashResult(data["result"] as JObject, entry.ReconcileWriteCommand,
                        entry.ReconcileRequest, out JObject receipt)) return false;
                    clean["result"] = receipt;
                }
                reconciled = true;
            }
            else
            {
                if (!TrySanitizeStashResult(data, entry.WebCommand, entry.Request, out clean)) return false;
                definitive = true;
            }
            sanitized = new JObject { ["success"] = true, ["data"] = clean };
            return true;
        }

        private static bool TrySanitizeStashResult(JObject data, string command, JObject request, out JObject clean)
        {
            clean = null;
            if (data == null || request == null || data["success"]?.Type != JTokenType.Boolean || !data.Value<bool>("success")) return false;
            if (command == "stashMigrate")
            {
                if (!IsExactObject(data, "success", "migrated") || data["migrated"]?.Type != JTokenType.Boolean) return false;
            }
            else if (command == "stashTake")
            {
                if (!IsExactObject(data, "success", "accepted", "blocked")
                    || !(data["accepted"] is JArray accepted) || !(data["blocked"] is JArray blocked)
                    || !(request["entries"] is JArray requested) || accepted.Count + blocked.Count != requested.Count) return false;
                var ids = new HashSet<string>(StringComparer.Ordinal);
                foreach (JToken token in accepted)
                {
                    var row = token as JObject;
                    if (!IsExactObject(row, "entryId", "quantity") || !StashEntryId(row["entryId"], out string id)
                        || !ids.Add(id) || !TryReadLongInteger(row["quantity"], 1, MaxSafeInteger, out long quantity)
                        || !requested.OfType<JObject>().Any(r => r.Value<string>("entryId") == id && r.Value<long>("quantity") == quantity)) return false;
                }
                foreach (JToken token in blocked)
                {
                    var row = token as JObject;
                    if (!IsExactObject(row, "entryId", "reason") || !StashEntryId(row["entryId"], out string id)
                        || !ids.Add(id) || ReadString(row["reason"]) != "inventory_full"
                        || !requested.OfType<JObject>().Any(r => r.Value<string>("entryId") == id)) return false;
                }
            }
            else if (command == "stashOpen" || command == "stashOpenMany")
            {
                int count = command == "stashOpen" ? 1 : request.Value<int>("count");
                if (!IsExactObject(data, "success", "kind", "consumed", "requestedCount", "remaining", "packages", "rewardReady")
                    || ReadString(data["kind"]) != (count == 1 ? "open" : "openMany")
                    || !TryReadInteger(data["consumed"], count, count, out int consumed)
                    || !TryReadInteger(data["requestedCount"], count, count, out int requestedCount)
                    || !TryReadLongInteger(data["remaining"], 0, MaxSafeInteger, out long remaining)
                    || data["rewardReady"]?.Type != JTokenType.Boolean
                    || !(data["packages"] is JArray packages) || packages.Count != count) return false;
                for (int i = 0; i < count; i++)
                {
                    var row = packages[i] as JObject;
                    if (!IsExactObject(row, "ordinal", "batchId", "entryCount")
                        || !TryReadInteger(row["ordinal"], i, i, out int ordinal)
                        || ReadString(row["batchId"]) != request.Value<string>("operationId") + ".p" + i
                        || !TryReadInteger(row["entryCount"], 0, 64, out int entries)) return false;
                }
            }
            else return false;
            clean = (JObject)data.DeepClone();
            return true;
        }

        private static bool TrySanitizeStashPage(JObject data, out JObject clean)
        {
            clean = null;
            if (!IsExactObject(data, "success", "storeId", "revision", "offset", "total", "entries", "migrationRequired", "pendingOperationId")
                || !TryReadSafeText(data["storeId"], 128, true, out string storeId)
                || storeId.Length > 0 && !ValidToken.IsMatch(storeId)
                || !TryReadLongInteger(data["revision"], 0, MaxSafeInteger, out long revision)
                || !TryReadInteger(data["offset"], 0, int.MaxValue, out int offset)
                || !TryReadInteger(data["total"], 0, int.MaxValue, out int total)
                || !(data["entries"] is JArray rows) || rows.Count != Math.Min(32, Math.Max(0, total - offset))
                || data["migrationRequired"]?.Type != JTokenType.Boolean
                || storeId.Length == 0 && !data.Value<bool>("migrationRequired")
                || !TryReadSafeText(data["pendingOperationId"], 128, true, out string pendingId)) return false;
            var projected = new JArray();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in rows)
            {
                var row = token as JObject;
                if (!IsExactObject(row, "entryId", "revision", "quantity", "item")
                    || !StashEntryId(row["entryId"], out string id) || !ids.Add(id)
                    || !TryReadLongInteger(row["revision"], 1, MaxSafeInteger, out long entryRevision)
                    || !TryReadLongInteger(row["quantity"], 1, MaxSafeInteger, out long quantity)
                    || !InventoryTask.TrySanitizeItem(row["item"] as JObject, out JObject item)
                    || item.Value<long>("quantity") != quantity) return false;
                projected.Add(new JObject { ["entryId"] = id, ["revision"] = entryRevision, ["quantity"] = quantity, ["item"] = item });
            }
            clean = (JObject)data.DeepClone(); clean["entries"] = projected;
            return true;
        }

        private static bool TrySanitizeStashSummary(JObject value, out JObject sanitized)
        {
            sanitized = null;
            if (!IsExactObject(value, "v", "storeId", "batchCount", "remainingCount", "capacity", "authorityRevision",
                "recoverableRootOperationId", "recoverableRootStatus", "recoveryRequired")
                || !TryReadToken(value["storeId"], out string storeId)
                || !TryReadInteger(value["remainingCount"], 0, int.MaxValue, out int count)
                || !TryReadInteger(value["batchCount"], count == 0 ? 0 : 1, count == 0 ? 0 : 1, out int batches)
                || !TryReadInteger(value["capacity"], 0, 0, out int capacity)
                || !TryReadLongInteger(value["authorityRevision"], 0, MaxSafeInteger, out long revision)
                || !TryReadSafeText(value["recoverableRootOperationId"], 128, true, out string rootId)
                || !TryReadSafeText(value["recoverableRootStatus"], 32, false, out string status)
                || !IsRewardRootStatus(status) || string.IsNullOrEmpty(rootId) != (status == "not_started")
                || value["recoveryRequired"]?.Type != JTokenType.Boolean
                || value.Value<bool>("recoveryRequired") && string.IsNullOrEmpty(rootId)) return false;
            sanitized = (JObject)value.DeepClone();
            return true;
        }
    }
}
