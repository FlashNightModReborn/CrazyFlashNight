using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Threading;

namespace CF7Launcher.Guardian.InputOwnership;

[Flags]
internal enum InputParticipant { None=0, AS2=1, NativeBridge=2, V8=4 }

internal readonly record struct InputCancel(string Session, int Connection, string Channel, int Epoch,
    int Ticket, string Endpoint, int Incarnation)
{
    internal string Fields => $"{Session}|{Connection}|{Channel}|{Epoch}|{Ticket}|{Endpoint}|{Incarnation}";
}

internal readonly record struct InputWireRecord(int Connection, string Payload);

// UI, LL hook and socket callbacks all enter this lock. No socket write or V8
// invocation runs under it. A single output worker preserves order on the wire.
internal sealed partial class SessionInputAuthority : ITextInputAuthority, IUiPointerAuthority
{
    internal const int DataCapacity = 64;
    private readonly object _gate = new();
    private readonly PhysicalInputLedger _physical = new(Enumerable.Range(0,256),fullVkRange:true);
    private readonly bool[] _suppressed = new bool[256];
    private readonly uint[] _admitted = new uint[8];
    private sealed class PendingWire
    {
        internal InputWireRecord Record;
        internal int EdgeCount;
        internal string Edges;
    }
    private readonly Queue<PendingWire> _data = new();
    private PendingWire _edgeTail;
    private readonly Dictionary<string,long> _instances = new(StringComparer.Ordinal);
    private InputWireRecord? _bind, _cancelControl, _reply;
    private Func<int,string,bool> _send;
    private bool _writing, _connected, _bound, _foreground, _business, _game, _requested=true;
    private bool _sequenceExhausted, _transportFailed;
    private int _connection, _epoch, _ticket, _batch, _latched, _lastLatchedFrame, _lastComboFrame;
    private int _lastLatchedSystemFrame;
    private long _inputSerial, _instanceSerial, _exitSerial, _focusSerial;
    private long _bindSentAt;
    private ulong _leaseSerial;
    private long _nativeFocusSerial;
    private readonly Dictionary<string,long> _endpointFocusSerial=new(StringComparer.Ordinal);
    internal long NextLocalFocusSerial()
    {
        lock(_gate) {
            if(_nativeFocusSerial==long.MaxValue)ExhaustSequence();
            return _sequenceExhausted ? 0 : ++_nativeFocusSerial;
        }
    }
    private TextInputLease? _text;
    private TextExitReceipt? _lastExit;
    private InputCancel? _pending, _inbound, _settledInbound;
    private InputParticipant _waiting;
    private bool _comboActive;
    // Begins a persistent native cancel and returns a poll bound to that bridge
    // instance and its issued ticket, including after a confirmed retirement.
    private Func<Func<bool>> _nativeCancel;
    private Func<bool> _nativeReceipt;
    internal event Action<InputCancel,string> V8Cancellation;
    internal InputCancel? LastAppliedCancel {get; private set;}
    internal int AppliedCancelCount {get; private set;}
    internal int V8ComboCount {get; private set;}
    internal PassiveFlashInputMode Mode {get;}
    public string CurrentSessionId {get;} = Guid.NewGuid().ToString("N");
    public long CurrentKeyboardEpoch {get {lock(_gate)return _epoch;}}
    public TextInputLease? CurrentTextLease {get {lock(_gate)return _text;}}
    public bool IsGameKeyboardAdmitted {get {lock(_gate)return _game;}}
    internal bool ForegroundEligible {get {lock(_gate)return _foreground;}}
    // Queued Host actions expire across a foreground loss or any intervening text lease.
    internal (long Generation, ulong Lease, int GameEpoch)? ShortcutStamp
    {
        get { lock (_gate) return _foreground && !_text.HasValue && !_sequenceExhausted
            ? (_physical.Prefix.Generation, _leaseSerial, _epoch) : null; }
    }
    internal int ConnectionIncarnation {get {lock(_gate)return _connection;}}
    internal long ObservationGeneration {get {lock(_gate)return _physical.Prefix.Generation;}}
    internal int PendingDataAtCancel {get; private set;}
    internal int PendingData {get {lock(_gate)return _data.Count;}}
    internal int LastLatchedFrameSeq {get {lock(_gate)return _lastLatchedFrame;}}
    internal bool Bound {get {lock(_gate)return _bound;}}
    internal bool IsPhysicallyDown(int vk) {lock(_gate)return _physical[vk]==ObservedKeyState.Down;}
    internal bool IsSuppressed(int vk) {lock(_gate)return (uint)vk<256 && _suppressed[vk];}
    internal int[] SuppressedVks {get {lock(_gate)return Enumerable.Range(0,256).Where(v=>_suppressed[v]).ToArray();}}
    internal string AdmittedHex {get {lock(_gate)return string.Concat(_admitted.Select(w=>w.ToString("X8",CultureInfo.InvariantCulture)));}}

