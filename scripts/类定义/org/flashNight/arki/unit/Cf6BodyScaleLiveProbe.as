import org.flashNight.arki.unit.*;
import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Point;

/** Read-only alpha measurement. Caller owns native initialization, authored standing pose and weapon visibility.
 * This class never changes actor transforms, timelines, masks, visibility, weapons or gameplay state.
 */
class org.flashNight.arki.unit.Cf6BodyScaleLiveProbe {
    private static var RESOLUTION:Number=4;
    private static var HEIGHT_TOLERANCE:Number=1;
    private static var SCALE_TOLERANCE:Number=0.02;
    private static function worldMatrix(body:MovieClip,world:MovieClip):Matrix {
        // A 1000px basis avoids amplifying AVM1's 1/20px coordinate conversion rounding.
        var p:Object={x:0,y:0},x:Object={x:1000,y:0},y:Object={x:0,y:1000};
        body.localToGlobal(p);body.localToGlobal(x);body.localToGlobal(y);
        world.globalToLocal(p);world.globalToLocal(x);world.globalToLocal(y);
        return new Matrix((x.x-p.x)/1000,(x.y-p.y)/1000,(y.x-p.x)/1000,(y.y-p.y)/1000,p.x,p.y);
    }
    public static function measure(units:Array):Object {
        var result:Object={measured:0,passed:0,failed:0,rows:[]},seen:Object={};
        var expectedRows:Array=Cf6BodyScaleNativeData.rows(),expected:Object={};
        for(var ri:Number=0;ri<expectedRows.length;ri++)expected[expectedRows[ri].linkage]=expectedRows[ri];
        for(var i:Number=0;i<units.length;i++) {
            var actor:MovieClip=units[i],kind:String=actor.兵种,rowPolicy:Object=expected[kind];
            if(rowPolicy==undefined || seen[kind] || typeof(actor.man)!="movieclip" || actor.version==undefined
                || actor.__unitInitializedVersion!==actor.version || actor._visible===false || actor.man._visible===false) {
                result.failed++;trace("[FAIL] Cf6BodyScaleLiveProbe invalid/duplicate/uninitialized "+kind);continue;
            }
            seen[kind]=true;
            var bounds:Object=actor.man.getBounds(actor._parent);
            var left:Number=Math.floor(bounds.xMin)-2,top:Number=Math.floor(bounds.yMin)-2;
            var width:Number=Math.ceil(bounds.xMax-left+2)*RESOLUTION,height:Number=Math.ceil(bounds.yMax-top+2)*RESOLUTION;
            if(!(width>0 && height>0 && width<=2880 && height<=2880)) {
                result.failed++;trace("[FAIL] Cf6BodyScaleLiveProbe invalid raster extent "+kind+" "+width+"x"+height);continue;
            }
            var matrix:Matrix=worldMatrix(actor.man,actor._parent);
            matrix.tx-=left;matrix.ty-=top;matrix.scale(RESOLUTION,RESOLUTION);
            var raw:BitmapData=new BitmapData(width,height,true,0),solid:BitmapData=new BitmapData(width,height,true,0);
            raw.draw(actor.man,matrix);
            solid.threshold(raw,raw.rectangle,new Point(0,0),">=",0x80000000,0xFFFFFFFF,0xFF000000,false);
            var alphaBox:Object=solid.getColorBoundsRect(0xFF000000,0,false);
            var nonempty:Boolean=alphaBox.width>0 && alphaBox.height>0;
            var unclipped:Boolean=alphaBox.x>0 && alphaBox.y>0 && alphaBox.right<width && alphaBox.bottom<height;
            var bodyHeight:Number=alphaBox.height/RESOLUTION;
            var expectedScale:Number=Cf6BodyScaleRules.heightScale(kind,actor.身高,100);
            var good:Boolean=nonempty && unclipped && Math.abs(bodyHeight-rowPolicy.expectedPixels)<=HEIGHT_TOLERANCE
                && Math.abs(Math.abs(actor._xscale)-expectedScale)<SCALE_TOLERANCE
                && Math.abs(actor._yscale-expectedScale)<SCALE_TOLERANCE;
            var row:Object={linkage:kind,height:bodyHeight,expectedPixels:rowPolicy.expectedPixels,
                footY:top+alphaBox.bottom/RESOLUTION-actor._y,scaleX:actor._xscale,scaleY:actor._yscale,expectedScale:expectedScale,
                standingFrame:actor._currentframe,bodyFrame:actor.man._currentframe,nonempty:nonempty,unclipped:unclipped,
                alphaMinimum:128,supersample:RESOLUTION,heightTolerance:HEIGHT_TOLERANCE,ok:good,
                basis:"actual native man alpha>=128 pixels; authored masks and all production transforms retained; caller hides named weapons"};
            result.rows.push(row);result.measured++;if(good)result.passed++;else result.failed++;
            trace("Cf6BodyScaleLiveProbe "+kind+" opaqueBodyHeight="+bodyHeight+" expected="+rowPolicy.expectedPixels
                +" delta="+(bodyHeight-rowPolicy.expectedPixels)+" footY="+row.footY+" scale="+actor._yscale
                +" expectedScale="+expectedScale+" bodyFrame="+actor.man._currentframe+" alpha=128 res=4 unclipped="+unclipped+" ok="+good);
            raw.dispose();solid.dispose();
        }
        if(result.measured!=7)result.failed++;
        trace("Cf6BodyScaleLiveProbe: "+result.measured+" measured, "+result.failed+" failed");return result;
    }
}
