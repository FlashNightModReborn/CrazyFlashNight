using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Diagnostic
{
    internal static partial class FocusTrace
    {
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        private static FocusInputBuffer _input = new FocusInputBuffer();
        private static FocusMouseHistory _history = new FocusMouseHistory();
        private static long _invocations, _armedUntil;
        private static int _rawHitTests;
        internal static Action RefreshTargetCache;
        [ThreadStatic] private static int _nativeDepth;
        internal static long NextInvocation() { return Interlocked.Increment(ref _invocations); }
        internal static bool InputArmed => Enabled && Environment.TickCount64 <= Interlocked.Read(ref _armedUntil);

        internal static void Input(string name, InputData data, string gesture = null, long qpc = 0)
        {
            if (!Enabled) return;
            try
            {
                if (!IsRolling && (Interlocked.Read(ref _sequence) >= EventBudget || Environment.TickCount64 >= _deadline))
                { Record("trace.limit"); return; }
                _input.Add(new InputRow { name = name, data = data, gesture = gesture ?? _gesture,
                    sequence = Interlocked.Increment(ref _sequence), qpc = qpc == 0 ? Stopwatch.GetTimestamp() : qpc,
                    utc = DateTime.UtcNow, managedTid = Environment.CurrentManagedThreadId,
                    nativeTid = GetCurrentThreadId() });
            }
            catch { Interlocked.Increment(ref _inputErrors); }
        }
        private static long _inputErrors;

        internal static long NativeEnter(IntPtr hwnd, int message, IntPtr wp, IntPtr lp, long generation,
            uint time, uint pos, uint sent)
        {
            long id = NextInvocation();
            Input("input.wndproc", new InputData { receiver = hwnd.ToInt64(), message = message,
                wParam = wp.ToInt64(), lParam = lp.ToInt64(), generation = generation,
                invocationId = id, depth = ++_nativeDepth, phase = "enter", messageTime = time,
                messagePos = pos, sendFlags = sent, coordinateSource = _snapshotDepth == 0 ? "raw_message" : "diagnostic_query" });
            return id;
        }

        internal static void NativeExit(long id, IntPtr hwnd, int message, IntPtr wp, IntPtr lp,
            IntPtr result, long generation, long started)
        {
            Input("input.wndproc", new InputData { receiver = hwnd.ToInt64(), message = message,
                wParam = wp.ToInt64(), lParam = lp.ToInt64(), result = result.ToInt64(),
                generation = generation, invocationId = id, depth = _nativeDepth, phase = "exit",
                startedQpc = started, elapsedMs = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency });
            _nativeDepth--;
        }

        internal static bool ObserveMessage(int message)
        {
            if (message == 0x84)
            {
                if (!InputArmed) return false;
                int count = Interlocked.Increment(ref _rawHitTests);
                if (count == 129) Input("input.coverage_limit", new InputData { message = message, phase = "raw_hit_test", result = 128 });
                return count <= 128;
            }
            return message == 0x0201 || message == 0x0202 || message == 0x0203
                || (InputArmed && (message == 0x21 || message == 0x84 || message == 0x6
                    || message == 0x1c || message == 7 || message == 8 || message == 0x215
                    || message == 0x1f || message == 0x211 || message == 0x212
                    || message == 0x231 || message == 0x232 || message == 0x18));
        }
    }
}
