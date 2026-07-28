using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoSvgRasterizerTests
{
    public static IEnumerable<object[]> TargetScales()
    {
        yield return [1.00, 40, 20];
        yield return [1.25, 50, 25];
        yield return [1.50, 60, 30];
        yield return [1.75, 70, 35];
    }

    [Theory]
    [MemberData(nameof(TargetScales))]
    public void QualifiedSvg_ExplicitlyMapsNegativeOriginViewBoxToTarget(
        double scale,
        int targetWidth,
        int targetHeight)
    {
        byte[] svg = Encoding.UTF8.GetBytes(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"20\" " +
            "viewBox=\"-10 -5 40 20\" preserveAspectRatio=\"xMidYMid meet\">" +
            "<rect x=\"-10\" y=\"-5\" width=\"40\" height=\"20\" fill=\"#FF0000\"/>" +
            "</svg>");
        using QualifiedSvg qualified = StrictSvgFacade.Load(svg);
        using SKBitmap bitmap = qualified.Rasterize(
            targetWidth,
            targetHeight,
            new PlayerInfoSvgRect(-10, -5, 40, 20));

        Assert.Equal(targetWidth, bitmap.Width);
        Assert.Equal(targetHeight, bitmap.Height);
        Assert.Equal(SKColorType.Bgra8888, bitmap.ColorType);
        Assert.Equal(SKAlphaType.Premul, bitmap.AlphaType);
        SKColor center = bitmap.GetPixel(targetWidth / 2, targetHeight / 2);
        Assert.Equal((byte)255, center.Alpha);
        Assert.True(center.Red >= 250);
        Assert.True(center.Green <= 5);
        Assert.True(center.Blue <= 5);
        Assert.Equal(scale, targetWidth / 40d, 8);
    }

    [Fact]
    public void Bake_ProducesEightCanonicalLayersWithOwnedMpStableGroupFragments()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            new System.Drawing.Rectangle(0, 0, 1024, 576),
            1f);
        var rasterizer = new PlayerInfoSvgRasterizer();
        var progress = new PlayerInfoRasterProgress();

        using PlayerInfoRasterBatch batch =
            rasterizer.Bake(plan, CancellationToken.None, progress);

        Assert.Equal(plan.BatchKey, batch.BatchKey);
        Assert.Equal(8, batch.Layers.Count);
        Assert.Equal(10, progress.ParseCount);
        Assert.Equal(10, progress.RasterCount);
        Assert.Equal(
            plan.Layers.Select(layer => layer.Key),
            batch.Layers.Select(layer => layer.Key));
        Assert.All(batch.Layers, layer =>
        {
            Assert.Equal(PixelFormat.Format32bppPArgb, layer.Bitmap.PixelFormat);
            Assert.Equal(layer.Key.PixelWidth, layer.Bitmap.Width);
            Assert.Equal(layer.Key.PixelHeight, layer.Bitmap.Height);
        });
        PlayerInfoRasterLayer mpFill = batch.Layers.Single(
            layer => layer.Key.LayerId == "mp.fill");
        Assert.Equal(
            new[] { "mp-left-mask", "mp-right-mask" },
            mpFill.FragmentIds.OrderBy(id => id, StringComparer.Ordinal));
        Assert.All(
            new[] { "mp-left-mask", "mp-right-mask" },
            fragmentId =>
            {
                System.Drawing.Bitmap fragment =
                    mpFill.RequireFragment(fragmentId);
                Assert.Equal(
                    PixelFormat.Format32bppPArgb,
                    fragment.PixelFormat);
                Assert.Equal(mpFill.Key.PixelWidth, fragment.Width);
                Assert.Equal(mpFill.Key.PixelHeight, fragment.Height);
            });
        Assert.All(
            batch.Layers.Where(layer => layer.Key.LayerId != "mp.fill"),
            layer => Assert.Empty(layer.FragmentIds));
        long expectedBytes = batch.Layers.Sum(layer =>
            checked(
                (long)layer.Key.PixelWidth *
                layer.Key.PixelHeight *
                4L *
                (layer.Key.LayerId == "mp.fill" ? 3L : 1L)));
        Assert.Equal(expectedBytes, batch.ByteSize);
        Assert.True(
            batch.ByteSize < PlayerInfoRasterPipeline.DefaultMaxCacheBytes);
    }

    [Fact]
    public void MpFragmenter_RejectsAnyBindingThatDoesNotPartitionDirectGroups()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(
                minimumRaster: false);
        PlayerInfoSvgAsset fill = assetSet.Assets.Single(
            asset => asset.Id == "mp.fill");

        Assert.Throws<System.IO.InvalidDataException>(() =>
            PlayerInfoSvgGroupFragmenter.Create(
                fill.Bytes,
                [
                    new PlayerInfoClipBinding(
                        "mp-left-mask",
                        "mp.fill",
                        ["mp-fill-left-slot"]),
                    new PlayerInfoClipBinding(
                        "mp-right-mask",
                        "mp.fill",
                        [
                            "mp-fill-right-decoration",
                            "mp-fill-right-slot"
                        ])
                ]));
    }

    [Fact]
    public void RasterLayer_RejectsAliasedOwnedFragmentBitmaps()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(
                minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            new Rectangle(0, 0, 1024, 576),
            1f);
        PlayerInfoRasterKey key = plan.Layers[0].Key;
        using var bitmap = new Bitmap(
            key.PixelWidth,
            key.PixelHeight,
            PixelFormat.Format32bppPArgb);
        using var aliasedFragment = new Bitmap(
            key.PixelWidth,
            key.PixelHeight,
            PixelFormat.Format32bppPArgb);

        Assert.Throws<ArgumentException>(() =>
            new PlayerInfoRasterLayer(
                key,
                bitmap,
                new Dictionary<string, Bitmap>(StringComparer.Ordinal)
                {
                    ["fragment-a"] = aliasedFragment,
                    ["fragment-b"] = aliasedFragment
                }));
    }

    [Fact]
    public void Bake_PreCancelledTokenPublishesNoPartialBatch()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            new System.Drawing.Rectangle(0, 0, 1024, 576),
            1f);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        Assert.Throws<OperationCanceledException>(
            () => new PlayerInfoSvgRasterizer().Bake(plan, cancellation.Token));
    }
}
