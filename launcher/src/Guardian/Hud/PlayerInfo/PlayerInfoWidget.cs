#nullable enable

using System;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>
/// Fixture-only PlayerInfo rendering unit. It intentionally implements neither
/// INativeHudWidget nor IUiDataConsumer, so it cannot enter the existing
/// NativeHud union or the production UiData fan-out by type.
/// </summary>
internal sealed class PlayerInfoWidget : IDisposable
{
    private readonly IPlayerInfoVisualStateSource _visualStateSource;
    private PlayerInfoFrameCompositor? _compositor;

    internal PlayerInfoWidget(
        PlayerInfoSvgAssetSet assetSet,
        IPlayerInfoVisualStateSource visualStateSource)
    {
        _visualStateSource = visualStateSource ??
            throw new ArgumentNullException(nameof(visualStateSource));
        _compositor = new PlayerInfoFrameCompositor(
            assetSet ?? throw new ArgumentNullException(nameof(assetSet)));
    }

    internal PlayerInfoVisualState VisualState =>
        _visualStateSource.VisualState;

    internal PlayerInfoFramePaintResult Paint(
        Bitmap destination,
        PlayerInfoRasterBatch batch,
        PlayerInfoRasterPlan plan)
    {
        var compositor = _compositor ??
            throw new ObjectDisposedException(nameof(PlayerInfoWidget));
        return compositor.Paint(destination, batch, plan, VisualState);
    }

    internal bool TryHitTest(Point _) => false;

    public void Dispose()
    {
        System.Threading.Interlocked.Exchange(ref _compositor, null)?.Dispose();
    }
}
