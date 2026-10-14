#nullable enable
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

// 真实游戏只读面板的局部 composition 端点（游戏内容只读）。
// 复用 WorldCompositor.CompositionSceneHost 与
// CoreWebView2CompositionController；不使用 WinForms WebView2、CDP 或私有反射。
// 本类不是 C1 虚拟世界宿主，不持有游戏存档/业务通道。
// help 之外的第二个消费者（intelligence）经 CompositionPanelProfile 参数化接入；
// transition（过场+loot 结算）是同一类型的独立固定投影端点，有自己的面板边界。
namespace CF7Launcher.Guardian
{
    // 只读面板端点身份：面板名、虚拟主机、页面、ready 消息与日志标签。
    // intelligence 经 Host 私有关闭上下文进入既有业务权威；help 也使用同一
    // exact 关闭事务。页面业务 reason 与 Host 的原生 cause 分开保存。
    internal sealed class CompositionPanelProfile
    {
        internal string PanelName;
        internal string HostName;
        internal string PageUrl;
        internal string ReadyMessageType;
        internal string WindowTitle;
        internal string LogTag;
        internal bool AllowTutorialPreference;
        internal bool AcceptsPanelResponses;
        internal bool DelegateCloseToAuthority;

        internal static readonly CompositionPanelProfile Help = new CompositionPanelProfile
        {
            PanelName = "help",
            HostName = "cf7-help.local",
            PageUrl = "https://cf7-help.local/composition-help.html",
            ReadyMessageType = "composition_help_ready",
            WindowTitle = "CF7 Help",
            LogTag = "[HelpSurface]",
            AllowTutorialPreference = true
        };

        internal static readonly CompositionPanelProfile Intelligence = new CompositionPanelProfile
        {
            PanelName = "intelligence",
            HostName = "cf7-intelligence.local",
            PageUrl = "https://cf7-intelligence.local/composition-intelligence.html",
            ReadyMessageType = "composition_intelligence_ready",
            WindowTitle = "CF7 Intelligence",
            LogTag = "[IntelligenceSurface]",
            AcceptsPanelResponses = true,
            DelegateCloseToAuthority = true
        };
    }

    internal sealed partial class CompositionHelpSurface : Form
    {
        private const int WmMouseActivate = 0x0021;
        private const int WmMouseMove = 0x0200;
        private const int WmLButtonDown = 0x0201;
        private const int WmLButtonUp = 0x0202;
        private const int WmLButtonDoubleClick = 0x0203;
        private const int WmRButtonDown = 0x0204;
        private const int WmRButtonUp = 0x0205;
        private const int WmRButtonDoubleClick = 0x0206;
        private const int WmMouseWheel = 0x020A;
        private const int WmMouseLeave = 0x02A3;
        private const int WmCaptureChanged = 0x0215;
        private const int MaActivateAndEat = 2;
        private const int VkEscape = 0x1B;

        private readonly Form _owner;
        private readonly string _webRoot;
        private readonly string _profileRoot;
        private readonly bool _transition;
        private readonly SceneTransitionBackingForm? _transitionBacking;
        private readonly SceneTransitionPresentationPolicy _presentationPolicy = SceneTransitionPresentationPolicy.Interactive;
        private bool _backgroundTransition;
        private readonly CompositionPanelProfile _profile;
        private readonly string _hostName, _pageUrl;
        private CoreWebView2Environment? _environment;
        private CompositionSceneHost? _scene;
        private CoreWebView2CompositionController? _web;
        private object? _webVisual;
        private TaskCompletionSource<bool>? _readyTcs;
        private int _prepareVersion;
        private bool _ready, _active, _disposed, _closePending, _trackingLeave, _capturedButton;
        private Rectangle _committed = Rectangle.Empty;
        private Rectangle _presentedViewport = Rectangle.Empty, _postedViewport = Rectangle.Empty;
        private int _postedViewportGeneration = -1;
        private string _panelInstance = "";
        private string _closeReason = "page_close";
        private JObject? _closeEnvelope;
        private int _pressedButtons;
        private readonly System.Windows.Forms.Timer _closeTimer = new() { Interval = 25 };

        internal string PanelName => _profile.PanelName;
        // DelegateCloseToAuthority 面板的非 close 入站消息（只读查询、panel-toast）。
        internal event Action<JObject>? InboundPanelMessage;
        internal event Action<JObject>? TransitionMessage;
        internal event Action? TransitionFailed;
        internal Func<JObject, string, JObject?>? TutorialPreferenceRequested;

