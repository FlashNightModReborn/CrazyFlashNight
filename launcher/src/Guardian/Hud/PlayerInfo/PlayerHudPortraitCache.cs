#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

// The icon catalog owns the source. Only the small, display-sized renditions belong to this cache.
internal sealed class PlayerHudPortraitCache : IDisposable
{
    private readonly record struct Key(Bitmap Source, int Width, int Height, bool Calm, bool Dense);
    private readonly Dictionary<Key, Bitmap> _rasters = new();
    private readonly Queue<Key> _order = new();
    private const int Limit = 48;

    internal void Draw(Graphics graphics, Bitmap source, RectangleF destination, float scale, bool calm = false, bool dense = false)
    {
        int width = Math.Clamp((int)Math.Ceiling(destination.Width * scale), 1, 192);
        int height = Math.Clamp((int)Math.Ceiling(destination.Height * scale), 1, 192);
        var key = new Key(source, width, height, calm, dense);
        if (!_rasters.TryGetValue(key, out var portrait))
        {
            portrait = Render(key);
            if (_order.Count == Limit)
            {
                var expired = _order.Dequeue();
                _rasters[expired].Dispose();
                _rasters.Remove(expired);
            }
            _rasters.Add(key, portrait);
            _order.Enqueue(key);
        }
        graphics.DrawImage(portrait, destination, new RectangleF(0, 0, width, height), GraphicsUnit.Pixel);
    }

    private static Bitmap Render(Key key)
    {
        var result = new Bitmap(key.Width, key.Height, PixelFormat.Format32bppPArgb);
        try
        {
            using var graphics = Graphics.FromImage(result);
            using var attributes = new ImageAttributes();
            attributes.SetWrapMode(WrapMode.TileFlipXY);
            if (key.Calm)
                attributes.SetColorMatrix(new ColorMatrix([
                    [.48f,.10f,.10f,0,0], [.14f,.56f,.16f,0,0], [.10f,.14f,.62f,0,0],
                    [0,0,0,key.Dense ? .78f : 1f,0], [0,.02f,.04f,0,1]
                ]));
            float sourceHeight = Math.Min(key.Source.Height, key.Source.Width * key.Height / (float)key.Width);
            float sourceWidth = sourceHeight * key.Width / key.Height;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.Half;
            graphics.DrawImage(key.Source, new Rectangle(0,0,key.Width,key.Height),
                (key.Source.Width-sourceWidth)/2, 0, sourceWidth, sourceHeight, GraphicsUnit.Pixel, attributes);
            return result;
        }
        catch { result.Dispose(); throw; }
    }

    public void Dispose()
    {
        foreach (var image in _rasters.Values) image.Dispose();
        _rasters.Clear();
        _order.Clear();
    }
}
