using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public sealed partial class ItemUseTask
    {
        private static bool TrySanitizeChoiceSnapshot(JObject data, out JObject clean)
        {
            clean = null;
            bool modern = data?["kpoints"] != null;
            if (!(modern ? IsExactObject(data, "success", "storeId", "revision", "offers", "pendingOperationId", "kpoints")
                    : IsExactObject(data, "success", "storeId", "revision", "offers", "pendingOperationId"))
                || modern && !TryReadLongInteger(data["kpoints"], 0, MaxSafeInteger, out _)
                || !TryReadSafeText(data["storeId"], 128, true, out string storeId)
                || storeId.Length > 0 && !ValidToken.IsMatch(storeId)
                || !TryReadLongInteger(data["revision"], 0, MaxSafeInteger, out long revision)
                || !TryReadSafeText(data["pendingOperationId"], 128, true, out string pending)
                || pending.Length > 0 && !ValidToken.IsMatch(pending)
                || !(data["offers"] is JArray offers) || offers.Count > 16
                || storeId.Length == 0 && (revision != 0 || offers.Count != 0)) return false;
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in offers)
            {
                var offer = token as JObject;
                if (!IsExactObject(offer, "offerId", "title", "options")
                    || !StashEntryId(offer["offerId"], out string id) || !ids.Add(id)
                    || !id.StartsWith(storeId + ".choice.", StringComparison.Ordinal)
                    || !TryReadSafeText(offer["title"], 96, false, out string title)
                    || !(offer["options"] is JArray options) || options.Count < 2 || options.Count > 4) return false;
                var optionIds = new HashSet<string>(StringComparer.Ordinal);
                foreach (JToken optionToken in options)
                {
                    var option = optionToken as JObject;
                    if (!(modern ? IsExactObject(option, "optionId", "title", "description", "items", "skills", "kCost", "available")
                            : IsExactObject(option, "optionId", "title", "description", "items"))
                        || !TryReadSafeText(option["optionId"], 64, false, out string optionId)
                        || !ValidToken.IsMatch(optionId) || !optionIds.Add(optionId)
                        || !TryReadSafeText(option["title"], 64, false, out string optionTitle)
                        || !TryReadSafeText(option["description"], 256, false, out string description)
                        || !(option["items"] is JArray items) || items.Count > 16 || !modern && items.Count < 1) return false;
                    if (modern)
                    {
                        if (!TryReadInteger(option["kCost"], 0, 1200, out _) || option["available"]?.Type != JTokenType.Boolean
                            || !(option["skills"] is JArray skills) || skills.Count > 2 || skills.Count == 0 && items.Count == 0) return false;
                        var skillKeys = new HashSet<string>(StringComparer.Ordinal);
                        foreach (JToken grant in skills)
                        {
                            if (!IsExactObject(grant as JObject, "skillKey", "level", "currentLevel", "description")
                                || !TryReadSafeText(grant["skillKey"], 64, false, out string key) || !skillKeys.Add(key)
                                || !TryReadInteger(grant["level"], 1, 100, out _) || !TryReadInteger(grant["currentLevel"], 0, 100, out _)
                                || grant["description"]?.Type != JTokenType.String || grant.Value<string>("description").Length > 2048
                                || System.Linq.Enumerable.Any(grant.Value<string>("description"), ch => char.IsControl(ch) && ch != '\n' && ch != '\r' && ch != '\t')) return false;
                        }
                    }
                    foreach (JToken itemToken in items)
                    {
                        var item = itemToken as JObject;
                        bool preview = item?["icon"] != null || item?["details"] != null;
                        if (!(preview ? IsExactObject(item, "itemName", "displayName", "quantity", "level", "icon", "details")
                                : IsExactObject(item, "itemName", "displayName", "quantity", "level"))
                            || !TryReadSafeText(item["itemName"], 96, false, out string name)
                            || !TryReadSafeText(item["displayName"], 128, false, out string display)
                            || !TryReadLongInteger(item["quantity"], 1, MaxSafeInteger, out long quantity)
                            || !TryReadInteger(item["level"], 0, 60, out int level)) return false;
                        if (preview && (!TryReadSafeText(item["icon"], 96, false, out _)
                            || item["details"]?.Type != JTokenType.String || item.Value<string>("details").Length > 4096
                            || System.Linq.Enumerable.Any(item.Value<string>("details"), ch =>
                                char.IsControl(ch) && ch != '\n' && ch != '\r' && ch != '\t'))) return false;
                    }
                }
            }
            clean = (JObject)data.DeepClone();
            return true;
        }

        private static bool TrySanitizeChoiceResult(JObject data, string command, JObject request, out JObject clean)
        {
            clean = null;
            if (command == "stashOpen")
            {
                if (!IsExactObject(data, "success", "kind", "offerId", "consumed", "remaining")
                    || ReadString(data["kind"]) != "choiceOpen"
                    || !StashEntryId(data["offerId"], out string offerId)
                    || !TryReadInteger(data["consumed"], 1, 1, out int consumed)
                    || !TryReadLongInteger(data["remaining"], 0, MaxSafeInteger, out long remaining)) return false;
                string store = ReadString(request["storeId"]);
                if (store.Length > 0 && !offerId.StartsWith(store + ".choice.", StringComparison.Ordinal)) return false;
            }
            else
            {
                if (!IsExactObject(data, "success", "kind", "offerId", "optionId", "rewardReady")
                    || ReadString(data["kind"]) != "choiceSelect"
                    || ReadString(data["offerId"]) != ReadString(request["offerId"])
                    || ReadString(data["optionId"]) != ReadString(request["optionId"])
                    || data["rewardReady"]?.Type != JTokenType.Boolean || !data.Value<bool>("rewardReady")) return false;
            }
            clean = (JObject)data.DeepClone();
            return true;
        }
    }
}
