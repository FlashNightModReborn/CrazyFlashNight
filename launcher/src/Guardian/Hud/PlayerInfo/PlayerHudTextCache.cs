#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Reuses B0's source-bound Aero numerals; owned physical-size rasters never escape a paint.</summary>
internal sealed class PlayerHudTextCache : IDisposable
{
    private readonly PlayerHudNumberGlyphs _glyphs = new();
    private readonly Dictionary<(string, string, float, float, int), Bitmap> _cache = new();
    private readonly record struct TextLayout(string Value, float Width, float Size);
    private readonly Dictionary<(string Value, string Font, float Size, float MaxWidth, double Threshold), TextLayout> _layouts = new();


    internal void Draw(Graphics graphics, string value, float x, float baseline, float fontSize, float scale, float maxWidth,
        Color? ink = null, string font = PlayerInfoPathGlyphAtlas.Aero, double compactThreshold = 10000)
    {
        var (bitmap, _, effectiveSize) = ResolveBitmap(value, fontSize, scale, maxWidth, ink, font, compactThreshold);
        graphics.DrawImage(bitmap, x - 1, baseline - effectiveSize, bitmap.Width / scale, bitmap.Height / scale);
    }

    internal float DrawRight(Graphics graphics, string value, float rightX, float baseline, float fontSize, float scale, float maxWidth,
        Color? ink = null, string font = PlayerInfoPathGlyphAtlas.Aero, double compactThreshold = 10000)
    {
        var (bitmap, width, effectiveSize) = ResolveBitmap(value, fontSize, scale, maxWidth, ink, font, compactThreshold);
        graphics.DrawImage(bitmap, rightX - width - 1, baseline - effectiveSize, bitmap.Width / scale, bitmap.Height / scale);
        return width;
    }

    internal float Width(string value, float fontSize, float maxWidth, double compactThreshold = 10000)
        => ResolveLayout(value, fontSize, maxWidth, PlayerInfoPathGlyphAtlas.Aero, compactThreshold).Width;

    private (Bitmap Bitmap, float Width, float EffectiveSize) ResolveBitmap(
        string value, float fontSize, float scale, float maxWidth, Color? ink, string font, double compactThreshold)
    {
        var color = ink ?? Color.White;
        var layout = ResolveLayout(value, fontSize, maxWidth, font, compactThreshold);
        value = layout.Value;
        fontSize = layout.Size;
        var width = layout.Width;
        var key = (value, font, fontSize, scale, color.ToArgb());
        if (!_cache.TryGetValue(key, out var bitmap))
        {
            if (_cache.Count >= 64) { foreach (var image in _cache.Values) image.Dispose(); _cache.Clear(); }
            using var pixels = new SKBitmap(new SKImageInfo(Math.Max(1, (int)Math.Ceiling((width + 2) * scale)),
                Math.Max(1, (int)Math.Ceiling((fontSize + 4) * scale)), SKColorType.Bgra8888, SKAlphaType.Premul));
            using var canvas = new SKCanvas(pixels);
            canvas.Clear(SKColors.Transparent); canvas.Scale(scale);
            _glyphs.Draw(canvas, font, value, fontSize, 1, fontSize,
                PlayerInfoPathTextAlignment.Left, new SKColor(color.R, color.G, color.B, color.A));
            bitmap = PlayerInfoPArgbBridge.Copy(pixels); _cache.Add(key, bitmap);
        }
        return (bitmap, width, fontSize);
    }

    private TextLayout ResolveLayout(string value, float fontSize, float maxWidth, string font, double compactThreshold)
    {
        // Fitting a numeric pair measures its widest-digit envelope. Its logical width
        // is stable across animation ticks, raster colours and viewport scales.
        var key = (value, font, fontSize, maxWidth, compactThreshold);
        if (_layouts.TryGetValue(key, out var layout)) return layout;
        var requestedSize = fontSize;
        var formatted = PlayerHudNumberFormat.FormatText(value, text => _glyphs.Measure(font, text, requestedSize), maxWidth, compactThreshold);
        value = formatted.Text;
        if (formatted.ReservedWidth > maxWidth) fontSize *= maxWidth / formatted.ReservedWidth;
        var width = _glyphs.Measure(font, value, fontSize);
        if (width > maxWidth) { fontSize *= maxWidth / width; width = maxWidth; }
        if (_layouts.Count >= 64) _layouts.Clear();
        return _layouts[key] = new(value, width, fontSize);
    }

    public void Dispose() { foreach (var image in _cache.Values) image.Dispose(); _cache.Clear(); _layouts.Clear(); _glyphs.Dispose(); }
}
