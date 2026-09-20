#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Diagnostics;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed record PlayerHudTarget(string Kind, int Slot, string Key, long Epoch,
    long Revision, int Bank, RectangleF Anchor, long ConnectionGeneration = 0, bool Paused = false);

/// <summary>UI-thread action owner. Transport callbacks only enqueue bounded work.</summary>
internal sealed class PlayerHudController : IDisposable
{
    private readonly Func<string, bool> _send;
    private readonly Func<bool> _connected;
    private readonly Action<Action> _dispatch;
    private readonly Queue<(long Generation, string Payload, long Enqueued)> _queue = new();
    private readonly object _gate = new();
    private readonly string _nonce = Guid.NewGuid().ToString("N");
    private bool _posted, _reset, _disposed;
    private long _nextId, _lastQuery, _hoverSequence;
    private long _generation, _adoptedGeneration = -1;
    private long _profileGeneration = -1;
    internal long Generation => System.Threading.Interlocked.Read(ref _generation);
    private string? _pendingId, _hoverId;
    private bool _resourceHover;
    internal PlayerHudState State { get; } = new();
    private long _poiseRequestGeneration = -1;
    internal PlayerHudProfiler? Profiler { get; } = PlayerHudProfiler.CreateFromEnvironment();
    internal bool WritePending => _pendingId != null;
    internal bool CanInteract => !_disposed && _connected() && _adoptedGeneration == Generation && State.Snapshot != null;
    internal string Message { get; private set; } = "";
    internal event Action? StatusChanged;
    internal event Action<PlayerHudTarget?>? ResourceTooltipRequested;

    internal PlayerHudController(Func<string, bool> send, Func<bool> connected, Action<Action> dispatch)
    {
        _send = send; _connected = connected; _dispatch = dispatch;
        State.ActionResult += OnResult;
    }

    /// <returns>Only unrelated data for the existing Web/NativeHud consumers.</returns>
    internal string TakeUiData(string raw)
    {
        if (_disposed || string.IsNullOrEmpty(raw)) return raw;
        if (!raw.StartsWith("pi:", StringComparison.Ordinal) && !raw.Contains("|pi:", StringComparison.Ordinal)) return raw;
        var remaining = new List<string>();
        foreach (var pair in raw.Split('|'))
        {
            if (pair.StartsWith("pi:", StringComparison.Ordinal)) Enqueue(pair.Substring(3));
            else remaining.Add(pair);
        }
        return string.Join("|", remaining);
    }

    private void Enqueue(string encoded)
    {
        if (encoded.Length > PlayerHudState.MaximumEncodedLength) return;
        lock (_gate)
        {
            if (_disposed) return;
            if (_queue.Count >= 64) { _queue.Clear(); _reset = true; }
            _queue.Enqueue((Generation, encoded, Profiler == null ? 0 : Stopwatch.GetTimestamp()));
            if (_posted) return;
            _posted = true;
        }
        _dispatch(Drain);
    }

    private void Drain()
    {
        (long Generation, string Payload, long Enqueued)[] packets; bool reset;
        lock (_gate)
        {
            if (_disposed) return;
            packets = _queue.ToArray(); _queue.Clear(); _posted = false;
            reset = _reset; _reset = false;
        }
        if (reset) { State.Disconnect(); Send(new JObject { ["action"] = "playerHudSync" }); }
        foreach (var packet in packets)
        {
            if (packet.Generation != Generation) continue;
            var started = Profiler == null ? 0 : Stopwatch.GetTimestamp();
            if (Profiler != null) Profiler.Record("receive.queueMs", Stopwatch.GetElapsedTime(packet.Enqueued, started).TotalMilliseconds);
            var before = State.AcceptedPackets;
            State.Receive(packet.Payload, Environment.TickCount64);
            if (Profiler != null)
            {
                Profiler.Record("receive.applyMs", Stopwatch.GetElapsedTime(started).TotalMilliseconds);
                Profiler.Record("receive.encodedBytes", packet.Payload.Length);
            }
            if (before != State.AcceptedPackets && State.Snapshot != null && packet.Generation == Generation)
                _adoptedGeneration = packet.Generation;
        }
        if (CanInteract && _poiseRequestGeneration != Generation &&
            Send(new JObject { ["action"] = "playerHudSync", ["poiseDetails"] = true }))
            _poiseRequestGeneration = Generation;
        if (Profiler != null && CanInteract && _profileGeneration != Generation &&
            Send(new JObject { ["action"] = "playerHudProfile", ["enabled"] = true, ["profileId"] = Profiler.Id }))
            _profileGeneration = Generation;
    }

