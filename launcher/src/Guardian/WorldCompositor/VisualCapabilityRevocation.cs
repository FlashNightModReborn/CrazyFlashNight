using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Local socket-write failure is not proof that AS2 received a revocation.
    // Keep retrying even when native drawing or scene readiness is unavailable.
    internal sealed class VisualCapabilityRevocation
    {
        private readonly object _sync = new();
        private bool _pending;
        private long _revision;
        private double _nextAttemptMs;
        internal bool Pending { get { lock (_sync) return _pending; } }

        internal void Request()
        {
            lock (_sync) { _revision++; _pending = true; _nextAttemptMs = 0; }
        }

        internal void Reset()
        {
            lock (_sync) { _revision++; _pending = false; _nextAttemptMs = 0; }
        }

        internal bool TrySend(double nowMs, Func<bool> send)
        {
            long revision;
            lock (_sync)
            {
                if (!_pending || nowMs < _nextAttemptMs) return false;
                revision = _revision;
                _nextAttemptMs = nowMs + 500;
            }
            // Never invoke socket/UI callbacks while holding the state lock.
            // An exception leaves the pending request intact and rate-limited.
            bool sent = send();
            lock (_sync)
            {
                if (sent && revision == _revision) _pending = false;
                return !_pending;
            }
        }
    }
}
