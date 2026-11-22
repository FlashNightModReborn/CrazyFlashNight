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
    private Bitmap? _retainedDestination;
    private PlayerInfoRasterBatch? _retainedBatch;
    private PlayerInfoRasterPlan? _retainedPlan;
    private PlayerInfoVisualState? _retainedState;
    private PlayerHudVitals? _retainedVitals;
    private int _retainedFrame;
    private Bitmap? _hpScratch;

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
    internal PlayerHudResourceMotion ResourceMotion => _resourceMotion;
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
    internal bool WantsLiveDecoration => LiveVitals is { Hp: > 0 } && VisualState.HasRenderableState
        && (_resourceMotion.Active || Denial.Active || !PlayerHudMotionSettings.ReducedMotion &&
            (_resourceMotion.CriticalHp || LiveVitals.Hp < LiveVitals.HpMax || LiveVitals.Mp > LiveVitals.MpMax || LiveVitals.ShieldDetail?.Recovery.State == "charging"));
    internal void ResetLiveClock()
    {
        _retainedDestination = null;
        _liveMilliseconds = 0; _resourceMotion.Reset(); if (LiveVitals is { Hp: > 0 }) _resourceMotion.Observe(LiveVitals); Denial.Observe(null); DecorationBudget.Reset();
    }
    internal void ClearResourceFeedback()
    {
        _retainedDestination = null;
        Denial.Clear();
        _resourceMotion.Reset();
        if (LiveVitals is { Hp: > 0 }) _resourceMotion.Observe(LiveVitals);
    }
    internal bool AdvanceLiveDecoration(int elapsedMs)
    {
        if (!WantsLiveDecoration || elapsedMs <= 0) return false;
        if (PlayerHudMotionSettings.ReducedMotion)
        {
            var wasActive = _resourceMotion.Active || Denial.Active;
            _resourceMotion.Advance(elapsedMs);
            Denial.Advance(elapsedMs);
            return wasActive;
        }
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

    internal PlayerInfoPaintTrace? PaintTrace
    {
        get => _compositor?.Trace;
        set { if (_compositor != null) _compositor.Trace = value; }
    }

    internal PlayerInfoFramePaintResult Paint(
        Bitmap destination,
        PlayerInfoRasterBatch batch,
        PlayerInfoRasterPlan plan)
    {
        _retainedDestination = null;
        return PaintFrame(destination, batch, plan, null);
    }

    internal Rectangle? PaintRetained(Bitmap destination, PlayerInfoRasterBatch batch, PlayerInfoRasterPlan plan)
    {
        var trace = PaintTrace;
        trace?.Begin();
        var live = LiveVitals;
        var state = VisualState;
        bool steady = live is { Hp: > 0 } && live.Hp < live.HpMax && live.Mp <= live.MpMax
            && !state.WantsAnimationTick && !_resourceMotion.Active && !_resourceMotion.CriticalHp
            && !PlayerHudMotionSettings.ReducedMotion && !Denial.Active && live.ShieldDetail?.Recovery.State != "charging";
        Rectangle? damage = null;
        if (steady && ReferenceEquals(destination, _retainedDestination) && ReferenceEquals(batch, _retainedBatch)
            && ReferenceEquals(plan, _retainedPlan) && ReferenceEquals(state, _retainedState) && live == _retainedVitals)
            damage = _compositor?.HpMotionDamage(plan, _retainedFrame, LiveFrame, state.Hp.CurrentVirtualFrame);
        _retainedDestination = null;
        if (trace != null)
        {
            trace.Regional = damage.HasValue;
            trace.PublishedPixels = (damage?.Width ?? destination.Width) * (damage?.Height ?? destination.Height);
            trace.EndPass(ResourcePass.DamagePlan);
        }
        if (damage is { } changed)
        {
            if (_hpScratch == null || _hpScratch.Size != destination.Size)
            {
                _hpScratch?.Dispose();
                _hpScratch = new Bitmap(destination.Width, destination.Height, destination.PixelFormat);
            }
            // Filters and antialiased GDI/SK primitives must see their surrounding pixels.
            // Compose beyond the published change, then copy only the inner rectangle.
            int guard = (int)Math.Ceiling(12 * plan.PhysicalScale) + 2;
            var paint = Rectangle.Intersect(Rectangle.Inflate(changed, guard, guard), new Rectangle(Point.Empty,destination.Size));
            PaintFrame(_hpScratch, batch, plan, paint, changed);
            trace?.EndPass(ResourcePass.ShieldAndHints);
            CopyRegion(_hpScratch, destination, changed);
            trace?.EndPass(ResourcePass.CopyRetainedRegion);
        }
        else
        {
            PaintFrame(destination, batch, plan, null);
            trace?.EndPass(ResourcePass.ShieldAndHints);
        }
        if (steady)
        {
            _retainedDestination = destination;
            _retainedBatch = batch;
            _retainedPlan = plan;
            _retainedState = state;
            _retainedVitals = live;
            _retainedFrame = LiveFrame;
        }
        return damage;
    }

    private static unsafe void CopyRegion(Bitmap source, Bitmap destination, Rectangle region)
    {
        var read = source.LockBits(region, System.Drawing.Imaging.ImageLockMode.ReadOnly, source.PixelFormat);
        try
        {
            var write = destination.LockBits(region, System.Drawing.Imaging.ImageLockMode.WriteOnly, destination.PixelFormat);
            try
            {
                int bytes = region.Width * 4;
                for (int y = 0; y < region.Height; y++)
                    Buffer.MemoryCopy((byte*)read.Scan0 + y * read.Stride, (byte*)write.Scan0 + y * write.Stride, bytes, bytes);
            }
            finally { destination.UnlockBits(write); }
        }
        finally { source.UnlockBits(read); }
    }

    private PlayerInfoFramePaintResult PaintFrame(Bitmap destination, PlayerInfoRasterBatch batch,
        PlayerInfoRasterPlan plan, Rectangle? damage, Rectangle? published = null)
    {
        var compositor = _compositor ??
            throw new ObjectDisposedException(nameof(PlayerInfoWidget));
        var result = compositor.PaintRegion(destination, batch, plan, VisualState, LiveVitals, LiveFrame, _resourceMotion, damage, published);
        // Shield readouts start at the authored plaque. Include the outer antialiasing
        // margin before skipping a whole GDI pass on HP-only damage to its left.
        double plaqueLeft = plan.FlashViewportPhysical.Left - plan.TightPhysicalBounds.Left
            + PlayerHudResourceLayout.ShieldPlaque.Left * plan.PhysicalScale;
        if ((!published.HasValue || published.Value.Right >= Math.Floor(plaqueLeft) - 2)
            && LiveVitals is { } live && (!live.ShieldReady || live.ShieldPresent || _resourceMotion.Shield.Presence > 0f))
        {
            _shieldReadout ??= new PlayerHudShieldReadout();
            _shieldReadout.Paint(destination,plan,damage,live,_resourceMotion);
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
        _hpScratch?.Dispose();
        _hpScratch = null;
        System.Threading.Interlocked.Exchange(ref _compositor, null)?.Dispose();
        System.Threading.Interlocked.Exchange(ref _shieldReadout, null)?.Dispose();
    }
}
