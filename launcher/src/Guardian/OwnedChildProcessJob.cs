using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
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
        private const uint CreateSuspended = 0x00000004;
        private const uint CreateUnicodeEnvironment = 0x00000400;
        private const uint CreateNoWindow = 0x08000000;
        private const uint UseShowWindow = 0x00000001;
        private const ushort ShowNoActivate = 4;
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

        internal static Process Start(ProcessStartInfo startInfo, bool showWithoutActivating = false)
        {
            if (startInfo == null) throw new ArgumentNullException(nameof(startInfo));
            if (startInfo.UseShellExecute)
                throw new ArgumentException("Owned children require direct process creation.", nameof(startInfo));
            lock (HostGate)
            {
                if (_hostJob == null) _hostJob = new OwnedChildProcessJob();
                if (showWithoutActivating) return _hostJob.StartNonActivatingChild(startInfo);
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
            Assign(child.SafeHandle);
        }

        private void Assign(SafeProcessHandle child)
        {
            if (_handle.IsClosed) throw new ObjectDisposedException(nameof(OwnedChildProcessJob));
            if (!AssignProcessToJobObject(_handle, child))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot bind the owned child to Host lifetime.");
        }

        internal Process StartNonActivatingChild(ProcessStartInfo startInfo)
        {
            if (_handle.IsClosed) throw new ObjectDisposedException(nameof(OwnedChildProcessJob));
            // The projector uses the original Win32 argument string and inherited environment
            // with game-specific storage overrides. ProcessStartInfo has no nonactivating show mode.
            string executable = Path.GetFullPath(startInfo.FileName);
            var command = new StringBuilder().Append('"').Append(executable).Append('"');
            if (!string.IsNullOrEmpty(startInfo.Arguments)) command.Append(' ').Append(startInfo.Arguments);
            var environment = new StringBuilder();
            foreach (var pair in startInfo.Environment.OrderBy(entry => entry.Key, StringComparer.OrdinalIgnoreCase))
                if (pair.Value != null) environment.Append(pair.Key).Append('=').Append(pair.Value).Append('\0');
            environment.Append('\0');
            var startup = new StartupWindow
            {
                Size = (uint)Marshal.SizeOf<StartupWindow>(),
                Flags = UseShowWindow,
                Show = ShowNoActivate
            };
            uint flags = CreateSuspended | CreateUnicodeEnvironment | (startInfo.CreateNoWindow ? CreateNoWindow : 0);
            IntPtr environmentBlock = Marshal.StringToHGlobalUni(environment.ToString());
            ProcessInformation information;
            try
            {
                string directory = string.IsNullOrEmpty(startInfo.WorkingDirectory) ? null : startInfo.WorkingDirectory;
                if (!CreateProcessW(executable, command, IntPtr.Zero, IntPtr.Zero, false, flags, environmentBlock,
                    directory, ref startup, out information))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot start the owned nonactivating child.");
            }
            finally { Marshal.FreeHGlobal(environmentBlock); }

            using var exactProcess = new SafeProcessHandle(information.Process, ownsHandle: true);
            using var initialThread = new SafeWaitHandle(information.Thread, ownsHandle: true);
            Process child = null;
            try
            {
                Assign(exactProcess);
                child = Process.GetProcessById(information.ProcessId);
                // Retain the process identity before resuming or releasing the handles from CreateProcessW.
                _ = child.SafeHandle;
                uint suspendCount = ResumeThread(initialThread);
                if (suspendCount == uint.MaxValue)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot resume the owned nonactivating child.");
                if (suspendCount != 1)
                    throw new InvalidOperationException("The owned child start thread had an unexpected suspend count.");
                return child;
            }
            catch
            {
                // On any startup failure, terminate only the process handle returned by this CreateProcessW.
                TerminateProcess(exactProcess, 1);
                if (WaitForSingleObject(exactProcess, 2000) != 0)
                    LogManager.Log("[Guardian] owned nonactivating child cleanup did not observe process exit");
                child?.Dispose();
                throw;
            }
        }

        public void Dispose() { _handle.Dispose(); }

        [StructLayout(LayoutKind.Sequential)]
        private struct StartupWindow
        {
            public uint Size;
            public IntPtr Reserved, Desktop, Title;
            public uint X, Y, Width, Height, Columns, Rows, FillAttributes, Flags;
            public ushort Show, ReservedBytes;
            public IntPtr ReservedData, StandardInput, StandardOutput, StandardError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation
        {
            public IntPtr Process, Thread;
            public int ProcessId, ThreadId;
        }

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

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint creationFlags,
            IntPtr environment, string directory, ref StartupWindow startup, out ProcessInformation information);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(SafeWaitHandle thread);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(SafeProcessHandle process, uint exitCode);

        [DllImport("kernel32.dll")]
        private static extern uint WaitForSingleObject(SafeProcessHandle process, uint milliseconds);
    }
}
