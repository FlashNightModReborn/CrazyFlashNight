import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.hud.WeaponAmmoHudProjection;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;
import org.flashNight.arki.unit.Action.Input.UnitActionIntentService;
import org.flashNight.arki.unit.Action.Skill.SkillReloadCore;

/** 隔离内存夹具：库存成功/失败、真实 MC 换弹门禁及 BaseItem 存档投影。 */
class org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntimeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var packs:Number;
    private static var serial:Number;
    private static var owners:Array;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] WeaponAmmoRuntimeTest: " + label); }
    }
    private static function assertNumber(expected:Number, actual:Number, label:String):Void {
        check(expected == actual, label + " expected=" + expected + " actual=" + actual);
    }
    private static function unit(cap:Number, shot:Number):MovieClip {
        var u:MovieClip = _root.createEmptyMovieClip("__ammoRuntime" + (++serial), _root.getNextHighestDepth());
        owners.push(u);
        u.长枪 = {name:"测试弹药枪", value:{level:1, shot:shot}};
        u.长枪弹匣容量 = cap;
        u.长枪属性 = {capacity:cap, reloadType:"tube", clipname:"测试弹匣", overload:{chamber:1, ghost:1}};
        u.被动技能 = {冲击连携:{启用:true, 等级:10}};
        u.攻击模式 = "长枪";
        u.状态 = "长枪站立";
        u.hp = 100;
        u.createEmptyMovieClip("man", 1);
        u.man.使用弹匣名称 = "测试弹匣";
        u.man.gotoAndPlay = function(label):Void { this.lastLabel = label; };
        u.man.gotoAndStop = function(label):Void { this.lastLabel = label; };
        _root.控制目标 = u._name;
        packs = 10;
        return u;
    }
    private static function total(u:Object):Number { return u.长枪弹匣容量 - u.长枪.value.shot; }

    public static function runAllTests():Void {
        passed=0; failed=0; serial=0; owners=[];
        var oldSubmit:Function = ItemUtil.singleSubmit;
        var oldTotal:Function = ItemUtil.getTotal;
        var oldContain:Function = ItemUtil.singleContain;
        var oldWorld = _root.gameworld;
        var oldControl = _root.控制目标;
        var oldSave = _root.存档系统;
        var oldUi = _root.玩家信息界面;
        var oldSound = _root.soundEffectManager;
        var oldPause = _root.暂停;
        var oldBattle = _root.当前为战斗地图;
        _root.gameworld = _root;
        _root.暂停 = false;
        _root.当前为战斗地图 = true;
        _root.存档系统 = {dirtyMark:false};
        _root.玩家信息界面 = {玩家必要信息界面:{}};
        _root.soundEffectManager = {playSound:function(name):Void {}};
        ItemUtil.singleSubmit = function(name:String, amount:Number, context:Object):Boolean {
            if (WeaponAmmoRuntimeTest.packs < amount) return false;
            WeaponAmmoRuntimeTest.packs -= amount;
            return true;
        };
        ItemUtil.getTotal = function(name:String):Number { return WeaponAmmoRuntimeTest.packs; };
        ItemUtil.singleContain = function(name:String, amount:Number):Object {
            return WeaponAmmoRuntimeTest.packs >= amount ? {} : null;
        };
        try {
            testConservation();
            testFailureAndPartialBudget();
            testSourcesAndShrink();
            testLegacyAndSerialization();
            testGateAndCancellation();
            testTappedGhostReload();
            testEligibilityAndAmmoConversion();
            testRepeatedCycles();
            testHudProjection();
            testFreeSupplyCannotPrintCredit();
            testReloadCommitAndInitializationFences();
            testDualRoundSegmentKeepsHalfReloadPolicy();
            testRewardExpiresOutsideEquippedSlots();
            testHeldTriggersAndLastPacket();
            testLongGunReloadInputOwnership();
            testDeferredPendingLifecycle();
            testPlainWeaponInitialization();
            testPauseBeforeFrameControlAdmission();
            testCancellationOwnershipAndPaidAmmo();
            testPaidSkillGhostOnlyAndRepeat();
            testPaidSkillNormalThenGhost();
            testPaidSkillBudgetExhaustion();
            testPaidSkillEligibilityAndDefaults();
            testPaidSkillLinkedOnce();
        } catch (error) { check(false, "unexpected exception: " + error); }
        ItemUtil.singleSubmit=oldSubmit; ItemUtil.getTotal=oldTotal; ItemUtil.singleContain=oldContain;
        _root.gameworld=oldWorld; _root.控制目标=oldControl; _root.存档系统=oldSave;
        _root.玩家信息界面=oldUi; _root.soundEffectManager=oldSound; _root.暂停=oldPause;
        _root.当前为战斗地图=oldBattle;
        for (var i:Number=0; i<owners.length; i++) owners[i].removeMovieClip();
        trace("--- WeaponAmmoRuntimeTest: " + passed + "/" + (passed+failed) + " passed, " + failed + " failed ---");
    }

    private static function testConservation():Void {
        var u:MovieClip=unit(8,0);
        var v:Object=u.长枪.value;
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(8,total(u),"initial ordinary full");
        assertNumber(0,WeaponAmmoRuntime.extras(s),"initialization grants no overload");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        assertNumber(8,total(u),"retaining chamber moves an existing round");
        assertNumber(7,WeaponAmmoRuntime.normal(v,8),"retained round excluded from normal");
        assertNumber(1,s.chamber,"chamber marked once");
        assertNumber(1,WeaponAmmoRuntime.fillRounds(u,"长枪",1,false,"测试弹匣",true),"top up ordinary slot");
        assertNumber(9,total(u),"ordinary plus chamber");
        assertNumber(7,s.reserve,"one paid round leaves seven");
        assertNumber(9,packs,"one packet charged");
        u.长枪属性.overload.ghostLimit=2;
        assertNumber(2,WeaponAmmoRuntime.fillRounds(u,"长枪",2,true,"测试弹匣",true),"ghost top-up consumes existing credit");
        assertNumber(11,total(u),"ordinary chamber and ghost coexist");
        assertNumber(5,s.reserve,"ghost consumes two paid rounds");
        assertNumber(9,packs,"no second charge while credit remains");
        assertNumber(1.5,WeaponAmmoRuntime.ghostMultiplier(u,"长枪"),"25 percent overload adds 50 percent spread");
        WeaponAmmoRuntime.consume(u,"长枪");
        assertNumber(1,s.ghost,"ghost consumed first");
        assertNumber(1.25,WeaponAmmoRuntime.ghostMultiplier(u,"长枪"),"penalty decreases with actual ghost count");
        WeaponAmmoRuntime.consume(u,"长枪");
        assertNumber(1,WeaponAmmoRuntime.ghostMultiplier(u,"长枪"),"no penalty after ghosts spent");
        assertNumber(1,s.chamber,"ghost use preserves chamber source");
        WeaponAmmoRuntime.consume(u,"长枪");
        assertNumber(8,total(u),"three committed shots consume three rounds");
        assertNumber(0,s.chamber,"chamber source consumed separately");
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(8,total(u),"refresh never restores spent extras");
        check(_root.存档系统.dirtyMark,"paid budget changes mark save dirty");
    }

    private static function testFailureAndPartialBudget():Void {
        var u:MovieClip=unit(8,7);
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        var before:Number=total(u);
        packs=0;
        assertNumber(0,WeaponAmmoRuntime.fillRounds(u,"长枪",1,false,"测试弹匣",true),"failed inventory submission rejects top-up");
        assertNumber(before,total(u),"failure grants no round");
        assertNumber(0,s.reserve,"failure grants no credit");
        s.reserve=1;
        assertNumber(1,WeaponAmmoRuntime.fillRounds(u,"长枪",3,false,"测试弹匣",true),"remaining one credit can commit despite larger batch");
        assertNumber(before+1,total(u),"partial paid batch retained");
        assertNumber(0,s.reserve,"partial credit exhausted exactly");
        check(!WeaponAmmoRuntime.fillMagazine(u,"长枪","测试弹匣",true),"empty reserve cannot pay a full reload");
        packs=1;
        check(WeaponAmmoRuntime.fillMagazine(u,"长枪","测试弹匣",true),"whole reload shares paid credit accounting");
        assertNumber(9,total(u),"whole reload retains chamber");
        assertNumber(1,s.reserve,"whole reload consumes only missing tube rounds");
    }

    private static function testSourcesAndShrink():Void {
        var u:MovieClip=unit(8,0);
        u.长枪属性.overload={chamber:1,ghost:1,ghostLimit:2,reward:1};
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        WeaponAmmoRuntime.fillRounds(u,"长枪",3,true,"测试弹匣",true);
        assertNumber(8,WeaponAmmoRuntime.addReward(u,"长枪",99),"reward has its own cap based only on normal capacity");
        assertNumber(19,total(u),"all source quotas coexist without recursive capacity");
        assertNumber(1.5,WeaponAmmoRuntime.ghostMultiplier(u,"长枪"),"reward and chamber excluded from ghost ratio");
        var paid:Number=s.reserve;
        u.被动技能.冲击连携.启用=false;
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(0,s.ghost,"disabling skill removes ghost eligibility");
        assertNumber(paid+2,s.reserve,"paid ghost rounds return to balance");
        assertNumber(8,s.reward,"ghost change preserves reward");
        u.长枪弹匣容量=4;
        u.长枪属性.overload.chamber=0;
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(4,s.reward,"reward shrinks to new normal capacity");
        assertNumber(paid+3,s.reserve,"shrink refunds only funded rounds rather than free initial ammo");
        assertNumber(8,total(u),"new total excludes refunded paid overflow");
        WeaponAmmoRuntime.supplyValue(u.长枪.value,true);
        assertNumber(0,s.reward,"return to base clears only reward source");
        assertNumber(paid+3,s.reserve,"base supply preserves paid balance");
        assertNumber(4,total(u),"base supply restores normal full");
    }

    private static function testLegacyAndSerialization():Void {
        var u:MovieClip=unit(5,-4);
        u.长枪属性.overload={chamber:1,reward:1};
        u.长枪属性.reloadType="magazine";
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(4,s.reward,"legacy GM6 negative shot migrates to reward");
        assertNumber(9,total(u),"legacy migration keeps total");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        check(WeaponAmmoRuntime.fillMagazine(u,"长枪","测试弹匣",true),"GM6 tactical reload commits");
        assertNumber(10,total(u),"GM6 chamber coexists with old reward");
        assertNumber(1,WeaponAmmoRuntime.addReward(u,"长枪",3),"reward cap does not eat chamber quota");
        assertNumber(11,total(u),"GM6 maximum is two C plus chamber");
        var real:BaseItem=new BaseItem("测试弹药枪",u.长枪.value,123);
        var saved:Object=real.toObject();
        assertNumber(5,saved.value.ammoState.reward,"BaseItem save projection includes typed reward");
        saved.value.ammoState.reward=0;
        assertNumber(5,s.reward,"serialized snapshot does not alias live state");
        var restored:Object=ObjectUtil.clone(real.toObject());
        u.长枪=restored;
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(11,total(u),"recreated item preserves total and sources");
        u=unit(8,4);
        u.长枪.value.reloadCount=7;
        s=WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(7,s.reserve,"legacy tube credit migrates once");
        assertNumber(0,u.长枪.value.reloadCount,"legacy field no longer shares paid and skill counters");
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(7,s.reserve,"refresh does not duplicate migrated credit");
    }

    private static function testGateAndCancellation():Void {
        var u:MovieClip=unit(8,8);
        var m:MovieClip=u.man;
        m.换弹标签=true; m.perRoundReload=false; m.reloadCanSelectTube=true;
        m.reloadPerRoundBurden=50; m.reloadEndFrame=20; m.reloadLoopBackFrame=8;
        u.动作C=true;
        ReloadManager.handleReloadGate(m);
        assertNumber(1,total(u),"empty hold commits first usable round at gate");
        check(m.perRoundReload && m.reloadHeldMode,"hold selects responsive per-round mode");
        assertNumber(7,u.长枪.value.ammoState.reserve,"first gate leaves paid credit");
        var remaining:Number=packs;
        u.动作C=false;
        ReloadManager.handleReloadGate(m);
        assertNumber(1,total(u),"release before next gate keeps committed first round");
        check(!m.换弹标签 && m.lastLabel=="空闲","release ends only held reload");
        ReloadManager.handleReloadGate(m);
        assertNumber(remaining,packs,"late gate after cancellation cannot charge inventory");
        m.换弹标签=true; m.reloadFrameControlActive=true;
        check(ReloadManager.tryCancelForFire(m,u,"长枪"),"loaded round permits immediate fire cancellation");
        assertNumber(1,total(u),"cancellation itself does not consume or create ammo");
        check(!m.reloadFrameControlActive,"frame driver cleared before firing");
        m.换弹标签=true; m.lastLabel="被击";
        ReloadManager.cancelReload(m,false);
        check(m.lastLabel=="被击","hit cleanup does not replace hit pose with idle");
        u=unit(8,8); m=u.man;
        m.换弹标签=true; m.perRoundReload=false; m.reloadCanSelectTube=true;
        u.动作C=false;
        ReloadManager.handleReloadGate(m);
        assertNumber(0,total(u),"empty tap retains whole-magazine path");
        check(!ReloadManager.tryCancelForFire(m,u,"长枪"),"empty gun cannot fire-cancel into free shot");
        _root.暂停=true; u.动作C=true;
        ReloadManager.controlReloadFrameRate(m);
        assertNumber(0,total(u),"pause commits no ammo");
        _root.暂停=false;
    }

    private static function testTappedGhostReload():Void {
        var u:MovieClip=unit(8,0), m:MovieClip=u.man;
        u.动作C=false;
        u.长枪属性.overload.ghostLimit=2;
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        WeaponAmmoRuntime.setNormal(u.长枪.value,8,8);
        s.reserve=3;
        ReloadManager.startReload(m,u,_root);
        check(m.换弹标签==true,"released R still admits ghost-only top-up");
        ReloadManager.initReloadBurden(m,1,10,4,20,[]);
        check(m.perRoundReload && !m.reloadHeldMode,"tap top-up uses an automatic per-round sequence");
        ReloadManager.handleReloadGate(m);
        assertNumber(1,s.ghost,"tap commits first ghost with R already released");
        ReloadManager.handleReloadGate(m);
        assertNumber(2,s.ghost,"tap continues to the merged ghost quota without holding R");
        assertNumber(11,total(u),"tap preserves ordinary and chamber alongside two ghosts");
        assertNumber(1,s.reserve,"tap charges exactly the two committed rounds");
        check(!WeaponAmmoRuntime.canReload(u,"长枪",true),"full source quotas stop another reload");
        ReloadManager.finishReload(m);
        var before:Number=s.reserve;
        ReloadManager.startReload(m,u,_root);
        check(!m.换弹标签 && s.reserve==before,"fully loaded repeated tap cannot charge again");

        u=unit(8,8);m=u.man;u.动作C=false;
        u.长枪属性.overload.ghostLimit=2;
        ReloadManager.startReload(m,u,_root);
        ReloadManager.initReloadBurden(m,1,10,4,20,[]);
        ReloadManager.handleReloadGate(m);
        check(!m.perRoundReload && total(u)==0,"empty tap first retains the whole-magazine gate");
        ReloadManager.reloadMagazine(m,u,_root);
        s=u.长枪.value.ammoState;
        assertNumber(8,total(u),"whole-magazine commit grants no free ghost rounds");
        check(m.perRoundReload && !m.reloadHeldMode && m.lastLabel==4,"empty tap continues with separately animated ghost loading");
        ReloadManager.handleReloadGate(m);
        assertNumber(1,s.ghost,"post-magazine ghost is paid at its own animation gate");
        check(m.reloadInputMask == undefined,"a reload with no inherited keys keeps no input latch");
        check(ReloadManager.tryCancelForFire(m,u,"长枪"),"tap ghost continuation remains fire-cancellable");
        before=s.reserve;ReloadManager.handleReloadGate(m);
        assertNumber(before,s.reserve,"late continuation gate cannot spend after fire cancellation");

        u=unit(4,0);m=u.man;u.动作C=false;u.攻击模式="双枪";
        u.手枪={name:"双管测试",value:{level:1,shot:0}};
        u.手枪2={name:"双管测试",value:{level:1,shot:0}};
        u.手枪弹匣容量=u.手枪2弹匣容量=4;
        u.手枪属性=u.手枪2属性={capacity:4,reloadType:"tube",clipname:"测试弹匣",overload:{ghost:1}};
        var manager:WeaponStateManager=new WeaponStateManager(u,"手枪","手枪2");
        check(!manager.mainIsFull && !manager.subIsFull,"dual fullness includes ghost quota after R release");
        m.weaponStateManager=manager;m.主手使用弹匣名称=m.副手使用弹匣名称="测试弹匣";
        var start:Function=ReloadManager.createDualGunReloadStartFunction(m,u,_root,manager);
        start();check(m.换弹标签==true,"dual tap admits a ghost-only reload");
        m.dualReloadStartHand="主手";
        ReloadManager.initDualGunReloadBurden(m,1,10,4,20,[]);
        ReloadManager.handleDualGunReloadGate(m);
        assertNumber(1,u.手枪.value.ammoState.ghost,"dual main hand receives tapped ghost");
        assertNumber(0,u.手枪2.value.ammoState.ghost,"dual gate cannot credit the wrong hand");
        ReloadManager.initDualGunReloadBurden(m,21,30,24,40,[]);
        ReloadManager.handleDualGunReloadGate(m);
        assertNumber(1,u.手枪2.value.ammoState.ghost,"dual second segment completes without holding R");
        manager.updateState();check(!manager.needsAnyReload(),"both ghost quotas complete the dual sequence");

        u=unit(4,0);m=u.man;u.动作C=false;
        u.被动技能.冲击连携.启用=false;
        s=WeaponAmmoRuntime.ensure(u,"长枪");s.chamber=1;u.长枪.value.shot=-1;
        ReloadManager.startReload(m,u,_root);
        check(!m.换弹标签 && s.ghost==0,"tap cannot bypass the passive skill requirement");
    }

    private static function testEligibilityAndAmmoConversion():Void {
        var u:MovieClip=unit(2,0);
        u.长枪属性.overload={ghostLimit:2};
        assertNumber(0,WeaponAmmoRuntime.ghostLimit(u,"长枪"),"inner kit alone grants no ghost eligibility");
        u.长枪属性.overload={ghost:1,ghostLimit:2};
        assertNumber(2,WeaponAmmoRuntime.ghostLimit(u,"长枪"),"eligible gun takes merged limit");
        u.被动技能.冲击连携.启用=false;
        assertNumber(0,WeaponAmmoRuntime.ghostLimit(u,"长枪"),"skill required independently of hardware");
        u.被动技能.冲击连携.启用=true;
        WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.fillRounds(u,"长枪",2,true,"测试弹匣",true);
        assertNumber(3,WeaponAmmoRuntime.ghostMultiplier(u,"长枪"),"100 percent ghost ratio caps at three times spread");
        u.长枪属性.clipname="另一弹匣";
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(0,s.ghost,"ammo conversion unloads paid extras");
        assertNumber(2,s.reserves["测试弹匣"],"old ammunition balance retains its original ammo identity");
        u.长枪属性.clipname="测试弹匣";
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(2,s.reserve,"switching back restores old balance without copying it");
        assertNumber(0,total(u),"ammo conversion leaves no free old-type ordinary rounds");
        WeaponAmmoRuntime.fillRounds(u,"长枪",2,false,"测试弹匣",true);
        assertNumber(2,s.paidNormal,"paid ordinary rounds tracked before conversion");
        u.长枪属性.clipname="另一弹匣";
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(0,total(u),"paid ordinary rounds cannot carry into another ammo type");
        assertNumber(2,s.reserves["测试弹匣"],"paid ordinary rounds refunded only to old type");
        u.长枪弹匣容量=1;
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(0,s.reserve,"capacity shrink cannot reprice old credits as new ammo");
        u.长枪属性.clipname="测试弹匣";
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(2,s.reserve,"original paid budget survives conversion and capacity change");
    }

    private static function testRepeatedCycles():Void {
        var u:MovieClip=unit(8,8);
        u.长枪属性.overload={ghost:1,ghostLimit:2};
        WeaponAmmoRuntime.ensure(u,"长枪");
        packs=100;
        var fired:Number=0;
        for (var i:Number=0; i<40; i++) {
            WeaponAmmoRuntime.fillRounds(u,"长枪",1,true,"测试弹匣",true);
            if (i%3==0 && total(u)>0) { WeaponAmmoRuntime.consume(u,"长枪"); fired++; }
            var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
            assertNumber((100-packs)*8,total(u)+s.reserve+fired,"resource conservation through repeated partial cycles "+i);
            check(s.ghost<=2 && total(u)<=10,"per-source hard cap through cycle "+i);
        }
    }

    private static function testHudProjection():Void {
        var u:MovieClip=unit(8,0);
        u.长枪属性.overload.ghostLimit=2;
        WeaponAmmoRuntime.beginReload(u,"长枪");
        WeaponAmmoRuntime.fillRounds(u,"长枪",3,true,"测试弹匣",true);
        var detail:Object=WeaponAmmoHudProjection.read(u,"长枪",null);
        assertNumber(11,detail.loaded,"HUD receives actual committed total");
        assertNumber(3,detail.overflow,"HUD receives actual excess rather than provider limit");
        assertNumber(1,detail.chamber,"HUD keeps chamber source");
        assertNumber(2,detail.ghost,"HUD keeps ghost source");
        assertNumber(5,detail.reserve,"HUD shows paid packet remainder");
        assertNumber(1.5,detail.spread,"HUD exposes applied ghost risk");
        check(WeaponAmmoHudProjection.read(u,"长枪",detail)===detail,"unchanged HUD snapshot is reused");
        WeaponAmmoRuntime.consume(u,"长枪");
        var after:Object=WeaponAmmoHudProjection.read(u,"长枪",detail);
        assertNumber(11,detail.loaded,"already emitted HUD snapshot remains immutable");
        assertNumber(10,after.loaded,"next snapshot observes real shot");
        assertNumber(1,after.ghost,"next snapshot observes consumed source");

    }

    private static function testFreeSupplyCannotPrintCredit():Void {
        var u:MovieClip=unit(8,0);
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        for(var i:Number=0;i<20;i++) {
            u.长枪弹匣容量=16;
            WeaponAmmoRuntime.ensure(u,"长枪");
            WeaponAmmoRuntime.supplyValue(u.长枪.value,false);
            WeaponAmmoRuntime.beginReload(u,"长枪");
            u.长枪弹匣容量=8;
            u.长枪属性.overload.chamber=0;
            WeaponAmmoRuntime.ensure(u,"长枪");
            assertNumber(0,s.reserve,"free refill and capacity cycling cannot mint credit "+i);
            u.长枪属性.overload.chamber=1;
        }
        u=unit(8,8);s=WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.fillMagazine(u,"长枪","测试弹匣",true);
        assertNumber(8,s.paidNormal,"paid reload records funded normal rounds");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        assertNumber(1,s.paidChamber,"retained funded round moves its payment classification");
        u.长枪属性.overload.chamber=0;
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(1,s.reserve,"removing funded chamber quota returns its actual cost");
        assertNumber(7,s.paidNormal,"paid normal balance is not duplicated");
        WeaponAmmoRuntime.consume(u,"长枪");
        assertNumber(6,s.paidNormal,"normal shot consumes funded round once");
    }

    private static function testReloadCommitAndInitializationFences():Void {
        var u:MovieClip=unit(8,8);
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        check(ReloadManager.commitMagazine(u,"长枪","测试弹匣"),"first magazine commit succeeds");
        var paid:Number=packs;
        check(ReloadManager.commitMagazine(u,"长枪","测试弹匣"),"duplicate satisfied commit is a no-op");
        assertNumber(paid,packs,"duplicate commit cannot charge another packet");
        u.长枪属性.overload.ghostLimit=2;
        WeaponAmmoRuntime.fillRounds(u,"长枪",2,true,"测试弹匣",true);
        var oldSkills:Object=u.被动技能;
        delete u.被动技能;
        WeaponAmmoRuntime.ensure(u,"长枪",true);
        assertNumber(2,s.ghost,"early equipment projection preserves ghost while skill container is not ready");
        u.被动技能=oldSkills;
        WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(2,s.ghost,"ready active skill preserves restored ghost");
        u=unit(8,3);
        u.长枪属性={capacity:8,clipname:"测试弹匣",overload:{ghostLimit:2}};
        check(WeaponAmmoRuntime.ensure(u,"长枪")==null,"inner-only metadata does not capture unrelated weapon state");
    }

    private static function testDualRoundSegmentKeepsHalfReloadPolicy():Void {
        var u:MovieClip=unit(2,1);
        u.攻击模式="双枪";
        u.手枪={value:{level:1,shot:1}};u.手枪2={value:{level:1,shot:1}};
        u.手枪弹匣容量=u.手枪2弹匣容量=2;
        u.手枪属性=u.手枪2属性={capacity:2,reloadType:"tube",clipname:"测试弹匣"};
        var m:MovieClip=u.man;
        m.换弹标签=true;m.perRoundReload=true;m.reloadEndFrame=20;m.reloadLoopBackFrame=8;
        m.dualReloadWeaponType="手枪";m.dualReloadHandPrefix="主手";
        m.dualReloadMagNameProp="主手使用弹匣名称";
        m.主手使用弹匣名称=m.副手使用弹匣名称="测试弹匣";
        m.weaponStateManager={updateState:function():Void {},
            canFinishMainHandReload:function(a,b,c):Boolean {return true;}};
        ReloadManager.handleDualGunReloadGate(m);
        assertNumber(0,u.手枪.value.shot,"dual current hand filled");
        assertNumber(1,u.手枪2.value.shot,"half reload leaves other loaded hand untouched");
        check(m.lastLabel=="换弹结束","per-round finish retains impact-chain half reload exit");
    }

    private static function testRewardExpiresOutsideEquippedSlots():Void {
        var u:MovieClip=unit(5,0);
        u.长枪属性.overload={chamber:1,ghost:1,reward:1};
        var s:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        WeaponAmmoRuntime.fillRounds(u,"长枪",2,true,"测试弹匣",true);
        WeaponAmmoRuntime.addReward(u,"长枪",5);
        var bag:Object=ObjectUtil.clone(u.长枪);
        var balance:Number=s.reserve;
        WeaponAmmoRuntime.endSortie();
        u.长枪=bag;
        s=WeaponAmmoRuntime.ensure(u,"长枪");
        assertNumber(0,s.reward,"old reward scope expires even when gun was stored in bag at boundary");
        assertNumber(1,s.ghost,"reward expiry preserves funded ghost");
        assertNumber(1,s.chamber,"reward expiry preserves retained chamber");
        assertNumber(balance,s.reserve,"reward expiry preserves packet balance");
        assertNumber(7,total(u),"expired rewards are removed rather than relabeled as ordinary ammo");
    }

    private static function testHeldTriggersAndLastPacket():Void {
        var u:MovieClip=unit(8,8);
        var m:MovieClip=u.man;
        u.动作A=true;u.动作C=true;
        m.换弹标签=true;m.perRoundReload=false;m.reloadCanSelectTube=true;
        m.reloadPerRoundBurden=50;m.reloadEndFrame=20;m.reloadLoopBackFrame=8;
        check(!ReloadManager.handleReloadInput(m,u),"held empty trigger must not freeze reload progression");
        ReloadManager.handleReloadGate(m);
        assertNumber(1,total(u),"first round still commits while empty trigger is held");
        u.动作A=false;u.动作C=false;
        ReloadManager.cancelReload(m,true);
        WeaponAmmoRuntime.consume(u,"长枪");
        packs=0;
        check(WeaponAmmoRuntime.fillMagazine(u,"长枪","测试弹匣",true),"last opened packet can partially fill empty tube without another magazine");
        assertNumber(7,total(u),"all remaining paid rounds become usable");
        assertNumber(0,u.长枪.value.ammoState.reserve,"last packet is actually exhausted");
        u=unit(2,0);u.攻击模式="双枪";u.动作A=true;u.动作B=true;
        u.手枪={value:{shot:2}};u.手枪2={value:{shot:0}};
        u.手枪弹匣容量=u.手枪2弹匣容量=2;
        m=u.man;m.换弹标签=true;m.mainAttempts=0;m.subAttempts=0;
        m.主手开始射击=function():Void {this.mainAttempts++;};
        m.副手开始射击=function():Void {this.subAttempts++;};
        check(ReloadManager.handleReloadInput(m,u),"loaded offhand handles cancellation when both triggers are held");
        assertNumber(0,m.mainAttempts,"empty main hand does not start another reload before offhand shot");
        assertNumber(1,m.subAttempts,"loaded offhand uses original firing route once");
        u=unit(8,8);u.动作B=true;
        u.长枪副武器配置={};u.长枪副武器状态={capacity:2,loaded:2};
        m=u.man;m.换弹标签=true;m.subAttempts=0;
        m.开始副武器射击=function():Void {this.subAttempts++;};
        check(ReloadManager.handleReloadInput(m,u),"loaded long-gun subweapon can interrupt empty primary reload");
        assertNumber(1,m.subAttempts,"K routes to subweapon rather than empty primary");
        check(!m.换弹标签,"subweapon cancellation clears primary frame driver");
    }

    /** #261：经过真实 begin 的旧电平，与手工置标签的新输入负例分别验证。 */
    private static function testLongGunReloadInputOwnership():Void {
        var u:MovieClip = unit(8, 8);
        var m:MovieClip = u.man;
        u.长枪属性.reloadType = "magazine";
        u.动作A = u.动作B = true;
        u.长枪副武器配置 = {capacity:2, consumeMode:"onLoadGroup", clipCostPerLoad:1, reserveName:"测试弹匣"};
        u.长枪副武器状态 = {capacity:2, loaded:2, nextFireTime:0};
        u.长枪副武器 = {value:{shot:0}};
        ReloadManager.startReload(m, u, _root);
        check(m.换弹标签, "primary empty enters reload with both triggers held");
        assertNumber(3, m.reloadInputMask, "reload captures both inherited inputs without an object");
        for (var i:Number = 0; i < 30; i++) ReloadManager.handleReloadInput(m, u);
        check(m.换弹标签, "old K cannot cancel primary reload for thirty samples");
        u.动作B = false; ReloadManager.handleReloadInput(m, u); u.动作B = true;
        check(ReloadManager.tryCancelForFire(m, u, "长枪副武器"), "new K still cancels with loaded subweapon");
        check(!m.换弹标签 && m.reloadInputMask == undefined, "cancel releases only this reload's input ownership");

        u.长枪.value.shot = 1;
        u.长枪副武器.value.shot = 2;
        u.长枪副武器状态.loaded = 0;
        m.开始副武器换弹 = function():Boolean { return LongGunSubWeaponCore.startManualReloadAnimation(this._parent); };
        check(!LongGunSubWeaponCore.requestShoot(u), "empty subweapon request does not report a fired shot");
        check(m.换弹标签 && LongGunSubWeaponCore.isManualReloadRequest(m), "empty K selects its own paid reload path");
        ReloadManager.handleReloadInput(m, u);
        check(m.换弹标签, "inherited J cannot cancel subweapon-first reload");
        assertNumber(1, u.长枪.value.shot, "subweapon request leaves primary ammunition untouched");
        ReloadManager.cancelReload(m, false);
        ShootCore.cleanup(u);

        // 本轮明确统一输入语义：普通 tube 的旧 J 也不能在首发装入后冒充新按压。
        u = unit(8, 8); m = u.man; u.动作A = true; u.动作C = true;
        ReloadManager.startReload(m, u, _root);
        ReloadManager.initReloadBurden(m, 42, 50, 43, 74, [51,56,64]);
        ReloadManager.handleReloadGate(m);
        assertNumber(1, total(u), "held-R gate commits exactly one paid tube round");
        check(m.换弹标签 && !ReloadManager.tryCancelForFire(m, u, "长枪"),
            "inherited J does not stop tube reload after its first committed round");
        var paid:Number = u.长枪.value.ammoState.reserve;
        u.动作A = false; ReloadManager.handleReloadInput(m, u); u.动作A = true;
        check(ReloadManager.tryCancelForFire(m, u, "长枪"), "new J can still interrupt tube reload");
        assertNumber(paid, u.长枪.value.ammoState.reserve, "new-press interruption preserves paid reserve");
        assertNumber(9, packs, "one tube gate charges one packet, cancellation charges nothing");
        ShootCore.cleanup(u);

        // 持续 J 入场，首发装入后只松 R。射击键的所有权和逐发装填的松键独立。
        u = unit(8, 8); m = u.man; u.动作A = u.动作C = true;
        ReloadManager.startReload(m, u, _root);
        ReloadManager.initReloadBurden(m, 42, 50, 43, 74, [51,56,64]);
        ReloadManager.handleReloadGate(m);
        check(m.reloadHeldMode && total(u) == 1, "held J/R enters paid tube mode");
        u.动作C = false;
        check(ReloadManager.handleReloadInput(m, u) && !m.换弹标签 && m.lastLabel == "空闲",
            "releasing only R stops tube reload while the inherited J stays held");
        ReloadManager.handleReloadGate(m);
        check(total(u) == 1 && packs == 9, "late gate cannot add a second round or charge again");
        ShootCore.cleanup(u);
    }

    private static function rejectPlainShot(owner:Object, slot:String, props:Object):Boolean {
        owner.__plainShotAdmitted = true;
        return false;
    }

    private static function testPlainWeaponInitialization():Void {
        var slots:Array = ["长枪", "手枪", "手枪2"];
        var invalid:Array = [NaN, Infinity, -Infinity, null, "bad", -1];
        for (var i:Number = 0; i < slots.length; i++) {
            var slot:String = slots[i];
            var u:MovieClip = unit(8,0);
            var fresh:BaseItem = new BaseItem("测试普通枪", {level:1, mods:[]});
            var saved:Object = fresh.toObject();
            check(saved.value.shot === undefined, slot + " fresh saved gun has no shot field");
            u[slot] = new BaseItem(saved.name, saved.value, saved.lastUpdate);
            u[slot + "属性"] = {capacity:8, clipname:"测试弹匣"};
            u[slot + "弹匣容量"] = 8;
            check(WeaponAmmoRuntime.ensure(u,slot) == null, slot + " plain gun keeps legacy ammo contract");
            var value:Object = u[slot].value;
            assertNumber(0,value.shot,slot + " missing counter initializes to zero");
            assertNumber(8,8-value.shot,slot + " fresh plain gun has finite full ammo");
            check(value.ammoState === undefined, slot + " initialization invents no typed overload state");
            u.__plainShotAdmitted = false;
            WeaponFireCore.executeShot(u,slot,null,{},WeaponAmmoRuntimeTest.rejectPlainShot);
            check(u.__plainShotAdmitted,slot + " fresh gun passes real fire-core ammo admission");
            assertNumber(0,value.shot,slot + " rejecting shot guard consumes no ammo");
            value.shot = 3;
            WeaponAmmoRuntime.ensure(u,slot);
            WeaponAmmoRuntime.ensure(u,slot);
            assertNumber(3,value.shot,slot + " repeated initialization preserves partial magazine");
            saved = u[slot].toObject();
            u[slot] = new BaseItem(saved.name,saved.value,saved.lastUpdate);
            WeaponAmmoRuntime.ensure(u,slot);
            value = u[slot].value;
            assertNumber(3,value.shot,slot + " serialized partial magazine restores unchanged");
            value.shot = 8;
            u.__plainShotAdmitted = false;
            WeaponFireCore.executeShot(u,slot,null,{},WeaponAmmoRuntimeTest.rejectPlainShot);
            check(!u.__plainShotAdmitted,slot + " genuinely empty gun stays blocked");
            check(ReloadManager.commitMagazine(u,slot,"测试弹匣"),slot + " plain empty gun reloads through production commit");
            assertNumber(0,value.shot,slot + " plain reload resets real counter");
            assertNumber(9,packs,slot + " plain reload consumes exactly one packet");
            for (var j:Number = 0; j < invalid.length; j++) {
                value.shot = invalid[j];
                WeaponAmmoRuntime.ensure(u,slot);
                assertNumber(0,value.shot,slot + " invalid plain counter repaired case " + j);
            }
        }
    }

    private static function testPauseBeforeFrameControlAdmission():Void {
        var u:MovieClip=unit(8,8);
        var m:MovieClip=u.man;
        m.换弹标签=true;m.reloadFrameControlRequest=true;
        _root.暂停=true;
        ReloadManager.controlReloadFrameRate(m);
        ReloadManager.reloadMagazine(m,u,_root);
        assertNumber(0,total(u),"pause before frame-controller admission cannot commit whole magazine");
        assertNumber(10,packs,"paused animation callback cannot charge inventory");
        check(m.reloadFrameControlRequest,"pause keeps controller admission pending for resume");
        _root.暂停=false;
        ReloadManager.reloadMagazine(m,u,_root);
        assertNumber(8,total(u),"resumed valid magazine callback commits normally");
        assertNumber(9,packs,"resume submits packet exactly once");
    }
    private static function testCancellationOwnershipAndPaidAmmo():Void {
        var u:MovieClip=unit(8,0), m:MovieClip=u.man;
        u.长枪属性.overload.ghostLimit=2;
        var ammo:Object=WeaponAmmoRuntime.ensure(u,"长枪");
        WeaponAmmoRuntime.beginReload(u,"长枪");
        WeaponAmmoRuntime.fillRounds(u,"长枪",3,true,"测试弹匣",true);
        var shot:Number=u.长枪.value.shot, paid:Number=ammo.reserve, stock:Number=packs;
        var chamber:Number=ammo.chamber, ghost:Number=ammo.ghost;
        m.换弹标签=true;m.reloadFrameControlActive=true;m.reloadFrameControlRequest=true;
        m.允许射击=false;m.playCount=0;m.idleCount=0;
        m.play=function():Void {this.playCount++;};
        m.gotoAndStop=function(label):Void {this.lastLabel=label;this.idleCount++;};
        ReloadManager.bumpReloadGeneration(m);
        var late:Function=m.结束换弹;
        u._semiLock_keepshooting=true;
        ReloadManager.cancelReload(m,false);
        check(m.idleCount===0&&m.playCount===0&&m.允许射击===false,"false cancel neither plays nor idles nor enables shooting");
        assertNumber(shot,u.长枪.value.shot,"tube cancel preserves committed total");
        assertNumber(paid,ammo.reserve,"tube cancel preserves paid reserve without refund");
        assertNumber(chamber,ammo.chamber,"cancel preserves retained chamber");
        assertNumber(ghost,ammo.ghost,"cancel preserves paid ghost rounds");
        assertNumber(stock,packs,"cancel cannot refund packet");
        check(u._semiLock_keepshooting===true,"cancel leaves firing cadence lock authoritative");
        m.换弹标签=true;m.reloadFrameControlActive=true;
        ReloadManager.bumpReloadGeneration(m);
        var generation:Number=ReloadManager.getReloadGeneration(m), token:Object=m.__reloadIdentity;
        late();
        check(m.__reloadIdentity===token&&ReloadManager.getReloadGeneration(m)===generation&&m.换弹标签===true
            &&m.reloadFrameControlActive===true&&m.idleCount===0,"old end cannot clear a new transaction on the same body");
        late=m.结束换弹;ReloadManager.bumpReloadGeneration(m);generation=ReloadManager.getReloadGeneration(m);late();
        check(m.__reloadIdentity===token&&ReloadManager.getReloadGeneration(m)===generation&&m.换弹标签===true,
            "same identity with a stale generation cannot finish a later commit");
        var before:Object=ReloadManager.snapshotReload(m), after:Object=ReloadManager.snapshotReload(m);
        check(before.identity===after.identity&&before.generation===after.generation&&m.idleCount===0,
            "#214 snapshot is read-only and does not repair idle");
        u.状态="技能";ReloadManager.cancelReload(m,true);
        check(m.idleCount===0,"true cancel cannot overwrite a skill even if owner.man still matches");
        u.状态="长枪行走";m.换弹标签=true;ReloadManager.bumpReloadGeneration(m);ReloadManager.cancelReload(m,true);
        check(m.idleCount===1&&m.lastLabel=="空闲"&&m.playCount===0,"live walk cancel jumps exactly to idle instead of play");
        m._name="detachedReloadBody";u.createEmptyMovieClip("man",2);
        ReloadManager.cancelReload(m,true);check(m.idleCount===1,"detached old body cannot return idle");

        // 普通整匣已提交后退役，重复帧不得再付费或把消耗清零。
        u=unit(4,4);m=u.man;u.长枪属性={capacity:4,clipname:"测试弹匣"};
        ReloadManager.startReload(m,u,_root);ReloadManager.reloadMagazine(m,u,_root);
        assertNumber(0,u.长枪.value.shot,"ordinary magazine commits before cancellation");
        stock=packs;u.长枪.value.shot=1;ReloadManager.cancelReload(m,false);ReloadManager.reloadMagazine(m,u,_root);
        assertNumber(1,u.长枪.value.shot,"late ordinary commit cannot refill after cancellation");
        assertNumber(stock,packs,"ordinary cancel neither refunds nor charges twice");

        // 双枪只付过一手，取消/迟到手提交不能改变另一手或重新收费。
        u=unit(2,0);m=u.man;u.攻击模式="双枪";u.状态="双枪站立";
        u.手枪={value:{shot:2}};u.手枪2={value:{shot:3}};
        u.手枪弹匣容量=2;u.手枪2弹匣容量=3;
        u.手枪属性={capacity:2,clipname:"测试弹匣"};u.手枪2属性={capacity:3,clipname:"测试弹匣"};
        check(ReloadManager.commitMagazine(u,"手枪","测试弹匣"),"dual first hand commits exactly once");
        stock=packs;m.换弹标签=true;ReloadManager.bumpReloadGeneration(m);late=m.结束换弹;
        var manager:Object={updateState:function():Void {}};
        var lateHand:Function=ReloadManager.createHandReloadFunction(m,u,_root,{handPrefix:"副手",weaponType:"手枪2"},manager);
        ReloadManager.cancelReload(m,false);generation=ReloadManager.getReloadGeneration(m);late();lateHand();
        assertNumber(0,u.手枪.value.shot,"paid first hand remains loaded");
        assertNumber(3,u.手枪2.value.shot,"unpaid second hand receives no round");
        assertNumber(stock,packs,"half reload cancel neither refunds first hand nor pays second");
        assertNumber(generation,ReloadManager.getReloadGeneration(m),"late inactive hand callback cannot advance generation");
    }

    /** #215 翻滚 opt-in 的内存夹具：两把手枪默认满仓，不占用长枪测试预算。 */
    private static function skillReloadUnit(cap:Number, shot:Number):MovieClip {
        var u:MovieClip = unit(cap, shot);
        u.长枪属性.overload.ghostLimit = 2;
        u.手枪 = {value:{shot:0}};
        u.手枪2 = {value:{shot:0}};
        u.手枪弹匣容量 = u.手枪2弹匣容量 = cap;
        u.手枪属性 = {capacity:cap, clipname:"测试弹匣"};
        u.手枪2属性 = {capacity:cap, clipname:"测试弹匣"};
        return u;
    }

    private static function testPaidSkillGhostOnlyAndRepeat():Void {
        var u:MovieClip = skillReloadUnit(8, 0);
        SkillReloadCore.reloadAllWeapons(u, true);
        var s:Object = u.长枪.value.ammoState;
        assertNumber(8, WeaponAmmoRuntime.normal(u.长枪.value, 8), "skill ghost-only keeps full normal magazine");
        assertNumber(2, s.ghost, "skill opt-in fills two ghosts even when shot was zero");
        assertNumber(6, s.reserve, "two ghosts leave six paid packet rounds");
        assertNumber(9, packs, "ghost-only skill buys exactly one normal-capacity packet");
        assertNumber(0, s.chamber, "skill ghost top-up grants no retained chamber");
        assertNumber(0, s.reward, "skill ghost top-up grants no reward rounds");
        SkillReloadCore.reloadAllWeapons(u, true);
        SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, true);
        ReloadManager.fillPaidGhostAfterSkill(u, "长枪");
        assertNumber(2, s.ghost, "repeated skill top-ups cannot exceed ghost limit");
        assertNumber(6, s.reserve, "repeated full skill cannot charge paid balance twice");
        assertNumber(9, packs, "repeated full skill cannot submit another packet");

        u = skillReloadUnit(8, 0);
        u.长枪属性.overload.reward = 1;
        s = WeaponAmmoRuntime.ensure(u, "长枪");
        WeaponAmmoRuntime.beginReload(u, "长枪");
        check(WeaponAmmoRuntime.fillMagazine(u, "长枪", "测试弹匣", true), "prepare existing paid normal and retained chamber");
        WeaponAmmoRuntime.addReward(u, "长枪", 2);
        u.长枪.value.reloadCount = 5;
        var reserveBefore:Number = s.reserve;
        var stockBefore:Number = packs;
        SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, true);
        assertNumber(8, WeaponAmmoRuntime.normal(u.长枪.value, 8), "negative-shot skill keeps normal capacity");
        assertNumber(2, s.ghost, "negative shot from existing extras does not block skill ghosts");
        assertNumber(1, s.chamber, "skill preserves existing chamber without adding one");
        assertNumber(2, s.reward, "skill preserves existing reward source");
        assertNumber(reserveBefore - 2, s.reserve, "skill spends only two existing paid credits");
        assertNumber(stockBefore, packs, "existing credits avoid another inventory packet");
        assertNumber(5, u.长枪.value.reloadCount, "skill does not grant tactical recovery");
        assertNumber(0, s.paidChamber, "skill does not change retained chamber funding");
    }

    private static function testPaidSkillNormalThenGhost():Void {
        var u:MovieClip = skillReloadUnit(8, 3);
        SkillReloadCore.reloadAllWeapons(u, true);
        var s:Object = u.长枪.value.ammoState;
        assertNumber(8, WeaponAmmoRuntime.normal(u.长枪.value, 8), "skill fills missing ordinary rounds first");
        assertNumber(3, s.paidNormal, "only three missing normal rounds are charged");
        assertNumber(2, s.ghost, "skill then fills the ghost gap");
        assertNumber(3, s.reserve, "ordinary three plus ghost two spend five packet rounds");
        assertNumber(9, packs, "ordinary and ghost skill share one paid packet");
        assertNumber(0, s.chamber, "ordinary skill fill does not run beginReload");
        assertNumber(0, s.reward, "ordinary skill fill does not grant rewards");

        u = skillReloadUnit(4, 0);
        u.手枪属性 = {capacity:4, reloadType:"tube", clipname:"测试弹匣", overload:{ghost:1, ghostLimit:2}};
        u.手枪2属性 = {capacity:4, reloadType:"tube", clipname:"测试弹匣", overload:{ghost:1, ghostLimit:2}};
        SkillReloadCore.reloadAllWeapons(u, true);
        assertNumber(2, u.长枪.value.ammoState.ghost, "batch opt-in reaches long gun");
        assertNumber(2, u.手枪.value.ammoState.ghost, "batch opt-in reaches main pistol");
        assertNumber(2, u.手枪2.value.ammoState.ghost, "batch opt-in reaches second pistol");
        assertNumber(7, packs, "each eligible weapon pays for its own packet");
    }

    private static function testPaidSkillBudgetExhaustion():Void {
        var u:MovieClip = skillReloadUnit(8, 0);
        var s:Object = WeaponAmmoRuntime.ensure(u, "长枪");
        s.reserve = 1; packs = 0;
        SkillReloadCore.reloadAllWeapons(u, true);
        assertNumber(1, s.ghost, "one remaining paid credit buys only one ghost");
        assertNumber(0, s.reserve, "single ghost exhausts exactly one paid credit");
        assertNumber(0, packs, "one-credit skill cannot create inventory");
        SkillReloadCore.reloadAllWeapons(u, true);
        assertNumber(1, s.ghost, "repeat with exhausted stock grants no second ghost");
        assertNumber(0, s.reserve, "repeat with exhausted stock cannot overdraw reserve");

        u = skillReloadUnit(8, 0); packs = 0;
        SkillReloadCore.reloadAllWeapons(u, true);
        s = u.长枪.value.ammoState;
        assertNumber(0, s.ghost, "no stock and no reserve cannot generate a free ghost");
        assertNumber(8, total(u), "failed ghost payment keeps ordinary ammo unchanged");
        assertNumber(0, s.reserve, "failed ghost payment grants no credit");

        u = skillReloadUnit(8, 2);
        s = WeaponAmmoRuntime.ensure(u, "长枪");
        s.reserve = 1; packs = 0;
        SkillReloadCore.reloadAllWeapons(u, true);
        assertNumber(7, WeaponAmmoRuntime.normal(u.长枪.value, 8), "last credit goes to ordinary deficit first");
        assertNumber(0, s.ghost, "partially filled normal magazine cannot receive skill ghosts");
        assertNumber(0, s.reserve, "partial ordinary fill consumes only available credit");

        u = skillReloadUnit(8, 0);
        s = WeaponAmmoRuntime.ensure(u, "长枪");
        s.reserve = 1;
        SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, true);
        assertNumber(2, s.ghost, "one-credit progress can continue using a newly paid packet");
        assertNumber(7, s.reserve, "second ghost leaves seven rounds from the new packet");
        assertNumber(9, packs, "continuation submits exactly one packet");
    }

    private static function testPaidSkillEligibilityAndDefaults():Void {
        var labels:Array = ["batch omitted", "batch false", "single omitted", "single false",
            "passive disabled", "feature disabled", "no native ghost", "non-tube"];
        for (var i:Number = 0; i < labels.length; i++) {
            var u:MovieClip = skillReloadUnit(8, 0);
            if (i == 4) u.被动技能.冲击连携.启用 = false;
            if (i == 5) {
                u.被动技能.冲击连携.__featurePrefs = {};
                u.被动技能.冲击连携.__featurePrefs["impact_chain.ghost_loading"] = false;
            }
            if (i == 6) u.长枪属性.overload = {ghostLimit:2};
            if (i == 7) u.长枪属性.reloadType = "magazine";
            if (i == 0) SkillReloadCore.reloadAllWeapons(u);
            else if (i == 1) SkillReloadCore.reloadAllWeapons(u, false);
            else if (i == 2) SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u);
            else if (i == 3) SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, false);
            else {
                SkillReloadCore.reloadAllWeapons(u, true);
                ReloadManager.fillPaidGhostAfterSkill(u, "长枪");
            }
            assertNumber(0, u.长枪.value.ammoState.ghost, labels[i] + " grants no ghost");
            assertNumber(0, u.长枪.value.ammoState.reserve, labels[i] + " creates no paid balance");
            assertNumber(10, packs, labels[i] + " spends no inventory");
        }

        u = skillReloadUnit(8, 3);
        SkillReloadCore.reloadAllWeapons(u);
        assertNumber(8, WeaponAmmoRuntime.normal(u.长枪.value, 8), "default skill still fills ordinary magazine");
        assertNumber(0, u.长枪.value.ammoState.ghost, "default ordinary skill gains no ghost benefit");
        assertNumber(5, u.长枪.value.ammoState.reserve, "default skill preserves ordinary paid accounting");

        u = skillReloadUnit(8, 2);
        var s:Object = WeaponAmmoRuntime.ensure(u, "长枪");
        _root.控制目标 = "__otherSkillHero";
        _root.存档系统.dirtyMark = false;
        SkillReloadCore.reloadAllWeapons(u, true);
        SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, true);
        ReloadManager.fillPaidGhostAfterSkill(u, "长枪");
        assertNumber(8, total(u), "non-player batch retains free ordinary supply");
        assertNumber(0, s.ghost, "non-player cannot opt into paid skill ghosts");
        assertNumber(0, s.reserve, "non-player supply creates no paid balance");
        assertNumber(10, packs, "non-player old paths spend no player inventory");
        check(!_root.存档系统.dirtyMark, "non-player ghost rejection marks no player save");

        u = skillReloadUnit(8, 0);
        var other:Object = {_name:u._name, 长枪:{value:{shot:0}}, 长枪弹匣容量:8,
            长枪属性:u.长枪属性, 被动技能:u.被动技能};
        s = WeaponAmmoRuntime.ensure(other, "长枪");
        ReloadManager.fillPaidGhostAfterSkill(other, "长枪");
        assertNumber(0, s.ghost, "matching hero name cannot replace exact player identity");
        assertNumber(10, packs, "foreign unit cannot spend hero inventory for ghosts");
    }

    private static function testPaidSkillLinkedOnce():Void {
        var oldLinked:Function = LongGunSubWeaponCore.reloadLinked;
        LongGunSubWeaponCore.reloadLinked = function(owner:Object):Boolean {
            owner.__skillLinkedCalls++;
            return false;
        };
        try {
            for (var i:Number = 0; i < 4; i++) {
                var u:MovieClip = skillReloadUnit(8, i == 0 ? 0 : 3);
                u.__skillLinkedCalls = 0;
                if (i == 2) packs = 0;
                if (i == 3) SkillReloadCore.reloadAllWeapons(u);
                else SkillReloadCore.reloadAllWeapons(u, true);
                assertNumber(1, u.__skillLinkedCalls, "batch links at most once even on linked failure case " + i);
                assertNumber(i == 2 || i == 3 ? 0 : 2, u.长枪.value.ammoState.ghost, "linked call cannot change ghost policy case " + i);
            }
            u = skillReloadUnit(8, 3); u.__skillLinkedCalls = 0;
            SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, true);
            assertNumber(1, u.__skillLinkedCalls, "single ordinary skill reload keeps exactly one linked attempt");
            SkillReloadCore.reloadWeapon(u.长枪, u.长枪属性, u, true);
            assertNumber(1, u.__skillLinkedCalls, "single ghost/full check adds no linked attempt");
        } finally {
            LongGunSubWeaponCore.reloadLinked = oldLinked;
        }
    }

    /** CP1 额外入口：须已装载生产玩家模板、四个行走状态机与空中控制器。
     * 该入口不复制移动算法；库存/角色夹具隔离，所有被测入口来自 _root 的生产挂接。
     */
    public static function runMovementAndAdmissionTests():Void {
        passed=failed=serial=0;owners=[];
        var functions:Object=_root.主角函数;
        check(typeof functions.行走公共体=="function"&&typeof functions.持枪行走状态机=="function"
            &&typeof functions.双枪行走状态机=="function"&&typeof _root.空中控制器._tick=="function",
            "CP1 loads production movement, action machines and landing controller");
        if(failed>0){trace("--- A1MovementAdmissionTest: prerequisites missing ---");return;}
        var saved:Object={world:_root.gameworld,control:_root.控制目标,clock:_root.帧计时器,pause:_root.暂停,
            collision:_root.collisionLayer,gravity:_root.重力加速度,effect:_root.效果,sound:_root.播放音效,
            auto:_root.控制目标全自动,mouse:_root.全鼠标控制};
        var world:MovieClip=_root.createEmptyMovieClip("__a1MovementWorld",_root.getNextHighestDepth());
        _root.gameworld=world;_root.帧计时器={当前帧数:100};_root.暂停=false;
        _root.控制目标全自动=false;_root.全鼠标控制=false;
        _root.collisionLayer={hitTest:function():Boolean {return false;}};
        if(!org.flashNight.arki.spatial.move.Mover.initTag)org.flashNight.arki.spatial.move.Mover.init();
        _root.重力加速度=2;_root.效果=function():Void {};_root.播放音效=function():Void {};
        try {
            testMovementQualifications(functions);
            testHeldFireFacing(functions);
            testMeleeRunningAttack(functions);
            testRunningReloadReady(functions);
            testCombatAdmission(functions,world);
        } catch(error) {check(false,"movement/admission exception: "+error);}
        for(var i:Number=0;i<owners.length;i++)owners[i].removeMovieClip();world.removeMovieClip();
        _root.gameworld=saved.world;_root.控制目标=saved.control;_root.帧计时器=saved.clock;_root.暂停=saved.pause;
        _root.collisionLayer=saved.collision;_root.重力加速度=saved.gravity;_root.效果=saved.effect;_root.播放音效=saved.sound;
        _root.控制目标全自动=saved.auto;_root.全鼠标控制=saved.mouse;
        trace("--- A1MovementAdmissionTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
    }
    private static function movementUnit():MovieClip {
        var u:MovieClip=_root.gameworld.createEmptyMovieClip("move"+(++serial),_root.gameworld.getNextHighestDepth());owners.push(u);
        u.createEmptyMovieClip("man",1);u.createEmptyMovieClip("control",2);
        u.攻击模式="长枪";u.状态="长枪站立";u.方向="右";
        u._x=u._y=u.Z轴坐标=u.起始Y=0;u.操控编号=-1;
        u.行走X速度=2;u.行走Y速度=1;u.跑X速度=6;u.跑Y速度=3;
        u.右行=u.左行=u.上行=u.下行=u.动作A=u.动作B=u.动作C=false;
        u.移动=function(dir:String,speed:Number):Void {
            if(dir=="左")this._x-=speed;else if(dir=="右")this._x+=speed;
            else if(dir=="上")this.Z轴坐标-=speed;else if(dir=="下")this.Z轴坐标+=speed;
        };
        u.方向改变=function(dir:String):Void {this.方向=dir;};
        u.状态改变=function(state:String):Void {this.状态=state;};
        u.按键控制攻击模式=function():Void {this.modeChanges++;};
        u.aabbCollider={updateFromUnitArea:function():Void {}};
        return u;
    }
    private static function testMovementQualifications(functions:Object):Void {
        var reloadFlags:Array=["换弹标签","reloadFrameControlActive","reloadFrameControlRequest"];
        for(var player:Number=0;player<2;player++)for(var axes:Number=0;axes<4;axes++)for(var f:Number=0;f<reloadFlags.length;f++){
            var u:MovieClip=movementUnit();u.行走=player==1?functions.行走_玩家:functions.行走;
            u.移动射击=(axes&1)!=0;u.上下移动射击=(axes&2)!=0;u.强制奔跑=true;u.右行=u.下行=true;
            u.man[reloadFlags[f]]=true;
            for(var tick:Number=0;tick<4;tick++)u.行走();
            assertNumber(u.移动射击?8:0,u._x,"reload horizontal qualification player="+player+" axes="+axes+" flag="+f);
            assertNumber(u.上下移动射击?4:0,u.Z轴坐标,"reload vertical qualification player="+player+" axes="+axes+" flag="+f);
            check(u.强制奔跑===true,"reload only derives effectiveRun; real Shift survives");
            delete u.man[reloadFlags[f]];var x:Number=u._x,z:Number=u.Z轴坐标;u.行走();
            check(u._x===x+6&&u.Z轴坐标===z+3&&u.状态=="长枪跑","next normal sample restores held Shift running");
        }
        u=movementUnit();u.飞行浮空=true;u.右行=true;u._rotation=17;functions.行走_玩家.call(u);
        check(u._x===0&&u._rotation===17,"player flying return precedes rotation and movement");
        u.飞行浮空=false;functions.行走_玩家.call(u);check(u._rotation===0,"player ground movement cleans rotation");
        u=movementUnit();u._rotation=17;u.右行=true;functions.行走.call(u);check(u._rotation===17,"non-player entry preserves its rotation contract");
        var guards:Array=["__cf6TraversalOwner","__cf6ElevatorPoseOwner","__cf6VehicleOwner"];
        for(var i:Number=0;i<guards.length;i++){
            u=movementUnit();u.右行=true;u[guards[i]]={};functions.行走_玩家.call(u);functions.行走.call(u);
            assertNumber(0,u._x,"shared movement preserves owner guard "+guards[i]);
        }
    }
    private static function testHeldFireFacing(functions:Object):Void {
        var flags:Array=["动作A","动作B","主手射击中","副手射击中","副武器射击中","射击最大后摇中"];
        for(var player:Number=0;player<2;player++)for(var i:Number=0;i<flags.length;i++){
            var u:MovieClip=movementUnit();u.行走=player==1?functions.行走_玩家:functions.行走;
            u.移动射击=true;u.上下移动射击=true;u.强制奔跑=true;u.左行=true;u[flags[i]]=true;
            // held fire 的两项故意没有 shootingState，覆盖长间隔 cap 已清掉动作标志的空窗。
            for(var tick:Number=0;tick<4;tick++)u.行走();
            check(u._x===-8&&u.方向=="右"&&u.移动射击倒退===true,"displacement and muzzle remain independent for "+flags[i]);
            u[flags[i]]=false;u._semiLock_keepshooting=true;u.行走();
            check(u._x===-14&&u.方向=="左"&&u.移动射击倒退===false,"release turns immediately while cadence lock remains "+flags[i]);
            check(u._semiLock_keepshooting===true&&u.强制奔跑===true,"facing does not rewrite lock or Shift");
        }
        u=movementUnit();u.攻击模式="双枪";u.移动射击=true;u.左行=true;
        for(i=0;i<8;i++){
            u.动作A=(i%2)==0;u.动作B=!u.动作A;u.主手射击中=u.副手射击中=false;functions.行走_玩家.call(u);
        }
        check(u._x===-16&&u.方向=="右","dual alternating hands retain aim across capped shootingState gaps");
        u.动作A=u.动作B=false;functions.行走_玩家.call(u);check(u.方向=="左","dual release can turn after both actions end");
        u=movementUnit();u.移动射击=true;u.左行=true;
        for(i=0;i<6;i++){
            u.方向="右";u.动作A=true;functions.行走_玩家.call(u);check(u.方向=="右","rapid press locks facing "+i);
            u.动作A=false;u.射击最大后摇中=true;functions.行走_玩家.call(u);check(u.方向=="右","existing recovery holds facing "+i);
            u.射击最大后摇中=false;functions.行走_玩家.call(u);check(u.方向=="左","rapid release turns after recovery "+i);
        }
        assertNumber(-36,u._x,"rapid taps keep walking displacement on every admitted tick");
    }
    private static function testRunningReloadReady(functions:Object):Void {
        var modes:Array=["长枪","手枪","手枪2","双枪"];
        for(var i:Number=0;i<modes.length;i++)for(var mobile:Number=0;mobile<2;mobile++){
            var u:MovieClip=movementUnit();u.攻击模式=modes[i];u.状态=modes[i]+"跑";
            u.行走=functions.行走_玩家;u.移动射击=mobile==1;u.强制奔跑=true;u.右行=true;u.动作C=true;
            var machine:Function=modes[i]=="双枪"?functions.双枪行走状态机:functions.持枪行走状态机;
            _root.帧计时器.当前帧数=100;machine.call(u.control);
            check(u.状态===modes[i]+(mobile==1?"行走":"站立")&&u.行走冷却帧===2,"R from run sets cooldown before pose handoff "+modes[i]);
            check(UnitActionIntentService.has(u,1,3,100),"run tap preserved by bounded intent "+modes[i]);
            u.动作C=false;_root.帧计时器.当前帧数=101;machine.call(u.control);
            check(u.行走冷却帧===1&&UnitActionIntentService.has(u,1,3,101),"not-ready man does not consume tap "+modes[i]);
            u.man.reloadStarts=0;u.man.开始换弹=function():Void {this.reloadStarts++;this.换弹标签=true;};
            _root.帧计时器.当前帧数=102;machine.call(u.control);
            check(u.man.reloadStarts===1&&!UnitActionIntentService.has(u,1,3,102),"ready man consumes R exactly once "+modes[i]);
            _root.帧计时器.当前帧数=103;machine.call(u.control);
            check(u.强制奔跑===true&&u.状态!==modes[i]+"跑","held direction cannot race ready reload back to run "+modes[i]);
            u=movementUnit();u.攻击模式=modes[i];u.状态=modes[i]+"跑";u.行走=functions.行走_玩家;
            u.移动射击=true;u.强制奔跑=true;u.右行=true;u.动作C=true;
            _root.帧计时器.当前帧数=200;machine.call(u.control);u.动作C=false;
            _root.帧计时器.当前帧数=204;machine.call(u.control);
            check(!UnitActionIntentService.has(u,1,3,204),"not-ready reload intent expires without unbounded retry "+modes[i]);
        }
    }
    private static function testMeleeRunningAttack(functions:Object):Void {
        var modes:Array=["空手","兵器"];
        for(var player:Number=0;player<2;player++)for(var m:Number=0;m<2;m++)for(var mobile:Number=0;mobile<2;mobile++) {
            var u:MovieClip=movementUnit();
            u.攻击模式=modes[m];u.状态=modes[m]+"跑";u.兵种="melee-regression-fixture";
            u.行走=player==1?functions.行走_玩家:functions.行走;
            u.移动射击=mobile==1;u.强制奔跑=true;u.右行=true;u.动作A=true;
            u.行走();
            check(u.状态===modes[m]+"跑","melee held attack keeps running before action arbitration");
            functions.拳刀行走状态机.call(u.control);
            check(u.状态===modes[m]+"冲击","melee running attack still selects impact for player="+player+" mobile="+mobile);
            check(u.强制奔跑===true,"melee arbitration preserves sampled Shift input");
        }
    }

    private static function testCombatAdmission(functions:Object,world:MovieClip):Void {
        var u:MovieClip=movementUnit();u.右行=u.动作A=u.动作B=u.动作C=true;u.移动射击=true;u.行走=functions.行走_玩家;
        world.__combatAdmitted=false;var state:String=u.状态;
        functions.行走_玩家.call(u);functions.行走.call(u);functions.攻击.call(u);functions.冲击.call(u);functions.跳.call(u);
        functions.按键控制攻击模式.call(u);
        check(functions.按键检测.call(u,0,1)===false,"combat closed rejects ordinary key sampling");
        check(functions.释放技能.call(u,"invalid",0,0)===false&&functions.释放主动战技.call(u)===false,"combat closed rejects skill start entries");
        var machines:Array=[functions.持枪行走状态机,functions.双枪行走状态机,functions.拳刀行走状态机,functions.手雷行走状态机];
        for(var i:Number=0;i<machines.length;i++)machines[i].call(u.control);
        check(u._x===0&&u.状态===state,"closed admission rejects even stale sampled movement and action flags");
        check(AIEnvironment.isPaused()&&ShootCore.isPresentationControlled(u),"AI target selection and shooting share frozen combat gate");
        var lanes:Array=[ShootCore.primaryParams,ShootCore.secondaryParams,ShootCore.subweaponParams];
        u._semiLock_keepshooting=true;
        for(i=0;i<lanes.length;i++){
            check(!ShootCore.continuousShoot(u,"长枪",100,lanes[i]),"closed gate rejects queued lane "+i);
            check(!ShootCore.continuousShootAs(u,{params:lanes[i]}),"closed gate rejects queued contextual lane "+i);
        }
        check(!ShootCore.isAnyShooting(u)&&u._semiLock_keepshooting===true,"rejected callbacks retire firing but retain held-trigger cadence lock");
        functions.强制移动.call(u,"右",7);assertNumber(7,u._x,"closed admission still permits scripted force movement through real Mover");
        u._y=-1;u.Z轴坐标=0;u.垂直速度=4;u.浮空=true;u.__air={sources:{naturalFall:{}}};
        _root.空中控制器._tick(u);
        check(u._y===0&&u.浮空===false&&u.temp_y===0&&u.__air.sources.naturalFall===undefined,
            "closed admission does not freeze natural landing physics or its cleanup");
        delete world.__combatAdmitted;u.动作A=u.动作B=u.动作C=false;u.主手射击中=u.副手射击中=u.副武器射击中=false;
        var x:Number=u._x;functions.行走_玩家.call(u);
        check(u._x===x+2&&!AIEnvironment.isPaused()&&!ShootCore.isPresentationControlled(u),"undefined combat admission preserves legacy movement/AI/fire eligibility");
    }

    private static var deferredOriginalAdd:Function;

    private static function deferredSpec():Object {
        return {weapontype:"突击步枪", subweapon:{name:"deferred测试副武器",cd:1000,
            consumeMode:"onFire",consumeTiming:"onFire",fireCost:1,hp:0,mp:17,
            capacity:3,initialLoaded:3,reserveName:"测试弹匣",power:100,
            bullet:"测试榴弹",sound:"test.wav",split:1,diffusion:0,
            velocity:25,range:50,impact:1,damageType:"物理",hitBehavior:{}}};
    }

    private static function deferredReadyMan(u:MovieClip, ready:Boolean):MovieClip {
        var previous:MovieClip=u.man;
        if(previous!=null){
            previous._name="__retiredDeferredFixture"+(++serial);
            previous.removeMovieClip();
        }
        delete u.man;
        var m:MovieClip=u.createEmptyMovieClip("man",u.getNextHighestDepth());
        m.射击许可标签=true;m.换弹标签=false;m.射击速度=1000;
        m.使用弹匣名称="测试弹匣";m.剩余弹匣数=10;
        m.gotoAndPlay=function(label:String):Void {this.lastLabel=label;};
        m.gotoAndStop=function(label:String):Void {this.lastLabel=label;};
        if(ready){
            var g:MovieClip=m.createEmptyMovieClip("枪",1);
            g=g.createEmptyMovieClip("枪",1);
            g=g.createEmptyMovieClip("装扮",1);
            var muzzle:MovieClip=g.createEmptyMovieClip("枪口位置",1);
            muzzle._x=7;muzzle._y=9;
        }
        return m;
    }

    private static function deferredUnit():MovieClip {
        var u:MovieClip=unit(8,0);
        u.hp=1000;u.mp=500;u.移动射击=true;u.动作A=false;u.动作B=true;
        u.兵种="主角-男";u.状态="长枪跑";u.__stateGotoLabel="长枪跑";
        u.方向="右";u.Z轴坐标=0;u.enableShoot=true;u.__deferredShots=0;
        u.__deferredReadyOnGoto=false;u.__deferredMissingMan=false;
        u.dispatcher=new org.flashNight.neur.Event.EventDispatcher();
        org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent.initialize(u);
        u.存储当前飞行状态=function():Void {};
        u.读取当前飞行状态=function():Void {};
        u.状态改变=function(state:String):Void {
            org.flashNight.arki.unit.UnitComponent.Routing.StateTransition.apply(this,state);
        };
        u.gotoAndStop=function(label:String):Void {
            this.__lastDeferredGoto=label;
            if(this.__deferredMissingMan){
                var previous:MovieClip=this.man;
                if(previous!=null){previous._name="__retiredMissingMan"+this._name;previous.removeMovieClip();}
                this.man=null;
            } else WeaponAmmoRuntimeTest.deferredReadyMan(this,this.__deferredReadyOnGoto===true);
        };
        LongGunSubWeaponCore.configureUnit(u,deferredSpec());
        return u;
    }

    // Observer only: all scheduling still executes the production wheel method.
    // Captured callback/args allow a deliberately late delivery after cancellation.
    private static function captureDeferredTask(callback:Function, delay:Number, repeatCount):Number {
        var params:Array=[];
        for(var i:Number=0;i<arguments.length;i++)params.push(arguments[i]);
        if(params.length==6 && params[3].长枪副武器状态===params[4]
                && params[4].pendingFire===params[5]){
            params[3].__capturedDeferred={callback:callback,unit:params[3],state:params[4],action:params[5]};
        }
        return deferredOriginalAdd.apply(org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I(),params);
    }

    private static function deliverDeferred(saved:Object):Void {
        if(saved!=null)saved.callback(saved.unit,saved.state,saved.action);
    }

    private static function tickDeferred(count:Number):Void {
        var wheel:Object=org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        for(var i:Number=0;i<count;i++)wheel.tick();
    }

    private static function recordDeferredShot(props:Object):Void {
        var u:MovieClip=_root.gameworld[props.发射者];
        u.__deferredShots++;
    }

    private static function rearmDeferredRequest(u:MovieClip):Void {
        u.状态="长枪跑";u.__stateGotoLabel="长枪跑";
        u.__deferredMissingMan=false;u.__deferredReadyOnGoto=false;
        deferredReadyMan(u,false);
        check(LongGunSubWeaponCore.requestShoot(u),"new pose request accepted after pending retirement");
    }

    private static function testDeferredPendingLifecycle():Void {
        var wheel:Object=org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        var savedAdd:Function=wheel.addTask;
        var savedShoot:Function=_root.子弹区域shoot传递;
        var savedRefresh:Function=_root.玩家信息界面.刷新mp显示;
        var savedPause:Boolean=_root.暂停;
        var savedFrameMs:Number=wheel.每帧毫秒;
        var firstOwner:Number=owners.length;
        wheel.reset();wheel.每帧毫秒=1000/30;
        deferredOriginalAdd=savedAdd;wheel.addTask=captureDeferredTask;
        _root.子弹区域shoot传递=recordDeferredShot;
        _root.玩家信息界面.刷新mp显示=function():Void {};
        _root.暂停=false;
        try {
            testDeferredSameStateAndEquipment();
            testDeferredCleanupAndTransitions();
            testDeferredInvalidityBeforeReadiness();
            testDeferredBoundedAndReady();
        } finally {
            for(var i:Number=firstOwner;i<owners.length;i++)ShootCore.cleanup(owners[i]);
            wheel.addTask=savedAdd;deferredOriginalAdd=null;
            wheel.reset();wheel.每帧毫秒=savedFrameMs;
            _root.子弹区域shoot传递=savedShoot;
            _root.玩家信息界面.刷新mp显示=savedRefresh;
            _root.暂停=savedPause;
        }
    }

    private static function testDeferredSameStateAndEquipment():Void {
        var wheel:Object=org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        var u:MovieClip=deferredUnit();
        check(LongGunSubWeaponCore.requestShoot(u),"not-ready pose request accepted");
        var state:Object=u.长枪副武器状态;
        var first:Object=state.pendingFire;
        var oldDelivery:Object=u.__capturedDeferred;
        check(first!=null && first.taskId!=null && wheel.getActiveTaskCount()==1,
            "one pending action owns one real wheel task");
        LongGunSubWeaponCore.cancelPendingFire(u);
        check(state.pendingFire==undefined && wheel.getActiveTaskCount()==0,
            "public cancellation removes the real wheel task");
        rearmDeferredRequest(u);
        var second:Object=state.pendingFire;
        check(second!=null && second!==first,"same equipment creates a new ordinary action identity");
        deliverDeferred(oldDelivery);
        check(state.pendingFire===second && u.__deferredShots==0 && wheel.getActiveTaskCount()==1,
            "late old action cannot run or cancel the new action in the same state");
        deferredReadyMan(u,true);tickDeferred(2);
        check(state.pendingFire==undefined && u.__deferredShots==1,
            "the current pending action commits once when its current muzzle becomes ready");
        assertNumber(2,LongGunSubWeaponCore.getLoadedCount(u),"successful deferred shot consumes one loaded round");
        assertNumber(483,u.mp,"successful deferred shot commits MP once");
        assertNumber(9,packs,"successful deferred shot submits one reserve cost");
        deliverDeferred(oldDelivery);
        check(u.__deferredShots==1,"completed old delivery remains inert");
        ShootCore.cleanup(u);

        u=deferredUnit();LongGunSubWeaponCore.requestShoot(u);
        oldDelivery=u.__capturedDeferred;state=u.长枪副武器状态;
        LongGunSubWeaponCore.configureUnit(u,deferredSpec());
        check(u.长枪副武器状态!==state && state.pendingFire==undefined
            && wheel.getActiveTaskCount()==0,"reconfiguration retires old state and its real task");
        var replacement:Object=u.长枪副武器状态;
        replacement.nextFireTime=getTimer()+5000;
        var deadline:Number=replacement.nextFireTime;
        deliverDeferred(oldDelivery);
        check(u.长枪副武器状态===replacement && replacement.nextFireTime==deadline
            && u.__deferredShots==0 && u.mp==500 && packs==10,
            "old equipment callback cannot mutate replacement ammunition or cooldown");
        ShootCore.cleanup(u);
    }

    private static function testDeferredCleanupAndTransitions():Void {
        var wheel:Object=org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        var u:MovieClip=deferredUnit();LongGunSubWeaponCore.requestShoot(u);
        var oldDelivery:Object=u.__capturedDeferred;
        var state:Object=u.长枪副武器状态;
        state.nextFireTime=getTimer()+5000;var deadline:Number=state.nextFireTime;
        ShootCore.cleanupLane(u,ShootCore.subweaponParams,true);
        check(state.pendingFire==undefined && wheel.getActiveTaskCount()==0 && state.nextFireTime==deadline,
            "real subweapon cleanupLane cancels pending while retaining the actual cooldown");
        deliverDeferred(oldDelivery);
        check(u.__deferredShots==0 && state.nextFireTime==deadline,"late cleanup callback cannot reset cadence");
        ShootCore.cleanup(u);

        u=deferredUnit();LongGunSubWeaponCore.requestShoot(u);
        oldDelivery=u.__capturedDeferred;
        org.flashNight.arki.unit.UnitComponent.Routing.StateTransition.apply(u,"空手跳");
        check(u.长枪副武器状态.pendingFire==undefined && wheel.getActiveTaskCount()==0,
            "accepted StateTransition replacement retires deferred ownership before goto");
        org.flashNight.arki.unit.UnitComponent.Routing.StateTransition.apply(u,"长枪站立");
        deferredReadyMan(u,true);deliverDeferred(oldDelivery);tickDeferred(4);
        check(u.__deferredShots==0 && u.mp==500 && packs==10,
            "returning from jump cannot revive the pre-jump firing action");
        ShootCore.cleanup(u);

        u=deferredUnit();LongGunSubWeaponCore.requestShoot(u);
        var pending:Object=u.长枪副武器状态.pendingFire;
        u.飞行浮空=true;
        org.flashNight.arki.unit.UnitComponent.Routing.StateTransition.apply(u,"长枪跑");
        check(u.长枪副武器状态.pendingFire===pending && wheel.getActiveTaskCount()==1,
            "refused flying-run transition does not retire the current pending action");
        u.飞行浮空=false;
        ShootCore.cleanup(u);

        u=deferredUnit();LongGunSubWeaponCore.requestShoot(u);
        oldDelivery=u.__capturedDeferred;
        u.长枪.value.shot=u.长枪弹匣容量;u.长枪属性.reloadType="magazine";
        ReloadManager.startReload(u.man,u,_root);
        check(u.man.换弹标签 && u.长枪副武器状态.pendingFire==undefined
            && wheel.getActiveTaskCount()==0,"real reload admission reaches cleanupLane and cancels pending");
        ReloadManager.finishReload(u.man);deferredReadyMan(u,true);
        deliverDeferred(oldDelivery);tickDeferred(4);
        check(u.__deferredShots==0 && u.mp==500 && packs==10,
            "reload completion does not resurrect its predecessor fire request");
        ShootCore.cleanup(u);
    }

    private static function testDeferredInvalidityBeforeReadiness():Void {
        var kinds:Array=["release","pause","dead","presentation","mode","airborne","down","reload","guard"];
        for(var missing:Number=0;missing<2;missing++)for(var i:Number=0;i<kinds.length;i++){
            var u:MovieClip=deferredUnit();u.__deferredMissingMan=missing==1;
            LongGunSubWeaponCore.requestShoot(u);
            var state:Object=u.长枪副武器状态;
            check(state.pendingFire!=null,"valid request enters bounded readiness: "+kinds[i]+" missing="+missing);
            var kind:String=kinds[i];
            if(kind=="release")u.动作B=false;
            else if(kind=="pause")_root.暂停=true;
            else if(kind=="dead")u.hp=0;
            else if(kind=="presentation")u.__cf6TraversalOwner={};
            else if(kind=="mode"){u.攻击模式="兵器";u.状态="兵器站立";}
            else if(kind=="airborne")u.浮空=true;
            else if(kind=="down")u.倒地=true;
            else if(kind=="reload")u.换弹中=true;
            else state.fireGuard=function():Boolean {return false;};
            tickDeferred(2);
            check(state.pendingFire==undefined && u.__deferredShots==0
                && u.mp==500 && packs==10 && state.nextFireTime==0,
                "invalid action retires before readiness: "+kind+" missing="+missing);
            check(org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I().getActiveTaskCount()==0,
                "invalid action leaves no real retry task: "+kind+" missing="+missing);
            _root.暂停=false;ShootCore.cleanup(u);
        }
    }

    private static function testDeferredBoundedAndReady():Void {
        var wheel:Object=org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        var u:MovieClip=deferredUnit();u.__deferredMissingMan=true;
        check(LongGunSubWeaponCore.requestShoot(u),"missing man is a bounded readiness wait");
        var pending:Object=u.长枪副武器状态.pendingFire;
        for(var i:Number=0;i<30;i++)LongGunSubWeaponCore.requestShoot(u);
        check(u.长枪副武器状态.pendingFire===pending && pending.retries==1 && wheel.getActiveTaskCount()==1,
            "held input cannot restart readiness budget or add parallel tasks");
        tickDeferred(12);
        check(u.长枪副武器状态.pendingFire==undefined && wheel.getActiveTaskCount()==0
            && u.__deferredShots==0,"missing-man retries exhaust without a permanent pending lock");
        rearmDeferredRequest(u);deferredReadyMan(u,true);tickDeferred(2);
        check(u.__deferredShots==1,"fresh request succeeds after bounded exhaustion");
        ShootCore.cleanup(u);

        u=deferredUnit();u.__deferredReadyOnGoto=true;
        check(LongGunSubWeaponCore.requestShoot(u),"synchronously ready pose handoff remains accepted");
        check(u.状态=="长枪行走" && u.长枪副武器状态.pendingFire==undefined
            && u.__capturedDeferred==undefined && u.__deferredShots==1,
            "synchronous callback reenters fireInternal once without scheduling a pending action");
        ShootCore.cleanup(u);

        u=deferredUnit();LongGunSubWeaponCore.requestShoot(u);
        u.长枪副武器状态.nextFireTime=getTimer()+5000;
        var deadline:Number=u.长枪副武器状态.nextFireTime;
        deferredReadyMan(u,true);tickDeferred(2);
        check(u.长枪副武器状态.pendingFire==undefined && u.__deferredShots==0
            && u.长枪副武器状态.nextFireTime==deadline && u.mp==500 && packs==10,
            "ready callback retires but cannot bypass an intervening real cooldown");
        ShootCore.cleanup(u);
    }

}
