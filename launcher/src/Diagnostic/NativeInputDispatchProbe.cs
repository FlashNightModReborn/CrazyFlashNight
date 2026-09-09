using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace CF7Launcher.Diagnostic
{
    // Guardian UI 线程局部观察；从不接管消息循环、修改 MSG 或触发恢复。
    internal sealed class NativeInputDispatchProbe : IDisposable
    {
        internal const int HeartbeatMessage = 0x8000 + 0x3e7;
        private delegate IntPtr Hook(int code, IntPtr wp, IntPtr lp);
        [StructLayout(LayoutKind.Sequential)]
        internal struct NativeMessage
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam, lParam;
            public uint time;
            public int x, y;
        }
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, Hook callback, IntPtr module, uint tid);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wp, IntPtr lp);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool PostMessage(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] internal static extern int GetMessageTime();
        [DllImport("user32.dll")] internal static extern uint GetMessagePos();
        [DllImport("user32.dll")] internal static extern uint InSendMessageEx(IntPtr reserved);
        private readonly Hook _callback;
        private readonly IntPtr _hwnd;
        private IntPtr _hook;
        private System.Threading.Timer _timer;
        private long _token, _pending, _postedAt, _lastPoll, _lastReport;
        private readonly object _heartbeatGate = new object();
        private bool _disposed;
        internal NativeInputDispatchProbe(IntPtr hwnd)
        {
            _hwnd = hwnd;
            _callback = Callback;
            _hook = _failedUnhook == null ? SetWindowsHookEx(3, _callback, IntPtr.Zero, GetCurrentThreadId()) : IntPtr.Zero;
            int error = _hook == IntPtr.Zero && _failedUnhook == null ? Marshal.GetLastWin32Error() : 0;
            FocusTrace.Record("input.coverage", new { source = "WH_GETMESSAGE", nativeTid = GetCurrentThreadId(),
                installed = _hook != IntPtr.Zero, error, skippedPriorUnhookFailure = _failedUnhook != null,
                scope = "guardian_ui_thread_only", heartbeatMs = 200 });
            _timer = new System.Threading.Timer(_ => Poll(), null, 200, 200);
        }
        private IntPtr Callback(int code, IntPtr wp, IntPtr lp)
        {
            if (_disposed || code < 0) return CallNextHookEx(_hook, code, wp, lp);
            long invocation = FocusTrace.NextInvocation();
            bool observe = false;
            NativeMessage msg = default;
            try
            {
                if (code == 0 && FocusTrace.Enabled)
                {
                    msg = Marshal.PtrToStructure<NativeMessage>(lp);
                    observe = FocusTrace.ObserveMessage((int)msg.message) || msg.message == HeartbeatMessage;
                    if (observe) Record(msg, wp, invocation, "enter", IntPtr.Zero);
                }
            }
            catch { FocusTrace.Input("input.probe_error", new InputData { phase = "getmessage_enter" }); }
            IntPtr result = CallNextHookEx(_hook, code, wp, lp);
            if (observe)
            {
                try { Record(Marshal.PtrToStructure<NativeMessage>(lp), wp, invocation, "after_next_hook", result); }
                catch { FocusTrace.Input("input.probe_error", new InputData { phase = "getmessage_exit" }); }
            }
            return result;
        }
        private static void Record(NativeMessage msg, IntPtr removed, long id, string phase, IntPtr result)
        {
            FocusTrace.Input("input.getmessage", new InputData { phase = phase, invocationId = id,
                receiver = msg.hwnd.ToInt64(), message = (int)msg.message, wParam = msg.wParam.ToInt64(),
                lParam = msg.lParam.ToInt64(), messageTime = msg.time,
                point = new System.Drawing.Point(msg.x, msg.y), flags = unchecked((uint)removed.ToInt64()),
                result = result.ToInt64(), coordinateSource = "MSG.pt" });
        }
        private void Poll()
        {
            if (!Monitor.TryEnter(_heartbeatGate)) return;
            try
            {
                if (_disposed || !FocusTrace.Enabled) return;
                long now = Stopwatch.GetTimestamp();
                double pollMs = _lastPoll == 0 ? 0 : (now - _lastPoll) * 1000.0 / Stopwatch.Frequency;
                _lastPoll = now;
                long pending = Interlocked.Read(ref _pending);
                if (pending != 0)
                {
                    if ((now - _lastReport) * 1000.0 / Stopwatch.Frequency >= 1000)
                    {
                        _lastReport = now;
                        FocusTrace.Input("input.heartbeat_wait", new InputData { invocationId = pending,
                            receiver = _hwnd.ToInt64(), elapsedMs = (now - _postedAt) * 1000.0 / Stopwatch.Frequency,
                            beforeNextMs = pollMs, coordinateSource = "background_poll" });
                    }
                    return;
                }
                long token = ++_token;
                _postedAt = now;
                Interlocked.Exchange(ref _pending, token);
                FocusTrace.Input("input.heartbeat_post", new InputData { invocationId = token,
                    receiver = _hwnd.ToInt64(), beforeNextMs = pollMs });
                if (!PostMessage(_hwnd, HeartbeatMessage, new IntPtr(token), IntPtr.Zero))
                {
                    int error = Marshal.GetLastWin32Error();
                    Interlocked.CompareExchange(ref _pending, 0, token);
                    FocusTrace.Input("input.heartbeat_failed", new InputData { invocationId = token, error = error });
                }
            }
            catch { FocusTrace.Input("input.probe_error", new InputData { phase = "heartbeat" }); }
            finally { Monitor.Exit(_heartbeatGate); }
        }
        internal void Acknowledge(long token)
        {
            if (token == 0 || Interlocked.Read(ref _pending) != token) return;
            long posted = Interlocked.Read(ref _postedAt);
            FocusTrace.Input("input.heartbeat_ack", new InputData { invocationId = token,
                receiver = _hwnd.ToInt64(), elapsedMs = (Stopwatch.GetTimestamp() - posted) * 1000.0 / Stopwatch.Frequency });
            Interlocked.CompareExchange(ref _pending, 0, token);
            try { FocusTrace.RefreshTargetCache?.Invoke(); }
            catch { FocusTrace.Input("input.probe_error", new InputData { phase = "target_cache_refresh" }); }
        }
        public void Dispose()
        {
            lock (_heartbeatGate) { if (_disposed) return; _disposed = true; _timer?.Dispose(); _timer = null; }
            if (_hook != IntPtr.Zero)
            {
                bool ok = UnhookWindowsHookEx(_hook);
                int error = ok ? 0 : Marshal.GetLastWin32Error();
                FocusTrace.Record("input.coverage", new { source = "WH_GETMESSAGE", phase = "unhook", ok, error });
                // 失败时保活 delegate，避免仍安装的原生回调指向已回收地址。
                if (!ok) _failedUnhook = this;
                else _hook = IntPtr.Zero;
            }
        }
        [ThreadStatic] private static NativeInputDispatchProbe _failedUnhook;
    }
}
