#nullable enable
using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

// Reuses the widget's exact target checks and controller. Neither queued pointer
// work nor a presentation restart can turn an old press into a new domain action.
internal sealed class PlayerHudPointerInput : IWorldHudInput
{
    private readonly PlayerHudBottomWidget _widget;
    private readonly Func<bool> _available;
    private sealed record Hit(PlayerHudTarget Target,Rectangle Bounds);
    private Hit? _down;
    internal PlayerHudPointerInput(PlayerHudBottomWidget widget,Func<bool> available)
    { _widget=widget;_available=available; }

    public object? HitTest(Point screen)
    {
        if(!_available())return null;
        var target=_widget.CapturePointerTarget(screen);
        return target==null?null:new Hit(target,_widget.ScreenBounds);
    }
    public void Dispatch(int message,Point screen,uint data,object? target)
    {
        if(message==0x2A3) { Cancel();return; }
        if(target is not Hit hit || !_available() || hit.Bounds!=_widget.ScreenBounds
            || hit.Target!=_widget.CapturePointerTarget(screen)) { Cancel();return; }
        MouseButtons button=message is 0x201 or 0x202?MouseButtons.Left
            :message is 0x204 or 0x205?MouseButtons.Right
            :message is 0x207 or 0x208?MouseButtons.Middle:MouseButtons.None;
        var args=new MouseEventArgs(button,1,screen.X,screen.Y,0);
        if(message==0x200)_widget.OnMouseEvent(args,MouseEventKind.Move);
        else if(WorldHudPointerRouter.IsDown(message))
        {
            if(button==MouseButtons.Left)_down=hit;
            _widget.OnMouseEvent(args,MouseEventKind.Down);
        }
        else if(WorldHudPointerRouter.IsUp(message))
        {
            var down=_down;
            if(button==MouseButtons.Left)_down=null;
            if(button!=MouseButtons.Left || down==null || down!=hit) { Cancel();return; }
            _widget.OnMouseEvent(args,MouseEventKind.Up);
            _widget.OnMouseEvent(args,MouseEventKind.Click);
        }
    }
    public void Cancel()
    {
        _down=null;
        _widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None,0,0,0,0),MouseEventKind.Cancel);
    }
}
