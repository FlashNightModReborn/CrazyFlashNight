import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.UnitComponent.Routing.StateTransition;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.neur.ScheduleTimer.CooldownWheel;

/** #165：现役角色/双枪上身时间轴、生产输入绑定及真实弹药提交；库存与弹体出口隔离。 */
class org.flashNight.arki.unit.Action.Shoot.DualGunReloadTimelineTest {
    private static var passed:Number, failed:Number, frame:Number, age:Number, index:Number;
    private static var driver:MovieClip, library:MovieClip, unit:MovieClip;
    private static var cases:Array, current:Object, shots:Array, reloads:Array, saved:Object, reloadProbe:Object;
    private static var stage:String, oldTick:Function, mainReload:Function, subReload:Function;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] DualGunReloadTimelineTest: "+current.name+" "+label);}
    }
    private static function data(side:Number):Object {
        return {capacity:side==0?2:3,interval:side==0?150:210,singleshoot:false,
            clipname:side==0?"dual-main-mag":"dual-off-mag",split:1,diffusion:1,sound:"",muzzle:"",
            bullet:side==0?"dual-main-probe":"dual-off-probe",velocity:30,bullethit:"",power:100,
            bulletsize:50,impact:5,targethit:"",weapontype:"冲锋枪"};
    }
    public static function initUnit(u:MovieClip):Void {
        u.兵种="主角-男";
        u.存储当前飞行状态=function():Void {};
        u.读取当前飞行状态=function():Void {};
        u.攻击模式="双枪";u.状态="双枪站立";u.方向="右";u.hp=100;u.Z轴坐标=0;
        u.手枪={name:"dual-main-probe",value:{shot:current.intent=="main"?0:2,level:1}};
        u.手枪2={name:current.same?"dual-main-probe":"dual-off-probe",value:{shot:current.intent=="off"?0:3,level:1}};
        u.手枪属性=data(0);u.手枪2属性=data(1);u.手枪弹匣容量=2;u.手枪2弹匣容量=3;
        u.被动技能={冲击连携:{启用:current.impact,等级:10},枪械师:{启用:false,等级:1}};
        u.动作A=u.动作B=u.动作C=false;u.主手射击中=u.副手射击中=false;
        u.行走=function():Void {};u.操控编号=-1;u.移动射击=false;u.行走冷却帧=0;
        u.dispatcher=new EventDispatcher();u.dispatcher.subscribe("processShot",FireEventComponent.processShot,u);
        u.手枪射击=WeaponFireCore.PISTOL_SHOOT;u.手枪2射击=WeaponFireCore.PISTOL2_SHOOT;
    }
    private static function stock(name:String):Number {return current.noOffStock&&name=="dual-off-mag"?0:1000;}
    private static function capture(props:Object):Void {
        var side:Number=props.子弹种类=="dual-off-probe"?1:0;
        if(shots[0].length+shots[1].length==0&&!current.intent&&!current.noOffStock)
            check(reloads[0]>0&&reloads[1]>0,"held triggers wait for both initial magazine commits");
        shots[side].push(frame);
        trace("[DUAL_RELOAD_SHOT] case="+current.name+" hand="+side+" frame="+frame+" reloads="+reloads.join(","));
    }
    public static function runAllTests():Void {
        passed=failed=frame=0;index=-1;stage="attach";reloadProbe=null;
        cases=[{name:"full-auto-different-impact-off",impact:false},{name:"full-auto-different-impact-on",impact:true},
            {name:"full-auto-same-impact-off",same:true,impact:false},{name:"full-auto-same-impact-on",same:true,impact:true},
            {name:"fresh-main-press-interrupts",impact:true,intent:"main"},
            {name:"fresh-off-press-interrupts",impact:true,intent:"off"},
            {name:"offhand-out-of-stock-finishes",impact:false,noOffStock:true},
            {name:"dual-main-upper-body-reload-continuity",impact:false,continuity:true,probeHand:"主手"},
            {name:"dual-off-upper-body-reload-continuity",impact:false,continuity:true,probeHand:"副手"}];
        saved={world:_root.gameworld,control:_root.控制目标,pause:_root.暂停,clock:_root.帧计时器,
            save:_root.存档系统,ui:_root.玩家信息界面,sound:_root.soundEffectManager,bullet:_root.子弹区域shoot传递,
            initHero:_root.初始化主角模板,functions:_root.主角函数,playSound:_root.播放音效,
            contain:ItemUtil.singleContain,total:ItemUtil.getTotal,submit:ItemUtil.singleSubmit};
        oldTick=CooldownWheel.I().tick;CooldownWheel.I().tick=function():Void {
            DualGunReloadTimelineTest.frame++;_root.帧计时器.当前帧数=DualGunReloadTimelineTest.frame;
            DualGunReloadTimelineTest.oldTick.call(CooldownWheel.I());
        };
        _root.暂停=false;_root.帧计时器={当前帧数:0};_root.存档系统={};_root.玩家信息界面={玩家必要信息界面:{}};
        _root.soundEffectManager={playSound:function():Void {}};_root.播放音效=function():Void {};
        _root.子弹区域shoot传递=capture;
        ItemUtil.singleContain=function(name:String):Object {return DualGunReloadTimelineTest.stock(name)>0?{}:null;};
        ItemUtil.getTotal=stock;ItemUtil.singleSubmit=function(name:String):Boolean{return DualGunReloadTimelineTest.stock(name)>0;};
        _root.初始化主角模板=function():Void {DualGunReloadTimelineTest.initUnit(this);};
        _root.主角函数={};
        _root.主角函数.初始化双枪射击函数=function():Void {ShootInitCore.initDualGun(this,this._parent);};
        _root.主角函数.双枪初始化换弹负担=ReloadManager.initDualGunReloadBurden;
        _root.主角函数.双枪换弹门禁=ReloadManager.handleDualGunReloadGate;
        _root.主角函数.双枪换弹帧率控制=ReloadManager.controlReloadFrameRate;
        library=_root.createEmptyMovieClip("__dualReloadLibrary",_root.getNextHighestDepth());library._visible=false;_root.gameworld=library;
        driver=_root.createEmptyMovieClip("__dualReloadDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {DualGunReloadTimelineTest.step();};
        nextCase();
    }
    private static function nextCase():Void {
        restoreProbePause();
        if(unit){ShootCore.cleanup(unit);unit.removeMovieClip();}EnhancedCooldownWheel.I().reset();ShootCore._lastShotTimes={};
        index++;if(index>=cases.length){finish();return;}
        current=cases[index];shots=[[],[]];reloads=[0,0];age=0;stage="attach";
        reloadProbe={progressed:false};
        unit=library.attachMovie("主角-男","dualReloadHero",library.getNextHighestDepth());
        check(unit!=null,"attaches production hero");if(unit==null){finish();return;}
        initUnit(unit);_root.控制目标=unit._name;
    }
    private static function step():Void {
        if(stage=="done")return;
        if(frame>cases.length*340+300){check(false,"native dual-gun watchdog");finish();return;}
        if(stage=="attach"){stage="ready";unit.gotoAndStop("双枪站立");return;}
        if(current.continuity){stepContinuity();return;}
        if(stage=="ready"){
            if(typeof unit.man.主手开始射击!="function"||typeof unit.man.副手开始射击!="function")return;
            check(unit.man._totalframes==107,"uses actual 107-frame dual-gun upper body");
            mainReload=unit.man.主手换弹匣;subReload=unit.man.副手换弹匣;
            unit.man.主手换弹匣=function():Void {DualGunReloadTimelineTest.reloads[0]++;DualGunReloadTimelineTest.mainReload();};
            unit.man.副手换弹匣=function():Void {DualGunReloadTimelineTest.reloads[1]++;DualGunReloadTimelineTest.subReload();};
            unit.动作A=unit.动作B=true;unit.man.开始换弹();stage="run";age=0;return;
        }
        age++;
        if(current.intent){
            if(age==3)unit[current.intent=="main"?"动作A":"动作B"]=false;
            if(age==6)unit[current.intent=="main"?"动作A":"动作B"]=true;
            if(age==2)check(shots[0].length+shots[1].length==0&&!!unit.man.换弹标签,"inherited hold does not cancel reload before a new press");
            if(age==10)check(!unit.man.换弹标签&&shots[current.intent=="main"?0:1].length>0,"one released and repressed hand can interrupt while the other stays held");
        }
        var limit:Number=current.intent?50:240;
        if(age<limit){if(unit.动作A)unit.man.主手开始射击();if(unit.动作B)unit.man.副手开始射击();}
        else {
            unit.动作A=unit.动作B=false;ShootCore.stopForReload(unit);
            trace("[DUAL_RELOAD_CASE] "+current.name+" shots="+shots[0].length+","+shots[1].length+" reloads="+reloads.join(","));
            if(!current.intent){
                check(shots[0].length>=4&&reloads[0]>=2,"main hand continues through multiple reload cycles");
                if(current.noOffStock)check(shots[1].length==0,"unavailable offhand stock does not grant free rounds");
                else check(shots[1].length>=6&&reloads[1]>=2,"offhand continues through multiple reload cycles without starvation");
            }
            nextCase();
        }
    }
    private static function restoreProbePause():Void {
        if(reloadProbe.paused===true){_root.暂停=reloadProbe.pause;reloadProbe.paused=false;}
    }
    private static function checkContinuity(direction:String):Void {
        var label:String=direction+" "+current.probeHand;
        check(age>reloadProbe.switchAge,label+" is observed on a later real enterFrame");
        check(unit.man.__reloadProbeIdentity===reloadProbe.marker,label+" preserves upper-body identity");
        check(unit.man.__reloadIdentity===reloadProbe.token,label+" preserves native reload token");
        check(unit.man.结束换弹===reloadProbe.completion,label+" preserves captured completion");
        check(unit.man.reloadFrameControlRequest===reloadProbe.request,label+" preserves control request");
        check(unit.man.reloadFrameProgress===reloadProbe.progress,label+" preserves fractional progress");
        check(unit.man._currentframe===reloadProbe.oldFrame,label+" preserves reload frame");
        check(unit.man.reloadFrameControlActive===true,label+" preserves frame control");
        check(unit.man.换弹标签===true,label+" preserves reload tag");
        check(ReloadManager.getReloadGeneration(unit.man)===reloadProbe.oldGeneration,label+" preserves generation");
    }
    private static function captureContinuity():Void {
        var marker:Object={};
        unit.man.__reloadProbeIdentity=marker;
        reloadProbe.marker=marker;
        reloadProbe.token=unit.man.__reloadIdentity;
        reloadProbe.completion=unit.man.结束换弹;
        reloadProbe.request=unit.man.reloadFrameControlRequest;
        reloadProbe.progress=unit.man.reloadFrameProgress;
        reloadProbe.oldFrame=unit.man._currentframe;
        reloadProbe.oldGeneration=ReloadManager.getReloadGeneration(unit.man);
        reloadProbe.standFrame=unit._currentframe;
        reloadProbe.pause=_root.暂停;reloadProbe.paused=true;_root.暂停=true;
        trace("[RELOAD_CONTINUITY_CAPTURE] case="+current.name+" hand="+current.probeHand+" frame="+reloadProbe.oldFrame+" generation="+reloadProbe.oldGeneration);
        // 由不会随换姿卸载的 root/class 驱动，使用正式状态转换入口。
        reloadProbe.switchAge=age;stage="probe-walk";
        StateTransition.apply(unit,"双枪行走");
    }
    private static function stepContinuity():Void {
        age++;
        if(age>260){check(false,"continuity watchdog at "+stage);nextCase();return;}
        try {advanceContinuity();}
        catch(error:Error){check(false,"continuity exception: "+error);nextCase();}
    }
    private static function advanceContinuity():Void {
        if(stage=="ready"){
            if(typeof unit.man.主手开始射击!="function"||typeof unit.man.副手开始射击!="function")return;
            check(typeof unit.man=="movieclip","uses a real production upper-body MovieClip");
            check(unit.man._totalframes==107,"uses actual 107-frame dual-gun upper body");
            check(unit.手枪.value.shot===2&&unit.手枪2.value.shot===3,"both magazines begin empty");
            // 观察两段真实提交；不按住扳机，避免装填后自动射击消耗断言所需的弹药。
            mainReload=unit.man.主手换弹匣;subReload=unit.man.副手换弹匣;
            unit.man.主手换弹匣=function():Void {DualGunReloadTimelineTest.reloads[0]++;DualGunReloadTimelineTest.mainReload();};
            unit.man.副手换弹匣=function():Void {DualGunReloadTimelineTest.reloads[1]++;DualGunReloadTimelineTest.subReload();};
            unit.动作A=unit.动作B=false;stage="probe-wait";unit.man.开始换弹();return;
        }
        if(stage=="probe-wait"){
            var midpoint:Number=Math.floor((unit.man.reloadStartFrame+unit.man.reloadEndFrame)/2);
            if(unit.man.reloadFrameControlActive===true&&unit.man.换弹标签===true
                &&unit.man.dualReloadHandPrefix==current.probeHand
                &&unit.man._currentframe>midpoint-1&&unit.man._currentframe<unit.man.reloadEndFrame-2)
                captureContinuity();
            return;
        }
        if(stage=="probe-walk"){
            check(unit._currentframe!==reloadProbe.standFrame,"parent reaches the walking keyframe");
            checkContinuity("stand->walk");
            reloadProbe.switchAge=age;stage="probe-stand";
            StateTransition.apply(unit,"双枪站立");return;
        }
        if(stage=="probe-stand"){
            check(unit._currentframe===reloadProbe.standFrame,"parent returns to the standing keyframe");
            checkContinuity("walk->stand");
            restoreProbePause();stage="probe-resume";return;
        }
        if(stage=="probe-resume"){
            if(unit.man.__reloadProbeIdentity===reloadProbe.marker&&unit.man._currentframe>reloadProbe.oldFrame)
                reloadProbe.progressed=true;
            if(unit.man.换弹标签===false){
                check(reloadProbe.progressed===true,"reload advances after restoring pause");
                check(unit.man.__reloadProbeIdentity===reloadProbe.marker,"original upper body finishes both reload segments");
                check(unit.man.reloadFrameControlActive!==true&&ReloadManager.getReloadGeneration(unit.man)>reloadProbe.oldGeneration,
                    "reload finishes and releases frame control");
                check(reloads[0]===1&&reloads[1]===1,"both native magazine commits run once");
                check(unit.手枪.value.shot===0&&unit.手枪2.value.shot===0,"both magazines are filled");
                check(shots[0].length+shots[1].length===0,"continuity fixture does not consume the loaded rounds");
                trace("[RELOAD_CONTINUITY_COMPLETE] case="+current.name+" progressed="+reloadProbe.progressed+" reloads="+reloads.join(","));
                nextCase();
            }
        }
    }
    private static function finish():Void {
        if(stage=="done")return;stage="done";delete driver.onEnterFrame;
        restoreProbePause();
        if(unit){ShootCore.cleanup(unit);unit.removeMovieClip();}EnhancedCooldownWheel.I().reset();
        trace("--- DualGunReloadTimelineTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
        CooldownWheel.I().tick=oldTick;
        ItemUtil.singleContain=saved.contain;ItemUtil.getTotal=saved.total;ItemUtil.singleSubmit=saved.submit;
        _root.gameworld=saved.world;_root.控制目标=saved.control;_root.暂停=saved.pause;_root.帧计时器=saved.clock;
        _root.存档系统=saved.save;_root.玩家信息界面=saved.ui;_root.soundEffectManager=saved.sound;
        _root.子弹区域shoot传递=saved.bullet;_root.初始化主角模板=saved.initHero;_root.主角函数=saved.functions;_root.播放音效=saved.playSound;
        library.removeMovieClip();_root.dualGunReloadTimelineComplete();
    }
}
