/** Instance-local mask history installed ONLY in a newly attached CF6 controlled hero's initObject. */
class org.flashNight.arki.scene.Cf6ActorMaskState {
    private static var factoryMarker:Object={};
    private static var nativeMethod:Function=MovieClip.prototype.setMask;

    public static function prepare(world:MovieClip,identity:Object,name:String,init:Object):Object {
        if(world==undefined || identity==null || world.__stageReturnWorldIdentity!==identity
                || typeof name!="string" || name=="" || init.setMask!=undefined
                || init.__cf6ActorMaskState!=undefined) return init;
        var result:Object={};
        for(var key:String in init) result[key]=init[key];
        var state:Object={factory:factoryMarker,world:world,worldIdentity:identity,name:name,
            birth:{},bound:false,knownNone:true,calls:0,nativeCallback:nativeMethod};
        state.wrapper=makeWrapper(state);
        result.__cf6ActorMaskState=state;result.setMask=state.wrapper;
        return result;
    }
    private static function makeWrapper(state:Object):Function {
        return function() {
            return org.flashNight.arki.scene.Cf6ActorMaskState.forward(this,state,arguments);
        };
    }
    /** No catch: the native return value and exception propagate unchanged. */
    public static function forward(receiver:Object,state:Object,args:Object) {
        state.knownNone=false;
        var sequence:Number=++state.calls;
        var result=state.nativeCallback.apply(receiver,args);
        if(state.calls===sequence && receiver.__cf6ActorMaskState===state
                && receiver.setMask===state.wrapper && result===true && args[0]===null)
            state.knownNone=true;
        return result;
    }
    /** Bind once after attachMovie returns; never adopts an already-existing unknown clip. */
    public static function bind(actor:MovieClip,init:Object):Boolean {
        var state:Object=init.__cf6ActorMaskState;
        if(state.factory!==factoryMarker || state.bound!==false
                || actor.__cf6ActorMaskState!==state || actor.setMask!==state.wrapper
                || state.nativeCallback!==nativeMethod || actor._name!==state.name
                || actor._parent!==state.world || state.world.__stageReturnWorldIdentity!==state.worldIdentity) return false;
        state.bound=true;state.actor=actor;
        return true;
    }
    public static function isKnownNone(actor:MovieClip):Boolean {
        var state:Object=actor.__cf6ActorMaskState;
        if(state.factory===factoryMarker && actor.setMask!==state.wrapper) state.knownNone=false;
        return actor._name!=undefined && state.factory===factoryMarker && state.bound===true
            && state.knownNone===true && actor.setMask===state.wrapper
            && state.nativeCallback===nativeMethod && state.actor===actor
            && actor._name===state.name && actor._parent===state.world
            && state.world.__stageReturnWorldIdentity===state.worldIdentity;
    }
    public static function identity(actor:MovieClip):Object {
        return isKnownNone(actor) ? actor.__cf6ActorMaskState.birth : null;
    }
}
