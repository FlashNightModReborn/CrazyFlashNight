import flash.display.BitmapData;
import flash.geom.Rectangle;
import flash.geom.Matrix;
import org.flashNight.arki.unit.Action.Melee.BladeShootCore;
import org.flashNight.arki.component.StatHandler.ImpactHandler;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.UnitAIInitializer;

/** Published AVM1 assets + production skill formulas and corpse drawing.
 * Spawn stats/equipment input, rewards and outgoing bullet sink are isolated fixtures.
 * Skill formulas use production SkillDamageCore/SkillAttributeCore with an explicit unit.
 * No player profile, save, installation promotion or combat hit settlement is exercised.
 */
class org.flashNight.arki.unit.Action.Melee.StudentRepairAssetTest {
    private static var passed:Number, failed:Number, ticks:Number, finished:Boolean;
    private static var world:MovieClip, military:MovieClip, black:MovieClip, driver:MovieClip;
    private static var loadProbeOnly:Boolean = false;
    private static var probeSpawnStage:Boolean = false;
    private static var loader:MovieClipLoader, listener:Object, cases:Array;
    private static var corpse:BitmapData, loadedCount:Number;
    private static var preview:MovieClip;
    private static var rapidPreviews:Array;
    private static var exportBitmaps:Boolean, worldRetired:Boolean;
    private static var exportPicture:Object, exportBounds:Rectangle;
    private static var exportY:Number, exportEndY:Number, startedAt:Number;
    private static var exportLines:Array;
    private static var exportBufferedRows:Number, exportedImages:Number, exportedRows:Number;
    private static var exportTimer:Number, hexCache:Object, hexCacheSize:Number;
    private static var readbackScanMs:Number, readbackEncodeMs:Number, readbackTraceMs:Number, readbackCallbacks:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] StudentRepairAssetTest: " + label); }
    }
    public static function runLoadProbe():Void { loadProbeOnly=true;probeSpawnStage=false;runFixture(); }
    public static function runSpawnProbe():Void { loadProbeOnly=true;probeSpawnStage=true;runFixture(); }
    public static function runAllTests():Void { loadProbeOnly=false;probeSpawnStage=false;runFixture(); }
    private static function runFixture():Void {
        passed=failed=ticks=loadedCount=0;finished=false;cases=[];rapidPreviews=[];
        exportBitmaps=_root.studentRepairExportBitmaps===true;exportPicture=null;startedAt=getTimer();exportedImages=exportedRows=0;worldRetired=false;exportTimer=undefined;hexCache={};hexCacheSize=0;readbackScanMs=readbackEncodeMs=readbackTraceMs=readbackCallbacks=0;
        trace("StudentRepairAssetTest bitmap-export="+exportBitmaps);
        trace("StudentRepairAssetTest phase=begin");
        Stage.scaleMode="noScale";
        world=_root.createEmptyMovieClip("__studentRepairWorld",_root.getNextHighestDepth());
        // Timelines still execute. The suite inspects native geometry and BitmapData;
        // avoid rasterizing seventy overlapping filtered actors into the test window.
        world._visible=false;
        driver=_root.createEmptyMovieClip("__studentRepairDriver",_root.getNextHighestDepth());
        military=world.createEmptyMovieClip("militaryLibrary",world.getNextHighestDepth());
        black=world.createEmptyMovieClip("blackLibrary",world.getNextHighestDepth());
        _root.gameworld=black;
        trace("StudentRepairAssetTest phase=world-created");
        fixture();
        trace("StudentRepairAssetTest phase=fixture-ready");
        loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void {
            try { StudentRepairAssetTest.loaded(mc); }
            catch (error:Object) { StudentRepairAssetTest.abortFixture("load-init "+mc._name,error); }
        };
        listener.onLoadError=function(mc:MovieClip,error:String):Void { trace("[TEST_FAIL] asset load "+error);StudentRepairAssetTest.finish(); };
        loader.addListener(listener);
        loader.loadClip("../flashswf/arts/new/大学人员.swf",military);
        loader.loadClip("../flashswf/arts/new/Codex黑仔素材.swf",black);
        trace("StudentRepairAssetTest phase=load-requested");
        driver.waited=0;
        driver.onEnterFrame=function():Void {
            try {
            if (StudentRepairAssetTest.loadedCount < 2) {
                this.waited++;
                if (this.waited>200) { StudentRepairAssetTest.check(false,"asset load timeout");StudentRepairAssetTest.finish(); }
            } else StudentRepairAssetTest.tick();
            } catch (error:Object) { StudentRepairAssetTest.abortFixture("driver tick "+StudentRepairAssetTest.ticks,error); }
        };
    }
    private static function fixture():Void {
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.暂停=false;
        _root.帧计时器={当前帧数:0};
        _root.主角函数.刀口位置生成子弹=BladeShootCore.shoot;
        _root.敌人属性表={};
        _root.敌人属性表["敌人-Codex黑仔"]={技能配置:{迅斩冷却:5000,凶斩冷却:8000}};
        _root.敌人函数.获取大学军阀派随机装扮=function(unit:MovieClip):Void { unit.长枪_装扮=""; };
        _root.敌人函数.配置音效=function():Void {};
        _root.装备引用配置={配置装扮:function(container:MovieClip):Void { container.基本款._visible=true; }};
        _root.初始化思考标签=function(mc:MovieClip):Void { mc._name="思考标签";mc.stop();mc._visible=false; };
        _root.发布消息=function():Void {};
        _root.效果=function():Void {};_root.播放音效=function():Void {};_root.add2map2=function():Void {};
        _root.子弹区域shoot传递=function(p:Object):Void { StudentRepairAssetTest.capture(p); };
        _root.子弹属性初始化=function(area:MovieClip):Object {
            var unit:MovieClip=area._parent._parent;
            var point:Object={x:0,y:0};area.localToGlobal(point);StudentRepairAssetTest.world.globalToLocal(point);
            return {发射者:unit._name,shootX:point.x,shootY:point.y,shootZ:unit.Z轴坐标};
        };
        _root.消弹属性初始化=function(area:MovieClip):Object { return {}; };
        _root.消除子弹=function(p:Object):Void { StudentRepairAssetTest.deflect(p); };
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=this.mp满血值=300;
            this.空手攻击力=100;this.内力=35;this.技能等级=1;
            this.刀属性={power:45};this.刀_刀口数=3;this.兵器动作类型="棍棒";
            this.被动技能={};this.体重=70;this.重量=70;
            this.行走X速度=3;this.行走Y速度=1.5;this.跑X速度=6;this.跑Y速度=3;
            this.Z轴坐标=250;this._y=250;this._x=100;
            this.方向="右";this.myxscale=100;
            this.aabbCollider={updateFromUnitArea:function():Void {}};
            this.version=1;this.fixtureWalks=0;this.fixtureMoves=0;
            this.dispatcher={publish:function(event:String,owner:MovieClip,target:MovieClip):Void {
                if (event=="aggroSet") owner.攻击目标=target._name;
                else if (event=="aggroClear") owner.攻击目标="无";
            }};
            this.area._visible=false;
            this.状态=this.攻击模式+"站立";
            this.状态改变=_root.敌人函数.状态改变;
            this.动画完毕=_root.敌人函数.动画完毕;
            this.移动=function(dir:String,speed:Number):Void {
                this.fixtureMoves++;_root.敌人函数.移动.call(this,dir,speed);
            };
            this.行走=function():Void { this.fixtureWalks++;_root.敌人函数.行走.call(this); };
            this.方向改变=function(dir:String):Void { this.方向=dir;this._xscale=dir=="左"?-100:100; };
            this.中招呐喊=function():Void {};this.攻击呐喊=function():Void {};
            this.击飞浮空=function():Void { this.倒地=true; };
            this.击飞倒地=_root.敌人函数.击飞倒地;
            this.死亡检测=_root.敌人函数.死亡检测;
            this.已加经验值=false;
            this.计算经验值=function():Void { this.已加经验值=true; };
            this.gotoAndStop(this.状态);
        };
        corpse=new BitmapData(1100,600,true,0);
        DeathEffectRenderer.isEnabled=true;DeathEffectRenderer.enableCulling=false;
        _root.add2map=function(unit:MovieClip,layer:Number):Void {
            StudentRepairAssetTest.freeze(unit);
            if (unit.fixtureCase.kind=="milDead") DeathEffectRenderer.renderCorpse(unit,layer);
        };
        _root.collisionLayer=world.createEmptyMovieClip("collisionLayer",world.getNextHighestDepth());
        _root.collisionLayer.hitTest=function():Boolean { return false; };
        Mover.init();
    }
    private static function loaded(mc:MovieClip):Void {
        trace("StudentRepairAssetTest phase=load-init name="+mc._name);
        mc.stop();loadedCount++;
        trace("StudentRepairAssetTest phase=stopped name="+mc._name);
        var remove:Array=[];
        for (var key:String in mc) {
            var child:Object=mc[key];
            if (typeof(child)=="movieclip" && child._parent===mc) remove.push(child);
        }
        trace("StudentRepairAssetTest phase=children-enumerated name="+mc._name+" count="+remove.length);
        for (var n:Number=0;n<remove.length;n++) { remove[n].swapDepths(mc.getNextHighestDepth());remove[n].removeMovieClip(); }
        trace("StudentRepairAssetTest phase=children-removed name="+mc._name);
        if (loadedCount!=2) return;
        var deadbody:MovieClip=black.createEmptyMovieClip("deadbody",black.getNextHighestDepth());
        deadbody.layers=[null,null,corpse];deadbody.attachBitmap(corpse,1);
        trace("StudentRepairAssetTest phase=before-depth-manager");
        DepthManager.instance=new DepthManager(black,0,1048575,128);
        trace("StudentRepairAssetTest phase=depth-manager-created");
        check(DepthManager.instance.calibrate(-1000,1000),"real movement depth manager calibrated");
        trace("StudentRepairAssetTest phase=depth-manager-calibrated");
        if (loadProbeOnly) {
            if (probeSpawnStage) {
                trace("StudentRepairAssetTest phase=before-one-military");
                addMilitary(0,false);
                trace("StudentRepairAssetTest phase=after-one-military");
                check(cases[0].unit._name==cases[0].id,"one real military instance attached");
                trace("StudentRepairAssetTest phase=before-one-black");
                addBlack("growthLow",0);
                trace("StudentRepairAssetTest phase=after-one-black");
                check(cases[1].unit._name==cases[1].id,"one real black instance attached");
            }
            if (probeSpawnStage) {
                driver.onEnterFrame=function():Void { StudentRepairAssetTest.probeTick(); };
                return;
            }
            trace("StudentLoadProbeTest passed="+passed+" failed="+failed);
            finished=true;delete driver.onEnterFrame;complete();return;
        }
        trace("StudentRepairAssetTest phase=spawn-begin");
        // Libraries are dictionaries; cases remain in each actual published library.
        for (var face:Number=0;face<2;face++) {
            addMilitary(face,false);addMilitary(face,true);
            var milKinds:Array=["milHit","milFly","milMelee"];
            for (var m:Number=0;m<milKinds.length;m++) {
                addMilitary(face,false);cases[cases.length-1].kind=milKinds[m];
            }
            var kinds:Array=["combo","rapid","heavy","heavyPrehit","heavyPosthit","prehit","posthit","dead","lost","mp","cooldown","ai","aiHeavy","pause","walk","chase","aiClose","aiFar","aiOpening","retreat","retreatHit","poiseLow","poiseSafe","poiseClose","poiseHealthy","poiseDeath","poiseLost","poiseExternal","growthLow","growth20","growth30","growthInvalid"];
            for (var k:Number=0;k<kinds.length;k++) addBlack(kinds[k],face);
        }
        trace("StudentRepairAssetTest phase=spawn-complete count="+cases.length);
    }
    private static function probeTick():Void {
        ticks++;
        if (ticks<3) return;
        trace("StudentRepairAssetTest phase=before-one-military-begin");
        begin(cases[0]);
        trace("StudentRepairAssetTest phase=after-one-military-begin");
        trace("StudentRepairAssetTest phase=before-one-black-begin");
        begin(cases[1]);
        trace("StudentRepairAssetTest phase=after-one-black-begin");
        trace("StudentLoadProbeTest passed="+passed+" failed="+failed);
        finished=true;delete driver.onEnterFrame;complete();
    }
    private static function addMilitary(face:Number, dead:Boolean):Void {
        var id:String="m"+cases.length;
        trace("StudentRepairAssetTest phase=spawn id="+id+" kind="+(dead?"milDead":"milRise")+" face="+face);
        var unit:MovieClip=military.attachMovie("敌人-军阀派学员",id,military.getNextHighestDepth(),{性别:face==0?"男":"女"});
        cases.push({id:id,unit:unit,kind:dead?"milDead":"milRise",face:face,hits:0,invalid:0,stale:0,freeze:0});
    }
    private static function addBlack(kind:String, face:Number):Void {
        var id:String="b"+cases.length;
        var target:MovieClip=black.createEmptyMovieClip(id+"Target",black.getNextHighestDepth());
        target.hp=1000;target.Z轴坐标=250;target._x=face==0?180:20;
        var init:Object={性别:"男",兵种:"敌人-Codex黑仔"};
        if (kind.indexOf("poise")==0) init.等级=kind=="poiseLow"?29:30;
        var extraForce:Number=0;
        if ((kind=="rapid" || kind=="heavy") && face==0) {
            extraForce=150;init.技能配置={内力加成:150};init.黑仔标定观测=true;
        } else if (kind=="cooldown") {
            init.技能配置={内力加成:face==0?-7:"invalid"};
        }
        if (kind.indexOf("growth")==0) {
            init.等级=kind=="growthLow"?10:kind=="growth20"?20:30;
            init.技能配置={内力每级:10,内力成长起始等级:10};
            extraForce=kind=="growth20"?100:kind=="growth30"?200:0;
            if (kind=="growthInvalid") { if (face==0) init.等级=Number.NaN;else init.技能配置.内力每级=-10; }
        }
        trace("StudentRepairAssetTest phase=spawn id="+id+" kind="+kind+" face="+face);
        var unit:MovieClip=black.attachMovie("敌人-Codex黑仔",id,black.getNextHighestDepth(),init);
        unit.fixtureExpectedForce=35+extraForce;
        cases.push({id:id,unit:unit,target:target,kind:kind,face:face,hits:0,invalid:0,stale:0,first:0,deflects:0,stages:0,freeze:0});
    }
    private static function begin(item:Object):Void {
        var u:MovieClip=item.unit;u.fixtureCase=item;
        u.方向改变(item.face==0?"右":"左");
        u.新版人物文字信息._visible=false;u.人物文字信息._visible=false;
        if (item.kind.indexOf("mil")==0) {
            u._x=item.face==0?160:360;u._y=150;
            if (item.kind=="milDead") u.hp=0;
            var state:String=item.kind=="milHit"?"被击":item.kind=="milFly"?"击倒":item.kind=="milMelee"?"长枪攻击":"倒地";
            u.状态改变(state);
            check(u.man._totalframes>1,item.id+" actual "+state+" animation exists");
            if (state=="倒地") check(hasPosePart(u.man,-174.35,195.35),item.id+" first prone head matches canonical rise source");
            return;
        }
        u.攻击目标=item.target._name;u.__黑仔下次技能=99999999;
        u.__黑仔禁用技能AI=false;
        u._visible=false;
        check(typeof(u.黑仔状态改变)=="function",item.id+" private controller initialized");
        check(u.刀=="木制球棒" && u.hasDressup===true,item.id+" weapon init retained");
        check(u.内力==u.fixtureExpectedForce,item.id+" compiled per-unit force bonus or invalid/default fallback");
        check(u.man._totalframes==64,item.id+" fixed cot-style stand segment");
        if (item.kind.indexOf("growth")==0) { u.__黑仔禁用技能AI=true;return; }
        if (item.kind=="walk" || item.kind=="chase") {
            item.startX=u._x;item.startZ=u.Z轴坐标;
            item.target._x=item.face==0?5000:-5000;
            u.左行=u.右行=u.上行=u.下行=false;
            if (item.kind=="chase") {
                UnitAIInitializer.initialize(u);
                check(u.unitAI.type=="Enemy",item.id+" production enemy chase AI initialized");
            } else {
                u[item.face==0?"右行":"左行"]=true;u.状态改变("兵器行走");
            }
            return;
        }
        if (item.kind.indexOf("poise")==0) {
            u.__黑仔下次技能=0;u.__黑仔禁用技能AI=true;
            item.target._x=u._x+(item.face==0?1:-1)*(item.kind=="poiseClose" || item.kind=="poiseHealthy"?40:250);
            u.韧性上限=1000;u.remainingImpactForce=item.kind=="poiseClose"?560:550;
            item.startMP=u.mp;
            if (item.kind=="poiseLow" || item.kind=="poiseHealthy") {
                check(!u.黑仔霸体可用(),item.id+" low-level or healthy-close unit cannot activate poise");
                u.状态改变("霸体");check(u.状态=="兵器站立" && u.mp==item.startMP && !u.刚体,item.id+" refused poise changes no state, MP or rigid flag");
                u.等级=Number.NaN;check(!u.黑仔霸体可用(),item.id+" NaN level fails closed");return;
            }
            if (item.kind=="poiseExternal") {
                u.刚体=true;check(!u.黑仔霸体可用(),item.id+" pre-existing external rigid source avoids wasteful cast");u.刚体=false;
            }
            check(u.黑仔霸体可用(),item.id+" conditional distance/load gate accepts level30");
            u.状态改变("霸体");
            check(u.状态=="霸体" && u.man._totalframes==36 && u.mp==item.startMP,item.id+" native activation carrier preserves MP");
            check(u.刚体 && u.__黑仔霸体刚体 && u.__黑仔霸体剩余帧==90,item.id+" owned source supplies rigid body at startup");
            check(u.man._currentframe==1,item.id+" native poise begins at first actual frame");item.poiseVisited={};item.poiseVisited[1]=true;
            check(u.__黑仔霸体就绪>getTimer()+10000 && !u.黑仔霸体可用(),item.id+" independent poise cooldown prevents repeat");
            u.状态改变("兵器攻击");check(u.状态=="霸体",item.id+" ordinary chase attack cannot overwrite activation");
            if (item.kind=="poiseExternal") {
                u.刚体=true;u.黑仔霸体结束();
                check(u.刚体 && !u.__黑仔霸体刚体,item.id+" poise cleanup preserves an externally written rigid source");
                u.刚体=false;check(!u.刚体,item.id+" external source can independently relinquish rigid body");
            }
            recordOtherPreview(item);return;
        }
        if (item.kind=="mp") {
            u.__黑仔禁用技能AI=true;u.mp=0;u.状态改变("迅斩");check(u.状态=="迅斩" && u.mp==0,item.id+" zero MP allows native rapid without consumption");u.状态改变("被击");u.状态改变("兵器站立");return;
        }
        if (item.kind=="aiClose" || item.kind=="aiFar") {
            item.target._x=u._x+(item.face==0?1:-1)*(item.kind=="aiClose"?30:260);
            u.__黑仔下次技能=0;
            check(u.黑仔技能选择()=="",item.id+" close/far range refuses a blind heavy cast");
            item.target.Z轴坐标=u.Z轴坐标+40;
            check(u.黑仔技能选择()=="",item.id+" mismatched lane refuses skill");
            u.__黑仔禁用技能AI=true;return;
        }
        if (item.kind=="retreat" || item.kind=="retreatHit") {
            item.startX=u._x;item.target._x=u._x+(item.face==0?45:-45);
            u.__黑仔下次技能=0;u.__黑仔迅斩就绪=99999999;
            item.startMP=u.mp;u.黑仔每帧();
            check(u.__黑仔退步中 && u.状态=="兵器行走",item.id+" close target starts bounded native retreat");
            check(u.mp==item.startMP,item.id+" reposition does not consume a skill");
            u.黑仔行走();var firstStep:Number=u._x-item.startX;
            check(item.face==0?firstStep<0:firstStep>0,item.id+" retreat moves away while facing target");
            check(u.方向==(item.face==0?"右":"左"),item.id+" retreat preserves weapon facing");
            var moves:Number=u.fixtureMoves;u.黑仔每帧();
            check(u.fixtureMoves==moves,item.id+" driver does not duplicate native movement");
            u.__黑仔下次技能=99999999;
            if (item.kind=="retreatHit") {
                u.状态改变("被击");item.stoppedX=u._x;
                check(!u.__黑仔退步中,item.id+" real incoming state cancels retreat");
            }
            return;
        }
        if (item.kind=="aiOpening") {
            item.target.dispatcher=new EventDispatcher();item.target.损伤值=100;
            u.黑仔目标绑定();item.startMP=u.mp;u.状态改变("迅斩");item.rapidReady=u.__黑仔迅斩就绪;item.rapidStartTime=getTimer();return;
        }
        if (item.kind=="ai" || item.kind=="aiHeavy") {
            item.target._x=item.face==0?(item.kind=="ai"?280:220):(item.kind=="ai"?-80:-20);
            u.__黑仔下次技能=0;u.黑仔每帧();
            check(u.状态==(item.kind=="ai"?"迅斩":"凶斩"),item.id+" range controller selects expected skill");
            u.__黑仔下次技能=99999999;
            return;
        }
        // Same unit and draw transform as rapid-f1: retain the actual incoming
        // idle pose to inspect the entry without changing controller timing.
        if (exportBitmaps && item.kind=="rapid" && item.face==0) {
            var idleImage:BitmapData=new BitmapData(750,440,true,0);
            u.man.刚体标签._visible=false;u.area._visible=false;u._visible=true;
            idleImage.draw(u,new Matrix(1.8,0,0,1.8,370,360),null,"normal",null,true);
            u._visible=false;
            rapidPreviews.push({id:"black-rapid-entry-idle",bitmap:idleImage});
        }
        var next:String=item.kind=="combo"?"兵器攻击":((item.kind=="heavy" || item.kind=="heavyPrehit" || item.kind=="heavyPosthit")?"凶斩":"迅斩");
        item.startMP=u.mp;u.状态改变(next);
        u.__黑仔下次技能=99999999;
        check(u.状态==next,item.id+" actual attack label entered");
        if (next=="迅斩") check(u.man._totalframes==30,item.id+" imported rapid retains all30 authored recovery frames");
        if (next=="凶斩") check(u.man._totalframes==49,item.id+" imported heavy retains all49 authored frames");
        check(u.mp==item.startMP,item.id+" attack preserves MP");
        check(u.man.刀.刀.装扮.刀口位置1!=undefined,item.id+" fixed bat actual marker exists");
        if (item.kind=="combo") recordOtherPreview(item);
        if (item.kind=="rapid") {
            item.preMin=1000;item.preMax=-1000;item.preDrift=0;
            item.startX=u._x;item.rapidFrames={};
            recordRapidPreview(item);
        }
        if (item.kind=="cooldown") {
            u.动画完毕();u.状态改变("迅斩");
            check(u.状态=="兵器站立",item.id+" cooldown prevents relaunch");
        }
    }
    private static function capture(p:Object):Void {
        var u:MovieClip=black[p.发射者];
        if (u==undefined) u=military[p.发射者];
        var item:Object=u.fixtureCase;
        if (item==undefined) { check(false,"emission owned by actual published enemy");return; }
        item.hits++;
        var authoredFrame:Number=u.man._currentframe;
        if (p.技能名=="迅斩") check(authoredFrame==16 || authoredFrame==17 || authoredFrame==21,item.id+" rapid emission aligned to imported strike frames");
        if (p.技能名=="凶斩") check(authoredFrame==20 || authoredFrame==21 || authoredFrame==22,item.id+" heavy emission aligned to imported strike frames");
        if (item.kind=="heavy") {
            var bounds:Object=p.区域定位area.getBounds(black);
            var frontMin:Number=item.face==0?bounds.xMin-u._x:u._x-bounds.xMax;
            var frontMax:Number=item.face==0?bounds.xMax-u._x:u._x-bounds.xMin;
            check(frontMin>=-0.1 && frontMax<=147,item.id+" actual heavy area stays in front and within authored bat reach");
            if (authoredFrame==22 && frontMin<=105 && frontMax>=105 &&
                bounds.yMin-u.Z轴坐标<=-65 && bounds.yMax-u.Z轴坐标>=-65) item.sweptContact=true;
            trace("[ASSET_BLADE_BOUNDS] "+item.id+"|face="+item.face+"|frame="+u.man._currentframe+
                "|xMin="+(bounds.xMin-u._x)+"|xMax="+(bounds.xMax-u._x)+
                "|yMin="+(bounds.yMin-u.Z轴坐标)+"|yMax="+(bounds.yMax-u.Z轴坐标));
        }
        if (!item.first) { item.first=u.man._currentframe;item.firstPower=p.子弹威力;item.firstKnock=p.击倒率;item.firstHorizontal=p.水平击退速度;item.skillName=p.技能名; }
        if (item.kind=="aiOpening" && p.技能名=="迅斩" && !item.openingEventsDone) {
            item.openingEventsDone=true;var t:MovieClip=item.target;
            t.dispatcher.publish("hit",t,u,p,null,DamageResult.NULL);
            check(!u.黑仔凶斩机会有效(t,getTimer()),item.id+" NULL geometry event does not grant a followup");
            var result:DamageResult=new DamageResult();
            t.免疫击退=true;t.dispatcher.publish("hit",t,u,p,null,result);
            check(!u.黑仔凶斩机会有效(t,getTimer()),item.id+" knockback immunity gives no displacement opening");
            t.免疫击退=false;t.刚体=true;t.dispatcher.publish("hit",t,u,p,null,result);
            check(!u.黑仔凶斩机会有效(t,getTimer()),item.id+" rigid hit does not grant a displacement opening");
            t.刚体=false;t.dispatcher.publish("hit",t,u,p,null,result);
            check(u.黑仔凶斩机会有效(t,getTimer()),item.id+" production dispatcher real-hit contract grants timed opening");
            u.__黑仔凶斩机会到期=getTimer()-1;
            check(!u.黑仔凶斩机会有效(t,getTimer()),item.id+" expired opening cannot override range");
            t.dispatcher.publish("hit",t,u,p,null,result);
            var alt:MovieClip=black.createEmptyMovieClip(item.id+"Alt",black.getNextHighestDepth());
            alt.hp=1000;alt.Z轴坐标=t.Z轴坐标;alt._x=t._x;alt.dispatcher=new EventDispatcher();
            u.攻击目标=alt._name;u.黑仔目标绑定();
            t.dispatcher.publish("hit",t,u,p,null,result);
            check(!u.黑仔凶斩机会有效(t,getTimer()),item.id+" old target event is unsubscribed after aggro change");
            u.攻击目标=t._name;u.黑仔目标绑定();alt.dispatcher.destroy();alt.removeMovieClip();
            t.dispatcher.publish("hit",t,u,p,null,result);
            t._x=u._x+(item.face==0?100:-100);
            item.openingStartTime=getTimer();
        }
        if (item.kind=="aiOpening" && p.技能名=="凶斩" && !item.firstHeavy) {
            item.firstHeavy=u.man._currentframe;
        }
        if (item.kind=="combo") {
            var f:Number=u.man._currentframe;
            item.stages|=f<19?1:f<46?2:f<64?4:f<91?8:16;
        }
        if (isNaN(p.子弹威力) || !(p.子弹威力>0) || isNaN(p.shootX) || isNaN(p.shootY) || isNaN(p.shootZ)) {
            if (!item.invalid) trace("[ASSET_INVALID_EMISSION] "+item.id+"|frame="+u.man._currentframe+"|power="+p.子弹威力+"|x="+p.shootX+"|y="+p.shootY+"|z="+p.shootZ+"|marker="+p.区域定位area);
            item.invalid++;
        }
        if (!(u.hp>0) || item.interrupted) item.stale++;
    }
    private static function deflect(p:Object):Void {
        var owner:MovieClip=p.区域定位area._parent._parent;
        var item:Object=owner.fixtureCase;
        if (item!=undefined) item.deflects++;
    }
    // Source goldens: university rise reimport 4a77c833c4, frames 1/2/15/20.
    // That source has anonymous limb instances; authored coordinates are stable,
    // whereas the previous copied names (head/feet/rifle) no longer exist.
    private static function hasPosePart(man:MovieClip, x:Number, y:Number):Boolean {
        for (var key:String in man) {
            var part:Object=man[key];
            if (typeof(part)=="movieclip" && part._parent===man &&
                Math.abs(part._x-x)<0.1 && Math.abs(part._y-y)<0.1) return true;
        }
        trace("[ASSET_POSE_MISSING] frame="+man._currentframe+" x="+x+" y="+y);
        return false;
    }
    private static function freeze(u:MovieClip):Void {
        var item:Object=u.fixtureCase;
        if (item==undefined) return;
        item.freeze++;
        if (item.kind!="milDead") return;
        check(hasPosePart(u.man,-174.4,195.4),item.id+" actual death freezes canonical prone head");
        check(hasPosePart(u.man,4.9,264.7),item.id+" canonical rifle lies with body");
        check(hasPosePart(u.man,-51.9,260.05),item.id+" canonical prone forearm stays attached");
    }
    private static function tick():Void {
        if (finished) return;ticks++;
        _root.帧计时器.当前帧数=ticks;
        if (ticks==3) {
            for (var i:Number=0;i<cases.length;i++) {
                trace("StudentRepairAssetTest phase=begin-case id="+cases[i].id+" kind="+cases[i].kind);
                begin(cases[i]);
            }
            trace("StudentRepairAssetTest phase=begin-complete count="+cases.length+" elapsed-ms="+(getTimer()-startedAt));return;
        }
        if (ticks%30==0) trace("StudentRepairAssetTest phase=timeline tick="+ticks+" previews="+rapidPreviews.length);
        if (ticks<4) return;
        for (var j:Number=0;j<cases.length;j++) {
            var item:Object=cases[j];var u:MovieClip=item.unit;
            if (item.kind=="rapid" && u.状态=="迅斩") recordRapidPreview(item);
            if (item.kind=="combo" && u.状态=="兵器攻击") recordOtherPreview(item);
            if (item.kind.indexOf("poise")==0) {
                if (u.状态=="霸体") { item.poiseVisited[u.man._currentframe]=true;recordOtherPreview(item); }
                if (ticks==10) item.pausedPoiseFrames=u.__黑仔霸体剩余帧;
                if (ticks==14) check(u.__黑仔霸体剩余帧==item.pausedPoiseFrames,item.id+" pause does not consume poise duration");
                if ((item.kind=="poiseSafe" || item.kind=="poiseClose") && u.状态=="兵器站立" && !item.castCompleted) {
                    item.castCompleted=true;check(u.刚体 && u.__黑仔霸体剩余帧>0,item.id+" rigid source remains after native activation recovery");
                    check(item.poiseVisited[13] && item.poiseVisited[25],item.id+" middle and late native poise frames actually execute before recovery");
                }
                if (!item.interrupted && ticks==20 && (item.kind=="poiseDeath" || item.kind=="poiseLost")) {
                    item.interrupted=true;item.hitsBefore=item.hits;
                    if (item.kind=="poiseDeath") u.hp=0;else item.target.hp=0;
                }
            }
            // Real native wall-clock diagnostics; no clock, cooldown or AI is substituted.
            if (item.kind=="aiOpening" && (item.lastObservedState!=u.状态 ||
                u.状态=="迅斩" && u.man._currentframe==26)) {
                trace("[ASSET_OPENING_TIMING] "+item.id+"|tick="+ticks+"|now="+getTimer()+
                    "|state="+u.状态+"|frame="+u.man._currentframe+"|dx="+Math.abs(item.target._x-u._x)+
                    "|mp="+u.mp+"|hits="+item.hits+"|opening="+u.__黑仔凶斩机会到期+
                    "|next="+u.__黑仔下次技能+"|rapidReady="+u.__黑仔迅斩就绪+
                    "|heavyReady="+u.__黑仔凶斩就绪+"|borrow="+u.__黑仔本次凶斩借势+
                    "|openingStart="+item.openingStartTime);
                item.lastObservedState=u.状态;
            }
            if (item.kind=="aiOpening" && u.状态=="凶斩" && !item.heavyStarted) {
                item.heavyStarted=true;
                check(u.__黑仔本次凶斩借势===true,item.id+" recovered rapid enters heavy using measured safe opening");
                check(u.mp==item.startMP,item.id+" recovered rapid/heavy preserve MP");
                check(u.__黑仔迅斩就绪==item.rapidReady && isFinite(u.__黑仔凶斩就绪) && u.__黑仔凶斩就绪>=item.rapidReady-u.__黑仔迅斩冷却+u.__黑仔凶斩冷却,item.id+" followup preserves both independent cooldowns");
                u.__黑仔下次技能=99999999;
            }
            if (item.kind=="chase" && !_root.暂停 && ticks%4==0) u.unitAI.update();
            if (item.kind=="walk" && ticks==59) item.previousWalks=u.fixtureWalks;
            if (item.kind=="walk" && ticks==60) check(u.fixtureWalks-item.previousWalks==1,item.id+" walk consumes direction flags once per frame");
            if (item.kind=="milFly" && u.状态=="击倒" && u.man._currentframe==9) {
                check(u.man._currentframe==9,item.id+" native airborne pose stops at frame 9 before landing");
                // The landing signal is a fixture; recovery uses the real published timeline.
                item.landed=true;u.状态改变("倒地");
            }
            if (item.kind=="milRise" && u.状态=="倒地") {
                var frame:Number=u.man._currentframe;
                if (frame==15) { item.riseMid=true;check(hasPosePart(u.man,165.75,155.5) && hasPosePart(u.man,183.75,207.95),item.id+" both mid-rise feet match canonical source"); }
                if (frame==20) { item.riseLate=true;check(hasPosePart(u.man,0,-20.7),item.id+" late rise head matches canonical source"); }
                if (u.man._currentframe>item.lastFrame) item.lastFrame=u.man._currentframe;
            }
            var interruption:String=item.kind;
            var f:Number=u.man._currentframe;
            if (item.kind=="pause" && ticks==10) { item.pausedFrame=f;item.pausedHits=item.hits; }
            if (item.kind=="pause" && ticks==14) check(f==item.pausedFrame && item.hits==item.pausedHits,item.id+" pause stops real man timeline and emission");
            if (!item.interrupted && (((interruption=="prehit" || interruption=="heavyPrehit") && f>=6) || ((interruption=="posthit" || interruption=="heavyPosthit") && item.hits>=3) ||
                (interruption=="dead" && f>=6) || (interruption=="lost" && f>=6))) {
                item.interrupted=true;item.hitsBefore=item.hits;
                if (interruption=="dead") u.hp=0;
                else if (interruption=="lost") item.target.hp=0;
                else u.状态改变("被击");
            }
        }
        if (ticks==9) _root.暂停=true;
        if (ticks==16) _root.暂停=false;
        if (ticks>=135) finish();
    }
    private static function finish():Void {
        if (finished) return;finished=true;driver.onEnterFrame=null;
        trace("StudentRepairAssetTest phase=assertions tick="+ticks+" count="+cases.length+" elapsed-ms="+(getTimer()-startedAt));
        for (var i:Number=0;i<cases.length;i++) {
            var item:Object=cases[i];var u:MovieClip=item.unit;
            if (item.kind=="milRise" || item.kind=="milHit" || item.kind=="milMelee" || item.kind=="milFly") {
                check(u.状态=="长枪站立" && !u.倒地,item.id+" actual lifecycle restores state and collider");
                if (item.kind=="milFly") check(item.landed===true,item.id+" knockdown-to-rise transition exercised");
                if (item.kind=="milRise") check(item.riseMid && item.riseLate && item.lastFrame>=24,item.id+" canonical rise traverses middle and late poses before recovery");
                if (item.kind=="milMelee") {
                    check(item.hits==8,item.id+" all eight actual rifle-melee windows executed");
                    check(item.invalid==0 && item.stale==0,item.id+" rifle-melee coordinates and lifetime valid");
                }
            }
            else if (item.kind=="milDead") check(item.freeze==1 && u._parent==undefined,item.id+" actual death detection draws once and removes unit");
            else if (item.kind=="walk" || item.kind=="chase") {
                var delta:Number=u._x-item.startX;
                check(item.face==0?delta>50:delta < -50,item.id+" native locomotion/AI advances toward correct side");
                check(u.fixtureMoves>20 && u.fixtureWalks>20,item.id+" real movement helpers consume AI flags");
                check(isFinite(delta) && u._y==u.Z轴坐标 && item.hits==0,item.id+" movement has finite coordinates and no attack");
                if (u.unitAI!=undefined) u.unitAI.destroy();
            }
            else {
                if (item.kind.indexOf("poise")==0) {
                    check(item.hits==0 && !u.__黑仔霸体刚体 && !(u.__黑仔霸体剩余帧>0),item.id+" poise emits no damaging windows and owned rigid effect expires or clears");
                    if (item.kind=="poiseSafe" || item.kind=="poiseClose") check(item.castCompleted===true && !u.刚体,item.id+" whole native activation and expiration exercised");
                    if (item.kind=="poiseDeath") {
                        trace("[ASSET_POISE_DEATH] "+item.id+"|state="+u.状态+"|frame="+u.man._currentframe+"|freeze="+item.freeze+"|parent="+u._parent+"|depth="+u.getDepth()+"|hp="+u.hp);
                        check(item.freeze==1 && u._parent==undefined,item.id+" death clears poise before removing unit once");
                    }
                    else check(u.状态=="兵器站立",item.id+" poise recovers or aborts to standing");
                    continue;
                }
                if (item.kind=="retreat" || item.kind=="retreatHit") {
                    var retreatDistance:Number=Math.abs(u._x-item.startX);
                    check(retreatDistance>0 && retreatDistance<=45.01 && !u.__黑仔退步中,item.id+" retreat is finite and bounded to45px");
                    if (item.kind=="retreatHit") check(u._x==item.stoppedX,item.id+" no stale retreat after incoming hit");
                }
                if (item.kind=="aiOpening") {
                    check(item.heavyStarted && item.hits==18 && item.firstHeavy==20,item.id+" actual rapid+normal-rhythm heavy windows execute after recovery");
                    u.黑仔目标解绑();item.target.hp=0;item.target.dispatcher.destroy();
                }
                var rapid:Boolean=item.kind=="rapid" || item.kind=="ai" || item.kind=="pause";
                var heavy:Boolean=item.kind=="heavy" || item.kind=="aiHeavy";
                var expected:Number=rapid?9:heavy?9:0;
                if (item.kind=="combo") { check(item.hits==39,item.id+" actual native five-stage short-handle bat combo emits count="+item.hits);check(item.first==11,item.id+" short-handle first window follows its own native preparation");check(item.stages==31,item.id+" all five native combo stages executed"); }
                else if (rapid || heavy) check(item.hits==expected,item.id+" complete skill windows count="+item.hits);
                if (rapid) check(item.first==16,item.id+" extended windup first hit frame="+item.first);
                if (item.kind=="rapid") {
                    check(item.preMax-item.preMin>8,item.id+" compiled windup has continuous torso anticipation span="+(item.preMax-item.preMin));
                    check(item.preDrift<0.01,item.id+" windup does not move the unit before native lunge");
                }
                if (heavy) check(item.first==20,item.id+" normal heavy first hit frame="+item.first);
                if (item.kind=="heavy") check(item.sweptContact===true,item.id+" fast downswing covers front target body between authored poses");
                if (rapid || heavy) check(item.deflects>0,item.id+" native deflection window executed");
                if (item.kind=="heavyPrehit" || item.kind=="heavyPosthit") check(item.interrupted===true,item.id+" imported heavy actually reaches requested interruption boundary");
                if (item.interrupted) check(item.hits==item.hitsBefore,item.id+" no outgoing attack after interruption");
                check(item.invalid==0 && item.stale==0,item.id+" finite coordinates/formula and valid lifetime");
                if (item.kind!="dead") check(u.状态=="兵器站立",item.id+" recovered standing state");
                else check(item.freeze==1 && u._parent==undefined,item.id+" death interrupt reaches removal once");
            }
        }
        var rapidPower:Array=[],heavyPower:Array=[],rapidKnock:Array=[],heavyKnock:Array=[],rapidHorizontal:Array=[];
        for (var pairIndex:Number=0;pairIndex<cases.length;pairIndex++) {
            var pair:Object=cases[pairIndex];
            if (pair.kind=="rapid") { rapidPower[pair.face]=pair.firstPower;rapidKnock[pair.face]=pair.firstKnock;rapidHorizontal[pair.face]=pair.firstHorizontal;check(pair.skillName=="迅斩",pair.id+" actual outgoing rapid attribution retained"); }
            if (pair.kind=="heavy") { heavyPower[pair.face]=pair.firstPower;heavyKnock[pair.face]=pair.firstKnock;check(pair.skillName=="凶斩",pair.id+" actual outgoing heavy attribution retained"); }
        }
        check(rapidHorizontal[0]==8 && rapidHorizontal[1]==8,"compiled rapid uses finite native horizontal knockback8 on both facings");
        check(Math.abs(rapidPower[0]-rapidPower[1])<0.001,"actual rapid emission does not scale with extra force");
        check(Math.abs(heavyPower[0]-heavyPower[1]-1350)<0.001,"actual heavy emission gains 9 power per force point at skill level 1");
        var nativeImpact:Object={hp:1000,防御力:100,韧性系数:5,躲闪率:10,remainingImpactForce:0};
        var rapidImpact:Object={hp:1000,防御力:100,韧性系数:5,躲闪率:10,remainingImpactForce:0};
        ImpactHandler.settleImpactForce(100,2/11,nativeImpact);
        ImpactHandler.settleImpactForce(100,rapidKnock[0],rapidImpact);
        check(Math.abs(rapidImpact.remainingImpactForce-nativeImpact.remainingImpactForce*2)<0.01,"actual compiled rapid denominator yields twice native rapid impact with equal settled damage");
        check(rapidKnock[0]>0 && rapidKnock[0]==rapidKnock[1] && heavyKnock[0]==10 && heavyKnock[1]==10,"rapid impact enhancement retains finite knock denominator and normal heavy impact");
        var visible:Rectangle=corpse.getColorBoundsRect(0xFF000000,0,false);
        trace("[ASSET_BITMAP_BOUNDS] military: "+visible);
        check(visible.width>50 && visible.height<80,"actual corpse bitmap stays in coherent prone band");
        _root.暂停=true;stopMovieTree(world);
        trace("StudentRepairAssetTest phase=export previews="+rapidPreviews.length);
        // Corpse bounds remain a required assertion; lossless image rows are diagnostic export.
        preview=black.attachMovie("敌人-Codex黑仔","blackPreview",black.getNextHighestDepth(),{兵种:"敌人-Codex黑仔"});
        preview.__黑仔禁用技能AI=true;
        preview.状态改变("兵器站立");preview.man.gotoAndStop(1);
        driver.shotWait=0;
        driver.onEnterFrame=function():Void {
            try { if (++this.shotWait>=4) StudentRepairAssetTest.snapshotAndComplete(); }
            catch (error:Object) { StudentRepairAssetTest.abortFixture("standing snapshot",error); }
        };
    }
    // All behavior assertions have already run. Retire their timelines before
    // diagnostic export; the new standing preview is attached after this freeze.
    private static function stopMovieTree(mc:MovieClip):Void {
        mc.stop();delete mc.onEnterFrame;
        for (var key:String in mc) {
            var child:Object=mc[key];
            if (typeof(child)=="movieclip" && child._parent===mc) stopMovieTree(MovieClip(child));
        }
    }
    private static function snapshotAndComplete():Void {
        driver.onEnterFrame=null;
        preview.人物文字信息._visible=false;preview.新版人物文字信息._visible=false;
        check(preview.man.身体._width>50 && preview.man.身体._height>100,"compiled fixed torso retains visible clothing geometry");
        var image:BitmapData=new BitmapData(600,600,true,0);
        image.draw(preview,new Matrix(3,0,0,3,250,450),null,"normal",null,true);
        var torso:Object={x:0,y:0};preview.man.身体.身体.基本款.localToGlobal(torso);preview.globalToLocal(torso);
        var torsoPixel:Number=image.getPixel32(Math.round(250+torso.x*3),Math.round(450+torso.y*3));
        check((torsoPixel>>>24)>0 && ((torsoPixel>>>16)&255)<100 && ((torsoPixel>>>8)&255)<100 && (torsoPixel&255)<100,"native black jacket center is filled and dark");
        // All snapshots own their pixels; release the live scene before readback.
        // Hidden timelines still allocate and dispatch events if left resident.
        retireWorld();
        if (!exportBitmaps) { image.dispose();complete();return; }
        rapidPreviews.unshift({id:"black-stand",bitmap:image});
        rapidPreviews.unshift({id:"military-corpses",bitmap:corpse,retain:true});
        driver.previewIndex=0;
        // Pixel serialization is independent of animation frame cadence.
        // A bounded timer slice also runs when the test player has an idle stage.
        exportTimer=setInterval(function():Void {
            try { StudentRepairAssetTest.exportTick(); }
            catch (error:Object) { StudentRepairAssetTest.abortFixture("bitmap export "+StudentRepairAssetTest.driver.previewIndex,error); }
        },10);
    }
    private static function recordOtherPreview(item:Object):Void {
        if (!exportBitmaps || item.face!=0 || (item.kind!="combo" && item.kind!="poiseSafe")) return;
        var u:MovieClip=item.unit;var frame:Number=u.man._currentframe;
        if (item.otherFrames==undefined) item.otherFrames={};
        if (item.otherFrames[frame]) return;
        if (item.kind=="combo") {
            if (!(frame==1 || frame==3 || frame==5 || frame==9 || frame==11 || frame==14 || frame==18 || frame==23 || frame==29 || frame==35 || frame==44 || frame==46 || frame==53 || frame==63 || frame==64 || frame==71 || frame==74 || frame==84 || frame==87 || frame==90 || frame==91 || frame==101 || frame==104 || frame==108)) return;
        } else if (!(frame==1 || frame==13 || frame==25 || frame==36)) return;
        item.otherFrames[frame]=true;
        var image:BitmapData=new BitmapData(750,440,true,0);
        u.man.刚体标签._visible=false;u.人物文字信息._visible=false;u.新版人物文字信息._visible=false;u.area._visible=false;u._visible=true;
        image.draw(u,new Matrix(1.8,0,0,1.8,370,360),null,"normal",null,true);u._visible=false;
        rapidPreviews.push({id:(item.kind=="combo"?"black-combo-f":"black-poise-f")+frame,bitmap:image});
    }
    private static function recordRapidPreview(item:Object):Void {
        var u:MovieClip=item.unit;
        var frame:Number=u.man._currentframe;
        if (frame<=14) {
            item.preMin=Math.min(item.preMin,u.man.身体._rotation);
            item.preMax=Math.max(item.preMax,u.man.身体._rotation);
            item.preDrift=Math.max(item.preDrift,Math.abs(u._x-item.startX));
        }
        if (!exportBitmaps || item.face!=0 || item.rapidFrames[frame]) return;
        // Capture every actual rapid frame, including the anticipation-to-strike transition.
        item.rapidFrames[frame]=true;
        var image:BitmapData=new BitmapData(750,440,true,0);
        u.man.刚体标签._visible=false;
        u.人物文字信息._visible=false;u.新版人物文字信息._visible=false;u.area._visible=false;
        u._visible=true;
        image.draw(u,new Matrix(1.8,0,0,1.8,370,360),null,"normal",null,true);
        u._visible=false;
        rapidPreviews.push({id:"black-rapid-f"+frame,bitmap:image});
    }
    private static function complete():Void {
        if (exportTimer!=undefined) { clearInterval(exportTimer);exportTimer=undefined; }
        if (exportBitmaps) {
            check(exportedImages==rapidPreviews.length && exportedImages>2 && exportedRows>0,"all queued native bitmaps exported before completion");
            trace("StudentRepairBitmapExport: "+exportedImages+" images, "+exportedRows+" rows");
        }
        trace("StudentRepairAssetTest phase=complete elapsed-ms="+(getTimer()-startedAt));
        if (!loadProbeOnly) trace("StudentRepairAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        retireWorld();driver.removeMovieClip();corpse.dispose();
        _root.studentRepairAssetComplete();
    }
    private static function retireWorld():Void {
        if (worldRetired) return;worldRetired=true;
        loader.removeListener(listener);
        loader.unloadClip(military);loader.unloadClip(black);world.removeMovieClip();
    }
    private static function abortFixture(phase:String, error:Object):Void {
        if (exportTimer!=undefined) { clearInterval(exportTimer);exportTimer=undefined; }
        trace("[TEST_FAIL] StudentRepairAssetTest exception phase="+phase+" error="+error);
        failed++;finished=true;delete driver.onEnterFrame;
        trace("StudentRepairAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        // The runner archives this failure and stops its owned host; never report pass.
        _root.studentRepairAssetComplete();
    }
    // Optional lossless visual evidence. Bound computation between rows to 8ms,
    // with a 64-row ceiling. Buffer trace writes so the editor does not repaint
    // thousands of individual rows while already-tested actors keep animating.
    private static function exportTick():Void {
        if (exportPicture==null) {
            if (driver.previewIndex>=rapidPreviews.length) { complete();return; }
            exportPicture=rapidPreviews[driver.previewIndex++];
            exportPicture.scanStart=readbackScanMs;exportPicture.encodeStart=readbackEncodeMs;exportPicture.traceStart=readbackTraceMs;exportPicture.beganAt=getTimer();
            exportBounds=exportPicture.bitmap.getColorBoundsRect(0xFFFFFFFF,0,false);
            exportY=exportBounds.y;exportEndY=exportBounds.y+exportBounds.height;
            exportLines=[];exportBufferedRows=0;
            trace("[ASSET_BITMAP_BEGIN] "+exportPicture.id+" "+exportPicture.bitmap.width+" "+exportPicture.bitmap.height);
        }
        var began:Number=getTimer(),rows:Number=0;readbackCallbacks++;
        while (exportY<exportEndY && rows<64 && (rows==0 || getTimer()-began<8)) {
            exportRow(exportPicture.bitmap,exportY++);rows++;
        }
        if (exportBufferedRows>=32 || exportY>=exportEndY) {
            var traceBegan:Number=getTimer();
            if (exportLines.length) trace(exportLines.join("\n"));
            readbackTraceMs+=getTimer()-traceBegan;
            exportLines=[];exportBufferedRows=0;
        }
        if (exportY>=exportEndY) {
            trace("[ASSET_READBACK_COST] "+exportPicture.id+" scan-ms="+(readbackScanMs-exportPicture.scanStart)+" encode-ms="+(readbackEncodeMs-exportPicture.encodeStart)+" trace-ms="+(readbackTraceMs-exportPicture.traceStart)+" wall-ms="+(getTimer()-exportPicture.beganAt));
            trace("[ASSET_BITMAP_END] "+exportPicture.id);exportedImages++;
            if (!exportPicture.retain) exportPicture.bitmap.dispose();
            exportPicture.bitmap=null;exportPicture=null;
        }
    }
    private static function exportRow(bitmap:BitmapData, y:Number):Void {
        // AVM1 repeatedly resolves class-qualified static members. Keep the pixel
        // and run loops on local aliases; join once instead of copying a growing row.
        var bounds:Rectangle=exportBounds;
        var palette:Object=hexCache;
        var paletteSize:Number=hexCacheSize;
        var makeHex:Function=bitmapColorHex;
        var endX:Number=bounds.x+bounds.width;
        var colors:Array=[],lengths:Array=[],runs:Array=[];
        var last:Number=-1,count:Number=0,opaque:Boolean=false;
        if (bounds.x>0) { last=0;count=bounds.x; }
        var scanBegan:Number=getTimer();
        for (var x:Number=bounds.x;x<endX;x++) {
            var pixel:Number=bitmap.getPixel32(x,y);
            if (pixel!=0) opaque=true;
            if (pixel==last) count++;
            else { if (count) { colors.push(last);lengths.push(count); } last=pixel;count=1; }
        }
        if (endX<bitmap.width) {
            if (last==0) count+=bitmap.width-endX;
            else { colors.push(last);lengths.push(count);last=0;count=bitmap.width-endX; }
        }
        colors.push(last);lengths.push(count);
        var scanMs:Number=getTimer()-scanBegan;
        var encodeBegan:Number=getTimer();
        for (var n:Number=0;n<colors.length;n++) {
            var value:Number=colors[n];
            var color:String=palette[value];
            if (color==undefined) {
                color=makeHex(value);
                if (paletteSize<32768) { palette[value]=color;paletteSize++; }
            }
            runs.push(color+":"+lengths[n]);
        }
        readbackScanMs+=scanMs;readbackEncodeMs+=getTimer()-encodeBegan;
        hexCacheSize=paletteSize;
        if (opaque) { exportLines.push("[ASSET_BITMAP_ROW] "+y+" "+runs.join(","));exportBufferedRows++;exportedRows++; }
    }
    private static function bitmapColorHex(pixel:Number):String {
        // AVM1 formats signed INT_MIN as "-(0000000". Serialize safe 16-bit halves.
        var low:String=(pixel & 65535).toString(16);
        while (low.length<4) low="0"+low;
        var color:String=((pixel >>> 16) & 65535).toString(16)+low;
        return color;
    }
}
