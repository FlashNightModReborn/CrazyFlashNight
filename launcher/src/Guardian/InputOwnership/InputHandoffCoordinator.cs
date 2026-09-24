#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;

namespace CF7Launcher.Guardian.InputOwnership;

internal enum InputHandoffPhase { BootClosed, Revoking, WaitNeutral, Preparing, Ready, Held, Blocked }
internal readonly record struct InputScope(string Id, long Incarnation);
internal readonly record struct HandoffRound(string Session, string Coverage, long Epoch, long Ticket, long Geometry);
internal readonly record struct CancelledScope(HandoffRound Round, InputScope Scope, bool GateClosed, bool ObligationsSettled);
internal readonly record struct PreparedScope(HandoffRound Round, InputScope Scope, ObservationPrefix Prefix);
internal readonly record struct InputGesture(HandoffRound Round, InputScope Scope, long Id, int Key, long BeginSequence);
internal readonly record struct InputOpenIntent(long Id, string Destination, InputGesture Gesture);
internal readonly record struct ContinuousKeyEvent(HandoffRound Round, InputScope Scope, int Key, bool Down, long Sequence);
// Closed per-scope whitelist of continuous (held movement) keys. Only scopes
// listed here may accept continuous edges; the default is empty and keeps C1
// semantics. B1 wires world-scope WASD/arrows; this is never an arbitrary
// combo permit, and declaring a key also removes it from gesture eligibility.
internal readonly record struct ContinuousInputPolicy(IReadOnlyDictionary<InputScope, IReadOnlySet<int>> Scopes)
{
    internal static ContinuousInputPolicy Declare(InputScope scope, params int[] keys) =>
        new(new Dictionary<InputScope, IReadOnlySet<int>> { [scope] = keys.ToHashSet() });
}

/// <summary>
/// Serialized, transport-independent C1-I coordinator. Adapters must deliver
/// observation/environment invalidations before business messages and enforce
/// token checks at the actual side-effect boundary. This model does not attest
/// any AS2 scope, Web retirement, OS source or absence of legacy U code.
/// B1 adds a closed per-scope continuous-key policy: declared keys flow as
/// admitted down/up events alongside the one pointer gesture, while Prepare/
/// Grant and every owner switch still require a strictly all-Up ledger.
/// </summary>
internal sealed class InputHandoffCoordinator
{
    private readonly PhysicalInputLedger _ledger;
    private readonly HashSet<InputScope> _coverage;
    private readonly HashSet<InputScope> _cancelled = new(), _prepared = new();
    private readonly Dictionary<InputScope, HashSet<int>> _continuous = new();
    // Keys admitted through AcceptContinuousEdge and still physically Down in
    // the current owner round. Cleared on every Revoke; never written into the
    // physical ledger. Snapshot-held or cross-owner keys are never admitted.
    private readonly HashSet<int> _admitted = new();
    private readonly string _session, _coverageIdentity;
    private long _epoch, _ticket, _geometry = 1, _gestureSequence, _intentSequence;
    private long _continuousFence = -1;
    private NeutralInputProof? _prepareProof;
    private ObservationPrefix _grantPrefix, _deferredFence;
    private InputScope? _owner, _next;
    private InputScope? _handoffSource;
    private InputGesture? _gesture;
    private (InputGesture Gesture, ObservationPrefix End)? _completed;
    private (InputGesture Gesture, ObservedInputEdge Edge)? _deferredEnd;
    private InputOpenIntent? _intent;
    private bool _environment, _transport = true;