        internal CompositionHelpSurface(Form owner, string webRoot, string profileRoot,
            CompositionPanelProfile? profile = null, bool transition = false,
            SceneTransitionPresentationPolicy? presentationPolicy = null,
            SceneTransitionBackingForm? transitionBacking = null)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _webRoot = webRoot ?? throw new ArgumentNullException(nameof(webRoot));
            _profileRoot = profileRoot ?? throw new ArgumentNullException(nameof(profileRoot));
            _transition = transition;
            if (transitionBacking != null && !transition)
                throw new ArgumentException("Only a transition endpoint can bind a transition backing", nameof(transitionBacking));
            _transitionBacking = transitionBacking;
            _presentationPolicy = transition ? presentationPolicy ?? SceneTransitionPresentationPolicy.Interactive
                : SceneTransitionPresentationPolicy.Interactive;
            _profile = profile ?? CompositionPanelProfile.Help;
            _hostName = transition ? "cf7-transition.local" : _profile.HostName;
            _pageUrl = transition ? "https://cf7-transition.local/scene-transition.html" : _profile.PageUrl;
            Text = transition ? "CF7 Scene Transition" : _profile.WindowTitle;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.Black;
            ClientSizeChanged += (_, _) => SyncViewport();
            VisibleChanged += (_, _) => SyncViewport();
        }

        protected override bool ShowWithoutActivation => true;
        protected override CreateParams CreateParams {
            get {
                var value = base.CreateParams;
                // DirectComposition supplies the complete alpha surface, including fade edges.
                if (_transition) value.ExStyle |= 0x00200000 | 0x80; // NOREDIRECTIONBITMAP | TOOLWINDOW
                if (_presentationPolicy.NonActivating) value.ExStyle |= 0x08000000; // NOACTIVATE
                return value;
            }
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            if (!_transition) base.OnPaintBackground(e);
        }

        internal bool Ready { get { return _ready && !_disposed; } }
        internal bool Active { get { return _active && Ready; } }
        internal int SessionGeneration { get; private set; }
        // transition 端点保留既有 [HelpSurface] 日志标签，不随面板 profile 漂移。
        private string LogTag => _transition ? "[HelpSurface]" : _profile.LogTag;

        private bool Stale(int version) => _disposed || version != _prepareVersion || IsDisposed;

