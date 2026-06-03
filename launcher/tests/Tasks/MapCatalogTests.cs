using System;
using System.IO;
using System.Text;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Data;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    // 地图 hotspot 拓扑收束：map_catalog.json 的 C# 加载 + 查询验证。
    // 覆盖 XmlDataLoader.LoadMapCatalog（解析 / 缺失 / 结构坏）、DataCache.GetMapCatalog（成功 + error 缓存）、
    // DataQueryTask("map_catalog") 的 HandleAsync 路由（成功 success:true / 缺失 success:false）。
    // 关键语义：map_catalog 是导航权威，坏数据必须硬失败到 success:false（不静默降级，对比 task_npc_registry）。
    public class MapCatalogTests : IDisposable
    {
        private readonly string _root;
        private readonly string _catalogPath;

        public MapCatalogTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-map-catalog-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(_root, "data", "map"));
            _catalogPath = Path.Combine(_root, "data", "map", "map_catalog.json");
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); } catch { }
        }

        private const string ValidFixture =
            "{\n" +
            "  \"groups\": [\n" +
            "    { \"id\": \"base\", \"page\": \"base\", \"label\": \"基地\" },\n" +
            "    { \"id\": \"defense\", \"page\": \"defense\", \"label\": \"第一防线\", \"lockedReason\": \"第一防线尚未开放\" }\n" +
            "  ],\n" +
            "  \"hotspots\": [\n" +
            "    { \"id\": \"base_lobby\", \"group\": \"base\", \"frame\": \"基地1层\" },\n" +
            "    { \"id\": \"subway\", \"group\": \"defense\", \"frame\": \"地图-隧道据点\" }\n" +
            "  ]\n" +
            "}\n";

        private void WriteCatalog(string text)
        {
            File.WriteAllText(_catalogPath, text, new UTF8Encoding(false));
        }

        // ── XmlDataLoader.LoadMapCatalog ──

        [Fact]
        public void Load_ParsesGroupsAndHotspots()
        {
            WriteCatalog(ValidFixture);
            JObject obj = XmlDataLoader.LoadMapCatalog(_root);

            JArray groups = (JArray)obj["groups"];
            JArray hotspots = (JArray)obj["hotspots"];
            Assert.Equal(2, groups.Count);
            Assert.Equal(2, hotspots.Count);
            Assert.Equal("subway", (string)hotspots[1]["id"]);
            Assert.Equal("defense", (string)hotspots[1]["group"]);
            Assert.Equal("地图-隧道据点", (string)hotspots[1]["frame"]);
        }

        [Fact]
        public void Load_MissingFile_Throws()
        {
            Assert.Throws<FileNotFoundException>(() => XmlDataLoader.LoadMapCatalog(_root));
        }

        [Fact]
        public void Load_EmptyHotspots_Throws()
        {
            WriteCatalog("{ \"groups\": [ { \"id\": \"base\", \"page\": \"base\", \"label\": \"基地\" } ], \"hotspots\": [] }");
            Assert.Throws<InvalidDataException>(() => XmlDataLoader.LoadMapCatalog(_root));
        }

        [Fact]
        public void Load_MissingGroups_Throws()
        {
            WriteCatalog("{ \"hotspots\": [ { \"id\": \"a\", \"group\": \"base\", \"frame\": \"f\" } ] }");
            Assert.Throws<InvalidDataException>(() => XmlDataLoader.LoadMapCatalog(_root));
        }

        // ── DataCache.GetMapCatalog ──

        [Fact]
        public void Cache_Success_ReturnsCatalog()
        {
            WriteCatalog(ValidFixture);
            var cache = new DataCache(_root);
            JObject data = cache.GetMapCatalog();
            Assert.NotNull(data);
            Assert.Null(cache.GetMapCatalogError());
            Assert.Equal(2, ((JArray)data["hotspots"]).Count);
        }

        [Fact]
        public void Cache_MissingFile_CachesError()
        {
            var cache = new DataCache(_root); // 无文件
            JObject data = cache.GetMapCatalog();
            Assert.Null(data);
            Assert.False(string.IsNullOrEmpty(cache.GetMapCatalogError()));
        }

        // ── DataQueryTask("map_catalog") 路由（非静默：失败 = success:false）──

        private static JObject MakeRequest()
        {
            var payload = new JObject();
            payload["dataType"] = "map_catalog";
            var msg = new JObject();
            msg["payload"] = payload;
            return msg;
        }

        private static JObject RunQuery(DataQueryTask task, JObject msg)
        {
            string captured = null;
            using (var done = new ManualResetEventSlim(false))
            {
                task.HandleAsync(msg, delegate(string resp) { captured = resp; done.Set(); });
                Assert.True(done.Wait(TimeSpan.FromSeconds(5)), "query did not respond in time");
            }
            return JObject.Parse(captured);
        }

        [Fact]
        public void Query_Success_ReturnsResultWithGroups()
        {
            WriteCatalog(ValidFixture);
            var task = new DataQueryTask(new DataCache(_root));
            JObject resp = RunQuery(task, MakeRequest());

            Assert.True((bool)resp["success"]);
            Assert.Equal(2, ((JArray)resp["result"]["hotspots"]).Count);
        }

        [Fact]
        public void Query_MissingFile_ReturnsFailureNotSilent()
        {
            var task = new DataQueryTask(new DataCache(_root)); // 无文件
            JObject resp = RunQuery(task, MakeRequest());

            Assert.False((bool)resp["success"]);
            Assert.Contains("map_catalog unavailable", (string)resp["error"]);
        }
    }
}