    internal InputHandoffCoordinator(PhysicalInputLedger ledger, string session, string coverageIdentity,
        IEnumerable<InputScope> scopes, ContinuousInputPolicy continuous = default)
    {
        _ledger = ledger ?? throw new ArgumentNullException(nameof(ledger));
        if (string.IsNullOrWhiteSpace(session) || string.IsNullOrWhiteSpace(coverageIdentity)) throw new ArgumentException("Identity is required");
        _session = session; _coverageIdentity = coverageIdentity;
        var exact = scopes.ToArray(); _coverage = exact.ToHashSet();
        if (exact.Length == 0 || exact.Length != _coverage.Count || exact.Any(scope => string.IsNullOrWhiteSpace(scope.Id) || scope.Incarnation <= 0)
            || exact.Select(scope => scope.Id).Distinct(StringComparer.Ordinal).Count() != exact.Length)
            throw new ArgumentException("Exact scope/incarnation coverage is required", nameof(scopes));
        if (continuous.Scopes != null)
            foreach (var pair in continuous.Scopes) {
                if (!_coverage.Contains(pair.Key) || pair.Value == null || pair.Value.Count == 0
                    || pair.Value.Any(key => !_ledger.Supports(key)))
                    throw new ArgumentException("Continuous keys must be a nonempty per-scope subset of covered scopes and supported keys", nameof(continuous));
                _continuous[pair.Key] = pair.Value.ToHashSet();
            }
    }

    internal InputHandoffPhase Phase { get; private set; } = InputHandoffPhase.BootClosed;
    internal string BlockReason { get; private set; } = "boot_closed";
    internal HandoffRound Round => new(_session, _coverageIdentity, _epoch, _ticket, _geometry);
    internal InputScope? Owner => _owner;
    internal InputScope? PreparingOwner => _next;
    internal bool HasPendingIntent => _intent.HasValue;
    internal bool HasContinuousHolds => _admitted.Count > 0;
    // This callback MUST use an independent control lane, never the failed data
    // queue. Delivery failure leaves this machine Revoking/Blocked, never ready.
    internal event Action<HandoffRound, IReadOnlyCollection<InputScope>>? CancelRequired;

    internal void SetEnvironment(bool eligible, long geometry)
    {
        if (geometry <= 0) throw new ArgumentOutOfRangeException(nameof(geometry));
        bool changed = _geometry != geometry || _environment != eligible;
        _geometry = geometry; _environment = eligible;
        if (changed && Phase != InputHandoffPhase.BootClosed) Revoke("environment_changed", false);
    }

    internal HandoffRound Start(InputScope target)
    {
        if (Phase != InputHandoffPhase.BootClosed) throw new InvalidOperationException("Already started");
        RequireScope(target); _next = target; return Revoke("startup", false);
    }

    internal HandoffRound Fail(string reason)
    {
        _transport = false;
        if (Phase == InputHandoffPhase.BootClosed) { BlockReason = reason; return Round; }
        return Revoke(reason, false);
    }

    // Recovery does not certify remote cleanup. Outstanding Cancelled receipts
    // still have to arrive, and a fresh neutral proof/prepare round is required.
    internal void TransportRecovered() { _transport = true; AdvanceAfterCancellation(); }

    internal HandoffRound Revoke(string reason, bool preserveIntent = false)
    {
        checked { _epoch++; _ticket++; }
        _owner = null; _gesture = null; _completed = null; _deferredEnd = null; _prepareProof = null;
        // Cancellation clears only this round's logical admission. The physical
        // ledger keeps the real held state, so no synthetic release is needed.
        _admitted.Clear(); _continuousFence = -1; _deferredFence = default;
        _cancelled.Clear(); _prepared.Clear();
        if (!preserveIntent) {
            _intent = null;
            if (_handoffSource.HasValue) _next = _handoffSource;
            _handoffSource = null;
        }
        Phase = InputHandoffPhase.Revoking; BlockReason = reason;
        CancelRequired?.Invoke(Round, _coverage.ToArray());
        return Round;
    }

    internal bool AcceptCancelled(CancelledScope receipt)
    {
        if (Phase != InputHandoffPhase.Revoking || receipt.Round != Round || !_coverage.Contains(receipt.Scope)
            || !receipt.GateClosed || !receipt.ObligationsSettled) return false;
        if (!_cancelled.Add(receipt.Scope)) return false;
        AdvanceAfterCancellation(); return true;
    }

