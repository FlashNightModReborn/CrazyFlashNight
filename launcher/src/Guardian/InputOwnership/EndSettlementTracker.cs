#nullable enable

namespace CF7Launcher.Guardian.InputOwnership;

/// <summary>
/// Pure-state END settlement watch, owned by the adapter's observer thread. A
/// physically completed gesture suspends hover immediately, before its END is
/// even dispatched; the reply deadline starts only when the adapter reports a
/// real dispatch. Exactly one terminal END reply carrying this gesture+round
/// (end_miss, panel_request or end_no_intent), a post-dispatch deadline or a
/// cancellation resolves the entry. Stale, duplicate or non-END replies never
/// settle a newer pending gesture, and cancellation clears only this logical
/// pending, never the physical ledger.
/// </summary>
internal sealed class EndSettlementTracker
{
    private bool _pending;
    private long _gesture;
    private HandoffRound _round;
    private long _dispatchedAt = -1;

    internal bool Pending => _pending;
    internal bool Dispatched => _pending && _dispatchedAt >= 0;
    internal long PendingGesture => _pending ? _gesture : -1;
    internal HandoffRound PendingRound => _pending ? _round : default;

    // Called on the same observer turn where Complete/TryCompleteDeferred
    // succeeded. A newer completion supersedes the pending identity.
    internal void Track(InputGesture gesture)
    {
        _pending = true; _gesture = gesture.Id; _round = gesture.Round; _dispatchedAt = -1;
    }

    // Stamped via the observer only after the adapter really sent END.
    internal bool MarkDispatched(long gesture, HandoffRound round, long tick)
    {
        if (!Matches(gesture, round)) return false;
        _dispatchedAt = tick; return true;
    }

    // Terminal END replies settle only their exact pending identity.
    internal bool Settle(string op, long gesture, HandoffRound round)
    {
        if (op != "END" || !Matches(gesture, round)) return false;
        _pending = false; return true;
    }

    // Bounded only after a real dispatch; an undispatched pending has no clock.
    internal bool Expire(long now, long timeout)
    {
        if (!_pending || _dispatchedAt < 0 || now - _dispatchedAt < timeout) return false;
        _pending = false; return true;
    }

    // Cancellation clears logical pending only.
    internal void Cancel() { _pending = false; _dispatchedAt = -1; }

    private bool Matches(long gesture, HandoffRound round) =>
        _pending && _gesture == gesture && _round == round;
}
