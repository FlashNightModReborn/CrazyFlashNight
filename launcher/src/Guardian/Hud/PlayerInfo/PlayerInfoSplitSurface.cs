#nullable enable

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed record PlayerInfoSplitSurfaceSnapshot(
    bool Ready,
    bool Suspended,
    bool Shutdown,
    bool Shown,
    string FixtureCaseId,
    string? DesiredBatchKey,
    Rectangle TightPhysicalBounds,
    long RepaintRequestCount,
    long PaintCount,
    long CommitCount,
    long CommitSuccessCount,
    long CommitFailureCount,
    IReadOnlyList<double> SurfaceMilliseconds,
    IReadOnlyList<double> PaintMilliseconds,
    IReadOnlyList<double> CommitMilliseconds,
    PlayerInfoRasterPipelineSnapshot Pipeline);

internal readonly record struct PlayerInfoSplitSurfaceCounterSnapshot(
    bool Ready,
    bool Suspended,
    bool Shutdown,
    bool Shown,
    string FixtureCaseId,
    string? DesiredBatchKey,
    Rectangle TightPhysicalBounds,
    long RepaintRequestCount,
    long PaintCount,
    long CommitCount,
    long CommitSuccessCount,
    long CommitFailureCount,
    PlayerInfoRasterPipelineSnapshot Pipeline);

