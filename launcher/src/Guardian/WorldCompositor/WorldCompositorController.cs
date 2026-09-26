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
        private readonly WorldPresentationCatalog _presentationCatalog;
        private readonly BulletVisualCatalog _bulletCatalog;
        private readonly bool _bulletCandidateEnabled;
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
        private int _appliedWeatherType=-1, _appliedWeatherQuality=-1;
        private float _appliedWeatherIntensity=float.NaN;
        private uint _appliedWeatherSeed;
        private int _appliedWeatherStyleType=-1;
        private int _appliedAtmospherePreset=-1;
        private string _appliedAtmosphereName;
        private float[] _appliedAtmosphereParameters;
        private readonly object _weatherCameraLock=new object();
        private float _weatherCameraX, _weatherCameraY, _weatherCameraScale=1;
        private float _weatherCameraGroundMin=360, _weatherCameraGroundMax=520;
        private bool _weatherCameraDispatchAllowed;
        private float _appliedWeatherCameraX=float.NaN, _appliedWeatherCameraY=float.NaN;
        private float _appliedWeatherCameraScale=float.NaN, _appliedWeatherGroundMin=float.NaN, _appliedWeatherGroundMax=float.NaN;
        private bool _weatherCapabilityAdvertised;
        private double _lastWeatherCapAttemptMs;
        internal Func<bool,bool> WeatherCapabilityChanged;
        internal Func<bool,bool> BulletCapabilityChanged;
        private volatile bool _bulletStylesReady, _bulletCapabilityAdvertised;
        private double _lastBulletCapAttemptMs;
        private double _bulletCaptureNotReadyMs;
        private long _lastBulletFrameLogTicks;
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
        // The F packet already drives hit numbers on the socket thread. Forward its
        // camera to the native visual state on that path as well: waiting for the
        // 33 ms UI timer adds a visible frame during running camera movement.
        internal void ObserveWeatherCamera(float x,float y,float scale)
        {
            if (!float.IsFinite(x) || !float.IsFinite(y) || !float.IsFinite(scale)
                || Math.Abs(x)>1000000 || Math.Abs(y)>1000000 || scale<=0 || scale>20) return;
            lock (_weatherCameraLock) {
                _weatherCameraX=x; _weatherCameraY=y; _weatherCameraScale=scale;
                if (_weatherCameraDispatchAllowed && _native!=null) PushWeatherCameraLocked();
            }
        }
        internal void ObserveBulletFrame(BulletVisualFrame frame,float cameraX,float cameraY,float cameraScale)
        {
            if (frame == null) return;
            bool failed = false;
            lock (_weatherCameraLock)
            {
                if (!_bulletCapabilityAdvertised || !_bulletStylesReady || _native == null) return;
                try {
                    _native.BulletFrame(frame,cameraX,cameraY,cameraScale);
                    if (frame.NativeOwned && frame.Instances.Length > 0) {
                        long now=Stopwatch.GetTimestamp();
                        if (now-_lastBulletFrameLogTicks>=Stopwatch.Frequency*2) {
                            _lastBulletFrameLogTicks=now;
                            LogManager.Log("event=bullet_visual_native_frame epoch="+frame.Epoch
                                +" frame="+frame.Frame+" normal="+frame.NormalCount
                                +" chain="+frame.ChainCount+" overflow="+frame.Overflow);
                        }
                    }
                }
                catch (Exception error) {
                    failed = true;
                    LogManager.Log("event=bullet_visual_native_frame_failed " + error.Message);
                }
            }
            if (failed) { _bulletStylesReady=false; RevokeBulletCapability("native_frame_failed"); }
        }
        internal void RejectBulletFrame()
        {
            _bulletStylesReady=false;
            RevokeBulletCapability("invalid_or_stale_frame");
        }
        internal void BulletConnectionLost() => RevokeBulletCapability("socket_disconnected");
        internal void ClearBulletFrame()
        {
            lock (_weatherCameraLock)
            {
                try { _native?.ClearBulletFrame(); }
                catch (Exception error) { LogManager.Log("event=bullet_visual_clear_failed " + error.Message); }
            }
        }
        private void RevokeBulletCapability(string reason)
        {
            bool advertised;
            lock (_weatherCameraLock)
            {
                advertised = _bulletCapabilityAdvertised;
                _bulletCapabilityAdvertised = false;
                try { _native?.ClearBulletFrame(); }
                catch (Exception error) { LogManager.Log("event=bullet_visual_clear_failed " + error.Message); }
            }
            if (!advertised) return;
            bool sent = false;
            try { sent = BulletCapabilityChanged?.Invoke(false) == true; }
            catch (Exception error) { LogManager.Log("event=bullet_visual_cap_revoke_failed " + error.Message); }
            LogManager.Log("event=bullet_visual_cap_revoke reason=" + reason + " sent=" + sent);
        }
        private void NoteBulletCaptureNotReady(string reason)
        {
            // A scheduled DRS resize can miss one capture tick. Keep ownership
            // through that brief handoff; sustained loss returns it to Flash.
            if (!_bulletCapabilityAdvertised) { _bulletCaptureNotReadyMs=0; return; }
            double now=NowMs();
            if (_bulletCaptureNotReadyMs==0) _bulletCaptureNotReadyMs=now;
            else if (now-_bulletCaptureNotReadyMs>=250) RevokeBulletCapability(reason);
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
            Action<double> setRenderScale,Action focusFlash,uint inputEpochLimit=WorldPointerMapper.EpochLimit,
            BulletVisualCatalog bulletCatalog=null)
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
            _bulletCatalog=bulletCatalog;
            _bulletCandidateEnabled=bulletCatalog!=null
                && AppContext.BaseDirectory.StartsWith(tempRoot,StringComparison.OrdinalIgnoreCase)
                && Environment.GetEnvironmentVariable("CF7_BULLET_NATIVE_DISABLE")!="1";
            _preset=WorldLightingPreset.Load(Path.Combine(projectRoot,"launcher","data","world-lighting","preset.json"),
                message => LogManager.Log(message));
            string visualPath=Path.Combine(projectRoot,
                WorldPresentationCatalog.RelativePath.Replace('/',Path.DirectorySeparatorChar));
            _presentationCatalog=WorldPresentationCatalog.Load(visualPath);
            LogManager.Log("event=world_presentation_catalog sha256="+_presentationCatalog.Sha256+" path="+visualPath);
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
            if (!frame.Ready || frame.Scene!=previousScene) {
                _surface?.CancelPointer();
                RevokeBulletCapability("scene_change");
            }
            _frame=frame;
            if (!frame.Ready || frame.Scene!=previousScene) InvalidateWeather();
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
                    _bulletStylesReady=false;
                    if (_bulletCandidateEnabled) {
                        try { _native.BulletStyles(_bulletCatalog); _bulletStylesReady=true; }
                        catch (Exception error) { LogManager.Log("event=bullet_visual_styles_unavailable " + error.Message); }
                    }
                    LogManager.Log("event=world_compositor_identity S=0x"+_owner.Handle.ToString("X")+" P=0x"+_surface.Handle.ToString("X")
                        +" F=0x"+_flash.ToString("X")+" hostPid="+Environment.ProcessId+" inputSession="+_pointerBridge.SessionIdentity);
                    _crop=Rectangle.Empty; _startedMs=NowMs(); _lastSettings=null; _active=true; _appliedSharpness=float.NaN;
                    _lastLut=null; _lutActive=false;
                    _appliedWeatherType=-1;
                    _appliedWeatherStyleType=-1;
                    _appliedAtmospherePreset=-1;
                    _appliedAtmosphereName=null;
                    LogManager.Log("event=world_compositor_start flash=0x"+_flash.ToString("X")+" fpsLimit=30");
                }
                if (_getFlash()!=_flash || !IsWindow(_flash)) { ResetSource(); return; }
                // Scene changes clear native weather before any geometry/ready early return.
                if (_appliedWeatherType<0) ApplyWeather(false);
                if (_appliedAtmospherePreset<0) ApplyAtmosphere(false);
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
                    if (!show) { _surface.Hide(); RevokeBulletCapability("surface_hidden"); }
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
                    if (!CanShow()) { _native.Active(false); _active=false; _surface.Hide(); RevokeBulletCapability("resize_hidden"); return; }
                }
                var stats=_native.Read();
                if (stats.State==2 || stats.State==3) throw new InvalidOperationException(stats.Message+" HRESULT=0x"+stats.Error.ToString("X8"));
                if (!Synchronize()) { NoteBulletCaptureNotReady("geometry_unknown"); return; } // an unknown extent must not mask native failure
                bool ready=stats.Received>0 && stats.Width==_crop.Width && stats.Height==_crop.Height && stats.LastFrameQpcMs>=_requiredFrameMs;
                if (ready) _bulletCaptureNotReadyMs=0;
                else NoteBulletCaptureNotReady("capture_not_ready");
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
                ApplyWeatherCamera(ready);
                ApplyWeather(ready);
                ApplyAtmosphere(ready);
                if (ready && !_surface.Visible) { _surface.Show(); PlaceBelowHud(); _surface.RefreshPointer(); }
                if (ready && !_weatherCapabilityAdvertised && NowMs()-_lastWeatherCapAttemptMs>=500) {
                    _lastWeatherCapAttemptMs=NowMs();
                    try { _weatherCapabilityAdvertised=WeatherCapabilityChanged?.Invoke(true)==true; }
                    catch (Exception error) { LogManager.Log("event=world_weather_cap_failed "+error.Message); }
                }
                if (ready && _bulletStylesReady && !_bulletCapabilityAdvertised
                    && NowMs()-_lastBulletCapAttemptMs>=500 && BulletCapabilityChanged!=null) {
                    _lastBulletCapAttemptMs=NowMs();
                    lock (_weatherCameraLock) _bulletCapabilityAdvertised=true;
                    bool sent=false;
                    try { sent=BulletCapabilityChanged(true); }
                    catch (Exception error) { LogManager.Log("event=bullet_visual_cap_failed " + error.Message); }
                    if (!sent) RevokeBulletCapability("cap_send_failed");
                    else LogManager.Log("event=bullet_visual_cap_native");
                }
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
            // DWM and the Flash child can round their bottom edges one pixel
            // apart after a window move. Capture only the measured intersection;
            // keep rejecting larger misses instead of inventing an origin.
            if (!TryCalculateCrop(source,capture,out Rectangle crop)) return RejectGeometry("source_outside_capture",screen,source,capture);
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
        private void InvalidateWeather()
        {
            _appliedWeatherType=-1;
            _appliedWeatherStyleType=-1;
            _appliedAtmospherePreset=-1;
            _appliedAtmosphereName=null;
            lock (_weatherCameraLock) {
                _weatherCameraDispatchAllowed=false;
                _appliedWeatherCameraX=_appliedWeatherCameraY=_appliedWeatherCameraScale=float.NaN;
            }
        }
        private void ApplyAtmosphere(bool captureReady)
        {
            if (_native==null) return;
            WorldLightingFrame frame=_frame;
            bool show=captureReady && frame?.Ready==true && frame.Atmosphere.Name!="none"
                && _lighting.ReadyScene==frame.Scene && !_lighting.WaitingForCapture;
            string name=show ? frame.Atmosphere.Name : "none";
            int preset=name=="none" ? 0 : name=="custom" ? 11 : _presentationCatalog.Atmosphere(name).Family;
            float[] parameters=show ? frame.Atmosphere.NativeParameters : AtmosphereFrame.None.NativeParameters;
            if (show && preset!=11 && name!=_appliedAtmosphereName) {
                AtmosphereLook look=_presentationCatalog.Atmosphere(name);
                _native.AtmosphereStyle(look.Family,look.Tuning);
            }
            bool changed=preset!=_appliedAtmospherePreset || _appliedAtmosphereParameters==null;
            for (int i=0;!changed && i<parameters.Length;i++)
                changed=parameters[i]!=_appliedAtmosphereParameters[i];
            if (changed) _native.Atmosphere(preset,parameters);
            _appliedAtmospherePreset=preset;
            _appliedAtmosphereParameters=parameters;
            if (!changed && name==_appliedAtmosphereName) return;
            _appliedAtmosphereName=name;
            LogManager.Log("event=world_atmosphere_apply scene="+(frame?.Scene ?? 0)+" preset="+preset
                +" captureReady="+captureReady);
        }
        private void ApplyWeather(bool captureReady)
        {
            if (_native==null) return;
            WorldLightingFrame frame=_frame;
            bool show=captureReady && frame!=null && frame.Ready && frame.WeatherNative
                && _lighting.ReadyScene==frame.Scene && !_lighting.WaitingForCapture;
            int type=show ? frame.WeatherType : 0;
            float intensity=show ? frame.WeatherIntensity : 0;
            // Flash's adaptive quality governs only its fallback drawing. Native
            // weather has a separate fixed and bounded GPU budget.
            int quality=show ? 0 : 3;
            uint seed=show ? unchecked((uint)frame.Scene) : 0;
            if (show && type!=0 && type!=_appliedWeatherStyleType) {
                WeatherLook look=_presentationCatalog.Weather(type);
                _native.WeatherStyle(look.Type,look.Count,look.Tuning);
                _appliedWeatherStyleType=type;
            }
            if (type==_appliedWeatherType && intensity==_appliedWeatherIntensity
                && quality==_appliedWeatherQuality && seed==_appliedWeatherSeed) return;
            _native.Weather(type,intensity,quality,seed);
            _appliedWeatherType=type; _appliedWeatherIntensity=intensity;
            _appliedWeatherQuality=quality; _appliedWeatherSeed=seed;
            LogManager.Log("event=world_weather_apply scene="+(frame?.Scene ?? 0)+" type="+type
                +" intensity="+intensity.ToString("F2",CultureInfo.InvariantCulture)
                +" quality="+quality+" captureReady="+captureReady
                +" waitingForCapture="+_lighting.WaitingForCapture);
        }
        private void ApplyWeatherCamera(bool captureReady)
        {
            WorldLightingFrame frame=_frame;
            bool allow=_native!=null && captureReady && frame?.Ready==true
                && (frame.WeatherNative || frame.Atmosphere.Name!="none")
                && _lighting.ReadyScene==frame.Scene && !_lighting.WaitingForCapture;
            lock (_weatherCameraLock) {
                _weatherCameraDispatchAllowed=allow;
                if (!allow) return;
                _weatherCameraGroundMin=frame.WeatherGroundMin;
                _weatherCameraGroundMax=frame.WeatherGroundMax;
                PushWeatherCameraLocked();
            }
        }
        // Caller holds _weatherCameraLock. StopCapture takes the same lock before
        // freeing the native session, so the socket callback cannot use a dead handle.
        private void PushWeatherCameraLocked()
        {
            if (_weatherCameraX==_appliedWeatherCameraX && _weatherCameraY==_appliedWeatherCameraY
                && _weatherCameraScale==_appliedWeatherCameraScale
                && _weatherCameraGroundMin==_appliedWeatherGroundMin
                && _weatherCameraGroundMax==_appliedWeatherGroundMax) return;
            _native.WeatherCamera(_weatherCameraX,_weatherCameraY,_weatherCameraScale,
                _weatherCameraGroundMin,_weatherCameraGroundMax);
            _appliedWeatherCameraX=_weatherCameraX; _appliedWeatherCameraY=_weatherCameraY;
            _appliedWeatherCameraScale=_weatherCameraScale;
            _appliedWeatherGroundMin=_weatherCameraGroundMin;
            _appliedWeatherGroundMax=_weatherCameraGroundMax;
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
            if (!TryCalculateCrop(game,capturedFrame,out Rectangle crop)) throw new ArgumentException("Game viewport outside capture bounds");
            return crop;
        }
        internal static bool TryCalculateCrop(Rectangle game,Rectangle capturedFrame,out Rectangle crop)
        {
            crop=Rectangle.Empty;
            if (game.Width<1 || game.Height<1 || capturedFrame.Width<1 || capturedFrame.Height<1) return false;
            Rectangle visible=Rectangle.Intersect(game,capturedFrame);
            if (visible.Width<1 || visible.Height<1
                || visible.Left-game.Left>2 || visible.Top-game.Top>2
                || game.Right-visible.Right>2 || game.Bottom-visible.Bottom>2) return false;
            crop=new Rectangle(visible.X-capturedFrame.X,visible.Y-capturedFrame.Y,visible.Width,visible.Height);
            return true;
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
            // Same-socket source loss must return visual ownership to Flash.
            RevokeBulletCapability("capture_stopped");
            _bulletStylesReady=false;
            _lastBulletCapAttemptMs=0;
            _lastBulletFrameLogTicks=0;
            _surface?.Hide();
            if (_weatherCapabilityAdvertised) {
                _weatherCapabilityAdvertised=false;
                try { WeatherCapabilityChanged?.Invoke(false); }
                catch (Exception error) { LogManager.Log("event=world_weather_cap_revoke_failed "+error.Message); }
            }
            _lastWeatherCapAttemptMs=0;
            _lastGeometryRejection=null;
            _lastCaptureGeneration=0;
            _appliedWeatherType=-1; _appliedWeatherIntensity=float.NaN;
            _appliedWeatherQuality=-1; _appliedWeatherSeed=0;
            _appliedWeatherStyleType=-1;
            _appliedAtmospherePreset=-1; _appliedAtmosphereParameters=null;
            _appliedAtmosphereName=null;
            lock (_weatherCameraLock) {
                _weatherCameraDispatchAllowed=false;
                _appliedWeatherCameraX=_appliedWeatherCameraY=_appliedWeatherCameraScale=float.NaN;
                _appliedWeatherGroundMin=_appliedWeatherGroundMax=float.NaN;
                _weatherCameraX=0; _weatherCameraY=0; _weatherCameraScale=1;
                _weatherCameraGroundMin=360; _weatherCameraGroundMax=520;
            }
            _inputRenewRequested=false;_inputClosed=false;
            _viewportHeld=false; _paintFenceMs=0;
            _everReady=false; _frameAdvancing=false; _progressKnown=false;
            _surface?.Hide();
            try { lock (_weatherCameraLock) { _native?.Dispose(); _native=null; } }
            finally { _native=null; _surface?.CancelPointer(); _surface?.Dispose(); _surface=null; if(_pointerBridge!=null)_retiringInput=_pointerBridge.CloseAsync(); _pointerBridge=null; _flash=IntPtr.Zero; }
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
