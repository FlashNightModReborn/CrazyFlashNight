using System;
using System.IO;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class LegacyPresetSlotSeederTests : IDisposable
    {
        private const string Slot = "crazyflasher7_saves2";
        private const string SwfPath = @"E:\steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\CRAZYFLASHER7MercenaryEmpire.swf";

        private readonly string _projectRoot;

        private sealed class StubLocator : ISolFileLocator
        {
            public string SlotWithSol;
            public string ResultPath = @"E:\share\slot.sol";

            public string FindSolFile(string slot, string swfPath)
            {
                return slot == SlotWithSol ? ResultPath : null;
            }
        }

        private sealed class StubParser : ISolParser
        {
            public int Calls;
            public JObject Data;

            public SolParseResult Parse(string path)
            {
                Calls++;
                SolParseResult result = new SolParseResult();
                result.ReturnCode = SolParseResult.RC_OK;
                result.Data = Data != null ? (JObject)Data.DeepClone() : null;
                return result;
            }
        }

        public LegacyPresetSlotSeederTests()
        {
            _projectRoot = Path.Combine(Path.GetTempPath(), "cf7-seeder-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_projectRoot);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_projectRoot))
                    Directory.Delete(_projectRoot, true);
            }
            catch { }
        }

        [Fact]
        public void SeedPresetSlotIfMissing_CreatesShadowForLegacyPresetSlot()
        {
            ArchiveTask archive = new ArchiveTask(_projectRoot);
            StubLocator locator = new StubLocator { SlotWithSol = Slot };
            StubParser parser = new StubParser { Data = BuildV3SoData("legacy_name") };
            SolResolver resolver = new SolResolver(locator, archive, parser, archive);
            LegacyPresetSlotSeeder seeder = new LegacyPresetSlotSeeder(archive, resolver, SwfPath);

            seeder.SeedPresetSlotIfMissing(Slot);

            JObject shadow;
            string error;
            Assert.True(archive.TryLoadShadowSync(Slot, out shadow, out error));
            Assert.Equal("legacy_name", shadow["0"][0].Value<string>());
            Assert.Equal(1, parser.Calls);
        }

        [Fact]
        public void SeedPresetSlotIfMissing_SkipsWhenAuthorityAlreadyExists()
        {
            ArchiveTask archive = new ArchiveTask(_projectRoot);
            string ignored;
            string error;
            archive.TrySeedShadowSync(Slot, BuildV3Snapshot("existing_authority"), out ignored, out error);

            StubLocator locator = new StubLocator { SlotWithSol = Slot };
            StubParser parser = new StubParser { Data = BuildV3SoData("legacy_name") };
            SolResolver resolver = new SolResolver(locator, archive, parser, archive);
            LegacyPresetSlotSeeder seeder = new LegacyPresetSlotSeeder(archive, resolver, SwfPath);

            seeder.SeedPresetSlotIfMissing(Slot);

            JObject shadow;
            Assert.True(archive.TryLoadShadowSync(Slot, out shadow, out error));
            Assert.Equal("existing_authority", shadow["0"][0].Value<string>());
            Assert.Equal(0, parser.Calls);
        }

        [Fact]
        public void SeedAllPresetSlotsIfMissing_OnlyProbesPresetLegacySlots()
        {
            ArchiveTask archive = new ArchiveTask(_projectRoot);
            StubLocator locator = new StubLocator { SlotWithSol = Slot };
            StubParser parser = new StubParser { Data = BuildV3SoData("legacy_name") };
            SolResolver resolver = new SolResolver(locator, archive, parser, archive);
            LegacyPresetSlotSeeder seeder = new LegacyPresetSlotSeeder(archive, resolver, SwfPath);

            seeder.SeedAllPresetSlotsIfMissing();

            Assert.Equal(1, parser.Calls);
            Assert.True(File.Exists(Path.Combine(_projectRoot, "saves", Slot + ".json")));
        }

        private static JObject BuildV3SoData(string name)
        {
            JObject so = new JObject();
            so["test"] = BuildV3Snapshot(name);
            return so;
        }

        private static JObject BuildV3Snapshot(string name)
        {
            JObject md = new JObject();
            md["version"] = "3.0";
            md["lastSaved"] = "2026-04-22 12:00:00";
            md["0"] = new JArray(name, "男", 1000, 10, 500, 170, 5, "勇者", 10000, 0, new JArray(), 0, new JArray(), "");

            JArray slot1 = new JArray();
            for (int i = 0; i < 28; i++) slot1.Add(0);
            md["1"] = slot1;
            md["2"] = JValue.CreateNull();
            md["3"] = 0;
            md["4"] = new JArray(new JArray(), 0);
            md["5"] = new JArray();
            md["6"] = JValue.CreateNull();
            md["7"] = new JArray(0, 0, 0, 0, 0);

            md["inventory"] = new JObject(
                new JProperty("背包", new JArray()),
                new JProperty("装备栏", new JObject()),
                new JProperty("药剂栏", new JArray()),
                new JProperty("仓库", new JArray()),
                new JProperty("战备箱", new JArray()));
            md["collection"] = new JObject(
                new JProperty("材料", new JObject()),
                new JProperty("情报", new JObject()));
            md["infrastructure"] = new JObject();
            md["tasks"] = new JObject(
                new JProperty("tasks_to_do", new JArray()),
                new JProperty("tasks_finished", new JObject()),
                new JProperty("task_chains_progress", new JObject()));
            md["pets"] = new JObject(
                new JProperty("宠物信息", new JArray(new JArray(), new JArray(), new JArray(), new JArray(), new JArray())),
                new JProperty("宠物领养限制", 5));
            md["shop"] = new JObject(
                new JProperty("商城已购买物品", new JArray()),
                new JProperty("商城购物车", new JArray()));
            return md;
        }
    }
}
