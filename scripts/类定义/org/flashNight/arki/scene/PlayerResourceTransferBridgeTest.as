import org.flashNight.arki.scene.PlayerResourceTransferBridge;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.SceneTransitionGuard;
import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
import org.flashNight.neur.Event.EventBus;
/** 真 MovieClip + 实际完整初始化协调器；run/关卡启动回调是内存夹具。 */
class org.flashNight.arki.scene.PlayerResourceTransferBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var world:MovieClip;
    private static var run:Object;
    private static var events:Number;
    private static var observedHp:Number;
    private static var observedMp:Number;
    private static var starts:Number;
    private static var keys:Array=["gameworld","控制目标","存档系统","savePath","_saveExt","物品栏","主角被动技能","玩家信息界面","装备引用配置","敌人函数","全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成","经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成","等级","限制系统","难度等级","宠物信息","佣兵个数限制","佣兵是否出战信息","同伴数据","当前为战斗地图","淡出动画","新出生","鼠标","全鼠标控制","转场景记录数据","场景进入位置名","上键","下键","左键","右键"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("FAIL ResourceBridge "+label);}
    }
    private static function onScene(world:Object):Void {
        events++;observedHp=world[_root.控制目标].hp;observedMp=world[_root.控制目标].mp;
    }
    private static function authority():Object {return run;}
    private static function inventoryFor(refs:Object):Object {return {getItem:function(slot:String):Object {return refs[slot];}};}
    private static function makeWorld(stage:Number):Object {
        if(world!=undefined) world.removeMovieClip();
        world=_root.createEmptyMovieClip("__resourceBridgeWorld",_root.getNextHighestDepth());_root.gameworld=world;
        var manager:Object={gameworld:world,currentStage:stage,isActive:true,onResourcesReady:function(gate:Object):Void {starts++;}};
        return PlayerResourceTransferBridge.beginStage(world,stage,manager);
    }
    private static function hitClip(parent:MovieClip,name:String):MovieClip {
        var clip:MovieClip=parent.createEmptyMovieClip(name,parent.getNextHighestDepth());
        clip.beginFill(0xffffff);clip.moveTo(-10,-10);clip.lineTo(10,-10);
        clip.lineTo(10,10);clip.lineTo(-10,10);clip.lineTo(-10,-10);clip.endFill();return clip;
    }
    private static function persistentFixture():Object {
        var t:Object=org.flashNight.arki.unit.PlayerStatProjectionTest.fixture();t.version=1;
        var slots:Array=["头部装备","上装装备","手部装备","下装装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
        var data:Object={};var i:Number;
        for(i=0;i<slots.length;i++) data[slots[i]]=t[slots[i]+"数据"];
        t.__sourceFixture={};
        for(i=0;i<slots.length;i++) {
            var slot:String=slots[i];
            t.__sourceFixture[slot]={name:"source:"+slot,value:{level:1,mods:[]},data:data[slot],getData:function():Object {return this.data;}};
        }
        var loader:Function=function(target:Object,key:String):Object {return target.__sourceFixture[key];};
        var dressup:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        for(i=0;i<slots.length;i++) dressup.loadEquipmentData(t,slots[i],loader,1);
        org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.beginCanonical(t);
        org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.completeCanonical(t);
        return t;
    }
    private static function makeActor():MovieClip {
        var seed:Object=persistentFixture();
        seed.兵种="主角-男";seed.hasDressup=true;
        PlayerResourceTransferBridge.prepareSpawn("主角-男","stat-test",seed);
        var t:MovieClip=world.createEmptyMovieClip("stat-test",world.getNextHighestDepth());
        for(var key:String in seed) if(key!="_name") t[key]=seed[key];
        t.enableShoot=true;_root.物品栏={装备栏:inventoryFor(t.__sourceFixture)};
        return t;
    }
    private static function initialize(t:Object,defer:Boolean):Object {
        var scope:Object=PlayerStatRefreshCoordinator.beginOuterInitialization(t,null);
        PlayerStatRefreshCoordinator.activateInitialization(t);
        PlayerStatRefreshCoordinator.prepareFullNumeric(t,scope);
        if(!defer) PlayerStatRefreshCoordinator.finishOuterAfterState(t,"空手站立",scope);
        return scope;
    }
    public static function runAllTests():Void {
        passed=failed=events=starts=0;var saved:Object={};var i:Number;
        for(i=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        var runApi:Object=StageRunSession;var originalAuthority:Function=runApi.getRunAuthority;
        var stageApi:Object=org.flashNight.arki.scene.StageManager;
        var oldManager:Object=stageApi.instance;
        var manager:Object=stageApi.getInstance();var managerState:Object={};
        var managerKeys:Array=["gameworld","currentStage","isActive","isFinished","isFailed","stageMode","stageInfoList"];
        for(i=0;i<managerKeys.length;i++) managerState[managerKeys[i]]=manager[managerKeys[i]];
        var probeMouse:MovieClip;
        try {
            _root.控制目标="stat-test";_root.存档系统={};_root.savePath="resource-bridge-memory";_root._saveExt={};
            _root.当前为战斗地图=true;_root.新出生=false;_root.佣兵个数限制=1;_root.主角被动技能={};_root.玩家信息界面={};
            _root.敌人函数={魔法伤害种类:["基础","电","热","冷","波","蚀","毒","冲","人类"]};
            _root.装备引用配置={刷新所有装扮:function(t:Object):Void {}};
            for(i=10;i<19;i++) _root[keys[i]]=0;
            run={outcome:"active",life:"alive"};runApi.getRunAuthority=authority;
            PlayerStatRefreshCoordinator.production().resetContext(_root.存档系统,String(_root.savePath),{});
            PlayerResourceTransferBridge.install();PlayerResourceTransferBridge.retire("test_begin");
            EventBus.getInstance().subscribe("SceneReady",onScene,null);
            var first:Object=makeWorld(0);var actor:MovieClip=makeActor();
            initialize(actor,false);
            check(events===0 && starts===0 && actor.__resourceSpawn.resourcesReady===true,"actor_ready_waits_for_scene_setup");
            PlayerResourceTransferBridge.finishStageSetup(first);
            check(events===1 && starts===1,"first_scene_publishes_once");
            actor.hp=900;actor.mp=0;
            var merc:MovieClip=world.createEmptyMovieClip("同伴0",world.getNextHighestDepth());
            merc.hp=42;merc.hp满血值=100;merc.mp=7;merc.用户ID="merc-1";merc.名字="Merc";
            // 原生回归工程使用 owning XFL 的原始淡出时间轴；普通 focused runner 使用同步替身。
            var fade:Object=_root.__resourceFadeProbe;
            if(fade==undefined) fade={_currentframe:5,
                gotoAndPlay:function(frame):Void {},gotoAndStop:function(frame):Void {},stop:function():Void {},
                淡出跳转帧:function(frame):Boolean {
                    if(this.__returnFadeActive===true) return false;
                    this.__returnFadeActive=true;this.跳转帧=frame;return true;
                }};
            trace("ResourceFadeFixture: "+(_root.__resourceFadeProbe==undefined ? "memory" : "authored_timeline"));
            _root.淡出动画=fade;
            // 生产 wuxianguotu_1.swf 门中的原调用序列，没有经过 Bridge。
            fade.跳转帧="wuxianguotu_1";
            fade.gotoAndPlay(2);fade.淡出跳转帧("wuxianguotu_1");fade.stop();
            var legacyTicket:Object=SceneTransitionGuard.captureCleanup();
            check(PlayerResourceTransferBridge.captureCleanup(legacyTicket,world,0)===false,"legacy_arrow_reproduces_rejection");
            check(PlayerResourceTransferBridge.cleanupFailureDetail()=="capture_intent_mismatch:missing","legacy_arrow_missing_intent_identified");
            check(PlayerResourceTransferBridge.cleanupFailureReason()=="resource_identity_invalid","identity_failure_not_reported_as_bad_hp");
            fade.__returnFadeActive=false;fade.跳转中=false;fade.gotoAndStop("空");
            manager.gameworld=world;manager.currentStage=0;manager.isActive=true;
            manager.isFinished=false;manager.isFailed=false;manager.stageMode="action";manager.stageInfoList=[{},{}];
            first.manager=manager;
            var door:MovieClip=hitClip(world,"门1");actor.area=hitClip(actor,"area");
            probeMouse=hitClip(_root,"__resourceProbeMouse");_root.鼠标=probeMouse;
            _root.全鼠标控制=true;_root.转场景记录数据=function():Void {};
            manager.bindStageExit(world);
            var boundExit:Function=door.切换场景;
            door.被点击=true;world.允许通行=false;
            door.切换场景("出生地","wuxianguotu_1","","右");
            check(fade.__returnFadeActive===false,"closed_exit_does_not_start_fade");
            world.允许通行=true;door.被点击=false;
            door.切换场景("出生地","wuxianguotu_1","","右");
            check(fade.__returnFadeActive===false,"mouse_exit_requires_click");
            // AVM1 Key.isDown 原生成员拒绝替换；四方向映射由独立源码端口回归，不伪装原生按键。
            trace("ResourceKeyboardEvidence: source_fixture_only");
            door.被点击=true;
            door.切换场景("出生地","other-scene","","右");
            check(fade.__returnFadeActive===false,"exit_rejects_wrong_destination");
            probeMouse._x=100;
            door.切换场景("出生地","wuxianguotu_1","","右");
            check(fade.__returnFadeActive===false,"mouse_must_hit_authored_door");
            probeMouse._x=0;actor._x=100;
            door.切换场景("出生地","wuxianguotu_1","","右");
            check(fade.__returnFadeActive===false,"actor_must_hit_authored_door");
            actor._x=0;actor.hp=0;
            door.切换场景("出生地","wuxianguotu_1","","右");
            check(fade.__returnFadeActive===false,"dead_actor_cannot_request_exit");
            var oldHpMax:Number=actor.hp满血值;var oldMpMax:Number=actor.mp满血值;
            actor.hp=4092;actor.hp满血值=2918;actor.mp=3236;actor.mp满血值=3321;
            door.切换场景("出生地","wuxianguotu_1","","右");fade.stop();
            check(fade.__returnFadeActive===true,"bound_arrow_reaches_actual_next_stage");
            var fadeTicket:Object=SceneTransitionGuard.captureCleanup();
            check(PlayerResourceTransferBridge.captureCleanup(fadeTicket,world,1)===false,"wrong_source_stage_still_rejected");
            check(PlayerResourceTransferBridge.cleanupFailureDetail()=="capture_intent_mismatch:source_stage","source_stage_failure_identified");
            var capturedFade:Object=PlayerResourceTransferBridge.captureCleanup(fadeTicket,world,manager.currentStage);
            check(capturedFade===fadeTicket,"bound_arrow_cleanup_admits_overflow_hp");
            check(actor.hp===4092 && actor.mp===3236,"admission_does_not_refill_or_clamp_resources");
            PlayerResourceTransferBridge.abortCleanup(fadeTicket);
            fade.__returnFadeActive=false;fade.跳转中=false;fade.gotoAndStop("空");
            door.切换场景("出生地","wuxianguotu_1","","右");fade.stop();
            var retryTicket:Object=SceneTransitionGuard.captureCleanup();
            check(retryTicket!==fadeTicket && PlayerResourceTransferBridge.captureCleanup(retryTicket,world,0)===retryTicket,"new_arrow_attempt_after_cleanup_abort");
            PlayerResourceTransferBridge.abortCleanup(retryTicket);
            fade.__returnFadeActive=false;fade.跳转中=false;fade.gotoAndStop("空");
            actor.hp=900;actor.mp=0;actor.hp满血值=oldHpMax;actor.mp满血值=oldMpMax;
            _root.淡出动画={跳转帧:"wuxianguotu_1",_currentframe:5};
            check(PlayerResourceTransferBridge.recordAdmittedDoor("wuxianguotu_1"),"door_intent_admitted");
            var ticket:Object=SceneTransitionGuard.captureCleanup();
            var captured:Object=PlayerResourceTransferBridge.captureCleanup(ticket,world,0);
            check(captured===ticket,"cleanup_final_sample_admitted");
            actor.hp=999;actor.mp=333; // 已采样之后的无关写不改变私有候选。
            PlayerResourceTransferBridge.commitCleanup(captured);
            var second:Object=makeWorld(1);actor=makeActor();
            var outer:Object=initialize(actor,true);
            PlayerResourceTransferBridge.finishStageSetup(second);
            check(events===1 && starts===1 && actor.__resourceSpawn.resourcesReady!==true,"deferred_template_blocks_start");
            PlayerStatRefreshCoordinator.finishOuterAfterState(actor,"空手站立",outer);
            check(actor.hp===900 && actor.mp===0,"final_outer_tail_restores_pair");
            check(events===2 && starts===2 && observedHp===900 && observedMp===0,"scene_consumers_see_final_pair");
            PlayerResourceTransferBridge.finishStageSetup(second);PlayerResourceTransferBridge.actorReady(actor);
            check(events===2 && starts===2,"duplicate_completions_do_not_publish");
            var params:Object={是否为佣兵:true,佣兵是否出战信息id:0,用户ID:"merc-1",名字:"Merc"};
            PlayerResourceTransferBridge.prepareSpawn("主角-男","同伴0",params);
            merc=world.createEmptyMovieClip("同伴0",world.getNextHighestDepth());
            for(var key:String in params) merc[key]=params[key];
            merc.hp=100;merc.hp满血值=100;merc.mp=35;merc.mp满血值=50;
            PlayerResourceTransferBridge.finishResources(merc,null);
            check(merc.hp===42 && merc.mp===35,"merc_deferred_hp_only");
            PlayerResourceTransferBridge.finishResources(merc,null);
            check(merc.hp===42 && merc.mp===35,"merc_one_shot");
            actor.hp=800;actor.mp=10;
            PlayerResourceTransferBridge.actorReady(actor);
            check(PlayerResourceTransferBridge.isReady(second) && events===2,"later_damage_does_not_replay_spawn_completion");
            // 实际 life authority 方法，内存 run/缓存端口；不调用扣币或存档入口。
            var oldLifeRun:Object=runApi._run;var oldReturnRequested=runApi._returnRequested;
            var targetCache:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
            var oldFindHero:Function=targetCache.findHero;
            runApi._run=run;runApi._returnRequested=false;
            targetCache.findHero=function():MovieClip {return _root.gameworld[_root.控制目标];};
            try {
                for(var revivalIndex:Number=0;revivalIndex<2;revivalIndex++) {
                    var beforeDeath:Object=world.__resourceReadyGate;
                    var beforeSpawn:Object=actor.__resourceSpawn;
                    _root.淡出动画={跳转帧:"wuxianguotu_1",_currentframe:5};
                    PlayerResourceTransferBridge.recordAdmittedDoor("wuxianguotu_1");
                    var deathTicket:Object=SceneTransitionGuard.captureCleanup();
                    actor.hp=0;StageRunSession.onHeroDeath();
                    check(run.life=="dead" && !PlayerResourceTransferBridge.isCurrent(beforeDeath),"death_revokes_prior_gate_"+revivalIndex);
                    actor.hp=2918;actor.hp满血值=2918;actor.mp=3321;actor.mp满血值=3321;
                    if(revivalIndex==0) {
                        check(!PlayerResourceTransferBridge.onHeroRespawn(actor),"unconfirmed_life_cannot_resume_resources");
                        run.life="alive";actor.mp=Number.NaN;
                        check(!PlayerResourceTransferBridge.onHeroRespawn(actor),"invalid_revived_resources_rejected");
                        actor.mp=3321;var originalBody:Object=actor.__playerStatBody;actor.__playerStatBody={};
                        check(!PlayerResourceTransferBridge.onHeroRespawn(actor),"revival_rejects_replaced_body");
                        actor.__playerStatBody=originalBody;var originalWorldIdentity:Object=world.__stageReturnWorldIdentity;world.__stageReturnWorldIdentity={};
                        check(!PlayerResourceTransferBridge.onHeroRespawn(actor),"revival_rejects_replaced_world");
                        world.__stageReturnWorldIdentity=originalWorldIdentity;
                        check(!PlayerResourceTransferBridge.onHeroRespawn(merc),"companion_cannot_resume_hero_resources");
                        run.life="dead";
                        // 模拟一次未成功的复活请求；保留同一次死亡 owner，不能恢复旧 generation。
                        PlayerResourceTransferBridge.retire("hero_dead");
                    }
                    StageRunSession.onHeroRespawn(actor);
                    check(run.life=="alive","real_respawn_authority_restores_life_"+revivalIndex);
                    var renewed:Object=world.__resourceReadyGate;
                    check(renewed!==beforeDeath && PlayerResourceTransferBridge.isReady(renewed),"revival_renews_ready_gate_"+revivalIndex);
                    check(actor.__resourceSpawn!==beforeSpawn && actor.__resourceActorIdentity!==beforeSpawn.identity,"revival_renews_actor_identity_"+revivalIndex);
                    check(!PlayerResourceTransferBridge.isCurrent(beforeDeath),"old_ready_gate_stays_retired_"+revivalIndex);
                    check(events===2 && starts===2 && actor.hp===2918 && actor.mp===3321,"revival_does_not_replay_scene_or_resources_"+revivalIndex);
                    check(PlayerResourceTransferBridge.captureCleanup(deathTicket,world,1)===false,"predeath_cleanup_intent_stays_invalid_"+revivalIndex);
                    StageRunSession.onHeroRespawn(actor);
                    check(world.__resourceReadyGate===renewed,"duplicate_respawn_keeps_current_gate_"+revivalIndex);
                    second=renewed;
                }
                actor.hp=1344;actor.mp=3321;
                _root.淡出动画={跳转帧:"wuxianguotu_1",_currentframe:5};
                PlayerResourceTransferBridge.recordAdmittedDoor("wuxianguotu_1");
                var revivedTicket:Object=SceneTransitionGuard.captureCleanup();
                var revivedCapture:Object=PlayerResourceTransferBridge.captureCleanup(revivedTicket,world,1);
                check(revivedCapture===revivedTicket,"second_transition_after_two_revivals_admitted");
                if(revivedCapture===revivedTicket) PlayerResourceTransferBridge.abortCleanup(revivedTicket);
            } finally {
                runApi._run=oldLifeRun;runApi._returnRequested=oldReturnRequested;targetCache.findHero=oldFindHero;
            }
            var newDoor:MovieClip=hitClip(world,"门1");world.允许通行=true;
            manager.gameworld=world;manager.currentStage=1;
            _root.淡出动画={_currentframe:5};
            boundExit.call(newDoor,"出生地","wuxianguotu_1","","右");
            check(_root.淡出动画.跳转帧==undefined,"old_exit_closure_cannot_target_replacement_world");
            _root.淡出动画={跳转帧:"wuxianguotu_1",_currentframe:5};
            check(PlayerResourceTransferBridge.recordAdmittedDoor("wuxianguotu_1"),"numeric_rejection_intent_admitted");
            actor.mp=Number.NaN;
            var invalidTicket:Object=SceneTransitionGuard.captureCleanup();
            check(PlayerResourceTransferBridge.captureCleanup(invalidTicket,world,1)===false,"nan_mp_still_blocks_teardown");
            check(PlayerResourceTransferBridge.cleanupFailureReason()=="resource_invalid","numeric_failure_keeps_numeric_message");
            // B 复活后继续 C、D；每次都用本图最终资源重新采样，不重放 A 的旧值。
            actor.hp=1344;actor.mp=3321;
            for(var nextIndex:Number=2;nextIndex<=3;nextIndex++) {
                var sourceHp:Number=actor.hp;var sourceMp:Number=actor.mp;
                var sourceMaxHp:Number=actor.hp满血值;var sourceMaxMp:Number=actor.mp满血值;
                _root.淡出动画={跳转帧:"wuxianguotu_1",_currentframe:5};
                check(PlayerResourceTransferBridge.recordAdmittedDoor("wuxianguotu_1"),"revived_chain_intent_"+nextIndex);
                var chainTicket:Object=SceneTransitionGuard.captureCleanup();
                check(PlayerResourceTransferBridge.captureCleanup(chainTicket,world,nextIndex-1)===chainTicket,"revived_chain_capture_"+nextIndex);
                PlayerResourceTransferBridge.commitCleanup(chainTicket);
                second=makeWorld(nextIndex);actor=makeActor();initialize(actor,false);
                PlayerResourceTransferBridge.finishStageSetup(second);
                var transferApi:Object=org.flashNight.arki.scene.PlayerResourceTransfer;
                check(actor.hp===transferApi.project(sourceHp,sourceMaxHp,actor.hp满血值,undefined)
                    && actor.mp===transferApi.project(sourceMp,sourceMaxMp,actor.mp满血值,undefined),"revived_chain_final_resources_"+nextIndex);
                check(PlayerResourceTransferBridge.isReady(second) && events===nextIndex+1 && starts===nextIndex+1,"revived_chain_ready_once_"+nextIndex);
                actor.hp=450;actor.mp=0;
            }
            // 换档会真实重置 production context；反例必须在成功链完成后独立收口。
            PlayerResourceTransferBridge.retire("hero_dead");
            _root.savePath="foreign-slot";
            check(!PlayerResourceTransferBridge.onHeroRespawn(actor),"revival_rejects_slot_change");
            PlayerResourceTransferBridge.retire("return_started");
            check(!PlayerResourceTransferBridge.isCurrent(second),"return_revokes_ready_generation");
            // 存档 context 改变后，旧 ready/cleanup 回调不能放行或写入另一角色。
            PlayerStatRefreshCoordinator.production().resetContext(_root.存档系统,"replacement-context",{});
            check(!PlayerResourceTransferBridge.isCurrent(second),"context_replacement_rejects_gate");
            PlayerResourceTransferBridge.actorReady(actor);check(events===4,"stale_ready_silent");
        } catch(error) {check(false,"exception "+error);}
        finally {
            EventBus.getInstance().unsubscribe("SceneReady",onScene,null);
            runApi.getRunAuthority=originalAuthority;
            for(i=0;i<managerKeys.length;i++) manager[managerKeys[i]]=managerState[managerKeys[i]];
            stageApi.instance=oldManager;
            if(probeMouse!=undefined) probeMouse.removeMovieClip();
            PlayerResourceTransferBridge.retire("test_finished");
            PlayerStatRefreshCoordinator.production().resetContext(null,"finished",null);
            if(world!=undefined) world.removeMovieClip();
            for(i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        trace("PlayerResourceTransferBridgeTest Tests Passed: "+passed);
        trace("PlayerResourceTransferBridgeTest Tests Failed: "+failed);
    }
}
