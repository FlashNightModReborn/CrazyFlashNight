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
