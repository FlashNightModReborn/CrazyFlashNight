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
        public void Merge_WithinWindow_AccumulatesCountAndRefreshesClock()
        {
            var m = NewModel();
            m.Add("money", "金钱", "金钱", 100, "pickup");
            m.Tick(1000);
            m.Add("money", "金钱", "金钱", 50, "pickup");

            Assert.Equal(1, m.ActiveCount);
            Assert.Equal(150, m.Cards[0].Count);
            Assert.Equal(1000, m.Cards[0].LastEventMs);
        }

        [Fact]
        public void Merge_AfterWindow_CreatesNewCard()
        {
            var m = NewModel();
            m.Add("money", "金钱", "金钱", 100, "pickup");
            m.Tick(LootFeedModel.MergeWindowMs + 1);
            m.Add("money", "金钱", "金钱", 50, "pickup");

            Assert.Equal(2, m.ActiveCount);
        }

        [Fact]
        public void Merge_DifferentKindOrName_NeverMerges()
        {
            var m = NewModel();
            m.Add("money", "金钱", "金钱", 1, "pickup");
            m.Add("kpoint", "金钱", "金钱", 1, "pickup");
            m.Add("money", "K点", "金钱", 1, "pickup");

            Assert.Equal(3, m.ActiveCount);
        }

        [Fact]
        public void Merge_BumpsCardToNewestPosition()
        {
            var m = NewModel();
            m.Add("item", "急救包", "急救包", 1, "pickup");
            m.Add("item", "绷带", "绷带", 1, "pickup");
            m.Add("item", "急救包", "急救包", 2, "pickup");

            Assert.Equal(2, m.ActiveCount);
            Assert.Equal("绷带", m.Cards[0].Name);
            Assert.Equal("急救包", m.Cards[1].Name);
            Assert.Equal(3, m.Cards[1].Count);
        }

        [Fact]
        public void Merge_IsFree_UnderRateLimit()
        {
            var m = NewModel();
            // 同窗口内 1 张新卡 + 远超限额的合并事件，全部应被接受
            m.Add("money", "金钱", "金钱", 1, "pickup");
            for (int i = 0; i < LootFeedModel.RateMaxNewCards * 3; i++)
                m.Add("money", "金钱", "金钱", 1, "pickup");

            Assert.Equal(1, m.ActiveCount);
            Assert.Equal(1 + LootFeedModel.RateMaxNewCards * 3, m.Cards[0].Count);
            Assert.Equal(0, m.DroppedCount);
        }

        [Fact]
        public void RateLimit_DropsExcessNewCards_IntoOverflow()
        {
            var m = NewModel();
            for (int i = 0; i < LootFeedModel.RateMaxNewCards + 3; i++)
                m.Add("item", "物品" + i, "物品" + i, 1, "pickup");

            Assert.Equal(LootFeedModel.RateMaxNewCards, m.ActiveCount);
            Assert.Equal(3, m.DroppedCount);
            Assert.True(m.OverflowCount >= 3);
        }

        [Fact]
        public void RateLimit_WindowResets()
        {
            var m = NewModel();
            for (int i = 0; i < LootFeedModel.RateMaxNewCards; i++)
                m.Add("item", "物品" + i, "物品" + i, 1, "pickup");
            m.Tick(LootFeedModel.RateWindowMs);
            m.Add("item", "新物品", "新物品", 1, "pickup");

            Assert.Equal(LootFeedModel.RateMaxNewCards + 1, m.ActiveCount);
            Assert.Equal(0, m.DroppedCount);
        }

        [Fact]
        public void Overflow_IncludesCardsBeyondMaxVisible()
        {
            var m = NewModel();
            for (int i = 0; i < LootFeedModel.MaxVisibleCards + 2; i++)
                m.Add("item", "物品" + i, "物品" + i, 1, "pickup");

            Assert.Equal(LootFeedModel.MaxVisibleCards + 2, m.ActiveCount);
            Assert.Equal(2, m.OverflowCount);
        }

        [Fact]
        public void Tick_ExpiresCardsAfterHoldPlusFade()
        {
            var m = NewModel();
            m.Add("item", "急救包", "急救包", 1, "pickup");
            m.Tick(LootFeedModel.HoldMs + LootFeedModel.FadeMs);
            Assert.Equal(1, m.ActiveCount);
            bool removed = m.Tick(1);

            Assert.True(removed);
            Assert.Equal(0, m.ActiveCount);
        }

        [Fact]
        public void Tick_DroppedCountResetsWhenFeedClears()
        {
            var m = NewModel();
            for (int i = 0; i < LootFeedModel.RateMaxNewCards + 2; i++)
                m.Add("item", "物品" + i, "物品" + i, 1, "pickup");
            Assert.Equal(2, m.DroppedCount);

            m.Tick(LootFeedModel.HoldMs + LootFeedModel.FadeMs + 1);

            Assert.Equal(0, m.ActiveCount);
            Assert.Equal(0, m.DroppedCount);
            Assert.Equal(0, m.OverflowCount);
        }

        [Fact]
        public void AlphaFor_FullAlphaDuringHold_FadesQuadraticallyAfter()
        {
            var m = NewModel();
            m.Add("item", "急救包", "急救包", 1, "pickup");
            var card = m.Cards[0];

            Assert.Equal(1f, LootFeedModel.AlphaFor(card, LootFeedModel.HoldMs, 200));

            float halfFade = LootFeedModel.AlphaFor(
                card, LootFeedModel.HoldMs + LootFeedModel.FadeMs / 2, 200);
            Assert.True(halfFade > 0.2f && halfFade < 0.3f); // (0.5)^2 = 0.25

            Assert.Equal(0f, LootFeedModel.AlphaFor(
                card, LootFeedModel.HoldMs + LootFeedModel.FadeMs, 200));
        }

        [Fact]
        public void Add_RejectsInvalidInput()
        {
            var m = NewModel();
            m.Add(null, "急救包", null, 1, "pickup");
            m.Add("item", null, null, 1, "pickup");
            m.Add("item", "急救包", null, 0, "pickup");
            m.Add("item", "急救包", null, -5, "pickup");

            Assert.Equal(0, m.ActiveCount);
        }
    }
}
