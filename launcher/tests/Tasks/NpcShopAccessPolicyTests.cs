using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using CF7Launcher.Data;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class NpcShopAccessPolicyTests
    {
        private static string Root
        {
            get
            {
                string path = AppContext.BaseDirectory;
                while (!File.Exists(Path.Combine(path, NpcShopAccessPolicy.RelativePath)))
                    path = Directory.GetParent(path)?.FullName ?? throw new IOException("Repository root missing.");
                return path;
            }
        }
        private static JObject Definition() => MapDefinition.Load(Root);
        private static JObject Facts(int main, int school, int bicycle, int motorcycle, int offroad) =>
            new JObject { ["chains"] = new JObject { ["主线"] = main, ["大学"] = school },
                ["infrastructure"] = new JObject { ["自行车"] = bicycle, ["摩托车"] = motorcycle, ["越野车"] = offroad },
                ["tasks"] = new JObject(), ["scene"] = new JObject(), ["navigation"] = new JObject { ["reason"] = "" } };
        private static JObject Access(int main = 0, int school = 0, int bicycle = 0, int motorcycle = 0, int offroad = 0)
        {
            var definition = Definition();
            return NpcShopAccessPolicy.Load(Root, definition).Project(definition,
                MapDomainService.Project(definition, Facts(main, school, bicycle, motorcycle, offroad), new JObject()));
        }

        [Theory]
        [InlineData("学生妹", 28, 0, 1, false)]
        [InlineData("学生妹", 29, 0, 1, true)]
        [InlineData("黑铁会外交部长", 68, 0, 1, false)]
        [InlineData("黑铁会外交部长", 69, 0, 1, true)]
        [InlineData("调酒师", 27, 0, 1, false)]
        [InlineData("调酒师", 28, 0, 1, true)]
        [InlineData("调酒师", 28, 0, 0, false)]
        [InlineData("吸特乐", 28, 0, 1, true)]
        [InlineData("Vanshuther", 99, 6, 1, false)]
        [InlineData("Vanshuther", 0, 7, 0, true)]
        [InlineData("黑仔", 28, 6, 1, true)]
        [InlineData("武器订购系统", 0, 7, 0, true)]
        public void CurrentServiceUsesExistingMapRules(string shop, int main, int school, int motorcycle, bool expected)
            => Assert.Equal(expected, Access(main, school, motorcycle: motorcycle).Value<bool>(shop));

        [Fact]
        public void SheriffAcceptsEitherCurrentPlacementAndDoesNotRequireWorldBinding()
        {
            Assert.False(Access(main: 13, bicycle: 1).Value<bool>("前治安官"));
            Assert.True(Access(main: 14, bicycle: 1).Value<bool>("前治安官"));
            Assert.True(Access(main: 22).Value<bool>("前治安官"));
            Assert.True(Access(main: 29).Value<bool>("学生妹"));
        }

        [Fact]
        public void FixedContactsRemainRemoteAndBookOrUnmappedServicesAreNotGuessed()
        {
            var access = Access(main: 99, school: 99, offroad: 1);
            foreach (string id in new[] { "Andy Law", "The Girl", "Shop Girl", "Boy", "King", "Pig", "格格巫" })
                Assert.True(Access().Value<bool>(id));
            Assert.False(access.Value<bool>("书中-迷之盔甲君"));
            Assert.False(access.Value<bool>("虎妙"));
        }

        [Fact]
        public void DisabledPlacementAndUnknownStoryFactsNeverGrantAccess()
        {
            var definition = Definition();
            var policy = NpcShopAccessPolicy.Load(Root, definition);
            var facts = Facts(29, 0, 0, 0, 0);
            foreach (var p in ((JObject)definition["placements"]).Properties()
                .Where(p => (string)p.Value["locationId"] == "base_lobby")) p.Value["enabled"] = false;
            Assert.False(policy.Project(definition, MapDomainService.Project(definition, facts, new JObject())).Value<bool>("学生妹"));
            facts["chains"] = new JObject();
            Assert.False(NpcShopAccessPolicy.Load(Root, Definition()).Project(Definition(),
                MapDomainService.Project(Definition(), facts, new JObject())).Value<bool>("黑铁会外交部长"));
        }

        [Fact]
        public void PolicyRejectsWrongNpcUnknownPlacementAndUnregisteredFixedContact()
        {
            var definition = Definition();
            string wrong = ((JObject)definition["placements"]).Properties().First(p =>
                (string)p.Value["locationId"] == "base_garage").Name;
            foreach (var row in new[] { JObject.Parse("{mode:'placement',placements:['missing']}"),
                new JObject { ["mode"] = "placement", ["placements"] = new JArray(wrong) }, JObject.Parse("{mode:'fixed'}") })
                Assert.Throws<InvalidDataException>(() => NpcShopAccessPolicy.Parse(new JObject {
                    ["schema"] = "npc-shop-access.v1", ["shops"] = new JObject { ["学生妹"] = row } },
                    definition, new[] { "学生妹" }, Array.Empty<string>()));
        }

        [Fact]
        public void ExistingFactsWireCarriesAndReevaluatesTheProductionShopProjection()
        {
            var definition = Definition();
            var runtime = new MapRuntimeContent(definition, MapTaskCatalog.Load(Root), new JObject(),
                NpcShopAccessPolicy.Load(Root, definition));
            using var domain = new MapDomainTask(runtime);
            var hello = domain.Process(JObject.Parse("{version:2,op:'hello'}"), 1, () => true);
            var raw = JObject.Parse("{chains:{'主线':29,'大学':0},infrastructure:{'摩托车':1},flags:{},finished:{},"
                + "activeOrder:[],deliverableIds:[],available:{},scene:{stageFlag:'',frameLabel:'',entrance:'',mapFrame:'',inCombat:false},"
                + "navigation:{reason:''},dynamic:{roommateGender:''}}");
            var request = new JObject { ["version"] = 2, ["op"] = "project", ["sessionToken"] = hello["result"]["sessionToken"],
                ["contentDigest"] = runtime.ContentDigest, ["revision"] = 1, ["sceneEpoch"] = 1, ["ready"] = true,
                ["facts"] = raw, ["interestTaskIds"] = new JArray(), ["captureIds"] = new JArray(), ["intent"] = JValue.CreateNull() };
            var allowed = domain.Process(request, 1, () => true);
            Assert.True(allowed.Value<bool>("success"));
            Assert.True(allowed["result"]["projection"]["shopAccess"].Value<bool>("学生妹"));
            raw["chains"]["主线"] = 28; request["revision"] = 2;
            var denied = domain.Process(request, 1, () => true);
            Assert.True(denied.Value<bool>("success"));
            Assert.False(denied["result"]["projection"]["shopAccess"].Value<bool>("学生妹"));
        }

        [Fact]
        public void PolicyCoversAllCurrentMaterialAndRecipeSourceShopsAndBindsEveryInput()
        {
            var materials = XDocument.Load(Path.Combine(Root, "data/dictionaries/material_catalog.xml"))
                .Root.Elements("Material").Select(x => x.Element("Name").Value).ToHashSet(StringComparer.Ordinal);
            var inputs = XDocument.Load(Path.Combine(Root, "data/crafting/list.xml")).Root.Elements("list")
                .SelectMany(x => JArray.Parse(File.ReadAllText(Path.Combine(Root, "data/crafting", x.Value.Trim() + ".json"))))
                .SelectMany(x => (JArray)x["materials"]).Select(x => ((string)x).Split('#')[0]).ToHashSet(StringComparer.Ordinal);
            var candidates = XDocument.Load(Path.Combine(Root, "data/shops/list.xml")).Root.Elements("shops")
                .Select(x => JObject.Parse(File.ReadAllText(Path.Combine(Root, "data/shops", x.Value.Trim()))))
                .Where(x => ((JObject)x["catalog"]).Properties().Any(p => {
                    string name = p.Value.Type == JTokenType.String ? (string)p.Value : (string)p.Value["name"];
                    return materials.Contains(name) || inputs.Contains(name);
                })).Select(x => (string)x["shopId"]).ToHashSet(StringComparer.Ordinal);
            var policy = JObject.Parse(File.ReadAllText(Path.Combine(Root, NpcShopAccessPolicy.RelativePath)));
            Assert.Equal(26, candidates.Count);
            Assert.True(candidates.SetEquals(((JObject)policy["shops"]).Properties().Select(p => p.Name)));
            var loaded = NpcShopAccessPolicy.Load(Root, Definition());
            Assert.Contains(NpcShopAccessPolicy.RelativePath, loaded.SourceHashes.Keys);
            Assert.Contains("data/shops/list.xml", loaded.SourceHashes.Keys);
            Assert.Contains("launcher/web/assets/tablet/contacts.json", loaded.SourceHashes.Keys);
        }
    }
}
