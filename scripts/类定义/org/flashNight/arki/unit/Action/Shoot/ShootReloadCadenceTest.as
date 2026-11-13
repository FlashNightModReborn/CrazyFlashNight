import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/** 隔离真实 AVM1/时间轮/生产射击与弹药提交；子弹出口不生成战场对象，不读写存档。 */
class org.flashNight.arki.unit.Action.Shoot.ShootReloadCadenceTest {
    private static var passed:Number, failed:Number, frame:Number, serial:Number;
    private static var shots:Array, caseName:String;
    private static var dispatchInterval:Number;
    private static var packs:Number;
    private static function check(ok:Boolean, label:String):Void {
        if(ok) passed++; else {failed++; trace("[TEST_FAIL] ShootReloadCadenceTest: " + label);}
    }
    private static function capture(props:Object):Void {shots.push(frame); dispatchInterval=props.发射间隔毫秒;}
    private static function ticks():Void {frame++; _root.帧计时器.当前帧数=frame; EnhancedCooldownWheel.I().tick();}
    private static function fixture(semi:Boolean, gs:Boolean):MovieClip {
        EnhancedCooldownWheel.I().reset(); ShootCore._lastShotTimes={}; frame=0; shots=[]; packs=10;
        var u:MovieClip=_root.createEmptyMovieClip("__cadence"+(++serial),_root.getNextHighestDepth());
        _root.控制目标=u._name;
        u.攻击模式="长枪";u.状态="长枪站立";u.hp=100;u.Z轴坐标=0;
        u.长枪={name:"cadence",value:{shot:2,level:1}};u.长枪弹匣容量=80;
        u.长枪属性={capacity:80,interval:400,singleshoot:semi,reloadType:"tube",clipname:"probe",diffusion:1,split:1};
        u.被动技能={枪械师:{启用:gs,等级:10}};u.动作A=false;u.动作B=false;u.动作C=false;
        u.dispatcher=new EventDispatcher();u.dispatcher.subscribe("processShot",FireEventComponent.processShot,u);
        u.长枪射击=WeaponFireCore.LONG_GUN_SHOOT;
        var m:MovieClip=u.createEmptyMovieClip("man",1);
        m.gotoAndPlay=function(label):Void {this.lastLabel=label;};
        m.gotoAndStop=function(label):Void {this.lastLabel=label;};
        m.射击许可标签=true;m.枪={枪:{装扮:{枪口位置:{}}}};
        ShootInitCore.initWeaponSystem(m,u,{weaponType:"长枪",isDualGun:false,weaponData:u.长枪属性});
        return u;
    }
    private static function finishCase(u:MovieClip):Void {
        trace("[CADENCE] case="+caseName+" shots="+shots.join(",")+" tasks="+EnhancedCooldownWheel.I().getActiveTaskCount()+" loop="+u.keepshooting+" chain="+u._gunslingerChain_keepshooting);
        ShootCore.cleanup(u);removeMovieClip(u);EnhancedCooldownWheel.I().reset();
    }
    private static function scenario(semi:Boolean, gs:Boolean, priorShot:Boolean, holdR:Boolean):Void {
        caseName=(semi?(gs?"gunslinger":"semi"):"auto")+"-prior="+priorShot+"-holdR="+holdR;
        var u:MovieClip=fixture(semi,gs);var m:MovieClip=u.man;
        if(priorShot){u.动作A=true;m.开始射击();ticks();u.动作A=false;}
        m.开始换弹();u.动作A=true;
        for(var i:Number=0;i<65;i++){
            u.动作C=holdR;
            if(holdR)m.开始换弹();else m.开始射击();
            ReloadManager.controlReloadFrameRate(m);
            ticks();
        }
        var minimum:Number=semi&&gs?11:12;
        for(var j:Number=1;j<shots.length;j++)check(shots[j]-shots[j-1]>=minimum,caseName+" interval "+shots[j-1]+"->"+shots[j]);
        u.动作A=false;u.动作C=false;for(var k:Number=0;k<20;k++)ticks();
        check(u.keepshooting==undefined&&u._gunslingerChain_keepshooting==undefined,caseName+" releases continuation");
        finishCase(u);
    }
    private static function repeatedTapCancellation():Void {
        caseName="semi-priorShot-cancel-rapidTap";
        var u:MovieClip=fixture(true,false),m:MovieClip=u.man;
        u.动作A=true;m.开始射击();u.动作A=false;for(var warm:Number=0;warm<6;warm++)ticks();m.开始换弹();
        for(var i:Number=0;i<130;i++){
            u.动作A=(i%2)==0;if(u.动作A)m.开始射击();ticks();
        }
        var shortAfterFirst:Number=0;
        for(var j:Number=2;j<shots.length;j++)if(shots[j]-shots[j-1]<12)shortAfterFirst++;
        trace("[SUSTAINED_REPRO] shots="+shots.join(",")+" shortAfterFirst="+shortAfterFirst);
        check(shortAfterFirst==0,"rapid taps never inherit an earlier shot's unlock callback");
        u.动作A=false;for(var k:Number=0;k<30;k++)ticks();finishCase(u);
    }
    private static function testRejectionAndLateOwners():Void {
        for(var mode:Number=0;mode<2;mode++) {
            caseName="no-stock-"+mode;var u:MovieClip=fixture(mode==1,false);var m:MovieClip=u.man;
            u.动作A=true;m.开始射击();var key:String=u._name+"_keepshooting";
            var rate:Object=ShootCore._lastShotTimes[key];var before:Number=u.长枪.value.shot;packs=0;
            m.开始换弹();
            check(ShootCore._lastShotTimes[key]===rate,"rejected reload preserves rate owner");
            check(u.主手射击中&&m.lastLabel=="射击","rejected reload preserves active shot and pose");
            check(u.长枪.value.shot==before&&!m.换弹标签,"rejected reload cannot mutate ammo or enter reload");
            u.动作A=false;for(var t:Number=0;t<15;t++)ticks();finishCase(u);
        }
        caseName="stale-owners";u=fixture(true,false);m=u.man;u.动作A=true;m.开始射击();
        key=u._name+"_keepshooting";var oldRate:Object=ShootCore._lastShotTimes[key];
        var oldSemi:Object=u._semiLock_keepshooting_owner;
        var oldUnit:MovieClip=u;
        removeMovieClip(u);serial--;u=fixture(true,false);m=u.man;u.动作A=true;m.开始射击();
        check(oldUnit===u,"stale callbacks exercise actual same-path MovieClip rebinding");
        var fresh:Object=ShootCore._lastShotTimes[key];
        ShootCore._clearRateLimit(key,oldRate);
        ShootCore._onSemiCooldownDone(oldUnit,"_semiLock_keepshooting","动作A",null,oldSemi);
        ShootCore._pollRelease(oldUnit,"_semiLock_keepshooting","动作A",null,oldSemi);
        check(ShootCore._lastShotTimes[key]===fresh,"late prior shot cannot clear replacement cooldown");
        check(u._semiLock_keepshooting===true,"late prior semi callback cannot replace the new press lock");
        ShootCore.cleanup(u);check(EnhancedCooldownWheel.I().getActiveTaskCount()==0,"teardown cancels rate, pending unlock and polling tasks");
        finishCase(u);
        caseName="pause";u=fixture(false,false);m=u.man;u.动作A=true;_root.暂停=true;m.开始射击();m.开始换弹();
        check(shots.length==0&&!m.换弹标签,"pause rejects both fire and reload before commit");
        check(!ShootCore._lastShotTimes[u._name+"_keepshooting"],"failed paused shot does not spend a fire interval");
        _root.暂停=false;m.开始射击();check(shots.length==1,"resume accepts a real shot");finishCase(u);
    }
    private static function lastRoundAndHandoff():Void {
        for (var index:Number = 0; index < 2; index++) {
            caseName = "last-round-" + index;
            var u:MovieClip = fixture(true, false);
            u.enableShoot = true; org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.ReloadEventComponent.initialize(u);
            var ms:Number = index == 0 ? 220 : 700;
            u.man.射击速度 = ms; u.长枪.value.shot = u.长枪弹匣容量 - 1; u.动作A = true;
            u.man.开始射击();
            check(shots.length == 1 && u.长枪.value.shot == 80 && !u.主手射击中, "last projectile commits and empty subscriber stops loop " + ms);
            check(u.射击最大后摇中 && u._semiLock_keepshooting && ShootCore._lastShotTimes[u._name + "_keepshooting"] != null,
                "last semi round retains recoil, rate and press gates " + ms);
            var bound:Number = Math.ceil(Math.min(ms, 300) * .03);
            for (var j:Number = 0; j < bound + 1; j++) ticks();
            check(!u.射击最大后摇中 && shots.length == 1 && u.keepshooting == undefined, "released final recoil without phantom repetition " + ms);
            u.man.开始射击();
            check(u.man.换弹标签, "empty held press can enter reload despite semi press lock");
            finishCase(u);
        }
        for (index = 0; index < 2; index++) {
            caseName = "gunslinger-skill-transfer-" + index;
            u = fixture(true, true); u.man.射击速度 = 1000; u.动作A = true; u.man.开始射击();
            for (j = 0; j < 27; j++) ticks();
            var oldMan:MovieClip = u.man;
            org.flashNight.arki.unit.UnitComponent.Routing.StateTransition.apply(u, "技能");
            check(!u.射击最大后摇中 && u._gunslingerChain_keepshooting_handoff === true,
                "accepted skill transition immediately retires recoil while holding cadence");
            if (index == 0) {
                for (j = 27; j < 37; j++) { oldMan.开始射击(); ticks(); }
                check(shots.length == 1, "900-1233ms cannot restart held shot early");
                ticks(); check(shots.length == 1, "old callback cannot shoot through new action");
                oldMan.开始射击(); check(shots.length == 2 && dispatchInterval == 1250, "held hand fires after 1250ms deadline and keeps its continuous projectile fill rate");
            } else {
                u.动作A = false; ticks(); u.动作A = true; oldMan.开始射击();
                check(shots.length == 2 && dispatchInterval == 850, "genuine release after 850ms stamps a new tap");
            }
            finishCase(u);
        }
    }

