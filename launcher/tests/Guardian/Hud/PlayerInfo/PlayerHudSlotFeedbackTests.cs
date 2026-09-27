using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudSlotFeedbackTests
{
    [Fact]
    public void SealPortsAndLampCornersAreBoundToTheActualAuthoredSvg()
    {
        var svg = XDocument.Parse(Encoding.UTF8.GetString(PlayerHudArtData.Get("slot-detail")));
        XNamespace ns = "http://www.w3.org/2000/svg";
        var authored = new List<PlayerHudSlotFeedbackGeometry.Segment>();
        foreach (var path in svg.Descendants(ns + "path"))
        {
            float[] Numbers(string value) => Regex.Matches(value, @"-?\d+(?:\.\d+)?")
                .Select(m => float.Parse(m.Value, CultureInfo.InvariantCulture)).ToArray();
            var matrix = Numbers((string)path.Parent.Attribute("transform"));
            var coordinates = Numbers((string)path.Attribute("d"));
            Assert.Equal(6, coordinates.Length);
            Assert.Equal(PlayerHudSlotFeedbackGeometry.FrameLineWidth,
                float.Parse((string)path.Attribute("stroke-width"), CultureInfo.InvariantCulture));
            PointF Map(int index) => new(matrix[0]*coordinates[index] + matrix[2]*coordinates[index+1] + matrix[4] + 13,
                matrix[1]*coordinates[index] + matrix[3]*coordinates[index+1] + matrix[5] + 13.1f);
            authored.Add(new(Map(0), Map(2))); authored.Add(new(Map(2), Map(4)));
        }
        var actual = PlayerHudSlotFeedbackGeometry.Corners.ToArray();
        Assert.Equal(authored.Count, actual.Length);
        for (var i=0; i<actual.Length; i++)
        {
            Near(authored[i].Start, actual[i].Start); Near(authored[i].End, actual[i].End);
        }
        var seal = PlayerHudSlotFeedbackGeometry.Seal.ToArray();
        Assert.Equal(3, seal.Length);
        Near(authored[1].End, seal[0].Start); Near(authored[4].Start, seal[0].End);
        Near(authored[0].End, seal[1].Start); Near(authored[4].End, seal[1].End);
        Near(authored[0].Start, seal[2].Start); Near(authored[5].End, seal[2].End);
    }

    [Fact]
    public void SealPreservesFixedTextBandsAndAllThreeCornerConnections()
    {
        var visible = PlayerHudSlotFeedbackGeometry.VisibleSeal.ToArray();
        foreach (var line in PlayerHudSlotFeedbackGeometry.Seal)
        {
            Assert.Contains(visible, s => s.Start == line.Start);
            Assert.Contains(visible, s => s.End == line.End);
        }
        foreach (var line in visible)
        foreach (var reserve in new[] { PlayerHudSlotFeedbackGeometry.BadgeReserve, PlayerHudSlotFeedbackGeometry.CaptionReserve })
        for (var step=1; step<100; step++)
        {
            var x=line.Start.X+(line.End.X-line.Start.X)*step/100;
            var y=line.Start.Y+(line.End.Y-line.Start.Y)*step/100;
            Assert.False(x>reserve.Left+0.001f && x<reserve.Right-0.001f && y>reserve.Top+0.001f && y<reserve.Bottom-0.001f);
        }
        Assert.Equal(PlayerHudBottomWidget.HotkeyRect(new(0,0,26,26)), PlayerHudSlotFeedbackGeometry.CaptionReserve);
    }

    [Fact]
    public void EmptyBankAndMissingMpOrItemsShareOneSealAndNoBreathingAnimation()
    {
        using var skill = Paint("blocked", "mp", true, 0);
        using var item = Paint("blocked", "item", true, 750);
        using var bank = Paint("blocked", "empty", false, 1200);
        Assert.Equal(Pixels(skill), Pixels(item)); Assert.Equal(Pixels(skill), Pixels(bank));
    }

    [Fact]
    public void CornerBreathIsVisibleOnARedIconWithoutCoveringItsCentre()
    {
        using var low = Paint("last", "mp", true, 0);
        using var high = Paint("last", "mp", true, 750);
        using var next = Paint("last", "mp", true, 1500);
        Assert.Equal(Pixels(low), Pixels(next));
        var difference = 0;
        var bounds = PlayerHudSlotFeedbackGeometry.MaximumPaintBounds; bounds.Offset(10,10);
        for (var y=0; y<low.Height; y++) for (var x=0; x<low.Width; x++)
        {
            var a=low.GetPixel(x,y); var b=high.GetPixel(x,y);
            if(a==b) continue;
            Assert.True(bounds.Contains(x,y), $"Corner light leaked: {x},{y}");
            difference += Math.Abs(b.R-a.R)+Math.Abs(b.G-a.G)+Math.Abs(b.B-a.B);
        }
        Assert.True(difference>5000, "Corner brightness must change against a red icon");
        for(var y=18;y<28;y++) for(var x=18;x<28;x++) Assert.Equal(low.GetPixel(x,y),high.GetPixel(x,y));
        using var cooling0 = Paint("last", "mp", false, 0);
        using var cooling1 = Paint("last", "mp", false, 750);
        Assert.Equal(Pixels(cooling0),Pixels(cooling1));
    }

    private static Bitmap Paint(string state, string reason, bool ready, int clock)
    {
        var bitmap = new Bitmap(52,52,PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bitmap); g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.FromArgb(20,22,24));
        using var icon = new SolidBrush(Color.FromArgb(180,5,8)); g.FillRectangle(icon,11,11,24,24);
        PlayerHudResourceHintPainter.PaintSlot(g,new(10,10,26,26),new(state,reason),ready,clock,0);
        return bitmap;
    }
    private static int[] Pixels(Bitmap image) => Enumerable.Range(0,image.Height)
        .SelectMany(y=>Enumerable.Range(0,image.Width).Select(x=>image.GetPixel(x,y).ToArgb())).ToArray();
    private static void Near(PointF expected, PointF actual)
    {
        Assert.InRange(Math.Abs(expected.X-actual.X),0,0.0001f);
        Assert.InRange(Math.Abs(expected.Y-actual.Y),0,0.0001f);
    }
}
