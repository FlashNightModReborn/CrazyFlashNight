import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.scene.BaseSiegeRules;

/** Actual AVM1 rule, production XML and published asset regression. */
class org.flashNight.arki.scene.BaseSiegeTest {
    private static var passed:Number;
    private static var failed:Number;
    public static var runId:String;
    private static var index:Number;
    private static var holder:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var files:Array;
    public static function runAllTests():Void {
        passed=0;failed=0;index=0;runId=String(_root.__baseSiegeFocusedRunId);
        check(BaseSiegeRules.canDeploy(true,false,true,true,false,true),"explained live nearby player can deploy");
        check(!BaseSiegeRules.canDeploy(false,false,true,true,false,true),"first wave explanation is required");
        check(!BaseSiegeRules.canDeploy(true,true,true,true,false,true),"operation is one-shot");
        check(!BaseSiegeRules.canDeploy(true,false,false,true,false,true),"remote operation is rejected");
        check(!BaseSiegeRules.canDeploy(true,false,true,false,false,true),"dead player cannot deploy");
        check(!BaseSiegeRules.canDeploy(true,false,true,true,true,true),"dialogue or pause cannot deploy");
        check(!BaseSiegeRules.canDeploy(true,false,true,true,false,false),"unloaded art cannot deploy");
        check(BaseSiegeRules.canClearRelay(true,true,true,true),"live defended relay admits original clear");
        check(!BaseSiegeRules.canClearRelay(false,true,true,true),"operation is required");
        check(!BaseSiegeRules.canClearRelay(true,false,true,true),"initialized guard is required");
        check(!BaseSiegeRules.canClearRelay(true,true,false,true),"defense wave must finish");
        check(!BaseSiegeRules.canClearRelay(true,true,true,false),"destroyed guard cannot clear");
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            org.flashNight.arki.scene.BaseSiegeTest.loadedStage(this,ok);
        };
        xml.load("../data/stages/基地房顶/基地.xml");
    }
    public static function loadedStage(xml:XML,ok:Boolean):Void {
        check(ok && xml.status==0,"production stage XML loads");
        var data:Object=XMLParser.parseXMLNode(xml.firstChild);
        var stages:Array=XMLParser.configureDataAsArray(data.SubStage);
        org.flashNight.arki.scene.BaseSiegeSceneTest.stages=stages;
        check(stages.length==8 && stages[0].id==0 && stages[7].id==7,"eight-scene continuous graph");
        check(stages[0].BasicInformation.PlayerX>1300 && stages[0].BasicInformation.Environment.Door.Direction=="左","crash starts at the wreck and exits left");
        check(stages[1].BasicInformation.PlayerX>1500 && stages[1].BasicInformation.Environment.Door.Direction=="左","rhino is traversed from right to left");
        check(stages[2].BasicInformation.PlayerX>1500 && stages[2].BasicInformation.Environment.Door.Direction=="下" && stages[2].BasicInformation.Environment.Door.y0==610 && stages[2].BasicInformation.Environment.Door.x0==765 && stages[2].BasicInformation.Environment.Door.x1==820,"tigr exits through the lower sandbags");
        check(stages[0].Wave.SubWave.length==2 && stages[0].Wave.SubWave[0].EnemyGroup.Enemy[1].Type=="兵种13","initial assault soldiers and dogs precede larger pursuit");
        var reunion:Object=findEvent(stages[0],"WaveFinished");var rhinoStart:Object=findEvent(stages[1],"Start");
        check(reunion.Enemy.length==2 && reunion.Enemy[0].Type=="兵种470" && reunion.Enemy[0].Level==20 && reunion.Enemy[1].Type=="兵种471" && reunion.Enemy[1].Level==20 && rhinoStart.Enemy.length==2,"both regular companions spawn at level 20 after the first wave and join rhino");
        check(stages[0].SpawnPoint.Point[0].x<150 && stages[0].SpawnPoint.Point[1].x<150 && reunion.Enemy[0].x<250 && reunion.Enemy[1].x<250 && reunion.Enemy[0].Parameters.方向=="右","pursuers and both regular companions enter from the left");
        check(stages[1].Wave.SubWave[1].EnemyGroup.Enemy[0].TriggerEvent.EventName=="SiegeCounterattack" && stages[2].Wave.SubWave[1].EnemyGroup.Enemy[0].Parameters.threatThreshold==15,"defense waves await activation and prioritize facility threat");
        var lobby:Array=stages[4].Wave.SubWave.EnemyGroup.Enemy;
        check(stages[4].Wave.SubWave.WaveInformation.FinishRequirement==3 && lobby[4].Quantity==10 && lobby[5].Quantity==10 && stages[5].Wave.SubWave.EnemyGroup.Enemy.length==6,"base combat balance and original friendly roster are restored");
        check(stages[7].BasicInformation.PlayerY==313 && stages[7].BasicInformation.Environment.Collision.length==4 && stages[7].Wave.SubWave.EnemyGroup.Enemy[2].x==588 && findEvent(stages[7],"SiegeEscortArrive")==null,"roof keeps original gameplay without escort gate");
        check(stages[0].BasicInformation.CallbackFunction==undefined && stages[4].BasicInformation.CallbackFunction==undefined && stages[5].BasicInformation.CallbackFunction==undefined,"ordinary rooms have no added polling controller");
        check(stages[1].SpawnPoint.Point[0].x==70 && stages[1].SpawnPoint.Point[0].y==430 && stages[1].SpawnPoint.Point[1].x==95 && stages[1].SpawnPoint.Point[1].y==550 && stages[2].SpawnPoint.Point[0].x==690 && stages[2].SpawnPoint.Point[1].x==1515,"rhino infantry enter at the far left; tigr infantry use APC dismount positions");
        check(stages[3].BasicInformation.Background=="flashswf/backgrounds/gk20_1_BG_围攻.swf" && String(stages[3].BasicInformation.Environment.Alignment).toLowerCase()=="true","only the siege gate uses the helicopter-free aligned variant");
        _root.贴背景图=function():Void {};
        files=["base_siege_relay","base_siege_coil","base_siege_hind","base_siege_equipment",
            "gk1_3_BG_围攻","gk1_2_BG_围攻","gk20_5_BG_围攻","gk1_4_BG_坠毁","gk20_1_BG_围攻"];
        loadNext();
    }
    private static function findEvent(stage:Object,name:String):Object {
        var rows:Array=XMLParser.configureDataAsArray(stage.Event);
        for(var i:Number=0;i<rows.length;i++)if(rows[i].EventName==name)return rows[i];
        return null;
    }
    private static function loadNext():Void {
        if (holder != null) holder.removeMovieClip();
        if (index>=files.length) {finish();return;}
        holder=_root.createEmptyMovieClip("__siegeAssetTest",_root.getNextHighestDepth());
        loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void {
            org.flashNight.arki.scene.BaseSiegeTest.loadedAsset(mc);
        };
        listener.onLoadError=function(mc:MovieClip,code:String):Void {
            org.flashNight.arki.scene.BaseSiegeTest.assetError(code);
        };
        loader.addListener(listener);
        loader.loadClip("../flashswf/backgrounds/"+files[index]+".swf",holder);
    }
    public static function assetError(code:String):Void {check(false,"asset load "+files[index]+" "+code);index++;loadNext();}
    public static function loadedAsset(mc:MovieClip):Void {
        var b:Object=mc.getBounds(mc);
        check(b.xMax-b.xMin>40 && b.yMax-b.yMin>20,"native art has nonempty bounds "+files[index]);
        if(index<4) {
            check(mc.__siegeReady===true,"native state-ready marker "+files[index]);
            mc.cacheAsBitmap=true;check(mc.cacheAsBitmap===true,"actual native asset supports bitmap cache "+files[index]);
        }
        if(index==4 || index==5) {
            var physical:BitmapData=new BitmapData(1688,640,true,0);physical.draw(mc);
            var px:Number=physical.getPixel(index==4?1104:1059,index==4?336:291);physical.dispose();
            var red:Number=(px>>16)&255;var green:Number=(px>>8)&255;var blue:Number=px&255;
            check(!(red>100 && green>100 && blue>100 && Math.abs(red-green)<12 && Math.abs(green-blue)<12),"background does not duplicate the full coil at its former anchor "+files[index]);
        }
        if(index==1) {
            check(mc.shieldMC._totalframes==73 && mc.interferenceMC._totalframes==49,"R5 host exposes the complete 73/49-frame mechanical paths");
            check(mc.effectPowered._totalframes==36,"powered coil uses a native intermittent 36-frame effect");
            mc.effectStandby._visible=false;mc.effectPowered._visible=true;
            mc.effectPowered.gotoAndStop(1);var quiet:Number=fingerprint(mc.effectPowered);
            mc.effectPowered.gotoAndStop(18);
            check(quiet!=fingerprint(mc.effectPowered),"charge and discharge frames have distinct rendered energy");
            mc.shieldMC._visible=true;mc.interferenceMC._visible=false;
            var before:Number=fingerprint(mc);mc.shieldMC.gotoAndStop(1);
            check(mc.shieldMC._currentframe==1 && before!=fingerprint(mc),"shield return reaches the shared tower and changes pixels");
            mc.shieldMC._visible=false;mc.interferenceMC._visible=true;mc.interferenceMC.gotoAndStop(49);
            check(mc.interferenceMC._currentframe==49 && before!=fingerprint(mc),"interference forward reaches its final pose and changes pixels");
        } else if(index==3) {
            check(mc._totalframes==3,"equipment exposes three states");
            var overload:Number=fingerprint(mc);mc.gotoAndStop(2);
            check(mc._currentframe==2,"outage native mode switch");
            var offline:Number=fingerprint(mc);mc.gotoAndStop(3);
            check(mc._currentframe==3,"repair native mode switch");
            check(overload!=offline && offline!=fingerprint(mc),"all equipment states produce different pixels");
        }
        index++;loadNext();
    }
    private static function fingerprint(mc:MovieClip):Number {
        var b:Object=mc.getBounds(mc);var scale:Number=Math.min(460/(b.xMax-b.xMin),460/(b.yMax-b.yMin));
        var mat:Matrix=new Matrix(scale,0,0,scale,10-b.xMin*scale,10-b.yMin*scale);
        var bitmap:BitmapData=new BitmapData(480,480,true,0);bitmap.draw(mc,mat);
        var hash:Number=0;
        for(var y:Number=0;y<480;y+=4) for(var x:Number=0;x<480;x+=4)
            hash=(hash+(bitmap.getPixel32(x,y)>>>0)*(x+y+1))%1000000007;
        bitmap.dispose();return hash;
    }
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else {failed++;trace("BaseSiegeTest FAIL: "+label);}
    }
    private static function finish():Void {
        trace("BaseSiegeTest Tests Passed: "+passed);
        trace("BaseSiegeTest Tests Failed: "+failed);
        trace("BaseSiegeTest Assets Loaded: "+index+"/"+files.length);
        if(failed>0 || passed!=54 || index!=files.length) throw new Error("BaseSiegeTest failed");
        org.flashNight.arki.scene.BaseSiegeSceneTest.runAllTests();
    }
}
