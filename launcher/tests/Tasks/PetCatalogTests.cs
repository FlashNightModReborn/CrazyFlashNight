using System;
using System.IO;
using System.Text;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Data;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    // Phase 1（pets.xml 去 AS2 常驻）：商城静态目录的 C# 直答验证。
    // 覆盖 PetCatalogLoader 解析 + PetTask.adopt_list web 直答（不经 Flash、不需 client ready）。
    public class PetCatalogTests : IDisposable
    {
        private readonly string _root;

        public PetCatalogTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-pet-catalog-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(_root, "data", "merc"));
            File.WriteAllText(Path.Combine(_root, "data", "merc", "pets.xml"), Fixture, Encoding.UTF8);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); } catch { }
        }

        private const string Fixture =
            "<Pets>\n" +
            "  <PetStore>\n" +
            "    <Category><Name>CatA</Name><List>0,1</List><List>2,null</List></Category>\n" +
            "    <Category><Name>CatB</Name><List>1</List></Category>\n" +
            "    <Category><Name>CatC</Name><List>0,2</List></Category>\n" +
            "  </PetStore>\n" +
            "  <Pet><id>0</id><Name>P0</Name><Identifier>id0</Identifier><RosterType>partner</RosterType><Height>100</Height>" +
            "<InitialLevel>1</InitialLevel><UnlockLevel>1</UnlockLevel><UnlockTask>0</UnlockTask><Unique>false</Unique>" +
            "<Price>500</Price><KPrice>0</KPrice><IncreasePrice>0</IncreasePrice>" +
            "<Promotion><Item>基础训练</Item><Item>强化药剂</Item></Promotion></Pet>\n" +
            "  <Pet><id>1</id><Name>P1</Name><Identifier>id1</Identifier><RosterType>mechanical</RosterType><Height>110</Height>" +
            "<InitialLevel>3</InitialLevel><UnlockLevel>5</UnlockLevel><UnlockTask>2</UnlockTask><Unique>true</Unique>" +
            "<Price>0</Price><KPrice>9</KPrice><IncreasePrice>90000</IncreasePrice></Pet>\n" +
            "  <Pet><id>2</id><Name>P2</Name><Identifier>id2</Identifier><RosterType>pet</RosterType><Height>120</Height>" +
            "<InitialLevel>1</InitialLevel><UnlockLevel>1</UnlockLevel><UnlockTask>0</UnlockTask><Unique>false</Unique>" +
            "<Price>700</Price><KPrice>0</KPrice><IncreasePrice>0</IncreasePrice></Pet>\n" +
            "</Pets>\n";

        [Fact]
        public void Loader_ParsesCategoriesAndPets()
        {
            PetCatalog cat = PetCatalogLoader.Load(_root);

            Assert.Equal(3, cat.Categories.Count);
            Assert.Equal("CatA", cat.Categories[0].Name);
            Assert.Equal(2, cat.Categories[0].Rows.Count);
            Assert.Equal(new int?[] { 0, 1 }, cat.Categories[0].Rows[0].ToArray());
            // "null" 占位解析为 null
            Assert.Equal(2, cat.Categories[0].Rows[1].Count);
            Assert.Equal(2, cat.Categories[0].Rows[1][0]);
            Assert.Null(cat.Categories[0].Rows[1][1]);

            Assert.Equal(3, cat.PetsById.Count);
            Assert.True(cat.PetsById[1].Unique);
            Assert.Equal(9, cat.PetsById[1].KPrice);
            Assert.Equal(90000, cat.PetsById[1].IncreasePrice);
            Assert.Equal("id2", cat.PetsById[2].Identifier);
            Assert.Equal("mechanical", cat.PetsById[1].RosterType);
            Assert.Equal(new[] { "基础训练", "强化药剂" }, cat.PetsById[0].Promotions.ToArray());
        }

        [Fact]
        public void Loader_InvalidRosterType_FallsBackToPet()
        {
            string path = Path.Combine(_root, "data", "merc", "pets.xml");
            File.WriteAllText(path, Fixture.Replace("<RosterType>partner</RosterType>", "<RosterType>robot</RosterType>"), Encoding.UTF8);

            PetCatalog cat = PetCatalogLoader.Load(_root);

            Assert.Equal("pet", cat.PetsById[0].RosterType);
        }

        [Fact]
        public void PetLib_WebDirect_ReturnsFullLibOrderedById()
        {
            string posted = null;
            var task = new PetTask(delegate { return false; }, delegate(string p) { }, _root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("pet_lib", JObject.Parse("{\"callId\":\"web-9\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("pet_lib", (string)resp["cmd"]);
            Assert.True((bool)resp["success"]);
            var lib = (JArray)resp["petLib"];
            Assert.Equal(3, lib.Count);
            // 按 id 升序
            Assert.Equal(0, (int)lib[0]["id"]);
            Assert.Equal(2, (int)lib[2]["id"]);
            // petLib 专属字段（getPetLibDef 用 id + promotions）
            Assert.Equal(3, (int)lib[1]["initialLevel"]);
            Assert.Equal(90000, (int)lib[1]["increasePrice"]);
            Assert.Equal("mechanical", (string)lib[1]["rosterType"]);
            var promos0 = (JArray)lib[0]["promotions"];
            Assert.Equal(2, promos0.Count);
            Assert.Equal("基础训练", (string)promos0[0]);
        }

        [Fact]
        public void AdoptList_WebDirect_ReturnsCategoriesAndAdoptable_NoClientNeeded()
        {
            string posted = null;
            // isClientReady = false：web 直答不依赖 Flash 连接
            var task = new PetTask(delegate { return false; }, delegate(string p) { }, _root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("adopt_list", JObject.Parse("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("pets", (string)resp["panel"]);
            Assert.Equal("adopt_list", (string)resp["cmd"]);
            Assert.Equal("web-1", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);

            // categories 恒全量
            var cats = (JArray)resp["categories"];
            Assert.Equal(3, cats.Count);
            Assert.Equal("CatA", (string)cats[0]["name"]);
            Assert.Equal("CatB", (string)cats[1]["name"]);

            // categoryIndex 缺省 → 全部分类：CatA[0,1,2(+null skip)] + CatB[1] + CatC[0,2] = 6 项
            var adoptable = (JArray)resp["adoptable"];
            Assert.Equal(6, adoptable.Count);
            Assert.Equal(0, (int)adoptable[0]["petId"]);
            Assert.Equal("P0", (string)adoptable[0]["name"]);
            Assert.Equal("partner", (string)adoptable[0]["rosterType"]);
        }

        [Fact]
        public void AdoptList_WebDirect_FiltersByCategoryIndex()
        {
            string posted = null;
            var task = new PetTask(delegate { return true; }, delegate(string p) { }, _root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("adopt_list", JObject.Parse("{\"callId\":\"web-2\",\"categoryIndex\":1}"));

            var resp = JObject.Parse(posted);
            Assert.True((bool)resp["success"]);
            // categories 仍全量（页签需要），adoptable 仅 CatB
            Assert.Equal(3, ((JArray)resp["categories"]).Count);
            var adoptable = (JArray)resp["adoptable"];
            Assert.Single(adoptable);
            Assert.Equal(1, (int)adoptable[0]["petId"]);
        }

        [Fact]
        public void AdoptList_WebDirect_FiltersByRosterTypeAndKeepsOriginalCategoryIndexes()
        {
            string posted = null;
            var task = new PetTask(delegate { return false; }, delegate(string p) { }, _root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("adopt_list", JObject.Parse(
                "{\"callId\":\"web-r\",\"rosterType\":\"mechanical\",\"categoryIndex\":0}"));

            var resp = JObject.Parse(posted);
            Assert.True((bool)resp["success"]);
            Assert.Equal(0, (int)resp["selectedCategoryIndex"]);
            var cats = (JArray)resp["categories"];
            Assert.Equal(2, cats.Count);
            Assert.Equal(0, (int)cats[0]["index"]);
            Assert.Equal(1, (int)cats[1]["index"]);
            Assert.Equal(1, (int)cats[0]["count"]);
            var adoptable = (JArray)resp["adoptable"];
            Assert.Single(adoptable);
            Assert.Equal(1, (int)adoptable[0]["petId"]);
        }

        [Fact]
        public void AdoptList_WebDirect_InvalidRosterType_ReturnsError()
        {
            string posted = null;
            var task = new PetTask(delegate { return false; }, delegate(string p) { }, _root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("adopt_list", JObject.Parse("{\"callId\":\"web-r2\",\"rosterType\":\"robot\"}"));

            var resp = JObject.Parse(posted);
            Assert.False((bool)resp["success"]);
            Assert.Equal("invalid_roster_type", (string)resp["error"]);
        }

        [Fact]
        public void AdoptList_NoProjectRoot_FallsBackToFlashForward()
        {
            string sent = null;
            // 无 projectRoot → 退回 Flash 透传（保留 legacy 行为）
            var task = new PetTask(delegate { return true; }, delegate(string p) { sent = p; });

            task.HandleWebRequest("adopt_list", JObject.Parse("{\"callId\":\"web-3\",\"categoryIndex\":0}"));

            Assert.NotNull(sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petAdoptList", (string)msg["action"]);
        }
    }
}
