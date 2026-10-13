using System;
using System.IO;
using System.Linq;
using System.Threading;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using CF7Launcher.RagTerminal;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// data_query "npc_dialogue" 的覆盖层接入回归：AS2 零改动，所以断言点放在返回 JSON 的逐字形状上
    /// （result 是「组的数组」，每组是 SubDialogue 数组，字段全小写、顺序与 XmlDataLoader 一致）。
    /// base XML 与覆盖层都写在临时目录，不碰仓库 data/。
    /// </summary>
    public sealed class DataQueryTaskDialogueOverlayTests : IDisposable
    {
        private const string Slot = "slotA";
        private readonly string _root =
            Path.Combine(Path.GetTempPath(), "cf7-data-query-overlay-" + Guid.NewGuid().ToString("N"));

        public DataQueryTaskDialogueOverlayTests()
        {
            Directory.CreateDirectory(_root);
            AgentDialogueOverrides.Invalidate();
            LogManager.SetSink(line => { });
        }

        public void Dispose()
        {
            AgentSaveContext.Clear();
            AgentDialogueOverrides.Invalidate();
            LogManager.ResetSink();
            try { Directory.Delete(_root, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        // ===================== fixture =====================

        /// <summary>基础 NPC 对话：两组，id 1 无门控、id 3 需主线进度 5。</summary>
        private void WriteBaseDialogues()
        {
            string dir = Path.Combine(_root, "data", "dialogues");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "list.xml"),
                "<?xml version=\"1.0\" encoding=\"utf-8\"?><root><items>npc_dialogue_test.xml</items></root>");
            File.WriteAllText(Path.Combine(dir, "npc_dialogue_test.xml"),
                "<?xml version=\"1.0\" encoding=\"utf-8\"?><root><Dialogues><Name>Andy Law</Name>"
                + "<Dialogue id=\"1\"><TaskRequirement>0</TaskRequirement><SubDialogue id=\"0\">"
                + "<Name>Andy Law</Name><Title>A兵团老大</Title><Char>Andy Law</Char><Text>基础甲</Text></SubDialogue></Dialogue>"
                + "<Dialogue id=\"3\"><TaskRequirement>5</TaskRequirement><SubDialogue id=\"0\">"
                + "<Name>Andy Law</Name><Title>A兵团老大</Title><Char>Andy Law</Char><Text>基础乙</Text></SubDialogue></Dialogue>"
                + "</Dialogues></root>");
        }

        private void WriteOverlay(string json)
        {
            string dir = Path.Combine(_root, "data", "rag", "agent_saves", Slot);
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, AgentDialogueOverrides.OverlayFileName), json);
        }

        private static JObject Replace(string baseDialogueId, params string[] texts) =>
            Entry("replace", baseDialogueId, null, texts);

        private static JObject Append(string groupId, params string[] texts) =>
            Entry("append", null, groupId, texts);

        private static JObject Entry(string action, string baseDialogueId, string groupId, string[] texts)
        {
            JArray subs = new JArray();
            foreach (string text in texts)
                subs.Add(new JObject
                {
                    ["Name"] = "Andy Law",
                    ["Title"] = "A兵团老大",
                    ["Char"] = "Andy Law",
                    ["Text"] = text
                });
            return new JObject
            {
                ["npc"] = "Andy Law",
                ["action"] = action,
                ["base_dialogue_id"] = baseDialogueId,
                ["group_id"] = groupId,
                ["subdialogues"] = subs
            };
        }

        private JObject Query(string npc, int taskProgress)
        {
            DataQueryTask task = new DataQueryTask(new DataCache(_root));
            using ManualResetEventSlim done = new ManualResetEventSlim(false);
            string response = null;
            task.HandleAsync(new JObject
            {
                ["payload"] = new JObject
                {
                    ["dataType"] = "npc_dialogue",
                    ["key"] = npc,
                    ["taskProgress"] = taskProgress
                }
            }, line => { response = line; done.Set(); });
            Assert.True(done.Wait(TimeSpan.FromSeconds(30)), "data_query 未在时限内回包");
            return JObject.Parse(response);
        }

        private static string[] TextsOf(JArray group) =>
            group.Select(sub => (string)sub["text"]).ToArray();

        // ===================== 用例 =====================

        [Fact]
        public void BoundSlotOverlayIsMergedIntoQueryResult()
        {
            WriteBaseDialogues();
            WriteOverlay(new JObject { ["overrides"] = new JArray(Replace("3", "覆盖台词"), Append("agent_1", "追加台词")) }.ToString());
            AgentSaveContext.Set(Slot);

            JObject response = Query("Andy Law", 10);

            Assert.True(response.Value<bool>("success"));
            Assert.Equal("data_query", response.Value<string>("task"));
            JArray result = (JArray)response["result"];
            Assert.Equal(3, result.Count);                                   // 基础 2 组 + 追加 1 组
            Assert.Equal(new[] { "基础甲" }, TextsOf((JArray)result[0]));
            Assert.Equal(new[] { "覆盖台词" }, TextsOf((JArray)result[1]));     // 整组替换
            Assert.Equal(new[] { "追加台词" }, TextsOf((JArray)result[2]));     // 末尾追加
            // 覆盖层台词与基础台词逐字同形：AS2 的 _root.组装单次对话 读的就是这套小写字段。
            Assert.Equal(new[] { "id", "name", "title", "char", "text", "target", "imageurl" },
                ((JObject)((JArray)result[0])[0]).Properties().Select(property => property.Name).ToArray());
            Assert.Equal(new[] { "id", "name", "title", "char", "text", "target", "imageurl" },
                ((JObject)((JArray)result[2])[0]).Properties().Select(property => property.Name).ToArray());
            Assert.Equal("Andy Law", (string)((JObject)((JArray)result[2])[0])["name"]);
        }

        [Fact]
        public void UnboundSlotKeepsBaseResultVerbatim()
        {
            WriteBaseDialogues();
            WriteOverlay(new JObject { ["overrides"] = new JArray(Replace("3", "覆盖台词"), Append("agent_1", "追加台词")) }.ToString());
            AgentSaveContext.Clear();                                        // standalone / 未绑定

            JArray result = (JArray)Query("Andy Law", 10)["result"];

            Assert.Equal(2, result.Count);
            Assert.Equal(new[] { "基础甲" }, TextsOf((JArray)result[0]));
            Assert.Equal(new[] { "基础乙" }, TextsOf((JArray)result[1]));
        }

        [Fact]
        public void AnotherSlotDoesNotSeeThisOverlay()
        {
            WriteBaseDialogues();
            WriteOverlay(new JObject { ["overrides"] = new JArray(Replace("3", "覆盖台词")) }.ToString());
            AgentSaveContext.Set("slotB");                                   // 覆盖层属于 slotA

            JArray result = (JArray)Query("Andy Law", 10)["result"];

            Assert.Equal(2, result.Count);
            Assert.Equal(new[] { "基础乙" }, TextsOf((JArray)result[1]));
        }

        [Fact]
        public void TaskRequirementFilterStillRunsAfterOverlay()
        {
            WriteBaseDialogues();
            WriteOverlay(new JObject { ["overrides"] = new JArray(Append("agent_1", "追加台词")) }.ToString());
            AgentSaveContext.Set(Slot);

            JArray result = (JArray)Query("Andy Law", 0)["result"];            // 进度 0

            // 基础 id=3（TaskRequirement 5）照旧被过滤；追加组 TaskRequirement 0 始终可用。
            Assert.Equal(2, result.Count);
            Assert.Equal(new[] { "基础甲" }, TextsOf((JArray)result[0]));
            Assert.Equal(new[] { "追加台词" }, TextsOf((JArray)result[1]));
        }

        [Fact]
        public void CorruptOverlayStillReturnsBaseDialogues()
        {
            WriteBaseDialogues();
            WriteOverlay("{\"overrides\": [ 坏掉的 JSON");
            AgentSaveContext.Set(Slot);

            JArray result = (JArray)Query("Andy Law", 10)["result"];

            Assert.Equal(2, result.Count);
            Assert.Equal(new[] { "基础乙" }, TextsOf((JArray)result[1]));
        }

        [Fact]
        public void UnknownNpcStillReturnsEmptyArray()
        {
            WriteBaseDialogues();
            WriteOverlay(new JObject { ["overrides"] = new JArray(Append("agent_1", "追加台词")) }.ToString());
            AgentSaveContext.Set(Slot);

            JObject response = Query("查无此人", 10);

            Assert.True(response.Value<bool>("success"));
            Assert.Empty((JArray)response["result"]);
        }

        [Fact]
        public void BaseLoadFailureStillReportsError()
        {
            // 没有 data/dialogues/list.xml：既有分支行为不变（Flash 走 legacy fallback）。
            AgentSaveContext.Set(Slot);

            JObject response = Query("Andy Law", 10);

            Assert.False(response.Value<bool>("success"));
            Assert.Contains("NPC data unavailable", response.Value<string>("error"), StringComparison.Ordinal);
        }
    }
}
