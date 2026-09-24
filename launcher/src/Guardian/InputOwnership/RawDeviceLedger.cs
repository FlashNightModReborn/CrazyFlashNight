#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;

namespace CF7Launcher.Guardian.InputOwnership;

internal enum RawPacketResult { Observed, Ignored, Invalid }
internal readonly record struct RawKeyChange(int Key, bool Down);

/// <summary>
/// Device aggregation for the isolated input adapter. Raw Input carries no
/// trustworthy hardware/injection attribution. Only a qualified OS snapshot may
/// clear an unattributed pre-held key; an orphan Up on another keyboard cannot.
/// This class neither installs an observer nor certifies its continuity.
/// </summary>
internal sealed class RawDeviceLedger
{
    private readonly Dictionary<long, HashSet<int>> _held = new();
    private readonly HashSet<int> _unattributed = new();
    private readonly Dictionary<(long Device, int Physical), int> _keyboard = new();
    private readonly RawModifierTracker _modifiers = new();
    internal static readonly int[] SnapshotKeys = Enumerable.Range(1, 254).ToArray();

    internal void Reset()
    {
        _held.Clear(); _unattributed.Clear(); _keyboard.Clear(); _modifiers.Reset();
    }

    internal bool IsDown(int key) => _unattributed.Contains(key) || _held.Values.Any(keys => keys.Contains(key));
    internal bool HasUnattributedHolds => _unattributed.Count != 0;

    internal bool SnapshotConsistent(IReadOnlyDictionary<int, bool> snapshot) =>
        snapshot.Count == SnapshotKeys.Length && SnapshotKeys.All(snapshot.ContainsKey)
        && _held.Values.SelectMany(keys => keys).All(key => snapshot[key]);

    // Call only AFTER the physical ledger has accepted the complete snapshot.
    // A snapshot is aggregate, not per-device: do not assign it to a made-up
    // keyboard. An aggregate OS Up cannot clear a known per-device hold.
    internal void Reconcile(IReadOnlyDictionary<int, bool> snapshot)
    {
        if (snapshot.Count != SnapshotKeys.Length || SnapshotKeys.Any(key => !snapshot.ContainsKey(key)))
            throw new ArgumentException("An exact complete snapshot is required", nameof(snapshot));
        if (!SnapshotConsistent(snapshot)) throw new InvalidOperationException("Snapshot contradicts a known device hold");
        _unattributed.Clear();
        foreach (var pair in snapshot)
            if (pair.Value && !_held.Values.Any(keys => keys.Contains(pair.Key))) _unattributed.Add(pair.Key);
    }

    internal RawPacketResult Keyboard(long device, int virtualKey, int scan, int flags, out RawKeyChange[] changes)
    {
        changes = Array.Empty<RawKeyChange>();
        if (scan == 0xFF || (flags & ~7) != 0) return RawPacketResult.Invalid; // keyboard overrun / unknown ABI
        if (virtualKey == 255) return RawPacketResult.Ignored; // documented fake key, not VK state
        if (virtualKey < 8 || virtualKey > 254 || scan <= 0 || scan > 0x7F) return RawPacketResult.Invalid;
        // Pause has no ordinary break edge. Do not add an immortal per-device
        // hold which would then forbid every neutral snapshot. Unsupported pulse
        // input cancels this source generation; recovery requires real snapshots.
        if (virtualKey == 19) return RawPacketResult.Invalid;
        int key = virtualKey, aggregate = 0;
        if (key is 16 or 17 or 18 || key is >= 160 and <= 165)
        {
            var disposition = _modifiers.Observe(device, key, scan, flags, out var modifier);
            if (disposition != RawModifierDisposition.Observed) return RawPacketResult.Invalid;
            key = modifier.Key; aggregate = modifier.AggregateKey;
        }
        // Unknown E1 layouts close admission.
        else if ((flags & 4) != 0) return RawPacketResult.Invalid;
        bool down = (flags & 1) == 0;
        var physical = (device, (scan << 3) | (flags & 6));
        if (down)
        {
            if (_keyboard.TryGetValue(physical, out int previous) && previous != key) return RawPacketResult.Invalid;
            _keyboard[physical] = key;
        }
        else if (_keyboard.Remove(physical, out int previous)) key = previous;
        // Main Enter and keypad Enter may share one VK on the same keyboard.
        Set(device, key, _keyboard.Any(pair => pair.Key.Device == device && pair.Value == key));
        var result = new List<RawKeyChange> { new(key, IsDown(key)) };
        if (aggregate != 0)
        {
            int left = aggregate == 16 ? 160 : aggregate == 17 ? 162 : 164;
            // Aggregate aliases are not separate physical keys. Unattributed
            // snapshot aliases stay conservative until the next reconciliation.
            bool aggregateDown = IsDown(left) || IsDown(left + 1) || _unattributed.Contains(aggregate);
            result.Add(new RawKeyChange(aggregate, aggregateDown));
        }
        changes = result.ToArray(); return RawPacketResult.Observed;
    }

    internal RawPacketResult Mouse(long device, int flags, out RawKeyChange[] changes)
    {
        changes = Array.Empty<RawKeyChange>();
        if ((flags & ~0xFFF) != 0) return RawPacketResult.Invalid;
        int[] keys = { 1, 2, 4, 5, 6 };
        var result = new List<RawKeyChange>();
        for (int i = 0; i < keys.Length; i++)
        {
            int pair = (flags >> (i * 2)) & 3;
            // A packet with both edges has no ordering contract. Do not guess.
            if (pair == 3) return RawPacketResult.Invalid;
        }
        for (int i = 0; i < keys.Length; i++)
        {
            int pair = (flags >> (i * 2)) & 3;
            if (pair == 0) continue;
            Set(device, keys[i], pair == 1); result.Add(new RawKeyChange(keys[i], IsDown(keys[i])));
        }
        changes = result.ToArray(); return result.Count == 0 ? RawPacketResult.Ignored : RawPacketResult.Observed;
    }

    private void Set(long device, int key, bool down)
    {
        if (!_held.TryGetValue(device, out var keys))
        {
            if (!down) return;
            _held.Add(device, keys = new HashSet<int>());
        }
        if (down) keys.Add(key); else keys.Remove(key);
        if (keys.Count == 0) _held.Remove(device);
    }
}
