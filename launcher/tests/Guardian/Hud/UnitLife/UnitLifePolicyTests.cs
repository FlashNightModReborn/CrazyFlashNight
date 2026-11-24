using System;
using CF7Launcher.Guardian.Hud.UnitLife;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.UnitLife;

public sealed class UnitLifePolicyTests
{
    private static readonly WorldLifeIdentity Unit = new(3, 7, 42, 1);
    private static WorldLifeFacts Hp(double value) => new(new UnitHealth(value, 100));
    private static WorldLifeState Start(double hp = 100, WorldLifeStart start = WorldLifeStart.Spawn,
        bool revealedInitially = true) => new(Unit, 0, Hp(hp), 100, start, revealedInitially);

    // Wheel-free 30fps frame clock matches AS2's exact 2s hold (60f), 3.07s ease-out (152f),
    // <5px snap, and 7.07s..10s fade (212..300f) for both dense and coalesced frames.
    [Theory]
    [InlineData(8, 1, 1)]
    [InlineData(64, 1, 1)]
    [InlineData(104, .5916824196597353, 1)]
    [InlineData(128, .4555765595463138, 1)]
    [InlineData(132, .4, 1)]
    [InlineData(156, .4, 1)]
    [InlineData(216, .4, 1)]
    [InlineData(260, .4, .5)]
    [InlineData(304, .4, 0)]
    public void WorldFrameClockMatchesGoldenPointsForDenseAndCoalescedFrames(int frame, double residual, double alpha)
    {
        var dense = Start();
        var sparse = Start();
        Assert.True(dense.Apply(Unit, 4, Hp(40)));
        Assert.True(sparse.Apply(Unit, 4, Hp(40)));
        for (int i = 5; i <= frame; ++i) Assert.True(dense.Apply(Unit, i, Hp(40)));
        Assert.True(sparse.Apply(Unit, frame, Hp(40)));
        Assert.Equal(residual, dense.Residual, 10);
        Assert.Equal(alpha, dense.Alpha, 10);
        Assert.Equal(dense.Residual, sparse.Residual, 10);
        Assert.Equal(dense.Alpha, sparse.Alpha, 10);
    }

    [Fact]
    public void WorldFrameClockSmoothlyInterpolatesBetweenLegacyFourFrameBoundaries()
    {
        var bar = Start();
        Assert.True(bar.Apply(Unit, 4, Hp(40)));
        Assert.True(bar.Apply(Unit, 65, Hp(40)));
        Assert.True(bar.Residual < 1.0 && bar.Residual > 0.95);
        Assert.True(bar.Apply(Unit, 66, Hp(40)));
        double at66 = bar.Residual;
        Assert.True(bar.Apply(Unit, 67, Hp(40)));
        Assert.True(bar.Residual < at66);
    }

    [Fact]
    public void SpawnStartsHiddenUntilHitOrDamageAndMultipliesWeatherOpacity()
    {
        var spawned = Start(100, WorldLifeStart.Spawn, revealedInitially: false);
        Assert.False(spawned.Revealed);
        Assert.Equal(0d, spawned.Alpha);
        Assert.True(spawned.Apply(Unit, 20, Hp(100)));
        Assert.Equal(0d, spawned.Alpha);
        Assert.True(spawned.Apply(Unit, 21, Hp(80) with { WeatherOpacity = 0.5f }));
        Assert.True(spawned.Revealed);
        Assert.Equal(1d, spawned.BarAlpha, 6);
        Assert.Equal(0.5d, spawned.Alpha, 6);
        var visual = spawned.ToVisual();
        Assert.Equal(0.5f, visual.Alpha, 3);
        Assert.Equal(0.8, visual.Health.Ratio, 6);
        Assert.Equal(1.0, visual.TrailRatio, 6);
    }

