#nullable enable
using System;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Separate bottom/Buff bounds; neither is unioned with the distant existing HUD.</summary>
internal sealed class PlayerHudRuntime : IPanelHudCompanion, IDisposable
{
    private readonly PlayerInfoSplitSurface _resources;
    private readonly NativeHudOverlay _bottom;
    private readonly NativeHudOverlay _buffs;
    private readonly Timer _queryTimer;
    private readonly PlayerHudController _controller;
    private readonly PlayerHudResourceTooltip _resourceTooltip;
    private bool _disposed;
    private bool _suspended, _restoringOrder;
    private readonly NativeHudOverlay _existingHud;

    internal PlayerHudRuntime(Form owner, Control anchor, PlayerInfoSplitSurface resources,
        PlayerHudController controller, string iconsRoot, NativeHudOverlay existingHud)
    {
        _resources = resources; _controller = controller; _existingHud = existingHud;
        _bottom = new NativeHudOverlay(owner, anchor);
        _buffs = new NativeHudOverlay(owner, anchor);
        if (controller.Profiler is { } profiler)
        {
            _bottom.RenderTimingObserver = (paint, commit, width, height) => profiler.Render("bottom", paint, commit, width, height);
            _buffs.RenderTimingObserver = (paint, commit, width, height) => profiler.Render("buff", paint, commit, width, height);
            _resources.RenderTimingObserver = (paint, commit, width, height) => profiler.Render("resources", paint, commit, width, height);
        }
        try
        {
            _resourceTooltip=new PlayerHudResourceTooltip(anchor,controller);
            _bottom.AddWidget(new PlayerHudBottomWidget(anchor, controller, iconsRoot));
            _bottom.AddWidget(_resourceTooltip.Widget);
            _buffs.AddWidget(new PlayerHudBuffWidget(anchor, controller));
            _buffs.SetZOrderInsertAfter(existingHud.Handle);
            _resources.SetZOrderInsertAfter(existingHud.Handle);
            // The authored chassis extends behind the resource gauges.
            _bottom.SetZOrderInsertAfter(existingHud.Handle);
            _existingHud.PresentationChanged += RestoreStack;
            _bottom.PresentationChanged += RestoreStack;
            _buffs.PresentationChanged += RestoreStack;
            _resources.PresentationChanged += RestoreStack;
            _queryTimer = new Timer { Interval = 250 };
            _queryTimer.Tick += OnTick; _queryTimer.Start();
        }
        catch
        {
            _existingHud.PresentationChanged -= RestoreStack;
            _bottom.PresentationChanged -= RestoreStack; _buffs.PresentationChanged -= RestoreStack; _resources.PresentationChanged -= RestoreStack;
            if(_resourceTooltip!=null){_bottom.RemoveWidget(_resourceTooltip.Widget);_resourceTooltip.Dispose();}
            _bottom.Dispose(); _buffs.Dispose(); throw;
        }
    }
    private void OnTick(object? sender, EventArgs args) => _controller.Tick(Environment.TickCount64);
    private void RestoreStack()
    {
        if (_disposed || _suspended || _restoringOrder) return;
        _restoringOrder = true;
        try
        {
            RestoreStack(_existingHud.Handle, _buffs.Handle, _resources.Handle, _bottom.Handle,
                (window, previous) => window == _buffs.Handle ? _buffs.RestoreRelativeOrder(previous)
                    : window == _resources.Handle ? _resources.RestoreRelativeOrder(previous)
                    : _bottom.RestoreRelativeOrder(previous));
        }
        finally { _restoringOrder = false; }
    }
    internal static void RestoreStack(IntPtr existing, IntPtr buffs, IntPtr resources, IntPtr bottom,
        Func<IntPtr, IntPtr, bool> restore)
    {
        // A hidden/skipped predecessor has arbitrary old Z position. Only a
        // successfully restored visible surface may anchor the next one.
        var previous=existing;
        if(restore(buffs,previous)) previous=buffs;
        if(restore(resources,previous)) previous=resources;
        restore(bottom,previous);
    }
    internal void SetReady() { _resources.SetReady(); _bottom.SetReady(); _buffs.SetReady(); }
    internal void PreCommitTransparent() { _bottom.PreCommitTransparent(); _buffs.PreCommitTransparent(); }
    public void Suspend()
    {
        _suspended = true;
        _controller.HideTooltip(); _resources.Suspend(); _bottom.Suspend(); _buffs.Suspend();
    }
    public void Resume()
    {
        if (_disposed) return;
        _suspended = false;
        _resources.Resume(); _bottom.Resume(); _buffs.Resume();
        RestoreStack();
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        _existingHud.PresentationChanged -= RestoreStack;
        _bottom.PresentationChanged -= RestoreStack; _buffs.PresentationChanged -= RestoreStack; _resources.PresentationChanged -= RestoreStack;
        _queryTimer.Stop(); _queryTimer.Tick -= OnTick; _queryTimer.Dispose();
        _resources.RenderTimingObserver = null; _bottom.RenderTimingObserver = null; _buffs.RenderTimingObserver = null;
        _bottom.RemoveWidget(_resourceTooltip.Widget);_resourceTooltip.Dispose();_bottom.Dispose(); _buffs.Dispose(); _controller.Dispose();
        // Program owns and drains the resource raster pipeline through its existing shutdown path.
    }
}