    private static function borrowedSkills():Void {
        var names:Array = ["铁枪之锋","调用射击发射其他弹药","突击者之眼","气锤光炮","突击者之怒"];
        var flags:Array = ["铁枪之锋许可","其他弹药开启","突击者之眼开启","气锤光炮开启","突击者之怒开启"];
        for (var i:Number = 0; i < names.length; i++) {
            for (var allow:Number = 0; allow < 2; allow++) {
                caseName = names[i] + (allow ? "-accepted" : "-denied");
                var u:MovieClip = fixture(false, false);
                u.长枪数据 = {skill:{split:3, bullet:"技能验收弹", clipname:"测试耗材", power:4}};
                u.chargeComplete = true; u.强制奔跑 = true; u.动作B = true; u.上行 = true;
                u.状态改变 = function(value:String):Void { this.状态 = value; };
                u.攻击 = function(request:Object):Void { this.man.开始射击(request); };
                var action:Object = _root.主动战技函数.长枪[names[i]];
                action.初始化(u);
                var sawInput:Array = [];
                u.dispatcher.subscribe("长枪射击", function():Void { sawInput.push(u.动作A); }, u);
                var prop:Object = u.man.子弹属性;
                prop.子弹威力 = 123; prop.子弹种类 = "原子弹"; prop.霰弹值 = 2; prop.sound = "原音效";
                var flagValue = u[flags[i]];
                var oldPacks:Number = packs;
                if (!allow) ShootCore.armRateLimit(u, "keepshooting", 1000);
                var permit:Boolean = action.释放许可判定(u);
                check(permit && packs == oldPacks, caseName + " permission alone never debits");
                var accepted:Boolean = action.释放(u);
                var expected:Number = !allow ? 2 : (i == 3 ? 80 : i == 1 || i == 2 ? 5 : 3);
                check(accepted === (allow == 1) && shots.length == allow && u.长枪.value.shot == expected,
                    caseName + " only actual dispatch consumes its exact magazine count");
                check(packs == oldPacks - (allow && i < 2 ? 1 : 0), caseName + " exact external inventory charge");
                check(!u.动作A && u.动作B && u.上行 && u.man.射击许可标签 && u[flags[i]] === flagValue
                    && prop.子弹种类 == "原子弹" && prop.子弹威力 == 123 && prop.霰弹值 == 2 && prop.sound == "原音效"
                    && (allow || u.强制奔跑), caseName + " input, permission and projectile template restored");
                check(u.man.子弹属性 === prop && (!allow || (sawInput.length == 1 && sawInput[0] === false)),
                    caseName + " pre-fire subscribers see real unpressed input");
                u.动作A = true;
                for (var wait:Number = 0; wait < 40; wait++) ticks();
                check(shots.length == allow && u.长枪.value.shot == expected && u.keepshooting == null
                    && !u.射击最大后摇中 && !u.主手射击中,
                    caseName + " new press without an attack request cannot inherit a borrowed loop");
                finishCase(u);
            }
        }
    }

