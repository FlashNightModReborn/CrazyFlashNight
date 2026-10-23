import flash.display.BitmapData;
import flash.geom.Matrix;
/** Real old/new canonical SWF pixel comparison, plus separate native shaft source probes. */
class org.flashNight.arki.scene.Cf6NativeSurfaceTest {
    private static var fixture:MovieClip,driver:MovieClip,bitmap:BitmapData,rows:Array,entry:Object,old:Object;
    private static var index:Number,passed:Number,failed:Number,done:Boolean;
    private static function check(ok:Boolean,label:String):Void {if(ok) passed++;else {failed++;trace("[FAIL] Cf6NativeSurface: "+label);}}
    public static function runAllTests():Void {
        passed=failed=0;index=-1;done=false;old={};
        rows=[{id:"A18",kind:"floor",version:"old",url:"../tmp/cf6-fieldfix-20261023/traversal/old-native/CF6_A18_BG.swf",upper:[[132,245],[335,245],[542,245],[746,245],[949,245],[1153,245],[1360,245],[1564,245]],lower:[[104,372],[307,372],[514,372],[718,372],[921,372],[1125,372],[1332,372],[1536,372]]},{id:"A18",kind:"floor",version:"new",url:"../flashswf/backgrounds/cf6/CF6_A18_BG.swf",upper:[[132,245],[335,245],[542,245],[746,245],[949,245],[1153,245],[1360,245],[1564,245]],lower:[[104,372],[307,372],[514,372],[718,372],[921,372],[1125,372],[1332,372],[1536,372]]},{id:"A19",kind:"floor",version:"old",url:"../tmp/cf6-fieldfix-20261023/traversal/old-native/CF6_A19_BG.swf",upper:[[132,245],[335,245],[540,245],[745,245],[949,245],[1153,245],[1360,245]],lower:[[104,372],[307,372],[514,372],[718,372],[1499,371],[921,372],[1125,372],[1332,372]]},{id:"A19",kind:"floor",version:"new",url:"../flashswf/backgrounds/cf6/CF6_A19_BG.swf",upper:[[132,245],[335,245],[540,245],[745,245],[949,245],[1153,245],[1360,245]],lower:[[104,372],[307,372],[514,372],[718,372],[1499,371],[921,372],[1125,372],[1332,372]]},{id:"A20",kind:"floor",version:"old",url:"../tmp/cf6-fieldfix-20261023/traversal/old-native/CF6_A20_BG.swf",upper:[[155,246],[359,246],[566,246],[770,246],[973,246],[1176,246]],lower:[[104,500],[307,500],[514,500],[718,500],[1499,500],[921,500],[1125,500],[1332,500]]},{id:"A20",kind:"floor",version:"new",url:"../flashswf/backgrounds/cf6/CF6_A20_BG.swf",upper:[[155,246],[359,246],[566,246],[770,246],[973,246],[1176,246]],lower:[[104,500],[307,500],[514,500],[718,500],[1499,500],[921,500],[1125,500],[1332,500]]},{id:"A22",kind:"floor",version:"old",url:"../tmp/cf6-fieldfix-20261023/traversal/old-native/CF6_A22_BG.swf",upper:[[155,246],[359,246],[566,246],[770,246],[973,246],[1176,246]],lower:[[104,500],[307,500],[514,500],[718,500],[1499,500],[921,500],[1125,500],[1332,500]]},{id:"A22",kind:"floor",version:"new",url:"../flashswf/backgrounds/cf6/CF6_A22_BG.swf",upper:[[155,246],[359,246],[566,246],[770,246],[973,246],[1176,246]],lower:[[104,500],[307,500],[514,500],[718,500],[1499,500],[921,500],[1125,500],[1332,500]]},{id:"A10",kind:"shaft",version:"current",url:"../flashswf/backgrounds/cf6/CF6_A10_elevator-scroll.swf",upper:[[350,100],[350,250],[350,400]],lower:[]},{id:"A13",kind:"shaft",version:"current",url:"../flashswf/backgrounds/cf6/CF6_A13_elevator-scroll.swf",upper:[[350,100],[350,250],[350,400]],lower:[]}];
        fixture=_root.createEmptyMovieClip("__cf6SurfaceFixture",_root.getNextHighestDepth());fixture._visible=false;
        driver=_root.createEmptyMovieClip("__cf6SurfaceWatch",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6NativeSurfaceTest.tick();};
        bitmap=new BitmapData(2400,900,true,0);next();
    }
    private static function next():Void {
        if(entry!=null) {entry.loader.removeListener(entry.listener);entry.holder.removeMovieClip();}
        if(++index==rows.length) {finish();return;}
        entry=rows[index];entry.age=0;entry.holder=fixture.createEmptyMovieClip("holder"+index,index);
        entry.clip=entry.holder.createEmptyMovieClip("art",0);
        entry.loader=new MovieClipLoader();entry.listener={row:entry,
            onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.Cf6NativeSurfaceTest.loaded(this.row,mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {org.flashNight.arki.scene.Cf6NativeSurfaceTest.loadError(this.row,error);}};
        entry.loader.addListener(entry.listener);check(entry.loader.loadClip(entry.url,entry.clip),"actual SWF request "+entry.id+" "+entry.version);
    }
    public static function loaded(row:Object,mc:MovieClip):Void {
        if(done || row!==entry || row.ready) return;row.ready=true;row.age=0;mc.stop();
        check(mc._totalframes==(row.kind=="floor"?2:1),"actual native root frames "+row.id+" "+row.version);
    }
    public static function loadError(row:Object,error:String):Void {
        if(done || row!==entry) return;check(false,"load "+row.id+" "+error);finish();
    }
    private static function sample(points:Array):Object {
        var result:Object={opaque:0,pixels:[]};
        for(var i:Number=0;i<points.length;i++) {
            var pixel:Number=bitmap.getPixel32(points[i][0]+100,points[i][1]+100);
            result.pixels.push(pixel);if((pixel>>>24)>128) result.opaque++;
        }
        return result;
    }
    private static function draw(target:MovieClip):Void {
        bitmap.fillRect(bitmap.rectangle,0);bitmap.draw(target,new Matrix(1,0,0,1,100,100));
    }
    private static function tick():Void {
        if(done) return;entry.age++;
        if(!entry.ready) {if(entry.age>300) {check(false,"native surface load timeout");finish();}return;}
        if(entry.age<8) return;
        draw(entry.clip);var upper:Object=sample(entry.upper),lower:Object=sample(entry.lower);
        trace("Cf6NativeSurface Pixels: map="+entry.id+" version="+entry.version+" upperOpaque="+upper.opaque+"/"+entry.upper.length+" lowerOpaque="+lower.opaque+"/"+entry.lower.length+" upper="+upper.pixels.join(",")+" lower="+lower.pixels.join(","));
        if(entry.kind=="floor") {
            if(entry.version=="old") old[entry.id]={upper:upper,lower:lower};
            else {
                var before:Object=old[entry.id];
                check(upper.opaque==entry.upper.length,"all new upper floor cells have pixels "+entry.id);
                check(lower.opaque==entry.lower.length,"all new lower floor cells remain filled "+entry.id);
                check(before.upper.opaque<upper.opaque,"old native upper-row defect is reproduced and improved "+entry.id);
                var same:Boolean=before.lower.pixels.length==lower.pixels.length;
                for(var i:Number=0;i<lower.pixels.length;i++) if(before.lower.pixels[i]!==lower.pixels[i]) same=false;
                check(same,"unaffected lower-cell pixels remain exact "+entry.id);
            }
        } else {
            check(upper.opaque==entry.upper.length,"native shaft source has nontransparent wall pixels "+entry.id);
            var mask:MovieClip=entry.holder.createEmptyMovieClip("windowMask",1);
            mask.beginFill(0xFFFFFF,100);mask.moveTo(50,60);mask.lineTo(650,60);mask.lineTo(650,410);mask.lineTo(50,410);mask.lineTo(50,60);mask.endFill();
            entry.clip.setMask(mask);draw(entry.holder);var clipped:Object=sample(entry.upper);
            var outside:Object=sample([[350,20],[25,200],[675,200]]);
            check(clipped.opaque==entry.upper.length && outside.opaque==0,"native shaft survives reviewed source-space window mask "+entry.id);
            trace("Cf6NativeSurface ShaftMask: map="+entry.id+" inside="+clipped.opaque+" outside="+outside.opaque);
        }
        next();
    }
    private static function finish():Void {
        if(done) return;done=true;if(entry!=null) entry.loader.removeListener(entry.listener);
        delete driver.onEnterFrame;driver.removeMovieClip();fixture.removeMovieClip();bitmap.dispose();
        trace("Cf6NativeSurfaceTest Tests Passed: "+passed);trace("Cf6NativeSurfaceTest Tests Failed: "+failed);
        _root.cf6NativeSurfaceComplete();
    }
}
