#nullable enable

using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoPathGlyphAtlasTests
{
    [Fact]
    public void GeneratedSource_CanonicalCleanBytesMatchTrackedProvenance()
    {
        string projectRoot = FindProjectRoot();
        string generatedRelativePath =
            "launcher/src/Guardian/Hud/PlayerInfo/" +
            "PlayerInfoPathGlyphAtlas.Generated.cs";
        string generatedPath = Path.Combine(
            projectRoot,
            generatedRelativePath.Replace(
                '/',
                Path.DirectorySeparatorChar));
        string provenancePath = Path.Combine(
            projectRoot,
            "tools",
            "player-info-hud",
            "evidence",
            "b0-06",
            "glyph-atlas-provenance.json");

        byte[] workingTreeBytes = File.ReadAllBytes(generatedPath);
        Assert.False(HasUtf8Bom(workingTreeBytes));
        string workingTreeText =
            new UTF8Encoding(false, true).GetString(workingTreeBytes);
        // Match Git's text clean direction without invoking a git executable:
        // checkout CRLF becomes canonical LF, while a lone CR fails closed.
        string canonicalText = workingTreeText
            .Replace("\r\n", "\n", StringComparison.Ordinal);
        Assert.DoesNotContain('\r', canonicalText);
        byte[] canonicalBytes =
            new UTF8Encoding(false, true).GetBytes(canonicalText);
        Assert.False(HasUtf8Bom(canonicalBytes));

        using JsonDocument provenance =
            JsonDocument.Parse(File.ReadAllBytes(provenancePath));
        JsonElement output =
            provenance.RootElement.GetProperty("output");
        Assert.Equal(
            generatedRelativePath,
            output.GetProperty("path").GetString());
        Assert.Equal(
            "UTF-8 without BOM, LF",
            output.GetProperty("encoding").GetString());
        Assert.Equal(
            output.GetProperty("byteLength").GetInt32(),
            canonicalBytes.Length);
        Assert.Equal(
            output.GetProperty("sha256").GetString(),
            Convert.ToHexString(SHA256.HashData(canonicalBytes)));
    }

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
    public void DrawText_StrengthOnePointFiveMatchesOpaquePlusHalfAlphaGlowPasses()
    {
        const int width = 96;
        const int height = 64;
        using var atlas = new PlayerInfoPathGlyphAtlas();
        using var actual = NewBitmap(width, height);
        using var expected = NewBitmap(width, height);
        using var singlePass = NewBitmap(width, height);

        using (var canvas = new SKCanvas(actual))
        {
            canvas.Clear(SKColors.Transparent);
            atlas.DrawText(
                canvas,
                PlayerInfoPathGlyphAtlas.LcdStd,
                "100",
                20f,
                48f,
                38f,
                PlayerInfoPathTextAlignment.Center,
                SKColors.White,
                1f,
                1.5f,
                new SKColor(255, 0, 0, 255));
            canvas.Flush();
        }

        using SKPath path = atlas.BuildTextPath(
            PlayerInfoPathGlyphAtlas.LcdStd,
            "100",
            20f,
            48f,
            38f,
            PlayerInfoPathTextAlignment.Center);
        DrawExpectedText(expected, path, includeHalfAlphaPass: true);
        DrawExpectedText(singlePass, path, includeHalfAlphaPass: false);

        AssertBitmapsEqual(expected, actual);
        Assert.True(
            CountDifferentPixels(singlePass, actual) > 0,
            "The strength=1.5 result must retain a measurable half-alpha second glow pass.");
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

    private static SKBitmap NewBitmap(int width, int height) =>
        new(
            width,
            height,
            SKColorType.Bgra8888,
            SKAlphaType.Premul);

    private static void DrawExpectedText(
        SKBitmap bitmap,
        SKPath path,
        bool includeHalfAlphaPass)
    {
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        using var blur = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 1f);
        using var fullGlow = new SKPaint
        {
            IsAntialias = true,
            Style = SKPaintStyle.Fill,
            Color = new SKColor(255, 0, 0, 255),
            MaskFilter = blur
        };
        canvas.DrawPath(path, fullGlow);
        if (includeHalfAlphaPass)
        {
            using var halfGlow = new SKPaint
            {
                IsAntialias = true,
                Style = SKPaintStyle.Fill,
                Color = new SKColor(255, 0, 0, 128),
                MaskFilter = blur
            };
            canvas.DrawPath(path, halfGlow);
        }

        using var glyph = new SKPaint
        {
            IsAntialias = true,
            Style = SKPaintStyle.Fill,
            Color = SKColors.White
        };
        canvas.DrawPath(path, glyph);
        canvas.Flush();
    }

    private static void AssertBitmapsEqual(SKBitmap expected, SKBitmap actual)
    {
        Assert.Equal(expected.Width, actual.Width);
        Assert.Equal(expected.Height, actual.Height);
        for (var y = 0; y < expected.Height; y++)
        {
            for (var x = 0; x < expected.Width; x++)
            {
                Assert.Equal(expected.GetPixel(x, y), actual.GetPixel(x, y));
            }
        }
    }

    private static int CountDifferentPixels(SKBitmap left, SKBitmap right)
    {
        Assert.Equal(left.Width, right.Width);
        Assert.Equal(left.Height, right.Height);
        var count = 0;
        for (var y = 0; y < left.Height; y++)
        {
            for (var x = 0; x < left.Width; x++)
            {
                if (left.GetPixel(x, y) != right.GetPixel(x, y))
                {
                    count++;
                }
            }
        }
        return count;
    }

    private static bool HasUtf8Bom(byte[] bytes) =>
        bytes.Length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;

    private static string FindProjectRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(
                    directory.FullName,
                    "global.json")) &&
                File.Exists(Path.Combine(
                    directory.FullName,
                    "launcher",
                    "CRAZYFLASHER7MercenaryEmpire.csproj")) &&
                File.Exists(Path.Combine(
                    directory.FullName,
                    "tools",
                    "player-info-hud",
                    "evidence",
                    "b0-06",
                    "glyph-atlas-provenance.json")))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException(
            "Unable to locate the repository root from the executing test assembly.");
    }
}