    private static function chargedRifleEffects():Void {
        var functions:Object = _root.装备生命周期函数;
        var savedRead:Function = functions.读取持久值;
        var savedInput:Function = _root.按键输入检测;
        functions.读取持久值 = function(value:Object,key:String,fallback) { return fallback; };
        _root.按键输入检测 = function():Boolean { return false; };
        try {
            for (var scenario:Number=0; scenario<3; scenario++) {
                var allow:Number=scenario==2 ? 1 : 0;
                caseName = "G1111-" + ["no-stone","empty","accepted"][scenario];
                var u:MovieClip=fixture(false,false);
                u.长枪.name="G1111"; u.syncRefs={};
                u.长枪数据={skill:{}};
                u.状态改变=function(name:String):Void { this.状态=name; };
                u.攻击=function(request:Object):Void { this.man.开始射击(request); };
                var skill:Object=_root.主动战技函数.长枪.铁枪之锋;
                skill.初始化(u);
                var ref:Object={自机:u,装备类型:"长枪",是否为主角:true};
                functions.G1111初始化(ref,{});
                var locked:MovieClip=u.createEmptyMovieClip("locked",u.getNextHighestDepth());
                locked.hp=90; ref.autoTarget=locked;
                var effects:Array=[];
                ref.finishChargedRifle=function(actor:MovieClip,request:Object):Void {
                    effects.push(request.fired && actor===u && request.directHit.target===locked && request.directHit.props.伤害类型=="真伤");
                };
                check(skill.释放许可判定(u) && packs==10,"G1111 admission has no debit");
                if (scenario==1) { u.长枪.value.shot=u.长枪弹匣容量; u.man.开始换弹=function():Void {}; }
                if (scenario==0) packs=0; // 许可后耗材消失，正常进入长枪预发事件，但不允许真实提交。
                var fired:Boolean=skill.释放(u);
                check(fired==Boolean(allow) && shots.length==allow && effects.length==allow
                    && (allow ? effects[0]===true && packs==9 : packs==(scenario==0?0:10)),
                    caseName+" direct hit / camera callback runs once only after accepted emission");
                finishCase(u);
            }
        } finally { functions.读取持久值=savedRead; _root.按键输入检测=savedInput; }
    }

