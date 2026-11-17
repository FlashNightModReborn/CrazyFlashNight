using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Pure, domain-specific validation for character-build mutations.
    ///
    /// This deliberately does not own pending calls, timers, panel bindings or reconciliation
    /// state. CharacterBuildTask owns those transport concerns; this leaf only reconstructs the
    /// four frozen Web requests and proves the complete AS2 mutation/reconcile projections.
    /// </summary>
    internal static class CharacterBuildProtocol
    {
        internal const int BackpackSlotCount = 50;
        internal const int DrugBankCount = 2;
        internal const int DrugLaneCount = 4;
        internal const int DrugPhysicalSlotCount = 8;
        private const double MaxSafeProjectionNumber = 9007199254740991d;

        private static readonly Regex ValidLease = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private static readonly string[] EquipmentSlots = {
            "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
            "长枪", "手枪", "手枪2", "刀", "手雷"
        };

        private static readonly string[] EquipmentLabels = {
            "头部", "上装", "下装", "手部", "脚部", "颈部",
            "长枪", "主手手枪", "副手手枪", "刀", "手雷"
        };

        private static readonly HashSet<string> EquipmentSlotSet =
            Set(EquipmentSlots);

        private static readonly HashSet<string> ItemKeys = Set(
            "name", "displayName", "icon", "majorType", "use", "actionType",
            "weaponType", "setId", "setName", "setOrder", "itemKind",
            "quantity", "enhancementLevel", "maxEnhancementLevel",
            "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed",
            "modSlotCapacity", "modSlotUsed", "modSlots", "modMeta", "rarity");

        private static readonly HashSet<string> ModKeys = Set(
            "name", "displayName", "icon", "grade", "gradeLabel", "gradeColor",
            "role", "roleLabel", "symbol", "scope");

        private static readonly HashSet<string> FullBackpackKeys = Set(
            "containerId", "capacity", "accessibleCapacity", "viewCapacity",
            "filterKey", "pageSizeHint", "locked", "snapshotSeq",
            "containerEpoch", "containerVersion", "offset", "limit", "slots",
            "filterFacets", "filterItemCount", "setFacets", "setFilterItemCount");

        internal static bool IsMutationCommand(string command)
        {
            return command == "equipEquipment"
                || command == "unequipEquipment"
                || command == "equipDrug"
                || command == "unequipDrug"
                || command == "configureEmergencyInjection";
        }

        internal static bool IsEquipmentSlotKey(string slotKey)
        {
            return EquipmentSlotSet.Contains(slotKey);
        }

        internal static bool IsCandidateCompatible(
            string targetKind,
            string targetSlotKey,
            string itemKind,
            string use,
            string majorType,
            double quantity)
        {
            if (targetKind == "drug")
            {
                return itemKind == "stack"
                    && use == "药剂"
                    && quantity > 0;
            }
            return IsEquipmentSlotCompatible(
                targetSlotKey,
                itemKind,
                use,
                majorType,
                quantity);
        }

        internal static string[] CompatibleEquipmentSlotKeys(
            string itemKind,
            string use,
            string majorType,
            double quantity)
        {
            var result = new List<string>();
            foreach (string slotKey in EquipmentSlots)
            {
                if (IsEquipmentSlotCompatible(
                        slotKey, itemKind, use, majorType, quantity))
                    result.Add(slotKey);
            }
            return result.ToArray();
        }

        internal static bool TryResolveMutationAction(
            string command,
            out string action)
        {
            switch (command)
            {
                case "equipEquipment":
                    action = "characterBuildEquipEquipment";
                    return true;
                case "unequipEquipment":
                    action = "characterBuildUnequipEquipment";
                    return true;
                case "equipDrug":
                    action = "characterBuildEquipDrug";
                    return true;
                case "unequipDrug":
                    action = "characterBuildUnequipDrug";
                    return true;
                case "configureEmergencyInjection":
                    action = "characterBuildConfigureEmergencyInjection";
                    return true;
                default:
                    action = null;
                    return false;
            }
        }

        internal static bool IsEmergencyInjectionChestName(string name)
        {
            return name == "统合61式胸甲" || name == "钛合金61式胸甲";
        }

        private static bool TryNormalizeChestTarget(
            JObject target,
            out JObject normalized)
        {
            normalized = null;
            string kind = ReadString(target != null ? target["kind"] : null);
            if (kind == "loadout")
            {
                long expectedLoadoutRevision;
                if (!IsExactObject(
                        target,
                        Set("kind", "slotKey", "expectedLoadoutRevision"))
                    || ReadString(target["slotKey"]) != "上装装备"
                    || !TryReadInteger(
                        target["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedLoadoutRevision))
                {
                    return false;
                }
                normalized = new JObject
                {
                    ["kind"] = "loadout",
                    ["slotKey"] = "上装装备",
                    ["expectedLoadoutRevision"] = expectedLoadoutRevision
                };
                return true;
            }
            if (kind == "backpack")
            {
                if (!IsExactObject(
                        target,
                        Set("kind", "containerId", "slot", "expectedLease")))
                {
                    return false;
                }
                JObject sourceKeys = new JObject
                {
                    ["containerId"] = target["containerId"],
                    ["slot"] = target["slot"],
                    ["expectedLease"] = target["expectedLease"]
                };
                JObject normalizedSource;
                if (!TryNormalizeBackpackSource(sourceKeys, out normalizedSource))
                {
                    return false;
                }
                normalized = normalizedSource;
                normalized["kind"] = "backpack";
                return true;
            }
            return false;
        }

        internal static bool TryNormalizeMutationPayload(
            string command,
            JObject payload,
            out JObject normalized,
            out long sessionGeneration,
            out string error)
        {
            normalized = null;
            sessionGeneration = 0;
            error = null;
            if (!IsMutationCommand(command)
                || payload == null
                || !HasVersion(payload)
                || !TryReadInteger(
                    payload["sessionGeneration"],
                    1,
                    int.MaxValue,
                    out sessionGeneration))
            {
                error = "invalid_payload";
                return false;
            }

            var result = new JObject
            {
                ["v"] = 1,
                ["sessionGeneration"] = sessionGeneration
            };

            if (command == "configureEmergencyInjection")
            {
                long expectedRevision;
                int slot;
                JObject normalizedChestTarget;
                if (!IsExactObject(payload, Set("v", "sessionGeneration", "expectedDrugRevision",
                        "chestTarget", "enabled", "drugSlot", "expectedItemName"))
                    || payload["enabled"].Type != JTokenType.Boolean
                    || !TryReadInteger(payload["expectedDrugRevision"], 0, int.MaxValue, out expectedRevision)
                    || !TryNormalizeChestTarget(payload["chestTarget"] as JObject, out normalizedChestTarget)
                    || !TryReadInteger(payload["drugSlot"], -1, 7, out slot)
                    || !IsBoundedText(payload["expectedItemName"], 160, true))
                {
                    error = "invalid_payload";
                    return false;
                }
                bool enabled = payload.Value<bool>("enabled");
                string itemName = payload.Value<string>("expectedItemName");
                if (enabled ? slot < 0 || string.IsNullOrWhiteSpace(itemName)
                    : slot != -1 || itemName != "")
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedDrugRevision"] = expectedRevision;
                result["chestTarget"] = normalizedChestTarget;
                result["enabled"] = enabled;
                result["drugSlot"] = slot;
                result["expectedItemName"] = itemName;
            }
            else if (command == "equipEquipment"
                || command == "unequipEquipment")
            {
                bool equip = command == "equipEquipment";
                HashSet<string> expected = equip
                    ? Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "slotKey", "source")
                    : Set("v", "sessionGeneration", "expectedLoadoutRevision",
                        "slotKey");
                long expectedRevision;
                string slotKey = ReadString(payload["slotKey"]);
                if (!IsExactObject(payload, expected)
                    || !TryReadInteger(
                        payload["expectedLoadoutRevision"],
                        0,
                        int.MaxValue,
                        out expectedRevision)
                    || !EquipmentSlotSet.Contains(slotKey))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedLoadoutRevision"] = expectedRevision;
                result["slotKey"] = slotKey;
                if (equip)
                {
                    JObject source;
                    if (!TryNormalizeBackpackSource(
                        payload["source"] as JObject, out source))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["source"] = source;
                }
            }
            else
            {
                bool equip = command == "equipDrug";
                HashSet<string> expected = equip
                    ? Set("v", "sessionGeneration", "expectedDrugRevision",
                        "drugSlot", "source")
                    : Set("v", "sessionGeneration", "expectedDrugRevision",
                        "drugSlot");
                long expectedRevision;
                int drugSlot;
                if (!IsExactObject(payload, expected)
                    || !TryReadInteger(
                        payload["expectedDrugRevision"],
                        0,
                        int.MaxValue,
                        out expectedRevision)
                    || !TryReadInteger(
                        payload["drugSlot"],
                        0,
                        DrugPhysicalSlotCount - 1,
                        out drugSlot))
                {
                    error = "invalid_payload";
                    return false;
                }
                result["expectedDrugRevision"] = expectedRevision;
                result["drugSlot"] = drugSlot;
                if (equip)
                {
                    JObject source;
                    if (!TryNormalizeBackpackSource(
                        payload["source"] as JObject, out source))
                    {
                        error = "invalid_payload";
                        return false;
                    }
                    result["source"] = source;
                }
            }

            normalized = result;
            return true;
        }

        internal static bool TryValidateMutationSuccess(
            JObject message,
            string command,
            JObject normalizedRequest,
            out bool changed,
            out int affectedBackpackSlot)
        {
            changed = false;
            affectedBackpackSlot = -1;
            if (!IsMutationCommand(command)
                || message == null
                || normalizedRequest == null
                || message["changed"] == null
                || message["changed"].Type != JTokenType.Boolean
                || ReadString(message["operation"]) != command
                || !TryReadInteger(
                    message["affectedBackpackSlot"],
                    command == "configureEmergencyInjection" ? -1 : 0,
                    BackpackSlotCount - 1,
                    out affectedBackpackSlot)
                || !IsLoadoutProjection(message["payload"] as JObject, true)
                || !IsFullBackpackSnapshots(
                    message["inventorySnapshots"] as JArray))
            {
                return false;
            }

            changed = message.Value<bool>("changed");
            if (command == "configureEmergencyInjection")
            {
                JObject chestTarget = normalizedRequest["chestTarget"] as JObject;
                string targetKind = ReadString(chestTarget != null ? chestTarget["kind"] : null);
                int expectedAffectedSlot = targetKind == "backpack"
                    ? chestTarget.Value<int>("slot") : -1;
                if (affectedBackpackSlot != expectedAffectedSlot) return false;

                JObject projection = (JObject)message["payload"];
                JObject targetConfiguration = projection["targetEmergencyInjection"] as JObject;
                bool enabled = normalizedRequest.Value<bool>("enabled");
                int slot = normalizedRequest.Value<int>("drugSlot");
                string itemName = normalizedRequest.Value<string>("expectedItemName");
                if (!IsEmergencyInjectionProjection(targetConfiguration)
                    || targetConfiguration.Value<bool>("enabled") != enabled
                    || targetConfiguration.Value<int>("physicalSlot") != slot
                    || targetConfiguration.Value<string>("itemKey") != itemName
                    || targetConfiguration.Value<string>("status") != (enabled ? "authorized" : "disabled"))
                {
                    return false;
                }
                if (targetKind == "loadout")
                {
                    JObject wornConfiguration = projection["emergencyInjection"] as JObject;
                    JObject wornChestRow = FindEquipmentRow(projection, "上装装备");
                    JObject wornItemEmergency = wornChestRow != null && wornChestRow.Value<bool>("occupied")
                        ? wornChestRow["item"]["emergencyInjection"] as JObject : null;
                    if (!IsEmergencyInjectionProjection(wornConfiguration)
                        || wornItemEmergency == null
                        || !JToken.DeepEquals(wornConfiguration, targetConfiguration)
                        || !JToken.DeepEquals(wornItemEmergency, targetConfiguration))
                    {
                        return false;
                    }
                }
                else if (targetKind == "backpack")
                {
                    JObject targetBackpack = (JObject)message["inventorySnapshots"][0];
                    JObject targetRow = (JObject)targetBackpack["slots"][affectedBackpackSlot];
                    if (!targetRow.Value<bool>("occupied")
                        || !IsEmergencyInjectionChestName(ReadString(targetRow["item"]["name"])))
                    {
                        return false;
                    }
                }
                else
                {
                    return false;
                }
                return !enabled || (projection["drugs"][slot].Value<bool>("occupied")
                    && projection["drugs"][slot]["item"].Value<string>("name") == itemName);
            }
            JObject source = normalizedRequest["source"] as JObject;
            if ((command == "equipEquipment" || command == "equipDrug")
                && (source == null
                    || source.Value<int>("slot") != affectedBackpackSlot))
            {
                return false;
            }

            JObject payload = (JObject)message["payload"];
            JObject backpack = (JObject)message["inventorySnapshots"][0];
            JObject affectedRow =
                (JObject)backpack["slots"][affectedBackpackSlot];
            if (!changed) return true;

            if (command == "equipEquipment"
                || command == "unequipEquipment")
            {
                string slotKey = normalizedRequest.Value<string>("slotKey");
                JObject target = FindEquipmentRow(payload, slotKey);
                if (target == null
                    || target.Value<bool>("occupied")
                        != (command == "equipEquipment"))
                {
                    return false;
                }
                if (command == "unequipEquipment"
                    && !affectedRow.Value<bool>("occupied"))
                {
                    return false;
                }
            }
            else
            {
                int drugSlot = normalizedRequest.Value<int>("drugSlot");
                JObject target = (JObject)payload["drugs"][drugSlot];
                if (target.Value<bool>("occupied")
                    != (command == "equipDrug"))
                {
                    return false;
                }
                if (command == "unequipDrug"
                    && !affectedRow.Value<bool>("occupied"))
                {
                    return false;
                }
            }
            return true;
        }

        internal static bool IsMutationReconcileSnapshot(
            JObject message,
            string reconcileAfterCallId)
        {
            return message != null
                && !string.IsNullOrEmpty(reconcileAfterCallId)
                && ReadString(message["reconcileAfterCallId"])
                    == reconcileAfterCallId
                && IsLoadoutProjection(message["payload"] as JObject, false)
                && IsFullBackpackSnapshots(
                    message["inventorySnapshots"] as JArray);
        }

        internal static bool IsLoadoutProjection(
            JObject payload,
            bool requireHealthy)
        {
            bool hasCandidateFacets =
                payload != null && payload["candidateFacets"] != null;
            var expectedKeys = Set(
                "equipment", "drugs", "drugLayout", "portrait",
                "stateHealth", "diagnostics");
            if (hasCandidateFacets) expectedKeys.Add("candidateFacets");
            bool hasEmergencyInjection = payload != null && payload["emergencyInjection"] != null;
            if (hasEmergencyInjection) expectedKeys.Add("emergencyInjection");
            bool hasTargetEmergencyInjection = payload != null && payload["targetEmergencyInjection"] != null;
            if (hasTargetEmergencyInjection) expectedKeys.Add("targetEmergencyInjection");
            if (!IsExactObject(
                    payload, expectedKeys)
                || (hasEmergencyInjection && !IsEmergencyInjectionProjection(payload["emergencyInjection"] as JObject))
                || (hasTargetEmergencyInjection && !IsEmergencyInjectionProjection(payload["targetEmergencyInjection"] as JObject))
                || !(payload["equipment"] is JArray equipment)
                || equipment.Count != EquipmentSlots.Length
                || !(payload["drugs"] is JArray drugs)
                || drugs.Count != DrugPhysicalSlotCount
                || !TryValidateDrugLayout(
                    payload["drugLayout"] as JObject,
                    out int activeBank)
                || !IsPortrait(payload["portrait"] as JObject)
                || !IsDiagnostics(payload["diagnostics"] as JArray)
                || !IsStateHealth(payload["stateHealth"]))
            {
                return false;
            }

            JArray diagnostics = (JArray)payload["diagnostics"];
            bool healthy = ReadString(payload["stateHealth"]) == "ok";
            if (healthy != (diagnostics.Count == 0)
                || (requireHealthy && !healthy))
            {
                return false;
            }

            for (int i = 0; i < EquipmentSlots.Length; i++)
            {
                JObject row = equipment[i] as JObject;
                if (row == null
                    || ReadString(row["slotKey"]) != EquipmentSlots[i]
                    || ReadString(row["label"]) != EquipmentLabels[i]
                    || row["occupied"] == null
                    || row["occupied"].Type != JTokenType.Boolean)
                {
                    return false;
                }
                bool occupied = row.Value<bool>("occupied");
                if (!IsExactObject(
                    row,
                    occupied
                        ? Set("slotKey", "label", "occupied", "item")
                        : Set("slotKey", "label", "occupied")))
                {
                    return false;
                }
                if (!occupied) continue;

                string itemKind;
                string use;
                string majorType;
                double quantity;
                if (!TryValidateItemProjection(
                        row["item"] as JObject,
                        out itemKind,
                        out use,
                        out majorType,
                        out quantity)
                    || !IsEquipmentSlotCompatible(
                        EquipmentSlots[i],
                        itemKind,
                        use,
                        majorType,
                        quantity))
                {
                    return false;
                }
            }

            for (int slot = 0; slot < DrugPhysicalSlotCount; slot++)
            {
                JObject row = drugs[slot] as JObject;
                if (row == null
                    || !IsDrugRow(row, slot, activeBank))
                {
                    return false;
                }
            }
            for (int lane = 0; lane < DrugLaneCount; lane++)
            {
                if (!HaveSameDrugCooldown(
                    drugs[lane] as JObject,
                    drugs[lane + DrugLaneCount] as JObject))
                {
                    return false;
                }
            }
            if (hasEmergencyInjection)
            {
                JObject configuration = (JObject)payload["emergencyInjection"];
                if (!IsConsistentDrugEmergencyProjection(configuration, drugs)) return false;
                JObject chestRow = FindEquipmentRow(payload, "上装装备");
                bool chestOccupied = chestRow != null && chestRow.Value<bool>("occupied");
                JObject chestItem = chestOccupied ? chestRow["item"] as JObject : null;
                string chestName = chestItem != null ? ReadString(chestItem["name"]) : null;
                if (chestItem != null && IsEmergencyInjectionChestName(chestName))
                {
                    JObject chestEmergency = chestItem["emergencyInjection"] as JObject;
                    if (chestEmergency != null && !JToken.DeepEquals(configuration, chestEmergency))
                    {
                        return false;
                    }
                }
                else if (configuration.Value<bool>("enabled")
                    || ReadString(configuration["status"]) != "disabled")
                {
                    return false;
                }
            }
            if (hasTargetEmergencyInjection
                && !IsConsistentDrugEmergencyProjection(
                    payload["targetEmergencyInjection"] as JObject, drugs))
            {
                return false;
            }
            for (int i = 0; i < equipment.Count; i++)
            {
                JObject eqRow = equipment[i] as JObject;
                if (eqRow != null && eqRow.Value<bool>("occupied"))
                {
                    JObject eqEmergency = eqRow["item"]["emergencyInjection"] as JObject;
                    if (eqEmergency != null && !IsConsistentDrugEmergencyProjection(eqEmergency, drugs))
                    {
                        return false;
                    }
                }
            }
            return !hasCandidateFacets
                || IsCandidateFacetProjection(
                    payload["candidateFacets"] as JObject);
        }

        private static bool IsConsistentDrugEmergencyProjection(JObject configuration, JArray drugs)
        {
            if (configuration == null || !configuration.Value<bool>("enabled")) return true;
            JObject row = (JObject)drugs[configuration.Value<int>("physicalSlot")];
            bool occupied = row.Value<bool>("occupied");
            string itemKey = occupied ? row["item"].Value<string>("name") : null;
            string status = configuration.Value<string>("status");
            bool same = occupied && itemKey == configuration.Value<string>("itemKey");
            return status == "authorized" ? same : status == "empty" ? !occupied : occupied && !same;
        }

        /// <summary>
        /// Optional v1 facet projection. Older AS2 payloads omit it and remain readable; once
        /// present, the complete inventory facet tree is strict and self-consistent so Web can
        /// distinguish an authoritative zero from an unavailable/unknown count.
        /// </summary>
        internal static bool IsEmergencyInjectionProjection(JObject value)
        {
            int version, slot;
            if (!IsExactObject(value, Set("v", "enabled", "physicalSlot", "itemKey", "status"))
                || !TryReadInteger(value["v"], 1, 1, out version)
                || value["enabled"].Type != JTokenType.Boolean
                || !TryReadInteger(value["physicalSlot"], -1, 7, out slot)
                || !IsBoundedText(value["itemKey"], 160, true)) return false;
            string status = ReadString(value["status"]);
            bool enabled = value.Value<bool>("enabled");
            string item = value.Value<string>("itemKey");
            if (enabled) return slot >= 0 && !string.IsNullOrWhiteSpace(item)
                && (status == "authorized" || status == "empty" || status == "item_changed");
            return slot == -1 && item == ""
                && (status == "disabled" || status == "unsupported_config");
        }

        internal static bool IsCandidateFacetProjection(JObject projection)
        {
            int filterItemCount;
            int facetItemCount;
            return IsExactObject(
                    projection,
                    Set("scope", "filterFacets", "filterItemCount"))
                && ReadString(projection["scope"]) == "all"
                && TryReadInteger(
                    projection["filterItemCount"],
                    0,
                    BackpackSlotCount,
                    out filterItemCount)
                && IsFacetArray(
                    projection["filterFacets"] as JArray,
                    0,
                    false,
                    out facetItemCount)
                && facetItemCount == filterItemCount;
        }

        internal static bool TryValidateItemProjection(
            JObject item,
            out string itemKind,
            out string use,
            out string majorType,
            out double quantity)
        {
            itemKind = null;
            use = null;
            majorType = null;
            quantity = 0;
            if (item == null) return false;

            bool hasBalance = item["balanceSummary"] != null;
            bool hasAppearance = item["appearance"] != null;
            bool hasEmergencyInjection = item["emergencyInjection"] != null;
            var expectedKeys = new HashSet<string>(
                ItemKeys,
                StringComparer.Ordinal);
            if (hasBalance) expectedKeys.Add("balanceSummary");
            if (hasAppearance) expectedKeys.Add("appearance");
            if (hasEmergencyInjection) expectedKeys.Add("emergencyInjection");
            if (!IsExactObject(item, expectedKeys)
                || !IsIdentityText(item["name"], 256)
                || !IsIdentityText(item["displayName"], 256)
                || !IsIdentityText(item["icon"], 256))
            {
                return false;
            }

            string[] optionalTextKeys = {
                "majorType", "use", "actionType", "weaponType", "setId",
                "setName", "rarity"
            };
            foreach (string key in optionalTextKeys)
            {
                int limit = key == "use" ? 64 : 256;
                if (!IsBoundedText(item[key], limit, true)) return false;
            }

            itemKind = ReadString(item["itemKind"]);
            use = ReadString(item["use"]);
            majorType = ReadString(item["majorType"]);
            if ((itemKind != "equipment" && itemKind != "stack")
                || !TryReadFiniteNumber(
                    item["quantity"],
                    0,
                    MaxSafeProjectionNumber,
                    out quantity))
            {
                return false;
            }

            int setOrder;
            int enhancementLevel;
            int maxEnhancementLevel;
            int modSlotCapacity;
            int modSlotUsed;
            if (!TryReadInteger(item["setOrder"], 0, int.MaxValue, out setOrder)
                || !TryReadInteger(
                    item["enhancementLevel"],
                    0,
                    int.MaxValue,
                    out enhancementLevel)
                || !TryReadInteger(
                    item["maxEnhancementLevel"],
                    0,
                    int.MaxValue,
                    out maxEnhancementLevel)
                || !TryReadInteger(
                    item["modSlotCapacity"],
                    0,
                    int.MaxValue,
                    out modSlotCapacity)
                || !TryReadInteger(
                    item["modSlotUsed"],
                    0,
                    int.MaxValue,
                    out modSlotUsed))
            {
                return false;
            }

            string[] booleanKeys = {
                "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed"
            };
            foreach (string key in booleanKeys)
            {
                if (item[key] == null
                    || item[key].Type != JTokenType.Boolean)
                {
                    return false;
                }
            }

            JArray modSlots = item["modSlots"] as JArray;
            if (modSlots == null
                || modSlots.Count > 3
                || modSlots.Count > modSlotUsed)
            {
                return false;
            }
            foreach (JToken token in modSlots)
            {
                if (!IsModProjection(token as JObject)) return false;
            }

            JToken modMeta = item["modMeta"];
            if (modMeta == null
                || (modMeta.Type != JTokenType.Null
                    && !IsModProjection(modMeta as JObject)))
            {
                return false;
            }

            bool isMaxEnhancement = item.Value<bool>("isMaxEnhancement");
            bool tierSlotAvailable = item.Value<bool>("tierSlotAvailable");
            bool tierSlotUsed = item.Value<bool>("tierSlotUsed");
            if (tierSlotUsed && !tierSlotAvailable) return false;
            if (itemKind == "equipment")
            {
                if (quantity != 1
                    || isMaxEnhancement
                        != (enhancementLevel >= maxEnhancementLevel))
                {
                    return false;
                }
            }
            else if (quantity <= 0
                || enhancementLevel != 0
                || isMaxEnhancement
                || tierSlotAvailable
                || tierSlotUsed
                || modSlotCapacity != 0
                || modSlotUsed != 0
                || modSlots.Count != 0)
            {
                return false;
            }

            return (!hasBalance
                    || IsBalanceSummary(item["balanceSummary"] as JObject))
                && (!hasAppearance || (EquipmentSlotSet.Contains(use)
                    && IsEquipmentAppearance(item["appearance"] as JObject)))
                && (!hasEmergencyInjection
                    || (itemKind == "equipment"
                        && use == "上装装备"
                        && IsEmergencyInjectionChestName(ReadString(item["name"]))
                        && IsEmergencyInjectionProjection(item["emergencyInjection"] as JObject)));
        }

        private static bool IsEquipmentAppearance(JObject appearance)
        {
            if (!IsExactObject(appearance, Set(
                    "dressup", "dressup1", "dressup2", "dressup3", "helmet", "hairAbove")))
                return false;
            foreach (string key in new[] { "dressup", "dressup1", "dressup2", "dressup3" })
            {
                if (!IsBoundedText(appearance[key], 256, true)) return false;
            }
            return appearance["helmet"].Type == JTokenType.Boolean
                && appearance["hairAbove"].Type == JTokenType.Boolean;
        }

        internal static bool TryNormalizeBackpackSource(
            JObject source,
            out JObject normalized)
        {
            normalized = null;
            int slot;
            string lease = ReadString(source != null
                ? source["expectedLease"] : null);
            if (!IsExactObject(
                    source,
                    Set("containerId", "slot", "expectedLease"))
                || ReadString(source["containerId"]) != "背包"
                || !TryReadInteger(
                    source["slot"],
                    0,
                    BackpackSlotCount - 1,
                    out slot)
                || string.IsNullOrEmpty(lease)
                || !ValidLease.IsMatch(lease))
            {
                return false;
            }
            normalized = new JObject
            {
                ["containerId"] = "背包",
                ["slot"] = slot,
                ["expectedLease"] = lease
            };
            return true;
        }

        private static bool TryValidateDrugLayout(
            JObject layout,
            out int activeBank)
        {
            activeBank = -1;
            int version;
            int bankCount;
            int laneCount;
            int physicalSlotCount;
            return IsExactObject(
                    layout,
                    Set("v", "bankCount", "laneCount", "physicalSlotCount",
                        "activeBank", "switchKeyLabel", "switchCooldown"))
                && TryReadInteger(layout["v"], 2, 2, out version)
                && TryReadInteger(
                    layout["bankCount"],
                    DrugBankCount,
                    DrugBankCount,
                    out bankCount)
                && TryReadInteger(
                    layout["laneCount"],
                    DrugLaneCount,
                    DrugLaneCount,
                    out laneCount)
                && TryReadInteger(
                    layout["physicalSlotCount"],
                    DrugPhysicalSlotCount,
                    DrugPhysicalSlotCount,
                    out physicalSlotCount)
                && TryReadInteger(
                    layout["activeBank"],
                    0,
                    DrugBankCount - 1,
                    out activeBank)
                && IsBoundedText(layout["switchKeyLabel"], 64, true)
                && IsCooldownProjection(
                    layout["switchCooldown"] as JObject);
        }

        private static bool IsCooldownProjection(JObject value)
        {
            int totalSteps;
            int currentStep;
            int progressPercent;
            int animationFrame;
            double remainingMs;
            return IsExactObject(
                    value,
                    Set("ready", "totalSteps", "currentStep", "progressPercent",
                        "animationFrame", "remainingMs"))
                && value["ready"] != null
                && value["ready"].Type == JTokenType.Boolean
                && TryReadInteger(
                    value["totalSteps"], 0, int.MaxValue, out totalSteps)
                && TryReadInteger(
                    value["currentStep"], 0, int.MaxValue, out currentStep)
                && currentStep <= totalSteps
                && TryReadInteger(
                    value["progressPercent"], 0, 100, out progressPercent)
                && TryReadInteger(
                    value["animationFrame"], 0, int.MaxValue, out animationFrame)
                && TryReadFiniteNumber(
                    value["remainingMs"],
                    0,
                    MaxSafeProjectionNumber,
                    out remainingMs)
                && (!value.Value<bool>("ready") || remainingMs == 0);
        }

        private static bool IsDrugRow(
            JObject row,
            int expectedSlot,
            int activeBank)
        {
            int slot;
            int bank;
            int lane;
            int totalSteps;
            int currentStep;
            int progressPercent;
            int animationFrame;
            double remainingMs;
            double quantity;
            if (!TryReadInteger(
                    row["slot"], 0, DrugPhysicalSlotCount - 1, out slot)
                || slot != expectedSlot
                || !TryReadInteger(
                    row["bank"], 0, DrugBankCount - 1, out bank)
                || bank != expectedSlot / DrugLaneCount
                || !TryReadInteger(
                    row["lane"], 0, DrugLaneCount - 1, out lane)
                || lane != expectedSlot % DrugLaneCount
                || row["active"] == null
                || row["active"].Type != JTokenType.Boolean
                || row.Value<bool>("active") != (bank == activeBank)
                || !IsBoundedText(row["keyLabel"], 64, true)
                || row["ready"] == null
                || row["ready"].Type != JTokenType.Boolean
                || !TryReadInteger(
                    row["totalSteps"], 0, int.MaxValue, out totalSteps)
                || !TryReadInteger(
                    row["currentStep"], 0, int.MaxValue, out currentStep)
                || currentStep > totalSteps
                || !TryReadInteger(
                    row["progressPercent"], 0, 100, out progressPercent)
                || !TryReadInteger(
                    row["animationFrame"], 0, int.MaxValue, out animationFrame)
                || !TryReadFiniteNumber(
                    row["remainingMs"],
                    0,
                    MaxSafeProjectionNumber,
                    out remainingMs)
                || row["occupied"] == null
                || row["occupied"].Type != JTokenType.Boolean
                || !TryReadFiniteNumber(
                    row["quantity"],
                    0,
                    MaxSafeProjectionNumber,
                    out quantity))
            {
                return false;
            }

            bool occupied = row.Value<bool>("occupied");
            if (!IsExactObject(
                    row,
                    occupied
                        ? Set("slot", "bank", "lane", "active", "keyLabel",
                            "ready", "totalSteps",
                            "currentStep", "progressPercent", "animationFrame",
                            "remainingMs", "occupied", "quantity", "item")
                        : Set("slot", "bank", "lane", "active", "keyLabel",
                            "ready", "totalSteps",
                            "currentStep", "progressPercent", "animationFrame",
                            "remainingMs", "occupied", "quantity")))
            {
                return false;
            }
            if (row.Value<bool>("ready") && remainingMs != 0) return false;
            if (!occupied) return quantity == 0;

            string itemKind;
            string use;
            string majorType;
            double itemQuantity;
            return TryValidateItemProjection(
                    row["item"] as JObject,
                    out itemKind,
                    out use,
                    out majorType,
                    out itemQuantity)
                && itemKind == "stack"
                && use == "药剂"
                && itemQuantity == quantity;
        }

        private static bool HaveSameDrugCooldown(JObject left, JObject right)
        {
            return left != null
                && right != null
                && JToken.DeepEquals(left["ready"], right["ready"])
                && JToken.DeepEquals(left["totalSteps"], right["totalSteps"])
                && JToken.DeepEquals(left["currentStep"], right["currentStep"])
                && JToken.DeepEquals(
                    left["progressPercent"], right["progressPercent"])
                && JToken.DeepEquals(
                    left["animationFrame"], right["animationFrame"])
                && JToken.DeepEquals(left["remainingMs"], right["remainingMs"]);
        }

        private static bool IsEquipmentSlotCompatible(
            string slotKey,
            string itemKind,
            string use,
            string majorType,
            double quantity)
        {
            if (slotKey == "手雷")
            {
                return itemKind == "stack"
                    && use == "手雷"
                    && quantity > 0;
            }
            return itemKind == "equipment"
                && quantity == 1
                && (majorType == "武器" || majorType == "防具")
                && (use == slotKey
                    || (slotKey == "手枪2" && use == "手枪"));
        }

        private static JObject FindEquipmentRow(
            JObject payload,
            string slotKey)
        {
            if (payload == null || !(payload["equipment"] is JArray rows))
                return null;
            foreach (JToken token in rows)
            {
                JObject row = token as JObject;
                if (ReadString(row != null ? row["slotKey"] : null) == slotKey)
                    return row;
            }
            return null;
        }

        /// <summary>
        /// Canonical full-backpack mutation projection shared by loadout and inventory-owned
        /// equipment tuning writes. This is a pure shape check and does not touch task state.
        /// </summary>
        internal static bool IsFullBackpackSnapshots(JArray snapshots)
        {
            return snapshots != null
                && snapshots.Count == 1
                && IsFullBackpackSnapshot(snapshots[0] as JObject);
        }

        private static bool IsFullBackpackSnapshot(JObject snapshot)
        {
            int capacity;
            int accessibleCapacity;
            int viewCapacity;
            int pageSizeHint;
            int snapshotSeq;
            int containerEpoch;
            int containerVersion;
            int offset;
            int limit;
            int filterItemCount;
            int setFilterItemCount;
            if (!IsExactObject(snapshot, FullBackpackKeys)
                || ReadString(snapshot["containerId"]) != "背包"
                || !TryReadInteger(
                    snapshot["capacity"], 0, int.MaxValue, out capacity)
                || !TryReadInteger(
                    snapshot["accessibleCapacity"],
                    0,
                    int.MaxValue,
                    out accessibleCapacity)
                || !TryReadInteger(
                    snapshot["viewCapacity"],
                    0,
                    int.MaxValue,
                    out viewCapacity)
                || ReadString(snapshot["filterKey"]) != "all"
                || !TryReadInteger(
                    snapshot["pageSizeHint"],
                    1,
                    int.MaxValue,
                    out pageSizeHint)
                || snapshot["locked"] == null
                || snapshot["locked"].Type != JTokenType.Boolean
                || !TryReadInteger(
                    snapshot["snapshotSeq"],
                    1,
                    int.MaxValue,
                    out snapshotSeq)
                || !TryReadInteger(
                    snapshot["containerEpoch"],
                    1,
                    int.MaxValue,
                    out containerEpoch)
                || !TryReadInteger(
                    snapshot["containerVersion"],
                    0,
                    int.MaxValue,
                    out containerVersion)
                || !TryReadInteger(snapshot["offset"], 0, 0, out offset)
                || !TryReadInteger(
                    snapshot["limit"],
                    BackpackSlotCount,
                    BackpackSlotCount,
                    out limit)
                || !TryReadInteger(
                    snapshot["filterItemCount"],
                    0,
                    BackpackSlotCount,
                    out filterItemCount)
                || !TryReadInteger(
                    snapshot["setFilterItemCount"],
                    0,
                    BackpackSlotCount,
                    out setFilterItemCount)
                || capacity != BackpackSlotCount
                || accessibleCapacity != BackpackSlotCount
                || viewCapacity != BackpackSlotCount
                || pageSizeHint != BackpackSlotCount
                || snapshot.Value<bool>("locked")
                || setFilterItemCount > filterItemCount
                || !(snapshot["slots"] is JArray slots)
                || slots.Count != BackpackSlotCount)
            {
                return false;
            }

            int occupiedCount = 0;
            for (int slot = 0; slot < BackpackSlotCount; slot++)
            {
                JObject row = slots[slot] as JObject;
                if (!IsBackpackSlot(row, slot)) return false;
                if (row.Value<bool>("occupied")) occupiedCount++;
            }
            if (occupiedCount != filterItemCount) return false;

            int facetCount;
            int setFacetCount;
            return IsFacetArray(
                    snapshot["filterFacets"] as JArray,
                    0,
                    false,
                    out facetCount)
                && facetCount == filterItemCount
                && IsFacetArray(
                    snapshot["setFacets"] as JArray,
                    0,
                    true,
                    out setFacetCount)
                && setFacetCount == setFilterItemCount;
        }

        private static bool IsBackpackSlot(JObject row, int expectedSlot)
        {
            int physicalSlot;
            string lease = ReadString(row != null ? row["slotLease"] : null);
            if (row == null
                || !TryReadInteger(
                    row["physicalSlot"],
                    0,
                    BackpackSlotCount - 1,
                    out physicalSlot)
                || physicalSlot != expectedSlot
                || row["occupied"] == null
                || row["occupied"].Type != JTokenType.Boolean
                || string.IsNullOrEmpty(lease)
                || !ValidLease.IsMatch(lease))
            {
                return false;
            }

            bool occupied = row.Value<bool>("occupied");
            if (!IsExactObject(
                    row,
                    occupied
                        ? Set("physicalSlot", "occupied", "slotLease",
                            "item", "confirmProjection")
                        : Set("physicalSlot", "occupied", "slotLease")))
            {
                return false;
            }
            if (!occupied) return true;

            string itemKind;
            string use;
            string majorType;
            double quantity;
            return TryValidateItemProjection(
                    row["item"] as JObject,
                    out itemKind,
                    out use,
                    out majorType,
                    out quantity)
                && IsConfirmProjection(
                    row["confirmProjection"] as JObject,
                    (JObject)row["item"]);
        }

        private static bool IsConfirmProjection(
            JObject confirm,
            JObject item)
        {
            double quantity;
            int enhancementLevel;
            double lastUpdate;
            return IsExactObject(
                    confirm,
                    Set("itemKind", "name", "displayName", "quantity",
                        "enhancementLevel", "rarity", "tier",
                        "modSignature", "lastUpdate"))
                && ReadString(confirm["itemKind"])
                    == ReadString(item["itemKind"])
                && ReadString(confirm["name"]) == ReadString(item["name"])
                && ReadString(confirm["displayName"])
                    == ReadString(item["displayName"])
                && ReadString(confirm["rarity"]) == ReadString(item["rarity"])
                && IsBoundedText(confirm["tier"], 256, true)
                && IsBoundedText(confirm["modSignature"], 2048, true)
                && TryReadFiniteNumber(
                    confirm["quantity"],
                    0,
                    MaxSafeProjectionNumber,
                    out quantity)
                && quantity == item.Value<double>("quantity")
                && TryReadInteger(
                    confirm["enhancementLevel"],
                    0,
                    int.MaxValue,
                    out enhancementLevel)
                && enhancementLevel == item.Value<int>("enhancementLevel")
                && TryReadFiniteNumber(
                    confirm["lastUpdate"],
                    0,
                    MaxSafeProjectionNumber,
                    out lastUpdate);
        }

        private static bool IsFacetArray(
            JArray facets,
            int depth,
            bool sets,
            out int totalCount)
        {
            totalCount = 0;
            if (facets == null
                || facets.Count > BackpackSlotCount
                || depth > 2)
            {
                return false;
            }
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in facets)
            {
                JObject facet = token as JObject;
                int count;
                double order;
                if (!IsExactObject(
                        facet,
                        Set("id", "label", "order", "count", "children"))
                    || !IsBoundedText(facet["id"], 128, false)
                    || !IsBoundedText(facet["label"], 128, false)
                    || !ids.Add(ReadString(facet["id"]))
                    || !TryReadFiniteNumber(
                        facet["order"],
                        -1000000,
                        1000000,
                        out order)
                    || !TryReadInteger(
                        facet["count"],
                        0,
                        BackpackSlotCount,
                        out count)
                    || !(facet["children"] is JArray children))
                {
                    return false;
                }

                int childCount;
                if (sets)
                {
                    if (children.Count != 0) return false;
                }
                else if (children.Count == 0)
                {
                    childCount = 0;
                }
                else if (depth >= 2
                    || !IsFacetArray(
                        children, depth + 1, false, out childCount)
                    || childCount > count)
                {
                    return false;
                }
                totalCount += count;
                if (totalCount > BackpackSlotCount) return false;
            }
            return true;
        }

        private static bool IsModProjection(JObject value)
        {
            if (!IsExactObject(value, ModKeys)) return false;
            foreach (string key in ModKeys)
            {
                bool identity = key == "name" || key == "displayName" || key == "icon";
                if (identity
                    ? !IsIdentityText(value[key], 256)
                    : !IsBoundedText(value[key], 128, true)) return false;
            }
            return true;
        }

        private static bool IsBalanceSummary(JObject value)
        {
            double weightLayers;
            double formula;
            double level;
            return IsExactObject(
                    value,
                    Set("state", "weightLayers", "formula", "level"))
                && ReadString(value["state"]) == "confirmed"
                && TryReadFiniteNumber(
                    value["weightLayers"],
                    -1000000,
                    1000000,
                    out weightLayers)
                && TryReadFiniteNumber(value["formula"], 1, 1, out formula)
                && TryReadFiniteNumber(
                    value["level"],
                    0,
                    int.MaxValue,
                    out level);
        }

        private static bool IsPortrait(JObject portrait)
        {
            string gender = portrait != null
                ? ReadString(portrait["gender"]) : null;
            return IsExactObject(
                    portrait,
                    Set("gender", "equipment", "appearance"))
                && (gender == "男" || gender == "女")
                && IsStringMap(
                    portrait["equipment"] as JObject,
                    EquipmentSlotSet,
                    256)
                && IsStringMap(
                    portrait["appearance"] as JObject,
                    Set("脸型", "发型"),
                    256);
        }

        private static bool IsStringMap(
            JObject value,
            HashSet<string> allowedKeys,
            int maximumLength)
        {
            if (value == null || value.Count > allowedKeys.Count) return false;
            foreach (JProperty property in value.Properties())
            {
                if (!allowedKeys.Contains(property.Name)
                    || !IsBoundedText(
                        property.Value, maximumLength, false))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool IsDiagnostics(JArray diagnostics)
        {
            if (diagnostics == null || diagnostics.Count > 64) return false;
            foreach (JToken token in diagnostics)
            {
                if (!IsBoundedText(token, 256, false)) return false;
            }
            return true;
        }

        private static bool IsStateHealth(JToken value)
        {
            string state = ReadString(value);
            return state == "ok" || state == "degraded";
        }

        private static bool HasVersion(JObject value)
        {
            int version;
            return value != null
                && TryReadInteger(value["v"], 1, 1, out version);
        }

        private static bool IsExactObject(
            JObject value,
            HashSet<string> expectedKeys)
        {
            if (value == null
                || expectedKeys == null
                || value.Count != expectedKeys.Count)
            {
                return false;
            }
            foreach (JProperty property in value.Properties())
            {
                if (!expectedKeys.Contains(property.Name)) return false;
            }
            return true;
        }

        private static HashSet<string> Set(params string[] values)
        {
            return new HashSet<string>(values, StringComparer.Ordinal);
        }

        private static string ReadString(JToken token)
        {
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
        }

        private static bool TryReadInteger(
            JToken token,
            int minimum,
            int maximum,
            out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long raw;
            try { raw = token.Value<long>(); }
            catch { return false; }
            if (raw < minimum || raw > maximum) return false;
            value = (int)raw;
            return true;
        }

        private static bool TryReadInteger(
            JToken token,
            long minimum,
            long maximum,
            out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= minimum && value <= maximum;
        }

        private static bool TryReadFiniteNumber(
            JToken token,
            double minimum,
            double maximum,
            out double value)
        {
            value = 0;
            if (token == null
                || (token.Type != JTokenType.Integer
                    && token.Type != JTokenType.Float))
            {
                return false;
            }
            try { value = token.Value<double>(); }
            catch { return false; }
            return !double.IsNaN(value)
                && !double.IsInfinity(value)
                && value >= minimum
                && value <= maximum;
        }

        private static bool IsBoundedText(
            JToken token,
            int maximumLength,
            bool allowEmpty)
        {
            string value = ReadString(token);
            if (value == null
                || value.Length > maximumLength
                || (!allowEmpty && value.Length == 0))
            {
                return false;
            }
            foreach (char c in value)
            {
                if (char.IsControl(c)) return false;
            }
            return true;
        }

        private static bool IsIdentityText(
            JToken token,
            int maximumLength)
        {
            if (!IsBoundedText(token, maximumLength, false)) return false;
            string value = token.Value<string>();
            return !string.IsNullOrWhiteSpace(value)
                && !string.Equals(
                    value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }
    }
}
