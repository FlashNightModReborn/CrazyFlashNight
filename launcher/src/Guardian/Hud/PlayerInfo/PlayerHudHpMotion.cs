#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Owned source paths for the three authored HP movie clips; no frame image atlas.</summary>
internal sealed class PlayerHudHpMotion : IDisposable
{
    private readonly SKPath _a = Parse(PlayerHudHpMotionData.MotifA);
    private readonly SKPath _b = Parse(PlayerHudHpMotionData.MotifB);
    private readonly SKPath[] _grid = PlayerHudHpMotionData.GridPaths.Select(Parse).ToArray();
    private readonly SKPath[] _light = PlayerHudHpMotionData.LightPaths.Select(Parse).ToArray();
    private readonly SKPaint _black = new() { IsAntialias = true, Color = SKColors.Black, Style = SKPaintStyle.Fill };
    private readonly SKPaint _gridInk = new() { IsAntialias = true, Color = SKColors.Black, Style = SKPaintStyle.Stroke, StrokeWidth = 0.1f };
    private readonly Dictionary<string, Bitmap> _rasters = new();
    private string? _batchKey;

    internal PlayerHudHpMotion()
    {
        Transform(_a, PlayerHudHpMotionData.MatrixA); Transform(_b, PlayerHudHpMotionData.MatrixB);
    }
    private static SKPath Parse(string value) => SKPath.ParseSvgPathData(value) ?? throw new InvalidOperationException("Invalid authored HP motion path");
    private static void Transform(SKPath path, float[] m) => path.Transform(new SKMatrix(m[0],m[2],m[4],m[1],m[3],m[5],0,0,1));

    internal Bitmap Raster(string id, PlayerInfoRasterPlan plan, PlayerInfoRasterLayerPlan layer)
    {
        if (_batchKey != plan.BatchKey)
        {
            foreach (var image in _rasters.Values) image.Dispose();
            _rasters.Clear(); _batchKey = plan.BatchKey;
        }
        if (_rasters.TryGetValue(id, out var cached)) return cached;
        using var svg = StrictSvgFacade.Load(PlayerHudArtData.Get(id));
        using var pixels = svg.Rasterize(layer.PixelWidth,layer.PixelHeight,layer.SourceViewBox,layer.SourceToBitmap);
        var result = PlayerInfoPArgbBridge.Copy(pixels); _rasters.Add(id,result); return result;
    }
    internal void DrawMotifs(SKCanvas canvas, int frame)
    {
        DrawMotif(canvas,_a,PlayerHudHpMotionData.PoseA,(frame % 100) / 99f);
        DrawMotif(canvas,_b,PlayerHudHpMotionData.PoseB,(frame % 100) / 99f);
    }
    private void DrawMotif(SKCanvas canvas, SKPath path, float[] pose, float t)
    {
        float Mix(int a, int b) => pose[a] + (pose[b] - pose[a]) * t;
        canvas.Save();
        canvas.Translate(Mix(4,8),Mix(5,9) - 0.05f);
        canvas.RotateDegrees(Mix(2,6)); canvas.Scale(Mix(3,7));
        canvas.Translate(-pose[0],-pose[1]); canvas.DrawPath(path,_black); canvas.Restore();
    }
    internal void DrawGrid(SKCanvas canvas, int frame)
    {
        canvas.Save(); canvas.Translate(0.05f,-1.85f);
        canvas.DrawPath(_grid[frame % 11],_gridInk); canvas.Restore();
    }
    internal void DrawLight(SKCanvas canvas, int frame)
    {
        var key = frame % 216 - 49;
        if (key < 0 || key >= _light.Length) return;
        var centers = PlayerHudHpMotionData.LightCenters;
        using var gradient = SKShader.CreateRadialGradient(new SKPoint(centers[key*2],centers[key*2+1]),48.425f,
            [new SKColor(255,255,255,0),new SKColor(255,255,255,153),new SKColor(255,255,255,0)],
            [0.4745098f,0.7764706f,1f],SKShaderTileMode.Clamp);
        using var paint = new SKPaint { IsAntialias=true,Shader=gradient,BlendMode=SKBlendMode.Overlay };
        canvas.Save(); canvas.Translate(-40.4f,-45.85f);
        canvas.DrawPath(_light[key],paint); canvas.Restore();
    }
    public void Dispose()
    {
        _a.Dispose(); _b.Dispose(); _black.Dispose(); _gridInk.Dispose();
        foreach(var path in _grid) path.Dispose(); foreach(var path in _light) path.Dispose();
        foreach(var image in _rasters.Values) image.Dispose(); _rasters.Clear();
    }
}
