using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Threading;
using Newtonsoft.Json;

namespace CF7Launcher.Diagnostic
{
    internal static partial class FocusTrace
    {
        private static readonly string ProcessRunId = Guid.NewGuid().ToString("N");
        private static long _sessionGeneration;
        private static TraceSessionState _currentState;
        private static string _lastSessionLabel;
        private static readonly TraceSessionState EmptyState = new TraceSessionState(null, 0, null, false, null, null) { Accepting = false };
        private static TraceSessionState CurrentState => Volatile.Read(ref _currentState) ?? EmptyState;

        internal sealed class TraceLease
        {
            internal readonly object State;
            internal readonly long Generation;
            internal TraceLease(object state, long generation) { State = state; Generation = generation; }
        }

        internal sealed class NativeTraceData
        {
            public long receiver;
            public int message;
            public string phase, dispatchId, dispatchOutcome;
            public Point client, point;
            public uint messageTime;
            public bool messageTimeAvailable, inSendMessage;
            public int? messageAgeMs;
            public bool? messageAgeAmbiguous, sourceQuerySucceeded;
            public uint? sourceDevice, sourceOrigin;
            public string sourceFailure;
            public string mouseId => correlation?.MouseId;
            public NativeMouseCorrelation correlation;
            public long result;
            public double elapsedMs;
            public object windows, hudInput;
            internal long ObservedTick;
            internal NativeTracePair Pair;
            public string pairState => phase == "enter" ? "entry_pending_until_exit_or_trace_terminal"
                : Pair?.Lost == true ? "partial_record_loss" : "paired";
            internal NativeTraceData Exit(long finalResult, double elapsed, string outcome)
            {
                var exit = (NativeTraceData)MemberwiseClone();
                exit.phase = "exit"; exit.result = finalResult; exit.elapsedMs = elapsed;
                exit.dispatchOutcome = outcome; exit.windows = exit.hudInput = null;
                return exit;
            }
        }

        internal sealed class NativeTracePair { internal bool Lost; }
        private sealed class TraceEvent
        {
            internal string Name, Gesture, Utc;
            internal object Data;
            internal long Sequence, Ticks;
            internal int Thread;
        }
        private sealed class TraceSessionState
        {
            internal readonly string Label;
            internal readonly long Generation;
            internal readonly Action<string> Sink;
            internal readonly object FlushGate = new object();
            internal readonly Queue<TraceEvent> Pending = new Queue<TraceEvent>();
            internal readonly Dictionary<string, NativeTracePair> InFlight = new Dictionary<string, NativeTracePair>();
            internal readonly RollingFocusLog Recording;
            internal readonly string RecordingRoot;
            internal readonly bool Rolling;
            internal bool Accepting = true;
            internal Timer Timer;
            internal long Sequence, Lost, NativeSequence, MouseSequence, HudSequence;
            internal long Deadline = Environment.TickCount64 + 30 * 60 * 1000;
            internal Rectangle Target;
            internal PhysicalInputEvent[] Ring = new PhysicalInputEvent[PhysicalRingCapacity];
            internal int RingHead, RingCount, NativeHitTests;
            internal long RingDropped;
            internal PhysicalInputEvent OpenGesture;
            internal string HitTestCandidateId;
            internal TraceSessionState(string label, long generation, Action<string> sink, bool rolling,
                RollingFocusLog recording, string recordingRoot)
            { Label = label; Generation = generation; Sink = sink; Rolling = rolling; Recording = recording; RecordingRoot = recordingRoot; }
        }

        internal static TraceLease TryCaptureLease()
        {
            if (!Enabled) return null;
            lock (Gate) {
                var state = _currentState;
                return state?.Accepting == true ? new TraceLease(state, state.Generation) : null;
            }
        }
        private static bool IsLeaseCurrentLocked(TraceLease lease) => lease != null
            && ReferenceEquals(lease.State, _currentState) && _currentState.Accepting
            && lease.Generation == _currentState.Generation;

        private static void RetireLocked(TraceSessionState state)
        {
            if (state == null) return;
            state.Accepting = false;
            foreach (var dispatch in state.InFlight) EnqueueLocked(state, "trace.native_terminal",
                new { dispatchId = dispatch.Key, pairState = dispatch.Value.Lost ? "partial_record_loss" : "partial_at_terminal", generation = state.Generation });
            state.InFlight.Clear();
            EnqueueLocked(state, "trace.stop", new { generation = state.Generation });
        }