    private void AdvanceAfterCancellation()
    {
        if (Phase is not (InputHandoffPhase.Revoking or InputHandoffPhase.Blocked)) return;
        if (!_cancelled.SetEquals(_coverage)) return;
        Phase = _transport ? InputHandoffPhase.WaitNeutral : InputHandoffPhase.Blocked;
        BlockReason = _transport ? "wait_neutral" : "transport_unhealthy";
    }

    internal bool TryPrepare(out ObservationPrefix prefix)
    {
        prefix = default;
        if (Phase != InputHandoffPhase.WaitNeutral || !_transport || !_environment || !_next.HasValue || _intent.HasValue) return false;
        _prepareProof = _ledger.TryProveNeutral(); if (!_prepareProof.HasValue) return false;
        checked { _ticket++; } // retry has a new ticket even when epoch/geometry stay constant
        _prepared.Clear(); Phase = InputHandoffPhase.Preparing;
        prefix = _prepareProof.Value.Prefix; return true;
    }

    internal bool AcceptPrepared(PreparedScope receipt)
    {
        if (!PrepareStillValid()) return false;
        return receipt.Round == Round && _coverage.Contains(receipt.Scope) && receipt.Prefix == _prepareProof!.Value.Prefix
            && _prepared.Add(receipt.Scope);
    }

    private bool PrepareStillValid()
    {
        if (Phase != InputHandoffPhase.Preparing) return false;
        if (_environment && _transport && _prepareProof.HasValue && _ledger.IsCurrent(_prepareProof.Value)) return true;
        _prepareProof = null; _prepared.Clear(); Phase = InputHandoffPhase.WaitNeutral;
        BlockReason = "prepare_interrupted"; return false;
    }

    // Must run on a fresh serialized turn after the adapter drains observations.
    // READY itself never grants. prefixDrained is adapter evidence, not a timer.
    internal bool TryGrant(bool prefixDrained)
    {
        if (!PrepareStillValid() || !_prepared.SetEquals(_coverage) || !prefixDrained) return false;
        _grantPrefix = _prepareProof!.Value.Prefix; _owner = _next;
        _handoffSource = null;
        Phase = InputHandoffPhase.Ready; BlockReason = ""; return true;
    }

