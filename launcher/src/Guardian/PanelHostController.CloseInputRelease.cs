using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Timer=System.Windows.Forms.Timer;

namespace CF7Launcher.Guardian
{
    public partial class PanelHostController
    {
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        private sealed class DeferredPhysicalClose
        {
            internal readonly PanelCommand Command;
            internal readonly Timer Timer;
            internal DeferredPhysicalClose(PanelCommand command) { Command=command; Timer=new Timer { Interval=25 }; }
            internal void Dispose() { Timer.Stop(); Timer.Dispose(); }
        }
        private readonly Dictionary<string,DeferredPhysicalClose> _physicalCloseWaits=new();
#if CF7_TEST_SEAMS
        internal Func<bool> CloseInputHeldForTests;
        internal void PollPhysicalClosesForTests()
        { foreach(var wait in new List<DeferredPhysicalClose>(_physicalCloseWaits.Values))PollPhysicalClose(wait); }
#endif
        private bool PhysicalCloseInputHeld()
        {
#if CF7_TEST_SEAMS
            if(CloseInputHeldForTests!=null)return CloseInputHeldForTests();
            if(_testPumpDispatcher!=null)return false;
#endif
            return ((GetAsyncKeyState(1)|GetAsyncKeyState(2)|GetAsyncKeyState(4)|GetAsyncKeyState(27))&0x8000)!=0;
        }
        private bool TryDeferCloseForInputRelease(PanelCommand command,HostCloseContext context)
        {
            if(context.Plan==ClosePlanKind.CleanupOnly || !ExactSourceAndAdmission(context) || !PhysicalCloseInputHeld())return false;
            foreach(var existing in _physicalCloseWaits.Values)
                if(existing.Command.CloseContext.Endpoint.Instance==context.Endpoint.Instance) {
                    try { command.ExactCloseCompleted?.Invoke(false); } catch { }
                    return true;
                }
            var wait=new DeferredPhysicalClose(command);
            _physicalCloseWaits.Add(context.CloseId,wait);
            wait.Timer.Tick+=(_,_)=>PollPhysicalClose(wait);
            wait.Timer.Start();
            return true;
        }
        private void PollPhysicalClose(DeferredPhysicalClose wait)
        {
            var context=wait.Command.CloseContext;
            if(!_physicalCloseWaits.TryGetValue(context.CloseId,out var current) || !ReferenceEquals(current,wait))return;
            bool stale=!ExactSourceAndAdmission(context);
            bool expired=DateTime.UtcNow-context.CreatedUtc>TimeSpan.FromSeconds(30);
            if(!stale && !expired && PhysicalCloseInputHeld())return;
            _physicalCloseWaits.Remove(context.CloseId); wait.Dispose();
            if(stale || expired) {
                context.Outcome=stale ? "Superseded" : "InputReleaseExpired";
                LastCloseOutcome=context;
                try { wait.Command.ExactCloseCompleted?.Invoke(false); } catch { }
                return;
            }
            bool kick;
            lock(_queueLock) {
                // This is the same admitted command, with its original identity and stamp.
                _queue.Enqueue(wait.Command); kick=!_processing; if(kick)_processing=true;
            }
            if(!kick)return;
            try {
                if(_testPumpDispatcher!=null)_testPumpDispatcher(PumpQueue);
                else _ownerForm.BeginInvoke((Action)PumpQueue);
            } catch { FailPendingPumpDispatch(true); }
        }
        private void DisposePhysicalCloseWaits()
        { foreach(var wait in _physicalCloseWaits.Values)wait.Dispose(); _physicalCloseWaits.Clear(); }
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
