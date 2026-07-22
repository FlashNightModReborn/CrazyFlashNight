using System;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tests.Contracts
{
    public static class PanelContractVectors
    {
        private static readonly Lazy<JObject> Contract = new Lazy<JObject>(LoadContract);

        public static IEnumerable<object[]> NpcShopPurchaseQuantityValid()
        {
            return ReadValues("npcshop", "purchaseQuantity", "valid");
        }

        public static IEnumerable<object[]> NpcShopPurchaseQuantityInvalid()
        {
            return ReadValues("npcshop", "purchaseQuantity", "invalid");
        }

        public static IEnumerable<object[]> CraftingCraftCountValid()
        {
            return ReadValues("crafting", "craftCount", "valid");
        }

        public static IEnumerable<object[]> CraftingCraftCountInvalid()
        {
            return ReadValues("crafting", "craftCount", "invalid");
        }

        public static IEnumerable<object[]> KShopPurchaseQuantityAll()
        {
            foreach (object[] row in ReadValues("kshop", "purchaseQuantity", "valid")) yield return row;
            foreach (object[] row in ReadValues("kshop", "purchaseQuantity", "invalid")) yield return row;
        }

        private static IEnumerable<object[]> ReadValues(string domain, string vector, string set)
        {
            JArray values = Contract.Value["vectors"]?[domain]?[vector]?[set] as JArray
                ?? throw new InvalidDataException("Missing panel contract vector: " + domain + "." + vector + "." + set);
            foreach (JToken value in values)
            {
                if (value.Type != JTokenType.Integer)
                    throw new InvalidDataException("Panel contract vector must contain integers: " + domain + "." + vector + "." + set);
                yield return new object[] { value.Value<int>() };
            }
        }

        private static JObject LoadContract()
        {
            string path = Path.Combine(AppContext.BaseDirectory, "Contracts", "panel-contracts.v1.json");
            if (!File.Exists(path)) throw new FileNotFoundException("Panel contract fixture was not copied to the test output.", path);
            return JObject.Parse(File.ReadAllText(path));
        }
    }
}
