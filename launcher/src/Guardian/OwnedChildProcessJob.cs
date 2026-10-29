using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Own only processes started by this Host. The unnamed, non-inherited job handle
    /// is closed by Windows even when Task Manager terminates the Host, so its Flash
    /// and embedded-terminal children cannot outlive it. Normal save/exit stays fenced.
    /// </summary>
    internal sealed class OwnedChildProcessJob : IDisposable
    {
        private const uint KillOnJobClose = 0x00002000;
        private static readonly object HostGate = new object();
        private static OwnedChildProcessJob _hostJob;
        private readonly SafeJobHandle _handle;

        internal OwnedChildProcessJob()
        {
            _handle = CreateJobObject(IntPtr.Zero, null);
            if (_handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            var limits = new ExtendedLimitInformation();
            limits.BasicLimitInformation.LimitFlags = KillOnJobClose;
            if (!SetInformationJobObject(_handle, 9, ref limits,
                (uint)Marshal.SizeOf<ExtendedLimitInformation>()))
            {
                int error = Marshal.GetLastWin32Error();
                _handle.Dispose();
                throw new Win32Exception(error);
            }
        }

        internal static Process Start(ProcessStartInfo startInfo)
        {
            if (startInfo == null) throw new ArgumentNullException(nameof(startInfo));
            if (startInfo.UseShellExecute)
                throw new ArgumentException("Owned children require direct process creation.", nameof(startInfo));
            lock (HostGate)
            {
                if (_hostJob == null) _hostJob = new OwnedChildProcessJob();
                Process child = Process.Start(startInfo);
                if (child == null) throw new InvalidOperationException("process_start_returned_null");
                try
                {
                    _hostJob.Assign(child);
                    return child;
                }
                catch
                {
                    // Assignment failure must not leave an unmanaged child after Start fails.
                    try { if (!child.HasExited) child.Kill(entireProcessTree: true); } catch { }
                    child.Dispose();
                    throw;
                }
            }
        }

        internal void Assign(Process child)
        {
            if (child == null) throw new ArgumentNullException(nameof(child));
            if (_handle.IsClosed) throw new ObjectDisposedException(nameof(OwnedChildProcessJob));
            if (!AssignProcessToJobObject(_handle, child.SafeHandle))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot bind the owned child to Host lifetime.");
        }

        public void Dispose() { _handle.Dispose(); }

        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimitInformation
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimitInformation
        {
            public BasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        private sealed class SafeJobHandle : SafeHandleZeroOrMinusOneIsInvalid
        {
            public SafeJobHandle() : base(true) { }
            protected override bool ReleaseHandle() { return CloseHandle(handle); }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeJobHandle CreateJobObject(IntPtr attributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(SafeJobHandle job, int informationClass,
            ref ExtendedLimitInformation information, uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(SafeJobHandle job, SafeProcessHandle process);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
