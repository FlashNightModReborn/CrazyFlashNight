using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Tests.Guardian
{
    // Read-only qualification precondition. Never wakes a display or injects input.
    internal static class DisplayPowerObservation
    {
        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        private delegate uint Notify(IntPtr context,uint type,IntPtr setting);
        [StructLayout(LayoutKind.Sequential)]
        private struct Subscription { public Notify Callback; public IntPtr Context; }
        [DllImport("powrprof.dll")]
        private static extern uint PowerSettingRegisterNotification(ref Guid setting,uint flags,
            ref Subscription recipient,out IntPtr registration);
        [DllImport("powrprof.dll")]
        private static extern uint PowerSettingUnregisterNotification(IntPtr registration);

        internal static int ReadSessionState()
        {
            using var ready=new ManualResetEvent(false);
            int state=-1;
            Notify callback=(_,_,data)=>
            {
                if(data!=IntPtr.Zero && Marshal.ReadInt32(data,16)>=4)
                {
                    Volatile.Write(ref state,Marshal.ReadInt32(data,20));
                    ready.Set();
                }
                return 0;
            };
            var recipient=new Subscription {Callback=callback};
            Guid setting=new("2B84C20E-AD23-4DDF-93DB-05FFBD7EFCA5");
            IntPtr registration=IntPtr.Zero;
            uint status=PowerSettingRegisterNotification(ref setting,2,ref recipient,out registration);
            try
            {
                if(status==0)ready.WaitOne(2000);
                return state;
            }
            finally
            {
                if(status==0)PowerSettingUnregisterNotification(registration);
                GC.KeepAlive(callback);
            }
        }
    }
}
