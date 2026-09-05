using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Threading;
using CF7Launcher.Guardian;
using Newtonsoft.Json;

namespace CF7Launcher.Diagnostic
{
    // 仅观察边界事件。钩子/UI 线程只入有界队列，既不写盘也不发送业务命令。
    internal static class FocusTrace
    {
        internal const int Capacity = 256;
        internal const int EventBudget = 8000;
        private static readonly object Gate = new object();
        private static readonly Queue<string> Pending = new Queue<string>();
        private static Timer _timer;
        private static Action<string> _sink;
        private static long _sequence, _lost, _mouseSequence, _hudSequence;
        private static long _deadline;
        private static int _flushing;
        private static Rectangle _target;
        private static string _physicalDown;
        private static Point _physicalPoint;
        private static long _physicalAt;
        private static bool _physicalAvailable;
        [ThreadStatic] private static string _gesture;
        internal static bool Enabled { get; private set; }
        internal static string Session { get; private set; }
        internal static string Gesture { get { return _gesture; } }

        internal static void StartFromEnvironment()
        {
            if (Environment.GetEnvironmentVariable("CF7_FOCUS_TRACE") == "1")
                Start(LogManager.Log, true);
        }

        internal static void Start(Action<string> sink, bool useTimer)
        {
            Stop();
            lock (Gate)
            {
                Pending.Clear();
                _sequence = _lost = _mouseSequence = _hudSequence = 0;
                _physicalDown = null;
                _physicalAvailable = false;
                _target = Rectangle.Empty;
                _gesture = null;
                Session = Guid.NewGuid().ToString("N");
                _sink = sink;
                _deadline = Environment.TickCount64 + 30 * 60 * 1000;
                Enabled = true;
            }
            Record("trace.start", new { capacity = Capacity, budget = EventBudget,
                durationMinutes = 30, corePath = typeof(FocusTrace).Assembly.Location,
                pid = Environment.ProcessId, externalReceiver = "unknown" });
            if (useTimer) _timer = new Timer(_ => Flush(), null, 500, 500);
        }

        internal static void Record(string name, object data = null, string gesture = null)
        {
            if (!Enabled) return;
            try
            {
                lock (Gate)
                {
                    if (!Enabled) return;
                    if (_sequence >= EventBudget || Environment.TickCount64 >= _deadline)
                    {
                        name = "trace.limit";
                        data = new { reason = _sequence >= EventBudget ? "event_budget" : "duration" };
                        Enabled = false;
                    }
                    string line = "[FocusTrace] " + JsonConvert.SerializeObject(new {
                        v = 1, session = Session, seq = ++_sequence,
                        utc = DateTime.UtcNow.ToString("O"), ticks = Stopwatch.GetTimestamp(),
                        frequency = Stopwatch.Frequency, tid = Environment.CurrentManagedThreadId,
                        @event = name, gesture = gesture ?? _gesture, data
                    });
                    if (Pending.Count == Capacity) { Pending.Dequeue(); _lost++; }
                    Pending.Enqueue(line);
                }
            }
            catch { /* 观察失败不得改变输入、转场或耐久门。 */ }
        }

        internal static void Flush()
        {
            if (Interlocked.Exchange(ref _flushing, 1) != 0) return;
            try
            {
                string batch;
                lock (Gate)
                {
                    if (Pending.Count == 0 && _lost == 0) return;
                    var lines = new List<string>(Pending.Count + 1);
                    if (_lost > 0)
                        lines.Add("[FocusTrace] " + JsonConvert.SerializeObject(new {
                            v = 1, session = Session, @event = "trace.dropped", count = _lost }));
                    _lost = 0;
                    while (Pending.Count > 0) lines.Add(Pending.Dequeue());
                    batch = string.Join(Environment.NewLine, lines);
                }
                try { _sink?.Invoke(batch); } catch { }
            }
            finally { Volatile.Write(ref _flushing, 0); }
        }

        internal static void Stop()
        {
            _timer?.Dispose();
            _timer = null;
            Record("trace.stop");
            lock (Gate) { Enabled = false; }
            Flush();
        }

        internal static IDisposable UseGesture(string gesture)
        {
            return new GestureScope(gesture);
        }

        private sealed class GestureScope : IDisposable
        {
            private readonly string _previous = _gesture;
            internal GestureScope(string value) { _gesture = value; }
            public void Dispose() { _gesture = _previous; }
        }

        internal static void SetTarget(Rectangle target) { _target = target; }

        internal static void PhysicalEdge(int message, Point point, uint flags, uint time, int panelGeneration)
        {
            if (!Enabled || (message != 0x0201 && message != 0x0202)) return;
            // 只观察右侧条件槽区域；释放可在区域外。没有全桌面点击历史。
            if (message == 0x0201)
            {
                _physicalAvailable = false;
                _physicalDown = null;
                if (!_target.Contains(point)) return;
                _physicalDown = "mouse." + Interlocked.Increment(ref _mouseSequence);
                _physicalPoint = point;
                _physicalAt = Environment.TickCount64;
                _physicalAvailable = true;
            }
            if (_physicalDown == null) return;
            Record(message == 0x0201 ? "mouse.down" : "mouse.up", new {
                mouseId = _physicalDown, point, hookTime = time, flags,
                injected = (flags & 1) != 0, panelGeneration,
                windows = FocusWindowSnapshot.At(point)
            });
            if (message == 0x0202) { _physicalAvailable = false; _physicalDown = null; }
        }

        internal static string HudDown(Point point, IntPtr receiver, string widget)
        {
            string id = "hud." + Interlocked.Increment(ref _hudSequence);
            bool match = _physicalAvailable && _physicalPoint == point
                && Environment.TickCount64 - _physicalAt <= 2000;
            Record("hud.down", new { receiver = receiver.ToInt64(), widget, point,
                mouseId = match ? _physicalDown : null,
                correlation = match ? "position_time_candidate" : "unobserved",
                windows = FocusWindowSnapshot.At(point) }, id);
            _physicalAvailable = false;
            return id;
        }
    }
}
