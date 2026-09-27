#nullable enable
using System;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudResourceOverlay
{
    /// <summary>HP-local coordinates, entirely inside the authored 47-unit raster. The tick origin stays fixed.</summary>
    internal static void ShieldRing(SKCanvas canvas, PlayerHudVitals value, int frame = 0,
        PlayerHudResourceMotion.Channel? motion = null, float startAngleDegrees = -90)
    {
        if (!value.ShieldPresent) return;
        const float radius = 42.55f;
        var circle = new SKRect(-radius,-radius,radius,radius);
        using var metalShader = SKShader.CreateLinearGradient(new SKPoint(0,-radius),new SKPoint(0,radius),
            [new SKColor(104,126,132),new SKColor(30,44,49)],[0f,1f],SKShaderTileMode.Clamp);
        using var fillShader = SKShader.CreateLinearGradient(new SKPoint(0,-radius),new SKPoint(0,radius),
            [new SKColor(0,255,255),new SKColor(0,163,163)],[0f,1f],SKShaderTileMode.Clamp);
        using var track = new SKPaint {IsAntialias=true,Style=SKPaintStyle.Stroke,StrokeWidth=5.2f,Shader=metalShader};
        using var fill = new SKPaint {IsAntialias=true,Style=SKPaintStyle.Stroke,StrokeWidth=3.5f,Shader=fillShader};
        using var sheen = new SKPaint {IsAntialias=true,Style=SKPaintStyle.Stroke,StrokeWidth=1.3f};
        using var trail = new SKPaint {IsAntialias=true,Style=SKPaintStyle.Stroke,StrokeWidth=1.5f,
            Color=new SKColor(151,194,211,(byte)(110*(motion?.Loss??0)))};
        var remaining = PlayerHudResourceMotion.ShieldFraction(value)*24;
        var oldRemaining = (motion?.Trail??0)*24;
        var phase = (frame%120)/120f*24;
        var charging = value.ShieldDetail?.Recovery.State == "charging";
        for(var segment=0;segment<24;segment++)
        {
            // Follow the authored HP counterclockwise fill. Depletion and recovery keep the same origin.
            var start = startAngleDegrees-segment*15-1.5f;
            canvas.DrawArc(circle,start,-12,false,track);
            var fraction = Math.Clamp(remaining-segment,0,1);
            var oldFraction = Math.Clamp(oldRemaining-segment,0,1);
            if(oldFraction>fraction && trail.Color.Alpha>0)
                canvas.DrawArc(circle,start-12*fraction,-12*(oldFraction-fraction),false,trail);
            if(fraction<=0) continue;
            canvas.DrawArc(circle,start,-12*fraction,false,fill);
            var distance = Math.Abs(segment+fraction/2-phase);
            distance = Math.Min(distance,24-distance);
            var light = Math.Clamp(1-distance/2.5f,0,1)*105;
            if(remaining-segment<=1)
                light = Math.Max(light,charging?170:170*(motion?.Gain??0));
            sheen.Color = new SKColor(206,255,255,(byte)light);
            if(light>0) canvas.DrawArc(circle,start,-12*fraction,false,sheen);
        }
    }

    /// <summary>The caller applies the original HP sector and transform. Foreground art masks the center.</summary>
    internal static void HpOverflow(SKCanvas canvas, SKPath authoredCoverage)
    {
        var bounds = authoredCoverage.Bounds;
        using var shade = SKShader.CreateLinearGradient(new SKPoint(bounds.MidX,bounds.Top),new SKPoint(bounds.MidX,bounds.Bottom),
            [new SKColor(255,191,145,235),new SKColor(231,122,91,235)],[0f,1f],SKShaderTileMode.Clamp);
        using var ink = new SKPaint {IsAntialias=true,Style=SKPaintStyle.Fill,Shader=shade};
        canvas.DrawPath(authoredCoverage,ink);
    }

    /// <summary>Main logical coordinates. The original MP stays full beneath the extra capacity layer.</summary>
    internal static void MpOverflow(SKCanvas canvas, PlayerHudVitals value, int frame = 0)
    {
        if(!(value.MpMax>0) || !(value.Mp>value.MpMax)) return;
        var fraction = (float)Math.Clamp((value.Mp-value.MpMax)/value.MpMax,0,1);
        var bounds = PlayerHudResourceLayout.MpBar;
        using var cells = new SKPath();
        foreach(var cell in PlayerHudBarArtData.Cells)
        {
            cells.MoveTo(cell[0].X+PlayerHudResourceLayout.ResourceOffsetX,cell[0].Y+PlayerHudResourceLayout.MpOffsetY);
            for(var i=1;i<cell.Length;i++) cells.LineTo(cell[i].X+PlayerHudResourceLayout.ResourceOffsetX,cell[i].Y+PlayerHudResourceLayout.MpOffsetY);
            cells.Close();
        }
        canvas.Save();canvas.ClipPath(cells);
        var end = bounds.Left+bounds.Width*fraction;
        canvas.ClipRect(new SKRect(bounds.Left,bounds.Top,end,bounds.Bottom));
        using var wash = new SKPaint {Color=new SKColor(143,219,255,170)};
        canvas.DrawRect(new SKRect(bounds.Left,bounds.Top,bounds.Right,bounds.Bottom),wash);
        using var line = new SKPaint {IsAntialias=true,Color=new SKColor(232,251,255,235),StrokeWidth=1.3f};
        var drift = (frame%30)/30f*5;
        for(var x=bounds.Left-bounds.Height-5+drift;x<bounds.Right;x+=5)
            canvas.DrawLine(x,bounds.Bottom,x+bounds.Height,bounds.Top,line);
        line.StrokeWidth=1.6f;canvas.DrawLine(end-0.8f,bounds.Top,end-0.8f,bounds.Bottom,line);
        canvas.Restore();
    }
}
