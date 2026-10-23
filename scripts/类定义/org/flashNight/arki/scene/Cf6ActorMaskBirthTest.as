import org.flashNight.arki.scene.Cf6ActorMaskState;

/** Native attachMovie initObject/first-frame ordering, forwarding, and birth identity. */
class org.flashNight.arki.scene.Cf6ActorMaskBirthTest {
    private static var library:MovieClip;
    private static var watch:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var ready:Boolean;
    private static var done:Boolean;
    private static var ticks:Number;
    private static var passed:Number;
    private static var failed:Number;
    private static var originalNative:Function;
    public static var failureMarker:Object;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6ActorMaskBirth: "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=ticks=0;ready=done=false;originalNative=MovieClip.prototype.setMask;
        library=_root.createEmptyMovieClip("__cf6NativeMaskBirth",_root.getNextHighestDepth());library._visible=false;
        watch=_root.createEmptyMovieClip("__cf6NativeMaskBirthWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6ActorMaskBirthTest.tick();};
        loader=new MovieClipLoader();
        listener={onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6ActorMaskBirthTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6ActorMaskBirthTest.loadError(error);}};
        loader.addListener(listener);
        check(loader.loadClip("test-runners/cf6-actor-mask-known-none/MaskBirthProbe.swf",library),"load actual native birth fixture");
    }
    public static function loaded(mc:MovieClip):Void {
        if(done || ready || mc!==library) return;
        library.stop();library.__stageReturnWorldIdentity={};
        var mask:MovieClip=library.createEmptyMovieClip("probeMask",10);
        mask.beginFill(0xFFFFFF,100);mask.moveTo(8,0);mask.lineTo(16,0);mask.lineTo(16,16);mask.lineTo(8,16);mask.endFill();
        check(library._totalframes==1 && mask._width>0,"native library and mask are initialized");
        var original:Object={_x:0,_y:0,preserved:123};
        var init:Object=Cf6ActorMaskState.prepare(library,library.__stageReturnWorldIdentity,"plain",original);
        check(init!==original && original.setMask==undefined && init.preserved===123,"init preparation preserves caller fields without mutating caller object");
        var actor:MovieClip=library.attachMovie("Cf6MaskBirthPlain","plain",20,init);
        check(actor!=undefined && Cf6ActorMaskState.bind(actor,init),"plain native attach binds its own birth state");
        init=Cf6ActorMaskState.prepare(library,library.__stageReturnWorldIdentity,"masked",{});
        actor=library.attachMovie("Cf6MaskBirthSet","masked",21,init);
        check(actor!=undefined && Cf6ActorMaskState.bind(actor,init),"first-frame set native attach binds its birth state");
        init=Cf6ActorMaskState.prepare(library,library.__stageReturnWorldIdentity,"clearedActor",{});
        actor=library.attachMovie("Cf6MaskBirthClear","clearedActor",22,init);
        check(actor!=undefined && Cf6ActorMaskState.bind(actor,init),"first-frame clear native attach binds its birth state");
        ready=true;ticks=0;
    }
    public static function loadError(error:String):Void {check(false,"native fixture load "+error);finish();}
    public static function tick():Void {
        if(done) return;ticks++;
        if(!ready) {if(ticks>300) {check(false,"native load timeout");finish();}return;}
        if(ticks<3) return;
        var plain:MovieClip=library.plain,masked:MovieClip=library.masked,clear:MovieClip=library.clearedActor;
        check(plain.firstFrameSawState===true && masked.firstFrameSawState===true && clear.firstFrameSawState===true,
            "actual first-frame scripts see initObject wrapper before invoking setMask");
        check(Cf6ActorMaskState.isKnownNone(plain) && plain.__cf6ActorMaskState.calls==0,"new untouched actor is born-known-none");
        check(!Cf6ActorMaskState.isKnownNone(masked) && masked.firstFrameNativeReturn===true
            && masked.__cf6ActorMaskState.calls==1,"first-frame external mask is recorded and native return retained");
        check(Cf6ActorMaskState.isKnownNone(clear) && clear.firstFrameNativeReturn===true
            && clear.__cf6ActorMaskState.calls==1,"first-frame successful clear establishes known-none");
        var result=plain.setMask(library.probeMask);
        check(result===true && !Cf6ActorMaskState.isKnownNone(plain),"external actor mask immediately invalidates capture eligibility");
        result=plain.setMask(null);
        check(result===true && Cf6ActorMaskState.isKnownNone(plain),"native successful clear is tracked without synthetic mask calls");
        var wrapper:Function=plain.setMask;plain.setMask=function():Boolean {return false;};
        check(!Cf6ActorMaskState.isKnownNone(plain),"wrapper replacement invalidates history");
        plain.setMask=wrapper;
        check(!Cf6ActorMaskState.isKnownNone(plain),"restoring function does not retroactively certify unknown interval");
        plain.setMask(null);
        check(Cf6ActorMaskState.isKnownNone(plain),"actual clear re-establishes eligibility");
        var oldBirth:Object=Cf6ActorMaskState.identity(plain);plain.removeMovieClip();
        var init:Object=Cf6ActorMaskState.prepare(library,library.__stageReturnWorldIdentity,"plain",{});
        plain=library.attachMovie("Cf6MaskBirthPlain","plain",23,init);Cf6ActorMaskState.bind(plain,init);
        check(Cf6ActorMaskState.isKnownNone(plain) && Cf6ActorMaskState.identity(plain)!==oldBirth,"same-path native rebirth gets an independent ordinary identity");
        var custom:Object={setMask:function():Boolean {return false;}};
        check(Cf6ActorMaskState.prepare(library,library.__stageReturnWorldIdentity,"custom",custom)===custom,
            "preexisting custom init method is not overwritten");
        var unknown:MovieClip=library.createEmptyMovieClip("untracked",24);
        check(!Cf6ActorMaskState.isKnownNone(unknown),"old or untracked clips cannot be certified by reading them");
        var receiver:Object={},state:Object={knownNone:true,calls:0};
        receiver.__cf6ActorMaskState=state;receiver.setMask=function():Void {};state.wrapper=receiver.setMask;
        state.nativeCallback=function() {this.received=[arguments[0],arguments[1]];return "native-value";};
        result=Cf6ActorMaskState.forward(receiver,state,[null,73]);
        check(result==="native-value" && receiver.received[0]===null && receiver.received[1]===73
            && state.knownNone===false,"forward preserves receiver, argument list and non-Boolean return");
        failureMarker={};state.knownNone=true;
        state.nativeCallback=function() {throw org.flashNight.arki.scene.Cf6ActorMaskBirthTest.failureMarker;};
        try {Cf6ActorMaskState.forward(receiver,state,[]);check(false,"exception must propagate");}
        catch(error) {check(error===failureMarker && state.knownNone===false,"same exception propagates with unknown state retained");}
        check(MovieClip.prototype.setMask===originalNative,"global MovieClip prototype is unchanged");
        finish();
    }
    private static function finish():Void {
        if(done) return;done=true;
        loader.removeListener(listener);delete watch.onEnterFrame;watch.removeMovieClip();library.removeMovieClip();
        trace("Cf6ActorMaskBirthTest Tests Passed: "+passed);
        trace("Cf6ActorMaskBirthTest Tests Failed: "+failed);
        _root.cf6ActorMaskBirthComplete();
    }
}
