import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.gesh.json.JSONLoader;
import org.flashNight.arki.scene.*;
/** Actual production bake consumer and SceneManager bitmap construction; isolated world only. */
class org.flashNight.arki.scene.Cf6ElevatorCompositeTest {
    private static var saved:Object,rows:Array,row:Object,world:MovieClip,driver:MovieClip,bitmap:BitmapData;
    private static var scene:SceneManager,baker:Function,index:Number,passed:Number,failed:Number,done:Boolean;
    private static var definitionLoader:JSONLoader,definitionAge:Number,definitionReady:Boolean;
    private static var points:Array=[[300,200],[512,200],[700,200],[512,300]];
    private static function check(ok:Boolean,label:String):Void {if(ok) passed++;else {failed++;trace("[FAIL] Cf6ElevatorComposite: "+label);}}
    public static function runAllTests():Void {
        passed=failed=0;index=-1;done=false;row=null;definitionReady=false;definitionAge=0;
        saved={world:_root.gameworld,save:_root._saveExt,path:_root.savePath,stage:_root.当前关卡名,
            manager:StageManager.instance,scene:SceneManager.instance,xmin:_root.Xmin,xmax:_root.Xmax,ymin:_root.Ymin,ymax:_root.Ymax};
        scene=SceneManager.getInstance();saved.sceneWorld=scene.gameworld;baker=_root.贴背景图;
        _root.贴背景图=function(force:Boolean) {return org.flashNight.arki.scene.Cf6ElevatorCompositeTest.requestBake(force);};
        _root.savePath="cf6.elevator.composite.fixture";_root.当前关卡名="书中历险-毒刺行动";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",slot:String(_root.savePath),seed:123,startedAt:1792750000000,planSeed:123}};
        _root.Xmin=_root.Ymin=0;_root.Xmax=1024;_root.Ymax=600;
        rows=[{map:"A10",delay:0},{map:"A10",delay:8},{map:"A13",delay:0},{map:"A13",delay:8}];
        driver=_root.createEmptyMovieClip("__cf6ElevatorCompositeWatch",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6ElevatorCompositeTest.tick();};
        bitmap=new BitmapData(1400,1200,true,0);
        // This focused host lives at scripts/TestLoader.swf. Read the current runtime
        // document explicitly; no synthetic map and no uninitialized PathManager.
        definitionLoader=new JSONLoader("../data/stages/books/cf6-sting.runtime.json",
            function(data:Object):Void {org.flashNight.arki.scene.Cf6ElevatorCompositeTest.definitionLoaded(data);},
            function(error:String):Void {org.flashNight.arki.scene.Cf6ElevatorCompositeTest.loadError("runtime-json:"+error);},false,"LiteJSON");
    }
    public static function definitionLoaded(data:Object):Void {
        if(done || definitionReady) return;
        var shape:Boolean=data.schema=="playable-book.v1" && data.id=="cf6-sting" && data.routeId=="historical"
            && data.maps instanceof Array && data.maps.length==20;
        var transports:Object={},a10:Number=0,a13:Number=0,geometry:Boolean=true;
        if(shape) for(var i:Number=0;i<data.maps.length;i++) {
            var map:Object=data.maps[i];
            if(map.mechanism.transport!=null) transports[map.id]=map.mechanism.transport.sourceSprite;
            if(map.id=="A10" || map.id=="A13") {
                if(map.id=="A10") a10++;else a13++;
                var scrolls:Number=0;
                for(var j:Number=0;j<map.mechanism.layers.length;j++) {
                    var layer:Object=map.mechanism.layers[j];
                    if(layer.role=="elevator-scroll") {
                        scrolls++;
                        if(typeof layer.url!="string" || !(layer.loopHeight>0) || !(layer.clip instanceof Array) || layer.clip.length!=4) geometry=false;
                    }
                }
                if(scrolls!=1 || !Cf6MapPresentation.valid(map.presentation)
                    || map.background!="cf6/CF6_"+map.id+"_BG.swf") geometry=false;
            }
        }
        var count:Number=0;for(var key:String in transports) count++;
        shape=shape && count==3 && transports.A09===1868 && transports.A14===1868 && transports.A18===1868;
        check(shape,"actual current runtime JSON contains 20 rooms and three original transports");
        if(!shape) {finish();return;}
        geometry=geometry && a10==1 && a13==1;
        check(geometry,"loaded runtime has unique A10/A13 presentation and shaft configurations");
        if(!geometry) {finish();return;}
        var accepted:Boolean=BookDefinition.acceptFor("cf6-sting",data) && BookDefinition.get("cf6-sting")===data;
        check(accepted,"production BookDefinition accepts the exact freshly loaded runtime object");
        if(!accepted) {finish();return;}
        definitionReady=true;
        trace("Cf6ElevatorComposite Runtime: url=../data/stages/books/cf6-sting.runtime.json maps="+data.maps.length+" transports="+count);
        next();
    }
    private static function cleanup():Void {
        if(row==null) return;
        for(var i:Number=0;i<row.loads.length;i++) row.loads[i].loader.removeListener(row.loads[i].listener);
        if(world.deadbody.layers[0]!=undefined) world.deadbody.layers[0].dispose();
        if(world.deadbody.layers[2]!=undefined) world.deadbody.layers[2].dispose();
        world.removeMovieClip();
    }
    private static function next():Void {
        cleanup();if(++index==rows.length) {finish();return;}
        row=rows[index];row.age=0;row.phase="background";row.loads=[];row.bakeRequested=false;row.readyTurns=0;
        var maps:Array=BookDefinition.get("cf6-sting").maps;var map:Object;var stageIndex:Number=-1;
        for(var i:Number=0;i<maps.length;i++) if(maps[i].id==row.map) {map=maps[i];stageIndex=i;}
        row.mapSpec=map;
        for(i=0;i<map.mechanism.layers.length;i++) if(map.mechanism.layers[i].role=="elevator-scroll") row.scroll=map.mechanism.layers[i];
        world=_root.createEmptyMovieClip("__cf6ElevatorCompositeWorld"+index,_root.getNextHighestDepth());world._visible=false;
        _root.gameworld=world;world.__stageReturnWorldIdentity={};world.场景背景url="flashswf/backgrounds/"+map.background;
        world.createEmptyMovieClip("背景",-200);world.createEmptyMovieClip("deadbody",-100);
        var cls:Object=StageManager;cls.instance={gameworld:world,currentStage:stageIndex,isFailed:false,isFinished:false};
        scene.gameworld=world;scene.addBodyLayers(1200,1000);
        check(world.deadbody.layers[0].transparent && (world.deadbody.layers[0].getPixel32(512,200)>>>24)==0,"real SceneManager creates transparent layers0 "+index);
        load(world.背景,"../"+world.场景背景url,"background");
    }
    private static function load(clip:MovieClip,url:String,kind:String):Void {
        var loadRow:Object={clip:clip,kind:kind};loadRow.loader=new MovieClipLoader();
        loadRow.listener={entry:loadRow,onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6ElevatorCompositeTest.loaded(this.entry,mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6ElevatorCompositeTest.loadError(error);}};
        loadRow.loader.addListener(loadRow.listener);row.loads.push(loadRow);
        check(loadRow.loader.loadClip(url,clip),"actual production asset load "+index+" "+kind);
    }
    public static function loaded(item:Object,clip:MovieClip):Void {
        if(done || item.ready) return;item.ready=true;
        check(clip._totalframes==(item.kind=="background"?2:1),"actual native frame count "+index+" "+item.kind);
        if(item.kind=="background") {row.backgroundReady=true;return;}
        clip._xscale=clip._yscale=row.mapSpec.presentation.scale*100;clip.stop();row.pending--;
    }
    public static function loadError(error:String):Void {check(false,"asset failure "+error);finish();}
    public static function requestBake(force:Boolean) {
        if(done || row==null) return false;row.bakeRequested=true;
        if(row.delay>0 && row.readyTurns<row.delay) return false;
        // Exact included production function, including Cf6MapPresentation, BD draw and unload.
        return baker(force);
    }
    private static function startScroll():Void {
        var p:Object=row.scroll,parent:MovieClip=world.deadbody;
        row.holder=parent.createEmptyMovieClip("__cf6LayerProbe",-100);
        row.holder._x=p.x-parent._x;row.holder._y=p.y-parent._y;row.pending=2;
        var art:MovieClip=row.holder.createEmptyMovieClip("art",0),art2:MovieClip=row.holder.createEmptyMovieClip("art2",1);
        load(art,"../"+p.url,"scroll0");load(art2,"../"+p.url,"scroll1");
        for(var i:Number=0;i<2;i++) {
            var mask:MovieClip=row.holder.createEmptyMovieClip(i==0?"windowMask":"windowMask2",2+i),r:Array=p.clip;
            mask.beginFill(0);mask.moveTo(r[0],r[1]);mask.lineTo(r[0]+r[2],r[1]);mask.lineTo(r[0]+r[2],r[1]+r[3]);mask.lineTo(r[0],r[1]+r[3]);mask.endFill();
            var target:MovieClip=i==0?art:art2;target.setMask(mask);
        }
        row.phase="scroll";row.age=0;
    }
    private static function pixels(target:MovieClip,m:Matrix):Array {
        bitmap.fillRect(bitmap.rectangle,0);bitmap.draw(target,m);var out:Array=[];
        for(var i:Number=0;i<points.length;i++) out.push(bitmap.getPixel32(points[i][0]+100,points[i][1]+100));return out;
    }
    private static function nonblack(values:Array):Boolean {
        for(var i:Number=0;i<values.length;i++) if((values[i]>>>24)<128 || ((values[i]>>>16)&255)<5
            || ((values[i]>>>8)&255)<5 || (values[i]&255)<5) return false;
        return true;
    }
    private static function maskDiagnostic():Void {
        row.holder.art._y=0;row.holder.art2._y=row.scroll.loopHeight;
        var m:Matrix=row.holder.transform.matrix.clone();m.concat(world.deadbody.transform.matrix);m.tx+=100;m.ty+=100;
        var before:Array=pixels(row.holder,m),black:Boolean=true;
        for(var i:Number=0;i<before.length;i++) if(before[i]!==-16777216) black=false;
        check(black,"negative control reproduces black external masks after asynchronous load "+index);
        var direct:Matrix=row.holder.art.transform.matrix.clone();direct.concat(m);
        var source:Array=pixels(row.holder.art,direct);
        check(nonblack(source),"same loaded native shaft has original nonblack content before external rebind "+index);
        check(Cf6MapMechanism.bindLoadedElevatorMask(row.holder,row.holder.art)
            && Cf6MapMechanism.bindLoadedElevatorMask(row.holder,row.holder.art2),"production helper binds both actual loaded shaft tiles "+index);
        var foreign:MovieClip=row.holder.createEmptyMovieClip("foreign",10);
        check(!Cf6MapMechanism.bindLoadedElevatorMask(row.holder,foreign),"production helper rejects foreign child "+index);
        foreign.removeMovieClip();
        var incomplete:MovieClip=world.createEmptyMovieClip("__missingMaskProbe",world.getNextHighestDepth());
        incomplete.createEmptyMovieClip("art",0);
        check(!Cf6MapMechanism.bindLoadedElevatorMask(incomplete,incomplete.art),"production helper rejects missing owned mask "+index);
        incomplete.removeMovieClip();
        trace("Cf6ElevatorComposite MaskDiagnostic: case="+index+" before="+before.join(",")+" direct="+source.join(",")+" rebound="+pixels(row.holder,m).join(","));
    }
    private static function compareAt(frame:Number):Void {
        var offset:Number=(frame%37)*row.scroll.loopHeight/36;
        row.holder.art._y=-offset;row.holder.art2._y=row.scroll.loopHeight-offset;
        var m:Matrix=row.holder.transform.matrix.clone();m.concat(world.deadbody.transform.matrix);m.tx+=100;m.ty+=100;
        var reference:Array=pixels(row.holder,m);var composed:Array=pixels(world,new Matrix(1,0,0,1,100,100));
        // Authoritative R2 tile SVG wall colors and its baked reference at these
        // points are RGB 16..42, not black; samples differ across the curved wall.
        check(nonblack(reference) && nonblack(composed),"original shaft nonblack material survives loop "+frame+" case="+index);
        var varied:Boolean=false;
        for(var v:Number=1;v<reference.length;v++) if(reference[v]!==reference[0]) varied=true;
        check(varied,"original curved shaft has spatial color variation "+frame+" case="+index);
        var good:Boolean=true;
        for(var i:Number=0;i<points.length;i++) {
            if((reference[i]>>>24)<128 || (composed[i]>>>24)<128) good=false;
            for(var shift:Number=0;shift<24;shift+=8) if(Math.abs(((reference[i]>>>shift)&255)-((composed[i]>>>shift)&255))>2) good=false;
        }
        check(good,"real baked layers0 preserves shaft pixels at loop frame "+frame+" case="+index);
        trace("Cf6ElevatorComposite Pixels: map="+row.map+" delay="+row.delay+" frame="+frame+" shaft="+reference.join(",")+" composed="+composed.join(",")+" bd="+row.baked.join(",")+" origin="+world.deadbody._x+","+world.deadbody._y+" holder="+row.holder._x+","+row.holder._y+" clip="+row.scroll.clip.join(","));
    }
    private static function tick():Void {
        if(done) return;
        if(!definitionReady) {if(++definitionAge>300) {check(false,"runtime JSON initialization timeout");finish();}return;}
        row.age++;
        if(row.age>300) {check(false,"phase timeout "+row.phase);finish();return;}
        if(row.phase=="background") {
            if(row.backgroundReady) row.readyTurns++;
            if(row.delay>0 && row.readyTurns==row.delay && row.bakeRequested) requestBake(true);
            if(world.__cf6BackgroundBake.drawCompleted!==true || world.背景._width!==0) return;
            check(world.__cf6BackgroundBake.worldIdentity===world.__stageReturnWorldIdentity && world.背景._height===0,"actual bake receipt and unloaded source "+index);
            row.baked=[];var empty:Boolean=true;
            for(var i:Number=0;i<points.length;i++) {
                var pixel:Number=world.deadbody.layers[0].getPixel32(Math.round(points[i][0]-world.deadbody.layerOriginX),Math.round(points[i][1]-world.deadbody.layerOriginY));
                row.baked.push(pixel);if((pixel>>>24)>0) empty=false;
            }
            check(empty,"baked static platform leaves original shaft windows transparent "+index);
            startScroll();return;
        }
        if(row.phase=="scroll" && row.pending==0 && row.age>=8) {
            maskDiagnostic();compareAt(0);compareAt(18);compareAt(36);next();
        }
    }
    private static function finish():Void {
        if(done) return;done=true;cleanup();delete driver.onEnterFrame;driver.removeMovieClip();bitmap.dispose();
        _root.贴背景图=baker;_root.gameworld=saved.world;_root._saveExt=saved.save;_root.savePath=saved.path;_root.当前关卡名=saved.stage;
        var cls:Object=StageManager;cls.instance=saved.manager;scene.gameworld=saved.sceneWorld;SceneManager.instance=saved.scene;
        _root.Xmin=saved.xmin;_root.Xmax=saved.xmax;_root.Ymin=saved.ymin;_root.Ymax=saved.ymax;
        trace("Cf6ElevatorCompositeTest Tests Passed: "+passed);trace("Cf6ElevatorCompositeTest Tests Failed: "+failed);
        _root.cf6ElevatorCompositeComplete();
    }
}
