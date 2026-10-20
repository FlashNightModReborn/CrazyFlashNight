import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.hud.WeaponAmmoHudProjection;

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
            testPauseBeforeFrameControlAdmission();
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
}
