import flash.display.BitmapData;
import flash.geom.Matrix;

/** Lightweight native-art diagnostic. Not a production damage/fragment test. */
class org.flashNight.arki.unit.Action.Melee.Cf2TankBossVisualProbe {
    private static var library:MovieClip,driver:MovieClip,actor:MovieClip,loader:MovieClipLoader;
    private static var count:Number,passed:Number,failed:Number;
    private static var ready:Boolean,done:Boolean;
    public static function runAllTests():Void {
        trace("[CF2_PROBE_ENTER]");
        count=passed=failed=0;ready=done=false;
        library=_root.createEmptyMovieClip("__tankArtProbe",1);driver=_root.createEmptyMovieClip("__tankArtClock",2);
        library._visible=false;_root.gameworld=library;_root.暂停=false;_root.是否阴影=true;
        _root.控制目标="none";_root.控制目标全自动=false;
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._visible=false;mc.stop();};
        _root.播放音效=function():Void {};_root.效果=function():Void {};
        _root.子弹区域shoot传递=function(data:Object):Void {};
        _root.初始化敌人模板=function():Void {
            this.hp=1000;this.空手攻击力=100;this.等级=37;this.状态="init";this.攻击目标="none";
            this.方向="右";this._x=this._y=this.Z轴坐标=300;this.行走X速度=this.行走Y速度=3;
            this.刚体=this.免疫击退=this.锁定方向=false;
            this.方向改变=function(side:String):Void {if(!this.锁定方向){this.方向=side;this._xscale=side=="左"?-100:100;}};
            this.状态改变=function(state:String):Void {this.状态=state;this.gotoAndStop(state);};
            this.动画完毕=function():Void {this.状态改变("空手站立");};
            this.移动=function(side:String,speed:Number):Void {this._x+=side=="左"?-speed:speed;};
            this.死亡检测=function():Void {};this.stop();
        };
        _root.地图元件={地图元件破碎动画:function(scope:MovieClip):Number {scope.onEnterFrame=function():Void {};return 1;},
            地图元件破碎动画运行中:function():Boolean {return false;},停止地图元件破碎动画:function():Void {}};
        loader=new MovieClipLoader();
        loader.addListener({onLoadInit:function(mc:MovieClip):Void {Cf2TankBossVisualProbe.loaded();},
            onLoadError:function(mc:MovieClip,error:String):Void {trace("[TEST_FAIL] visual load "+error);Cf2TankBossVisualProbe.finish();}});
        trace("[CF2_PROBE_LOAD] "+loader.loadClip("../flashswf/arts/new/Codex大机器人素材.swf",library));
        driver.onEnterFrame=function():Void {Cf2TankBossVisualProbe.tick();};
    }
    private static function loaded():Void {
        trace("[CF2_PROBE_LOADED]");
        actor=library.attachMovie("敌人-CF2大机器人","visualTank",2);
        trace("[CF2_PROBE_ACTOR] "+actor+" hp="+actor.hp+" identity="+actor.tankIdentity
            +" tick="+typeof actor.tankTick+" world="+actor.tankWorldValid());
        ready=true;count=0;
    }
    private static function pose(state:String):Void {
        actor.tankCancelAttack();
        actor.方向改变("右");
        actor.状态改变(state);
        if(actor.area!=null && actor.area._visible!==false){
            failed++;trace("[TEST_FAIL] area visible on "+state);
        }
        if(state!="血腥死" && actor.man.tankArt._currentframe!=1){
            failed++;trace("[TEST_FAIL] tankArt frame mismatch on "+state+" got="+actor.man.tankArt._currentframe+" want=1");
        }
    }
    private static function tick():Void {
        if(done)return;count++;
        if(!ready){if(count>600){failed++;trace("[TEST_FAIL] visual load watchdog");finish();}return;}
        if(count==3)pose("空手站立");
        if(count==8)render("stand-right");
        if(count==8 || count==40 || count==90){
            var b:MovieClip=actor.man;
            trace("[CF2_PROBE_CLOCK] count="+count+" unitClock="+actor.tankClock+" mode="+b.tankMode
                +" frameId="+b.tankFrameIdentity+" driverId="+b.tankBodyDriver.bodyIdentity
                +" identityMatch="+(b.tankFrameIdentity===b.tankBodyDriver.bodyIdentity)
                +" owner="+actor.tankOwner+" bodyTick="+typeof actor.tankBodyTick
                +" art="+b.tankArt+" artStart="+b.tankArtStart+" artFrame="+b.tankArt._currentframe);
        }
        if(count==10)pose("空手行走");
        if(count==18)render("walk-right");
        if(count==20)pose("机枪射击");
        if(count==40)render("gatling-right");
        if(count==65)pose("激光扫射");
        if(count==90)render("laser-right");
        if(count==130)pose("全弹发射");
        if(count==160)render("barrage-right");
        if(count==310)pose("移动全弹");
        if(count==345)render("mobile-right");
        if(count==520){actor.hp=0;pose("血腥死");}
        if(count==525)render("death-start");
        if(count==545)render("death-fragments");
        if(count==570)finish();
    }
    private static function hex(value:Number):String {
        var s:String="",digits:String="0123456789abcdef";
        for(var k:Number=28;k>=0;k-=4)s+=digits.charAt((value>>>k)&15);return s;
    }
    private static function render(name:String):Void {
        var w:Number=1200,h:Number=650;
        var image:BitmapData=new BitmapData(w,h,true,0xffe8e6e2);
        var m:Matrix=actor.transform.matrix;m.tx=700;m.ty=500;
        actor.人物文字信息._visible=false;image.draw(actor,m);
        var pixels:Number=0;
        for(var y:Number=0;y<h;y+=4)for(var x:Number=0;x<w;x+=4)if(image.getPixel(x,y)!=0xe8e6e2)pixels++;
        if(pixels>100)passed++;else{failed++;trace("[TEST_FAIL] empty native visual "+name);}
        trace("[CF2_PROBE_IMAGE] "+name+" state="+actor.状态+" frame="+actor.man._currentframe+" pixels="+pixels);
        if(_root.tankProbeCapture!==true){image.dispose();return;}
        trace("[CF2_TANK_IMAGE_BEGIN] "+name+" "+w+" "+h);
        // Skip native-confirmed background pixels without cropping/rescaling
        // the actual image or changing its lossless full-canvas row format.
        var content:Object=image.getColorBoundsRect(0xffffffff,0xffe8e6e2,false);
        var left:Number=content.x,right:Number=content.x+content.width;
        var top:Number=content.y,bottom:Number=content.y+content.height;
        var chunk:String="";
        for(var y:Number=0;y<h;y++){
            var parts:Array=[];
            if(y<top || !(y<bottom) || !(left<right)){
                parts.push("ffe8e6e2:"+w);
            }else{
                if(left>0)parts.push("ffe8e6e2:"+left);
                var value:Number=image.getPixel32(left,y),run:Number=1;
                for(var x:Number=left+1;x<right;x++){
                    var next:Number=image.getPixel32(x,y);
                    if(next==value)run++;else{parts.push(hex(value)+":"+run);value=next;run=1;}
                }
                parts.push(hex(value)+":"+run);
                if(right<w)parts.push("ffe8e6e2:"+(w-right));
            }
            var row:String=y+"="+parts.join(",")+";";
            if(length(chunk)>0 && length(chunk)+length(row)>8192){trace("[CF2_TANK_IMAGE_DATA] "+name+" "+chunk);chunk="";}
            chunk+=row;
        }
        if(length(chunk)>0)trace("[CF2_TANK_IMAGE_DATA] "+name+" "+chunk);
        trace("[CF2_TANK_IMAGE_END] "+name);image.dispose();
    }
    private static function finish():Void {
        if(done)return;done=true;
        if(actor!=null)actor.removeMovieClip();
        library.removeMovieClip();delete driver.onEnterFrame;driver.removeMovieClip();
        trace("Cf2TankBossVisualProbe: "+passed+" passed, "+failed+" failed");
        _root.cf2TankProbeComplete();
    }
}