    [Fact]
    public void RepeatedDamageAndHealingUseLastResidualWithoutGrowingItOnHeal()
    {
        var bar = Start();
        bar.Apply(Unit, 4, Hp(40));
        bar.Apply(Unit, 104, Hp(40));
        double previous = bar.Residual;
        bar.Apply(Unit, 105, Hp(20));
        Assert.Equal(previous, bar.Residual);
        bar.Apply(Unit, 224, Hp(20));
        Assert.True(bar.Residual < previous && bar.Residual >= .2);
        previous = bar.Residual;
        bar.Apply(Unit, 225, Hp(90));
        bar.Apply(Unit, 800, Hp(90));
        Assert.Equal(previous, bar.Residual);
        Assert.Equal(.9, bar.Facts.Health.Ratio);
    }

    [Fact]
    public void HitRevealsFadedBarOnceAndDoesNotAcceptStaleEventsOrAnotherOccupant()
    {
        var bar = Start();
        bar.Apply(Unit, 300, Hp(100));
        Assert.Equal(0d, bar.Alpha);
        Assert.True(bar.Hit(Unit, 301, 13, 1, 50));
        Assert.Equal(1d, bar.Alpha);
        Assert.Equal(50, bar.ColorOffset);
        Assert.Equal(-.11105424940538612, bar.OffsetX, 10);
        Assert.Equal(.3025932028680198, bar.OffsetY, 10);
        Assert.False(bar.Hit(Unit, 301, 13, 1, 50));
        Assert.True(bar.Hit(Unit, 301, 14, 1)); // second hit has jitter but no brightness sample
        Assert.Equal(50, bar.ColorOffset);
        Assert.Equal(2 * .3025932028680198, bar.OffsetY, 10);
        Assert.True(bar.Apply(Unit, 304, Hp(100) with { Darkened = true }));
        Assert.Equal(50, bar.ColorOffset); // 4-frame hit flash still active at frame 304
        Assert.True(bar.Apply(Unit, 305, Hp(100) with { Darkened = true }));
        Assert.Equal(-75, bar.ColorOffset); // hit flash ends after 4 frames -> falls back to Darkened
        foreach (var wrong in new[] { Unit with { StreamEpoch = 8 }, Unit with { SceneEpoch = 4 },
                                      Unit with { Handle = 43 }, Unit with { Generation = 2 } })
        {
            Assert.False(bar.Apply(wrong, 310, Hp(15)));
            Assert.False(bar.Hit(wrong, 310, 15, 1, 50));
        }
        Assert.False(bar.Hit(Unit, 300, 15, 1, 50));
        Assert.True(bar.Apply(Unit, 306, Hp(90)));
        Assert.Equal(0d, bar.OffsetX);
        Assert.Equal(0d, bar.OffsetY);
        Assert.True(bar.Apply(Unit, 307, Hp(90)));
        Assert.Equal(0, bar.ColorOffset);
    }

    [Fact]
    public void MaxOnlyChangeLeavesFadedBarAndHiddenHpChangesApplyImmediatelyWhenVisible()
    {
        var bar = Start();
        bar.Apply(Unit, 300, Hp(100));
        var largerMax = new WorldLifeFacts(new(100, 200));
        bar.Apply(Unit, 304, largerMax);
        Assert.Equal(0d, bar.Alpha);
        Assert.Equal(1d, bar.Actual);
        Assert.Equal(.5, bar.Facts.Health.Ratio);
        var damaged = largerMax with { Health = new(70, 200) };
        bar.Apply(Unit, 308, damaged with { InformationVisible = false });
        bar.Apply(Unit, 600, damaged with { InformationVisible = false });
        Assert.Equal(0d, bar.Alpha);
        Assert.Equal(1d, bar.Actual);
        bar.Apply(Unit, 601, damaged);
        Assert.Equal(1d, bar.Alpha);
        Assert.Equal(.35, bar.Actual);
        Assert.Equal(.5, bar.Residual);
    }

