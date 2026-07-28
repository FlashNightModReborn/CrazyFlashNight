#nullable enable

using System;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoPathGlyphAtlasTests
{
    [Fact]
    public void ExactAtlas_ContainsTwoSourceBoundFacesAndNoFontProgram()
    {
        Assert.Equal("0123456789/%MP-", PlayerInfoPathGlyphAtlasData.Characters);
        Assert.Equal(2, PlayerInfoPathGlyphAtlasData.Fonts.Length);
        Assert.Equal(
            new[] { "aero", "lcd-std" },
            PlayerInfoPathGlyphAtlasData.Fonts
                .Select(font => font.Id)
                .OrderBy(value => value, StringComparer.Ordinal));
        Assert.All(PlayerInfoPathGlyphAtlasData.Fonts, font =>
        {
            Assert.Equal(1024, font.UnitsPerEm);
            Assert.Equal(0, font.FsType);
            Assert.Equal(15, font.Glyphs.Length);
            Assert.Equal(
                PlayerInfoPathGlyphAtlasData.Characters.OrderBy(value => value),
                font.Glyphs
                    .Select(glyph => glyph.Character)
                    .OrderBy(value => value));
            Assert.All(font.Glyphs, glyph =>
            {
                Assert.True(glyph.Advance > 0);
                Assert.False(string.IsNullOrWhiteSpace(glyph.PathData));
            });
        });

        string[] resources = typeof(PlayerInfoPathGlyphAtlas).Assembly
            .GetManifestResourceNames();
        Assert.DoesNotContain(resources, name =>
            name.EndsWith(".ttf", StringComparison.OrdinalIgnoreCase) ||
            name.EndsWith(".otf", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Atlas_MeasuresAndBuildsDeterministicDevicePath()
    {
        using var atlas = new PlayerInfoPathGlyphAtlas();

        Assert.Equal(
            new[] { "aero", "lcd-std" },
            atlas.FontIds);
        float measured = atlas.MeasureText(
            PlayerInfoPathGlyphAtlas.Aero,
            "00100/10000",
            13f);
        using SKPath path = atlas.BuildTextPath(
            PlayerInfoPathGlyphAtlas.Aero,
            "00100/10000",
            13f,
            120f,
            24f,
            PlayerInfoPathTextAlignment.Right);

        Assert.True(measured > 0);
        Assert.False(path.IsEmpty);
        // Alignment is based on authored advances. Aero has a small positive
        // right ink overhang, so the outline may extend beyond the advance anchor.
        Assert.InRange(path.Bounds.Right, 120f, 120.5f);
        Assert.True(path.Bounds.Left < path.Bounds.Right);
        Assert.True(path.Bounds.Top < path.Bounds.Bottom);
    }

    [Fact]
    public void Atlas_FailsClosedForUnknownFaceOrGlyph()
    {
        using var atlas = new PlayerInfoPathGlyphAtlas();

        Assert.Throws<InvalidDataException>(() =>
            atlas.MeasureText("system-fallback", "1", 12f));
        Assert.Throws<InvalidDataException>(() =>
            atlas.MeasureText(PlayerInfoPathGlyphAtlas.Aero, "A", 12f));
    }

    [Fact]
    public void Atlas_DisposeIsIdempotentAndRejectsLaterUse()
    {
        var atlas = new PlayerInfoPathGlyphAtlas();

        atlas.Dispose();
        atlas.Dispose();

        Assert.Throws<ObjectDisposedException>(() =>
            atlas.MeasureText(PlayerInfoPathGlyphAtlas.LcdStd, "1", 12f));
    }
}
