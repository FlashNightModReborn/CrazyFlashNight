import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardInboxService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUseService;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.task.TaskRewardCommit;
import org.flashNight.arki.item.LootMaterializationPlanner;
import org.flashNight.arki.item.MapChestStashService;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.arki.pause.PauseManager;

class org.flashNight.arki.item.RewardStashServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    public static function runAllTests():Boolean {
        passed = 0; failed = 0;
        testSnapshots();
        testStore();
        testSummaryPurity();
        testSaveFence();
        testSourceTransactions();
        trace("RewardStashServiceTest Tests Passed: " + passed);
        trace("RewardStashServiceTest Tests Failed: " + failed);
        return failed == 0;
    }
    private static function check(value:Boolean, name:String):Void {
        if (value) { passed++; trace("[PASS] " + name); }
        else { failed++; trace("[FAIL] " + name); }
    }
    private static function testSnapshots():Void {
        var source:Object = {nested:{shots:37}, list:[]};
        source.list.push(source.nested);
        var copy:Object = PersistedSnapshot.clone(source);
        copy.nested.shots = 3;
        check(source.nested.shots == 37 && copy.list[0].shots == 37, "persisted snapshot detaches values and aliases");
        var keys:Number = 0;
        for(var key:String in source.nested) keys++;
        check(keys == 1, "persisted snapshot does not stamp source objects");
        var cycle:Object = {}; cycle.self = cycle;
        var rejected:Boolean = false;
        try { PersistedSnapshot.clone(cycle); } catch(error) { rejected = true; }
        check(rejected && cycle.self == cycle, "cyclic serialized snapshot is rejected before mutation");
        var dates:Object = {date:new Date(1000), empty:[], missing:null};
        var detached:Object = PersistedSnapshot.clone(dates);
        check(detached.date.getTime() == 1000 && detached.empty instanceof Array && detached.missing == null,
            "persisted snapshot preserves AMF value shapes");
    }
    private static function testStore():Void {
        var store:Object = RewardStashStore.create("fixture", null);
        var equipment:Object = {name:"gun", value:{level:5, tier:"二阶", mods:["test"], shots:37}, lastUpdate:100};
        check(RewardStashStore.append(store, [{name:"med", value:3, lastUpdate:1}, equipment]), "append mixed full items");
        check(RewardStashStore.append(store, [{name:"med", value:7, lastUpdate:2}, equipment]), "append second source");
        check(store.entries.length == 3 && store.entries[0].item.value == 10, "cross-source merge without equipment merge");
        check(store.entries[1].item.value.shots == 37 && store.entries[1].item.value.mods[0] == "test", "complete equipment preserved");
        equipment.value.shots = 99;
        check(store.entries[1].item.value.shots == 37, "source alias detached");
        var beforeCandidate:String = new LiteJSON().stringify(store);
        var candidate:Object = RewardStashStore.candidate(store);
        RewardStashStore.append(candidate,[{name:"med",value:2,lastUpdate:3}]);
        RewardStashStore.removeQuantity(candidate,candidate.entries[0].entryId,1);
        check(new LiteJSON().stringify(store) == beforeCandidate && candidate.entries[0].item.value == 11,
            "candidate append and take never mutate the committed row before-image");
        var id:String = store.entries[0].entryId;
        check(RewardStashStore.removeQuantity(store, id, 4) && store.entries[0].item.value == 6, "partial quantity withdrawal");
        check(RewardStashStore.removeQuantity(store, id, 6) && RewardStashStore.find(store, id) == null, "zero stock removed");
        RewardStashStore.append(store, [{name:"med", value:1, lastUpdate:3}]);
        check(store.entries[2].entryId != id, "removed identity never reused");
        var count:Number = store.entries.length;
        check(!RewardStashStore.append(store, [{name:"med", value:2, lastUpdate:4}, {name:"bad", value:0, lastUpdate:4}])
            && store.entries.length == count && store.entries[2].item.value == 1, "invalid tail has no prefix writes");
        RewardStashStore.recordCommit(store, "op.1", "fp", {success:true, accepted:[]});
        check(RewardStashStore.inspectCommand(store, "fixture", 0, "op.1", "fp").state == "committed", "exact committed replay");
        check(RewardStashStore.inspectCommand(store, "fixture", 0, "op.1", "different").state == "conflict", "operation identity conflict");
        RewardStashStore.recordCommit(store, "op.2", "fp2", {success:true});
        check(RewardStashStore.inspectCommand(store, "fixture", 0, "op.1", "fp").state == "stale", "forgotten operation cannot re-admit");
        check(RewardStashStore.inspectCommand(store, "other-role", 2, "op.3", "fp").state == "stale", "store identity boundary");
        var invalid:Object = RewardStashStore.create("bad", null); invalid.entries = {valuable:{name:"med", value:8}};
        check(!RewardStashStore.normalize(invalid).ok && invalid.entries.valuable.value == 8, "nonempty malformed collection retained");
        var empty:Object = RewardStashStore.create("empty", null); empty.entries = {};
        check(RewardStashStore.normalize(empty).ok && empty.entries instanceof Array, "known empty AMF shape normalized");
    }
    private static function testSourceTransactions():Void {
        var keys:Array = ["savePath", "允许存档", "角色名", "等级", "基础身价值", "身价", "存档系统", "mydata", "_saveExt", "暂停", "UpdateTaskProgress", "物品栏", "收集品栏", "金钱", "虚拟币", "经验值", "技能点数", "gameworld", "主角被动技能", "商城已购买物品", "UI系统", "tasks_to_do", "tasks_finished", "task_chains_progress", "等级限制", "根据等级得升级所需经验", "根据等级计算获得技能点", "提交任务完成状态", "投影已提交任务成长", "taskCompleteCheck", "isChallengeMode", "_lastTaskFinishError", "__stashGrowthNotices"];
        var previous:Object = {};
        for (var i:Number = 0; i < keys.length; i++) previous[keys[i]] = _root[keys[i]];
        var tasksBefore:Object = TaskUtil.tasks;
        var metadata:Object = ItemUtil.itemDataDict;
        var equipmentMetadata:Object = ItemUtil.equipmentDict;
        var material:Object = ItemUtil.materialDict;
        var information:Object = ItemUtil.informationMaxValueDict;
        var sm:SaveManager = SaveManager.getInstance();
        var slot:String = "CF7_RewardStash_Integration_Test";
        var so:SharedObject = SharedObject.getLocal(slot); so.clear();
        _root.savePath = slot; _root.允许存档 = true; _root.角色名 = "StashIntegration";
        _root.等级 = 1; _root.基础身价值 = 1000; _root.金钱 = 0; _root.虚拟币 = 0;
        _root.经验值 = 0; _root.技能点数 = 0; _root.商城已购买物品 = [];
        _root.存档系统 = {dirtyMark:false}; _root._saveExt = {}; _root.主角被动技能 = {};
        _root.UpdateTaskProgress = function():Void {};
        _root.物品栏 = {};
        var containers:Array = ["背包", "药剂栏", "装备栏", "仓库", "战备箱"];
        for (var c:Number = 0; c < containers.length; c++) _root.物品栏[containers[c]] = new org.flashNight.arki.item.itemCollection.ArrayInventory(null, 50);
        _root.收集品栏 = {材料:new org.flashNight.arki.item.itemCollection.DictCollection(null), 情报:new org.flashNight.arki.item.itemCollection.InformationCollection(null)};
        ItemUtil.itemDataDict = {暂存测试材料:{name:"暂存测试材料", type:"收集品", use:"材料", displayname:"测试材料", icon:"a", data:{level:1}},
            暂存测试装备:{name:"暂存测试装备", type:"武器", use:"长枪", displayname:"测试装备", icon:"b", data:{level:1}}};
        ItemUtil.equipmentDict = {暂存测试装备:true};
        ItemUtil.materialDict = {暂存测试材料:true}; ItemUtil.informationMaxValueDict = {};
        RewardInboxService.resetForTests();
        try {
            sm._configureSaveFlowForTest({saveInFlight:false, flushResult:true});
            var context:Object = {source:"test", operationId:"source.1"};
            check(RewardStashService.begin("source.1", context, null, null), "source candidate starts");
            check(RewardStashService.admit([{name:"暂存测试材料", value:9, lastUpdate:1}], false, true, context), "source admits physical item");
            var done:Object = RewardStashService.end("source.1", {success:true}, "reward.map_stash");
            check(done.success && RewardStashService.peek().entries[0].item.value == 9, "source and stash commit once");
            var stash:Object = RewardStashService.peek();
            var take:Object = {storeId:stash.storeId, expectedRevision:stash.commitRevision, operationId:"take.1",
                entries:[{entryId:stash.entries[0].entryId, revision:stash.entries[0].revision, quantity:4}]};
            var physical:Number = sm._getSavePhysicalStatsForTest().flushSO;
            var moved:Object = RewardStashService.take(take);
            check(moved.success && moved.accepted.length == 1 && RewardStashService.peek().entries[0].item.value == 5, "partial take commits exact accepted stock");
            check(ItemUtil.contain([{name:"暂存测试材料", value:4}]) != null, "take arrives at material affinity destination");
            check(RewardStashService.take(take).success && RewardStashService.peek().entries[0].item.value == 5, "same take is replayed without another removal");
            sm._configureSaveFlowForTest({flushResult:false});
            stash = RewardStashService.peek();
            take = {storeId:stash.storeId, expectedRevision:stash.commitRevision, operationId:"take.false",
                entries:[{entryId:stash.entries[0].entryId, revision:stash.entries[0].revision, quantity:2}]};
            var fail:Object = RewardStashService.take(take);
            check(!fail.success && fail.error == "save_not_committed" && RewardStashService.peek().entries[0].item.value == 5,
                "failed take restores source and destination");
            check(ItemUtil.contain([{name:"暂存测试材料", value:5}]) == null, "failed take does not leak inventory quantity");
            sm._configureSaveFlowForTest({flushResult:true});
            // 地图源从计划到消费分开，false 恢复原规则、true 之后才执行实体结束。
            _root.gameworld = {}; MapChestStashService.beginWorld(_root.gameworld);
            var rule:Object = {名字:"暂存测试材料", 最小数量:2, 最大数量:2, 总数:4};
            var box:Object = {presetName:"装备箱", row:2, col:4, 掉落物:[rule], killedCount:0};
            var kill:Function = function(target:Object):Boolean { target.killedCount++; return true; };
            var plan:Object = LootMaterializationPlanner.planForStash(box);
            check(plan.success && rule.总数 == 4 && box.掉落物 != null, "map planning does not consume source");
            sm._configureSaveFlowForTest({flushResult:false});
            var no:Object = MapChestStashService.open(box, kill);
            check(!no.success && box.killedCount == 0 && rule.总数 == 4 && box.掉落物 != null, "map false restores source before retry");
            sm._configureSaveFlowForTest({flushResult:"pending"});
            var undecided:Object = MapChestStashService.open(box, kill);
            check(!undecided.success && undecided.error == "commit_pending" && box.killedCount == 0, "map pending preserves entity and candidate");
            sm._configureSaveFlowForTest({flushResult:true});
            check(RewardStashService.resume(RewardStashService.pendingOperationId()).success && box.killedCount == 1, "map resolves then ends entity once");
            var owned:Number = RewardStashStore.ownedQuantity(RewardStashService.peek(), "暂存测试材料");
            check(MapChestStashService.open(box, kill).success && box.killedCount == 1
                && RewardStashStore.ownedQuantity(RewardStashService.peek(), "暂存测试材料") == owned, "duplicate source cannot grant again");
            // 模拟保存成功后动画前的同源恢复：只看保存的消费证明，不靠死亡布尔值。
            delete box.__rewardStashCommitted; delete box.__rewardStashEnded;
            check(MapChestStashService.open(box, kill).success
                && RewardStashStore.ownedQuantity(RewardStashService.peek(), "暂存测试材料") == owned, "durable map proof survives lost visual marker");
            check(so.data[SaveManager.SAVE_KEY].shop.商城已购买物品.length == 0 && so.data.商城已购买物品.length == 0, "full save keeps empty K mirrors equal");
            testTaskTurnIn(sm);
            testLegacyK(sm, so);
            testPacks(sm);
        } finally {
            if (RewardStashService.pendingOperationId() != "") {
                sm._configureSaveFlowForTest({flushResult:true}); RewardStashService.resume(RewardStashService.pendingOperationId());
            }
            sm._configureSaveFlowForTest({flushResult:undefined, saveInFlight:false});
            so.clear(); TaskUtil.tasks = tasksBefore; ItemUseService.setContextValidator(null); ItemUtil.itemDataDict = metadata; ItemUtil.equipmentDict = equipmentMetadata; ItemUtil.materialDict = material; ItemUtil.informationMaxValueDict = information;
            for (var j:Number = 0; j < keys.length; j++) _root[keys[j]] = previous[keys[j]];
            RewardInboxService.resetForTests();
        }
    }

    private static function testTaskTurnIn(sm:SaveManager):Void {
        var bag:Object = _root.物品栏.背包;
        for (var b:Number = 0; b < 50; b++) bag.add(b, BaseItem.create("暂存测试装备", 2));
        _root.tasks_to_do = [{id:"stash.test.quest", requirements:{challenge:{finished:false}}}];
        _root.tasks_finished = []; _root.task_chains_progress = {};
        _root.等级限制 = 3; _root.__stashGrowthNotices = 0;
        _root.根据等级得升级所需经验 = function(level:Number):Number { return level * 10; };
        _root.根据等级计算获得技能点 = function(level:Number):Number { return level; };
        _root.taskCompleteCheck = function(index:Number):Boolean { return true; };
        _root.isChallengeMode = function():Boolean { return false; };
        _root.提交任务完成状态 = function(id:String, chain:Object):Void { _root.tasks_finished.push(id); };
        _root.投影已提交任务成长 = function(before:Number):Void { _root.__stashGrowthNotices++; throw new Error("optional_projection"); };
        TaskUtil.tasks = {};
        TaskUtil.tasks["stash.test.quest"] = {id:"stash.test.quest", rewards:["暂存测试装备#5#二阶", "暂存测试装备#6", "经验值#35", "技能点#3"],
            finish_submit_items:["暂存测试装备##1"], challenge:{rewards:[]}, finish_conversation:"完成"};
        var token:String = TaskRewardCommit.instanceToken(_root.tasks_to_do[0]);
        var count:Number = RewardStashService.peek().entries.length;
        sm._configureSaveFlowForTest({flushResult:false});
        check(!TaskRewardCommit.finish(0, token) && _root.tasks_to_do.length == 1 && _root.tasks_finished.length == 0,
            "task false keeps exact completion and consumption reversible");
        check(_root.等级 == 1 && _root.经验值 == 0 && _root.技能点数 == 0 && _root.__stashGrowthNotices == 0
            && RewardStashService.peek().entries.length == count, "task false restores growth and reward stock without notices");
        sm._configureSaveFlowForTest({flushResult:"pending"});
        token = TaskRewardCommit.instanceToken(_root.tasks_to_do[0]);
        var attempts:Number = sm._getSavePhysicalStatsForTest().flushAttempt;
        check(!TaskRewardCommit.finish(0, token) && _root._lastTaskFinishError == "commit_pending" && _root.__stashGrowthNotices == 0,
            "full backpack task can prepare reward overflow and pending growth together");
        check(RewardInboxService.inboxSummary().remainingCount == count && RewardStashService.page(0).total == count,
            "pending badge and page expose committed stock only");
        sm._configureSaveFlowForTest({flushResult:true});
        check(RewardStashService.resume(RewardStashService.pendingOperationId()).success && _root.tasks_to_do.length == 0
            && _root.tasks_finished.length == 1, "task pending resolves completion exactly once");
        check(_root.等级 == 3 && _root.经验值 == 35 && _root.技能点数 == 8 && _root.__stashGrowthNotices == 1,
            "task growth is durable before a throwing optional projection");
        check(RewardStashService.peek().entries.length == count + 1 && bag.getItem(0).value.level == 5
            && bag.getItem(0).value.tier == "二阶", "turn-in freed slot receives full equipment and other reward is stashed");
        check(sm._getSavePhysicalStatsForTest().flushAttempt == attempts + 2 && !TaskRewardCommit.finish(0, token),
            "task uses one candidate and one retry without repeat grant");
    }

    private static function testLegacyK(sm:SaveManager, so:SharedObject):Void {
        var rows:Array = [];
        for (var i:Number = 0; i < 45; i++) rows.push([i,"暂存测试装备",0,0,3]);
        _root.商城已购买物品 = rows;
        var shop:Object = {purchasedToken:"k.before"};
        shop.buildPurchasedSnapshot = function():Object {
            var fingerprints:Array = [];
            for (var i:Number = 0; i < _root.商城已购买物品.length; i++) fingerprints.push("row." + _root.商城已购买物品[i][0]);
            return {success:true,purchased:_root.商城已购买物品,fingerprints:fingerprints};
        };
        shop.rotatePurchasedToken = function():Void { this.purchasedToken += ".next"; };
        _root.UI系统 = {商城WebView:shop};
        var before:Number = RewardStashService.peek().entries.length;
        var store:Object = RewardStashService.peek();
        var rev:Number = store.commitRevision; var id:String = store.storeId;
        sm._configureSaveFlowForTest({flushResult:false});
        check(!RewardStashService.migrate("k.false", id, rev).success && _root.商城已购买物品.length == 45
            && shop.purchasedToken == "k.before" && RewardStashService.peek().entries.length == before,
            "K migration false restores stock, legacy source and token");
        sm._configureSaveFlowForTest({flushResult:true});
        check(RewardStashService.migrate("k.40", id, rev).success && _root.商城已购买物品.length == 5
            && RewardStashService.peek().entries.length == before + 40, "K migration bounds first commit to forty rows");
        check(RewardStashService.migrate("k.40", id, rev).success && _root.商城已购买物品.length == 5,
            "K committed operation replays without consuming next rows");
        check(RewardStashService.migrate("k.5", id, RewardStashService.peek().commitRevision).success
            && RewardStashService.peek().entries.length == before + 45, "K migration drains remaining rows without charging again");
        check(so.data[SaveManager.SAVE_KEY].shop.商城已购买物品.length == 0 && so.data.商城已购买物品.length == 0,
            "K migration clears nested and top-level mirrors in the same full save");
    }

    private static function testPacks(sm:SaveManager):Void {
        ItemUtil.itemDataDict["暂存测试礼包"] = {name:"暂存测试礼包", displayname:"测试礼包", icon:"a", type:"消耗品",use:"礼包",
            data:{level:1,rewardPack:{mode:"fixed",entries:{entry:{itemName:"暂存测试材料",quantityMin:2,quantityMax:2}}}}};
        _root.物品栏.背包.remove(20);
        _root.物品栏.背包.add(20, BaseItem.create("暂存测试礼包", 4));
        ItemUseService.setContextValidator(function(panel:String,generation:Number):Object { return {success:true}; });
        var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 50);
        var store:Object = RewardStashService.peek();
        var owned:Number = RewardStashStore.ownedQuantity(store,"暂存测试材料");
        var request:Object = {task:"cmd", action:"itemUseStashOpenMany", callId:1,v:2,panelInstanceId:"test.stash",sessionGeneration:1,
            operationId:"packs.3",storeId:store.storeId,expectedRevision:store.commitRevision,count:3,
            source:{physicalSlot:20,slotLease:String(snapshot.slots[20].slotLease),itemName:"暂存测试礼包",backpackVersion:Number(snapshot.containerVersion)}};
        sm._configureSaveFlowForTest({flushResult:"pending"});
        var result:Object = ItemUseService.execute("stashOpenMany",request);
        check(!result.success && result.error == "commit_pending" && _root.物品栏.背包.getItem(20).value == 1,
            "multi-pack freezes three rolls and deducts three in one candidate");
        sm._configureSaveFlowForTest({flushResult:true});
        check(RewardStashService.resume(RewardStashService.pendingOperationId()).success
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"暂存测试材料") == owned + 6,
            "multi-pack pending resumes frozen rewards without reroll");
        result = ItemUseService.execute("stashOpenMany",request);
        check(result.success && result.data.packages.length == 3 && _root.物品栏.背包.getItem(20).value == 1,
            "multi-pack exact replay returns original receipt without another deduction");
        testPackBoundaries(sm);
        ItemUseService.setContextValidator(null);
    }

    private static function packRequest(op:String, count:Number):Object {
        var snap:Object = InventoryPanelService.buildExternalSnapshot("背包",0,50);
        var store:Object = RewardStashService.peek();
        return {task:"cmd",action:"itemUseStashOpenMany",callId:1,v:2,panelInstanceId:"test.stash",sessionGeneration:1,
            operationId:op,storeId:store.storeId,expectedRevision:store.commitRevision,count:count,
            source:{physicalSlot:20,slotLease:String(snap.slots[20].slotLease),itemName:"暂存测试礼包",backpackVersion:Number(snap.containerVersion)}};
    }

    private static function testPackBoundaries(sm:SaveManager):Void {
        var bag:Object = _root.物品栏.背包;
        bag.remove(20); bag.add(20,BaseItem.create("暂存测试礼包",64));
        InventoryPanelService.invalidateExternalSlot("背包",20);
        var invalid:Array = [0,1,65,NaN,"3"];
        var owned:Number = RewardStashStore.ownedQuantity(RewardStashService.peek(),"暂存测试材料");
        var initial:Number = sm._getSavePhysicalStatsForTest().flushAttempt;
        for(var i:Number=0;i<invalid.length;i++) {
            var bad:Object = packRequest("invalid."+i,3); bad.count=invalid[i];
            var rejected:Object = ItemUseService.execute("stashOpenMany",bad);
            check(!rejected.success && sm._getSavePhysicalStatsForTest().flushAttempt == initial && bag.getItem(20).value == 64,
                "v2 pack count rejects without write "+i);
        }
        var extra:Object = packRequest("invalid.extra",3); extra.untrusted=true;
        check(!ItemUseService.execute("stashOpenMany",extra).success && bag.getItem(20).value == 64,"v2 pack rejects extra envelope fields");
        var faults:Array = ["append","receipt","false","throw"];
        for(var f:Number=0;f<faults.length;f++) {
            var before:Object = PersistedSnapshot.clone(RewardStashService.peek());
            var req:Object = packRequest("fault."+f,3);
            ItemUseService.setOpenManyFaultForTests(faults[f],1);
            sm._configureSaveFlowForTest({flushResult:faults[f]=="false"?false:true,
                beforeLocalCommit:faults[f]=="throw"?function():Void {throw new Error("preflush");}:null});
            var result:Object = ItemUseService.execute("stashOpenMany",req);
            check(!result.success && bag.getItem(20).value == 64 && ObjectUtil.deepEquals(RewardStashService.peek(),before)
                && RewardStashService.pendingOperationId() == "", "v2 pack full rollback at "+faults[f]);
        }
        ItemUseService.setOpenManyFaultForTests("",0);
        sm._configureSaveFlowForTest({flushResult:true,beforeLocalCommit:null});
        var request:Object = packRequest("packs.64",64);
        initial = sm._getSavePhysicalStatsForTest().flushAttempt;
        var committed:Object = ItemUseService.execute("stashOpenMany",request);
        check(committed.success && committed.data.packages.length == 64 && bag.getItem(20) == null
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"暂存测试材料") == owned+128
            && sm._getSavePhysicalStatsForTest().flushAttempt == initial+1,"v2 sixty-four packs merge across sources with one save");
        var conflict:Object = PersistedSnapshot.clone(request); conflict.count=2;
        check(!ItemUseService.execute("stashOpenMany",conflict).success
            && sm._getSavePhysicalStatsForTest().flushAttempt == initial+1,"v2 same operation with changed payload cannot append");
        var query:Object = {storeId:request.storeId,expectedRevision:request.expectedRevision,operationId:request.operationId};
        RewardInboxService.resetSession();
        check(RewardStashService.query(query).state == "committed" && ItemUseService.execute("stashOpenMany",request).success
            && sm._getSavePhysicalStatsForTest().flushAttempt == initial+1,"v2 receipt survives authority reset and lost response");
        bag.add(20,BaseItem.create("暂存测试礼包",2)); InventoryPanelService.invalidateExternalSlot("背包",20);
        ItemUtil.itemDataDict["暂存测试礼包"].data.rewardPack={mode:"independent",entries:{entry:{itemName:"暂存测试材料",quantityMin:1,quantityMax:1,chanceNumerator:1,chanceDenominator:2}}};
        ItemUseService.setRandomValuesForTests([1,1]);
        var zero:Object=ItemUseService.execute("stashOpenMany",packRequest("packs.zero",2));
        ItemUseService.setRandomValuesForTests(null);
        check(zero.success && zero.data.packages.length == 2 && zero.data.packages[0].entryCount == 0
            && bag.getItem(20) == null && RewardStashStore.ownedQuantity(RewardStashService.peek(),"暂存测试材料") == owned+128,
            "zero-hit packs consume exactly their source and retain empty receipt descriptors");
        check(!ItemUseService.execute("stashOpenMany",request).success
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"暂存测试材料") == owned+128,
            "forgotten v2 operation remains stale after a later commit");
        var legacy:Object = {v:1,operationId:"retired.fresh"};
        check(ItemUseService.execute("openMany",legacy).error == "unsupported_version"
            && RewardStashStore.ownedQuantity(RewardStashService.peek(),"暂存测试材料") == owned+128,"v1 fresh pack write is retired without asset changes");
    }

    private static function testSummaryPurity():Void {
        var prior:Object = _root._saveExt;
        _root._saveExt = undefined;
        var first:Object = RewardInboxService.inboxSummary();
        check(first.remainingCount == 0 && _root._saveExt === undefined, "empty badge never creates save extension");
        var page:Object = RewardStashService.page(0);
        check(page.success && !page.migrationRequired && _root._saveExt === undefined, "empty page never migrates or opens authority");
        _root._saveExt = prior;
    }
    private static function testSaveFence():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var keys:Array = ["savePath", "允许存档", "角色名", "等级", "基础身价值", "身价", "存档系统", "mydata", "_saveExt", "暂停", "UpdateTaskProgress"];
        var before:Object = {};
        for (var i:Number = 0; i < keys.length; i++) before[keys[i]] = _root[keys[i]];
        var slot:String = "CF7_RewardStashFence_Test";
        var so:SharedObject = SharedObject.getLocal(slot);
        so.clear(); so.data.proof = "before";
        _root.savePath = slot; _root.允许存档 = true; _root.角色名 = "RewardStashTest";
        _root.等级 = 1; _root.基础身价值 = 1000; _root.存档系统 = {dirtyMark:false};
        _root._saveExt = {}; _root.mydata = {proof:"root-before"};
        _root.UpdateTaskProgress = function():Void {};
        sm._configureSaveFlowForTest({saveInFlight:false, flushResult:false});
        check(sm.beginRewardCommit("false", null, null), "candidate admitted before domain write");
        so.data.proof = "candidate";
        check(sm.commitRewardCandidate("false", "reward.stash_take") == "not_committed", "definite false classified");
        check(so.data.proof == "before" && _root.mydata.proof == "root-before" && !sm.hasRewardCommitPending(), "false restores SO and root mydata together");
        sm.beginRewardCommit("restore-image", null, null);
        so.data.proof = "candidate-retained";
        var snapshots:Object = PersistedSnapshot;
        var originalClone:Function = snapshots.clone;
        snapshots.clone = function(value:Object):Object { throw new Error("synthetic restore allocation failure"); return null; };
        var cancelled:Boolean = sm.cancelRewardCommit("restore-image");
        snapshots.clone = originalClone;
        check(!cancelled && sm.hasRewardCommitPending() && so.data.proof == "candidate-retained",
            "failed restore clone preserves SO data and keeps the candidate frozen");
        check(sm.resolveRewardCommit("restore-image") == "not_committed" && so.data.proof == "before"
            && _root.mydata.proof == "root-before" && !sm.hasRewardCommitPending(),
            "restore retry recovers the complete before-image before unlocking");
        sm._configureSaveFlowForTest({flushResult:"pending"});
        check(sm.beginRewardCommit("pending", null, null), "pending candidate admitted");
        check(sm.commitRewardCandidate("pending", "reward.stash_take") == "pending", "permission pending distinguished from false");
        check(sm.hasRewardCommitPending() && !sm.beginRewardCommit("competing", null, null), "pending blocks competing candidate");
        check(!sm.flushDurableNow("manual_save") && !sm.loadAll(), "pending blocks ordinary save and role load");
        PauseManager.set(false, "webpanel:release");
        check(_root.暂停 === true, "panel close cannot resume unresolved assets");
        var packed:Number = sm._getSavePhysicalStatsForTest().packGameState;
        sm._configureSaveFlowForTest({flushResult:true});
        check(sm.resolveRewardCommit("pending") == "committed" && !sm.hasRewardCommitPending(), "same candidate resolves true");
        check(sm._getSavePhysicalStatsForTest().packGameState == packed, "pending resolution never repacks");
        check(_root.暂停 === false, "resolved save restores requested pause value");
        sm._configureSaveFlowForTest({flushResult:undefined, saveInFlight:false});
        so.clear();
        for (var j:Number = 0; j < keys.length; j++) _root[keys[j]] = before[keys[j]];
    }
}
