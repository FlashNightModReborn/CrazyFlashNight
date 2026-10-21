using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>Only the material/procurement route's scoped shop set gains story eligibility rules.</summary>
    public sealed class NpcShopAccessPolicy
    {
        public const string RelativePath = "data/shops/remote-access.json";
        private readonly JObject services;
        private readonly HashSet<string> shopIds;
        public IReadOnlyDictionary<string, string> SourceHashes { get; }

        private NpcShopAccessPolicy(JObject rows, IEnumerable<string> shops, Dictionary<string, string> hashes)
        { services = rows; shopIds = new HashSet<string>(shops, StringComparer.Ordinal); SourceHashes = hashes; }

        public static NpcShopAccessPolicy Load(string root, JObject definition)
        {
            var hashes = new Dictionary<string, string>(StringComparer.Ordinal);
            byte[] Read(string path)
            { var bytes = MapProjectFiles.Read(root, path); hashes[path] = MapDefinition.Hash(bytes); return bytes; }
            var policy = MapProjectFiles.Json(Read(RelativePath));
            var list = XDocument.Parse(System.Text.Encoding.UTF8.GetString(Read("data/shops/list.xml")).TrimStart('\uFEFF'));
            var shops = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in list.Root.Elements("shops"))
            {
                string path = "data/shops/" + item.Value.Trim();
                var catalog = MapProjectFiles.Json(Read(path));
                MapRuleEvaluator.Need(shops.Add((string)catalog["shopId"]), "商店身份重复。");
            }
            var contacts = JArray.Parse(System.Text.Encoding.UTF8.GetString(Read("launcher/web/assets/tablet/contacts.json")).TrimStart('\uFEFF'));
            return Parse(policy, definition, shops, contacts.Select(x => (string)x["shopId"]), hashes);
        }

        internal static NpcShopAccessPolicy Parse(JObject policy, JObject definition,
            IEnumerable<string> shops, IEnumerable<string> contacts, Dictionary<string, string> hashes = null)
        {
            MapRuleEvaluator.Keys(policy, "schema", "shops");
            MapRuleEvaluator.Need((string)policy["schema"] == "npc-shop-access.v1" && policy["shops"] is JObject rows && rows.Count is > 0 and <= 64,
                "商店准入配置不正确。");
            var known = new HashSet<string>(shops, StringComparer.Ordinal);
            var fixedContacts = new HashSet<string>(contacts, StringComparer.Ordinal);
            foreach (var row in ((JObject)policy["shops"]).Properties())
            {
                MapRuleEvaluator.Need(known.Contains(row.Name) && row.Value is JObject, "商店准入引用了未知商店。");
                var service = (JObject)row.Value;
                string mode = service.Value<string>("mode");
                MapRuleEvaluator.Keys(service, "mode", "placements");
                MapRuleEvaluator.Need(new[] { "placement", "fixed", "book", "local" }.Contains(mode), "未知商店准入模式。");
                if (mode != "placement")
                {
                    MapRuleEvaluator.Need(service["placements"] == null, "该商店模式不接受驻点。");
                    MapRuleEvaluator.Need(mode != "fixed" || fixedContacts.Contains(row.Name), "固定远程商店必须来自现役平板联系人。");
                    MapRuleEvaluator.Need(mode != "book" || row.Name == "书中-迷之盔甲君", "书中商店身份不正确。");
                    continue;
                }
                MapRuleEvaluator.Need(service["placements"] is JArray ids && ids.Count is > 0 and <= 8
                    && ids.All(x => x.Type == JTokenType.String) && ids.Distinct(JToken.EqualityComparer).Count() == ids.Count, "商店驻点列表不正确。");
                foreach (string id in (JArray)service["placements"])
                {
                    var placement = definition["placements"]?[id] as JObject;
                    var npc = placement == null ? null : definition["npcs"]?[(string)placement["npcId"]] as JObject;
                    MapRuleEvaluator.Need(npc != null && new[] { npc.Value<string>("label") }
                        .Concat(((JArray)npc["runtimeNames"]).Values<string>()).Concat(((JArray)npc["aliases"]).Values<string>())
                        .Contains(row.Name, StringComparer.Ordinal), "商店驻点未绑定对应 NPC：" + row.Name);
                }
            }
            return new NpcShopAccessPolicy((JObject)policy["shops"].DeepClone(), known,
                hashes ?? new Dictionary<string, string>(StringComparer.Ordinal));
        }

        public JObject Project(JObject definition, JObject projected)
        {
            // Shops outside this scoped route retain their existing local behavior.
            var result = new JObject(shopIds.OrderBy(x => x, StringComparer.Ordinal).Select(id => new JProperty(id, true)));
            foreach (var row in services.Properties())
            {
                string mode = row.Value.Value<string>("mode");
                bool allowed = mode == "fixed";
                if (mode == "placement")
                    allowed = ((JArray)row.Value["placements"]).Values<string>().Any(id =>
                    {
                        var placement = definition["placements"][id];
                        var location = projected["locations"]?[(string)placement["locationId"]];
                        return projected["placements"]?[id]?.Value<bool>("present") == true
                            && location?.Value<bool>("visible") == true && location.Value<bool>("enterable");
                    });
                // The exact book context and physically present NPCs remain AS2 authorities.
                result[row.Name] = allowed;
            }
            return result;
        }
    }
}
