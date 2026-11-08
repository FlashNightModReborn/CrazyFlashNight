using System;
using System.IO;
using System.Text;
using CF7Launcher.Data;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// 功能二：按存档奖励覆盖层自身的形状校验，以及「对话展示 rewards / AS2 结算 rewards」
    /// 同源投影。只做离线文件与纯函数验证，不等于 SWF 编译或游戏内结算。
    /// </summary>
    public sealed class TaskRewardOverrideTests : IDisposable
    {
        private const string Slot = "slot-1";
        private const string OverlayFile = "data/rag/agent_saves/slot-1/task_reward_overrides.json";
        private readonly string root = Path.Combine(Path.GetTempPath(),
            "cf7-reward-store-test-" + Guid.NewGuid().ToString("N"));

        public TaskRewardOverrideTests()
        {
            Directory.CreateDirectory(root);
            Put("data/infrastructure/infrastructure.xml",
                "<root><Infrastructure><Name>自行车</Name><Level/><Level/></Infrastructure></root>");
            Put("data/task/list.xml", "<root><task>required.json</task></root>");
            Put("data/task/text/list.xml", "<root><text>required.json</text></root>");
            Put("data/task/required.json",
                "{\"tasks\":[{\"id\":50004,\"title\":\"跑腿\",\"rewards\":[\"金币#1000\",\"经验值#1000\"]}]}");
            Put("data/task/text/required.json", "{\"$BASE\":\"基础文本\"}");
        }

        private string PathFor(string file) => Path.Combine(root, file.Replace('/', Path.DirectorySeparatorChar));

        private void Put(string file, string text)
        {
            string path = PathFor(file);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }

        private static JObject BackendAction(string actionId, int taskId, string extraJson, int cap = 99000)
        {
            return JObject.Parse("{\"action_id\":\"" + actionId
                + "\",\"kind\":\"task_reward_adjust\",\"task_id\":" + taskId
                + ",\"extra_rewards\":" + extraJson + ",\"额度上限\":" + cap
                + ",\"额度依据\":{\"任务类型\":\"传话\",\"阶段\":3,\"好感度\":60,"
                + "\"好感度系数\":1.1,\"阶段基础上限\":30000,\"讨价还价放大倍数\":1.0}}");
        }

        private TaskRewardOverrideStore Store(string slot = Slot) =>
            new TaskRewardOverrideStore(root, () => slot);

        [Fact]
        public void NormalizeAcceptsBackendPayloadShape()
        {
            JObject entry = TaskRewardOverrideStore.Normalize(
                BackendAction("a1", 50004, "[\"金币#500\",\"普通hp药剂#2\"]"), "50004", out string error);

            Assert.Equal("", error);
            Assert.NotNull(entry);
            Assert.Equal("50004", entry.Value<string>("task_id"));
            Assert.Equal(new[] { "金币#500", "普通hp药剂#2" }, entry["extra_rewards"].Values<string>());
            Assert.Equal(99000, entry.Value<int>("额度上限"));
            Assert.Equal("传话", entry["额度依据"].Value<string>("任务类型"));
            Assert.Equal("a1", entry.Value<string>("action_id"));
        }

        [Fact]
        public void NormalizeRejectsForeignTaskId()
        {
            Assert.Null(TaskRewardOverrideStore.Normalize(
                BackendAction("a2", 50005, "[\"金币#500\"]"), "50004", out string error));
            Assert.Equal("malformed_action", error);
        }

        [Theory]
        [InlineData("[]")]
        [InlineData("[\"金币#1\",\"金币#2\",\"金币#3\"]")]
        [InlineData("[\"金币\"]")]
        [InlineData("[\"金币#-1\"]")]
        [InlineData("[\"金币#1#2\"]")]
        public void NormalizeRejectsInvalidRewards(string extraJson)
        {
            Assert.Null(TaskRewardOverrideStore.Normalize(
                BackendAction("a3", 50004, extraJson), "50004", out string error));
            Assert.Equal("invalid_extra_rewards", error);
        }

        [Fact]
        public void AppendExtraRewardsKeepsOriginalAndCapsAtTwo()
        {
            var task = new JObject { ["rewards"] = new JArray("金币#1000", "经验值#1000") };
            var entry = new JObject
            {
                ["extra_rewards"] = new JArray("金币#500", "普通hp药剂#2", "第三样#1")
            };

            TaskRewardOverrideStore.AppendExtraRewards(task, entry);

            Assert.Equal(new[] { "金币#1000", "经验值#1000", "金币#500", "普通hp药剂#2" },
                task["rewards"].Values<string>());
        }

        [Fact]
        public void TryApplyOverwritesSameTaskAndReportsRelativeSource()
        {
            var store = Store();
            JObject first = TaskRewardOverrideStore.Normalize(
                BackendAction("b1", 50004, "[\"金币#500\"]"), "50004", out _);
            Assert.True(store.TryApply(first, out string relativePath, out string error));
            Assert.Equal("", error);
            Assert.Equal(OverlayFile, relativePath);

            JObject second = TaskRewardOverrideStore.Normalize(
                BackendAction("b2", 50004, "[\"经验值#10\"]"), "50004", out _);
            Assert.True(store.TryApply(second, out _, out _));

            JObject overlay = JObject.Parse(File.ReadAllText(PathFor(OverlayFile)));
            Assert.Single(overlay.Properties());           // 按 task_id 整条覆盖，不累加
            Assert.Equal(new[] { "经验值#10" }, overlay["50004"]["extra_rewards"].Values<string>());
            Assert.Equal("b2", overlay["50004"].Value<string>("action_id"));
        }

        [Fact]
        public void TryApplyWithoutSlotFailsWithoutWriting()
        {
            var store = Store(null);
            JObject entry = TaskRewardOverrideStore.Normalize(
                BackendAction("b3", 50004, "[\"金币#500\"]"), "50004", out _);

            Assert.False(store.TryApply(entry, out string relativePath, out string error));
            Assert.Equal("no_slot", error);
            Assert.Null(relativePath);
            Assert.False(File.Exists(PathFor(OverlayFile)));
        }

        [Fact]
        public void TryApplyIsFailClosedOnCorruptOverlay()
        {
            Put(OverlayFile, "{\"50004\":");
            var store = Store();
            JObject entry = TaskRewardOverrideStore.Normalize(
                BackendAction("b4", 50004, "[\"金币#500\"]"), "50004", out _);

            Assert.False(store.TryApply(entry, out _, out string error));
            Assert.Equal("overlay_corrupt", error);
            Assert.Equal("{\"50004\":", File.ReadAllText(PathFor(OverlayFile)));
        }

        [Fact]
        public void CatalogProjectionReadsTheSameOverlayFile()
        {
            var before = MapTaskCatalog.Load(root);
            Assert.Equal(new[] { "金币#1000", "经验值#1000" },
                before.Tasks["50004"]["rewards"].Values<string>());

            var store = Store();
            store.TryApply(TaskRewardOverrideStore.Normalize(
                BackendAction("b5", 50004, "[\"金币#500\",\"普通hp药剂#2\"]"), "50004", out _),
                out _, out _);

            var after = MapTaskCatalog.Load(root, null, null, null,
                MapTaskCatalog.AgentSaveRewardOverrideSource(Slot));

            Assert.Equal(new[] { "金币#1000", "经验值#1000", "金币#500", "普通hp药剂#2" },
                after.Tasks["50004"]["rewards"].Values<string>());
            // 字节进 SourceBytes：宿主 task_sync 能把这份覆盖层作为变化源发给 AS2 重读。
            Assert.Contains(OverlayFile, MapTaskCatalog.ChangedSources(before, after));
        }

        [Fact]
        public void CatalogProjectionIgnoresUnknownTaskButKeepsSourceBytes()
        {
            var store = Store();
            store.TryApply(TaskRewardOverrideStore.Normalize(
                BackendAction("b6", 50004, "[\"金币#500\"]"), "50004", out _), out _, out _);
            JObject overlay = JObject.Parse(File.ReadAllText(PathFor(OverlayFile)));
            overlay["999999"] = JObject.Parse("{\"task_id\":\"999999\",\"extra_rewards\":[\"金币#1\"]}");
            File.WriteAllText(PathFor(OverlayFile), overlay.ToString(Newtonsoft.Json.Formatting.None),
                new UTF8Encoding(false));

            var catalog = MapTaskCatalog.Load(root, null, null, null,
                MapTaskCatalog.AgentSaveRewardOverrideSource(Slot));

            Assert.Null(catalog.Tasks["999999"]);
            Assert.Equal(new[] { "金币#1000", "经验值#1000", "金币#500" },
                catalog.Tasks["50004"]["rewards"].Values<string>());
            Assert.True(catalog.SourceBytes.ContainsKey(OverlayFile));
        }

        [Fact]
        public void CatalogProjectionRejectsMalformedOverlayEntry()
        {
            Put(OverlayFile, "{\"50004\":{\"task_id\":\"50004\"}}");

            Assert.Throws<InvalidDataException>(() => MapTaskCatalog.Load(root, null, null, null,
                MapTaskCatalog.AgentSaveRewardOverrideSource(Slot)));
        }

        [Fact]
        public void MissingOverlayIsNotAChange()
        {
            var before = MapTaskCatalog.Load(root);
            var after = MapTaskCatalog.Load(root, null, null, null,
                MapTaskCatalog.AgentSaveRewardOverrideSource(Slot));

            Assert.Equal(before.Digest, after.Digest);
            Assert.Empty(MapTaskCatalog.ChangedSources(before, after));
        }

        public void Dispose()
        {
            try { if (Directory.Exists(root)) Directory.Delete(root, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
