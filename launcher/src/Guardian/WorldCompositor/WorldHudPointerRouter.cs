using System;
using System.Collections.Generic;
using System.Drawing;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Only presentation/input ownership lives here. The domain captures and checks
    // its own immutable target identity before dispatching an existing command.
    internal interface IWorldHudInput
    {
        object HitTest(Point screen);
        object HitTestWheel(Point screen) => HitTest(screen);
        object RetainPointerTarget(object pressedTarget,Point screen) => null;
        void Dispatch(int message,Point screen,uint data,object target);
        void Cancel();
    }

    internal sealed class WorldHudPointerRouter
    {
        private readonly Action<Action> _post;
        private readonly Queue<Pending> _queue=new();
        private readonly record struct Pending(int Message,Point Screen,uint Data,object Target);
        private Pending? _move;
        private IWorldHudInput _input;
        private object _pressedTarget;
        private int _held,_releaseBarrier;
        private bool _hover,_scheduled;
        private long _generation;
        internal const int Capacity=256;
        internal bool IsDragging => _held!=0 || _releaseBarrier!=0;

        internal WorldHudPointerRouter(Action<Action> post) => _post=post;
        internal void SetInput(IWorldHudInput input)
        {
            if(ReferenceEquals(input,_input))return;
            Cancel();_input=input;
        }
        internal void ObserveReleased(int physicalButtons)
        {
            // A release may occur while this window is hidden. A later fresh down
            // is admitted only after the physical all-up boundary was observed.
            if(physicalButtons==0)_releaseBarrier=0;
        }
        internal void RequireRelease(int physicalButtons) => _releaseBarrier|=physicalButtons;
        internal bool TryRoute(int message,Point screen,uint data,bool flashDragging)
        {
            int bit=ButtonBit(message,data);
            if(_releaseBarrier!=0)
            {
                if(IsDown(message))_releaseBarrier|=bit;
                if(IsUp(message))_releaseBarrier&=~bit;
                return true;
            }
            if(flashDragging && _held==0) { Leave();return false; }
            object target=_held!=0 && _pressedTarget!=null?_input?.RetainPointerTarget(_pressedTarget,screen):null;
            target ??= message==0x20A ? _input?.HitTestWheel(screen) : _input?.HitTest(screen);
            if(_held==0 && target==null) { Leave();return false; }
            if(IsDown(message) && _held==0)_pressedTarget=target;
            if(IsDown(message))_held|=bit;
            if(IsUp(message))_held&=~bit;
            if(_held==0)_pressedTarget=null;
            _hover=target!=null;
            Enqueue(new Pending(message,screen,data,target));
            return true;
        }
        internal void Leave()
        {
            if(!_hover)return;
            _hover=false;Enqueue(new Pending(0x2A3,Point.Empty,0,null));
        }
        internal void Cancel()
        {
            ++_generation;_scheduled=false;_queue.Clear();_move=null;
            _releaseBarrier|=_held;_held=0;_hover=false;_pressedTarget=null;
            var input=_input;
            if(input!=null)_post(input.Cancel);
        }
        private void Enqueue(Pending packet)
        {
            if(packet.Message==0x200)_move=packet;
            else
            {
                if(_queue.Count+(_move.HasValue?1:0)>=Capacity) { Cancel();return; }
                if(_move is {} move) { _queue.Enqueue(move);_move=null; }
                _queue.Enqueue(packet);
            }
            if(_scheduled)return;
            _scheduled=true;long generation=_generation;
            _post(()=>Drain(generation));
        }
        private void Drain(long generation)
        {
            if(generation!=_generation)return;
            _scheduled=false;
            try
            {
                while(generation==_generation && _queue.TryDequeue(out var packet))Deliver(packet);
                if(generation==_generation && _move is {} move) { _move=null;Deliver(move); }
            }
            catch(Exception error)
            {
                LogManager.Log("event=world_hud_input_rejected error="+error.GetType().Name);
                Cancel();
            }
        }
        private void Deliver(Pending packet) => _input?.Dispatch(packet.Message,packet.Screen,packet.Data,packet.Target);
        internal static bool IsDown(int message) => message is 0x201 or 0x204 or 0x207 or 0x20B;
        internal static bool IsUp(int message) => message is 0x202 or 0x205 or 0x208 or 0x20C;
        internal static int ButtonBit(int message,uint data) => message>=0x20B && message<=0x20D
            ? ((data>>16)==1?32:64) : message>=0x207 && message<=0x209?16:message>=0x204 && message<=0x206?2:1;
    }
}
