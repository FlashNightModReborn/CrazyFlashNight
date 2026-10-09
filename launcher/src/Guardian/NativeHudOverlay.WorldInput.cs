using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian;

public partial class NativeHudOverlay
{
    internal IWorldHudInput CreateWorldInput(Control anchor) => new MainHudInput(this,anchor,()=>SharedInputAvailable);

    internal sealed class MainHudInput : IWorldHudInput
    {
        private readonly NativeHudOverlay _hud;
        private readonly Control _anchor;
        private readonly Func<bool> _available;
        private sealed record Hit(INativeHudWidget Widget,object Action,long Generation,Rectangle Viewport,bool Wheel);
        private Hit _down,_capture;
        private INativeHudWidget _hover;
        internal MainHudInput(NativeHudOverlay hud,Control anchor,Func<bool> available)
        { _hud=hud;_anchor=anchor;_available=available; }
        private Rectangle Viewport=>_anchor.RectangleToScreen(_anchor.ClientRectangle);

        public object HitTest(Point screen)
        {
            if(!_available())return null;
            if(_capture!=null && Current(_capture,screen))return _capture;
            var widget=_hud.HitTestScreen(screen);
            return widget==null?null:Capture(widget,screen,false);
        }
        public object RetainPointerTarget(object pressedTarget,Point screen)
        {
            if(pressedTarget is not Hit hit || !_available() || hit.Generation!=_hud._pointerInputGeneration || hit.Viewport!=Viewport
                || !hit.Widget.Visible || hit.Widget is not INativeHudPointerSnapshot snapshot)return null;
            return snapshot.IsCapturedPointerCurrent(hit.Action)?hit:null;
        }
        public object HitTestWheel(Point screen)
        {
            if(!_available())return null;
            INativeHudWidget[] widgets;
            lock(_hud._widgetsLock)widgets=_hud._widgets.ToArray();
            for(int i=widgets.Length-1;i>=0;i--)
            {
                var widget=widgets[i];if(!widget.Visible)continue;
                var target=(widget as INativeHudPointerSnapshot)?.CaptureWheelTarget(screen);
                if(target!=null)return new Hit(widget,target,_hud._pointerInputGeneration,Viewport,true);
                // A higher interactive surface blocks a lower wheel consumer.
                if(widget.TryHitTest(screen))return Capture(widget,screen,false);
            }
            return null;
        }
        private Hit Capture(INativeHudWidget widget,Point screen,bool wheel)
            =>new(widget,(widget as INativeHudPointerSnapshot)?.CapturePointerTarget(screen),_hud._pointerInputGeneration,Viewport,wheel);
        private bool Current(Hit hit,Point screen)
        {
            if(!_available() || hit.Generation!=_hud._pointerInputGeneration || hit.Viewport!=Viewport || !hit.Widget.Visible)return false;
            lock(_hud._widgetsLock)if(!_hud._widgets.Contains(hit.Widget))return false;
            if(hit.Widget is not INativeHudPointerSnapshot snapshot || hit.Action==null)return false;
            if(ReferenceEquals(hit,_capture) && snapshot.IsCapturedPointerCurrent(hit.Action))return true;
            object current=hit.Wheel?snapshot.CaptureWheelTarget(screen):snapshot.CapturePointerTarget(screen);
            return Equals(hit.Action,current) && (hit.Wheel || ReferenceEquals(_hud.HitTestScreen(screen),hit.Widget));
        }
        public void Dispatch(int message,Point screen,uint data,object target)
        {
            if(message==0x2A3) { SetHover(null,screen);return; }
            if(target is not Hit hit || !Current(hit,screen))
            {
                if(message!=0x200)Cancel();
                else SetHover(null,screen);
                return;
            }
            if(message==0x20A)
            {
                if(hit.Wheel && hit.Widget is INativeHudWheelConsumer wheel)
                {
                    CancelDown();wheel.OnMouseWheel(screen,unchecked((short)(data>>16)));
                }
                return;
            }
            SetHover(hit.Widget,screen);
            if(message==0x200)
            {
                hit.Widget.OnMouseEvent(Args(screen,MouseButtons.None),MouseEventKind.Move);return;
            }
            // All current main-HUD actions use the left button. Other edges are
            // absorbed by their visible surface without inventing a left action.
            if(message==0x201)
            {
                CancelDown();
                if(!Current(hit,screen))return;
                _down=hit;
                hit.Widget.OnMouseEvent(Args(screen,MouseButtons.Left),MouseEventKind.Down);
                if(hit.Widget is INativeHudPointerSnapshot snapshot && snapshot.IsCapturedPointerCurrent(hit.Action))_capture=hit;
            }
            else if(message==0x202)
            {
                var down=_down;
                if(down==null || down!=hit) { CancelDown();return; }
                _down=null;_capture=null;
                var args=Args(screen,MouseButtons.Left);
                hit.Widget.OnMouseEvent(args,MouseEventKind.Up);
                // Up can close, replace or advance a session. A subsequent Click
                // must never act on that replacement (or fire a close twice).
                if(((INativeHudPointerSnapshot)hit.Widget).NeedsPointerClick && Current(hit,screen))
                    hit.Widget.OnMouseEvent(args,MouseEventKind.Click);
            }
        }
        private static MouseEventArgs Args(Point point,MouseButtons buttons)=>new(buttons,1,point.X,point.Y,0);
        private void SetHover(INativeHudWidget next,Point screen)
        {
            if(ReferenceEquals(next,_hover))return;
            var old=_hover;_hover=next;
            old?.OnMouseEvent(Args(screen,MouseButtons.None),MouseEventKind.Leave);
            next?.OnMouseEvent(Args(screen,MouseButtons.None),MouseEventKind.Enter);
        }
        private void CancelDown()
        {
            var down=_down;_down=null;_capture=null;
            down?.Widget.OnMouseEvent(Args(Point.Empty,MouseButtons.None),MouseEventKind.Cancel);
        }
        public void Cancel() { CancelDown();SetHover(null,Point.Empty); }
    }
}
