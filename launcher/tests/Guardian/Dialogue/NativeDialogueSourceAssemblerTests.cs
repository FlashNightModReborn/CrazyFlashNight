using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Data;
using CF7Launcher.Guardian.Dialogue;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// NativeDialogueSourceAssembler（wire v2 source book / npc_dialogue）定向回归。
    ///
    /// 覆盖合同关键点：
    /// - 真实数据 data/dialogues/npc_dialogue_A兵团.xml：酒泡氤氲-啤酒 的组选择、
    ///   行字段、$PC/$PC_TITLE 快照替换、$PC_CHAR→heroPortrait、TaskRequirement
    ///   过滤（有/无 taskProgress）与旧 读取NPC对话（通信解析.as:440-461）对拍。
    /// - 派生数据：imageurl 三态、char 的 "#表情" 切分与缺失、heroPortrait 缺席
    ///   回落空静态槽、"角色名" 哨兵不复刻、text 原样透传。
    /// - contentVersion：同源同值、64hex 小写、改内容必漂移、content_drift 拒绝。
    /// - 拒绝面：unknown_source / source_unavailable / group_missing /
    ///   empty_source / content_drift 各自 reason 与判定顺序。
    /// </summary>
    public sealed class NativeDialogueSourceAssemblerTests
    {
        // ── 基建 ────────────────────────────────────────────────

        private sealed class TempProject : IDisposable
        {
            internal readonly string Root;

            internal TempProject(params string[] dialogueFileContents)
            {
                Root = Path.Combine(Path.GetTempPath(),
                    "ndsrc-" + Guid.NewGuid().ToString("N"));
                string dir = Path.Combine(Root, "data", "dialogues");
                Directory.CreateDirectory(dir);

                var items = new List<string>();
                for (int i = 0; i < dialogueFileContents.Length; i++)
                {
                    string name = "npc_dialogue_t" + i + ".xml";
                    File.WriteAllText(Path.Combine(dir, name), dialogueFileContents[i]);
                    items.Add("  <items>" + name + "</items>");
                }
                File.WriteAllText(Path.Combine(dir, "list.xml"),
                    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<root>\n"
                    + string.Join("\n", items) + "\n</root>\n");
            }

            internal TempProject WithFile(string fileName, string content)
            {
                string dir = Path.Combine(Root, "data", "dialogues");
                File.WriteAllText(Path.Combine(dir, fileName), content);
                string list = File.ReadAllText(Path.Combine(dir, "list.xml"));
                list = list.Replace("</root>", "  <items>" + fileName + "</items>\n</root>");
                File.WriteAllText(Path.Combine(dir, "list.xml"), list);
                return this;
            }

            public void Dispose()
            {
                try { Directory.Delete(Root, true); } catch { }
            }
        }

        /// <summary>从测试输出目录向上找到仓库内的真实数据文件。</summary>
        private static string RepoFile(string relative)
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null)
            {
                string candidate = Path.Combine(dir.FullName, relative);
                if (File.Exists(candidate)) return candidate;
                dir = dir.Parent;
            }
            throw new FileNotFoundException(relative);
        }

        private static JObject Snapshot()
        {
            return new JObject
            {
                ["playerName"] = "测试玩家",
                ["heroTitle"] = "佣兵头衔",
                ["advanceKey"] = 13,
                ["heroPortrait"] = new JObject
                {
                    ["kind"] = "doll", ["key"] = "hero", ["expression"] = "普通",
                    ["appearance"] = new JObject
                    {
                        ["gender"] = "男", ["face"] = "1", ["hair"] = "短发"
                    }
                }
            };
        }

        private static JObject Ref(string key, string version,
            int? group = null, int? taskProgress = null)
        {
            var r = new JObject
            {
                ["type"] = "npc_dialogue",
                ["key"] = key,
                ["contentVersion"] = version
            };
            if (group.HasValue) r["group"] = group.Value;
            if (taskProgress.HasValue) r["taskProgress"] = taskProgress.Value;
            return r;
        }

        private static string VersionOf(DataCache cache)
        {
            return NativeDialogueSourceAssembler.ComputeContentVersion(cache.GetNpcDialogues());
        }

        private static bool Try(NativeDialogueSourceAssembler asm, JObject sourceRef,
            JObject snapshot, out List<JObject> lines, out string reason)
        {
            bool ok = asm.TryAssemble(sourceRef, snapshot, out lines,
                out int rowCount, out reason);
            if (ok) Assert.Equal(lines.Count, rowCount);
            else { Assert.Null(lines); Assert.Equal(0, rowCount); Assert.NotNull(reason); }
            return ok;
        }

        // ── 真实数据：装配正确性 ────────────────────────────────

        [Fact]
        public void BeerGroupAssemblesLinesWithSnapshotPlaceholders()
        {
            using var project = new TempProject(
                File.ReadAllText(RepoFile("data/dialogues/npc_dialogue_A兵团.xml")));
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);

            Assert.True(Try(asm, Ref("酒泡氤氲-啤酒", VersionOf(cache), group: 0),
                Snapshot(), out var lines, out _));
            Assert.Equal(5, lines.Count);

            // 第 0 行：普通 NPC，全部原样
            Assert.Equal("酒保", lines[0].Value<string>("name"));
            Assert.Equal("前情报员", lines[0].Value<string>("title"));
            Assert.Equal("多谢惠顾，这个如何？", lines[0].Value<string>("text"));
            Assert.Equal("static", lines[0]["portrait"].Value<string>("kind"));
            Assert.Equal("酒保", lines[0]["portrait"].Value<string>("key"));
            Assert.Equal("普通", lines[0]["portrait"].Value<string>("expression"));
            Assert.Equal("keep", lines[0].Value<string>("imageAction"));
            Assert.Equal("", lines[0].Value<string>("imagePath"));

            // 第 1 行：$PC/$PC_TITLE 用快照值；$PC_CHAR → heroPortrait
            Assert.Equal("测试玩家", lines[1].Value<string>("name"));
            Assert.Equal("佣兵头衔", lines[1].Value<string>("title"));
            Assert.Equal("doll", lines[1]["portrait"].Value<string>("kind"));
            Assert.Equal("hero", lines[1]["portrait"].Value<string>("key"));
            Assert.Equal("男", lines[1]["portrait"]["appearance"].Value<string>("gender"));
            Assert.Equal("味道有点特殊···", lines[1].Value<string>("text"));
        }

        [Fact]
        public void GroupIndexSelectsRequestedGroup()
        {
            using var project = new TempProject(
                File.ReadAllText(RepoFile("data/dialogues/npc_dialogue_A兵团.xml")));
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);
            string version = VersionOf(cache);

            Assert.True(Try(asm, Ref("酒泡氤氲-啤酒", version, group: 1),
                Snapshot(), out var g1, out _));
            Assert.Equal(4, g1.Count);
            Assert.Equal("这里的酒是用大麦作为原料酿造的，然后混了基地的地下水，末日里有这种选择也算难得了。",
                g1[0].Value<string>("text"));

            Assert.True(Try(asm, Ref("酒泡氤氲-啤酒", version, group: 4),
                Snapshot(), out var g4, out _));
            Assert.Equal(3, g4.Count);
            Assert.Equal("（无意间听到了不少新鲜事······也许该把它们记录下来）",
                g4[2].Value<string>("text"));

            // group 缺省 = 0
            Assert.True(Try(asm, Ref("酒泡氤氲-啤酒", version),
                Snapshot(), out var g0, out _));
            Assert.Equal("多谢惠顾，这个如何？", g0[0].Value<string>("text"));
        }

        /// <summary>
        /// 与旧 读取NPC对话 对拍（通信解析.as:452-457）：
        /// `if (总对话[i].TaskRequirement > 主线任务进度) continue` 后按下标取组。
        /// A兵团「酒泡氤氲-啤酒」TaskRequirement 序列 = [0,0,0,22,22]，
        /// 「酒泡氤氲-鸡尾酒」= [22,22,22]。
        /// </summary>
        [Theory]
        [InlineData(-1, 0)]
        [InlineData(0, 3)]
        [InlineData(10, 3)]
        [InlineData(21, 3)]
        [InlineData(22, 5)]
        [InlineData(100, 5)]
        public void TaskProgressFilterMatchesLegacyReader(int progress, int expectedGroups)
        {
            using var project = new TempProject(
                File.ReadAllText(RepoFile("data/dialogues/npc_dialogue_A兵团.xml")));
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);
            string version = VersionOf(cache);

            // 独立复算过滤投影：TR <= progress 的组数（对拍基准）
            var index = cache.GetNpcDialogues();
            int legacyCount = 0;
            foreach (var g in index["酒泡氤氲-啤酒"])
                if (g.TaskRequirement <= progress) legacyCount++;
            Assert.Equal(expectedGroups, legacyCount);

            // 最后一组可达、越界即 group_missing（空投影同样走 group_missing）
            if (expectedGroups > 0)
            {
                Assert.True(Try(asm,
                    Ref("酒泡氤氲-啤酒", version, group: expectedGroups - 1, taskProgress: progress),
                    Snapshot(), out _, out _));
            }
            Assert.False(Try(asm,
                Ref("酒泡氤氲-啤酒", version, group: expectedGroups, taskProgress: progress),
                Snapshot(), out _, out string reason));
            Assert.Equal("group_missing", reason);
        }

        [Fact]
        public void MissingTaskProgressDisablesFilter()
        {
            using var project = new TempProject(
                File.ReadAllText(RepoFile("data/dialogues/npc_dialogue_A兵团.xml")));
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);
            string version = VersionOf(cache);

            // 不带 taskProgress：全部 5 组可选，含 TR=22 的组
            Assert.True(Try(asm, Ref("酒泡氤氲-啤酒", version, group: 4),
                Snapshot(), out var lines, out _));
            Assert.Equal(3, lines.Count);

            // 鸡尾酒 3 组全 TR=22：progress=0 → 空投影 → group_missing；
            // 不带 progress → 不过滤
            Assert.False(Try(asm, Ref("酒泡氤氲-鸡尾酒", version, group: 0, taskProgress: 0),
                Snapshot(), out _, out string filtered));
            Assert.Equal("group_missing", filtered);
            Assert.True(Try(asm, Ref("酒泡氤氲-鸡尾酒", version, group: 2),
                Snapshot(), out var cocktail, out _));
            Assert.Equal(6, cocktail.Count);

            // 非整数 taskProgress 按 0 处理（最严过滤，不放出高门槛组）
            var malformed = Ref("酒泡氤氲-鸡尾酒", version, group: 0);
            malformed["taskProgress"] = "22";
            Assert.False(Try(asm, malformed, Snapshot(), out _, out string strict));
            Assert.Equal("group_missing", strict);
        }

        // ── 派生数据：行字段语义 ────────────────────────────────

        private const string DerivedXml =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<root><Dialogues>\n" +
            "  <Name>测试NPC</Name>\n" +
            "  <Dialogue id=\"0\">\n" +
            "    <SubDialogue id=\"0\"><Name>甲</Name><Title>职</Title>" +
            "<Char>酒保#微笑</Char><Text>带表情的静态立绘</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"1\"><Name>乙</Name><Title>职</Title>" +
            "<Char>酒保#</Char><Text>空表情回落</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"2\"><Name>丙</Name><Title>职</Title>" +
            "<Text>没有 Char 字段</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"3\"><Name>丁</Name><Title>职</Title>" +
            "<Char>#怒</Char><Text>空 base 带表情</Text></SubDialogue>\n" +
            "  </Dialogue>\n" +
            "</Dialogues></root>\n";

        [Fact]
        public void StaticCharExpressionSplitAndMissingChar()
        {
            using var project = new TempProject(DerivedXml);
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);

            Assert.True(Try(asm, Ref("测试NPC", VersionOf(cache), group: 0),
                Snapshot(), out var lines, out _));
            Assert.Equal(4, lines.Count);

            Assert.Equal("酒保", lines[0]["portrait"].Value<string>("key"));
            Assert.Equal("微笑", lines[0]["portrait"].Value<string>("expression"));

            Assert.Equal("酒保", lines[1]["portrait"].Value<string>("key"));
            Assert.Equal("普通", lines[1]["portrait"].Value<string>("expression"));

            Assert.Equal("static", lines[2]["portrait"].Value<string>("kind"));
            Assert.Equal("", lines[2]["portrait"].Value<string>("key"));

            Assert.Equal("", lines[3]["portrait"].Value<string>("key"));
            Assert.Equal("怒", lines[3]["portrait"].Value<string>("expression"));
        }

        private const string HeroXml =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<root><Dialogues>\n" +
            "  <Name>测试NPC</Name>\n" +
            "  <Dialogue id=\"0\">\n" +
            "    <SubDialogue id=\"0\"><Name>$PC</Name><Title>$PC_TITLE</Title>" +
            "<Char>$PC_CHAR</Char><Text>占位行</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"1\"><Name>$PC</Name><Title>$PC_TITLE</Title>" +
            "<Char>玩家</Char><Text>玩家占位</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"2\"><Name>$PC</Name><Title>$PC_TITLE</Title>" +
            "<Char>主角模板</Char><Text>主角模板占位</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"3\"><Name>$PC</Name><Title>$PC_TITLE</Title>" +
            "<Char>$PC_CHAR#惊讶</Char><Text>带表情的 hero</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"4\"><Name>角色名</Name><Title>$PC_TITLE</Title>" +
            "<Char>$PC_CHAR</Char><Text>哨兵不复刻</Text></SubDialogue>\n" +
            "  </Dialogue>\n" +
            "</Dialogues></root>\n";

        [Fact]
        public void HeroPlaceholdersUseSnapshotHeroPortrait()
        {
            using var project = new TempProject(HeroXml);
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);
            JObject snapshot = Snapshot();

            Assert.True(Try(asm, Ref("测试NPC", VersionOf(cache), group: 0),
                snapshot, out var lines, out _));
            Assert.Equal(5, lines.Count);

            for (int i = 0; i < 4; i++)
            {
                Assert.Equal("doll", lines[i]["portrait"].Value<string>("kind"));
                Assert.Equal("hero", lines[i]["portrait"].Value<string>("key"));
                Assert.True(JToken.DeepEquals(snapshot["heroPortrait"]["appearance"],
                    lines[i]["portrait"]["appearance"]));
            }
            Assert.Equal("普通", lines[0]["portrait"].Value<string>("expression"));
            // 行内显式 #expr 覆盖快照 expression
            Assert.Equal("惊讶", lines[3]["portrait"].Value<string>("expression"));

            // "角色名" 哨兵不复刻：原样透传
            Assert.Equal("角色名", lines[4].Value<string>("name"));

            // 输出行不持有快照引用：事后改快照，已装配行不变
            snapshot["heroPortrait"]["appearance"]["gender"] = "女";
            Assert.Equal("男", lines[0]["portrait"]["appearance"].Value<string>("gender"));
        }

        [Fact]
        public void MissingHeroPortraitFallsBackToEmptyStaticSlot()
        {
            using var project = new TempProject(HeroXml);
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);
            var snapshot = Snapshot();
            snapshot.Remove("heroPortrait");

            Assert.True(Try(asm, Ref("测试NPC", VersionOf(cache), group: 0),
                snapshot, out var lines, out _));
            Assert.Equal("static", lines[0]["portrait"].Value<string>("kind"));
            Assert.Equal("", lines[0]["portrait"].Value<string>("key"));
            // 行仍保留（保行不拒句），name 占位符照常替换
            Assert.Equal("测试玩家", lines[0].Value<string>("name"));
        }

        private const string ImageXml =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<root><Dialogues>\n" +
            "  <Name>测试NPC</Name>\n" +
            "  <Dialogue id=\"0\">\n" +
            "    <SubDialogue id=\"0\"><Name>甲</Name><Char>甲</Char>" +
            "<Text>无 imageurl</Text></SubDialogue>\n" +
            "    <SubDialogue id=\"1\"><Name>乙</Name><Char>乙</Char>" +
            "<Text>显式关图</Text><ImageUrl>close</ImageUrl></SubDialogue>\n" +
            "    <SubDialogue id=\"2\"><Name>丙</Name><Char>丙</Char>" +
            "<Text>换新图</Text><ImageUrl>flashswf/images/task_images/x.png</ImageUrl></SubDialogue>\n" +
            "    <SubDialogue id=\"3\"><Name>丁</Name><Char>丁</Char>" +
            "<Text>空串</Text><ImageUrl></ImageUrl></SubDialogue>\n" +
            "    <SubDialogue id=\"4\"><Name>戊</Name><Char>戊</Char>" +
            "<Text>$PC 在正文不替换</Text></SubDialogue>\n" +
            "  </Dialogue>\n" +
            "</Dialogues></root>\n";

        [Fact]
        public void ImageurlThreeStatesMatchV1SendLine()
        {
            using var project = new TempProject(ImageXml);
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);

            Assert.True(Try(asm, Ref("测试NPC", VersionOf(cache), group: 0),
                Snapshot(), out var lines, out _));
            Assert.Equal(5, lines.Count);

            Assert.Equal("keep", lines[0].Value<string>("imageAction"));
            Assert.Equal("", lines[0].Value<string>("imagePath"));

            Assert.Equal("clear", lines[1].Value<string>("imageAction"));
            Assert.Equal("", lines[1].Value<string>("imagePath"));

            Assert.Equal("show", lines[2].Value<string>("imageAction"));
            Assert.Equal("flashswf/images/task_images/x.png",
                lines[2].Value<string>("imagePath"));

            // 空串 imageurl 与缺省同态：keep
            Assert.Equal("keep", lines[3].Value<string>("imageAction"));

            // text 原样透传，不过占位符
            Assert.Equal("$PC 在正文不替换", lines[4].Value<string>("text"));
        }

        // ── contentVersion ──────────────────────────────────────

        [Fact]
        public void ContentVersionIsDeterministicAndDetectsDrift()
        {
            using var project = new TempProject(
                File.ReadAllText(RepoFile("data/dialogues/npc_dialogue_A兵团.xml")));
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);

            string version = VersionOf(cache);
            Assert.Matches("^[0-9a-f]{64}$", version);
            // 同源同值：同一缓存重算、新缓存重载同一份文件，结果一致
            Assert.Equal(version, VersionOf(cache));
            Assert.Equal(version, VersionOf(new DataCache(project.Root)));

            // 版本不符 → content_drift（先于 group_missing：内容身份先于一组一行）
            Assert.False(Try(asm, Ref("酒泡氤氲-啤酒", version.Replace('a', 'b'), group: 99),
                Snapshot(), out _, out string drift));
            Assert.Equal("content_drift", drift);
            var noVersion = Ref("酒泡氤氲-啤酒", version);
            noVersion.Remove("contentVersion");
            Assert.False(Try(asm, noVersion, Snapshot(), out _, out drift));
            Assert.Equal("content_drift", drift);

            // 改一个正文字符 → 新解析数据 → 新版本；旧版本号被拒
            string path = Path.Combine(project.Root, "data", "dialogues",
                "npc_dialogue_t0.xml");
            string original = File.ReadAllText(path);
            File.WriteAllText(path, original.Replace("多谢惠顾", "多谢光顾"));
            var cache2 = new DataCache(project.Root);
            string version2 = VersionOf(cache2);
            Assert.NotEqual(version, version2);
            var asm2 = new NativeDialogueSourceAssembler(cache2);
            Assert.False(Try(asm2, Ref("酒泡氤氲-啤酒", version),
                Snapshot(), out _, out drift));
            Assert.Equal("content_drift", drift);
            Assert.True(Try(asm2, Ref("酒泡氤氲-啤酒", version2, group: 0),
                Snapshot(), out _, out _));
        }

        // ── 拒绝面 ──────────────────────────────────────────────

        [Fact]
        public void RejectReasonMatrix()
        {
            using var project = new TempProject(
                File.ReadAllText(RepoFile("data/dialogues/npc_dialogue_A兵团.xml")));
            var cache = new DataCache(project.Root);
            var asm = new NativeDialogueSourceAssembler(cache);
            string version = VersionOf(cache);

            // unknown_source：type 缺失 / 其他源类型 / 整个 sourceRef 为 null
            Assert.False(Try(asm, null, Snapshot(), out _, out string reason));
            Assert.Equal("unknown_source", reason);
            var noType = Ref("酒泡氤氲-啤酒", version); noType.Remove("type");
            Assert.False(Try(asm, noType, Snapshot(), out _, out reason));
            Assert.Equal("unknown_source", reason);
            var otherType = Ref("酒泡氤氲-啤酒", version);
            otherType["type"] = "stage_dialogue";
            Assert.False(Try(asm, otherType, Snapshot(), out _, out reason));
            Assert.Equal("unknown_source", reason);

            // source_unavailable：data 目录缺失 → 索引加载失败（DataCache 缓存错误态）
            string bare = Path.Combine(Path.GetTempPath(),
                "ndsrc-bare-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(bare);
            try
            {
                var deadAsm = new NativeDialogueSourceAssembler(new DataCache(bare));
                Assert.False(Try(deadAsm, Ref("x", version), Snapshot(), out _, out reason));
                Assert.Equal("source_unavailable", reason);
            }
            finally { try { Directory.Delete(bare, true); } catch { } }

            // group_missing：key 不存在 / 越界 / 负数 / 非整数 group
            Assert.False(Try(asm, Ref("不存在的NPC", version), Snapshot(), out _, out reason));
            Assert.Equal("group_missing", reason);
            Assert.False(Try(asm, Ref("酒泡氤氲-啤酒", version, group: 99),
                Snapshot(), out _, out reason));
            Assert.Equal("group_missing", reason);
            Assert.False(Try(asm, Ref("酒泡氤氲-啤酒", version, group: -1),
                Snapshot(), out _, out reason));
            Assert.Equal("group_missing", reason);
            var badGroup = Ref("酒泡氤氲-啤酒", version);
            badGroup["group"] = "0";
            Assert.False(Try(asm, badGroup, Snapshot(), out _, out reason));
            Assert.Equal("group_missing", reason);

            // empty_source：Dialogue 存在但没有任何 SubDialogue
            const string emptyGroupXml =
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                "<root><Dialogues>\n" +
                "  <Name>空NPC</Name>\n" +
                "  <Dialogue id=\"0\"></Dialogue>\n" +
                "</Dialogues></root>\n";
            using var emptyGroup = new TempProject(emptyGroupXml);
            var emptyCache = new DataCache(emptyGroup.Root);
            var emptyAsm = new NativeDialogueSourceAssembler(emptyCache);
            Assert.False(Try(emptyAsm, Ref("空NPC", VersionOf(emptyCache)),
                Snapshot(), out _, out reason));
            Assert.Equal("empty_source", reason);
        }
    }
}
