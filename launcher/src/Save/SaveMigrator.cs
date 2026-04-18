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
        /// 2.7 → 3.0 migration: lift SOL top-level keys into mydata.tasks /
        /// mydata.pets / mydata.shop nested shape, with defaults when SOL
        /// top-level is absent. Port of SaveManager.as:1052-1072.
        /// </summary>
        public static void Migrate_2_7_to_3_0(JObject mydata, JObject soData)
        {
            if (mydata == null) return;

            if (IsAbsent(mydata["tasks"]))
            {
                JObject tasks = new JObject();
                tasks["tasks_to_do"] = PreferNonAbsent(soData["tasks_to_do"], new JArray());
                tasks["tasks_finished"] = PreferNonAbsent(soData["tasks_finished"], new JObject());
                tasks["task_chains_progress"] = PreferNonAbsent(soData["task_chains_progress"], new JObject());
                mydata["tasks"] = tasks;
            }
            if (IsAbsent(mydata["pets"]))
            {
                JObject pets = new JObject();
                pets["宠物信息"] = PreferNonAbsent(soData["战宠"], DefaultPetsArray());
                pets["宠物领养限制"] = PreferNonAbsent(soData["宠物领养限制"], new JValue(5));
                mydata["pets"] = pets;
            }
            if (IsAbsent(mydata["shop"]))
            {
                JObject shop = new JObject();
                shop["商城已购买物品"] = PreferNonAbsent(soData["商城已购买物品"], new JArray());
                shop["商城购物车"] = PreferNonAbsent(soData["商城购物车"], new JArray());
                mydata["shop"] = shop;
            }
            mydata["version"] = "3.0";
        }

        /// <summary>
        /// SOL top-level key authoritative merge. Port of SaveManager.as:288-319
        /// (loadAll SOL path). Semantics:
        /// - tasks: group gate — if soData.tasks_to_do exists, use SOL top-level
        ///   for all three fields; otherwise keep whatever mydata.tasks has.
        /// - pets: group gate — if soData.战宠 exists, use SOL top-level for
        ///   both fields; otherwise keep mydata.pets.
        /// - shop: per-field — each field independently prefers SOL top-level.
        /// </summary>
        public static void MergeTopLevelKeys(JObject mydata, JObject soData)
        {
            if (mydata == null || soData == null) return;

            // tasks group gate
            if (!IsAbsent(soData["tasks_to_do"]))
            {
                JObject prev = mydata["tasks"] as JObject;
                JObject merged = new JObject();
                merged["tasks_to_do"] = soData["tasks_to_do"];
                merged["tasks_finished"] = Coalesce(
                    soData["tasks_finished"],
                    prev != null ? prev["tasks_finished"] : null,
                    new JObject());
                merged["task_chains_progress"] = Coalesce(
                    soData["task_chains_progress"],
                    prev != null ? prev["task_chains_progress"] : null,
                    new JObject());
                mydata["tasks"] = merged;
            }

            // pets group gate
            if (!IsAbsent(soData["战宠"]))
            {
                JObject prev = mydata["pets"] as JObject;
                JObject merged = new JObject();
                merged["宠物信息"] = soData["战宠"];
                merged["宠物领养限制"] = Coalesce(
                    soData["宠物领养限制"],
                    prev != null ? prev["宠物领养限制"] : null,
                    new JValue(5));
                mydata["pets"] = merged;
            }

            // shop per-field
            JObject shop = EnsureShop(mydata);
            if (!IsAbsent(soData["商城已购买物品"]))
                shop["商城已购买物品"] = soData["商城已购买物品"];
            if (!IsAbsent(soData["商城购物车"]))
                shop["商城购物车"] = soData["商城购物车"];
            if (IsAbsent(shop["商城已购买物品"])) shop["商城已购买物品"] = new JArray();
            if (IsAbsent(shop["商城购物车"])) shop["商城购物车"] = new JArray();
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

        private static JToken PreferNonAbsent(JToken primary, JToken fallback)
        {
            if (!IsAbsent(primary)) return primary;
            return fallback;
        }

        private static JToken Coalesce(JToken a, JToken b, JToken fallback)
        {
            if (!IsAbsent(a)) return a;
            if (!IsAbsent(b)) return b;
            return fallback;
        }

        private static JObject EnsureShop(JObject mydata)
        {
            JObject shop = mydata["shop"] as JObject;
            if (shop == null)
            {
                shop = new JObject();
                mydata["shop"] = shop;
            }
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
