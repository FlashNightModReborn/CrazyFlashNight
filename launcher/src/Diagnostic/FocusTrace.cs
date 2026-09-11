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
        // 物理输入历史环：只保留左键沿（含目标外点击）。32 次点击足够覆盖秒级延迟诊断，
        // 溢出用 ringDropped / mouse.ring_evict 明示而不是静默丢证据。
        internal const int PhysicalRingCapacity = 32;
        // 超过 2s 的候选标记 stale 但保留（旧实现直接丢弃，导致 3-4s 原生延迟完全无证据）。
        private const int StaleCandidateMs = 2000;
        // 超过 60s 的偏移视为无关残留：不再作为同点候选，但理由要可区分。
        private const int MaxCandidateDelayMs = 60000;
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
        private static PhysicalInputEvent[] _ring = new PhysicalInputEvent[PhysicalRingCapacity];
        private static int _ringHead, _ringCount;
        private static long _ringDropped;
        private static PhysicalInputEvent _openGesture;
        private static string _hitTestCandidateId;
        private static int _nativeHitTests;
        [ThreadStatic] private static int _snapshotDepth;
        internal static Func<Point, object> HudInputSnapshot;
        // 测试时钟注入点：默认 null 时走真实 Environment.TickCount64；测试替换后必须还原。
        internal static Func<long> TickCount64Provider;
        [ThreadStatic] private static string _gesture;
        internal static bool Enabled { get; private set; }
        internal static string Session { get; private set; }
        internal static string Gesture { get { return _gesture; } }

        private static long ObservedNow()
        {
            Func<long> provider = TickCount64Provider;
            return provider != null ? provider() : Environment.TickCount64;
        }

        // GetTickCount 域（MSLLHOOKSTRUCT.time / GetMessageTime / TickCount 低 32 位）的
        // wrap-safe 差值（ms）。两个 32 位时间戳先各自截到低 32 位再做 unchecked 减法，
        // 使 49.7 天 wrap 穿越仍得到正确的短间隔。
        // delta < 0 = 不可能区间：事件时刻"晚于"观察时刻，真实差只能解释为跨整圈 wrap 的
        // 歧义（真实差可能是 delta + 2^32）——调用方标注 ambiguous，不得输出负延迟当证据，
        // 也不得臆造超大延迟。
        internal static int WrappingTickDeltaMs(uint laterTick, uint earlierTick, out bool ambiguous)
        {
            int delta = unchecked((int)(laterTick - earlierTick));
            ambiguous = delta < 0;
            return delta;
        }

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
                _ring = new PhysicalInputEvent[PhysicalRingCapacity];
                _ringHead = _ringCount = 0;
                _ringDropped = 0;
                _openGesture = null;
                _hitTestCandidateId = null;
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
                nativeInputObservation = 2, physicalRingCapacity = PhysicalRingCapacity,
                staleCandidateMs = StaleCandidateMs, maxCandidateDelayMs = MaxCandidateDelayMs,
                corePath = typeof(FocusTrace).Assembly.Location,
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

        // 单个物理手势：down 必有；up 依附最近未闭合的 down（释放点可出目标区，也可能整个缺失）。
        private sealed class PhysicalInputEvent
        {
            internal string Id;
            internal long Seq;
            internal Point Point;
            internal uint HookTime;
            internal uint Flags;
            internal int PanelGeneration;
            internal long ObservedTick64;
            internal bool InTarget;
            internal bool UpObserved;
            internal Point UpPoint;
            internal uint UpHookTime;
            internal long UpObservedTick64;
            // 两条互不相干的认领轴：原生 WndProc 送达 vs 托管 OnMouseDown 送达。
            // 消息可能已到 WndProc 但在进入 OnMouseDown 前又被卡住，轴分开才能看见。
            internal bool NativeDownClaimed, NativeUpClaimed, HudClaimed;
        }

        private const int PhaseDown = 0, PhaseUp = 1, AxisNative = 1, AxisHud = 2;

        private static void PushRing(PhysicalInputEvent entry)
        {
            if (_ringCount == PhysicalRingCapacity)
            {
                PhysicalInputEvent evicted = _ring[_ringHead];
                _ringDropped++;
                if (evicted != null)
                    Record("mouse.ring_evict", new { evictedId = evicted.Id, seq = evicted.Seq,
                        inTarget = evicted.InTarget, upObserved = evicted.UpObserved,
                        nativeDownClaimed = evicted.NativeDownClaimed, hudClaimed = evicted.HudClaimed,
                        ringDropped = _ringDropped });
            }
            else _ringCount++;
            _ring[_ringHead] = entry;
            _ringHead = (_ringHead + 1) % PhysicalRingCapacity;
        }

        internal static string PhysicalEdge(int message, Point point, uint flags, uint time, int panelGeneration)
        {
            if (!Enabled || (message != 0x0201 && message != 0x0202)) return null;
            // 快照放 Gate 外采集：CaptureHudInput 会取 _widgetsLock，持 Gate 再取它会与
            // widget 在 _widgetsLock 内 Record（取 Gate）构成 ABBA。
            bool inTargetDown = message == 0x0201 && _target.Contains(point);
            object windows = null, hudInput = null;
            long foreground = 0;
            if (message == 0x0201)
            {
                if (inTargetDown) { windows = FocusWindowSnapshot.At(point); hudInput = CaptureHudInput(point); }
                else foreground = FocusWindowSnapshot.ForegroundHandle().ToInt64();
            }
            else
            {
                PhysicalInputEvent maybeOpen = _openGesture;
                if (maybeOpen != null && maybeOpen.InTarget) windows = FocusWindowSnapshot.At(point);
                else foreground = FocusWindowSnapshot.ForegroundHandle().ToInt64();
            }
            lock (Gate)
            {
                if (!Enabled) return null;
                long observed = ObservedNow();
                // LL 钩子在安装线程的消息循环里跑：UI 线程卡住时回调本身就迟到，
                // hookDispatchMs 把"我们自己的派发停滞"从外部排队延迟里分离出来。
                // hookTime 是 wrap 32 位域，先截低 32 位再减，避免 uptime>2^32 后假大值。
                bool hookDispatchAmbiguous;
                long hookDispatchMs = WrappingTickDeltaMs((uint)observed, time, out hookDispatchAmbiguous);
                if (message == 0x0201)
                {
                    var entry = new PhysicalInputEvent {
                        Id = "mouse." + Interlocked.Increment(ref _mouseSequence), Seq = _mouseSequence,
                        Point = point, HookTime = time, Flags = flags, PanelGeneration = panelGeneration,
                        ObservedTick64 = observed, InTarget = inTargetDown };
                    PushRing(entry);
                    _openGesture = entry;
                    if (!inTargetDown)
                    {
                        Record("mouse.edge", new { mouseId = entry.Id, edge = "down", point,
                            hookTime = time, hookDispatchMs, hookDispatchAmbiguous,
                            flags, injected = (flags & 1) != 0,
                            panelGeneration, inTarget = false, foreground });
                        return null;
                    }
                    _hitTestCandidateId = entry.Id;
                    _nativeHitTests = 0;
                    Record("mouse.down", new { mouseId = entry.Id, point, hookTime = time,
                        hookDispatchMs, hookDispatchAmbiguous, flags, injected = (flags & 1) != 0,
                        panelGeneration, windows, hudInput });
                    return entry.Id;
                }
                PhysicalInputEvent open = _openGesture;
                _openGesture = null;
                if (open != null)
                {
                    open.UpObserved = true;
                    open.UpPoint = point;
                    open.UpHookTime = time;
                    open.UpObservedTick64 = observed;
                }
                if (open != null && open.InTarget)
                {
                    Record("mouse.up", new { mouseId = open.Id, point, hookTime = time,
                        hookDispatchMs, hookDispatchAmbiguous, flags, injected = (flags & 1) != 0,
                        panelGeneration, windows });
                    return open.Id;
                }
                Record("mouse.edge", new { mouseId = open == null ? null : open.Id, edge = "up",
                    point, hookTime = time, hookDispatchMs, hookDispatchAmbiguous,
                    flags, injected = (flags & 1) != 0,
                    panelGeneration, inTarget = open != null && open.InTarget,
                    unmatched = open == null ? "no_open_down" : null, foreground });
                return null;
            }
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

        // 兼容包装：返回最旧未认领同点候选的 id（非证明），无候选返回 null。
        internal static string NativeMouseCandidate(Point point)
        {
            return MatchGesture(point, PhaseDown, 0, false, AxisNative, false).MouseId;
        }

        // 原生 WndProc 消息认领路径：posted 输入消息时传入 GetMessageTime，
        // 得到"物理事件 → 消息入队"的真实延迟；SendMessage 合成消息应传 messageTimeAvailable=false。
        internal static NativeMouseCorrelation CorrelateNativeMouse(Point point, int nativeMessage, uint messageTime, bool messageTimeAvailable)
        {
            return MatchGesture(point, nativeMessage == 0x0202 ? PhaseUp : PhaseDown,
                messageTime, messageTimeAvailable, AxisNative, true);
        }

        // 非认领查看：hittest/mouse_activate/exit 阶段引用同一候选但不消耗认领位。
        internal static NativeMouseCorrelation PeekNativeMouseCorrelation(Point point, int nativeMessage)
        {
            return MatchGesture(point, nativeMessage == 0x0202 ? PhaseUp : PhaseDown,
                0, false, AxisNative, false);
        }

        internal static NativeMouseCorrelation PeekNativeMouseCorrelation(Point point, int nativeMessage, uint messageTime, bool messageTimeAvailable)
        {
            return MatchGesture(point, nativeMessage == 0x0202 ? PhaseUp : PhaseDown,
                messageTime, messageTimeAvailable, AxisNative, false);
        }

        private static NativeMouseCorrelation MatchGesture(Point point, int phase, uint messageTime,
            bool messageTimeAvailable, int axis, bool claim)
        {
            var result = new NativeMouseCorrelation { Kind = "unobserved" };
            lock (Gate)
            {
                result.RingDepth = _ringCount;
                result.RingDropped = _ringDropped;
                result.DelaySource = messageTimeAvailable ? "message_time" : "observed";
                if (!Enabled) { result.Reason = "disabled"; return result; }
                long now = ObservedNow();
                PhysicalInputEvent pick = null, newestClaimed = null;
                int timingAfter = 0, staleResidue = 0, upMissing = 0, consumedAtPoint = 0, outOfTarget = 0;
                for (int i = 0; i < _ringCount; i++)
                {
                    PhysicalInputEvent e = _ring[(_ringHead - _ringCount + i + PhysicalRingCapacity) % PhysicalRingCapacity];
                    if (e == null) continue;
                    bool pointMatch;
                    if (phase == PhaseUp)
                    {
                        if (e.UpObserved) pointMatch = e.UpPoint == point;
                        else pointMatch = false;
                        // down 同点但 up 在别处或从未出现：从本点视角都是"up 未在此被观察"。
                        if (!pointMatch && e.Point == point) upMissing++;
                    }
                    else pointMatch = e.Point == point;
                    if (!pointMatch)
                    {
                        if (phase != PhaseUp || e.Point != point) result.OtherPointEntries++;
                        continue;
                    }
                    bool claimed = axis == AxisHud ? e.HudClaimed
                        : phase == PhaseUp ? e.NativeUpClaimed : e.NativeDownClaimed;
                    if (claimed)
                    {
                        if (axis == AxisHud) consumedAtPoint++;
                        else { result.ClaimedAtPoint++; newestClaimed = e; }
                        continue;
                    }
                    if (axis == AxisHud && !e.InTarget) { outOfTarget++; continue; }
                    if (messageTimeAvailable)
                    {
                        int hTime = (int)(phase == PhaseUp ? e.UpHookTime : e.HookTime);
                        int delay = unchecked((int)messageTime - hTime);
                        if (delay < 0) { timingAfter++; continue; }
                        if (delay > MaxCandidateDelayMs) { staleResidue++; continue; }
                    }
                    result.CandidateCount++;
                    if (pick == null) pick = e; // FIFO：同点多个未认领候选时取最旧者
                }
                bool repeatRef = false;
                if (pick == null && axis == AxisNative && newestClaimed != null)
                {
                    pick = newestClaimed;
                    repeatRef = true;
                }
                if (pick == null)
                {
                    result.Reason = _ringCount == 0 ? "no_candidate_in_ring"
                        : timingAfter > 0 ? "timing_after_message"
                        : staleResidue > 0 ? "stale_residue_only"
                        : consumedAtPoint > 0 ? "already_consumed"
                        : upMissing > 0 ? "up_not_observed"
                        : outOfTarget > 0 ? "out_of_target"
                        : "position_mismatch";
                    return result;
                }
                result.MouseId = pick.Id;
                result.Seq = pick.Seq;
                result.InTarget = pick.InTarget;
                result.Kind = repeatRef ? "repeat_reference" : "position_time_candidate";
                result.Ambiguous = !repeatRef && result.CandidateCount > 1;
                uint hookTime = phase == PhaseUp ? pick.UpHookTime : pick.HookTime;
                long observed = phase == PhaseUp ? pick.UpObservedTick64 : pick.ObservedTick64;
                // 与 PhysicalEdge 同一 wrap-safe 差值：entry 的 hookTime 是 32 位域。
                result.HookDispatchMs = WrappingTickDeltaMs((uint)observed, hookTime, out bool hookAmb);
                result.HookDispatchAmbiguous = hookAmb;
                result.HookToObservedMs = now - observed;
                if (messageTimeAvailable)
                {
                    result.HookToMessageMs = unchecked((int)messageTime - (int)hookTime);
                    result.Stale = result.HookToMessageMs.Value > StaleCandidateMs;
                }
                else result.Stale = result.HookToObservedMs > StaleCandidateMs;
                if (claim && !repeatRef)
                {
                    if (axis == AxisHud) pick.HudClaimed = true;
                    else if (phase == PhaseUp) pick.NativeUpClaimed = true;
                    else pick.NativeDownClaimed = true;
                }
                return result;
            }
        }

        internal static bool ShouldTraceNativeHitTest(Point point)
        {
            // 不记录 MouseMove 历史；每个候选手势最多 8 次命中查询，stale 候选不再提前掐断证据。
            if (_snapshotDepth != 0 || !Enabled) return false;
            var corr = MatchGesture(point, PhaseDown, 0, false, AxisNative, false);
            if (corr.MouseId == null) return false;
            if (corr.MouseId != _hitTestCandidateId) { _hitTestCandidateId = corr.MouseId; _nativeHitTests = 0; }
            if (_nativeHitTests >= 8) return false;
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
            var corr = MatchGesture(point, PhaseDown, 0, false, AxisHud, true);
            Record("hud.down", new { receiver = receiver.ToInt64(), widget, point,
                mouseId = corr.MouseId, correlation = corr.Kind, detail = corr,
                windows = FocusWindowSnapshot.At(point) }, id);
            return id;
        }
    }

    // 原生鼠标消息 ↔ 物理手势的候选关联结果。MouseId 非 null 仍是"候选"而非证明：
    // position+time 匹配不排除外部注入；null 时 Reason 说明为何没有候选，绝不编造 id。
    internal sealed class NativeMouseCorrelation
    {
        [JsonProperty("mouseId")] public string MouseId { get; internal set; }
        [JsonProperty("kind")] public string Kind { get; internal set; }
        [JsonProperty("reason")] public string Reason { get; internal set; }
        [JsonProperty("ambiguous")] public bool Ambiguous { get; internal set; }
        [JsonProperty("stale")] public bool Stale { get; internal set; }
        [JsonProperty("candidateCount")] public int CandidateCount { get; internal set; }
        [JsonProperty("claimedAtPoint")] public int ClaimedAtPoint { get; internal set; }
        [JsonProperty("otherPointEntries")] public int OtherPointEntries { get; internal set; }
        [JsonProperty("ringDepth")] public int RingDepth { get; internal set; }
        [JsonProperty("ringDropped")] public long RingDropped { get; internal set; }
        [JsonProperty("hookDispatchMs")] public double HookDispatchMs { get; internal set; }
        [JsonProperty("hookDispatchAmbiguous")] public bool HookDispatchAmbiguous { get; internal set; }
        [JsonProperty("hookToMessageMs")] public double? HookToMessageMs { get; internal set; }
        [JsonProperty("hookToObservedMs")] public double HookToObservedMs { get; internal set; }
        [JsonProperty("delaySource")] public string DelaySource { get; internal set; }
        [JsonProperty("inTarget")] public bool? InTarget { get; internal set; }
        [JsonProperty("seq")] public long? Seq { get; internal set; }
    }
}
