#nullable enable
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal enum ResourcePass
{
    DamagePlan, Masks, ClearAndWrap, MpBase, HpBase, BaseReuseOrStore,
    OverflowAndPulse, Light, MotifsAndRim, Grid, ShieldRing, Readouts,
    FlushAndUnlock, ShieldAndHints, CopyRetainedRegion, PublishSetup, GdiFlush, Submit
}

// Attached only to the measured surface by a diagnostic client on its UI thread.
internal sealed class PlayerInfoPaintTrace
{
    internal long[] WallTicks { get; } = new long[Enum.GetValues<ResourcePass>().Length];
    internal ulong[] ThreadCycles { get; } = new ulong[Enum.GetValues<ResourcePass>().Length];
    internal bool Regional { get; set; }
    internal bool ReusedBase { get; set; }
    internal bool HasLight { get; set; }
    internal int MotionFrame { get; set; }
    internal int PublishedPixels { get; set; }
    private long _wall;
    private ulong _cycles;

    [DllImport("kernel32.dll")]
    private static extern bool QueryThreadCycleTime(IntPtr thread, out ulong cycles);

    internal void Begin()
    {
        Array.Clear(WallTicks);
        Array.Clear(ThreadCycles);
        Regional = ReusedBase = HasLight = false;
        MotionFrame = PublishedPixels = 0;
        QueryThreadCycleTime(new IntPtr(-2), out _cycles);
        _wall = Stopwatch.GetTimestamp();
    }

    internal void EndPass(ResourcePass pass)
    {
        long wall = Stopwatch.GetTimestamp();
        QueryThreadCycleTime(new IntPtr(-2), out ulong cycles);
        WallTicks[(int)pass] += wall - _wall;
        ThreadCycles[(int)pass] += cycles - _cycles;
        _wall = wall;
        _cycles = cycles;
    }
}
