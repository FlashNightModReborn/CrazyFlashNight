using System;

namespace CF7Launcher.Guardian
{
    public partial class PanelHostController
    {
        internal Action CaptureNativeEscapeAction()
        {
            var owner=EffectiveInputOwner;
            var endpoint=System.Threading.Volatile.Read(ref _activeEndpointLease);
            if(endpoint==null || owner.Kind is not (EffectiveInputOwnerKind.LegacyPanel or EffectiveInputOwnerKind.CompositionPanel
                or EffectiveInputOwnerKind.Settlement))return null;
            long admission=System.Threading.Interlocked.Read(ref _inputAdmissionStamp);
            IntPtr foreground=_closeFocusManager?.ReadCloseForeground() ?? IntPtr.Zero;
            var context=new HostCloseContext(endpoint,NativeCloseCause.Escape,new Newtonsoft.Json.Linq.JObject {
                ["type"]="panel",["panel"]=endpoint.Panel,["panelInstanceId"]=endpoint.Instance,["cmd"]="close" },foreground);
            if(_closeFocusManager!=null && (context.SourceIdentity==null
                || context.SourceIdentity.Root!=endpoint.Handle && context.SourceIdentity.Root!=endpoint.OwnerRoot))return null;
            return ()=> {
                void deliver() {
                    if(_disposed || !ReferenceEquals(owner,EffectiveInputOwner)
                        || !ReferenceEquals(endpoint,_activeEndpointLease) || admission!=System.Threading.Interlocked.Read(ref _inputAdmissionStamp)
                        || !ExactCloseSource(context))return;
                    if(_web==null || endpoint.Panel=="help")TryCloseHostContext(context,endpoint.Panel=="help",null,null,null);
                    else if(endpoint.Surface is CompositionHelpSurface surface) {
                        if(endpoint.Panel=="intelligence")_web.HandleCompositionIntelligenceClose(context);
                        else surface.TryPostExact("{\"type\":\"panel_esc\",\"reason\":\"escape\"}",endpoint);
                    } else _web.PostNativeEscapeExact(endpoint);
                }
                if(_ownerForm==null)deliver();
                else try { _ownerForm.BeginInvoke((Action)deliver); } catch { }
            };
        }
    }
}
