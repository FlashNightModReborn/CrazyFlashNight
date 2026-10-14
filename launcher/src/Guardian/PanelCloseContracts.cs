using System;
using System.Diagnostics;
using System.Threading;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal enum NativeCloseCause { PageClose, Escape, Deactivated, CaptureLost, ProcessFailed, HostOperation, Reset, Dispose, FailedOpen }
    internal enum ClosePlanKind { ReturnGame, ReturnStack, Navigate, Replace, CleanupOnly }
    internal enum AuthorityCommitState { NotStarted, Committed, Unknown }
    internal sealed class EndpointLease
    {
        internal readonly object Surface, Controller;
        internal readonly CoreWebView2 Core;
        internal readonly string Panel, Instance, HostLifetime;
        internal readonly long ControllerGeneration, SessionGeneration, HandleEpoch, DocumentEpoch;
        internal readonly IntPtr Handle, OwnerRoot;
        internal EndpointLease(object surface, object controller, CoreWebView2 core, string panel, string instance,
            string hostLifetime, long controllerGeneration, long sessionGeneration, long handleEpoch, IntPtr handle, long documentEpoch=0,IntPtr ownerRoot=default)
        { Surface=surface; Controller=controller; Core=core; Panel=panel; Instance=instance; HostLifetime=hostLifetime;
          ControllerGeneration=controllerGeneration; SessionGeneration=sessionGeneration; HandleEpoch=handleEpoch; Handle=handle; DocumentEpoch=documentEpoch; OwnerRoot=ownerRoot; }
    }
    internal sealed class HostCloseContext
    {
        internal readonly string CloseId = Guid.NewGuid().ToString("N");
        internal readonly EndpointLease Endpoint;
        internal readonly NativeCloseCause Cause;
        internal readonly JObject Envelope;
        internal readonly IntPtr SourceForeground;
        internal readonly CloseSourceWindowIdentity SourceIdentity;
        internal WindowManager.FlashFocusTarget FocusTarget;
        internal readonly DateTime CreatedUtc = DateTime.UtcNow;
        internal long AdmissionStamp;
        internal ClosePlanKind Plan;
        internal AuthorityCommitState Authority;
        internal bool CleanupFailed;
        internal bool SourceRetired;
        internal bool ReleaseGenericPause;
        internal string Outcome;
        private int _executed;
        private int _admitted;
        internal bool TryAdmit(long stamp,WindowManager.FlashFocusTarget target)
        { if(Interlocked.CompareExchange(ref _admitted,1,0)!=0)return false; AdmissionStamp=stamp; FocusTarget=target; return true; }
        internal HostCloseContext(EndpointLease endpoint, NativeCloseCause cause, JObject envelope, IntPtr foreground)
        { Endpoint=endpoint; Cause=cause; Envelope=(JObject)envelope.DeepClone(); SourceForeground=foreground;
          SourceIdentity=CloseSourceWindowIdentity.Capture(foreground);
          Plan=cause is NativeCloseCause.Deactivated or NativeCloseCause.CaptureLost or NativeCloseCause.ProcessFailed
            or NativeCloseCause.Reset or NativeCloseCause.Dispose or NativeCloseCause.FailedOpen ? ClosePlanKind.CleanupOnly : ClosePlanKind.ReturnGame; }
        internal bool TryExecuteOnce() => Interlocked.CompareExchange(ref _executed,1,0)==0;
    }
    internal sealed class CloseSourceWindowIdentity
    {
        private static readonly DateTime CurrentHostBirth=ReadHostBirth();
        private static DateTime ReadHostBirth() { using var process=Process.GetCurrentProcess(); return process.StartTime.ToUniversalTime(); }
        [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
        [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd,uint flag);
        internal readonly IntPtr Window, Root;
        internal readonly uint Pid, Tid, RootPid, RootTid;
        internal readonly DateTime HostBirth;
        private CloseSourceWindowIdentity(IntPtr window,IntPtr root,uint pid,uint tid,uint rootPid,uint rootTid,DateTime birth)
        { Window=window; Root=root; Pid=pid; Tid=tid; RootPid=rootPid; RootTid=rootTid; HostBirth=birth; }
        internal static CloseSourceWindowIdentity Capture(IntPtr window)
        {
            try {
                if(window==IntPtr.Zero || !IsWindow(window))return null;
                using var process=Process.GetCurrentProcess();
                uint tid=GetWindowThreadProcessId(window,out uint pid);
                IntPtr root=GetAncestor(window,2);
                uint rootTid=GetWindowThreadProcessId(root,out uint rootPid);
                if(pid!=(uint)process.Id || rootPid!=pid || tid==0 || rootTid==0)return null;
                return new CloseSourceWindowIdentity(window,root,pid,tid,rootPid,rootTid,CurrentHostBirth);
            } catch { return null; }
        }
        internal bool IsCurrent()
        {
            try {
                uint tid=GetWindowThreadProcessId(Window,out uint pid), rootTid=GetWindowThreadProcessId(Root,out uint rootPid);
                return IsWindow(Window) && IsWindow(Root) && GetAncestor(Window,2)==Root
                    && tid==Tid && pid==Pid && rootTid==RootTid && rootPid==RootPid
                    && CurrentHostBirth==HostBirth;
            } catch { return false; }
        }
    }
    internal sealed class FocusPermit
    {
        private int _state, _tail;
        internal readonly HostCloseContext Close;
        internal readonly Func<bool> Guard;
        internal readonly WindowManager.FlashFocusTarget Target;
        internal bool RootVerified;
        internal FocusPermit(HostCloseContext close, Func<bool> guard, WindowManager.FlashFocusTarget target)
        { Close=close; Guard=guard; Target=target; }
        internal bool EnterLive() => Interlocked.CompareExchange(ref _state,1,0)==0 && Eligible();
        internal bool Eligible() {
            if (Volatile.Read(ref _state)!=1) return false;
            try { if(Guard())return true; } catch { }
            Revoke(); return false;
        }
        internal bool EnterTail() => RootVerified && Interlocked.CompareExchange(ref _tail,1,0)==0 && Eligible();
        internal void Revoke() => Interlocked.Exchange(ref _state,2);
        internal void Complete() => Interlocked.Exchange(ref _state,3);
    }
}
