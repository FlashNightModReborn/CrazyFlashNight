using System;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace CF7Launcher.Diagnostic
{
    // Explicit, bounded observation only. Reuses FocusTrace's queue, background writer,
    // identity and rolling retention. Never injects input or repairs application state.
    internal sealed class InputLatencyProbe : IDisposable
    {
        internal const double SlowMs = 40;
        internal const int SlowEventLimit = 64;
        private const int IntervalMs = 20;
        private static readonly string[] Metrics = { "ui_dispatch", "sampler_gap", "hook_delivery",
            "cursor_queue", "cursor_present", "transition_tick", "transition_raise", "surface_present",
            "surface_viewport", "web_input", "world_read", "world_geometry", "transition_hide" };
        internal static InputLatencyProbe Current { get; private set; }
        private readonly object _gate = new();
        private readonly Action<Action> _post;
        private readonly Action<string, object> _record;
        private readonly Func<double> _now;
        private readonly string _cursorMode;
        private readonly System.Threading.Timer _timer;
        private Window _window, _pending;
        private double _lastPulse;
        private int _pulsing;
        private bool _disposed;

        internal static InputLatencyProbe StartConfigured(Control owner, string cursorMode)
        {
            if (!IsRequested(Environment.GetEnvironmentVariable("CF7_INPUT_LATENCY"), FocusTrace.Enabled)) return null;
            Current = new InputLatencyProbe(action => owner.BeginInvoke(action),
                (name, data) => FocusTrace.Record(name, data), cursorMode, useTimer: true);
            return Current;
        }
        internal static bool IsRequested(string value, bool recording) => recording && value == "1";

        internal InputLatencyProbe(Action<Action> post, Action<string, object> record, string cursorMode,
            Func<double> now = null, bool useTimer = false)
        {
            _post = post; _record = record; _cursorMode = cursorMode;
            _now = now ?? (() => Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency);
            if (useTimer) _timer = new System.Threading.Timer(_ => Pulse(), null, Timeout.Infinite, Timeout.Infinite);
            Emit("input_latency.start", new { thresholdMs = SlowMs, intervalMs = IntervalMs,
                windowLimitMs = 30000, tailMs = 2000, slowEventLimit = SlowEventLimit, cursorMode });
        }

        internal void BeginTransition(string id, long epoch, string phase)
        {
            lock (_gate)
            {
                if (_disposed) return;
                if (_window != null) Complete("superseded");
                double now = _now();
                _window = new Window { Id = id, Epoch = epoch, Phase = phase, Start = now, Deadline = now + 30000 };
                _lastPulse = now;
                Emit("input_latency.window", new { id, epoch, phase, cursorMode = _cursorMode });
                _timer?.Change(IntervalMs, IntervalMs);
            }
        }
        internal void SetPhase(string phase, bool finished = false)
        {
            lock (_gate)
            {
                if (_window == null || _disposed) return;
                if (_window.Phase != phase)
                    Emit("input_latency.phase", new { id = _window.Id, epoch = _window.Epoch, phase });
                _window.Phase = phase;
                if (finished) _window.Deadline = Math.Min(_window.Deadline, _now() + 2000);
            }
        }

        internal static Sample Measure(string metric) => Current?.BeginSample(metric) ?? default;
        internal Sample BeginSample(string metric)
        {
            lock (_gate)
                return _disposed || _window == null ? default : new Sample(this, _window, _window.Phase, metric, _now());
        }
        internal static void ObserveHook(uint timestamp, uint flags)
        {
            var probe = Current;
            if (probe == null || (flags & 1) != 0) return; // synthetic input is not physical latency evidence
            int elapsed = FocusTrace.WrappingTickDeltaMs(unchecked((uint)Environment.TickCount), timestamp, out bool ambiguous);
            if (!ambiguous) probe.Observe("hook_delivery", elapsed);
        }
        internal void Observe(string metric, double ms)
        {
            lock (_gate) Record(_window, _window?.Phase, metric, ms);
        }

        // One outstanding BeginInvoke maximum, even if the UI is blocked or a new scene starts.
        // Queue delay and sampler scheduling delay are separate measurements.
        internal void Pulse()
        {
            if (Interlocked.Exchange(ref _pulsing, 1) != 0) return;
            try
            {
                Window window; string phase; double sent;
                lock (_gate)
                {
                    if (_disposed || _window == null) return;
                    sent = _now();
                    if (sent >= _window.Deadline) { Complete("window_end"); return; }
                    window = _window; phase = window.Phase;
                    Record(window, phase, "sampler_gap", Math.Max(0, sent - _lastPulse - IntervalMs));
                    _lastPulse = sent;
                    if (_pending != null) return;
                    _pending = window;
                }
                try
                {
                    _post(() =>
                    {
                        lock (_gate)
                        {
                            if (ReferenceEquals(_pending, window)) _pending = null;
                            Record(window, phase, "ui_dispatch", _now() - sent);
                        }
                    });
                }
                catch (Exception error)
                {
                    lock (_gate)
                    {
                        if (ReferenceEquals(_pending, window)) _pending = null;
                        Emit("input_latency.dispatch_unavailable", new { id = window.Id, error = error.GetType().Name });
                        if (ReferenceEquals(_window, window)) Complete("dispatch_unavailable");
                    }
                }
            }
            finally { Volatile.Write(ref _pulsing, 0); }
        }

        private void Record(Window window, string phase, string metric, double ms)
        {
            if (_disposed || window == null || !ReferenceEquals(_window, window) || !double.IsFinite(ms) || ms < 0) return;
            int index = Array.IndexOf(Metrics, metric);
            if (index < 0) return;
            window.Count[index]++;
            window.Max[index] = Math.Max(window.Max[index], ms);
            if (ms < SlowMs) return;
            window.Slow[index]++;
            if (window.Emitted++ >= SlowEventLimit) return;
            Emit("input_latency.slow", new { id = window.Id, epoch = window.Epoch, phase, metric,
                ms = Math.Round(ms, 2), offsetMs = Math.Round(_now() - window.Start, 2) });
        }
        private void Complete(string reason)
        {
            var window = _window;
            if (window == null) return;
            _window = null;
            _timer?.Change(Timeout.Infinite, Timeout.Infinite);
            Emit("input_latency.summary", new { id = window.Id, epoch = window.Epoch, phase = window.Phase, reason,
                cursorMode = _cursorMode, durationMs = Math.Round(_now() - window.Start, 2),
                omittedSlowEvents = Math.Max(0, window.Emitted - SlowEventLimit),
                metrics = Metrics.Select((name, i) => new { name, count = window.Count[i], slow = window.Slow[i],
                    maxMs = Math.Round(window.Max[i], 2) }).ToArray() });
        }
        private void Emit(string name, object data)
        {
            try { _record(name, data); } catch { /* observation never changes the business result */ }
        }
        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                Complete("disposed"); _disposed = true;
                _timer?.Dispose();
                if (ReferenceEquals(Current, this)) Current = null;
            }
        }
        internal sealed class Window
        {
            internal string Id, Phase;
            internal long Epoch;
            internal double Start, Deadline;
            internal int Emitted;
            internal readonly int[] Count = new int[Metrics.Length], Slow = new int[Metrics.Length];
            internal readonly double[] Max = new double[Metrics.Length];
        }
        internal readonly struct Sample : IDisposable
        {
            private readonly InputLatencyProbe _probe;
            private readonly Window _window;
            private readonly string _phase, _metric;
            private readonly double _started;
            internal Sample(InputLatencyProbe probe, Window window, string phase, string metric, double started)
            { _probe = probe; _window = window; _phase = phase; _metric = metric; _started = started; }
            public void Dispose()
            {
                if (_probe == null) return;
                lock (_probe._gate) _probe.Record(_window, _phase, _metric, _probe._now() - _started);
            }
        }
    }
}
