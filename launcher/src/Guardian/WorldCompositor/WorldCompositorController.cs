using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed class WorldCompositorController : IDisposable
    {
        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly Func<IntPtr> _getFlash;
        private readonly Func<bool> _canPresent;
        private readonly Func<bool> _shouldPrepare;
        private readonly Action<string> _notify;
        private readonly Action<double> _setRenderScale;
        private readonly Action _focusFlash;
        private readonly WorldColorMatrix _preset;
        private readonly Timer _timer = new Timer { Interval=33 };
        private NativeCompositorSession _native;
        private WorldCompositionSurface _surface;
        private NativePointerBridge _pointerBridge;
        private IntPtr _flash;
        private Rectangle _crop;
        private WorldLightingFrame _frame;
        private WorldLightingTransition _lighting = new WorldLightingTransition();
        private long _reportedPendingScene;
        private bool _disposed, _starting, _faulted, _active;
        private bool _permissionChecked, _borderless;
        private double _waitingStateMs;
        private double _requiredFrameMs, _startedMs, _lastLogMs;
        private float[] _lastSettings;
        private double _targetScale=1, _appliedScale=1;
        private float _targetSharpness;
        private float _appliedSharpness=float.NaN;
        private bool _viewportHeld;
        private double _paintFenceMs;
        private volatile bool _schedulingAllowed;
        internal bool SchedulingAllowed => _schedulingAllowed;
        internal bool RouteCapturedPointer(int x,int y,int message,uint mouseData) =>
            !_disposed && _active && _surface!=null && _surface.RouteCapturedPointer(x,y,message,mouseData);
        internal void ApplyRenderSelection(RenderSelection selection,float sharpness)
        {
            if (_disposed) return;
            _targetScale=selection.Scale;
            _targetSharpness=selection.Quality=="LOW" && selection.Scale<1 ? sharpness : 0;
            if (_targetScale!=_appliedScale) _schedulingAllowed=false;
        }

        internal WorldCompositorController(Form owner, Control anchor, Func<IntPtr> getFlash,
            Func<bool> canPresent, Action<string> notify, string projectRoot, Func<bool> shouldPrepare,
            Action<double> setRenderScale,Action focusFlash)
        {
            _owner=owner; _anchor=anchor; _getFlash=getFlash; _canPresent=canPresent; _notify=notify; _shouldPrepare=shouldPrepare;
            _setRenderScale=setRenderScale; _focusFlash=focusFlash;
            _preset=WorldColorMatrix.Load(Path.Combine(projectRoot,"launcher","data","world-lighting","preset.json"));
            _timer.Tick+=OnTick;
            _owner.LocationChanged+=OnGeometryChanged; _owner.SizeChanged+=OnGeometryChanged;
            _owner.DpiChanged+=OnDpiChanged; _owner.FormClosed+=OnClosed;
            _anchor.SizeChanged+=OnGeometryChanged; _anchor.LocationChanged+=OnGeometryChanged;
            _timer.Start();
        }
        internal void Adopt(WorldLightingFrame frame)
        {
            bool wasPending=_lighting.Pending;
            bool wasWaiting=_lighting.WaitingForCapture;
            long previousScene=_frame?.Scene ?? 0;
            if (_disposed || !_lighting.Adopt(frame,NowMs())) return;
            if (!frame.Ready || frame.Scene!=previousScene) _surface?.CancelPointer();
            _frame=frame;
            if (_lighting.Pending && (!wasPending || frame.Scene!=previousScene))
                LogManager.Log("event=world_lighting_hold scene="+frame.Scene+" hasGrade="+_lighting.HasValidState);
            if (_lighting.WaitingForCapture && (!wasWaiting || frame.Scene!=previousScene))
                LogManager.Log("event=world_lighting_wait_frame scene="+frame.Scene+" seq="+frame.Sequence);
            if (frame.Ready && !_lighting.WaitingForCapture && (wasPending || frame.Scene!=previousScene || frame.Immediate))
                LogManager.Log("event=world_lighting_state seq="+frame.Sequence+" scene="+frame.Scene+" ready=true light="+frame.Light.ToString("F3",CultureInfo.InvariantCulture)+" mode="+frame.Mode+" sourceNeutral=true blendMs="+_lighting.BlendDurationMs.ToString("F0",CultureInfo.InvariantCulture));
        }
        internal void ResetSource()
        {
            _lighting=new WorldLightingTransition(); _reportedPendingScene=0; _frame=null; _schedulingAllowed=false; StopCapture();
            _targetScale=_appliedScale=1; _setRenderScale(1);
        }
        private async void OnTick(object sender,EventArgs args)
        {
            if (_disposed || _faulted || _starting) return;
            try {
                string module=Path.Combine(AppContext.BaseDirectory,NativeCompositorSession.ModuleName);
                if (!_permissionChecked) {
                    if (!_shouldPrepare()) return;
                    _starting=true;
                    if (!File.Exists(module)) throw new FileNotFoundException("缺少世界合成模块，请更新完整游戏运行组件",module);
                    int access=await Task.Run(()=>NativeCompositorSession.RequestBorderless(module));
                    if (_disposed) return;
                    _permissionChecked=true; _borderless=access==1;
                    LogManager.Log("event=world_compositor_borderless status="+access);
                    if (!_borderless) _notify?.Invoke("当前系统保留画面捕获边框");
                }
                if (_native==null) {
                    if (!_canPresent() || _getFlash()==IntPtr.Zero) return;
                    if (_frame?.Ready!=true) {
                        if (_waitingStateMs==0) _waitingStateMs=NowMs();
                        if (NowMs()-_waitingStateMs>30000) throw new TimeoutException("未收到有效的 AS2 场景光照状态");
                        return;
                    }
                    _waitingStateMs=0; _starting=true;
                    if (_disposed || !_canPresent()) return;
                    _flash=_getFlash(); _pointerBridge=await NativePointerBridge.Start(_flash,_owner.Handle);
                    if(_disposed || _flash!=_getFlash()) { _pointerBridge.Dispose(); return; }
                    _surface=new WorldCompositionSurface(_getFlash,_focusFlash,_pointerBridge) { Owner=_owner };
                    _surface.CreateControl();
                    _native=new NativeCompositorSession(module,_owner.Handle,(uint)Environment.ProcessId,_surface.Handle,0,_borderless);
                    _crop=Rectangle.Empty; _startedMs=NowMs(); _lastSettings=null; _active=true; _appliedSharpness=float.NaN;
                    LogManager.Log("event=world_compositor_start flash=0x"+_flash.ToString("X")+" fpsLimit=30");
                }
                if (_getFlash()!=_flash || !IsWindow(_flash)) { ResetSource(); return; }
                if(!_pointerBridge.IsAlive) throw new InvalidOperationException("Projector input bridge exited unexpectedly");
                // Scene readiness changes the grade, not ownership of the visible surface.
                // Keep capturing with the held grade until the next scene is ready.
                bool show=_lighting.ShouldPresent(CanShow());
                if (show && _lighting.IsOverdue(NowMs()) && _reportedPendingScene!=_frame.Scene) {
                    _reportedPendingScene=_frame.Scene;
                    LogManager.Log("event=world_lighting_hold_long scene="+_frame.Scene);
                }
                if (show!=_active) {
                    _active=show; _native.Active(show); _requiredFrameMs=NowMs();
                    if (!show) _surface.Hide();
                }
                if (!_active) {
                    _schedulingAllowed=false;
                    if (_frame==null && NowMs()-_startedMs>10000) throw new TimeoutException("未收到配套 AS2 光照状态，请检查 asLoader 构建");
                    return;
                }
                _surface.FlushMove();
                if (_targetScale!=_appliedScale && !_surface.IsDragging) {
                    _starting=true; _schedulingAllowed=false;
                    var resizingNative=_native; var resizingSource=_flash;
                    double resizeStarted=NowMs();
                    _native.HoldViewport(); _viewportHeld=true;
                    double heldAt=NowMs();
                    _setRenderScale(_targetScale); _appliedScale=_targetScale;
                    double resizedAt=NowMs();
                    double painted=await _pointerBridge.RepaintAsync(heldAt);
                    if (_disposed || _native!=resizingNative || _getFlash()!=resizingSource) return;
                    _paintFenceMs=painted;
                    _requiredFrameMs=Math.Max(_requiredFrameMs,painted);
                    LogManager.Log("event=world_render_resize scale="+_appliedScale.ToString("F2",CultureInfo.InvariantCulture)
                        +" paintFenceMs="+painted.ToString("F1",CultureInfo.InvariantCulture)
                        +" waitGpuMs="+(heldAt-resizeStarted).ToString("F1",CultureInfo.InvariantCulture)
                        +" resizeMs="+(resizedAt-heldAt).ToString("F1",CultureInfo.InvariantCulture)
                        +" repaintMs="+(NowMs()-resizedAt).ToString("F1",CultureInfo.InvariantCulture)
                        +" handoffMs="+(NowMs()-resizeStarted).ToString("F1",CultureInfo.InvariantCulture));
                    if (!CanShow()) { _native.Active(false); _active=false; _surface.Hide(); return; }
                }
                if (!Synchronize()) return;
                var stats=_native.Read();
                if (stats.State==2 || stats.State==3) throw new InvalidOperationException(stats.Message+" HRESULT=0x"+stats.Error.ToString("X8"));
                bool ready=stats.Received>0 && stats.Width==_crop.Width && stats.Height==_crop.Height && stats.LastFrameQpcMs>=_requiredFrameMs;
                // Observe healthy FPS during a gesture; only the actual resize waits
                // for release. Frequent clicks must not reset the recovery timer.
                _schedulingAllowed=ready && _frame?.Ready==true && _targetScale==_appliedScale;
                if (ready && _appliedSharpness!=_targetSharpness) { _native.Sharpness(_targetSharpness); _appliedSharpness=_targetSharpness; }
                // Read() reports a captured frame after its Present submission. This is a
                // timestamp freshness fence, not proof of the pixels' semantic scene identity.
                if (ready && _lighting.ConfirmCapturedFrame(stats.LastFrameQpcMs,NowMs()))
                    LogManager.Log("event=world_lighting_frame_handoff scene="+_lighting.ReadyScene+" captureQpcMs="+stats.LastFrameQpcMs.ToString("F1",CultureInfo.InvariantCulture));
                var settings=_preset.ShaderSettings(_lighting.Sample(NowMs()));
                bool changed=_lastSettings==null;
                for (int i=0;!changed && i<settings.Length;i++) if (Math.Abs(settings[i]-_lastSettings[i])>0.000001f) changed=true;
                if (changed) { _native.Matrix(settings); _lastSettings=settings; }
                if (ready && !_surface.Visible) { _surface.Show(); PlaceBelowHud(); _surface.RefreshPointer(); }
                if (!ready && NowMs()-Math.Max(_startedMs,_requiredFrameMs)>10000) throw new TimeoutException("世界捕获没有恢复有效画面");
                if (NowMs()-_lastLogMs>1000) {
                    _lastLogMs=NowMs();
                    LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                        "event=world_compositor_frame received={0} presented={1} size={2}x{3} ageMs={4:F1} submitMs={5:F3} presentMs={6:F3} cpuReadbacks={7} adapter={8} light={9:F3} scale={10:F2} output={11}x{12}",
                        stats.Received,stats.Presented,stats.Width,stats.Height,stats.LastFrameQpcMs==0 ? -1 : NowMs()-stats.LastFrameQpcMs,stats.SubmitMs,stats.PresentMs,stats.CpuReadbacks,stats.Adapter,_lighting.LastReadyLight,_appliedScale,_surface.ClientSize.Width,_surface.ClientSize.Height));
                }
            } catch (Exception error) {
                _faulted=true; _timer.Stop();
                if (!_owner.IsDisposed) _owner.Hide();
                StopCapture();
                LogManager.Log("event=world_compositor_failed "+error);
                // Rendering is a runtime requirement. Do not silently continue as a fully lit world.
                if (!_owner.IsDisposed) {
                    MessageBox.Show(_owner,"世界画面渲染失败，本次游戏将关闭。请保留日志并使用配套构建重试。\n"+error.Message,"画面渲染失败",MessageBoxButtons.OK,MessageBoxIcon.Error);
                    _owner.Close();
                }
            } finally { _starting=false; }
        }
        private bool CanShow() => !_owner.IsDisposed && _owner.Visible && _owner.WindowState!=FormWindowState.Minimized && _anchor.Visible && _canPresent();
        private bool Synchronize()
        {
            Rectangle screen=_anchor.RectangleToScreen(_anchor.ClientRectangle);
            if (DwmGetWindowAttribute(_owner.Handle,9,out Rect frame,Marshal.SizeOf<Rect>())!=0) throw new InvalidOperationException("Cannot resolve capture bounds");
            if (screen.Width<1 || screen.Height<1 || !frame.Rectangle.Contains(screen)) { _schedulingAllowed=false; _surface.Hide(); _requiredFrameMs=NowMs(); return false; }
            if (!GetClientRect(_flash,out Rect client)) return false;
            var sourceOrigin=new Point(0,0);
            if (!ClientToScreen(_flash,ref sourceOrigin)) return false;
            var source=new Rectangle(sourceOrigin,new Size(client.Right,client.Bottom));
            if (!screen.Contains(source) || source.Width<1 || source.Height<1) { _schedulingAllowed=false; return false; }
            Rectangle crop=CalculateCrop(source,frame.Rectangle);
            if (crop!=_crop || _surface.Bounds!=screen || _viewportHeld) {
                // Source-size changes keep the previous full-size GPU image visible.
                // Actual output-window changes still use the existing geometry lifecycle.
                if (_surface.Bounds!=screen) _surface.Hide();
                _requiredFrameMs=_viewportHeld ? Math.Max(_requiredFrameMs,_paintFenceMs) : NowMs();
                _native.Viewport(crop,_requiredFrameMs); _viewportHeld=false;
                _crop=crop; _surface.Bounds=screen; _surface.RefreshPointer();
            }
            return true;
        }
        internal static Rectangle CalculateCrop(Rectangle game,Rectangle capturedFrame)
        {
            if (game.Width<1 || game.Height<1 || !capturedFrame.Contains(game)) throw new ArgumentException("Game viewport outside capture bounds");
            return new Rectangle(game.X-capturedFrame.X,game.Y-capturedFrame.Y,game.Width,game.Height);
        }
        private void PlaceBelowHud()
        {
            IntPtr previous=GetWindow(_owner.Handle,3);
            if (previous!=IntPtr.Zero && previous!=_surface.Handle) SetWindowPos(_surface.Handle,previous,0,0,0,0,0x0013);
        }
        private void OnGeometryChanged(object sender,EventArgs e) { _schedulingAllowed=false; if (_native!=null) { _surface.Hide(); _requiredFrameMs=NowMs(); } }
        private void OnDpiChanged(object sender,DpiChangedEventArgs e) => OnGeometryChanged(sender,e);
        private void OnClosed(object sender,FormClosedEventArgs e) => Dispose();
        private static double NowMs() => Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;
        private void StopCapture()
        {
            _viewportHeld=false; _paintFenceMs=0;
            _surface?.Hide();
            try { _native?.Dispose(); } finally { _native=null; _surface?.CancelPointer(); _surface?.Dispose(); _surface=null; _pointerBridge?.Dispose(); _pointerBridge=null; _flash=IntPtr.Zero; }
        }
        public void Dispose()
        {
            if (_disposed) return; _disposed=true; _timer.Stop(); StopCapture(); _timer.Dispose();
            _owner.LocationChanged-=OnGeometryChanged; _owner.SizeChanged-=OnGeometryChanged;
            _owner.DpiChanged-=OnDpiChanged; _owner.FormClosed-=OnClosed;
            _anchor.SizeChanged-=OnGeometryChanged; _anchor.LocationChanged-=OnGeometryChanged;
        }
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left,Top,Right,Bottom; public Rectangle Rectangle=>Rectangle.FromLTRB(Left,Top,Right,Bottom); }
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd,int attribute,out Rect value,int size);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd,uint command);
        [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd,ref Point point);
    }
}
