// UiFreezeProbe — independent background probe for UI-thread watchdog stalls.
//
// This probe is observational only. It never changes foreground focus and never
// calls any focus recovery path; it records whether the UI-thread Forms.Timer
// stopped ticking while the system foreground is NULL or Windows marks a window
// as hung.
//
// C# 5 / net462.

using System;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Diagnostic
{
    public sealed class UiFreezeProbe : IDisposable
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsHungAppWindow(IntPtr hWnd);

        private const int PollIntervalMs = 1000;
        private const int VacuumReportThresholdSec = 3;
        private const int VacuumReportIntervalSec = 10;
        private const int UiStaleThresholdMs = 2000;
        private const int UiStaleReportIntervalMs = 10000;
        private const int HungReportIntervalMs = 10000;

        private readonly Func<IntPtr> _guardianHwndProvider;
        private readonly Func<IntPtr> _flashHwndProvider;
        private readonly Func<int> _lastWatchdogTickProvider;
        private readonly Func<bool> _isSuspendedProvider;

        private Thread _thread;
        private volatile bool _stopRequested;
        private int _started;
        private int _vacuumSeconds;
        private int _lastVacuumReportSecond;
        private int _lastUiStaleReportTick;
        private int _lastHungReportTick;
        private bool _lastGuardianHung;
        private bool _lastFlashHung;
        // 闪退诊断: 跟踪 stale 边界, 给出 enter / exit 配对日志, 方便算冻结总时长 + 对齐外部事件
        private bool _inStale;
        private int _staleEnterTick;
        private int _staleMaxAge;
        private IntPtr _staleEnterFg;

        public UiFreezeProbe(
            Func<IntPtr> guardianHwndProvider,
            Func<IntPtr> flashHwndProvider,
            Func<int> lastWatchdogTickProvider,
            Func<bool> isSuspendedProvider)
        {
            _guardianHwndProvider = guardianHwndProvider;
            _flashHwndProvider = flashHwndProvider;
            _lastWatchdogTickProvider = lastWatchdogTickProvider;
            _isSuspendedProvider = isSuspendedProvider;
        }

        public void Start()
        {
            if (Interlocked.Exchange(ref _started, 1) != 0) return;

            // 紧急刹车: 默认 ON, 仅在 env 显式置 "0"/"false" 时跳过后台线程启动。
            // 玩家版作为"黑匣子"永久保留——不暴露 toml 开关避免误关。
            // 触发条件示例: 怀疑探针自身在某机型与杀软 / 反作弊驱动交互不可预期时。
            if (IsDisabledByEnv())
            {
                LogManager.Log("[UIFreezeProbe] disabled by env CF7_DIAG_FOCUS_PROBE");
                return;
            }

            _stopRequested = false;
            _thread = new Thread(Run);
            _thread.IsBackground = true;
            _thread.Name = "UIFreezeProbe";
            _thread.Start();
        }

        private static bool IsDisabledByEnv()
        {
            string v;
            try { v = Environment.GetEnvironmentVariable("CF7_DIAG_FOCUS_PROBE"); }
            catch { return false; }
            if (string.IsNullOrEmpty(v)) return false;
            v = v.Trim();
            return v == "0" || string.Equals(v, "false", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "off", StringComparison.OrdinalIgnoreCase)
                || string.Equals(v, "no", StringComparison.OrdinalIgnoreCase);
        }

        public void Stop()
        {
            _stopRequested = true;
            Thread t = _thread;
            _thread = null;
            if (t != null)
            {
                try
                {
                    if (!t.Join(1500))
                        t.Interrupt();
                }
                catch { }
            }
            Interlocked.Exchange(ref _started, 0);
        }

        public void Dispose()
        {
            Stop();
        }

        private void Run()
        {
            LogManager.Log("[UIFreezeProbe] started interval=" + PollIntervalMs + "ms");
            while (!_stopRequested)
            {
                try
                {
                    Thread.Sleep(PollIntervalMs);
                    Sample();
                }
                catch (ThreadInterruptedException)
                {
                    return;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[UIFreezeProbe] sample_failed " + ex.GetType().Name + ": " + ex.Message);
                }
            }
        }

        private void Sample()
        {
            if (_isSuspendedProvider != null && _isSuspendedProvider())
            {
                ResetTransientState();
                return;
            }

            int lastWatchdogTick = (_lastWatchdogTickProvider != null)
                ? _lastWatchdogTickProvider()
                : 0;
            if (lastWatchdogTick == 0)
            {
                ResetTransientState();
                return;
            }

            int now = Environment.TickCount;
            int uiTickAge = ElapsedMs(lastWatchdogTick, now);
            IntPtr fg = GetForegroundWindow();

            if (fg == IntPtr.Zero)
            {
                _vacuumSeconds++;
                if (_vacuumSeconds >= VacuumReportThresholdSec
                    && (_lastVacuumReportSecond == 0
                        || _vacuumSeconds - _lastVacuumReportSecond >= VacuumReportIntervalSec))
                {
                    _lastVacuumReportSecond = _vacuumSeconds;
                    LogManager.Log("[UIFreezeProbe] vacuum_seen seconds=" + _vacuumSeconds
                        + " ui_tick_age=" + uiTickAge + "ms");
                }
            }
            else
            {
                _vacuumSeconds = 0;
                _lastVacuumReportSecond = 0;
            }

            IntPtr guardianHwnd = SafeHandle(_guardianHwndProvider);
            IntPtr flashHwnd = SafeHandle(_flashHwndProvider);
            bool guardianHung = IsHung(guardianHwnd);
            bool flashHung = IsHung(flashHwnd);
            if (guardianHung || flashHung)
            {
                bool hungChanged = guardianHung != _lastGuardianHung
                    || flashHung != _lastFlashHung;
                bool reportDue = _lastHungReportTick == 0
                    || ElapsedMs(_lastHungReportTick, now) >= HungReportIntervalMs;
                if (hungChanged || reportDue)
                {
                    _lastHungReportTick = now;
                    _lastGuardianHung = guardianHung;
                    _lastFlashHung = flashHung;
                    LogManager.Log("[UIFreezeProbe] hung_window flash=" + flashHung
                        + " guardian=" + guardianHung
                        + " flashHwnd=" + FormatHwnd(flashHwnd)
                        + " guardianHwnd=" + FormatHwnd(guardianHwnd));
                }
            }
            else
            {
                _lastGuardianHung = false;
                _lastFlashHung = false;
            }

            if (uiTickAge > UiStaleThresholdMs)
            {
                if (!_inStale)
                {
                    // enter: 一次性事件, 标出冻结起点
                    _inStale = true;
                    _staleEnterTick = now;
                    _staleEnterFg = fg;
                    _staleMaxAge = uiTickAge;
                    LogManager.Log("[UIFreezeProbe] ui_stale_enter age=" + uiTickAge
                        + "ms fg=" + FormatHwnd(fg));
                }
                else
                {
                    if (uiTickAge > _staleMaxAge) _staleMaxAge = uiTickAge;
                }

                if (ShouldReport(ref _lastUiStaleReportTick, now, UiStaleReportIntervalMs))
                {
                    LogManager.Log("[UIFreezeProbe] ui_thread_stale age=" + uiTickAge
                        + "ms fg=" + FormatHwnd(fg));
                }
            }
            else if (_inStale)
            {
                // exit: 冻结期总时长 = 从 enter 到现在; 期间 max age = UI 线程最长一次没 tick 的间隔
                int frozenWallMs = ElapsedMs(_staleEnterTick, now);
                LogManager.Log("[UIFreezeProbe] ui_stale_exit wall=" + frozenWallMs
                    + "ms maxAge=" + _staleMaxAge
                    + "ms enterFg=" + FormatHwnd(_staleEnterFg)
                    + " exitFg=" + FormatHwnd(fg));
                _inStale = false;
                _staleEnterTick = 0;
                _staleMaxAge = 0;
                _staleEnterFg = IntPtr.Zero;
                _lastUiStaleReportTick = 0;  // 下次再 stale 立即 report, 不卡 10s 节流
            }
        }

        private void ResetTransientState()
        {
            _vacuumSeconds = 0;
            _lastVacuumReportSecond = 0;
            _lastGuardianHung = false;
            _lastFlashHung = false;
            // suspend / watchdog 未就绪期间, stale 状态强制重置
            // (suspended 复原后才重新进入 stale 边界跟踪, 避免 enter 后无 exit)
            _inStale = false;
            _staleEnterTick = 0;
            _staleMaxAge = 0;
            _staleEnterFg = IntPtr.Zero;
        }

        private static bool IsHung(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return false;
            try { return IsHungAppWindow(hWnd); }
            catch { return false; }
        }

        private static IntPtr SafeHandle(Func<IntPtr> provider)
        {
            if (provider == null) return IntPtr.Zero;
            try { return provider(); }
            catch { return IntPtr.Zero; }
        }

        private static bool ShouldReport(ref int lastReportTick, int now, int intervalMs)
        {
            if (lastReportTick == 0 || ElapsedMs(lastReportTick, now) >= intervalMs)
            {
                lastReportTick = now;
                return true;
            }
            return false;
        }

        private static int ElapsedMs(int startTick, int nowTick)
        {
            int elapsed = unchecked(nowTick - startTick);
            return elapsed < 0 ? int.MaxValue : elapsed;
        }

        private static string FormatHwnd(IntPtr hWnd)
        {
            return "0x" + hWnd.ToInt64().ToString("X");
        }
    }
}