    private static function borrowedCadence():Void {
        for (var variant:Number = 0; variant < 3; variant++) {
            caseName = "borrowed-held-" + variant;
            var u:MovieClip = fixture(true, variant != 0);
            u.长枪数据 = {skill:{split:2,bullet:"技能验收弹"}};
            u.攻击 = function(request:Object):Void { this.man.开始射击(request); };
            var skill:Object = _root.主动战技函数.长枪.突击者之眼;
            skill.初始化(u);
            u.动作A = true;
            // Level-ten gunslinger uses 850ms tap / 1250ms hold with a 1000ms base interval.
            u.man.射击速度 = 1000;
            check(skill.释放(u) === true && shots.length == 1 && u.keepshooting == null,
                caseName + " one borrowed round without an ordinary loop");
            if (variant == 2) { u.动作A = false; ticks(); u.动作A = true; }
            var before:Number = variant == 2 ? 24 : 35;
            while (frame < before) ticks();
            u.man.开始射击();
            check(shots.length == 1, caseName + " ordinary press observes previous fire budget");
            while (frame < 41) ticks();
            check(shots.length == 1, caseName + " neither holding nor elapsed budget dispatches by itself");
            if (variant == 0) {
                u.man.开始射击();
                check(shots.length == 1, "ordinary semi remains locked until actual release");
                u.动作A = false; ticks(); ticks(); u.动作A = true;
            }
            u.man.开始射击();
            var expectedInterval:Number = variant == 1 ? 1250 : variant == 2 ? 850 : 1000;
            check(shots.length == 2 && dispatchInterval == expectedInterval,
                caseName + " next genuine request uses its own held/tap interval");
            finishCase(u);
        }
        caseName = "ammo-event-does-not-own-recoil";
        u = fixture(false, false);
        ShootCore.scheduleRecoil(u, "keepshooting2", 200, null);
        u.主手射击中 = true;
        org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.ReloadEventComponent.updateNpcBullet(u, "主手射击中", 0);
        check(!u.主手射击中 && u.射击最大后摇中, "empty primary cannot release another hand's active recoil");
        for (var j:Number = 0; j < 10; j++) ticks();
        u.主手射击中 = true;
        org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.ReloadEventComponent.updateBulletOrigin(u, "主手射击中", 1, "子弹数");
        check(u.主手射击中 && !u.射击最大后摇中, "ammo refresh cannot invent a recoil lane");
        finishCase(u);
    }

