#nullable enable
using System;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;

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
    private readonly PlayerHudBottomWidget _bottomWidget;
    private readonly PlayerHudPointerInput _sharedInput;
    private readonly IWorldHudInput? _mainInput;
    private readonly bool _shareMainHud;
    private WorldCompositorController? _world;
    private bool _sharedActive,_changingBackend,_backendChanged;

    internal OverlayBase[] PresentationSurfaces => new OverlayBase[] { _buffs, _resources, _bottom };

    internal PlayerHudRuntime(Form owner, Control anchor, PlayerInfoSplitSurface resources,
        PlayerHudController controller, string iconsRoot, NativeHudOverlay existingHud,bool shareMainHud=false)
    {
        _shareMainHud=shareMainHud;
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
            _bottomWidget=new PlayerHudBottomWidget(anchor, controller, iconsRoot);
            _sharedInput=new PlayerHudPointerInput(_bottomWidget,()=>_sharedActive && _bottom.SharedInputAvailable);
            _mainInput=shareMainHud?existingHud.CreateWorldInput(anchor):null;
            _bottom.AddWidget(_bottomWidget);
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
    internal void SetSharedWorld(WorldCompositorController? world)
    {
        if(ReferenceEquals(_world,world))return;
        if(_world!=null)
        {
            _world.ResourcePresentation.Changed-=ReconcileBackend;
            _world.BottomPresentation.Changed-=ReconcileBackend;
            _world.BuffPresentation.Changed-=ReconcileBackend;
            if(_shareMainHud)_world.MainHudPresentation.Changed-=ReconcileBackend;
            _world.SetHudInput(null);
            if(_shareMainHud)_world.SetMainHudInput(null);
        }
        _world=null;
        ReconcileBackend();
        _world=world;
        if(world!=null)
        {
            world.ResourcePresentation.Changed+=ReconcileBackend;
            world.BottomPresentation.Changed+=ReconcileBackend;
            world.BuffPresentation.Changed+=ReconcileBackend;
            if(_shareMainHud)world.MainHudPresentation.Changed+=ReconcileBackend;
        }
        ReconcileBackend();
    }
    private void ReconcileBackend()
    {
        if(_changingBackend) { _backendChanged=true;return; }
        _changingBackend=true;
        try
        {
            do
            {
                _backendChanged=false;
                bool shared=!_disposed && !_suspended && _world!=null && _world.ResourcePresentation.IsAvailable
                    && _world.BottomPresentation.IsAvailable && _world.BuffPresentation.IsAvailable
                    && (!_shareMainHud || _world.MainHudPresentation.IsAvailable);
                if(shared==_sharedActive)continue;
                // Only a gesture actually owned by the legacy HUD transfers this
                // release barrier. A held Flash gesture must retain its own release.
                if(shared && (_bottom.HasLegacyPointerGesture || (_shareMainHud && _existingHud.HasLegacyPointerGesture)))_world!.RetireLegacyHudGesture();
                _sharedActive=shared;
                _sharedInput.Cancel();
                _mainInput?.Cancel();
                _world?.SetHudInput(null);
                if(_shareMainHud)_world?.SetMainHudInput(null);
                // These three surfaces switch as a unit. An unavailable/failed
                // member cannot leave native resources under a legacy bottom HWND.
                _bottom.SetSharedPresentation(shared?_world!.BottomPresentation:null);
                _buffs.SetSharedPresentation(shared?_world!.BuffPresentation:null);
                _resources.SetSharedPresentation(shared?_world!.ResourcePresentation:null);
                // Main HUD must remain above PlayerInfo. If any member returns
                // to a legacy HWND, retire the complete unit before restoring it.
                if(_shareMainHud && !_existingHud.IsDisposed)_existingHud.SetSharedPresentation(shared?_world!.MainHudPresentation:null);
                if(shared)
                {
                    _world!.SetHudInput(_sharedInput);
                    if(_shareMainHud)_world.SetMainHudInput(_mainInput);
                }
                else RestoreStack();
                LogManager.Log("event=player_hud_backend shared="+shared+" layers=bottom,resources,buffs"+(_shareMainHud?",main":""));
            } while(_backendChanged);
        }
        finally { _changingBackend=false; }
    }
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
        ReconcileBackend();
        _controller.HideTooltip(); _resources.Suspend(); _bottom.Suspend(); _buffs.Suspend();
    }
    public void Resume()
    {
        if (_disposed) return;
        _suspended = false;
        ReconcileBackend();
        _resources.Resume(); _bottom.Resume(); _buffs.Resume();
        RestoreStack();
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        SetSharedWorld(null);
        _existingHud.PresentationChanged -= RestoreStack;
        _bottom.PresentationChanged -= RestoreStack; _buffs.PresentationChanged -= RestoreStack; _resources.PresentationChanged -= RestoreStack;
        _queryTimer.Stop(); _queryTimer.Tick -= OnTick; _queryTimer.Dispose();
        _resources.RenderTimingObserver = null; _bottom.RenderTimingObserver = null; _buffs.RenderTimingObserver = null;
        _bottom.RemoveWidget(_resourceTooltip.Widget);_resourceTooltip.Dispose();_bottom.Dispose(); _buffs.Dispose(); _controller.Dispose();
        // Program owns and drains the resource raster pipeline through its existing shutdown path.
    }
}
