using System;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian.InputOwnership;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal sealed partial class CompositionHelpSurface
    {
        private long _controllerGeneration, _endpointSessionGeneration, _surfaceHandleEpoch;
        private string _endpointHostLifetime = Guid.NewGuid().ToString("N");
        private CoreWebView2 _endpointCore, _callbackCore;
        internal CoreWebView2 InternalCoreWebView2 => _disposed ? null : _endpointCore;
        private CoreWebView2CompositionController _callbackController;
        private EventHandler<CoreWebView2WebMessageReceivedEventArgs> _messageAdapter;
        private EventHandler<CoreWebView2AcceleratorKeyPressedEventArgs> _acceleratorAdapter;
        private EventHandler<CoreWebView2ProcessFailedEventArgs> _failureAdapter;
        private HostCloseContext _pendingHostClose;
        private EndpointLease _captureEndpointLease;
        private bool _surfaceInputBound, _surfaceModal;
        private ITextInputAuthority _compositionTextAuthority;
        private WebTextFocusBinding _compositionFields;
        private EventHandler<object> _controllerGotFocus, _controllerLostFocus;
        private EventHandler<CoreWebView2NavigationStartingEventArgs> _fieldNavigationStarting;
        private EventHandler<CoreWebView2NavigationCompletedEventArgs> _fieldNavigationCompleted;
        private ulong _fieldNavigationId;
        private bool _controllerFocused, _imeEscapeDown;
        private static bool IsIntelligenceQuery(string command) => command is "bundle" or "catalog" or "snapshot"
            or "state" or "tooltip" or "glossary_catalog" or "glossary_snapshot" or "bestiary_catalog";
        internal event Action<HostCloseContext> HostCloseRequested;
        internal event Action<bool> SurfaceModalStateChanged;

        internal void BindInputAuthority(ITextInputAuthority textAuthority, IUiPointerAuthority pointerAuthority,
            bool enableUniversalTextFocus = false)
        {
            if (_disposed) return;
            bool bound = textAuthority != null || pointerAuthority != null;
            var authority = enableUniversalTextFocus ? textAuthority : null;
            if (_surfaceInputBound == bound && ReferenceEquals(_compositionTextAuthority, authority)) return;
            RetireEndpointInput();
            _surfaceInputBound = bound;
            _compositionTextAuthority = authority;
            if (!bound) _surfaceModal = false;
            if (_endpointCore != null) RegisterEndpointCallbacks();
        }

        // The scene controller calls this at the existing world-input hold boundary,
        // including when the transition is still painting on its recovery backing.
        internal void NotifySurfaceModalState(bool blocksGameInput)
        {
            if (!_surfaceInputBound || _disposed || _surfaceModal == blocksGameInput) return;
            _surfaceModal = blocksGameInput;
            if (blocksGameInput)
            {
                bool localCapture = IsHandleCreated && Capture;
                CancelActivePointerGesture("surface_modal");
                // A native sibling such as Modifier may still own this UI thread's
                // capture. Let its capture-loss path cancel the exact pointer ticket.
                if (!localCapture) ReleaseCapture();
            }
            SurfaceModalStateChanged?.Invoke(blocksGameInput);
        }

        internal void RetireEndpointInput()
        {
            CancelActivePointerGesture("surface_retired");
            RetireCompositionFields("composition_endpoint_retired");
            _imeEscapeDown = false;
        }

        private void CancelActivePointerGesture(string reason)
        {
            bool ownsCapture = IsHandleCreated && Capture;
            bool hadGesture = _pressedButtons != 0 || ownsCapture;
            _captureEndpointLease = null;
            _pressedButtons = 0;
            _capturedButton = false;
            // Clear the old lease before dropping capture, which synchronously fires WM_CAPTURECHANGED.
            if (ownsCapture) Capture = false;
            if (hadGesture) LogManager.Log(LogTag + " pointer gesture cancelled: " + reason);
        }

        protected override void OnVisibleChanged(EventArgs e)
        {
            if (!Visible) RetireEndpointInput();
            base.OnVisibleChanged(e);
            if (Visible) SyncCompositionFields();
        }

        internal void AttachHostLifetime(string lifetime) { _endpointHostLifetime=lifetime; }
        protected override void OnHandleCreated(EventArgs e)
        {
            Interlocked.Increment(ref _surfaceHandleEpoch);
            base.OnHandleCreated(e);
            if (_compositionTextAuthority != null && _endpointCore != null) RegisterEndpointCallbacks();
        }
        protected override void OnHandleDestroyed(EventArgs e)
        {
            RetireEndpointInput();
            Interlocked.Increment(ref _surfaceHandleEpoch);
            base.OnHandleDestroyed(e);
        }
        internal EndpointLease CaptureEndpointLease()
        {
            if(_disposed || !_active || string.IsNullOrEmpty(_panelInstance))return null;
            return new EndpointLease(this,_web,_endpointCore,_transition ? "loot" : _profile.PanelName,_panelInstance,_endpointHostLifetime,
                _controllerGeneration,_endpointSessionGeneration,_surfaceHandleEpoch,IsHandleCreated ? Handle : IntPtr.Zero,
                ownerRoot:_owner.IsHandleCreated ? _owner.Handle : IntPtr.Zero);
        }
        internal bool IsLeaseCurrent(EndpointLease lease) => lease!=null && !_disposed
            && ReferenceEquals(lease.Surface,this) && ReferenceEquals(lease.Controller,_web) && ReferenceEquals(lease.Core,_endpointCore)
            && lease.HostLifetime==_endpointHostLifetime && lease.ControllerGeneration==_controllerGeneration
            && lease.SessionGeneration==_endpointSessionGeneration && lease.HandleEpoch==_surfaceHandleEpoch
            && lease.Instance==_panelInstance && _active;
        private bool IsRegistrationCurrent(EndpointLease lease) => lease!=null && !_disposed
            && ReferenceEquals(lease.Controller,_web) && ReferenceEquals(lease.Core,_endpointCore)
            && lease.ControllerGeneration==_controllerGeneration && lease.SessionGeneration==_endpointSessionGeneration
            && lease.HostLifetime==_endpointHostLifetime;
        private void DetachEndpointCallbacks()
        {
            RetireEndpointInput();
            if(_callbackCore!=null) {
                if(_messageAdapter!=null)_callbackCore.WebMessageReceived-=_messageAdapter;
                if(_failureAdapter!=null)_callbackCore.ProcessFailed-=_failureAdapter;
                if(_fieldNavigationStarting!=null)_callbackCore.NavigationStarting-=_fieldNavigationStarting;
                if(_fieldNavigationCompleted!=null)_callbackCore.NavigationCompleted-=_fieldNavigationCompleted;
            }
            if (_callbackController != null)
            {
                if (_acceleratorAdapter != null) _callbackController.AcceleratorKeyPressed -= _acceleratorAdapter;
                if (_controllerGotFocus != null) _callbackController.GotFocus -= _controllerGotFocus;
                if (_controllerLostFocus != null) _callbackController.LostFocus -= _controllerLostFocus;
            }
            _fieldNavigationStarting = null;
            _fieldNavigationCompleted = null;
            _controllerGotFocus = null;
            _controllerLostFocus = null;
            _fieldNavigationId = 0;
            _controllerFocused = false;
            _callbackCore=null; _callbackController=null;
        }
        private void RegisterEndpointCallbacks()
        {
            bool sameController = _web != null && ReferenceEquals(_callbackController, _web);
            bool focused = sameController && _controllerFocused;
            ulong navigation = sameController ? _fieldNavigationId : 0;
            DetachEndpointCallbacks();
            if(_web==null || _endpointCore==null)return;
            _controllerFocused = focused;
            _fieldNavigationId = navigation;
            var lease=new EndpointLease(this,_web,_endpointCore,_profile.PanelName,_panelInstance,_endpointHostLifetime,
                _controllerGeneration,_endpointSessionGeneration,_surfaceHandleEpoch,IsHandleCreated ? Handle : IntPtr.Zero);
            var ready=_readyTcs;
            _messageAdapter=(sender,args)=> {
                if(!IsRegistrationCurrent(lease) || !ReferenceEquals(sender,lease.Core) || args.Source!=_pageUrl)return;
                JObject message; try { message=JObject.Parse(args.WebMessageAsJson); } catch { return; }
                if(message["type"]?.Type!=JTokenType.String)return;
                if ((string)message["type"] == WebTextFocusBinding.MessageType)
                {
                    if (lease.HandleEpoch == _surfaceHandleEpoch
                        && _compositionFields is { } fields && IsCompositionTextCurrent(fields))
                    {
                        IntPtr editor = ObserveCompositionEditorWindow();
                        fields.Observe(message, _owner.IsHandleCreated ? _owner.Handle : IntPtr.Zero, editor,
                            requestGameOnBlur: true);
                    }
                    return;
                }
                if((string)message["type"]==(_transition ? "scene_transition_ready" : _profile.ReadyMessageType)) {
                    if(ReferenceEquals(ready,_readyTcs))ready?.TrySetResult(true);
                    return;
                }
                if(!IsLeaseCurrent(lease))return;
                DispatchPanelEnvelope(message);
            };
            _acceleratorAdapter=(sender,args)=> {
                if (IsLeaseCurrent(lease) && ReferenceEquals(sender,lease.Controller) && !IsCompositionEscape(args))
                    OnAcceleratorKey(sender,args);
            };
            _failureAdapter=(sender,args)=> {
                if (!IsRegistrationCurrent(lease) || !ReferenceEquals(sender,lease.Core)) return;
                RetireEndpointInput();
                OnWebProcessFailed(sender,args);
            };
            _callbackCore=_endpointCore; _callbackController=_web;
            _callbackCore.WebMessageReceived+=_messageAdapter;
            _callbackCore.ProcessFailed+=_failureAdapter;
            _callbackController.AcceleratorKeyPressed+=_acceleratorAdapter;
            if (_compositionTextAuthority != null) RegisterCompositionFieldCallbacks(lease, _web);
            SyncCompositionFields();
        }

        private void RegisterCompositionFieldCallbacks(EndpointLease registration, CoreWebView2CompositionController controller)
        {
            bool Current() => IsRegistrationCurrent(registration) && registration.HandleEpoch == _surfaceHandleEpoch;
            _controllerGotFocus = (sender, _) =>
            {
                if (!ReferenceEquals(sender, controller) || !Current()) return;
                _controllerFocused = true;
                SyncCompositionFields();
            };
            _controllerLostFocus = (sender, _) =>
            {
                if (ReferenceEquals(sender, controller) && Current())
                    QueueCompositionFocusExit("composition_controller_lost_focus");
            };
            _fieldNavigationStarting = (sender, args) =>
            {
                if (!ReferenceEquals(sender, registration.Core) || !Current()
                    || args.Cancel || args.Uri != _pageUrl) return;
                _fieldNavigationId = args.NavigationId;
                RetireCompositionFields("composition_navigation");
            };
            _fieldNavigationCompleted = (sender, args) =>
            {
                if (!ReferenceEquals(sender, registration.Core) || !Current()
                    || _fieldNavigationId != args.NavigationId) return;
                _fieldNavigationId = 0;
                if (args.IsSuccess) SyncCompositionFields();
            };
            controller.GotFocus += _controllerGotFocus;
            controller.LostFocus += _controllerLostFocus;
            registration.Core.NavigationStarting += _fieldNavigationStarting;
            registration.Core.NavigationCompleted += _fieldNavigationCompleted;
        }

        private void QueueCompositionFocusExit(string reason)
        {
            if (!_surfaceInputBound || !IsHandleCreated) return;
            var fields = _compositionFields;
            long? turn = fields?.FocusTurn;
            long handleEpoch = _surfaceHandleEpoch;
            var exit = fields?.CaptureExit(reason, requestGame: true, detach: false);
            void ConfirmDeparture()
            {
                if (handleEpoch == _surfaceHandleEpoch && ReferenceEquals(_compositionFields, fields))
                {
                    // A new turn on the same controller owns its own DOM/native
                    // loss. The old callback cannot retire that turn's focus.
                    if (fields?.FocusTurn != turn || IsHandleCreated && GetForegroundWindow() == Handle) return;
                    _controllerFocused = false;
                    _imeEscapeDown = false;
                }
                exit?.Invoke();
            }
            try { BeginInvoke((Action)ConfirmDeparture); }
            catch (InvalidOperationException) { ConfirmDeparture(); }
        }

        private string CompositionTextInstance() => _transition && string.IsNullOrEmpty(_panelInstance)
            ? $"transition.{SessionGeneration}" : _panelInstance;

        private bool IsCompositionTextCurrent(WebTextFocusBinding fields) =>
            !_disposed && Visible && Active && _fieldNavigationId == 0
            && fields.PanelInstanceId == CompositionTextInstance();

        private IntPtr ObserveCompositionEditorWindow()
        {
            // Composition has no control HWND for each DOM editor. The exact
            // controller's focus event qualifies its surface HWND as the editor.
            return _controllerFocused && !_presentationPolicy.NonActivating && IsHandleCreated
                && GetForegroundWindow() == Handle ? Handle : IntPtr.Zero;
        }

        private void SyncCompositionFields()
        {
            if (_compositionTextAuthority == null || _disposed || !Visible || !Active || !IsHandleCreated
                || _fieldNavigationId != 0 || _endpointCore == null || _endpointCore.Source != _pageUrl) return;
            string instance = CompositionTextInstance();
            if (string.IsNullOrEmpty(instance) || _compositionFields?.PanelInstanceId == instance) return;
            RetireCompositionFields("composition_session_changed");
            string panel = _transition ? "transition" : _profile.PanelName;
            var fields = new WebTextFocusBinding(_compositionTextAuthority, instance, "composition." + panel + ".");
            _compositionFields = fields;
            _ = fields.InstallAsync(_endpointCore, _pageUrl);
        }

        private void RetireCompositionFields(string reason)
        {
            var fields = _compositionFields;
            _compositionFields = null;
            fields?.CaptureExit(reason, requestGame: !_disposed)?.Invoke();
        }

        private bool IsCompositionEscape(CoreWebView2AcceleratorKeyPressedEventArgs args)
        {
            if (args.VirtualKey != VkEscape || _compositionTextAuthority == null) return false;
            if (args.KeyEventKind == CoreWebView2KeyEventKind.KeyUp)
            {
                bool imeEscape = _imeEscapeDown;
                _imeEscapeDown = false;
                return imeEscape;
            }
            if (args.KeyEventKind == CoreWebView2KeyEventKind.KeyDown && _compositionFields?.ImeComposing == true)
                _imeEscapeDown = true;
            return _imeEscapeDown;
        }
        private void BindEndpointSession(string instance)
        {
            _pendingHostClose = null;
            _panelInstance=instance;
            if(Interlocked.Increment(ref _endpointSessionGeneration)<=0) { _active=false; throw new InvalidOperationException("Endpoint session generation exhausted"); }
            RegisterEndpointCallbacks();
        }
        internal bool TryPostExact(string json, EndpointLease lease)
        {
            if(!IsLeaseCurrent(lease) || lease.Core==null)return false;
            try { lease.Core.PostWebMessageAsJson(json); return IsLeaseCurrent(lease); } catch { return false; }
        }
        internal Action<string> CaptureResponseSink()
        {
            var lease=CaptureEndpointLease();
            return json=> {
                void post() { TryPostExact(json,lease); }
                if(InvokeRequired) { try { BeginInvoke((Action)post); } catch { } } else post();
            };
        }
        internal bool RetireExact(EndpointLease lease)
        { if(!IsLeaseCurrent(lease))return false; Retire(); return true; }
        internal bool IsRetiredEndpoint(EndpointLease lease) => !_disposed && !_active && _endpointCore==null
            && ReferenceEquals(lease.Surface,this) && lease.ControllerGeneration+1==_controllerGeneration
            && lease.HostLifetime==_endpointHostLifetime;
        private static NativeCloseCause NativeCause(string reason) => reason.Split(':')[0] switch {
            "esc"=>NativeCloseCause.Escape, "deactivated"=>NativeCloseCause.Deactivated,
            "capture_lost"=>NativeCloseCause.CaptureLost, "process_failed"=>NativeCloseCause.ProcessFailed,
            _=>NativeCloseCause.PageClose
        };
        private void QueueExactClose(string reason, JObject envelope)
        {
            var lease = CaptureEndpointLease();
            if (lease == null || !IsHandleCreated) return;
            var body = envelope ?? new JObject
            {
                ["type"] = "panel",
                ["panel"] = _profile.PanelName,
                ["cmd"] = "close",
                ["panelInstanceId"] = lease.Instance
            };
            var pending = new HostCloseContext(lease, NativeCause(reason), body, CaptureGameForeground());
            _pendingHostClose = pending;
            CancelActivePointerGesture("surface_close");
            // Dispatch off the WebView2 callback. Only this posted turn can deliver its context.
            try
            {
                BeginInvoke((Action)(() =>
                {
                    if (ReferenceEquals(_pendingHostClose, pending)) TryDeliverClose();
                }));
            }
            catch (InvalidOperationException)
            {
                if (ReferenceEquals(_pendingHostClose, pending)) _pendingHostClose = null;
            }
        }

        private void TryDeliverClose()
        {
            var pending = _pendingHostClose;
            _pendingHostClose = null;
            if (pending != null && IsLeaseCurrent(pending.Endpoint)) HostCloseRequested?.Invoke(pending);
        }
    }
}
