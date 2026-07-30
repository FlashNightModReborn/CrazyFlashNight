using System;
using System.Collections.Generic;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Wings
{
    /// <summary>
    /// Session-only adapter from authenticated Wings broker receipts to the
    /// existing offline-output result authority. Recording performs the
    /// complete HMAC and exact live-binding validation once, then retains
    /// only an immutable, bounded-lifetime projection. Resolving a terminal
    /// fact must not depend on the execution credential or grant remaining
    /// live after the action has already completed.
    /// </summary>
    internal sealed class SessionOnlyTrustedWingsActionResultAuthority
        : ITrustedActionResultAuthority,
          IDisposable
    {
        private const int MaximumEntries = 64;
        private static readonly TimeSpan MaximumEntryLifetime =
            TimeSpan.FromSeconds(10);

        private readonly object _sync = new object();
        private readonly string _sessionId;
        private readonly IAgentRuntimeClock _clock;
        private readonly long _entryLifetimeMilliseconds;
        private readonly TrustedWingsActionReceiptAuthority
            _projector;
        private readonly Dictionary<string, Entry> _entries =
            new Dictionary<string, Entry>(
                StringComparer.Ordinal);
        private readonly Queue<string> _order =
            new Queue<string>();
        private bool _disposed;

        internal SessionOnlyTrustedWingsActionResultAuthority(
            string sessionId,
            TrustedWingsActionReceiptAuthority projector,
            IAgentRuntimeClock clock,
            TimeSpan? entryLifetime = null)
        {
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            _sessionId = sessionId;
            _projector = projector
                ?? throw new ArgumentNullException(
                    nameof(projector));
            _clock = clock
                ?? throw new ArgumentNullException(
                    nameof(clock));
            TimeSpan lifetime =
                entryLifetime ?? MaximumEntryLifetime;
            if (lifetime <= TimeSpan.Zero
                || lifetime > MaximumEntryLifetime)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(entryLifetime));
            }
            _entryLifetimeMilliseconds =
                checked((long)lifetime.TotalMilliseconds);
        }

        internal int CountForTest
        {
            get
            {
                lock (_sync)
                    return _entries.Count;
            }
        }

        internal bool TryRecord(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            WingsBrokeredActionReceipt evidence,
            out string receiptId,
            out string reasonCode)
        {
            receiptId = null;
            if (intent == null
                || !string.Equals(
                    intent.SessionId,
                    _sessionId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "wings_result_session_mismatch";
                return false;
            }
            if (!_projector.TryProject(
                    principal,
                    intent,
                    evidence,
                    out TrustedWingsActionProjection projection,
                    out reasonCode)
                || !IsFrozenOutcome(projection.Outcome))
            {
                reasonCode ??=
                    "wings_result_projection_invalid";
                return false;
            }

            string issuedReceiptId =
                OpaqueIdGenerator.Create("wresult");
            long expiresMonotonic;
            try
            {
                expiresMonotonic = checked(
                    _clock.MonotonicMilliseconds
                    + _entryLifetimeMilliseconds);
            }
            catch (OverflowException)
            {
                reasonCode =
                    "wings_result_projection_invalid";
                return false;
            }
            var facts = new TrustedActionResultFacts(
                issuedReceiptId,
                projection.ActionId,
                intent.SessionId,
                intent.SaveBindingId,
                intent.LoreViewId,
                projection.Outcome);
            lock (_sync)
            {
                if (_disposed)
                {
                    reasonCode =
                        "wings_result_authority_disposed";
                    return false;
                }
                PruneExpiredUnsafe(
                    _clock.MonotonicMilliseconds);
                while (_entries.Count >= MaximumEntries)
                {
                    if (_order.Count == 0)
                    {
                        _entries.Clear();
                        break;
                    }
                    _entries.Remove(_order.Dequeue());
                }
                _entries.Add(
                    issuedReceiptId,
                    new Entry(
                        facts,
                        expiresMonotonic));
                _order.Enqueue(issuedReceiptId);
            }
            receiptId = issuedReceiptId;
            reasonCode = null;
            return true;
        }

        public bool TryResolve(
            string receiptId,
            out TrustedActionResultFacts facts,
            out string reasonCode)
        {
            facts = null;
            Entry entry;
            lock (_sync)
            {
                long now = _clock.MonotonicMilliseconds;
                PruneExpiredUnsafe(now);
                if (_disposed
                    || string.IsNullOrWhiteSpace(receiptId)
                    || !_entries.TryGetValue(
                        receiptId,
                        out entry))
                {
                    reasonCode =
                        "wings_result_unavailable";
                    return false;
                }
                if (now >= entry.ExpiresMonotonic)
                {
                    _entries.Remove(receiptId);
                    reasonCode =
                        "wings_result_unavailable";
                    return false;
                }
                facts = entry.Facts;
            }
            reasonCode = null;
            return true;
        }

        internal void Remove(string receiptId)
        {
            if (string.IsNullOrWhiteSpace(receiptId))
                return;
            lock (_sync)
                _entries.Remove(receiptId);
        }

        internal void RevokeSession()
        {
            lock (_sync)
            {
                _entries.Clear();
                _order.Clear();
            }
        }

        private void PruneExpiredUnsafe(long nowMonotonic)
        {
            while (_order.Count > 0)
            {
                string receiptId = _order.Peek();
                if (!_entries.TryGetValue(
                        receiptId,
                        out Entry entry))
                {
                    _order.Dequeue();
                    continue;
                }
                if (nowMonotonic < entry.ExpiresMonotonic)
                    break;
                _order.Dequeue();
                _entries.Remove(receiptId);
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                _entries.Clear();
                _order.Clear();
            }
        }

        private static bool IsFrozenOutcome(
            ActionOutcome outcome)
        {
            return outcome is ActionOutcome.Rejected
                or ActionOutcome.InputDispatched
                or ActionOutcome.EffectObserved
                or ActionOutcome.DomainCommitted
                or ActionOutcome.Unknown;
        }

        private sealed class Entry
        {
            internal Entry(
                TrustedActionResultFacts facts,
                long expiresMonotonic)
            {
                Facts = facts;
                ExpiresMonotonic = expiresMonotonic;
            }

            internal TrustedActionResultFacts Facts { get; }
            internal long ExpiresMonotonic { get; }
        }
    }
}
