#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal readonly record struct PlayerInfoFramePaintResult(
    int HpVirtualFrame,
    int MpVirtualFrame,
    int MpLeftContourCount,
    int MpRightContourCount,
    string MpRimAssetId,
    string MpPaletteStart);

internal readonly record struct PlayerInfoTextLayout(
    string Id,
    string FontId,
    float FontPixels,
    float AnchorX,
    float BaselineY,
    PlayerInfoPathTextAlignment Alignment,
    float GlowSigmaPixels,
    SKColor? GlowColor);

/// <summary>
/// Narrow, source-derived composition contract for the effects implemented in
/// B0. It deliberately excludes the two B3-deferred HP effects.
/// </summary>
internal static class PlayerInfoCompositionRecipe
{
    internal const string HpFillAssetId = "hp.fill";
    internal const string DynamicTextEffectId =
        "hp-mp-dynamic-text-and-glow";

    internal static PlayerInfoTextLayout MpLabel { get; } = new(
        "mp-label",
        PlayerInfoPathGlyphAtlas.Aero,
        15.9744f,
        2.8f,
        18.55f,
        PlayerInfoPathTextAlignment.Left,
        0f,
        null);

    internal static PlayerInfoTextLayout MpPercent { get; } = new(
        "mp-percent",
        PlayerInfoPathGlyphAtlas.Aero,
        11.9808f,
        -2.15f,
        30.5f,
        PlayerInfoPathTextAlignment.Left,
        0f,
        null);

    internal static PlayerInfoTextLayout MpCurrent { get; } = new(
        "mp-current",
        PlayerInfoPathGlyphAtlas.Aero,
        13.0048f,
        78.55f,
        17.85f,
        PlayerInfoPathTextAlignment.Right,
        0f,
        null);

    internal static PlayerInfoTextLayout MpMaximum { get; } = new(
        "mp-maximum",
        PlayerInfoPathGlyphAtlas.Aero,
        13.0048f,
        80.65f,
        17.85f,
        PlayerInfoPathTextAlignment.Left,
        0f,
        null);

    internal static PlayerInfoTextLayout HpPercent { get; } = new(
        "hp-percent",
        PlayerInfoPathGlyphAtlas.LcdStd,
        19.968f,
        13.45f,
        -4.5f,
        PlayerInfoPathTextAlignment.Right,
        1f,
        new SKColor(0, 0, 0, 220));

    internal static PlayerInfoTextLayout HpMaximum { get; } = new(
        "hp-maximum",
        PlayerInfoPathGlyphAtlas.LcdStd,
        11.9808f,
        8.975f,
        19.95f,
        PlayerInfoPathTextAlignment.Center,
        1f,
        new SKColor(0, 0, 0, 220));

    internal static PlayerInfoTextLayout HpCurrent { get; } = new(
        "hp-current",
        PlayerInfoPathGlyphAtlas.LcdStd,
        11.9808f,
        -5.775f,
        7.7f,
        PlayerInfoPathTextAlignment.Center,
        1f,
        new SKColor(0, 0, 0, 220));

    internal static IReadOnlyList<PlayerInfoTextLayout> TextLayouts { get; } =
        Array.AsReadOnly(
        new[]
        {
            MpLabel,
            MpPercent,
            MpCurrent,
            MpMaximum,
            HpPercent,
            HpMaximum,
            HpCurrent
        });

    internal static void ValidateEffectPolicy(PlayerInfoEffectPolicy policy)
    {
        ArgumentNullException.ThrowIfNull(policy);
        var activeIds = policy.ImplementedActiveLayers
            .Select(effect => effect.Id)
            .ToArray();
        if (!activeIds.SequenceEqual(
                [DynamicTextEffectId],
                StringComparer.Ordinal))
        {
            throw new InvalidDataException(
                "PlayerInfo composition recipe requires exactly the active dynamic-text effect.");
        }

        var deferredIds = policy.DeferredB3Layers
            .Select(effect => effect.Id)
            .ToArray();
        if (!deferredIds.SequenceEqual(
            [
                "hp-horizontal-line-glow",
                "hp-light-overlay"
            ],
            StringComparer.Ordinal))
        {
            throw new InvalidDataException(
                "PlayerInfo composition recipe requires the exact two B3-deferred HP effects.");
        }
    }

