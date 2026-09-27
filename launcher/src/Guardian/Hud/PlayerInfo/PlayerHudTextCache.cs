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
    internal void Draw(Graphics graphics, string value, float x, float baseline, float fontSize, float scale, float maxWidth,
        Color? ink = null, string font = PlayerInfoPathGlyphAtlas.Aero)
    {
        var color = ink ?? Color.White;
        var requestedSize = fontSize;
        var formatted = PlayerHudNumberFormat.FormatText(value, text => _glyphs.Measure(font, text, requestedSize), maxWidth);
        value = formatted.Text;
        if (formatted.ReservedWidth > maxWidth) fontSize *= maxWidth / formatted.ReservedWidth;
        var width = _glyphs.Measure(font, value, fontSize);
        if (width > maxWidth) { fontSize *= maxWidth / width; width = maxWidth; }
        var key = (value, font, fontSize, scale, color.ToArgb());
        if (!_cache.TryGetValue(key, out var bitmap))
        {
            if (_cache.Count >= 48) { foreach (var image in _cache.Values) image.Dispose(); _cache.Clear(); }
            using var pixels = new SKBitmap(new SKImageInfo(Math.Max(1, (int)Math.Ceiling((width + 2) * scale)),
                Math.Max(1, (int)Math.Ceiling((fontSize + 4) * scale)), SKColorType.Bgra8888, SKAlphaType.Premul));
            using var canvas = new SKCanvas(pixels);
            canvas.Clear(SKColors.Transparent); canvas.Scale(scale);
            _glyphs.Draw(canvas, font, value, fontSize, 1, fontSize,
                PlayerInfoPathTextAlignment.Left, new SKColor(color.R, color.G, color.B, color.A));
            bitmap = PlayerInfoPArgbBridge.Copy(pixels); _cache.Add(key, bitmap);
        }
        graphics.DrawImage(bitmap, x - 1, baseline - fontSize, bitmap.Width / scale, bitmap.Height / scale);
    }
    public void Dispose() { foreach (var image in _cache.Values) image.Dispose(); _cache.Clear(); _glyphs.Dispose(); }
}