    internal static void ValidateArgs(ref string[] args, string passiveEnv = null, string legacyEnv = null)
    {
        ArgumentNullException.ThrowIfNull(args);
        if (legacyEnv is not (null or "" or "0"))
            throw new ArgumentException("CF7_LEGACY_ACTIVE_FLASH_INPUT cannot enable active Flash input.");
        if (passiveEnv is not (null or "" or "disabled"))
            throw new ArgumentException("CF7_R1_PASSIVE_INPUT must be disabled.");

        const string passiveFlag = "--r1-passive-input";
        int option = -1;
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (arg == null) throw new ArgumentException("Missing command-line argument.");
            if (arg == passiveFlag)
            {
                if (option >= 0 || i + 1 >= args.Length || args[i + 1] != "disabled")
                    throw new ArgumentException("Expected a single --r1-passive-input disabled.");
                option = i++;
            }
            else if (arg.StartsWith("--r1-", StringComparison.OrdinalIgnoreCase)
                || arg.StartsWith("--legacy-active-flash-input", StringComparison.OrdinalIgnoreCase)
                || arg.StartsWith("--unified-input-candidate", StringComparison.OrdinalIgnoreCase)
                || arg.StartsWith("--hotkey-guard", StringComparison.OrdinalIgnoreCase)
                || arg.StartsWith("--diag-input", StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException("Unsupported Flash input option.");
            }
        }
        if (option >= 0) args = args.Take(option).Concat(args.Skip(option + 2)).ToArray();
    }

    internal SessionInputAuthority(PassiveFlashInputMode mode = PassiveFlashInputMode.Disabled)
    {
        if(mode!=PassiveFlashInputMode.Disabled)
            throw new ArgumentOutOfRangeException(nameof(mode));
        Mode=mode;
    }

