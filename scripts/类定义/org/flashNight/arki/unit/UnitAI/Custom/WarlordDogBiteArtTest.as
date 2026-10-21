import flash.display.BitmapData;
import flash.geom.Matrix;

/** Isolated, pixel-only probe. Production movement/damage are deliberately stubbed.
 * Draws the real published actors at their original root registration, no frame fit. */
class org.flashNight.arki.unit.UnitAI.Custom.WarlordDogBiteArtTest {
    private static var dog:MovieClip,legacy:MovieClip,driver:MovieClip;
    private static var age:Number,index:Number,passed:Number,failed:Number,captures:Number;
    private static var finished:Boolean;
    public static function runAllTests():Void {
        age=0;index=0;passed=0;failed=0;captures=0;finished=false;
        _root.是否阴影=true;_root.血腥开关=true;
        _root.初始化敌人模板=function():Void {};
        _root.铁卫犬={初始化:function():Void{},撕咬:function():Void{}};
        _root.子弹区域shoot=function():Void {};
        _root.播放音效=function():Void {};
        _root.获得翻译=function(value:String):String {return value;};
        driver=_root.createEmptyMovieClip("__biteArtDriver",10000);
        dog=_root.attachMovie("敌人-军阀铁卫犬","__biteArtDog",10001,{身高:175});
        legacy=_root.attachMovie("Reference-OriginalZombieDog","__biteArtLegacy",10002,{身高:175});
        setup(dog);setup(legacy);
        check(dog!=undefined && legacy!=undefined,"both real library linkages attach");
        driver.onEnterFrame=function():Void {
            try {WarlordDogBiteArtTest.advance();}
            catch(error) {WarlordDogBiteArtTest.check(false,"exception: "+error);WarlordDogBiteArtTest.finish();}
        };
    }
    private static function setup(actor:MovieClip):Void {
        actor.hp=1000;actor.__ironGuard={ready:true};actor.方向="右";
        actor.移动=function():Void {};
        actor.动画完毕=function():Void {};
        actor.gotoAndStop("空手攻击");actor.man.gotoAndStop(1);
        actor._x=-2000;actor._y=-2000;
        actor.area._visible=false;actor.新版人物文字信息._visible=false;
    }
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else {failed++;trace("WarlordDogBiteArtTest FAIL: "+label);}
    }
    private static function advance():Void {
        if(finished)return;
        if(++age<3)return;
        var frame:Number=index+1;
        check(dog.man._currentframe==frame && legacy.man._currentframe==frame,"settled frame "+frame);
        capture(dog,"guard-right-"+frame,1);
        capture(legacy,"legacy-right-"+frame,1);
        capture(dog,"guard-left-"+frame,-1);
        capture(legacy,"legacy-left-"+frame,-1);
        index++;age=0;
        if(index==24){finish();return;}
        dog.man.gotoAndStop(index+1);legacy.man.gotoAndStop(index+1);
    }
    private static function capture(actor:MovieClip,id:String,direction:Number):Void {
        var bitmap:BitmapData=new BitmapData(400,240,true,0);
        bitmap.draw(actor,new Matrix(2*direction,0,0,2,200,170),null,"normal",null,true);
        var bounds:Object=bitmap.getColorBoundsRect(0xFFFFFFFF,0,false);
        check(bounds.width>60 && bounds.height>40 && bounds.x>0 && bounds.y>0 &&
            bounds.x+bounds.width<400 && bounds.y+bounds.height<240,"visible unclipped "+id);
        var output:String="[BITE_BITMAP_BEGIN] "+id+" 400 240\n";
        for(var y:Number=bounds.y;y<bounds.y+bounds.height;y++) {
            var row:String="",last:Number=0,count:Number=bounds.x;
            for(var x:Number=bounds.x;x<bounds.x+bounds.width;x++) {
                var pixel:Number=bitmap.getPixel32(x,y);
                if(pixel==last)count++;
                else {if(count)row+=hex(last)+":"+count+",";last=pixel;count=1;}
            }
            if(last==0)count+=bitmap.width-(bounds.x+bounds.width);
            else {row+=hex(last)+":"+count+",";last=0;count=bitmap.width-(bounds.x+bounds.width);}
            output+="[BITE_BITMAP_ROW] "+y+" "+row+hex(last)+":"+count+"\n";
        }
        trace(output+"[BITE_BITMAP_END] "+id);bitmap.dispose();captures++;
    }
    private static function hex(value:Number):String {
        var digits:String="0123456789abcdef",s:String="";
        for(var shift:Number=28;shift>=0;shift-=4)s+=digits.charAt((value>>>shift)&15);
        return s;
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        dog.man.stop();legacy.man.stop();
        trace("WarlordDogBiteArtTest Tests Passed: "+passed);
        trace("WarlordDogBiteArtTest Tests Failed: "+failed);
        trace("WarlordDogBiteArtTest Captures: "+captures);
        _root.warlordDogBiteComplete();
    }
}