    private static function equippedGrenadeCases():Void {
        for (var stacked:Number = 0; stacked < 2; stacked++) {
            for (var allowed:Number = 0; allowed < 2; allowed++) {
                caseName = "equipped-grenade-" + stacked + "-" + allowed;
                var u:MovieClip = fixture(false, false);
                packs = 0;
                var store:Object = {held:{name:"测试耗材", value:stacked ? 2 : 1}, refreshes:0};
                store.getItem = function(slot:String):Object { return slot == "手雷" ? this.held : null; };
                store.remove = function(slot:String):Void { if (slot == "手雷") this.held = null; };
                _root.物品栏 = {装备栏:store};
                _root.刷新人物装扮 = function(name:String):Void { store.refreshes++; };
                _root.存档系统.dirtyMark = false;
                u.长枪数据 = {skill:{split:3, bullet:"验收弹", clipname:"测试耗材"}};
                u.攻击 = function(request:Object):Void { this.man.开始射击(request); };
                var skill:Object = _root.主动战技函数.长枪.调用射击发射其他弹药;
                skill.初始化(u);
                if (!allowed) ShootCore.armRateLimit(u, "keepshooting", 1000);
                check(skill.释放许可判定(u) && store.held.value == (stacked ? 2 : 1),
                    caseName + " admission preserves equipped item");
                var accepted:Boolean = skill.释放(u);
                check(accepted === (allowed == 1) && shots.length == allowed &&
                    (allowed && !stacked ? store.held == null : store.held.value == (stacked ? 2 : 1) - allowed),
                    caseName + " one actual shot spends exactly one equipped item");
                check(store.refreshes == (allowed && !stacked ? 1 : 0) && u.__borrowedLongGunShot == null
                    && u.动作A === false && _root.存档系统.dirtyMark === (allowed == 1),
                    caseName + " actor refresh and dirty state match the accepted equipped-slot mutation");
                finishCase(u);
            }
        }
    }

    public static function runAllTests():Void {
        passed=failed=serial=0;
        var saved:Object={world:_root.gameworld,control:_root.控制目标,pause:_root.暂停,clock:_root.帧计时器,save:_root.存档系统,
            ui:_root.玩家信息界面,sound:_root.soundEffectManager,bullet:_root.子弹区域shoot传递,
            inventory:_root.物品栏,refresh:_root.刷新人物装扮,contain:ItemUtil.singleContain,total:ItemUtil.getTotal,submit:ItemUtil.singleSubmit};
        _root.gameworld=_root;_root.暂停=false;_root.帧计时器={当前帧数:0};_root.存档系统={};
        _root.玩家信息界面={玩家必要信息界面:{}};_root.soundEffectManager={playSound:function():Void {}};
        _root.子弹区域shoot传递=capture;
        ItemUtil.singleContain=function(name:String,amount:Number):Object {return ShootReloadCadenceTest.packs>=amount?{}:null;};
        ItemUtil.getTotal=function(name:String):Number {return ShootReloadCadenceTest.packs;};
        ItemUtil.singleSubmit=function(name:String,amount:Number):Boolean {if(ShootReloadCadenceTest.packs<amount)return false;ShootReloadCadenceTest.packs-=amount;return true;};
        try {
            testRejectionAndLateOwners();repeatedTapCancellation();
            lastRoundAndHandoff(); borrowedSkills(); chargedRifleEffects(); borrowedCadence(); equippedGrenadeCases();
            for(var mode:Number=0;mode<3;mode++)for(var prior:Number=0;prior<2;prior++)for(var held:Number=0;held<2;held++)scenario(mode>0,mode==2,prior==1,held==1);
        }catch(error){check(false,"unexpected exception: "+error);}
        _root.gameworld=saved.world;_root.控制目标=saved.control;_root.暂停=saved.pause;_root.帧计时器=saved.clock;
        _root.物品栏=saved.inventory;_root.刷新人物装扮=saved.refresh;
        _root.存档系统=saved.save;_root.玩家信息界面=saved.ui;_root.soundEffectManager=saved.sound;_root.子弹区域shoot传递=saved.bullet;
        ItemUtil.singleContain=saved.contain;ItemUtil.getTotal=saved.total;ItemUtil.singleSubmit=saved.submit;
        trace("--- ShootReloadCadenceTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
    }
}
