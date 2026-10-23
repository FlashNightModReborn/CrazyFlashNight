import org.flashNight.arki.scene.*;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.neur.Event.EventDispatcher;
import flash.display.BitmapData;
import flash.geom.Matrix;
/** Real transport SWF + real event wheel; disposable spawn stub tests conserved reservations. */
class org.flashNight.arki.scene.Cf6TransportTest {
 private static var passed:Number,failed:Number,index:Number,age:Number;
 private static var s:Object,saved:Object,driver:MovieClip,wheel:WaveSpawnWheel;
 private static var ids:Array=["A09","A14","A18"],depths:Array=[112,505,147],counts:Array=[5,7,5];
 private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[FAIL] Cf6Transport: "+label);}}
 private static function steps(n:Number):Void {for(var i:Number=0;i<n;i++) Cf6TransportService.tick(s);}
 private static function spec():Object {return {schema:"cf6-transport.v1",id:ids[index]+"-transport-"+depths[index],sourceSprite:1868,
 url:"flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf",x:300,y:300,sortY:305.35,artMatrix:[1,0,0,1,0,0],
 hitBounds:[-295,-42,268,253],frames:29,dispatchFrame:29,subWaveIndex:1};}
 private static function begin():Void {
  var w:MovieClip=_root.createEmptyMovieClip("__cf6TransportFixture",_root.getNextHighestDepth());_root.gameworld=w;
  w.__stageReturnWorldIdentity={};w.dispatcher=new EventDispatcher();
  var counter:Number=900000;w.getNextHighestDepth=function():Number{return counter++;};
  DepthManager.instance=new DepthManager(w,0,870655,16);DepthManager.instance.calibrate(0,1000);
  _root.savePath="cf6.transport.fixture";_root.当前关卡名="书中历险-毒刺行动";
  _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",slot:_root.savePath,seed:19,startedAt:100,outcome:"active"}};
  var sm:Object=StageManager;sm.instance={currentStage:0,isActive:true,isFinished:false,isFailed:false,isCleared:false};
  var ws:Object=WaveSpawner;ws.instance={gameworld:w,isActive:true,isFinished:false,currentWave:0,tickCount:0,created:0,live:0,accepted:[],frameClock:0,admittedFrames:[]};
  ws.instance.spawn=function(a,idx:Number,wi:Number,q:Number):Boolean {if(this.live>=2)return false;this.live++;this.created++;this.accepted.push(q);this.admittedFrames.push(this.frameClock);return true;};
  WaveSpawnWheel.instance=null;wheel=WaveSpawnWheel.getInstance();wheel.init();
  var r:Object={world:w,owner:w.__stageReturnWorldIdentity,mapId:ids[index],stageManager:sm.instance,stageIndex:0,
    slot:String(_root.savePath),stageName:_root.当前关卡名,runIdentity:_root._saveExt.bookRun,phase:"combat"};w.__cf6Mechanism=r;
  var h:MovieClip=w.createEmptyMovieClip("hero",w.getNextHighestDepth());h.hp=100;h._x=1000;h._y=300;
  var a:MovieClip=h.createEmptyMovieClip("area",1);a.beginFill(0);a.moveTo(-3,-3);a.lineTo(3,-3);a.lineTo(3,3);a.lineTo(-3,3);a.endFill();_root.控制目标="hero";
  s=Cf6TransportService.begin(r,spec());age=0;
 }
 public static function runAllTests():Void {
  passed=failed=index=0;var sm:Object=StageManager,ws:Object=WaveSpawner;
  saved={world:_root.gameworld,sm:sm.instance,ws:ws.instance,wheel:WaveSpawnWheel.instance,depth:DepthManager.instance,
   slot:_root.savePath,name:_root.当前关卡名,ext:_root._saveExt,hero:_root.控制目标,pause:_root.暂停,transition:_root.场景转换中};
  _root.暂停=false;_root.场景转换中=false;begin();driver=_root.createEmptyMovieClip("__cf6TransportDriver",_root.getNextHighestDepth());
  driver.onEnterFrame=function():Void {Cf6TransportTest.poll();};
 }
 private static function poll():Void {
  if(s==null || s.failed || ++age>600){check(false,"native resource load timeout/error "+ids[index]);finish();return;}
  if(!s.ready)return;exercise();Cf6TransportService.end(s);wheel.dispose();s.room.world.removeMovieClip();index++;
  if(index<3)begin();else finish();
 }
 private static function exercise():Void {
  check(s.ready && s.art._totalframes==29,"actual 29-frame native resource "+ids[index]);
  check(s.art._xscale==100 && s.art._yscale==100,"original visual scale "+ids[index]);
  var bitmap:BitmapData=new BitmapData(450,300,true,0),all:Boolean=true,changed:Boolean=false,first:String="";
  for(var f:Number=1;f<=29;f++){
   s.art.gotoAndStop(f);bitmap.fillRect(bitmap.rectangle,0);bitmap.draw(s.art,new Matrix(1,0,0,1,220,240));
   var opaque:Number=0,signature:String="";
   for(var y:Number=0;y<300;y+=7)for(var x:Number=0;x<450;x+=7){var pixel:Number=bitmap.getPixel32(x,y);if((pixel>>>24)>0)opaque++;signature+=pixel+",";}
   if(opaque==0)all=false;if(f==1)first=signature;else if(signature!=first)changed=true;
  }
  bitmap.dispose();s.art.gotoAndStop(1);
  check(all,"all 29 frames retain visible native pixels "+ids[index]);check(changed,"source timeline genuinely changes pose "+ids[index]);
  steps(10);check(s.phase=="idle" && s.frame==1,"outside area cannot start transport");
  s.room.world.hero._x=300;steps(1);check(s.phase=="opening" && s.frame==1,"contact starts source animation");
  _root.暂停=true;steps(10);check(s.frame==1,"pause freezes opening");_root.暂停=false;
  steps(28);check(s.frame==29 && s.phase=="ready-to-dispatch" && !s.attempted,"frame29 latches before future wave subscription");
  var ws:Object=s.spawner;ws.currentWave=1;steps(3);check(!s.attempted,"wave tick zero cannot publish before listeners exist");
  wheel.subscribeSpawnEvent(counts[index],400,0,{},0,1,{EventName:"Cf6TransportReady",Parameters:[s.spec.id]});
  s.room.world.dispatcher.publish("Cf6TransportReady","wrong-owner");wheel.minHeapTick();check(ws.created==0,"real wheel rejects foreign instance token");
  ws.tickCount=1;steps(1);check(s.attempted && s.phase=="spent","latched source dispatch delivered after listener registration");
  check(ws.created==0,"400ms event queue cannot synchronously burst on dispatch");
  for(var n:Number=0;n<180;n++){ws.frameClock++;if(ws.frameClock%3==0)wheel.slotTick();wheel.minHeapTick();ws.live=0;}
  var spaced:Boolean=ws.admittedFrames.length==counts[index];
  for(var ai:Number=1;ai<ws.admittedFrames.length;ai++)if(ws.admittedFrames[ai]-ws.admittedFrames[ai-1]!=15)spaced=false;
  check(spaced,"actual timed wheel separates transport admissions by existing500ms recurring quantum");
  trace("[CF6_TRANSPORT_CADENCE] map="+ids[index]+" frames="+ws.admittedFrames.join(","));
  check(ws.created==counts[index],"existing finite budget delivered exactly "+counts[index]);
  steps(60);for(n=0;n<60;n++){ws.frameClock++;if(ws.frameClock%3==0)wheel.slotTick();wheel.minHeapTick();ws.live=0;}
  check(ws.created==counts[index],"spent transport never adds units");
  check(ws.accepted[0]==counts[index] && ws.accepted[ws.accepted.length-1]==1,"wheel preserves remaining-count sequence");
  s.room.stageManager.isCleared=true;steps(120);
  check(!s.closed && s.phase=="spent" && s.frame==29 && Cf6PropDepthService.valid(s.ticket)
    && s.ticket.holder._parent===s.room.world,"cleared room retains owned vehicle in final pose "+ids[index]);
  var parked:BitmapData=new BitmapData(450,300,true,0);parked.draw(s.art,new Matrix(1,0,0,1,220,240));
  check(parked.getColorBoundsRect(0xFF000000,0,false).width>0 && ws.created==counts[index],
    "parked transport remains visibly drawn and cannot publish extra enemies "+ids[index]);parked.dispose();
  s.room.stageManager.isCleared=false;
  // Re-arm only the fixture to test the irreversible publication fence.
  s.phase="ready-to-dispatch";s.attempted=false;var original:Function=s.room.world.dispatcher.publish;
  s.room.world.dispatcher.publish=function():Void {throw new Error("listener committed then threw");};
  steps(1);check(s.failed && s.attempted && s.reason=="delivery-unknown","throw after delivery retains unknown lock");
  s.room.world.dispatcher.publish=original;steps(10);check(s.failed && s.attempted,"unknown publication never retries");
  var shared:Object=s.ticket.session,other:Object=Cf6PropDepthService.create(shared,"other",10,10,10);
  Cf6TransportService.end(s);check(s.closed && Cf6PropDepthService.valid(other),"cleanup preserves shared door/prop depth ownership");
  Cf6PropDepthService.end(shared);
 }
 private static function finish():Void {
  delete driver.onEnterFrame;driver.removeMovieClip();Cf6TransportService.end(s);if(wheel!=null)wheel.dispose();if(s!=null)s.room.world.removeMovieClip();
  var sm:Object=StageManager,ws:Object=WaveSpawner;sm.instance=saved.sm;ws.instance=saved.ws;WaveSpawnWheel.instance=saved.wheel;DepthManager.instance=saved.depth;
  _root.gameworld=saved.world;_root.savePath=saved.slot;_root.当前关卡名=saved.name;_root._saveExt=saved.ext;_root.控制目标=saved.hero;_root.暂停=saved.pause;_root.场景转换中=saved.transition;
  trace("Cf6TransportTest Tests Passed: "+passed);trace("Cf6TransportTest Tests Failed: "+failed);_root.cf6TransportComplete();
 }
}
