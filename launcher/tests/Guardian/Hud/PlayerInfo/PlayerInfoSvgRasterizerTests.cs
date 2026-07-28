using System;
using System.Collections.Generic;
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
    public void Bake_ProducesOneAtomicPArgbLayerForEveryCanonicalAsset()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            new System.Drawing.Rectangle(0, 0, 1024, 576),
            1f);
        var rasterizer = new PlayerInfoSvgRasterizer();

        using PlayerInfoRasterBatch batch =
            rasterizer.Bake(plan, CancellationToken.None);

        Assert.Equal(plan.BatchKey, batch.BatchKey);
        Assert.Equal(8, batch.Layers.Count);
        Assert.Equal(
            plan.Layers.Select(layer => layer.Key),
            batch.Layers.Select(layer => layer.Key));
        Assert.All(batch.Layers, layer =>
        {
            Assert.Equal(PixelFormat.Format32bppPArgb, layer.Bitmap.PixelFormat);
            Assert.Equal(layer.Key.PixelWidth, layer.Bitmap.Width);
            Assert.Equal(layer.Key.PixelHeight, layer.Bitmap.Height);
        });
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
