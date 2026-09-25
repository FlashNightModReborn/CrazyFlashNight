using System;
using System.Collections.Generic;
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
        private readonly Action _focus;
        private readonly PointerQueue _queue=new PointerQueue();
        private IWorldPointerSink _bridge;
        private readonly uint _epochLimit;
        private readonly long _sequenceLimit;
        private readonly Func<int> _readPhysicalButtons;
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
        internal bool IsDragging => _physicalButtons!=0 || _postedButtons!=0 || _queue.Count!=0;
        internal WorldCompositionSurface(Func<IntPtr> getFlash,Action focus,IWorldPointerSink bridge,uint epochLimit=WorldPointerMapper.EpochLimit,long sequenceLimit=WorldPointerMapper.SequenceLimit,Func<int> physicalButtons=null)
        {
            if(epochLimit<8 || epochLimit>WorldPointerMapper.EpochLimit || sequenceLimit<16 || sequenceLimit>WorldPointerMapper.SequenceLimit)throw new ArgumentOutOfRangeException(nameof(epochLimit));
            _epochLimit=epochLimit;_sequenceLimit=sequenceLimit;_readPhysicalButtons=physicalButtons ?? ReadPhysicalButtons;
            _getFlash=getFlash; _focus=focus; _bridge=bridge;
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
            Point screen=new Point(x,y);
            bool owned=WindowFromPoint(screen)==Handle;
            if (_physicalButtons!=0) {
                GetWindowThreadProcessId(GetForegroundWindow(),out uint pid);
                GetWindowThreadProcessId(_getFlash(),out uint flashPid);
                if (pid!=(uint)Environment.ProcessId && pid!=flashPid) { CancelPointer("foreground_lost"); return false; }
            } else if (!owned) {
                if (_inside) { _inside=false; Enqueue(new PointerPacket(0x2A3,Point.Empty,Point.Empty,0,0,_inputEpoch,0,_geometryVersion,NextSequence())); }
                return false;
            }
            return IntakePointer(message,screen,mouseData);
        }
        // Queue/gesture intake, split from the WindowFromPoint/foreground checks so
        // tests can drive the envelope path without a topmost physical window.
        internal bool IntakePointer(int message,Point screen,uint mouseData)
        {
            _inside=true;
            int bit=ButtonBit(message,mouseData);
            if(_renewing || _awaitRelease) {
                if(IsDown(message))_physicalButtons|=bit;
                if(IsUp(message))_physicalButtons&=~bit;
                if(!_renewing && _readPhysicalButtons()==0){_awaitRelease=false;_physicalButtons=0;}
                return message!=0x200;
            }
            if(_awaitFreshDown && !IsDown(message) && message!=0x200)return message!=0x200;
            // Soft boundary waits for an old gesture's release. The hard bound
            // cancels explicitly; no packet can be encoded by masking overflow.
            if((_physicalButtons==0 && (_inputEpoch>=_epochLimit-2 || _sequence>=_sequenceLimit-8))
                || (IsDown(message) && _physicalButtons==0 && _inputEpoch>=_epochLimit)) {
                if(IsDown(message))_physicalButtons|=bit;
                BeginRenewal();return message!=0x200;
            }
            // A physical down with no held buttons starts a new gesture and mints
            // the next input epoch. This is what re-admits input after a focus
            // loss: the projector revokes every epoch issued before its
            // focus-loss boundary, so the first post-loss down must carry a
            // newer epoch — and this advance is the only place that provides one.
            if (IsDown(message) && _physicalButtons==0) { _awaitFreshDown=false;_openGesture=++_gestureSeed; ++_inputEpoch; }
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
            GracefulRenewal=_postedButtons==0;
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
        internal void FlushMove()
        {
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
            if (_draining || _renewing || IsDisposed) return;
            _draining=true;
            long generation=_workGeneration;
            try { while (generation==_workGeneration && _queue.TryDequeue(out var packet)) Deliver(packet); }
            finally { _draining=false; if(_queue.Count!=0)ScheduleDrain(); }
        }
        private uint TrackGeometry(Size source)
        {
            if(source!=_geometrySource || ClientSize!=_geometryOutput) {
                _geometrySource=source; _geometryOutput=ClientSize; _geometryVersion++;
            }
            return _geometryVersion;
        }
        private void Deliver(PointerPacket packet)
        {
            var sink=_bridge;
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
            // Packets carry the geometry they were queued under. A stale-geometry
            // packet keeps its physical screen point and is remapped under the
            // current sizes; the old client offset is never applied to a new size.
            Point client=packet.Client;
            if (packet.Geometry!=geometry) {
                client=PointToClient(packet.Screen);
                if (packet.Message!=0x200)
                    LogManager.Log("event=world_pointer_remap msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence+" geo="+packet.Geometry+"->"+geometry);
            }
            Point point=WorldPointerMapper.Map(client,ClientSize,new Size(bounds.Right,bounds.Bottom));
            bool down=IsDown(packet.Message), up=IsUp(packet.Message);
            int bit=ButtonBit(packet.Message,packet.Data);
            var status=sink.Send(new PointerPacket(packet.Message,packet.Screen,client,packet.Flags,packet.Data,packet.Epoch,packet.Gesture,geometry,packet.Sequence),point);
            if (status!=PointerPostStatus.Posted) {
                // A failed post must not leave a half-open gesture, and a local
                // rejection is never evidence of delivery.
                if (_openGesture!=0 || _postedButtons!=0 || down) CancelPointer("post_"+StatusName(status));
                else LogManager.Log("event=world_pointer_reject reason="+StatusName(status)+" msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence);
                return;
            }
            if(down) {
                _inputTarget=rootWindow; _postedButtons|=bit;
                _focus?.Invoke();
            }
            if(down || up) LogManager.Log("event=world_pointer_posted msg=0x"+packet.Message.ToString("X")+" seq="+packet.Sequence
                +" epoch="+packet.Epoch+" gesture="+packet.Gesture+" geo="+geometry+" x="+point.X+" y="+point.Y
                +" source="+bounds.Right+"x"+bounds.Bottom+" session="+((sink as NativePointerBridge)?.SessionIdentity.ToString() ?? "fixture")+" consumed="+sink.EndpointConsumedSeq);
            if(up) { _postedButtons&=~bit; if(_postedButtons==0) _openGesture=0; }
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
            if(!Visible || IsDisposed || _renewing) return;
            Point screen=Cursor.Position;
            if(WindowFromPoint(screen)==Handle)
                Enqueue(new PointerPacket(0x200,screen,PointToClient(screen),_physicalButtons,0,_inputEpoch,_openGesture,_geometryVersion,NextSequence()));
        }
        // Publish the atomic floor and a persistent release ticket before the
        // advisory cancel data packet. Broker control wakes the endpoint after
        // post failure. Already-admitted original calls are retired separately.
        internal void CancelPointer(string reason="explicit")
        {
            if(_renewing)return;
            _workGeneration++;_posted=false;_queue.Clear();
            if(_inputEpoch>=_epochLimit || _sequence>=_sequenceLimit){BeginRenewal();return;}
            uint epoch=++_inputEpoch;
            bool floor=_bridge.RaiseMinEpoch(epoch);
            bool had=_inputTarget!=IntPtr.Zero || _inside || _postedButtons!=0 || _physicalButtons!=0 || _openGesture!=0;
            _physicalButtons=_postedButtons=0; _inputTarget=IntPtr.Zero; _inside=false; _openGesture=0;
            if (had) {
                var packet=new PointerPacket(0x1F,Point.Empty,Point.Empty,0,0,epoch,0,_geometryVersion,NextSequence());
                var status=_bridge.Send(packet,new Point(-1,-1));
                LogManager.Log("event=world_pointer_cancel epoch="+epoch+" seq="+packet.Sequence+" reason="+reason
                    +" floor="+floor+" post="+StatusName(status)+" consumed="+_bridge.EndpointConsumedSeq);
            } else {
                LogManager.Log("event=world_pointer_cancel epoch="+epoch+" reason="+reason+" floor="+floor+" post=none");
            }
        }
        private static bool IsDown(int m) => m==0x201 || m==0x204 || m==0x207 || m==0x20B;
        private static bool IsUp(int m) => m==0x202 || m==0x205 || m==0x208 || m==0x20C;
        private static int ButtonBit(int m,uint data) => m>=0x20B && m<=0x20D ? ((data>>16)==1 ? 32 : 64) : m>=0x207 && m<=0x209 ? 16 : m>=0x204 && m<=0x206 ? 2 : 1;
        protected override void OnVisibleChanged(EventArgs e) { if(!Visible)CancelPointer("hidden"); base.OnVisibleChanged(e); }
        protected override void WndProc(ref Message m)
        {
            if(m.Msg==0x84){m.Result=new IntPtr(1);return;}
            if(m.Msg==0x21){m.Result=new IntPtr(3);return;}
            if(m.Msg==0x14){m.Result=new IntPtr(1);return;}
            base.WndProc(ref m);
        }
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left,Top,Right,Bottom; }
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [DllImport("user32.dll")] private static extern short GetKeyState(int key);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll",SetLastError=true)] private static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint color,byte alpha,uint flags);
    }
}
