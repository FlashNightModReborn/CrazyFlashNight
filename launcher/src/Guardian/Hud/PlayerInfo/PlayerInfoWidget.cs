#nullable enable

using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>
/// Isolated PlayerInfo rendering unit, optionally driven by live vitals. It implements neither
/// INativeHudWidget nor IUiDataConsumer, so it cannot enter the existing
/// NativeHud union or the production UiData fan-out by type.
/// </summary>
internal sealed class PlayerInfoWidget : IDisposable
{
    private readonly IPlayerInfoVisualStateSource _visualStateSource;
    private PlayerInfoFrameCompositor? _compositor;
    private PlayerHudShieldReadout? _shieldReadout;

    internal PlayerInfoWidget(
        PlayerInfoSvgAssetSet assetSet,
        IPlayerInfoVisualStateSource visualStateSource)
    {
        _visualStateSource = visualStateSource ??
            throw new ArgumentNullException(nameof(visualStateSource));
        _compositor = new PlayerInfoFrameCompositor(
            assetSet ?? throw new ArgumentNullException(nameof(assetSet)));
    }

    internal PlayerHudVitals? LiveVitals { get; set; }
    private int _liveMilliseconds;
    internal int LiveFrame => _liveMilliseconds * 3 / 100;
    internal bool WantsLiveDecoration => LiveVitals is { Decorations:true, Hp: > 0 } && VisualState.HasRenderableState;
    internal void ResetLiveClock() => _liveMilliseconds = 0;
    internal bool AdvanceLiveDecoration(int elapsedMs)
    {
        if (!WantsLiveDecoration || elapsedMs <= 0) return false;
        var before = LiveFrame;
        // LCM of the authored 100/11/216-frame loops at 30 fps.
        _liveMilliseconds = (int)((_liveMilliseconds + (long)elapsedMs) % 1980000);
        return before != LiveFrame;
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
        var result = compositor.Paint(destination, batch, plan, VisualState, LiveVitals, LiveFrame);
        if (LiveVitals is { } live && (!live.ShieldReady || live.ShieldPresent))
        {
            _shieldReadout ??= new PlayerHudShieldReadout();
            using var graphics = Graphics.FromImage(destination);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TranslateTransform(plan.FlashViewportPhysical.Left-plan.TightPhysicalBounds.Left,
                plan.FlashViewportPhysical.Top-plan.TightPhysicalBounds.Top);
            graphics.ScaleTransform((float)plan.PhysicalScale,(float)plan.PhysicalScale);
            _shieldReadout.Paint(graphics,live,(float)plan.PhysicalScale);
        }
        return result;
    }

    internal bool TryHitTest(Point _) => false;

    public void Dispose()
    {
        System.Threading.Interlocked.Exchange(ref _compositor, null)?.Dispose();
        System.Threading.Interlocked.Exchange(ref _shieldReadout, null)?.Dispose();
    }
}
