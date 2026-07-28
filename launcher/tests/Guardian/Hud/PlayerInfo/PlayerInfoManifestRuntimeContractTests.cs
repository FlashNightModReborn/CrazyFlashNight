using System;
using System.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoManifestRuntimeContractTests
{
    [Fact]
    public void EmbeddedManifest_PreservesTypedRuntimeLayoutAndRendererIdentity()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);

        Assert.Equal(1024, assetSet.Stage.LogicalWidth);
        Assert.Equal(64, assetSet.Stage.LogicalHeight);
        Assert.Equal(new[] { "mp", "hp" }, assetSet.Stage.CompositeOrder);
        Assert.Equal(
            "Svg.Skia/5.1.1;SkiaSharp/3.119.4;cf7-player-info-static-svg-v1;Bgra8888/premultiplied",
            assetSet.RendererIdentity.CacheIdentity);
        Assert.Equal(new[] { "hp", "mp" }, assetSet.Gauges.Keys.OrderBy(id => id));

        PlayerInfoSvgGauge hp = assetSet.Gauges["hp"];
        Assert.Equal(
            new PlayerInfoSvgMatrix(
                0.847213745117188,
                0,
                0,
                0.847213745117188,
                37.75,
                5.65),
            hp.StageMatrix);
        Assert.Equal(
            new[] { "hp.backplate", "hp.fill", "hp.rim" },
            hp.AssetIds);

        PlayerInfoSvgGauge mp = assetSet.Gauges["mp"];
        Assert.Equal(
            new[]
            {
                "mp.backplate",
                "mp.fill",
                "mp.rim",
                "mp.rim-vf70",
                "mp.rim-vf91"
            },
            mp.AssetIds);

        Assert.All(assetSet.Assets, asset =>
        {
            Assert.True(asset.ViewBox.Width > 0);
            Assert.True(asset.ViewBox.Height > 0);
            Assert.Equal(new PlayerInfoSvgPoint(0, 0), asset.Registration);
            Assert.Equal("source-over", asset.BlendMode);
            Assert.Equal(1d, asset.Opacity);
            Assert.True(asset.Cacheable);
        });
    }

    [Fact]
    public void RasterKey_ContainsOnlyFrozenSevenDimensions()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            new System.Drawing.Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1.75f);
        PlayerInfoRasterKey key = plan.Layers[0].Key;

        Assert.Equal(assetSet.Revision, key.AssetSetRevision);
        Assert.Equal(assetSet.ExactManifestSha256, key.ExactManifestSha256);
        Assert.False(string.IsNullOrWhiteSpace(key.LayerId));
        Assert.True(key.PixelWidth > 0);
        Assert.True(key.PixelHeight > 0);
        Assert.Equal(assetSet.RendererIdentity.CacheIdentity, key.RendererIdentity);
        Assert.Equal(assetSet.RasterContractVersion, key.RasterContractVersion);
        Assert.DoesNotContain("1.75", key.ToCacheIdentity(), StringComparison.Ordinal);
    }
}
