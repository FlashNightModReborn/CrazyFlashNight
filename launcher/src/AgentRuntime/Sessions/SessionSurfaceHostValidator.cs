using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Sessions
{
    internal sealed class SessionSurfaceValidationContext
    {
        public SessionSurfaceValidationContext(
            SessionProcessIdentity launcherProcess,
            SessionProcessIdentity flashProcess,
            Func<string, SessionSurfaceSnapshot> resolveRegisteredSurface)
        {
            LauncherProcess = launcherProcess;
            FlashProcess = flashProcess;
            ResolveRegisteredSurface = resolveRegisteredSurface
                ?? throw new ArgumentNullException(
                    nameof(resolveRegisteredSurface));
        }

        public SessionProcessIdentity LauncherProcess { get; }
        public SessionProcessIdentity FlashProcess { get; }
        public Func<string, SessionSurfaceSnapshot> ResolveRegisteredSurface { get; }
    }

    internal interface ISessionSurfaceHostValidator
    {
        bool ValidateSession(
            SessionRegistryHostOwner hostOwner,
            SessionHostRegistration registration,
            out string reasonCode);

        bool ValidateAttemptProcess(
            SessionRegistryHostOwner hostOwner,
            SessionProcessIdentity flashProcess,
            out string reasonCode);

        bool ValidateSurface(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceValidationContext context,
            SessionSurfaceHostRegistration registration,
            out string reasonCode);
    }

    internal interface ISessionProcessProbe
    {
        bool IsExactProcess(SessionProcessIdentity expected);

        bool IsDirectChildProcess(
            SessionProcessIdentity child,
            SessionProcessIdentity parent);
    }

    internal sealed class SystemSessionProcessProbe : ISessionProcessProbe
    {
        public bool IsExactProcess(SessionProcessIdentity expected)
        {
            if (expected == null) return false;
            try
            {
                using Process process =
                    Process.GetProcessById(expected.ProcessId);
                if (process.HasExited) return false;
                DateTimeOffset startTime =
                    new DateTimeOffset(process.StartTime.ToUniversalTime());
                string path = process.MainModule?.FileName;
                return startTime.UtcDateTime.Ticks
                        == expected.StartTimeUtc.UtcDateTime.Ticks
                    && path != null
                    && string.Equals(
                        Path.GetFullPath(path),
                        expected.ExecutablePath,
                        StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception exception) when (
                exception is ArgumentException
                || exception is InvalidOperationException
                || exception is Win32Exception
                || exception is NotSupportedException)
            {
                return false;
            }
        }

        public bool IsDirectChildProcess(
            SessionProcessIdentity child,
            SessionProcessIdentity parent)
        {
            if (child == null
                || parent == null
                || !IsExactProcess(child)
                || !IsExactProcess(parent))
            {
                return false;
            }

            IntPtr snapshot = CreateToolhelp32Snapshot(
                Th32csSnapProcess,
                0);
            if (snapshot == InvalidHandleValue)
                return false;
            try
            {
                var entry = new ProcessEntry32
                {
                    Size = checked(
                        (uint)Marshal.SizeOf<ProcessEntry32>())
                };
                if (!Process32First(snapshot, ref entry))
                    return false;
                do
                {
                    if (entry.ProcessId == child.ProcessId)
                    {
                        return entry.ParentProcessId
                            == parent.ProcessId;
                    }
                    entry.Size = checked(
                        (uint)Marshal.SizeOf<ProcessEntry32>());
                }
                while (Process32Next(snapshot, ref entry));
                return false;
            }
            finally
            {
                CloseHandle(snapshot);
            }
        }

        private const uint Th32csSnapProcess = 0x00000002;
        private static readonly IntPtr InvalidHandleValue =
            new IntPtr(-1);

        [StructLayout(
            LayoutKind.Sequential,
            CharSet = CharSet.Unicode)]
        private struct ProcessEntry32
        {
            public uint Size;
            public uint Usage;
            public int ProcessId;
            public IntPtr DefaultHeapId;
            public uint ModuleId;
            public uint ThreadCount;
            public int ParentProcessId;
            public int BasePriority;
            public uint Flags;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string ExecutableFile;
        }

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(
            uint flags,
            uint processId);

        [DllImport(
            "kernel32.dll",
            EntryPoint = "Process32FirstW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32First(
            IntPtr snapshot,
            ref ProcessEntry32 entry);

        [DllImport(
            "kernel32.dll",
            EntryPoint = "Process32NextW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32Next(
            IntPtr snapshot,
            ref ProcessEntry32 entry);

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }

    internal interface ISessionWindowProbe
    {
        bool TryGetOwnerProcessId(long windowHandle, out int processId);
        long GetOwnerWindow(long windowHandle);
    }

    internal sealed class WindowsSessionWindowProbe : ISessionWindowProbe
    {
        private const uint GwOwner = 4;

        public bool TryGetOwnerProcessId(
            long windowHandle,
            out int processId)
        {
            processId = 0;
            if (windowHandle <= 0) return false;
            uint threadId = GetWindowThreadProcessId(
                new IntPtr(windowHandle),
                out uint rawProcessId);
            if (threadId == 0
                || rawProcessId == 0
                || rawProcessId > int.MaxValue)
            {
                return false;
            }
            processId = checked((int)rawProcessId);
            return true;
        }

        public long GetOwnerWindow(long windowHandle)
        {
            if (windowHandle <= 0) return 0;
            return GetWindow(
                new IntPtr(windowHandle),
                GwOwner).ToInt64();
        }

        [DllImport(
            "user32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(
            IntPtr windowHandle,
            out uint processId);

        [DllImport(
            "user32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        private static extern IntPtr GetWindow(
            IntPtr windowHandle,
            uint command);
    }

    /// <summary>
    /// Production validation uses exact PID/start-time/path and HWND ownership.
    /// It intentionally has no window-title or executable-name fallback.
    /// </summary>
    internal sealed class WindowsSessionSurfaceHostValidator
        : ISessionSurfaceHostValidator
    {
        private readonly ISessionProcessProbe _processProbe;
        private readonly ISessionWindowProbe _windowProbe;

        public WindowsSessionSurfaceHostValidator(
            ISessionProcessProbe processProbe = null,
            ISessionWindowProbe windowProbe = null)
        {
            _processProbe = processProbe ?? new SystemSessionProcessProbe();
            _windowProbe = windowProbe ?? new WindowsSessionWindowProbe();
        }

        public bool ValidateSession(
            SessionRegistryHostOwner hostOwner,
            SessionHostRegistration registration,
            out string reasonCode)
        {
            if (hostOwner == null
                || registration?.LauncherProcess == null
                || !hostOwner.LauncherProcess.IsExact(
                    registration.LauncherProcess))
            {
                reasonCode = "launcher_owner_mismatch";
                return false;
            }
            if (!_processProbe.IsExactProcess(registration.LauncherProcess))
            {
                reasonCode = "launcher_process_stale";
                return false;
            }
            if (registration.FlashProcess != null
                && !_processProbe.IsExactProcess(registration.FlashProcess))
            {
                reasonCode = "flash_process_stale";
                return false;
            }
            if (registration.FlashProcess != null
                && !_processProbe.IsDirectChildProcess(
                    registration.FlashProcess,
                    registration.LauncherProcess))
            {
                reasonCode = "flash_parent_process_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        public bool ValidateAttemptProcess(
            SessionRegistryHostOwner hostOwner,
            SessionProcessIdentity flashProcess,
            out string reasonCode)
        {
            if (hostOwner == null)
            {
                reasonCode = "launcher_owner_mismatch";
                return false;
            }
            if (flashProcess != null
                && !_processProbe.IsExactProcess(flashProcess))
            {
                reasonCode = "flash_process_stale";
                return false;
            }
            if (flashProcess != null
                && !_processProbe.IsDirectChildProcess(
                    flashProcess,
                    hostOwner.LauncherProcess))
            {
                reasonCode = "flash_parent_process_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        public bool ValidateSurface(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceValidationContext context,
            SessionSurfaceHostRegistration registration,
            out string reasonCode)
        {
            if (hostOwner == null
                || context == null
                || registration?.OwnerProcess == null)
            {
                reasonCode = "surface_owner_unverifiable";
                return false;
            }
            if (!_processProbe.IsExactProcess(registration.OwnerProcess))
            {
                reasonCode = "surface_owner_process_stale";
                return false;
            }
            if (!_windowProbe.TryGetOwnerProcessId(
                    registration.WindowHandle,
                    out int observedOwnerProcessId)
                || observedOwnerProcessId
                    != registration.OwnerProcess.ProcessId)
            {
                reasonCode = "surface_hwnd_owner_mismatch";
                return false;
            }

            SessionProcessIdentity expectedOwner =
                ExpectedOwnerProcess(context, registration.OwnerRelation);
            if (expectedOwner != null
                && !expectedOwner.IsExact(registration.OwnerProcess))
            {
                reasonCode = "surface_process_relation_mismatch";
                return false;
            }

            if (registration.OwnerRelation
                    == SessionSurfaceOwnerRelation.LauncherOwned
                || registration.OwnerRelation
                    == SessionSurfaceOwnerRelation.FlashOwned)
            {
                SessionSurfaceSnapshot ownerSurface =
                    context.ResolveRegisteredSurface(
                        registration.OwnerTargetId);
                if (ownerSurface == null
                    || ownerSurface.SafetyKind
                        != AgentTargetSafetyKind.RuntimeOwned
                    || ownerSurface.WindowHandle
                        != registration.OwnerWindowHandle
                    || _windowProbe.GetOwnerWindow(
                        registration.WindowHandle)
                        != registration.OwnerWindowHandle)
                {
                    reasonCode = "surface_window_owner_relation_mismatch";
                    return false;
                }
            }
            else if (registration.OwnerRelation
                    == SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported
                && registration.OwnerWindowHandle != 0
                && _windowProbe.GetOwnerWindow(
                    registration.WindowHandle)
                    != registration.OwnerWindowHandle)
            {
                reasonCode =
                    "surface_window_owner_relation_mismatch";
                return false;
            }

            reasonCode = null;
            return true;
        }

        private static SessionProcessIdentity ExpectedOwnerProcess(
            SessionSurfaceValidationContext context,
            SessionSurfaceOwnerRelation relation)
        {
            return relation switch
            {
                SessionSurfaceOwnerRelation.LauncherTopLevel =>
                    context.LauncherProcess,
                SessionSurfaceOwnerRelation.LauncherOwned =>
                    context.LauncherProcess,
                SessionSurfaceOwnerRelation.RuntimeOverlay =>
                    context.LauncherProcess,
                SessionSurfaceOwnerRelation.FlashTopLevel =>
                    context.FlashProcess,
                SessionSurfaceOwnerRelation.FlashOwned =>
                    context.FlashProcess,
                SessionSurfaceOwnerRelation.HumanOnlySecurityReported =>
                    null,
                _ => null
            };
        }
    }
}
