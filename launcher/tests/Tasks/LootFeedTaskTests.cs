using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class LootFeedTaskTests
    {
        private static JObject Payload(object kind, object name, object count,
            object source = null, object icon = null)
        {
            var p = new JObject();
            if (kind != null) p["kind"] = JToken.FromObject(kind);
            if (name != null) p["name"] = JToken.FromObject(name);
            if (count != null) p["count"] = JToken.FromObject(count);
            if (source != null) p["source"] = JToken.FromObject(source);
            if (icon != null) p["icon"] = JToken.FromObject(icon);
            return p;
        }

        [Fact]
        public void TryParse_ValidPayload_PassesThrough()
        {
            string kind, name, source, icon;
            long count;
            bool ok = LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 3, "pickup", "急救包"),
                out kind, out name, out count, out source, out icon);

            Assert.True(ok);
            Assert.Equal("item", kind);
            Assert.Equal("急救包", name);
            Assert.Equal(3, count);
            Assert.Equal("pickup", source);
            Assert.Equal("急救包", icon);
        }

        [Fact]
        public void TryParse_NullPayload_Rejected()
        {
            string kind, name, source, icon;
            long count;
            Assert.False(LootFeedTask.TryParsePayload(
                null, out kind, out name, out count, out source, out icon));
        }

        [Theory]
        [InlineData("gold")]
        [InlineData("KILL")]
        [InlineData("")]
        public void TryParse_UnknownKind_Rejected(string badKind)
        {
            string kind, name, source, icon;
            long count;
            Assert.False(LootFeedTask.TryParsePayload(
                Payload(badKind, "急救包", 1),
                out kind, out name, out count, out source, out icon));
        }

        [Theory]
        [InlineData("money")]
        [InlineData("kpoint")]
        [InlineData("intel")]
        [InlineData("item")]
        [InlineData("equip")]
        [InlineData("kill")]
        public void TryParse_AllWhitelistedKinds_Accepted(string goodKind)
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload(goodKind, "金钱", 1),
                out kind, out name, out count, out source, out icon));
            Assert.Equal(goodKind, kind);
        }

        [Fact]
        public void TryParse_MissingOrOverlongName_Rejected()
        {
            string kind, name, source, icon;
            long count;
            Assert.False(LootFeedTask.TryParsePayload(
                Payload("item", null, 1),
                out kind, out name, out count, out source, out icon));
            Assert.False(LootFeedTask.TryParsePayload(
                Payload("item", new string('甲', 65), 1),
                out kind, out name, out count, out source, out icon));
        }

        [Theory]
        [InlineData(0)]
        [InlineData(-3)]
        public void TryParse_NonPositiveCount_Rejected(long badCount)
        {
            string kind, name, source, icon;
            long count;
            Assert.False(LootFeedTask.TryParsePayload(
                Payload("money", "金钱", badCount),
                out kind, out name, out count, out source, out icon));
        }

        [Fact]
        public void TryParse_CountClampedToMax()
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("money", "金钱", 1000000),
                out kind, out name, out count, out source, out icon));
            Assert.Equal(99999, count);
        }

        [Fact]
        public void TryParse_UnknownSource_FallsBackToUnknown()
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1, "cheat"),
                out kind, out name, out count, out source, out icon));
            Assert.Equal("unknown", source);
        }

        [Theory]
        [InlineData("pickup")]
        [InlineData("level_reward")]
        [InlineData("quest_reward")]
        [InlineData("loot_box")]
        [InlineData("kill")]
        public void TryParse_AllWhitelistedSources_Accepted(string goodSource)
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1, goodSource),
                out kind, out name, out count, out source, out icon));
            Assert.Equal(goodSource, source);
        }

        [Fact]
        public void TryParse_MissingIcon_BecomesNull()
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1),
                out kind, out name, out count, out source, out icon));
            Assert.Null(icon);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(1)]
        [InlineData(2)]
        public void TryParse_KillEliteLevel_AcceptsClosedRange(int expectedRank)
        {
            var payload = Payload("kill", "精英敌人", 1, "kill", "敌人-精英");
            payload["eliteLevel"] = expectedRank;
            string kind, name, source, icon;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll));
            Assert.Equal(expectedRank, eliteLevel);
        }

        [Theory]
        [InlineData(-1)]
        [InlineData(3)]
        [InlineData(99)]
        public void TryParse_InvalidKillEliteLevel_DegradesToOrdinary(int invalidRank)
        {
            var payload = Payload("kill", "敌人", 1, "kill");
            payload["eliteLevel"] = invalidRank;
            string kind, name, source, icon;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll));
            Assert.Equal(0, eliteLevel);
        }

        [Fact]
        public void TryParse_NonIntegerOrNonKillEliteLevel_IsIgnored()
        {
            var malformedKill = Payload("kill", "敌人", 1, "kill");
            malformedKill["eliteLevel"] = "2";
            var nonKill = Payload("item", "急救包", 1, "pickup");
            nonKill["eliteLevel"] = 2;
            string kind, name, source, icon;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                malformedKill, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll));
            Assert.Equal(0, eliteLevel);
            Assert.True(LootFeedTask.TryParsePayload(
                nonKill, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll));
            Assert.Equal(0, eliteLevel);
        }

        [Fact]
        public void TryParse_HugeIntegerEliteLevel_DoesNotDropKillEvent()
        {
            var payload = Payload("kill", "敌人", 1, "kill");
            payload["eliteLevel"] = Newtonsoft.Json.Linq.JToken.Parse(
                "999999999999999999999999999999999999999999");
            string kind, name, source, icon;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll));
            Assert.Equal(0, eliteLevel);
        }

        // ==================== doll 元组（纸娃娃运行时烘焙） ====================

        private sealed class RecordingBakeSink : CF7Launcher.Guardian.Hud.Loot.IDollBakeSink
        {
            public readonly System.Collections.Generic.List<string> Keys =
                new System.Collections.Generic.List<string>();
            public readonly System.Collections.Generic.List<System.Collections.Generic.IReadOnlyDictionary<string, string>> Tuples =
                new System.Collections.Generic.List<System.Collections.Generic.IReadOnlyDictionary<string, string>>();
            public void EnsurePortrait(System.Collections.Generic.IReadOnlyDictionary<string, string> tuple, string key)
            {
                Tuples.Add(tuple);
                Keys.Add(key);
            }
        }

        private static JObject DollPayload(object icon, JObject doll)
        {
            var p = Payload("kill", "主角-男", 1, "kill", icon);
            if (doll != null) p["doll"] = doll;
            return p;
        }

        private static JObject ValidDoll()
        {
            var d = new JObject();
            d["face"] = "女变装-基本脸型";
            d["hair"] = "发型-女式-玫红色马尾";
            d["body"] = "佣兵-战术背心";
            d["gender"] = "女";
            return d;
        }

        [Fact]
        public void TryParse_DollMissingOrExplicitNull_BecomesNull()
        {
            string kind, name, source, icon;
            long count;
            System.Collections.Generic.Dictionary<string, string> doll;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("kill", "主角-男", 1, "kill"),
                out kind, out name, out count, out source, out icon, out doll));
            Assert.Null(doll);

            var withNull = DollPayload(null, null);
            withNull["doll"] = JValue.CreateNull();
            Assert.True(LootFeedTask.TryParsePayload(
                withNull,
                out kind, out name, out count, out source, out icon, out doll));
            Assert.Null(doll);
        }

        [Theory]
        [InlineData("not-an-object")]
        [InlineData(42)]
        [InlineData(true)]
        public void TryParse_DollNotObject_IgnoredButPayloadAccepted(object badDoll)
        {
            var p = Payload("kill", "主角-男", 1, "kill");
            p["doll"] = JToken.FromObject(badDoll);
            string kind, name, source, icon;
            long count;
            System.Collections.Generic.Dictionary<string, string> doll;
            Assert.True(LootFeedTask.TryParsePayload(
                p, out kind, out name, out count, out source, out icon, out doll));
            Assert.Null(doll);
        }

        [Fact]
        public void TryParse_DollFieldNotString_WholeDollIgnored()
        {
            var d = ValidDoll();
            d["face"] = 42;
            string kind, name, source, icon;
            long count;
            System.Collections.Generic.Dictionary<string, string> doll;
            Assert.True(LootFeedTask.TryParsePayload(
                DollPayload(null, d),
                out kind, out name, out count, out source, out icon, out doll));
            Assert.Null(doll);
        }

        [Fact]
        public void TryParse_DollFieldOverlong_WholeDollIgnored()
        {
            var d = ValidDoll();
            d["body"] = new string('甲', 65);
            string kind, name, source, icon;
            long count;
            System.Collections.Generic.Dictionary<string, string> doll;
            Assert.True(LootFeedTask.TryParsePayload(
                DollPayload(null, d),
                out kind, out name, out count, out source, out icon, out doll));
            Assert.Null(doll);
        }

        [Fact]
        public void TryParse_DollValid_WhitelistFieldsAndDefaults()
        {
            var d = ValidDoll();
            d["unknownField"] = "应被忽略";
            string kind, name, source, icon;
            long count;
            System.Collections.Generic.Dictionary<string, string> doll;
            Assert.True(LootFeedTask.TryParsePayload(
                DollPayload(null, d),
                out kind, out name, out count, out source, out icon, out doll));
            Assert.NotNull(doll);
            // 白名单 10 字段齐全，缺省归一为 ""，多余字段不进入元组
            Assert.Equal(10, doll.Count);
            Assert.False(doll.ContainsKey("unknownField"));
            Assert.Equal("女变装-基本脸型", doll["face"]);
            Assert.Equal("发型-女式-玫红色马尾", doll["hair"]);
            Assert.Equal("佣兵-战术背心", doll["body"]);
            Assert.Equal("女", doll["gender"]);
            Assert.Equal("", doll["mask"]);
            Assert.Equal("", doll["head"]);
            Assert.Equal("", doll["neck"]);
        }

        [Fact]
        public void Handle_KillWithDoll_DerivesIconAndTriggersBake()
        {
            string tempDir = CreateTempDir();
            try
            {
                using (var catalog = new CF7Launcher.Guardian.Hud.Loot.LootIconCatalog(tempDir))
                {
                    var widget = new CF7Launcher.Guardian.Hud.Loot.LootFeedWidget(
                        new System.Windows.Forms.Control(), catalog);
                    var sink = new RecordingBakeSink();
                    var task = new LootFeedTask(widget, sink);

                    var msg = new JObject();
                    msg["payload"] = DollPayload("斗士-26", ValidDoll());
                    Assert.Null(task.Handle(msg));

                    Assert.Single(sink.Keys);
                    Assert.Single(sink.Tuples);
                    // icon 由 doll 单点派生，payload.icon（"斗士-26"）被覆盖
                    var expectedTuple = new System.Collections.Generic.Dictionary<string, string>
                    {
                        { "face", "女变装-基本脸型" }, { "hair", "发型-女式-玫红色马尾" },
                        { "mask", "" }, { "head", "" }, { "body", "佣兵-战术背心" },
                        { "leg", "" }, { "hand", "" }, { "foot", "" },
                        { "neck", "" }, { "gender", "女" }
                    };
                    string expectedKey = CF7Launcher.Guardian.Hud.Loot.DollPortraitKey.Compute(expectedTuple);
                    Assert.Equal(expectedKey, sink.Keys[0]);
                    Assert.StartsWith("纸娃娃-", sink.Keys[0]);
                    Assert.Equal("女", sink.Tuples[0]["gender"]);
                }
            }
            finally
            {
                System.IO.Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public void Handle_KillWithoutDoll_NoBakeTriggered()
        {
            string tempDir = CreateTempDir();
            try
            {
                using (var catalog = new CF7Launcher.Guardian.Hud.Loot.LootIconCatalog(tempDir))
                {
                    var widget = new CF7Launcher.Guardian.Hud.Loot.LootFeedWidget(
                        new System.Windows.Forms.Control(), catalog);
                    var sink = new RecordingBakeSink();
                    var task = new LootFeedTask(widget, sink);

                    var msg = new JObject();
                    msg["payload"] = Payload("kill", "敌人-92式终结者", 1, "kill", "敌人-92式终结者");
                    Assert.Null(task.Handle(msg));
                    Assert.Empty(sink.Keys);
                }
            }
            finally
            {
                System.IO.Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public void Handle_NonKillKindWithDoll_NoBakeTriggered()
        {
            string tempDir = CreateTempDir();
            try
            {
                using (var catalog = new CF7Launcher.Guardian.Hud.Loot.LootIconCatalog(tempDir))
                {
                    var widget = new CF7Launcher.Guardian.Hud.Loot.LootFeedWidget(
                        new System.Windows.Forms.Control(), catalog);
                    var sink = new RecordingBakeSink();
                    var task = new LootFeedTask(widget, sink);

                    var p = Payload("item", "急救包", 1, "pickup");
                    p["doll"] = ValidDoll();
                    var msg = new JObject();
                    msg["payload"] = p;
                    Assert.Null(task.Handle(msg));
                    // doll 仅在 kind=="kill" 时派生图标/触发烘焙
                    Assert.Empty(sink.Keys);
                }
            }
            finally
            {
                System.IO.Directory.Delete(tempDir, true);
            }
        }

        private static string CreateTempDir()
        {
            string dir = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(), "cf7-loot-feed-test-" + System.Guid.NewGuid().ToString("N"));
            System.IO.Directory.CreateDirectory(dir);
            return dir;
        }
    }
}
