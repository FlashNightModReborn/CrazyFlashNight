using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// 按存档 NPC 日常对话覆盖层（AgentDialogueOverrides）的合并规则单测。
    /// fixture 全在临时目录（绝不写进 data/），base 索引在内存里构造；
    /// 日志经 LogManager sink 收集，用来断言 fail-closed 口径（缺文件静默、坏文件报 error、坏条目只警告跳过）。
    /// </summary>
    public sealed class AgentDialogueOverridesTests : IDisposable
    {
        private const string Slot = "slotA";
        private readonly string _root =
            Path.Combine(Path.GetTempPath(), "cf7-agent-dialogue-" + Guid.NewGuid().ToString("N"));
        private readonly List<string> _logs = new List<string>();

        public AgentDialogueOverridesTests()
        {
            Directory.CreateDirectory(_root);
            // 覆盖层缓存是进程级静态的：先清干净，缓存计数断言才只看本用例。
            AgentDialogueOverrides.Invalidate();
            LogManager.SetSink(line => { lock (_logs) _logs.Add(line); });
        }

        public void Dispose()
        {
            LogManager.ResetSink();
            AgentDialogueOverrides.Invalidate();
            try { Directory.Delete(_root, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        // ===================== fixture =====================

        private AgentDialogueOverrides Overrides() => new AgentDialogueOverrides(_root);

        private string WriteOverlay(string json, string slotKey = Slot)
        {
            string dir = Path.Combine(_root, "data", "rag", "agent_saves", slotKey);
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, AgentDialogueOverrides.OverlayFileName);
            File.WriteAllText(path, json);
            return path;
        }

        private static string Overlay(params JToken[] entries) =>
            new JObject { ["overrides"] = new JArray(entries) }.ToString();

        /// <summary>覆盖层条目形态照后端冻结的 schema：台词是 PascalCase。</summary>
        private static JObject Replace(string npc, string baseDialogueId, params string[] texts) =>
            new JObject
            {
                ["npc"] = npc,
                ["action"] = "replace",
                ["base_dialogue_id"] = baseDialogueId,
                ["group_id"] = null,
                ["subdialogues"] = Subs(texts),
                ["reason"] = "测试",
                ["source_task_id"] = 213506,
                ["source_trigger"] = "重要任务",
                ["created_at"] = "2026-10-13T00:00:00Z"
            };

        private static JObject Append(string npc, string groupId, params string[] texts) =>
            new JObject
            {
                ["npc"] = npc,
                ["action"] = "append",
                ["base_dialogue_id"] = null,
                ["group_id"] = groupId,
                ["subdialogues"] = Subs(texts)
            };

        private static JArray Subs(params string[] texts)
        {
            JArray array = new JArray();
            foreach (string text in texts)
                array.Add(new JObject
                {
                    ["Name"] = "Andy Law",
                    ["Title"] = "A兵团老大",
                    ["Char"] = "Andy Law",
                    ["Text"] = text
                });
            return array;
        }

        /// <summary>base 索引形状与 XmlDataLoader 输出一致：台词字段全小写、target/imageurl 为 null。</summary>
        private static Dictionary<string, List<DialogueGroup>> BaseIndex() =>
            new Dictionary<string, List<DialogueGroup>>(StringComparer.Ordinal)
            {
                ["Andy Law"] = new List<DialogueGroup> { Group("1", 0, "基础甲"), Group("3", 5, "基础乙") },
                ["小F"] = new List<DialogueGroup> { Group("0", 0, "基础丙") }
            };

        private static DialogueGroup Group(string groupId, int taskRequirement, params string[] texts)
        {
            JArray subs = new JArray();
            foreach (string text in texts)
                subs.Add(new JObject
                {
                    ["id"] = "",
                    ["name"] = "Andy Law",
                    ["title"] = "A兵团老大",
                    ["char"] = "Andy Law",
                    ["text"] = text,
                    ["target"] = JValue.CreateNull(),
                    ["imageurl"] = JValue.CreateNull()
                });
            return new DialogueGroup { TaskRequirement = taskRequirement, GroupId = groupId, SubDialogues = subs };
        }

        private static string[] Texts(DialogueGroup group) =>
            group.SubDialogues.Select(sub => (string)sub["text"]).ToArray();

        private static string Dump(Dictionary<string, List<DialogueGroup>> index) =>
            string.Join("|", index.Keys.OrderBy(key => key, StringComparer.Ordinal)
                .Select(key => key + ":" + string.Join(",", index[key]
                    .Select(group => group.GroupId + "/" + group.TaskRequirement + "/" + string.Join("+", Texts(group))))));

        private bool Logged(string fragment)
        {
            lock (_logs) return _logs.Any(line => line.Contains(fragment, StringComparison.Ordinal));
        }

        // ===================== replace =====================

        [Fact]
        public void ReplaceSwapsWholeGroupAndKeepsTaskRequirement()
        {
            WriteOverlay(Overlay(Replace("Andy Law", "3", "覆盖台词一", "覆盖台词二")));

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            List<DialogueGroup> groups = merged["Andy Law"];
            Assert.Equal(2, groups.Count);
            DialogueGroup replaced = groups[1];
            Assert.Equal("3", replaced.GroupId);                 // 组 id 沿用被替换组
            Assert.Equal(5, replaced.TaskRequirement);           // 门控沿用被替换组，不变成 0
            Assert.Equal(new[] { "覆盖台词一", "覆盖台词二" }, Texts(replaced));
            Assert.Equal(new[] { "基础甲" }, Texts(groups[0]));   // 同 NPC 未触及的组原样
            Assert.Equal(new[] { "基础丙" }, Texts(merged["小F"][0])); // 其他 NPC 原样
        }

        [Fact]
        public void ReplaceAppliesInOrderAndLastEntryWins()
        {
            WriteOverlay(Overlay(
                Replace("Andy Law", "3", "先写"),
                Replace("Andy Law", "3", "后写")));

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            Assert.Equal(2, merged["Andy Law"].Count);
            Assert.Equal(new[] { "后写" }, Texts(merged["Andy Law"][1]));
        }

        [Fact]
        public void ReplaceMissingNpcOrGroupIdOnlySkipsThatEntry()
        {
            WriteOverlay(Overlay(
                Replace("查无此人", "3", "跳过一"),
                Replace("Andy Law", "99", "跳过二"),
                Replace("Andy Law", "1", "有效覆盖")));

            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();
            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, baseIndex);

            // 坏条目只跳过自己：有效条目照常生效，整份覆盖层没被丢，基础数据也没加载失败。
            Assert.Equal(2, merged.Count);
            Assert.Equal(new[] { "有效覆盖" }, Texts(merged["Andy Law"][0]));
            Assert.Equal(new[] { "基础乙" }, Texts(merged["Andy Law"][1]));
            Assert.Equal(new[] { "基础丙" }, Texts(merged["小F"][0]));
            Assert.True(Logged("replace 跳过：NPC 不在基础数据"));
            Assert.True(Logged("replace 跳过：组 id 不存在"));
            Assert.False(Logged("ERROR"));
        }

        [Fact]
        public void NpcNameMatchingIsOrdinalCaseSensitive()
        {
            WriteOverlay(Overlay(Replace("andy law", "3", "大小写不一致")));

            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();
            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, baseIndex);

            Assert.Equal(new[] { "基础乙" }, Texts(merged["Andy Law"][1]));
            Assert.False(merged.ContainsKey("andy law"));
            Assert.True(Logged("replace 跳过：NPC 不在基础数据"));
        }

        // ===================== append =====================

        [Fact]
        public void AppendAddsNewGroupWithZeroTaskRequirement()
        {
            WriteOverlay(Overlay(Append("Andy Law", "agent_1", "追加台词")));

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            List<DialogueGroup> groups = merged["Andy Law"];
            Assert.Equal(3, groups.Count);
            DialogueGroup appended = groups[2];                  // 追加在末尾
            Assert.Equal("agent_1", appended.GroupId);
            Assert.Equal(0, appended.TaskRequirement);           // 始终可用
            Assert.Equal(new[] { "追加台词" }, Texts(appended));
            Assert.Equal(new[] { "基础甲" }, Texts(groups[0]));
            Assert.Equal(new[] { "基础乙" }, Texts(groups[1]));
        }

        [Fact]
        public void AppendWithSameGroupIdReplacesInsteadOfDuplicating()
        {
            // 同一文件里后端改写了同一条目：按 (npc, group_id) 定位并整组替换，不追加出重复组。
            WriteOverlay(Overlay(
                Append("Andy Law", "agent_1", "第一版"),
                Append("Andy Law", "agent_1", "第二版"),
                Append("Andy Law", "agent_2", "另一组")));

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            List<DialogueGroup> groups = merged["Andy Law"];
            Assert.Equal(4, groups.Count);
            Assert.Equal(new[] { "agent_1", "agent_2" },
                groups.Skip(2).Select(group => group.GroupId).ToArray());
            Assert.Equal(new[] { "第二版" }, Texts(groups[2]));
            Assert.Equal(new[] { "另一组" }, Texts(groups[3]));
        }

        [Fact]
        public void AppendForUnknownNpcCreatesStandaloneEntry()
        {
            WriteOverlay(Overlay(Append("新面孔", "agent_1", "追加台词")));

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            Assert.Equal(new[] { "agent_1" }, merged["新面孔"].Select(group => group.GroupId).ToArray());
            Assert.Equal(0, merged["新面孔"][0].TaskRequirement);
            Assert.Equal(2, merged["Andy Law"].Count);           // 其他 NPC 不受影响
        }

        // ===================== base 缓存不被污染 =====================

        [Fact]
        public void OverlayNeverMutatesBaseIndexAndIsIdempotent()
        {
            WriteOverlay(Overlay(Replace("Andy Law", "3", "覆盖台词"), Append("Andy Law", "agent_1", "追加台词")));

            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();
            List<DialogueGroup> baseGroups = baseIndex["Andy Law"];
            DialogueGroup baseGroup = baseGroups[1];
            string baseGroupJson = baseGroup.SubDialogues.ToString(Newtonsoft.Json.Formatting.None);

            Dictionary<string, List<DialogueGroup>> first = Overrides().Apply(Slot, baseIndex);
            Dictionary<string, List<DialogueGroup>> second = Overrides().Apply(Slot, baseIndex);

            // base 字典、组列表、组对象、台词 JArray 全部原封不动（base 是进程级缓存）。
            Assert.Equal(2, baseGroups.Count);
            Assert.Same(baseGroup, baseGroups[1]);
            Assert.Equal(baseGroupJson, baseGroup.SubDialogues.ToString(Newtonsoft.Json.Formatting.None));
            Assert.Equal(2, baseIndex.Count);

            // 应用两次结果一致，且合并结果里的对象都是新的。
            Assert.Equal(Dump(first), Dump(second));
            Assert.Equal(3, first["Andy Law"].Count);
            Assert.NotSame(baseGroups, first["Andy Law"]);
            Assert.NotSame(baseGroup, first["Andy Law"][1]);
            Assert.NotSame(first["Andy Law"][1].SubDialogues, second["Andy Law"][1].SubDialogues);
        }

        // ===================== fail-closed =====================

        [Fact]
        public void MissingOverlayFileMeansNoOverlayAndStaysSilent()
        {
            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, baseIndex);

            Assert.Same(baseIndex, merged);                       // 没有增量＝原样返回 base
            Assert.Empty(_logs);
        }

        [Fact]
        public void CorruptOverlayKeepsBaseDataWithoutThrowing()
        {
            WriteOverlay("{\"overrides\": [ {\"npc\": \"Andy Law\", ");

            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();
            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, baseIndex);

            Assert.Same(baseIndex, merged);
            Assert.True(Logged("ERROR parse failed"));
        }

        [Fact]
        public void NonArrayOverridesIsTreatedAsNoOverlay()
        {
            WriteOverlay("{\"overrides\": {\"npc\": \"Andy Law\"}}");

            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();

            Assert.Same(baseIndex, Overrides().Apply(Slot, baseIndex));
            Assert.True(Logged("ERROR overrides 不是数组"));
        }

        [Fact]
        public void MalformedEntriesAreSkippedOneByOne()
        {
            WriteOverlay(Overlay(
                new JObject { ["npc"] = "Andy Law", ["action"] = "rewrite", ["base_dialogue_id"] = "3", ["subdialogues"] = Subs("未知动作") },
                new JObject { ["npc"] = "Andy Law", ["action"] = "append", ["subdialogues"] = Subs("缺 group_id") },
                new JObject { ["npc"] = "Andy Law", ["action"] = "replace", ["base_dialogue_id"] = "1", ["subdialogues"] = "不是数组" },
                new JObject { ["npc"] = "Andy Law", ["action"] = "replace", ["base_dialogue_id"] = "1",
                    ["subdialogues"] = new JArray(new JObject { ["Name"] = "Andy Law" }) },   // 缺 Text
                Replace("Andy Law", "3", "有效覆盖")));

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            Assert.Equal(2, merged["Andy Law"].Count);
            Assert.Equal(new[] { "基础甲" }, Texts(merged["Andy Law"][0]));   // 缺 Text 的那条没把组替空
            Assert.Equal(new[] { "有效覆盖" }, Texts(merged["Andy Law"][1]));
            Assert.True(Logged("action 不是 replace/append"));
            Assert.True(Logged("append 缺少 group_id"));
            Assert.True(Logged("subdialogues 不是数组"));
            Assert.True(Logged("缺 Text"));
            Assert.True(Logged("没有可用台词，整条跳过"));
            Assert.False(Logged("ERROR"));
        }

        [Fact]
        public void EntriesBeyondFileLimitAreIgnored()
        {
            JArray entries = new JArray();
            for (int i = 1; i <= AgentDialogueOverrides.MaxEntriesPerFile; i++)
                entries.Add(Append("Andy Law", "agent_" + i, "追加" + i));
            entries.Add(Append("Andy Law", "agent_overflow", "超上限台词"));   // 第 201 条
            WriteOverlay(new JObject { ["overrides"] = entries }.ToString());

            Dictionary<string, List<DialogueGroup>> merged = Overrides().Apply(Slot, BaseIndex());

            Assert.Equal(2 + AgentDialogueOverrides.MaxEntriesPerFile, merged["Andy Law"].Count);
            Assert.DoesNotContain(merged["Andy Law"], group => group.GroupId == "agent_overflow");
            Assert.True(Logged("条目超上限"));
        }

        [Fact]
        public void UnboundOrIllegalSlotNeverDerivesOverlayPath()
        {
            WriteOverlay(Overlay(Replace("Andy Law", "3", "覆盖台词")));

            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();
            foreach (string slotKey in new[] { null, "", "../slotA", "slot A", new string('a', 129) })
                Assert.Same(baseIndex, Overrides().Apply(slotKey, baseIndex));

            Assert.Null(Overrides().OverlayPath("../slotA"));
            Assert.Equal(Path.Combine(_root, "data", "rag", "agent_saves", Slot, "dialogue_overrides.json"),
                Overrides().OverlayPath(Slot));
            Assert.Empty(_logs);
        }

        [Fact]
        public void NullBaseIndexStaysNull()
        {
            WriteOverlay(Overlay(Replace("Andy Law", "3", "覆盖台词")));

            Assert.Null(Overrides().Apply(Slot, null));
        }

        // ===================== 归一化与缓存 =====================

        [Fact]
        public void OverlayLinesAreNormalizedToBaseFieldShape()
        {
            // 后端写 PascalCase，AS2 读的是 XmlDataLoader 那套小写字段（AS2 零改动）。
            WriteOverlay(new JObject
            {
                ["overrides"] = new JArray(new JObject
                {
                    ["npc"] = "Andy Law",
                    ["action"] = "replace",
                    ["base_dialogue_id"] = "3",
                    ["subdialogues"] = new JArray(
                        new JObject { ["Name"] = "Andy Law", ["Title"] = "A兵团老大", ["Char"] = "Andy Law", ["Text"] = "覆盖台词" },
                        new JObject { ["Text"] = "只有台词" })
                })
            }.ToString());

            JArray subs = Overrides().Apply(Slot, BaseIndex())["Andy Law"][1].SubDialogues;

            Assert.Equal(2, subs.Count);
            Assert.Equal(new[] { "id", "name", "title", "char", "text", "target", "imageurl" },
                ((JObject)subs[0]).Properties().Select(property => property.Name).ToArray());
            Assert.Equal("Andy Law", (string)subs[0]["name"]);
            Assert.Equal("A兵团老大", (string)subs[0]["title"]);
            Assert.Equal("覆盖台词", (string)subs[0]["text"]);
            Assert.Equal("", (string)subs[0]["id"]);
            // 缺说话人时给空串而不是 null：AS2 会直接对 char 做 split("#")。
            Assert.Equal("", (string)subs[1]["char"]);
            Assert.Equal(JTokenType.Null, subs[1]["target"].Type);
            Assert.Equal(JTokenType.Null, subs[1]["imageurl"].Type);
        }

        [Fact]
        public void OverlayIsCachedByFileStampAndRereadAfterChange()
        {
            WriteOverlay(Overlay(Append("Andy Law", "agent_1", "第一版")));
            AgentDialogueOverrides overrides = Overrides();
            Assert.Equal(new[] { "第一版" }, Texts(overrides.Apply(Slot, BaseIndex())["Andy Law"][2]));
            Assert.Equal(1, AgentDialogueOverrides.CachedSlotCount);

            // 文件没变：命中缓存（槽位数不增，结果一致）。
            Assert.Equal(new[] { "第一版" }, Texts(overrides.Apply(Slot, BaseIndex())["Andy Law"][2]));
            Assert.Equal(1, AgentDialogueOverrides.CachedSlotCount);

            // 文件变了（写入时间 + 长度指纹）：重读生效。
            string path = WriteOverlay(Overlay(Append("Andy Law", "agent_1", "第二版内容更长")));
            File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(5));
            Assert.Equal(new[] { "第二版内容更长" }, Texts(overrides.Apply(Slot, BaseIndex())["Andy Law"][2]));

            // 显式失效后按当前文件重读。
            AgentDialogueOverrides.Invalidate();
            Assert.Equal(0, AgentDialogueOverrides.CachedSlotCount);
            Assert.Equal(new[] { "第二版内容更长" }, Texts(overrides.Apply(Slot, BaseIndex())["Andy Law"][2]));
        }

        [Fact]
        public void OverlaysAreScopedPerSlot()
        {
            WriteOverlay(Overlay(Append("Andy Law", "agent_1", "甲槽追加")), "slotA");
            WriteOverlay(Overlay(Replace("Andy Law", "3", "乙槽覆盖")), "slotB");

            AgentDialogueOverrides overrides = Overrides();
            Assert.Equal(new[] { "甲槽追加" }, Texts(overrides.Apply("slotA", BaseIndex())["Andy Law"][2]));
            Assert.Equal(new[] { "乙槽覆盖" }, Texts(overrides.Apply("slotB", BaseIndex())["Andy Law"][1]));
            Assert.Equal(2, AgentDialogueOverrides.CachedSlotCount);
        }
    }
}
