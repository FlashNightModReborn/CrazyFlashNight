using System.Linq;
using Xunit;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public class LootFeedModelTests
    {
        private static LootFeedModel NewModel()
        {
            return new LootFeedModel();
        }

        [Fact]
        public void Merge_SameSourceAndRank_AccumulatesWithoutReordering()
        {
            var model = NewModel();
            model.Add("item", "急救包", "急救包", 1, "pickup");
            model.Add("item", "绷带", "绷带", 1, "pickup");
            long firstSequence = model.Cards[0].Sequence;
            long secondSequence = model.Cards[1].Sequence;

            model.Add("item", "急救包", "急救包", 2, "pickup");

            Assert.Equal(2, model.ActiveCount);
            Assert.Equal(3, model.Cards[0].Count);
            Assert.Equal(firstSequence, model.Cards[0].Sequence);
            Assert.Equal(secondSequence, model.Cards[1].Sequence);
        }

        [Fact]
        public void VisualMerge_SeparatesSchedulingPolicyAndEliteLevel()
        {
            var model = NewModel();
            model.Add("item", "奖励箱", "奖励箱", 1, "pickup");
            model.Add("item", "奖励箱", "奖励箱", 1, "quest_reward");
            model.Add("kill", "左轮", "敌人-左轮", 1, "kill", 0);
            model.Add("kill", "左轮", "敌人-左轮", 1, "kill", 1);
            model.Add("kill", "左轮", "敌人-左轮", 1, "kill", 2);

            Assert.Equal(5, model.ActiveCount);
            Assert.Equal(new[] { 0, 1, 2 },
                model.Cards.Where(card => card.Kind == "kill").Select(card => card.EliteLevel).ToArray());
        }

        [Fact]
        public void VisualMerge_CombinesRawSourcesWithEqualPolicyAndIsolatesUnknown()
        {
            var standard = NewModel();
            standard.Add("item", "急救包", "急救包", 1, "pickup", 0,
                "gain", null, "急救包");
            standard.Add("item", "急救包", "急救包", 1, "npc_shop_purchase", 0,
                "gain", null, "急救包");
            Assert.Equal(2, Assert.Single(standard.Cards).Count);

            var guaranteed = NewModel();
            guaranteed.Add("item", "奖励箱", "奖励箱", 1, "quest_reward", 0,
                "gain", null, "奖励箱");
            guaranteed.Add("item", "奖励箱", "奖励箱", 1, "level_reward", 0,
                "gain", null, "奖励箱");
            Assert.Equal(2, Assert.Single(guaranteed.Cards).Count);

            var unknown = NewModel();
            unknown.Add("item", "急救包", "急救包", 1, "pickup", 0,
                "gain", null, "急救包");
            unknown.Add("item", "急救包", "急救包", 1, "unknown", 0,
                "gain", null, "急救包");
            Assert.Equal(2, unknown.ActiveCount);
        }

        [Fact]
        public void VisualMerge_SeparatesDirectionAndTier()
        {
            var model = NewModel();
            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "gain", null, "步枪弹匣");
            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");
            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");
            model.Add("equip", "战术背心", "战术背心", 1, "quest_reward", 0,
                "gain", "一阶", "战术背心");
            model.Add("equip", "战术背心", "战术背心", 1, "quest_reward", 0,
                "gain", "二阶", "战术背心");

            Assert.Equal(4, model.ActiveCount);
            Assert.Equal(new[] { "gain", "loss", "gain", "gain" },
                model.Cards.Select(card => card.Direction).ToArray());
            LootFeedModel.LootCard loss = Assert.Single(
                model.Cards, card => card.Direction == "loss");
            Assert.Equal(2, loss.Count);
        }

        [Fact]
        public void MergeKey_UsesCanonicalItemKeyInsteadOfDisplayName()
        {
            var model = NewModel();
            model.Add("item", "同名展示", "图标", 1, "pickup", 0,
                "gain", null, "item.alpha");
            model.Add("item", "同名展示", "图标", 1, "pickup", 0,
                "gain", null, "item.beta");

            Assert.Equal(2, model.ActiveCount);
            Assert.Equal(new[] { "item.alpha", "item.beta" },
                model.Cards.Select(card => card.ItemKey).ToArray());
        }

        [Fact]
        public void VisualMerge_SeparatesPresentationEvenWithSameCanonicalItemKey()
        {
            var names = NewModel();
            names.Add("item", "展示甲", "图标", 1, "pickup", 0,
                "gain", null, "canonical.item");
            names.Add("item", "展示乙", "图标", 1, "pickup", 0,
                "gain", null, "canonical.item");
            Assert.Equal(2, names.ActiveCount);

            var icons = NewModel();
            icons.Add("item", "相同展示", "图标甲", 1, "pickup", 0,
                "gain", null, "canonical.item");
            icons.Add("item", "相同展示", "图标乙", 1, "pickup", 0,
                "gain", null, "canonical.item");
            Assert.Equal(2, icons.ActiveCount);
        }

        [Fact]
        public void ReloadLoss_RepeatedOperationsAggregateIntoOneVisibleCard()
        {
            var model = NewModel();
            model.Add("item", "冲锋枪钢芯穿甲弹", "冲锋枪钢芯穿甲弹", 1, "reload", 0,
                "loss", null, "冲锋枪钢芯穿甲弹");
            model.Add("item", "冲锋枪钢芯穿甲弹", "冲锋枪钢芯穿甲弹", 1, "reload", 0,
                "loss", null, "冲锋枪钢芯穿甲弹");

            LootFeedModel.LootCard card = Assert.Single(model.Cards);
            Assert.Equal("loss", card.Direction);
            Assert.Equal(2, card.Count);
            Assert.Equal(LootFeedModel.RetentionClass.ExactAggregate, card.Retention);
            Assert.Equal(LootFeedModel.UrgencyClass.Immediate, card.Urgency);
        }

        [Fact]
        public void Gain_RepeatedCommittedEventsAggregateIntoOneVisibleCard()
        {
            var model = NewModel();
            model.Add("item", "急救包", "急救包", 1, "pickup", 0,
                "gain", null, "急救包");
            model.Add("item", "急救包", "急救包", 1, "npc_shop_purchase", 0,
                "gain", null, "急救包");

            LootFeedModel.LootCard card = Assert.Single(model.Cards);
            Assert.Equal("gain", card.Direction);
            Assert.Equal(2, card.Count);
        }

        [Fact]
        public void ReloadLoss_IsImmediateExactFeedback()
        {
            var model = NewModel();
            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");

            LootFeedModel.LootCard card = Assert.Single(model.Cards);
            Assert.Equal(LootFeedModel.RetentionClass.ExactAggregate, card.Retention);
            Assert.Equal(LootFeedModel.UrgencyClass.Immediate, card.Urgency);
        }

        [Fact]
        public void ReloadLoss_PreemptsFreshPromptPoolImmediately()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards; i++)
                model.Add("item", "任务奖励" + i, "奖励" + i, 1, "quest_reward");

            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");

            Assert.Contains(model.Cards,
                card => card.ItemKey == "步枪弹匣" && card.Direction == "loss"
                    && card.Urgency == LootFeedModel.UrgencyClass.Immediate);
            Assert.Equal(1, model.PendingCount);
            Assert.Equal(LootFeedModel.RetentionClass.Guaranteed,
                model.PendingCards[0].Retention);
        }

        [Fact]
        public void Loss_RepeatedCommittedEventsAggregatePositiveMagnitude()
        {
            var model = NewModel();
            model.Add("item", "能量电池", "能量电池", 1, "skill_cost", 0,
                "loss", null, "能量电池");
            model.Add("item", "能量电池", "能量电池", 2, "skill_cost", 0,
                "loss", null, "能量电池");

            LootFeedModel.LootCard card = Assert.Single(model.Cards);
            Assert.Equal("loss", card.Direction);
            Assert.Equal(3, card.Count);
        }

        [Fact]
        public void Merge_AfterWindow_CreatesAnotherGuaranteedCard()
        {
            var model = NewModel();
            model.Add("item", "任务奖励", "任务奖励", 1, "quest_reward");
            model.Tick(LootFeedModel.MergeWindowMs + 1);
            model.Add("item", "任务奖励", "任务奖励", 1, "quest_reward");

            Assert.Equal(2, model.ActiveCount);
        }

        [Fact]
        public void ReloadLoss_AfterWindow_StartsFreshCardInsteadOfAggregating()
        {
            var model = NewModel();
            model.Add("item", "冲锋枪钢芯穿甲弹", "冲锋枪钢芯穿甲弹", 1,
                "reload", 0, "loss", null, "冲锋枪钢芯穿甲弹");
            long firstSequence = model.Cards[0].Sequence;
            model.Tick(LootFeedModel.MergeWindowMs + 1);
            model.Add("item", "冲锋枪钢芯穿甲弹", "冲锋枪钢芯穿甲弹", 1,
                "reload", 0, "loss", null, "冲锋枪钢芯穿甲弹");

            LootFeedModel.LootCard card = Assert.Single(model.Cards);
            Assert.NotEqual(firstSequence, card.Sequence);
            Assert.Equal(1, card.Count);
        }

        [Fact]
        public void TwelveQuestRewards_QueueLosslesslyAndPendingDoesNotAge()
        {
            var model = NewModel();
            for (int i = 0; i < 12; i++)
                model.Add("item", "任务奖励" + i, "奖励" + i, 1, "quest_reward");

            Assert.Equal(LootFeedModel.MaxVisibleCards, model.ActiveCount);
            Assert.Equal(7, model.PendingCount);
            Assert.All(model.Cards, card => Assert.Equal(
                LootFeedModel.RetentionClass.Guaranteed, card.Retention));

            // 远超首批卡的完整生命周期；第二批此时才激活，因此不能按事件出生时间消失。
            model.Tick(10000);
            Assert.Equal(LootFeedModel.MaxVisibleCards, model.ActiveCount);
            Assert.Equal(2, model.PendingCount);
            Assert.All(model.Cards, card => Assert.Equal(0, card.VisibleAgeMs));

            model.Tick(10000);
            Assert.Equal(2, model.ActiveCount);
            Assert.Equal(0, model.PendingCount);
            Assert.Contains(model.Cards, card => card.Name == "任务奖励10");
            Assert.Contains(model.Cards, card => card.Name == "任务奖励11");
        }

        [Fact]
        public void PendingActivation_RestartsMergeWindow()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards; i++)
                model.Add("item", "任务奖励" + i, "奖励" + i, 1, "quest_reward");
            model.Add("kill", "精英守卫", "精英守卫", 1, "kill", 1);

            model.Tick(10000);
            Assert.Single(model.Cards);
            Assert.Equal("精英守卫", model.Cards[0].Name);

            model.Add("kill", "精英守卫", "精英守卫", 2, "kill", 1);
            Assert.Single(model.Cards);
            Assert.Equal(3, model.Cards[0].Count);
        }

        [Fact]
        public void Pickup_PreemptsOrdinaryKillAfterMinimumExposure()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards; i++)
                model.Add("kill", "杂兵" + i, "杂兵" + i, 1, "kill", 0);

            model.Add("item", "稀有材料", "稀有材料", 1, "pickup");
            Assert.DoesNotContain(model.Cards, card => card.Name == "稀有材料");
            Assert.Equal(1, model.PendingCount);

            model.Tick(LootFeedModel.MinPreemptVisibleMs);

            Assert.Contains(model.Cards, card => card.Name == "稀有材料");
            Assert.Equal(1, model.PendingCount); // 被抢占的杂兵卡仍可恢复显示
        }

        [Fact]
        public void Boss_PreemptsScheduledGuaranteedRewardImmediately()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards; i++)
                model.Add("item", "任务奖励" + i, "奖励" + i, 1, "quest_reward");

            model.Add("kill", "终极首领", "终极首领", 1, "kill", 2);

            LootFeedModel.LootCard boss = Assert.Single(model.Cards, card => card.EliteLevel == 2);
            Assert.Equal(LootFeedModel.RetentionClass.Guaranteed, boss.Retention);
            Assert.Equal(LootFeedModel.UrgencyClass.Immediate, boss.Urgency);
            Assert.Equal(1, model.PendingCount);
            Assert.Equal(LootFeedModel.RetentionClass.Guaranteed, model.PendingCards[0].Retention);
        }

        [Fact]
        public void PriorityReplacement_ReusesVictimSlot()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards; i++)
                model.Add("kill", "杂兵" + i, "杂兵" + i, 1, "kill", 0);
            model.Tick(LootFeedModel.MinPreemptVisibleMs);

            long[] before = model.Cards.Select(card => card.Sequence).ToArray();
            model.Add("kill", "精英守卫", "精英守卫", 1, "kill", 1);
            long[] after = model.Cards.Select(card => card.Sequence).ToArray();

            Assert.NotEqual(before[0], after[0]);
            Assert.Equal(before.Skip(1), after.Skip(1));
            Assert.Equal("精英守卫", model.Cards[0].Name);
        }

        [Fact]
        public void CountVisualUpdate_IsThrottledButLogicalTotalIsExact()
        {
            var model = NewModel();
            model.Add("money", "金钱", "金钱", 1, "pickup");
            for (int i = 0; i < 10; i++)
                model.Add("money", "金钱", "金钱", 1, "pickup");

            Assert.Equal(11, model.Cards[0].Count);
            Assert.Equal(1, model.Cards[0].DisplayCount);

            model.Tick(LootFeedModel.CountVisualIntervalMs - 1);
            Assert.Equal(1, model.Cards[0].DisplayCount);
            model.Tick(1);

            Assert.Equal(11, model.Cards[0].DisplayCount);
            Assert.Equal(1, model.Cards[0].PreviousDisplayCount);
            Assert.Equal(LootFeedModel.CountVisualIntervalMs,
                model.Cards[0].CountTransitionStartedMs);
        }

        [Fact]
        public void CountCommit_RequestsGeometryOnlyWhenTheVisibleDigitBucketChanges()
        {
            var model = NewModel();
            model.Add("kill", "杂兵", "杂兵", 1, "kill", 0);

            model.Add("kill", "杂兵", "杂兵", 1, "kill", 0);
            LootFeedModel.Change toTwo = model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.True((toTwo & LootFeedModel.Change.Geometry) != 0);
            Assert.Equal(2, model.Cards[0].DisplayCount);

            model.Add("kill", "杂兵", "杂兵", 7, "kill", 0);
            LootFeedModel.Change toNine = model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.True((toNine & LootFeedModel.Change.Visual) != 0);
            Assert.True((toNine & LootFeedModel.Change.Geometry) == 0);
            Assert.Equal(9, model.Cards[0].DisplayCount);

            model.Add("kill", "杂兵", "杂兵", 1, "kill", 0);
            LootFeedModel.Change toTen = model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.True((toTen & LootFeedModel.Change.Geometry) != 0);
            Assert.Equal(10, model.Cards[0].DisplayCount);
        }

        [Fact]
        public void LossCountCommit_OneToTwoIsVisualOnlyAndNineToTenChangesGeometry()
        {
            var model = NewModel();
            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");

            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");
            LootFeedModel.Change toTwo = model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.True((toTwo & LootFeedModel.Change.Visual) != 0);
            Assert.True((toTwo & LootFeedModel.Change.Geometry) == 0);

            model.Add("item", "步枪弹匣", "步枪弹匣", 7, "reload", 0,
                "loss", null, "步枪弹匣");
            LootFeedModel.Change toNine = model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.True((toNine & LootFeedModel.Change.Visual) != 0);
            Assert.True((toNine & LootFeedModel.Change.Geometry) == 0);

            model.Add("item", "步枪弹匣", "步枪弹匣", 1, "reload", 0,
                "loss", null, "步枪弹匣");
            LootFeedModel.Change toTen = model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.True((toTen & LootFeedModel.Change.Geometry) != 0);
        }

        [Theory]
        [InlineData(0L, 0)]
        [InlineData(1L, 0)]
        [InlineData(2L, 1)]
        [InlineData(9L, 1)]
        [InlineData(10L, 2)]
        [InlineData(999L, 3)]
        [InlineData(1000L, 4)]
        [InlineData(long.MaxValue, 19)]
        public void CountLayoutBucket_IsStableWithinOneDigitWidth(long count, int expected)
        {
            Assert.Equal(expected, LootFeedModel.CountLayoutBucket(count));
        }

        [Theory]
        [InlineData(1L, 1)]
        [InlineData(2L, 1)]
        [InlineData(9L, 1)]
        [InlineData(10L, 2)]
        public void LossCountLayoutBucket_IncludesTheAlwaysVisibleMagnitude(long count, int expected)
        {
            Assert.Equal(expected, LootFeedModel.CountLayoutBucket(count, "loss"));
        }

        [Fact]
        public void PendingIndicator_ReportsRecoverableCardCountAtEightHertz()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards + 2; i++)
                model.Add("item", "任务奖励" + i, "奖励" + i, 1, "quest_reward");

            Assert.Equal(2, model.PendingCount);
            Assert.Equal(0, model.DisplayPendingCount);
            model.Tick(LootFeedModel.CountVisualIntervalMs);
            Assert.Equal(2, model.DisplayPendingCount);
        }

        [Fact]
        public void OrdinaryKills_CompressOnlyIdentityOverflowAndPreserveTotal()
        {
            var model = NewModel();
            for (int i = 0; i < LootFeedModel.MaxDistinctOrdinaryKillCards + 2; i++)
                model.Add("kill", "杂兵" + i, "杂兵" + i, 1, "kill", 0);

            var all = model.Cards.Concat(model.PendingCards).ToArray();
            Assert.Equal(LootFeedModel.MaxDistinctOrdinaryKillCards + 1, all.Length);
            LootFeedModel.LootCard summary = Assert.Single(all, card => card.IsAmbientSummary);
            Assert.Equal("杂兵击杀", summary.Name);
            Assert.Equal(2, summary.Count);
            Assert.Equal(10, all.Sum(card => card.Count));
            Assert.Equal(LootFeedModel.RetentionClass.Compressible, summary.Retention);
        }

        [Fact]
        public void AlphaFor_UsesSmoothStepForEntryAndExit()
        {
            var card = new LootFeedModel.LootCard { VisibleAgeMs = 80, FadeElapsedMs = 0 };
            Assert.Equal(0.5f, LootFeedModel.AlphaFor(card, 160), 3);

            card.VisibleAgeMs = 160;
            Assert.Equal(1f, LootFeedModel.AlphaFor(card, 160));

            card.FadeElapsedMs = LootFeedModel.FadeMs / 2;
            Assert.Equal(0.5f, LootFeedModel.AlphaFor(card, 160), 3);
            card.FadeElapsedMs = LootFeedModel.FadeMs;
            Assert.Equal(0f, LootFeedModel.AlphaFor(card, 160));
        }

        [Fact]
        public void Add_RejectsInvalidInput()
        {
            var model = NewModel();
            model.Add(null, "急救包", null, 1, "pickup");
            model.Add("item", null, null, 1, "pickup");
            model.Add("item", "急救包", null, 0, "pickup");
            model.Add("item", "急救包", null, -5, "pickup");

            Assert.Equal(0, model.ActiveCount);
            Assert.Equal(0, model.PendingCount);
        }

        [Theory]
        [InlineData("neutral", "item")]
        [InlineData("gain", "kill")]
        [InlineData("loss", "kill")]
        [InlineData("sideways", "item")]
        public void Add_RejectsInvalidDirectionKindCombination(string direction, string kind)
        {
            var model = NewModel();
            model.Add(kind, "目标", null, 1, kind == "kill" ? "kill" : "pickup",
                0, direction);
            Assert.Equal(0, model.ActiveCount);
        }
    }
}
