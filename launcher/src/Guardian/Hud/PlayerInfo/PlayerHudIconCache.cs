#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Owned, physical-size icons. Never retains another consumer's evictable 64px bitmap.</summary>
internal sealed class PlayerHudIconCache : IDisposable
{
    private readonly string _root;
    private readonly JObject _manifest;
    private readonly Dictionary<(string, int), Bitmap?> _cache = new();
    private long _bytes;
    internal PlayerHudIconCache(string root)
    {
        _root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        _manifest = JObject.Parse(File.ReadAllText(Path.Combine(root, "manifest.json")));
    }
    internal Bitmap? Get(string key, int pixels)
    {
        if (key.Length == 0) return null;
        pixels = Math.Clamp(pixels, 16, 256);
        var cacheKey = (key, pixels);
        if (_cache.TryGetValue(cacheKey, out var existing)) return existing;
        // Get is consumed synchronously inside Paint. No returned bitmap escapes that call.
        if (_bytes + pixels * pixels * 4L > 16 * 1024 * 1024) Clear();
        Bitmap? result = null;
        var file = _manifest[key]?["f1"]?.Value<string>();
        if (!string.IsNullOrEmpty(file))
        {
            var path = Path.GetFullPath(Path.Combine(_root, file));
            if (path.StartsWith(_root, StringComparison.OrdinalIgnoreCase) && File.Exists(path))
            {
                using var source = MapHudImageDecoder.LoadBitmap(path, 2048);
                result = new Bitmap(pixels, pixels, PixelFormat.Format32bppPArgb);
                using var g = Graphics.FromImage(result);
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.Transparent);
                var scale = Math.Min((float)pixels / source.Width, (float)pixels / source.Height);
                var w = source.Width * scale; var h = source.Height * scale;
                g.DrawImage(source, (pixels - w) / 2, (pixels - h) / 2, w, h);
                _bytes += pixels * pixels * 4L;
            }
        }
        _cache.Add(cacheKey, result); return result;
    }
    private void Clear() { foreach (var b in _cache.Values) b?.Dispose(); _cache.Clear(); _bytes = 0; }
    public void Dispose() => Clear();
}
