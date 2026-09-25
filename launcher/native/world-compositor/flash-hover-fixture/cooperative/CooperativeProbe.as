stop();
Stage.scaleMode="showAll";Stage.align="TL";
var sock:XMLSocket=new XMLSocket();
var connected:Boolean=false;
var session:String="";
var coverage:Number=1,ownerEpoch:Number=0,cancelTicket:Number=0,lastWire:Number=0,lastGesture:Number=0;
var serial:Number=0,frames:Number=0,childSeed:Number=0;
var domains:Array=[],jobs:Array=[];
var activeToken:Object=null;
var geometry:Number=1,readyDelay:Number=0;
var pendingReady:Object=null;
var logicalBegins:Number=0,logicalEnds:Number=0,logicalCommits:Number=0,rawCallbacks:Number=0;
var allClosed:Boolean=true,hoverA:Boolean=false,hoverB:Boolean=false;
function sendEvent(ev:String,d:Object,token:Object):Void {
 if(!connected)return;
 serial++;
 var target:String=d==null?"":d.name;
 var incarnation:String=d==null?"":d.incarnation;
 var gid:Number=token==null?0:token.gesture;
 var begin:Number=token==null?0:token.beginSeq;
 var button:Number=token==null?0:token.button;
 var pending:Number=0;
 var content:String=d==null?"":d.contentBuild;
 for(var i:Number=0;i<jobs.length;i++)if(!jobs[i].revoked && jobs[i].domain===d)pending++;
 sock.send("{\"protocol\":2,\"capabilities\":\"pointer-left-explicit;raw-diagnostic;deferred-guarded;no-keyboard\",\"contentBuild\":\""+content+"\",\"seq\":"+serial+",\"timer\":"+getTimer()+",\"frame\":"+frames+",\"event\":\""+ev+"\",\"target\":\""+target+"\",\"x\":"+_root._xmouse+",\"y\":"+_root._ymouse+",\"hoverA\":"+hoverA+",\"hoverB\":"+hoverB+",\"session\":\""+session+"\",\"geometry\":"+geometry+",\"coverage\":"+coverage+",\"epoch\":"+ownerEpoch+",\"ticket\":"+cancelTicket+",\"incarnation\":\""+incarnation+"\",\"gesture\":"+gid+",\"button\":"+button+",\"beginSeq\":"+begin+",\"gateClosed\":"+allClosed+",\"pending\":"+pending+",\"logicalBegins\":"+logicalBegins+",\"logicalEnds\":"+logicalEnds+",\"logicalCommits\":"+logicalCommits+",\"rawCallbacks\":"+rawCallbacks+"}");
}
function drawDomain(d:Object,hover:Boolean,held:Boolean):Void {
 var mc:MovieClip=d.clip;mc.clear();mc.beginFill(held?0xDD9900:hover?0x00DD55:0x336699,100);
 mc.moveTo(0,0);mc.lineTo(160,0);mc.lineTo(160,70);mc.lineTo(0,70);mc.lineTo(0,0);mc.endFill();
}
function rawEvent(name:String,d:Object):Void {rawCallbacks++;sendEvent("raw-"+name,d,null);}
function installDomain(parent:MovieClip,name:String):Void {
 var mc:MovieClip=parent.createEmptyMovieClip("button",1);mc._x=name=="A"?80:350;mc._y=120;
 // Plain identity survives AVM1 same-path MovieClip reference reuse.
 var d:Object={name:name,incarnation:name=="A"?"main-1":"child-"+(++childSeed),clip:mc,alive:true,open:false,contentBuild:name=="A"?"r9-main-v2":"r9-child-v2"};
 if(session!="")closeDomains();
 domains.push(d);drawDomain(d,false,false);mc.tabEnabled=false;
 // Raw callbacks NEVER commit, select visuals or enqueue business jobs.
 mc.onPress=function():Void {rawEvent("press",d);};
 mc.onRelease=function():Void {rawEvent("release",d);};
 mc.onReleaseOutside=function():Void {rawEvent("releaseOutside",d);};
 mc.onDragOut=function():Void {rawEvent("dragOut",d);};
 mc.onDragOver=function():Void {rawEvent("dragOver",d);};
 mc.onRollOver=function():Void {rawEvent("over",d);};
 mc.onRollOut=function():Void {rawEvent("out",d);};
 if(session!="")sendEvent("REGISTER",d,null);
}
function domainAt(x:Number,y:Number):Object {
 var pt:Object={x:x,y:y};_root.localToGlobal(pt);
 for(var i:Number=domains.length-1;i>=0;i--){
  var d:Object=domains[i];
  if(d.alive && d.open && d.clip._visible && d.clip.hitTest(pt.x,pt.y,true))return d;
 }
 return null;
}
function closeDomains():Void {
 allClosed=true;pendingReady=null;if(activeToken!=null)activeToken.revoked=true;activeToken=null;
 for(var i:Number=0;i<jobs.length;i++)jobs[i].revoked=true;
 jobs=[];hoverA=false;hoverB=false;
 for(i=0;i<domains.length;i++){domains[i].open=false;drawDomain(domains[i],false,false);}
}
function reject():Void {sendEvent("REJECT",null,null);}
function command(wire:String):Void {
 var p:Array=wire.split("|");if(p.length!=12){closeDomains();sendEvent("FAULT",null,null);return;}
 var op:String=p[0];
 var geo:Number=Number(p[11]);
 if(isNaN(geo)||geo!=Math.floor(geo)||!(geo>0)||!(geo<1000001)){reject();return;}
 if(op=="HELLO"){
  if(session!="" || p[1].length!=32 || domains.length!=2){reject();return;}
  session=p[1];lastWire=Number(p[5]);
  for(var h:Number=0;h<domains.length;h++)sendEvent("REGISTER",domains[h],null);
  return;
 }
 if(session=="" || p[1]!=session){reject();return;}
 var cv:Number=Number(p[2]),ep:Number=Number(p[3]),ticket:Number=Number(p[4]),sq:Number=Number(p[5]);
 if(isNaN(cv)||isNaN(ep)||isNaN(ticket)||isNaN(sq)||cv!=Math.floor(cv)||ep!=Math.floor(ep)||ticket!=Math.floor(ticket)||!(cv>0)||!(cv<1000001)||!(ep>0)||!(ep<1000001)||!(ticket>0)||!(ticket<1000001)||sq!=Math.floor(sq)||!(sq>lastWire)||!(sq<1000001)){reject();return;}
 lastWire=sq;
 if(op=="RELOAD"){
  if(!allClosed || cv!=coverage+1 || ep!=ownerEpoch || ticket!=cancelTicket){reject();return;}
  closeDomains();coverage=cv;
  for(var r:Number=0;r<domains.length;r++)if(domains[r].name=="B"){domains[r].alive=false;domains.splice(r,1);break;}
  _root.child.unloadMovie();_root.child.loadMovie("CooperativeChild.swf");sendEvent("REGISTER",domains[0],null);return;
 }
 if(cv!=coverage || domains.length!=2){reject();return;}
 if(op=="CANCEL"){
  if(ep<ownerEpoch || ticket<cancelTicket || (ep==ownerEpoch && ticket!=cancelTicket) || (ticket==cancelTicket && ep!=ownerEpoch)){reject();return;}
  closeDomains();ownerEpoch=ep;cancelTicket=ticket;geometry=geo;
  for(var c:Number=0;c<domains.length;c++)sendEvent("CANCELLED",domains[c],null);
  return;
 }
 if(ep!=ownerEpoch || ticket!=cancelTicket || geo!=geometry){reject();return;}
 if(op=="TEST_READY_DELAY" && allClosed){readyDelay=Number(p[9]);return;}
 if(op=="READY"){
  if(!allClosed || cancelTicket==0){reject();return;}
  allClosed=false;
  for(var a:Number=0;a<domains.length;a++){
   domains[a].open=true;
   if(a==1 && readyDelay>0)pendingReady={due:frames+readyDelay,domain:domains[a],epoch:ownerEpoch,ticket:cancelTicket};
   else sendEvent("READY",domains[a],null);
  }
  return;
 }
 if(allClosed){reject();return;}
 var gid:Number=Number(p[6]),button:Number=Number(p[7]),begin:Number=Number(p[8]),px:Number=Number(p[9]),py:Number=Number(p[10]);
 if(isNaN(gid)||isNaN(button)||isNaN(begin)||isNaN(px)||isNaN(py)||!(Math.abs(px)<100000)||!(Math.abs(py)<100000)){reject();return;}
 var hit:Object=domainAt(px,py);
 if(op=="UPDATE"){
  if(activeToken!=null && (activeToken.gesture!=gid || activeToken.beginSeq!=begin || activeToken.button!=button)){reject();return;}
  hoverA=hit!=null && hit.name=="A";hoverB=hit!=null && hit.name=="B";
  for(var v:Number=0;v<domains.length;v++)drawDomain(domains[v],domains[v]===hit,activeToken!=null && activeToken.domain===domains[v]);
  return;
 }
 if(op=="BEGIN"){
  if(activeToken!=null || button!=1 || begin!=sq || !(gid>lastGesture) || gid!=Math.floor(gid)){reject();return;}
  lastGesture=gid;if(hit==null){sendEvent("MISS",null,null);return;}
  activeToken={geometry:geometry,session:session,coverage:coverage,epoch:ownerEpoch,ticket:cancelTicket,gesture:gid,button:button,beginSeq:begin,domain:hit,incarnation:hit.incarnation,revoked:false};
  logicalBegins++;drawDomain(hit,true,true);sendEvent("mBegin",hit,activeToken);return;
 }
 if(op=="END"){
  var t:Object=activeToken;
  if(t==null || t.revoked || t.geometry!=geometry || t.gesture!=gid || t.button!=button || t.beginSeq!=begin || !t.domain.alive || t.incarnation!=t.domain.incarnation){reject();return;}
  activeToken=null;logicalEnds++;sendEvent("mEnd",t.domain,t);drawDomain(t.domain,t.domain===hit,false);
  if(t.domain===hit){t.due=frames+12;jobs.push(t);}else{t.revoked=true;sendEvent("mEndOutside",t.domain,t);}
  return;
 }
 reject();
}
_root.createEmptyMovieClip("mainScope",1);installDomain(_root.mainScope,"A");
_root.createEmptyMovieClip("child",2);_root.child.loadMovie("CooperativeChild.swf");
_root.createTextField("label",20,30,20,580,75);
_root.label.text="Disposable cooperative M-domain probe\nA: main SWF / B: loaded child SWF; no game or saves";
var keyObserver:Object={};
keyObserver.onKeyDown=function():Void {rawEvent("key",null);};
Key.addListener(keyObserver);
sock.onData=function(data:String):Void {command(data);};
sock.onConnect=function(ok:Boolean):Void {connected=ok;};
sock.onClose=function():Void {connected=false;closeDomains();};
sock.connect("127.0.0.1",32187);
_root.onEnterFrame=function():Void {
 frames++;
 if(pendingReady!=null && pendingReady.due<=frames){
  var readyJob:Object=pendingReady;pendingReady=null;
  if(!allClosed && readyJob.epoch==ownerEpoch && readyJob.ticket==cancelTicket)sendEvent("READY",readyJob.domain,null);
 }
 if(connected && session=="" && domains.length==2 && frames%3==0)sendEvent("ready",null,null);
 for(var i:Number=jobs.length-1;i>=0;i--){
  var t:Object=jobs[i];
  if(t.due<=frames){
   jobs.splice(i,1);
   if(t.geometry==geometry && !t.revoked && !allClosed && t.session==session && t.coverage==coverage && t.epoch==ownerEpoch && t.ticket==cancelTicket && t.domain.alive && t.domain.open && t.incarnation==t.domain.incarnation){
    t.revoked=true;logicalCommits++;sendEvent("mCommit",t.domain,t);
   }
  }
 }
 if(frames%3==0)sendEvent("sample",null,null);
};