    [Fact]
    public void SameFrameFactsPrecedeMultipleHitsAndCannotBeReplayedAfterThem()
    {
        var bar = Start();
        Assert.True(bar.Apply(Unit, 4, Hp(60)));
        Assert.False(bar.Hit(Unit, 4, 1, 1, 26)); // rejecting invalid brightness leaves event ID available
        Assert.True(bar.Hit(Unit, 4, 1, 1));
        Assert.True(bar.Hit(Unit, 4, 2, 1));
        Assert.False(bar.Apply(Unit, 4, Hp(25)));
        Assert.Equal(.6, bar.Actual);
        Assert.Equal(2 * .3025932028680198, bar.OffsetY, 10);
        Assert.True(bar.Hit(Unit, 8, 3, 1, 75));
        Assert.False(bar.Apply(Unit, 8, Hp(25))); // stale even when no snapshot arrived first
        Assert.True(bar.Apply(Unit, 12, Hp(25)));
        Assert.Equal(.25, bar.Actual);
        Assert.Equal(0d, bar.OffsetY);
        Assert.True(bar.Apply(Unit, 312, Hp(25)));
        Assert.Equal(0d, bar.Alpha);
        Assert.True(bar.Hit(Unit, 313, 4, 1)); // no invented shade when source supplies only jitter
        Assert.Equal(0, bar.ColorOffset);
        Assert.Equal(1d, bar.Alpha);
        Assert.NotEqual(0d, bar.OffsetY);
    }

    [Fact]
    public void PausedFrameDoesNotAdvanceAndHiddenFramesDoNotAge()
    {
        var bar = Start(40);
        Assert.True(bar.Apply(Unit, 1, Hp(40) with { InformationVisible = false }));
        Assert.Equal(0d, bar.Alpha);
        Assert.True(bar.Apply(Unit, 998, Hp(40) with { InformationVisible = false }));
        Assert.True(bar.Apply(Unit, 999, Hp(40)));
        Assert.Equal(1d, bar.Alpha);
        Assert.Equal(1d, bar.Residual);
        Assert.False(bar.Apply(Unit, 999, Hp(40)));
        Assert.Equal(1d, bar.Residual);
        Assert.True(bar.Apply(Unit, 1098, Hp(40)));
        Assert.Equal(.5916824196597353, bar.Residual, 10);
    }

    [Fact]
    public void ResyncSnapsToFactsAndRetainsRawHealthAndDistinctShieldPoiseAndRigidStates()
    {
        var id = Unit with { StreamEpoch = 8, Generation = 2 };
        var facts = Hp(20) with { Shield = new(0, 10), Poise = .6, TaggedRigid = true };
        var bar = new WorldLifeState(id, 30, facts, 80, WorldLifeStart.Resync);
        Assert.Equal(.2, bar.Residual);
        Assert.True(bar.Revealed);
        Assert.False(bar.ShieldVisible); // AS2 BaseShield.isEmpty() hides zero-capacity shield
        Assert.Equal(0d, bar.ShieldRatio);
        Assert.Equal(.6, bar.PoiseRatio);
        Assert.True(bar.Rigid);
        Assert.False(bar.Apply(Unit, 400, Hp(80)));
        Assert.False(bar.Apply(id, 32, facts with { Health = new(20, 0) }));
        Assert.True(bar.Apply(id, 32, facts with { Health = new(130, 100), Shield = new(10, 0), Airborne = true }));
        Assert.Equal(130d, bar.Facts.Health.Current);
        Assert.Equal(.3, bar.Facts.Health.OverflowRatio, 10);
        Assert.False(bar.ShieldVisible);
        Assert.Equal(0d, bar.PoiseRatio);
        Assert.True(bar.Apply(id, 36, facts with { Health = new(-3, 100), Shield = new(8, 10), Down = true }));
        Assert.Equal(-3d, bar.Facts.Health.Current);
        Assert.Equal(0d, bar.Facts.Health.Ratio);
        Assert.True(bar.ShieldVisible);
        Assert.Equal(.8, bar.ShieldRatio);
        Assert.Equal(0d, bar.PoiseRatio);
        var visual = bar.ToVisual();
        Assert.Equal(.8, visual.ShieldRatio, 6);
        Assert.True(visual.Down && visual.Rigid);
        Assert.Equal(0d, visual.PoiseRatio);
    }