    internal static PlayerInfoSvgAsset GetHpPaintSourceAsset(
        PlayerInfoSvgAssetSet assetSet)
    {
        ArgumentNullException.ThrowIfNull(assetSet);
        return assetSet.Assets.Single(asset =>
            string.Equals(
                asset.Id,
                HpFillAssetId,
                StringComparison.Ordinal));
    }
}

/// <summary>
/// Composes the fixture-only PlayerInfo frame into a tight PArgb bitmap.
/// Static SVG layers come from the atomic raster batch; HP coverage/gradient,
/// MP masks and all text remain programmatic and source-bound.
/// </summary>
internal sealed class PlayerInfoFrameCompositor : IDisposable
{
    private const string HpBackplate = "hp.backplate";
    private const string HpFill = PlayerInfoCompositionRecipe.HpFillAssetId;
    private const string HpRim = "hp.rim";
    private const string MpBackplate = "mp.backplate";
    private const string MpFill = "mp.fill";
    private const string MpLeftMask = "mp-left-mask";
    private const string MpRightMask = "mp-right-mask";

    private readonly PlayerInfoSvgAssetSet _assetSet;
    private readonly PlayerInfoSvgGauge _hp;
    private readonly PlayerInfoSvgGauge _mp;
    private readonly PlayerInfoPathGlyphAtlas _glyphs;
    private PlayerInfoHpPaintSource? _hpPaint;
    private bool _disposed;

    internal PlayerInfoFrameCompositor(PlayerInfoSvgAssetSet assetSet)
    {
        _assetSet = assetSet ?? throw new ArgumentNullException(nameof(assetSet));
        if (!assetSet.Gauges.TryGetValue("hp", out _hp!) ||
            !assetSet.Gauges.TryGetValue("mp", out _mp!))
        {
            throw new InvalidDataException(
                "PlayerInfo compositor requires typed HP and MP gauges.");
        }
        PlayerInfoCompositionRecipe.ValidateEffectPolicy(assetSet.EffectPolicy);
        _glyphs = new PlayerInfoPathGlyphAtlas();
        try
        {
            _hpPaint = PlayerInfoHpPaintSource.Load(
                PlayerInfoCompositionRecipe.GetHpPaintSourceAsset(assetSet),
                _hp);
        }
        catch
        {
            _glyphs.Dispose();
            throw;
        }
    }

    internal PlayerInfoFramePaintResult Paint(
        Bitmap destination,
        PlayerInfoRasterBatch batch,
        PlayerInfoRasterPlan plan,
        PlayerInfoVisualState visualState)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(destination);
        ArgumentNullException.ThrowIfNull(batch);
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(visualState);
        if (!visualState.HasRenderableState)
        {
            throw new InvalidOperationException(
                "PlayerInfo compositor refuses a state without both gauge LKG values.");
        }
        if (destination.PixelFormat != PixelFormat.Format32bppPArgb ||
            destination.Width != plan.TightPhysicalBounds.Width ||
            destination.Height != plan.TightPhysicalBounds.Height)
        {
            throw new InvalidDataException(
                "PlayerInfo destination must be tight Format32bppPArgb.");
        }
        if (!string.Equals(batch.BatchKey, plan.BatchKey, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                "PlayerInfo batch and placement plan identities differ.");
        }

        var layers = batch.Layers.ToDictionary(
            layer => layer.Key.LayerId,
            StringComparer.Ordinal);
        if (layers.Count != PlayerInfoSvgAssetCatalog.ExpectedAssetCount)
        {
            throw new InvalidDataException(
                "PlayerInfo compositor requires the exact eight-layer batch.");
        }

