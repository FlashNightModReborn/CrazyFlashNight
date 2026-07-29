#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed record PlayerInfoPathGlyphData(
    char Character,
    int Advance,
    int LeftSideBearing,
    string PathData);

internal sealed record PlayerInfoPathFontData(
    string Id,
    string SourceFile,
    string SourceSha256,
    int SourceByteLength,
    int UnitsPerEm,
    int Ascent,
    int Descent,
    int FsType,
    PlayerInfoPathGlyphData[] Glyphs);

internal enum PlayerInfoPathTextAlignment
{
    Left,
    Center,
    Right
}

/// <summary>
/// Owns the small, source-bound path atlas used by PlayerInfo. It deliberately
/// has no system-font, GDI font, TTF, or fallback path.
/// </summary>
internal sealed class PlayerInfoPathGlyphAtlas : IDisposable
{
    internal const string LcdStd = "lcd-std";
    internal const string Aero = "aero";

    private Dictionary<string, FontFace>? _fonts;

    internal PlayerInfoPathGlyphAtlas()
    {
        var fonts = new Dictionary<string, FontFace>(StringComparer.Ordinal);
        try
        {
            foreach (var data in PlayerInfoPathGlyphAtlasData.Fonts)
            {
                if (string.IsNullOrWhiteSpace(data.Id) ||
                    data.UnitsPerEm <= 0 ||
                    data.SourceByteLength <= 0 ||
                    data.FsType != 0 ||
                    data.Glyphs.Length !=
                        PlayerInfoPathGlyphAtlasData.Characters.Length ||
                    !fonts.TryAdd(data.Id, new FontFace(data)))
                {
                    throw new InvalidDataException(
                        "PlayerInfo path-font metadata is invalid or duplicated.");
                }
            }
            if (fonts.Count != 2 ||
                !fonts.ContainsKey(LcdStd) ||
                !fonts.ContainsKey(Aero))
            {
                throw new InvalidDataException(
                    "PlayerInfo path atlas must contain exactly LCD Std and Aero.");
            }
            _fonts = fonts;
        }
        catch
        {
            foreach (var font in fonts.Values)
            {
                font.Dispose();
            }
            throw;
        }
    }

    internal IReadOnlyList<string> FontIds =>
        GetFonts().Keys.OrderBy(value => value, StringComparer.Ordinal).ToArray();

