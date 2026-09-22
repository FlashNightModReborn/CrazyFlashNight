using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed class WorldCompositionSurface : Form
    {
        private readonly Func<IntPtr> _getFlash;
        private readonly Action _focus;
        private readonly Queue<PointerPacket> _queue=new Queue<PointerPacket>();
        private readonly NativePointerBridge _bridge;
        private int _physicalButtons, _deliveredButtons;
        private bool _posted, _draining, _inside;
        private IntPtr _inputTarget;
        private PointerPacket? _pendingMove;
        private readonly record struct PointerPacket(int Message,Point Point,int Flags,uint Data);
        internal bool IsDragging => _physicalButtons!=0 || _deliveredButtons!=0 || _queue.Count!=0;
        internal WorldCompositionSurface(Func<IntPtr> getFlash,Action focus,NativePointerBridge bridge)
        {
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
                if (pid!=(uint)Environment.ProcessId && pid!=flashPid) { QueueCancel(); return false; }
            } else if (!owned) {
                if (_inside) { _inside=false; Enqueue(new PointerPacket(0x2A3,Point.Empty,0,0)); }
                return false;
            }
            _inside=true;
            int bit=ButtonBit(message,mouseData);
            if (IsDown(message)) _physicalButtons|=bit;
            if (IsUp(message)) _physicalButtons&=~bit;
            int flags=_physicalButtons;
            if ((GetKeyState(0x10)&0x8000)!=0) flags|=4;
            if ((GetKeyState(0x11)&0x8000)!=0) flags|=8;
            Enqueue(new PointerPacket(message,PointToClient(screen),flags,mouseData));
            // Consuming a low-level MOVE also freezes the OS cursor itself. Let motion
            // update the physical pointer; the surface's ordinary WndProc does not
            // forward it. Button/wheel edges are exclusively delivered by this queue.
            return message!=0x200;
        }
        private void Enqueue(PointerPacket packet)
        {
            // Native cursor motion stays immediate in the shared hook. Flash receives
            // at most one hover/motion update per render tick; buttons flush it first.
            if (packet.Message==0x200) { _pendingMove=packet; return; }
            if (_pendingMove.HasValue) { _queue.Enqueue(_pendingMove.Value); _pendingMove=null; }
            _queue.Enqueue(packet);
            if (_posted || _draining) return;
            _posted=true; BeginInvoke(new Action(Drain));
        }
        internal void FlushMove()
        {
            if (_draining || !_pendingMove.HasValue) return;
            var move=_pendingMove.Value; _pendingMove=null; Deliver(move);
        }
        private void Drain()
        {
            _posted=false;
            if (_draining || IsDisposed) return;
            _draining=true;
            try { while (_queue.Count>0) Deliver(_queue.Dequeue()); }
            finally { _draining=false; }
        }
        private void Deliver(PointerPacket packet)
        {
            if (packet.Message==0x1F) { CancelPointer(); return; }
            IntPtr rootWindow=_getFlash();
            if (rootWindow==IntPtr.Zero || !IsWindow(rootWindow)) return;
            if (packet.Message==0x2A3) {
                if (_deliveredButtons==0) _bridge.Send(0x200,new Point(-1,-1),0);
                return;
            }
            if (!Visible || !GetClientRect(rootWindow,out Rect bounds) || bounds.Right<1 || bounds.Bottom<1) return;
            Point point=WorldPointerMapper.Map(packet.Point,ClientSize,new Size(bounds.Right,bounds.Bottom));
            bool down=IsDown(packet.Message), up=IsUp(packet.Message);
            int bit=ButtonBit(packet.Message,packet.Data);
            if(down) {
                _inputTarget=rootWindow; _deliveredButtons|=bit;
                _focus?.Invoke();
            }
            _bridge.Send(packet.Message,point,packet.Flags,packet.Data);
            if(down || up) LogManager.Log("event=world_pointer message="+packet.Message+" x="+point.X+" y="+point.Y+" source="+bounds.Right+"x"+bounds.Bottom);
            if(up) _deliveredButtons&=~bit;
        }
        internal void RefreshPointer()
        {
            if(!Visible || IsDisposed) return;
            Point screen=Cursor.Position;
            if(WindowFromPoint(screen)==Handle)
                _pendingMove=new PointerPacket(0x200,PointToClient(screen),_physicalButtons,0);
        }
        private void QueueCancel() { _physicalButtons=0; _inside=false; Enqueue(new PointerPacket(0x1F,Point.Empty,0,0)); }
        internal void CancelPointer()
        {
            _queue.Clear();
            _pendingMove=null;
            if(_inputTarget!=IntPtr.Zero || _inside) _bridge.Send(0x1F,new Point(-1,-1),0);
            _physicalButtons=_deliveredButtons=0; _inputTarget=IntPtr.Zero; _inside=false;
        }
        private static bool IsDown(int m) => m==0x201 || m==0x204 || m==0x207 || m==0x20B;
        private static bool IsUp(int m) => m==0x202 || m==0x205 || m==0x208 || m==0x20C;
        private static int ButtonBit(int m,uint data) => m>=0x20B && m<=0x20D ? ((data>>16)==1 ? 32 : 64) : m>=0x207 && m<=0x209 ? 16 : m>=0x204 && m<=0x206 ? 2 : 1;
        protected override void OnVisibleChanged(EventArgs e) { if(!Visible)CancelPointer(); base.OnVisibleChanged(e); }
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
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll",SetLastError=true)] private static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint color,byte alpha,uint flags);
    }
}
