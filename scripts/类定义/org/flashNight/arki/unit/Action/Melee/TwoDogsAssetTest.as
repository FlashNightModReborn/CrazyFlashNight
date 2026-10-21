import flash.display.BitmapData;
import flash.geom.Matrix;

/** Published native dogs through explicit shared imports in one native host.
 * Initialization/movement and outgoing bullets are fixtures; no save is loaded.
 */
class org.flashNight.arki.unit.Action.Melee.TwoDogsAssetTest {
    private static var hosts:Array, cases:Array;
    private static var driver:MovieClip, loadedCount:Number, ticks:Number, passed:Number, failed:Number;
    private static var ready:Boolean, finished:Boolean, phase:Number, captureIndex:Number;
    private static var captureActors:Array, captureQueue:Array, colors:Object;
    private static var links:Array=["敌人-僵尸1-狗","敌人-制式军警犬","敌人-盗贼撕咬犬"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] TwoDogsAssetTest: "+label);}
    }
    public static function action(actor:MovieClip):MovieClip {
        for(var key:String in actor) {
            var value:Object=actor[key];
            if(typeof(value)=="movieclip" && value._parent==actor &&
                (value._totalframes==50 || value._totalframes==15 || value._totalframes==87 ||
                 value._totalframes==40 || value._totalframes==119 || value._totalframes==94 || value._totalframes==89))return MovieClip(value);
        }
        return null;
    }
    public static function runAllTests():Void {
        hosts=[];cases=[];loadedCount=ticks=passed=failed=phase=captureIndex=0;
        ready=finished=false;colors={};captureQueue=null;
        _root.暂停=false;_root.控制目标="__no_player";_root.控制目标全自动=false;
        _root.gameworld=_root.createEmptyMovieClip("__twoDogsWorld",_root.getNextHighestDepth());
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};_root.效果=function():Void {};_root.add2map2=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.子弹区域shoot=function(sound,scatter,spread,effect,kind,power,speed,range,mapEffect,owner,x,y,z,hostile,knock,hitEffect):Void {
            TwoDogsAssetTest.shot(String(owner),Number(power),Number(range),Number(x),Number(y),Boolean(hostile),Number(knock),String(kind));
        };
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=5;
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";this.是否为敌人=true;
            this.攻击目标="无";this.Z轴坐标=this._y=200;this._x=200;this.fixtureDone=0;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:100}};
            this.swapDepths=function():Void {};this.行走=function():Void {};this.移动=function():Void {};
            this.击飞浮空=function():Void {};this.击飞倒地=function():Void {};this.击倒呐喊=function():Void {};
            this.方向改变=function(dir:String):Void {this.方向=dir;var a:MovieClip=TwoDogsAssetTest.action(this);if(a)a._xscale=dir=="左"?-100:100;};
            this.状态改变=function(state:String):Void {this.状态=state;this.gotoAndStop(state);};
            this.动画完毕=function():Void {this.fixtureDone++;TwoDogsAssetTest.action(this).stop();};
            this.死亡检测=function():Void {this.fixtureDone++;TwoDogsAssetTest.action(this).stop();};
            this.fixtureBorn=true;this.stop();
        };
        _root.gameworld._visible=false;
        hosts=[_root.gameworld,_root.gameworld,_root.gameworld];
        driver=_root.createEmptyMovieClip("__twoDogsDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {TwoDogsAssetTest.tick();};
        loaded();
    }
    private static function loaded():Void {
        for(var v:Number=0;v<3;v++)for(var facing:Number=0;facing<2;facing++)for(var move:Number=0;move<4;move++) {
            var index:Number=cases.length,owner:String="dogCase"+index;
            var actor:MovieClip=hosts[v==0?0:1].attachMovie(links[v],owner,hosts[v==0?0:1].getNextHighestDepth(),{身高:120,fixtureCase:index});
            check(actor!=null,"attach via native shared imports "+owner);
            if(actor==null){finish();return;}
            cases.push({actor:actor,variant:v,facing:facing,move:move,shots:[],owner:owner});
        }
        captureActors=[];
        for(var kind:Number=1;kind<3;kind++) {
            var direct:MovieClip=hosts[2].attachMovie(links[kind],"dogDirect"+kind,hosts[2].getNextHighestDepth(),{身高:120,fixtureCase:-1});
            check(direct!=null,"attach direct owner "+links[kind]);captureActors.push(direct);
        }
        ready=true;ticks=0;
    }
    public static function shot(owner:String,power:Number,range:Number,x:Number,y:Number,hostile:Boolean,knock:Number,kind:String):Void {
        for(var i:Number=0;i<cases.length;i++)if(cases[i].owner==owner) {
            cases[i].shots.push({tick:ticks,frame:action(cases[i].actor)._currentframe,power:power,range:range,x:x,y:y,hostile:hostile,knock:knock,kind:kind});return;
        }
    }
    private static function tick():Void {
        if(finished)return;ticks++;
        if(captureQueue!=null){captureStep();return;}
        if(!ready){if(ticks>600){check(false,"load timeout");finish();}return;}
        if(ticks==3) {
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i],u:MovieClip=c.actor;
                check(u.fixtureBorn===true,"native initialization "+i);
                check(u.hp_min==120 && u.hp_max==1000 && u.空手攻击力_min==15 && u.空手攻击力_max==300,"inherited native hp and attack "+i);
                check(u.随机移动机率==100 && u.不掉钱===true && u.奔跑速度倍率==1 && u.中心高度==30,"inherited native flags "+i);
                u.方向=c.facing==0?"右":"左";u.状态改变(c.move==0?"空手攻击":"血腥死");
            }
        }
        if(ticks==5)for(var j:Number=0;j<cases.length;j++) {
            var item:Object=cases[j],a:MovieClip=action(item.actor);
            check(a!=null,"native action clip "+j);
            a._xscale=item.facing==0?100:-100;item.actor.fixtureDone=0;item.shots=[];
            if(item.move==0)a.gotoAndPlay(1);else a.gotoAndPlay("a"+(item.move-1));
        }
        if(ticks==115) {
            for(var k:Number=0;k<cases.length;k++) {
                var current:Object=cases[k],base:Object=cases[current.facing*4+current.move];
                check(current.actor.fixtureDone==1,"one terminal callback "+k+" = "+current.actor.fixtureDone);
                // The published dog emits at frames 7, 13 and 16. XFL frame 8
                // only moves the existing hit instance, so onClipEvent(load)
                // does not run again. readback.py checks this in the real SWFs.
                check(current.shots.length==(current.move==0?3:0),"actual native emission count "+k+" = "+current.shots.length);
                var actualFrames:Array=[];
                for(var si:Number=0;si<current.shots.length;si++)actualFrames.push(current.shots[si].frame);
                trace("[DOG_CASE] "+k+" variant="+current.variant+" facing="+current.facing+" move="+current.move+" emissions="+current.shots.length+" frames="+actualFrames.join(",")+" callbacks="+current.actor.fixtureDone);
                if(current.variant>0) {
                    check(current.shots.length==base.shots.length,"baseline emission parity "+k);
                    for(var n:Number=0;n<current.shots.length;n++) {
                        var s:Object=current.shots[n],r:Object=base.shots[n];
                        check(s.power==100 && s.range==30 && s.knock==10 && s.kind=="近战子弹","actual outgoing hit fields "+k+"/"+n);
                        check(s.tick==r.tick && s.frame==r.frame && s.power==r.power && s.range==r.range && s.hostile==r.hostile && s.knock==r.knock && s.kind==r.kind && Math.abs(s.x-r.x)<0.05 && Math.abs(s.y-r.y)<0.05,"unchanged live hit frame/position/contract "+k+"/"+n);
                    }
                }
            }
            captureQueue=_root.twoDogsCapturePoses;captureIndex=phase=0;
            check(captureQueue.length>0,"native visual queue");
        }
    }
    private static function hex(value:Number):String {
        var key:String="c"+value;if(colors[key]!=undefined)return colors[key];
        var out:String="";for(var shift:Number=24;shift>=0;shift-=8){var s:String=((value>>>shift)&255).toString(16);out+=(s.length<2?"0":"")+s;}
        colors[key]=out;return out;
    }
    private static function captureStep():Void {
        if(captureIndex>=captureQueue.length){trace("[DOG_IMAGES_COMPLETE] frames="+captureQueue.length);finish();return;}
        var p:Array=captureQueue[captureIndex],actor:MovieClip=captureActors[p[0]],source:MovieClip;
        if(phase==0){actor.方向="右";actor.状态改变(p[2]);phase=1;return;}
        source=action(actor);
        if(phase==1){check(source!=null,"capture clip "+p[1]);source.gotoAndStop(p[3]);phase=2;return;}
        var detail:Boolean=String(p[1]).indexOf("-attack-")>=0;
        var w:Number=detail?240:180,h:Number=detail?186:140,scale:Number=Math.min((w-20)/p[6],(h-20)/p[7]);
        var m:Matrix=new Matrix(scale,0,0,scale,10-p[4]*scale,10-p[5]*scale);
        var bd:BitmapData=new BitmapData(w,h,true,0);bd.draw(source,m);
        var visible:Number=0;for(var yy:Number=0;yy<h;yy+=3)for(var xx:Number=0;xx<w;xx+=3)if((bd.getPixel32(xx,yy)>>>24)>128)visible++;
        check(p[8]?visible==0:visible>20*(w*h)/(360*280),"native visible/death-empty contract "+p[1]+" pixels="+visible);
        if(p.length>9)for(var probe:Number=0;probe<p[9].length;probe++) {
            var sample:Array=p[9][probe];
            var pixel:Number=bd.getPixel32(Math.round(10+(sample[0]-p[4])*scale),Math.round(10+(sample[1]-p[5])*scale));
            var alpha:Number=pixel>>>24,red:Number=(pixel>>>16)&255,green:Number=(pixel>>>8)&255,blue:Number=pixel&255;
            if(sample[2]=="gap")check(alpha<32,"open anterior gape "+p[1]);
            else if(sample[2]=="tongue")check(alpha>240 && red>green*1.2 && red>blue,"visible tongue "+p[1]);
            else check(alpha>240,"opaque rear cheek "+p[1]);
        }
        trace("[DOG_IMAGE_BEGIN] "+p[1]+" "+w+" "+h+" sparse");
        var written:Number=0;
        colors={};var batch:Array=[],batchBytes:Number=0;
        for(var row:Number=0;row<h;row++) {
            var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
            for(var col:Number=1;col<w;col++){var value:Number=bd.getPixel32(col,row);if(value==last)count++;else{parts.push(count+":"+hex(last));last=value;count=1;}}
            parts.push(count+":"+hex(last));
            if(parts.length!=1 || last!=0){
                var line:String="[DOG_IMAGE_ROW] "+p[1]+" "+row+" "+parts.join(",");
                if(batchBytes+line.length>12000){trace(batch.join("\n"));batch=[];batchBytes=0;}
                batch.push(line);batchBytes+=line.length+1;written++;
            }
        }
        if(batch.length>0)trace(batch.join("\n"));
        trace("[DOG_IMAGE_END] "+p[1]+" rows="+written);bd.dispose();captureIndex++;phase=0;
    }
    private static function finish():Void {
        if(finished)return;finished=true;driver.onEnterFrame=null;
        trace("TwoDogsAssetTest: "+passed+" passed, "+failed+" failed; 24 actual timeline cases");
        _root.twoDogsAssetComplete();
    }
}