    // Ordering contract: for each drained edge the adapter first calls
    // ObservationChanged(edge) for revocation bookkeeping, then routes the same
    // edge to AcceptContinuousEdge/Begin/Complete. A fresh edge on a key
    // declared for the CURRENT owner is legal continuous input, never a
    // conflict: it only refreshes the retained completion/deferred fences.
    // Any other observation still invalidates them exactly as before.
    internal void ObservationChanged(ObservedInputEdge? edge = null)
    {
        if (Phase == InputHandoffPhase.BootClosed) return;
        if (Phase is InputHandoffPhase.Ready or InputHandoffPhase.Held
            && _ledger.Prefix.Generation != _grantPrefix.Generation) {
            Revoke("source_generation_changed", false); return;
        }
        bool continuous = edge.HasValue && _owner.HasValue && edge.Value.Prefix == _ledger.Prefix
            && edge.Value.Prefix.Generation == _grantPrefix.Generation && Declared(_owner.Value, edge.Value.Key);
        bool repeatedEnd = edge.HasValue && edge.Value.Prefix == _ledger.Prefix
            && edge.Value.Prefix.Generation == _grantPrefix.Generation
            && edge.Value.Duplicate && !edge.Value.Down
            && ((_completed.HasValue && edge.Value.Key == _completed.Value.Gesture.Key)
                || (_deferredEnd.HasValue && edge.Value.Key == _deferredEnd.Value.Gesture.Key));
        if (_completed.HasValue && _completed.Value.End != _ledger.Prefix) {
            if (continuous || repeatedEnd) _completed = (_completed.Value.Gesture, _ledger.Prefix); else _completed = null;
        }
        if (_deferredEnd.HasValue && edge.HasValue && edge.Value.Prefix != _deferredFence) {
            if (continuous || repeatedEnd) _deferredFence = edge.Value.Prefix;
            else { Revoke("input_after_deferred_end", false); return; }
        }
        if (!_ledger.SourcesHealthy) { Revoke("observation_unhealthy", false); return; }
        // Snapshot Up is not a business KeyRelease. Cancel contradictory old
        // admission rather than carrying it into a later fresh Down. A current
        // real Up is removed by AcceptContinuousEdge on this serialized turn.
        if (_admitted.Any(key => _ledger[key] != ObservedKeyState.Down
            && !(edge.HasValue && edge.Value.Prefix == _ledger.Prefix
                && edge.Value.Key == key && !edge.Value.Down && !edge.Value.Duplicate))) {
            Revoke("continuous_snapshot_disagrees", false); return;
        }
        if (Phase == InputHandoffPhase.Held && edge.HasValue && _gesture.HasValue && !continuous
            && (edge.Value.Key != _gesture.Value.Key || (edge.Value.Down && !edge.Value.Duplicate)))
        {
            Revoke("gesture_conflict", false); return;
        }
        if (_admitted.Count > 0 && (!_ledger.HasQualifiedBaseline || !continuous)) {
            // A newly pressed left pointer may begin the one gesture. Any
            // other unadmitted hold or unknown baseline stops continuous work
            // through ordinary cancellation, without changing physical state.
            int pointer = _gesture?.Key ?? (edge.HasValue && edge.Value.Key == 1 ? 1 : 0);
            if (!_ledger.IsNeutralExcept(_admitted, pointer)) {
                Revoke("continuous_input_conflict", false); return;
            }
        }
        if (Phase == InputHandoffPhase.Preparing) PrepareStillValid();
    }

    // A key declared continuous for its owner is movement input, never the
    // single pointer gesture. Legally admitted held keys do not defeat Begin.
    internal InputGesture? Begin(InputScope scope, ObservedInputEdge edge, long geometry)
    {
        if (Phase != InputHandoffPhase.Ready || scope != _owner || !_environment || !_transport || !_ledger.SourcesHealthy
            || geometry != _geometry || edge.Prefix != _ledger.Prefix || edge.Prefix.Generation != _grantPrefix.Generation
            || edge.Prefix.Sequence <= _grantPrefix.Sequence || !edge.Down || edge.Duplicate || Declared(scope, edge.Key)
            || !(edge.WasNeutral || (_continuous.ContainsKey(scope) && _ledger.IsNeutralExcept(_admitted, edge.Key)))) return null;
        _completed = null;
        _gesture = new InputGesture(Round, scope, ++_gestureSequence, edge.Key, edge.Prefix.Sequence);
        Phase = InputHandoffPhase.Held; return _gesture;
    }

    internal bool Complete(InputGesture gesture, ObservedInputEdge edge, long geometry)
    {
        bool valid = Phase == InputHandoffPhase.Held && _gesture == gesture && gesture.Round == Round
            && gesture.Scope == _owner && _environment && _transport && _ledger.SourcesHealthy && geometry == _geometry
            && edge.Prefix == _ledger.Prefix && edge.Prefix.Generation == _grantPrefix.Generation
            && edge.Prefix.Sequence > gesture.BeginSequence && edge.Key == gesture.Key && !edge.Down && !edge.Duplicate
            && _ledger.IsNeutralExcept(_admitted);
        if (!valid) return false;
        _completed = (gesture, edge.Prefix);
        _gesture = null; Phase = InputHandoffPhase.Ready; return true;
    }

