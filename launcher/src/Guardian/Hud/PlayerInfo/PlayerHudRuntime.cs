#nullable enable
using System;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Loot;
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
    private readonly PlayerHudResourceTooltip _buffTooltip;
    private readonly IWorldHudInput _combinedInput;
    private bool _disposed;
    private bool _suspended, _restoringOrder;
    private readonly NativeHudOverlay _existingHud;
    private readonly PlayerHudBottomWidget _bottomWidget;
    private readonly PlayerHudFocusTargetWidget _focusTargetWidget;
    private readonly PlayerHudPointerInput _sharedInput;
    private readonly IWorldHudInput? _mainInput;
    private readonly bool _shareMainHud;
    private WorldCompositorController? _world;
    private bool _sharedActive,_changingBackend,_backendChanged;

    internal OverlayBase[] PresentationSurfaces => new OverlayBase[] { _buffs, _resources, _bottom };
    private Action<double,double,int,int>? _mainTimingObserver;

    internal PlayerHudRuntime(Form owner, Control anchor, PlayerInfoSplitSurface resources,
        PlayerHudController controller, string iconsRoot, NativeHudOverlay existingHud,bool shareMainHud=false,
        LootIconCatalog? portraitCatalog=null)
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
            if(shareMainHud)existingHud.RenderTimingObserver=_mainTimingObserver=
                (paint,commit,width,height)=>profiler.Render("main",paint,commit,width,height);
        }
        try
        {
            _resourceTooltip=new PlayerHudResourceTooltip(anchor,controller);
            _buffTooltip=new PlayerHudResourceTooltip(anchor,controller,true);
            _bottomWidget=new PlayerHudBottomWidget(anchor, controller, iconsRoot);
            _sharedInput=new PlayerHudPointerInput(_bottomWidget,()=>_sharedActive && _bottom.SharedInputAvailable);
            _mainInput=shareMainHud?existingHud.CreateWorldInput(anchor):null;
            _bottom.AddWidget(_bottomWidget);
            _bottom.AddWidget(_resourceTooltip.Widget);
            _buffs.AddWidget(new PlayerHudBuffWidget(anchor, controller));
            _focusTargetWidget = new PlayerHudFocusTargetWidget(anchor, controller, portraitCatalog);
            _buffs.AddWidget(_focusTargetWidget);
            _buffs.AddWidget(_buffTooltip.Widget);
            _combinedInput=new WorldHudInputLayers(_sharedInput,_buffs.CreateWorldInput(anchor));
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
            if (shareMainHud) existingHud.PartialRepaintEnabled = true;
        }
        catch
        {
            _existingHud.PresentationChanged -= RestoreStack;
            _bottom.PresentationChanged -= RestoreStack; _buffs.PresentationChanged -= RestoreStack; _resources.PresentationChanged -= RestoreStack;
            if(_resourceTooltip!=null){_bottom.RemoveWidget(_resourceTooltip.Widget);_resourceTooltip.Dispose();}
            if(_buffTooltip!=null){_buffs.RemoveWidget(_buffTooltip.Widget);_buffTooltip.Dispose();}
            _bottom.Dispose(); _buffs.Dispose(); throw;
        }
    }
    private void OnTick(object? sender, EventArgs args) => _controller.Tick(Environment.TickCount64);
    internal void SetPortraitBakeSink(IDollBakeSink? dollBake) => _focusTargetWidget.SetPortraitBakeSink(dollBake);
    internal void NotifyPortraitReady(string key) => _focusTargetWidget.NotifyPortraitReady(key);
    /// <summary>把插话输入浮窗的前台探针分发给本组三个 surface（主 HUD 由宿主单独接线）。</summary>
    internal void SetInterjectInputForegroundProbe(Func<bool> probe)
    {
        _bottom.InterjectInputForegroundProbe = probe;
        _buffs.InterjectInputForegroundProbe = probe;
        _resources.InterjectInputForegroundProbe = probe;
    }
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
                if(shared && (_bottom.HasLegacyPointerGesture || _buffs.HasLegacyPointerGesture || (_shareMainHud && _existingHud.HasLegacyPointerGesture)))_world!.RetireLegacyHudGesture();
                _sharedActive=shared;
                _combinedInput.Cancel();
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
                    _world!.SetHudInput(_combinedInput);
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
        if (_shareMainHud) _existingHud.PartialRepaintEnabled = false;
        _existingHud.PresentationChanged -= RestoreStack;
        _bottom.PresentationChanged -= RestoreStack; _buffs.PresentationChanged -= RestoreStack; _resources.PresentationChanged -= RestoreStack;
        _queryTimer.Stop(); _queryTimer.Tick -= OnTick; _queryTimer.Dispose();
        _resources.RenderTimingObserver = null; _bottom.RenderTimingObserver = null; _buffs.RenderTimingObserver = null;
        if(_mainTimingObserver!=null && ReferenceEquals(_existingHud.RenderTimingObserver,_mainTimingObserver))
            _existingHud.RenderTimingObserver=null;
        _mainTimingObserver=null;
        _buffs.RemoveWidget(_buffTooltip.Widget);_buffTooltip.Dispose();
        _bottom.RemoveWidget(_resourceTooltip.Widget);_resourceTooltip.Dispose();_bottom.Dispose(); _buffs.Dispose(); _controller.Dispose();
        // Program owns and drains the resource raster pipeline through its existing shutdown path.
    }
}