/// <summary>
/// Dedicated tight PlayerInfo layered window. It is fixture-only in B0 and is
/// intentionally not part of NativeHudOverlay's widget union.
/// </summary>
internal sealed class PlayerInfoSplitSurface :
    OverlayBase,
    IPanelHudCompanion
{
    internal const string FixtureCaseEnvironment =
        "CF7_PLAYER_INFO_FIXTURE_CASE";
    private const int AnimationPollMilliseconds = 16;

    private PlayerInfoSvgAssetSet? _assetSet;
    private PlayerInfoAnimationModel? _animation;
    private PlayerInfoWidget? _widget;
    private PlayerInfoRasterPipeline? _pipeline;
    private System.Windows.Forms.Timer? _animationTimer;
    private readonly object _metricsGate = new();
    private readonly List<double> _surfaceMilliseconds = [];
    private readonly List<double> _paintMilliseconds = [];
    private readonly List<double> _commitMilliseconds = [];

    private PlayerInfoLayeredDibSurface? _composedSurface;
    private string? _desiredBatchKey;
    private Rectangle _tightPhysicalBounds;
    private Point _committedOrigin;
    private Size _committedSize;
    private IntPtr _committedZOrderInsertAfter;
    private IntPtr _zOrderInsertAfter;
    private bool _zOrderDirty = true;
    private Task _drainTask = Task.CompletedTask;
    private long _lastAnimationTimestamp;
    private int _renderPostPending;
    private bool _ready;
    private bool _suspended;
    private bool _resumePending;
    private bool _shutdown;
    private bool _disposed;
    private bool _qualificationClockOwned;
    private long _repaintRequestCount;
    private long _paintCount;
    private long _commitCount;
    private long _commitSuccessCount;
    private long _commitFailureCount;

    private PlayerInfoSplitSurface(
        Form owner,
        Control anchor)
        : base(owner, anchor, 1024f, 576f)
    {
    }

    internal static PlayerInfoSplitSurface CreateFixture(
        Form owner,
        Control anchor,
        string fixtureCase,
        ILayeredWindowCommitObserver? observer = null) =>
        CreateFixtureCore(
            owner,
            anchor,
            fixtureCase,
            observer,
            () => PlayerInfoSvgAssetContract.LoadProductionEmbedded(
                minimumRaster: false));

    internal static PlayerInfoSplitSurface CreateFixtureForTest(
        Form owner,
        Control anchor,
        string fixtureCase,
        Func<PlayerInfoSvgAssetSet> assetLoader,
        ILayeredWindowCommitObserver? observer = null) =>
        CreateFixtureCore(
            owner,
            anchor,
            fixtureCase,
            observer,
            assetLoader);

    internal static bool TryResolveFixtureCase(
        string? rawValue,
        out string fixtureCase)
    {
        fixtureCase = string.Empty;
        if (string.IsNullOrWhiteSpace(rawValue) ||
            !string.Equals(rawValue, rawValue.Trim(), StringComparison.Ordinal) ||
            !PlayerInfoFixtureInput.IsAllowedCaseId(rawValue))
        {
            return false;
        }
        fixtureCase = rawValue;
        return true;
    }

    private static PlayerInfoSplitSurface CreateFixtureCore(
        Form owner,
        Control anchor,
        string fixtureCase,
        ILayeredWindowCommitObserver? observer,
        Func<PlayerInfoSvgAssetSet> assetLoader)
    {
        ArgumentNullException.ThrowIfNull(owner);
        ArgumentNullException.ThrowIfNull(anchor);
        ArgumentNullException.ThrowIfNull(assetLoader);
        if (!PlayerInfoFixtureInput.IsAllowedCaseId(fixtureCase))
        {
            throw new ArgumentException(
                $"Unknown PlayerInfo fixture case '{fixtureCase}'.",
                nameof(fixtureCase));
        }

        // OverlayBase creates and owner-roots its HWND in the base constructor.
        // Keep the derived constructor non-throwing, then initialize under a
        // factory-owned reference so every later failure can dispose the Form,
        // unsubscribe owner/anchor handlers, and release partial native state.
        var surface = new PlayerInfoSplitSurface(owner, anchor);
        try
        {
            surface.Initialize(fixtureCase, observer, assetLoader);
            return surface;
        }
        catch
        {
            surface.Dispose();
            throw;
        }
    }

    private void Initialize(
        string fixtureCase,
        ILayeredWindowCommitObserver? observer,
        Func<PlayerInfoSvgAssetSet> assetLoader)
    {
        _assetSet = assetLoader() ??
            throw new InvalidOperationException(
                "PlayerInfo asset loader returned no asset set.");
        _animation = new PlayerInfoAnimationModel();
        _widget = new PlayerInfoWidget(_assetSet, _animation);
        _pipeline = new PlayerInfoRasterPipeline(
            new PlayerInfoSvgRasterizer());
        _animationTimer = new System.Windows.Forms.Timer
        {
            Interval = AnimationPollMilliseconds
        };
        _animationTimer.Tick += OnAnimationTick;
        _pipeline.BatchPublished += OnBatchPublished;
        SetCommitObserver(observer);
        _animation.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId(fixtureCase));
        _lastAnimationTimestamp = Stopwatch.GetTimestamp();
    }

    private PlayerInfoSvgAssetSet AssetSet =>
        _assetSet ??
        throw new InvalidOperationException(
            "PlayerInfo split surface initialization is incomplete.");

    private PlayerInfoWidget Widget =>
        _widget ??
        throw new InvalidOperationException(
            "PlayerInfo split surface initialization is incomplete.");

    private PlayerInfoAnimationModel Animation =>
        _animation ??
        throw new InvalidOperationException(
            "PlayerInfo split surface initialization is incomplete.");

    private PlayerInfoRasterPipeline Pipeline =>
        _pipeline ??
        throw new InvalidOperationException(
            "PlayerInfo split surface initialization is incomplete.");

    private System.Windows.Forms.Timer AnimationTimer =>
        _animationTimer ??
        throw new InvalidOperationException(
            "PlayerInfo split surface initialization is incomplete.");

    internal void SetReady()
    {
        ThrowIfDisposed();
        if (_shutdown)
        {
            return;
        }
        _ready = true;
        OnPositionChanged();
    }

    internal void SetZOrderInsertAfter(IntPtr handle)
    {
        ThrowIfDisposed();
        _zOrderInsertAfter = handle;
        _zOrderDirty = true;
        if (_shown && !_suspended && !_shutdown)
        {
            ScheduleRender();
        }
    }

    internal bool SetFixtureCase(string fixtureCase)
    {
        ThrowIfDisposed();
        if (_shutdown ||
            !PlayerInfoFixtureInput.IsAllowedCaseId(fixtureCase))
        {
            return false;
        }
        var changed = Animation.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId(fixtureCase));
        if (changed)
        {
            ScheduleRender();
        }
        UpdateAnimationTimer();
        return changed;
    }

    /// <summary>
    /// Deterministic B0 qualification clock. Production never calls this seam:
    /// taking ownership stops the wall-clock timer so one requested logical
    /// step can be attributed to at most one posted surface transaction.
    /// </summary>
    internal bool AdvanceFixtureForQualification(int elapsedMilliseconds)
    {
        ThrowIfDisposed();
        if (elapsedMilliseconds < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(elapsedMilliseconds));
        }
        if (_shutdown || !_ready || !_ownerVisible || _suspended)
        {
            return false;
        }
        _qualificationClockOwned = true;
        AnimationTimer.Stop();
        var changed = Animation.Tick(elapsedMilliseconds);
        if (changed)
        {
            ScheduleRender();
        }
        return changed;
    }

    public void Suspend()
    {
        if (_disposed || _shutdown || _suspended)
        {
            return;
        }
        _suspended = true;
        _resumePending = false;
        try
        {
            _animationTimer?.Stop();
        }
        catch (Exception ex)
        {
            LogBestEffort(
                "[PlayerInfoSplitSurface] suspend timer stop failed: " +
                ex.Message);
        }
        try
        {
            DismissOverlay();
        }
        catch (Exception ex)
        {
            LogBestEffort(
                "[PlayerInfoSplitSurface] suspend hide failed: " +
                ex.Message);
        }
    }

    public void Resume()
    {
        if (_disposed || _shutdown || !_suspended)
        {
            return;
        }
        _suspended = false;
        _resumePending = true;
        if (_ready)
        {
            try
            {
                OnPositionChanged();
            }
            catch (Exception ex)
            {
                LogBestEffort(
                    "[PlayerInfoSplitSurface] resume position sync failed: " +
                    ex.Message);
            }
        }
    }

    internal Task BeginShutdown()
    {
        if (_shutdown)
        {
            return _drainTask;
        }
        _shutdown = true;
        _ready = false;
        _resumePending = false;
        _animationTimer?.Stop();
        if (_pipeline is not null)
        {
            _pipeline.BatchPublished -= OnBatchPublished;
        }
        DismissOverlay();
        if (_pipeline is not null)
        {
            _pipeline.Dispose();
            _drainTask = _pipeline.WaitForIdleAsync();
        }
        return _drainTask;
    }

    internal Task WaitForDrainAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        if (timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }
        return _drainTask.WaitAsync(timeout, cancellationToken);
    }

    internal PlayerInfoSplitSurfaceSnapshot Snapshot
    {
        get
        {
            lock (_metricsGate)
            {
                return new PlayerInfoSplitSurfaceSnapshot(
                    _ready,
                    _suspended,
                    _shutdown,
                    _shown,
                    Animation.LastFixtureCaseId ?? string.Empty,
                    _desiredBatchKey,
                    _tightPhysicalBounds,
                    _repaintRequestCount,
                    _paintCount,
                    _commitCount,
                    _commitSuccessCount,
                    _commitFailureCount,
                    _surfaceMilliseconds.ToArray(),
                    _paintMilliseconds.ToArray(),
                    _commitMilliseconds.ToArray(),
                    Pipeline.Snapshot);
            }
        }
    }

    internal PlayerInfoSplitSurfaceCounterSnapshot Counters
    {
        get
        {
            lock (_metricsGate)
            {
                return new PlayerInfoSplitSurfaceCounterSnapshot(
                    _ready,
                    _suspended,
                    _shutdown,
                    _shown,
                    Animation.LastFixtureCaseId ?? string.Empty,
                    _desiredBatchKey,
                    _tightPhysicalBounds,
                    _repaintRequestCount,
                    _paintCount,
                    _commitCount,
                    _commitSuccessCount,
                    _commitFailureCount,
                    Pipeline.Snapshot);
            }
        }
    }

    internal bool ResumePending => _resumePending;

    protected override void OnPositionChanged()
    {
        if (!_ready ||
            !_ownerVisible ||
            _suspended ||
            _shutdown ||
            _disposed)
        {
            return;
        }
        var viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
        if (viewport.Width <= 0 || viewport.Height <= 0)
        {
            DismissOverlay();
            return;
        }

        var dpiScale = DeviceDpi > 0 ? DeviceDpi / 96f : 1f;
        PlayerInfoRasterPlan plan;
        try
        {
            plan = PlayerInfoRasterPlanner.Create(
                AssetSet,
                viewport,
                dpiScale);
        }
        catch (Exception ex)
        {
            LogBestEffort(
                "[PlayerInfoSplitSurface] placement rejected: " + ex.Message);
            DismissOverlay();
            return;
        }

        _desiredBatchKey = plan.BatchKey;
        if (_tightPhysicalBounds != plan.TightPhysicalBounds)
        {
            _tightPhysicalBounds = plan.TightPhysicalBounds;
            DismissOverlay();
        }
        try
        {
            var result = Pipeline.Request(plan);
            _resumePending = false;
            if (result is
                PlayerInfoRasterRequestResult.CurrentHit or
                PlayerInfoRasterRequestResult.CacheHit)
            {
                ScheduleRender();
            }
        }
        catch (ObjectDisposedException)
        {
            DismissOverlay();
        }
        catch (Exception ex)
        {
            LogBestEffort(
                "[PlayerInfoSplitSurface] raster request rejected: " +
                ex.Message);
            DismissOverlay();
        }
    }

    protected override void OnOwnerVisibilityChanged(bool ownerVisible)
    {
        if (!ownerVisible)
        {
            try
            {
                _animationTimer?.Stop();
            }
            catch (Exception ex)
            {
                LogBestEffort(
                    "[PlayerInfoSplitSurface] hidden timer stop failed: " +
                    ex.Message);
            }
            try
            {
                // OverlayBase would otherwise restore the last committed
                // bitmap immediately after activation. This asynchronous
                // surface invalidates that image while hidden and shows only
                // after the current state has been rendered and committed.
                DismissOverlay();
            }
            catch (Exception ex)
            {
                LogBestEffort(
                    "[PlayerInfoSplitSurface] hidden dismiss failed: " +
                    ex.Message);
            }
            return;
        }
        if (_ready && !_suspended && !_shutdown && !_disposed)
        {
            OnPositionChanged();
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && !_disposed)
        {
            _disposed = true;
            try
            {
                BeginShutdown();
            }
            catch
            {
            }
            if (_animationTimer is not null)
            {
                _animationTimer.Tick -= OnAnimationTick;
                _animationTimer.Dispose();
                _animationTimer = null;
            }
            Interlocked.Exchange(ref _composedSurface, null)?.Dispose();
            _widget?.Dispose();
            _widget = null;
            _animation = null;
        }
        base.Dispose(disposing);
    }

    private void OnBatchPublished(
        object? sender,
        PlayerInfoRasterBatchPublishedEventArgs args)
    {
        if (_shutdown ||
            !string.Equals(
                args.BatchKey,
                Volatile.Read(ref _desiredBatchKey),
                StringComparison.Ordinal))
        {
            return;
        }
        ScheduleRender();
    }

    private void ScheduleRender()
    {
        if (_disposed ||
            _shutdown ||
            !_ready ||
            !_ownerVisible ||
            _suspended)
        {
            return;
        }
        if (Interlocked.Exchange(ref _renderPostPending, 1) != 0)
        {
            return;
        }
        Interlocked.Increment(ref _repaintRequestCount);
        try
        {
            BeginInvoke((MethodInvoker)RenderPostedOnUiThread);
        }
        catch
        {
            Interlocked.Exchange(ref _renderPostPending, 0);
        }
    }

    private void RenderPostedOnUiThread()
    {
        Interlocked.Exchange(ref _renderPostPending, 0);
        if (_disposed ||
            _shutdown ||
            !_ready ||
            !_ownerVisible ||
            _suspended)
        {
            return;
        }
        RenderCurrentOnUiThread();
        UpdateAnimationTimer();
    }

    private void RenderCurrentOnUiThread()
    {
        if (_disposed ||
            _shutdown ||
            !_ready ||
            !_ownerVisible ||
            _suspended)
        {
            return;
        }
        var surfaceStart = Stopwatch.GetTimestamp();
        Bitmap? composed = null;
        Rectangle tight = Rectangle.Empty;
        var painted = false;
        var desired = _desiredBatchKey;
        var paintStart = Stopwatch.GetTimestamp();
        try
        {
            if (!Pipeline.TryUseCurrent((batch, plan) =>
                {
                    if (!string.Equals(
                            batch.BatchKey,
                            desired,
                            StringComparison.Ordinal) ||
                        plan.TightPhysicalBounds != _tightPhysicalBounds ||
                        !Animation.VisualState.HasRenderableState)
                    {
                        return;
                    }
                    composed = EnsureComposed(
                        plan.TightPhysicalBounds.Width,
                        plan.TightPhysicalBounds.Height);
                    Widget.Paint(composed, batch, plan);
                    tight = plan.TightPhysicalBounds;
                    painted = true;
                }))
            {
                return;
            }
        }
        catch (Exception ex)
        {
            LogBestEffort(
                "[PlayerInfoSplitSurface] paint rejected: " + ex.Message);
            DismissOverlay();
            return;
        }
        if (!painted || composed is null || tight.Width <= 0 || tight.Height <= 0)
        {
            DismissOverlay();
            return;
        }

        var paintMs = ElapsedMilliseconds(paintStart);
        lock (_metricsGate)
        {
            _paintCount++;
            _paintMilliseconds.Add(paintMs);
        }

        var preparedSurface = _composedSurface;
        if (preparedSurface is null ||
            !ReferenceEquals(preparedSurface.Bitmap, composed))
        {
            throw new InvalidOperationException(
                "PlayerInfo prepared DIB changed during its UI-thread paint transaction.");
        }
        var commit = CommitPreparedDibObserved(
            preparedSurface.MemoryDc,
            preparedSurface.Width,
            preparedSurface.Height,
            tight.Left,
            tight.Top,
            255);
        lock (_metricsGate)
        {
            _commitCount++;
            _commitMilliseconds.Add(commit.ElapsedMilliseconds);
            if (commit.Succeeded)
            {
                _commitSuccessCount++;
            }
            else
            {
                _commitFailureCount++;
            }
        }
        if (!commit.Succeeded)
        {
            RecordSurfaceMilliseconds(surfaceStart);
            DismissOverlay();
            return;
        }

        var origin = tight.Location;
        var size = tight.Size;
        var insertAfter =
            _zOrderInsertAfter == IntPtr.Zero ? HWND_TOP : _zOrderInsertAfter;
        var firstShow = !_shown;
        if (firstShow ||
            origin != _committedOrigin ||
            size != _committedSize ||
            insertAfter != _committedZOrderInsertAfter ||
            _zOrderDirty)
        {
            var positioned = SetWindowPos(
                Handle,
                insertAfter,
                origin.X,
                origin.Y,
                size.Width,
                size.Height,
                SWP_NOACTIVATE |
                (firstShow ? SWP_SHOWWINDOW : 0));
            if (positioned)
            {
                _committedOrigin = origin;
                _committedSize = size;
                _committedZOrderInsertAfter = insertAfter;
                _zOrderDirty = false;
                _shown = true;
            }
            else
            {
                LogBestEffort(
                    "[PlayerInfoSplitSurface] SetWindowPos rejected " +
                    $"firstShow={firstShow} nativeError=" +
                    Marshal.GetLastWin32Error() + ".");
                if (firstShow)
                {
                    RecordSurfaceMilliseconds(surfaceStart);
                    DismissOverlay();
                    return;
                }
            }
        }
        RecordSurfaceMilliseconds(surfaceStart);
    }

    private Bitmap EnsureComposed(int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(width),
                "PlayerInfo tight surface must be non-empty.");
        }
        if (_composedSurface is not null &&
            _composedSurface.Width == width &&
            _composedSurface.Height == height)
        {
            return _composedSurface.Bitmap;
        }
        var replacement = new PlayerInfoLayeredDibSurface(width, height);
        Interlocked.Exchange(ref _composedSurface, replacement)?.Dispose();
        return replacement.Bitmap;
    }

    private void OnAnimationTick(object? sender, EventArgs args)
    {
        if (_disposed ||
            _shutdown ||
            _suspended ||
            !_ready ||
            !_ownerVisible)
        {
            _animationTimer?.Stop();
            return;
        }
        var now = Stopwatch.GetTimestamp();
        var elapsed = Math.Clamp(
            (long)Math.Round(
                (now - _lastAnimationTimestamp) *
                1000d /
                Stopwatch.Frequency,
                MidpointRounding.AwayFromZero),
            0,
            int.MaxValue);
        _lastAnimationTimestamp = now;
        if (Animation.Tick((int)elapsed))
        {
            ScheduleRender();
        }
        UpdateAnimationTimer();
    }

    private void UpdateAnimationTimer()
    {
        if (_disposed ||
            _shutdown ||
            _suspended ||
            !_ready ||
            !_ownerVisible ||
            _qualificationClockOwned ||
            !Animation.WantsAnimationTick)
        {
            _animationTimer?.Stop();
            return;
        }
        if (!AnimationTimer.Enabled)
        {
            _lastAnimationTimestamp = Stopwatch.GetTimestamp();
            AnimationTimer.Start();
        }
    }

    private static double ElapsedMilliseconds(long startTimestamp) =>
        (Stopwatch.GetTimestamp() - startTimestamp) *
        1000d /
        Stopwatch.Frequency;

    private void RecordSurfaceMilliseconds(long startTimestamp)
    {
        lock (_metricsGate)
        {
            _surfaceMilliseconds.Add(ElapsedMilliseconds(startTimestamp));
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private static void LogBestEffort(string message)
    {
        try
        {
            LogManager.Log(message);
        }
        catch
        {
            // Companion transitions are a no-throw state contract. A
            // diagnostic sink must not turn best-effort logging into a second
            // transition failure after the state bit has already changed.
        }
    }
}
