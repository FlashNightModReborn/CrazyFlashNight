import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Rectangle;

/** Real compiled action playback/capture; no AI, combat, saves or item stats. */
class org.flashNight.arki.unit.UnitAI.Custom.SheriffPhaseTwoActionTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var index:Number;
    private static var frame:Number;
    private static var count:Number;
    private static var wait:Boolean;
    private static var actor:MovieClip;
    private static var clock:MovieClip;
    private static var names:Array;
    private static var counts:Array;
    private static var guard:BitmapData;
    private static var capture:Boolean;
    private static var previousCapture:BitmapData;
    private static var palette:Array;
    private static var colorLookup:Object;
    private static var playbackAge:Number;
    private static var capturing:Boolean;
    private static var shotsSeen:Number;

    public static function runAllTests():Void {
        passed=0;failed=0;index=0;frame=1;wait=false;
        palette=[0];colorLookup=new Object();colorLookup["00000"]=0;
        names=["持盾待机","盾击","持盾刺击","持盾射击","持盾冲刺"];
        counts=[1,42,76,138,49];capture=_root.phaseTwoCapture===true;
        trace("SheriffPhaseTwoActionTest Capture Player: "+System.capabilities.playerType);
        _root.createTextField("title",500,18,12,630,40);
        _root.title.text="前治安官 · 二阶段原生动作预览";
        clock=_root.createEmptyMovieClip("actionClock",490);
        clock.onEnterFrame=function():Void {SheriffPhaseTwoActionTest.step();};
        mount();
    }

    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("SheriffPhaseTwoActionTest FAIL: "+label);}
    }

    private static function mount():Void {
        if(actor)actor.removeMovieClip();
        actor=_root.createEmptyMovieClip("previewActor",100);
        var man:MovieClip=actor.attachMovie("前治安官动作-"+names[index],"man",0);
        check(man!=undefined,"native export "+names[index]);
        if(!man){finish();return;}
        man._xscale=27.7084350585938;man._yscale=27.6901245117188;
        man._x=3.4;man._y=-62.35;
        actor._x=310;actor._y=430;actor._xscale=240;actor._yscale=240;
        man.gotoAndPlay(1);frame=1;wait=false;count=counts[index];
        playbackAge=0;capturing=false;shotsSeen=0;
        check(man._totalframes==count,"frame count "+names[index]);
        _root.title.text="二阶段动作："+names[index]+" · "+count+" 帧";
    }

    private static function bitmap():BitmapData {
        var image:BitmapData=new BitmapData(400,360,true,0);
        image.draw(actor,new Matrix(2,0,0,2,150,320),null,"normal",null,true);
        return image;
    }

    public static function step():Void {
        var man:MovieClip=actor.man;
        if(!man)return;
        if(!capturing) {
            playbackAge++;
            if(index==3 && man._currentframe>=26 && man._currentframe<=82 && (man._currentframe-26)%8==0)shotsSeen++;
            if(playbackAge<count+3)return;
            if(index==3)check(shotsSeen==8,"full magazine played before reload");
            check(man._currentframe==count,"autonomous playback stops at guard "+index);
            capturing=true;frame=1;wait=false;return;
        }
        // Let the native display list and load callbacks settle after goto.
        if(!wait){man.gotoAndStop(frame);wait=true;return;}
        wait=false;
        check(man._currentframe==frame,"native frame "+index+"/"+frame);
        check(man.盾具!=undefined,"shield persists "+index+"/"+frame);
        check(man.盾具.手电口!=undefined,"light port persists "+index+"/"+frame);
        check(man.盾具.换弹承托!=undefined && man.盾具.换弹承托._parent==man.盾具,"support belongs to shield "+index+"/"+frame);
        check(man.盾具.承托枪位!=undefined,"shield-local rest port "+index+"/"+frame);
        var bounds:Object=man.getBounds(actor);
        check(bounds.xMin>-1000 && bounds.xMax<2000 && bounds.yMin>-1000 && bounds.yMax<1000,
            "bounded geometry "+index+"/"+frame);
        if(index==2 || index==3) {
            var drawn:Boolean=index==2 ? frame>=9 && frame<=68 : frame>=9 && frame<=131;
            var supported:Boolean=index==3 && frame>=94 && frame<=113;
            check((man.手持武器!=undefined)==(drawn && !supported),"hand weapon ownership "+index+"/"+frame);
            check((man.承托武器!=undefined)==supported,"cradle weapon ownership "+index+"/"+frame);
            var weapon:MovieClip=supported ? man.承托武器 : man.手持武器;
            if(drawn)check((index==2 ? weapon.刀口位置 : weapon.枪口位置)!=undefined,"attack port");
            if(supported)checkSupportedGun(man,weapon);
            if(index==2 && drawn)checkKnifeGrip(man,weapon);
        }
        // Exact same geometry at every shared action endpoint, independent
        // of the compiler's symbol IDs. Compare native rendered pixels.
        // Show the existing native beam in this visual-only fixture. This
        // does not install equipment effects or change any combat values.
        man.盾具.装备光束._visible=true;
        var picks:Array=[[],[],[18,24,36,48],[93,102,110,122],[]];
        var captureFrame:Boolean=false;
        for(var n:Number=0;n<picks[index].length;n++)if(frame==picks[index][n])captureFrame=capture;
        var image:BitmapData;
        if(index==0 || frame==1 || frame==count || captureFrame)image=bitmap();
        if(index==0)guard=image.clone();
        else if(frame==1 || frame==count) {
            var difference=image.compare(guard);
            check(typeof difference=="number" && difference==0,"identical guard pixels "+index+"/"+frame);
            if(typeof difference!="number")difference.dispose();
        }
        if(captureFrame){emit(image,"phase2-"+index+"-"+frame);image=null;}
        if(image)image.dispose();
        if(frame<count){frame++;return;}
        // Autonomous end-stop behavior was verified before frame capture.
        if(man._currentframe!=count)check(false,"unexpected end pose");
        index++;
        if(index<names.length)mount();else finish();
    }

    private static function checkKnifeGrip(man:MovieClip,weapon:MovieClip):Void {
        var hand:MovieClip=man.肢体16;
        check(hand.握点!=undefined && hand.腕点!=undefined,"closed knife hand ports "+frame);
        var oldX:Number=actor._xscale,oldY:Number=actor._yscale;
        var scales:Array=[[240,240],[-240,240],[-160,210]];
        for(var i:Number=0;i<scales.length;i++) {
            actor._xscale=scales[i][0];actor._yscale=scales[i][1];
            var palm:Object={x:0,y:0};var grip:Object={x:0,y:0};
            hand.握点.localToGlobal(palm);weapon.localToGlobal(grip);
            check(Math.abs(palm.x-grip.x)<.65 && Math.abs(palm.y-grip.y)<.65,
                "knife remains inside fist when mirrored or scaled "+frame+"/"+i);

        }
        actor._xscale=oldX;actor._yscale=oldY;
    }

    private static function checkSupportedGun(man:MovieClip,weapon:MovieClip):Void {
        var oldX:Number=actor._xscale,oldY:Number=actor._yscale;
        var scales:Array=[[240,240],[-240,240],[-160,210]];
        for(var i:Number=0;i<scales.length;i++) {
            actor._xscale=scales[i][0];actor._yscale=scales[i][1];
            var rest:Object={x:0,y:0};
            var grip:Object={x:0,y:0};
            man.盾具.承托枪位.localToGlobal(rest);weapon.localToGlobal(grip);
            check(Math.abs(rest.x-grip.x)<.65 && Math.abs(rest.y-grip.y)<.65,
                "supported pistol aligns when mirrored or scaled "+frame+"/"+i);
        }
        actor._xscale=oldX;actor._yscale=oldY;
    }

    private static function finish():Void {
        delete clock.onEnterFrame;
        if(guard)guard.dispose();
        if(previousCapture)previousCapture.dispose();
        trace("SheriffPhaseTwoActionTest Tests Passed: "+passed);
        trace("SheriffPhaseTwoActionTest Tests Failed: "+failed);
        trace("SheriffPhaseTwoActionTest Native Actions Complete: "+index);
        _root.phaseTwoTestComplete();

    }

    private static function emit(image:BitmapData,id:String):Void {
        // Lossless palette + changed rectangle. Full-row trace previously
        // overwhelmed the CS6 Output panel; actual rendered pixels are retained.
        var bounds:Rectangle=new Rectangle(0,0,image.width,image.height);
        if(previousCapture) {
            var difference=image.compare(previousCapture);
            if(typeof difference=="number")bounds=new Rectangle(0,0,0,0);
            else{bounds=difference.getColorBoundsRect(0xFFFFFFFF,0,false);difference.dispose();}
        }
        var additions:String="",rows:String="";
        for(var y:Number=bounds.y;y<bounds.y+bounds.height;y++) {
            var row:String="",last:Number=-1,count:Number=0;
            for(var x:Number=bounds.x;x<bounds.x+bounds.width;x++) {
                var pixel:Number=image.getPixel32(x,y);
                var key:String=hex(pixel),entry=colorLookup[key];
                if(entry==undefined) {
                    entry=palette.length;palette.push(pixel);colorLookup[key]=entry;
                    additions+=(additions.length ? "," : "")+key;
                }
                if(entry==last)count++;
                else{if(count)row+=last.toString(36)+":"+count.toString(36)+",";last=entry;count=1;}
            }
            if(count)row+=last.toString(36)+":"+count.toString(36);
            rows+="[PHASE2_ROW] "+y+" "+row+"\n";
        }
        if(previousCapture)previousCapture.dispose();
        previousCapture=image.clone();
        var header="[PHASE2_FRAME] "+id+" "+image.width+" "+image.height+" "+bounds.x+" "+bounds.y+" "+bounds.width+" "+bounds.height+"\n";
        trace((additions.length ? "[PHASE2_COLORS] "+additions+"\n" : "")+header+rows+"[PHASE2_END] "+id);
        image.dispose();
    }
    private static function hex(pixel:Number):String {
        var low:String=(pixel&65535).toString(16);
        while(length(low)<4)low="0"+low;
        return ((pixel>>>16)&65535).toString(16)+low;
    }
}
