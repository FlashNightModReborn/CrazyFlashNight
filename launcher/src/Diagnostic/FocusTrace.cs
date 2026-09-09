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
    internal static partial class FocusTrace
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
        private sealed class TargetCache
        {
            internal Rectangle bounds;
            internal long at;
            internal bool eligible;
        }
        private static TargetCache _target = new TargetCache();
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
                LogManager.Log("[FocusRecording] enabled mode=rolling files=3 bytesPerFile=6291456 incidentSlots=4 incidentBytes=1048576 session=" + Session);
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
                _input = new FocusInputBuffer();
                _history = new FocusMouseHistory();
                _inputErrors = _armedUntil = 0;
                _sequence = _lost = _mouseSequence = _hudSequence = 0;
                _nativeHitTests = _rawHitTests = 0;
                _target = new TargetCache();
                _skillKeys = Array.Empty<int>();
                _skillKeysAt = 0;
                _gesture = null;
                Session = session ?? Guid.NewGuid().ToString("N");
                IsRolling = rolling;
                _sink = sink;
                _deadline = Environment.TickCount64 + 30 * 60 * 1000;
                Enabled = true;
            }
            Record("trace.start", new { capacity = Capacity, budget = rolling ? (int?)null : EventBudget,
                durationMinutes = rolling ? (int?)null : 30, recordingMode = rolling ? "rolling" : "bounded",
                nativeInputObservation = 2, inputCapacity = FocusInputBuffer.Capacity, historyPairs = FocusMouseHistory.Capacity, historyMs = FocusMouseHistory.RetentionMs, corePath = typeof(FocusTrace).Assembly.Location,
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
                        v = 1, session = Session, seq = Interlocked.Increment(ref _sequence),
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
                var inputLines = _input.Drain(Session);
                string batch;
                lock (Gate)
                {
                    if (Pending.Count == 0 && _lost == 0 && inputLines.Count == 0) return;
                    var lines = new List<string>(Pending.Count + 1);
                    if (_lost > 0)
                        lines.Add("[FocusTrace] " + JsonConvert.SerializeObject(new {
                            v = 1, session = Session, @event = "trace.dropped", count = _lost }));
                    _lost = 0;
                    while (Pending.Count > 0) lines.Add(Pending.Dequeue());
                    lines.AddRange(inputLines);
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
            Record("trace.stop", new { inputErrors = Interlocked.Read(ref _inputErrors), historyOverwritten = _history.Overwritten });
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
            CaptureSkillLogBatch(decoded);
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

        internal static void SetTarget(Rectangle target, bool eligible = true)
        {
            Volatile.Write(ref _target, new TargetCache { bounds = target, eligible = eligible, at = Environment.TickCount64 });
        }

        internal static string PhysicalEdge(int message, Point point, uint flags, uint time, int panelGeneration)
        {
            if (!Enabled || (message != 0x0201 && message != 0x0202)) return null;
            bool down = message == 0x0201;
            long now = Environment.TickCount64;
            TargetCache target = Volatile.Read(ref _target);
            bool eligible = target.bounds.Contains(point);
            long overwritten = _history.Overwritten;
            string id = _history.Edge(down, eligible, point,
                down && eligible ? "mouse." + Interlocked.Increment(ref _mouseSequence) : null, now);
            if (_history.Overwritten != overwritten)
                Input("input.history_overwritten", new InputData { generation = _history.Overwritten });
            if (down && eligible) { Interlocked.Exchange(ref _armedUntil, now + FocusMouseHistory.RetentionMs); _nativeHitTests = 0; _rawHitTests = 0; }
            if (id == null)
            {
                if (down && InputArmed) Input("mouse.outside_target", new InputData { message = message,
                    flags = flags, hookTime = time, injected = (flags & 1) != 0 });
                return null;
            }
            Input(down ? "mouse.down" : "mouse.up", new InputData { mouseId = id, message = message,
                point = point, flags = flags, hookTime = time, injected = (flags & 1) != 0,
                panelGeneration = panelGeneration, coordinateSource = "ll_screen_cached_target",
                targetEligible = target.eligible, cacheAgeMs = now - target.at });
            return id;
        }

        internal static void HookChainResult(string mouseId, int message, IntPtr result, long started, long observedAt = 0)
        {
            if (mouseId == null || !Enabled) return;
            Input("mouse.hook_chain_result", new InputData { mouseId = mouseId, message = message,
                nextHookResult = result.ToInt64(), suppressed = result != IntPtr.Zero,
                beforeNextMs = observedAt == 0 ? 0 : (started - observedAt) * 1000.0 / Stopwatch.Frequency,
                elapsedMs = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency });
        }

        internal static string NativeMouseCandidate(Point point)
        {
            return Enabled ? _history.Candidate(point, Environment.TickCount64, out _) : null;
        }

        internal static bool ShouldTraceNativeHitTest(Point point)
        {
            if (_snapshotDepth != 0 || !InputArmed || _nativeHitTests >= 32) return false;
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
            string candidate = _history.Candidate(point, Environment.TickCount64, out int count);
            Input("hud.down", new InputData { receiver = receiver.ToInt64(), widget = widget, point = point,
                mouseId = candidate, candidateCount = count,
                correlation = count == 0 ? "unobserved" : count == 1 ? "position_time_candidate" : "ambiguous",
                coordinateSource = "screen" }, id);
            return id;
        }
    }
}
