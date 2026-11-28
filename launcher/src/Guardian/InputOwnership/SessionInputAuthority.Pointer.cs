using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;

namespace CF7Launcher.Guardian.InputOwnership;

internal sealed partial class SessionInputAuthority
{
    internal const string WorldEndpoint="flash.world";
    private sealed record PointerClaim(PointerGestureTicket Ticket,string Target);
    private readonly Dictionary<long,PointerClaim> _pointers=new();
    private readonly Dictionary<int,long> _buttons=new();
    private readonly Dictionary<string,long> _pointerInstances=new(StringComparer.Ordinal);
    private long _pointerEpoch=1, _geometry=1, _gesture;
    private int _worldCancelSequence;
    private (int Ticket, uint NativeEpoch)? _pendingWorldCancel;
    private InputWireRecord? _worldCancelControl;
    public long CurrentPointerEpoch {get {lock(_gate)return _pointerEpoch;}}
    public long CurrentGeometryVersion {get {lock(_gate)return _geometry;}}
    internal event Action<long> GestureInvalidated;
    internal long LastGestureId {get {lock(_gate)return _gesture;}}
    private bool PointerAvailable => _bound && _foreground && !_sequenceExhausted && !_transportFailed && _pointerEpoch<long.MaxValue;
    private bool WorldPointerAvailable => _game && _geometry<long.MaxValue &&
        _pendingWorldCancel == null && _worldCancelSequence < int.MaxValue;

    internal object DescribePointerAdmission(string endpointId, long instanceGeneration, int button)
    {
        lock (_gate)
        {
            _pointerInstances.TryGetValue(endpointId, out long currentInstance);
            _buttons.TryGetValue(button, out long gestureId);
            _pointers.TryGetValue(gestureId, out var claim);
            return new { bound = _bound, foreground = _foreground, transportFailed = _transportFailed,
                sequenceExhausted = _sequenceExhausted, pointerEpoch = _pointerEpoch, geometryVersion = _geometry,
                endpointId, instanceGeneration, currentInstance, button, occupyingEndpoint = claim?.Ticket.EndpointId,
                occupyingGesture = claim?.Ticket.GestureId };
        }
    }

    public bool TryBeginPointer(string endpointId,long instanceGeneration,int button,Point screenPoint,
        string localTargetId,out PointerGestureTicket ticket)
    {
        lock(_gate) {
            ticket=default;
            if(!PointerAvailable || _gesture==long.MaxValue || button<0 || !IsToken(endpointId) || string.IsNullOrEmpty(localTargetId) ||
                instanceGeneration<=0 || (endpointId==WorldEndpoint && !WorldPointerAvailable))return false;
            if(_pointerInstances.TryGetValue(endpointId,out long old) && instanceGeneration!=old) {
                if(instanceGeneration<old)return false;
                foreach(var claim in _pointers.Values.Where(c=>c.Ticket.EndpointId==endpointId).ToArray())
                    CancelPointer(claim.Ticket,"endpoint_recreated");
            }
            _pointerInstances[endpointId]=instanceGeneration;
            if(_buttons.ContainsKey(button))return false;
            ticket=new(endpointId,instanceGeneration,_geometry,_pointerEpoch,++_gesture,button);
            _pointers.Add(ticket.GestureId,new(ticket,localTargetId)); _buttons.Add(button,ticket.GestureId);
            return true;
        }
    }
    public bool ValidatePointerCommit(in PointerGestureTicket ticket,string localTargetId)
    {
        lock(_gate)return PointerAvailable && ticket.PointerEpoch==_pointerEpoch && _pointers.TryGetValue(ticket.GestureId,out var claim)
            && claim.Ticket==ticket && claim.Target==localTargetId && _pointerInstances[ticket.EndpointId]==ticket.InstanceGeneration
            && (ticket.EndpointId!=WorldEndpoint || (WorldPointerAvailable && ticket.GeometryVersion==_geometry));
    }
    internal bool DispatchWorldPointer(PointerGestureTicket? ticket,string target,Action post)
    {
        lock(_gate) {
            if(!PointerAvailable || !WorldPointerAvailable ||
                (ticket is {} t && (t.EndpointId!=WorldEndpoint || !ValidatePointerCommit(t,target))))return false;
            post();return true;
        }
    }
    // Queued mouse-up owns its original claim through native Post. A second
    // rapid click can have a separate claim before that first drain completes.
    internal void SealPointer(in PointerGestureTicket ticket)
    {
        lock(_gate)if(_buttons.TryGetValue(ticket.Button,out long id) && ticket.GestureId==id)_buttons.Remove(ticket.Button);
    }
    public void EndPointer(in PointerGestureTicket ticket,bool committed)
    {
        lock(_gate) {
            if(!_pointers.TryGetValue(ticket.GestureId,out var claim) || claim.Ticket!=ticket)return;
            SealPointer(ticket); _pointers.Remove(ticket.GestureId);
        }
    }
    public void CancelPointer(in PointerGestureTicket ticket,string reason)
    {
        lock(_gate) {
            if(!_pointers.TryGetValue(ticket.GestureId,out var claim) || claim.Ticket!=ticket)return;
            EndPointer(ticket,false); GestureInvalidated?.Invoke(ticket.GestureId);
        }
    }
    internal void ChangeWorldGeometry()
    {
        lock(_gate) {
            if(_geometry<long.MaxValue)++_geometry;
            foreach(var claim in _pointers.Values.Where(c=>c.Ticket.EndpointId==WorldEndpoint).ToArray())
                CancelPointer(claim.Ticket,"geometry_changed");
        }
    }
    internal void QueueWorldPointerCancel(uint nativeEpoch)
    {
        lock (_gate)
        {
            // The Game cancellation settles any registered Flash drag too.
            if (!_game || !_bound || !_connected || _pendingWorldCancel.HasValue ||
                _worldCancelSequence == int.MaxValue) return;
            int ticket = ++_worldCancelSequence;
            _pendingWorldCancel = (ticket, nativeEpoch);
            _worldCancelControl = new(_connection,
                FormattableString.Invariant($"I1|WorldPointerCancel|{CurrentSessionId}|{_connection}|{ticket}|{nativeEpoch}"));
            WakeWriter();
        }
    }

    private bool AcknowledgeWorldPointerCancel(string[] fields)
    {
        if (fields.Length != 7 || fields[6] != "1" || !Number(fields[4], out int ticket) ||
            !Number(fields[5], out int nativeEpoch) || _pendingWorldCancel != (ticket, (uint)nativeEpoch))
            return false;
        _pendingWorldCancel = null;
        return true;
    }

    private void ClearWorldPointerCancel()
    {
        _worldCancelControl = null;
        _pendingWorldCancel = null;
        _worldCancelSequence = 0;
    }
    private void InvalidatePointers()
    {
        if(_pointerEpoch<long.MaxValue)++_pointerEpoch;
        foreach(var claim in _pointers.Values.ToArray())CancelPointer(claim.Ticket,"revoked");
    }
}
