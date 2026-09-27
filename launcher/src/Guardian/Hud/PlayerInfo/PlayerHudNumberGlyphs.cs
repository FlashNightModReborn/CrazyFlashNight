#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Preserves the authored number outlines; unit glyphs come from the configured native font role.</summary>
internal sealed class PlayerHudNumberGlyphs : IDisposable
{
    private const string Authored = "0123456789/%MP-";
    private readonly PlayerInfoPathGlyphAtlas _atlas = new();
    private readonly Dictionary<char, (SKPath Path, float Advance)> _supplements = new();
    private Font? _unitFont;

    internal float Measure(string font, string text, float size)
    {
        var width = 0f;
        foreach (var c in text)
            width += Authored.IndexOf(c) >= 0 ? _atlas.MeasureText(font, c.ToString(), size) : Supplement(c).Advance * size / 100;
        return width;
    }

    internal void Draw(SKCanvas canvas, string font, string text, float size, float x, float baseline,
        PlayerInfoPathTextAlignment alignment, SKColor color, float glowSigma = 0, SKColor? glow = null)
    {
        var width = Measure(font, text, size);
        if (alignment == PlayerInfoPathTextAlignment.Center) x -= width / 2;
        else if (alignment == PlayerInfoPathTextAlignment.Right) x -= width;
        using var combined = new SKPath { FillType = SKPathFillType.EvenOdd };
        foreach (var c in text)
        {
            if (Authored.IndexOf(c) >= 0)
            {
                using var path = _atlas.BuildTextPath(font, c.ToString(), size, x, baseline, PlayerInfoPathTextAlignment.Left);
                combined.AddPath(path); x += _atlas.MeasureText(font, c.ToString(), size);
            }
            else
            {
                var glyph = Supplement(c); using var path = new SKPath(glyph.Path);
                var scale = size / 100;
                path.Transform(new SKMatrix(scale, 0, x, 0, scale, baseline, 0, 0, 1));
                combined.AddPath(path); x += glyph.Advance * scale;
            }
        }
        if (glowSigma > 0 && glow.HasValue)
        {
            using var blur = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, glowSigma);
            using var glowPaint = new SKPaint { IsAntialias = true, Color = glow.Value, MaskFilter = blur };
            canvas.DrawPath(combined, glowPaint);
            glowPaint.Color = glow.Value.WithAlpha((byte)(glow.Value.Alpha / 2));
            canvas.DrawPath(combined, glowPaint);
        }
        using var ink = new SKPaint { IsAntialias = true, Color = color };
        canvas.DrawPath(combined, ink);
    }

    private (SKPath Path, float Advance) Supplement(char character)
    {
        if (_supplements.TryGetValue(character, out var cached)) return cached;
        if (character == ' ') { cached = (new SKPath(), 30); _supplements.Add(character, cached); return cached; }
        _unitFont ??= NativeHudFonts.CreateRoleFont("native.hud.body", 100, FontStyle.Regular, GraphicsUnit.Pixel);
        using var outline = new GraphicsPath();
        outline.AddString(character.ToString(), _unitFont.FontFamily, (int)_unitFont.Style,
            100, PointF.Empty, StringFormat.GenericTypographic);
        var bounds = outline.GetBounds();
        var ascent = 100f * _unitFont.FontFamily.GetCellAscent(_unitFont.Style) / _unitFont.FontFamily.GetEmHeight(_unitFont.Style);
        var points = outline.PointCount == 0 ? Array.Empty<PointF>() : outline.PathPoints;
        var types = outline.PointCount == 0 ? Array.Empty<byte>() : outline.PathTypes;
        var path = new SKPath { FillType = SKPathFillType.EvenOdd };
        SKPoint Point(int i) => new(points[i].X - bounds.Left, points[i].Y - ascent);
        for (var i = 0; i < points.Length; i++)
        {
            switch (types[i] & 7)
            {
                case 0: path.MoveTo(Point(i)); break;
                case 1: path.LineTo(Point(i)); break;
                case 3:
                    if (i + 2 >= points.Length) throw new InvalidOperationException("Incomplete native unit glyph curve.");
                    path.CubicTo(Point(i), Point(i + 1), Point(i + 2)); i += 2; break;
            }
            if ((types[i] & 0x80) != 0) path.Close();
        }
        var unitScale = character is '万' or '亿' ? 0.82f : 1f;
        if (unitScale != 1) path.Transform(SKMatrix.CreateScale(unitScale,unitScale));
        var advance = Math.Max(character == '.' ? 22 : 28, bounds.Width + 5) * unitScale;
        // This cache only receives a bounded presentation alphabet, plus existing ammo markers.
        if (_supplements.Count >= 64) { foreach (var item in _supplements.Values) item.Path.Dispose(); _supplements.Clear(); }
        cached = (path, advance); _supplements.Add(character, cached); return cached;
    }

    public void Dispose()
    {
        foreach (var item in _supplements.Values) item.Path.Dispose();
        _supplements.Clear(); _unitFont?.Dispose(); _atlas.Dispose();
    }
}
