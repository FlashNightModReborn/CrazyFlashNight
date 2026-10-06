import flash.display.BitmapData;
import flash.geom.Rectangle;
import flash.geom.Matrix;
import org.flashNight.arki.unit.Action.Melee.BladeShootCore;
import org.flashNight.gesh.depth.DepthManager;

/** Native published asset readback. Engine initialization, targets and bullet sink
 * are fixtures. Uses the actual enemy controllers and timeline/clip scripts.
 * This is an asset/resource test; it does not settle combat or touch saves. */
class org.flashNight.arki.unit.Action.Melee.BlackShadowAssetTest {
    private static var passed:Number, failed:Number, ticks:Number, loadedCount:Number;
    private static var world:MovieClip, black:MovieClip, teacher:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object, cases:Array, probes:Array;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[TEST_FAIL] BlackShadowAssetTest: "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=ticks=loadedCount=0;cases=[];probes=[];
        Stage.scaleMode="noScale";
        world=_root.createEmptyMovieClip("__blackShadowWorld",_root.getNextHighestDepth());
        black=world.createEmptyMovieClip("blackLibrary",world.getNextHighestDepth());
        teacher=world.createEmptyMovieClip("teacherLibrary",world.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__blackShadowDriver",_root.getNextHighestDepth());
        _root.gameworld=black;
        fixture();loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void {BlackShadowAssetTest.loaded(mc);};
        listener.onLoadError=function(mc:MovieClip,error:String):Void {BlackShadowAssetTest.check(false,"asset load "+error);BlackShadowAssetTest.complete();};
        loader.addListener(listener);
        loader.loadClip("../flashswf/arts/new/Codex黑仔素材.swf",black);
        loader.loadClip("../flashswf/arts/new/体育老师.swf",teacher);
        driver.onEnterFrame=function():Void {
            if(BlackShadowAssetTest.loadedCount<2) {
                if(++BlackShadowAssetTest.ticks>200){BlackShadowAssetTest.check(false,"load timeout");BlackShadowAssetTest.complete();}
            }else BlackShadowAssetTest.tick();
        };
    }
    private static function fixture():Void {
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.暂停=false;_root.是否阴影=true;
        _root.帧计时器={当前帧数:0};_root.敌人属性表={};
        _root.敌人属性表["敌人-Codex黑仔"]={技能配置:{迅斩冷却:5000,凶斩冷却:8000}};
        _root.主角函数.刀口位置生成子弹=BladeShootCore.shoot;
        _root.装备引用配置={配置装扮:function(c:MovieClip):Void {c.基本款._visible=true;}};
        _root.初始化思考标签=function(c:MovieClip):Void {c._name="思考标签";c.stop();c._visible=false;};
        _root.敌人函数.配置音效=function():Void {};
        _root.发布消息=function():Void {};_root.播放音效=function():Void {};
        _root.效果=function():Void {};_root.add2map2=function():Void {};_root.add2map=function():Void {};
        _root.子弹属性初始化=function(c:MovieClip):Object {
            var u:MovieClip=c;while(u._parent!=undefined && !u.fixtureSample) u=u._parent;
            return {发射者:u._name};
        };
        _root.子弹区域shoot传递=function(p:Object):Void {
            var u:MovieClip=BlackShadowAssetTest.black[p.发射者];
            if(u==undefined)u=BlackShadowAssetTest.teacher[p.发射者];
            u.fixtureHits++;
        };
        _root.消弹属性初始化=function():Object {return {};};_root.消除子弹=function():Void {};
        _root.初始化敌人模板=function():Void {
            this.fixtureSample=true;this.fixtureHits=0;
            this.hp=this.hp满血值=1000;this.mp=this.mp满血值=300;this.等级=30;
            this.空手攻击力=100;this.内力=35;this.技能等级=1;this.刀属性={power:45};this.刀_刀口数=3;
            this.兵器动作类型="棍棒";this.被动技能={};this.体重=this.重量=70;
            this.行走X速度=3;this.行走Y速度=1.5;this.跑X速度=6;this.跑Y速度=3;
            this.Z轴坐标=250;this._y=250;this._x=100;this.方向="右";this.myxscale=100;
            this.攻击模式=this.攻击模式?this.攻击模式:"空手";
            this.aabbCollider={updateFromUnitArea:function():Void {}};
            this.韧性上限=1000;this.remainingImpactForce=0;
            this.version=1;this.已加经验值=false;
            this.dispatcher={publish:function(event:String,owner:MovieClip,target:MovieClip):Void {
                if(event=="aggroSet")owner.攻击目标=target._name;else if(event=="aggroClear")owner.攻击目标="无";
            }};
            this.状态=this.攻击模式+"站立";
            this.状态改变=_root.敌人函数.状态改变;
            this.动画完毕=function():Void {this.fixtureEnded=true;this.man.stop();};
            this.fixtureMoves=0;
            this.移动=function():Void {this.fixtureMoves++;};this.被击移动=function():Void {};this.行走=function():Void {};
            this.方向改变=function(d:String):Void {this.方向=d;this._xscale=d=="左"?-100:100;};
            this.死亡检测=function():Void {};this.击飞浮空=function():Void {};this.击飞倒地=function():Void {};
            this.中招呐喊=function():Void {};this.攻击呐喊=function():Void {};
            this.UpdateBigSmallState=function():Void {};this.buff={限时赋值:function():Void {}};
            this.area._visible=false;this.gotoAndStop(this.状态);
        };
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();loadedCount++;var remove:Array=[];
        for(var key:String in mc){var child:Object=mc[key];if(typeof(child)=="movieclip" && child._parent===mc)remove.push(child);}
        for(var j:Number=0;j<remove.length;j++){remove[j].swapDepths(mc.getNextHighestDepth());remove[j].removeMovieClip();}
        if(loadedCount!=2)return;
        DepthManager.instance=new DepthManager(black,0,1048575,128);
        var target:MovieClip=black.createEmptyMovieClip("target",black.getNextHighestDepth());
        target.hp=1000;target.Z轴坐标=target._y=250;target._x=220;
        teacher.target=target;
        var labels:Array=["兵器站立","兵器行走","兵器跑","兵器攻击","迅斩","凶斩","被击","击倒","倒地","霸体"];
        var lengths:Array=[64,22,22,108,27,44,20,17,25,36];
        for(var f:Number=0;f<2;f++) for(var k:Number=0;k<labels.length;k++) {
            var u:MovieClip=black.attachMovie("敌人-Codex黑仔","b"+cases.length,black.getNextHighestDepth(),{兵种:"敌人-Codex黑仔"});
            cases.push({unit:u,label:labels[k],face:f,length:lengths[k],seen:{},samples:0});
        }
        // Native blood death randomly selects a0..a6 and removes its owner at
        // each branch's end. Select every reachable branch after its load event.
        var deathStarts:Array=[1,81,149,190,228,309,375];
        for(f=0;f<2;f++)for(k=0;k<deathStarts.length;k++) {
            u=black.attachMovie("敌人-Codex黑仔","b"+cases.length,black.getNextHighestDepth(),{兵种:"敌人-Codex黑仔"});
            cases.push({unit:u,label:"血腥死",face:f,variant:k,start:deathStarts[k],length:515,seen:{},samples:0});
        }
        var names:Array=["燃烧指节","诛杀步","虎拳","日字冲拳","破极拳","旋风腿","平踢"];
        var starts:Array=[1,19,32,91,133,194,289];
        var teacherTarget:MovieClip=black.createEmptyMovieClip("teacherTarget",black.getNextHighestDepth());
        teacherTarget.hp=1000;teacherTarget.Z轴坐标=teacherTarget._y=250;teacherTarget._x=200;
        for(k=0;k<names.length;k++) {
            u=teacher.attachMovie("敌人-体育老师","t"+k,teacher.getNextHighestDepth(),{兵种:"敌人-体育老师"});
            probes.push({unit:u,name:names[k],start:starts[k],entered:false});
        }
        var dry:MovieClip=black.attachMovie("敌人-Codex黑仔","mpProbe",black.getNextHighestDepth(),{兵种:"敌人-Codex黑仔"});
        var mpTarget:MovieClip=black.createEmptyMovieClip("mpTarget",black.getNextHighestDepth());
        mpTarget.hp=1000;mpTarget.Z轴坐标=mpTarget._y=250;mpTarget._x=350;
        driver.dry=dry;ticks=0;
    }
    private static function initializeCases():Void {
        for(var k:Number=0;k<cases.length;k++) {
            var item:Object=cases[k],u:MovieClip=item.unit;
            check(typeof(u.黑仔状态改变)=="function",item.label+" actual controller initialized");
            u.__黑仔禁用技能AI=true;u.mp=0;u.攻击目标="target";u.方向改变(item.face==0?"右":"左");
            u.黑仔技能选择=function():String {return "";};
            black.target._x=u._x+(item.face==0?1:-1)*(item.label=="霸体"?250:120);
            if(item.label!="兵器站立")delete u.shadow;
            u.状态改变(item.label);u.__黑仔下次技能=99999999;u.man.stop();
        }
        for(k=0;k<probes.length;k++) {
            var p:Object=probes[k];u=p.unit;
            u.攻击目标="teacherTarget";u.mp=0;u.近战招式=p.name;u.状态改变("近战");
        }
        var dry:MovieClip=driver.dry;
        dry.__黑仔禁用技能AI=true;dry.攻击目标="mpTarget";dry.mp=0;
        var mpTarget:MovieClip=black.mpTarget;
        mpTarget._x=dry._x+250;
        dry.状态改变("迅斩");check(dry.状态=="迅斩" && dry.mp==0,"black MP0 allows rapid");
        var rapidReady:Number=dry.__黑仔迅斩就绪;
        dry.状态改变("被击");dry.状态改变("兵器站立");
        dry.状态改变("迅斩");check(dry.状态=="兵器站立" && dry.mp==0 && dry.__黑仔迅斩就绪==rapidReady,"rapid cooldown still refuses repeat at MP0");
        dry.状态改变("凶斩");check(dry.状态=="凶斩" && dry.mp==0,"black MP0 allows heavy");
        var heavyReady:Number=dry.__黑仔凶斩就绪;
        dry.状态改变("被击");dry.状态改变("兵器站立");
        dry.状态改变("凶斩");check(dry.状态=="兵器站立" && dry.mp==0 && dry.__黑仔凶斩就绪==heavyReady,"heavy cooldown still refuses repeat at MP0");
        dry.__黑仔下次技能=0;dry.状态改变("霸体");
        check(dry.状态=="霸体" && dry.mp==0 && dry.__黑仔霸体刚体,"black MP0 allows poise under safe-distance condition");
        var poiseReady:Number=dry.__黑仔霸体就绪;
        dry.状态改变("被击");dry.状态改变("兵器站立");dry.__黑仔下次技能=0;
        dry.状态改变("霸体");
        check(dry.状态=="兵器站立" && dry.mp==0 && dry.__黑仔霸体就绪==poiseReady,"poise cooldown still refuses repeat at MP0");
        dry.__黑仔迅斩就绪=dry.__黑仔凶斩就绪=dry.__黑仔下次技能=0;
        mpTarget._x=dry._x+120;
        check(dry.黑仔技能选择()=="凶斩","AI chooses heavy at MP0 in its safe range");
        dry.__黑仔凶斩就绪=99999999;mpTarget._x=dry._x+180;
        check(dry.黑仔技能选择()=="迅斩","AI chooses rapid at MP0 after heavy unavailable");
        mpTarget._x=dry._x+40;dry.__黑仔凶斩就绪=dry.__黑仔下次技能=dry.__黑仔退步就绪=0;
        dry.__黑仔禁用技能AI=false;
        check(dry.黑仔开始退步() && dry.__黑仔退步中,"MP0 still permits close-range retreat");
        dry.黑仔停止退步();dry.__黑仔禁用技能AI=true;dry.__黑仔下次技能=99999999;

    }
    private static function tick():Void {
        _root.帧计时器.当前帧数=++ticks;
        if(ticks<5) {if(ticks==4)initializeCases();return;}
        for(var j:Number=0;j<cases.length;j++) {
            var item:Object=cases[j];var u:MovieClip=item.unit;var f:Number=u.man._currentframe;
            if(item.label=="血腥死" && ticks<7)continue;
            if(u.man==undefined) {
                if(item.label=="血腥死")item.removed=true;
                else check(false,item.label+" facing"+item.face+" native timeline unexpectedly absent");
                continue;
            }
            if(f>item.length || item.seen[f]) continue;
            item.seen[f]=true;item.samples++;
            var s:MovieClip=u.shadow;
            var live:Boolean=s._parent===u.man && s._visible;
            check(live,item.label+" facing"+item.face+" frame"+f+" owns visible shadow");
            if(live) {
                var bounds:Object=s.getBounds(s);
                var image:BitmapData=new BitmapData(100,100,true,0);
                var sx:Number=90/(bounds.xMax-bounds.xMin), sy:Number=90/(bounds.yMax-bounds.yMin);
                image.draw(s,new Matrix(sx,0,0,sy,5-bounds.xMin*sx,5-bounds.yMin*sy));
                var visible:Rectangle=image.getColorBoundsRect(0xFF000000,0,false);
                check(visible.width>60 && visible.height>60,item.label+" frame"+f+" shadow has rendered pixels");
                image.dispose();
            }
            if(item.face==0 && (f==3 || item.label=="击倒" && f==9 || item.label=="倒地" && f==19)) snapshot(u,item.label+"-f"+f);
            if(item.face==0 && item.label=="血腥死" && (item.variant==0 || item.variant==6) && f==item.start+2) snapshot(u,item.label+"-a"+item.variant+"-f"+f);
        }
        if(ticks==6)for(j=0;j<cases.length;j++) {
            item=cases[j];
            if(item.label=="血腥死")item.unit.man.gotoAndPlay("a"+item.variant);
            else item.unit.man.play();
        }
        for(j=0;j<probes.length;j++) {
            var p:Object=probes[j];u=p.unit;
            if(!p.entered && u.状态=="近战" && u.man._currentframe>=p.start) p.entered=true;
        }
        if(ticks<119)return;
        for(j=0;j<cases.length;j++) {
            item=cases[j];
            check(item.samples>Math.min(item.length-1,8),item.label+" facing"+item.face+" multiple actual frames observed: "+item.samples);
            if(item.label=="血腥死")check(item.removed,item.label+" a"+item.variant+" finishes its native owner removal");
            else check(item.unit.mp==0,item.label+" remains at MP0 through the native timeline");
            if(item.label=="迅斩" || item.label=="凶斩") {
                check(item.unit.fixtureHits>0,item.label+" facing"+item.face+" emits actual attacks at MP0");
                trace("[BLACK_MP0] "+item.label+"|face="+item.face+"|shots="+item.unit.fixtureHits+"|mp="+item.unit.mp);
            }
            trace("[SHADOW_COVERAGE] "+item.label+"|face="+item.face+"|variant="+item.variant+"|samples="+item.samples);
        }
        for(j=0;j<probes.length;j++) {
            p=probes[j];u=p.unit;
            check(p.entered,p.name+" teacher MP0 enters native move");
            if(p.name=="诛杀步")check(u.fixtureMoves>0 && u.fixtureHits==0,p.name+" teacher MP0 executes native pursuit instructions without attack");
            else check(u.fixtureHits>0,p.name+" teacher MP0 emits actual attacks");
            check(u.mp==0,p.name+" teacher native move does not charge MP");
            trace("[TEACHER_MP0] "+p.name+"|entered="+p.entered+"|shots="+u.fixtureHits+"|mp="+u.mp);
        }
        check(driver.dry.mp==0,"black MP0 remains empty after115 native ticks");
        complete();
    }
    private static function snapshot(u:MovieClip,id:String):Void {
        u.人物文字信息._visible=false;u.新版人物文字信息._visible=false;
        var image:BitmapData=new BitmapData(400,400,true,0);
        image.draw(u,new Matrix(2,0,0,2,170,310),null,"normal",null,true);
        trace("[SHADOW_BITMAP_BEGIN] "+id+" 400 400");
        for(var y:Number=0;y<400;y++) {
            var last:Number=image.getPixel32(0,y),count:Number=0,row:String="",opaque:Boolean=false;
            for(var x:Number=0;x<400;x++) {
                var color:Number=image.getPixel32(x,y);if(color!=0)opaque=true;
                if(color==last)count++;else {if(row!="")row+=",";row+=bitmapColorHex(last)+":"+count;last=color;count=1;}
            }
            row+=(row!=""?",":"")+bitmapColorHex(last)+":"+count;
            if(opaque)trace("[SHADOW_BITMAP_ROW] "+y+" "+row);
        }
        trace("[SHADOW_BITMAP_END] "+id);image.dispose();
    }
    private static function bitmapColorHex(pixel:Number):String {
        // AVM1 formats signed INT_MIN as "-(0000000". Serialize safe halves.
        var low:String=(pixel & 65535).toString(16);
        while(low.length<4)low="0"+low;
        return ((pixel >>>16)&65535).toString(16)+low;
    }
    private static function complete():Void {
        trace("BlackShadowAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" shadow timelines; "+probes.length+" teacher MP0 moves");
        driver.onEnterFrame=null;loader.unloadClip(black);loader.unloadClip(teacher);
        world.removeMovieClip();driver.removeMovieClip();_root.blackShadowAssetComplete();
    }
}
