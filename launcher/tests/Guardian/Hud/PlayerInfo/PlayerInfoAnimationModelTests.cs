using System;
using System.Collections.Generic;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoAnimationModelTests
{
    private static readonly int[] HpFullToEmpty =
    [
        1, 10, 18, 26, 33, 40, 46, 52, 58, 63, 68, 73, 77, 81,
        85, 88, 91, 94, 97, 100, 102, 104, 106, 108, 110, 112,
        114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124,
        125, 126, 127, 128, 129
    ];

    private static readonly int[] HpEmptyToFull =
    [
        129, 120, 112, 104, 97, 90, 84, 78, 72, 67, 62, 57, 53,
        49, 45, 42, 39, 36, 33, 30, 28, 26, 24, 22, 20, 18, 16,
        15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1
    ];

    private static readonly int[] MpFullToEmpty =
    [
        1, 8, 15, 21, 27, 32, 37, 42, 46, 50, 54, 58, 61, 64,
        67, 70, 73, 75, 77, 79, 81, 83, 85, 87, 88, 89, 90, 91,
        92, 93, 94, 95, 96, 97, 98, 99, 100, 101
    ];

    public static IEnumerable<object[]> FrozenFixtureCases()
    {
        yield return ["empty", 129, 101];
        yield return ["min_step", 128, 100];
        yield return ["p25", 97, 76];
        yield return ["p50", 65, 51];
        yield return ["p75", 33, 26];
        yield return ["p99", 3, 2];
        yield return ["full", 1, 1];
        yield return ["mp_vf34", 44, 34];
        yield return ["mp_vf35", 45, 35];
        yield return ["mp_vf70", 90, 70];
        yield return ["mp_vf91", 117, 91];
    }

    [Fact]
    public void FixtureAllowlist_IsExactCaseSensitiveAndRejectsUnknownIds()
    {
        Assert.Equal(
            new[]
            {
                "empty",
                "min_step",
                "p25",
                "p50",
                "p75",
                "p99",
                "full",
                "mp_vf34",
                "mp_vf35",
                "mp_vf70",
                "mp_vf91"
            },
            PlayerInfoFixtureInput.AllowedCaseIds);
        Assert.All(
            PlayerInfoFixtureInput.AllowedCaseIds,
            caseId => Assert.True(PlayerInfoFixtureInput.IsAllowedCaseId(caseId)));
        Assert.False(PlayerInfoFixtureInput.IsAllowedCaseId("FULL"));
        Assert.False(PlayerInfoFixtureInput.IsAllowedCaseId(null));
        Assert.Throws<ArgumentException>(
            () => PlayerInfoFixtureInput.FromCaseId("custom"));
        Assert.Throws<ArgumentException>(
            () => new PlayerInfoFixtureInput(
                "FULL",
                new PlayerInfoGaugeInput(1, 1),
                new PlayerInfoGaugeInput(1, 1)));
    }

    [Theory]
    [MemberData(nameof(FrozenFixtureCases))]
    public void FrozenFixtureCases_MapToExactHpAndMpVirtualFrames(
        string caseId,
        int expectedHpFrame,
        int expectedMpFrame)
    {
        var model = new PlayerInfoAnimationModel();

        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId(caseId)));

        Assert.Equal(caseId, model.LastFixtureCaseId);
        Assert.True(model.VisualState.HasRenderableState);
        Assert.Equal(expectedHpFrame, model.VisualState.Hp.TargetVirtualFrame);
        Assert.Equal(expectedHpFrame, model.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(expectedMpFrame, model.VisualState.Mp.TargetVirtualFrame);
        Assert.Equal(expectedMpFrame, model.VisualState.Mp.CurrentVirtualFrame);
    }

    [Fact]
    public void ValidValues_ClampBeforeFrameMappingAndDisplayFormatting()
    {
        var model = new PlayerInfoAnimationModel();
        var fixture = new PlayerInfoFixtureInput(
            "empty",
            new PlayerInfoGaugeInput(-123.75, 10.9),
            new PlayerInfoGaugeInput(99.9, 10.9));

        Assert.True(model.ApplyFixture(fixture));

        PlayerInfoGaugeVisualState hp = model.VisualState.Hp;
        Assert.Equal(0d, hp.ClampedCurrent);
        Assert.Equal(129, hp.TargetVirtualFrame);
        Assert.Equal("0", hp.CurrentText);
        Assert.Equal("10", hp.MaximumText);
        Assert.Equal("0", hp.PercentText);
        Assert.Null(hp.CombinedText);

        PlayerInfoGaugeVisualState mp = model.VisualState.Mp;
        Assert.Equal(10.9d, mp.ClampedCurrent);
        Assert.Equal(1, mp.TargetVirtualFrame);
        Assert.Equal("10", mp.CurrentText);
        Assert.Equal("10", mp.MaximumText);
        Assert.Equal("100%", mp.PercentText);
        Assert.Equal("00010/00010", mp.CombinedText);
    }

    [Fact]
    public void FirstInvalidInput_RemainsUnrenderableAndDoesNotAnimate()
    {
        var model = new PlayerInfoAnimationModel();
        var fixture = new PlayerInfoFixtureInput(
            "empty",
            new PlayerInfoGaugeInput(double.NaN, 100),
            null);

        Assert.False(model.ApplyFixture(fixture));

        Assert.False(model.VisualState.HasRenderableState);
        Assert.False(model.VisualState.Hp.HasRenderableState);
        Assert.False(model.VisualState.Mp.HasRenderableState);
        AssertInvalid(
            model.VisualState.Hp,
            PlayerInfoInvalidInputReasons.CurrentNonFinite);
        AssertInvalid(
            model.VisualState.Mp,
            PlayerInfoInvalidInputReasons.Missing);
        Assert.False(model.WantsAnimationTick);
        Assert.False(model.Tick(1_000));
        Assert.False(model.VisualState.HasRenderableState);
    }

    [Fact]
    public void InvalidInput_FreezesOnlyThatGaugeAtItsLastKnownGoodState()
    {
        var model = new PlayerInfoAnimationModel();
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full")));
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("empty")));
        Assert.True(model.Tick(200));
        Assert.Equal(46, model.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(37, model.VisualState.Mp.CurrentVirtualFrame);

        var hpBeforeInvalid = model.VisualState.Hp;
        var invalidHp = new PlayerInfoFixtureInput(
            "p50",
            new PlayerInfoGaugeInput(double.PositiveInfinity, 12_800),
            new PlayerInfoGaugeInput(10_000, 10_000));
        Assert.True(model.ApplyFixture(invalidHp));
        AssertInvalid(
            model.VisualState.Hp,
            PlayerInfoInvalidInputReasons.CurrentNonFinite);
        Assert.True(hpBeforeInvalid.HasSameVisual(model.VisualState.Hp));

        Assert.True(model.Tick(1_000));
        Assert.Equal(46, model.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(1, model.VisualState.Mp.CurrentVirtualFrame);
        Assert.False(model.VisualState.Mp.WantsAnimationTick);

        var recoveredHp = new PlayerInfoFixtureInput(
            "empty",
            new PlayerInfoGaugeInput(0, 12_800),
            new PlayerInfoGaugeInput(10_000, 10_000));
        Assert.False(model.ApplyFixture(recoveredHp));
        Assert.Null(model.VisualState.Hp.Diagnostic);
        Assert.True(model.VisualState.Hp.IsInputValid);
        Assert.True(model.VisualState.Hp.WantsAnimationTick);

        Assert.True(model.Tick(34));
        Assert.Equal(52, model.VisualState.Hp.CurrentVirtualFrame);
    }

    [Theory]
    [InlineData(0, PlayerInfoInvalidInputReasons.MaximumNotPositive)]
    [InlineData(-1, PlayerInfoInvalidInputReasons.MaximumNotPositive)]
    [InlineData(double.PositiveInfinity, PlayerInfoInvalidInputReasons.MaximumNonFinite)]
    public void RepeatedInvalidInput_RetainsLkgAndNeverBecomesStale(
        double invalidMaximum,
        string expectedReason)
    {
        var model = new PlayerInfoAnimationModel();
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("p50")));
        PlayerInfoGaugeVisualState lastGood = model.VisualState.Hp;
        var invalid = new PlayerInfoFixtureInput(
            "p50",
            new PlayerInfoGaugeInput(10, invalidMaximum),
            PlayerInfoFixtureInput.FromCaseId("p50").Mp);

        Assert.False(model.ApplyFixture(invalid));
        Assert.False(model.ApplyFixture(invalid));

        Assert.True(lastGood.HasSameVisual(model.VisualState.Hp));
        AssertInvalid(model.VisualState.Hp, expectedReason);
        Assert.DoesNotContain(
            "stale",
            model.VisualState.Hp.Diagnostic!.Value.Code,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SameValidInput_DoesNotResetLogicalClockRemainder()
    {
        var model = CreateFullToEmptyTransition();
        PlayerInfoFixtureInput empty =
            PlayerInfoFixtureInput.FromCaseId("empty");

        Assert.False(model.Tick(16));
        Assert.Equal(480, model.LogicalFrameRemainderNumerator);
        Assert.False(model.ApplyFixture(empty));
        Assert.Equal(480, model.LogicalFrameRemainderNumerator);
        Assert.False(model.Tick(17));
        Assert.Equal(990, model.LogicalFrameRemainderNumerator);
        Assert.True(model.Tick(1));
        Assert.Equal(20, model.LogicalFrameRemainderNumerator);
        Assert.Equal(10, model.VisualState.Hp.CurrentVirtualFrame);
    }

    [Fact]
    public void IntegerThirtyFpsAccumulator_IsPartitionInvariantAndCanCatchUp()
    {
        var oneCall = CreateFullToEmptyTransition();
        var partitioned = CreateFullToEmptyTransition();

        Assert.True(oneCall.Tick(1_000));
        Assert.False(partitioned.Tick(33));
        Assert.True(partitioned.Tick(33));
        Assert.True(partitioned.Tick(34));
        Assert.True(partitioned.Tick(900));

        Assert.Equal(
            oneCall.VisualState.Hp.CurrentVirtualFrame,
            partitioned.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(118, oneCall.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(
            oneCall.VisualState.Mp.CurrentVirtualFrame,
            partitioned.VisualState.Mp.CurrentVirtualFrame);
        Assert.Equal(94, oneCall.VisualState.Mp.CurrentVirtualFrame);
        Assert.Equal(0, oneCall.LogicalFrameRemainderNumerator);
        Assert.Equal(0, partitioned.LogicalFrameRemainderNumerator);

        Assert.True(oneCall.Tick(int.MaxValue));
        Assert.Equal(129, oneCall.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(101, oneCall.VisualState.Mp.CurrentVirtualFrame);
        Assert.False(oneCall.WantsAnimationTick);
        Assert.False(oneCall.Tick(1_000));
    }

    [Fact]
    public void HpFullToEmpty_SmoothingMatchesCompleteFortyOneTickGolden()
    {
        var model = CreateFullToEmptyTransition();

        Assert.Equal(
            HpFullToEmpty,
            CaptureGaugeSequence(model, hp: true, HpFullToEmpty.Length - 1));
    }

    [Fact]
    public void HpEmptyToFull_SmoothingMatchesCompleteFortyOneTickGolden()
    {
        var model = new PlayerInfoAnimationModel();
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("empty")));
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full")));

        Assert.Equal(
            HpEmptyToFull,
            CaptureGaugeSequence(model, hp: true, HpEmptyToFull.Length - 1));
    }

    [Fact]
    public void MpFullToEmpty_SmoothingMatchesCompleteThirtySevenTickGolden()
    {
        var model = CreateFullToEmptyTransition();

        Assert.Equal(
            MpFullToEmpty,
            CaptureGaugeSequence(model, hp: false, MpFullToEmpty.Length - 1));
    }

    [Fact]
    public void MidTransitionReversal_UsesCurrentFrameAndRepeatedTargetIsNoOp()
    {
        var model = CreateFullToEmptyTransition();
        for (var index = 0; index < 5; index++)
        {
            Assert.True(model.Tick(OneLogicalFrameDelta(index)));
        }
        Assert.Equal(40, model.VisualState.Hp.CurrentVirtualFrame);

        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full")));
        Assert.False(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full")));
        Assert.True(model.Tick(OneLogicalFrameDelta(5)));
        Assert.Equal(37, model.VisualState.Hp.CurrentVirtualFrame);
    }

    [Fact]
    public void Tick_RejectsNegativeElapsedAndZeroIsANoOp()
    {
        var model = CreateFullToEmptyTransition();
        PlayerInfoVisualState before = model.VisualState;

        Assert.Throws<ArgumentOutOfRangeException>(() => model.Tick(-1));
        Assert.False(model.Tick(0));
        Assert.Same(before, model.VisualState);
        Assert.Equal(0, model.LogicalFrameRemainderNumerator);
    }

    private static PlayerInfoAnimationModel CreateFullToEmptyTransition()
    {
        var model = new PlayerInfoAnimationModel();
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full")));
        Assert.True(model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("empty")));
        return model;
    }

    private static int[] CaptureGaugeSequence(
        PlayerInfoAnimationModel model,
        bool hp,
        int tickCount)
    {
        var frames = new List<int>
        {
            hp
                ? model.VisualState.Hp.CurrentVirtualFrame
                : model.VisualState.Mp.CurrentVirtualFrame
        };
        for (var index = 0; index < tickCount; index++)
        {
            Assert.True(model.Tick(OneLogicalFrameDelta(index)));
            frames.Add(
                hp
                    ? model.VisualState.Hp.CurrentVirtualFrame
                    : model.VisualState.Mp.CurrentVirtualFrame);
        }
        return frames.ToArray();
    }

    private static int OneLogicalFrameDelta(int index) =>
        index % 3 == 0 ? 34 : 33;

    private static void AssertInvalid(
        PlayerInfoGaugeVisualState state,
        string expectedReason)
    {
        Assert.False(state.IsInputValid);
        Assert.NotNull(state.Diagnostic);
        Assert.Equal(
            PlayerInfoInputDiagnostic.InvalidInputCode,
            state.Diagnostic!.Value.Code);
        Assert.Equal(state.GaugeId, state.Diagnostic.Value.GaugeId);
        Assert.Equal(expectedReason, state.Diagnostic.Value.Reason);
    }
}