        private static void EnqueueLocked(TraceSessionState state, string name, object data = null, string gesture = null)
        {
            if (state.Pending.Count == Capacity) {
                var dropped = state.Pending.Dequeue(); state.Lost++;
                if (dropped.Data is NativeTraceData native && native.Pair != null) native.Pair.Lost = true;
            }
            state.Pending.Enqueue(new TraceEvent { Name = name, Data = data, Gesture = gesture,
                Sequence = ++state.Sequence, Utc = DateTime.UtcNow.ToString("O"), Ticks = Stopwatch.GetTimestamp(),
                Thread = Environment.CurrentManagedThreadId });
        }
        private static bool WithinBudgetLocked(TraceSessionState state)
        {
            if (state.Rolling || state.Sequence < EventBudget && Environment.TickCount64 < state.Deadline) return true;
            EnqueueLocked(state, "trace.limit", new { reason = state.Sequence >= EventBudget ? "event_budget" : "duration" });
            state.Accepting = false;
            return false;
        }
        internal static bool TryRecord(TraceLease lease, string name, object data = null, string gesture = null)
        {
            try { lock (Gate) {
                if (!IsLeaseCurrentLocked(lease)) return false;
                var state = (TraceSessionState)lease.State;
                if (!WithinBudgetLocked(state)) return false;
                EnqueueLocked(state, name, data, gesture); return true;
            } } catch { return false; }
        }
        internal static bool TryBeginNative(TraceLease lease, NativeTraceData data)
        {
            try { lock (Gate) {
                if (!IsLeaseCurrentLocked(lease)) return false;
                var state = (TraceSessionState)lease.State;
                if (!WithinBudgetLocked(state) || state.InFlight.Count >= Capacity) { state.Lost++; return false; }
                if (state.NativeSequence == long.MaxValue) { state.Accepting = false; return false; }
                data.dispatchId = ProcessRunId + "." + state.Generation + ".dispatch." + ++state.NativeSequence;
                data.phase = "enter";
                data.correlation = MatchGesture(data.point, data.message == 0x0202 ? PhaseUp : PhaseDown,
                    data.messageTime, data.messageTimeAvailable, AxisNative, true, data.ObservedTick);
                data.Pair = new NativeTracePair();
                state.InFlight.Add(data.dispatchId, data.Pair);
                EnqueueLocked(state, "hud.native_mouse", data); return true;
            } } catch { return false; }
        }
        internal static bool TryEndNative(TraceLease lease, NativeTraceData entry, long result, double elapsed, string outcome)
        {
            try { lock (Gate) {
                if (!IsLeaseCurrentLocked(lease) || entry?.dispatchId == null) return false;
                var state = (TraceSessionState)lease.State;
                if (!state.InFlight.Remove(entry.dispatchId)) return false;
                EnqueueLocked(state, "hud.native_mouse", entry.Exit(result, elapsed, outcome)); return true;
            } } catch { return false; }
        }
        private static void FlushSession(TraceSessionState state, bool wait)
        {
            if (state == null) return;
            if (wait) Monitor.Enter(state.FlushGate); else if (!Monitor.TryEnter(state.FlushGate)) return;
            try {
                List<TraceEvent> events; long lost;
                lock (Gate) {
                    if (state.Pending.Count == 0 && state.Lost == 0) return;
                    events = new List<TraceEvent>(state.Pending); state.Pending.Clear();
                    lost = state.Lost; state.Lost = 0;
                }
                // No serialization, sink, Win32 or callback executes under the state lock.
                var lines = new List<string>(events.Count + 1);
                if (lost > 0) lines.Add("[FocusTrace] " + JsonConvert.SerializeObject(new {
                    v = 2, processRunId = ProcessRunId, generation = state.Generation, session = state.Label,
                    @event = "trace.dropped", count = lost }));
                foreach (var item in events) {
                    try { lines.Add("[FocusTrace] " + JsonConvert.SerializeObject(new {
                        v = 2, processRunId = ProcessRunId, generation = state.Generation, session = state.Label,
                        seq = item.Sequence, utc = item.Utc, ticks = item.Ticks, frequency = Stopwatch.Frequency,
                        tid = item.Thread, @event = item.Name, gesture = item.Gesture, data = item.Data })); }
                    catch { lock (Gate) {
                        state.Lost++;
                        if (item.Data is NativeTraceData native && native.Pair != null) native.Pair.Lost = true;
                    } }
                }
                try { if (lines.Count > 0) state.Sink?.Invoke(string.Join(Environment.NewLine, lines)); }
                catch (Exception error) {
                    if (state.Recording != null) {
                        lock (Gate) { state.Accepting = false; }
                        try { state.Recording.MarkError(error.Message); } catch { }
                    }
                }
            } finally { Monitor.Exit(state.FlushGate); }
        }
        private static long NextHudSequence() { lock (Gate) { return ++CurrentState.HudSequence; } }
#if CF7_TEST_SEAMS
        internal static void SetDeadlineForTests(long deadline) { lock (Gate) { CurrentState.Deadline = deadline; } }
        internal static void FlushLeaseForTests(TraceLease lease) => FlushSession(lease?.State as TraceSessionState, false);
#endif
    }
}
