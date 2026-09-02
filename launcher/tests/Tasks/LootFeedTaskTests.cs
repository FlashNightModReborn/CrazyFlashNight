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

        private static JObject VersionOnePayload(
            string kind, string name, long count, string source)
        {
            JObject payload = Payload(kind, name, count, source);
            payload["v"] = 1;
            payload["direction"] = kind == "kill" ? "neutral" : "gain";
            payload["operationId"] = "test-operation";
            payload["itemKey"] = name;
            return payload;
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
        [InlineData("material")]
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
        public void TryParse_CountWithinSafeIntegerRange_RemainsExact()
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("money", "金钱", 1000000),
                out kind, out name, out count, out source, out icon));
            Assert.Equal(1000000, count);
        }

        [Fact]
        public void TryParse_UnknownSource_FallsBackToUnknown()
        {
            string kind, name, source, icon;
            long count;
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1, "not_registered"),
                out kind, out name, out count, out source, out icon));
            Assert.Equal("unknown", source);
        }

        [Theory]
        [InlineData("pickup")]
        [InlineData("level_reward")]
        [InlineData("quest_reward")]
        [InlineData("achievement_reward")]
        [InlineData("quest_turn_in")]
        [InlineData("inventory_discard")]
        [InlineData("equipment_tuning")]
        [InlineData("loot_box")]
        [InlineData("npc_shop_purchase")]
        [InlineData("npc_shop_sale")]
        [InlineData("kshop_purchase")]
        [InlineData("kshop_claim")]
        [InlineData("crafting")]
        [InlineData("consumable_effect")]
        [InlineData("pet_service")]
        [InlineData("mercenary_service")]
        [InlineData("reload")]
        [InlineData("skill_cost")]
        [InlineData("weapon_cost")]
        [InlineData("item_use")]
        [InlineData("task_entry")]
        [InlineData("arena_entry")]
        [InlineData("arena_reward")]
        [InlineData("base_upgrade")]
        [InlineData("tavern_purchase")]
        [InlineData("vehicle_service")]
        [InlineData("gym_training")]
        [InlineData("appearance_service")]
        [InlineData("player_revive")]
        [InlineData("cheat")]
        [InlineData("system_reward")]
        [InlineData("reward_inbox")]
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
        public void TryParse_FractionalOrStringCount_Rejected()
        {
            string kind, name, source, icon;
            long count;
            Assert.False(LootFeedTask.TryParsePayload(
                Payload("money", "金钱", 1.5),
                out kind, out name, out count, out source, out icon));
            Assert.False(LootFeedTask.TryParsePayload(
                Payload("money", "金钱", "2"),
                out kind, out name, out count, out source, out icon));
        }

        [Fact]
        public void TryParse_IntegerBeyondInt64_ClampsToJavascriptSafeMaximum()
        {
            var payload = Payload("money", "金钱", 1);
            payload["count"] = JToken.Parse("999999999999999999999999999999999999999999");
            string kind, name, source, icon;
            long count;

            Assert.True(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon));
            Assert.Equal(9007199254740991L, count);
        }

        [Fact]
        public void TryParse_VersionOneCountBeyondJavascriptSafeMaximumRejected()
        {
            var payload = VersionOnePayload("money", "金钱", 1, "pickup");
            payload["count"] = JToken.Parse("9007199254740992");
            string kind, name, source, icon;
            long count;

            Assert.False(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon));
        }

        [Fact]
        public void TryParse_BidirectionalMetadata_PreservesPositiveMagnitude()
        {
            var payload = Payload("item", "步枪弹匣", 2, "reload", "步枪弹匣");
            payload["direction"] = "loss";
            payload["tier"] = "二阶";
            payload["operationId"] = "reload-17";
            payload["mergeScope"] = "reload-17";
            payload["reason"] = "reload";
            payload["itemKey"] = "5.56mm弹匣";
            string kind, name, source, icon, direction, tier, operationId, mergeScope, reason, itemKey;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason, out itemKey));
            Assert.Equal("loss", direction);
            Assert.Equal(2, count);
            Assert.Equal("二阶", tier);
            Assert.Equal("reload-17", operationId);
            Assert.Equal("reload-17", mergeScope);
            Assert.Equal("reload", reason);
            Assert.Equal("5.56mm弹匣", itemKey);
        }

        [Fact]
        public void TryParse_VersionOneAcceptedButUnknownOrMalformedVersionRejected()
        {
            string kind, name, source, icon;
            long count;
            var current = VersionOnePayload("item", "急救包", 1, "pickup");
            Assert.True(LootFeedTask.TryParsePayload(
                current, out kind, out name, out count, out source, out icon));

            current["v"] = 2;
            Assert.False(LootFeedTask.TryParsePayload(
                current, out kind, out name, out count, out source, out icon));
            current["v"] = "1";
            Assert.False(LootFeedTask.TryParsePayload(
                current, out kind, out name, out count, out source, out icon));
            current["v"] = JValue.CreateNull();
            Assert.False(LootFeedTask.TryParsePayload(
                current, out kind, out name, out count, out source, out icon));
        }

        [Theory]
        [InlineData("kind")]
        [InlineData("name")]
        [InlineData("source")]
        [InlineData("direction")]
        [InlineData("icon")]
        [InlineData("tier")]
        [InlineData("operationId")]
        [InlineData("mergeScope")]
        [InlineData("reason")]
        [InlineData("itemKey")]
        public void TryParse_VersionOnePresentNonStringTextRejected(string propertyName)
        {
            string kind, name, source, icon;
            long count;
            var payload = VersionOnePayload("item", "急救包", 1, "pickup");
            payload[propertyName] = 7;

            Assert.False(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon));
        }

        [Fact]
        public void TryParse_PresentOverlongIdentityMetadataRejected()
        {
            string kind, name, source, icon;
            long count;
            var payload = VersionOnePayload("item", "急救包", 1, "pickup");
            payload["operationId"] = new string('x', 97);

            Assert.False(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon));
        }

        [Fact]
        public void DedupeKey_DistinguishesCommittedEffectsWithinOneOperation()
        {
            string material = LootFeedTask.BuildDedupeIdentity(
                "craft-17", "loss", "material", "铁片", null,
                "crafting", "material_cost", "operation");
            string fee = LootFeedTask.BuildDedupeIdentity(
                "craft-17", "loss", "material", "铁片", null,
                "crafting", "service_fee", "operation");
            string otherScope = LootFeedTask.BuildDedupeIdentity(
                "craft-17", "loss", "material", "铁片", null,
                "crafting", "material_cost", "separate-card");

            Assert.NotEqual(material, fee);
            Assert.NotEqual(material, otherScope);
        }

        [Fact]
        public void TryParse_LegacyPayload_UsesDisplayNameAsFallbackItemKey()
        {
            string kind, name, source, icon, direction, tier, operationId, mergeScope, reason, itemKey;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1, "pickup"),
                out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason, out itemKey));
            Assert.Equal("急救包", itemKey);
        }

        [Theory]
        [InlineData("source")]
        [InlineData("direction")]
        [InlineData("operationId")]
        [InlineData("itemKey")]
        public void TryParse_VersionOneMissingRequiredIdentityField_Rejected(
            string propertyName)
        {
            string kind, name, source, icon;
            long count;
            JObject payload = VersionOnePayload("item", "急救包", 1, "pickup");
            payload.Remove(propertyName);

            Assert.False(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon));
        }

        [Fact]
        public void TryParse_VersionOneUnknownSourceRejected_LegacyStillDegrades()
        {
            string kind, name, source, icon;
            long count;
            JObject current = VersionOnePayload(
                "item", "急救包", 1, "not_registered");
            Assert.False(LootFeedTask.TryParsePayload(
                current, out kind, out name, out count, out source, out icon));

            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1, "not_registered"),
                out kind, out name, out count, out source, out icon));
            Assert.Equal("unknown", source);
        }

        [Theory]
        [InlineData("neutral", "item")]
        [InlineData("loss", "kill")]
        [InlineData("gain", "kill")]
        [InlineData("sideways", "item")]
        public void TryParse_InvalidDirectionKindCombination_Rejected(
            string directionValue, string kindValue)
        {
            var payload = Payload(kindValue, "目标", 1,
                kindValue == "kill" ? "kill" : "pickup");
            payload["direction"] = directionValue;
            string kind, name, source, icon, direction, tier, operationId, mergeScope, reason;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.False(LootFeedTask.TryParsePayload(
                payload, out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason));
        }

        [Fact]
        public void TryParse_LegacyDirection_DefaultsByKind()
        {
            string kind, name, source, icon, direction, tier, operationId, mergeScope, reason;
            long count;
            int eliteLevel;
            System.Collections.Generic.Dictionary<string, string> doll;

            Assert.True(LootFeedTask.TryParsePayload(
                Payload("item", "急救包", 1, "pickup"),
                out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason));
            Assert.Equal("gain", direction);
            Assert.True(LootFeedTask.TryParsePayload(
                Payload("kill", "敌人", 1, "kill"),
                out kind, out name, out count, out source, out icon,
                out eliteLevel, out doll, out direction, out tier,
                out operationId, out mergeScope, out reason));
            Assert.Equal("neutral", direction);
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

        [Fact]
        public void Handle_DedupeWindowDropsExactReplayAndStaysBounded()
        {
            string tempDir = CreateTempDir();
            try
            {
                using (var catalog = new CF7Launcher.Guardian.Hud.Loot.LootIconCatalog(tempDir))
                {
                    var widget = new CF7Launcher.Guardian.Hud.Loot.LootFeedWidget(
                        new System.Windows.Forms.Control(), catalog);
                    var task = new LootFeedTask(widget);
                    for (int i = 0; i < 513; i++)
                    {
                        var payload = VersionOnePayload("item", "急救包", 1, "pickup");
                        payload["operationId"] = "pickup-" + i;
                        var message = new JObject { ["payload"] = payload };
                        task.Handle(message);
                        if (i == 0) task.Handle((JObject)message.DeepClone());
                    }

                    Assert.Equal(512, task.DedupeEntryCountForTest);
                }
            }
            finally
            {
                System.IO.Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public void Handle_DivergentReplayForSameCommittedEffectIsDropped()
        {
            string tempDir = CreateTempDir();
            try
            {
                using (var catalog = new CF7Launcher.Guardian.Hud.Loot.LootIconCatalog(tempDir))
                {
                    var widget = new CF7Launcher.Guardian.Hud.Loot.LootFeedWidget(
                        new System.Windows.Forms.Control(), catalog);
                    var task = new LootFeedTask(widget);
                    JObject payload = VersionOnePayload("item", "急救包", 1, "pickup");
                    payload["operationId"] = "pickup-conflict";
                    task.Handle(new JObject { ["payload"] = payload });

                    JObject conflicting = (JObject)payload.DeepClone();
                    conflicting["count"] = 2;
                    task.Handle(new JObject { ["payload"] = conflicting });

                    Assert.Equal(1, task.DedupeEntryCountForTest);
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
