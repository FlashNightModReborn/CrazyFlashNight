#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudPoisePainter
{
    internal static PlayerHudPoiseVisual Flags(PlayerHudVitals value) => value.PoiseVisual ??
        new(value.PoiseDetail?.Phase == "air", value.PoiseDetail?.Phase == "rigid", value.PoiseDetail?.Phase == "down");

    internal static void Paint(Graphics g, PlayerHudVitals value, GraphicsPath cells)
    {
        var detail=value.PoiseDetail; var flags=Flags(value);
        var ready=detail!=null && detail.Phase!="unavailable";
        var inactive=!ready || flags.Airborne || flags.Rigid || flags.Down;
        var fraction=(float)Math.Clamp(value.Poise,0,1);
        var source=PlayerHudBarArtData.MpBounds;
        var split=detail is {HasStaggerBand:true} && !inactive ? (float)detail.Threshold*source.Width : 0;
        var saved=g.Save();
        g.TranslateTransform(PlayerHudResourceLayout.ResourceOffsetX+PlayerHudResourceLayout.PoiseOffsetX,PlayerHudResourceLayout.PoiseTop-source.Top);
        using var track=new SolidBrush(Color.FromArgb(24,28,28));
        g.FillPath(track,cells);
        // Bottom: rigid chassis remains visible through cell gaps and the inner edges at full poise.
        if(flags.Rigid)
        {
            using var armor=new HatchBrush(HatchStyle.Horizontal,Color.FromArgb(101,122,130),Color.FromArgb(46,62,68));
            using var frame=new Pen(Color.FromArgb(160,178,184),1.1f);
            g.FillPath(armor,cells);g.DrawPath(frame,cells);
        }
        if(split>0)
        {
            var zone=g.Save();g.SetClip(cells,CombineMode.Intersect);
            using var riskTrack=new SolidBrush(Color.FromArgb(61,45,19));
            g.FillRectangle(riskTrack,source.Left,source.Top,split,source.Height);g.Restore(zone);
        }
        // Middle: preserve the current outline in inactive states; it is a dim reference, not available protection.
        var filled=g.Save();
        g.SetClip(cells,CombineMode.Intersect);
        var inset=flags.Rigid?1.2f:0;
        g.SetClip(new RectangleF(source.Left,source.Top+inset,source.Width*fraction,source.Height-inset*2),CombineMode.Intersect);
        using var fill=new SolidBrush(ready?PlayerHudResourceStyle.Poise:Color.FromArgb(97,104,105));
        g.FillPath(fill,cells);
        if(split>0)
        {
            using var riskFill=new SolidBrush(PlayerHudResourceStyle.PoiseRisk);
            g.FillRectangle(riskFill,source.Left,source.Top,split,source.Height);
        }
        g.Restore(filled);
        using var border=new Pen(inactive?Color.FromArgb(91,104,110):Color.FromArgb(139,130,80),0.3f);
        g.DrawPath(border,cells);
        if(split>0)
        {
            var risk=g.Save();g.SetClip(cells,CombineMode.Intersect);
            g.SetClip(new RectangleF(source.Left,source.Top,split,source.Height),CombineMode.Intersect);
            using var cut=new SolidBrush(Color.FromArgb(20,24,24));
            for(var x=source.Left+2;x<source.Left+split;x+=6)
                g.FillPolygon(cut,[new PointF(x-1.8f,source.Bottom),new PointF(x,source.Bottom-2.4f),new PointF(x+1.8f,source.Bottom)]);
            g.Restore(risk);
            var boundary=source.Left+split;
            g.FillRectangle(cut,boundary-1.1f,source.Top,2.2f,source.Height);
            using var marker=new SolidBrush(Color.FromArgb(245,241,222));
            g.FillPolygon(marker,[new PointF(boundary-2.3f,source.Top-2),new PointF(boundary+2.3f,source.Top-2),new PointF(boundary,source.Top+0.5f)]);
        }
        // Top: stable, sparse airborne/down textures replace the full-to-empty switch. No blink clock.
        if(flags.Airborne || flags.Down)
        {
            var overlay=g.Save();g.SetClip(cells,CombineMode.Intersect);
            using var hatch=new HatchBrush(flags.Down?HatchStyle.DiagonalCross:HatchStyle.ForwardDiagonal,
                Color.FromArgb(205,38,51,57),Color.FromArgb(30,17,24,28));
            g.FillRectangle(hatch,source);g.Restore(overlay);
        }
        g.Restore(saved);
    }
}
