#nullable enable

using System;
using System.Drawing;
using System.Linq;
using System.Reflection;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoWidgetTests
{
    [Fact]
    public void TypeBoundary_CannotEnterNativeHudOrUiDataFanout()
    {
        Type[] interfaces = typeof(PlayerInfoWidget).GetInterfaces();

        Assert.DoesNotContain(typeof(INativeHudWidget), interfaces);
        Assert.DoesNotContain(typeof(IUiDataConsumer), interfaces);
        Assert.DoesNotContain(typeof(IPlayerInfoVisualStateSource), interfaces);
        Assert.DoesNotContain(
            typeof(PlayerInfoAnimationModel),
            typeof(PlayerInfoWidget)
                .GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                .Select(field => field.FieldType));
        Assert.Null(
            typeof(PlayerInfoWidget).GetMethod(
                "ApplyFixture",
                BindingFlags.Instance | BindingFlags.NonPublic));
        Assert.Null(
            typeof(PlayerInfoWidget).GetMethod(
                "Tick",
                BindingFlags.Instance | BindingFlags.NonPublic));
    }

    [Fact]
    public void TryHitTest_IsAlwaysFalse()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        var model = new PlayerInfoAnimationModel();
        using var widget = new PlayerInfoWidget(assets, model);

        Assert.False(widget.TryHitTest(Point.Empty));
        Assert.False(widget.TryHitTest(new Point(int.MinValue, int.MaxValue)));
    }

    [Fact]
    public void InjectedSource_IsTheSingleReadOnlyVisualAuthority()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        var model = new PlayerInfoAnimationModel();
        using var widget = new PlayerInfoWidget(assets, model);

        Assert.Same(model.VisualState, widget.VisualState);
        Assert.True(model.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId("full")));
        Assert.Same(model.VisualState, widget.VisualState);
        Assert.False(model.WantsAnimationTick);
        Assert.True(model.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId("empty")));
        Assert.Same(model.VisualState, widget.VisualState);
        Assert.True(model.WantsAnimationTick);
        Assert.False(model.Tick(16));
        Assert.True(model.Tick(18));
        Assert.Same(model.VisualState, widget.VisualState);
        Assert.Equal(10, widget.VisualState.Hp.CurrentVirtualFrame);
        Assert.Equal(8, widget.VisualState.Mp.CurrentVirtualFrame);
        Assert.Equal("empty", model.LastFixtureCaseId);
    }

    [Fact]
    public void DisposeIsIdempotentAndRejectsFurtherUse()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        var model = new PlayerInfoAnimationModel();
        var widget = new PlayerInfoWidget(assets, model);

        widget.Dispose();
        widget.Dispose();

        using var destination = new Bitmap(1, 1);
        Assert.Throws<ObjectDisposedException>(() =>
            widget.Paint(destination, null!, null!));
    }
}
