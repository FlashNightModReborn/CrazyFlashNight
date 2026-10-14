using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal sealed partial class CompositionHelpSurface
    {
        private long _controllerGeneration, _endpointSessionGeneration, _surfaceHandleEpoch;
        private string _endpointHostLifetime = Guid.NewGuid().ToString("N");
        private CoreWebView2 _endpointCore, _callbackCore;
        private CoreWebView2CompositionController _callbackController;
        private EventHandler<CoreWebView2WebMessageReceivedEventArgs> _messageAdapter;
        private EventHandler<CoreWebView2AcceleratorKeyPressedEventArgs> _acceleratorAdapter;
        private EventHandler<CoreWebView2ProcessFailedEventArgs> _failureAdapter;
        private EventHandler _pendingCloseTick;
        private HostCloseContext _pendingHostClose;
        private EndpointLease _captureEndpointLease;
        private static bool IsIntelligenceQuery(string command) => command is "bundle" or "catalog" or "snapshot"
            or "state" or "tooltip" or "glossary_catalog" or "glossary_snapshot";
        internal event Action<HostCloseContext> HostCloseRequested;
        internal void AttachHostLifetime(string lifetime) { _endpointHostLifetime=lifetime; }
        protected override void OnHandleCreated(EventArgs e)
        { Interlocked.Increment(ref _surfaceHandleEpoch); base.OnHandleCreated(e); }
        protected override void OnHandleDestroyed(EventArgs e)
        { Interlocked.Increment(ref _surfaceHandleEpoch); base.OnHandleDestroyed(e); }
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
            if(_callbackCore!=null) {
                if(_messageAdapter!=null)_callbackCore.WebMessageReceived-=_messageAdapter;
                if(_failureAdapter!=null)_callbackCore.ProcessFailed-=_failureAdapter;
            }
            if(_callbackController!=null && _acceleratorAdapter!=null)_callbackController.AcceleratorKeyPressed-=_acceleratorAdapter;
            _callbackCore=null; _callbackController=null;
        }
        private void RegisterEndpointCallbacks()
        {
            DetachEndpointCallbacks();
            if(_web==null || _endpointCore==null)return;
            var lease=new EndpointLease(this,_web,_endpointCore,_profile.PanelName,_panelInstance,_endpointHostLifetime,
                _controllerGeneration,_endpointSessionGeneration,_surfaceHandleEpoch,IsHandleCreated ? Handle : IntPtr.Zero);
            var ready=_readyTcs;
            _messageAdapter=(sender,args)=> {
                if(!IsRegistrationCurrent(lease) || !ReferenceEquals(sender,lease.Core) || args.Source!=_pageUrl)return;
                JObject message; try { message=JObject.Parse(args.WebMessageAsJson); } catch { return; }
                if(message["type"]?.Type!=JTokenType.String)return;
                if((string)message["type"]==(_transition ? "scene_transition_ready" : _profile.ReadyMessageType)) {
                    if(ReferenceEquals(ready,_readyTcs))ready?.TrySetResult(true);
                    return;
                }
                if(!IsLeaseCurrent(lease))return;
                DispatchPanelEnvelope(message);
            };
            _acceleratorAdapter=(sender,args)=> { if(IsLeaseCurrent(lease) && ReferenceEquals(sender,lease.Controller))OnAcceleratorKey(sender,args); };
            _failureAdapter=(sender,args)=> { if(IsRegistrationCurrent(lease) && ReferenceEquals(sender,lease.Core))OnWebProcessFailed(sender,args); };
            _callbackCore=_endpointCore; _callbackController=_web;
            _callbackCore.WebMessageReceived+=_messageAdapter;
            _callbackCore.ProcessFailed+=_failureAdapter;
            _callbackController.AcceleratorKeyPressed+=_acceleratorAdapter;
        }
        private void BindEndpointSession(string instance)
        {
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
        private void QueueHostClose(string reason, JObject envelope)
        {
            var lease=CaptureEndpointLease(); if(lease==null)return;
            var body=envelope ?? new JObject { ["type"]="panel",["panel"]=_profile.PanelName,["cmd"]="close",["panelInstanceId"]=lease.Instance };
            var pending=new HostCloseContext(lease,NativeCause(reason),body,CaptureGameForeground());
            _pendingHostClose=pending;
            if(_pendingCloseTick!=null)_closeTimer.Tick-=_pendingCloseTick;
            _pendingCloseTick=(_,_)=>DeliverHostClose(pending);
            _closeTimer.Tick+=_pendingCloseTick;
            if(pending.Plan!=ClosePlanKind.CleanupOnly)_closeTimer.Start();
            BeginInvoke((Action)(()=>DeliverHostClose(pending)));
        }
        private void DeliverHostClose(HostCloseContext pending)
        {
            if(!ReferenceEquals(_pendingHostClose,pending))return;
            if(!IsLeaseCurrent(pending.Endpoint)) { _closeTimer.Stop(); _pendingHostClose=null; _closePending=false; return; }
            if(pending.Plan!=ClosePlanKind.CleanupOnly &&
                (GetAsyncKeyState(0x01)|GetAsyncKeyState(0x02)|GetAsyncKeyState(0x04)|GetAsyncKeyState(VkEscape))<0)return;
            _closeTimer.Stop(); _pendingHostClose=null; _closePending=false;
            HostCloseRequested?.Invoke(pending);
        }
    }
}
