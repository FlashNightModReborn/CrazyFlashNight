using System;
using System.IO;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudResourceMotionTests
{
    private static PlayerHudVitals Vitals()
    {
        var state=new PlayerHudState();Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()),1));
        return state.Snapshot.Vitals with {Hp=1430,HpMax=1000,Mp=750,MpMax=600,Shield=1000,ShieldMax=1000,
            ShieldPresent=true,ShieldReady=true,Decorations=false};
    }

    [Fact]
    public void LossChangesAuthorityFillImmediatelyAndAfterimageExpiresDespiteRepeatedSnapshots()
    {
        var v=Vitals();var motion=new PlayerHudResourceMotion();motion.Observe(v);
        Assert.False(motion.Active);
        v=v with {Shield=300,Hp=1100};motion.Observe(v);
        Assert.Equal(.3f,PlayerHudResourceMotion.ShieldFraction(v));
        Assert.Equal(.1f,PlayerHudResourceMotion.OverflowFraction(v));
        Assert.Equal(1,motion.Shield.Trail);
        for(var i=0;i<8;i++){motion.Observe(v);motion.Advance(33);}
        Assert.False(motion.Active);Assert.Equal(.3f,motion.Shield.Trail);
    }

    [Fact]
    public void CapacityChangesAndEpochResetDoNotPretendToBeHitsOrHealing()
    {
        var v=Vitals();var motion=new PlayerHudResourceMotion();motion.Observe(v);
        motion.Observe(v with {ShieldMax=2000,HpMax=2000});Assert.False(motion.Active);
        motion.Observe(v with {ShieldMax=2000,Shield=0,HpMax=2000});Assert.True(motion.Active);
        motion.Reset();motion.Observe(v);Assert.False(motion.Active);
        motion.Observe(v with {Shield=0,ShieldReady=false});Assert.False(motion.Shield.Active);
        motion.Observe(null);Assert.False(motion.Active);
    }

    [Fact]
    public void TemporaryShieldPresenceHoldsBrightFillAcrossShortGapAndReleasesWithoutZeroDarkFlash()
    {
        var baseVitals = Vitals() with { ShieldPresent = false, Shield = 0, ShieldMax = 0 };
        var motion = new PlayerHudResourceMotion();
        motion.Observe(baseVitals);
        Assert.Equal(0f, motion.Shield.Presence);

        var tempShield = baseVitals with { ShieldPresent = true, Shield = 200, ShieldMax = 200 };
        motion.Observe(tempShield);
        Assert.InRange(motion.Shield.Presence, 0.1f, 0.9f);
        motion.Advance(PlayerHudResourceMotion.AttackMilliseconds);
        Assert.Equal(1f, motion.Shield.Presence);
        Assert.Equal(1f, motion.Shield.DisplayFraction);
        Assert.Equal(0f, motion.EmptyMix);

        // Shield expires: Grace window holds presence (frame anti-flicker), switches fill to desaturated ghost, and shows 0 readout
        motion.Observe(baseVitals);
        motion.Advance(240);
        Assert.Equal(1f, motion.Shield.Presence);
        Assert.Equal(1f, motion.Shield.DisplayFraction);
        Assert.Equal(0, motion.ResolveShieldDisplay(baseVitals).Shield);
        Assert.Equal(1f, motion.EmptyMix);

        // Re-acquiring temporary shield during grace window snaps back to active bright shield without dip/flicker
        motion.Observe(tempShield);
        Assert.Equal(1f, motion.Shield.Presence);
        Assert.Equal(1f, motion.Shield.DisplayFraction);
        Assert.Equal(200, motion.ResolveShieldDisplay(tempShield).Shield);
        Assert.Equal(0f, motion.EmptyMix);

        // Final expiration: holds 360ms as desaturated ghost with 0 readout, then dissolves smoothly over 480ms
        motion.Observe(baseVitals);
        motion.Advance(PlayerHudResourceMotion.GraceMilliseconds);
        Assert.Equal(1f, motion.Shield.Presence);
        Assert.Equal(1f, motion.Shield.DisplayFraction);
        Assert.Equal(0, motion.ResolveShieldDisplay(baseVitals).Shield);
        Assert.Equal(1f, motion.EmptyMix);

        motion.Advance(PlayerHudResourceMotion.ReleaseMilliseconds / 2);
        Assert.InRange(motion.Shield.Presence, 0.45f, 0.55f);
        Assert.Equal(1f, motion.Shield.DisplayFraction);
        Assert.Equal(0, motion.ResolveShieldDisplay(baseVitals).Shield);
        Assert.Equal(1f, motion.EmptyMix);

        motion.Advance(PlayerHudResourceMotion.ReleaseMilliseconds);
        Assert.Equal(0f, motion.Shield.Presence);
        Assert.False(motion.Shield.Active);
    }

    [Fact]
    public void MultiHitChipDamageWithinShortWindowTriggersAfterimageTrailAndShieldBreakPulse()
    {
        var v = Vitals();
        var motion = new PlayerHudResourceMotion();
        motion.Observe(v);

        // First 1.5% hit (< 2.5% per-frame threshold) starts accumulating in the 260ms window
        v = v with { Shield = 985 };
        motion.Observe(v);
        Assert.False(motion.Shield.Active);

        // Second 1.5% hit 50ms later brings cumulative window drop to 3.0% (>= 2.5%), triggering trail from 1.0!
        motion.Advance(50);
        v = v with { Shield = 970 };
        motion.Observe(v);
        Assert.True(motion.Shield.Active);
        Assert.True(motion.Shield.Loss > 0f);
        Assert.Equal(1.0f, motion.Shield.Trail, 2);

        // Third 1.5% hit 50ms later sustains the trail while Loss > 0
        motion.Advance(50);
        v = v with { Shield = 955 };
        motion.Observe(v);
        Assert.True(motion.Shield.Loss > 0.9f);

        // Combat hit breaking shield to 0 triggers BreakPulse
        v = v with { Shield = 0 };
        motion.Observe(v);
        Assert.Equal(1f, motion.Shield.BreakPulse);
        motion.Advance(PlayerHudResourceMotion.BreakDurationMilliseconds);
        Assert.Equal(0f, motion.Shield.BreakPulse);
    }

    [Fact]
    public void TemporaryShieldLayerExpiringOverDepletedBaseShieldHoldsBeforeEasing()
    {
        var depletedBase = Vitals() with { ShieldPresent = true, Shield = 0, ShieldMax = 500 };
        var motion = new PlayerHudResourceMotion();
        motion.Observe(depletedBase);
        Assert.Equal(1f, motion.EmptyMix);

        var withTempLayer = depletedBase with { Shield = 300, ShieldMax = 800 };
        motion.Observe(withTempLayer);
        motion.Advance(PlayerHudResourceMotion.EmptyTransitionMilliseconds);
        Assert.Equal(0f, motion.EmptyMix);
        Assert.Equal(0.375f, motion.Shield.DisplayFraction, 3);

        // Temporary layer expires untouched (capacity and maxCapacity both drop by 300)
        motion.Observe(depletedBase);
        Assert.True(motion.Shield.HoldingLayer);
        Assert.Equal(0.375f, motion.Shield.DisplayFraction, 3);
        Assert.Equal(300, motion.ResolveShieldDisplay(depletedBase).Shield, 1);
        Assert.Equal(0f, motion.EmptyMix);

        motion.Advance(PlayerHudResourceMotion.GraceMilliseconds);
        Assert.Equal(0.375f, motion.Shield.DisplayFraction, 3);
        motion.Advance(PlayerHudResourceMotion.ReleaseMilliseconds);
        Assert.False(motion.Shield.HoldingLayer);
        Assert.Equal(0f, motion.Shield.DisplayFraction, 3);
    }

    [Fact]
    public void ContinuousNaturalDecayDoesNotTriggerHitFlashWhileDiscreteLossDoes()
    {
        var v = Vitals();
        var motion = new PlayerHudResourceMotion();
        motion.Observe(v);

        // 1% continuous decay step (< 2.5% threshold) does not trigger hit flash
        v = v with { Shield = 990 };
        motion.Observe(v);
        Assert.False(motion.Shield.Active);
        Assert.Equal(0.99f, motion.Shield.Trail, 3);

        // 30% discrete combat hit (>= 2.5% threshold) triggers hit trail & flash
        v = v with { Shield = 690 };
        motion.Observe(v);
        Assert.True(motion.Active);
        Assert.Equal(0.99f, motion.Shield.Trail, 3);
    }

    [Fact]
    public void ShieldReadoutThrottlesContinuousDecayAndSnapsOnBoundariesOrDiscreteHits()
    {
        var v = Vitals();
        var motion = new PlayerHudResourceMotion();
        motion.Observe(v);
        Assert.Equal(1000, motion.ResolveShieldDisplay(v).Shield);

        // Small continuous decay is throttled for 100ms
        var decayed = v with { Shield = 988 };
        motion.Observe(decayed);
        Assert.Equal(1000, motion.ResolveShieldDisplay(decayed).Shield);
        motion.Advance(PlayerHudResourceMotion.ReadoutThrottleMilliseconds);
        Assert.Equal(988, motion.ResolveShieldDisplay(decayed).Shield);

        // Discrete hit snaps immediately without waiting for throttle
        var hit = v with { Shield = 600 };
        motion.Observe(hit);
        Assert.Equal(600, motion.ResolveShieldDisplay(hit).Shield);

        // Depletion to 0 snaps immediately
        var broken = v with { Shield = 0 };
        motion.Observe(broken);
        Assert.Equal(0, motion.ResolveShieldDisplay(broken).Shield);
    }

    [Fact]
    public void ResistantBypassTransitionInterpolatesSmoothly()
    {
        var detail = new PlayerHudShield("finite", 500, false, new("full", 1, 0, 0));
        var v = Vitals() with { ShieldDetail = detail };
        var motion = new PlayerHudResourceMotion();
        motion.Observe(v);
        Assert.Equal(0f, motion.ResistantMix);

        v = v with { ShieldDetail = detail with { ResistsBypass = true } };
        motion.Observe(v);
        Assert.True(motion.Active);
        motion.Advance(PlayerHudResourceMotion.ResistantTransitionMilliseconds / 2);
        Assert.InRange(motion.ResistantMix, 0.45f, 0.55f);
        motion.Advance(PlayerHudResourceMotion.ResistantTransitionMilliseconds);
        Assert.Equal(1f, motion.ResistantMix);
    }

    [Fact]
    public void DecorationBudgetUsesSustainedNativeCostAndRecoversWithoutStopping()
    {
        var budget=new PlayerHudDecorationBudget();
        for(var i=0;i<15;i++)budget.Observe(50); // cold font/raster setup is excluded
        Assert.Equal(1,budget.FrameStride);
        for(var i=0;i<29;i++)budget.Observe(9);
        Assert.Equal(1,budget.FrameStride);budget.Observe(9);Assert.Equal(2,budget.FrameStride);
        for(var i=0;i<119;i++)budget.Observe(2);
        Assert.Equal(2,budget.FrameStride);budget.Observe(2);Assert.Equal(1,budget.FrameStride);
        budget.Observe(double.NaN);budget.Observe(-1);Assert.Equal(1,budget.FrameStride);
    }

    private static SKBitmap Ring(PlayerHudVitals v,int frame,PlayerHudResourceMotion motion=null)
    {
        var image=new SKBitmap(200,200,SKColorType.Bgra8888,SKAlphaType.Premul);
        using var canvas=new SKCanvas(image);canvas.Clear(SKColors.Transparent);canvas.Translate(100,100);canvas.Scale(2);
        PlayerHudResourceOverlay.ShieldRing(canvas,v,frame,motion?.Shield);
        return image;
    }

    [Fact]
    public void ShieldFlowChangesFilledPixelsWithoutMovingTheMeterGeometry()
    {
        var v=Vitals();using var a=Ring(v,0);using var b=Ring(v,45);
        var changed=0;
        for(var y=0;y<200;y++)for(var x=0;x<200;x++)
        {
            var p=a.GetPixel(x,y);var q=b.GetPixel(x,y);
            Assert.Equal(p.Alpha>0,q.Alpha>0);
            if(p!=q)changed++;
        }
        Assert.True(changed>20,"The stored amount must have visible bounded flow even after Flash drops its tier.");
    }

    [Fact]
    public void EmptyShieldSettlesWithoutPermanentFlashesAndUnknownStateHasNoCyanFill()
    {
        var v=Vitals();var motion=new PlayerHudResourceMotion();motion.Observe(v);
        v=v with {Shield=0};motion.Observe(v);
        using var hit=Ring(v,0,motion);motion.Advance(300);using var settled=Ring(v,0,motion);
        using var later=Ring(v,90,motion);
        Assert.NotEqual(hit.Bytes,settled.Bytes);Assert.Equal(settled.Bytes,later.Bytes);
        using var unknown=Ring(v with {Shield=1000,ShieldReady=false},0);
        Assert.Equal(settled.Bytes,unknown.Bytes);
    }

    [Fact]
    public void NativeBudgetThinsIdleFramesButKeepsHitFeedbackAndClearsItAfterHide()
    {
        var v=Vitals();var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
        var model=new PlayerInfoAnimationModel();model.ApplyProduction(v);
        using var widget=new PlayerInfoWidget(assets,model){LiveVitals=v};
        for(var i=0;i<45;i++)widget.DecorationBudget.Observe(10);
        var idle=0;for(var i=0;i<12;i++)if(widget.AdvanceLiveDecoration(17))idle++;
        Assert.InRange(idle,2,4);
        widget.LiveVitals=v with {Shield=0};
        var feedback=0;for(var i=0;i<12;i++)if(widget.AdvanceLiveDecoration(17))feedback++;
        Assert.InRange(feedback,5,7);Assert.Equal(0,widget.LiveVitals.Shield);
        widget.ClearResourceFeedback();
        var resumed=0;for(var i=0;i<12;i++)if(widget.AdvanceLiveDecoration(17))resumed++;
        Assert.InRange(resumed,2,4);
    }

    [Fact]
    public void FullSizePoisePercentFitsWithoutShrinkingIntoTheFill()
    {
        using var glyphs=new PlayerHudNumberGlyphs();
        var width=glyphs.Measure(PlayerInfoPathGlyphAtlas.Aero,"100%",11.5f);
        Assert.True(width<=PlayerHudResourceLayout.PoisePercentWidth);
        Assert.True(PlayerHudResourceLayout.PoisePercentX+width+3<=PlayerHudResourceLayout.PoiseBar.Left);
    }

    [Fact]
    public void CaptureMotionFramesForReviewWhenRequested()
    {
        var output=Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE_DIR");
        if(Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE")!="1"||string.IsNullOrEmpty(output))return;
        Directory.CreateDirectory(output);
        for(var i=0;i<60;i++)
        {
            var v=Vitals();using var bitmap=new SKBitmap(240,240,SKColorType.Bgra8888,SKAlphaType.Premul);
            using(var canvas=new SKCanvas(bitmap))
            {
                canvas.Clear(new SKColor(23,28,30));canvas.Translate(120,120);canvas.Scale(2.4f);
                PlayerHudResourceOverlay.ShieldRing(canvas,v,i*3);
            }
            using var image=SKImage.FromBitmap(bitmap);using var data=image.Encode(SKEncodedImageFormat.Png,100);
            using var file=File.Create(Path.Combine(output,$"shield-motion-{i:D2}.png"));data.SaveTo(file);
        }
    }
}
