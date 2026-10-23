import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
/** 实际协调器、实际数值/资源 adapter、RoutingIntent 和 MovieClip；不冒称完整游戏旅程。 */
class org.flashNight.arki.unit.PlayerStatLifecycleTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var world:MovieClip;
    private static var c:PlayerStatRefreshCoordinator;
    private static var keys:Array=["gameworld","控制目标","存档系统","savePath","_saveExt","物品栏","主角被动技能","玩家信息界面","装备引用配置","敌人函数","全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成","经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成","刷新人物装扮","等级","限制系统","难度等级","宠物信息","佣兵个数限制","佣兵是否出战信息","同伴数据"];
    public static function runAllTests():Void {
        passed=failed=0;var saved:Object={};var i:Number;
        for(i=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        world=_root.createEmptyMovieClip("__playerStatLifecycleWorld",_root.getNextHighestDepth());
        try {
            _root.gameworld=world;_root.控制目标="stat-test";_root.存档系统={};_root.savePath="isolated-stat-lifecycle";_root._saveExt={};
            _root.敌人函数={魔法伤害种类:["基础","电","热","冷","波","蚀","毒","冲","人类"]};
            for(i=10;i<19;i++) _root[keys[i]]=0;
            _root.装备引用配置={刷新所有装扮:function(t:Object):Void {t.__testReferenceRefreshes++;}};
            testNestedScene();testTicketRecovery();testGrowthIntents();testGrowthEarlyRecovery();testPublicCompatibility();
            testLegacyEquipment();
            testConditionalInputsAndBuffTimer();testOrdinaryExtClone();testSkillCandidateGate();testContextDetach();testWarlordContext();
        } catch(error) {check(false,"suite exception: "+error);}
        finally {
            c.resetContext(null,"test_finished",null);
            world.removeMovieClip();
            for(i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        trace("PlayerStatLifecycleTest Tests Passed: "+passed);
        trace("PlayerStatLifecycleTest Tests Failed: "+failed);
    }
    private static function check(ok:Boolean,label:String):Void {
        if(ok) {passed++;trace("[PASS] StatLifecycle: "+label);} else {failed++;trace("[FAIL] StatLifecycle: "+label);}
    }
    private static function fixture(preserveContext:Boolean):MovieClip {
        var old:MovieClip=world["stat-test"];if(old!=undefined) old.removeMovieClip();
        var t:MovieClip=world.createEmptyMovieClip("stat-test",world.getNextHighestDepth());
        var factory:Object=org.flashNight.arki.unit.PlayerStatProjectionTest;
        var seed:Object=factory.persistentFixture();
        for(var key:String in seed) if(key!="_name") t[key]=seed[key];
        t.hasDressup=true;t.__testReferenceRefreshes=0;t.enableShoot=true;
        _root.物品栏={装备栏:inventoryFor(t.__sourceFixture)};
        _root.主角被动技能={};_root.玩家信息界面={};
        c=PlayerStatRefreshCoordinator.production();if(preserveContext!==true) c.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
        return t;
    }
    private static function inventoryFor(refs:Object):Object {return {getItem:function(slot:String):Object {return refs[slot];}};}
    private static function ready(t:Object):Void {
        var scope:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);
        PlayerStatRefreshCoordinator.activateInitialization(t);
        PlayerStatRefreshCoordinator.prepareFullNumeric(t,scope);
        PlayerStatRefreshCoordinator.finishOuterAfterState(t,"空手站立",scope);
    }
    private static function testNestedScene():Void {
        var t:MovieClip=fixture();_root.主角被动技能={独行者:{等级:3,启用:true}};
        var scene:Object=PlayerStatRefreshCoordinator.beginSceneInitialization(world);
        var template:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);
        PlayerStatRefreshCoordinator.activateInitialization(t);var body:Object=t.__playerStatBody;
        var inner:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);
        PlayerStatRefreshCoordinator.prepareFullNumeric(t,inner);
        PlayerStatRefreshCoordinator.finishOuterAfterState(t,"空手站立",inner);
        check(c.flush("inner").reason=="pending_ready" && t.__playerStatFullReady==null,"inner numeric and state completion do not publish outer readiness");
        _root.主角被动技能.独行者.等级=4;c.invalidate(2,"skills",c.contextToken());
        PlayerStatRefreshCoordinator.finishOuterAfterState(t,"空手站立",template);
        check(c.flush("scene_ready").reason=="pending_ready" && t.__testReferenceRefreshes==2,"post-state continuation closes both scopes but waits for scene resource owner");
        t.hp=1300;t.mp=222;
        var result:Object=PlayerStatRefreshCoordinator.endSceneInitialization(scene);
        check((result.status=="applied" || result.status=="unchanged") && t.__playerStatFullReady===body && t.hp满血值==1200,"late authoritative passive revision is included before final scene readiness");
        check(t.hp==1300 && t.mp==222 && c.diagnostics().dirtyMask==0,"transfer resource exceptions survive final tail with captured watermarks");
        check(c.flush("unchanged").status=="unchanged" && t.__playerStatBody===body,"final initial build is absorbed without another full initialization");
    }
    private static function ownerFor(t:Object,state:Object):Object {
        return {verifyInput:function(p:Object):Boolean {return p===state;},
            rebuild:function(ticket:Object):Void {
                state.starts++;var scope:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,ticket);
                PlayerStatRefreshCoordinator.activateInitialization(t);
                var rejected:Boolean=false;
                try {PlayerStatRefreshCoordinator.activateInitialization(t);} catch(error) {rejected=true;}
                state.duplicateRejected=rejected;
                PlayerStatRefreshCoordinator.prepareFullNumeric(t,scope);
                PlayerStatRefreshCoordinator.finishOuterAfterState(t,"空手站立",scope);
            },verifyOutput:function(p:Object):Boolean {return p===state && state.starts==1;}};
    }
    private static function faultUi(state:Object):Object {return {刷新hp显示:function():Void {if(state.fail) {state.fail=false;throw new Error("full_tail_failure");}}};}
    private static function testTicketRecovery():Void {
        var t:MovieClip=fixture();ready(t);var before:Object=t.__playerStatBody;
        var state:Object={starts:0,fail:true};var owner:Object=ownerFor(t,state);
        var ticket:Object=c.prepareEquipmentTransition(state,owner);
        _root.玩家信息界面=faultUi(state);c.invalidate(5,"equipment",c.contextToken());
        var result:Object=c.flush("equipment");
        check(result.status=="failed" && ticket.status=="started" && state.starts==1 && state.duplicateRejected && t.__playerStatBody===ticket.targetBody && before!==ticket.targetBody,"preallocated body starts exactly once and a final-tail fault holds the ticket");
        check(c.flush("ordinary_retry").reason=="equipment_owner_recovery_required" && state.starts==1,"ordinary dirty retry never replays the started full owner");
        check(PlayerStatRefreshCoordinator.resumeFullInitialization(ticket,{}).reason=="lifecycle_abort_required","a different owner cannot resume a full initialization");
        result=PlayerStatRefreshCoordinator.resumeFullInitialization(ticket,owner);
        check(result.status=="applied" && c.flush("owner_recovered").status=="applied" && state.starts==1 && ticket.status=="completed","original owner resumes only the saved pure final tail and completes B1");
        check(c.diagnostics().dirtyMask==0 && t.enableShoot && t.__playerStatProjectionBlocked===false,"recovery clears covered bits and releases only the projection action gate");
    }
    private static function testContextDetach():Void {
        var t:MovieClip=fixture();ready(t);
        var scene:Object=PlayerStatRefreshCoordinator.beginSceneInitialization(world);
        var hp:Number=t.hp;var token:Object=c.contextToken();
        c.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
        check(c.contextToken()!==token && c.flush("unbound").reason=="pending_actor","same-slot authority reset detaches before any automatic actor binding");
        check(PlayerStatRefreshCoordinator.endSceneInitialization(scene).reason=="stale_scene_scope" && t.hp==hp,"late old scene completion does not publish or write the previous actor");
    }
    private static function testOrdinaryExtClone():Void {
        var t:MovieClip=fixture();ready(t);
        var token:Object=c.contextToken();var body:Object=t.__playerStatBody;var refreshes:Number=t.__testReferenceRefreshes;
        var hp:Number=t.hp;var ext:Object={};for(var key:String in _root._saveExt) ext[key]=_root._saveExt[key];
        _root._saveExt=ext;
        _root.主角被动技能={独行者:{等级:4,启用:true}};
        var current:Object=PlayerStatRefreshCoordinator.production();c.invalidate(2,"skills",token);
        check(current===c && c.contextToken()===token && c.flush("reward_ext_clone").status=="applied"
                && t.hp满血值==1200 && t.hp==hp && t.__playerStatBody===body && t.__testReferenceRefreshes==refreshes,
            "ordinary ext clone keeps live generation and projects committed skills without detaching or full initialization");
    }
    private static function testSkillCandidateGate():Void {
        var t:MovieClip=fixture();ready(t);var before:Number=t.hp满血值;
        var body:Object=t.__playerStatBody;var blocked:Boolean=false;
        var oldGymHp:Number=_root.全局健身HP加成;
        PlayerStatRefreshCoordinator.setSkillRewardReadGate(function():Boolean {return true;});
        try {
            _root.主角被动技能={独行者:{等级:4,启用:true}};c.invalidate(2,"skills",c.contextToken());
            check(c.flush("pending_reward_skill").reason=="skill_reward_pending" && t.hp满血值==before,
                "uncommitted skill candidate cannot enter another domain stat projection");
            try {PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);} catch(error) {blocked=String(error.message)=="skill_reward_pending";}
            check(blocked && t.__playerStatBody===body,"pending skill candidate also blocks full lifecycle consumption");
            // NPC 不读取玩家候选；保存等待不能中止已经在同场景加载的其他单位。
            _root.全局健身HP加成=333;
            PlayerStatRefreshCoordinator.setGymGrowthReadGate(function():Boolean {return true;});
            var npc:MovieClip=world.createEmptyMovieClip("stat-npc",world.getNextHighestDepth());
            var factory:Object=org.flashNight.arki.unit.PlayerStatProjectionTest;
            var seed:Object=factory.persistentFixture();
            for(var key:String in seed) if(key!="_name") npc[key]=seed[key];
            npc.hasDressup=true;npc.__testReferenceRefreshes=0;
            ready(npc);
            check(npc.__playerStatFullReady===npc.__playerStatBody && npc.hp满血值==1000
                    && t.hp满血值==before && t.__playerStatBody===body,
                "pending player growth gates leave unrelated NPC initialization intact without consuming player skill or Gym candidates");
            npc.removeMovieClip();
        } finally {
            _root.全局健身HP加成=oldGymHp;
            PlayerStatRefreshCoordinator.setGymGrowthReadGate(undefined);
            PlayerStatRefreshCoordinator.setSkillRewardReadGate(undefined);
        }
        check(c.flush("confirmed_reward_skill").status=="applied" && t.hp满血值==1200 && t.__playerStatBody===body,
            "confirmed skill fact resumes pending cold work without another body");
    }
    private static function growthFunction(t:Object):Function {
        return function(level:Number):Void {
            t.__testGrowthOwnerCalls++;
            PlayerStatRefreshCoordinator.activateInitialization(t);
            t.hp基本满血值=1000+level*10;
            PlayerStatRefreshCoordinator.prepareFullNumeric(t,{plan:t.__playerStatInitPlan});
            PlayerStatLifecycleTest.settleFullOwnerResources(t);
        };
    }
    private static function testGrowthIntents():Void {
        var recovery:Object=org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery;
        var t:MovieClip=fixture();ready(t);t.__testGrowthOwnerCalls=0;t.根据等级初始数值=growthFunction(t);
        var owner:Object=recovery.captureIntentOwner("native-growth-21");
        var result:Object=recovery.refresh(t,21,owner);
        check((result.status=="applied" || result.status=="unchanged") && result.playEffect && t.hp==1210 && t.__testGrowthOwnerCalls==1,"growth owner initializes once and consumes one alive recovery before final readiness");
        t.hp-=100;result=recovery.refresh(t,21,owner);c.invalidate(1,"growth",c.contextToken());c.flush("independent_after_growth");
        check(!result.playEffect && t.hp==1110 && t.__testGrowthOwnerCalls==1,"duplicate growth and later ordinary STATS do not restore real subsequent damage");
        t=fixture();t.hp=0;ready(t);t.__testGrowthOwnerCalls=0;t.根据等级初始数值=growthFunction(t);
        var oldMp:Number=t.mp;result=recovery.refresh(t,22,recovery.captureIntentOwner("native-dead-growth"));
        check(t.hp==0 && t.mp==oldMp && t.__testGrowthOwnerCalls==1,"dead growth preserves death and previous MP");
        t=fixture();ready(t);_root.控制目标="missing-stat-actor";
        owner=recovery.captureIntentOwner("native-missing-growth");result=recovery.refresh(undefined,23,owner);
        _root.控制目标="stat-test";ready(t);var hp:Number=t.hp;
        check(result.status=="pending" && !recovery.refresh(t,23,owner).playEffect && t.hp==hp,"missing actor keeps numeric work pending without a delayed free level heal on a new body");
        t=fixture();ready(t);t.__testGrowthOwnerCalls=0;t.根据等级初始数值=growthFunction(t);
        var fault:Object={fail:true};_root.玩家信息界面=faultUi(fault);
        owner=recovery.captureIntentOwner("native-growth-tail-fault");result=recovery.refresh(t,24,owner);
        check(result.status=="failed" && t.hp==1240 && t.__testGrowthOwnerCalls==1,"growth recovery already consumed when final derived publication fails");
        result=c.flush("growth_tail_recovery");
        check((result.status=="applied" || result.status=="unchanged") && t.hp==1240 && t.__testGrowthOwnerCalls==1,"captured full tail resumes through the cold barrier without another growth owner or heal");
    }
    private static function testConditionalInputsAndBuffTimer():Void {
        var t:MovieClip=fixture();_root.主角被动技能={独行者:{等级:3,启用:true}};
        _root.限制系统={limitLevel:0,DisableCompanion:false};_root.难度等级=1;
        _root.宠物信息=[];_root.佣兵个数限制=1;_root.佣兵是否出战信息=[0];_root.同伴数据=[[20,"native-merc"]];
        ready(t);var body:Object=t.__playerStatBody;
        check(t.hp满血值==1150,"authoritative no-companion predicate enables loner");
        _root.宠物信息=[[0,1,100,0,1]];c.invalidate(1,"companion",c.contextToken());c.flush("pet_flag");
        check(t.hp满血值==1000 && t.hp==600 && t.__playerStatBody===body,"pet flag removes loner without replacing the body or healing");
        _root.限制系统.DisableCompanion=true;c.invalidate(1,"companion",c.contextToken());c.flush("restricted_companions");
        check(t.hp满血值==1150,"DisableCompanion retains the existing predicate definition");
        _root.限制系统.DisableCompanion=false;_root.宠物信息[0][4]=0;_root.佣兵是否出战信息[0]=1;
        c.invalidate(1,"companion",c.contextToken());c.flush("merc_flag");
        check(t.hp满血值==1000,"valid deployed mercenary suppresses loner");
        _root.佣兵是否出战信息[0]=-1;c.invalidate(1,"companion",c.contextToken());c.flush("merc_death_flag");
        check(t.hp满血值==1150 && t.__testReferenceRefreshes==1,"mercenary death flag restores loner through numeric projection alone");
        var manager:org.flashNight.arki.component.Buff.BuffManager=new org.flashNight.arki.component.Buff.BuffManager(t);
        t.buffManager=manager;
        var timer:org.flashNight.arki.component.Buff.Component.TimeLimitComponent=new org.flashNight.arki.component.Buff.Component.TimeLimitComponent(120);
        var effect:org.flashNight.arki.component.Buff.MetaBuff=new org.flashNight.arki.component.Buff.MetaBuff([
            new org.flashNight.arki.component.Buff.PodBuff("防御力","add",17)],[timer],0);
        manager.addBuff(effect,"native-stat-duration");manager.update(30);
        for(var i:Number=0;i<10;i++) {c.invalidate(1,"companion",c.contextToken());c.flush("timed_projection");}
        check(timer.getRemaining()==90 && t.buffManager===manager && t.防御力==207,"real timed MetaBuff keeps its remaining frames and manager through ten STATS commits");
        manager.update(90);c.invalidate(1,"companion",c.contextToken());c.flush("expired_projection");
        check(t.防御力==190 && t.hp==600,"real Buff expiration returns to current permanent base without resource restoration");
        manager.destroy();t.buffManager=undefined;
    }
    private static function failingGrowth(t:Object,state:Object):Function {
        return function(level:Number):Void {
            t.__testGrowthOwnerCalls++;
            PlayerStatRefreshCoordinator.activateInitialization(t);
            t.hp基本满血值=1000+level*10;
            if(state.fail) {state.fail=false;throw new Error("growth_before_numeric");}
            PlayerStatRefreshCoordinator.prepareFullNumeric(t,{plan:t.__playerStatInitPlan});
            PlayerStatLifecycleTest.settleFullOwnerResources(t);
        };
    }
    private static function mpGetter(state:Object):Function {return function():Number {return state.mp;};}
    private static function mpSetter(state:Object):Function {return function(value:Number):Void {state.mp=value;if(state.fail && value==state.triggerValue) {state.fail=false;throw new Error("growth_mp_setter_after_write");}};}
    private static function settleFullOwnerResources(t:Object):Void {
        var r:Object=t.__playerStatInitPlan.ownerResources;
        r.settledHp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleHpAfterMaxChange(r.hp,r.oldMax,Number(t.hp满血值));
        r.hpAttempted=true;t.hp=r.settledHp;r.hpDone=true;
        r.settledMp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleMpAfterMaxChange(r.mp,Number(t.mp满血值));
        r.mpAttempted=true;t.mp=r.settledMp;r.mpDone=true;r.stage="settled";
    }
    private static function testGrowthEarlyRecovery():Void {
        var recovery:Object=org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery;
        var t:MovieClip=fixture();ready(t);t.__testGrowthOwnerCalls=0;var fault:Object={fail:true};
        t.根据等级初始数值=failingGrowth(t,fault);
        var owner:Object=recovery.captureIntentOwner("growth-early-25");var result:Object=recovery.refresh(t,25,owner);
        check(result.status=="failed" && t.hp==600 && t.__testGrowthOwnerCalls==1,"early growth failure retains unconsumed resources and original owner");
        c.flush("ordinary_early_growth");recovery.refresh(t,25,owner);
        check(t.__testGrowthOwnerCalls==1,"ordinary barrier and duplicate committed growth do not restart a failed full owner");
        result=recovery.recoverLatest();
        check((result.status=="applied" || result.status=="unchanged") && result.playEffect && t.hp==1250 && t.__testGrowthOwnerCalls==2,"explicit original growth owner performs one controlled restart and one heal");
        t.hp-=50;result=recovery.recoverLatest();
        check(!result.playEffect && t.hp==1200 && t.__testGrowthOwnerCalls==2,"repeated explicit recovery cannot repeat the completed heal or effect");
        t=fixture();ready(t);t.__testGrowthOwnerCalls=0;t.根据等级初始数值=growthFunction(t);
        var mpFault:Object={mp:t.mp,fail:true,triggerValue:t.mp满血值};delete t.mp;t.addProperty("mp",mpGetter(mpFault),mpSetter(mpFault));
        result=recovery.refresh(t,26,recovery.captureIntentOwner("growth-partial-setter"));
        check(result.status=="failed" && t.hp==1260 && t.__testGrowthOwnerCalls==1,"one-shot HP and MP setter attempts are consumed before a partial setter exception");
        result=recovery.recoverLatest();
        check((result.status=="applied" || result.status=="unchanged") && t.hp==1260 && t.__testGrowthOwnerCalls==2,"partial one-shot recovery rebuilds only the owner and never repeats either setter");
        t=fixture();ready(t);t.__testGrowthOwnerCalls=0;fault={fail:true};t.根据等级初始数值=failingGrowth(t,fault);
        recovery.refresh(t,28,recovery.captureIntentOwner("growth-queued-first"));
        recovery.refresh(t,29,recovery.captureIntentOwner("growth-queued-second"));
        result=recovery.recoverLatest();
        check((result.status=="applied" || result.status=="unchanged") && t.hp==1290 && t.等级==29 && t.__testGrowthOwnerCalls==3,"a higher committed growth intent survives an earlier failed owner without replaying any reward");
        t=fixture();ready(t);t.__testGrowthOwnerCalls=0;fault={fail:true};t.根据等级初始数值=failingGrowth(t,fault);
        recovery.refresh(t,30,recovery.captureIntentOwner("growth-invalid-window"));t.hp-=1;
        check(recovery.recoverLatest().reason=="growth_recovery_window_invalid" && t.hp==599 && t.__testGrowthOwnerCalls==1,"changed resource window refuses early full restart without restoring new damage");
        t=fixture();ready(t);t.__testGrowthOwnerCalls=0;fault={fail:true};t.根据等级初始数值=failingGrowth(t,fault);
        owner=recovery.captureIntentOwner("growth-replaced-body");recovery.refresh(t,32,owner);
        recovery.refresh(t,33,recovery.captureIntentOwner("growth-replaced-queued"));
        var originalContext:Object=c.contextToken();var previousOwnerCalls:Number=t.__testGrowthOwnerCalls;
        t=fixture(true);t.等级=33;t.hp基本满血值=1330;t.hp=456;t.__testGrowthOwnerCalls=previousOwnerCalls;t.根据等级初始数值=growthFunction(t);
        var newScope:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);
        PlayerStatRefreshCoordinator.activateInitialization(t);var replacementHp:Number=t.hp;
        result=recovery.recoverCommitted(owner);
        check(result.status=="pending" && !result.playEffect && t.hp==replacementHp && c.contextToken()===originalContext,"old growth cannot declare a same-path replacement body ready or heal it before its own initialization ends");
        PlayerStatRefreshCoordinator.prepareFullNumeric(t,newScope);PlayerStatRefreshCoordinator.endOuterInitialization(newScope);
        result=recovery.recoverCommitted(owner);var duplicate:Object=recovery.refresh(t,33,recovery.captureIntentOwner("growth-replaced-duplicate"));
        check((result.status=="applied" || result.status=="unchanged") && !result.playEffect && !duplicate.playEffect
            && t.hp==replacementHp && t.__testGrowthOwnerCalls==1,"legitimate replacement retires old and queued one-shot heals while keeping the new numeric barrier");
        result=recovery.refresh(t,34,recovery.captureIntentOwner("growth-after-replacement"));
        check((result.status=="applied" || result.status=="unchanged") && result.playEffect && t.hp==1340 && t.__testGrowthOwnerCalls==2,"a later committed level uses its new body owner after an old failed growth intent is retired status="+result.status+":"+result.reason+" hp="+t.hp+" calls="+t.__testGrowthOwnerCalls+" level="+t.等级);
    }
    private static function testPublicCompatibility():Void {
        var t:MovieClip=fixture();ready(t);var body:Object=t.__playerStatBody;
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        for(var slot:String in t.__sourceFixture) t.__sourceFixture[slot].getData=function():Object {throw new Error("getData_in_public_stats");return null;};
        var manager:org.flashNight.arki.component.Buff.BuffManager=new org.flashNight.arki.component.Buff.BuffManager(t);t.buffManager=manager;
        manager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("防御力","add",17),"public-compat-defense");manager.update(0);
        var startedAt:Number=getTimer();
        var result:Object;for(var i:Number=0;i<100;i++) result=api.updateProperties(t);
        trace("PlayerStatPublic100ElapsedMs: "+(getTimer()-startedAt));
        check(result.status=="applied" && t.长枪属性.power==105 && t.防御力==117 && t.hp==600
                && t.buffManager===manager && t.__playerStatBody===body && t.__testReferenceRefreshes==1,"100 public compatibility STATS use stable input, preserve the real manager/body/resources and never invoke full initialization");
        manager.destroy();t.buffManager=undefined;
    }
    private static function legacyFull(t:Object,state:Object):Function {
        return function(name:String,ticket:Object):Object {
            if(ticket==null) return PlayerStatRefreshCoordinator.refreshLegacyEquipment(t);
            state.starts++;var scope:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,ticket);
            try {
                PlayerStatRefreshCoordinator.activateInitialization(t);
                if(state.fail) {state.fail=false;throw new Error("legacy_early_failure");}
                t.version++;
                var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
                var slots:Array=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.getSlotKeys();
                for(var i:Number=0;i<slots.length;i++) api.loadEquipmentData(t,slots[i],PlayerStatLifecycleTest.equipmentItem,1);
                var projection:Object=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
                projection.beginCanonical(t);projection.completeCanonical(t);
                PlayerStatRefreshCoordinator.prepareFullNumeric(t,scope);
                return PlayerStatRefreshCoordinator.endOuterInitialization(scope);
            } catch(error) {PlayerStatRefreshCoordinator.failOuterInitialization(scope,error);throw error;}
        };
    }
    private static function equipmentItem(t:Object,key:String):Object {return _root.物品栏.装备栏.getItem(key);}
    private static function countMode(state:Object):Function {return function(mode:String):Void {state.modeCalls++;state.mode=mode;};}
    private static function testLegacyEquipment():Void {
        var items:Object=org.flashNight.arki.item.ItemUtil;
        var oldData:Object=items.itemDataDict;var oldEquipment:Object=items.equipmentDict;
        var oldLookup:Function=_root.getItemData;var oldSound:Object=_root.soundEffectManager;var oldMessage:Function=_root.发布消息;
        var oldAcquire:Function=_root.singleAcquire;
        var oldProjectionPort:Object=_root.玩家属性投影;
        try {
            items.itemDataDict={pickupStatGun:{name:"pickupStatGun",type:"武器",use:"长枪",data:{level:1,power:150,capacity:30}},pickupStatDrug:{name:"pickupStatDrug",type:"消耗品",use:"药剂",data:{}}};
            items.equipmentDict={pickupStatGun:true};_root.getItemData=org.flashNight.arki.item.ItemUtil.getItemData;
            _root.soundEffectManager={playSound:function():Void {}};_root.发布消息=function():Void {};
            var t:MovieClip=legacyFixture();var state:Object={starts:0,modeCalls:0};
            _root.刷新人物装扮=legacyFull(t,state);t.攻击模式切换=countMode(state);_root.等级=60;
            var manager:org.flashNight.arki.unit.Action.PickUp.PickUpManager=new org.flashNight.arki.unit.Action.PickUp.PickUpManager();
            var success:Boolean=manager.拾取并装备("pickupStatGun",1);
            check(success && state.starts==1 && state.modeCalls==1 && state.mode=="长枪" && _root.存档系统.dirtyMark===true,"quick equip commits once and changes attack mode only after the full numeric barrier success="+success+" starts="+state.starts+" mode="+state.modeCalls+" reason="+c.diagnostics().reason);
            check(!manager.拾取并装备("pickupStatDrug",1) && state.starts==1,"wrong equipment kind produces no equipment invalidation or full initialization");
            t=legacyFixture();state={starts:0,modeCalls:0,fail:true};
            _root.刷新人物装扮=legacyFull(t,state);t.攻击模式切换=countMode(state);
            success=manager.拾取并装备("pickupStatGun",1);
            var item:Object=_root.物品栏.装备栏.getItem("长枪");var bagItem:Object=_root.物品栏.背包.getItem("0");
            c.flush("legacy_ordinary_retry");
            check(success && item.name=="pickupStatGun" && state.starts==1 && state.modeCalls==0
                    && t.__playerStatProjectionBlocked===true,"failed quick-equip projection remains a committed asset success and ordinary retry cannot restart or change mode success="+success+" starts="+state.starts+" reason="+c.diagnostics().reason);
            var result:Object=PlayerStatRefreshCoordinator.recoverLegacyEquipment(t);
            org.flashNight.arki.unit.Action.PickUp.PickUpManager.resumePendingEquipmentMode(t);
            org.flashNight.arki.unit.Action.PickUp.PickUpManager.resumePendingEquipmentMode(t);
            check((result.status=="applied" || result.status=="unchanged") && state.starts==2 && state.modeCalls==1
                    && _root.物品栏.装备栏.getItem("长枪")===item && _root.物品栏.背包.getItem("0")===bagItem,"explicit legacy recovery reprojects the committed inventory and consumes the pending mode exactly once result="+result.status+":"+result.reason+" starts="+state.starts+" mode="+state.modeCalls);
            t=legacyFixture();state={starts:0,modeCalls:0};_root.刷新人物装扮=legacyFull(t,state);t.攻击模式切换=countMode(state);
            var original:Object=_root.物品栏.装备栏.getItem("长枪");
            for(var slot:Number=0;slot<4;slot++) _root.物品栏.背包.add(slot,org.flashNight.arki.item.BaseItem.create("pickupStatDrug",1));
            _root.存档系统.dirtyMark=false;
            check(!manager.拾取并装备("pickupStatGun",1) && _root.物品栏.装备栏.getItem("长枪")===original
                && state.starts==0 && _root.存档系统.dirtyMark===false,"full real backpack rejects quick equip without moving the existing item or invalidating its projection");
            t=legacyFixture();state={starts:0,modeCalls:0,fail:true};_root.刷新人物装扮=legacyFull(t,state);t.攻击模式切换=countMode(state);
            manager.拾取并装备("pickupStatGun",1);
            var staleReceipt:Object=t.__pickupEquipmentModeReceipt;
            c.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
            var replacement:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);
            PlayerStatRefreshCoordinator.activateInitialization(t);PlayerStatRefreshCoordinator.prepareFullNumeric(t,replacement);
            PlayerStatRefreshCoordinator.endOuterInitialization(replacement);
            org.flashNight.arki.unit.Action.PickUp.PickUpManager.resumePendingEquipmentMode(t);
            check(state.modeCalls==0 && t.__playerStatBody!==staleReceipt.body,"an unrelated new body never consumes a failed pickup's old mode continuation");
            t=legacyFixture();
            _root.singleAcquire=function(name:String,count:Number):Boolean {return _root.物品栏.背包.add(-1,org.flashNight.arki.item.BaseItem.create(name,count));};
            world.dispatcher={publish:function():Void {}};
            var drop:MovieClip=world.createEmptyMovieClip("__repeatPickup",world.getNextHighestDepth());drop.物品名="pickupStatDrug";drop.数量=1;
            manager.pickup(drop,{hp:10,名字:"isolated companion"},false);manager.pickup(drop,{hp:10,名字:"isolated companion"},false);
            check(_root.物品栏.背包.getItem("0").name=="pickupStatDrug" && _root.物品栏.背包.getItem("1")==null,
                "repeated input on the same real pickup entity consumes the real backpack write only once");drop.removeMovieClip();
            t=legacyFixture();state={starts:0,modeCalls:0};_root.刷新人物装扮=legacyFull(t,state);
            var candidate:Object=org.flashNight.arki.item.BaseItem.create("pickupStatGun",1);
            _root.物品栏.背包.add(0,candidate);original=_root.物品栏.装备栏.getItem("长枪");
            var sourceIcon:Object={item:candidate,collection:_root.物品栏.背包,index:0};
            var targetIcon:Object={item:original,collection:_root.物品栏.装备栏,index:"长枪"};
            _root.玩家属性投影={允许遗留装备变更:function():Boolean {return false;}};
            check(!org.flashNight.arki.item.ItemUtil.moveItemToEquipment(sourceIcon,targetIcon,"长枪")
                && _root.物品栏.装备栏.getItem("长枪")===original && state.starts==0,
                "legacy public item movement requires the installed numeric admission before touching real containers");
            _root.玩家属性投影.允许遗留装备变更=function():Boolean {return PlayerStatRefreshCoordinator.admitLegacyEquipmentMutation();};
            _root.soundEffectManager={playSound:function():Void {throw new Error("optional_equipment_sound");}};
            _root.发布消息=function():Void {throw new Error("optional_equipment_message");};
            success=org.flashNight.arki.item.ItemUtil.moveItemToEquipment(sourceIcon,targetIcon,"长枪");
            check(success && state.starts==1 && _root.物品栏.装备栏.getItem("长枪")===candidate
                && _root.物品栏.背包.getItem("0")===original && c.diagnostics().dirtyMask==0,
                "real legacy swap stays committed and projects once even when both optional sound and message fail");
            var body:Object=t.__playerStatBody;
            success=org.flashNight.arki.item.ItemUtil.moveItemToInventory({item:original,collection:_root.物品栏.背包,index:0},
                {item:null,collection:_root.物品栏.背包,index:1});
            check(success && state.starts==1 && t.__playerStatBody===body && c.diagnostics().dirtyMask==0,
                "ordinary non-worn inventory movement does not declare equipment work or initialize the player");
        } finally {items.itemDataDict=oldData;items.equipmentDict=oldEquipment;_root.getItemData=oldLookup;_root.soundEffectManager=oldSound;_root.发布消息=oldMessage;_root.singleAcquire=oldAcquire;_root.玩家属性投影=oldProjectionPort;}
    }
    private static function legacyFixture():MovieClip {
        var t:MovieClip=fixture();
        // 使用真正 BaseItem 的序列化入口和实际装载，不把数值 mock 当成可搬运资产。
        // 消费本 TestLoader 已装配的真实容器，避免测试反向把子类加入初始化器的依赖环。
        // 入口另行断言三类的继承方法；这里既不补原型，也不以替身替代资产。
        var collectionTypes:Object=_global.org.flashNight.arki.item.itemCollection;
        var equipmentConstructor:Function=collectionTypes["EquipmentInventory"];
        var backpackConstructor:Function=collectionTypes["ArrayInventory"];
        var inventory:Object=new equipmentConstructor({长枪:{name:"pickupStatGun",value:{level:1,mods:[]},lastUpdate:1}});
        _root.物品栏.装备栏=inventory;
        _root.物品栏.背包=new backpackConstructor({},4);
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var projection:Object=org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        var slots:Array=projection.getSlotKeys();t.version++;
        for(var i:Number=0;i<slots.length;i++) api.loadEquipmentData(t,slots[i],PlayerStatLifecycleTest.equipmentItem,1);
        projection.beginCanonical(t);projection.completeCanonical(t);
        ready(t);
        return t;
    }
    private static function testWarlordContext():Void {
        var t:MovieClip=fixture();ready(t);var token:Object=c.contextToken();var hp:Number=t.hp;
        var warlord:Object=org.flashNight.arki.scene.WarlordActionEncounterService;
        var snapshot:Object=warlord.testOnlySnapshotGlobals();
        warlord.testOnlyApplyEncounterGlobals();var temporary:Object=c.contextToken();
        check(temporary!==token && c.flush("warlord_unbound").reason=="pending_actor" && t.hp==hp,"Warlord temporary input boundary detaches the ordinary player before replacement");
        warlord.testOnlyRestoreGlobals(snapshot);
        check(c.contextToken()!==temporary && c.flush("warlord_restored_unbound").reason=="pending_actor" && t.hp==hp,"Warlord restore uses a new context without restoring old applied watermarks");
    }
}
