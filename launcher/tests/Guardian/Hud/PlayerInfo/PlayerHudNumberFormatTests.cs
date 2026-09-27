using System;
using System.IO;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudNumberFormatTests
{
    private static float Measure(string text) => text.Length * 8;
    [Theory]
    [InlineData(7, "7")]
    [InlineData(23, "23")]
    [InlineData(-5, "-5")]
    [InlineData(9999, "9999")]
    public void SmallAndCriticalCountsRetainExactIntegers(double value, string expected)
        => Assert.Equal(expected, PlayerHudNumberFormat.Fit(value, Measure, 24, 100000000));

    [Fact]
    public void CompactValuesKeepMagnitudeWithoutRoundingUpToAnotherUnit()
    {
        Assert.Equal("12.3万", PlayerHudNumberFormat.Fit(123456, Measure, 40));
        Assert.Equal("9999万", PlayerHudNumberFormat.Fit(99999999, Measure, 40));
        Assert.Equal("1.23亿", PlayerHudNumberFormat.Fit(123456789, Measure, 40));
        Assert.DoesNotContain("∞", PlayerHudNumberFormat.Fit(double.MaxValue, Measure, 48));
    }

    [Theory]
    [InlineData("∞")]
    [InlineData("--")]
    [InlineData("未知")]
    [InlineData("12+")]
    public void NonNumericAmmoIsNotInventedAsZero(string value)
        => Assert.Equal(value, PlayerHudNumberFormat.FitText(value, Measure, 8));

    [Fact]
    public void PairedCountsKeepSmallLoadedAmmoAndCompactOnlyTheLargeReserve()
    {
        var text = PlayerHudNumberFormat.FitText("7 / 123456789", Measure, 64);
        Assert.StartsWith("7/", text); Assert.Contains("亿", text); Assert.True(Measure(text) <= 64);
    }

    [Theory]
    [InlineData("--/123456789","--/",true)]
    [InlineData("12+/123456789","12+/",true)]
    [InlineData("123456789/--","/--",false)]
    public void MixedAmmoPairsRetainMarkersAndFormatTheNumericSide(string value,string marker,bool prefix)
    {
        var formatted=PlayerHudNumberFormat.FormatText(value,Measure,64);
        if(prefix)Assert.StartsWith(marker,formatted.Text);else Assert.EndsWith(marker,formatted.Text);
        Assert.Contains("亿",formatted.Text);Assert.True(Measure(formatted.Text)<=64);
        Assert.Equal("75 / 4",PlayerHudNumberFormat.FitText("75 / 4",Measure,64));
    }

    [Fact]
    public void APositiveFractionalShieldStrengthIsNotPresentedAsZero()
    {
        var shield=new PlayerHudShield("finite",0.3,false,new("manual",0,0,0));
        Assert.Equal("0.3",PlayerHudResourceStyle.ShieldStrengthReadout(shield));
        Assert.Equal("0.3",PlayerHudNumberFormat.FitText("0.3",Measure,40));
    }

    private static void ConfigureFonts()
    {
        var directory=new DirectoryInfo(AppContext.BaseDirectory);
        while(directory!=null && !File.Exists(Path.Combine(directory.FullName,"fonts","fonts.xml")))directory=directory.Parent;
        Assert.NotNull(directory);RuntimeFontCatalog.Configure(directory.FullName);
    }

    [Fact]
    public void ReportedShieldSequenceKeepsUnitsPrecisionAndFontReservation()
    {
        ConfigureFonts();using var glyphs=new PlayerHudNumberGlyphs();
        float MeasureActual(string text)=>glyphs.Measure(PlayerInfoPathGlyphAtlas.Aero,text,11.5f);
        Assert.True(MeasureActual("149000/169695")>91);
        Assert.True(MeasureActual("118397/169695")<91); // the old policy switched back to raw here
        string maximum=null;float? reserved=null;
        foreach(var amount in new[]{169695,149000,118397,111111,100001,149111,118888})
        {
            var result=PlayerHudNumberFormat.FormatText(amount+"/169695",MeasureActual,91);
            var pair=result.Text.Split('/');Assert.EndsWith("万",pair[0]);Assert.EndsWith("万",pair[1]);
            maximum??=pair[1];reserved??=result.ReservedWidth;
            Assert.Equal(maximum,pair[1]);Assert.Equal(reserved.Value,result.ReservedWidth);
            Assert.True(MeasureActual(result.Text)<=91);
        }
    }

    [Fact]
    public void CompactTemplateRetainsTrailingPrecisionAndCriticalSmallCounts()
    {
        Assert.Equal("12.0万",PlayerHudNumberFormat.Fit(120000,Measure,40,169695));
        Assert.Equal("11.1万",PlayerHudNumberFormat.Fit(111111,Measure,40,169695));
        Assert.StartsWith("7/",PlayerHudNumberFormat.FitText("7/169695",Measure,64));
        Assert.EndsWith("万",PlayerHudNumberFormat.FitText("7/169695",Measure,91));
        Assert.Equal("0",PlayerHudNumberFormat.Fit(0,Measure,40,169695));
    }

    [Fact]
    public void NarrowDigitsCannotRestoreRawHpMpOrAmmoWithinTheSameMagnitudeBand()
    {
        ConfigureFonts();using var glyphs=new PlayerHudNumberGlyphs();
        foreach(var font in new[]{PlayerInfoPathGlyphAtlas.Aero,PlayerInfoPathGlyphAtlas.LcdStd})
        {
            float Width(string text)=>glyphs.Measure(font,text,13.0048f);
            PlayerHudNumberText? previous=null;
            foreach(var amount in new[]{99999999,11111111,12345678,10000000})
            {
                var result=PlayerHudNumberFormat.Format(amount,Width,43,99999999);
                Assert.EndsWith("万",result.Text);
                if(previous.HasValue)Assert.Equal(previous.Value.ReservedWidth,result.ReservedWidth);
                previous=result;
            }
        }
        // GDI ammo uses the same formatter, including a separate small loaded-count budget.
        float Proportional(string text){var width=0f;foreach(var c in text)width+=c=='1'?2:8;return width;}
        foreach(var amount in new[]{123456789,111111111,199999999})
            Assert.Contains("亿",PlayerHudNumberFormat.FitText("7/"+amount,Proportional,64));
    }
}
