#nullable enable
using System.Collections.Generic;
using System.Linq;

namespace CF7Launcher.Guardian.InputOwnership;

internal enum RawModifierDisposition { NotModifier, Observed, Unsupported }
internal readonly record struct RawModifierObservation(int Key,bool RawDown,bool KeyDown,int AggregateKey,bool AggregateDown);

/// <summary>
/// Candidate normalization of RAWKEYBOARD modifier observations. It preserves
/// device-held state and never issues an owner grant or a health certificate.
/// Registration/device-generation changes and unknown packets require the
/// caller to invalidate its observation authority; resetting this tracker alone
/// is not evidence that keys were physically released.
/// </summary>
internal sealed class RawModifierTracker
{
    private readonly Dictionary<long,HashSet<int>> _devices=new();
    internal IReadOnlyCollection<int> HeldKeys=>_devices.Values.SelectMany(v=>v).Distinct().Order().ToArray();
    internal void Reset()=>_devices.Clear();

    internal RawModifierDisposition Observe(long device,int virtualKey,int scan,int flags,out RawModifierObservation observation)
    {
        observation=default;
        if(virtualKey is not (16 or 17 or 18) && (virtualKey<160 || virtualKey>165))return RawModifierDisposition.NotModifier;
        // Do not guess a side for virtual-key-only injection (scan=0), E1,
        // overrun, contradictory explicit keys, or an unsupported flags layout.
        if((flags&~3)!=0)return RawModifierDisposition.Unsupported;
        bool extended=(flags&2)!=0;
        int family=virtualKey is 16 or 160 or 161?16:virtualKey is 17 or 162 or 163?17:18;
        int key=family switch {
            16 when !extended && scan==42=>160,
            16 when !extended && scan==54=>161,
            17 when scan==29=>extended?163:162,
            18 when scan==56=>extended?165:164,
            _=>0
        };
        if(key==0 || (virtualKey>=160 && virtualKey!=key))return RawModifierDisposition.Unsupported;
        bool down=(flags&1)==0;
        if(!_devices.TryGetValue(device,out var held)) {
            // An orphan Up is an observation, not a synthetic Down; do not keep
            // an unbounded registry of devices that hold no supported keys.
            if(down){held=new HashSet<int>();_devices.Add(device,held);}
        }
        if(held!=null) {
            if(down)held.Add(key);else held.Remove(key);
            if(held.Count==0)_devices.Remove(device);
        }
        int left=family==16?160:family==17?162:164;
        observation=new RawModifierObservation(key,down,
            _devices.Values.Any(keys=>keys.Contains(key)),family,
            _devices.Values.Any(keys=>keys.Contains(left) || keys.Contains(left+1)));
        return RawModifierDisposition.Observed;
    }
}