    internal float MeasureText(string fontId, string text, float fontPixels)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (!float.IsFinite(fontPixels) || fontPixels <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(fontPixels),
                "Path-font size must be finite and positive.");
        }
        var font = GetFont(fontId);
        var advance = 0L;
        foreach (var character in text)
        {
            advance = checked(advance + font.GetGlyph(character).Data.Advance);
        }
        return checked((float)(advance * (double)fontPixels / font.Data.UnitsPerEm));
    }

    internal SKPath BuildTextPath(
        string fontId,
        string text,
        float fontPixels,
        float anchorX,
        float baselineY,
        PlayerInfoPathTextAlignment alignment)
    {
        ArgumentNullException.ThrowIfNull(text);
        if (!float.IsFinite(fontPixels) || fontPixels <= 0 ||
            !float.IsFinite(anchorX) ||
            !float.IsFinite(baselineY))
        {
            throw new ArgumentOutOfRangeException(
                nameof(fontPixels),
                "Path-font geometry must be finite and the size positive.");
        }

        var font = GetFont(fontId);
        var scale = fontPixels / font.Data.UnitsPerEm;
        var measured = MeasureText(fontId, text, fontPixels);
        var originX = alignment switch
        {
            PlayerInfoPathTextAlignment.Left => anchorX,
            PlayerInfoPathTextAlignment.Center => anchorX - (measured / 2f),
            PlayerInfoPathTextAlignment.Right => anchorX - measured,
            _ => throw new ArgumentOutOfRangeException(nameof(alignment))
        };

        var combined = new SKPath
        {
            FillType = SKPathFillType.EvenOdd
        };
        try
        {
            var cursorUnits = 0;
            foreach (var character in text)
            {
                var glyph = font.GetGlyph(character);
                var matrix = new SKMatrix(
                    scale,
                    0f,
                    originX + (cursorUnits * scale),
                    0f,
                    -scale,
                    baselineY,
                    0f,
                    0f,
                    1f);
                using var transformed = new SKPath();
                glyph.Path.Transform(matrix, transformed);
                combined.AddPath(transformed);
                cursorUnits = checked(cursorUnits + glyph.Data.Advance);
            }
            return combined;
        }
        catch
        {
            combined.Dispose();
            throw;
        }
    }

    internal void DrawText(
        SKCanvas canvas,
        string fontId,
        string text,
        float fontPixels,
        float anchorX,
        float baselineY,
        PlayerInfoPathTextAlignment alignment,
        SKColor color,
        float glowSigmaPixels,
        float glowStrength,
        SKColor? glowColor)
    {
        ArgumentNullException.ThrowIfNull(canvas);
        if (!float.IsFinite(glowSigmaPixels) || glowSigmaPixels < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(glowSigmaPixels));
        }
        if (!float.IsFinite(glowStrength) ||
            (glowSigmaPixels == 0f &&
             (glowStrength != 0f || glowColor.HasValue)) ||
            (glowSigmaPixels > 0f &&
             (glowStrength != 1.5f || !glowColor.HasValue)))
        {
            throw new ArgumentOutOfRangeException(
                nameof(glowStrength),
                "PlayerInfo path text accepts either no glow or the exact source-derived strength 1.5 glow.");
        }

        using var path = BuildTextPath(
            fontId,
            text,
            fontPixels,
            anchorX,
            baselineY,
            alignment);
        if (glowSigmaPixels > 0)
        {
            using var blur = SKMaskFilter.CreateBlur(
                SKBlurStyle.Normal,
                glowSigmaPixels);
            var sourceColor = glowColor!.Value;
            using var fullGlow = new SKPaint
            {
                IsAntialias = true,
                Style = SKPaintStyle.Fill,
                Color = sourceColor.WithAlpha(255),
                MaskFilter = blur
            };
            using var halfGlow = new SKPaint
            {
                IsAntialias = true,
                Style = SKPaintStyle.Fill,
                Color = sourceColor.WithAlpha(128),
                MaskFilter = blur
            };
            canvas.DrawPath(path, fullGlow);
            canvas.DrawPath(path, halfGlow);
        }

        using var paint = new SKPaint
        {
            IsAntialias = true,
            Style = SKPaintStyle.Fill,
            Color = color
        };
        canvas.DrawPath(path, paint);
    }

    public void Dispose()
    {
        var fonts = System.Threading.Interlocked.Exchange(ref _fonts, null);
        if (fonts is null)
        {
            return;
        }
        foreach (var font in fonts.Values)
        {
            font.Dispose();
        }
    }

    private Dictionary<string, FontFace> GetFonts() =>
        _fonts ?? throw new ObjectDisposedException(nameof(PlayerInfoPathGlyphAtlas));

    private FontFace GetFont(string fontId)
    {
        if (string.IsNullOrEmpty(fontId) ||
            !GetFonts().TryGetValue(fontId, out var font))
        {
            throw new InvalidDataException(
                $"PlayerInfo path font '{fontId}' is not in the exact atlas.");
        }
        return font;
    }

    private sealed class FontFace : IDisposable
    {
        private Dictionary<char, Glyph>? _glyphs;

        internal FontFace(PlayerInfoPathFontData data)
        {
            Data = data;
            var glyphs = new Dictionary<char, Glyph>();
            try
            {
                foreach (var glyphData in data.Glyphs)
                {
                    if (glyphData.Advance <= 0 ||
                        string.IsNullOrWhiteSpace(glyphData.PathData) ||
                        PlayerInfoPathGlyphAtlasData.Characters.IndexOf(
                            glyphData.Character) < 0 ||
                        glyphs.ContainsKey(glyphData.Character))
                    {
                        throw new InvalidDataException(
                            $"PlayerInfo path glyph '{glyphData.Character}' is invalid.");
                    }
                    var path = SKPath.ParseSvgPathData(glyphData.PathData) ??
                        throw new InvalidDataException(
                            $"PlayerInfo path glyph '{glyphData.Character}' did not parse.");
                    glyphs.Add(glyphData.Character, new Glyph(glyphData, path));
                }
                if (new string(glyphs.Keys.OrderBy(value => value).ToArray()) !=
                    new string(
                        PlayerInfoPathGlyphAtlasData.Characters
                            .OrderBy(value => value)
                            .ToArray()))
                {
                    throw new InvalidDataException(
                        $"PlayerInfo path font '{data.Id}' has an incomplete glyph closure.");
                }
                _glyphs = glyphs;
            }
            catch
            {
                foreach (var glyph in glyphs.Values)
                {
                    glyph.Dispose();
                }
                throw;
            }
        }

        internal PlayerInfoPathFontData Data { get; }

        internal Glyph GetGlyph(char character)
        {
            var glyphs = _glyphs ??
                throw new ObjectDisposedException(nameof(FontFace));
            if (!glyphs.TryGetValue(character, out var glyph))
            {
                throw new InvalidDataException(
                    $"PlayerInfo glyph U+{(int)character:X4} is outside the exact atlas.");
            }
            return glyph;
        }

        public void Dispose()
        {
            var glyphs = System.Threading.Interlocked.Exchange(
                ref _glyphs,
                null);
            if (glyphs is null)
            {
                return;
            }
            foreach (var glyph in glyphs.Values)
            {
                glyph.Dispose();
            }
        }
    }

    private sealed class Glyph(
        PlayerInfoPathGlyphData data,
        SKPath path) : IDisposable
    {
        internal PlayerInfoPathGlyphData Data { get; } = data;
        internal SKPath Path { get; } = path;
        public void Dispose() => Path.Dispose();
    }
}
