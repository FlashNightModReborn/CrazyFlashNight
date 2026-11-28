using System;
using System.Collections.Generic;
using CF7Launcher.Guardian.InputOwnership;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Bounded input queue for the surface. Motion coalesces into a single pending
    // move; button/wheel edges are never coalesced. Overflow is reported, never a
    // silent drop of a button edge.
    internal sealed class PointerQueue
    {
        internal const int Capacity=256;
        private readonly Queue<PointerPacket> _packets=new Queue<PointerPacket>();
        private PointerPacket? _move;
        internal int Count => _packets.Count;
        // Returns false when the queue is full; the caller must cancel the gesture.
        internal bool Enqueue(in PointerPacket packet)
        {
            if(packet.Message==0x200) { _move=packet; return true; }
            if(_packets.Count>=Capacity) return false;
            if(_move.HasValue) { _packets.Enqueue(_move.Value); _move=null; }
            if(_packets.Count>=Capacity) return false;
            _packets.Enqueue(packet);
            return true;
        }
        internal bool TryDequeue(out PointerPacket packet) => _packets.TryDequeue(out packet);
        internal PointerPacket? TakeMove() { var move=_move; _move=null; return move; }
        internal void Clear() { _packets.Clear(); _move=null; }
    }
    internal sealed class WorldCompositionSurface : Form
    {
        private readonly Func<IntPtr> _getFlash;
        private SessionInputAuthority _r1;
        private Func<bool> _exactForeground;
        private long _worldInstance,_authorityPointerEpoch;
        private readonly Dictionary<(uint Gesture,int Button),PointerGestureTicket> _worldClaims=new();
        private long _lastPostedLeftUp;
        private bool AuthoredDragMayBeLive => (_postedButtons & 1) != 0 ||
            (_lastPostedLeftUp > 0 && _bridge.EndpointCompletedSeq < _lastPostedLeftUp);
        internal void BindPassiveInput(SessionInputAuthority authority,Func<bool> foreground=null)
        {
            _r1=authority; _authorityPointerEpoch=authority.CurrentPointerEpoch; _exactForeground=foreground; _worldInstance=authority.NextInstanceGeneration(SessionInputAuthority.WorldEndpoint);
        }
        internal bool SynchronizePassiveGrant()
        {
            if(_r1==null || _authorityPointerEpoch==_r1.CurrentPointerEpoch)return false;
            _authorityPointerEpoch=_r1.CurrentPointerEpoch;
            // The native control slot already sealed issued work. Drop the UI
            // queue and retire local held buttons even if their Up went to an editor.
            CancelPointer("grant_revoked",endpointSealed:true);
            return true;
        }
        private string WorldTarget => _getFlash().ToString("X");
        private bool BeginWorldClaim(int bit,Point screen,out PointerGestureTicket ticket) =>
            _r1.TryBeginPointer(SessionInputAuthority.WorldEndpoint,_worldInstance,bit,screen,WorldTarget,out ticket);
        private readonly PointerQueue _queue=new PointerQueue();
        private readonly WorldHudPointerRouter _hudPointer;
        internal void SetHudInput(IWorldHudInput input) => _hudPointer.SetInput(input);
        internal void RetireLegacyHudGesture() => _hudPointer.RequireRelease(_readPhysicalButtons());
        private IWorldPointerSink _bridge;
        private readonly uint _epochLimit;
        private readonly long _sequenceLimit;
        private readonly Func<int> _readPhysicalButtons;
        private readonly Func<IntPtr> _readCapture;
        private bool _renewing,_awaitRelease,_awaitFreshDown;
        internal event Action RenewalRequested;
        internal bool InputRenewing => _renewing;
        internal bool GracefulRenewal {get;private set;}
        private int _physicalButtons, _postedButtons;
        private bool _posted, _draining, _inside;
        private IntPtr _inputTarget;
        // v4 bounded state: reset only by Rebind after confirmed retirement.
        // The presentation HWND survives; old local work is cleared and a new
        // physical gesture is required. Geometry is metadata, not session identity.
        private uint _inputEpoch=1, _gestureSeed, _openGesture, _geometryVersion;
        private Size _geometryOutput, _geometrySource;
        private long _sequence,_workGeneration;
        internal bool IsDragging => _physicalButtons!=0 || _postedButtons!=0 || _queue.Count!=0 || _hudPointer.IsDragging;
        internal WorldCompositionSurface(
            Func<IntPtr> flash, IWorldPointerSink sink,
            int inputEpochLimit = (int)WorldPointerMapper.EpochLimit, long maxEventsPerEpoch = WorldPointerMapper.SequenceLimit,
            Func<int> physicalButtons = null, Func<IntPtr> captureWindow = null)
        {
            if (inputEpochLimit < 8 || inputEpochLimit > WorldPointerMapper.EpochLimit)
                throw new ArgumentOutOfRangeException(nameof(inputEpochLimit));
            if (maxEventsPerEpoch < 16 || maxEventsPerEpoch > WorldPointerMapper.SequenceLimit)
                throw new ArgumentOutOfRangeException(nameof(maxEventsPerEpoch));
            _epochLimit = (uint)inputEpochLimit;
            _sequenceLimit = maxEventsPerEpoch;
            _readPhysicalButtons = physicalButtons ?? ReadPhysicalButtons;
            _readCapture = captureWindow ?? GetCapture;
            _getFlash = flash;
            _bridge = sink;
            _hudPointer=new WorldHudPointerRouter(callback=> {
                if(IsHandleCreated && !IsDisposed)BeginInvoke(new Action(()=> {
                    if(IsDisposed)return;
                    FlushMove();callback(); // Cancel still has to reach the HUD. Its queue fences stale callbacks by generation.
                }));
            });
            Text="CF7 world composition"; FormBorderStyle=FormBorderStyle.None;
            ShowInTaskbar=false; StartPosition=FormStartPosition.Manual; BackColor=Color.Black;
        }
        protected override bool ShowWithoutActivation => true;
        protected override CreateParams CreateParams {
            get { var cp=base.CreateParams; cp.ExStyle=(cp.ExStyle|0x08000000|0x80|0x80000)&~(0x40000|0x20); return cp; }
        }
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (!SetLayeredWindowAttributes(Handle,0,255,2)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        // Called on the UI thread by the existing WH_MOUSE_LL hook. Never focus,
        // capture, or synchronously call the Flash thread from inside that hook.
        internal bool RouteCapturedPointer(int x,int y,int message,uint mouseData)
        {
            if (!Visible || IsDisposed || !IsHandleCreated) return false;
            if(_exactForeground?.Invoke()==false) { _r1.SetForeground(false); return false; }
            IntPtr capture=_readCapture();
            if(_physicalButtons==0 && !_hudPointer.IsDragging && capture!=IntPtr.Zero && capture!=Handle)
            {
                // An unmigrated Native HUD/window can still own a real capture.
                // Crossing the new bottom raster must not steal its button release.
                _hudPointer.Leave();LeaveFlashForHud();return false;
            }
            Point screen=new Point(x,y);
            bool owned=WindowFromPoint(screen)==Handle;
            if (_physicalButtons!=0 || _hudPointer.IsDragging) {
                GetWindowThreadProcessId(GetForegroundWindow(),out uint pid);
                GetWindowThreadProcessId(_getFlash(),out uint flashPid);
                if (pid!=(uint)Environment.ProcessId && pid!=flashPid) { CancelPointer("foreground_lost"); return false; }
            } else if (!owned) {
                _hudPointer.Leave();
                if (_inside) { _inside=false; Enqueue(new PointerPacket(0x2A3,Point.Empty,Point.Empty,0,0,_inputEpoch,0,_geometryVersion,NextSequence())); }
                return false;
            }
            return IntakePointer(message,screen,mouseData);
        }
        // Queue/gesture intake, split from the WindowFromPoint/foreground checks so
        // tests can drive the envelope path without a topmost physical window.
        internal bool IntakePointer(int message,Point screen,uint mouseData)
        {
            SynchronizePassiveGrant();
            if(_captureBlocked)return message!=0x200;
            int bit=ButtonBit(message,mouseData);
            if(_renewing || _awaitRelease) {
                if(IsDown(message))_physicalButtons|=bit;
                if(IsUp(message))_physicalButtons&=~bit;
                int physical=_readPhysicalButtons();
                if(IsUp(message))physical&=~bit;
                if(IsDown(message))physical|=bit;
                if(!_renewing && physical==0) { _awaitRelease=false;_physicalButtons=0;_hudPointer.ObserveReleased(0); }
                return message!=0x200;
            }
            if(_awaitFreshDown && !IsDown(message) && message!=0x200)return message!=0x200;
            if(_hudPointer.TryRoute(message,screen,mouseData,_physicalButtons!=0))
            {
                if(IsDown(message))_awaitFreshDown=false;
                LeaveFlashForHud();
                return message!=0x200;
            }
            if(_r1!=null) {
                if(!_r1.IsGameKeyboardAdmitted)return message!=0x200;
                if(!GetClientRect(_getFlash(),out Rect source) || source.Right<1 || source.Bottom<1)return message!=0x200;
                TrackGeometry(new Size(source.Right,source.Bottom),IsDown(message) ? bit : 0);
                if(_awaitRelease)return message!=0x200;
                if(IsUp(message) && (_physicalButtons&bit)==0)return true;
            }
            _inside=true;
            // Soft boundary waits for an old gesture's release. The hard bound
            // cancels explicitly; no packet can be encoded by masking overflow.
            if((_physicalButtons==0 && (_inputEpoch>=_epochLimit-2 || _sequence>=_sequenceLimit-8))
                || (IsDown(message) && _physicalButtons==0 && _inputEpoch>=_epochLimit)) {
                if(IsDown(message))_physicalButtons|=bit;
                BeginRenewal();return message!=0x200;
            }
            // A fresh physical Down opens a gesture above the previously cancelled epoch.
            if (IsDown(message) && _physicalButtons==0) { _awaitFreshDown=false;_openGesture=++_gestureSeed; ++_inputEpoch; }
            if(_r1!=null) {
                if(IsDown(message)) {
                    if(!BeginWorldClaim(bit,screen,out var claim))return true;
                    _worldClaims[(_openGesture,bit)]=claim;
                } else if(IsUp(message)) {
                    if(!_worldClaims.TryGetValue((_openGesture,bit),out var claim))return true;
                    _r1.SealPointer(claim);
                }
            }
            if (IsDown(message)) _physicalButtons|=bit;
            if (IsUp(message)) _physicalButtons&=~bit;
            Enqueue(new PointerPacket(message,screen,PointToClient(screen),_physicalButtons|Modifiers(),mouseData,_inputEpoch,_openGesture,_geometryVersion,NextSequence()));
            // Consuming a low-level MOVE also freezes the OS cursor itself. Let motion
            // update the physical pointer; the surface's ordinary WndProc does not
            // forward it. Button/wheel edges are exclusively delivered by this queue.
            return message!=0x200;
        }
        private void BeginRenewal()
        {
            if(_renewing)return;
            if(_r1!=null){_r1.ChangeWorldGeometry();_worldClaims.Clear();}
            _hudPointer.Cancel();
            GracefulRenewal=_postedButtons==0;
            if (_r1 != null && AuthoredDragMayBeLive)
            {
                _bridge.RaiseMinEpoch(_inputEpoch + 1);
                _r1.QueueWorldPointerCancel(_inputEpoch + 1);
            }
            _lastPostedLeftUp = 0;
            _workGeneration++;_posted=false;
            _renewing=true;_queue.Clear();_openGesture=0;_postedButtons=0;_inputTarget=IntPtr.Zero;
            if(!GracefulRenewal)_bridge.RaiseMinEpoch(WorldPointerMapper.EpochLimit+1);
            LogManager.Log("event=world_pointer_quiesce epoch="+_inputEpoch+" seq="+_sequence);
            // Only queue the coordinator. Never wait for another UI thread inside a hook.
            long generation=_workGeneration;
            if(IsHandleCreated)BeginInvoke(new Action(()=> {if(!IsDisposed && _renewing && generation==_workGeneration)RenewalRequested?.Invoke();}));
        }
        internal void Rebind(IWorldPointerSink sink)
        {
            if(!_renewing)throw new InvalidOperationException("Input was not quiesced");
            _workGeneration++;_posted=false;
            _queue.Clear();_bridge=sink;_inputEpoch=1;_sequence=0;_gestureSeed=0;_openGesture=0;
            _inputTarget=IntPtr.Zero;_postedButtons=0;_physicalButtons=_readPhysicalButtons();
            _awaitRelease=_physicalButtons!=0;_awaitFreshDown=true;_renewing=false;
        }
        private static int ReadPhysicalButtons()
        {
            int flags=0;int[] keys={1,2,4,5,6};int[] bits={1,2,16,32,64};
            for(int i=0;i<keys.Length;i++)if((GetAsyncKeyState(keys[i])&0x8000)!=0)flags|=bits[i];
            return flags;
        }
        private long NextSequence()
        {
            if(_renewing)return 0;
            if(_sequence>=_sequenceLimit){BeginRenewal();return 0;}
            return ++_sequence;
        }
        private int Modifiers()
        {
            int flags=0;
            if ((GetKeyState(0x10)&0x8000)!=0) flags|=4;
            if ((GetKeyState(0x11)&0x8000)!=0) flags|=8;
            return flags;
        }
        private void Enqueue(in PointerPacket packet)
        {
            // Native cursor motion stays immediate in the shared hook. Flash receives
            // at most one hover/motion update per render tick; buttons flush it first.
            if(_renewing || packet.Sequence==0)return;
            if(!_queue.Enqueue(packet)) { CancelPointer("queue_full"); return; }
            ScheduleDrain();
        }
        private void ScheduleDrain()
        {
            if(_posted || _draining || _renewing || !IsHandleCreated)return;
            _posted=true;long generation=_workGeneration;
            BeginInvoke(new Action(()=>{if(generation==_workGeneration)Drain();}));
        }
        private bool _captureBlocked;
        internal void SetCaptureInputBlocked(bool blocked)
        {
            if(_captureBlocked==blocked)return;
            _captureBlocked=blocked;
            if(blocked)CancelPointer("capture_recovery");
            else {
                int physical=_readPhysicalButtons();
                _awaitRelease=physical!=0;
                _awaitFreshDown=true;
                _hudPointer.RequireRelease(physical);
            }
        }
        internal void FlushMove()
        {
            SynchronizePassiveGrant();
            if(_captureBlocked)return;
            int physical=_readPhysicalButtons();
            _hudPointer.ObserveReleased(physical);
            if(_awaitRelease && !_renewing && physical==0) { _awaitRelease=false;_physicalButtons=0; }
            if (_draining || _renewing) return;
            // A render tick can precede the posted Drain callback. Tail motion
            // is newer than queued edges; never deliver it ahead of Down/Up.
            if (_queue.Count!=0) Drain();
            if (_draining || _renewing || IsDisposed) return;
            var move=_queue.TakeMove();
            if (move.HasValue) Deliver(move.Value);
        }
        internal void Drain()
        {
            _posted=false;
            if (_captureBlocked || _draining || _renewing || IsDisposed) return;
            _draining=true;
            long generation=_workGeneration;
            try { while (generation==_workGeneration && _queue.TryDequeue(out var packet)) Deliver(packet); }
            finally { _draining=false; if(_queue.Count!=0)ScheduleDrain(); }
        }
        private uint TrackGeometry(Size source,int freshDown=0)
        {
            if(source!=_geometrySource || ClientSize!=_geometryOutput) {
                if(_r1!=null && !_geometrySource.IsEmpty)CancelWorldPointer("geometry_changed",freshDown:freshDown);
                _geometrySource=source; _geometryOutput=ClientSize; _geometryVersion++;
            }
            return _geometryVersion;
        }
        private void Deliver(PointerPacket packet)
        {
            if(SynchronizePassiveGrant())return;
            var sink=_bridge;
            if(_exactForeground?.Invoke()==false){_r1.SetForeground(false);return;}
            IntPtr rootWindow=_getFlash();
            if (rootWindow==IntPtr.Zero || !IsWindow(rootWindow)) { if(_openGesture!=0 || _postedButtons!=0) CancelPointer("source_gone"); return; }
            // A rebuilt target never receives packets chosen for the old one.
            if (_inputTarget!=IntPtr.Zero && rootWindow!=_inputTarget) { CancelPointer("target_rebuilt"); return; }
            if (packet.Message==0x2A3) {
                if (_postedButtons==0) Post(new PointerPacket(0x200,Point.Empty,Point.Empty,0,0,packet.Epoch,0,packet.Geometry,packet.Sequence),new Point(-1,-1));
                return;
            }
            if (!Visible || !GetClientRect(rootWindow,out Rect bounds) || bounds.Right<1 || bounds.Bottom<1) return;
            uint geometry=TrackGeometry(new Size(bounds.Right,bounds.Bottom));
            // In gameplay only an unheld hover can be remapped from its physical screen point.
            // Button edges and drags belong to the geometry of their pointer ticket.
            Point client=packet.Client;
            if (packet.Geometry!=geometry) {
                if(_r1!=null) {
                    if(packet.Message!=0x200 || packet.Gesture!=0 || (packet.Flags&0x73)!=0 || _awaitRelease)return;
                    long sequence=NextSequence();
                    if(sequence==0)return;
                    packet=new PointerPacket(packet.Message,packet.Screen,packet.Client,packet.Flags,packet.Data,_inputEpoch,0,geometry,sequence);
                }
                client=PointToClient(packet.Screen);
                if (packet.Message!=0x200)
                    LogManager.Log("event=world_pointer_remap msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence+" geo="+packet.Geometry+"->"+geometry);
            }
            Point point=WorldPointerMapper.Map(client,ClientSize,new Size(bounds.Right,bounds.Bottom));
            bool down=IsDown(packet.Message), up=IsUp(packet.Message);
            int bit=ButtonBit(packet.Message,packet.Data);
            var mapped=new PointerPacket(packet.Message,packet.Screen,client,packet.Flags,packet.Data,packet.Epoch,packet.Gesture,geometry,packet.Sequence);
            PointerPostStatus status=PointerPostStatus.PostFailed;
            PointerGestureTicket? claim=null;
            if(_r1==null)status=sink.Send(mapped,point);
            else {
                if(down || up) {
                    if(!_worldClaims.TryGetValue((packet.Gesture,bit),out var locked))return;
                    claim=locked;
                }
                else if(packet.Message==0x200 && (packet.Flags&0x73)!=0) {
                    int held=packet.Flags&0x73;
                    if(!_worldClaims.TryGetValue((packet.Gesture,held & -held),out var drag))return;
                    claim=drag;
                }
                if(!_r1.DispatchWorldPointer(claim,WorldTarget,()=>status=sink.Send(mapped,point))) {
                    if(packet.Gesture!=0)CancelPointer("grant_revoked");
                    return;
                }
            }
            if (status!=PointerPostStatus.Posted) {
                // A failed post must not leave a half-open gesture, and a local
                // rejection is never evidence of delivery.
                if (_openGesture!=0 || _postedButtons!=0 || down) CancelPointer("post_"+StatusName(status));
                else LogManager.Log("event=world_pointer_reject reason="+StatusName(status)+" msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence);
                return;
            }
            if(down) {
                _inputTarget=rootWindow; _postedButtons|=bit;
            }
            if(down || up) LogManager.Log("event=world_pointer_posted msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence
                +" epoch="+packet.Epoch+" gesture="+packet.Gesture+" geo="+geometry+" x="+point.X+" y="+point.Y
                +" source="+bounds.Right+"x"+bounds.Bottom+" session="+((sink as NativePointerBridge)?.SessionIdentity.ToString() ?? "fixture")+" consumed="+sink.EndpointConsumedSeq);
            if(up) {
                if (bit == 1) _lastPostedLeftUp = packet.Sequence;
                _postedButtons&=~bit;
                if(_postedButtons==0 && (_r1==null || _openGesture==packet.Gesture))_openGesture=0;
                if(claim is {} completed){_r1.EndPointer(completed,true);_worldClaims.Remove((packet.Gesture,bit));}
            }
        }
        private void Post(in PointerPacket packet,Point point)
        {
            var status=_bridge.Send(packet,point);
            if (status==PointerPostStatus.Posted) return;
            if (_openGesture!=0 || _postedButtons!=0) CancelPointer("post_"+StatusName(status));
            else LogManager.Log("event=world_pointer_reject reason="+StatusName(status)+" msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence);
        }
        private static string StatusName(PointerPostStatus status) => status switch {
            PointerPostStatus.Posted=>"posted",
            PointerPostStatus.BridgeClosed=>"bridge_closed",
            PointerPostStatus.SourceGone=>"source_gone",
            PointerPostStatus.PostFailed=>"post_failed",
            _=>"unknown" };
        internal void RefreshPointer()
        {
            if(!Visible || IsDisposed || _renewing || _captureBlocked) return;
            Point screen=Cursor.Position;
            if(WindowFromPoint(screen)==Handle && _hudPointer.TryRoute(0x200,screen,0,_physicalButtons!=0))LeaveFlashForHud();
            else if(WindowFromPoint(screen)==Handle)
                Enqueue(new PointerPacket(0x200,screen,PointToClient(screen),_physicalButtons,0,_inputEpoch,_openGesture,_geometryVersion,NextSequence()));
        }
        private void LeaveFlashForHud()
        {
            if(!_inside)return;
            _inside=false;
            Enqueue(new PointerPacket(0x2A3,Point.Empty,Point.Empty,0,0,_inputEpoch,0,_geometryVersion,NextSequence()));
        }
        // Publish the atomic floor and a persistent release ticket before the
        // advisory cancel data packet. Broker control wakes the endpoint after
        // post failure. Already-admitted original calls are retired separately.
        internal void CancelPointer(string reason="explicit",bool endpointSealed=false)
        {
            _hudPointer.Cancel();
            CancelWorldPointer(reason,endpointSealed);
        }
        internal void CancelWorldPointer(string reason,bool endpointSealed=false,int freshDown=0)
        {
            _probeOpenDown=null;
            if(_r1!=null) {
                if(!endpointSealed)_r1.ChangeWorldGeometry();
                _worldClaims.Clear();
                int held=_readPhysicalButtons();
                if(_physicalButtons==0 && _postedButtons==0 && _openGesture==0)held&=~freshDown;
                _awaitRelease=held!=0; _awaitFreshDown=true;
            }
            if(_renewing)return;
            _workGeneration++;_posted=false;_queue.Clear();
            if(_inputEpoch>=_epochLimit || _sequence>=_sequenceLimit){BeginRenewal();return;}
            uint epoch=++_inputEpoch;
            bool floor=endpointSealed || _bridge.RaiseMinEpoch(epoch);
            if (!endpointSealed && AuthoredDragMayBeLive) _r1?.QueueWorldPointerCancel(epoch);
            _lastPostedLeftUp = 0;
            bool had=_inputTarget!=IntPtr.Zero || _inside || _postedButtons!=0 || _physicalButtons!=0 || _openGesture!=0;
            _physicalButtons=_postedButtons=0; _inputTarget=IntPtr.Zero; _inside=false; _openGesture=0;
            if (had && !endpointSealed) {
                var packet=new PointerPacket(0x1F,Point.Empty,Point.Empty,0,0,epoch,0,_geometryVersion,NextSequence());
                var status=_bridge.Send(packet,new Point(-1,-1));
                LogManager.Log("event=world_pointer_cancel epoch="+epoch+" seq="+packet.Sequence+" reason="+reason
                    +" floor="+floor+" post="+StatusName(status)+" consumed="+_bridge.EndpointConsumedSeq);
            } else {
                LogManager.Log("event=world_pointer_cancel epoch="+epoch+" reason="+reason+" floor="+floor+" post=none");
            }
        }
        private (uint Gesture,PointerGestureTicket Ticket)? _probeOpenDown;
        internal bool TryBeginProbeWorldClaim(Point point,int button,out PointerGestureTicket ticket,out string target)
        {
            SynchronizePassiveGrant();
            target=WorldTarget;
            ticket=default;
            return _r1!=null && BeginWorldClaim(button,point,out ticket);
        }
        internal bool PostProbeDown(Point point,int button)
        {
            SynchronizePassiveGrant();
            IntPtr source=_getFlash();
            if(_r1==null || _renewing || _captureBlocked || IsDragging || _probeOpenDown!=null
                || !GetClientRect(source,out var bounds) || point.X<0 || point.Y<0 || point.X>=bounds.Right || point.Y>=bounds.Bottom
                || _inputEpoch>=_epochLimit-1 || _sequence>=_sequenceLimit-2)return false;
            int down=button switch {1=>0x201,2=>0x204,16=>0x207,_=>0};
            if(down==0 || !BeginWorldClaim(button,point,out var ticket))return false;
            uint gesture=++_gestureSeed;
            uint epoch=++_inputEpoch;
            bool posted=false;
            bool ok=_r1.DispatchWorldPointer(ticket,WorldTarget,()=>posted=_bridge.Send(new PointerPacket(down,point,point,
                button,0,epoch,gesture,_geometryVersion,NextSequence()),point)==PointerPostStatus.Posted) && posted;
            if(!ok) {
                _r1.EndPointer(ticket,false);
                CancelPointer("probe_down_failed");
                return false;
            }
            _probeOpenDown=(gesture,ticket);
            _openGesture=gesture; _inputTarget=source; _postedButtons|=button; _physicalButtons|=button;
            return true;
        }
        internal bool PostProbeUp(Point point,int button)
        {
            SynchronizePassiveGrant();
            IntPtr source=_getFlash();
            if(_r1==null || _renewing || _captureBlocked || _probeOpenDown is not {} open || open.Ticket.Button!=button
                || !GetClientRect(source,out var bounds) || point.X<0 || point.Y<0 || point.X>=bounds.Right || point.Y>=bounds.Bottom
                || _sequence>=_sequenceLimit-1)return false;
            int up=button switch {1=>0x202,2=>0x205,16=>0x208,_=>0};
            if(up==0)return false;
            _probeOpenDown=null;
            bool posted=false;
            long sequence = NextSequence();
            try {
                return _r1.DispatchWorldPointer(open.Ticket,WorldTarget,()=>posted=_bridge.Send(new PointerPacket(up,point,point,
                    0,0,_inputEpoch,open.Gesture,_geometryVersion,sequence),point)==PointerPostStatus.Posted) && posted;
            } finally {
                if (posted && button == 1) _lastPostedLeftUp = sequence;
                if (!posted) CancelPointer("probe_up_failed");
                _postedButtons&=~button; _physicalButtons&=~button;
                if(_postedButtons==0)_openGesture=0;
                _r1.EndPointer(open.Ticket,posted);
            }
        }
        internal bool PostProbeWheel(Point point,int delta)
        {
            SynchronizePassiveGrant();
            IntPtr source=_getFlash();
            if(_r1==null || !_r1.IsGameKeyboardAdmitted || _renewing || _captureBlocked || IsDragging || delta==0
                || !GetClientRect(source,out var bounds) || point.X<0 || point.Y<0 || point.X>=bounds.Right || point.Y>=bounds.Bottom
                || _inputEpoch>=_epochLimit-1 || _sequence>=_sequenceLimit-1)return false;
            uint epoch=++_inputEpoch;
            uint data=(uint)(ushort)(short)delta<<16;
            bool posted=false;
            return _r1.DispatchWorldPointer(null,WorldTarget,()=>posted=_bridge.Send(new PointerPacket(0x20A,point,point,
                0,data,epoch,0,_geometryVersion,NextSequence()),point)==PointerPostStatus.Posted) && posted;
        }
        // Isolated agent stimulus uses the same native session and monotonic
        // allocator. Coordinates are source client pixels, independent of WGC.
        internal bool PostProbeClick(Point point,int button)
        {
            SynchronizePassiveGrant();
            IntPtr source=_getFlash();
            if(_r1==null || _renewing || _captureBlocked || IsDragging || !GetClientRect(source,out var bounds)
                || point.X<0 || point.Y<0 || point.X>=bounds.Right || point.Y>=bounds.Bottom
                || _inputEpoch>=_epochLimit-1 || _sequence>=_sequenceLimit-2)return false;
            int down=button switch {1=>0x201,2=>0x204,16=>0x207,_=>0};
            if(down==0 || !BeginWorldClaim(button,point,out var ticket))return false;
            uint epoch=++_inputEpoch;
            bool posted=false;
            bool post(int msg, int buttons)
            {
                long sequence = NextSequence();
                if (_bridge.Send(new PointerPacket(msg, point, point, buttons, 0, epoch,
                    0, _geometryVersion, sequence), point) != PointerPostStatus.Posted)
                    return false;
                if (button == 1)
                {
                    if (buttons != 0) _postedButtons |= 1;
                    else
                    {
                        _postedButtons &= ~1;
                        _lastPostedLeftUp = sequence;
                    }
                }
                return true;
            }
            try {
                return _r1.DispatchWorldPointer(ticket,WorldTarget,()=>posted=post(down,button) && post(down+1,0)) && posted;
            } finally {
                _r1.EndPointer(ticket,posted);
                if(!posted)CancelPointer("probe_post_failed");
            }
        }
        private static bool IsDown(int m) => m==0x201 || m==0x204 || m==0x207 || m==0x20B;
        private static bool IsUp(int m) => m==0x202 || m==0x205 || m==0x208 || m==0x20C;
        private static int ButtonBit(int m,uint data) => m>=0x20B && m<=0x20D ? ((data>>16)==1 ? 32 : 64) : m>=0x207 && m<=0x209 ? 16 : m>=0x204 && m<=0x206 ? 2 : 1;
        protected override void OnVisibleChanged(EventArgs e) { if(!Visible)CancelPointer("hidden"); base.OnVisibleChanged(e); }
        protected override void WndProc(ref Message m)
        {
            const int wmDeviceChange=0x219, nodesChanged=7, removalComplete=0x8004;
            if(m.Msg==wmDeviceChange && m.WParam.ToInt64() is nodesChanged or removalComplete)
                _r1?.ObserveSourceLost("device_topology_changed");
            if(m.Msg==0x84){m.Result=new IntPtr(1);return;}
            if(m.Msg==0x21){m.Result=new IntPtr(3);return;}
            if(m.Msg==0x14){m.Result=new IntPtr(1);return;}
            base.WndProc(ref m);
        }
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left,Top,Right,Bottom; }
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetCapture();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [DllImport("user32.dll")] private static extern short GetKeyState(int key);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll",SetLastError=true)] private static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint color,byte alpha,uint flags);
    }
}
