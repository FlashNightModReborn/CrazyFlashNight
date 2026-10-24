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
        "经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成","主角是否在地上"];
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
        try { setup(); runJointCase(); }
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
        // Keep the case to plain long guns: no equipment lifecycle scripts or special build traits.
        var equipment:Object=_root.物品栏.装备栏;
        for(key in equipment.items) delete equipment.items[key];
        var gun0:Object=fixture.equipment("整合长枪A",1,"",[],1);
        var gun1:Object=fixture.equipment("整合长枪B",1,"",[],2);
        var gun2:Object=fixture.equipment("整合长枪C",1,"",[],3);
        equipment.items.长枪=gun0;_root.物品栏.背包.items["0"]=gun1;_root.物品栏.背包.items["1"]=gun2;
        installGun(seed,gun0.name,40);installGun(seed,gun1.name,60);installGun(seed,gun2.name,80);
        coordinator=PlayerStatRefreshCoordinator.production();
        coordinator.resetContext(_root.存档系统,String(_root.savePath),_root._saveExt);
        _root.__statCoordinatorForTests=coordinator;
        fixture.__activeMutationRoot=_root;
        callbacks=fixture.protocolCallbacks(_root,false,true);
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
