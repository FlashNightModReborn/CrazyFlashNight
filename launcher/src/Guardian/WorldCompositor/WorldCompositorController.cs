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
        private readonly WorldLightingPreset _preset;
        private readonly Timer _timer = new Timer { Interval=33 };
        private NativeCompositorSession _native;
        private WorldCompositionSurface _surface;
        private NativePointerBridge _pointerBridge;
        private IntPtr _flash;
        private Rectangle _crop;
        private string _lastGeometryRejection;
        private ulong _lastCaptureGeneration;
        private WorldLightingFrame _frame;
        private WorldLightingTransition _lighting = new WorldLightingTransition();
        private long _reportedPendingScene;
        private bool _disposed, _starting, _faulted, _active;
        private bool _inputRenewRequested,_inputClosed;
        private Task<bool> _retiringInput;
        internal NativePointerBridge InputBridgeForDiagnostics => _pointerBridge;
        internal int InputRenewals { get; private set; }
        private readonly uint _inputEpochLimit;
        private bool _permissionChecked, _borderless;
        private double _waitingStateMs;
        private double _requiredFrameMs, _startedMs, _lastLogMs;
        private float[] _lastSettings;
        // LUT 路径（lut-set-v1）：_lutActive=原生当前在 LUT 分支；_lastLut/_lastLutLight 是变更检测
        // （变更才上传，不逐帧传）；会话重建（StopCapture/ResetSource）时随 _lastSettings 一并复位。
        private bool _lutActive;
        private byte[] _lastLut;
        private double _lastLutLight;
        private double _targetScale=1, _appliedScale=1;
        private float _targetSharpness;
        private float _appliedSharpness=float.NaN;
        private bool _viewportHeld;
        private double _paintFenceMs;
        // A0 观测：「曾经 ready」与「当前推进」分离。_everReady 闩锁首次有效帧；
        // _frameAdvancing 按 250ms 有界窗口判定推进，用于区分停帧/暂停/阻塞，
        // 只观测记录，不触发自动重启或抢焦。
        private bool _everReady, _frameAdvancing, _progressKnown;
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

        internal readonly struct LutLabGrabResult
        {
            internal LutLabGrabResult(int code,int width,int height) { Code=code; Width=width; Height=height; }
            internal readonly int Code, Width, Height;
        }
        internal double LightingGamma => _preset.Gamma;
        // dev-only LUT 实验室抓帧桥：返回最近捕获帧（未调色 BGRA）。_native 生命周期归 UI 线程，
        // 跨线程调用经 owner.Invoke 排队；合成器未运行/导出缺失/无有效帧时透传原生错误码。
        internal LutLabGrabResult GrabLatestFrameBgra(byte[] buffer)
        {
            if (_owner.IsDisposed) return new LutLabGrabResult(NativeCompositorSession.GrabNoFrame,0,0);
            if (_owner.InvokeRequired)
                return (LutLabGrabResult)_owner.Invoke(new Func<LutLabGrabResult>(() => GrabLatestFrameBgra(buffer)));
            var session=_native;
            if (_disposed || session==null) return new LutLabGrabResult(NativeCompositorSession.GrabNoFrame,0,0);
            // 缺陷 X（2026-09-24）：合成器未呈现（含面板遮挡挂起）或世界视口裁剪尚未建立时，
            // 原生侧 crop 为空会退化为整窗回读（含标题栏）。仅世界视口已建立才允许抓帧。
            if (!CanGrabWorldViewport(_active,_crop)) return new LutLabGrabResult(NativeCompositorSession.GrabNoWorldViewport,0,0);
            int width,height;
            return new LutLabGrabResult(session.GrabLatestFrame(buffer,out width,out height),width,height);
        }
        internal static bool CanGrabWorldViewport(bool active, System.Drawing.Rectangle crop)
        {
            return active && crop.Width >= 1 && crop.Height >= 1;
        }

        internal WorldCompositorController(Form owner, Control anchor, Func<IntPtr> getFlash,
            Func<bool> canPresent, Action<string> notify, string projectRoot, Func<bool> shouldPrepare,
            Action<double> setRenderScale,Action focusFlash,uint inputEpochLimit=WorldPointerMapper.EpochLimit)
        {
            string tempRoot=Path.GetFullPath(Path.Combine(projectRoot,"tmp"))+Path.DirectorySeparatorChar;
            string testCap=Environment.GetEnvironmentVariable("CF7_INPUT_SESSION_TEST_CAP");
            if(inputEpochLimit==WorldPointerMapper.EpochLimit && AppContext.BaseDirectory.StartsWith(tempRoot,StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(testCap)) {
                if(!uint.TryParse(testCap,out inputEpochLimit) || inputEpochLimit<8 || inputEpochLimit>WorldPointerMapper.EpochLimit)
                    throw new ArgumentOutOfRangeException("CF7_INPUT_SESSION_TEST_CAP");
                LogManager.Log("event=world_pointer_test_cap value="+inputEpochLimit+" NOT_DEPLOYED=true");
            }
            _inputEpochLimit=inputEpochLimit;
            _owner=owner; _anchor=anchor; _getFlash=getFlash; _canPresent=canPresent; _notify=notify; _shouldPrepare=shouldPrepare;
            _setRenderScale=setRenderScale; _focusFlash=focusFlash;
            _preset=WorldLightingPreset.Load(Path.Combine(projectRoot,"launcher","data","world-lighting","preset.json"),
                message => LogManager.Log(message));
            _timer.Tick+=OnTick;
            _owner.LocationChanged+=OnGeometryChanged; _owner.SizeChanged+=OnGeometryChanged;
            _owner.DpiChanged+=OnDpiChanged; _owner.FormClosed+=OnClosed; _owner.Deactivate+=OnOwnerDeactivated;
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
                if(_inputRenewRequested && !_inputClosed) {await RenewInputAsync();if(_disposed)return;}
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
                    if(_retiringInput!=null) {
                        _starting=true;bool retired=await _retiringInput;_retiringInput=null;
                        if(_disposed)return;
                        if(!retired) {_inputClosed=true;_notify?.Invoke("输入恢复尚未确认，请保留日志后重新启动游戏");return;}
                    }
                    if(_inputClosed)return;
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
                    _surface=new WorldCompositionSurface(_getFlash,_focusFlash,_pointerBridge,_inputEpochLimit) { Owner=_owner };
                    BindInput(_pointerBridge,_surface);
                    _surface.CreateControl();
                    _native=new NativeCompositorSession(module,_owner.Handle,(uint)Environment.ProcessId,_surface.Handle,0,_borderless);
                    LogManager.Log("event=world_compositor_identity S=0x"+_owner.Handle.ToString("X")+" P=0x"+_surface.Handle.ToString("X")
                        +" F=0x"+_flash.ToString("X")+" hostPid="+Environment.ProcessId+" inputSession="+_pointerBridge.SessionIdentity);
                    _crop=Rectangle.Empty; _startedMs=NowMs(); _lastSettings=null; _active=true; _appliedSharpness=float.NaN;
                    _lastLut=null; _lutActive=false;
                    LogManager.Log("event=world_compositor_start flash=0x"+_flash.ToString("X")+" fpsLimit=30");
                }
                if (_getFlash()!=_flash || !IsWindow(_flash)) { ResetSource(); return; }
                if(!_pointerBridge.IsAlive && !_inputClosed && !_inputRenewRequested) {
                    _inputClosed=true;_surface.CancelPointer("bridge_closed");
                    LogManager.Log("event=world_pointer_closed_unconfirmed unexpected_exit");
                    _notify?.Invoke("输入连接已停止，请保留日志后重新启动游戏");
                }
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
                if (!_inputClosed && !_surface.InputRenewing && _targetScale!=_appliedScale && !_surface.IsDragging) {
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
                var stats=_native.Read();
                if (stats.State==2 || stats.State==3) throw new InvalidOperationException(stats.Message+" HRESULT=0x"+stats.Error.ToString("X8"));
                if (!Synchronize()) return; // an unknown extent must not mask native failure
                bool ready=stats.Received>0 && stats.Width==_crop.Width && stats.Height==_crop.Height && stats.LastFrameQpcMs>=_requiredFrameMs;
                // A0 观测：推进证据用有界窗口而非逐 tick 比较——30FPS 下逐 tick 比
                // LastFrameQpcMs 会因两时钟错位交替 flap。age<250ms 视为推进中；
                // 静态/暂停场景源不推进是合法的，不按固定帧龄判死，只分离事实：
                // everReady（曾经出帧）、advancing（推进窗口内）、sceneReady（AS2 场景状态）。
                bool advancing=stats.LastFrameQpcMs>0 && NowMs()-stats.LastFrameQpcMs<250;
                if (ready) _everReady=true;
                if (!_progressKnown || advancing!=_frameAdvancing)
                {
                    _progressKnown=true; _frameAdvancing=advancing;
                    LogManager.Log("event=world_compositor_progress state="+(advancing?"advancing":"stalled")
                        +" everReady="+_everReady+" sceneReady="+(_frame?.Ready==true)
                        +" captureQpcMs="+stats.LastFrameQpcMs.ToString("F1",CultureInfo.InvariantCulture));
                }
                // Observe healthy FPS during a gesture; only the actual resize waits
                // for release. Frequent clicks must not reset the recovery timer.
                _schedulingAllowed=!_inputClosed && !_surface.InputRenewing && ready && _frame?.Ready==true && _targetScale==_appliedScale;
                if (ready && _appliedSharpness!=_targetSharpness) { _native.Sharpness(_targetSharpness); _appliedSharpness=_targetSharpness; }
                // Read() reports a captured frame after its Present submission. This is a
                // timestamp freshness fence, not proof of the pixels' semantic scene identity.
                if (ready && _lighting.ConfirmCapturedFrame(stats.LastFrameQpcMs,NowMs()))
                    LogManager.Log("event=world_lighting_frame_handoff scene="+_lighting.ReadyScene+" captureQpcMs="+stats.LastFrameQpcMs.ToString("F1",CultureInfo.InvariantCulture));
                if (_preset.UsesLut(_lighting.CurrentMode)) {
                    // LUT 路径（lut-set-v1）：350ms 过渡状态机不变，采样语义由矩阵改为连续 light 等级，
                    // 相邻整数档 CPU blend（32^3 逐字节）；变更才上传原生（过渡期间逐 tick、稳态零上传）。
                    double lutLight=WorldLutSet.ClampLight(_lighting.SampleLight(NowMs()));
                    if (_lastLut==null || Math.Abs(lutLight-_lastLutLight)>1e-6) {
                        _lastLut=_preset.LutSet.BlendLevel(lutLight);
                        _native.SetLut(_lastLut);
                        _lastLutLight=lutLight;
                    }
                    _lutActive=true;
                } else {
                    if (_lutActive) { _native.ClearLut(); _lutActive=false; }
                    var settings=_preset.ShaderSettings(_lighting.Sample(NowMs()));
                    bool changed=_lastSettings==null;
                    for (int i=0;!changed && i<settings.Length;i++) if (Math.Abs(settings[i]-_lastSettings[i])>0.000001f) changed=true;
                    if (changed) { _native.Matrix(settings); _lastSettings=settings; }
                }
                if (ready && !_surface.Visible) { _surface.Show(); PlaceBelowHud(); _surface.RefreshPointer(); }
                if (!ready && NowMs()-Math.Max(_startedMs,_requiredFrameMs)>10000) throw new TimeoutException("世界捕获没有恢复有效画面");
                if (NowMs()-_lastLogMs>1000) {
                    _lastLogMs=NowMs();
                    LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                        "event=world_compositor_frame received={0} presented={1} size={2}x{3} ageMs={4:F1} submitMs={5:F3} presentMs={6:F3} cpuReadbacks={7} adapter={8} light={9:F3} scale={10:F2} output={11}x{12} everReady={13} advancing={14}",
                        stats.Received,stats.Presented,stats.Width,stats.Height,stats.LastFrameQpcMs==0 ? -1 : NowMs()-stats.LastFrameQpcMs,stats.SubmitMs,stats.PresentMs,stats.CpuReadbacks,stats.Adapter,_lighting.LastReadyLight,_appliedScale,_surface.ClientSize.Width,_surface.ClientSize.Height,_everReady,_frameAdvancing));
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
        internal void BindInput(NativePointerBridge bridge,WorldCompositionSurface surface)
        {
            _pointerBridge=bridge;_surface=surface;_flash=_getFlash();
            _surface.RenewalRequested+=()=>_inputRenewRequested=true;
        }
        private async Task RenewInputAsync()
        {
            if(_inputRenewRequested && !_inputClosed) {
                    _starting=true;_inputRenewRequested=false;
                    var old=_pointerBridge;var surface=_surface;var source=_flash;
                    bool closed=await old.CloseAsync(surface.GracefulRenewal);
                    if(_disposed || surface!=_surface || source!=_getFlash())return;
                    if(!closed) {
                        _inputClosed=true;_notify?.Invoke("输入恢复尚未确认，请保留日志后重新启动游戏");
                    } else {
                        try {
                            var next=await NativePointerBridge.Start(source,_owner.Handle);
                            if(_disposed || surface!=_surface || source!=_getFlash()) {next.Dispose();return;}
                            _pointerBridge=next;surface.Rebind(next);InputRenewals++;
                            LogManager.Log("event=world_pointer_renewed session="+next.SessionIdentity+" count="+InputRenewals);
                        } catch(Exception error) {
                            _inputClosed=true;LogManager.Log("event=world_pointer_closed_unconfirmed bind="+error.Message);
                            _notify?.Invoke("输入恢复尚未确认，请保留日志后重新启动游戏");
                        }
                    }
                }
        }
        private bool CanShow() => !_owner.IsDisposed && _owner.Visible && _owner.WindowState!=FormWindowState.Minimized && _anchor.Visible && _canPresent();
        private bool Synchronize()
        {
            Rectangle screen=_anchor.RectangleToScreen(_anchor.ClientRectangle);
            if (DwmGetWindowAttribute(_owner.Handle,9,out Rect frame,Marshal.SizeOf<Rect>())!=0) throw new InvalidOperationException("Cannot resolve capture bounds");
            if(!GetWindowRect(_owner.Handle,out Rect window))return false;
            Size content=_native.ReadCaptureSize();
            if(_lastCaptureGeneration!=_native.CaptureGeneration) {
                _lastCaptureGeneration=_native.CaptureGeneration;
                LogManager.Log("event=world_compositor_capture_generation value="+_lastCaptureGeneration+" WGC="+content+" window="+window.Rectangle);
            }
            if(!TryResolveCaptureFrame(frame.Rectangle,window.Rectangle,content,out Rectangle capture))
                return RejectGeometry("capture_bounds_pending content="+content+" window="+window.Rectangle,screen,Rectangle.Empty,frame.Rectangle);
            if (screen.Width<1 || screen.Height<1 || !capture.Contains(screen)) return RejectGeometry("output_outside_capture",screen,Rectangle.Empty,capture);
            if (!GetClientRect(_flash,out Rect client)) return false;
            var sourceOrigin=new Point(0,0);
            if (!ClientToScreen(_flash,ref sourceOrigin)) return false;
            var source=new Rectangle(sourceOrigin,new Size(client.Right,client.Bottom));
            // S is captured and P is independently presented. Cross-DPI child
            // rounding can put F one pixel beyond P while still inside S. P is
            // not the capture boundary: refusing here left an old crop active
            // throughout restore/maximize until a later DRS resize happened.
            if (source.Width<1 || source.Height<1 || !capture.Contains(source)) return RejectGeometry("source_outside_capture",screen,source,capture);
            Rectangle crop=CalculateCrop(source,capture);
            if(_lastGeometryRejection!=null) {
                LogManager.Log("event=world_compositor_geometry_resumed FClient="+source+" captureFrame="+capture+" P="+screen);
                _lastGeometryRejection=null;
            }
            if (crop!=_crop || _surface.Bounds!=screen || _viewportHeld) {
                // Keep the previous composed image over the reduced-resolution F.
                // A geometry transition must not expose F while awaiting a fresh frame.
                _requiredFrameMs=_viewportHeld ? Math.Max(_requiredFrameMs,_paintFenceMs) : NowMs();
                _native.Viewport(crop,_requiredFrameMs); _viewportHeld=false;
                _crop=crop; _surface.Bounds=screen; _surface.RefreshPointer();
                LogManager.Log("event=world_compositor_geometry FClient="+source+" captureFrame="+capture+" dwmFrame="+frame.Rectangle+" windowFrame="+window.Rectangle+" WGC="+content+" crop="+crop+" P="+_surface.Bounds+" frameFenceMs="+_requiredFrameMs.ToString("F1",CultureInfo.InvariantCulture));
            }
            return true;
        }
        private bool RejectGeometry(string reason,Rectangle output,Rectangle source,Rectangle capture)
        {
            _schedulingAllowed=false;
            string detail="reason="+reason+" FClient="+source+" captureFrame="+capture+" P="+output+" retainedCrop="+_crop;
            if(detail!=_lastGeometryRejection) {
                _lastGeometryRejection=detail;
                LogManager.Log("event=world_compositor_geometry_wait "+detail);
            }
            return false;
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
        private void OnGeometryChanged(object sender,EventArgs e)
        {
            _schedulingAllowed=false;
            if (_surface==null || _surface.IsDisposed) return;
            if (!CanShow()) { _surface.Hide(); return; }
            Rectangle screen=_anchor.RectangleToScreen(_anchor.ClientRectangle);
            if (screen.Width<1 || screen.Height<1 || _surface.Bounds==screen) return;
            // Windows' modal move loop can delay the render timer. Move P in the
            // geometry callback itself, preserving its last full-size image and
            // HWND. Hiding it here exposed the 67% DRS child and black remainder.
            _surface.CancelPointer("geometry_changed");
            _surface.Bounds=screen;
            LogManager.Log("event=world_compositor_follow P="+screen+" visible="+_surface.Visible);
        }
        internal static bool TryResolveCaptureFrame(Rectangle extended,Rectangle window,Size content,out Rectangle frame)
        {
            frame=Rectangle.Empty;
            if(content.Width<=0 || content.Height<=0)return false;
            if(content==extended.Size){frame=extended;return true;}
            if(content==window.Size){frame=window;return true;}
            return false; // transition/unknown geometry: do not invent an origin
        }
        private void OnDpiChanged(object sender,DpiChangedEventArgs e) => OnGeometryChanged(sender,e);
        private void OnClosed(object sender,FormClosedEventArgs e) => Dispose();
        // 宿主失活同样撤销在途指针输入：Host 抬共享代次下界，是投影端 WM_KILLFOCUS
        // 本地下界之外的第二道保险。
        private void OnOwnerDeactivated(object sender,EventArgs e) => _surface?.CancelPointer("owner_deactivate");
        private static double NowMs() => Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;
        private void StopCapture()
        {
            _lastGeometryRejection=null;
            _lastCaptureGeneration=0;
            _inputRenewRequested=false;_inputClosed=false;
            _viewportHeld=false; _paintFenceMs=0;
            _everReady=false; _frameAdvancing=false; _progressKnown=false;
            _surface?.Hide();
            try { _native?.Dispose(); } finally { _native=null; _surface?.CancelPointer(); _surface?.Dispose(); _surface=null; if(_pointerBridge!=null)_retiringInput=_pointerBridge.CloseAsync(); _pointerBridge=null; _flash=IntPtr.Zero; }
        }
        public void Dispose()
        {
            if (_disposed) return; _disposed=true; _timer.Stop(); StopCapture(); _timer.Dispose();
            _owner.LocationChanged-=OnGeometryChanged; _owner.SizeChanged-=OnGeometryChanged;
            _owner.DpiChanged-=OnDpiChanged; _owner.FormClosed-=OnClosed; _owner.Deactivate-=OnOwnerDeactivated;
            _anchor.SizeChanged-=OnGeometryChanged; _anchor.LocationChanged-=OnGeometryChanged;
        }
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left,Top,Right,Bottom; public Rectangle Rectangle=>Rectangle.FromLTRB(Left,Top,Right,Bottom); }
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd,int attribute,out Rect value,int size);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd,uint command);
        [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] private static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd,ref Point point);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
    }
}
