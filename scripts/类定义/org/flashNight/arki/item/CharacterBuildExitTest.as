import org.flashNight.arki.item.CharacterBuildService;
import org.flashNight.arki.item.DrugSlotAffinityService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.neur.Server.SaveManager;

/** Runs after the production player template fails its numeric projection. */
class org.flashNight.arki.item.CharacterBuildExitTest {
    private static var serial:Number;
    private static function serialize(container:Object):Object {
        var out:Object={};
        for (var key:String in container.items) {
            var item:Object=container.items[key];
            out[key]={name:item.name,value:item.value,lastUpdate:item.lastUpdate};
        }
        return out;
    }

    public static function setup():Void {
        _root.savePath="cf7_agent_i334_lifecycle_"+new Date().getTime();
        _root.角色名="整备退出测试";
        _root.允许存档=true;
        _root.基础身价值=1000;_root.身高=175;_root.金钱=0;_root.虚拟币=0;_root.经验值=0;
        _root.技能点数=0;_root.键值设定=[];_root.玩家称号="";_root.difficultyMode=0;_root.easterEgg=false;
        _root.佣兵是否出战信息=[];_root.同伴数据=[];_root.同伴数=0;_root.主角技能表=[[]];_root.主线任务进度=0;
        _root.商城已购买物品=[];_root.商城购物车=[];_root.tasks_to_do=[];_root.tasks_finished={};_root.task_chains_progress={};
        _root.基建系统={infrastructure:{}};_root.宠物信息=[[],[],[],[],[]];_root.宠物领养限制=5;
        _root.UpdateTaskProgress=function() {};
        var inv:Object=_root.物品栏;
        // Start with a real catalog handgun. The swap leaves its original value in backpack slot 9.
        var originalGun:Object=inv.背包.items["7"];
        inv.装备栏.items["手枪"]=originalGun;
        delete inv.背包.items["7"];
        originalGun.value.shot=4;
        originalGun.value.reloadCount=3;
        inv.装备栏.toObject=inv.药剂栏.toObject=inv.背包.toObject=function() {return org.flashNight.arki.item.CharacterBuildExitTest.serialize(this);};
        inv.仓库=new ArrayInventory(null,10);
        inv.战备箱=new ArrayInventory(null,10);
        _root.收集品栏={材料:new DictCollection(null),情报:new DictCollection(null)};
        _root._saveExt.drugLoadout=DrugSlotAffinityService.previewNormalized(_root,inv.药剂栏).feature;
        serial=0;
    }

    private static function prepare(p:Object):Object {
        p.sequence=++serial;
        p.operationId="0123456789012345678901234567890"+String.fromCharCode(64+serial);
        p.phase="prepare";p.role="";p.context="";
        var response:Object=CharacterBuildService.persistedExit(p);
        p.role=response.role;p.context=response.context;
        return response;
    }