    internal void Disconnected()
    {
        if (_disposed) return;
        System.Threading.Interlocked.Increment(ref _generation);
        _adoptedGeneration = -1;
        lock (_gate) { _queue.Clear(); _reset = true; }
        _dispatch(() => { if (!_disposed) { State.Disconnect(); HideTooltip(); } });
        // A connection/window/actor change does not resolve an unknown write.
    }

    internal bool Act(PlayerHudTarget target)
    {
        if (_disposed || WritePending || !_connected() || target.ConnectionGeneration != Generation || _adoptedGeneration != Generation || State.Snapshot?.Epoch != target.Epoch) return false;
        if (target.Kind is not ("skill" or "drug" or "switch")) return false;
        _pendingId = "ph:" + _nonce + ":" + (++_nextId);
        _lastQuery = Environment.TickCount64;
        Message = "正在确认操作…";
        var request = Identity(target, "playerHudAction"); request["actionId"] = _pendingId;
        Send(request); // A failed send may be delivery-unknown. Only exact results resolve it.
        StatusChanged?.Invoke(); return true;
    }

    internal void Tick(long now)
    {
        Profiler?.Flush();
        if (!_disposed && _pendingId != null && now - _lastQuery >= 1500 && _connected())
        {
            _lastQuery = now;
            Message = "操作结果待确认，请稍候";
            Send(new JObject { ["action"] = "playerHudQuery", ["actionId"] = _pendingId });
            StatusChanged?.Invoke();
        }
    }

    private void OnResult(PlayerHudActionResult result)
    {
        if (result.ActionId != _pendingId) return;
        if (result.Error is "pending" or "unknown" or "needs_reconcile")
        {
            Message = "操作结果待确认，请勿重复操作";
        }
        else
        {
            _pendingId = null;
            Message = result.Success ? "" : result.Error switch
            {
                "bag_full" => "背包空间不足，请先腾出一个空格",
                "cooldown" => "冷却尚未结束，请稍后再试",
                "locked" => "当前物品已锁定",
                "stale_state" => "栏位已变化，请重新选择",
                _ => "当前无法操作，请稍后再试"
            };
        }
        StatusChanged?.Invoke();
    }

    internal void ShowTooltip(PlayerHudTarget target)
    {
        HideTooltip();
        if (!_connected() || target.ConnectionGeneration != Generation || _adoptedGeneration != Generation || State.Snapshot?.Epoch != target.Epoch) return;
        if(target.Kind=="resources")
        {
            _resourceHover=true;ResourceTooltipRequested?.Invoke(target);return;
        }
        _hoverId = "phh:" + _nonce + ":" + (++_hoverSequence);
        var message = Identity(target, "playerHudTooltip");
        message["op"] = "show"; message["hoverId"] = _hoverId;
        message["anchor"] = new JObject { ["x"] = target.Anchor.X, ["y"] = target.Anchor.Y,
            ["width"] = target.Anchor.Width, ["height"] = target.Anchor.Height };
        Send(message);
    }

    internal void HideTooltip()
    {
        if(_resourceHover){_resourceHover=false;ResourceTooltipRequested?.Invoke(null);}
        if (_hoverId != null) Send(new JObject { ["action"] = "playerHudTooltip", ["op"] = "hide", ["hoverId"] = _hoverId });
        _hoverId = null;
    }

    private static JObject Identity(PlayerHudTarget t, string action) => new()
    {
        ["action"] = action, ["epoch"] = t.Epoch, ["kind"] = t.Kind,
        ["slot"] = t.Slot, ["key"] = t.Key, ["revision"] = t.Revision, ["bank"] = t.Bank, ["paused"] = t.Paused
    };
    private bool Send(JObject message)
    {
        if (_disposed || !_connected()) return false;
        message["task"] = "cmd";
        try { return _send(message.ToString(Formatting.None) + "\0"); }
        catch (Exception) { return false; }
    }
    public void Dispose()
    {
        HideTooltip(); _disposed = true; State.ActionResult -= OnResult;
        Profiler?.Dispose();
        lock (_gate) _queue.Clear();
    }
}
