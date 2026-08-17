using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>Shared closed-schema validator for AS2-owned procurement projections.</summary>
    internal static class ProcurementProjectionValidator
    {
        private const long MaxSafeInteger = 9007199254740991L;

        internal static bool IsPlanSummary(JObject value)
        {
            long revision;
            return HasExactKeys(value, "revision", "directShopNavigation")
                && TryInteger(value["revision"], 0, MaxSafeInteger, out revision)
                && IsBoolean(value["directShopNavigation"]);
        }

        internal static bool IsOwnedSummary(JObject value)
        {
            if (!HasExactKeys(value, "bag", "drug", "equipped", "battleBox",
                    "material", "information", "usable", "total",
                    "usableMaxEnhancement", "totalMaxEnhancement")) return false;
            long bag, drug, equipped, battleBox, material, information;
            long usable, total, usableMax, totalMax;
            if (!TryInteger(value["bag"], 0, MaxSafeInteger, out bag)
                || !TryInteger(value["drug"], 0, MaxSafeInteger, out drug)
                || !TryInteger(value["equipped"], 0, MaxSafeInteger, out equipped)
                || !TryInteger(value["battleBox"], 0, MaxSafeInteger, out battleBox)
                || !TryInteger(value["material"], 0, MaxSafeInteger, out material)
                || !TryInteger(value["information"], 0, MaxSafeInteger, out information)
                || !TryInteger(value["usable"], 0, MaxSafeInteger, out usable)
                || !TryInteger(value["total"], 0, MaxSafeInteger, out total)
                || !TryInteger(value["usableMaxEnhancement"], 0, MaxSafeInteger, out usableMax)
                || !TryInteger(value["totalMaxEnhancement"], 0, MaxSafeInteger, out totalMax))
                return false;
            bool collection = material > 0 || information > 0;
            if (material > 0 && information > 0) return false;
            return collection
                ? bag == 0 && drug == 0 && equipped == 0 && battleBox == 0
                    && usable == material + information && total == usable
                    && usableMax == 0 && totalMax == 0
                : usable == bag + drug && total == usable + equipped + battleBox
                    && totalMax >= usableMax;
        }

        internal static bool IsDemand(JObject value, string expectedItemName)
        {
            if (!HasExactKeys(value, "itemName", "required", "requiredEnhancement",
                    "usableOwned", "equippedOwned", "battleBoxOwned", "totalOwned",
                    "usableMaxEnhancement", "equippedMaxEnhancement",
                    "battleBoxMaxEnhancement", "totalMaxEnhancement",
                    "obtainMissing", "relocateMissing",
                    "needsEnhancement", "craftRequired", "taskRequired",
                    "plannedRecipeCount", "activeTaskCount", "reasons", "sources")
                || !IsIdentity(value["itemName"], 128)
                || !string.Equals(value.Value<string>("itemName"), expectedItemName,
                    StringComparison.Ordinal)
                || !IsBoolean(value["needsEnhancement"])) return false;
            string[] integerFields = { "required", "requiredEnhancement", "usableOwned",
                "equippedOwned", "battleBoxOwned", "totalOwned",
                "usableMaxEnhancement", "equippedMaxEnhancement",
                "battleBoxMaxEnhancement", "totalMaxEnhancement",
                "obtainMissing", "relocateMissing", "craftRequired", "taskRequired",
                "plannedRecipeCount", "activeTaskCount" };
            var integers = new Dictionary<string, long>(StringComparer.Ordinal);
            foreach (string field in integerFields)
            {
                long number;
                if (!TryInteger(value[field], 0, MaxSafeInteger, out number)) return false;
                integers[field] = number;
            }
            if (integers["totalOwned"] != integers["usableOwned"]
                    + integers["equippedOwned"] + integers["battleBoxOwned"]
                || integers["totalMaxEnhancement"] < integers["usableMaxEnhancement"]
                || integers["totalMaxEnhancement"] < integers["equippedMaxEnhancement"]
                || integers["totalMaxEnhancement"] < integers["battleBoxMaxEnhancement"]
                || integers["equippedOwned"] == 0
                    && integers["equippedMaxEnhancement"] != 0
                || integers["battleBoxOwned"] == 0
                    && integers["battleBoxMaxEnhancement"] != 0
                || integers["obtainMissing"] > Math.Max(1, integers["required"])
                || integers["relocateMissing"] > Math.Max(1, integers["required"])
                || integers["relocateMissing"] > integers["equippedOwned"]
                    + integers["battleBoxOwned"]) return false;
            JArray reasons = value["reasons"] as JArray;
            JArray sources = value["sources"] as JArray;
            if (reasons == null || reasons.Count < 1 || reasons.Count > 64
                || sources == null || sources.Count > 32) return false;
            foreach (JToken token in reasons)
            {
                JObject reason = token as JObject;
                long required;
                string kind = reason != null ? reason.Value<string>("kind") : null;
                string mode = reason != null ? reason.Value<string>("mode") : null;
                if (!HasExactKeys(reason, "kind", "sourceId", "label", "required", "mode")
                    || (kind != "craft" && kind != "task")
                    || !IsIdentity(reason["sourceId"], 128)
                    || !IsIdentity(reason["label"], 256)
                    || !TryInteger(reason["required"], 1, MaxSafeInteger, out required)
                    || (mode != "consume" && mode != "retain"
                        && mode != "submit" && mode != "contain")) return false;
            }
            var sourceKeys = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in sources)
            {
                JObject source = token as JObject;
                string kind = source != null ? source.Value<string>("kind") : null;
                long index;
                string key;
                if (kind == "npcshop")
                {
                    if (!HasExactKeys(source, "kind", "shopId", "catalogIndex", "label")
                        || !IsIdentity(source["shopId"], 80)
                        || !TryInteger(source["catalogIndex"], 0, 10000, out index)
                        || !IsIdentity(source["label"], 256)) return false;
                    key = kind + "\u001f" + source.Value<string>("shopId") + "\u001f" + index;
                }
                else if (kind == "kshop")
                {
                    if (!HasExactKeys(source, "kind", "catalogIndex", "entryId",
                            "category", "label")
                        || !TryInteger(source["catalogIndex"], 0, 10000, out index)
                        || !IsIdentity(source["entryId"], 256)
                        || !IsSafeText(source["category"], 128, true)
                        || !IsIdentity(source["label"], 256)) return false;
                    key = kind + "\u001f" + index + "\u001f"
                        + source.Value<string>("entryId");
                }
                else return false;
                if (!sourceKeys.Add(key)) return false;
            }
            return true;
        }

        internal static bool IsPlanMutation(JObject value)
        {
            long revision, planned;
            return HasExactKeys(value, "success", "v", "revision", "recipeId", "plannedCrafts")
                && value.Value<bool?>("success") == true
                && value.Value<int?>("v") == 1
                && TryInteger(value["revision"], 1, MaxSafeInteger, out revision)
                && IsRecipeId(value["recipeId"])
                && TryInteger(value["plannedCrafts"], 0, 99, out planned);
        }

        internal static bool IsCommitState(JObject value)
        {
            long revision, planned;
            return HasExactKeys(value, "revision", "plannedCrafts", "changed")
                && TryInteger(value["revision"], 0, MaxSafeInteger, out revision)
                && TryInteger(value["plannedCrafts"], 0, 99, out planned)
                && IsBoolean(value["changed"]);
        }

        internal static bool IsRecipeId(JToken token)
        {
            string value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            if (string.IsNullOrEmpty(value) || value.Length > 96
                || !value.StartsWith("craft.", StringComparison.Ordinal)) return false;
            foreach (char ch in value)
                if (!(ch >= 'a' && ch <= 'z') && !(ch >= '0' && ch <= '9')
                    && ch != '-' && ch != '.') return false;
            return true;
        }

        private static bool IsIdentity(JToken token, int max)
        {
            if (!IsSafeText(token, max, false)) return false;
            string value = token.Value<string>();
            return !string.Equals(value.Trim(), "undefined",
                StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsSafeText(JToken token, int max, bool allowEmpty)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            if (value == null || value.Length > max || (!allowEmpty && value.Length == 0)) return false;
            foreach (char ch in value) if (char.IsControl(ch)) return false;
            return allowEmpty || !string.IsNullOrWhiteSpace(value);
        }

        private static bool IsBoolean(JToken token)
        {
            return token != null && token.Type == JTokenType.Boolean;
        }

        private static bool TryInteger(JToken token, long min, long max, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= min && value <= max;
        }

        private static bool HasExactKeys(JObject value, params string[] keys)
        {
            if (value == null || value.Count != keys.Length) return false;
            var expected = new HashSet<string>(keys, StringComparer.Ordinal);
            foreach (JProperty property in value.Properties())
                if (!expected.Contains(property.Name)) return false;
            return true;
        }
    }
}
