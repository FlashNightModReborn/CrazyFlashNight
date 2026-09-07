using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Threading;
using System.IO;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    // 仅观察边界事件。钩子/UI 线程只入有界队列，既不写盘也不发送业务命令。
    internal static class FocusTrace
    {
        internal const int Capacity = 256;
        internal const int EventBudget = 8000;
        private static readonly object Gate = new object();
        private static readonly object FlushGate = new object();
        private static readonly Queue<string> Pending = new Queue<string>();
        private static Timer _timer;
        private static Action<string> _sink;
        private static long _sequence, _lost, _mouseSequence, _hudSequence;
        private static long _deadline;
        private static RollingFocusLog _rollingLog;
        private static string _recordingRoot;
        internal static bool IsRolling { get; private set; }
        private static Rectangle _target;
        private static string _physicalDown;
        private static Point _physicalPoint;
        private static long _physicalAt;
        private static bool _physicalAvailable;
        private static string _nativeMouseId;
        private static Point _nativePoint;
        private static long _nativeAt;
        private static int _nativeHitTests;
        [ThreadStatic] private static int _snapshotDepth;
        internal static Func<Point, object> HudInputSnapshot;
        [ThreadStatic] private static string _gesture;
        internal static bool Enabled { get; private set; }
        internal static string Session { get; private set; }
        internal static string Gesture { get { return _gesture; } }

        internal static void StartConfigured(bool enabled, string projectRoot)
        {
            Stop();
            if (!enabled) return;
            RollingFocusLog recording = null;
            try
            {
                string session = Guid.NewGuid().ToString("N");
                string core = typeof(FocusTrace).Assembly.Location;
                using (Process process = Process.GetCurrentProcess())
                {
                    var context = new JObject { ["schema"] = "cf7-focus-recording.v1", ["session"] = session,
                        ["mode"] = "rolling", ["startedAtUtc"] = DateTime.UtcNow.ToString("O"),
                        ["runtimeMode"] = string.Equals(Path.GetFullPath(core), Path.GetFullPath(Path.Combine(projectRoot,
                            "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.dll")), StringComparison.OrdinalIgnoreCase)
                                ? "formal_runtime" : "isolated_or_test",
                        ["process"] = new JObject { ["pid"] = Environment.ProcessId, ["path"] = Environment.ProcessPath,
                            ["startedAtUtc"] = process.StartTime.ToUniversalTime().ToString("O") },
                        ["files"] = new JArray(FileIdentity(core, core),
                            FileIdentity(Path.Combine(projectRoot, "scripts", "asLoader.swf"), "scripts/asLoader.swf"),
                            FileIdentity(Path.Combine(projectRoot, "runtime", "cf7-runtime-manifest.tsv"), "runtime/cf7-runtime-manifest.tsv")) };
                    recording = new RollingFocusLog(Path.Combine(projectRoot, "logs", "focus-trace"), context);
                    Start(recording.Append, true, true, session);
                    _rollingLog = recording;
                    _recordingRoot = projectRoot;
                }
                LogManager.Log("[FocusRecording] enabled mode=rolling files=3 bytesPerFile=8388608 session=" + Session);
            }
            catch (Exception ex)
            {
                try { recording?.Dispose(); } catch { }
                Stop();
                LogManager.Log("[FocusRecording] start failed: " + ex.Message);
            }
        }

        private static JObject FileIdentity(string path, string label)
        {
            return new JObject { ["path"] = label,
                ["sha256"] = File.Exists(path) ? Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))) : null };
        }

        internal static void Start(Action<string> sink, bool useTimer, bool rolling = false, string session = null)
        {
            Stop();
            lock (Gate)
            {
                Pending.Clear();
                _sequence = _lost = _mouseSequence = _hudSequence = 0;
                _physicalDown = null;
                _physicalAvailable = false;
                _nativeMouseId = null;
                _nativeHitTests = 0;
                _target = Rectangle.Empty;
                _gesture = null;
                Session = session ?? Guid.NewGuid().ToString("N");
                IsRolling = rolling;
                _sink = sink;
                _deadline = Environment.TickCount64 + 30 * 60 * 1000;
                Enabled = true;
            }
            Record("trace.start", new { capacity = Capacity, budget = rolling ? (int?)null : EventBudget,
                durationMinutes = rolling ? (int?)null : 30, recordingMode = rolling ? "rolling" : "bounded",
                nativeInputObservation = 1, corePath = typeof(FocusTrace).Assembly.Location,
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
                    if (!IsRolling && (_sequence >= EventBudget || Environment.TickCount64 >= _deadline))
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

        internal static void Flush(bool wait = false)
        {
            if (wait) Monitor.Enter(FlushGate);
            else if (!Monitor.TryEnter(FlushGate)) return;
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
                try { _sink?.Invoke(batch); }
                catch (Exception ex)
                {
                    if (_rollingLog != null)
                    {
                        lock (Gate) { Enabled = false; }
                        _rollingLog.MarkError(ex.Message);
                        LogManager.Log("[FocusRecording] write failed, recording stopped: " + ex.Message);
                    }
                }
            }
            finally { Monitor.Exit(FlushGate); }
        }

        internal static void Stop()
        {
            _timer?.Dispose();
            _timer = null;
            Record("trace.stop");
            lock (Gate) { Enabled = false; }
            Flush(true);
            RollingFocusLog recording = _rollingLog;
            _rollingLog = null;
            _recordingRoot = null;
            try { recording?.Dispose(); } catch { }
        }

        internal static void Shutdown(Action<ProcessStartInfo> startCollector = null)
        {
            string root = _recordingRoot;
            string session = Session;
            Stop();
            if (root != null) FocusExitCollector.Start(root, session, startCollector);
        }

        internal static void CaptureAs2LogBatch(string decoded)
        {
            if (!Enabled || !IsRolling || string.IsNullOrEmpty(decoded)) return;
            string marker = "[FocusTraceAS2] session=" + Session + " ";
            foreach (Match match in Regex.Matches(decoded, Regex.Escape(marker) + @"[^|&\r\n]*"))
                Record("as2.observation", new { source = "http_log_batch", raw = match.Value });
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

        internal static string PhysicalEdge(int message, Point point, uint flags, uint time, int panelGeneration)
        {
            if (!Enabled || (message != 0x0201 && message != 0x0202)) return null;
            // 只观察右侧条件槽区域；释放可在区域外。没有全桌面点击历史。
            if (message == 0x0201)
            {
                _physicalAvailable = false;
                _physicalDown = null;
                if (!_target.Contains(point)) { _nativeMouseId = null; return null; }
                _physicalDown = "mouse." + Interlocked.Increment(ref _mouseSequence);
                _physicalPoint = point;
                _physicalAt = Environment.TickCount64;
                _physicalAvailable = true;
                _nativeMouseId = _physicalDown;
                _nativeHitTests = 0;
            }
            if (_physicalDown == null) return null;
            string mouseId = _physicalDown;
            _nativePoint = point;
            _nativeAt = Environment.TickCount64;
            Record(message == 0x0201 ? "mouse.down" : "mouse.up", new {
                mouseId, point, hookTime = time, flags,
                injected = (flags & 1) != 0, panelGeneration,
                windows = FocusWindowSnapshot.At(point),
                hudInput = message == 0x0201 ? CaptureHudInput(point) : null
            });
            if (message == 0x0202) { _physicalAvailable = false; _physicalDown = null; }
            return mouseId;
        }

        // 只解释后续 hook 链的返回值，不识别拦截者，也不改变/重放输入。
        internal static void HookChainResult(string mouseId, int message, IntPtr result, long started, long observedAt = 0)
        {
            if (mouseId == null || !Enabled) return;
            Record("mouse.hook_chain_result", new { mouseId, message,
                nextHookResult = result.ToInt64(), suppressed = result != IntPtr.Zero,
                beforeNextMs = observedAt == 0 ? (double?)null : (started - observedAt) * 1000.0 / Stopwatch.Frequency,
                elapsedMs = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency });
        }

        internal static string NativeMouseCandidate(Point point)
        {
            return Enabled && _nativeMouseId != null && _nativePoint == point
                && Environment.TickCount64 - _nativeAt <= 2000 ? _nativeMouseId : null;
        }

        internal static bool ShouldTraceNativeHitTest(Point point)
        {
            // 不记录 MouseMove 历史；每次目标点击最多 8 次命中查询。
            if (_snapshotDepth != 0 || NativeMouseCandidate(point) == null || _nativeHitTests >= 8)
                return false;
            _nativeHitTests++;
            return true;
        }

        internal static object CaptureHudInput(Point point)
        {
            if (!Enabled) return null;
            try { return HudInputSnapshot?.Invoke(point); }
            catch { return new { unavailable = "snapshot_failed" }; }
        }

        internal static IDisposable ObserveSnapshot()
        {
            return new SnapshotScope();
        }

        private sealed class SnapshotScope : IDisposable
        {
            internal SnapshotScope() { _snapshotDepth++; }
            public void Dispose() { _snapshotDepth--; }
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
