import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.component.Damage.*;

/** Actual published gamma-ECHO timelines; initialization and outgoing damage are fixtures.
 * AI strength and real damage are measured separately by the dual-Worker arena.
 * No player profile or persistence is loaded by this suite.
 */
class org.flashNight.arki.unit.Action.Melee.GammaEchoAssetTest {
    private static var library:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, ticks:Number, ready:Boolean, finished:Boolean;
    private static var cases:Array, defaults:Array;
    private static var exportDeaths:Boolean, captureQueue:Array, captureCursor:Number, colorCache:Object;
    private static var exportConnections:Boolean, connectionQueue:Array, connectionCursor:Number;
    private static var connectionSample:Object, connectionPhase:Number;
    private static var sustainOff:MovieClip, sustainNormal:MovieClip;
    private static var links:Array = ["敌人-延寿克隆兽", "敌人-完全体克隆兽"];

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] GammaEchoAssetTest: " + name); }
    }

    public static function runAllTests():Void {
        passed=failed=ticks=0;ready=finished=false;cases=[];defaults=[];
        exportDeaths=_root.gammaEchoExportDeathFrames===true;captureQueue=null;captureCursor=0;colorCache={};
        exportConnections=_root.gammaEchoExportConnectionFrames===true;connectionQueue=null;connectionCursor=0;connectionSample=null;connectionPhase=0;
        library=_root.createEmptyMovieClip("__gammaEchoLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__gammaEchoDriver",_root.getNextHighestDepth());
        library._visible=false;
        _root.gameworld=library;
        _root.暂停=false;_root.控制目标="__no_player";_root.控制目标全自动=false;
        _root.播放音效=function():Void {};
        _root.发布消息=function():Void {};
        _root.效果=function():Void {};
        _root.add2map2=function():Void {};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.敌人二级函数={攻击时移动:function():Void {},X轴追踪移动:function():Void {},
            Z轴追踪移动:function():Void {},计算攻击角度:function():Void {},固定角度移动:function():Void {}};
        _root.子弹属性初始化=function(area:MovieClip):Object {
            var actor:MovieClip=area;
            while (actor != null && actor.fixtureCase == undefined) actor=actor._parent;
            return {fixtureCase:actor.fixtureCase};
        };
        _root.子弹区域shoot传递=function(p:Object):Void {GammaEchoAssetTest.capture(p);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=typeof(this.fixtureLevel)=="number"?this.fixtureLevel:30;
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";
            this.攻击目标="无";this.Z轴坐标=this._y=200;this._x=200;
            this.fixtureDone=0;this.fixtureTransitions=0;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:100}};
            this.倒地=this.浮空=this.硬直中=false;
            this.swapDepths=function():Void {};
            this.行走=function():Void {};
            this.击飞浮空=function():Void {};
            this.击飞倒地=function():Void {};
            this.击倒呐喊=function():Void {};
            this.方向改变=function(dir:String):Void {this.方向=dir;if(this.man)this.man._xscale=dir=="左"?-100:100;};
            this.状态改变=function(next:String):Void {
                this.fixtureTransitions++;this.状态=next;this.gotoAndStop(next);
                if(this.man)this.man._xscale=this.方向=="左"?-100:100;
            };
            this.动画完毕=function():Void {this.fixtureDone++;this.man.stop();};
            this.死亡检测=function():Void {this.fixtureDone++;this.man.stop();};
            this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {GammaEchoAssetTest.loaded();},
            onLoadError:function(mc:MovieClip,error:String):Void {GammaEchoAssetTest.check(false,"load "+error);GammaEchoAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",library),"load actual published library");
        driver.onEnterFrame=function():Void {GammaEchoAssetTest.tick();};
    }

    private static function loaded():Void {
        var moves:Array=["basic","跳跃撕咬","跑动捕杀","撕裂嘶吼"];
        var counts:Array=[2,2,8,5];
        for(var v:Number=0;v<2;v++) {
            for(var facing:Number=0;facing<2;facing++) {
                for(var j:Number=0;j<moves.length;j++) add(v,facing,moves[j],counts[j]);
            }
            for(var side:Number=0;side<2;side++)for(var d:Number=0;d<3;d++)add(v,side,"death"+d,0);
            for(var edge:Number=64;edge<=65;edge++) {
                var unit:MovieClip=library.attachMovie(links[v],"gammaDefault"+v+"_"+edge,library.getNextHighestDepth(),
                    {fixtureCase:-1,fixtureLevel:edge,_arenaCalibrationUnit:true});
                defaults.push({actor:unit,level:edge});
            }
        }
        sustainOff=library.attachMovie(links[1],"gammaSustainOff",library.getNextHighestDepth(),
            {fixtureCase:-1,_arenaCalibrationUnit:true,克隆兽吸血模式:"off"});
        sustainNormal=library.attachMovie(links[1],"gammaSustainNormal",library.getNextHighestDepth(),
            {fixtureCase:-1,克隆兽吸血模式:"off"});
        ready=true;ticks=0;
    }

    private static function add(variant:Number,facing:Number,move:String,expected:Number):Void {
        var index:Number=cases.length;
        var actor:MovieClip=library.attachMovie(links[variant],"gammaCase"+index,library.getNextHighestDepth(),
            {fixtureCase:index,克隆兽AI模式:move=="death2"?"enhanced":"baseline",_arenaCalibrationUnit:true});
        check(actor!=null,"attach "+links[variant]+" / "+move+" / "+facing);
        cases.push({actor:actor,variant:variant,facing:facing,move:move,expected:expected,shots:0,powerOk:true,rangeOk:true});
    }

    private static function capture(p:Object):Void {
        var c:Object=cases[p.fixtureCase];
        if(c==undefined)return;
        c.shots++;if(p.子弹威力!=100)c.powerOk=false;
        if(p.Z轴攻击范围!=30)c.rangeOk=false;
    }

    private static function aiChecks(actor:MovieClip,variant:Number):Void {
        check(typeof(actor.gammaEchoChooseSkill)=="function","private brain compiled "+variant);
        check(actor.克隆兽完全体==(variant==1),"variant identity "+variant);
        check(actor.gammaEchoArenaAudit.mode=="baseline","actual arena mode audit "+variant);
        check(actor.gammaEchoArenaAudit.fullPower==(variant==1),"actual arena variant audit "+variant);
        check(actor.gammaEchoChooseSkill(70,0,0)=="撕裂嘶吼","close roar priority "+variant);
        check(actor.gammaEchoChooseSkill(120,0,0)=="撕裂嘶吼","near roar "+variant);
        check(actor.gammaEchoChooseSkill(200,0,0)=="跳跃撕咬","mid leap "+variant);
        check(actor.gammaEchoChooseSkill(330,0,0)=="跑动捕杀","far rush "+variant);
        check(actor.gammaEchoChooseSkill(500,0,0)=="none","outside range "+variant);
        check(actor.gammaEchoChooseSkill(120,25,0)=="none","lane mismatch "+variant);
        check(actor.gammaEchoChooseSkill(120,0,70)=="none","airborne target "+variant);
        check(actor.gammaEchoChooseSkill(NaN,0,0)=="none","invalid distance "+variant);
        var target:MovieClip=library.createEmptyMovieClip("gammaTarget",library.getNextHighestDepth());
        target.hp=1000;target.Z轴坐标=200;target._y=200;target._x=320;
        target.createEmptyMovieClip("area",1);
        var sensor:MovieClip=library.createEmptyMovieClip("gammaSensor",library.getNextHighestDepth());
        sensor.hitTest=function():Boolean{return true;};
        actor.攻击目标=target._name;
        var before:Number=actor.fixtureTransitions;
        _root.暂停=true;actor.gammaEchoThink(sensor);_root.暂停=false;
        check(actor.fixtureTransitions==before,"pause cannot attack "+variant);
        _root.控制目标=actor._name;actor.gammaEchoThink(sensor);_root.控制目标="__no_player";
        check(actor.fixtureTransitions==before,"manual control cannot attack "+variant);
        target.hp=0;actor.gammaEchoThink(sensor);target.hp=1000;
        check(actor.fixtureTransitions==before,"dead target cannot attack "+variant);
        actor.硬直中=true;actor.gammaEchoThink(sensor);actor.硬直中=false;
        check(actor.fixtureTransitions==before,"stun cannot attack "+variant);
        target.Z轴坐标=260;actor.gammaEchoThink(sensor);target.Z轴坐标=200;
        check(actor.fixtureTransitions==before && actor.下行,"align lane without attack "+variant);
        actor.gammaEchoThink(sensor);
        check(actor.近战招式=="撕裂嘶吼" && actor.状态=="近战","select actual near action "+variant);
        actor.状态改变("空手站立");target._x=80;
        actor.gammaEchoThink(sensor);
        check(actor.方向=="左" && actor.近战招式=="撕裂嘶吼","no extra idle after native action; left-facing selection "+variant);
        actor.攻击目标="无";actor.状态改变("空手站立");
        target.removeMovieClip();sensor.removeMovieClip();
    }

    private static function pixels(actor:MovieClip,key:String):Void {
        var source:MovieClip=actor.man;
        var b:Object=source.getBounds(source);
        check(b.xMax>b.xMin && b.yMax>b.yMin,"nonempty native bounds "+key);
        var scale:Number=Math.min(380/(b.xMax-b.xMin),380/(b.yMax-b.yMin));
        var m:Matrix=new Matrix(scale,0,0,scale,20-b.xMin*scale,20-b.yMin*scale);
        var bd:BitmapData=new BitmapData(420,420,true,0);
        bd.draw(source,m);
        var visible:Number=0;
        for(var y:Number=0;y<420;y+=3)for(var x:Number=0;x<420;x+=3)if((bd.getPixel32(x,y)>>>24)>128)visible++;
        check(visible>2000,"actual Flash vector pixels "+key);
        trace("[GAMMA_IMAGE_BEGIN] "+key+" 420 420");
        for(var row:Number=0;row<420;row++) {
            var line:String="";
            for(var col:Number=0;col<420;col++) {
                var value:Number=bd.getPixel32(col,row);
                // AVM1 Number.toString(16) is signed for packed ARGB; serialize bytes.
                for(var shift:Number=24;shift>=0;shift-=8) {
                    var byteValue:Number=(value>>>shift)&255;
                    var hex:String=byteValue.toString(16);
                    if(length(hex)<2)hex="0"+hex;
                    line+=hex;
                }
            }
            trace("[GAMMA_ROW] "+key+" "+row+" "+line);
        }
        trace("[GAMMA_IMAGE_END] "+key);
        bd.dispose();
    }

    private static function sustainChecks(actor:MovieClip,variant:Number):Void {
        var expected:Number=variant==1?5:0;
        check(actor.吸血==expected,"actual published innate life steal "+variant);
        check(actor.gammaEchoArenaAudit.lifeStealPercent==expected,"observed life steal configuration "+variant);
        var bullet:Object={吸血:0,子弹威力:200,stateFlags:0};
        BulletInitializer.inheritShooterAttributes(bullet,actor);
        check(bullet.吸血==expected,"production bullet inherits life steal "+variant);
        var handler:LifeStealDamageHandle=LifeStealDamageHandle.getInstance();
        var result:DamageResult=new DamageResult();
        var target:Object={损伤值:200,hp:1000,shield:null};
        actor.hp=500;
        handler.handleBulletDamage(bullet,actor,target,null,result);
        check(actor.hp==(variant==1?510:500),"production damage handler heals only Tyrant "+variant);
        target.shield={getStrength:function():Number{return 200;}};
        actor.hp=500;handler.handleBulletDamage(bullet,actor,target,null,result);
        check(actor.hp==500,"blocking shield prevents innate life steal "+variant);
        target.shield=null;target.损伤值=0;
        handler.handleBulletDamage(bullet,actor,target,null,result);
        check(actor.hp==500,"zero damage cannot heal "+variant);
        actor.hp=0;target.损伤值=200;
        handler.handleBulletDamage(bullet,actor,target,null,result);
        check(actor.hp==0,"life steal cannot revive dead actor "+variant);
        actor.hp=1000;
        handler.handleBulletDamage(bullet,actor,target,null,result);
        check(variant==1?actor.hp>1000 && actor.hp<1010:actor.hp==1000,"shared overflow attenuation "+variant);
        actor.hp=1000;
    }

    private static function tick():Void {
        if(finished)return;
        ticks++;
        if(connectionQueue!=null) { captureConnectionStep();return; }
        if(captureQueue!=null) { captureDeathStep();return; }
        if(!ready){if(ticks>300){check(false,"load timeout");finish();}return;}
        if(ticks==3) {
            for(var di:Number=0;di<defaults.length;di++) {
                var probe:MovieClip=defaults[di].actor;
                var expectedMode:String=defaults[di].level>=65?"baseline":"enhanced";
                check(probe.克隆兽AI模式==expectedMode,"default mode at native armor boundary "+di);
                check(probe.gammaEchoArenaAudit.mode==expectedMode,"default mode observed after initialization "+di);
                check(probe.unitAI.data.xrange==(expectedMode=="enhanced"?0:100),"default automatic attack range "+di);
            }
            // Run private logic on a separate actor so the timeline cases stay clean.
            for(var v:Number=0;v<2;v++) {
                var actor:MovieClip=cases[v*14].actor;
                sustainChecks(actor,v);
                aiChecks(actor,v);
                var enhanced:MovieClip=cases[v*14+13].actor;
                check(enhanced.克隆兽AI模式=="enhanced","enhanced entry mode "+v);
                check(enhanced.x轴攻击范围==0 && enhanced.unitAI.data.xrange==0,"private attack owns decision "+v);
                check(enhanced.gammaEchoChooseSkill(0,0,0)=="撕裂嘶吼","overlapping target close priority "+v);
            }
            check(sustainOff.吸血==0,"isolated arena can disable Tyrant sustain for comparison");
            check(sustainNormal.吸血==5,"ordinary spawn ignores arena-only sustain switch");
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i],u:MovieClip=c.actor;
                u.fixtureDone=0;c.shots=0;c.powerOk=c.rangeOk=true;
                u.方向改变(c.facing==0?"右":"左");
                if(c.move.substr(0,5)=="death") {
                    u.状态改变("血腥死");u.man.gotoAndPlay("a"+c.move.substr(5));
                } else if(c.move=="basic")u.状态改变("空手攻击");
                else {u.近战招式=c.move;u.状态改变("近战");}
            }
        }
        if(ticks==4) {
            pixels(cases[0].actor,"stabilized-native");
            pixels(cases[14].actor,"full-power-native");
        }
        if(ticks==155) {
            for(var k:Number=0;k<cases.length;k++) {
                var item:Object=cases[k];
                check(item.shots==item.expected,"actual emission "+k+" "+item.move+" = "+item.shots+" / "+item.expected);
                check(item.powerOk && item.rangeOk,"unchanged hit contract "+k);
                check(item.actor.fixtureDone==1,"exactly one terminal callback "+k+" "+item.move);
                check(item.actor.man._width>0 && item.actor.man._height>0,"body persists through last frame "+k);
            }
            if(exportConnections) { beginConnectionCapture();return; }
            if(exportDeaths) { beginDeathCapture();return; }
            finish();
        }
    }

    private static function colorHex(value:Number):String {
        var cacheKey:String="c"+value;
        if(colorCache[cacheKey]!=undefined)return colorCache[cacheKey];
        var out:String="";
        for(var shift:Number=24;shift>=0;shift-=8) {
            var h:String=((value>>>shift)&255).toString(16);
            out+=(h.length<2?"0":"")+h;
        }
        colorCache[cacheKey]=out;return out;
    }

    private static function beginConnectionCapture():Void {
        connectionQueue=[];connectionCursor=0;
        var poses:Array=[
            ["idle","空手站立",1],["walk-a","空手行走",5],["walk-b","空手行走",13],
            ["run-a","空手跑",5],["run-b","空手跑",13],["basic","空手攻击",13],
            ["leap","近战",20],["rush","近战",60],["roar","近战",110],
            ["hit","被击",9],["fall","击倒",12],["death-leg","血腥死",46],
            ["death-arm","血腥死",77],["death-side","血腥死",109]
        ];
        for(var v:Number=0;v<2;v++)for(var p:Number=0;p<poses.length;p++) {
            connectionQueue.push({variant:v,pose:poses[p]});
        }
    }

    private static function captureConnectionStep():Void {
        if(connectionSample==null && connectionCursor>=connectionQueue.length) {
            trace("[GAMMA_CONNECTION_EXPORT_COMPLETE] frames="+connectionQueue.length);
            finish();return;
        }
        if(connectionSample==null) {
            connectionSample=connectionQueue[connectionCursor++];connectionPhase=0;
        }
        var sample:Object=connectionSample;
        var actor:MovieClip=cases[sample.variant*14].actor;
        // A newly placed MovieClip settles on the next Flash frame. Capturing
        // in the state-change call can read an unloaded old `man` reference.
        if(connectionPhase==0) {
            actor.方向改变("右");actor.近战招式="跳跃撕咬";
            actor.状态改变(sample.pose[1]);connectionPhase=1;return;
        }
        if(connectionPhase==1) {actor.man.gotoAndStop(sample.pose[2]);connectionPhase=2;return;}
        var source:MovieClip=actor.man,b:Object=source.getBounds(source);
        var scale:Number=Math.min(380/(b.xMax-b.xMin),320/(b.yMax-b.yMin));
        var bd:BitmapData=new BitmapData(420,360,true,0);
        bd.draw(source,new Matrix(scale,0,0,scale,20-b.xMin*scale,20-b.yMin*scale));
        var key:String=(sample.variant==0?"lambda":"tyrant")+"-"+sample.pose[0];
        var visible:Number=0;
        for(var yy:Number=0;yy<360;yy+=4)for(var xx:Number=0;xx<420;xx+=4)if((bd.getPixel32(xx,yy)>>>24)>128)visible++;
        check(visible>100,"nonempty settled connection pose "+key);
        trace("[GAMMA_CONNECTION_BEGIN] "+key+" 420 360");
        for(var row:Number=0;row<360;row++) {
            var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
            for(var col:Number=1;col<420;col++) {
                var value:Number=bd.getPixel32(col,row);
                if(value==last)count++;
                else {parts.push(count+":"+colorHex(last));last=value;count=1;}
            }
            parts.push(count+":"+colorHex(last));
            trace("[GAMMA_CONNECTION_ROW] "+key+" "+row+" "+parts.join(","));
        }
        trace("[GAMMA_CONNECTION_END] "+key);bd.dispose();connectionSample=null;
    }

    private static function beginDeathCapture():Void {
        captureQueue=[];captureCursor=0;
        var starts:Array=[0,47,78],ends:Array=[45,76,108];
        for(var v:Number=0;v<2;v++)for(var branch:Number=0;branch<3;branch++) {
            for(var at:Number=starts[branch];at<=ends[branch];at+=3) {
                captureQueue.push({variant:v,branch:branch,at:at});
            }
            if((ends[branch]-starts[branch])%3!=0)captureQueue.push({variant:v,branch:branch,at:ends[branch]});
        }
    }

    private static function captureDeathStep():Void {
        if(captureCursor>=captureQueue.length) {
            trace("[GAMMA_DEATH_EXPORT_COMPLETE] frames="+captureQueue.length);
            finish();return;
        }
        var sample:Object=captureQueue[captureCursor++];
        var actor:MovieClip=cases[sample.variant*14+8].actor;
        actor.状态改变("血腥死");actor.man.gotoAndStop(sample.at+1);
        var key:String=(sample.variant==0?"stabilized":"full-power")+"-a"+sample.branch+"-f"+sample.at;
        var bd:BitmapData=new BitmapData(640,320,true,0);
        bd.draw(actor.man,new Matrix(1.25,0,0,1.25,412.5,181.25));
        trace("[GAMMA_DEATH_BEGIN] "+key+" 640 320");
        for(var row:Number=0;row<320;row++) {
            var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
            for(var col:Number=1;col<640;col++) {
                var value:Number=bd.getPixel32(col,row);
                if(value==last)count++;
                else {parts.push(count+":"+colorHex(last));last=value;count=1;}
            }
            parts.push(count+":"+colorHex(last));
            trace("[GAMMA_DEATH_ROW] "+key+" "+row+" "+parts.join(","));
        }
        trace("[GAMMA_DEATH_END] "+key);bd.dispose();
    }

    private static function finish():Void {
        if(finished)return;finished=true;
        delete driver.onEnterFrame;
        if(loader!=null)loader.removeListener(listener);
        trace("GammaEchoAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        library.removeMovieClip();driver.removeMovieClip();
        delete _root.gammaEchoExportDeathFrames;
        delete _root.gammaEchoExportConnectionFrames;
        _root.gammaEchoAssetComplete();
    }
}
