using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks;

internal readonly record struct ModifierCloseScope(string Token, string Instance, int Generation, int Connection, string CloseId);

internal sealed class ModifierPanelCloseTracker : IDisposable
{
    private const int Capacity = 24;
    private const int MaxAttempts = 3;
    private const int RetryDelayMs = 250;
    private readonly object _gate = new();
    private readonly Dictionary<string, Pending> _pending = new(StringComparer.Ordinal);
    private readonly Timer _retry;
    private readonly Func<ModifierCloseScope, bool> _send;
    private bool _disposed;
    private int _retiredThrough;

    private sealed class Pending
    {
        internal readonly ModifierCloseScope Scope;
        internal int Attempts;
        internal long NextAttempt;

        internal Pending(ModifierCloseScope scope) { Scope = scope; }
    }

    internal ModifierPanelCloseTracker(Func<ModifierCloseScope, bool> send)
    {
        _send = send ?? throw new ArgumentNullException(nameof(send));
        _retry = new Timer(_ => RetryPending(), null, Timeout.Infinite, Timeout.Infinite);
    }

    internal bool HasCapacity { get { lock (_gate) return !_disposed && _pending.Count < Capacity; } }
    internal int RetainedCount { get { lock (_gate) return _pending.Count; } }

    internal bool Retain(ModifierCloseScope scope)
    {
        lock (_gate)
        {
            if (_disposed || _pending.Count >= Capacity || scope.Connection <= _retiredThrough || scope.Generation <= 0 || string.IsNullOrEmpty(scope.CloseId) || _pending.ContainsKey(scope.CloseId)) return false;
            _pending.Add(scope.CloseId, new Pending(scope));
            return true;
        }
    }

    internal void Submit(ModifierCloseScope scope)
    {
        lock (_gate)
        {
            if (_disposed || !_pending.TryGetValue(scope.CloseId, out Pending pending) || pending.Scope != scope
                || pending.Attempts != 0) return;
            pending.Attempts = 1;
            pending.NextAttempt = Environment.TickCount64 + RetryDelayMs;
            ScheduleRetry();
        }
        Send(scope, 1);
    }

    internal bool Acknowledge(ModifierCloseScope receipt, string disposition)
    {
        if (disposition is not ("closed" or "retired")) return false;
        lock (_gate)
        {
            if (_disposed || !_pending.TryGetValue(receipt.CloseId, out Pending pending) || pending.Scope != receipt || pending.Attempts == 0) return false;
            _pending.Remove(receipt.CloseId);
            ScheduleRetry();
        }
        if (FocusTrace.Enabled)
            FocusTrace.Record("modifier.close_receipt", new { token = receipt.Token, instance = receipt.Instance,
                generation = receipt.Generation, connection = receipt.Connection, closeId = receipt.CloseId, disposition });
        return true;
    }

    internal void RetireConnection(int connection)
    {
        lock (_gate)
        {
            if (_disposed || connection <= 0) return;
            _retiredThrough = Math.Max(_retiredThrough, connection);
            foreach (string key in _pending.Where(pair => pair.Value.Scope.Connection == connection).Select(pair => pair.Key).ToArray())
                _pending.Remove(key);
            ScheduleRetry();
        }
    }

    private void ScheduleRetry()
    {
        long earliest = long.MaxValue;
        foreach (Pending pending in _pending.Values)
            if (pending.Attempts > 0 && pending.Attempts < MaxAttempts) earliest = Math.Min(earliest, pending.NextAttempt);
        int delay = earliest == long.MaxValue ? Timeout.Infinite : (int)Math.Clamp(earliest - Environment.TickCount64, 0L, RetryDelayMs);
        _retry.Change(delay, Timeout.Infinite);
    }

    private void RetryPending()
    {
        var due = new List<(ModifierCloseScope Scope, int Attempt)>();
        lock (_gate)
        {
            if (_disposed) return;
            long now = Environment.TickCount64;
            foreach (Pending pending in _pending.Values)
            {
                if (pending.Attempts == 0 || pending.Attempts >= MaxAttempts || pending.NextAttempt > now) continue;
                pending.NextAttempt = now + RetryDelayMs;
                due.Add((pending.Scope, ++pending.Attempts));
            }
            ScheduleRetry();
        }
        foreach (var (scope, attempt) in due) Send(scope, attempt);
    }

    private void Send(ModifierCloseScope scope, int attempt)
    {
        lock (_gate)
        {
            if (_disposed || !_pending.TryGetValue(scope.CloseId, out Pending pending) || pending.Scope != scope) return;
        }
        bool sent = false;
        try { sent = _send(scope); }
        catch (Exception error) { LogManager.Log("[Modifier] close notice failed: " + error.GetType().Name); }
        if (FocusTrace.Enabled)
            FocusTrace.Record("modifier.close_sent", new { token = scope.Token, instance = scope.Instance, generation = scope.Generation,
                connection = scope.Connection, closeId = scope.CloseId, attempt, sent });
        if (attempt == MaxAttempts)
            LogManager.Log("[Modifier] close notice retry budget used for connection " + scope.Connection);
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _pending.Clear();
            _retry.Dispose();
        }
    }
}
