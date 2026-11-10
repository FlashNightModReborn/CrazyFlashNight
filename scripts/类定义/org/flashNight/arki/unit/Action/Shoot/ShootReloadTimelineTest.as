import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.UnitComponent.Routing.StateTransition;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.neur.ScheduleTimer.CooldownWheel;

/** 现役 things0 角色与换弹标签；输入经生产绑定，库存和弹体出口隔离。 */
class org.flashNight.arki.unit.Action.Shoot.ShootReloadTimelineTest {
    private static var passed:Number, failed:Number, frame:Number, age:Number, index:Number, stage:String;
    private static var driver:MovieClip, library:MovieClip, unit:MovieClip, loader:MovieClipLoader;
    private static var shots:Array, cases:Array, current:Object, readyAt:Number;
    private static var weapon:Object, weapons:Object, loadingWeapon:String, sourceXml:XML, oldRateClear:Function, oldWheelTick:Function;
    private static var saved:Object, reloadProbe:Object;
    private static function check(ok:Boolean,label:String):Void {if(ok)passed++;else{failed++;trace("[TEST_FAIL] ShootReloadTimelineTest: "+label);}}
    public static function initUnit(u:MovieClip):Void {
        u.兵种="主角-男";
        u.存储当前飞行状态=function():Void {};
        u.读取当前飞行状态=function():Void {};
        u.攻击模式="长枪";u.状态="长枪站立";u.方向="右";u.hp=100;u.Z轴坐标=0;
        u.长枪={name:current.weaponName||"53式步骑枪",value:{shot:current.prior?0:2,level:1}};u.长枪弹匣容量=weapon.capacity;
        u.长枪属性={};for(var key:String in weapon)u.长枪属性[key]=weapon[key];u.长枪属性.singleshoot=current.semi;
        u.被动技能={枪械师:{启用:current.gs,等级:10}};u.动作A=u.动作B=u.动作C=false;
        u.行走=function():Void {};u.操控编号=-1;u.移动射击=false;u.行走冷却帧=0;
        u.dispatcher=new EventDispatcher();u.dispatcher.subscribe("processShot",FireEventComponent.processShot,u);
        u.长枪射击=WeaponFireCore.LONG_GUN_SHOOT;
        if(current.continuity)initContinuityUnit(u);
    }
    private static function initContinuityUnit(u:MovieClip):Void {
        var mode:String=current.mode;
        u.攻击模式=mode;u.状态=mode+"站立";
        // 只隔离弹药配置；上身必须来自生产 things0 的真实主角，不能用 Object 替代。
        u[mode]={name:"upper-body-reload-probe",value:{shot:current.cancelLive?1:3,level:1}};
        u[mode+"弹匣容量"]=3;
        u[mode+"属性"]={capacity:3,interval:200,singleshoot:false,clipname:"continuity-probe-mag",
            split:1,diffusion:1,sound:"",muzzle:"",bullet:"continuity-probe",velocity:30,
            bullethit:"",power:100,bulletsize:50,impact:5,targethit:"",weapontype:mode};
        u.手枪射击=WeaponFireCore.PISTOL_SHOOT;u.手枪2射击=WeaponFireCore.PISTOL2_SHOOT;
    }
    private static function capture(props:Object):Void {
        shots.push(frame);trace("[TIMELINE_SHOT] case="+current.name+" frame="+frame+" man="+unit.man._currentframe+" task="+unit.keepshooting+" chain="+unit._gunslingerChain_keepshooting+" reload="+!!unit.man.换弹标签);
    }
    private static function observeRateClear(key:String, owner:Object):Void {trace("[RATE_UNLOCK] frame="+frame+" lastShot="+shots[shots.length-1]+" key="+key);oldRateClear(key,owner);}
    public static function runAllTests():Void {
        passed=failed=frame=0;index=-1;stage="loading";shots=[];cases=[];unit=null;reloadProbe=null;
        cases=[{name:"type53-tapR-heldFire",semi:true,gs:false,hold:false},{name:"type53-priorShot-tapR-tapFire",semi:true,gs:false,hold:false,tap:true,prior:true},{name:"type53-priorShot-tapR-heldFire",semi:true,gs:false,hold:false,prior:true},{name:"type53-holdR-heldFire",semi:true,gs:false,hold:true},{name:"type53-gunslinger",semi:true,gs:true,hold:false},{name:"auto-control",semi:false,gs:false,hold:false}];
        var magazineCases:Array=[
            {name:"barrett-alternating-R-J",weaponName:"战术巴雷特",semi:true,gs:false,prior:true,pattern:"alternate"},
            {name:"barrett-heldJ-tapR",weaponName:"战术巴雷特",semi:true,gs:false,prior:true,pattern:"heldFire"},
            {name:"barrett-heldR-tapJ",weaponName:"战术巴雷特",semi:true,gs:false,prior:true,pattern:"heldReload"},
            {name:"barrett-priorShot-tapR-heldFire",weaponName:"战术巴雷特",semi:true,gs:false,hold:false,prior:true}
        ];
        if(_root.__cadenceMagazineOnly)cases=[];
        for(var caseIndex:Number=0;caseIndex<magazineCases.length;caseIndex++)cases.push(magazineCases[caseIndex]);
        if(!_root.__cadenceMagazineOnly){
            cases.push({name:"longgun-upper-body-reload-continuity",continuity:true,mode:"长枪",gs:false});
            cases.push({name:"pistol-upper-body-reload-continuity",continuity:true,mode:"手枪",gs:false});
            cases.push({name:"pistol2-upper-body-reload-continuity",continuity:true,mode:"手枪2",gs:false});
            cases.push({name:"cancel-live-idle-fire-reload",continuity:true,mode:"长枪",gs:false,cancelLive:true});
            cases.push({name:"native-same-path-late-completion",nativeIdentity:true,mode:"长枪",gs:false});
        }
        weapons={};
        saved={world:_root.gameworld,control:_root.控制目标,pause:_root.暂停,clock:_root.帧计时器,
            save:_root.存档系统,ui:_root.玩家信息界面,sound:_root.soundEffectManager,bullet:_root.子弹区域shoot传递,
            initHero:_root.初始化主角模板,functions:_root.主角函数,playSound:_root.播放音效,
            contain:ItemUtil.singleContain,total:ItemUtil.getTotal,submit:ItemUtil.singleSubmit};
        _root.主角函数={};
        oldRateClear=ShootCore._clearRateLimit;ShootCore._clearRateLimit=observeRateClear;
        oldWheelTick=CooldownWheel.I().tick;CooldownWheel.I().tick=function():Void {
            ShootReloadTimelineTest.frame++;_root.帧计时器.当前帧数=ShootReloadTimelineTest.frame;
            ShootReloadTimelineTest.oldWheelTick.call(CooldownWheel.I());
        };
        _root.暂停=false;_root.帧计时器={当前帧数:0};_root.存档系统={};_root.玩家信息界面={玩家必要信息界面:{}};
        _root.soundEffectManager={playSound:function():Void {}};_root.播放音效=function():Void {};
        _root.子弹区域shoot传递=capture;
        ItemUtil.singleContain=function():Object {return {};};ItemUtil.getTotal=function():Number {return 10;};ItemUtil.singleSubmit=function():Boolean{return true;};
        _root.初始化主角模板=function():Void {ShootReloadTimelineTest.initUnit(this);};
        _root.主角函数.初始化长枪射击函数=function():Void {ShootInitCore.initLongGun(this,this._parent);};
        _root.主角函数.初始化手枪射击函数=function():Void {ShootInitCore.initPistol(this,this._parent);};
        _root.主角函数.初始化手枪2射击函数=function():Void {ShootInitCore.initPistol2(this,this._parent);};
        _root.主角函数.初始化换弹负担=ReloadManager.initReloadBurden;
        _root.主角函数.换弹门禁=ReloadManager.handleReloadGate;
        _root.主角函数.换弹帧率控制=ReloadManager.controlReloadFrameRate;
        library=_root.createEmptyMovieClip("__cadenceLibrary",_root.getNextHighestDepth());library._visible=false;_root.gameworld=library;
        driver=_root.createEmptyMovieClip("__cadenceTimelineDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {ShootReloadTimelineTest.step();};
        check(_root.__cadenceRsl!=null,"production things0 RSL anchor is instantiated");
        loadWeapon("53式步骑枪","data/items/武器_长枪_狙击步枪.xml");
    }
    private static function loadWeapon(name:String,path:String):Void {
        loadingWeapon=name;sourceXml=new XML();sourceXml.ignoreWhite=true;sourceXml.onLoad=function(ok:Boolean):Void {
            var test:Object=org.flashNight.arki.unit.Action.Shoot.ShootReloadTimelineTest;
            test.check(ok,"real item XML loads "+test.loadingWeapon);
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            for(var i:Number=0;i<parsed.item.length;i++)if(parsed.item[i].name==test.loadingWeapon)test.weapons[test.loadingWeapon]=parsed.item[i].data;
            var data:Object=test.weapons[test.loadingWeapon];
            test.check(data.interval==1000&&data.singleshoot==true,"actual 1000ms semi-auto data "+test.loadingWeapon);
            if(test.loadingWeapon=="53式步骑枪")test.loadWeapon("战术巴雷特","data/items/武器_长枪_反器材武器.xml");
            else {
                test.check(data.capacity==8&&data.reloadType!="tube","Barrett uses an eight-round magazine, not a tube");
                test.nextCase();
            }
        };sourceXml.load(path);
    }
    private static function nextCase():Void {
        restoreProbePause();
        if(unit){ShootCore.cleanup(unit);unit.removeMovieClip();}EnhancedCooldownWheel.I().reset();ShootCore._lastShotTimes={};
        index++;if(index>=cases.length){finish();return;}current=cases[index];weapon=weapons[current.weaponName||"53式步骑枪"];shots=[];age=0;stage="attach";
        reloadProbe={progressed:false};
        unit=library.attachMovie("主角-男","cadenceHero",library.getNextHighestDepth());
        check(unit!=null,"attach production hero "+current.name);if(unit==null){finish();return;}initUnit(unit);_root.控制目标=unit._name;
    }
    private static function step():Void {

        if(frame%30==0)trace("[TIMELINE_STATE] frame="+frame+" stage="+stage+" case="+index+" unit="+unit+" unitFrame="+unit._currentframe+" man="+unit.man+" manFrame="+unit.man._currentframe+" start="+typeof unit.man.开始射击+" mode="+unit.攻击模式);
        if(stage=="done")return;
        if(frame>cases.length*200+300){check(false,"native timeline watchdog");finish();return;}
        if(stage=="loading")return;
        if(stage=="attach"){stage="ready";unit.gotoAndStop((current.mode||"长枪")+"站立");return;}
        if(current.nativeIdentity){stepNativeIdentity();return;}
        if(current.continuity){stepContinuity();return;}
        if(stage=="ready"){
            if(typeof unit.man.开始射击!="function")return;
            trace("[TIMELINE_READY] case="+current.name+" semi="+unit.man.是否单发+" interval="+unit.man.射击速度+" ammo="+unit.长枪.value.shot);
            check(unit.man._totalframes==78,"actual long-gun timeline has 78 frames");
            readyAt=frame;age=0;stage="run";return;
        }
        age++;
        if(current.pattern) {
            unit.动作A=age<120&&(age==1||current.pattern=="heldFire");unit.动作C=false;
            if(age>=3&&age<120) {
                unit.动作A=current.pattern=="heldFire"||(age%2)==0;
                unit.动作C=current.pattern=="heldReload"||(age%2)==1;
            }
        } else {
            if(age==1&&current.prior)unit.动作A=true;
            if(age==2){unit.动作A=false;if(!current.prior)unit.动作C=true;}
            if(current.prior&&age==16)unit.动作C=true;
            if(age==(current.prior?18:4)){unit.动作A=true;unit.动作C=current.hold;}
            if(current.tap && age>18 && age<120)unit.动作A=(age%2)==0;
        }
        if(age==120){unit.动作A=false;unit.动作C=false;}
        if(age<120){if(unit.动作C)unit.man.开始换弹();else if(unit.动作A)unit.man.开始射击();}
        if(age==155){
            trace("[TIMELINE_CASE] "+current.name+" shots="+shots.join(",")+" active="+EnhancedCooldownWheel.I().getActiveTaskCount());
            check(shots.length>0,"actual timeline fires "+current.name);
            var minimum:Number=current.gs?26:30;
            for(var i:Number=1;i<shots.length;i++)check(shots[i]-shots[i-1]>=minimum,"native cadence "+current.name+" "+shots[i-1]+"->"+shots[i]);
            if(current.pattern=="heldFire")check(shots.length==1,"repeated R cannot rearm a continuously held ordinary semi-auto press");
            if(current.pattern=="alternate"||current.pattern=="heldReload")check(shots.length>=3,"alternating magazine controls continue accepting cooled-down shots");
            check(unit.keepshooting==undefined&&unit._gunslingerChain_keepshooting==undefined,"stop removes chain "+current.name);
            nextCase();
        }
    }
    private static function restoreProbePause():Void {
        if(reloadProbe.paused===true){_root.暂停=reloadProbe.pause;reloadProbe.paused=false;}
    }
    private static function checkContinuity(direction:String):Void {
        var label:String=current.name+" "+direction;
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
        trace("[RELOAD_CONTINUITY_CAPTURE] case="+current.name+" frame="+reloadProbe.oldFrame+" generation="+reloadProbe.oldGeneration);
        // A1 升级为正式 apply；状态与阶段先保存在 class，父级跳帧后立即返回。
        if(current.cancelLive){
            restoreProbePause();
            reloadProbe.cancelShot=unit[current.mode].value.shot;
            stage="probe-cancelled";ReloadManager.cancelReload(unit.man,true);return;
        }
        reloadProbe.switchAge=age;stage="probe-walk";
        StateTransition.apply(unit,current.mode+"行走");
    }
    private static function stepContinuity():Void {
        // age 只由 root driver 的真实 enterFrame 推进，不依赖会随暂停停走的游戏时钟。
        age++;
        if(age>220){check(false,current.name+" continuity watchdog at "+stage);nextCase();return;}
        try {advanceContinuity();}
        catch(error:Error){check(false,current.name+" continuity exception: "+error);nextCase();}
    }
    private static function advanceContinuity():Void {
        if(stage=="ready"){
            if(typeof unit.man.开始换弹!="function")return;
            check(typeof unit.man=="movieclip",current.name+" uses a real production upper-body MovieClip");
            check(unit[current.mode].value.shot===(current.cancelLive?1:3),current.name+" begins with expected magazine");
            stage="probe-wait";unit.man.开始换弹();return;
        }
        if(stage=="probe-wait"){
            var midpoint:Number=Math.floor((unit.man.reloadStartFrame+unit.man.reloadEndFrame)/2);
            if(unit.man.reloadFrameControlActive===true&&unit.man.换弹标签===true
                &&unit.man._currentframe>midpoint-1&&unit.man._currentframe<unit.man.reloadEndFrame-2)
                captureContinuity();
            return;
        }
        if(stage=="probe-cancelled"){
            check(!unit.man.换弹标签&&unit.man.reloadFrameControlActive!==true,"live cancel releases reload frame control");
            check(unit[current.mode].value.shot===reloadProbe.cancelShot,"live cancel does not load or refund rounds");
            unit.动作A=true;unit.man.开始射击();unit.动作A=false;
            check(shots.length===1,"native idle frame restores permission to shoot after cancel(true)");
            ShootCore.stopForReload(unit);
            stage="probe-restarted";unit.man.开始换弹();return;
        }
        if(stage=="probe-restarted"){
            if(unit.man.reloadFrameControlActive!==true)return;
            check(unit.man.__reloadIdentity!==reloadProbe.token,"next reload has a new plain-object token");
            var before:Object=ReloadManager.snapshotReload(unit.man);
            reloadProbe.completion();
            check(unit.man.__reloadIdentity===before.identity&&ReloadManager.getReloadGeneration(unit.man)===before.generation
                &&unit.man._currentframe===before.frame&&unit.man.reloadFrameControlActive===before.controlActive,
                "old completion cannot clear or idle the next reload on the same body");
            reloadProbe.marker={};unit.man.__reloadProbeIdentity=reloadProbe.marker;
            reloadProbe.oldFrame=unit.man._currentframe;reloadProbe.oldGeneration=before.generation;
            stage="probe-resume";return;
        }
        if(stage=="probe-walk"){
            check(unit._currentframe!==reloadProbe.standFrame,current.name+" parent reaches the walking keyframe");
            checkContinuity("stand->walk");
            reloadProbe.switchAge=age;stage="probe-stand";
            StateTransition.apply(unit,current.mode+"站立");return;
        }
        if(stage=="probe-stand"){
            check(unit._currentframe===reloadProbe.standFrame,current.name+" parent returns to the standing keyframe");
            checkContinuity("walk->stand");
            restoreProbePause();stage="probe-resume";return;
        }
        if(stage=="probe-resume"){
            if(unit.man.__reloadProbeIdentity===reloadProbe.marker&&unit.man._currentframe>reloadProbe.oldFrame)
                reloadProbe.progressed=true;
            if(unit.man.换弹标签===false){
                check(reloadProbe.progressed===true,current.name+" reload advances after restoring pause");
                check(unit.man.__reloadProbeIdentity===reloadProbe.marker,current.name+" original upper body finishes reload");
                check(unit.man.reloadFrameControlActive!==true&&ReloadManager.getReloadGeneration(unit.man)>reloadProbe.oldGeneration,
                    current.name+" reload finishes and releases frame control");
                check(unit[current.mode].value.shot===0,current.name+" magazine is filled by the native reload timeline");
                check(shots.length===(current.cancelLive?1:0),current.name+" only the explicit cancellation shot consumes a round");
                trace("[RELOAD_CONTINUITY_COMPLETE] case="+current.name+" progressed="+reloadProbe.progressed+" ammo="+unit[current.mode].value.shot);
                nextCase();
            }
        }
    }
    // 真实 AVM1 同路径重建；旧剪辑引用可重指向新 man，generation 故意相同。
    private static function stepNativeIdentity():Void {
        age++;
        if(age>12){check(false,"native identity watchdog");if(reloadProbe.owner)reloadProbe.owner.removeMovieClip();nextCase();return;}
        if(stage=="ready"){
            var owner:MovieClip=library.createEmptyMovieClip("lateReloadOwner",library.getNextHighestDepth());
            reloadProbe.owner=owner;owner.攻击模式="长枪";owner.状态="长枪站立";
            var oldMan:MovieClip=owner.createEmptyMovieClip("man",1);
            oldMan.换弹标签=true;oldMan.reloadFrameControlActive=true;
            ReloadManager.bumpReloadGeneration(oldMan);
            reloadProbe.oldRef=oldMan;reloadProbe.oldPath=String(oldMan);reloadProbe.oldToken=oldMan.__reloadIdentity;
            reloadProbe.late=oldMan.结束换弹;reloadProbe.oldGeneration=ReloadManager.getReloadGeneration(oldMan);
            stage="identity-removed";oldMan.removeMovieClip();return;
        }
        if(stage=="identity-removed"){
            var fresh:MovieClip=reloadProbe.owner.createEmptyMovieClip("man",1);
            fresh.换弹标签=true;fresh.reloadFrameControlActive=true;fresh.reloadFrameProgress=0.5;fresh.idleCount=0;
            fresh.gotoAndStop=function(label):Void {this.idleCount++;};
            ReloadManager.bumpReloadGeneration(fresh);stage="identity-late";return;
        }
        if(stage=="identity-late"){
            fresh=reloadProbe.owner.man;
            check(typeof fresh=="movieclip"&&String(fresh)===reloadProbe.oldPath,"native replacement uses exactly the same MovieClip path");
            check(reloadProbe.oldRef===fresh,"AVM1 old MovieClip reference retargets to the same-path replacement");
            check(fresh.__reloadIdentity!==reloadProbe.oldToken,"replacement owns a different ordinary-object token");
            check(ReloadManager.getReloadGeneration(fresh)===reloadProbe.oldGeneration,"equal generations cannot substitute for token identity");
            var before:Object=ReloadManager.snapshotReload(fresh);reloadProbe.late();
            check(fresh.__reloadIdentity===before.identity&&ReloadManager.getReloadGeneration(fresh)===before.generation
                &&fresh.换弹标签===true&&fresh.reloadFrameControlActive===true&&fresh.reloadFrameProgress===0.5&&fresh.idleCount===0,
                "late completion cannot mutate any replacement reload field or jump idle");
            ReloadManager.cancelReload(fresh,true);check(fresh.idleCount===1,"current replacement still supports synchronous live cancellation");
            reloadProbe.owner.removeMovieClip();nextCase();
        }
    }
    private static function finish():Void {
        if(stage=="done")return;stage="done";delete driver.onEnterFrame;
        restoreProbePause();
        if(unit){ShootCore.cleanup(unit);unit.removeMovieClip();}EnhancedCooldownWheel.I().reset();
        trace("--- ShootReloadTimelineTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
        CooldownWheel.I().tick=oldWheelTick;ShootCore._clearRateLimit=oldRateClear;
        ItemUtil.singleContain=saved.contain;ItemUtil.getTotal=saved.total;ItemUtil.singleSubmit=saved.submit;
        _root.gameworld=saved.world;_root.控制目标=saved.control;_root.暂停=saved.pause;_root.帧计时器=saved.clock;
        _root.存档系统=saved.save;_root.玩家信息界面=saved.ui;_root.soundEffectManager=saved.sound;
        _root.子弹区域shoot传递=saved.bullet;_root.初始化主角模板=saved.initHero;_root.主角函数=saved.functions;_root.播放音效=saved.playSound;
        // 当前调用可能来自 driver.onEnterFrame；先保留无回调的空 driver，避免中断 Complete 链。
        library.removeMovieClip();
        _root.shootReloadTimelineComplete();
    }
}
