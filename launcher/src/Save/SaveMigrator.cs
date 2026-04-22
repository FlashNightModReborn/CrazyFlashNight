// CF7:ME save-data migration + validation (C# port of SaveManager.as migration
// and validation logic). C# 5 syntax; targets .NET Framework 4.6.2.

using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    /// <summary>
    /// Static helpers that mirror the AS2 SaveManager.as migration + validation
    /// functions. The goal is structural parity: given the same soData, the
    /// launcher and AS2 must converge on the same normalizedMydata.
    /// </summary>
    public static class SaveMigrator
    {
        /// <summary>
        /// AMF0 undefined, AMF0 null, and JSON-missing should all be treated
        /// as "absent" by presence checks (matches AS2 `v == undefined`).
        /// </summary>
        public static bool IsAbsent(JToken token)
        {
            return token == null || token.Type == JTokenType.Null;
        }

        /// <summary>
        /// 2.7 -> 3.0 migration: lift mirrored SOL top-level keys into
        /// mydata.tasks / mydata.pets / mydata.shop.
        /// </summary>
        public static void Migrate_2_7_to_3_0(JObject mydata, JObject soData)
        {
            if (mydata == null) return;
            if (IsAbsent(mydata["3"]))
                mydata["3"] = 0;

            if (IsAbsent(mydata["tasks"]))
            {
                JObject tasks = new JObject();
                tasks["tasks_to_do"] = CloneToken(PreferTaskArray(soData["tasks_to_do"], null, new JArray()));
                tasks["tasks_finished"] = CloneToken(PreferTaskObject(soData["tasks_finished"], null, new JObject()));
                tasks["task_chains_progress"] = BuildTaskChainsProgress(
                    soData["task_chains_progress"],
                    null,
                    mydata["3"]);
                mydata["tasks"] = tasks;
            }
            if (IsAbsent(mydata["pets"]))
            {
                mydata["pets"] = BuildPetsBundle(
                    soData["战宠"],
                    soData["宠物领养限制"],
                    null);
            }
            if (IsAbsent(mydata["shop"]))
            {
                mydata["shop"] = BuildShopBundle(
                    soData["商城已购买物品"],
                    soData["商城购物车"],
                    null);
            }
            mydata["version"] = "3.0";
            NormalizeResolvedSnapshot(mydata);
        }

        /// <summary>
        /// Merge mirrored top-level SOL keys into normalized mydata.
        /// Prefer non-empty top-level layers; if top-level is present but empty
        /// while nested mydata still has data, keep nested to avoid data loss.
        /// Tasks also repair legacy mainline from mydata["3"].
        /// </summary>
        public static void MergeTopLevelKeys(JObject mydata, JObject soData)
        {
            if (mydata == null || soData == null) return;

            JObject prevTasks = mydata["tasks"] as JObject;
            JObject mergedTasks = new JObject();
            mergedTasks["tasks_to_do"] = CloneToken(PreferTaskArray(
                soData["tasks_to_do"],
                prevTasks != null ? prevTasks["tasks_to_do"] : null,
                new JArray()));
            mergedTasks["tasks_finished"] = CloneToken(PreferTaskObject(
                soData["tasks_finished"],
                prevTasks != null ? prevTasks["tasks_finished"] : null,
                new JObject()));
            mergedTasks["task_chains_progress"] = BuildTaskChainsProgress(
                soData["task_chains_progress"],
                prevTasks != null ? prevTasks["task_chains_progress"] : null,
                mydata["3"]);
            mydata["tasks"] = mergedTasks;

            mydata["pets"] = BuildPetsBundle(
                soData["战宠"],
                soData["宠物领养限制"],
                mydata["pets"] as JObject);

            mydata["shop"] = BuildShopBundle(
                soData["商城已购买物品"],
                soData["商城购物车"],
                mydata["shop"] as JObject);
            NormalizeResolvedSnapshot(mydata);
        }

        /// <summary>
        /// Repair legacy/edited snapshots in place without fabricating missing
        /// top-level sections. Only fields already present are normalized.
        /// </summary>
        public static void NormalizeResolvedSnapshot(JObject mydata)
        {
            if (mydata == null) return;

            JObject tasks = mydata["tasks"] as JObject;
            if (tasks != null)
            {
                if (!IsAbsent(tasks["tasks_to_do"]))
                    tasks["tasks_to_do"] = NormalizeTaskArray(tasks["tasks_to_do"]);
                if (!IsAbsent(tasks["tasks_finished"]))
                    tasks["tasks_finished"] = NormalizeTaskFinishedObject(tasks["tasks_finished"]);
                if (!IsAbsent(tasks["task_chains_progress"]))
                    tasks["task_chains_progress"] = NormalizeTaskChainsProgress(tasks["task_chains_progress"], mydata["3"]);
            }

            JObject pets = mydata["pets"] as JObject;
            if (pets != null)
            {
                if (!IsAbsent(pets["宠物信息"]))
                    pets["宠物信息"] = NormalizePetsInfo(pets["宠物信息"]);
            }

            JObject shop = mydata["shop"] as JObject;
            if (shop != null)
            {
                if (!IsAbsent(shop["商城已购买物品"]))
                    shop["商城已购买物品"] = NormalizeListArray(shop["商城已购买物品"]);
                if (!IsAbsent(shop["商城购物车"]))
                    shop["商城购物车"] = NormalizeListArray(shop["商城购物车"]);
            }
        }

        /// <summary>
        /// 28-item structural validation mirroring AS2 validateMydata
        /// (SaveManager.as:703-740). Returns true when mydata is a complete
        /// 3.0 snapshot safe to feed into loadFromMydata(snap).
        /// </summary>
        public static bool ValidateResolvedSnapshot(JObject mydata)
        {
            if (mydata == null) return false;

            // version / lastSaved
            string ver = mydata.Value<string>("version");
            if (ver != "3.0") return false;
            if (IsAbsent(mydata["lastSaved"])) return false;

            // mydata[0..7] character arrays
            JArray a0 = mydata["0"] as JArray;
            if (a0 == null || a0.Count < 14) return false;
            JArray a1 = mydata["1"] as JArray;
            if (a1 == null || a1.Count < 28) return false;
            if (IsAbsent(mydata["3"])) return false;
            JArray a4 = mydata["4"] as JArray;
            if (a4 == null || a4.Count < 2) return false;
            if (!(mydata["5"] is JArray)) return false;
            JArray a7 = mydata["7"] as JArray;
            if (a7 == null || a7.Count < 5) return false;

            // inventory
            JObject inv = mydata["inventory"] as JObject;
            if (inv == null) return false;
            string[] invKeys = new string[] { "背包", "装备栏", "药剂栏", "仓库", "战备箱" };
            for (int i = 0; i < invKeys.Length; i++)
            {
                if (IsAbsent(inv[invKeys[i]])) return false;
            }

            // collection / infrastructure
            JObject col = mydata["collection"] as JObject;
            if (col == null) return false;
            if (IsAbsent(col["材料"]) || IsAbsent(col["情报"])) return false;
            if (IsAbsent(mydata["infrastructure"])) return false;

            // tasks
            JObject tasks = mydata["tasks"] as JObject;
            if (tasks == null) return false;
            if (!(tasks["tasks_to_do"] is JArray)) return false;
            if (!(tasks["tasks_finished"] is JObject)) return false;
            if (!(tasks["task_chains_progress"] is JObject)) return false;

            // pets
            JObject pets = mydata["pets"] as JObject;
            if (pets == null) return false;
            JArray petInfo = pets["宠物信息"] as JArray;
            if (petInfo == null || petInfo.Count < 5) return false;
            for (int i = 0; i < petInfo.Count; i++)
            {
                if (!(petInfo[i] is JArray)) return false;
            }
            if (IsAbsent(pets["宠物领养限制"])) return false;

            // shop
            JObject shop = mydata["shop"] as JObject;
            if (shop == null) return false;
            if (!(shop["商城已购买物品"] is JArray)) return false;
            if (!(shop["商城购物车"] is JArray)) return false;

            return true;
        }

        // ───────── helpers ─────────

        private static JToken CloneToken(JToken token)
        {
            if (token == null) return null;
            return token.DeepClone();
        }

        private static JToken Coalesce(JToken a, JToken b, JToken fallback)
        {
            if (!IsAbsent(a)) return a;
            if (!IsAbsent(b)) return b;
            return fallback;
        }

        private static bool HasTaskEntries(JToken token)
        {
            if (IsAbsent(token)) return false;
            JArray arr = token as JArray;
            if (arr != null) return arr.Count > 0;
            JObject obj = token as JObject;
            if (obj == null || !obj.HasValues) return false;
            if (!IsAbsent(obj["id"])) return true;

            foreach (JProperty prop in obj.Properties())
            {
                int ignored;
                if (IsNonNegativeIntegerKey(prop.Name)) return true;
                if (string.Equals(prop.Name, "主线", StringComparison.Ordinal)) return true;
                if (!IsTaskProgressMetaKey(prop.Name) && TryGetIntegralValue(prop.Value, out ignored))
                    return true;
            }
            return false;
        }

        private static JToken PreferTaskArray(JToken primary, JToken fallback, JToken defaultValue)
        {
            if (!IsAbsent(primary))
            {
                if (HasTaskEntries(primary) || IsAbsent(fallback) || !HasTaskEntries(fallback))
                    return primary;
            }
            if (!IsAbsent(fallback)) return fallback;
            return defaultValue;
        }

        private static JToken PreferTaskObject(JToken primary, JToken fallback, JToken defaultValue)
        {
            if (!IsAbsent(primary))
            {
                if (HasTaskEntries(primary) || IsAbsent(fallback) || !HasTaskEntries(fallback))
                    return primary;
            }
            if (!IsAbsent(fallback)) return fallback;
            return defaultValue;
        }

        private static JObject BuildTaskChainsProgress(JToken primary, JToken fallback, JToken legacyMainToken)
        {
            JToken picked = PreferTaskObject(primary, fallback, new JObject());
            return NormalizeTaskChainsProgress(picked, legacyMainToken);
        }

        private static bool IsNonNegativeIntegerKey(string key)
        {
            if (string.IsNullOrEmpty(key)) return false;
            int index;
            return int.TryParse(key, out index) && index >= 0;
        }

        private static bool TryGetIntegralValue(JToken token, out int value)
        {
            value = 0;
            if (IsAbsent(token)) return false;

            try
            {
                if (token.Type == JTokenType.Boolean)
                {
                    value = token.Value<bool>() ? 1 : 0;
                    return true;
                }

                if (token.Type == JTokenType.Integer)
                {
                    value = token.Value<int>();
                    return true;
                }

                if (token.Type == JTokenType.Float)
                {
                    double num = token.Value<double>();
                    if (double.IsNaN(num) || double.IsInfinity(num)) return false;
                    value = (int)Math.Floor(num);
                    return true;
                }

                if (token.Type == JTokenType.String)
                {
                    string text = token.Value<string>();
                    return int.TryParse(text, out value);
                }
            }
            catch
            {
                return false;
            }

            return false;
        }

        private static bool IsTaskProgressMetaKey(string key)
        {
            return string.Equals(key, "id", StringComparison.Ordinal)
                || string.Equals(key, "requirements", StringComparison.Ordinal)
                || string.Equals(key, "stages", StringComparison.Ordinal)
                || string.Equals(key, "challenge", StringComparison.Ordinal)
                || string.Equals(key, "finished", StringComparison.Ordinal);
        }

        private static JArray NormalizeTaskArray(JToken token)
        {
            JArray result = new JArray();
            if (IsAbsent(token)) return result;

            JArray arr = token as JArray;
            if (arr != null)
            {
                for (int i = 0; i < arr.Count; i++)
                {
                    JObject task = NormalizeTaskEntry(arr[i]);
                    if (task != null) result.Add(task);
                }
                return result;
            }

            JObject obj = token as JObject;
            if (obj == null) return result;

            JArray indexed;
            if (TryConvertIndexedObjectToArray(obj, out indexed))
                return NormalizeTaskArray(indexed);

            JObject single = NormalizeTaskEntry(obj);
            if (single != null) result.Add(single);
            return result;
        }

        private static JObject NormalizeTaskEntry(JToken token)
        {
            JObject obj = token as JObject;
            if (obj == null || IsAbsent(obj["id"])) return null;

            JObject result = obj.DeepClone() as JObject;
            if (result == null) return null;

            JObject requirements = result["requirements"] as JObject;
            if (requirements == null)
            {
                requirements = new JObject();
                result["requirements"] = requirements;
            }
            else
            {
                requirements = requirements.DeepClone() as JObject;
                result["requirements"] = requirements;
            }

            JToken stagesSource = requirements["stages"];
            if (IsAbsent(stagesSource) && !IsAbsent(result["stages"]))
                stagesSource = result["stages"];

            requirements["stages"] = NormalizeListArray(stagesSource);
            result.Remove("stages");
            return result;
        }

        private static JObject NormalizeTaskFinishedObject(JToken token)
        {
            JObject result = new JObject();
            if (IsAbsent(token)) return result;

            JArray arr = token as JArray;
            if (arr != null)
            {
                for (int i = 0; i < arr.Count; i++)
                {
                    int value;
                    if (TryGetIntegralValue(arr[i], out value))
                        result[i.ToString()] = value;
                }
                return result;
            }

            JObject obj = token as JObject;
            if (obj == null) return result;

            foreach (JProperty prop in obj.Properties())
            {
                int value;
                if (IsNonNegativeIntegerKey(prop.Name) && TryGetIntegralValue(prop.Value, out value))
                    result[prop.Name] = value;
            }
            return result;
        }

        private static JObject NormalizeTaskChainsProgress(JToken token, JToken legacyMainToken)
        {
            JObject result = new JObject();
            if (!IsAbsent(token))
            {
                JArray arr = token as JArray;
                if (arr != null)
                {
                    for (int i = 0; i < arr.Count; i++)
                    {
                        int value;
                        if (TryGetIntegralValue(arr[i], out value))
                            result[i.ToString()] = value;
                    }
                }
                else
                {
                    JObject obj = token as JObject;
                    if (obj != null)
                    {
                        foreach (JProperty prop in obj.Properties())
                        {
                            int value;
                            if (IsTaskProgressMetaKey(prop.Name)) continue;
                            if (TryGetIntegralValue(prop.Value, out value))
                                result[prop.Name] = value;
                        }
                    }
                }
            }

            int legacyMain;
            if (result["主线"] == null && TryGetLegacyMainProgress(legacyMainToken, out legacyMain))
                result["主线"] = legacyMain;
            return result;
        }

        private static bool TryGetLegacyMainProgress(JToken token, out int progress)
        {
            progress = 0;
            if (IsAbsent(token)) return false;
            try
            {
                double value = token.Value<double>();
                if (double.IsNaN(value)) return false;
                progress = (int)Math.Floor(value);
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static bool HasListEntries(JToken token)
        {
            if (IsAbsent(token)) return false;
            JArray arr = token as JArray;
            return arr != null && arr.Count > 0;
        }

        private static JToken PreferListArray(JToken primary, JToken fallback, JToken defaultValue)
        {
            if (!IsAbsent(primary))
            {
                if (HasListEntries(primary) || IsAbsent(fallback) || !HasListEntries(fallback))
                    return primary;
            }
            if (!IsAbsent(fallback)) return fallback;
            return defaultValue;
        }

        private static bool HasPetEntries(JToken token)
        {
            JArray arr = token as JArray;
            if (arr == null) return false;
            for (int i = 0; i < arr.Count; i++)
            {
                JArray petArr = arr[i] as JArray;
                if (petArr != null)
                {
                    if (petArr.Count > 0) return true;
                    continue;
                }

                JObject petObj = arr[i] as JObject;
                if (petObj != null)
                {
                    if (petObj.HasValues) return true;
                    continue;
                }

                if (!IsAbsent(arr[i])) return true;
            }
            return false;
        }

        private static JToken PreferPetsInfo(JToken primary, JToken fallback, JToken defaultValue)
        {
            if (!IsAbsent(primary))
            {
                if (HasPetEntries(primary) || IsAbsent(fallback) || !HasPetEntries(fallback))
                    return primary;
            }
            if (!IsAbsent(fallback)) return fallback;
            return defaultValue;
        }

        private static JObject BuildPetsBundle(JToken primaryInfo, JToken primaryLimit, JObject previousPets)
        {
            JToken fallbackInfo = previousPets != null ? previousPets["宠物信息"] : null;
            JToken fallbackLimit = previousPets != null ? previousPets["宠物领养限制"] : null;
            bool usePrimaryInfo = !IsAbsent(primaryInfo)
                && (HasPetEntries(primaryInfo) || IsAbsent(fallbackInfo) || !HasPetEntries(fallbackInfo));
            JToken chosenInfo = PreferPetsInfo(primaryInfo, fallbackInfo, DefaultPetsArray());

            JObject pets = new JObject();
            pets["宠物信息"] = CloneToken(chosenInfo);
            pets["宠物领养限制"] = CloneToken(usePrimaryInfo
                ? Coalesce(primaryLimit, fallbackLimit, new JValue(5))
                : Coalesce(fallbackLimit, primaryLimit, new JValue(5)));
            return pets;
        }

        private static JArray NormalizePetsInfo(JToken token)
        {
            JArray source = token as JArray;
            if (source == null)
            {
                JObject obj = token as JObject;
                JArray indexed;
                if (obj != null && TryConvertIndexedObjectToArray(obj, out indexed))
                    source = indexed;
            }

            JArray result = new JArray();
            if (source != null)
            {
                for (int i = 0; i < source.Count; i++)
                {
                    result.Add(NormalizePetSlot(source[i]));
                }
            }

            while (result.Count < 5)
                result.Add(new JArray());
            return result;
        }

        private static JArray NormalizePetSlot(JToken token)
        {
            if (IsAbsent(token)) return new JArray();

            JArray arr = token as JArray;
            if (arr != null) return arr.DeepClone() as JArray ?? new JArray();

            JObject obj = token as JObject;
            if (obj == null || !obj.HasValues) return new JArray();

            JArray indexed;
            if (TryConvertIndexedObjectToArray(obj, out indexed))
                return indexed;

            return new JArray();
        }

        private static JObject BuildShopBundle(JToken primaryPurchased, JToken primaryCart, JObject previousShop)
        {
            JToken fallbackPurchased = previousShop != null ? previousShop["商城已购买物品"] : null;
            JToken fallbackCart = previousShop != null ? previousShop["商城购物车"] : null;

            JObject shop = new JObject();
            shop["商城已购买物品"] = CloneToken(PreferListArray(primaryPurchased, fallbackPurchased, new JArray()));
            shop["商城购物车"] = CloneToken(PreferListArray(primaryCart, fallbackCart, new JArray()));
            return shop;
        }

        private static JArray NormalizeListArray(JToken token)
        {
            if (IsAbsent(token)) return new JArray();

            JArray arr = token as JArray;
            if (arr != null) return arr.DeepClone() as JArray ?? new JArray();

            JObject obj = token as JObject;
            if (obj == null) return new JArray();

            JArray indexed;
            if (TryConvertIndexedObjectToArray(obj, out indexed))
                return indexed;

            return new JArray();
        }

        private static bool TryConvertIndexedObjectToArray(JObject obj, out JArray array)
        {
            array = null;
            if (obj == null) return false;

            SortedDictionary<int, JToken> ordered = new SortedDictionary<int, JToken>();
            foreach (JProperty prop in obj.Properties())
            {
                int index;
                if (!int.TryParse(prop.Name, out index) || index < 0)
                    return false;
                if (!ordered.ContainsKey(index))
                    ordered[index] = CloneToken(prop.Value);
            }

            array = new JArray();
            foreach (KeyValuePair<int, JToken> entry in ordered)
            {
                array.Add(entry.Value);
            }
            return true;
        }

        private static JArray DefaultPetsArray()
        {
            JArray a = new JArray();
            for (int i = 0; i < 5; i++) a.Add(new JArray());
            return a;
        }
    }
}
