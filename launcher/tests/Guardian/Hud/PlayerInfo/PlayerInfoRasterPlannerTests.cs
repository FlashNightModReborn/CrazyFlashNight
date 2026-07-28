using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoRasterPlannerTests
{
    public static IEnumerable<object[]> Viewports()
    {
        yield return
        [
            new Rectangle(0, 0, 1024, 576),
            new Rectangle(0, 512, 1024, 64),
            1d
        ];
        yield return
        [
            new Rectangle(0, 0, 1600, 900),
            new Rectangle(0, 800, 1600, 100),
            1.5625d
        ];
        yield return
        [
            new Rectangle(0, 0, 1920, 1080),
            new Rectangle(0, 960, 1920, 120),
            1.875d
        ];
        yield return
        [
            new Rectangle(0, 96, 1024, 576),
            new Rectangle(0, 608, 1024, 64),
            1d
        ];
    }

    [Theory]
    [MemberData(nameof(Viewports))]
    public void Create_MapsFrozenTy512WithFloorTopLeftAndCeilBottomRight(
        Rectangle viewport,
        Rectangle expectedStage,
        double expectedScale)
    {
        PlayerInfoRasterPlan plan = Create(viewport, 1f);

        Assert.Equal(expectedStage, plan.StagePhysicalBounds);
        Assert.Equal(expectedScale, plan.PhysicalScale, 8);
        Assert.Equal(8, plan.Layers.Count);
        Assert.Equal(8, plan.Layers.Select(layer => layer.Key.LayerId).Distinct().Count());
        Assert.All(plan.Layers, layer =>
        {
            Assert.True(layer.PhysicalBounds.Width > 0);
            Assert.True(layer.PhysicalBounds.Height > 0);
            Assert.Equal(layer.PhysicalBounds.Width, layer.Key.PixelWidth);
            Assert.Equal(layer.PhysicalBounds.Height, layer.Key.PixelHeight);
        });
    }

    [Theory]
    [InlineData(1.00f)]
    [InlineData(1.25f)]
    [InlineData(1.50f)]
    [InlineData(1.75f)]
    public void MonitorDpiScale_IsTelemetryOnlyAndNeverDoubleMultiplies(
        float monitorDpiScale)
    {
        Rectangle viewport = new(13, 17, 1280, 720);
        PlayerInfoRasterPlan baseline = Create(viewport, 1f);
        PlayerInfoRasterPlan candidate = Create(viewport, monitorDpiScale);

        Assert.Equal(monitorDpiScale, candidate.MonitorDpiScale);
        Assert.Equal(baseline.PhysicalScale, candidate.PhysicalScale);
        Assert.Equal(baseline.StagePhysicalBounds, candidate.StagePhysicalBounds);
        Assert.Equal(
            baseline.Layers.Select(layer => layer.Key),
            candidate.Layers.Select(layer => layer.Key));
    }

    [Theory]
    [InlineData(1.00, 1024, 576)]
    [InlineData(1.25, 1280, 720)]
    [InlineData(1.50, 1536, 864)]
    [InlineData(1.75, 1792, 1008)]
    public void PhysicalScale_ChangesIntegerRasterDimensionsExactlyOnce(
        double expectedScale,
        int viewportWidth,
        int viewportHeight)
    {
        PlayerInfoRasterPlan plan = Create(
            new Rectangle(0, 0, viewportWidth, viewportHeight),
            (float)expectedScale);

        Assert.Equal(expectedScale, plan.PhysicalScale, 8);
        PlayerInfoRasterLayerPlan hp = plan.Layers.Single(
            layer => layer.Key.LayerId == "hp.backplate");
        double exactWidth =
            hp.SourceViewBox.Width * hp.Gauge.StageMatrix.A * expectedScale;
        Assert.InRange(hp.PixelWidth, (int)Math.Floor(exactWidth), (int)Math.Ceiling(exactWidth) + 1);
    }

    [Fact]
    public void SamePhysicalSizeAtDifferentScreenOrigin_ReusesKeysButNotPlacement()
    {
        PlayerInfoRasterPlan first = Create(
            new Rectangle(0, 0, 1024, 576),
            1f);
        PlayerInfoRasterPlan moved = Create(
            new Rectangle(311, 227, 1024, 576),
            1.75f);

        Assert.Equal(first.BatchKey, moved.BatchKey);
        Assert.Equal(
            first.Layers.Select(layer => layer.Key),
            moved.Layers.Select(layer => layer.Key));
        Assert.All(
            first.Layers.Zip(moved.Layers),
            pair =>
            {
                Assert.Equal(
                    pair.First.PhysicalBounds.Size,
                    pair.Second.PhysicalBounds.Size);
                Assert.Equal(
                    new Point(311, 227),
                    new Point(
                        pair.Second.PhysicalBounds.Left - pair.First.PhysicalBounds.Left,
                        pair.Second.PhysicalBounds.Top - pair.First.PhysicalBounds.Top));
            });
    }

    [Theory]
    [InlineData(1.00)]
    [InlineData(1.25)]
    [InlineData(1.50)]
    [InlineData(1.75)]
    public void NegativeViewBox_UsesOutwardFloorCeilingAtEveryPhysicalScale(
        double physicalScale)
    {
        var viewport = new Rectangle(
            13,
            17,
            checked((int)Math.Round(1024 * physicalScale)),
            checked((int)Math.Round(576 * physicalScale)));
        PlayerInfoRasterPlan plan = Create(viewport, (float)physicalScale);
        PlayerInfoRasterLayerPlan hp = plan.Layers.Single(
            layer => layer.Key.LayerId == "hp.backplate");

        Assert.True(hp.SourceViewBox.Left < 0);
        Assert.True(hp.SourceViewBox.Top < 0);
        double exactLeft = viewport.Left +
            ((hp.Gauge.StageMatrix.Tx +
              (hp.Gauge.StageMatrix.A * hp.SourceViewBox.Left)) *
             physicalScale);
        double exactTop = viewport.Top +
            ((PlayerInfoRasterPlanner.PlayerInfoStageTopLogical +
              hp.Gauge.StageMatrix.Ty +
              (hp.Gauge.StageMatrix.D * hp.SourceViewBox.Top)) *
             physicalScale);
        double exactRight = viewport.Left +
            ((hp.Gauge.StageMatrix.Tx +
              (hp.Gauge.StageMatrix.A * hp.SourceViewBox.Right)) *
             physicalScale);
        double exactBottom = viewport.Top +
            ((PlayerInfoRasterPlanner.PlayerInfoStageTopLogical +
              hp.Gauge.StageMatrix.Ty +
              (hp.Gauge.StageMatrix.D * hp.SourceViewBox.Bottom)) *
             physicalScale);

        Assert.Equal((int)Math.Floor(exactLeft), hp.PhysicalBounds.Left);
        Assert.Equal((int)Math.Floor(exactTop), hp.PhysicalBounds.Top);
        Assert.Equal((int)Math.Ceiling(exactRight), hp.PhysicalBounds.Right);
        Assert.Equal((int)Math.Ceiling(exactBottom), hp.PhysicalBounds.Bottom);
    }

    private static PlayerInfoRasterPlan Create(
        Rectangle viewport,
        float monitorDpiScale)
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        return PlayerInfoRasterPlanner.Create(
            assetSet,
            viewport,
            monitorDpiScale);
    }
}
