// Cold capability experiment only. No imports, RSL, actors or game services.
stop();
Stage.scaleMode = "showAll";
var rejectedGets:Number = 0;
var denySharedObject:Function = function(name:String):Object {
    rejectedGets++;
    return null;
};
SharedObject.getLocal = denySharedObject;
var replaced:Boolean = SharedObject.getLocal === denySharedObject;
_global.__b1DenySharedObject = denySharedObject;
ASSetPropFlags(_global, "__b1DenySharedObject", 7);
if (replaced) {
    ASSetPropFlags(SharedObject, "getLocal", 7);
    // This invokes only our verified denial function, never the native getter.
    SharedObject.getLocal("B1_CAPABILITY_NO_STORAGE");
}
_global.__cf7InputIsolationBootstrapV1 = {v:1, mode:"closed-legacy-drivers", module:"BaseWorld.swf"};
ASSetPropFlags(_global, "__cf7InputIsolationBootstrapV1", 7);
ASSetPropFlags(_global.__cf7InputIsolationBootstrapV1, null, 7);
var reportWire:XMLSocket = new XMLSocket();
_global.__b1Emit = function(message:String):Void { reportWire.send(message); };
reportWire.onConnect = function(ok:Boolean):Void {
    if (!ok) return;
    reportWire.send('{"kind":"B1_COLD_CAPABILITY","sharedObjectGetterReplaced":' + replaced + ',"deniedCalls":' + rejectedGets + ',"gameLoaded":false,"inputGranted":false}');
    if (replaced) { var child:MovieClip = _root.createEmptyMovieClip("base", 1); child._lockroot = true; child.loadMovie("BaseWorld.swf"); }
};
reportWire.connect("127.0.0.1", 32188);
