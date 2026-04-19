// CF7:ME save-data migration + validation (C# port of SaveManager.as migration
// and validation logic). C# 5 syntax; targets .NET Framework 4.6.2.

using System;
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
            if (IsAbsent(tasks["tasks_to_do"])) return false;
            if (IsAbsent(tasks["tasks_finished"])) return false;
            if (IsAbsent(tasks["task_chains_progress"])) return false;

            // pets
            JObject pets = mydata["pets"] as JObject;
            if (pets == null) return false;
            if (IsAbsent(pets["宠物信息"])) return false;
            if (IsAbsent(pets["宠物领养限制"])) return false;

            // shop
            JObject shop = mydata["shop"] as JObject;
            if (shop == null) return false;
            if (IsAbsent(shop["商城已购买物品"])) return false;
            if (IsAbsent(shop["商城购物车"])) return false;

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
            return obj != null && obj.HasValues;
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
            JObject result = picked as JObject;
            if (result != null) result = result.DeepClone() as JObject;
            if (result == null) result = new JObject();

            int legacyMain;
            if (result["主线"] == null && TryGetLegacyMainProgress(legacyMainToken, out legacyMain))
            {
                result["主线"] = legacyMain;
            }
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

        private static JObject BuildShopBundle(JToken primaryPurchased, JToken primaryCart, JObject previousShop)
        {
            JToken fallbackPurchased = previousShop != null ? previousShop["商城已购买物品"] : null;
            JToken fallbackCart = previousShop != null ? previousShop["商城购物车"] : null;

            JObject shop = new JObject();
            shop["商城已购买物品"] = CloneToken(PreferListArray(primaryPurchased, fallbackPurchased, new JArray()));
            shop["商城购物车"] = CloneToken(PreferListArray(primaryCart, fallbackCart, new JArray()));
            return shop;
        }

        private static JArray DefaultPetsArray()
        {
            JArray a = new JArray();
            for (int i = 0; i < 5; i++) a.Add(new JArray());
            return a;
        }
    }
}
