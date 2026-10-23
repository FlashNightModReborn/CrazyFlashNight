import flash.display.BitmapData;
import org.flashNight.arki.render.BloodVisualBridge;
import org.flashNight.arki.component.Effect.BitmapEffectRenderer;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

class org.flashNight.arki.render.BloodVisualBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value)passed++;else{failed++;trace("[TEST_FAIL] BloodVisualBridgeTest: "+name);}
    }
    private static function children(world:MovieClip):Number {
        var result:Number=0;
        for(var key:String in world)if(typeof world[key]=="movieclip" && world[key]._parent===world)result++;
        return result;
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var oldWorld:MovieClip=_root.gameworld;
        var oldGravity=_root.重力加速度,oldDraw=_root.绘图引擎,oldVisual=_root.是否视觉元素,oldPause=_root.暂停;
        var oldDict:Object=BitmapEffectRenderer.bitmapDict;
        var oldInfos:Array=BitmapEffectRenderer.bloodstainInfos;
        var world:MovieClip=_root.createEmptyMovieClip("__bloodBridgeUnitTest",198700);
        var body:MovieClip=world.createEmptyMovieClip("deadbody",1);
        var floor:BitmapData=new BitmapData(256,256,true,0);
        var upper:BitmapData=new BitmapData(256,256,true,0);
        body.layers=[floor,null,upper];body.layerOriginX=10;body.layerOriginY=20;
        var dict:Object={};var infos:Array=[];var bitmaps:Array=[];
        for(var i:Number=0;i<8;i++) {
            var image:BitmapData=new BitmapData(2,2,true,0xFF000000|((i+1)*0x001100));
            bitmaps.push(image);dict["bloodProbe"+i]=image;infos[i]={id:"bloodProbe"+i,offsetX:1,offsetY:1};
        }
        BitmapEffectRenderer.bitmapDict=dict;BitmapEffectRenderer.bloodstainInfos=infos;
        _root.gameworld=world;_root.重力加速度=2.25;_root.是否视觉元素=true;_root.暂停=false;
        var battle:LinearCongruentialEngine=LinearCongruentialEngine.getInstance();
        var battleBefore:Number=battle.captureState();
        var clipsBefore:Number=children(world);
        BloodVisualBridge.resetScene();BloodVisualBridge.configure(true,0);
        for(i=0;i<65;i++)check(BloodVisualBridge.trySpawn(50,60,100,100),"ordinary decorative request is consumed "+i);
        check(BloodVisualBridge.getStats().queued==64,"birth events stop at 64 before serialization");
        var packet:String=BloodVisualBridge.flush();var parts:Array=packet.split(";");var fields:Array=parts[1].split(",");
        check(parts.length==65 && fields.length==9 && fields[0]=="p" && Number(fields[1])==1
            && Number(fields[7])>0 && Number(fields[8])==2.25,"one compact seeded birth carries the authored gravity");
        check(BloodVisualBridge.flush()=="" && children(world)==clipsBefore,"births do not replay or create display objects");
        _root.重力加速度=0/0;
        BloodVisualBridge.trySpawn(50,60,100,-100);
        fields=BloodVisualBridge.flush().substr(1).split(",");
        check(Number(fields[6])==-100 && Number(fields[8])==1,"mirroring is retained and invalid gravity uses bounded default");
        _root.重力加速度=1;
        BloodVisualBridge.receiveLandings([[1,7,30,40]]);BloodVisualBridge.flush();
        var pixel:Number=floor.getPixel32(19,19);
        check((pixel>>>24)==255 && (pixel&0xFFFFFF)==0x008800 && upper.getPixel32(19,19)==0,"explicit variant uses original origin/centering and only layer zero");
        var drawn:Number=BloodVisualBridge.getStats().stamped;
        BloodVisualBridge.receiveLandings([[1,1,30,40],[0,1,30,40]]);
        check(BloodVisualBridge.getStats().pendingStamps==0 && BloodVisualBridge.getStats().stamped==drawn,"duplicate and invalid landing ids never queue another stamp");
        BloodVisualBridge.receiveLandings([[2,0,40,40],[3,1,50,40],[4,2,60,40],[5,3,70,40],[6,4,80,40]]);
        BloodVisualBridge.flush();
        check(BloodVisualBridge.getStats().pendingStamps==1 && BloodVisualBridge.getStats().stamped==drawn+4,"one frame stamps at most four queued landings");
        _root.暂停=true;BloodVisualBridge.flush();
        check(BloodVisualBridge.getStats().pendingStamps==1,"pause freezes pending stamps");
        _root.暂停=false;BloodVisualBridge.flush();
        check(BloodVisualBridge.getStats().pendingStamps==0,"resume drains the remaining landing once");
        BloodVisualBridge.receiveLandings([[7,8,90,40],[8,1,0/0,40],[9,1,"90",40]]);
        check(BloodVisualBridge.getStats().pendingStamps==0 && BloodVisualBridge.getStats().lastStamp==6,"invalid variants and coordinates cannot advance the valid landing watermark");
        var oversized:Array=[];for(i=10;i<19;i++)oversized.push([i,0,100,100]);
        BloodVisualBridge.receiveLandings(oversized);
        check(BloodVisualBridge.getStats().pendingStamps==0,"a landing batch above eight is rejected");
        var id:Number=10;
        for(var batch:Number=0;batch<9;batch++) {
            var group:Array=[];for(i=0;i<8;i++)group.push([id++,0,100,100]);
            BloodVisualBridge.receiveLandings(group);
        }
        check(BloodVisualBridge.getStats().pendingStamps==64 && BloodVisualBridge.getStats().lastStamp==81,"source queue stays at 64 and consumed overflow cannot later replay");
        BloodVisualBridge.resetScene();
        check(BloodVisualBridge.getStats().pendingStamps==0 && BloodVisualBridge.getStats().lastStamp==0,"scene reset clears the queue and landing watermark");
        var policy:Object=org.flashNight.arki.render.WorkerProjectionPolicy;
        var originalNone:Function=policy.isNone;
        policy.isNone=function(name:String):Boolean{return true;};
        BloodVisualBridge.trySpawn(50,60,100,100);BloodVisualBridge.receiveLandings([[1,1,30,40]]);
        check(BloodVisualBridge.flush()=="" && BloodVisualBridge.getStats().pendingStamps==0
            && children(world)==clipsBefore,"none mode allocates no visual MCs or stamp backlog");
        policy.isNone=originalNone;
        BloodVisualBridge.configure(false,0);
        check(BloodVisualBridge.trySpawn(50,60,100,100) && BloodVisualBridge.flush()=="","known but unavailable native decoration is consumed without fallback");
        BloodVisualBridge.configure(false,-1);
        check(!BloodVisualBridge.trySpawn(50,60,100,100),"unknown paired blood catalog retains its existing caller route");
        check(battle.captureState()===battleBefore,"pure blood bridge never consumes the battle LCG");
        check(!BitmapEffectRenderer.renderBloodstainVariant(40,40,8),"explicit bitmap variant is bounded");
        BloodVisualBridge.disconnect();BloodVisualBridge.resetScene();
        BitmapEffectRenderer.bitmapDict=oldDict;BitmapEffectRenderer.bloodstainInfos=oldInfos;
        _root.gameworld=oldWorld;_root.重力加速度=oldGravity;_root.绘图引擎=oldDraw;_root.是否视觉元素=oldVisual;_root.暂停=oldPause;
        for(i=0;i<bitmaps.length;i++)bitmaps[i].dispose();floor.dispose();upper.dispose();world.removeMovieClip();
        trace("BloodVisualBridgeTest Tests Passed: "+passed);
        trace("BloodVisualBridgeTest Tests Failed: "+failed);
    }
}