        var hpFrame = visualState.Hp.CurrentVirtualFrame;
        var mpFrame = visualState.Mp.CurrentVirtualFrame;
        ValidateVirtualFrame(_hp, hpFrame);
        ValidateVirtualFrame(_mp, mpFrame);
        var leftMask = BuildMpMask(MpLeftMask, mpFrame);
        var rightMask = BuildMpMask(MpRightMask, mpFrame);
        using var leftPath = leftMask.Path;
        using var rightPath = rightMask.Path;
        var palette = SelectPalette(mpFrame);
        var rimAssetId = SelectRim(mpFrame);

        BitmapData? locked = null;
        try
        {
            locked = destination.LockBits(
                new Rectangle(0, 0, destination.Width, destination.Height),
                ImageLockMode.ReadWrite,
                PixelFormat.Format32bppPArgb);
            if (locked.Scan0 == IntPtr.Zero ||
                locked.Stride < checked(destination.Width * 4))
            {
                throw new InvalidDataException(
                    "PlayerInfo destination has an unsupported PArgb stride.");
            }
            var info = new SKImageInfo(
                destination.Width,
                destination.Height,
                SKColorType.Bgra8888,
                SKAlphaType.Premul);
            using var surface = SKSurface.Create(info, locked.Scan0, locked.Stride) ??
                throw new InvalidOperationException(
                    "Skia could not wrap the PlayerInfo PArgb destination.");
            var canvas = surface.Canvas;
            canvas.Clear(SKColors.Transparent);

            DrawLayer(canvas, layers[MpBackplate], plan);
            if (mpFrame != _mp.FrameMap.EmptyVirtualFrame)
            {
                DrawMpFill(
                    canvas,
                    layers[MpFill],
                    plan,
                    leftPath,
                    rightPath);
            }
            DrawLayer(canvas, layers[rimAssetId], plan);

            DrawLayer(canvas, layers[HpBackplate], plan);
            DrawHpFill(canvas, layers[HpFill], plan, hpFrame);
            DrawLayer(canvas, layers[HpRim], plan);

            DrawText(canvas, plan, visualState, palette);
            canvas.Flush();
            surface.Flush();
        }
        finally
        {
            if (locked is not null)
            {
                destination.UnlockBits(locked);
            }
        }

