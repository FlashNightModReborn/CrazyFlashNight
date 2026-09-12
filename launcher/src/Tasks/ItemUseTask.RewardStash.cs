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
            JObject normalizedFilterSpec = null;
            JObject normalizedTarget = null;
            if (command == "stashPage")
            {
                keys.Add("offset");
                if (!TryReadInteger(payload["offset"], 0, int.MaxValue, out int offset)) return false;
                if (payload.Property("filterSpec") != null)
                {
                    keys.Add("filterSpec");
                    if (!(payload["filterSpec"] is JObject)
                        || !InventoryTask.TryNormalizeStandaloneFilterSpec(
                            payload["filterSpec"], out normalizedFilterSpec)
                        || normalizedFilterSpec == null) return false;
                }
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
                    if (payload.Property("target") != null)
                    {
                        keys.Add("target");
                        if (rows.Count != 1
                            || !InventoryTask.TryNormalizeBackpackTargetRef(
                                payload["target"] as JObject, out normalizedTarget)) return false;
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
            if (normalizedFilterSpec != null) normalized["filterSpec"] = normalizedFilterSpec;
            if (normalizedTarget != null) normalized["target"] = normalizedTarget;
            return true;
        }

        private static bool StashEntryId(JToken value, out string id)
        {
            return TryReadSafeText(value, 160, false, out id)
                && System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9._~-]+$");
        }

        /// <summary>
        /// stashTake 逐项结果的权威接收区域闭集：contract 固定五项，
        /// Host 不臆测全部进背包；带 target 时只许 背包。
        /// </summary>
        private static readonly HashSet<string> StashTakeDestinations =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "背包", "装备栏", "药剂栏", "材料", "情报"
            };

        /// <summary>stashTake blocked.reason 可枚举闭集；contract 固定四项，新增值须与 AS2 同步。</summary>
        private static readonly HashSet<string> StashTakeBlockedReasons =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "inventory_full", "target_stale", "target_occupied", "target_incompatible"
            };

        /// <summary>
        /// accepted/blocked 行的可选目标字段校验：destination 必须在闭集内且带 slot 或
        /// 请求 target 时只能为背包；slot 必须 0..49 并在请求带 target 时精确等于请求。
        /// </summary>
        private static bool TryReadStashTakePlacement(JObject row, JObject requestTarget)
        {
            bool hasDestination = row["destination"] != null;
            bool hasSlot = row["slot"] != null;
            if (!hasDestination && !hasSlot) return true;
            string destination = hasDestination ? ReadString(row["destination"]) : null;
            if (hasDestination
                && (destination == null
                    || !StashTakeDestinations.Contains(destination)
                    || (destination != "背包" && (requestTarget != null || hasSlot))))
            {
                return false;
            }
            if (hasSlot)
            {
                int slot;
                if (!TryReadInteger(row["slot"], 0, 49, out slot)
                    || (requestTarget != null && slot != requestTarget.Value<int>("slot")))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool HasOnlyKeys(JObject value, params string[] allowed)
        {
            if (value == null) return false;
            foreach (JProperty property in value.Properties())
            {
                bool found = false;
                for (int i = 0; i < allowed.Length; i++)
                {
                    if (string.Equals(property.Name, allowed[i], StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
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
                    || error == "malformed_legacy_equipment"
                    || error == "invalid_target" || error == "target_stale"
                    || error == "target_occupied" || error == "target_incompatible");
                sanitized = new JObject { ["success"] = false, ["error"] = error };
                return true;
            }
            if (!(message["data"] is JObject data) || data["success"]?.Type != JTokenType.Boolean
                || !data.Value<bool>("success")) return false;
            JObject clean;
            if (entry.WebCommand == "stashPage")
            {
                if (!TrySanitizeStashPage(data, entry.Request, out clean)) return false;
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
                JObject requestTarget = request["target"] as JObject;
                var ids = new HashSet<string>(StringComparer.Ordinal);
                foreach (JToken token in accepted)
                {
                    var row = token as JObject;
                    if (!HasOnlyKeys(row, "entryId", "quantity", "destination", "slot")
                        || row["entryId"] == null || row["quantity"] == null
                        || !StashEntryId(row["entryId"], out string id)
                        || !ids.Add(id) || !TryReadLongInteger(row["quantity"], 1, MaxSafeInteger, out long quantity)
                        || !requested.OfType<JObject>().Any(r => r.Value<string>("entryId") == id && r.Value<long>("quantity") == quantity)
                        || !TryReadStashTakePlacement(row, requestTarget)) return false;
                }
                foreach (JToken token in blocked)
                {
                    var row = token as JObject;
                    string reason = row != null ? ReadString(row["reason"]) : null;
                    if (!HasOnlyKeys(row, "entryId", "reason", "destination", "slot")
                        || row["entryId"] == null || reason == null
                        || !StashEntryId(row["entryId"], out string id)
                        || !ids.Add(id) || !StashTakeBlockedReasons.Contains(reason)
                        || !requested.OfType<JObject>().Any(r => r.Value<string>("entryId") == id)
                        || !TryReadStashTakePlacement(row, requestTarget)) return false;
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

        private static bool TrySanitizeStashPage(JObject data, JObject request, out JObject clean)
        {
            clean = null;
            bool filtered = request != null && request.Property("filterSpec") != null;
            JToken requestSpec = filtered ? request["filterSpec"] : null;
            if (!IsExactObject(data, filtered
                    ? new[] { "success", "storeId", "revision", "offset", "total", "entries",
                        "migrationRequired", "pendingOperationId", "filterSpec",
                        "filterFacets", "filterItemCount", "unfilteredTotal",
                        "setFacets", "setFilterItemCount" }
                    : new[] { "success", "storeId", "revision", "offset", "total", "entries",
                        "migrationRequired", "pendingOperationId" })
                || !TryReadSafeText(data["storeId"], 128, true, out string storeId)
                || storeId.Length > 0 && !ValidToken.IsMatch(storeId)
                || !TryReadLongInteger(data["revision"], 0, MaxSafeInteger, out long revision)
                || !TryReadInteger(data["offset"], 0, int.MaxValue, out int offset)
                || !TryReadInteger(data["total"], 0, int.MaxValue, out int total)
                || !(data["entries"] is JArray rows) || rows.Count != Math.Min(32, Math.Max(0, total - offset))
                || data["migrationRequired"]?.Type != JTokenType.Boolean
                || !TryReadSafeText(data["pendingOperationId"], 128, true, out string pendingId)) return false;
            // 未物化空暂存是纯读合法形状：storeId 为空且非迁移分支时，
            // 必须是 revision/total/entries/pendingId 全零的精确无库存页，
            // 空身份却携带非零库存或修订一律拒绝；不为纯读强制创建存档。
            if (storeId.Length == 0
                && !data.Value<bool>("migrationRequired")
                && (revision != 0 || total != 0 || rows.Count != 0 || pendingId.Length != 0))
            {
                return false;
            }
            JObject responseSpec = null;
            JArray facets = null;
            JArray setFacets = null;
            if (filtered)
            {
                int facetTotal;
                int setFacetTotal;
                if (!InventoryTask.TrySanitizeResponseFilterSpec(data["filterSpec"], out responseSpec)
                    || responseSpec == null || !JToken.DeepEquals(requestSpec, responseSpec)) return false;
                int unfilteredTotal;
                int filterItemCount;
                if (!TryReadInteger(data["unfilteredTotal"], 0, int.MaxValue, out unfilteredTotal)
                    || total > unfilteredTotal
                    || !TryReadInteger(data["filterItemCount"], 0, unfilteredTotal, out filterItemCount)
                    || filterItemCount != unfilteredTotal
                    || !InventoryTask.TrySanitizeFacets(
                        data["filterFacets"] as JArray, 0, false, unfilteredTotal,
                        out facets, out facetTotal)
                    || facetTotal != filterItemCount
                    || !TryReadInteger(data["setFilterItemCount"], 0, filterItemCount, out int setFilterItemCount)
                    || !InventoryTask.TrySanitizeFacets(
                        data["setFacets"] as JArray, 0, true, filterItemCount,
                        out setFacets, out setFacetTotal)
                    || setFacetTotal != setFilterItemCount) return false;
            }
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
            if (filtered)
            {
                clean["filterSpec"] = responseSpec;
                clean["filterFacets"] = facets;
                clean["setFacets"] = setFacets;
            }
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
