import org.flashNight.arki.item.CharacterBuildService;
import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.component.Collider.IColliderFactory;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/**
 * Joint seam: real CharacterBuild owner + production stat adapter + the unmodified
 * player-template refresh function included by the runner. No manual body/ready writes.
 * Peripheral substitutes: in-memory inventory/catalog/save and Web DTO callbacks; no running AI,
 * firing, scheduler ticks, audio or paper-doll renderer. Real blank MovieClips exercise
 * native gotoAndStop + RoutingIntent, but do not represent an authored character timeline.
 * Empty legacy Buff methods model a zero-buff actor; modern BuffManager/dispatcher,
 * colliders, depth manager, numeric projection and all completion proofs stay production.
 */
class org.flashNight.arki.item.CharacterBuildProductionLifecycleTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var world:MovieClip;
    private static var hero:MovieClip;
    private static var coordinator:Object;
    private static var fixture:Object;
    private static var phase:String;
    private static var callbacks:Object;
    private static var rootKeys:Array=["gameworld","控制目标","物品栏","存档系统","savePath","_saveExt",
        "性别","脸型","发型","等级","getItemData","itemCatalog","itemUses","_webPanelPauseLease",
        "快捷物品栏键1","快捷物品栏键2","快捷物品栏键3","快捷物品栏键4","药剂组切换键","keyshow",
        "__statCoordinatorForTests","帧计时器","装备引用配置","UI系统","玩家信息界面","敌人函数",
        "主角被动技能","暂停","当前为战斗地图","最大等级","当前玩家总数","发布消息","服务器",
        "全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成",
        "经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成","主角是否在地上","server"];
    private static function check(value:Boolean, label:String):Boolean {
        if(value) {passed++;trace("[PASS] CharacterBuildProductionLifecycle: "+label);}
        else {failed++;trace("[FAIL] CharacterBuildProductionLifecycle: "+label);}
        return value;
    }
    private static function noOp():Void {}
    private static function taskId():Number {return 1;}
    public static function runAllTests():Void {
        passed=failed=0;phase="setup";
        var saved:Object={};var i:Number;
        for(i=0;i<rootKeys.length;i++) saved[rootKeys[i]]=_root[rootKeys[i]];
        var oldDepth:DepthManager=DepthManager.instance;
        var oldFactory:IColliderFactory=StaticInitializer.factory;
        fixture=org.flashNight.arki.item.CharacterBuildServiceTest;
        try {
            setup(); runJointCase(); if(failed==0) runMultiSlotCase();
            var modes:Array=["ready","timeout","stale"];
            for(i=0;i<modes.length && failed==0;i++) {
                CharacterBuildService.testOnlyReset();
                coordinator.resetContext(null,"fixture_between_cases",null);
                DepthManager.instance.dispose();world.removeMovieClip();
                setup();runModeWaitCase(modes[i]);
            }
        }
        catch(error) {diagnostic("exception",{error:String(error.message==undefined ? error : error.message)});check(false,"exception in "+phase);}
        finally {
            CharacterBuildService.testOnlyReset();
            if(coordinator!=null) coordinator.resetContext(null,"fixture_finished",null);
            if(world!=undefined) world.removeMovieClip();
            if(DepthManager.instance!=null && DepthManager.instance!==oldDepth) DepthManager.instance.dispose();
            DepthManager.instance=oldDepth;StaticInitializer.factory=oldFactory;
            for(i=0;i<rootKeys.length;i++) _root[rootKeys[i]]=saved[rootKeys[i]];
        }
        trace("CharacterBuildProductionLifecycleTest Tests Passed: "+passed);
        trace("CharacterBuildProductionLifecycleTest Tests Failed: "+failed);
    }
    private static function setup():Void {
        var seed:Object=fixture.fixtureRoot(1);
        // Reuse only the established in-memory domain ports. Never adopt its fake rebuild or adapter.
        var copy:Array=["物品栏","存档系统","_saveExt","性别","脸型","发型","等级","getItemData","itemCatalog","itemUses",
            "_webPanelPauseLease","快捷物品栏键1","快捷物品栏键2","快捷物品栏键3","快捷物品栏键4","药剂组切换键","keyshow"];
        for(var i:Number=0;i<copy.length;i++) _root[copy[i]]=seed[copy[i]];
        _root.savePath="isolated-character-production-fixture";
        _root.暂停=true;_root.当前为战斗地图=true;_root.当前玩家总数=1;_root.最大等级=60;
        _root.控制目标="fixtureHero";_root.主角被动技能={};
        var bonusKeys:Array=["全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成",
            "经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成"];
        for(i=0;i<bonusKeys.length;i++) _root[bonusKeys[i]]=0;
        _root.发布消息=noOp;_root.服务器={发布服务器消息:noOp};
        // Rendering and scheduling ports are inert; all stat/dispatcher/BuffManager work stays real.
        _root.帧计时器={当前帧数:100,添加单次任务:taskId,添加任务:taskId,添加循环任务:taskId,
            添加冷却任务:taskId,移除任务:noOp,移除生命周期任务:noOp,
            taskManager:{addLifecycleTask:taskId,removeTask:noOp},
            unitUpdateWheel:{add:taskId,remove:noOp}};
        _root.装备引用配置={刷新所有装扮:noOp};
        _root.UI系统={iconBar:{initialize:noOp}};
        _root.玩家信息界面={刷新攻击模式:noOp,刷新hp显示:noOp,刷新mp显示:noOp};
        _root.敌人函数={魔法伤害种类:["基础","电","热","冷","波","蚀","毒","冲","人类"]};
        world=_root.createEmptyMovieClip("__characterProductionWorld",_root.getNextHighestDepth());
        _root.gameworld=world;world.dispatcher=new LifecycleEventDispatcher(world);
        DepthManager.instance=new DepthManager(world,0,1048575,32);DepthManager.instance.calibrate(-100,500);
        StaticInitializer.factory=new AABBColliderFactory(1);
        hero=world.createEmptyMovieClip(_root.控制目标,world.getNextHighestDepth());
        var base:Object=org.flashNight.arki.unit.PlayerStatProjectionTest.fixture();
        for(var key:String in base) if(key!="_name" && key!="area" && typeof base[key]!="function") hero[key]=base[key];
        // Real player-template methods, including actual passive/weapon/lifecycle functions.
        for(key in _root.主角函数) if(typeof _root.主角函数[key]=="function") hero[key]=_root.主角函数[key];
        hero.名字="isolated Andy";hero.兵种="主角-男";hero.性别="男";hero.是否为敌人=false;
        hero.状态="空手站立";hero.攻击模式="空手";hero.方向="右";hero.速度_min=30;hero.速度_max=40;
        hero.hp=600;hero.hp满血值=1000;hero.mp=200;hero.mp满血值=500;
        hero.被动技能={};hero.label={};hero.unitAI={};hero.buff={初始:noOp,更新:noOp,赋值:noOp,删除:noOp};
        hero.createEmptyMovieClip("man",1);hero.createEmptyMovieClip("新版人物文字信息",2);
        var area:MovieClip=hero.createEmptyMovieClip("area",3);
        area.beginFill(0,0);area.moveTo(-10,-50);area.lineTo(10,-50);area.lineTo(10,0);area.lineTo(-10,0);area.endFill();
        // Plain items isolate the real shared lifecycle from item-specific scripts.
        var equipment:Object=_root.物品栏.装备栏;
        for(key in equipment.items) delete equipment.items[key];
        var gun0:Object=fixture.equipment("整合长枪A",1,"",[],1);
        var gun1:Object=fixture.equipment("整合长枪B",1,"",[],2);
        var gun2:Object=fixture.equipment("整合长枪C",1,"",[],3);
        equipment.items.长枪=gun0;_root.物品栏.背包.items["0"]=gun1;_root.物品栏.背包.items["1"]=gun2;
        installGun(seed,gun0.name,40);installGun(seed,gun1.name,60);installGun(seed,gun2.name,80);
        var helmet:Object=fixture.equipment("整合头盔",1,"",[],4);
        equipment.items.头部装备=helmet;
        fixture.setCatalogData(seed,helmet.name,{type:"防具",use:"头部装备",data:{level:1,weight:1,hp:0,defence:0}});
        var sequenceSlots:Array=["上装装备","下装装备","手部装备","脚部装备","刀","手枪","长枪"];
        for(i=0;i<sequenceSlots.length;i++) {
            var slot:String=sequenceSlots[i];var item:Object=fixture.equipment("连续换装"+slot,1,"",[],i+5);
            _root.物品栏.背包.items[String(i+2)]=item;
            fixture.setCatalogData(seed,item.name,{type:i<4 ? "防具" : "武器",use:slot,actiontype:"普通",
                data:{level:1,weight:1,hp:0,defence:0,power:30,capacity:20,interval:120,
                    velocity:20,split:1,bullet:"普通子弹",diffusion:0,damage:0,gunpower:0}});
        }
        coordinator=PlayerStatRefreshCoordinator.production();
        coordinator.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
        _root.__statCoordinatorForTests=coordinator;
        fixture.__activeMutationRoot=_root;
        callbacks=fixture.writerPersistenceCallbacks(_root);
        CharacterBuildService.testOnlyUseRoot(_root);CharacterBuildService.testOnlyUseCallbacks(callbacks);
    }
    private static function installGun(seed:Object,name:String,power:Number):Void {
        var data:Object={type:"武器",use:"长枪",actiontype:"普通",data:{level:1,power:power,capacity:20,
            interval:120,velocity:20,split:1,weight:2,bullet:"普通子弹",diffusion:0,damage:0,gunpower:0}};
        fixture.setCatalogData(seed,name,data);
    }
    private static function runJointCase():Void {
        phase="initial_real_refresh";
        check(typeof _root.刷新人物装扮=="function","production refresh loaded from direct template include");
        _root.刷新人物装扮(hero._name);
        diagnostic("baseline",null);
        if(!check(hero.__playerStatBody!=null && hero.__playerStatFullReady===hero.__playerStatBody
                && hero.__playerStatInitializing===false,"initial fullReady produced by real full template")) return;
        var baseline:Object=coordinator.flush("joint_baseline");
        if(!check(baseline.status=="applied" || baseline.status=="unchanged","production numeric baseline settled")) return;
        phase="open";
        var panel:String="workbench.production.lifecycle";
        var opened:Object=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
        diagnostic("opened",opened);
        if(!check(opened.success===true,"real CharacterBuild snapshot admits production-ready actor")) return;
        phase="first_mutation";
        var first:Object=CharacterBuildService.execute("equipEquipment",fixture.equipmentMutationParams("equipEquipment",panel,opened,"长枪",0));
        diagnostic("first_mutation",first);
        if(!check(first.success===true && first.changed===true && first.loadoutRevision==1,"first exact longgun mutation")) return;
        phase="second_mutation";
        var secondParams:Object=fixture.equipmentMutationParams("equipEquipment",panel,first,"长枪",1);
        secondParams.requestCallId=panel+".equip.second";
        var second:Object=CharacterBuildService.execute("equipEquipment",secondParams);
        diagnostic("second_mutation",second);
        if(!check(second.success===true && second.changed===true && second.loadoutRevision==2,"second exact longgun mutation")) return;
        phase="finalize";
        _root.帧计时器.当前帧数++;
        var result:Object=CharacterBuildService.finalize(second.sessionGeneration,second.loadoutRevision,false);
        diagnostic("finalize",result);
        check(result.success===true,"two committed longgun mutations finalize through real complete lifecycle");
        check(_root.savePath=="isolated-character-production-fixture","save owner remains in the isolated in-memory fixture");
    }
    private static function runMultiSlotCase():Void {
        phase="field_sequence_open";
        var panel:String="workbench.production.field-sequence";
        var current:Object=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
        if(!check(current.success===true,"multi-slot sequence opens a fresh exact session")) return;
        var slots:Array=["头部装备","上装装备","下装装备","手部装备","脚部装备","长枪","刀","手枪"];
        var sources:Array=[null,2,3,4,5,8,6,7];
        for(var i:Number=0;i<slots.length;i++) {
            phase="field_sequence_mutation_"+i;
            var command:String=i==0 ? "unequipEquipment" : "equipEquipment";
            var params:Object=fixture.equipmentMutationParams(command,panel,current,slots[i],sources[i]);
            params.requestCallId=panel+".mutation."+i;
            current=CharacterBuildService.execute(command,params);
            diagnostic(phase,current);
            if(!check(current.success===true && current.changed===true && current.loadoutRevision==i+1,
                "head removal and sequential armor/weapon mutation "+i)) return;
        }
        phase="field_sequence_finalize";
        _root.帧计时器.当前帧数++;
        var result:Object=CharacterBuildService.finalize(current.sessionGeneration,current.loadoutRevision,false);
        diagnostic("field_sequence_finalize",result);
        check(result.success===true && result.closed===true && result.loadoutRevision==8
            && result.liveRevision==8 && result.liveRefreshDirty===false && result.persistence.success===true,
            "eight committed equipment changes finish through the real complete lifecycle");
        check(hero.hp==600 && hero.mp==200,"multi-slot close preserves current HP and MP");
        check(_root.savePath=="isolated-character-production-fixture","multi-slot case never adopts a player save");
    }
    /** The renderer is inert here: only this component receipt is simulated.
     * The actual owner, rebuild, final barriers and persistence count stay real. */
    private static function runModeWaitCase(mode:String):Void {
        phase="mode_wait_"+mode;
        _root.刷新人物装扮(hero._name);coordinator.flush("mode_wait_baseline");
        var item:Object=fixture.equipment("dominator",1,"",[],20);
        _root.物品栏.背包.items["9"]=item;
        fixture.setCatalogData(_root,item.name,{type:"武器",use:"手枪",actiontype:"普通",
            data:{level:1,weight:1,power:30,capacity:20,interval:120,velocity:20,
                split:1,bullet:"普通子弹",diffusion:0,damage:0,gunpower:0}});
        var panel:String="workbench.mode-wait."+mode;
        var opened:Object=CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".open"));
        if(!check(opened.success===true,mode+" opens before Dominator mutation")) return;
        var changed:Object=CharacterBuildService.execute("equipEquipment",
            fixture.equipmentMutationParams("equipEquipment",panel,opened,"手枪",9));
        if(!check(changed.success===true && changed.changed===true,mode+" equips Dominator")) return;
        var params:Object=fixture.wireParams(panel,panel+".finalize");
        params.sessionGeneration=changed.sessionGeneration;params.expectedLoadoutRevision=changed.loadoutRevision;
        var replies:Array=[];var codec:LiteJSON=new LiteJSON();
        _root.server={sendSocketMessage:function(message:String):Boolean {replies.push(codec.parse(message));return true;}};
        var api:Object=org.flashNight.arki.item.CharacterBuildService;
        api.handle("finalize",params);
        var ticket:Object=api._statTicket;var body:Object=hero.__playerStatBody;
        diagnostic("mode_wait_"+mode,null);
        if(!check(api._modeFinalizeWait!=null && coordinator.awaitingEquipmentComponent(ticket)
                && replies.length==0 && callbacks.state.saveCalls==0,
                mode+" defers response and persistence for the original component")) return;
        api.pollModeFinalization();
        check(replies.length==0 && hero.__playerStatBody===body && callbacks.state.saveCalls==0,
            mode+" repeated wait neither rebuilds nor saves");
        check(CharacterBuildService.execute("snapshot",fixture.wireParams(panel,panel+".busy")).error=="write_busy",
            mode+" cannot replace the active session during wait");
        if(mode=="ready") {
            hero.变形手枪={属性投影身体:{}};
            PlayerStatRefreshCoordinator.notifyModeComponentReady(hero,hero.变形手枪.属性投影身体);
            check(coordinator.awaitingEquipmentComponent(ticket),"stale component receipt cannot finish current body");
            hero.变形手枪.属性投影身体=body;
            PlayerStatRefreshCoordinator.notifyModeComponentReady(hero,body);
        } else if(mode=="timeout") api._modeFinalizeWait.deadline=0;
        else coordinator.resetContext(_root.存档系统,"replacement_context",_root._saveExt);
        api.pollModeFinalization();api.pollModeFinalization();
        trace("CHARACTER_MODE_WAIT_RESULT "+codec.stringifySafe({mode:mode,reply:replies[0],
            saveCalls:callbacks.state.saveCalls,dirty:_root.存档系统.dirtyMark,
            ticketStatus:ticket.status,planStage:hero.__playerStatInitPlan.stage}));
        check(api._modeFinalizeWait==null && replies.length==1,mode+" produces one terminal reply");
        if(mode=="ready") {
            check(replies[0].success===true && replies[0].closed===true && callbacks.state.saveCalls==1,
                "actual ready receipt finalizes once with one persistence call");
            check(hero.__playerStatBody===body && hero.hp==600 && hero.mp==200,
                "component completion preserves body HP and MP");
        } else check(replies[0].success===false && replies[0].error==(mode=="timeout" ? "flush_failed" : "stale_session")
                && callbacks.state.saveCalls==0,mode+" remains a known failure without persistence");
        if(mode=="timeout") {
            check(hero.__playerStatBody===body,"timeout alone cannot rebuild the body");
            params.recoverProjection=true;params.requestCallId=panel+".recover";
            api.handle("finalize",params);
            var retryBody:Object=hero.__playerStatBody;
            check(api._modeFinalizeWait!=null && retryBody!==body && replies.length==1 && callbacks.state.saveCalls==0,
                "explicit recovery after known timeout rebuilds once and still waits before saving");
            hero.变形手枪={属性投影身体:body};
            PlayerStatRefreshCoordinator.notifyModeComponentReady(hero,body);
            api.pollModeFinalization();
            check(replies.length==1,"old component cannot complete recovered body");
            hero.变形手枪.属性投影身体=retryBody;
            PlayerStatRefreshCoordinator.notifyModeComponentReady(hero,retryBody);
            api.pollModeFinalization();
            check(replies.length==2 && replies[1].success===true && callbacks.state.saveCalls==1,
                "explicit recovery persists only after its own component receipt");
        }
    }
    private static function diagnostic(label:String,result:Object):Void {
        var api:Object=org.flashNight.arki.item.CharacterBuildService;
        var ticket:Object=api._statTicket;
        var plan:Object=hero.__playerStatInitPlan;
        var d:Object=coordinator==null ? {} : coordinator.diagnostics();
        var record:Object={label:label,phase:phase,success:result.success,error:result.error,
            coordinatorStatus:d.status,reason:d.reason,stage:d.stage,dirtyMask:d.dirtyMask,
            ticketStatus:ticket.status,planOpen:plan.open,planStage:plan.stage,planFailed:plan.failed,
            tailStage:plan.tailCheckpoint.stage,initializing:hero.__playerStatInitializing,
            fullReady:hero.__playerStatFullReady!=null && hero.__playerStatFullReady===hero.__playerStatBody,
            hasDressup:hero.hasDressup,hp:hero.hp,hpMax:hero.hp满血值,mp:hero.mp,mpMax:hero.mp满血值};
        var codec:LiteJSON=new LiteJSON();trace("CHARACTER_PRODUCTION_LIFECYCLE "+codec.stringifySafe(record));
    }
}