    // A sampled aggregate Up can precede its queued Raw Up. Snapshot conflict
    // invalidates neutral proof, but must not permanently strand a valid Held
    // gesture. Retain this one real End until a qualified snapshot settles it.
    // This does not invent/replay an edge or clear physical state.
    internal bool DeferCompletion(InputGesture gesture, ObservedInputEdge edge, long geometry)
    {
        if (Phase != InputHandoffPhase.Held || _gesture != gesture || gesture.Round != Round
            || gesture.Scope != _owner || !_environment || !_transport || !_ledger.SourcesHealthy || geometry != _geometry
            || edge.Prefix != _ledger.Prefix || edge.Prefix.Generation != _grantPrefix.Generation
            || edge.Prefix.Sequence <= gesture.BeginSequence || edge.Key != gesture.Key || edge.Down || edge.Duplicate) return false;
        _deferredEnd = (gesture, edge); _deferredFence = edge.Prefix; return true;
    }

    internal bool TryCompleteDeferred(out InputGesture gesture, out ObservedInputEdge edge)
    {
        gesture = default; edge = default;
        if (!_deferredEnd.HasValue || Phase != InputHandoffPhase.Held || !_ledger.IsNeutralExcept(_admitted) || !_environment || !_transport
            || _deferredEnd.Value.Gesture.Round != Round || _deferredEnd.Value.Edge.Prefix.Generation != _ledger.Prefix.Generation) return false;
        (gesture, edge) = _deferredEnd.Value;
        _deferredEnd = null; _deferredFence = default; _gesture = null; _completed = (gesture, _ledger.Prefix);
        Phase = InputHandoffPhase.Ready; return true;
    }

    // Atomically finish the valid gesture, mint an intent, then revoke its old
    // domain. Neither ACK retries nor duplicate End can mint another opener.
    internal InputOpenIntent? CompleteAndHandoff(InputGesture gesture, ObservedInputEdge edge, long geometry, InputScope target, string destination)
    {
        RequireScope(target);
        if (string.IsNullOrWhiteSpace(destination)) return null;
        if (!Complete(gesture, edge, geometry)) return null;
        return HandoffCompleted(gesture, target, destination);
    }

    // The actual endpoint can report its opener after consuming End. Retain
    // only this exact completion; a newer observation invalidates the request.
    internal InputOpenIntent? HandoffCompleted(InputGesture gesture, InputScope target, string destination)
    {
        RequireScope(target);
        if (string.IsNullOrWhiteSpace(destination) || Phase != InputHandoffPhase.Ready
            || !_completed.HasValue || _completed.Value.Gesture != gesture || _completed.Value.End != _ledger.Prefix
            || gesture.Round != Round || gesture.Scope != _owner || !_environment || !_transport
            || !_ledger.IsNeutralExcept(_admitted)) return null;
        _completed = null;
        _intent = new InputOpenIntent(++_intentSequence, destination, gesture);
        _handoffSource = gesture.Scope;
        _next = target; var result = _intent; Revoke("handoff", true); return result;
    }

    // Consume after cancellation, to construct/prepare the destination with its
    // gate still CLOSED. Opening a visual is not an input grant. The adapter must
    // cancel the whole handoff if construction fails, not replay this intent.
    internal bool ConsumeIntentForPreparation(InputOpenIntent intent)
    {
        if (Phase != InputHandoffPhase.WaitNeutral || _intent != intent || !_environment || !_transport) return false;
        _intent = null; return true;
    }

    // Explicit adapter contract for a retained page lifetime: after consuming
    // the validated one-shot opener, construction continues behind a CLOSED
    // gate across geometry changes. A construction failure must Fail, never
    // grant or replay the opener. This binds a destination, not input authority.
    // Adapters without this retained-lifetime contract keep rollback semantics.
    internal bool ConsumeIntentForRetainedPreparation(InputOpenIntent intent)
    {
        if (!ConsumeIntentForPreparation(intent)) return false;
        _handoffSource = null;
        return true;
    }

