using System;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class ChainVisualEngineTests
    {
        private static string Group(int step = 0, int style = 1, int visible = 1,
            int advanceX = 0, int advance = 10, int scaleX = 100) =>
            $"G,1,{style},{step},100,200,0,{scaleX},100,100,{visible},{advance},{advanceX}";
        private static string Packet(int sequence, string body, int epoch = 1, int tick = 100) =>
            $"1|{epoch}|{sequence}|{tick}" + (body.Length > 0 ? ";" + body : "");
        private const string Birth = "B,1,1,2,3,0.6,0.8,20";

        [Fact]
        public void BirthUsesCurrentPoseAndFollowingStepAdvancesBeforeReinforcement()
        {
            var engine = new ChainVisualEngine();
            var born = Assert.Single(engine.Consume(7, Packet(1, Group() + ";" + Birth), 8));
            Assert.Equal(102f, born.X);
            Assert.Equal(203f, born.Y);
            var moved = engine.Consume(7, Packet(2, Group(1, advanceX: 1)
                + ";B,1,2,7,8,0,1,0", tick: 101), 8);
            Assert.Equal(2, moved.Length);
            Assert.Equal(110f, moved[0].X);
            Assert.Equal(209f, moved[0].Y);
            Assert.Equal(107f, moved[1].X);
            Assert.Equal(208f, moved[1].Y);
            var frozenX = engine.Consume(7, Packet(3, Group(2), tick: 102), 8);
            Assert.Equal(110f, frozenX[0].X);
            Assert.Equal(215f, frozenX[0].Y);
        }

        [Fact]
        public void SameGroupStepPausesUnitsAndVisibilityOnlySuppressesDrawing()
        {
            var engine = new ChainVisualEngine();
            engine.Consume(7, Packet(1, Group() + ";" + Birth), 8);
            Assert.Empty(engine.Consume(7, Packet(2, Group(visible: 0)), 8));
            var resumed = Assert.Single(engine.Consume(7, Packet(3, Group(advance: 900000)), 8));
            Assert.Equal(102f, resumed.X);
            Assert.Equal(203f, resumed.Y);
            Assert.False(engine.NeedsResync);
        }

        [Fact]
        public void NegativeScaleUsesOriginalChainMatrixAndRotationRule()
        {
            var engine = new ChainVisualEngine();
            var item = Assert.Single(engine.Consume(7,
                Packet(1, Group(scaleX: -100) + ";B,1,1,2,3,0,1,0"), 8));
            Assert.Equal(98f, item.X);
            Assert.Equal(203f, item.Y);
            Assert.Equal(180f, item.Rotation);
            Assert.Equal(-100f, item.ScaleX);
        }

        [Fact]
        public void DeathAndAbsentGroupClearOnlyTheirVisualUnits()
        {
            var engine = new ChainVisualEngine();
            engine.Consume(7, Packet(1, Group() + ";" + Birth + ";B,1,2,8,0,0,1,0"), 8);
            var survivor = Assert.Single(engine.Consume(7, Packet(2, Group(1) + ";D,1,1"), 8));
            Assert.Equal(108f, survivor.X);
            Assert.Empty(engine.Consume(7, Packet(3, ""), 8));
            Assert.False(engine.NeedsResync);
        }

        [Fact]
        public void OldGenerationEpochAndDuplicatePacketsCannotReplayOrClearCurrentState()
        {
            var engine = new ChainVisualEngine();
            string initial = Packet(12, Group() + ";" + Birth, epoch: 9);
            Assert.Single(engine.Consume(7, initial, 8));
            Assert.Null(engine.Consume(6, Packet(99, "", epoch: 100), 8));
            Assert.Null(engine.Consume(7, Packet(99, "", epoch: 8), 8));
            Assert.Null(engine.Consume(7, initial, 8));
            engine.ResetIfGeneration(6);
            Assert.Single(engine.Consume(7, Packet(13, Group(1), epoch: 9), 8));
            Assert.Equal(9, engine.Epoch);
            Assert.False(engine.NeedsResync);
        }

        [Fact]
        public void SequenceGapRequiresNewEpochAndNeverExtrapolatesMissingGameplayTicks()
        {
            var engine = new ChainVisualEngine();
            engine.Consume(7, Packet(1, Group() + ";" + Birth), 8);
            Assert.Empty(engine.Consume(7, Packet(3, Group(2)), 8));
            Assert.True(engine.NeedsResync);
            Assert.Empty(engine.Consume(7, Packet(4, Group() + ";" + Birth), 8));
            Assert.Single(engine.Consume(7, Packet(1, Group() + ";" + Birth, epoch: 2), 8));
            Assert.False(engine.NeedsResync);
            Assert.Null(engine.Consume(7, Packet(500, "", epoch: 1), 8));
        }

        [Fact]
        public void GroupStepJumpOrUnknownDeathFailsClosedWithoutPartialBirths()
        {
            var engine = new ChainVisualEngine();
            engine.Consume(7, Packet(1, Group() + ";" + Birth), 8);
            Assert.Empty(engine.Consume(7, Packet(2, Group(3) + ";B,1,2,0,0,0,1,0"), 8));
            Assert.True(engine.NeedsResync);
            engine.Reset();
            engine.Consume(8, Packet(1, Group() + ";" + Birth), 8);
            Assert.Empty(engine.Consume(8, Packet(2, Group(1)
                + ";B,1,2,0,0,0,1,0;D,1,999"), 8));
            Assert.True(engine.NeedsResync);
            Assert.Single(engine.Consume(9, Packet(1, Group() + ";" + Birth), 8));
        }

        [Fact]
        public void CapacityAdmitsMaxUnitsAndRejectsOverflowWithoutSilentTruncation()
        {
            int max = ChainVisualFrame.MaxUnits;
            string births = string.Join(";",
                Enumerable.Range(1, max).Select(i => $"B,1,{i},0,0,0,1,0"));
            var engine = new ChainVisualEngine();
            Assert.Equal(max, engine.Consume(7, Packet(1, Group() + ";" + births), 8).Length);
            Assert.Equal(max, engine.Consume(7, Packet(2, Group(1)), 8).Length);
            Assert.Empty(engine.Consume(7, Packet(3, Group(2)
                + ";B,1," + (max + 1) + ",0,0,0,1,0"), 8));
            Assert.True(engine.NeedsResync);
        }

        [Fact]
        public void ReusedScratchKeepsEarlierReturnedArraysIntact()
        {
            var engine = new ChainVisualEngine();
            var first = engine.Consume(7, Packet(1, Group() + ";" + Birth), 8);
            var second = engine.Consume(7, Packet(2, Group(1)), 8);
            Assert.NotSame(first, second);
            var third = engine.Consume(7, Packet(3, Group(2)), 8);
            Assert.NotSame(second, third);
            Assert.Equal(102f, first[0].X);
            Assert.Equal(203f, first[0].Y);
            Assert.Equal(102f, second[0].X);
            Assert.Equal(209f, second[0].Y);
            Assert.Equal(102f, third[0].X);
            Assert.Equal(215f, third[0].Y);
        }

        [Fact]
        public void FullCatalogIndicesRemainStableWhenOrdinaryOnlySlotsHaveNoChainLinkage()
        {
            var engine = new ChainVisualEngine();
            Assert.Equal(7, Assert.Single(engine.Consume(7,
                Packet(1, Group(style: 7) + ";" + Birth), 8)).Style);
            Assert.False(ChainVisualFrame.TryParse(Packet(1, Group(style: 8) + ";" + Birth), 8, out _));
        }

        [Theory]
        [InlineData("G,1,1,0,NaN,200,0,100,100,100,1,10,0")]
        [InlineData("G,1,1,0,100,200,0,100,100,101,1,10,0")]
        [InlineData("G,1,1,0,100,200,0,100,100,100,2,10,0")]
        [InlineData("G,1,1,0,100,200,0,100,100,100,1,10,2")]
        [InlineData("G,1,1,0,100,200,0,100,100,100,1,Infinity,0")]
        [InlineData("G,1,1,0,100,200,0,100,100,100,1,10,0,")]
        public void ParserRejectsMalformedGroupFields(string group)
        {
            Assert.False(ChainVisualFrame.TryParse(Packet(1, group + ";" + Birth), 8, out _));
        }

        [Fact]
        public void ParserRejectsUnknownGroupInvalidBirthAndOversizedPayload()
        {
            Assert.False(ChainVisualFrame.TryParse(Packet(1, Birth), 8, out _));
            Assert.False(ChainVisualFrame.TryParse(Packet(1, Group() + ";B,1,1,0,0,2,1,0"), 8, out _));
            Assert.False(ChainVisualFrame.TryParse(Packet(1, Group() + ";" + Birth + ";" + Group()), 8, out _));
            Assert.False(ChainVisualFrame.TryParse(new string('x', 1024 * 1024 + 1), 8, out _));
            var engine = new ChainVisualEngine();
            Assert.Empty(engine.Consume(7, Packet(1, Group() + ";" + Birth + ";" + Birth), 8));
            Assert.True(engine.NeedsResync);
        }

        [Fact]
        public void SameGenerationResetKeepsReplayBarrierUntilANewEpoch()
        {
            var engine = new ChainVisualEngine();
            string old = Packet(1, Group() + ";" + Birth);
            engine.Consume(7, old, 8);
            engine.ResetIfGeneration(7);
            Assert.Null(engine.Consume(7, old, 8));
            Assert.Single(engine.Consume(7, Packet(1, Group() + ";" + Birth, epoch: 2), 8));
        }

        [Theory]
        [InlineData(";")]
        [InlineData(";;")]
        [InlineData(";D,1,1;")]
        public void EmptyOrTrailingRecordsRemainRejected(string suffix)
        {
            Assert.False(ChainVisualFrame.TryParse(Packet(1, Group() + ";" + Birth) + suffix, 8, out _));
        }

        [Fact]
        public void HeaderSignsAndExtraFieldsKeepTheirStrictGrammar()
        {
            Assert.False(ChainVisualFrame.TryReadHeader("1|+1|1|1", out _, out _, out _));
            Assert.False(ChainVisualFrame.TryReadHeader("1|1|1|1|0", out _, out _, out _));
            Assert.True(ChainVisualFrame.TryParse("1|1|1|1", 8, out var empty));
            Assert.Empty(empty.Groups); Assert.Empty(empty.Events);
        }
    }
}
