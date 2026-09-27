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

    private PlayerHudVitals? _liveVitals;
    private readonly PlayerHudResourceMotion _resourceMotion = new();
    internal PlayerHudDenialMotion Denial { get; } = new();
    internal PlayerHudDecorationBudget DecorationBudget { get; } = new();
    internal PlayerHudVitals? LiveVitals
    {
        get => _liveVitals;
        set
        {
            _liveVitals = value;
            if (value is { Hp: <= 0 }) _resourceMotion.Reset();
            else _resourceMotion.Observe(value);
        }
    }
    private int _liveMilliseconds;
    internal int LiveFrame => _liveMilliseconds * 3 / 100;
    // The legacy decorations flag describes Flash's tier, not the cost of this native surface.
    internal bool WantsLiveDecoration => LiveVitals is { Hp: > 0 } && VisualState.HasRenderableState;
    internal void ResetLiveClock()
    {
        _liveMilliseconds = 0; _resourceMotion.Reset(); Denial.Observe(null); DecorationBudget.Reset();
    }
    internal void ClearResourceFeedback()
    {
        Denial.Clear();
        _resourceMotion.Reset();
        if (LiveVitals is { Hp: > 0 }) _resourceMotion.Observe(LiveVitals);
    }
    internal bool AdvanceLiveDecoration(int elapsedMs)
    {
        if (!WantsLiveDecoration || elapsedMs <= 0) return false;
        var stride = _resourceMotion.Active || Denial.Active ? 1 : DecorationBudget.FrameStride;
        var before = LiveFrame / stride;
        // LCM of the authored 100/11/216-frame loops at 30 fps.
        _liveMilliseconds = (int)((_liveMilliseconds + (long)elapsedMs) % 1980000);
        _resourceMotion.Advance(elapsedMs);
        Denial.Advance(elapsedMs);
        return before != LiveFrame / stride;
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
        var result = compositor.Paint(destination, batch, plan, VisualState, LiveVitals, LiveFrame, _resourceMotion);
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
        if (Denial.MpAlpha > 0)
        {
            using var g = Graphics.FromImage(destination);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TranslateTransform(plan.FlashViewportPhysical.Left - plan.TightPhysicalBounds.Left,
                plan.FlashViewportPhysical.Top - plan.TightPhysicalBounds.Top);
            g.ScaleTransform((float)plan.PhysicalScale, (float)plan.PhysicalScale);
            PlayerHudResourceHintPainter.PaintMp(g, Denial.MpAlpha);
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
