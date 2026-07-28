#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal readonly record struct PlayerInfoRasterKey(
    string AssetSetRevision,
    string ExactManifestSha256,
    string LayerId,
    int PixelWidth,
    int PixelHeight,
    string RendererIdentity,
    int RasterContractVersion)
{
    internal string ToCacheIdentity() =>
        string.Join(
            "\u001f",
            AssetSetRevision,
            ExactManifestSha256,
            LayerId,
            PixelWidth.ToString(CultureInfo.InvariantCulture),
            PixelHeight.ToString(CultureInfo.InvariantCulture),
            RendererIdentity,
            RasterContractVersion.ToString(CultureInfo.InvariantCulture));
}

internal sealed class PlayerInfoRasterLayerPlan(
    PlayerInfoSvgAsset asset,
    PlayerInfoSvgGauge gauge,
    PlayerInfoRasterKey key,
    Rectangle physicalBounds)
{
    internal PlayerInfoSvgAsset Asset { get; } = asset;
    internal PlayerInfoSvgGauge Gauge { get; } = gauge;
    internal PlayerInfoRasterKey Key { get; } = key;
    internal Rectangle PhysicalBounds { get; } = physicalBounds;
    internal PlayerInfoSvgRect SourceViewBox => Asset.ViewBox;
    internal PlayerInfoSvgPoint Registration => Asset.Registration;
    internal int PixelWidth => Key.PixelWidth;
    internal int PixelHeight => Key.PixelHeight;
}

internal sealed class PlayerInfoRasterPlan(
    Rectangle flashViewportPhysical,
    Rectangle stagePhysicalBounds,
    double physicalScale,
    float monitorDpiScale,
    IReadOnlyList<PlayerInfoRasterLayerPlan> layers)
{
    internal Rectangle FlashViewportPhysical { get; } = flashViewportPhysical;
    internal Rectangle StagePhysicalBounds { get; } = stagePhysicalBounds;
    internal Rectangle TightPhysicalBounds { get; } =
        PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
            stagePhysicalBounds,
            layers);
    internal double PhysicalScale { get; } = physicalScale;

    // Telemetry only. PMv2 viewport coordinates are already physical pixels.
    internal float MonitorDpiScale { get; } = monitorDpiScale;
    internal IReadOnlyList<PlayerInfoRasterLayerPlan> Layers { get; } = layers;
    internal string BatchKey { get; } = string.Join(
        "\u001e",
        layers.Select(layer => layer.Key.ToCacheIdentity()));
}

internal static class PlayerInfoRasterPlanner
{
    internal const double MainStageLogicalHeight = 576d;
    // CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml:5654-5657 freezes
    // the PlayerInfo child placement at ty=512 in the 1024x576 main stage.
    internal const double PlayerInfoStageTopLogical = 512d;

