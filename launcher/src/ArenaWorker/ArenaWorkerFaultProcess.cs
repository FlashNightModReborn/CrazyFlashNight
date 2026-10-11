using System;
using System.Diagnostics;
using System.IO;
using CF7Launcher.Bus;

namespace CF7Launcher.ArenaWorker
{
    internal interface IArenaWorkerFaultProcess : IDisposable
    {
        XmlSocketPeerProcessIdentity Identity { get; }
        bool IsAlive { get; }
        void Kill();
        bool WaitForExit(int timeoutMs);
    }

    // A private handle to the already-authoritative Flash process. The HTTP caller
    // never supplies a PID or an executable path and cannot select another process.
    internal sealed class ArenaWorkerFaultProcess : IArenaWorkerFaultProcess
    {
        private readonly Process _process;
        public XmlSocketPeerProcessIdentity Identity { get; }
        private ArenaWorkerFaultProcess(Process process, XmlSocketPeerProcessIdentity identity)
        {
            _process = process;
            Identity = identity;
        }

        internal static IArenaWorkerFaultProcess Open(XmlSocketPeerProcessIdentity expected, Process tracked)
        {
            if (expected == null || tracked == null || tracked.Id != expected.ProcessId)
                throw new InvalidOperationException("The currently owned Flash process is unavailable.");
            Process process = Process.GetProcessById(expected.ProcessId);
            try
            {
                _ = process.Handle; // Keep this exact OS process object through Kill and observation.
                string actualPath = Path.GetFullPath(process.MainModule.FileName);
                if (process.HasExited || process.StartTime.ToUniversalTime().Ticks != expected.StartTimeUtc.UtcTicks
                    || !string.Equals(actualPath, Path.GetFullPath(expected.ExecutablePath), StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("The owned Flash process identity changed.");
                return new ArenaWorkerFaultProcess(process, expected);
            }
            catch
            {
                process.Dispose();
                throw;
            }
        }

        public bool IsAlive => !_process.HasExited;
        public void Kill() => _process.Kill(entireProcessTree: false);
        public bool WaitForExit(int timeoutMs) => _process.WaitForExit(timeoutMs);
        public void Dispose() => _process.Dispose();
    }
}
