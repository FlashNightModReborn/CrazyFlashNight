#nullable enable
using System;
using System.Collections.Generic;
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
    private readonly Dictionary<string, SKImage> _rasters = new();
    private readonly SKRect[] _motifCoverage = new SKRect[100];
    private string? _batchKey;

    internal PlayerHudHpMotion()
    {
        Transform(_a, PlayerHudHpMotionData.MatrixA); Transform(_b, PlayerHudHpMotionData.MatrixB);
    }
    private static SKPath Parse(string value) => SKPath.ParseSvgPathData(value) ?? throw new InvalidOperationException("Invalid authored HP motion path");
    private static void Transform(SKPath path, float[] m) => path.Transform(new SKMatrix(m[0],m[2],m[4],m[1],m[3],m[5],0,0,1));

    // Conservative path bounds in the same HP-local coordinates as the authored clips.
    private static SKRect MotifBounds(SKPath path, float[] pose, float t)
    {
        float Mix(int a, int b) => pose[a] + (pose[b] - pose[a]) * t;
        var matrix = SKMatrix.CreateTranslation(Mix(4,8), Mix(5,9) - 0.05f)
            .PreConcat(SKMatrix.CreateRotationDegrees(Mix(2,6)))
            .PreConcat(SKMatrix.CreateScale(Mix(3,7), Mix(3,7)))
            .PreConcat(SKMatrix.CreateTranslation(-pose[0], -pose[1]));
        using var transformed = new SKPath();
        path.Transform(matrix, transformed);
        return transformed.Bounds;
    }

    internal SKRect MovingCoverage(int frame, bool hasLight)
    {
        var grid = _grid[frame % 11].Bounds;
        grid.Offset(0.05f, -1.85f);
        grid.Inflate(0.5f, 0.5f);
        int phase = frame % 100;
        if (_motifCoverage[phase].IsEmpty)
            _motifCoverage[phase] = SKRect.Union(MotifBounds(_a, PlayerHudHpMotionData.PoseA, phase / 99f),
                MotifBounds(_b, PlayerHudHpMotionData.PoseB, phase / 99f));
        var bounds = SKRect.Union(_motifCoverage[phase], grid);
        int light = frame % 216 - 49;
        if (hasLight && light >= 0 && light < _light.Length)
        {
            var path = _light[light].Bounds;
            path.Offset(-40.4f, -45.85f);
            bounds = SKRect.Union(bounds, path);
        }
        return bounds;
    }

    internal SKImage Raster(string id, PlayerInfoRasterPlan plan, PlayerInfoRasterLayerPlan layer)
    {
        if (_batchKey != plan.BatchKey)
        {
            foreach (var image in _rasters.Values) image.Dispose();
            _rasters.Clear(); _batchKey = plan.BatchKey;
        }
        if (_rasters.TryGetValue(id, out var cached)) return cached;
        using var svg = StrictSvgFacade.Load(PlayerHudArtData.Get(id));
        using var pixels = svg.Rasterize(layer.PixelWidth,layer.PixelHeight,layer.SourceViewBox,layer.SourceToBitmap);
        pixels.SetImmutable();
        var raster = SKImage.FromBitmap(pixels);
        _rasters.Add(id, raster);
        return raster;
    }
    private readonly (SKBitmap? Pixels,int Left,int Top)[] _silhouettes = new (SKBitmap?,int,int)[100];
    private SKMatrix _silhouetteMatrix;
    private SKBitmap? _maskScratch;
    private long _silhouetteBytes;
    internal long SilhouetteBytes => _silhouetteBytes;
    private const long SilhouetteByteLimit = 4 * 1024 * 1024;

    internal void DrawMotifs(SKCanvas canvas,int frame)
    {
        int phase=frame % 100;
        var matrix=canvas.TotalMatrix;
        if (matrix!=_silhouetteMatrix)
        {
            ClearSilhouettes();
            _silhouetteMatrix=matrix;
        }
        var stamp=_silhouettes[phase];
        if (stamp.Pixels==null)
        {
            float t=phase/99f;
            var local=SKRect.Union(MotifBounds(_a,PlayerHudHpMotionData.PoseA,t),MotifBounds(_b,PlayerHudHpMotionData.PoseB,t));
            var device=matrix.MapRect(local);
            int left=Math.Max(0,(int)Math.Floor(device.Left)-2),top=Math.Max(0,(int)Math.Floor(device.Top)-2);
            int w=(int)Math.Ceiling(device.Right)+2-left,h=(int)Math.Ceiling(device.Bottom)+2-top;
            if (w<=0 || h<=0) return;
            var info=new SKImageInfo(w,h,SKColorType.Alpha8,SKAlphaType.Premul);
            int scratchWidth=Math.Max(left+w,_maskScratch?.Width??0);
            int scratchHeight=Math.Max(top+h,_maskScratch?.Height??0);
            if ((long)info.RowBytes*h+_silhouetteBytes+(long)scratchWidth*scratchHeight*4>SilhouetteByteLimit)
            {
                DrawMotifPaths(canvas,phase);
                return;
            }
            var mask=new SKBitmap(info);
            // Use the actual device origin. Moving the transform into the cropped tile changes
            // Skia antialias coverage at fractional scales. Only retain the cropped alpha.
            if (_maskScratch==null || _maskScratch.Width<left+w || _maskScratch.Height<top+h)
            {
                _maskScratch?.Dispose();
                _maskScratch=new SKBitmap(scratchWidth,scratchHeight);
            }
            using (var layer=new SKCanvas(_maskScratch))
            {
                layer.Clear(SKColors.Transparent);
                layer.SetMatrix(matrix);
                DrawMotifPaths(layer,phase);
            }
            using (var view=_maskScratch.PeekPixels())
                if (!view.ReadPixels(info,mask.GetPixels(),mask.RowBytes,left,top))
                {
                    mask.Dispose();
                    DrawMotifPaths(canvas,phase);
                    return;
                }
            mask.SetImmutable();
            _silhouetteBytes+=mask.ByteCount;
            _silhouettes[phase]=stamp=(mask,left,top);
        }
        canvas.Save();
        canvas.ResetMatrix();
        canvas.DrawBitmap(stamp.Pixels,stamp.Left,stamp.Top,_black);
        canvas.Restore();
    }

    private void ClearSilhouettes()
    {
        foreach (var stamp in _silhouettes) stamp.Pixels?.Dispose();
        Array.Clear(_silhouettes);
        _silhouetteBytes=0;
        _maskScratch?.Dispose(); _maskScratch=null;
    }

    internal void DrawMotifPaths(SKCanvas canvas,int frame)
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
    internal bool HasLight(int frame) => (uint)(frame % 216 - 49) < (uint)_light.Length;

    internal void DrawLight(SKCanvas canvas, int frame)
    {
        var key = frame % 216 - 49;
        if (key < 0 || key >= _light.Length) return;
        var centers = PlayerHudHpMotionData.LightCenters;
        using var gradient = SKShader.CreateRadialGradient(new SKPoint(centers[key*2],centers[key*2+1]),48.425f,
            [new SKColor(255,255,255,0),new SKColor(255,255,255,96),new SKColor(255,255,255,0)],
            [0.4745098f,0.7764706f,1f],SKShaderTileMode.Clamp);
        using var paint = new SKPaint { IsAntialias=true,Shader=gradient,BlendMode=SKBlendMode.Overlay };
        canvas.Save(); canvas.Translate(-40.4f,-45.85f);
        canvas.DrawPath(_light[key],paint); canvas.Restore();
    }
    public void Dispose()
    {
        ClearSilhouettes();
        _a.Dispose(); _b.Dispose(); _black.Dispose(); _gridInk.Dispose();
        foreach(var path in _grid) path.Dispose(); foreach(var path in _light) path.Dispose();
        foreach(var image in _rasters.Values) image.Dispose(); _rasters.Clear();
    }
}
