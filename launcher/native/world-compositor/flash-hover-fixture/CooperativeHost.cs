using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;

// Experimental, disposable M domain. This is deliberately NOT compiled into
// launcher/src and grants no cancellation capability to the game's legacy F.
internal sealed partial class HoverHost
{
    private readonly bool cooperative=Environment.GetEnvironmentVariable("CF7_HOVER_COOPERATIVE")=="1";
    private NetworkStream probeStream;
    private readonly string mSession=Guid.NewGuid().ToString("N");
    private readonly Dictionary<string,string> mScopes=new();
    private readonly HashSet<string> mCancelled=new(),mReady=new();
    private readonly Queue<(MouseHook data,int message,bool foreground,bool admitted,int epoch,int geometry,long qpc)> mEdges=new();
    private bool mScheduled,mCalibrating,mOpen,mAwaitReady,mBroken,mDropChildCancelReceipt;
    private int mHeld,mSeenDown,mKnown,mCoverage=1,mEpoch,mTicket,mGesture,mBeginSeq,mSeq;
    private const int AllButtons=0x73;
    private string mState="Unregistered";
    private bool mDataFault,mFaultControlPosted,mPauseDrain;
    private int mGeometry=1;
    private Action mAfterFirstReady;
    private bool AllScopes(HashSet<string> receipts)=>mScopes.Count==2 && receipts.SetEquals(mScopes.Values);
    private static string Str(Sample s,string k){using var j=JsonDocument.Parse(s.Raw);return j.RootElement.GetProperty(k).GetString();}
    private int CountM(string ev)=>samples.Count(s=>s.Event==ev);
    private void Wire(string op,int gesture=0,int button=0,int begin=0,double x=-1,double y=-1,string session=null,int? coverage=null,int? epoch=null,int? ticket=null,int? geometry=null)
    {
        if(mSeq>=1_000_000){mBroken=true;mOpen=false;throw new InvalidOperationException("fixture sequence exhausted; retire");}
        string packet=string.Join("|",op,session??mSession,coverage??mCoverage,epoch??mEpoch,ticket??mTicket,++mSeq,gesture,button,begin,x.ToString(CultureInfo.InvariantCulture),y.ToString(CultureInfo.InvariantCulture),geometry??mGeometry);
        Log("M_SEND "+packet);
        byte[] bytes=Encoding.UTF8.GetBytes(packet+"\0");
        try {probeStream.Write(bytes,0,bytes.Length);}catch{mOpen=false;mBroken=true;throw;}
    }
    private void ObserveCooperative(Sample sample)
    {
        if(sample.Event=="ready")return;
        using var doc=JsonDocument.Parse(sample.Raw);var j=doc.RootElement;
        if(!j.TryGetProperty("session",out var session) || session.GetString()!=mSession)return;
        if(sample.Event=="FAULT"){mOpen=false;mBroken=true;return;}
        string inc=j.GetProperty("incarnation").GetString();
        if(sample.Event=="REGISTER") {
            if(Value(sample,"coverage")!=mCoverage || (sample.Target!="A" && sample.Target!="B") || j.GetProperty("protocol").GetInt32()!=2 || j.GetProperty("capabilities").GetString()!="pointer-left-explicit;raw-diagnostic;deferred-guarded;no-keyboard" || j.GetProperty("contentBuild").GetString()!=(sample.Target=="A"?"r9-main-v2":"r9-child-v2")){mOpen=false;mBroken=true;return;}
            if(mScopes.TryGetValue(sample.Target,out var old) && old!=inc){mOpen=false;mBroken=true;return;}
            mScopes[sample.Target]=inc;return;
        }
        if(!mScopes.TryGetValue(sample.Target,out var expected) || expected!=inc || Value(sample,"coverage")!=mCoverage || Value(sample,"epoch")!=mEpoch || Value(sample,"ticket")!=mTicket || Value(sample,"geometry")!=mGeometry)return;
        if(sample.Event=="CANCELLED" && Value(sample,"pending")==0 && j.GetProperty("gateClosed").GetBoolean() && !(mDropChildCancelReceipt && sample.Target=="B"))mCancelled.Add(inc);
        if(sample.Event=="READY" && mAwaitReady && AllScopes(mCancelled) && mKnown==AllButtons && mHeld==0 && !mDataFault) {
            mReady.Add(inc);
            if(mReady.Count==1 && mAfterFirstReady!=null){var action=mAfterFirstReady;mAfterFirstReady=null;action();}
            // Final grant is posted after the observation prefix, never inside
            // receipt parsing. A conflicting LL edge invalidates this round.
            if(AllScopes(mReady)) {
                int epoch=mEpoch,geometry=mGeometry;
                BeginInvoke(new Action(()=>{
                    if(!mBroken && !mDataFault && mAwaitReady && mHeld==0 && mEdges.Count==0 && epoch==mEpoch && geometry==mGeometry && AllScopes(mReady)) {
                        mAwaitReady=false;mOpen=true;mState="Ready";
                    } else if(mAwaitReady && epoch==mEpoch)CancelCooperative("prepare_prefix_changed");
                }));
            }
        }
    }
    private void CancelCooperative(string cause)
    {
        if(mBroken || mScopes.Count!=2)return;
        mOpen=false;mAwaitReady=false;mState="Revoking";mCancelled.Clear();mReady.Clear();
        mEpoch++;mTicket++;mBeginSeq=0;
        // mHeld/mKnown survive cancellation, even when the owner is hidden.
        Wire("CANCEL");Log("M_CANCEL "+JsonSerializer.Serialize(new{cause,mHeld,mKnown,mEpoch,mTicket}));
        surface?.CancelPointer("cooperative_fixture_"+cause);
    }
    private async Task OpenCooperative()
    {
        if(mHeld!=0 || mKnown!=AllButtons || mBroken || mDataFault)throw new InvalidOperationException("physical neutral not qualified");
        var deadline=Stopwatch.StartNew();
        while(!mOpen && deadline.ElapsedMilliseconds<12000) {
            await WaitFor(()=>mBroken || mDataFault || (AllScopes(mCancelled) && mHeld==0 && mKnown==AllButtons),"cancel and neutral before prepare");
            if(mBroken || mDataFault)throw new InvalidOperationException("input fault remains blocked");
            mAwaitReady=true;mReady.Clear();Wire("READY");
            await WaitFor(()=>mBroken || mDataFault || mOpen || !mAwaitReady,"prepare completed or invalidated");
        }
        if(!mOpen)throw new InvalidOperationException("prepare recovery deadline");
    }
    private void FaultCooperativeData()
    {
        // Closing admission is immediate; sending CANCEL is independent of the
        // bounded input queue and does not run inside the LL hook.
        mDataFault=true;mOpen=false;mAwaitReady=false;mKnown=0;mState="FaultBlocked";mEdges.Clear();mCancelled.Clear();mReady.Clear();
        if(Environment.GetEnvironmentVariable("CF7_COOPERATIVE_S1_NEGATIVE")=="1") {
            // Explicit discarded control: reproduce R8's loss of the revoke path.
            Log("NEGATIVE_CONTROL S1 revoke intentionally suppressed");mBroken=true;return;
        }
        if(mFaultControlPosted)return;
        mFaultControlPosted=true;
        BeginInvoke(new Action(()=>{mFaultControlPosted=false;if(!mBroken)CancelCooperative("data_queue_fault");}));
    }
    private void CooperativeGeometryChanged()
    {
        checked{mGeometry++;}
        if(mScopes.Count==2 && !mBroken)CancelCooperative("geometry_changed");
    }
    private bool RouteCooperative(MouseHook data,int message)
    {
        bool owned=GetForegroundWindow()==Handle || GetForegroundWindow()==source;
        if(mEdges.Count>=256){FaultCooperativeData();return owned && message!=0x200;}
        mEdges.Enqueue((data,message,owned,mOpen,mEpoch,mGeometry,Stopwatch.GetTimestamp()));
        if(!mScheduled){mScheduled=true;BeginInvoke(new Action(DrainCooperative));}
        // LL hook does no network I/O. This disposable domain owns all its raw
        // callbacks. In production this permission cannot be borrowed by U.
        if(mCalibrating)return owned && message!=0x200;
        bool consumed=controller!=null && controller.RouteCapturedPointer(data.point.X,data.point.Y,message,data.data);
        return consumed || (owned && message!=0x200);
    }
    private void DrainCooperative()
    {
        mScheduled=false;
        if(mPauseDrain)return;
        while(mEdges.TryDequeue(out var edge)) {
            int msg=edge.message;
            bool down=msg==0x201 || msg==0x204 || msg==0x207 || msg==0x20B;
            bool up=msg==0x202 || msg==0x205 || msg==0x208 || msg==0x20C;
            int bit=msg==0x20B || msg==0x20C ? ((edge.data.data>>16)==1?32:64) : msg==0x207 || msg==0x208?16:msg==0x204 || msg==0x205?2:1;
            int before=mHeld;
            if(down){mHeld|=bit;mSeenDown|=bit;}
            if(up){mHeld&=~bit;if((mSeenDown&bit)!=0)mKnown|=bit;}
            if(down || up)Log("M_EDGE "+JsonSerializer.Serialize(new{qpc=edge.qpc,stimulusId=edge.data.extra.ToUInt64(),message=msg,edge.admitted,edge.epoch,currentEpoch=mEpoch,mHeld,mKnown,mSeq,mGesture}));
            if(mCalibrating || mBroken || mDataFault)continue;
            bool foreground=edge.foreground && (GetForegroundWindow()==Handle || GetForegroundWindow()==source);
            if((mOpen || mAwaitReady) && (!foreground || (mAwaitReady && (down || up)) || (down && (before!=0 || bit!=1))))CancelCooperative(!foreground?"foreign_foreground":"prepare_or_button_conflict");
            if(!mOpen || !edge.admitted || edge.epoch!=mEpoch || edge.geometry!=mGeometry)continue;
            Point local=surface.PointToClient(edge.data.point);
            double x=local.X*640.0/surface.ClientSize.Width,y=local.Y*360.0/surface.ClientSize.Height;
            if(down && bit==1 && before==0 && mKnown==AllButtons) {
                mGesture++;mBeginSeq=mSeq+1;mState="Held";
                Wire("BEGIN",mGesture,1,mBeginSeq,x,y);
            } else if(up && bit==1 && mBeginSeq!=0) {
                Wire("END",mGesture,1,mBeginSeq,x,y);mBeginSeq=0;mState="Ready";
            } else if(msg==0x200)Wire("UPDATE",mGesture,1,mBeginSeq,x,y);
        }
    }
    private async Task MClick(string target)
    {
        int b=CountM("mBegin"),e=CountM("mEnd"),c=CountM("mCommit");
        long start=Mark("M-click-"+target);
        MovePointer(target=="A"?160:430,150);await Task.Delay(120);Edge(2);
        await WaitFor(()=>CountM("mBegin")==b+1,"logical Begin");
        Edge(4);await WaitFor(()=>CountM("mCommit")==c+1,"logical deferred commit");
        var events=samples.Where(s=>s.Tick>=start && (s.Event=="mBegin" || s.Event=="mEnd" || s.Event=="mCommit")).ToArray();
        Check(CountM("mEnd")==e+1 && events.Select(s=>s.Event).SequenceEqual(new[]{"mBegin","mEnd","mCommit"}) && events.All(s=>s.Target==target) && events.Select(s=>Value(s,"gesture")).Distinct().Count()==1 && events.Select(s=>Value(s,"beginSeq")).Distinct().Count()==1 && events.Select(s=>Str(s,"incarnation")).Distinct().Count()==1,"M_exact_new_gesture_"+target,events.Select(s=>new{s.Event,s.Target,gesture=Value(s,"gesture"),begin=Value(s,"beginSeq"),incarnation=Str(s,"incarnation")}).ToArray());
    }
    private void MultiEdge(uint flags,uint data=0)
    {
        long id=++stimulusId;
        Log("STIMULUS "+JsonSerializer.Serialize(new{id,phase,qpc=Stopwatch.GetTimestamp(),kind="button",flags,data}));
        var input=new INPUT{type=0,mouse=new MOUSEINPUT{flags=flags,data=data,extra=new UIntPtr((ulong)id)}};
        if(SendInput(1,new[]{input},Marshal.SizeOf<INPUT>())!=1)throw new InvalidOperationException("calibration SendInput failed");
    }
    private async Task RunCooperative()
    {
        Log("M_MODE experimental disposable domain; raw VM failure retained in separate HoverProbe control");
        mCalibrating=true;MovePointer(280,270);await Task.Delay(100);
        foreach(var b in new[]{(2u,4u,0u),(8u,16u,0u),(32u,64u,0u),(128u,256u,1u),(128u,256u,2u)}) {
            MultiEdge(b.Item1,b.Item3);await Task.Delay(40);MultiEdge(b.Item2,b.Item3);await Task.Delay(40);
        }
        mCalibrating=false;Check(mKnown==AllButtons && mHeld==0,"M_neutral_observed_edges",new{mKnown,mHeld});
        Wire("HELLO");await WaitFor(()=>mScopes.Count==2,"main and loaded child REGISTER");
        Deactivate+=(_,__)=>{if(mOpen || mAwaitReady)CancelCooperative("deactivate");};
        LocationChanged+=(_,__)=>CooperativeGeometryChanged();
        ClientSizeChanged+=(_,__)=>CooperativeGeometryChanged();
        CancelCooperative("initial");await OpenCooperative();
        await MClick("A");await MClick("B");

        // No-focus cancel: physical ledger remains held and old Up must not End.
        Mark("M-no-focus-cancel");MovePointer(160,150);await Task.Delay(100);int begins=CountM("mBegin");Edge(2);
        await WaitFor(()=>CountM("mBegin")==begins+1,"held Begin before no-focus cancel");
        int ends=CountM("mEnd"),commits=CountM("mCommit");CancelCooperative("explicit_no_focus");
        await WaitFor(()=>mCancelled.Count==2,"cancel main and child");
        Check(mHeld==1 && !mOpen,"M_cancel_preserves_held",new{mHeld,mState});
        Edge(4);await Task.Delay(250);
        Check(mHeld==0 && CountM("mEnd")==ends && CountM("mCommit")==commits,"M_old_up_no_commit",new{mHeld,ends=CountM("mEnd"),commits=CountM("mCommit")});
        await OpenCooperative();await MClick("A");

        // Real foreground switch with held input, external Up, independent new B.
        Mark("M-external-cancel");MovePointer(160,150);await Task.Delay(100);begins=CountM("mBegin");Edge(2);
        await WaitFor(()=>CountM("mBegin")==begins+1,"held Begin before switch");ends=CountM("mEnd");commits=CountM("mCommit");
        externalProbe=Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory,"FlashHoverHost.exe"),"--external"){UseShellExecute=false});
        await WaitFor(()=>{externalProbe.Refresh();return externalProbe.MainWindowHandle!=IntPtr.Zero;},"external HWND");
        SetForegroundWindow(externalProbe.MainWindowHandle);await Task.Delay(200);MovePointer(900,120);await Task.Delay(100);Edge(4);await Task.Delay(200);
        Check(GetForegroundWindow()==externalProbe.MainWindowHandle && !mOpen && mHeld==0 && mCancelled.Count==2,"M_external_cancel_and_neutral",new{mHeld,mState,receipts=mCancelled.Count});
        Check(CountM("mEnd")==ends && CountM("mCommit")==commits,"M_external_old_gesture_no_commit",CountM("mCommit"));
        Activate();FocusFlash();await Task.Delay(200);await OpenCooperative();await MClick("A");await MClick("B");

        // Deferred work was authorized but has not committed at the cancel edge.
        Mark("M-deferred-revoke");MovePointer(160,150);await Task.Delay(100);begins=CountM("mBegin");Edge(2);
        await WaitFor(()=>CountM("mBegin")==begins+1,"Begin for deferred case");ends=CountM("mEnd");commits=CountM("mCommit");Edge(4);
        await WaitFor(()=>CountM("mEnd")==ends+1,"End before pending revoke");CancelCooperative("pending_job");await Task.Delay(650);
        Check(CountM("mCommit")==commits && mCancelled.Count==2,"M_deferred_job_invalidated",CountM("mCommit"));await OpenCooperative();

        // A right button while left is down revokes the entire gesture. Releasing
        // just left never qualifies neutral; neither old edge may become new End.
        Mark("M-multi-button");MovePointer(160,150);await Task.Delay(100);begins=CountM("mBegin");Edge(2);
        await WaitFor(()=>CountM("mBegin")==begins+1,"Begin before multi-button");commits=CountM("mCommit");MultiEdge(8);await Task.Delay(120);Edge(4);await Task.Delay(100);
        Check(mHeld==2 && !mOpen,"M_multi_button_still_waits",new{mHeld,mState});MultiEdge(16);await Task.Delay(150);
        Check(mHeld==0 && CountM("mCommit")==commits,"M_multi_button_no_commit",CountM("mCommit"));await OpenCooperative();

        Mark("M-drag-blank-and-keyboard");MovePointer(160,150);await Task.Delay(120);begins=CountM("mBegin");Edge(2);
        await WaitFor(()=>CountM("mBegin")==begins+1,"Begin for drag");ends=CountM("mEnd");commits=CountM("mCommit");
        MovePointer(280,270);await Task.Delay(120);Edge(4);await Task.Delay(600);
        Check(CountM("mEnd")==ends+1 && CountM("mCommit")==commits && !samples.Last().HoverA && !samples.Last().HoverB,"M_drag_outside_no_commit",new{ends=CountM("mEnd"),commits=CountM("mCommit")});
        begins=CountM("mBegin");Edge(2);await Task.Delay(80);Edge(4);await Task.Delay(500);
        Check(CountM("mBegin")==begins && CountM("mCommit")==commits,"M_blank_hit_cannot_borrow_target",CountM("mBegin"));
        int rawKeys=CountM("raw-key");FocusFlash();
        foreach(uint flags in new[]{0u,2u}) {
            long id=++stimulusId;Log("STIMULUS "+JsonSerializer.Serialize(new{id,phase,qpc=Stopwatch.GetTimestamp(),kind="space",flags}));
            var key=new INPUT{type=1,keyboard=new KEYBDINPUT{vk=32,flags=flags,extra=new UIntPtr((ulong)id)}};
            if(SendInput(1,new[]{key},Marshal.SizeOf<INPUT>())!=1)throw new InvalidOperationException("key SendInput failed");
            await Task.Delay(80);
        }
        await Task.Delay(500);Check(CountM("raw-key")>rawKeys && CountM("mCommit")==commits,"M_raw_keyboard_no_business",new{rawKeys=CountM("raw-key"),commits=CountM("mCommit")});

        // Parent cancellation alone is an explicit failure control. Old receipts
        // cannot satisfy a newer ticket, and a held return cannot request READY.
        Mark("M-cancel-barrier-negative-controls");var oldReceipt=samples.Last(s=>s.Event=="CANCELLED");
        mDropChildCancelReceipt=true;CancelCooperative("drop_child_receipt");ObserveCooperative(oldReceipt);
        Check(mCancelled.Count==0,"M_old_receipt_rejected",mCancelled.Count);await Task.Delay(250);
        Check(mCancelled.Count==1 && !mOpen,"M_parent_receipt_cannot_open_child",mCancelled.ToArray());
        mDropChildCancelReceipt=false;Wire("CANCEL");await OpenCooperative();
        MovePointer(160,150);await Task.Delay(120);begins=CountM("mBegin");Edge(2);await WaitFor(()=>CountM("mBegin")==begins+1,"held return Begin");
        CancelCooperative("still_held_return");await WaitFor(()=>mCancelled.Count==2,"held return cancel");
        bool refused=false;try{await OpenCooperative();}catch(InvalidOperationException){refused=true;}
        Check(refused && mHeld==1 && !mOpen,"M_return_held_cannot_readmit",new{refused,mHeld,mOpen});
        Edge(4);await Task.Delay(120);await OpenCooperative();await MClick("A");

        // Old session/epoch/ticket and replay cannot create business obligations.
        Mark("M-stale-and-replay");begins=CountM("mBegin");commits=CountM("mCommit");
        Wire("BEGIN",mGesture+1,1,mSeq+1,160,150,session:"old-session");
        Wire("BEGIN",mGesture+1,1,mSeq+1,160,150,epoch:mEpoch-1);
        Wire("READY",ticket:mTicket-1);Wire("END",mGesture,1,mBeginSeq,160,150);await Task.Delay(450);
        Check(CountM("mBegin")==begins && CountM("mCommit")==commits,"M_stale_protocol_rejected",new{begins=CountM("mBegin"),commits=CountM("mCommit")});
        await MClick("A");

        // Same-path child reload changes coverage and incarnation. No parent ACK
        // can reopen it. The old incarnation remains in the frozen evidence.
        Mark("M-child-reload");CancelCooperative("child_reload");await WaitFor(()=>mCancelled.Count==2,"pre-reload cancel");
        string oldChild=mScopes["B"];mScopes.Clear();mCancelled.Clear();mReady.Clear();mCoverage++;
        Wire("RELOAD");await WaitFor(()=>mScopes.Count==2,"new child coverage");
        Check(mScopes["B"]!=oldChild && !mOpen,"M_reload_new_incarnation_closed",new{oldChild,current=mScopes["B"],mCoverage});
        CancelCooperative("new_coverage");await OpenCooperative();await MClick("B");
        await RunCooperativeFaultCases();
        // Finish the slice closed; no subsequent input is authorized.
        CancelCooperative("end_of_slice");await WaitFor(()=>mCancelled.Count==2,"final close receipts");
        Check(!mBroken && mDataFault && !mOpen,"M_control_transport_survives_injected_data_fault",new{mSeq,mState,mDataFault});
        Log("M_LIMITS pointer-only M fixture; no production C1, IME, unregistered SWF or game cancellation certification");
    }
    private async Task RunCooperativeFaultCases()
    {
        Mark("S2-ready-conflict");CancelCooperative("ready_race_test");
        await WaitFor(()=>AllScopes(mCancelled),"S2 initial cancellation");
        Wire("TEST_READY_DELAY",x:6); // fixture-only: actual AS2 delays B receipt.
        int oldTicket=mTicket,commits=CountM("mCommit"),begins=CountM("mBegin");
        mAfterFirstReady=()=>Edge(2);
        Task prepare=OpenCooperative();
        await WaitFor(()=>mHeld==1 && mTicket>oldTicket,"LL down invalidates partial READY");
        Check(!mOpen && !mAwaitReady,"S2_partial_ready_revoked",new{mHeld,mTicket,oldTicket});
        await Task.Delay(250);Edge(4);await prepare;
        Check(mOpen && CountM("mBegin")==begins && CountM("mCommit")==commits,"S2_recovers_without_replaying_input",new{mTicket,begins=CountM("mBegin"),commits=CountM("mCommit")});
        await MClick("A");

        Mark("S3-queued-down-geometry");MovePointer(160,150);await Task.Delay(150);
        begins=CountM("mBegin");commits=CountM("mCommit");mPauseDrain=true;Edge(2);
        await WaitFor(()=>mEdges.Any(x=>x.message==0x201),"LL down queued before geometry change");
        int oldGeometry=mGeometry;Location=new Point(Left+35,Top+25);
        mPauseDrain=false;DrainCooperative();await Task.Delay(300);Edge(4);await Task.Delay(150);
        Check(mGeometry>oldGeometry && !mOpen && CountM("mBegin")==begins && CountM("mCommit")==commits,"S3_old_queued_edge_cannot_retarget",new{oldGeometry,mGeometry,begins=CountM("mBegin")});
        await OpenCooperative();
        Wire("BEGIN",mGesture+1,1,mSeq+1,160,150,geometry:oldGeometry);await Task.Delay(150);
        Check(CountM("mBegin")==begins,"S3_endpoint_rejects_old_geometry",CountM("mBegin"));await MClick("A");

        Mark("S1-data-queue-fault-pending-job");MovePointer(160,150);await Task.Delay(120);
        begins=CountM("mBegin");int ends=CountM("mEnd");commits=CountM("mCommit");Edge(2);
        await WaitFor(()=>CountM("mBegin")==begins+1,"S1 Begin");Edge(4);
        await WaitFor(()=>CountM("mEnd")==ends+1,"S1 actual AS2 deferred obligation");
        Log("FAULT_INJECT actual bounded data queue overflow; not physical input");
        mPauseDrain=true;
        var move=new MouseHook{point=Cursor.Position};
        for(int i=0;i<257;i++)RouteCooperative(move,0x200);
        mPauseDrain=false;DrainCooperative();
        Check(mDataFault && !mOpen && mKnown==0,"S1_host_fault_is_not_cancel_certificate",new{mDataFault,mKnown,receipts=mCancelled.Count});
        await Task.Delay(650);
        Check(CountM("mCommit")==commits && AllScopes(mCancelled),"S1_remote_deferred_obligation_revoked",new{commits=CountM("mCommit"),scopes=mCancelled.ToArray()});
        if(mBroken)return;
        bool refused=false;try{await OpenCooperative();}catch(InvalidOperationException){refused=true;}
        Check(refused && !mOpen,"S1_unknown_observer_does_not_reopen",new{refused,mOpen});
    }
}