        return new PlayerInfoFramePaintResult(
            hpFrame,
            mpFrame,
            leftMask.ContourCount,
            rightMask.ContourCount,
            rimAssetId,
            palette.StartVirtualFrame.ToString(CultureInfo.InvariantCulture));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _hpPaint?.Dispose();
        _hpPaint = null;
        _glyphs.Dispose();
    }

    private void DrawHpFill(
        SKCanvas canvas,
        PlayerInfoRasterLayer layer,
        PlayerInfoRasterPlan plan,
        int virtualFrame)
    {
        var fraction = (_hp.FrameMap.EmptyVirtualFrame - virtualFrame) /
            (double)_hp.FrameMap.StepCount;
        if (fraction <= 0)
        {
            return;
        }
        fraction = Math.Clamp(fraction, 0, 1);

        var layerPlan = FindLayerPlan(plan, HpFill);
        var target = ToLocalRect(
            layerPlan.PhysicalBounds,
            plan.TightPhysicalBounds);
        var viewBox = layerPlan.SourceViewBox;
        var scaleX = target.Width / (float)viewBox.Width;
        var scaleY = target.Height / (float)viewBox.Height;
        var hpPaint = _hpPaint ??
            throw new ObjectDisposedException(nameof(PlayerInfoFrameCompositor));

        canvas.Save();
        try
        {
            canvas.Translate(
                target.Left - ((float)viewBox.Left * scaleX),
                target.Top - ((float)viewBox.Top * scaleY));
            canvas.Scale(scaleX, scaleY);
            if (fraction < 1)
            {
                using var sector = BuildHpSector(fraction);
                canvas.ClipPath(
                    sector,
                    SKClipOperation.Intersect,
                    antialias: true);
            }

            var rotation = _hp.FillTextureRotation ??
                throw new InvalidDataException(
                    "Typed HP rotation contract is missing.");
            var degrees = (virtualFrame + rotation.SourceFrameOffset) *
                rotation.DegreesPerSourceFrame;
            using var shader = hpPaint.CreateShader((float)degrees);
            using var paint = new SKPaint
            {
                IsAntialias = true,
                Style = SKPaintStyle.Fill,
                Shader = shader
            };
            canvas.DrawPath(hpPaint.CoveragePath, paint);
        }
        finally
        {
            canvas.Restore();
        }
    }

    private SKPath BuildHpSector(double fraction)
    {
        var clip = _hp.Clip ??
            throw new InvalidDataException("Typed HP radial clip is missing.");
        var radius = (float)clip.Radius;
        var sector = new SKPath
        {
            FillType = SKPathFillType.Winding
        };
        sector.MoveTo((float)clip.Center.X, (float)clip.Center.Y);
        var startRadians = clip.StartAngleDegrees * Math.PI / 180;
        sector.LineTo(
            (float)(clip.Center.X + (radius * Math.Cos(startRadians))),
            (float)(clip.Center.Y + (radius * Math.Sin(startRadians))));
        sector.ArcTo(
            new SKRect(
                (float)clip.Center.X - radius,
                (float)clip.Center.Y - radius,
                (float)clip.Center.X + radius,
                (float)clip.Center.Y + radius),
            (float)clip.StartAngleDegrees,
            (float)(-360d * fraction),
            forceMoveTo: false);
        sector.Close();
        return sector;
    }

    private MpMaskResult BuildMpMask(string maskId, int virtualFrame)
    {
        var sourceOffset = _mp.FrameMap.SourceFrameOffset ??
            throw new InvalidDataException(
                "Typed MP source-frame offset is missing.");
        var sourceFrame = checked(virtualFrame + sourceOffset);
        var path = new SKPath
        {
            FillType = SKPathFillType.Winding
        };
        if (virtualFrame == _mp.FrameMap.EmptyVirtualFrame)
        {
            return new MpMaskResult(path, 0);
        }

        var interval = _mp.MorphIntervals.SingleOrDefault(candidate =>
            string.Equals(candidate.MaskId, maskId, StringComparison.Ordinal) &&
            sourceFrame >= candidate.SourceStart &&
            sourceFrame <= candidate.SourceEnd) ??
            throw new InvalidDataException(
                $"No typed {maskId} interval for virtual frame {virtualFrame}.");
        var span = interval.SourceEnd - interval.SourceStart;
        if (span <= 0)
        {
            path.Dispose();
            throw new InvalidDataException(
                $"Typed {maskId} interval has a non-positive span.");
        }
        var u = (sourceFrame - interval.SourceStart) / (double)span;

        foreach (var correspondence in interval.Correspondence)
        {
            if (correspondence.AStartAndAnchorsTwips.Count !=
                    correspondence.BStartAndAnchorsTwips.Count ||
                correspondence.AStartAndAnchorsTwips.Count < 4)
            {
                path.Dispose();
                throw new InvalidDataException(
                    $"Typed {maskId} correspondence endpoints are incompatible.");
            }
            for (var index = 0;
                 index < correspondence.AStartAndAnchorsTwips.Count;
                 index++)
            {
                var a = correspondence.AStartAndAnchorsTwips[index];
                var b = correspondence.BStartAndAnchorsTwips[index];
                var x = (a.X + ((b.X - a.X) * u)) /
                    _assetSet.Units.SourceTwipsPerSvgUnit;
                var y = (a.Y + ((b.Y - a.Y) * u)) /
                    _assetSet.Units.SourceTwipsPerSvgUnit;
                if (index == 0)
                {
                    path.MoveTo((float)x, (float)y);
                }
                else
                {
                    path.LineTo((float)x, (float)y);
                }
            }
            path.Close();
        }
        return new MpMaskResult(path, interval.Correspondence.Count);
    }

    private static void DrawMpFill(
        SKCanvas canvas,
        PlayerInfoRasterLayer layer,
        PlayerInfoRasterPlan plan,
        SKPath leftMask,
        SKPath rightMask)
    {
        DrawClippedBitmap(
            canvas,
            layer.RequireFragment(MpLeftMask),
            layer.Key.LayerId,
            plan,
            leftMask);
        DrawClippedBitmap(
            canvas,
            layer.RequireFragment(MpRightMask),
            layer.Key.LayerId,
            plan,
            rightMask);
    }

    private static void DrawClippedBitmap(
        SKCanvas canvas,
        Bitmap bitmap,
        string layerId,
        PlayerInfoRasterPlan plan,
        SKPath localMask)
    {
        var layerPlan = FindLayerPlan(plan, layerId);
        var destination = ToLocalRect(
            layerPlan.PhysicalBounds,
            plan.TightPhysicalBounds);
        var viewBox = layerPlan.SourceViewBox;
        using var mappedMask = new SKPath();
        var matrix = new SKMatrix(
            destination.Width / (float)viewBox.Width,
            0f,
            destination.Left -
                ((float)viewBox.Left * destination.Width / (float)viewBox.Width),
            0f,
            destination.Height / (float)viewBox.Height,
            destination.Top -
                ((float)viewBox.Top * destination.Height / (float)viewBox.Height),
            0f,
            0f,
            1f);
        localMask.Transform(matrix, mappedMask);

        canvas.Save();
        try
        {
            canvas.ClipPath(
                mappedMask,
                SKClipOperation.Intersect,
                antialias: true);
            DrawBitmap(canvas, bitmap, layerId, plan);
        }
        finally
        {
            canvas.Restore();
        }
    }

    private static void DrawLayer(
        SKCanvas canvas,
        PlayerInfoRasterLayer layer,
        PlayerInfoRasterPlan plan)
    {
        DrawBitmap(
            canvas,
            layer.Bitmap,
            layer.Key.LayerId,
            plan);
    }

    private static void DrawBitmap(
        SKCanvas canvas,
        Bitmap bitmap,
        string layerId,
        PlayerInfoRasterPlan plan)
    {
        var layerPlan = FindLayerPlan(plan, layerId);
        var destination = ToLocalRect(
            layerPlan.PhysicalBounds,
            plan.TightPhysicalBounds);
        BitmapData? locked = null;
        try
        {
            locked = bitmap.LockBits(
                new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                ImageLockMode.ReadOnly,
                PixelFormat.Format32bppPArgb);
            if (locked.Scan0 == IntPtr.Zero ||
                locked.Stride < checked(bitmap.Width * 4))
            {
                throw new InvalidDataException(
                    $"PlayerInfo layer '{layerId}' has an unsupported stride.");
            }
            var info = new SKImageInfo(
                bitmap.Width,
                bitmap.Height,
                SKColorType.Bgra8888,
                SKAlphaType.Premul);
            using var skBitmap = new SKBitmap();
            if (!skBitmap.InstallPixels(info, locked.Scan0, locked.Stride))
            {
                throw new InvalidOperationException(
                    $"Skia could not wrap PlayerInfo layer '{layerId}'.");
            }
            canvas.DrawBitmap(skBitmap, destination);
        }
        finally
        {
            if (locked is not null)
            {
                bitmap.UnlockBits(locked);
            }
        }
    }

    private void DrawText(
        SKCanvas canvas,
        PlayerInfoRasterPlan plan,
        PlayerInfoVisualState state,
        PlayerInfoPaletteState palette)
    {
        DrawGaugeText(canvas, plan, _mp, () =>
        {
            var label = ParseColor(palette.Label);
            var percent = ParseColor(palette.Percent);
            var current = ParseColor(palette.Current);
            var maximum = ParseColor(palette.Max);

            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.MpLabel,
                "MP",
                label);
            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.MpPercent,
                state.Mp.PercentText,
                percent);

            DrawMpDecorativeText(canvas, palette);
            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.MpCurrent,
                state.Mp.CurrentText,
                current);
            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.MpMaximum,
                state.Mp.MaximumText,
                maximum);
        });

        DrawGaugeText(canvas, plan, _hp, () =>
        {
            var white = SKColors.White;
            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.HpPercent,
                state.Hp.PercentText,
                white);
            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.HpMaximum,
                state.Hp.MaximumText,
                white);
            DrawPathText(
                canvas,
                PlayerInfoCompositionRecipe.HpCurrent,
                state.Hp.CurrentText,
                white);
        });
    }

    private void DrawMpDecorativeText(
        SKCanvas canvas,
        PlayerInfoPaletteState palette)
    {
        var current = ParseColor(
            palette.DecorativeCurrent.Color,
            palette.DecorativeCurrent.Alpha);
        var maximum = ParseColor(
            palette.DecorativeMax.Color,
            palette.DecorativeMax.Alpha);
        DrawPathText(
            canvas,
            PlayerInfoCompositionRecipe.MpCurrent,
            "99999",
            current);
        DrawPathText(
            canvas,
            PlayerInfoCompositionRecipe.MpMaximum,
            "99999",
            maximum);
    }

    private void DrawPathText(
        SKCanvas canvas,
        PlayerInfoTextLayout layout,
        string text,
        SKColor color) =>
        _glyphs.DrawText(
            canvas,
            layout.FontId,
            text,
            layout.FontPixels,
            layout.AnchorX,
            layout.BaselineY,
            layout.Alignment,
            color,
            layout.GlowSigmaPixels,
            layout.GlowColor);

    private static void DrawGaugeText(
        SKCanvas canvas,
        PlayerInfoRasterPlan plan,
        PlayerInfoSvgGauge gauge,
        Action draw)
    {
        var scale = (float)(plan.PhysicalScale * gauge.StageMatrix.A);
        var translationX = (float)(
            plan.FlashViewportPhysical.Left +
            (gauge.StageMatrix.Tx * plan.PhysicalScale) -
            plan.TightPhysicalBounds.Left);
        var translationY = (float)(
            plan.FlashViewportPhysical.Top +
            ((PlayerInfoRasterPlanner.PlayerInfoStageTopLogical +
              gauge.StageMatrix.Ty) * plan.PhysicalScale) -
            plan.TightPhysicalBounds.Top);
        canvas.Save();
        try
        {
            canvas.Translate(translationX, translationY);
            canvas.Scale(scale, scale);
            draw();
        }
        finally
        {
            canvas.Restore();
        }
    }

    private string SelectRim(int virtualFrame) =>
        _mp.RimVariants
            .Where(variant => virtualFrame >= variant.StartVirtualFrame)
            .OrderBy(variant => variant.StartVirtualFrame)
            .LastOrDefault()?.AssetId ??
        throw new InvalidDataException(
            $"No typed MP rim for virtual frame {virtualFrame}.");

    private PlayerInfoPaletteState SelectPalette(int virtualFrame) =>
        _mp.PaletteStates
            .Where(state => virtualFrame >= state.StartVirtualFrame)
            .OrderBy(state => state.StartVirtualFrame)
            .LastOrDefault() ??
        throw new InvalidDataException(
            $"No typed MP palette for virtual frame {virtualFrame}.");

    private static PlayerInfoRasterLayerPlan FindLayerPlan(
        PlayerInfoRasterPlan plan,
        string layerId) =>
        plan.Layers.Single(layer =>
            string.Equals(layer.Key.LayerId, layerId, StringComparison.Ordinal));

    private static SKRect ToLocalRect(
        Rectangle absolute,
        Rectangle tight) =>
        new(
            absolute.Left - tight.Left,
            absolute.Top - tight.Top,
            absolute.Right - tight.Left,
            absolute.Bottom - tight.Top);

    private static SKColor ParseColor(string value, double alpha = 1)
    {
        if (value is null ||
            value.Length != 7 ||
            value[0] != '#' ||
            !uint.TryParse(
                value.AsSpan(1),
                NumberStyles.AllowHexSpecifier,
                CultureInfo.InvariantCulture,
                out var rgb) ||
            !double.IsFinite(alpha) ||
            alpha < 0 ||
            alpha > 1)
        {
            throw new InvalidDataException(
                $"PlayerInfo color '{value}' is outside #RRGGBB/alpha.");
        }
        return new SKColor(
            (byte)(rgb >> 16),
            (byte)(rgb >> 8),
            (byte)rgb,
            (byte)Math.Round(alpha * 255, MidpointRounding.AwayFromZero));
    }

    private static void ValidateVirtualFrame(
        PlayerInfoSvgGauge gauge,
        int virtualFrame)
    {
        if (virtualFrame < gauge.FrameMap.FullVirtualFrame ||
            virtualFrame > gauge.FrameMap.EmptyVirtualFrame)
        {
            throw new InvalidDataException(
                $"PlayerInfo {gauge.Id} virtual frame {virtualFrame} is outside the typed map.");
        }
    }

    private sealed record MpMaskResult(SKPath Path, int ContourCount);

    private sealed class PlayerInfoHpPaintSource : IDisposable
    {
        private const string SvgNamespace = "http://www.w3.org/2000/svg";
        private bool _disposed;

        private PlayerInfoHpPaintSource(
            SKPath coveragePath,
            SKPoint center,
            float radius,
            SKColor[] colors,
            float[] positions,
            SKMatrix gradientMatrix)
        {
            CoveragePath = coveragePath;
            Center = center;
            Radius = radius;
            Colors = colors;
            Positions = positions;
            GradientMatrix = gradientMatrix;
        }

        internal SKPath CoveragePath { get; }
        private SKPoint Center { get; }
        private float Radius { get; }
        private SKColor[] Colors { get; }
        private float[] Positions { get; }
        private SKMatrix GradientMatrix { get; }

        internal static PlayerInfoHpPaintSource Load(
            PlayerInfoSvgAsset asset,
            PlayerInfoSvgGauge gauge)
        {
            var rotation = gauge.FillTextureRotation ??
                throw new InvalidDataException(
                    "Typed HP fill rotation is missing.");
            if (rotation.SvgGradientIds.Count != 1)
            {
                throw new InvalidDataException(
                    "PlayerInfo HP accepts exactly one rotating gradient.");
            }
            var text = new UTF8Encoding(false, true)
                .GetString(asset.Bytes.Span);
            var document = XDocument.Parse(
                text,
                LoadOptions.None);
            var ns = XNamespace.Get(SvgNamespace);
            var pathElement = document
                .Descendants(ns + "path")
                .SingleOrDefault(element =>
                    string.Equals(
                        (string?)element.Attribute("id"),
                        "hp-fill-path-0004",
                        StringComparison.Ordinal)) ??
                throw new InvalidDataException(
                    "Canonical HP fixed coverage path is missing.");
            var gradientId = rotation.SvgGradientIds.Single();
            if (!string.Equals(
                    (string?)pathElement.Attribute("fill"),
                    $"url(#{gradientId})",
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "Canonical HP coverage no longer references the typed gradient.");
            }
            var pathData = (string?)pathElement.Attribute("d");
            var coverage = SKPath.ParseSvgPathData(pathData) ??
                throw new InvalidDataException(
                    "Canonical HP coverage path did not parse.");
            coverage.FillType = SKPathFillType.EvenOdd;
            try
            {
                var gradient = document
                    .Descendants(ns + "radialGradient")
                    .SingleOrDefault(element =>
                        string.Equals(
                            (string?)element.Attribute("id"),
                            gradientId,
                            StringComparison.Ordinal)) ??
                    throw new InvalidDataException(
                        "Canonical HP rotating radial gradient is missing.");
                if (!string.Equals(
                        (string?)gradient.Attribute("gradientUnits"),
                        "userSpaceOnUse",
                        StringComparison.Ordinal) ||
                    !string.Equals(
                        (string?)gradient.Attribute("spreadMethod"),
                        "reflect",
                        StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "Canonical HP gradient units/spread drifted.");
                }
                var stops = gradient.Elements(ns + "stop").ToArray();
                if (stops.Length != 2)
                {
                    throw new InvalidDataException(
                        "Canonical HP gradient must contain exactly two stops.");
                }
                var positions = stops
                    .Select(stop => ParseFloatAttribute(stop, "offset"))
                    .ToArray();
                if (positions[0] != 0 || positions[1] != 1)
                {
                    throw new InvalidDataException(
                        "Canonical HP gradient stops must remain 0/1.");
                }
                var colors = stops
                    .Select(stop => ParseColor(
                        (string?)stop.Attribute("stop-color") ??
                        throw new InvalidDataException(
                            "Canonical HP gradient stop has no color.")))
                    .ToArray();
                var matrix = ParseMatrix(
                    (string?)gradient.Attribute("gradientTransform"));
                return new PlayerInfoHpPaintSource(
                    coverage,
                    new SKPoint(
                        ParseFloatAttribute(gradient, "cx"),
                        ParseFloatAttribute(gradient, "cy")),
                    ParseFloatAttribute(gradient, "r"),
                    colors,
                    positions,
                    matrix);
            }
            catch
            {
                coverage.Dispose();
                throw;
            }
        }

        internal SKShader CreateShader(float clockwiseDegrees)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var radians = clockwiseDegrees * MathF.PI / 180f;
            var cos = MathF.Cos(radians);
            var sin = MathF.Sin(radians);
            var source = GradientMatrix;
            var composed = new SKMatrix(
                (cos * source.ScaleX) - (sin * source.SkewY),
                (cos * source.SkewX) - (sin * source.ScaleY),
                (cos * source.TransX) - (sin * source.TransY),
                (sin * source.ScaleX) + (cos * source.SkewY),
                (sin * source.SkewX) + (cos * source.ScaleY),
                (sin * source.TransX) + (cos * source.TransY),
                0f,
                0f,
                1f);
            return SKShader.CreateRadialGradient(
                Center,
                Radius,
                Colors,
                Positions,
                SKShaderTileMode.Mirror,
                composed);
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            CoveragePath.Dispose();
        }

        private static float ParseFloatAttribute(
            XElement element,
            string attribute)
        {
            var value = (string?)element.Attribute(attribute);
            if (!float.TryParse(
                    value,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var number) ||
                !float.IsFinite(number))
            {
                throw new InvalidDataException(
                    $"Canonical HP gradient attribute '{attribute}' is invalid.");
            }
            return number;
        }

        private static SKMatrix ParseMatrix(string? value)
        {
            const string prefix = "matrix(";
            if (value is null ||
                !value.StartsWith(prefix, StringComparison.Ordinal) ||
                !value.EndsWith(")", StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "Canonical HP gradient matrix is missing.");
            }
            var values = value[prefix.Length..^1]
                .Split(
                    (char[]?)null,
                    StringSplitOptions.RemoveEmptyEntries)
                .Select(token =>
                {
                    if (!float.TryParse(
                            token,
                            NumberStyles.Float,
                            CultureInfo.InvariantCulture,
                            out var number) ||
                        !float.IsFinite(number))
                    {
                        throw new InvalidDataException(
                            "Canonical HP gradient matrix is non-finite.");
                    }
                    return number;
                })
                .ToArray();
            if (values.Length != 6)
            {
                throw new InvalidDataException(
                    "Canonical HP gradient matrix must have six components.");
            }
            return new SKMatrix(
                values[0],
                values[2],
                values[4],
                values[1],
                values[3],
                values[5],
                0f,
                0f,
                1f);
        }
    }
}
