using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;
using CF7Launcher.V8;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class ProposedR1AdversarialTests
{
    [Theory]
    [InlineData("Modifier", "Interject")]
    [InlineData("Modifier", "InterjectConfig")]
    [InlineData("Interject", "Modifier")]
    [InlineData("Interject", "InterjectConfig")]
    [InlineData("InterjectConfig", "Modifier")]
    [InlineData("InterjectConfig", "Interject")]
    [InlineData("Modifier", "Modifier")]
    public void R1_LateTextLeaveCannotReleaseSuccessor(string oldEndpoint, string nextEndpoint)
    {
        using var sut = ProposedAdversarialBindings.Create<IR1Text>();
        var old = sut.EnterText(oldEndpoint, 5);
        Action lateLeave = sut.QueueLeaveFromActualEndpoint(old);
        var current = sut.EnterText(nextEndpoint, 6);
        Assert.NotEqual(old, current);
        Assert.Equal<TextLeaseIdentity?>(current, sut.CurrentTextLease);
        Assert.False(sut.GameKeyboardAllowed);
        lateLeave();
        lateLeave();
        Assert.Equal<TextLeaseIdentity?>(current, sut.CurrentTextLease);
        Assert.False(sut.GameKeyboardAllowed);
        Assert.Equal(0, sut.GameTailKeyCount);
        sut.QueueLeaveFromActualEndpoint(current)();
        Assert.Null(sut.CurrentTextLease);
        Assert.True(sut.GameKeyboardAllowed);
        Assert.Equal(0, sut.GameTailKeyCount);
    }

    [Fact]
    public void R1_CancelAndRealUpKeepPhysicalLedgerSeparateFromBusinessRelease()
    {
        using var sut = ProposedAdversarialBindings.Create<IR1Keyboard>();
        const int vk = 0x44;
        sut.Observe(vk, down: true, sequence: 11);
        Assert.Equal(new[] { BusinessEdge.Press }, sut.TakeBusinessEdges());
        sut.CancelAndSettle();
        Assert.True(sut.IsPhysicallyDown(vk));
        Assert.True(sut.IsSuppressed(vk));
        Assert.Empty(sut.TakeBusinessEdges());

        sut.GrantNewEpoch();
        sut.Observe(vk, down: true, sequence: 12); // observed repeat
        Assert.True(sut.IsPhysicallyDown(vk));
        Assert.Empty(sut.TakeBusinessEdges());
        sut.Observe(vk, down: false, sequence: 13);
        Assert.False(sut.IsPhysicallyDown(vk));
        Assert.False(sut.IsSuppressed(vk));
        Assert.Empty(sut.TakeBusinessEdges());
        sut.Observe(vk, down: true, sequence: 14);
        sut.Observe(vk, down: false, sequence: 15);
        Assert.Equal(new[] { BusinessEdge.Press, BusinessEdge.Release }, sut.TakeBusinessEdges());
    }

    [Fact]
    public void R1_DataQueueExhaustionStillAppliesControlAndWaitsForEverySemanticAck()
    {
        using var sut = ProposedAdversarialBindings.Create<IR1Transport>();
        sut.GrantAndQueueDeferredBusiness();
        sut.HoldDataDrain();
        for (int i = 0; i < sut.DataCapacity; i++) Assert.True(sut.TryQueueNextData());
        Assert.False(sut.TryQueueNextData());
        var cancelled = sut.RequestCancelWithSuccessorWaiting();
        sut.PumpControlWithoutPumpingData();
        Assert.Equal(sut.DataCapacity, sut.PendingDataBeforeControl);
        Assert.Equal<CancelIdentity?>(cancelled, sut.LastAppliedCancel);
        Assert.False(sut.OldGateOpen);
        Assert.False(sut.SuccessorGranted);
        sut.NativeTransportAck(cancelled);
        Assert.False(sut.SuccessorGranted);
        sut.RunOldDeferredWork();
        Assert.Equal(0, sut.OldBusinessCommits);
        sut.SemanticAck(cancelled, "AS2");
        Assert.False(sut.SuccessorGranted);
        sut.SemanticAck(cancelled, "V8");
        Assert.True(sut.SuccessorGranted);
        Assert.Equal(0, sut.OldBusinessCommits);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void R1_OldCancelArrivingAfterNewGrantDoesNotMutateCurrentGrant(bool fromPriorConnection)
    {
        using var sut = ProposedAdversarialBindings.Create<IR1Transport>();
        sut.GrantAndQueueDeferredBusiness();
        var old = sut.SettleAndGrantSuccessor();
        if (fromPriorConnection) sut.RebindAndGrant();
        var current = sut.CurrentGrant;
        sut.DownInCurrentEpoch();
        int applied = sut.AppliedCancelCount;

        sut.DeliverCancelToRealEndpoints(old);
        sut.DeliverCancelToRealEndpoints(old);
        Assert.Equal(applied, sut.AppliedCancelCount);
        Assert.Equal(current, sut.CurrentGrant);
        Assert.True(sut.SuccessorGranted);
        Assert.True(sut.CurrentDownStillAdmitted);
        sut.UpInCurrentEpoch();
        Assert.Equal(1, sut.CurrentReleaseCount);
        Assert.Equal(0, sut.OldBusinessCommits);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void R1_OldClickIsNeverRetargetedByNewGeometry(bool downAlreadyReachedOriginal)
    {
        using var sut = ProposedAdversarialBindings.Create<IR1Pointer>();
        long keyboardEpoch = sut.KeyboardEpoch;
        sut.Map(version: 10, sourceIncarnation: 2, target: "A");
        var old = sut.QueueDownAtSharedScreenPoint();
        if (downAlreadyReachedOriginal) sut.DeliverQueuedDown();
        sut.Map(version: 11, sourceIncarnation: 2, target: "B");
        sut.Flush();
        sut.UpAtSharedScreenPoint();
        sut.Flush();
        Assert.Equal(0, sut.OriginalDowns("B"));
        Assert.Equal(0, sut.OriginalReleases("A"));
        Assert.Equal(0, sut.OriginalReleases("B"));
        Assert.Equal(0, sut.BusinessClicks("A"));
        Assert.Equal(0, sut.BusinessClicks("B"));
        Assert.Equal(downAlreadyReachedOriginal ? 1 : 0, sut.OriginalDowns("A"));
        Assert.Contains(old, sut.InvalidatedGestures);
        Assert.Equal(keyboardEpoch, sut.KeyboardEpoch);

        var control = sut.TakeWorldCancel();
        if (downAlreadyReachedOriginal)
        {
            var cancel = Assert.IsType<InputWireRecord>(control);
            sut.HoverAtSharedScreenPoint();
            Assert.Null(sut.HoverTarget);

            void AssertFreshClickStillBlocked()
            {
                Assert.Equal(old, sut.QueueDownAtSharedScreenPoint());
                sut.DeliverQueuedDown();
                sut.UpAtSharedScreenPoint();
                sut.Flush();
                Assert.Equal(0, sut.OriginalDowns("B"));
                Assert.Equal(0, sut.OriginalReleases("B"));
                Assert.Equal(0, sut.BusinessClicks("B"));
                Assert.Equal(keyboardEpoch, sut.KeyboardEpoch);
            }

            AssertFreshClickStillBlocked();
            Assert.False(sut.ReplyWorldCancel(cancel, matchingEpoch: false));
            AssertFreshClickStillBlocked();
            Assert.True(sut.ReplyWorldCancel(cancel, matchingEpoch: true));
        }
        else
        {
            Assert.Null(control);
        }

        sut.HoverAtSharedScreenPoint();
        Assert.Equal("B", sut.HoverTarget);
        sut.QueueDownAtSharedScreenPoint();
        sut.DeliverQueuedDown();
        sut.UpAtSharedScreenPoint();
        sut.Flush();
        Assert.Equal(1, sut.OriginalDowns("B"));
        Assert.Equal(1, sut.OriginalReleases("B"));
        Assert.Equal(1, sut.BusinessClicks("B"));
    }
}

// Test adapters expose observed facts. Do not implement input policy here.
// A missing adapter produces a named binding failure so zero checks cannot go green.
internal static partial class ProposedAdversarialBindings
{
    internal static T Create<T>() where T : class, IDisposable
    {
        object instance = null;
        Bind(typeof(T), ref instance);
        Assert.True(instance is T, "BLOCKED_BINDING: bind the candidate production path for " + typeof(T).Name);
        return (T)instance;
    }

    static partial void Bind(Type contract, ref object instance);
}

internal readonly record struct TextLeaseIdentity(string Endpoint, long Incarnation, long LeaseId);
internal interface IR1Text : IDisposable
{
    TextLeaseIdentity EnterText(string endpoint, long incarnation);
    Action QueueLeaveFromActualEndpoint(TextLeaseIdentity lease);
    TextLeaseIdentity? CurrentTextLease { get; }
    bool GameKeyboardAllowed { get; }
    int GameTailKeyCount { get; }
}

internal enum BusinessEdge { Press, Release }
internal interface IR1Keyboard : IDisposable
{
    void Observe(int key, bool down, long sequence);
    void CancelAndSettle();
    void GrantNewEpoch();
    bool IsPhysicallyDown(int key);
    bool IsSuppressed(int key);
    IReadOnlyList<BusinessEdge> TakeBusinessEdges();
}

internal readonly record struct CancelIdentity(string Session, long Connection, string Channel,
    long Epoch, long Ticket, string Endpoint, long Incarnation);
internal interface IR1Transport : IDisposable
{
    int DataCapacity { get; }
    int PendingDataBeforeControl { get; }
    CancelIdentity? LastAppliedCancel { get; }
    bool OldGateOpen { get; }
    bool SuccessorGranted { get; }
    long CurrentGrant { get; }
    int AppliedCancelCount { get; }
    int OldBusinessCommits { get; }
    bool CurrentDownStillAdmitted { get; }
    int CurrentReleaseCount { get; }
    void GrantAndQueueDeferredBusiness();
    void HoldDataDrain();
    bool TryQueueNextData();
    CancelIdentity RequestCancelWithSuccessorWaiting();
    void PumpControlWithoutPumpingData();
    void NativeTransportAck(CancelIdentity cancel);
    void SemanticAck(CancelIdentity cancel, string scope);
    void RunOldDeferredWork();
    CancelIdentity SettleAndGrantSuccessor();
    void RebindAndGrant();
    void DownInCurrentEpoch();
    void UpInCurrentEpoch();
    void DeliverCancelToRealEndpoints(CancelIdentity cancel);
}

internal interface IR1Pointer : IDisposable
{
    long KeyboardEpoch { get; }
    string HoverTarget { get; }
    IReadOnlyList<long> InvalidatedGestures { get; }
    void Map(long version, long sourceIncarnation, string target);
    long QueueDownAtSharedScreenPoint();
    void DeliverQueuedDown();
    void UpAtSharedScreenPoint();
    void HoverAtSharedScreenPoint();
    InputWireRecord? TakeWorldCancel();
    bool ReplyWorldCancel(InputWireRecord control, bool matchingEpoch);
    void Flush();
    int OriginalDowns(string target);
    int OriginalReleases(string target);
    int BusinessClicks(string target);
}

internal static partial class ProposedAdversarialBindings
{
    static partial void Bind(Type contract,ref object instance)
    {
        instance=contract==typeof(IR1Pointer) ? new PointerBinding() : new InputBinding();
    }

    // Only the wire peer and physical source are driven here. All grants,
    // queue limits, cutoffs, receipts and commits go through production code.
    private class InputBinding : IR1Text,IR1Keyboard,IR1Transport
    {
        protected readonly SessionInputAuthority Input=new(PassiveFlashInputMode.Disabled);
        private long _focusSerial;
        private int _frame;
        private VersionedComboFrame _deferred;
        private bool _nativeReturned;
        private readonly List<BusinessEdge> _observed=new();
        internal InputBinding()
        {
            Input.SetForeground(true); Input.SetBusinessEligible(true,"fixture_ready"); Bind(1);
        }
        private void Bind(int c)
        {
            Input.Connect(c);
            Assert.True(Input.TryTakeOutput(out var hello));
            Assert.Equal($"I1|Bind|{Input.CurrentSessionId}|{c}|15|1|64",hello.Payload);
            Assert.True(Input.Receive(c,hello.Payload.Replace("|Bind|","|Capability|")));
            DrainData();
        }
        private void DrainData()
        {
            while(Input.TryTakeOutput(out var r)) {
                var f=r.Payload.Split('|');
                Assert.Equal("InputBatch",f[1]);
                foreach(string e in f[10].Split(';').Where(e=>e!="-"))
                    _observed.Add(e.EndsWith(",D") ? BusinessEdge.Press : BusinessEdge.Release);
                ++_frame;
                Assert.True(Input.Receive(r.Connection,$"I1|Latch|{f[2]}|{f[3]}|{f[4]}|{f[5]}|{_frame}|{_frame}"));
            }
        }
        public void Observe(int key,bool down,long sequence)=>Input.ObserveKey(key,down,inputSerial:sequence);
        public bool IsPhysicallyDown(int key)=>Input.IsPhysicallyDown(key);
        public bool IsSuppressed(int key)=>Input.IsSuppressed(key);
        public IReadOnlyList<BusinessEdge> TakeBusinessEdges()
        {
            DrainData();var edges=_observed.ToArray();_observed.Clear();return edges;
        }
        public void CancelAndSettle()
        {
            Input.SetBusinessEligible(false,"fixture_suspend");
            PumpControlWithoutPumpingData(); SemanticAck(LastAppliedCancel.Value,"AS2");
        }
        public void GrantNewEpoch()=>Input.SetBusinessEligible(true,"fixture_resume");
        public TextLeaseIdentity EnterText(string endpoint,long incarnation)
        {
            Assert.True(Input.RegisterObservedInstance(endpoint,incarnation));
            var lease=Input.AcquireText(endpoint,incarnation,new(Input.CurrentSessionId,(IntPtr)1,(IntPtr)2,++_focusSerial,true)).Value;
            if(Input.LastAppliedCancel is {} c && Input.IsWaiting(c,InputParticipant.AS2)) {
                PumpControlWithoutPumpingData();SemanticAck(LastAppliedCancel.Value,"AS2");
            }
            return new(lease.EndpointId,lease.InstanceGeneration,(long)lease.LeaseId);
        }
        public Action QueueLeaveFromActualEndpoint(TextLeaseIdentity lease)=>Input.CaptureEditorLeave(
            new(lease.Endpoint,lease.Incarnation,(ulong)lease.LeaseId),()=>new(Input.CurrentSessionId,++_focusSerial,"focus_left",true));
        public TextLeaseIdentity? CurrentTextLease=>Input.CurrentTextLease is {} l ?
            new(l.EndpointId,l.InstanceGeneration,(long)l.LeaseId) : null;
        public bool GameKeyboardAllowed=>Input.IsGameKeyboardAdmitted;
        public int GameTailKeyCount {get {DrainData();return _observed.Count;}}
        public int DataCapacity=>SessionInputAuthority.DataCapacity;
        public int PendingDataBeforeControl=>Input.PendingDataAtCancel;
        public CancelIdentity? LastAppliedCancel {get;private set;}
        public bool OldGateOpen=>Input.Admits(_deferred.Session,_deferred.Connection,_deferred.Epoch);
        public bool SuccessorGranted=>Input.IsGameKeyboardAdmitted && Input.CurrentKeyboardEpoch!=_deferred.Epoch;
        public long CurrentGrant=>Input.CurrentKeyboardEpoch;
        public int AppliedCancelCount=>Input.AppliedCancelCount;
        public int OldBusinessCommits{get;private set;}
        public bool CurrentDownStillAdmitted=>(Convert.ToUInt32(Input.AdmittedHex.Substring(16,8),16)&16)!=0;
        public int CurrentReleaseCount=>TakeBusinessEdges().Count(e=>e==BusinessEdge.Release);
        public void GrantAndQueueDeferredBusiness()
        {
            Input.AttachNative(()=>()=>_nativeReturned);
            string payload=$"I1|{Input.CurrentSessionId}|{Input.ConnectionIncarnation}|{CurrentGrant}|1|1|0|1|1|0|1|0|0|-";
            Assert.True(VersionedComboFrame.TryParse(payload,out _deferred));
            Assert.True(Input.BeginCombo(_deferred,Input.ConnectionIncarnation));
        }
        public void RunOldDeferredWork()
        {
            if(Input.CompleteCombo(_deferred,"1|1|old||[]"))OldBusinessCommits++;
        }
        public void HoldDataDrain()=>Assert.Equal(0,Input.PendingData);
        public bool TryQueueNextData()=>Input.Heartbeat();
        public CancelIdentity RequestCancelWithSuccessorWaiting()
        {
            var t=Input.Cancel("transport_test").Value;
            return new(t.Session,t.Connection,t.Channel,t.Epoch,t.Ticket,t.Endpoint,t.Incarnation);
        }
        public void PumpControlWithoutPumpingData()
        {
            Assert.True(Input.TryTakeOutput(out var item,controlOnly:true));
            var f=item.Payload.Split('|'); Assert.Equal("Cancel",f[1]);
            LastAppliedCancel=new(f[2],int.Parse(f[3]),f[4],int.Parse(f[5]),int.Parse(f[6]),f[7],int.Parse(f[8]));
        }
        private static InputCancel Ticket(CancelIdentity c)=>new(c.Session,(int)c.Connection,c.Channel,(int)c.Epoch,
            (int)c.Ticket,c.Endpoint,(int)c.Incarnation);
        public void NativeTransportAck(CancelIdentity cancel)
        {
            Assert.True(Input.IsWaiting(Ticket(cancel),InputParticipant.NativeBridge));
            _nativeReturned=true;Input.Heartbeat();
        }
        public void SemanticAck(CancelIdentity c,string scope)
        {
            var t=Ticket(c);
            if(scope=="AS2")Assert.True(Input.Receive(t.Connection,"I1|Cancelled|"+t.Fields+"|1|1"));
            else Assert.True(Input.Acknowledge(t,InputParticipant.V8));
        }
        public CancelIdentity SettleAndGrantSuccessor()
        {
            var t=RequestCancelWithSuccessorWaiting();PumpControlWithoutPumpingData();
            NativeTransportAck(t);SemanticAck(t,"AS2");SemanticAck(t,"V8");DrainData();return t;
        }
        public void RebindAndGrant()
        {
            Input.Disconnect(Input.ConnectionIncarnation);Input.Heartbeat();Bind(Input.ConnectionIncarnation+1);
        }
        public void DownInCurrentEpoch()=>Input.ObserveKey(0x44,true);
        public void UpInCurrentEpoch()=>Input.ObserveKey(0x44,false);
        public void DeliverCancelToRealEndpoints(CancelIdentity c)
        {
            var t=Ticket(c);
            Assert.False(Input.Receive(t.Connection,"I1|Cancel|"+t.Fields+"|late"));
            Assert.False(Input.Acknowledge(t,InputParticipant.V8));
            Assert.False(Input.Acknowledge(t,InputParticipant.NativeBridge));
        }
        public virtual void Dispose(){}
    }

    private sealed class PointerBinding : InputBinding,IR1Pointer,IWorldPointerSink
    {
        private readonly Form _source=new(){FormBorderStyle=FormBorderStyle.None};
        private readonly WorldCompositionSurface _surface;
        private readonly List<(int Msg,string Target)> _deliveries=new();
        private readonly List<long> _invalidated=new();
        private readonly List<string> _clicks=new();
        private int _physical;
        internal PointerBinding()
        {
            _surface=new WorldCompositionSurface(()=>_source.Handle,this,
                physicalButtons:()=>_physical) {Bounds=new Rectangle(-5000,-5000,100,100)};
            Input.GestureInvalidated+=_invalidated.Add;
            _surface.BindPassiveInput(Input);_surface.Show();
        }
        private Point PointOnScreen=>_surface.PointToScreen(new Point(30,25));
        public long KeyboardEpoch=>Input.CurrentKeyboardEpoch;
        public string HoverTarget {get;private set;}
        public IReadOnlyList<long> InvalidatedGestures=>_invalidated;
        public void Map(long version,long sourceIncarnation,string target)
        {
            _surface.SetCaptureInputBlocked(true);
            _source.ClientSize=new Size(target=="A" ? 100 : 200,100);
            _surface.SetCaptureInputBlocked(false);
        }
        public long QueueDownAtSharedScreenPoint()
        {
            _physical=1;_surface.IntakePointer(0x201,PointOnScreen,0);return Input.LastGestureId;
        }
        public void DeliverQueuedDown()=>_surface.Drain();
        public void UpAtSharedScreenPoint(){_physical=0;_surface.IntakePointer(0x202,PointOnScreen,0);}
        public void HoverAtSharedScreenPoint(){_surface.IntakePointer(0x200,PointOnScreen,0);Flush();}
        public InputWireRecord? TakeWorldCancel()
            => Input.TryTakeOutput(out var control, controlOnly: true) ? control : null;

        public bool ReplyWorldCancel(InputWireRecord control, bool matchingEpoch)
        {
            string[] fields = control.Payload.Split('|');
            Assert.Equal(6, fields.Length);
            Assert.Equal("WorldPointerCancel", fields[1]);
            fields[1] = "WorldPointerCancelled";
            if (!matchingEpoch)
                fields[5] = (uint.Parse(fields[5], CultureInfo.InvariantCulture) + 1).ToString(CultureInfo.InvariantCulture);
            return Input.Receive(control.Connection, string.Join("|", fields) + "|1");
        }

        public void Flush()=>_surface.FlushMove();
        public int OriginalDowns(string t)=>_deliveries.Count(p=>p==(0x201,t));
        public int OriginalReleases(string t)=>_deliveries.Count(p=>p==(0x202,t));
        public int BusinessClicks(string t)=>_clicks.Count(hit=>hit==t);
        public PointerPostStatus Send(in PointerPacket p,Point point)
        {
            string target=point.X>=50?"B":"A";
            _deliveries.Add((p.Message,target));
            // A deliberately sensitive consumer: even one stray original Up
            // calls its action. The fixture never suppresses or reroutes it.
            if(p.Message==0x202)_clicks.Add(target);
            if(p.Message==0x200)HoverTarget=target;
            EndpointConsumedSeq=p.Sequence;return PointerPostStatus.Posted;
        }
        public long EndpointConsumedSeq{get;private set;}
        public bool RaiseMinEpoch(uint epoch)=>true;
        public override void Dispose(){_surface.Dispose();_source.Dispose();}
    }
}

public static class R1AdversarialTestsWireIntegration
{
    [Fact]
    public static void TcpBindFrameRealV8ResultAndResetUseOneIncarnation()
    {
        DirectoryInfo dir=new(AppContext.BaseDirectory);
        while(dir!=null && !File.Exists(Path.Combine(dir.FullName,"launcher","scripts","dist","hit-number-bundle.js")))dir=dir.Parent;
        Assert.NotNull(dir);
        using var v8=new V8Runtime(Path.Combine(dir.FullName,"launcher","scripts"));
        v8.InitGameInput();
        var authority=new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        var frame=new FrameTask(v8,null);
        FrameTask unboundFrame=null;
        try {
        using var server=new XmlSocketServer(new MessageRouter(),AllowLoopbackXmlSocketPeerAuthority.Instance);
        frame.SetSocket(server);frame.BindInputAuthority(authority);
        server.SetFrameHandler(frame);server.BindInputAuthority(authority);
        authority.SetForeground(true);authority.SetBusinessEligible(true,"wire_test");
        Assert.True(server.Start(0));
        using var peer=new TcpClient();
        peer.Connect(IPAddress.Loopback,server.Port);peer.ReceiveTimeout=4000;
        var stream=peer.GetStream();
        void Send(string wire)=>stream.Write(Encoding.UTF8.GetBytes(wire+"\0"));
        string Read(string prefix) {
            for(int i=0;i<16;i++) {
                using var data=new MemoryStream();
                int b;while((b=stream.ReadByte())>0)data.WriteByte((byte)b);
                if(b<0)throw new EndOfStreamException();
                string packet=Encoding.UTF8.GetString(data.ToArray());
                if(packet.StartsWith(prefix,StringComparison.Ordinal))return packet;
            }
            throw new InvalidDataException(prefix);
        }
        // One authored trie transition: event 9 (A) accepts command 1.
        var transitions=Enumerable.Repeat(-1,38).ToArray();transitions[9]=1;
        var module=new {alphabetSize=19,transitions,accept=new[]{0,1},depth=new[]{0,1},hint=new[]{0,0},
            patterns=new[]{Array.Empty<int>(),new[]{9}},commandNames=new[]{"","拳"}};
        Send("D0\u0001"+System.Text.Json.JsonSerializer.Serialize(module));
        string bind=Read("I1|Bind|");
        string sc=authority.CurrentSessionId+"|"+authority.ConnectionIncarnation;
        Assert.Equal("I1|Bind|"+sc+"|15|1|64",bind);
        Send(bind.Replace("|Bind|","|Capability|"));
        var batch=Read("I1|InputBatch|").Split('|');string epoch=batch[4];
        Send($"I1|Latch|{sc}|{epoch}|{batch[5]}|1|1");
        string origin=$"{sc}|{epoch}|1|1|0|1|1";
        Send("F0,0,1\u0001\u0004I1|"+origin+"|0|1|0|2|11,1,D;12,1,U");
        string[] k=Read("I1|K|").Split('|');
        Assert.Equal(15,k.Length);
        Assert.Equal(origin,string.Join("|",k,2,8));
        Assert.Equal("1",k[10]);Assert.Equal("1",k[11]);Assert.Equal("拳",Uri.UnescapeDataString(k[12]));
        Assert.Equal(1,authority.V8ComboCount);
        Send("R");
        string[] cancel=Read("I1|Cancel|").Split('|');
        Assert.Equal(epoch,cancel[5]);Assert.False(authority.IsGameKeyboardAdmitted);
        Send("I1|Cancelled|"+string.Join("|",cancel,2,7)+"|1|1");
        Assert.True(int.Parse(Read("I1|InputBatch|").Split('|')[4])>int.Parse(epoch));
        // On a passive-bound connection, unversioned four-field F/\x04 is rejected before V8;
        // benchmark B echo acts as an ordered wire barrier proving no bare K was emitted.
        Send("F0,0,1\u0001\u00040|1|0|0");
        Send("F0,0,1\u0001\u000416|1|0|0");
        Send("Br1-benchmark");
        Assert.Equal("K \u0001\u0002r1-benchmark",Read("K"));
        Assert.Equal(1,authority.V8ComboCount);

        // The headless/unbound FrameTask also rejects old frames before V8.
        unboundFrame = new FrameTask(v8, null);
        unboundFrame.SetSocket(server);
        server.SetFrameHandler(unboundFrame);
        Send("F0,0,1\u0001\u00040|1|0|0");
        Send("F0,0,1\u0001\u000416|1|0|0");
        Send("Br4-unbound");
        Assert.Equal("K \u0001\u0002r4-unbound", Read("K"));
        } finally { frame.Stop(); unboundFrame?.Stop(); }
    }

    [Fact]
    public static void InputBitmapCoversAllEightWordsAndBatchesAtMost64Edges()
    {
        var a=new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        a.Connect(7);a.TryTakeOutput(out _);
        a.SetForeground(true);a.SetBusinessEligible(true,"ready");
        Assert.True(a.Receive(7,$"I1|Capability|{a.CurrentSessionId}|7|15|1|64"));
        Assert.True(a.TryTakeOutput(out _));
        for(int vk=0;vk<64;vk++)Assert.True(a.ObserveKey(vk,true));
        Assert.True(a.ObserveKey(255,true));
        Assert.True(a.TryTakeOutput(out var first));
        var f=first.Payload.Split('|');
        Assert.Equal("FFFFFFFFFFFFFFFF"+new string('0',48),f[8]);
        Assert.Equal("64",f[9]);Assert.Equal(64,f[10].Split(';').Length);
        Assert.True(a.TryTakeOutput(out var last));
        f=last.Payload.Split('|');
        Assert.Equal("FFFFFFFFFFFFFFFF"+new string('0',40)+"80000000",f[8]);
        Assert.Equal("1",f[9]);Assert.EndsWith(",255,D",f[10]);
    }

    [Fact]
    public static void AWorldReleaseDuringTextDoesNotConsumeTheNextFreshClick()
    {
        using var pointer=ProposedAdversarialBindings.Create<IR1Pointer>();
        var editor=(IR1Text)pointer;
        pointer.Map(10,2,"A");
        pointer.QueueDownAtSharedScreenPoint();pointer.DeliverQueuedDown();
        var lease=editor.EnterText("modifier.edit.itemQuery",5);
        pointer.UpAtSharedScreenPoint();pointer.Flush();
        editor.QueueLeaveFromActualEndpoint(lease)();
        pointer.QueueDownAtSharedScreenPoint();pointer.DeliverQueuedDown();
        pointer.UpAtSharedScreenPoint();pointer.Flush();
        Assert.Equal(2,pointer.OriginalDowns("A"));Assert.Equal(1,pointer.OriginalReleases("A"));
        Assert.Equal(1,pointer.BusinessClicks("A"));
    }
    [Fact]
    public static void PassiveModeAndAgentProbeRequireExactOptIn()
    {
        var emptyArgs = Array.Empty<string>();
        SessionInputAuthority.ValidateArgs(ref emptyArgs, passiveEnv: null);
        SessionInputAuthority.ValidateArgs(ref emptyArgs, passiveEnv: "");
        Assert.Empty(emptyArgs);
        Assert.Equal(PassiveFlashInputMode.Disabled, new SessionInputAuthority().Mode);
        Assert.ThrowsAny<ArgumentException>(() => new SessionInputAuthority((PassiveFlashInputMode)0));

        var args = new[] { "--r1-passive-input", "disabled", "--agent-harness", "fixture" };
        SessionInputAuthority.ValidateArgs(ref args);
        Assert.Equal(new[] { "--agent-harness", "fixture" }, args);

        var rollbackArgs = new[] { "--legacy-active-flash-input", "--agent-harness", "fixture" };
        var offArgs = new[] { "--r1-passive-input", "off" };
        var unsupportedArgs = new[] { "--r1-passive-input", "enabled_subclass" };
        var incompleteArgs = new[] { "--r1-passive-input" };
        var duplicateArgs = new[] { "--r1-passive-input", "disabled", "--r1-passive-input", "disabled" };
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref rollbackArgs));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref offArgs));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref unsupportedArgs));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref incompleteArgs));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref duplicateArgs));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref emptyArgs, passiveEnv: "off"));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref emptyArgs, passiveEnv: "enabled_subclass"));
        Assert.Throws<ArgumentException>(() => SessionInputAuthority.ValidateArgs(ref emptyArgs, legacyEnv: "1"));
        var agent=new AgentControlTask(null,null,null);
        var request=new Newtonsoft.Json.Linq.JObject{["action"]="r1PassiveProbe",["op"]="grantSessionForProbe",
            ["expectedSlot"]="cf7_agent_test",["expectedAttemptId"]="a"};
        Assert.Equal("passive_off",(string)Newtonsoft.Json.Linq.JObject.Parse(agent.Handle(request))["error"]);
        using var owner=new Form();
        var input=new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        var save=new Newtonsoft.Json.Linq.JObject{["slot"]="cf7_agent_test",["attemptId"]="current"};
        agent=new AgentControlTask(null,null,null,null,null,null,null,null,null,()=>save);
        agent.BindPassiveProbe(input,null,null,owner,()=>throw new InvalidOperationException("unauthorized grant"));
        request["expectedSlot"]="player";
        Assert.Equal("probe_identity_required",(string)Newtonsoft.Json.Linq.JObject.Parse(agent.Handle(request))["error"]);
        request["expectedSlot"]="cf7_agent_test";
        Assert.Equal("probe_attempt_mismatch",(string)Newtonsoft.Json.Linq.JObject.Parse(agent.Handle(request))["error"]);
        Assert.False(input.IsGameKeyboardAdmitted);
    }
}