        // 必须在 UI 线程调用。失败记录日志并抛出；Retire/Dispose 后晚到的
        // await 完成不得复活旧 controller。
        internal async Task PrepareAsync()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(CompositionHelpSurface));
            if (InvokeRequired) throw new InvalidOperationException("PrepareAsync must run on the surface UI thread.");
            int version = unchecked(++_prepareVersion);
            _ready = false; _active = false; _closePending = false;
            TearDownEndpoint();
            try {
                var environment = await FixedWebViewRuntime.CreateAsync(_profileRoot);
                if (Stale(version)) { throw new ObjectDisposedException(nameof(CompositionHelpSurface)); }
                _environment = environment;
                _scene = CompositionSceneHost.Create(Handle);
                var controller = await environment.CreateCoreWebView2CompositionControllerAsync(Handle);
                if (Stale(version)) { controller.Close(); throw new ObjectDisposedException(nameof(CompositionHelpSurface)); }
                _web = controller;
                _web.IsVisible = false; // Hidden preheat never grants presentation.
                _web.Bounds = DeviceClientRectangle();
                _web.DefaultBackgroundColor = Color.Transparent;
                _web.ShouldDetectMonitorScaleChanges = false;
                _web.RasterizationScale = 1;
                _web.BoundsMode = CoreWebView2BoundsMode.UseRawPixels;
                var core = _web.CoreWebView2;
                FixedWebViewRuntime.ValidateCore(core);
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.IsZoomControlEnabled = false;
                core.Settings.AreBrowserAcceleratorKeysEnabled = false;
                IntPtr visual = _scene.AcquireVisual(2);
                try { _webVisual = Marshal.GetObjectForIUnknown(visual); _web.RootVisualTarget = _webVisual; }
                finally { Marshal.Release(visual); }
                core.SetVirtualHostNameToFolderMapping(_hostName, _webRoot, CoreWebView2HostResourceAccessKind.DenyCors);
                core.NavigationStarting += OnNavigationStarting;
                core.NewWindowRequested += (_, args) => args.Handled = true;
                core.DownloadStarting += (_, args) => args.Cancel = true;
                core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                core.WebResourceRequested += OnWebResourceRequested;
                _readyTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                _endpointCore=core;
                if(System.Threading.Interlocked.Increment(ref _controllerGeneration)<=0)throw new InvalidOperationException("Controller generation exhausted");
                RegisterEndpointCallbacks();
                core.Navigate(_pageUrl);
                var ready = _readyTcs.Task;
                var timeout = Task.Delay(15000);
                if (await Task.WhenAny(ready, timeout) != ready)
                    throw new TimeoutException(
                        (_transition ? "scene_transition_ready" : _profile.ReadyMessageType)
                        + " not received within 15s");
                await ready;
                if (Stale(version)) throw new ObjectDisposedException(nameof(CompositionHelpSurface));
                _ready = true;
                SyncViewport();
                LogManager.Log(LogTag + " prepare ready gen=" + SessionGeneration);
            } catch (Exception error) {
                if (!Stale(version)) LogManager.Log(LogTag + " prepare failed: " + error);
                throw;
            }
        }

        internal bool ResumePanel(Rectangle rect)
        {
            if (!Ready || _web == null) return false;
            SessionGeneration++;
            Owner = _owner;
            Bounds = rect;
            _active = true;
            _closePending = false;
            if (!Visible) Show();
            SyncViewport();
            // 仅当前台已属本进程窗口（游戏/owner 同进程）才允许激活；
            // 外部前台窗口时不抢焦点。
            if (!_presentationPolicy.NonActivating && ForegroundIsSameProcess()) {
                Activate();
                _web.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
            }
            LogManager.Log(LogTag + " resume gen=" + SessionGeneration + " rect=" + rect);
            return true;
        }

        internal bool TryPost(string json)
        {
            if (_transition) return TryPostTransitionPanel(json);
            if (!Active || _web == null) return false;
            var message = JObject.Parse(json);
            string? type = message.Value<string>("type");
            if (type == "panel_cmd")
            {
                if (message.Value<string>("panel") != _profile.PanelName) return false;
                if (message.Value<string>("cmd") == "open")
                {
                    string? instance = message["initData"]?.Value<string>("panelInstanceId");
                    if (string.IsNullOrEmpty(instance)) return false;
                    BindEndpointSession(instance);
                }
            }
            else if (type == "tutorial_preference_result")
            {
                if (!_profile.AllowTutorialPreference
                    || !HelpTutorialPreferenceCommand.IsResultFor(message, _panelInstance)) return false;
            }
            else if (type == "panel_resp")
            {
                // 只读查询回包：面板名匹配 + 当前会话活跃；回包不带 panelInstanceId，
                // 会话边界由 AcceptsPanelResponses 面板的活跃窗口承担。
                if (!_profile.AcceptsPanelResponses
                    || message.Value<string>("panel") != _profile.PanelName
                    || message["callId"]?.Type != JTokenType.String) return false;
            }
            else if (type != "panel_viewport_set" && type != "panel_esc") return false;
            _web.CoreWebView2.PostWebMessageAsJson(json);
            return true;
        }

        internal void RepositionPanel(Rectangle rect, bool ensureVisible)
        {
            if (_disposed) return;
            Bounds = rect;
            if (ensureVisible && !Visible) Show();
            SyncViewport();
        }

        internal bool CommitGeometry(Rectangle rect, int generation)
        {
            if (!Active || generation != SessionGeneration || _scene == null) return false;
            Bounds = rect;
            _committed = rect;
            SyncViewport();
            return true;
        }

        internal void ClearGeometry(string reason)
        {
            _committed = Rectangle.Empty;
            if (!_disposed && _scene != null) SyncViewport();
            LogManager.Log(LogTag + " geometry cleared: " + reason);
        }

        internal bool Replay(Rectangle rect, int generation, string reason)
        {
            if (!Active || generation != SessionGeneration || _scene == null || _committed != rect) return false;
            Bounds = _committed;
            if (!Visible) Show();
            SyncViewport();
            LogManager.Log(LogTag + " geometry replayed: " + reason);
            return true;
        }

        internal void Retire()
        {
            if (_disposed) return;
            System.Threading.Interlocked.Increment(ref _endpointSessionGeneration);
            System.Threading.Interlocked.Increment(ref _controllerGeneration);
            DetachEndpointCallbacks();
            _pendingHostClose=null;
            unchecked { _prepareVersion++; }
            _ready = false; _active = false; _closePending = false; _committed = Rectangle.Empty;
            _closeTimer.Stop(); _panelInstance = ""; _pressedButtons = 0; _closeEnvelope = null;
            _capturedButton = false; Capture = false;
            TearDownEndpoint();
            if (Visible) Hide();
            LogManager.Log(LogTag + " retired gen=" + SessionGeneration);
        }

        // The transition is a separate fixed projection endpoint; it never enters panel pause/snapshot.
        internal bool PresentTransition(Rectangle rect, bool backgroundQualified = false) {
            using var latency = CF7Launcher.Diagnostic.InputLatencyProbe.Measure("surface_present");
            if (!_transition || !Ready || _web == null
                || !_presentationPolicy.CanPresentSurface(_owner.Visible,_owner.WindowState==FormWindowState.Minimized,
                    CanRestoreGameFocus,backgroundQualified)) return false;
            _backgroundTransition = _presentationPolicy.NonActivating && backgroundQualified;
            if (!_active) return ResumePanel(rect) && CommitGeometry(rect, SessionGeneration);
            _committed = rect;
            if (Bounds != rect) Bounds = rect;
            if (!Visible) {
                Show();
                if (!_presentationPolicy.NonActivating) { Activate(); _web.MoveFocus(CoreWebView2MoveFocusReason.Programmatic); }
            }
            SyncViewport();
            return true;
        }
        internal bool PostTransition(JObject message) {
            if (!_transition || !Active || _web == null || message.Value<string>("type") != "scene_transition") return false;
            _web.CoreWebView2.PostWebMessageAsJson(message.ToString(Newtonsoft.Json.Formatting.None));
            return true;
        }
        internal void HideTransition() {
            if (!_transition || _disposed) return;
            _active = false; _committed = Rectangle.Empty;
            _backgroundTransition = false;
            _pressedButtons = 0; _capturedButton = false; Capture = false;
            if (Visible) Hide();
            SyncViewport();
        }
        internal void SuppressTransition() {
            _backgroundTransition = false;
            if (_transition && !_disposed && Visible) { _pressedButtons = 0; _capturedButton = false; Capture = false; Hide(); SyncViewport(); }
        }
        internal void RaiseTransition() {
            if (_transition && Active && Visible && (CanRestoreGameFocus || _backgroundTransition))
                SceneTransitionWindowOrder.RaiseIfCovered(this, _owner,preserveForeignOrder:_presentationPolicy.NonActivating);
        }
        internal bool TransitionInputReleased => _pressedButtons == 0
            && (GetAsyncKeyState(0x01) | GetAsyncKeyState(0x02) | GetAsyncKeyState(0x0D) | GetAsyncKeyState(0x20)) >= 0;

        // 仅本窗、原 owner，或转场构造时绑定且仍由该 owner 持有的可见 backing。
        // 不把其他同进程窗口当作游戏输入所有者。
        internal bool CanRestoreGameFocus => CaptureGameForeground()!=IntPtr.Zero;
        internal IntPtr CaptureGameForeground()
        {
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return IntPtr.Zero;
            if (foreground == Handle || GetAncestor(foreground, 2) == Handle) return foreground;
            if (_owner != null && !_owner.IsDisposed
                && (foreground == _owner.Handle || GetAncestor(foreground, 2) == _owner.Handle)) return foreground;
            if (_transition && _transitionBacking != null && !_transitionBacking.IsDisposed
                && _transitionBacking.IsHandleCreated && _transitionBacking.Visible
                && ReferenceEquals(_transitionBacking.Owner, _owner)
                && (foreground == _transitionBacking.Handle
                    || GetAncestor(foreground, 2) == _transitionBacking.Handle)) return foreground;
            return IntPtr.Zero;
        }

        private bool ForegroundIsSameProcess()
        {
            return CaptureGameForeground()!=IntPtr.Zero;
        }

        private Rectangle DeviceClientRectangle()
        {
            // PerMonitorV2 下 ClientSize 即设备像素。
            return new Rectangle(0, 0, Math.Max(1, ClientSize.Width), Math.Max(1, ClientSize.Height));
        }

        private void SyncViewport()
        {
            using var latency = CF7Launcher.Diagnostic.InputLatencyProbe.Measure("surface_viewport");
            if (_disposed || IsDisposed) return;
            var bounds = DeviceClientRectangle();
            if (_web != null && _web.Bounds != bounds) _web.Bounds = bounds;
            // Showing a WinForms host does not show a composition controller that
            // was created while hidden. Pair browser visibility with the live surface.
            if (_web != null)
            {
                bool visible = Active && Visible && _owner.Visible
                    && _owner.WindowState != FormWindowState.Minimized;
                if (_web.IsVisible != visible)
                {
                    _web.IsVisible = visible;
                    LogManager.Log(LogTag + " controller visible=" + visible
                        + " gen=" + SessionGeneration);
                }
            }
            if (Active && _web != null
                && (_postedViewport != bounds || _postedViewportGeneration != SessionGeneration))
            {
                _web.CoreWebView2.PostWebMessageAsJson(new JObject {
                    ["type"] = "panel_viewport_set", ["w"] = bounds.Width, ["h"] = bounds.Height
                }.ToString(Newtonsoft.Json.Formatting.None));
                _postedViewport = bounds;
                _postedViewportGeneration = SessionGeneration;
            }
            // Presentation already commits and waits for native completion. A 25ms
            // transition tick must not repeat that UI-thread fence at unchanged size.
            // Browser visibility and WebView's own frame submissions remain independent.
            if (_scene != null && _presentedViewport != bounds) {
                _scene.Presentation(false, false, bounds.Width, bounds.Height);
                _presentedViewport = bounds;
            }
        }

        private void OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs args)
        {
            if (args.Uri != _pageUrl) args.Cancel = true;
        }

        private void OnWebResourceRequested(object? sender, CoreWebView2WebResourceRequestedEventArgs args)
        {
            // 仅放行同 origin 文件；不读游戏 save，不响应外链/下载。
            if (_environment == null
                || !args.Request.Uri.StartsWith("https://" + _hostName + "/", StringComparison.Ordinal)) {
                args.Response = _environment?.CreateWebResourceResponse(
                    Stream.Null, 403, "panel origin only", "Content-Type: text/plain");
                return;
            }
        }

        private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
        {
            if (_disposed || _web == null || !ReferenceEquals(sender, _web.CoreWebView2)
                || args.Source != _pageUrl) return;
            JObject message;
            try { message = JObject.Parse(args.WebMessageAsJson); }
            catch { return; }
            DispatchPanelEnvelope(message);
        }
