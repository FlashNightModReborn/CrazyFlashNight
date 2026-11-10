import org.flashNight.neur.Event.Delegate;
import org.flashNight.aven.Coordinator.EventCoordinator;

/** Qualification-only root HTTP pulse. No game mutations or frame acceleration. */
class org.flashNight.neur.Server.Issue205SourceProbe {
    private static var _timer:Number;
    private static var _port:Number;
    private static var _enabled:Boolean=false;
    private static var _configured:Boolean=false;
    private static var _busy:Boolean=false;
    private static var _seq:Number=0;
    private static var _serial:Number=0;
    private static var _ownerSeq:Number=0;
    private static var _attach:Number=0;
    private static var _unload:Number=0;
    private static var _dispose:Number=0;
    private static var _counts:Array=[0,0,0,0,0,0,0,0,0,0,0];
    private static var _order:Array=[0,0,0,0,0,0,0,0,0,0,0];
    public static function install():Void {
        if (_timer!=undefined) return;
        _timer=setInterval(Delegate.create(Issue205SourceProbe,pulse),500);
    }
    public static function mark(index:Number):Void {
        if (!_enabled) return;
        _counts[index]++;_order[index]=++_serial;
    }
    public static function attached(world:MovieClip):Void {
        if (!_enabled || world==null) return;
        var owner:Object={id:++_ownerSeq,unloaded:false};
        world.__issue205Owner=owner;
        _global.ASSetPropFlags(world,["__issue205Owner"],1,false);
        owner.unloadCallback=Delegate.createWithParams(owner,onWorldUnload,[owner]);
        EventCoordinator.addUnloadCallback(world,owner.unloadCallback);
        _attach++;
    }
    private static function onWorldUnload(owner:Object):Void {
        // Delegate owns a plain object, never a saved AVM1 MovieClip reference.
        if (owner.unloaded===true) return;
        owner.unloaded=true;
        org.flashNight.neur.Server.Issue205SourceProbe.noteUnload();
    }
    public static function noteUnload():Void { if (_enabled) _unload++; }
    public static function disposing():Void { if (_enabled) _dispose++; }
    private static function configuration(raw:String):Void {
        _busy=false;_configured=true;
        if (raw==null || raw.indexOf('"enabled":true')<0) {
            clearInterval(_timer);_timer=undefined;return;
        }
        _enabled=true;
        if (_root.gameworld!=undefined) attached(_root.gameworld);
    }
    private static function acknowledged(raw:String):Void { _busy=false; }
    private static function pulse():Void {
        if (_busy) return; // At most one outstanding request, even on HTTP loss.
        var port:Number=Number(_root.server.currentPort);
        if (!(port>0)) return;
        if (!_configured) {
            _port=port;_busy=true;
            var config:LoadVars=new LoadVars();
            config.onData=Delegate.create(Issue205SourceProbe,configuration);
            config.load("http://localhost:"+_port+"/issue205/config");return;
        }
        if (!_enabled) return;
        var world:MovieClip=_root.gameworld;
        var present:Boolean=world!=undefined && world._name!=undefined;
        var p:LoadVars=new LoadVars();
        p.seq=++_seq;p.timer=getTimer();p.world=present?1:0;
        p.owner=present && world.__issue205Owner!=undefined?world.__issue205Owner.id:0;
        p.attach=_attach;p.unload=_unload;p.dispose=_dispose;
        p.gameFrame=Number(_root.帧计时器.当前帧数);p.serverFrame=Number(_root.server.currentFrame);
        p.battle=_root.当前为战斗地图===true?1:0;
        p.paused=_root.暂停===true || _root._webPanelPauseLease!=undefined
            || world.__stageIntroExecutionHeld===true || world.__combatAdmitted===false?1:0;
        p.transition=_root.场景转换中===true || _root.淡出动画.__returnFadeActive===true?1:0;
        p.scene=present?String(world.场景名).substr(0,96):"none";
        p.counts=_counts.join(",");p.order=_order.join(",");
        p.onData=Delegate.create(Issue205SourceProbe,acknowledged);
        _busy=true;p.sendAndLoad("http://localhost:"+_port+"/issue205/source",p,"POST");
    }
    /** Test fixture reads values without installing HTTP or creating a world. */
    public static function inspectForTest():Object {return {counts:_counts.concat(),order:_order.concat(),attach:_attach,unload:_unload,dispose:_dispose};}
    public static function enableForTest(value:Boolean):Void {_enabled=value;}
}
