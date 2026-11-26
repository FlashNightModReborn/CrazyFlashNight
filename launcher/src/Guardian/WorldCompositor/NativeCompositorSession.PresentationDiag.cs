using System;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.WorldCompositor;

internal sealed partial class NativeCompositorSession
{
    private readonly PresentationDiagReadDelegate _readPresentationDiag;

    internal bool PresentationDiagAvailable => _session != IntPtr.Zero && _readPresentationDiag != null;

    internal PresentationDiagStats? ReadPresentationDiag()
    {
        if (!PresentationDiagAvailable) return null;
        var stats = new PresentationDiagStats { Size = (uint)Marshal.SizeOf<PresentationDiagStats>() };
        return _readPresentationDiag(_session, ref stats) == 1 ? stats : null;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PresentationDiagStats
    {
        internal uint Size, Enabled, RetainedWorldPreBlit, RetainedShakeBlitActive;
        internal ulong Completed, ActiveBlitSamples, ZeroBypassSamples;
        internal double WorldPreBlitMsTotal, WorldPreBlitP50Ms, WorldPreBlitP95Ms, WorldPreBlitP99Ms;
        internal double ShakeBlitActiveMsTotal, ShakeBlitActiveP50Ms, ShakeBlitActiveP95Ms, ShakeBlitActiveP99Ms;
        internal double ShakeBlitBypassMsTotal;
        internal ulong ShakeStageCreates, ShakeStageAllocFails;
        internal double ShakeStageCreateCpuMsTotal, ShakeStageCreateCpuMaxMs;
        internal ulong BulletHistoryDraws, BulletBatchesUploaded, BulletUploadBytes;
        internal ulong RayDraws, RayBatchesUploaded, RayUploadBytes;
        internal ulong WakeFreshSource, WakeHudVersion, WakeShake, WakeFrozenPresenceOnly, WakeOther;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int PresentationDiagReadDelegate(IntPtr session, ref PresentationDiagStats stats);
}
