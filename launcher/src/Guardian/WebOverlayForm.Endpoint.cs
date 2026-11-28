using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Guardian
{
    // This binding belongs to one Host-selected document and panel instance.
    // Page messages carry only editor identity and focus facts, never field values.
    internal sealed class WebTextFocusBinding
    {
        internal const string MessageType = "ui_field_focus";
        private readonly ITextInputAuthority _authority;
        private readonly string _prefix;
        private readonly IReadOnlyDictionary<string, string> _selectors;
        private readonly Dictionary<string, long> _generations = new(StringComparer.Ordinal);
        private readonly string _documentToken = Guid.NewGuid().ToString("N");
        private readonly long _installSerial = TextInputClaim.NextFocusSerial();
        private long _focusTurn;
        private string _focusedEndpoint;
        private TextInputClaim _claim;
        private TextExitReceipt? _lastExit;

        internal WebTextFocusBinding(ITextInputAuthority authority, string instance, string prefix,
            IReadOnlyDictionary<string, string> selectors = null)
        {
            _authority = authority;
            PanelInstanceId = instance;
            _prefix = prefix;
            _selectors = selectors;
        }

        internal string PanelInstanceId { get; }
        internal long FocusTurn => _focusTurn;
        internal bool ImeComposing { get; private set; }

        internal Task InstallAsync(CoreWebView2 core, string source) =>
            InstallAsync(core.ExecuteScriptAsync, source, frame: false);

        internal Task InstallAsync(CoreWebView2Frame coreFrame, string source) =>
            InstallAsync(coreFrame.ExecuteScriptAsync, source, frame: true);

        private async Task InstallAsync(Func<string, Task<string>> execute, string source, bool frame)
        {
            var binding = new JObject
            {
                ["source"] = source,
                ["instance"] = PanelInstanceId,
                ["token"] = _documentToken,
                ["serial"] = _installSerial.ToString(CultureInfo.InvariantCulture),
                ["prefix"] = _prefix,
                ["frame"] = frame,
                ["selectors"] = _selectors == null ? null : JObject.FromObject(_selectors)
            };
            try
            {
                await execute(InstallScript + "("
                    + binding.ToString(Newtonsoft.Json.Formatting.None) + ")");
            }
            catch (InvalidOperationException) { }
            catch (COMException) { }
        }

        internal void Observe(JObject message, IntPtr root, IntPtr editor, bool requestGameOnBlur)
        {
            if (StringField(message, "type") != MessageType
                || StringField(message, "panelInstanceId") != PanelInstanceId
                || StringField(message, "documentToken") != _documentToken
                || message["focusTurn"] is not JValue { Value: long turn }
                || turn <= 0 || turn > 9007199254740991L
                || message["focused"]?.Type != JTokenType.Boolean
                || message["composing"]?.Type != JTokenType.Boolean)
                return;

            string endpoint = StringField(message, "endpointId");
            if (!AcceptsEndpoint(endpoint)) return;
            string phase = StringField(message, "phase");
            bool focused = (bool)message["focused"];
            bool composing = (bool)message["composing"];
            if (phase == "focusin")
            {
                if (!focused || turn <= _focusTurn || root == IntPtr.Zero || editor == IntPtr.Zero) return;
                if (!_generations.TryGetValue(endpoint, out long generation))
                    _generations.Add(endpoint, generation = _authority.NextInstanceGeneration(endpoint));
                string session = _authority.CurrentSessionId;
                var observation = new TextFocusObservation(session, root, editor,
                    TextInputClaim.NextFocusSerial(), LocalFocusConfirmed: true, ImeComposing: composing);
                if (_authority.AcquireText(endpoint, generation, observation) is not { } lease) return;
                _focusTurn = turn;
                _focusedEndpoint = endpoint;
                _claim = new TextInputClaim(_authority, session, lease);
                ImeComposing = composing;
                _lastExit = null;
                return;
            }
            if (turn != _focusTurn || endpoint != _focusedEndpoint) return;
            if (phase == "focusout" && !focused && !composing)
                CaptureExit("web_field_focusout", requestGameOnBlur)?.Invoke();
            else if (focused && phase == "compositionstart" && composing)
                ImeComposing = true;
            else if (focused && phase == "compositionend" && !composing)
                ImeComposing = false;
        }

        internal Action CaptureExit(string reason, bool requestGame, int triggerVk = 0, bool detach = true)
        {
            var captured = _claim;
            if (captured == null)
            {
                if (!requestGame || _lastExit is not { } previous) return null;
                if (detach) _lastExit = null;
                return () =>
                {
                    if (_lastExit == previous) _lastExit = null;
                    _authority.RequestGameKeyboard(previous);
                };
            }

            void ClearCapturedField()
            {
                if (!ReferenceEquals(_claim, captured)) return;
                _claim = null;
                _focusedEndpoint = null;
                ImeComposing = false;
            }
            if (detach) ClearCapturedField();
            var observation = new TextExitObservation(captured.SessionId, TextInputClaim.NextFocusSerial(),
                reason, EditorFocusCleared: true, TriggerVk: triggerVk);
            return () =>
            {
                ClearCapturedField();
                var receipt = captured.Authority.ReleaseText(captured.Lease, observation);
                if (receipt.Status != TextExitStatus.Released) return;
                if (requestGame) captured.Authority.RequestGameKeyboard(receipt);
                else _lastExit = receipt;
            };
        }

        internal TextExitReceipt? TakeExitReceipt()
        {
            var receipt = _lastExit;
            _lastExit = null;
            return receipt;
        }

        private bool AcceptsEndpoint(string endpoint)
        {
            if (endpoint == null || !endpoint.StartsWith(_prefix, StringComparison.Ordinal)) return false;
            string field = endpoint.Substring(_prefix.Length);
            if (_selectors != null) return _selectors.ContainsKey(field);
            if (_prefix == "web.settings." && field == "keys.search") return true;
            // Generated element IDs are local to this document binding.
            return field.StartsWith("field.", StringComparison.Ordinal)
                && int.TryParse(field.AsSpan(6), NumberStyles.None, CultureInfo.InvariantCulture, out int id)
                && id > 0 && field == "field." + id.ToString(CultureInfo.InvariantCulture);
        }

        private static string StringField(JObject message, string name) =>
            message[name]?.Type == JTokenType.String ? (string)message[name] : null;

        internal const string InstallScript = """
            (function (binding) {
                if ((window !== window.top) !== !!binding.frame || location.href !== binding.source || !window.chrome?.webview) return;
                const previous = window.cf7TextFocusBinding;
                if (previous && BigInt(previous.serial) >= BigInt(binding.serial)) return;
                previous?.dispose();
                const host = window.chrome.webview;
                const ids = new WeakMap();
                const nonText = new Set(['button', 'checkbox', 'color', 'file', 'hidden',
                    'image', 'radio', 'range', 'reset', 'submit']);
                let fieldSerial = 0, turn = 0, active = null;
                const imeKeys = new Set();
                const mutations = new MutationObserver(syncFocus);

                function editor() {
                    if (!document.hasFocus()) return null;
                    const node = document.activeElement;
                    if (!node || node.disabled) return null;
                    if (node.tagName === 'INPUT') return nonText.has(node.type) ? null : node;
                    if (node.tagName === 'TEXTAREA') return node;
                    return node.isContentEditable ? node.closest('[contenteditable]') : null;
                }

                function fieldId(node) {
                    if (binding.selectors) {
                        for (const [id, selector] of Object.entries(binding.selectors))
                            if (node.matches(selector)) return id;
                        return null;
                    }
                    if (binding.prefix === 'web.settings.' && node.matches('.settings-key-search'))
                        return 'keys.search';
                    if (!ids.has(node)) ids.set(node, 'field.' + (++fieldSerial));
                    return ids.get(node);
                }

                function report(item, phase, focused) {
                    host.postMessage({
                        type: 'ui_field_focus', panelInstanceId: binding.instance,
                        documentToken: binding.token, endpointId: binding.prefix + item.id,
                        focusTurn: item.turn, phase, focused, composing: focused && item.composing
                    });
                }

                function clearFocus() {
                    const old = active;
                    active = null;
                    mutations.disconnect();
                    if (old) report(old, 'focusout', false);
                }

                function syncFocus() {
                    if (window.cf7TextFocusBinding !== installed) return;
                    const node = editor();
                    if (active?.node === node) return;
                    clearFocus();
                    const id = node && fieldId(node);
                    if (!id || turn >= Number.MAX_SAFE_INTEGER) return;
                    active = { node, id, turn: ++turn, composing: false };
                    mutations.observe(document.documentElement, { childList: true, subtree: true });
                    report(active, 'focusin', true);
                }

                function focusOut(event) {
                    if (active && (active.node === event.target || active.node.contains(event.target))) clearFocus();
                }

                function composition(event) {
                    if (!active || !(active.node === event.target || active.node.contains(event.target))) return;
                    active.composing = event.type === 'compositionstart';
                    report(active, event.type, true);
                }

                function keepImeKeyLocal(event) {
                    if (event.key !== 'Escape' && event.key !== 'Enter') return;
                    if (event.type === 'keydown') {
                        if (event.isComposing || active?.composing) imeKeys.add(event.key);
                        else if (!event.repeat) imeKeys.delete(event.key);
                    }
                    if (!imeKeys.has(event.key)) return;
                    if (event.type === 'keyup') imeKeys.delete(event.key);
                    event.stopImmediatePropagation();
                }

                const installed = { serial: binding.serial, dispose() {
                    active = null;
                    mutations.disconnect();
                    document.removeEventListener('focusin', syncFocus, true);
                    document.removeEventListener('focusout', focusOut, true);
                    document.removeEventListener('compositionstart', composition, true);
                    document.removeEventListener('compositionend', composition, true);
                    window.removeEventListener('focus', syncFocus);
                    window.removeEventListener('blur', clearFocus);
                    window.removeEventListener('keydown', keepImeKeyLocal, true);
                    window.removeEventListener('keyup', keepImeKeyLocal, true);
                }};
                window.cf7TextFocusBinding = installed;
                document.addEventListener('focusin', syncFocus, true);
                document.addEventListener('focusout', focusOut, true);
                document.addEventListener('compositionstart', composition, true);
                document.addEventListener('compositionend', composition, true);
                window.addEventListener('focus', syncFocus);
                window.addEventListener('blur', clearFocus);
                window.addEventListener('keydown', keepImeKeyLocal, true);
                window.addEventListener('keyup', keepImeKeyLocal, true);
                syncFocus();
            })
            """;
    }

    public partial class WebOverlayForm
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(Point point);
        private long _legacyDocumentEpoch;
        private long _legacyControllerEpoch, _legacyHandleEpoch;
        private CoreWebView2 _legacyCallbackCore;
        private EventHandler<CoreWebView2WebMessageReceivedEventArgs> _legacyMessageAdapter;
        private EventHandler<CoreWebView2ProcessFailedEventArgs> _legacyFailureAdapter;
        private EventHandler<CoreWebView2NavigationCompletedEventArgs> _fieldNavigationAdapter;
        private int _managedCloseDepth;
        private HostCloseContext _trustedClose;
        private const string SettingsSearchEndpoint = "web.settings.keys.search";
        private const string OverlayDocumentUrl = "https://overlay.local/overlay.html";
        private ITextInputAuthority _webTextAuthority;
        private IUiPointerAuthority _webPointerAuthority;
        private bool PointerAuthorityBound => _webPointerAuthority != null;
        private int _npcOutsideButtons;
        [DllImport("user32.dll")] private static extern IntPtr GetCapture();
        [DllImport("user32.dll")] private static extern bool ReleaseCapture();
        private ManagedWebField _settingsSearch;
        private PanelHostController _fieldPanelHost;
        private bool _universalTextFocus;
        private WebTextFocusBinding _documentFields;
        private EndpointLease _fieldEndpoint;
        private CoreWebView2Controller _fieldController;
        private EventHandler<object> _fieldLostFocus;
        private PanelHostController _universalPanelHost;
        private sealed record TerminalPage(string Instance, string Source, CoreWebView2 Core, long DocumentEpoch);
        private TerminalPage _terminalPage;
        private CoreWebView2Frame _terminalFrame;
        private string _terminalDocumentSource;
        private WebTextFocusBinding _terminalFields;

        private sealed class ManagedWebField
        {
            internal readonly EndpointLease Endpoint;
            internal readonly CoreWebView2Controller Controller;
            internal readonly long InstanceGeneration;
            internal readonly string DocumentToken = Guid.NewGuid().ToString("N");
            internal long FocusTurn;
            internal TextInputClaim Claim;

            internal ManagedWebField(EndpointLease endpoint, CoreWebView2Controller controller, long generation)
            {
                Endpoint = endpoint;
                Controller = controller;
                InstanceGeneration = generation;
            }
        }

        internal void BindInputAuthority(ITextInputAuthority textAuthority, IUiPointerAuthority pointerAuthority,
            bool enableUniversalTextFocus = false)
        {
            bool universal = enableUniversalTextFocus && textAuthority != null;
            if (_disposed) return;
            _webPointerAuthority = pointerAuthority;
            _inputShield?.SetPointerAuthorityBound(pointerAuthority != null);
            if (ReferenceEquals(_webTextAuthority, textAuthority) && _universalTextFocus == universal) return;
            RetireManagedWebField("web_authority_changed");
            RetireDocumentFields("web_authority_changed");
            _webTextAuthority = textAuthority;
            _universalTextFocus = universal;
            SyncUniversalPanelHost();
            SyncDocumentFields();
        }

        private bool OwnsGameplayPointerWindow(IntPtr window)
        {
            if (window == IntPtr.Zero || !_owner.IsHandleCreated) return false;
            IntPtr root = GetAncestor(window, 2 /* GA_ROOT */);
            return root == _owner.Handle || Control.FromHandle(root) switch
            {
                WorldCompositionSurface world => ReferenceEquals(world.Owner, _owner),
                NativeHudOverlay hud => hud.OwnsBoundFallbackPointer(_owner),
                _ => false
            };
        }

        private IntPtr HitGameplayPointerWindow(Point screen)
        {
            if (!_anchor.IsHandleCreated || !_anchor.Visible || _panelMode
                || !_anchor.RectangleToScreen(_anchor.ClientRectangle).Contains(screen))
                return IntPtr.Zero;
            IntPtr window = WindowFromPoint(screen);
            IntPtr capture = GetCapture();
            if (capture != IntPtr.Zero && capture != window) return IntPtr.Zero;
            if (CaptureTrustedCloseForeground() == IntPtr.Zero) return IntPtr.Zero;
            return OwnsGameplayPointerWindow(window) ? window : IntPtr.Zero;
        }

        private bool RouteInteractionPress(Point screen, int message, uint data, Action<int, int, int> probe)
        {
            if (!PointerAuthorityBound)
            {
                probe(screen.X, screen.Y, message);
                return false;
            }
            if (HitGameplayPointerWindow(screen) == IntPtr.Zero) return false;
            if (_notchFallback is NativeHudOverlay hud)
            {
                int button = WorldHudPointerRouter.ButtonBit(message, data);
                if ((_npcOutsideButtons & button) != 0) return true;
                // The HUD owns the exact ticket and any paired release for this outside press.
                if (hud.TryRouteBoundNpcOutside(screen, button, () => _npcOutsideButtons |= button,
                    () => probe(screen.X, screen.Y, message))) return true;
            }

            probe(screen.X, screen.Y, message);
            return false;
        }

        private bool ConsumeNpcOutsideRelease(int message, uint data)
        {
            if (_npcOutsideButtons == 0 || !WorldHudPointerRouter.IsUp(message)) return false;
            int button = WorldHudPointerRouter.ButtonBit(message, data);
            if ((_npcOutsideButtons & button) == 0) return false;
            _npcOutsideButtons &= ~button;
            return true;
        }

        private bool RouteInteractionWheel(Point screen, int delta, Func<int, int, int, bool> probe)
        {
            if (!PointerAuthorityBound) return probe?.Invoke(screen.X, screen.Y, delta) == true;
            IntPtr window = HitGameplayPointerWindow(screen);
            if (window == IntPtr.Zero) return false;
            // The no-activate fallback HUD may be under the cursor while its owner
            // receives WM_MOUSEWHEEL. Return immediately if the HUD claims the edge.
            if (Control.FromHandle(window) is NativeHudOverlay hud && hud.OwnsBoundFallbackPointer(_owner)
                && hud.TryRouteBoundFallbackWheel(screen, delta)) return true;
            // P routes pinned Tooltip through MainHudInput. Only the floating
            // inspection probe stays here, since it has no interactive HWND hit.
            return _notchFallback is NativeHudOverlay main && !main.HasPinnedTooltip()
                && probe?.Invoke(screen.X, screen.Y, delta) == true;
        }

        internal bool LivePanelEndpointAvailable => !_disposed && _webReady && _panelMode;
        internal EndpointLease CaptureEndpointLease(string panel, string instance, string lifetime)
        {
            if(_disposed || _webView?.CoreWebView2==null)return null;
            return new EndpointLease(this,_webView,_webView.CoreWebView2,panel,instance,lifetime,
                _legacyControllerEpoch,_panelSessionGeneration,_legacyHandleEpoch,IsHandleCreated ? Handle : IntPtr.Zero,_legacyDocumentEpoch,
                _owner?.IsHandleCreated==true ? _owner.Handle : IntPtr.Zero);
        }
        internal bool IsEndpointCurrent(EndpointLease lease) => lease!=null && !_disposed && _webReady
            && ReferenceEquals(lease.Surface,this) && ReferenceEquals(lease.Controller,_webView)
            && ReferenceEquals(lease.Core,_webView?.CoreWebView2) && lease.ControllerGeneration==_legacyControllerEpoch
            && lease.HandleEpoch==_legacyHandleEpoch && lease.Handle==(IsHandleCreated ? Handle : IntPtr.Zero)
            && lease.DocumentEpoch==_legacyDocumentEpoch
            && lease.SessionGeneration==_panelSessionGeneration && (_panelHost==null ||
                lease.Panel==_panelHost.ActivePanelName && lease.Instance==_panelHost.ActivePanelInstanceId);
        protected override void OnHandleCreated(EventArgs e)
        {
            Interlocked.Increment(ref _legacyHandleEpoch);
            base.OnHandleCreated(e);
            if (_webTextAuthority != null && !_disposed && _legacyCallbackCore != null)
                RegisterLegacyEndpointCallbacks();
        }
        protected override void OnHandleDestroyed(EventArgs e)
        {
            Interlocked.Increment(ref _legacyHandleEpoch);
            RetireActiveEndpointInput("web_handle_destroyed");
            if (_universalPanelHost != null) _universalPanelHost.PanelChanged -= OnUniversalPanelChanged;
            _universalPanelHost = null;
            base.OnHandleDestroyed(e);
        }
        private void RegisterLegacyEndpointCallbacks()
        {
            RetireActiveEndpointInput("web_registration_changed");
            if(_legacyCallbackCore!=null) {
                if(_legacyMessageAdapter!=null)_legacyCallbackCore.WebMessageReceived-=_legacyMessageAdapter;
                if(_legacyFailureAdapter!=null)_legacyCallbackCore.ProcessFailed-=_legacyFailureAdapter;
                if(_fieldNavigationAdapter!=null)_legacyCallbackCore.NavigationCompleted-=_fieldNavigationAdapter;
                _legacyCallbackCore.FrameCreated -= OnTerminalFrameCreated;
            }
            if (_terminalPage != null && _terminalPage.DocumentEpoch != _legacyDocumentEpoch) ClearTerminalPage();
            SyncUniversalPanelHost();
            var core=_webView?.CoreWebView2; var controller=_webView;
            if(core==null)return;
            long generation=_legacyControllerEpoch, document=_legacyDocumentEpoch, handleEpoch=_legacyHandleEpoch;
            long session=_panelSessionGeneration;
            bool current() => !_disposed && ReferenceEquals(controller,_webView)
                && ReferenceEquals(core,_webView?.CoreWebView2) && generation==_legacyControllerEpoch
                && document==_legacyDocumentEpoch && session==_panelSessionGeneration && handleEpoch==_legacyHandleEpoch;
            _legacyMessageAdapter=(sender,args)=> {
                if(!current() || !ReferenceEquals(sender,core))return;
                JObject message; try { message=JObject.Parse(args.WebMessageAsJson); } catch { return; }
                string type = message["type"]?.Type == JTokenType.String ? (string)message["type"] : null;
                if (type == WebTextFocusBinding.MessageType)
                {
                    if (_webTextAuthority != null && args.Source == OverlayDocumentUrl)
                    {
                        if (_universalTextFocus)
                        {
                            if (_documentFields != null && IsDocumentFieldEndpointCurrent(_fieldEndpoint))
                                _documentFields.Observe(message, _fieldEndpoint.OwnerRoot, ObserveWebEditorWindow(),
                                    requestGameOnBlur: true);
                        }
                        else OnManagedWebFieldFocus(message);
                    }
                    return;
                }
                if(message["type"]?.Type==JTokenType.String && (string)message["type"]=="panel"
                    && message["cmd"]?.Type==JTokenType.String && (string)message["cmd"]=="close" && _panelHost!=null) {
                    if(message["panel"]?.Type!=JTokenType.String || message["panelInstanceId"]?.Type!=JTokenType.String
                        || message["nativeCause"]!=null || message["hostCloseReason"]!=null
                        || args.Source!=OverlayDocumentUrl)return;
                    var endpoint=CaptureEndpointLease((string)message["panel"],(string)message["panelInstanceId"],_panelHost.HostLifetime);
                    if(!IsEndpointCurrent(endpoint))return;
                    var context=new HostCloseContext(endpoint,NativeCloseCause.PageClose,message,CaptureTrustedCloseForeground());
                    _panelHost.WithHostCloseContext(context,()=>OnWebMessageReceived(sender,args));
                    return;
                }
                OnWebMessageReceived(sender,args);
                if (type == "ready" && args.Source == OverlayDocumentUrl && current()) SyncDocumentFields();
            };
            _legacyFailureAdapter=(sender,args)=> {
                if (!current() || !ReferenceEquals(sender,core)) return;
                RetireActiveEndpointInput("web_process_failed");
                OnWebViewProcessFailed(sender,args);
            };
            _fieldNavigationAdapter = (sender, _) =>
            {
                if (!_universalTextFocus || !current() || !ReferenceEquals(sender, core) || !IsHandleCreated) return;
                try { BeginInvoke((Action)(() => { if (current()) SyncDocumentFields(); })); }
                catch (InvalidOperationException) { }
            };
            _legacyCallbackCore=core;
            core.WebMessageReceived+=_legacyMessageAdapter; core.ProcessFailed+=_legacyFailureAdapter;
            core.NavigationCompleted+=_fieldNavigationAdapter;
            core.FrameCreated += OnTerminalFrameCreated;
        }

        private bool IsDocumentFieldEndpointCurrent(EndpointLease endpoint) =>
            endpoint != null && IsManagedWebFieldCurrent(endpoint) && !_panelHost.CompositionHelpOwnsInput;

        private void SyncUniversalPanelHost()
        {
            var host = _universalTextFocus ? _panelHost : null;
            if (ReferenceEquals(_universalPanelHost, host)) return;
            if (_universalPanelHost != null) _universalPanelHost.PanelChanged -= OnUniversalPanelChanged;
            _universalPanelHost = host;
            if (host != null) host.PanelChanged += OnUniversalPanelChanged;
        }

        private void OnUniversalPanelChanged(string panel, string instance)
        {
            if (_terminalPage != null && (panel != "ragchat" || instance != _terminalPage.Instance))
                ClearTerminalPage();
            SyncDocumentFields();
        }

        private void SyncDocumentFields()
        {
            if (!_universalTextFocus) return;
            if (_documentFields != null && IsDocumentFieldEndpointCurrent(_fieldEndpoint)) return;
            RetireDocumentFields("web_panel_retired");
            var host = _panelHost;
            if (host == null || string.IsNullOrEmpty(host.ActivePanelInstanceId)
                || !SessionInputAuthority.IsToken(host.ActivePanelName) || !IsHandleCreated) return;
            var endpoint = CaptureEndpointLease(host.ActivePanelName, host.ActivePanelInstanceId, host.HostLifetime);
            if (!IsDocumentFieldEndpointCurrent(endpoint) || endpoint.Core.Source != OverlayDocumentUrl) return;
            var controller = TryGetWebViewController();
            if (controller == null) return;
            var fields = new WebTextFocusBinding(_webTextAuthority, endpoint.Instance, "web." + endpoint.Panel + ".");
            _documentFields = fields;
            _fieldEndpoint = endpoint;
            _fieldController = controller;
            _fieldLostFocus = (sender, _) =>
            {
                if (ReferenceEquals(_documentFields, fields) && ReferenceEquals(sender, controller)
                    && ObserveWebEditorWindow() == IntPtr.Zero)
                {
                    fields.CaptureExit("web_controller_lost_focus", requestGame: true)?.Invoke();
                    _terminalFields?.CaptureExit("web_controller_lost_focus", requestGame: true)?.Invoke();
                }
            };
            controller.LostFocus += _fieldLostFocus;
            _ = fields.InstallAsync(endpoint.Core, OverlayDocumentUrl);
            SyncTerminalFields();
        }

        private void RetireDocumentFields(string reason)
        {
            RetireTerminalFields(reason);
            var fields = _documentFields;
            if (fields == null) return;
            _documentFields = null;
            _fieldEndpoint = null;
            try { _fieldController.LostFocus -= _fieldLostFocus; }
            catch (InvalidOperationException) { }
            catch (COMException) { }
            _fieldController = null;
            _fieldLostFocus = null;
            fields.CaptureExit(reason, requestGame: !_disposed)?.Invoke();
        }

        private static string TerminalSource(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri)
            && uri.UserInfo.Length == 0 && uri.GetLeftPart(UriPartial.Authority) == RagTerminal.RagTerminalService.LoopbackOrigin
            ? uri.AbsoluteUri : null;

        private void ObserveTerminalOpen(string json, CoreWebView2 core)
        {
            if (!_universalTextFocus || !json.Contains("\"ragchat\"", StringComparison.Ordinal)) return;
            JObject message;
            try { message = JObject.Parse(json); }
            catch (Newtonsoft.Json.JsonException) { return; }
            static string ReadString(JObject body, string name) => body[name]?.Type == JTokenType.String
                ? (string)body[name] : null;
            if (ReadString(message, "type") != "panel_cmd" || ReadString(message, "panel") != "ragchat"
                || ReadString(message, "cmd") != "open" || message["initData"] is not JObject data) return;
            string instance = ReadString(message, "panelInstanceId");
            string source = TerminalSource(ReadString(data, "frontend_url"));
            ClearTerminalPage();
            if (!string.IsNullOrEmpty(instance) && instance == ReadString(message, "panelInstanceId") && source != null)
                _terminalPage = new TerminalPage(instance, source, core, _legacyDocumentEpoch);
        }

        private void OnTerminalFrameCreated(object sender, CoreWebView2FrameCreatedEventArgs args)
        {
            var page = _terminalPage;
            if (!_universalTextFocus || page == null || !ReferenceEquals(sender, page.Core)) return;
            var frame = args.Frame;
            ulong navigation = 0;
            string source = null;
            bool Current() => !_disposed && _universalTextFocus && ReferenceEquals(_terminalPage, page)
                && page.DocumentEpoch == _legacyDocumentEpoch && ReferenceEquals(_legacyCallbackCore, page.Core);
            bool OwnsFrame() => Current() && ReferenceEquals(_terminalFrame, frame);
            frame.NavigationStarting += (_, e) =>
            {
                if (!Current() || e.Cancel || _terminalFrame != null && !OwnsFrame()) return;
                string incoming = TerminalSource(e.Uri);
                if (_terminalFrame == null && incoming != page.Source) return;
                RetireTerminalFields("terminal_navigation");
                _terminalFrame = frame;
                _terminalDocumentSource = null;
                navigation = e.NavigationId;
                source = incoming;
            };
            frame.NavigationCompleted += (_, e) =>
            {
                if (!OwnsFrame() || !e.IsSuccess || e.NavigationId != navigation || source == null) return;
                _terminalDocumentSource = source;
                SyncTerminalFields();
            };
            frame.Destroyed += (_, _) =>
            {
                if (!OwnsFrame()) return;
                RetireTerminalFields("terminal_frame_destroyed");
                _terminalFrame = null;
                _terminalDocumentSource = null;
            };
            frame.WebMessageReceived += (frameSender, e) =>
            {
                if (!ReferenceEquals(frameSender, frame) || !OwnsFrame() || !IsTerminalPanelCurrent()
                    || _terminalFields is not { } fields || e.Source != _terminalDocumentSource) return;
                JObject message;
                try { message = JObject.Parse(e.WebMessageAsJson); }
                catch (Newtonsoft.Json.JsonException) { return; }
                fields.Observe(message, _fieldEndpoint.OwnerRoot, ObserveWebEditorWindow(), requestGameOnBlur: true);
            };
        }

        private bool IsTerminalPanelCurrent() => _terminalPage != null && _fieldEndpoint?.Panel == "ragchat"
            && _fieldEndpoint.Instance == _terminalPage.Instance && IsDocumentFieldEndpointCurrent(_fieldEndpoint);

        private void SyncTerminalFields()
        {
            if (_terminalFields != null || _terminalFrame == null || _terminalDocumentSource == null
                || !IsTerminalPanelCurrent()) return;
            var fields = new WebTextFocusBinding(_webTextAuthority, _terminalPage.Instance, "web.ragchat.terminal.");
            _terminalFields = fields;
            _ = fields.InstallAsync(_terminalFrame, _terminalDocumentSource);
        }

        private void ClearTerminalPage()
        {
            RetireTerminalFields("terminal_panel_retired");
            _terminalPage = null;
            _terminalFrame = null;
            _terminalDocumentSource = null;
        }

        private void RetireTerminalFields(string reason)
        {
            var fields = _terminalFields;
            _terminalFields = null;
            fields?.CaptureExit(reason, requestGame: !_disposed)?.Invoke();
        }

        private bool IsManagedWebFieldCurrent(EndpointLease endpoint)
            => _panelMode && _webNavigationId == 0 && _panelHost != null
                && endpoint.HostLifetime == _panelHost.HostLifetime && IsEndpointCurrent(endpoint);

        private IntPtr ObserveWebEditorWindow()
        {
            if (_webView?.IsHandleCreated != true || !_webView.Visible) return IntPtr.Zero;
            IntPtr focus = GetFocus();
            IntPtr webHwnd = _webView.Handle;
            return focus != IntPtr.Zero && (focus == webHwnd || IsChild(webHwnd, focus)) ? focus : IntPtr.Zero;
        }

        private void OnManagedWebFieldFocus(JObject message)
        {
            if (message["endpointId"]?.Type != JTokenType.String
                || (string)message["endpointId"] != SettingsSearchEndpoint
                || message["panelInstanceId"]?.Type != JTokenType.String
                || message["documentToken"]?.Type != JTokenType.String
                || message["phase"]?.Type != JTokenType.String
                || message["focusTurn"] is not JValue { Value: long turn } || turn <= 0
                || message["focused"]?.Type != JTokenType.Boolean
                || message["composing"]?.Type != JTokenType.Boolean
                || _panelHost?.ActivePanelName != "settings"
                || (string)message["panelInstanceId"] != _panelHost.ActivePanelInstanceId)
                return;

            string phase = (string)message["phase"];
            bool focused = (bool)message["focused"];
            bool composing = (bool)message["composing"];
            if (phase is not ("focusin" or "focusout" or "compositionstart" or "compositionend")
                || focused != (phase != "focusout")
                || composing && phase is ("focusout" or "compositionend")
                || !composing && phase == "compositionstart") return;

            var field = _settingsSearch;
            if (field == null || !IsManagedWebFieldCurrent(field.Endpoint))
            {
                if (phase != "focusin" || ObserveWebEditorWindow() == IntPtr.Zero) return;
                var endpoint = CaptureEndpointLease("settings", _panelHost.ActivePanelInstanceId, _panelHost.HostLifetime);
                var controller = TryGetWebViewController();
                if (endpoint == null || controller == null || !IsManagedWebFieldCurrent(endpoint)) return;
                RetireManagedWebField("web_field_replaced");
                field = new ManagedWebField(endpoint, controller, _webTextAuthority.NextInstanceGeneration(SettingsSearchEndpoint));
                controller.LostFocus += OnManagedWebControllerLostFocus;
                _fieldPanelHost = _panelHost;
                _fieldPanelHost.PanelChanged += OnManagedWebPanelChanged;
                _settingsSearch = field;
            }

            if ((string)message["documentToken"] != field.DocumentToken)
            {
                if (phase == "focusin")
                {
                    // Ask the live document to echo its binding. A queued report from
                    // a previous navigation at the same URL cannot carry this token.
                    var binding = new JObject
                    {
                        ["type"] = "ui_field_focus_binding",
                        ["endpointId"] = SettingsSearchEndpoint,
                        ["panelInstanceId"] = field.Endpoint.Instance,
                        ["documentToken"] = field.DocumentToken
                    };
                    try { field.Endpoint.Core.PostWebMessageAsJson(binding.ToString(Newtonsoft.Json.Formatting.None)); }
                    catch (InvalidOperationException) { }
                    catch (System.Runtime.InteropServices.COMException) { }
                }
                return;
            }

            if (phase == "focusout")
            {
                if (turn == field.FocusTurn) ReleaseManagedWebField(field, "web_field_focusout");
                return;
            }
            // Composition reports are facts about the current turn. They do not
            // rotate the lease or make a hidden editor eligible for acquisition.
            if (phase != "focusin" || turn <= field.FocusTurn) return;
            IntPtr editor = ObserveWebEditorWindow();
            if (editor == IntPtr.Zero || field.Endpoint.OwnerRoot == IntPtr.Zero) return;
            field.FocusTurn = turn;
            var authority = _webTextAuthority;
            string session = authority.CurrentSessionId;
            var observed = new TextFocusObservation(session, field.Endpoint.OwnerRoot, editor,
                TextInputClaim.NextFocusSerial(), LocalFocusConfirmed: true, ImeComposing: composing);
            if (authority.AcquireText(SettingsSearchEndpoint, field.InstanceGeneration, observed) is { } lease)
                field.Claim = new TextInputClaim(authority, session, lease);
        }

        private void ReleaseManagedWebField(ManagedWebField field, string reason)
        {
            var captured = field.Claim;
            field.Claim = null;
            if (captured == null) return;
            var observed = new TextExitObservation(captured.SessionId, TextInputClaim.NextFocusSerial(),
                reason, EditorFocusCleared: true);
            var receipt = captured.Authority.ReleaseText(captured.Lease, observed);
            // Record the request while PanelHost still blocks gameplay. Only
            // its settled close/owner transition can admit the pending request.
            if (receipt.Status == TextExitStatus.Released && !_disposed
                && _panelHost?.GameOwnsInput == false)
                captured.Authority.RequestGameKeyboard(receipt);
        }

        private void OnManagedWebControllerLostFocus(object sender, object args)
        {
            var field = _settingsSearch;
            if (field != null && ReferenceEquals(field.Controller, sender) && ObserveWebEditorWindow() == IntPtr.Zero)
                ReleaseManagedWebField(field, "web_controller_lost_focus");
        }

        private void OnManagedWebPanelChanged(string panel, string instance)
        {
            if (_settingsSearch is { } field && !IsManagedWebFieldCurrent(field.Endpoint))
                RetireManagedWebField("web_panel_retired");
        }

        private void RetireManagedWebField(string reason)
        {
            var field = _settingsSearch;
            if (field == null) return;
            _settingsSearch = null;
            _fieldPanelHost.PanelChanged -= OnManagedWebPanelChanged;
            _fieldPanelHost = null;
            ReleaseManagedWebField(field, reason);
            try { field.Controller.LostFocus -= OnManagedWebControllerLostFocus; }
            catch (InvalidOperationException) { }
            catch (System.Runtime.InteropServices.COMException) { }
        }

        private void RetireActiveEndpointInput(string reason = "web_panel_suspended")
        {
            _inputShield?.CancelActivePointerGesture();
            if (IsHandleCreated)
            {
                IntPtr capture = GetCapture();
                if (capture != IntPtr.Zero && (capture == Handle || IsChild(Handle, capture)))
                    ReleaseCapture();
            }
            RetireManagedWebField(reason);
            RetireDocumentFields(reason);
        }

        internal IntPtr CaptureTrustedCloseForeground()
        {
            var snapshot=CaptureCurrentSessionForegroundSnapshot();
            IntPtr foreground=snapshot.ForegroundHwnd;
            IntPtr root=GetAncestor(foreground,2);
            if(IsHandleCreated && (foreground==Handle || root==Handle))return foreground;
            if(_owner!=null && _owner.IsHandleCreated && (foreground==_owner.Handle || root==_owner.Handle))return foreground;
            return IntPtr.Zero;
        }
        internal Action<string> CaptureResponseSink()
        {
            var lease=CaptureEndpointLease(_panelHost?.ActivePanelName,_panelHost?.ActivePanelInstanceId,_panelHost?.HostLifetime);
            return json=> {
                void post() { if(!IsEndpointCurrent(lease))return; try { lease.Core.PostWebMessageAsJson(json); } catch { } }
                if(InvokeRequired) { try { BeginInvoke((Action)post); } catch { } } else post();
            };
        }
        internal void HandleCompositionIntelligenceClose(HostCloseContext context)
        {
            if(_disposed || _panelHost==null || context?.Endpoint.Panel!="intelligence"
                || context.Endpoint.Instance!=_panelHost.ActivePanelInstanceId
                || context.Endpoint.Surface is not CompositionHelpSurface surface || !surface.IsLeaseCurrent(context.Endpoint))return;
            var previous=_trustedClose; _trustedClose=context;
            try { _panelHost.WithHostCloseContext(context,()=>HandlePanelMessage(context.Envelope.ToString(Newtonsoft.Json.Formatting.None))); }
            finally { _trustedClose=previous; }
        }
        internal IDisposable EnterManagedClose()
        { _managedCloseDepth++; return new ManagedCloseScope(this); }
        internal void PostNativeEscapeExact(EndpointLease endpoint)
        {
            if(!IsEndpointCurrent(endpoint))return;
            endpoint.Core.PostWebMessageAsJson("{\"type\":\"panel_esc\",\"reason\":\"escape\"}");
        }
        private sealed class ManagedCloseScope : IDisposable
        {
            private WebOverlayForm _owner;
            internal ManagedCloseScope(WebOverlayForm owner) { _owner=owner; }
            public void Dispose() { var owner=_owner; _owner=null; if(owner!=null)owner._managedCloseDepth--; }
        }
        internal bool ReleaseClosePause() => TryReleaseGenericWebPanelPause();
        internal void PublishClosePanelState()
        {
            if (!_panelMode) RetireActiveEndpointInput("web_panel_closed");
            _onPanelStateChanged?.Invoke(false);
        }
    }
}
