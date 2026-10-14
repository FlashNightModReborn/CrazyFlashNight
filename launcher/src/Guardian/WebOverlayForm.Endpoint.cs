using System;
using System.Threading;
using Newtonsoft.Json.Linq;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Guardian
{
    public partial class WebOverlayForm
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        private long _legacyDocumentEpoch;
        private long _legacyControllerEpoch, _legacyHandleEpoch;
        private CoreWebView2 _legacyCallbackCore;
        private EventHandler<CoreWebView2WebMessageReceivedEventArgs> _legacyMessageAdapter;
        private EventHandler<CoreWebView2ProcessFailedEventArgs> _legacyFailureAdapter;
        private int _managedCloseDepth;
        private HostCloseContext _trustedClose;
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
        { Interlocked.Increment(ref _legacyHandleEpoch); base.OnHandleCreated(e); }
        protected override void OnHandleDestroyed(EventArgs e)
        { Interlocked.Increment(ref _legacyHandleEpoch); base.OnHandleDestroyed(e); }
        private void RegisterLegacyEndpointCallbacks()
        {
            if(_legacyCallbackCore!=null) {
                if(_legacyMessageAdapter!=null)_legacyCallbackCore.WebMessageReceived-=_legacyMessageAdapter;
                if(_legacyFailureAdapter!=null)_legacyCallbackCore.ProcessFailed-=_legacyFailureAdapter;
            }
            var core=_webView?.CoreWebView2; var controller=_webView;
            if(core==null)return;
            long generation=_legacyControllerEpoch, document=_legacyDocumentEpoch, handleEpoch=_legacyHandleEpoch;
            int session=_panelSessionGeneration;
            bool current() => !_disposed && ReferenceEquals(controller,_webView)
                && ReferenceEquals(core,_webView?.CoreWebView2) && generation==_legacyControllerEpoch
                && document==_legacyDocumentEpoch && session==_panelSessionGeneration && handleEpoch==_legacyHandleEpoch;
            _legacyMessageAdapter=(sender,args)=> {
                if(!current() || !ReferenceEquals(sender,core))return;
                JObject message; try { message=JObject.Parse(args.WebMessageAsJson); } catch { return; }
                if(message["type"]?.Type==JTokenType.String && (string)message["type"]=="panel"
                    && message["cmd"]?.Type==JTokenType.String && (string)message["cmd"]=="close" && _panelHost!=null) {
                    if(message["panel"]?.Type!=JTokenType.String || message["panelInstanceId"]?.Type!=JTokenType.String
                        || message["nativeCause"]!=null || message["hostCloseReason"]!=null
                        || args.Source!="https://overlay.local/overlay.html")return;
                    var endpoint=CaptureEndpointLease((string)message["panel"],(string)message["panelInstanceId"],_panelHost.HostLifetime);
                    if(!IsEndpointCurrent(endpoint))return;
                    var context=new HostCloseContext(endpoint,NativeCloseCause.PageClose,message,CaptureTrustedCloseForeground());
                    _panelHost.WithHostCloseContext(context,()=>OnWebMessageReceived(sender,args));
                    return;
                }
                OnWebMessageReceived(sender,args);
            };
            _legacyFailureAdapter=(sender,args)=> { if(current() && ReferenceEquals(sender,core))OnWebViewProcessFailed(sender,args); };
            _legacyCallbackCore=core;
            core.WebMessageReceived+=_legacyMessageAdapter; core.ProcessFailed+=_legacyFailureAdapter;
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
        internal void PublishClosePanelState() { _onPanelStateChanged?.Invoke(false); }
    }
}
