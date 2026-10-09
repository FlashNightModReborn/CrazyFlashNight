using System.Drawing;

namespace CF7Launcher.Guardian.WorldCompositor;

// One gesture queue, with the same front-to-back order as the composed rasters.
// Targets retain their actual consumer; delayed edges cannot be re-hit-tested
// into another HUD domain. Each domain still validates its own target identity.
internal sealed class WorldHudInputLayers : IWorldHudInput
{
    private readonly IWorldHudInput _front,_back;
    private IWorldHudInput _hover,_pressedOwner;
    private int _heldButtons;
    private sealed record Hit(IWorldHudInput Owner,object Target);
    internal WorldHudInputLayers(IWorldHudInput front,IWorldHudInput back) { _front=front;_back=back; }
    public object HitTest(Point screen)=>Capture(screen,false);
    public object HitTestWheel(Point screen)=>Capture(screen,true);
    public object RetainPointerTarget(object pressedTarget,Point screen)
    {
        if(pressedTarget is not Hit hit)return null;
        object retained=hit.Owner.RetainPointerTarget(hit.Target,screen);
        return retained==null?null:new Hit(hit.Owner,retained);
    }
    private object Capture(Point screen,bool wheel)
    {
        object target=wheel?_front.HitTestWheel(screen):_front.HitTest(screen);
        if(target!=null)return new Hit(_front,target);
        target=wheel?_back.HitTestWheel(screen):_back.HitTest(screen);
        return target==null?null:new Hit(_back,target);
    }
    public void Dispatch(int message,Point screen,uint data,object target)
    {
        var hit=target as Hit;
        var next=hit?.Owner;
        if(_hover!=next) { _hover?.Dispatch(0x2A3,screen,0,null);_hover=next; }
        if(WorldHudPointerRouter.IsDown(message))
        {
            if(_heldButtons==0)_pressedOwner=next;
            _heldButtons|=WorldHudPointerRouter.ButtonBit(message,data);
            if(_pressedOwner!=next) { _pressedOwner?.Cancel();_pressedOwner=null;return; }
        }
        if(WorldHudPointerRouter.IsUp(message))
        {
            int bit=WorldHudPointerRouter.ButtonBit(message,data);
            if((_heldButtons&bit)==0)return;
            _heldButtons&=~bit;
            var pressed=_pressedOwner;if(_heldButtons==0)_pressedOwner=null;
            if(pressed==null || pressed!=next) { pressed?.Cancel();next?.Cancel();return; }
        }
        if(hit!=null)hit.Owner.Dispatch(message,screen,data,hit.Target);
        else if(message!=0x200)Cancel();
    }
    public void Cancel() { _hover=null;_pressedOwner=null;_heldButtons=0;_front.Cancel();_back.Cancel(); }
}
