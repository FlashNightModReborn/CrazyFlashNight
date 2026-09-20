#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed class PlayerHudArtCache : IDisposable
{
    private readonly Dictionary<(string, int, int), Bitmap> _cache = new();
    private long _bytes;
    internal Bitmap Get(string id, int width, int height)
    {
        width = Math.Clamp(width, 1, 4096); height = Math.Clamp(height, 1, 2048);
        var key = (id, width, height);
        if (_cache.TryGetValue(key, out var value)) return value;
        var bytes = (long)width * height * 4;
        if (bytes > 16 * 1024 * 1024) throw new ArgumentOutOfRangeException(nameof(width), "HUD art exceeds its owned bitmap budget");
        if (_cache.Count >= 96 || _bytes + bytes > 16 * 1024 * 1024) Clear();
        using var svg = StrictSvgFacade.Load(PlayerHudArtData.Get(id));
        using var pixels = svg.Rasterize(width, height);
        if (id is "drug-hover" or "buff-panel")
        {
            // Authored unequip hover: blurX/Y=8, orange glow, strength=2.
            using var composed = new SKBitmap(pixels.Info);
            using var canvas = new SKCanvas(composed); canvas.Clear(SKColors.Transparent);
            var bounds = PlayerHudArtData.Bounds(id);
            var dx = width / bounds.Width; var dy = height / bounds.Height;
            using var filter = id == "drug-hover"
                ? SKImageFilter.CreateDropShadow(0, 0, 4 * dx, 4 * dy, new SKColor(255, 102, 51))
                : SKImageFilter.CreateDropShadow(1.4142136f * dx, 1.4142136f * dy, 0, 0, new SKColor(0, 0, 0, 204));
            using var glow = new SKPaint { ImageFilter = filter };
            canvas.DrawBitmap(pixels, 0, 0, glow);
            if (id == "drug-hover") canvas.DrawBitmap(pixels, 0, 0, glow);
            value = PlayerInfoPArgbBridge.Copy(composed);
        }
        else value = PlayerInfoPArgbBridge.Copy(pixels);
        _cache.Add(key, value); _bytes += bytes; return value;
    }
    private void Clear() { foreach (var entry in _cache.Values) entry.Dispose(); _cache.Clear(); _bytes = 0; }
    public void Dispose() => Clear();
}
