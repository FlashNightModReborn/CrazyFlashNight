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
    private readonly Dictionary<(string Font,char Glyph,float Size),float> _advances=new();

    private float Advance(string font,char glyph,float size)
    {
        var key=(font,glyph,size);
        if (_advances.TryGetValue(key,out float result)) return result;
        result=Authored.Contains(glyph) ? _atlas.MeasureText(font,glyph.ToString(),size) : Supplement(glyph).Advance*size/100;
        if (_advances.Count>=1024) _advances.Clear();
        _advances.Add(key,result);
        return result;
    }

    internal float Measure(string font, string text, float size)
    {
        var width = 0f;
        foreach (var c in text)
            width += Advance(font,c,size);
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

    private readonly record struct SpriteKey(string Font,char Glyph,float Size,float ScaleX,float ScaleY,float Sigma,SKColor Glow,SKColor Ink);
    private sealed record Sprite(SKImage Pixels,int Left,int Top,int Bytes);
    private readonly Dictionary<SpriteKey,Sprite> _sprites=new();
    private long _spriteBytes;

    internal void DrawLive(SKCanvas canvas,string font,string text,float size,float x,float baseline,
        PlayerInfoPathTextAlignment alignment,SKColor ink,float sigma,SKColor glow,long byteLimit)
    {
        float width=Measure(font,text,size);
        if (alignment==PlayerInfoPathTextAlignment.Center) x-=width/2;
        else if (alignment==PlayerInfoPathTextAlignment.Right) x-=width;
        var matrix=canvas.TotalMatrix;
        canvas.Save();
        canvas.ResetMatrix();
        try
        {
            foreach (char c in text)
            {
                var key=new SpriteKey(font,c,MathF.Round(size*256)/256,matrix.ScaleX,matrix.ScaleY,sigma,glow,ink);
                if (!_sprites.TryGetValue(key,out var sprite))
                {
                    sprite=BakeGlyph(key);
                    long bytes=sprite.Bytes;
                    if (_spriteBytes+bytes>byteLimit) ClearSprites();
                    if (bytes<=byteLimit)
                    {
                        _sprites.Add(key,sprite);
                        _spriteBytes+=bytes;
                        // Warm the remaining digits on first use of a numeric style and scale.
                        // At very large display scales keep the ordinary bounded, lazy path.
                        if (char.IsAsciiDigit(c) && bytes*12<=byteLimit-_spriteBytes)
                        {
                            for (char digit='0';digit<='9';digit++)
                            {
                                var other=key with { Glyph=digit };
                                if (_sprites.ContainsKey(other)) continue;
                                var baked=BakeGlyph(other);
                                if (_spriteBytes+baked.Bytes>byteLimit) { baked.Pixels.Dispose(); break; }
                                _sprites.Add(other,baked);
                                _spriteBytes+=baked.Bytes;
                            }
                        }
                    }
                }
                var point=matrix.MapPoint(x,baseline);
                canvas.DrawImage(sprite.Pixels,MathF.Round(point.X)+sprite.Left,MathF.Round(point.Y)+sprite.Top);
                if (sprite.Bytes>byteLimit) sprite.Pixels.Dispose();
                x+=Advance(font,c,size);
            }
        }
        finally { canvas.Restore(); }
    }

    private Sprite BakeGlyph(SpriteKey key)
    {
        string text=key.Glyph.ToString();
        using var path=Authored.Contains(key.Glyph)
            ? _atlas.BuildTextPath(key.Font,text,key.Size,0,0,PlayerInfoPathTextAlignment.Left)
            : new SKPath(Supplement(key.Glyph).Path);
        if (!Authored.Contains(key.Glyph)) path.Transform(SKMatrix.CreateScale(key.Size/100,key.Size/100));
        var bounds=SKMatrix.CreateScale(key.ScaleX,key.ScaleY).MapRect(path.Bounds);
        int pad=(int)Math.Ceiling(4*key.Sigma*Math.Max(key.ScaleX,key.ScaleY))+2;
        int left=(int)Math.Floor(bounds.Left)-pad,top=(int)Math.Floor(bounds.Top)-pad;
        using var tile=new SKBitmap((int)Math.Ceiling(bounds.Right)+pad-left,(int)Math.Ceiling(bounds.Bottom)+pad-top);
        using var layer=new SKCanvas(tile);
        layer.Clear(SKColors.Transparent);
        layer.Translate(-left,-top);
        layer.Scale(key.ScaleX,key.ScaleY);
        using var paint=new SKPaint { IsAntialias=true };
        if (key.Sigma>0)
        {
            using var blur=SKMaskFilter.CreateBlur(SKBlurStyle.Normal,key.Sigma);
            paint.MaskFilter=blur;
            paint.Color=key.Glow;
            layer.DrawPath(path,paint);
            paint.Color=key.Glow.WithAlpha((byte)(key.Glow.Alpha/2));
            layer.DrawPath(path,paint);
            paint.MaskFilter=null;
        }
        paint.Color=key.Ink;
        layer.DrawPath(path,paint);
        tile.SetImmutable();
        return new Sprite(SKImage.FromBitmap(tile),left,top,tile.ByteCount);
    }
    private void ClearSprites()
    {
        foreach (var sprite in _sprites.Values) sprite.Pixels.Dispose();
        _sprites.Clear();
        _spriteBytes=0;
    }

    private (SKPath Path, float Advance) Supplement(char character)
    {
        if (_supplements.TryGetValue(character, out var cached)) return cached;
        if (character is ' ' or '\u2009')
        {
            cached = (new SKPath(), character == ' ' ? 30 : 20);
            _supplements.Add(character, cached);
            return cached;
        }
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
        ClearSprites();
        foreach (var item in _supplements.Values) item.Path.Dispose();
        _supplements.Clear(); _unitFont?.Dispose(); _atlas.Dispose();
    }
}