    [Fact]
    public void FocusUsesItsOwnMillisecondLossGainHysteresisAndUnitInfoChannels()
    {
        var focus = new FocusLifeState(new(100, 100));
        focus.Apply(new(20, 100));
        Assert.True(focus.Critical);
        focus.Tick(90);
        Assert.Equal(1d, focus.TrailRatio);
        focus.Tick(115);
        Assert.Equal(.6, focus.TrailRatio, 9);
        focus.Apply(new(15, 100));
        Assert.Equal(1d, focus.TrailRatio);
        focus.Tick(320);
        Assert.Equal(.15, focus.TrailRatio);
        focus.Apply(new(30, 100));
        Assert.True(focus.Critical);
        Assert.Equal(.15, focus.HealStartRatio);
        focus.Tick(180);
        Assert.Equal(.5f, focus.GainAlpha);
        focus.Tick(180);
        Assert.False(focus.HasActiveTransition);
        focus.Apply(new(31, 100));
        Assert.False(focus.Critical);

        // Shield, poise, posture flags, and 85ms quadratic hitSeq flash with rapid-burst gating
        focus.Apply(new(31, 100), shieldRatio: 0.65, poiseRatio: 0.72, hasPoise: true,
            rigid: true, airborne: false, down: false, darkened: true, hitSeq: 4, staticFeedback: false);
        Assert.Equal(0.65, focus.Visual.ShieldRatio, 6);
        Assert.Equal(0.72, focus.Visual.PoiseRatio, 6);
        Assert.True(focus.Visual.HasPoise && focus.Visual.Rigid && focus.Visual.Darkened);
        Assert.Equal(1f, focus.HitFlash, 3);
        Assert.True(focus.HasActiveTransition);
        Assert.True(focus.Tick(40));
        float midFlash = focus.HitFlash;
        Assert.True(midFlash > 0f && midFlash < 0.5f); // quadratic falloff decays quickly
        // Rapid consecutive hitSeq during active flash must NOT pin flash back to 1.0
        focus.Apply(new(31, 100), shieldRatio: 0.65, poiseRatio: 0.72, hasPoise: true,
            rigid: true, airborne: false, down: false, darkened: true, hitSeq: 5, staticFeedback: false);
        Assert.Equal(midFlash, focus.HitFlash, 3);
        Assert.True(focus.Tick(50));
        Assert.Equal(0f, focus.HitFlash, 3);
        Assert.False(focus.HasActiveTransition);
        // Once settled, next hitSeq fires a fresh pulse
        focus.Apply(new(31, 100), shieldRatio: 0.65, poiseRatio: 0.72, hasPoise: true,
            rigid: true, airborne: false, down: false, darkened: true, hitSeq: 6, staticFeedback: false);
        Assert.Equal(1f, focus.HitFlash, 3);
        focus.Tick(90);
        Assert.False(focus.HasActiveTransition);

        // Static feedback suppresses hit flash while retaining authoritative facts
        focus.Apply(new(140, 100), shieldRatio: 0.25, poiseRatio: 0.4, hasPoise: true,
            rigid: false, airborne: true, down: false, darkened: false, hitSeq: 7, staticFeedback: true);
        Assert.Equal(1d, focus.TrailRatio);
        Assert.Equal(.4, focus.Visual.Health.OverflowRatio, 9);
        Assert.Equal(0f, focus.HitFlash, 3);
        Assert.True(focus.Visual.Airborne);
        Assert.False(focus.HasActiveTransition);
    }
}
