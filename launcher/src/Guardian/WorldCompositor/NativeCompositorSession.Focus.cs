using System;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.WorldCompositor;

internal sealed partial class NativeCompositorSession
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int FocusStageDelegate(IntPtr session,[In] byte[] atlas,int width,int height,[In] int[] instances,int count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int FocusReadDelegate(IntPtr session,out FocusInstanceStats stats,int count);
    private readonly FocusStageDelegate _stageFocus;
    private readonly FocusReadDelegate _readFocus;
    internal bool FocusFillAvailable => _stageFocus != null && _session != IntPtr.Zero;
    internal bool StageFocus(byte[] atlas,int width,int height,int[] instances,int count)
        => FocusFillAvailable && _stageFocus(_session,atlas,width,height,instances,count)==1;
    [StructLayout(LayoutKind.Sequential)]
    internal struct FocusInstanceStats
    {
        public ulong Stages,Draws,Instances,AtlasUploads,AtlasBytes,ParameterBytes;
    }
    internal FocusInstanceStats? TryReadFocusInstanceStats()
        => _session != IntPtr.Zero && _readFocus != null && _readFocus(_session,out var result,6)==1 ? result : null;
}
