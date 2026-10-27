import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.neur.Event.EventDispatcher;

/** 真实独立SWF导出、BitmapData绘制、胸炮三态、图标双帧和生产切枪事件。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.UnifiedType61AssetTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var library:MovieClip;
    private static var watcher:MovieClip;
    private static var current:MovieClip;
    private static var index:Number;
    private static var pose:Number;
    private static var waitFrame:Boolean;
    private static var hashes:Array;
    private static var complete:Boolean;
    private static var events:Number;
    private static var links:Array=["女变装-Codex-统合61式胸甲上臂", "女变装-Codex-统合61式胸甲右下臂", "女变装-Codex-统合61式胸甲左下臂", "女变装-Codex-统合61式胸甲身体", "女变装-Codex-统合61式腿甲右大腿", "女变装-Codex-统合61式腿甲小腿", "女变装-Codex-统合61式腿甲屁股", "女变装-Codex-统合61式腿甲左大腿", "男变装-Codex-统合61式头部装甲", "男变装-Codex-统合61式手甲右手", "男变装-Codex-统合61式手甲左手", "男变装-Codex-统合61式胸甲上臂", "男变装-Codex-统合61式胸甲右下臂", "男变装-Codex-统合61式胸甲左下臂", "男变装-Codex-统合61式胸甲身体", "男变装-Codex-统合61式腿甲右大腿", "男变装-Codex-统合61式腿甲小腿", "男变装-Codex-统合61式腿甲屁股", "男变装-Codex-统合61式腿甲左大腿", "男变装-Codex-统合61式装甲鞋", "图标-Codex-统合61式装甲鞋", "图标-Codex-统合61式手甲", "图标-Codex-统合61式腿甲", "图标-Codex-统合61式胸甲", "图标-Codex-统合61式头部装甲"];
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[FAIL] UnifiedType61AssetTest: "+label);}}
    public static function runAllTests():Void {
        passed=0;failed=0;index=0;complete=false;events=0;
        check(links.length==25,"exact export manifest");
        checkSwitchEvent();
        library=_root.createEmptyMovieClip("__unified61Library",_root.getNextHighestDepth());
        watcher=_root.createEmptyMovieClip("__unified61AssetWatch",_root.getNextHighestDepth());watcher.age=0;
        watcher.onEnterFrame=function():Void {
            if(++this.age>1800){UnifiedType61AssetTest.check(false,"native asset timeout");UnifiedType61AssetTest.finish();}
        };
        var loader:MovieClipLoader=new MovieClipLoader();
        var listener:Object={};
        listener.onLoadInit=function(mc:MovieClip):Void {if(!UnifiedType61AssetTest.complete)UnifiedType61AssetTest.begin();};
        listener.onLoadError=function(mc:MovieClip,error:String):Void {UnifiedType61AssetTest.check(false,error);UnifiedType61AssetTest.finish();};
        loader.addListener(listener);
        loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",library);
    }
    private static function checkSwitchEvent():Void {
        var u:MovieClip=_root.createEmptyMovieClip("__unified61ModeProbe",_root.getNextHighestDepth());
        var rootMode = _root.攻击模式; var rootGun = _root.长枪;
        _root.攻击模式="foreign-root-mode"; _root.长枪=null;
        u.攻击模式="空手";u.飞行浮空=false;u.长枪={};u.手枪={};u.手枪2={};u.刀={};
        u.dispatcher=new EventDispatcher();u.根据模式重新读取武器加成=function(mode:String):Void {};
        u.状态改变=function(state:String):Void {};
        u.攻击模式切换=_root.主角函数.攻击模式切换;
        u.dispatcher.subscribe("attackModeChanged",function(owner:Object,before:String,after:String):Void {
            if(owner && before!=after)UnifiedType61AssetTest.events++;
        },u);
        u.攻击模式切换("长枪");check(u.攻击模式=="长枪" && events==1,"real switch publishes one event");
        u.攻击模式切换("长枪");check(events==1,"same mode does not redeem again");
        u.攻击模式切换("手枪");check(u.攻击模式=="双枪" && events==2,"real dual gun switch");
        u.攻击模式切换("不存在的模式");check(events==2,"invalid mode emits no event");
        check(_root.攻击模式=="foreign-root-mode","switch cannot mutate definition-scope root state");
        delete u.长枪; _root.长枪={name:"foreign-root-gun"};u.攻击模式切换("长枪");
        check(u.攻击模式=="双枪" && events==2,"missing own gun never borrows root gun");
        _root.攻击模式=rootMode; _root.长枪=rootGun;
        u.长枪={};u.攻击模式="空手";events=0;u.modeReentered=false;
        u.状态改变=function(state:String):Void {if(!this.modeReentered){this.modeReentered=true;this.攻击模式切换("手枪");}};
        u.攻击模式切换("长枪");check(u.攻击模式=="双枪" && events==1,"state callback reentry emits only final successful switch");
        u.攻击模式="空手";events=0;u.modeReentered=false;
        u.状态改变=function(state:String):Void {if(!this.modeReentered){this.modeReentered=true;this.攻击模式切换("长枪");}};
        u.攻击模式切换("长枪");check(u.攻击模式=="长枪" && events==1,"redundant nested switch does not swallow outer success");
        u.状态改变=function(state:String):Void {};u.手雷={};events=0;
        var rootNetwork=_root.是否允许发送联机数据;_root.是否允许发送联机数据=false;u.是否允许发送联机数据=true;
        u.攻击模式切换("手雷");check(u.攻击模式=="长枪" && events==0,"network refusal uses current unit");
        _root.是否允许发送联机数据=true;u.是否允许发送联机数据=false;
        u.攻击模式切换("手雷");check(u.攻击模式=="手雷" && events==1,"root network flag cannot refuse another unit");
        _root.是否允许发送联机数据=rootNetwork;
        var oldControl=_root.控制目标;_root.控制目标=u._name;u.飞行浮空=true;
        u.存储当前飞行状态=function(reason:String):Void {this.flySaved=reason;};
        u.攻击模式切换("兵器");check(u.flySaved=="切换武器","flight state is saved on actual receiver");_root.控制目标=oldControl;
        u.dispatcher.destroy();u.removeMovieClip();
    }
    private static function begin():Void {
        watcher.onEnterFrame=function():Void {UnifiedType61AssetTest.step();};
        attachNext();
    }
    private static function attachNext():Void {
        if(current)current.removeMovieClip();
        if(!(index<links.length)){finish();return;}
        current=library.attachMovie(links[index],"__piece",20000+index);
        check(current!=undefined,"attach "+links[index]);
        if(!current){index++;attachNext();return;}
        pose=1;hashes=[];current.gotoAndStop(1);waitFrame=true;
    }
    private static function step():Void {
        if(complete)return;
        if(waitFrame){waitFrame=false;return;}
        var box:Object=current.getBounds(current);
        var width:Number=box.xMax-box.xMin;var height:Number=box.yMax-box.yMin;
        check(isFinite(width)&&isFinite(height)&&width>0&&height>0,"bounds "+links[index]+" frame "+pose);
        var pixels:BitmapData=new BitmapData(160,160,true,0);
        var scale:Number=144/Math.max(width,height);var matrix:Matrix=new Matrix(scale,0,0,scale,8-box.xMin*scale,8-box.yMin*scale);
        pixels.draw(current,matrix);
        var nonempty:Number=0;var hash:Number=0;
        for(var y:Number=0;y<160;y+=2)for(var x:Number=0;x<160;x+=2){
            var color:Number=pixels.getPixel32(x,y);if((color>>>24)>0)nonempty++;
            hash=(hash*31+(color>>>0))%1000000007;
        }
        pixels.dispose();check(nonempty>10,"native pixels "+links[index]+" frame "+pose);hashes.push(hash);
        var maxPose:Number=links[index].indexOf("图标-")==0?2:(links[index].indexOf("胸甲身体")>-1?3:1);
        if(pose<maxPose){pose++;current.gotoAndStop(pose);waitFrame=true;return;}
        if(maxPose==3)check(hashes[0]!=hashes[1]&&hashes[1]!=hashes[2]&&hashes[0]!=hashes[2],"closed open fire distinct "+links[index]);
        index++;attachNext();
    }
    private static function finish():Void {
        if(complete)return;complete=true;
        if(current)current.removeMovieClip();if(library)library.removeMovieClip();if(watcher)watcher.removeMovieClip();
        trace("UnifiedType61AssetTest Tests Passed: "+passed);trace("UnifiedType61AssetTest Tests Failed: "+failed);
        _root.unifiedAssetFocusedComplete();
    }
}