    internal static PlayerInfoRasterPlan Create(
        PlayerInfoSvgAssetSet assetSet,
        Rectangle flashViewportPhysical,
        float monitorDpiScale)
    {
        ArgumentNullException.ThrowIfNull(assetSet);
        if (flashViewportPhysical.Width <= 0 || flashViewportPhysical.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(flashViewportPhysical),
                "Flash viewport must have positive physical dimensions.");
        }
        if (!float.IsFinite(monitorDpiScale) || monitorDpiScale <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(monitorDpiScale),
                "Monitor DPI scale must be finite and positive.");
        }

        var physicalScale = flashViewportPhysical.Height / MainStageLogicalHeight;
        var stageTopLogical = PlayerInfoStageTopLogical;
        if (stageTopLogical + assetSet.Stage.LogicalHeight != MainStageLogicalHeight)
        {
            throw new InvalidOperationException(
                "Typed PlayerInfo stage no longer matches the frozen main-stage placement.");
        }
        var stageBounds = MapLogicalRect(
            flashViewportPhysical,
            physicalScale,
            new PlayerInfoSvgRect(
                0,
                stageTopLogical,
                assetSet.Stage.LogicalWidth,
                assetSet.Stage.LogicalHeight));

        var assetsById = assetSet.Assets.ToDictionary(
            asset => asset.Id,
            StringComparer.Ordinal);
        var layers = new List<PlayerInfoRasterLayerPlan>(
            PlayerInfoSvgAssetCatalog.ExpectedAssetCount);
        foreach (var gaugeId in assetSet.Stage.CompositeOrder)
        {
            if (!assetSet.Gauges.TryGetValue(gaugeId, out var gauge))
            {
                throw new InvalidOperationException(
                    $"PlayerInfo gauge '{gaugeId}' is missing from the typed manifest.");
            }
            foreach (var assetId in gauge.AssetIds)
            {
                if (!assetsById.TryGetValue(assetId, out var asset))
                {
                    throw new InvalidOperationException(
                        $"PlayerInfo asset '{assetId}' is missing from the typed manifest.");
                }

                var transformed = gauge.StageMatrix.TransformBounds(asset.ViewBox);
                var physicalBounds = MapLogicalRect(
                    flashViewportPhysical,
                    physicalScale,
                    new PlayerInfoSvgRect(
                        transformed.X,
                        stageTopLogical + transformed.Y,
                        transformed.Width,
                        transformed.Height));
                if (physicalBounds.Width > StrictSvgValidator.MaxDimension ||
                    physicalBounds.Height > StrictSvgValidator.MaxDimension)
                {
                    throw new InvalidOperationException(
                        $"PlayerInfo layer '{asset.Id}' exceeds the raster dimension contract.");
                }

                var key = new PlayerInfoRasterKey(
                    assetSet.Revision,
                    assetSet.ExactManifestSha256,
                    asset.Id,
                    physicalBounds.Width,
                    physicalBounds.Height,
                    assetSet.RendererIdentity.CacheIdentity,
                    assetSet.RasterContractVersion);
                layers.Add(new PlayerInfoRasterLayerPlan(
                    asset,
                    gauge,
                    key,
                    physicalBounds));
            }
        }

        if (layers.Count != PlayerInfoSvgAssetCatalog.ExpectedAssetCount ||
            layers.Select(layer => layer.Key.LayerId)
                .Distinct(StringComparer.Ordinal)
                .Count() != PlayerInfoSvgAssetCatalog.ExpectedAssetCount)
        {
            throw new InvalidOperationException(
                $"PlayerInfo raster plan must contain exactly {PlayerInfoSvgAssetCatalog.ExpectedAssetCount} unique layers.");
        }

        return new PlayerInfoRasterPlan(
            flashViewportPhysical,
            stageBounds,
            physicalScale,
            monitorDpiScale,
            layers);
    }

    internal static Rectangle ComputeTightPhysicalBounds(
        Rectangle stagePhysicalBounds,
        IReadOnlyList<PlayerInfoRasterLayerPlan> layers)
    {
        if (stagePhysicalBounds.Width <= 0 ||
            stagePhysicalBounds.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(stagePhysicalBounds),
                "PlayerInfo stage bounds must be non-empty.");
        }
        ArgumentNullException.ThrowIfNull(layers);
        if (layers.Count == 0)
        {
            throw new InvalidOperationException(
                "PlayerInfo raster plan must contain at least one layer.");
        }

        var stageLeft = (long)stagePhysicalBounds.Left;
        var stageTop = (long)stagePhysicalBounds.Top;
        var stageRight = stageLeft + stagePhysicalBounds.Width;
        var stageBottom = stageTop + stagePhysicalBounds.Height;
        ValidatePhysicalEdges(
            stageLeft,
            stageTop,
            stageRight,
            stageBottom,
            "PlayerInfo stage bounds");

        long unionLeft = long.MaxValue;
        long unionTop = long.MaxValue;
        long unionRight = long.MinValue;
        long unionBottom = long.MinValue;
        for (var index = 0; index < layers.Count; index++)
        {
            var layer = layers[index];
            if (layer is null)
            {
                throw new InvalidOperationException(
                    $"PlayerInfo raster layer at index {index} is null.");
            }

            var bounds = layer.PhysicalBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                throw new InvalidOperationException(
                    $"PlayerInfo raster layer '{layer.Key.LayerId}' has empty physical bounds.");
            }

            var right = (long)bounds.Left + bounds.Width;
            var bottom = (long)bounds.Top + bounds.Height;
            ValidatePhysicalEdges(
                bounds.Left,
                bounds.Top,
                right,
                bottom,
                $"PlayerInfo raster layer '{layer.Key.LayerId}'");

            unionLeft = Math.Min(unionLeft, bounds.Left);
            unionTop = Math.Min(unionTop, bounds.Top);
            unionRight = Math.Max(unionRight, right);
            unionBottom = Math.Max(unionBottom, bottom);
        }

        var tightLeft = Math.Max(unionLeft, stageLeft);
        var tightTop = Math.Max(unionTop, stageTop);
        var tightRight = Math.Min(unionRight, stageRight);
        var tightBottom = Math.Min(unionBottom, stageBottom);
        if (tightRight <= tightLeft || tightBottom <= tightTop)
        {
            throw new InvalidOperationException(
                "PlayerInfo layer envelope does not intersect the stage bounds.");
        }

        return Rectangle.FromLTRB(
            checked((int)tightLeft),
            checked((int)tightTop),
            checked((int)tightRight),
            checked((int)tightBottom));
    }

    private static Rectangle MapLogicalRect(
        Rectangle flashViewportPhysical,
        double physicalScale,
        PlayerInfoSvgRect logicalRect)
    {
        var left = FloorToInt(
            flashViewportPhysical.Left + (logicalRect.Left * physicalScale));
        var top = FloorToInt(
            flashViewportPhysical.Top + (logicalRect.Top * physicalScale));
        var right = CeilingToInt(
            flashViewportPhysical.Left + (logicalRect.Right * physicalScale));
        var bottom = CeilingToInt(
            flashViewportPhysical.Top + (logicalRect.Bottom * physicalScale));
        if (right <= left || bottom <= top)
        {
            throw new InvalidOperationException(
                "PlayerInfo logical bounds mapped to an empty physical rectangle.");
        }
        return Rectangle.FromLTRB(left, top, right, bottom);
    }

    private static int FloorToInt(double value)
    {
        if (!double.IsFinite(value) || value < int.MinValue || value > int.MaxValue)
        {
            throw new InvalidOperationException(
                "PlayerInfo physical coordinate is non-finite or outside Int32.");
        }
        return checked((int)Math.Floor(value));
    }

    private static int CeilingToInt(double value)
    {
        if (!double.IsFinite(value) || value < int.MinValue || value > int.MaxValue)
        {
            throw new InvalidOperationException(
                "PlayerInfo physical coordinate is non-finite or outside Int32.");
        }
        return checked((int)Math.Ceiling(value));
    }

    private static void ValidatePhysicalEdges(
        long left,
        long top,
        long right,
        long bottom,
        string subject)
    {
        if (left < int.MinValue ||
            top < int.MinValue ||
            right > int.MaxValue ||
            bottom > int.MaxValue ||
            right <= left ||
            bottom <= top)
        {
            throw new InvalidOperationException(
                subject + " exceed the non-empty Int32 rectangle contract.");
        }
    }
}