    // Presentation-only hover targets have no business opener. This is not a
    // substitute for Complete/HandoffCompleted for command-producing endpoints.
    internal bool SelectReadOnlyHover(InputScope target)
    {
        RequireScope(target);
        if (Phase != InputHandoffPhase.Ready || !_environment || !_transport
            || _intent.HasValue || target == _owner) return false;
        _next = target; Revoke("readonly_hover", false); return true;
    }

    // The adapter must first close the actual retired controller. Replacement
    // is allowed only behind its complete cancellation coverage, never by hide.
    internal bool ReplaceRetiredScope(InputScope oldScope, InputScope replacement, InputScope emptyFallback, bool restore)
    {
        RequireScope(oldScope); RequireScope(emptyFallback);
        // The existing replacement lane serves Web with an empty key policy.
        // A continuous endpoint needs separate qualification of its new policy;
        // never silently downgrade its movement keys to ordinary gesture keys.
        if (_continuous.ContainsKey(oldScope)) return false;
        if (Phase is not (InputHandoffPhase.WaitNeutral or InputHandoffPhase.Blocked)
            || !_cancelled.SetEquals(_coverage) || replacement.Id != oldScope.Id || replacement.Incarnation <= oldScope.Incarnation) return false;
        _coverage.Remove(oldScope); _coverage.Add(replacement);
        var next = restore ? replacement : emptyFallback;
        if (_next == oldScope) _next = next;
        if (_handoffSource == oldScope) _handoffSource = next;
        Revoke("endpoint_replaced", true); return true;
    }

    // Same serialized turn, AFTER ObservationChanged(edge) for that edge. Only
    // a fresh same-generation edge on a key declared for the CURRENT owner
    // mints one ContinuousKeyEvent carrying round/scope/key/down/sequence.
    // Duplicate, stale, undeclared or cross-owner edges mint nothing. Down
    // admits the key into the neutral exemption; Up requires a prior admitted
    // Down, so an observed-but-not-admitted release produces no business.
    internal ContinuousKeyEvent? AcceptContinuousEdge(ObservedInputEdge edge, long geometry)
    {
        if (Phase is not (InputHandoffPhase.Ready or InputHandoffPhase.Held) || !_owner.HasValue
            || !Declared(_owner.Value, edge.Key) || !_environment || !_transport || !_ledger.SourcesHealthy
            || geometry != _geometry || edge.Prefix != _ledger.Prefix || edge.Prefix.Generation != _grantPrefix.Generation
            || edge.Prefix.Sequence <= _grantPrefix.Sequence || edge.Duplicate
            || edge.Prefix.Sequence <= _continuousFence) return null;
        // Monotone sequence alone cannot prove freshness: a delayed Down may
        // arrive after its actual Up. Never admit against a different prefix,
        // unknown baseline, or an unrelated physical hold. The existing single
        // gesture may coexist, but snapshot-held movement keys may not.
        var allowed = new HashSet<int>(_admitted);
        if (edge.Down) allowed.Add(edge.Key);
        if (!_ledger.IsNeutralExcept(allowed, _gesture?.Key ?? 0)
            || _ledger[edge.Key] != (edge.Down ? ObservedKeyState.Down : ObservedKeyState.Up)) return null;
        bool admitted = edge.Down ? _admitted.Add(edge.Key) : _admitted.Remove(edge.Key);
        if (!admitted) return null;
        _continuousFence = edge.Prefix.Sequence;
        return new ContinuousKeyEvent(Round, _owner.Value, edge.Key, edge.Down, edge.Prefix.Sequence);
    }

    private bool Declared(InputScope scope, int key) =>
        _continuous.TryGetValue(scope, out var keys) && keys.Contains(key);

    private void RequireScope(InputScope scope)
    {
        if (!_coverage.Contains(scope)) throw new ArgumentException("Scope is outside the executable coverage", nameof(scope));
    }
}