    public static function run(panel:String,changed:Object,failed:Object,check:Function):Void {
        var sm:SaveManager=SaveManager.getInstance(), internals:Object=sm;
        var p:Object={v:1,callId:1,panelInstanceId:panel,sessionGeneration:changed.sessionGeneration,writeEpoch:1,
            transportGeneration:17,loadoutRevision:changed.loadoutRevision,liveRevision:failed.liveRevision,
            drugRevision:changed.drugRevision,slot:_root.savePath};
        var originalLease=_root._webPanelPauseLease;
        var pauses:Object=org.flashNight.arki.pause.PauseManager;
        var otherLease:String=pauses.lease(true,"independent_exit_fixture");
        var gun:Object=_root.物品栏.装备栏.getItem("手枪").value;
        var store:SharedObject=SharedObject.getLocal(p.slot);
        var gym:Object=org.flashNight.arki.ui.GymTrainingPanelService;
        var loot:Object=org.flashNight.arki.scene.Cf6SoldierLoot;
        var ground:Object=org.flashNight.arki.scene.Cf6SoldierGroundPickup;
        var settingsClass:Object=SaveManager;
        var setting=settingsClass._settingsBootstrap,training=gym._session,operation=loot.operation,claim=ground.pending;
        var socket:Object=org.flashNight.neur.Server.ServerManager.getInstance();
        var send:Function=socket.sendServerMessage;
        socket.sendServerMessage=function(message:String) {
            if (message.indexOf("RewardCommit")>=0 || message.indexOf("SaveManager")>=0) trace("CHARACTER_EXIT_OWNER "+message);
        };
        try {
            var realSlot:String=p.slot;p.slot="cf7_agent_other";
            check(prepare(p).state=="blocked","wrong physical SOL blocked before write");
            p.slot=realSlot;
            var ext:Object=_root._saveExt;
            _root._saveExt={};
            check(prepare(p).state=="blocked","successor save owner cannot use the original panel");
            _root._saveExt=ext;
            var bag:Object=_root.物品栏.背包.items;
            var displaced=bag["9"];bag["9"]={name:"foreign-endpoint",value:1};
            check(prepare(p).state=="blocked","changed backpack half of an accepted swap blocks exit");
            if (displaced!=null) bag["9"]=displaced; else delete bag["9"];
            var oldAmmo:Object=displaced.value;
            var savedReload:Number=oldAmmo.reloadCount;
            oldAmmo.reloadCount=savedReload+1;
            check(prepare(p).state=="blocked","an unannounced reload of the displaced gun invalidates the accepted swap");
            oldAmmo.reloadCount=savedReload;
            var firstAffinity:Object=ext.drugLoadout.slots[0];
            ext.drugLoadout.slots[0]={itemKey:"exit-fixture-unmatched",lastDepletedSequence:-1};
            check(prepare(p).state=="blocked","drug affinity requiring repair prevents a terminal save");
            ext.drugLoadout.slots[0]=firstAffinity;
            settingsClass._settingsBootstrap={protocol:2,slot:realSlot,writeAdmission:"hold"};
            check(prepare(p).state=="blocked","settings owner hold prevents a terminal save");
            settingsClass._settingsBootstrap=setting;
            gym._session={phase:"save_pending",saveOwner:_root.存档系统,slotKey:realSlot,sourceExt:_root._saveExt};
            check(prepare(p).state=="blocked","gym unconfirmed growth prevents a terminal save");
            gym._session=training;
            loot.operation="cf6-partial-admission";
            check(prepare(p).state=="blocked","CF6 pending admission prevents a terminal save");
            loot.operation=operation;
            ground.pending={};
            check(prepare(p).state=="blocked","ground claim pending prevents a terminal save");
            ground.pending=claim;
            var scope:Object={ready:false};
            check(sm.beginRewardCommit("exit.fixture.reward",function() {return this.ready;},scope),
                "reward owner takes its original write");
            var rewardState:String=sm.commitRewardCandidate("exit.fixture.reward","reward.stash_take");
            trace("CHARACTER_EXIT_REWARD outcome="+rewardState+" phase="+internals._rewardCandidate.phase
                +" raw="+internals._rewardPhysicalResult+" exact="+internals._rewardCandidate.saveAttempt.rawConfirmed
                +" registered="+SaveManager.isRegisteredSaveReason("reward.stash_take"));
            check(rewardState=="pending" && internals._rewardCandidate.saveAttempt.rawConfirmed===true,
                "physical reward commit succeeded while its domain finalizer was held");
            check(prepare(p).state=="blocked","raw true of unresolved reward cannot authorize exit");
            scope.ready=true;
            check(sm.resolveRewardCommit("exit.fixture.reward")=="committed","original reward owner settles");
            var candidate:Object=prepare(p);
            var build:Object=CharacterBuildService;
            trace("CHARACTER_EXIT_ELIGIBLE state="+candidate.state+" core="+build.exitEligible(p)
                +" reward="+sm.hasRewardCommitPending()+" settings="+sm.settingsWriteAllowed());
            if (!check(candidate.state=="prepared","exact original failed projection is eligible after owners settle")) return;
            p.phase="persist";
            _root.UpdateTaskProgress=function() { gun.shot=99; };
            check(CharacterBuildService.persistedExit(p).state=="blocked" && gun.shot==11,
                "a late ammo callback during the physical save invalidates exit and cannot change shot");
            _root.UpdateTaskProgress=function() { oldAmmo.reloadCount=savedReload+1; };
            check(prepare(p).state=="prepared","displaced gun callback test prepares");
            p.phase="persist";
            check(CharacterBuildService.persistedExit(p).state=="blocked" && oldAmmo.reloadCount===savedReload,
                "a callback retaining the displaced gun cannot change its backpack ammunition");
            _root.UpdateTaskProgress=function() {
                var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
                api.commandDominatorMode({},null,"击杀模式",false);
            };
            check(prepare(p).state=="prepared","late weapon mode test prepares");
            p.phase="persist";
            check(CharacterBuildService.persistedExit(p).state=="blocked" && gun.shot==11,
                "a late mode callback invalidates the terminal image");
            _root.UpdateTaskProgress=function() { sm.markDirty(); };
            check(prepare(p).state=="prepared","safe retry is a fresh player intent after known rejection");
            p.phase="persist";
            check(CharacterBuildService.persistedExit(p).state=="blocked","late dirty generation prevents receipt");
            _root.UpdateTaskProgress=function() { _root._saveExt.lateWrite=334; };
            check(prepare(p).state=="prepared","known rejection returns control to the original session");
            p.phase="persist";
            check(CharacterBuildService.persistedExit(p).state=="blocked","an unmarked late extension write invalidates the image");
            _root.UpdateTaskProgress=function() {};
            sm._configureSaveFlowForTest({flushResult:false});
            check(prepare(p).state=="prepared","physical failure test prepares");
            p.phase="persist";
            check(CharacterBuildService.persistedExit(p).state=="blocked","raw false cannot authorize termination");
            sm._configureSaveFlowForTest({flushResult:undefined});
            check(prepare(p).state=="prepared","settled original projection prepares once");
            p.phase="persist";
            var terminal:Object=CharacterBuildService.persistedExit(p);
            trace("CHARACTER_EXIT_RESULT state="+terminal.state+" serial="+terminal.saveSerial+" physical="+sm.fullSaveSerial());
            if (!check(terminal.state=="terminate" && terminal.saveSerial>0,"strict physical save grants termination only")) return;
            var persisted:Number=sm.fullSaveSerial();
            p.phase="query";
            check(CharacterBuildService.persistedExit(p).state=="terminate" && sm.fullSaveSerial()==persisted,
                "lost reply queries the original physical serial without writing");
            check(_root._webPanelPauseLease===originalLease && _root.暂停===true && terminal.liveRevision<terminal.loadoutRevision,
                "terminal receipt keeps original pause and failed live revision");
            check(!CharacterBuildService.execute("finalize",p).success,"terminal receipt cannot authorize ordinary finalize");
            check(pauses.isPausedExcept(String(originalLease)),"independent pause claim stays active after receipt");
            gun.shot=999;
            check(gun.shot==11 && CharacterBuildService.persistedExit(p).state=="blocked" && sm.fullSaveSerial()==persisted,
                "late callback after a lost reply invalidates the receipt before reissue");
            sm._configureSaveFlowForTest({flushResult:"pending"});
            check(prepare(p).state=="prepared","pending result test prepares");
            p.phase="persist";
            check(CharacterBuildService.persistedExit(p).state=="unconfirmed","raw pending retains the original operation");
            persisted=sm.fullSaveSerial();
            p.phase="query";
            check(CharacterBuildService.persistedExit(p).state=="unconfirmed" && sm.fullSaveSerial()==persisted,
                "query of pending raw result neither authorizes nor writes again");
        } finally {
            // End this isolated fixture. A live unconfirmed terminal operation stays sealed.
            var owner:Object=org.flashNight.arki.item.CharacterBuildExit;
            if (_root.__characterExitSeal!=null) owner.release(_root,_root.__characterExitSeal);
            sm._configureSaveFlowForTest({flushResult:undefined});
            settingsClass._settingsBootstrap=setting;gym._session=training;loot.operation=operation;ground.pending=claim;
            _root.UpdateTaskProgress=function() {};
            pauses.releaseLease(otherLease);
            socket.sendServerMessage=send;
            store.clear();
        }
    }
}
