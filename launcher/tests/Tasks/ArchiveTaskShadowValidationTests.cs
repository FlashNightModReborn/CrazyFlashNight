using System;
using System.IO;
using System.Text;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class ArchiveTaskShadowValidationTests : IDisposable
    {
        private readonly string _projectRoot;
        private readonly ArchiveTask _archive;

        public ArchiveTaskShadowValidationTests()
        {
            _projectRoot = Path.Combine(Path.GetTempPath(), "cf7-archive-shadow-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_projectRoot);
            Directory.CreateDirectory(Path.Combine(_projectRoot, "saves"));
            _archive = new ArchiveTask(_projectRoot);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_projectRoot)) Directory.Delete(_projectRoot, true); }
            catch { }
        }

        [Fact]
        public void Shadow_RejectsInvalidRuntimeSnapshot()
        {
            JObject invalid = BuildValidMydata();
            ((JArray)invalid["0"])[0] = JValue.CreateNull();

            JObject resp = SendShadow("cf7_agent_arena_calibration", invalid);

            Assert.False(resp.Value<bool>("success"));
            Assert.Equal("shadow_snapshot_invalid", resp.Value<string>("error"));
            Assert.False(File.Exists(Path.Combine(_projectRoot, "saves", "cf7_agent_arena_calibration.json")));
        }

        [Fact]
        public void Shadow_WritesValidRuntimeSnapshot()
        {
            JObject valid = BuildValidMydata();

            JObject resp = SendShadow("cf7_agent_arena_calibration", valid);

            Assert.True(resp.Value<bool>("success"));
            string path = Path.Combine(_projectRoot, "saves", "cf7_agent_arena_calibration.json");
            Assert.True(File.Exists(path));
            JObject written = JObject.Parse(File.ReadAllText(path, Encoding.UTF8));
            Assert.Equal("测试角色", (string)((JArray)written["0"])[0]);
        }

        private JObject SendShadow(string slot, JObject data)
        {
            JObject msg = new JObject();
            JObject payload = new JObject();
            payload["op"] = "shadow";
            payload["slot"] = slot;
            payload["data"] = data.ToString(Formatting.None);
            msg["payload"] = payload;

            string responseJson = null;
            using (ManualResetEventSlim done = new ManualResetEventSlim(false))
            {
                _archive.HandleAsync(msg, delegate(string r) { responseJson = r; done.Set(); });
                Assert.True(done.Wait(TimeSpan.FromSeconds(5)), "Timed out waiting for shadow response");
            }
            return JObject.Parse(responseJson);
        }

        private static JObject BuildValidMydata()
        {
            JObject md = new JObject();
            md["version"] = "3.0";
            md["lastSaved"] = "2026-01-01 00:00:00";

            JArray slot0 = new JArray();
            slot0.Add("测试角色"); slot0.Add("男"); slot0.Add(1000); slot0.Add(10);
            slot0.Add(500); slot0.Add(170); slot0.Add(5); slot0.Add("无");
            slot0.Add(10000); slot0.Add(0); slot0.Add(new JArray()); slot0.Add(0);
            slot0.Add(new JArray()); slot0.Add("");
            md["0"] = slot0;

            JArray slot1 = new JArray();
            for (int i = 0; i < 28; i++) slot1.Add(0);
            md["1"] = slot1;

            md["2"] = JValue.CreateNull();
            md["3"] = 0;
            md["4"] = new JArray(new JArray(), 0);
            md["5"] = new JArray();
            md["6"] = JValue.CreateNull();

            JArray slot7 = new JArray();
            for (int i = 0; i < 5; i++) slot7.Add(0);
            md["7"] = slot7;

            JObject inv = new JObject();
            inv["背包"] = new JArray();
            inv["装备栏"] = new JObject();
            inv["药剂栏"] = new JArray();
            inv["仓库"] = new JArray();
            inv["战备箱"] = new JArray();
            md["inventory"] = inv;

            JObject col = new JObject();
            col["材料"] = new JObject();
            col["情报"] = new JObject();
            md["collection"] = col;
            md["infrastructure"] = new JObject();

            JObject tasks = new JObject();
            tasks["tasks_to_do"] = new JArray();
            tasks["tasks_finished"] = new JObject();
            tasks["task_chains_progress"] = new JObject();
            md["tasks"] = tasks;

            JObject pets = new JObject();
            JArray petInfo = new JArray();
            for (int i = 0; i < 5; i++) petInfo.Add(new JArray());
            pets["宠物信息"] = petInfo;
            pets["宠物领养限制"] = 5;
            md["pets"] = pets;

            JObject shop = new JObject();
            shop["商城已购买物品"] = new JArray();
            shop["商城购物车"] = new JArray();
            md["shop"] = shop;
            return md;
        }
    }
}
