#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>V3.8 signed resource, stance and SP chassis, retained at the current physical scale.</summary>
internal sealed class PlayerHudDeckArt : IDisposable
{
    private Bitmap? _image;
    private const float OriginY = 512;

    internal void Paint(Graphics target, float scale)
    {
        var width = Math.Max(1, (int)Math.Ceiling(1024 * scale));
        var height = Math.Max(1, (int)Math.Ceiling(64 * scale));
        if (_image == null || _image.Width != width || _image.Height != height)
        {
            using var pending = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(pending))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.ScaleTransform(width / 1024f, height / 64f);
                g.TranslateTransform(0, -OriginY);
                PaintPlate(g);
            }
            var current = _image;
            _image = (Bitmap)pending.Clone();
            current?.Dispose();
        }
        target.DrawImage(_image, new RectangleF(0,OriginY,1024,64), new RectangleF(0,0,width,height), GraphicsUnit.Pixel);
    }

    private static void PaintPlate(Graphics g)
    {
        const float top = PlayerHudResourceLayout.DeckTop;
        using var chassis = new LinearGradientBrush(new RectangleF(0,top,1024,62.5f),Color.Black,Color.Black,90f);
        chassis.InterpolationColors = new ColorBlend {Positions=[0,.55f,1],Colors=[Color.FromArgb(38,42,44),Color.FromArgb(20,24,26),Color.FromArgb(8,10,11)]};
        g.FillRectangle(chassis,0,top,298.5f,62.5f);
        g.FillRectangle(chassis,480.5f,top,112,62.5f);

        void Line(Color ink,float width,float x1,float y1,float x2,float y2)
        {
            using var pen = new Pen(ink,width); g.DrawLine(pen,x1,y1,x2,y2);
        }
        var dark = Color.FromArgb(9,11,12);
        var silver = Color.FromArgb(87,214,217,215);
        Line(dark,1.2f,77,514,298.5f,514); Line(silver,.8f,77,514.9f,298,514.9f);
        Line(dark,1.2f,481,514,591.5f,514); Line(silver,.8f,481,514.9f,591.5f,514.9f);
        Line(Color.FromArgb(5,7,8),1.4f,298.5f,top,298.5f,576);
        Line(Color.FromArgb(46,214,217,215),.7f,297.2f,515.5f,297.2f,572);
        using var trace = new Pen(Color.FromArgb(72,120,126,124),.6f);
        g.DrawLines(trace,[new PointF(84,562),new(112,562),new(116,563.2f),new(289,563.2f),new(294,562)]);
        var arc = g.Save();
        g.TranslateTransform(48.2f,568.45f); g.ScaleTransform(.84721375f,.84721375f);
        using var sweep = new GraphicsPath();
        // Exact converted quadratic curves from the signed bottom-ornaments stripe.
        sweep.AddBezier(38.725f,-41.65f,36.6321f,-38.2533f,34.0738f,-35.0533f,31.05f,-32.05f);
        sweep.AddBezier(31.05f,-32.05f,23.035f,-24.0075f,13.6183f,-19.2742f,2.8f,-17.85f);
        using var lip = new Pen(Color.FromArgb(212,216,214),2.3f);
        g.DrawPath(lip,sweep); g.Restore(arc);

        PointF[] socket=[new(84,516),new(288.5f,516),new(292.5f,520),new(292.5f,524.8f),new(290.5f,526.8f),new(84,526.8f),new(84,518)];
        using var recess = new SolidBrush(Color.FromArgb(14,18,20));
        using var border = new Pen(Color.FromArgb(56,104,114,116),.6f);
        g.FillPolygon(recess,socket); g.DrawPolygon(border,socket);
        Line(Color.FromArgb(41,96,106,108),.65f,118,521.4f,284,521.4f);
        for (int i=0;i<6;i++) Line(Color.FromArgb(31,148,156,154),.8f,87.5f+i*4,523.9f,91.5f+i*4,518.7f);

        PointF[] beam=[new(592.5f,529.5f),new(592.5f,517.8f),new(597.5f,513f),new(738.5f,513f),new(742,515),new(939.5f,515),new(950.5f,526.2f),new(1018.5f,526.2f),new(1022,529.5f)];
        using var metal = new LinearGradientBrush(new RectangleF(592.5f,513,430,16.5f),Color.Black,Color.Black,90f);
        metal.InterpolationColors = new ColorBlend {Positions=[0,.45f,1],Colors=[Color.FromArgb(239,239,239),Color.FromArgb(212,214,212),Color.FromArgb(154,157,155)]};
        using var rim = new Pen(Color.FromArgb(16,19,20),.8f);
        g.FillPolygon(metal,beam); g.DrawPolygon(rim,beam);
        Line(Color.FromArgb(174,255,255,255),.8f,598.5f,513.8f,737.5f,513.8f);
        Line(Color.FromArgb(133,255,255,255),.7f,742.5f,515.8f,938.5f,515.8f);
        using var sp = new SolidBrush(Color.FromArgb(11,14,15));
        PointF[] slot=[new(646.4f,514.4f),new(736.5f,514.4f),new(733.6f,527.4f),new(643.5f,527.4f)];
        g.FillPolygon(sp,slot); g.DrawPolygon(rim,slot);
    }
    public void Dispose() => _image?.Dispose();
}