#if CF7_TEST_SEAMS
        internal void DispatchEnvelopeForRecheck(JObject message)
            => DispatchPanelEnvelope(message);
#endif
        private void DispatchPanelEnvelope(JObject message)
        {
            if(message?["type"]?.Type!=JTokenType.String)return;
            string? type = message.Value<string>("type");
            if (type == (_transition ? "scene_transition_ready" : _profile.ReadyMessageType)) {
                _readyTcs?.TrySetResult(true);
                return;
            }
            if (_transition) {
                if (Active && IsTransitionMessageType(type))
                    TransitionMessage?.Invoke(message);
                else if (Active && (IsSettlementMessage(message,_panelInstance)
                    || type=="panel-toast" && _panelInstance.Length>0 && message["html"]?.Type==JTokenType.String
                        && message.Value<string>("html").Length<=4096))
                    SettlementMessage?.Invoke(message);
                return;
            }
            if (type == "tutorial_preference" && _profile.AllowTutorialPreference
                && Active && _panelInstance.Length > 0) {
                var result = TutorialPreferenceRequested?.Invoke(message, _panelInstance);
                if (result != null) TryPost(result.ToString(Newtonsoft.Json.Formatting.None));
                return;
            }
            // 页面关闭请求：等物理鼠标键与 ESC 全部释放后才上抛关闭，
            // 避免在按下手势中途触发关闭重入。
            if(type=="panel" && message["cmd"]?.Type==JTokenType.String && (string)message["cmd"]=="close") {
                if(message["panel"]?.Type==JTokenType.String && (string)message["panel"]==_profile.PanelName
                    && message["panelInstanceId"]?.Type==JTokenType.String && (string)message["panelInstanceId"]==_panelInstance
                    && Active && _panelInstance.Length>0 && message["nativeCause"]==null && message["hostCloseReason"]==null)
                    RequestClose("page_close",message);
                return;
            }
            // 委托面板（intelligence）的其余入站消息：只读查询与 panel-toast，
            // 绑定当前面板名与活跃会话后交给 controller 配置的既有 Web 权威。
            if (_profile.DelegateCloseToAuthority && Active && _panelInstance.Length > 0) {
                if (type == "panel" && message["panel"]?.Type==JTokenType.String && (string)message["panel"]==_profile.PanelName
                    && message["cmd"]?.Type==JTokenType.String && IsIntelligenceQuery((string)message["cmd"]))
                    InboundPanelMessage?.Invoke(message);
                else if (type == "panel-toast" && message["html"]?.Type == JTokenType.String
                    && message.Value<string>("html").Length <= 4096)
                    InboundPanelMessage?.Invoke(message);
            }
        }

        internal static bool IsTransitionMessageType(string type) => type is
            "scene_transition_presented" or "scene_transition_action" or "scene_transition_report_view";

        internal event Action<JObject> SettlementMessage;
        internal string SettlementInstance => _transition ? _panelInstance : "";
        internal bool TryPostTransitionPanel(string json) {
            if (!_transition || !Active || _web == null) return false;
            JObject p;
            try { p=JObject.Parse(json); } catch { return false; }
            string type=p.Value<string>("type");
            if(type=="panel_cmd") {
                if(p.Value<string>("panel")!="loot") return false;
                if(p.Value<string>("cmd")=="open") {
                    string instance=p["initData"]?.Value<string>("panelInstanceId");
                    if(string.IsNullOrEmpty(instance) || _panelInstance.Length>0 && _panelInstance!=instance) return false;
                    BindEndpointSession(instance);
                } else if(p.Value<string>("panelInstanceId")!=_panelInstance || _panelInstance.Length==0) return false;
            } else if(type is "panel_resp" or "scene_transition_report_restore") {
                if(p.Value<string>("panelInstanceId")!=_panelInstance || _panelInstance.Length==0) return false;
            } else if(type=="scene_transition_complete") {
                if(_panelInstance.Length==0) return false;
            } else if(type is not ("panel_viewport_set" or "panel_esc")) return false;
            _web.CoreWebView2.PostWebMessageAsJson(json);
            return true;
        }
        internal void ReleaseSettlementBinding() { if(_transition) { _panelInstance=""; Interlocked.Increment(ref _endpointSessionGeneration); RegisterEndpointCallbacks(); } }
        internal static bool IsSettlementMessage(JObject p,string instance) {
            if(p==null || string.IsNullOrEmpty(instance) || p["panelInstanceId"]?.Type!=JTokenType.String
                || p.Value<string>("panelInstanceId")!=instance) return false;
            string text(string key) => p[key]?.Type==JTokenType.String ? p.Value<string>(key) : null;
            string type=text("type");
            return type=="task" && text("task")=="loot_request"
                || type=="panel" && text("panel")=="loot"
                    && (text("domain")=="inventory" || text("cmd")=="close")
                || type=="scene_transition_report_presented";
        }

        private void OnWebProcessFailed(object? sender, CoreWebView2ProcessFailedEventArgs args)
        {
            if (_web == null || !ReferenceEquals(sender, _web.CoreWebView2)) return;
            LogManager.Log(LogTag + " web process failed: " + args.ProcessFailedKind);
            if (_transition) { _ready = false; TransitionFailed?.Invoke(); return; }
            RequestClose("process_failed:" + args.ProcessFailedKind);
        }

        private void OnAcceleratorKey(object? sender, CoreWebView2AcceleratorKeyPressedEventArgs args)
        {
            if (args.VirtualKey == VkEscape)
            {
                args.Handled = true;
                if (!_transition && args.KeyEventKind == CoreWebView2KeyEventKind.KeyUp)
                    RequestClose("esc");
            }
        }

        protected override void OnActivated(EventArgs e)
        {
            base.OnActivated(e);
            if (!_presentationPolicy.NonActivating && Active && _web != null)
                _web.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
        }

        protected override void OnDeactivate(EventArgs e)
        {
            base.OnDeactivate(e);
            // 普通阅读面板切到其他应用时保留当前会话和阅读位置，与地图一致。
            // 不关闭、不重开，也不申请焦点；实际捕获丢失和进程故障仍走独立清理。
            // 只有转场继续在前台归属稳定后抑制显示。
            if (!_transition || _disposed || IsDisposed || !IsHandleCreated) return;
            var lease=CaptureEndpointLease();
            BeginInvoke((Action)(() => {
                if (_disposed || !_active || IsDisposed || !IsLeaseCurrent(lease)) return;
                if (!ForegroundIsOurs() && !_backgroundTransition) { Hide(); SyncViewport(); }
            }));
        }

        private bool ForegroundIsOurs()
        {
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return false;
            if (foreground == Handle || GetAncestor(foreground, 2) == Handle) return true;
            if (_owner != null && !_owner.IsDisposed
                && (foreground == _owner.Handle || GetAncestor(foreground, 2) == _owner.Handle)) return true;
            GetWindowThreadProcessId(foreground, out uint pid);
            return pid == Environment.ProcessId;
        }

        private void RequestClose(string reason, JObject? envelope = null)
        {
            if (_transition) return;
            if (_disposed || !_active || _closePending) return;
            _closePending = true;
            _closeReason = reason;
            _closeEnvelope = envelope;
            QueueHostClose(reason,envelope);
        }

        private void TryDeliverClose()
        {
            if(_pendingHostClose!=null)DeliverHostClose(_pendingHostClose);
        }

        protected override void WndProc(ref Message m)
        {
            if (_presentationPolicy.NonActivating) {
                SceneTransitionWindowOrder.ConstrainBackgroundShow(ref m,this,_owner);
                if (m.Msg == WmMouseActivate) { m.Result = new IntPtr(4); return; } // MA_NOACTIVATEANDEAT
            }
            bool input = m.Msg is WmMouseMove or WmMouseLeave or WmLButtonDown
                or WmLButtonUp or WmRButtonDown or WmRButtonUp or WmMouseWheel
                or WmLButtonDoubleClick or WmRButtonDoubleClick;
            if (input && (!Active || _committed.IsEmpty || _closePending))
            { base.WndProc(ref m); return; }
            switch (m.Msg) {
                case WmMouseActivate:
                    // 外部首击只激活并吞掉；不向页面伪造 click/up。
                    if (GetAncestor(GetForegroundWindow(), 2) != Handle) {
                        m.Result = new IntPtr(MaActivateAndEat);
                        return;
                    }
                    break;
                case WmMouseMove:
                    using (CF7Launcher.Diagnostic.InputLatencyProbe.Measure("web_input"))
                        if (_web != null) _web.SendMouseInput(CoreWebView2MouseEventKind.Move, MouseKeys(m.WParam), 0, MousePoint(m.LParam));
                    EnsureLeaveTracking();
                    break;
                case WmMouseLeave:
                    _trackingLeave = false;
                    if (_web != null) _web.SendMouseInput(CoreWebView2MouseEventKind.Leave, CoreWebView2MouseEventVirtualKeys.None, 0, Point.Empty);
                    break;
                case WmLButtonDown:
                case WmRButtonDown:
                case WmLButtonDoubleClick:
                case WmRButtonDoubleClick:
                    bool left = m.Msg is WmLButtonDown or WmLButtonDoubleClick;
                    _pressedButtons |= left ? 1 : 2;
                    _capturedButton = true;
                    _captureEndpointLease=CaptureEndpointLease();
                    Capture = true;
                    if (_web != null) _web.SendMouseInput(
                        left ? CoreWebView2MouseEventKind.LeftButtonDown : CoreWebView2MouseEventKind.RightButtonDown,
                        MouseKeys(m.WParam), 0, MousePoint(m.LParam));
                    break;
                case WmLButtonUp:
                case WmRButtonUp:
                    int released = m.Msg == WmLButtonUp ? 1 : 2;
                    if ((_pressedButtons & released) == 0) break;
                    _pressedButtons &= ~released;
                    if (_web != null) _web.SendMouseInput(
                        m.Msg == WmLButtonUp ? CoreWebView2MouseEventKind.LeftButtonUp : CoreWebView2MouseEventKind.RightButtonUp,
                        MouseKeys(m.WParam), 0, MousePoint(m.LParam));
                    _capturedButton = _pressedButtons != 0;
                    if (!_capturedButton) Capture = false;
                    if (_closePending) {
                        var pending=_pendingHostClose;
                        if(pending!=null)BeginInvoke((Action)(()=>DeliverHostClose(pending)));
                    }
                    break;
                case WmMouseWheel:
                    if (_web != null) _web.SendMouseInput(CoreWebView2MouseEventKind.Wheel,
                        MouseKeys(m.WParam), WheelDelta(m.WParam), PointToClient(MousePosition));
                    break;
                case WmCaptureChanged:
                    if (_capturedButton && !Capture && IsLeaseCurrent(_captureEndpointLease)) {
                        // 捕获被外部夺走：不合成 up，直接请求关闭。
                        _capturedButton = false;
                        RequestClose("capture_lost");
                    }
                    break;
            }
            // Composition owns these messages. Do not also dispatch WinForms mouse
            // focus/parent-wheel handling after delivery to the Web endpoint.
            if (input) { m.Result = IntPtr.Zero; return; }
            base.WndProc(ref m);
        }

        private void EnsureLeaveTracking()
        {
            if (_trackingLeave) return;
            var track = new TRACKMOUSEEVENT {
                Size = (uint)Marshal.SizeOf<TRACKMOUSEEVENT>(),
                Flags = 0x00000002, // TME_LEAVE
                Track = Handle
            };
            _trackingLeave = TrackMouseEvent(ref track);
        }

        private static Point MousePoint(IntPtr lParam)
        {
            int value = lParam.ToInt32();
            return new Point((short)(value & 0xFFFF), (short)((value >> 16) & 0xFFFF));
        }

        private static uint WheelDelta(IntPtr wParam) => unchecked((uint)(int)(short)((wParam.ToInt64() >> 16) & 0xFFFF));

        private static CoreWebView2MouseEventVirtualKeys MouseKeys(IntPtr wParam)
        {
            int mk = (int)(wParam.ToInt64() & 0xFFFF);
            var keys = CoreWebView2MouseEventVirtualKeys.None;
            if ((mk & 0x01) != 0) keys |= CoreWebView2MouseEventVirtualKeys.LeftButton;
            if ((mk & 0x02) != 0) keys |= CoreWebView2MouseEventVirtualKeys.RightButton;
            if ((mk & 0x04) != 0) keys |= CoreWebView2MouseEventVirtualKeys.Shift;
            if ((mk & 0x08) != 0) keys |= CoreWebView2MouseEventVirtualKeys.Control;
            if ((mk & 0x10) != 0) keys |= CoreWebView2MouseEventVirtualKeys.MiddleButton;
            return keys;
        }

        private void TearDownEndpoint()
        {
            DetachEndpointCallbacks();
            _endpointCore=null;
            _presentedViewport = _postedViewport = Rectangle.Empty;
            _postedViewportGeneration = -1;
            if (_web != null) {
                var core = _web.CoreWebView2;
                core.NavigationStarting -= OnNavigationStarting;
                core.WebResourceRequested -= OnWebResourceRequested;
                core.ProcessFailed -= OnWebProcessFailed;
                core.WebMessageReceived -= OnWebMessage;
                _web.AcceleratorKeyPressed -= OnAcceleratorKey;
                _web.RootVisualTarget = null;
                _web.Close();
                _web = null;
            }
            if (_webVisual != null && Marshal.IsComObject(_webVisual)) Marshal.ReleaseComObject(_webVisual);
            _webVisual = null;
            _scene?.Dispose();
            _scene = null;
            _environment = null;
            _readyTcs?.TrySetCanceled();
            _readyTcs = null;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !_disposed) {
                _disposed = true;
                _closeTimer.Dispose();
                unchecked { _prepareVersion++; }
                // Dispose 必须落在 UI 线程；跨线程且句柄已建时同步封送。
                // 句柄未建说明从未 Prepare，无线程关联资源可清。
                if (IsHandleCreated && InvokeRequired)
                    Invoke((Action)TearDownEndpoint);
                else if (!InvokeRequired)
                    TearDownEndpoint();
            }
            base.Dispose(disposing);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TRACKMOUSEEVENT
        {
            public uint Size;
            public uint Flags;
            public IntPtr Track;
            public uint HoverTime;
        }

        [DllImport("user32.dll")] private static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT value);
        [DllImport("user32.dll", EntryPoint="GetForegroundWindow")] private static extern IntPtr NativeGetForegroundWindow();
#if CF7_TEST_SEAMS
        internal Func<IntPtr>? ForegroundReaderForRecheck;
#endif
        private IntPtr GetForegroundWindow()
        {
#if CF7_TEST_SEAMS
            if (ForegroundReaderForRecheck != null) return ForegroundReaderForRecheck();
#endif
            return NativeGetForegroundWindow();
        }
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    }
}
