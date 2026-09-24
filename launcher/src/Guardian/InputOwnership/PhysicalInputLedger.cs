#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;

namespace CF7Launcher.Guardian.InputOwnership;

internal enum ObservedKeyState : byte { Unknown, Up, Down }
// Unmarked is not hardware attestation. Hardware is reserved for separately
// attributed sources; absence of an LL injected bit cannot establish it.
internal enum InputObservationSource { Hardware, Injected, Unmarked }
internal readonly record struct ObservationPrefix(long Generation, long Sequence);
internal readonly record struct NeutralInputProof(ObservationPrefix Prefix);
internal readonly record struct ObservedInputEdge(
    ObservationPrefix Prefix, int Key, bool Down, InputObservationSource Source,
    bool WasNeutral, bool Duplicate);

/// <summary>
/// Owner-independent state. It has no focus, display, routing or cancellation
/// operations. An endpoint being hidden/cancelled cannot invent a physical Up.
/// The OS adapter, not this state machine, must establish snapshot eligibility
/// and the health of its observation sources. Tests of this class do not certify
/// that adapter or a Windows hook.
/// </summary>
internal sealed class PhysicalInputLedger
{
    private readonly Dictionary<int, ObservedKeyState> _keys;
    private long _generation=1, _sequence;
    private bool _baselineQualified;
    internal PhysicalInputLedger(IEnumerable<int> supportedKeys)
    {
        ArgumentNullException.ThrowIfNull(supportedKeys);
        var keys=supportedKeys.ToArray();
        if(keys.Length==0 || keys.Any(k=>k<1 || k>254) || keys.Distinct().Count()!=keys.Length)
            throw new ArgumentException("Supported physical keys must be a nonempty exact set",nameof(supportedKeys));
        _keys=keys.ToDictionary(k=>k,_=>ObservedKeyState.Unknown);
    }
    internal ObservationPrefix Prefix=>new(_generation,_sequence);
    internal bool SourcesHealthy {get;private set;}
    internal bool HasQualifiedBaseline => _baselineQualified;
    internal string BlockReason {get;private set;}="boot_unknown";
    internal bool IsNeutral=>SourcesHealthy && _baselineQualified && _keys.Values.All(v=>v==ObservedKeyState.Up);
    internal ObservedKeyState this[int key]=>_keys.TryGetValue(key,out var state)?state:ObservedKeyState.Unknown;
    internal bool Supports(int key)=>_keys.ContainsKey(key);
    // Neutral except Down keys admitted through fresh same-generation edges in
    // the current owner round. Unknown and snapshot-held keys are never exempt;
    // only an edge admitted via AcceptContinuousEdge enters the exempt set.
    internal bool IsNeutralExcept(IReadOnlySet<int> admittedHeld,int exceptKey=0)
    {
        if(!SourcesHealthy || !_baselineQualified)return false;
        foreach(var pair in _keys)
            if(pair.Value!=ObservedKeyState.Up
                && !(pair.Value==ObservedKeyState.Down && (pair.Key==exceptKey || admittedHeld.Contains(pair.Key))))return false;
        return true;
    }

    internal ObservationPrefix Invalidate(string reason)
    {
        checked{_generation++;_sequence++;}
        SourcesHealthy=false;_baselineQualified=false;BlockReason=reason;
        foreach(int key in _keys.Keys.ToArray())_keys[key]=ObservedKeyState.Unknown;
        return Prefix;
    }
    // Only a fresh source registration/health proof may follow an invalidation.
    // It does not itself manufacture a neutral baseline.
    internal bool ConfirmSources(ObservationPrefix registrationPrefix)
    {
        if(registrationPrefix!=Prefix)return false;
        SourcesHealthy=true;BlockReason="baseline_unknown";return true;
    }
    // An ordinary sampling race is not loss of the observation source. Revoke
    // the cached neutral proof, then permit a fresh qualified/drained snapshot.
    // No owner may grant input while this baseline is awaiting reconciliation.
    private void DeferSnapshot(string reason)
    {
        checked{_sequence++;}
        _baselineQualified=false;BlockReason=reason;
    }
    // Query eligibility or per-device consistency can be temporarily unavailable
    // without losing the source. Preserve held state but revoke neutral proofs.
    internal void RequireReconciliation(string reason) => DeferSnapshot(reason);
    internal ObservedInputEdge? Observe(long sourceGeneration,int key,bool down,InputObservationSource source)
    {
        if(sourceGeneration!=_generation || !_keys.TryGetValue(key,out var previous))return null;
        bool neutral=IsNeutral;
        checked{_sequence++;}
        var state=down?ObservedKeyState.Down:ObservedKeyState.Up;
        _keys[key]=state;
        if (_baselineQualified) BlockReason = IsNeutral ? "" : "held";
        return new ObservedInputEdge(Prefix,key,down,source,neutral,previous==state);
    }
    /// <summary>
    /// Both complete snapshots must agree, refer to the same qualified desktop
    /// and source prefix, and have no intervening observed edge. The adapter must
    /// drain its observation prefix before calling. A zero result alone is not
    /// an environment qualification. Snapshots are copied, never retained.
    /// </summary>
    internal bool TryReconcile(ObservationPrefix fence,
        IReadOnlyDictionary<int,bool> before,IReadOnlyDictionary<int,bool> after,
        bool environmentQualified,bool prefixDrained)
    {
        if(!SourcesHealthy || fence!=Prefix)return false;
        if(!environmentQualified || before.Count!=_keys.Count || after.Count!=_keys.Count) {
            Invalidate("snapshot_unqualified");return false;
        }
        if(!prefixDrained){DeferSnapshot("snapshot_prefix_pending");return false;}
        foreach(int key in _keys.Keys)
            if(!before.ContainsKey(key) || !after.ContainsKey(key)) {
                Invalidate("snapshot_key_set_mismatch");return false;
            }
        if(_keys.Keys.Any(key=>before[key]!=after[key])){DeferSnapshot("snapshot_raced");return false;}
        foreach(int key in _keys.Keys.ToArray())_keys[key]=after[key]?ObservedKeyState.Down:ObservedKeyState.Up;
        // Sampling is an observation too. Even all-zero refresh invalidates a
        // prior grant proof, preventing a cached proof from crossing a new fence.
        checked{_sequence++;}
        _baselineQualified=true;
        BlockReason=IsNeutral?"":"held";
        return true;
    }
    internal NeutralInputProof? TryProveNeutral()=>IsNeutral?new NeutralInputProof(Prefix):null;
    internal bool IsCurrent(NeutralInputProof proof)=>IsNeutral && proof.Prefix==Prefix;
}
