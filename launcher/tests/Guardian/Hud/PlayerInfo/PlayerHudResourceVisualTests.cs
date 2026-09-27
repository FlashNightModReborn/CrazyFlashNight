using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Threading;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudResourceVisualTests
{
    private static string Root()
    {
        var d=new DirectoryInfo(AppContext.BaseDirectory);
        while(d!=null){if(File.Exists(Path.Combine(d.FullName,"AGENTS.md")))return d.FullName;d=d.Parent;}
        throw new DirectoryNotFoundException();
    }
    private static PlayerHudVitals Vitals()
    {
        RuntimeFontCatalog.Configure(Root());
        var state=new PlayerHudState();Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()),1));
        return state.Snapshot.Vitals with { Hp=1000,HpMax=1000,Mp=600,MpMax=600,Shield=300,ShieldMax=1000,
            ShieldReady=true,ShieldPresent=true,Poise=1,PoiseDetail=new(0.45,true,"buffer"),PoiseVisual=new(false,false,false),
            ShieldDetail=new("finite",99999,true,new("waiting",0.6,1600,4000)) };
    }
    private static Bitmap Resource(PlayerHudVitals value, int frame = 0)
    {
        var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
        var plan=PlayerInfoRasterPlanner.Create(assets,new Rectangle(0,0,1024,576),1);
        using var batch=new PlayerInfoSvgRasterizer().Bake(plan,CancellationToken.None);
        var model=new PlayerInfoAnimationModel();model.ApplyProduction(value);
        using var widget=new PlayerInfoWidget(assets,model){LiveVitals=value};
        widget.AdvanceLiveDecoration((int)Math.Ceiling(frame*1000d/30));
        using var crop=new Bitmap(plan.TightPhysicalBounds.Width,plan.TightPhysicalBounds.Height,PixelFormat.Format32bppPArgb);
        widget.Paint(crop,batch,plan);
        var image=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
        using(var g=Graphics.FromImage(image))g.DrawImageUnscaled(crop,plan.TightPhysicalBounds.Location);
        return image;
    }
    private static Bitmap Poise(PlayerHudVitals value)
    {
        var image=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
        using var cells=new GraphicsPath();foreach(var cell in PlayerHudBarArtData.Cells)cells.AddPolygon(cell);
        using var g=Graphics.FromImage(image);PlayerHudPoisePainter.Paint(g,value,cells);return image;
    }
    private static int Difference(Bitmap a,Bitmap b,RectangleF bounds)
    {
        var result=0;var r=Rectangle.Ceiling(bounds);
        for(var y=r.Top;y<r.Bottom;y++)for(var x=r.Left;x<r.Right;x++)if(a.GetPixel(x,y)!=b.GetPixel(x,y))result++;
        return result;
    }

    [Fact]
    public void FullShieldRingHasLeftViewportMarginAndRecoveryDoesNotAlterStrengthOrCapacity()
    {
        var value=Vitals() with {Shield=1000};using var full=Resource(value);
        var cyan=0;var minimum=1000;
        for(var y=474;y<554;y++)for(var x=0;x<90;x++)
        {
            var c=full.GetPixel(x,y);if(c.R<20&&c.G>100&&Math.Abs(c.G-c.B)<3){cyan++;minimum=Math.Min(minimum,x);}
        }
        Assert.True(cyan>150);Assert.True(minimum>=4,"The left-shifted ring must preserve its four-unit viewport safety margin.");
        using var before=Resource(value with {ShieldDetail=value.ShieldDetail with {Recovery=new("waiting",0,4000,4000)}});
        using var after=Resource(value with {ShieldDetail=value.ShieldDetail with {Recovery=new("waiting",0.9,400,4000)}});
        Assert.Equal(0,Difference(before,after,PlayerHudResourceLayout.ShieldStrengthPlaque));
        Assert.True(Difference(before,after,PlayerHudResourceLayout.ShieldCapacityPlaque)>300);
        Assert.Equal(0,Difference(before,after,new RectangleF(0,508,90,45)));
    }

    [Fact]
    public void TrueDamageResistanceColorsOnlyThePlaqueAndRemainsDistinctWhenDepleted()
    {
        var value=Vitals();using var resistant=Resource(value);
        using var normal=Resource(value with {ShieldDetail=value.ShieldDetail with {ResistsBypass=false}});
        Assert.True(Difference(resistant,normal,PlayerHudResourceLayout.ShieldStrengthPlaque)>300);
        Assert.Equal(0,Difference(resistant,normal,PlayerHudResourceLayout.ShieldCapacityPlaque));
        using var emptyResistant=Resource(value with {Shield=0});
        using var emptyNormal=Resource(value with {Shield=0,ShieldDetail=value.ShieldDetail with {ResistsBypass=false}});
        Assert.True(Difference(emptyResistant,emptyNormal,PlayerHudResourceLayout.ShieldStrengthPlaque)>300);
    }

    [Fact]
    public void AirborneAndRigidAreIndependentLayersWithDimPoiseReference()
    {
        var value=Vitals();using var normal=Poise(value);
        var airborne=value with {PoiseVisual=new(true,false,false),PoiseDetail=value.PoiseDetail with {Phase="air"}};
        using var air=Poise(airborne);using var emptyAir=Poise(airborne with {Poise=0});
        using var combined=Poise(airborne with {PoiseVisual=new(true,true,false)});
        using var repeated=Poise(airborne);
        var bounds=PlayerHudResourceLayout.PoiseBar;
        Assert.True(Difference(air,emptyAir,bounds)>50,"Airborne must retain a dim reference instead of clearing all fill geometry.");
        Assert.True(Difference(air,combined,bounds)>30,"Rigid metal edges must remain visible beneath the airborne texture.");
        Assert.Equal(0,Difference(air,repeated,bounds));
        var bright=0;var normalBright=0;var rect=Rectangle.Ceiling(bounds);
        for(var y=rect.Top;y<rect.Bottom;y++)for(var x=rect.Left;x<rect.Right;x++)
        {
            var c=air.GetPixel(x,y);if(c.R>200&&c.G>140&&c.B<80)bright++;
            c=normal.GetPixel(x,y);if(c.R>200&&c.G>140&&c.B<80)normalBright++;
        }
        Assert.True(bright>0,"The underlying poise layer should survive instead of switching the whole fill to gray.");
        Assert.True(bright<normalBright*0.85,"The inactive texture must visibly mark the underlying fill as unavailable.");
        Assert.True(Difference(normal,air,bounds)>200);
    }

    [Fact]
    public void OverflowAddsGeometryInsideEachResourceWithoutBorrowingShieldCapacity()
    {
        var value=Vitals();using var normal=Resource(value);
        using var hp=Resource(value with {Hp=1400});using var mp=Resource(value with {Mp=900});
        Assert.True(Difference(normal,mp,PlayerHudResourceLayout.MpBar)>100);
        var warm=0;
        for(var y=478;y<552;y++)for(var x=12;x<89;x++)
        {
            var dx=x-(37.75+PlayerHudResourceLayout.HpOffsetX);var dy=y-514.65;
            var radius=Math.Sqrt(dx*dx+dy*dy);var c=hp.GetPixel(x,y);
            if(radius>28&&radius<32.5&&c.R>190&&c.G>120&&c.B<200)warm++;
        }
        Assert.True(warm>20,"HP overflow must have an internal warm second layer beyond its numerical percent.");
        Assert.Equal(0,Difference(normal,hp,PlayerHudResourceLayout.ShieldPlaque));
        Assert.Equal(0,Difference(normal,mp,PlayerHudResourceLayout.ShieldPlaque));
    }

    [Fact]
    public void SmallHpOverflowRemainsVisibleAcrossTheAuthoredMotion()
    {
        var value=Vitals();var output=Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE_DIR");
        foreach(var frame in new[]{0,17,49,73,99})
        {
            using var normal=Resource(value,frame);
            foreach(var extra in new[]{10,50,280,500})
            {
                using var inlay=Resource(value with {Hp=1000+extra},frame);
                var visible=0;
                for(var y=481;y<549;y++)for(var x=7;x<80;x++)
                {
                    var dx=x-(37.75+PlayerHudResourceLayout.HpOffsetX);var dy=y-514.65;
                    var radius=Math.Sqrt(dx*dx+dy*dy);
                    if(radius<27.5 || radius>33)continue;
                    var before=normal.GetPixel(x,y);var after=inlay.GetPixel(x,y);
                    if(after.R>100 && after.G>before.G+15)visible++;
                }
                Assert.True(visible>0,$"HP +{extra/10}% disappeared behind the cutouts at frame {frame}.");
                if(Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE")=="1" && !string.IsNullOrEmpty(output))
                {
                    Directory.CreateDirectory(output);
                    using var preview=new Bitmap(600,220,PixelFormat.Format32bppPArgb);
                    using(var g=Graphics.FromImage(preview))
                    {
                        g.Clear(Color.FromArgb(28,32,34));g.ScaleTransform(2,2);g.DrawImageUnscaled(inlay,0,-470);
                    }
                    preview.Save(Path.Combine(output,$"hp-inlay-{100+extra/10}-{frame:D2}.png"));
                }
            }
        }
    }

    [Fact]
    public void ShieldAndOverflowGrowIntoTheSameQuadrantAsTheOriginalHp()
    {
        var value=Vitals() with {Shield=250};using var quarter=Resource(value);
        using var normal=Resource(value with {Shield=0});using var extra=Resource(value with {Shield=0,Hp=1250});
        var leftCyan=0;var rightCyan=0;var leftWarm=0;var rightWarm=0;
        for(var y=475;y<514;y++)for(var x=0;x<83;x++)
        {
            var dx=x-(37.75+PlayerHudResourceLayout.HpOffsetX);var dy=y-514.65;
            var radius=Math.Sqrt(dx*dx+dy*dy);var c=quarter.GetPixel(x,y);
            if(radius>34 && radius<39 && c.R<40 && c.G>130 && c.B>130)
            {if(dx<0)leftCyan++;else rightCyan++;}
            var before=normal.GetPixel(x,y);var after=extra.GetPixel(x,y);
            if(radius>26 && radius<33 && after.G>before.G+25)
            {if(dx<0)leftWarm++;else rightWarm++;}
        }
        Assert.True(leftCyan>25);Assert.Equal(0,rightCyan);
        Assert.True(leftWarm>25);Assert.Equal(0,rightWarm);
        var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
        Assert.Equal(-90,assets.Gauges["hp"].Clip.StartAngleDegrees);
        Assert.Equal("counterclockwise",assets.Gauges["hp"].Clip.Direction);
    }

    [Fact]
    public void OverflowUnderlapsTheCenterAtEveryCardinalEdgeWithoutColoringTheFace()
    {
        var value=Vitals();using var normal=Resource(value);using var extra=Resource(value with {Hp=2000});
        var centerX=37.75+PlayerHudResourceLayout.HpOffsetX;const double centerY=514.65;
        // The old inner radius 28.8 left this entire strip below it uncovered.
        foreach(var angle in new[]{-90,0,90,180})
        {
            var filled=0;
            for(var y=488;y<542;y++)for(var x=16;x<71;x++)
            {
                var dx=x-centerX;var dy=y-centerY;var radius=Math.Sqrt(dx*dx+dy*dy)/0.8472137451;
                if(radius<27.55 || radius>28.65)continue;
                var degrees=Math.Atan2(dy,dx)*180/Math.PI;
                var distance=Math.Abs(degrees-angle);distance=Math.Min(distance,360-distance);
                if(distance>20)continue;
                if(extra.GetPixel(x,y).G>normal.GetPixel(x,y).G+10)filled++;
            }
            Assert.True(filled>0,$"Uncovered original inner edge at {angle} degrees.");
        }
        // Opaque authored center remains in front; choose a text-free point on its face.
        Assert.Equal(normal.GetPixel(43,537),extra.GetPixel(43,537));
    }

    [Fact]
    public void AuthoredDigitsKeepFiveDigitStrengthAndUseChineseUnitsForExceptionalStrength()
    {
        RuntimeFontCatalog.Configure(Root());using var glyphs=new PlayerHudNumberGlyphs();
        float Measure(string text)=>glyphs.Measure(PlayerInfoPathGlyphAtlas.Aero,text,11);
        Assert.Equal("99999",PlayerHudNumberFormat.Fit(99999,Measure,40));
        var compact=PlayerHudNumberFormat.Fit(99999999,Measure,40);
        Assert.Equal("9999万",compact);Assert.True(Measure(compact)<=40);
        float MpMeasure(string text)=>glyphs.Measure(PlayerInfoPathGlyphAtlas.Aero,text,13.0048f);
        var mp=PlayerHudNumberFormat.Fit(99999999,MpMeasure,43);
        Assert.Equal("9999万",mp);
        Assert.True(13.0048f*Math.Min(1,43/MpMeasure(mp))>=10.5f);
    }

    [Theory]
    [InlineData("ground",false,false,"waiting")]
    [InlineData("air",true,false,"waiting")]
    [InlineData("rigid",false,true,"waiting")]
    [InlineData("air-rigid",true,true,"waiting")]
    [InlineData("charging",false,false,"charging")]
    [InlineData("health-blocked",false,false,"health")]
    [InlineData("mp-blocked",false,false,"mp")]
    public void StateMatrixRemainsInsideResourceArea(string name,bool airborne,bool rigid,string recovery)
    {
        var value=Vitals();value=value with {PoiseVisual=new(airborne,rigid,false),
            PoiseDetail=value.PoiseDetail with {Phase=airborne?"air":rigid?"rigid":"buffer"},
            Shield=recovery is "health" or "mp"?0:300,
            ShieldDetail=value.ShieldDetail with {Recovery=recovery=="waiting"?value.ShieldDetail.Recovery:new(recovery,recovery=="charging"?1:0,0,0)}};
        using var image=Resource(value);using var poise=Poise(value);
        using(var g=Graphics.FromImage(image))g.DrawImageUnscaled(poise,0,0);
        Assert.Equal(0,image.GetPixel(310,490).A);
        if(Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE")=="1")
        {
            var output=Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE_DIR")??Path.Combine(Root(),"tmp","player-info-full");Directory.CreateDirectory(output);
            using var preview=new Bitmap(300,110,PixelFormat.Format32bppPArgb);
            using(var g=Graphics.FromImage(preview)){g.Clear(Color.FromArgb(18,24,28));g.DrawImageUnscaled(image,0,-470);}
            preview.Save(Path.Combine(output,"hud-state-"+name+".png"));
        }
    }
}
