using System;
using System.Collections.Generic;
using System.Threading;

namespace CF7Launcher.Tasks
{
    internal enum PanelPendingCallEndReason
    {
        Timeout,
        DeliveryUnknown,
        Cleared
    }

    internal sealed class PanelPendingCall<TContext>
    {
        public string WebCallId { get; private set; }
        public TContext Context { get; private set; }

        internal PanelPendingCall(string webCallId, TContext context)
        {
            WebCallId = webCallId;
            Context = context;
        }
    }

    /// <summary>
    /// Tracks the mechanical lifetime of correlated Web-to-backend calls.
    /// Call-specific state remains opaque in <typeparamref name="TContext"/>.
    /// </summary>
    internal sealed class PanelPendingCallTracker<TContext> : IDisposable
    {
        private sealed class TrackedCall
        {
            public PanelPendingCall<TContext> Call;
            public Timer Timer;
        }

        private const int RecentCallIdCapacity = 256;

        private readonly Func<bool> _isReady;
        private readonly Func<string, bool> _trySend;
        private readonly int _timeoutMs;
        private readonly Action<PanelPendingCall<TContext>, PanelPendingCallEndReason> _onEnded;
        private readonly Dictionary<int, TrackedCall> _pending =
            new Dictionary<int, TrackedCall>();
        private readonly HashSet<string> _activeWebCallIds =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> _recentWebCallIds =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly Queue<string> _recentWebCallIdOrder = new Queue<string>();
        private readonly object _gate = new object();

        private int _sequence;
        private bool _disposed;

        public PanelPendingCallTracker(
            Func<bool> isReady,
            Func<string, bool> trySend,
            int timeoutMs,
            Action<PanelPendingCall<TContext>, PanelPendingCallEndReason> onEnded)
        {
            _isReady = isReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
            _timeoutMs = Math.Max(1, timeoutMs);
            _onEnded = onEnded ?? throw new ArgumentNullException(nameof(onEnded));
        }

        public bool IsReady()
        {
            lock (_gate)
            {
                if (_disposed) return false;
            }

            return _isReady();
        }

        public int PendingCount
        {
            get
            {
                lock (_gate)
                    return _pending.Count;
            }
        }

        public bool IsKnownWebCallId(string webCallId)
        {
            if (string.IsNullOrEmpty(webCallId)) return false;
            lock (_gate)
            {
                return _activeWebCallIds.Contains(webCallId)
                    || _recentWebCallIds.Contains(webCallId);
            }
        }

        public bool TryRememberRejected(string webCallId)
        {
            if (string.IsNullOrEmpty(webCallId)) return false;
            lock (_gate)
            {
                if (_disposed || _activeWebCallIds.Contains(webCallId)
                    || _recentWebCallIds.Contains(webCallId)) return false;
                RememberRecentLocked(webCallId);
                return true;
            }
        }

        public bool TryBegin(
            string webCallId,
            TContext context,
            out int backendCallId)
        {
            backendCallId = 0;
            if (string.IsNullOrEmpty(webCallId))
                throw new ArgumentException("A Web call id is required.", nameof(webCallId));

            lock (_gate)
            {
                if (_disposed) return false;
                if (_activeWebCallIds.Contains(webCallId)
                    || _recentWebCallIds.Contains(webCallId))
                    return false;

                int assignedCallId = unchecked(++_sequence);
                backendCallId = assignedCallId;
                var call = new PanelPendingCall<TContext>(webCallId, context);
                var tracked = new TrackedCall { Call = call };
                _pending.Add(assignedCallId, tracked);
                _activeWebCallIds.Add(webCallId);
                tracked.Timer = new Timer(
                    delegate { HandleTimeout(assignedCallId); },
                    null,
                    System.Threading.Timeout.Infinite,
                    System.Threading.Timeout.Infinite);
                tracked.Timer.Change(_timeoutMs, System.Threading.Timeout.Infinite);
                return true;
            }
        }

        public void Send(int backendCallId, string payload)
        {
            lock (_gate)
            {
                if (_disposed || !_pending.ContainsKey(backendCallId)) return;
            }

            if (_trySend(payload)) return;

            PanelPendingCall<TContext> call = Take(backendCallId);
            if (call != null) NotifyEnded(call, PanelPendingCallEndReason.DeliveryUnknown);
        }

        public bool TryComplete(
            int backendCallId,
            out PanelPendingCall<TContext> call)
        {
            call = Take(backendCallId);
            return call != null;
        }

        public void Clear()
        {
            List<PanelPendingCall<TContext>> calls;
            lock (_gate) { calls = TakeAllLocked(); }
            NotifyEnded(calls, PanelPendingCallEndReason.Cleared);
        }

        public void Dispose()
        {
            List<PanelPendingCall<TContext>> calls;
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                calls = TakeAllLocked();
            }
            NotifyEnded(calls, PanelPendingCallEndReason.Cleared);
        }

        private void HandleTimeout(int backendCallId)
        {
            PanelPendingCall<TContext> call = Take(backendCallId);
            if (call != null) NotifyEnded(call, PanelPendingCallEndReason.Timeout);
        }

        private PanelPendingCall<TContext> Take(int backendCallId)
        {
            lock (_gate) { return TakeLocked(backendCallId); }
        }

        private PanelPendingCall<TContext> TakeLocked(int backendCallId)
        {
            TrackedCall tracked;
            if (!_pending.TryGetValue(backendCallId, out tracked)) return null;

            _pending.Remove(backendCallId);
            if (tracked.Timer != null) tracked.Timer.Dispose();
            _activeWebCallIds.Remove(tracked.Call.WebCallId);
            RememberRecentLocked(tracked.Call.WebCallId);
            return tracked.Call;
        }

        private List<PanelPendingCall<TContext>> TakeAllLocked()
        {
            var backendCallIds = new List<int>(_pending.Keys);
            var calls = new List<PanelPendingCall<TContext>>(backendCallIds.Count);
            foreach (int backendCallId in backendCallIds)
            {
                PanelPendingCall<TContext> call = TakeLocked(backendCallId);
                if (call != null) calls.Add(call);
            }
            return calls;
        }

        private void RememberRecentLocked(string webCallId)
        {
            if (string.IsNullOrEmpty(webCallId)
                || !_recentWebCallIds.Add(webCallId)) return;

            _recentWebCallIdOrder.Enqueue(webCallId);
            while (_recentWebCallIdOrder.Count > RecentCallIdCapacity)
                _recentWebCallIds.Remove(_recentWebCallIdOrder.Dequeue());
        }

        private void NotifyEnded(
            IEnumerable<PanelPendingCall<TContext>> calls,
            PanelPendingCallEndReason reason)
        {
            foreach (PanelPendingCall<TContext> call in calls) NotifyEnded(call, reason);
        }

        private void NotifyEnded(
            PanelPendingCall<TContext> call,
            PanelPendingCallEndReason reason)
        {
            _onEnded(call, reason);
        }
    }
}
