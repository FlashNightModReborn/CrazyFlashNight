using System;
using System.Diagnostics;
using System.Threading;

namespace CF7Launcher.Guardian
{
    public partial class WindowManager
    {
        private long _focusTargetEpoch = 1;
        private Process _registeredFocusProcess;
        internal IntPtr ReadCloseForeground() { try { return _focusApi.GetForegroundWindow(); } catch { return IntPtr.Zero; } }
        internal sealed class FlashFocusTarget
        {
            internal readonly IntPtr Window, Root;
            internal readonly uint Pid, Tid, RootPid, RootTid;
            internal readonly long EmbedEpoch;
            internal readonly DateTime ProcessBirth;
            internal readonly Process Process;
            internal FlashFocusTarget(IntPtr window, IntPtr root, uint pid, uint tid, uint rootPid, uint rootTid,
                long epoch, Process process, DateTime birth)
            { Window=window; Root=root; Pid=pid; Tid=tid; RootPid=rootPid; RootTid=rootTid;
              EmbedEpoch=epoch; Process=process; ProcessBirth=birth; }
        }
        private void SetTrackedFlashWindow(IntPtr window)
        { _flashHwnd=window; Interlocked.Increment(ref _focusTargetEpoch); }
        internal FlashFocusTarget CaptureFlashFocusTarget()
        {
            try {
                IntPtr window=_flashHwnd; long epoch=Interlocked.Read(ref _focusTargetEpoch);
                if(!_allowForeground || !IsCurrentFlashWindow(window) || _registeredFocusProcess==null || _registeredFocusProcess.HasExited)return null;
                uint tid=_focusApi.GetWindowThreadProcessId(window,out uint pid);
                IntPtr root=_focusApi.GetRootWindow(window);
                uint rootTid=_focusApi.GetWindowThreadProcessId(root,out uint rootPid);
                if(pid!=(uint)_registeredFocusProcess.Id || tid==0 || rootTid==0 || root==IntPtr.Zero)return null;
                var target=new FlashFocusTarget(window,root,pid,tid,rootPid,rootTid,epoch,_registeredFocusProcess,
                    _registeredFocusProcess.StartTime.ToUniversalTime());
                return ValidateFlashFocusTarget(target) ? target : null;
            } catch { return null; }
        }
        private bool ValidateFlashFocusTarget(FlashFocusTarget target)
        {
            try {
                if(target==null || target.EmbedEpoch!=Interlocked.Read(ref _focusTargetEpoch)
                    || !IsCurrentFlashWindow(target.Window) || !_focusApi.IsWindow(target.Root)
                    || target.Process.HasExited || target.Process.StartTime.ToUniversalTime()!=target.ProcessBirth)return false;
                uint tid=_focusApi.GetWindowThreadProcessId(target.Window,out uint pid);
                uint rootTid=_focusApi.GetWindowThreadProcessId(target.Root,out uint rootPid);
                return tid==target.Tid && pid==target.Pid && rootTid==target.RootTid && rootPid==target.RootPid
                    && _focusApi.GetRootWindow(target.Window)==target.Root;
            } catch { return false; }
        }
        internal bool HandoffFlashFocusOnce(string reason, IntPtr source, FlashFocusTarget target, Func<bool> guard,Action cleanupUnknown=null)
        {
            if(!_allowForeground || source==IntPtr.Zero)return false;
            bool eligible() => guard() && ValidateFlashFocusTarget(target) && guard();
            try {
                if(!eligible() || _focusApi.GetForegroundWindow()!=source || !eligible())return false;
                if(!_focusApi.SetForegroundWindow(target.Root))return false;
                if(!eligible() || _focusApi.GetForegroundWindow()!=target.Root || !eligible())return false;
                RestoreFlashInnerFocusOnce(reason,target,guard,cleanupUnknown);
                return eligible() && _focusApi.GetForegroundWindow()==target.Root;
            } catch { return false; }
        }
        internal bool RestoreFlashInnerFocusOnce(string reason, FlashFocusTarget target, Func<bool> guard,Action cleanupUnknown=null)
        {
            bool eligible() => guard() && ValidateFlashFocusTarget(target)
                && _focusApi.GetForegroundWindow()==target.Root && guard();
            void reportCleanupUnknown() { try { cleanupUnknown?.Invoke(); } catch { } }
            bool attached=false,attachAttempted=false,attachUnknown=false; uint from=0, to=target?.Tid ?? 0;
            try {
                if(!eligible())return false;
                if(IsFlashInnerFocusHeld(target.Window))return eligible();
                from=_focusApi.GetCurrentThreadId();
                if(from!=to) {
                    if(!eligible())return false;
                    attachAttempted=true;
                    try { attached=_focusApi.AttachThreadInput(from,to,true); }
                    catch { attachUnknown=true; throw; }
                    if(!attached)return false;
                }
                if(!eligible())return false;
                _focusApi.SetFocus(target.Window);
                return eligible() && IsFlashInnerFocusHeld(target.Window) && eligible();
            } catch(Exception error) {
                try { LogManager.Log("[PanelCloseFocus] native failure reason="+reason+" type="+error.GetType().Name); } catch { }
                return false;
            } finally {
                if(attached || attachAttempted && attachUnknown) {
                    try { if(!_focusApi.AttachThreadInput(from,to,false)) {
                        reportCleanupUnknown(); LogManager.Log("[PanelCloseFocus] detach returned false reason="+reason);
                    } }
                    catch(Exception error) { reportCleanupUnknown(); try { LogManager.Log("[PanelCloseFocus] cleanup_unknown reason="+reason+" type="+error.GetType().Name); } catch { } }
                }
            }
        }
    }
}
