import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;

/** Actual scenic SWF through production room loader/depth/render and real clear projection. */
class org.flashNight.arki.scene.Cf6ScenicWingsAssetsTest {
    private static var saved:Object,room:Object,manager:Object,row:Object,spec:Object;
    private static var world:MovieClip,sky:MovieClip,driver:MovieClip;
    private static var bitmap:BitmapData,firstFacing:BitmapData;
    private static var index:Number,age:Number,frame:Number,passed:Number,failed:Number;
    private static var pixelFrames:Number,correctFrames:Boolean,done:Boolean,phase:String,observerLease:String;
    private static var cueCalls:Number,clearCalls:Number,spawnCalls:Number,killCalls:Number,teardownOnClear:Boolean;
    private static function check(ok:Boolean,label:String):Void {if(ok) passed++;else {failed++;trace("[FAIL] Cf6ScenicWingsAssets: "+label);}}
    private static function near(a:Number,b:Number):Boolean {return Math.abs(a-b)<0.06;}
    public static function onClear():Void {
        clearCalls++;
        if(teardownOnClear) Cf6MapMechanism.teardown();
    }
    public static function onSpawn():Void {spawnCalls++;}
    public static function onKill():Void {killCalls++;}
    public static function effect():Void {cueCalls++;}
    public static function runAllTests():Void {
        passed=failed=0;index=-1;done=false;firstFacing=null;cueCalls=clearCalls=spawnCalls=killCalls=0;teardownOnClear=false;
        var target:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var effectApi:Object=org.flashNight.arki.component.Effect.EffectSystem;
        saved={world:_root.gameworld,sky:_root.天空盒,manager:StageManager.instance,depth:DepthManager.instance,
            control:_root.控制目标,ext:_root._saveExt,slot:_root.savePath,stageName:_root.当前关卡名,pause:_root.暂停,
            server:_root.server,message:_root.发布消息,findHero:target.findHero,effect:effectApi.Effect};
        PauseManager.install();_root.暂停=false;_root.server={isSocketConnected:false};
        _root.发布消息=function(value:String):Void {trace("Cf6ScenicWingsAssets message: "+value);};
        target.findHero=function():MovieClip {return _root.gameworld.hero;};
        effectApi.Effect=effect;
        sky=_root.createEmptyMovieClip("__cf6ScenicSky",30070);sky._visible=false;_root.天空盒=sky;
        world=_root.createEmptyMovieClip("__cf6ScenicWorld",30071);world._visible=false;_root.gameworld=world;
        world.__stageReturnWorldIdentity={};world.dispatcher=new EventDispatcher();
        world.dispatcher.subscribe("Clear",onClear,Cf6ScenicWingsAssetsTest);
        world.dispatcher.subscribe("UnitSpawn",onSpawn,Cf6ScenicWingsAssetsTest);
        world.createEmptyMovieClip("效果",20);world.createEmptyMovieClip("deadbody",1);
        world.createEmptyMovieClip("地图",2);world.地图.僵尸型敌人总个数=7;
        var hero:MovieClip=world.createEmptyMovieClip("hero",10);hero.hp=100;hero._x=300;hero._y=hero.Z轴坐标=300;
        hero.dispatcher=new EventDispatcher();hero.dispatcher.subscribe("enemyKilled",onKill,Cf6ScenicWingsAssetsTest);
        _root.控制目标="hero";
        DepthManager.instance=new DepthManager(world,0,870655,32);DepthManager.instance.calibrate(0,800);
        var managerApi:Object=StageManager;managerApi.instance=null;manager=StageManager.getInstance();
        manager.gameworld=world;manager.environment={};manager.spawnPoints=[];manager.currentStage=0;
        manager.isActive=true;manager.isFinished=false;manager.isFailed=false;manager.isCleared=false;
        manager.stageMode="legacy";manager.stageInfoList=[{},{}];manager.timePoolController=null;
        manager.currentStageInfo={basicInfo:{Animation:{Load:-1}}};
        _root.savePath="cf6.scenic.assets.fixture";_root.当前关卡名="书中历险-毒刺行动";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",slot:String(_root.savePath),seed:57,startedAt:1700}};
        bitmap=new BitmapData(600,500,true,0);
        driver=_root.createEmptyMovieClip("__cf6ScenicAssetsWatch",30072);
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6ScenicWingsAssetsTest.tick();};
        next();
    }
    private static function next():Void {
        index++;if(index==2) {verifyClear(false);verifyClear(true);finish();return;}
        var mapId:String=index==0?"A06":"A08";
        // Original world1778/depth186 and world1841/depth158; body scale is the current 190cm policy.
        spec={id:mapId+"-scenic-wings",role:"scenic-actor",url:"flashswf/backgrounds/cf6/preparation/CF6_ScenicWings.swf",
            x:index==0?1767.5947:685.9093,y:index==0?358.4:443.904,sortY:index==0?358.4:443.904,
            width:1,height:1,depth:index==0?186:158,frames:15,visualScale:1,
            artMatrix:[index==0?-1.209123662:1.209123662,0,0,1.209123662,0,0]};
        if(index==0) spec.speech="Andy！救我！";
        var layers:Array=[spec];
        if(index==0) layers.push({id:"sky",role:"screen-fixed",coordinateSpace:"root-stage",
            url:"flashswf/backgrounds/cf6/CF6_A06_sky.swf",x:0,y:-20,width:800,height:187,depth:0});
        check(Cf6MapMechanism.beginRoom(world,world.__stageReturnWorldIdentity,mapId,{layers:layers}),"production beginRoom "+mapId);
        room=world.__cf6Mechanism;row=room.layers[0];
        observerLease=PauseManager.lease(true,"scenic-assets-observer");
        phase="loading";age=0;frame=1;pixelFrames=0;correctFrames=true;
    }
    private static function draw():Object {
        var textVisible:Boolean=row.holder.speech._visible;
        row.holder.speech._visible=false;
        bitmap.fillRect(bitmap.rectangle,0);bitmap.draw(row.holder,new Matrix(1,0,0,1,300,260));
        row.holder.speech._visible=textVisible;
        return bitmap.getColorBoundsRect(0xFF000000,0,false);
    }
    public static function tick():Void {
        if(done) return;age++;
        if(room.failed) {check(false,"production scene load failed "+index);finish();return;}
        if(phase=="loading") {
            if(room.pending>0) {if(age>300) {check(false,"actual resource timeout "+index);finish();}return;}
            check(row.ready && row.holder.art._totalframes==15,"actual published fifteen-frame actor "+index);
            check(Cf6PropDepthService.valid(row.ticket) && row.holder._parent===world,"production owned world-depth holder "+index);
            var nativeX:Number=index==0?1035.7:401.9,nativeY:Number=index==0?210:260.1;
            check(near(row.holder._x,nativeX*128/75) && near(row.holder._y,nativeY*128/75)
                && near(row.ticket.sortY,nativeY*128/75),"original world footpoint transformed exactly once "+index);
            var matrix:Object=row.holder.art.transform.matrix;
            check((index==0?matrix.a<0:matrix.a>0) && near(Math.abs(matrix.a),1.209123662)
                && near(matrix.d,1.209123662) && matrix.tx==0 && matrix.ty==0,"native left/right facing and independent body scale "+index);
            check(index==0?row.holder.speech.text=="Andy！救我！":row.holder.speech===undefined,"only A06 has original rescue speech "+index);
            phase="frames";age=0;room.animationFrame=0;Cf6MapMechanism.tick();return;
        }
        if(phase=="frames" && age>=2) {
            var rect:Object=draw();
            if(rect.width>30 && rect.height>100) pixelFrames++;else correctFrames=false;
            if(row.holder.art._currentframe!==frame) correctFrames=false;
            if(frame==1) {
                check(rect.width>30 && rect.height>100 && rect.height<260,"positive actual native actor pixels "+index);
                check(Math.abs(rect.y+rect.height-260)<10,"native visible feet meet the holder ground anchor "+index);
                var pink:Number=0,blueCount:Number=0;
                for(var colorY:Number=rect.y;colorY<rect.y+rect.height;colorY++) {
                    for(var colorX:Number=rect.x;colorX<rect.x+rect.width;colorX++) {
                        var pixel:Number=bitmap.getPixel32(colorX,colorY);
                        if((pixel>>>24)<224) continue;
                        var red:Number=(pixel>>16)&255,green:Number=(pixel>>8)&255,blue:Number=pixel&255;
                        if(red>50 && red>green*1.4 && blue>green*1.3) pink++;
                        if(blue>50 && blue>red*1.4 && green>red*1.15) blueCount++;
                    }
                }
                check(pink>300 && pink>blueCount*3,"actual scene NPC keeps pink clothing and hair instead of enemy blue "+index);
                trace("Cf6ScenicWingsAssets Palette: map="+room.mapId+" pink="+pink+" blue="+blueCount);
                if(index==0) firstFacing=bitmap.clone();
                else {
                    var compared:Number=0,wrong:Number=0;
                    for(var py:Number=20;py<350;py++) for(var px:Number=80;px<520;px++) {
                        var left:Number=firstFacing.getPixel32(599-px,py)>>>24,right:Number=bitmap.getPixel32(px,py)>>>24;
                        if(left>=240 && right>=240) compared++;
                        else if(left>=240 && right==0 || right>=240 && left==0) wrong++;
                    }
                    check(compared>500 && wrong<compared*0.08,"actual A06/A08 pixels mirror around the same foot origin");
                }
            }
            if(frame<15) {frame++;age=0;room.animationFrame=frame-1;Cf6MapMechanism.tick();return;}
            check(correctFrames && pixelFrames==15,"all fifteen real native frames remain visible "+index);
            verifyInert();unload();next();
        }
    }
    private static function verifyInert():Void {
        var holder:MovieClip=row.holder,art:MovieClip=holder.art;
        check(holder.hp===undefined && art.hp===undefined && holder.area===undefined && art.area===undefined
            && holder.dispatcher===undefined && art.dispatcher===undefined && art.wingsTick===undefined,
            "scene holder and actual SWF have no unit damage/AI interfaces "+index);
        var bullet:Object={hitCount:0},shooter:MovieClip=world.hero;
        var rejected:Boolean=BulletQueueProcessor.injectHit(bullet,shooter,holder,holder._x,holder._y,1,false)==null;
        rejected=BulletQueueProcessor.injectHit(bullet,shooter,art,holder._x,holder._y,1,false)==null && rejected;
        check(rejected && bullet.hitCount==0 && holder.hp===undefined && art.hp===undefined,"production hit admission rejects visual actor without damage "+index);
        check(world.地图.僵尸型敌人总个数==7 && spawnCalls==0 && killCalls==0 && clearCalls==0
            && !manager.isCleared && !room.clearRequested && world.允许通行===false,
            "actor animation cannot spawn units consume wave count or clear a room "+index);
        trace("Cf6ScenicWingsAssets NativeCase: map="+room.mapId+" frames="+pixelFrames+" sortY="+row.ticket.sortY
            +" facing="+row.holder.art.transform.matrix.a+" count="+world.地图.僵尸型敌人总个数);
    }
    private static function unload():Void {
        var name:String=row.holder._name,oldRoom:Object=room,load:Object=row.loads[0];
        Cf6MapMechanism.teardown();PauseManager.releaseLease(observerLease);observerLease=null;
        check(row.ticket.closed && world[name]===undefined && !world.__cf6PropDepthSession,"teardown removes only owned scene art and depth registration "+index);
        var foreign:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());foreign.foreign=true;
        var art:MovieClip=foreign.createEmptyMovieClip("art",0);art.foreign=true;
        load.listener.onLoadInit(art);
        check(foreign.foreign && art.foreign && art._parent===foreign && !foreign.speech,"late original loader callback cannot rebind same-path replacement "+index);
        foreign.removeMovieClip();
    }
    private static function verifyClear(teardownListener:Boolean):Void {
        teardownOnClear=teardownListener;cueCalls=clearCalls=0;
        manager.isCleared=false;manager.isFailed=false;manager.isFinished=false;world.关卡结束=false;world.允许通行=false;
        check(Cf6MapMechanism.beginRoom(world,world.__stageReturnWorldIdentity,"A08",{layers:[]}),"clear projection fixture binds "+teardownListener);
        Cf6MapMechanism.tick();room=world.__cf6Mechanism;
        manager.clearStage();
        check(room.clearRequested && !manager.isCleared && cueCalls==0,"real clear request intercepted before authority "+teardownListener);
        Cf6MapMechanism.tick();
        check(manager.isCleared && world.关卡结束 && clearCalls==1,"real StageManager assigns clear then synchronously dispatches "+teardownListener);
        check(cueCalls==1 && Cf6ExitGuideService.hasClearCue(manager,world),"actual final clear deduplicates cue after isCleared and synchronous listener "+teardownListener);
        Cf6MapMechanism.teardown();
    }
    private static function finish():Void {
        if(done) return;done=true;Cf6MapMechanism.teardown();
        if(observerLease!=null) PauseManager.releaseLease(observerLease);
        delete driver.onEnterFrame;driver.removeMovieClip();world.removeMovieClip();sky.removeMovieClip();
        DepthManager.instance.dispose();DepthManager.instance=saved.depth;
        var managerApi:Object=StageManager;managerApi.instance=saved.manager;
        var target:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;target.findHero=saved.findHero;
        var effectApi:Object=org.flashNight.arki.component.Effect.EffectSystem;effectApi.Effect=saved.effect;
        _root.gameworld=saved.world;_root.天空盒=saved.sky;_root.控制目标=saved.control;
        _root._saveExt=saved.ext;_root.savePath=saved.slot;_root.当前关卡名=saved.stageName;
        _root.server=saved.server;_root.发布消息=saved.message;_root.暂停=saved.pause;
        bitmap.dispose();if(firstFacing!=null) firstFacing.dispose();
        trace("Cf6ScenicWingsAssetsTest Tests Passed: "+passed);trace("Cf6ScenicWingsAssetsTest Tests Failed: "+failed);
        _root.cf6ScenicWingsAssetsComplete();
    }
}
