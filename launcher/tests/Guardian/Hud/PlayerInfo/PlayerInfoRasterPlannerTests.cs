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
            new Rectangle(0, 512, 282, 46),
            1d,
            1.00f
        ];
        yield return
        [
            new Rectangle(0, 0, 1600, 900),
            new Rectangle(0, 800, 1600, 100),
            new Rectangle(0, 800, 440, 72),
            1.5625d,
            1.25f
        ];
        yield return
        [
            new Rectangle(0, 0, 1920, 1080),
            new Rectangle(0, 960, 1920, 120),
            new Rectangle(0, 960, 528, 86),
            1.875d,
            1.50f
        ];
        yield return
        [
            new Rectangle(0, 120, 1280, 720),
            new Rectangle(0, 760, 1280, 80),
            new Rectangle(0, 760, 352, 57),
            1.25d,
            1.75f
        ];
    }

    [Theory]
    [MemberData(nameof(Viewports))]
    public void Create_MapsFrozenTy512WithFloorTopLeftAndCeilBottomRight(
        Rectangle viewport,
        Rectangle expectedStage,
        Rectangle expectedTight,
        double expectedScale,
        float monitorDpiScale)
    {
        PlayerInfoRasterPlan plan = Create(viewport, monitorDpiScale);

        Assert.Equal(expectedStage, plan.StagePhysicalBounds);
        Assert.Equal(expectedTight, plan.TightPhysicalBounds);
        Assert.Equal(expectedScale, plan.PhysicalScale, 8);
        Assert.Equal(monitorDpiScale, plan.MonitorDpiScale);
        Assert.Equal(8, plan.Layers.Count);
        Assert.Equal(8, plan.Layers.Select(layer => layer.Key.LayerId).Distinct().Count());
        Rectangle layerEnvelope = plan.Layers
            .Select(layer => layer.PhysicalBounds)
            .Aggregate(Rectangle.Union);
        Assert.Equal(
            Rectangle.Intersect(layerEnvelope, plan.StagePhysicalBounds),
            plan.TightPhysicalBounds);
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
        Assert.Equal(baseline.TightPhysicalBounds, candidate.TightPhysicalBounds);
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
        Assert.Equal(first.TightPhysicalBounds.Size, moved.TightPhysicalBounds.Size);
        Assert.Equal(
            new Point(311, 227),
            new Point(
                moved.TightPhysicalBounds.Left - first.TightPhysicalBounds.Left,
                moved.TightPhysicalBounds.Top - first.TightPhysicalBounds.Top));
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

    [Fact]
    public void ComputeTightPhysicalBounds_NullLayersFailClosed()
    {
        Assert.Throws<ArgumentNullException>(() =>
            PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
                new Rectangle(0, 512, 1024, 64),
                null!));
    }

    [Fact]
    public void ComputeTightPhysicalBounds_EmptyLayersFailClosed()
    {
        Assert.Throws<InvalidOperationException>(() =>
            PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
                new Rectangle(0, 512, 1024, 64),
                Array.Empty<PlayerInfoRasterLayerPlan>()));
    }

    [Theory]
    [InlineData(0, 64)]
    [InlineData(1024, 0)]
    [InlineData(-1, 64)]
    [InlineData(1024, -1)]
    public void ComputeTightPhysicalBounds_DegenerateStageFailsClosed(
        int width,
        int height)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
                new Rectangle(0, 512, width, height),
                [CreateLayer(new Rectangle(0, 512, 1, 1))]));
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(1, 0)]
    [InlineData(-1, 1)]
    [InlineData(1, -1)]
    public void ComputeTightPhysicalBounds_DegenerateLayerFailsClosed(
        int width,
        int height)
    {
        Assert.Throws<InvalidOperationException>(() =>
            PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
                new Rectangle(0, 512, 1024, 64),
                [CreateLayer(new Rectangle(0, 512, width, height))]));
    }

    [Fact]
    public void ComputeTightPhysicalBounds_DisjointEnvelopeFailsClosed()
    {
        Assert.Throws<InvalidOperationException>(() =>
            PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
                new Rectangle(0, 512, 1024, 64),
                [CreateLayer(new Rectangle(0, 0, 10, 10))]));
    }

    [Fact]
    public void ComputeTightPhysicalBounds_WrappedEdgeFailsClosed()
    {
        Assert.Throws<InvalidOperationException>(() =>
            PlayerInfoRasterPlanner.ComputeTightPhysicalBounds(
                new Rectangle(0, 512, 1024, 64),
                [
                    CreateLayer(
                        new Rectangle(int.MaxValue - 1, 512, 2, 1))
                ]));
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

    private static PlayerInfoRasterLayerPlan CreateLayer(Rectangle bounds)
    {
        PlayerInfoRasterLayerPlan template = Create(
            new Rectangle(0, 0, 1024, 576),
            1f).Layers[0];
        return new PlayerInfoRasterLayerPlan(
            template.Asset,
            template.Gauge,
            template.Key,
            bounds);
    }
}
