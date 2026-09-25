// No game imports: install and verify boundaries before a Host-authorized load.
stop();
Stage.scaleMode = "showAll"; Stage.align = "TL";
var b1StorageDenials:Number = 0, b1InputDenials:Number = 0, b1SocketDenials:Number = 0;
var b1Loaded:Boolean = false, b1Connected:Boolean = false;
var b1DenyStorage:Function = function(name:String):Object { b1StorageDenials++; return null; };
SharedObject.getLocal = b1DenyStorage;
ASSetPropFlags(SharedObject, "getLocal", 7);
var b1DenyKey:Function = function(code:Number):Boolean { b1InputDenials++; return false; };
var b1DenyListener:Function = function(listener:Object):Boolean { b1InputDenials++; return false; };
ASSetPropFlags(Key, "isDown,addListener", 0, 4);
ASSetPropFlags(Mouse, "addListener", 0, 4);
Key.isDown = b1DenyKey; Key.addListener = b1DenyListener; Mouse.addListener = b1DenyListener;
ASSetPropFlags(Key, "isDown,addListener", 7); ASSetPropFlags(Mouse, "addListener", 7);
_global.__b1DenySharedObject = b1DenyStorage;
_global.__b1InputBoundaryIntact = function():Boolean {
    return SharedObject.getLocal === b1DenyStorage && Key.isDown === b1DenyKey
        && Key.addListener === b1DenyListener && Mouse.addListener === b1DenyListener;
};
_global.__cf7InputIsolationBootstrapV1 = {v:1, mode:"closed-legacy-drivers", module:"RuntimeWorld.swf"};
ASSetPropFlags(_global.__cf7InputIsolationBootstrapV1, null, 7);
ASSetPropFlags(_global, "__cf7InputIsolationBootstrapV1,__b1DenySharedObject,__b1InputBoundaryIntact", 7);
var b1Wire:XMLSocket = new XMLSocket();
_global.__b1Wire = b1Wire;
_global.__b1Emit = function(message:String):Void { if (b1Connected) b1Wire.send(message); };
_global.__b1TransportOpen = function():Boolean { return b1Connected; };
ASSetPropFlags(_global, "__b1Wire,__b1Emit,__b1TransportOpen", 7);
var b1DenyConnect:Function = function(host:String, port:Number):Boolean { b1SocketDenials++; return false; };
b1Wire.onConnect = function(ok:Boolean):Void {
    if (!ok) return;
    b1Connected = true;
    // The one exact-process channel is already connected. All later attempts,
    // including reconnect, are denied; a lost channel requires a fresh VM.
    XMLSocket.prototype.connect = b1DenyConnect;
    ASSetPropFlags(XMLSocket.prototype, "connect", 7);
    var checkSocket:XMLSocket = new XMLSocket();
    var boundary:Boolean = _global.__b1InputBoundaryIntact() && checkSocket.connect === b1DenyConnect;
    b1Wire.send('{"kind":"BOOTSTRAP_READY","boundaryIntact":' + boundary + ',"gameLoaded":false,"inputGranted":false}');
};
b1Wire.onData = function(message:String):Void {
    b1Wire.send('{"kind":"BOOTSTRAP_COMMAND","connected":' + Boolean(b1Connected) + ',"transportOpen":' + _global.__b1TransportOpen() + ',"loadMatches":' + (message === "LOAD_B1_RUNTIME") + '}');
    if (!b1Connected) return;
    if (!b1Loaded) {
        if (message !== "LOAD_B1_RUNTIME" || !_global.__b1InputBoundaryIntact()
            || XMLSocket.prototype.connect !== b1DenyConnect) return;
        b1Loaded = true;
        b1Wire.send('{"kind":"BOOTSTRAP_LOADING","gameLoaded":false,"inputGranted":false}');
        var world:MovieClip = _root.createEmptyMovieClip("runtimeWorld", 1); world._lockroot = true;
        world.loadMovie("RuntimeWorld.swf");
        return;
    }
    if (typeof _global.__b1Receive == "function") _global.__b1Receive(message);
};
b1Wire.onClose = function():Void {
    b1Connected = false;
    if (typeof _global.__b1Cancel == "function") _global.__b1Cancel("transport_lost");
};
if (_global.__b1InputBoundaryIntact()) b1Wire.connect("127.0.0.1",32188);
