stop();
Stage.scaleMode = "showAll";
Stage.align = "TL";
var probeFrame:Number = 0;
var hoverA:Boolean = false;
var hoverB:Boolean = false;
var serial:Number = 0;
var connected:Boolean = false;
var sock:XMLSocket = new XMLSocket();
var pressId:Number = 0;
var pressCommits:Number = 0;
var releaseCommits:Number = 0;
var outsideCommits:Number = 0;
var dragCommits:Number = 0;
var keyCommits:Number = 0;
var deferredCommits:Number = 0;
var globalDown:Number = 0;
var globalUp:Number = 0;
var pendingCommits:Array = [];
var eventPressId:Number = 0;
function emit(eventName:String, targetName:String):Void {
    if (!connected) return;
    serial++;
    sock.send("{\"seq\":" + serial + ",\"timer\":" + getTimer() + ",\"frame\":" + probeFrame + ",\"event\":\"" + eventName + "\",\"target\":\"" + targetName + "\",\"x\":" + _root._xmouse + ",\"y\":" + _root._ymouse + ",\"hoverA\":" + hoverA + ",\"hoverB\":" + hoverB + ",\"pressId\":" + eventPressId + ",\"pressCommits\":" + pressCommits + ",\"releaseCommits\":" + releaseCommits + ",\"outsideCommits\":" + outsideCommits + ",\"dragCommits\":" + dragCommits + ",\"keyCommits\":" + keyCommits + ",\"deferredCommits\":" + deferredCommits + ",\"globalDown\":" + globalDown + ",\"globalUp\":" + globalUp + "}");
}
function paint(mc:MovieClip, active:Boolean):Void {
    mc.clear(); mc.beginFill(active ? 0x00DD55 : 0x336699, 100);
    mc.moveTo(0,0); mc.lineTo(160,0); mc.lineTo(160,70); mc.lineTo(0,70); mc.lineTo(0,0); mc.endFill();
}
function makeButton(id:String, xpos:Number):Void {
    var mc:MovieClip = _root.createEmptyMovieClip(id, _root.getNextHighestDepth());
    mc._x = xpos; mc._y = 120; paint(mc,false);
    mc.onRollOver = function():Void { if(this._name=="A") hoverA=true; else hoverB=true; paint(this,true); emit("over",this._name); };
    mc.onRollOut = function():Void { if(this._name=="A") hoverA=false; else hoverB=false; paint(this,false); emit("out",this._name); };
    mc.onPress = function():Void { this.pressId = ++pressId; eventPressId = this.pressId; pressCommits++; emit("press",this._name); };
    mc.onRelease = function():Void { eventPressId = this.pressId; releaseCommits++; pendingCommits.push({due:probeFrame+2, pressId:eventPressId, name:this._name}); emit("release",this._name); };
    mc.onReleaseOutside = function():Void { eventPressId = this.pressId; outsideCommits++; pendingCommits.push({due:probeFrame+2, pressId:eventPressId, name:this._name}); emit("releaseOutside",this._name); };
    mc.onDragOut = function():Void { eventPressId=this.pressId; hoverA=false; hoverB=false; dragCommits++; emit("dragOut",this._name); };
    mc.onDragOver = function():Void { eventPressId=this.pressId; if(this._name=="A") hoverA=true; else hoverB=true; emit("dragOver",this._name); };
}
makeButton("A",80); makeButton("B",350);
var mouseObserver:Object = {};
mouseObserver.onMouseDown = function():Void { globalDown++; emit("globalDown",""); };
mouseObserver.onMouseUp = function():Void { globalUp++; emit("globalUp",""); };
Mouse.addListener(mouseObserver);
var keyObserver:Object = {};
keyObserver.onKeyDown = function():Void { if(Key.getCode()==32) {keyCommits++; emit("keyCommit","");} };
Key.addListener(keyObserver);
_root.createTextField("label", 20, 30, 20, 580, 75);
_root.label.text = "Disposable Flash pointer probe - no game or saves\nA: left rectangle / B: right rectangle";
sock.onConnect = function(ok:Boolean):Void { connected=ok; emit("ready",""); };
sock.connect("127.0.0.1",32187);
_root.onEnterFrame = function():Void {
    probeFrame++;
    for(var i:Number=pendingCommits.length-1;i>=0;i--) {
        var job:Object=pendingCommits[i];
        if(job.due<=probeFrame) {eventPressId=job.pressId;deferredCommits++;emit("deferredCommit",job.name);pendingCommits.splice(i,1);}
    }
    if(probeFrame % 3 == 0)emit("sample","");
};