    internal void AttachWriter(Func<int,string,bool> send) {lock(_gate){_send=send; WakeWriter();}}
    internal void AttachNative(Func<Func<bool>> beginCancel) {lock(_gate)_nativeCancel=beginCancel;}
    internal void Connect(int generation)
    {
        lock(_gate) {
            if(generation<=_connection)return;
            if(_connected)Disconnect(_connection);
            _connection=generation; _ticket=_lastLatchedFrame=_lastLatchedSystemFrame=0;
            _connected=true; _bound=_transportFailed=false; _settledInbound=null;
            QueueBind();
        }
    }
    private void QueueBind()
    {
        _bindSentAt=Environment.TickCount64;
        _bind=new(_connection,$"I1|Bind|{CurrentSessionId}|{_connection}|15|1|64");
        WakeWriter();
    }
    internal void Disconnect(int generation)
    {
        lock(_gate) {
            if(!_connected || generation!=_connection)return;
            _connected=_bound=false;
            if(!_game)InvalidatePointers();
            Revoke("disconnect");
            _bind=_cancelControl=_reply=null; _data.Clear(); _edgeTail=null; _text=null; _lastExit=null;
            ClearWorldPointerCancel();
            _requested=true;
            // Only this socket participant was definitely torn down.
            if(_pending is {} ticket && ticket.Connection==generation)Acknowledge(ticket,InputParticipant.AS2);
        }
    }
    internal void ObserveSourceLost(string reason)
    {
        lock(_gate) {
            _foreground=false;
            SuppressHeld();
            _physical.Invalidate(reason);
            if(!_game)InvalidatePointers();
            Revoke(reason);
        }
    }
    internal void SetForeground(bool eligible, Func<int,bool> held=null,Func<bool> stillEligible=null)
    {
        lock(_gate) {
            if(_foreground==eligible)return;
            if(!eligible) {
                ObserveSourceLost("foreground_lost");
                return;
            }
            // A key already down on return is never a fresh business Down.
            // Reconcile both reads at the same serialized observation prefix.
            var fence=_physical.Prefix;
            if(held==null && fence!=new ObservationPrefix(1,0))return;
            if(!_physical.ConfirmSources(fence))return;
            Dictionary<int,bool> sample() {
                var keys=Enumerable.Range(0,256).ToDictionary(v=>v,v=>held?.Invoke(v)==true);
                for(int generic=16,left=0xA0;generic<=18;generic++,left+=2)
                    keys[generic]|=keys[left] || keys[left+1];
                return keys;
            }
            try {
                var before=sample();
                var after=sample();
                if(!_physical.TryReconcile(fence,before,after,stillEligible?.Invoke()??true,true))return;
            } catch(Exception) {
                ObserveSourceLost("snapshot_unavailable");return;
            }
            _foreground=true;
            SuppressHeld();
            GrantIfReady();
        }
    }
    internal void SetBusinessEligible(bool eligible, string reason)
    {
        lock(_gate) {
            if(_business==eligible)return;
            _business=eligible;
            if(!eligible)Revoke(reason);
            else GrantIfReady();
        }
    }
    private void GrantIfReady()
    {
        if(_game || _sequenceExhausted || _transportFailed || !_bound || !_connected || !_foreground || !_business || !_requested ||
            _text.HasValue || _pending.HasValue || !_physical.HasQualifiedBaseline)return;
        if(_epoch==int.MaxValue || _ticket==int.MaxValue || !HasWireObservationRoom()) {
            ExhaustSequence();return;
        }
        ++_epoch;
        // Reserve the cancellation identity before opening the gate, including
        // the final representable grant. The peer can issue a later fresh ticket.
        _ticket=Math.Max(_epoch,_ticket+1);
        _game=true;
        _batch=_latched=_lastComboFrame=_commandSeq=0;
        EnqueueBatch("-");
    }
    private bool HasWireObservationRoom(int count=0)
    {
        var prefix=_physical.Prefix;
        return prefix.Generation<int.MaxValue && prefix.Sequence<int.MaxValue-count;
    }
    private void ExhaustSequence()
    {
        if(_sequenceExhausted)return;
        _sequenceExhausted=true;
        if(!_game)InvalidatePointers();
        Revoke("sequence_exhausted");
    }
    private void SuppressHeld()
    {
        for(int v=0;v<256;v++)if(_physical[v]==ObservedKeyState.Down)_suppressed[v]=true;
    }
    private static int GenericModifier(int vk) => vk switch {
        0xA0 or 0xA1=>16, 0xA2 or 0xA3=>17, 0xA4 or 0xA5=>18, _=>0 };
    internal bool ObserveKey(int vk,bool down, bool allowBusiness=true, long inputSerial=0,
        InputObservationSource source=InputObservationSource.Unmarked,long? deviceId=null)
    {
        lock(_gate) {
            if((uint)vk>255 || !_foreground || _sequenceExhausted || (inputSerial!=0 && inputSerial<=_inputSerial))return false;
            int generic=GenericModifier(vk);
            if(inputSerial==long.MaxValue || !HasWireObservationRoom(generic==0 ? 1 : 2)) {
                ExhaustSequence();return false;
            }
            if(!_physical.HasQualifiedBaseline) {ObserveSourceLost("baseline_unknown");return false;}
            if(inputSerial!=0)_inputSerial=inputSerial;
            string edge=ProjectObservation(_physical.Observe(_physical.Prefix.Generation,vk,down,source,deviceId),allowBusiness);
            if(generic!=0) {
                string modifier=ProjectObservation(_physical.ObserveModifierAlias(generic,source),allowBusiness);
                if(modifier!=null)edge=edge==null ? modifier : edge+";"+modifier;
            }
            return edge!=null && EnqueueBatch(edge);
        }
    }
    // Outside the session only finish an already-suppressed key. Other
    // foreground applications' keys never enter this session's ledger.
    internal void ObserveSuppressedRelease(int vk,InputObservationSource source,long? deviceId=null)
    {
        lock(_gate) {
            if((uint)vk>255 || !_suppressed[vk] || _sequenceExhausted)return;
            int generic=GenericModifier(vk);
            if(!HasWireObservationRoom(generic==0 ? 1 : 2)) {ExhaustSequence();return;}
            var release=_physical.Observe(_physical.Prefix.Generation,vk,false,source,deviceId);
            if(!_foreground && vk is >=16 and <=18) {
                int left=0xA0+2*(vk-16);
                if(_suppressed[left] || _suppressed[left+1])return;
            }
            if(release is {Down:false})_suppressed[vk]=false;
            if(generic!=0 && _suppressed[generic] && !_suppressed[vk] && !_suppressed[vk^1] &&
                _physical.ObserveModifierAlias(generic,source) is {Down:false})_suppressed[generic]=false;
        }
    }
    private string ProjectObservation(ObservedInputEdge? observation,bool allowBusiness)
    {
        if(observation is not {} observed)return null;
        int vk=observed.Key;
        bool down=observed.Down;
        if(_suppressed[vk]) { if(!down)_suppressed[vk]=false; return null; }
        if(down && (!_game || !allowBusiness)) {
            if((_admitted[vk>>5]&(1u<<(vk&31)))==0)_suppressed[vk]=true;
            return null;
        }
        if(!_game || observed.Duplicate)return null;
        int word=vk>>5;
        uint bit=1u<<(vk&31);
        if(((_admitted[word]&bit)!=0)==down)return null;
        if(down)_admitted[word]|=bit; else _admitted[word]&=~bit;
        return $"{observed.Prefix.Sequence},{vk},{(down?"D":"U")}";
    }
    private bool EnqueueBatch(string edges)
    {
        if(!_game)return false;
        if(_batch==int.MaxValue || !HasWireObservationRoom()) {
            ExhaustSequence();return false;
        }
        if(!_physical.HasQualifiedBaseline) {ObserveSourceLost("baseline_unknown");return false;}
        int added=edges=="-" ? 0 : 1+edges.Count(ch=>ch==';');
        bool extend=added!=0 && _edgeTail!=null && _edgeTail.EdgeCount+added<=64;
        if(!extend && (_data.Count>=DataCapacity || _batch-_latched>=DataCapacity)) {
            Revoke("data_exhausted");
            return false;
        }
        PendingWire batch;
        if(extend) {
            batch=_edgeTail;batch.EdgeCount+=added;batch.Edges+=";"+edges;
        } else {
            ++_batch;
            batch=new PendingWire{EdgeCount=added,Edges=edges};
            _data.Enqueue(batch);_edgeTail=added==0 ? null : batch;
        }
        var prefix=_physical.Prefix;
        batch.Record=new(_connection,$"I1|InputBatch|{CurrentSessionId}|{_connection}|{_epoch}|{_batch}|{prefix.Generation}|{prefix.Sequence}|{AdmittedHex}|{batch.EdgeCount}|{batch.Edges}");
        WakeWriter();return true;
    }
    internal bool Heartbeat()
    {
        lock(_gate) {
            if(_connected && !_bound && !_transportFailed && !_bind.HasValue && Environment.TickCount64-_bindSentAt>=1000)QueueBind();
            if(_pending is {} t && _nativeReceipt?.Invoke()==true)Acknowledge(t,InputParticipant.NativeBridge);
            return EnqueueBatch("-");
        }
    }
    internal InputCancel? Cancel(string reason)
    {
        lock(_gate)return Revoke(reason);
    }
    private InputCancel? Revoke(string reason, InputCancel? incoming=null)
    {
        SuppressHeld();
        if(_pending.HasValue)return _pending;
        if(!_game)return null;
        _game=false;
        Array.Clear(_admitted);
        var t=incoming ?? new InputCancel(CurrentSessionId,_connection,"Game",_epoch,_ticket,"AS2",_connection);
        _pending=t; LastAppliedCancel=t;
        if(AppliedCancelCount<int.MaxValue)++AppliedCancelCount;
        PendingDataAtCancel=_data.Count;
        var beginNative=_nativeCancel;
        var cancelV8=V8Cancellation;
        bool settleV8=_comboActive;
        _waiting=(_bound?InputParticipant.AS2:0) | (settleV8?InputParticipant.V8:0) |
            (beginNative!=null?InputParticipant.NativeBridge:0);
        _data.Clear(); _edgeTail=null; _pendingCombo=null;
        InvalidatePointers();
        if(_bound) {
            _cancelControl=new(_connection,"I1|Cancel|"+t.Fields+"|"+(IsToken(reason)?reason:"input_revoked"));
            WakeWriter();
        }
        if(beginNative!=null)_nativeReceipt=beginNative();
        if(settleV8 && cancelV8!=null)
            ThreadPool.QueueUserWorkItem(_=>cancelV8(t,reason));
        FinishIfSettled();
        return t;
    }
    internal bool IsWaiting(InputCancel ticket,InputParticipant participant)
    {
        lock(_gate)return _pending==ticket && (_waiting&participant)!=0;
    }
    internal bool Acknowledge(InputCancel ticket,InputParticipant participant)
    {
        lock(_gate) {
            if(_pending!=ticket || participant is not (InputParticipant.AS2 or InputParticipant.V8 or InputParticipant.NativeBridge)
                || (_waiting&participant)==0)return false;
            _waiting &= ~participant;
            if(participant==InputParticipant.NativeBridge)_nativeReceipt=null;
            if(participant==InputParticipant.V8)_comboActive=false;
            FinishIfSettled();return true;
        }
    }
    private void FinishIfSettled()
    {
        if(!_pending.HasValue || _waiting!=0)return;
        if(_inbound is {} inbound && _connected && inbound.Connection==_connection) {
            _settledInbound=inbound; Reply(inbound);
        }
        _pending=_inbound=null;
        GrantIfReady();
    }
    private void Reply(InputCancel ticket)
    {
        _reply=new(ticket.Connection,"I1|Cancelled|"+ticket.Fields+"|1|1");
        WakeWriter();
    }
    internal bool Receive(int generation,string packet)
    {
        if(!WireText(packet))return false;
        string[] f=packet.Split('|');
        lock(_gate) {
            if(!_connected || generation!=_connection || f.Length<4 || f[0]!="I1" || f[2]!=CurrentSessionId ||
                !Number(f[3],out int c) || c!=generation)return false;
            if(f[1]=="Capability") {
                if(_bound || _transportFailed || f.Length!=7 || f[4]!="15" || f[5]!="1" || f[6]!="64")return false;
                _bind=null;_bound=true;GrantIfReady();return true;
            }
            if(!_bound)return false;
            if (f[1] == "WorldPointerCancelled") return AcknowledgeWorldPointerCancel(f);
            if(f[1]=="Latch")
            {
                // ServerManager coalesces staged batches and sends at most one
                // Latch per system frame, after incrementing inputFrameSeq.
                if(f.Length!=8 || !Number(f[4],out int e) || !_game || e!=_epoch || !Number(f[5],out int batch)
                    || batch<=_latched || batch>_batch || !Number(f[6],out int systemFrame) || systemFrame<=_lastLatchedSystemFrame || !Number(f[7],out int frame)
                    || frame<=_lastLatchedFrame)return false;
                _latched=batch; _lastLatchedSystemFrame=systemFrame; _lastLatchedFrame=frame;
                if(frame==int.MaxValue || systemFrame==int.MaxValue)ExhaustSequence();
                return true;
            }
            if(f.Length<10 || f[4]!="Game" || f[7]!="AS2" || !Number(f[5],out int epoch) ||
                !Number(f[6],out int id) || !Number(f[8],out int inc) || inc!=c)return false;
            var ticket=new InputCancel(f[2],c,f[4],epoch,id,f[7],inc);
            if(f[1]=="Cancelled")return f.Length==11 && f[9]=="1" && f[10]=="1" && Acknowledge(ticket,InputParticipant.AS2);
            if(f[1]!="Cancel" || f.Length!=10 || !IsToken(f[9]))return false;
            if(ticket==_settledInbound) {Reply(ticket);return true;}
            if(epoch!=_epoch || id<_ticket)return false;
            if(_pending.HasValue) {
                // Simultaneous local and peer cancellation shares one identity.
                // A repeated request cannot settle any participant's obligation.
                if(ticket!=_pending || _inbound.HasValue)return false;
                _inbound=ticket;return true;
            }
            if(!_game)return false;
            _ticket=id;_inbound=ticket;Revoke(f[9],ticket);return true;
        }
    }
    internal static bool Number(string s,out int value,int min=1,int max=int.MaxValue)
    {
        value=0;
        return s is {Length:>0 and <=10} && (s.Length==1 || s[0]!='0') && s.AsSpan().IndexOfAnyExceptInRange('0','9')<0 &&
            int.TryParse(s,NumberStyles.None,CultureInfo.InvariantCulture,out value) && value>=min && value<=max;
    }
    internal static bool WireText(string value) => value is {Length:>0 and <=4096} && value.All(c=>c>=' ' && c<='~');
    internal static bool IsToken(string value) => value is {Length:>0 and <=96} &&
        value.All(c=>char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-');
    internal bool TryTakeOutput(out InputWireRecord item,bool controlOnly=false)
    {
        lock(_gate) {
            // Bind precedes data on a new connection. Cancel has its own slot
            // even if a data write on the previous grant is still in flight.
            if(_bind is {} bind){_bind=null;item=bind;return true;}
            if(_cancelControl is {} cancel){_cancelControl=null;item=cancel;return true;}
            if(_worldCancelControl is {} worldCancel){_worldCancelControl=null;item=worldCancel;return true;}
            if(_reply is {} reply){_reply=null;item=reply;return true;}
            if(!controlOnly && _data.TryDequeue(out var data)) {
                if(ReferenceEquals(_edgeTail,data))_edgeTail=null;
                item=data.Record;return true;
            }
            item=default;return false;
        }
    }
    private void WakeWriter()
    {
        if(_send==null || _writing)return;
        _writing=true;
        ThreadPool.QueueUserWorkItem(_=> {
            while(true) {
                InputWireRecord record;
                lock(_gate) {
                    if(!TryTakeOutput(out record)){_writing=false;return;}
                }
                bool written;
                try {written=_send(record.Connection,record.Payload);}
                catch(Exception) {written=false;}
                if(!written) {
                    lock(_gate) {
                        if(_connection==record.Connection && _connected) {
                            // A failed write is not teardown. Keep its semantic
                            // receipt outstanding until the actual disconnect.
                            _transportFailed=true;
                            if(!_game && !_pending.HasValue)InvalidatePointers();
                            Revoke("transport_write");
                        }
                    }
                }
            }
        });
    }

    internal (bool QueueWasFull, InputCancel? Ticket, bool OldPointerRejected, bool EarlyGrantRejected) RunQueueCancelChallengeForProbe()
    {
        lock(_gate) {
            if(!_game || !_bound || !_connected || !_foreground)return default;
            long worldInc=_pointerInstances.TryGetValue(WorldEndpoint,out long cur) && cur>0 ? cur : NextInstanceGeneration(WorldEndpoint);
            if(!TryBeginPointer(WorldEndpoint,worldInc,1,new Point(32,32),"probe_world",out var oldTicket))
                return default;
            while(_data.Count<DataCapacity && _batch<int.MaxValue-1) {
                ++_batch;
                var prefix=_physical.Prefix;
                _data.Enqueue(new PendingWire{EdgeCount=0,Edges="-",
                    Record=new(_connection,$"I1|InputBatch|{CurrentSessionId}|{_connection}|{_epoch}|{_batch}|{prefix.Generation}|{prefix.Sequence}|{AdmittedHex}|0|-")});
            }
            _edgeTail=null;
            bool wasFull=_data.Count>=DataCapacity;
            var ticket=Revoke("r1_p05_queue_cancel");
            bool oldRejected=!ValidatePointerCommit(oldTicket,"probe_world");
            GrantIfReady();
            bool earlyRejected=!_game && _pending.HasValue;
            return (wasFull,ticket,oldRejected,earlyRejected);
        }
    }

    internal object ProbeSnapshot()
    {
        lock(_gate)return new {
            sessionId=CurrentSessionId, connectionIncarnation=_connection, observationGeneration=_physical.Prefix.Generation,
            keyboardEpoch=_epoch, pointerEpoch=_pointerEpoch, geometryVersion=_geometry,
            currentTextLease=_text is {} l ? new {endpointId=l.EndpointId,incarnation=l.InstanceGeneration,leaseId=l.LeaseId} : null,
            admittedHex=AdmittedHex, suppressedVks=SuppressedVks, physicalDownVks=Enumerable.Range(0,256).Where(IsPhysicallyDown).ToArray(),
            i1Bound=_bound,lastLatchedFrameSeq=_lastLatchedFrame,v8ComboCount=V8ComboCount,
            foregroundEligible=_foreground,businessEligible=_business,gameKeyboardAdmitted=_game,cancelTicket=_pending?.Ticket,
            waitingParticipants=_waiting.ToString()
        };
    }
    internal bool RegisterObservedInstance(string endpoint,long incarnation)
    {
        lock(_gate) {
            if(_sequenceExhausted || !IsToken(endpoint) || incarnation<=0 ||
                (_instances.TryGetValue(endpoint,out long old) && incarnation<old))return false;
            if(old!=incarnation)_endpointFocusSerial.Remove(endpoint);
            _instances[endpoint]=incarnation; _instanceSerial=Math.Max(_instanceSerial,incarnation);return true;
        }
    }
    public long NextInstanceGeneration(string endpointId)
    {
        if(!IsToken(endpointId))throw new ArgumentException("Invalid input endpoint",nameof(endpointId));
        lock(_gate) {
            if(_instanceSerial==long.MaxValue)ExhaustSequence();
            if(_sequenceExhausted)return 0;
            _endpointFocusSerial.Remove(endpointId);
            return _instances[endpointId]=++_instanceSerial;
        }
    }
    public TextInputLease? AcquireText(string endpointId,long instanceGeneration,in TextFocusObservation focus)
    {
        lock(_gate) {
            if(_sequenceExhausted || focus.SessionId!=CurrentSessionId || !focus.LocalFocusConfirmed || focus.FocusSerial<=0 ||
                focus.EditorHwnd==IntPtr.Zero || focus.RootHwnd==IntPtr.Zero || !IsToken(endpointId) ||
                !_instances.TryGetValue(endpointId,out long inc) || inc!=instanceGeneration ||
                (_endpointFocusSerial.TryGetValue(endpointId,out long seen) && focus.FocusSerial<=seen))return null;
            if(_leaseSerial==ulong.MaxValue) {ExhaustSequence();return null;}
            _text=new TextInputLease(endpointId,inc,++_leaseSerial);
            _endpointFocusSerial[endpointId]=_focusSerial=focus.FocusSerial; _lastExit=null; _requested=false;
            Revoke("text_acquired");
            return _text;
        }
    }
    internal Action CaptureEditorLeave(TextInputLease lease,Func<TextExitObservation> observe)
    {
        return ()=>RequestGameKeyboard(ReleaseText(lease,observe()));
    }
    public TextExitReceipt ReleaseText(in TextInputLease lease,in TextExitObservation exit)
    {
        lock(_gate) {
            if(_text!=lease || exit.SessionId!=CurrentSessionId || !exit.EditorFocusCleared || exit.FocusSerial<_focusSerial)
                return new(TextExitStatus.Stale,CurrentSessionId,lease,_epoch,_exitSerial);
            if(_exitSerial==long.MaxValue) {
                ExhaustSequence();
                return new(TextExitStatus.Stale,CurrentSessionId,lease,_epoch,_exitSerial);
            }
            SuppressHeld(); _text=null; _endpointFocusSerial[lease.EndpointId]=exit.FocusSerial;
            var receipt=new TextExitReceipt(TextExitStatus.Released,CurrentSessionId,lease,_epoch,++_exitSerial);
            _lastExit=receipt; return receipt;
        }
    }
    public bool RequestGameKeyboard(in TextExitReceipt receipt)
    {
        lock(_gate) {
            if(!_lastExit.HasValue || _lastExit.Value!=receipt || _text.HasValue)return false;
            _lastExit=null; _requested=true; GrantIfReady();return _game;
        }
    }

    // The front door retires its document with requestGame:false. Only the
    // actual reveal can consume that receipt, including a late exact blur.
    internal void RequestGameAfterBootstrapReveal()
    {
        lock (_gate)
            if (_lastExit is { } receipt && receipt.Lease.EndpointId.StartsWith("bootstrap.frontdoor.", StringComparison.Ordinal))
                RequestGameKeyboard(receipt);
    }
}
