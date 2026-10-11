using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.ArenaWorker
{
    internal interface IArenaWorkerWindowObservationApi
    {
        bool IsWindow(IntPtr window);
        bool IsVisible(IntPtr window);
        bool IsMinimized(IntPtr window);
        int OwnerProcessId(IntPtr window);
        IntPtr ForegroundWindow();
    }

    // A point observation of the already bound windows, with no activation,
    // enumeration, capture, input injection, or control-affinity calls.
    internal sealed class ArenaWorkerWindowObserver
    {
        private readonly IArenaWorkerWindowObservationApi _api;
        private readonly int _hostPid;
        private readonly IntPtr _guardian;
        private readonly Func<IntPtr> _flashWindow;
        private readonly Func<int> _flashPid;
        private readonly Func<PerformanceDisplayState> _performance;

        internal ArenaWorkerWindowObserver(IntPtr guardian, Func<IntPtr> flashWindow, Func<Process> flashProcess,
            Func<PerformanceDisplayState> performance = null)
            : this(new WindowsApi(), Environment.ProcessId, guardian, flashWindow, () => {
                try { return flashProcess()?.Id ?? 0; } catch { return 0; }
            }, performance) { }

        internal ArenaWorkerWindowObserver(IArenaWorkerWindowObservationApi api, int hostPid,
            IntPtr guardian, Func<IntPtr> flashWindow, Func<int> flashPid, Func<PerformanceDisplayState> performance = null)
        {
            _api = api; _hostPid = hostPid; _guardian = guardian;
            _flashWindow = flashWindow; _flashPid = flashPid;
            _performance = performance;
        }

        internal JObject CapturePerformance()
        {
            PerformanceDisplayState state = _performance?.Invoke();
            return new JObject {
                ["observed"] = state != null && state.Width > 0 && state.Height > 0,
                ["sampledAtUtc"] = DateTime.UtcNow.ToString("o"),
                ["preset"] = state?.Preset, ["mode"] = state?.Mode, ["status"] = state?.Status,
                ["width"] = state?.Width, ["height"] = state?.Height, ["quality"] = state?.Quality,
                ["effectLevel"] = state?.EffectLevel, ["reason"] = state?.Reason
            };
        }

        internal JObject Capture()
        {
            var result = new JObject { ["observed"] = false, ["sampledAtUtc"] = DateTime.UtcNow.ToString("o") };
            try
            {
                IntPtr flash = _flashWindow();
                int flashPid = _flashPid();
                IntPtr foreground = _api.ForegroundWindow();
                int foregroundPid = foreground == IntPtr.Zero ? 0 : _api.OwnerProcessId(foreground);
                result["guardianHwnd"] = Format(_guardian); result["flashHwnd"] = Format(flash);
                result["foregroundHwnd"] = Format(foreground); result["foregroundProcessId"] = foregroundPid;
                if (!Matches(_guardian, _hostPid) || !Matches(flash, flashPid))
                {
                    result["reason"] = "bound_window_unavailable";
                    return result;
                }
                result["guardianVisible"] = _api.IsVisible(_guardian);
                result["guardianMinimized"] = _api.IsMinimized(_guardian);
                result["flashVisible"] = _api.IsVisible(flash);
                result["flashMinimized"] = _api.IsMinimized(flash);
                result["hostForeground"] = foregroundPid == _hostPid;
                result["flashForeground"] = foregroundPid == flashPid;
                // Destruction or owner replacement during the sample invalidates it.
                bool stable = flash == _flashWindow() && flashPid == _flashPid()
                    && Matches(_guardian, _hostPid) && Matches(flash, flashPid);
                result["observed"] = stable;
                if (!stable) result["reason"] = "bound_window_changed_during_sample";
            }
            catch (Exception ex) { result["reason"] = "window_probe_" + ex.GetType().Name; }
            return result;
        }

        private bool Matches(IntPtr window, int pid) => window != IntPtr.Zero && pid > 0
            && _api.IsWindow(window) && _api.OwnerProcessId(window) == pid;
        private static string Format(IntPtr window) => "0x" + window.ToInt64().ToString("X");

        private sealed class WindowsApi : IArenaWorkerWindowObservationApi
        {
            [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
            [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
            [DllImport("user32.dll", EntryPoint = "IsWindow")] private static extern bool NativeIsWindow(IntPtr hwnd);
            [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
            public bool IsWindow(IntPtr window) => NativeIsWindow(window);
            public bool IsVisible(IntPtr window) => IsWindowVisible(window);
            public bool IsMinimized(IntPtr window) => IsIconic(window);
            public int OwnerProcessId(IntPtr window) { GetWindowThreadProcessId(window, out uint pid); return checked((int)pid); }
            public IntPtr ForegroundWindow() => GetForegroundWindow();
        }
    }
}
