import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.item.RewardInboxService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.InformationCollection;
import org.flashNight.neur.Server.SaveManager;

/** Real Flash SOL writes, isolated test slots, one sample per frame. No flush test override. */
class org.flashNight.arki.item.RewardStashScaleTest {
    private static var _sizes:Array = [0,64,256,1024,4096];
    private static var _index:Number;
    private static var _sample:Number;
    private static var _times:Array;
    private static var _pageTimes:Array;
    private static var _phases:Object;
    private static var _backup:Object;
    private static var _metadata:Object;
    private static var _equipment:Object;
    private static var _node:MovieClip;
    private static var _done:Function;
    private static var _keys:Array = ["savePath","允许存档","角色名","等级","基础身价值","身价","存档系统","mydata","_saveExt",
        "暂停","UpdateTaskProgress","物品栏","收集品栏","金钱","虚拟币","经验值","技能点数","主角被动技能",
        "商城已购买物品","商城购物车","tasks_to_do","tasks_finished","task_chains_progress","宠物信息","宠物领养限制"];

    public static function start(done:Function):Void {
        _done = done; _index = 0; _sample = 0; _backup = {};
        for (var k:Number=0;k<_keys.length;k++) _backup[_keys[k]] = _root[_keys[k]];
        _metadata=ItemUtil.itemDataDict; _equipment=ItemUtil.equipmentDict;
        ItemUtil.itemDataDict={暂存规模测试装备:{name:"暂存规模测试装备",displayname:"暂存规模测试装备",type:"武器",use:"长枪",icon:"test",data:{level:1}}};
        ItemUtil.equipmentDict={暂存规模测试装备:true};
        _root.允许存档=true; _root.角色名="StashScale"; _root.等级=1; _root.基础身价值=1000;
        _root.金钱=0; _root.虚拟币=0; _root.经验值=0; _root.技能点数=0;
        _root.存档系统={dirtyMark:false}; _root.主角被动技能={};
        _root.商城已购买物品=[]; _root.商城购物车=[];
        _root.tasks_to_do=[]; _root.tasks_finished=[]; _root.task_chains_progress={};
        _root.宠物信息=[]; _root.宠物领养限制=[];
        _root.UpdateTaskProgress=function():Void {};
        _root.物品栏={};
        var names:Array=["背包","装备栏","药剂栏","仓库","战备箱"];
        for(var c:Number=0;c<names.length;c++) _root.物品栏[names[c]]=new ArrayInventory(null,50);
        _root.收集品栏={材料:new DictCollection(null),情报:new InformationCollection(null)};
        SaveManager.getInstance()._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false,resetScheduler:true});
        RewardInboxService.resetForTests();
        _node=_root.createEmptyMovieClip("__rewardStashScale",_root.getNextHighestDepth());
        _node.onEnterFrame=function():Void { org.flashNight.arki.item.RewardStashScaleTest.tick(); };
    }

    private static function prepare():Void {
        var count:Number=_sizes[_index];
        _root.savePath="CF7_RewardStash_Scale_"+count;
        SharedObject.getLocal(_root.savePath).clear();
        var legacy:Object={v:1,sequence:0,authorityRevision:1,batches:[],receipts:[],migrations:[],supplyKeys:[],activeClaimRoot:null,claimRootTerminal:null};
        var store:Object=RewardStashStore.create("scale."+count,legacy);
        var items:Array=[];
        for(var i:Number=0;i<count;i++) items.push({name:"暂存规模测试装备",lastUpdate:i+1,value:{level:5,tier:"二阶",shots:37,mods:[]}});
        if(!RewardStashStore.append(store,items)) throw new Error("scale_prepare_failed");
        _root._saveExt={rewardInbox:store,mapStashSources:{v:1,generation:1,consumed:[]}};
        _times=[]; _pageTimes=[]; _sample=0; _phases={beforeMs:[],packMs:[],freezeMs:[],flushMs:[]};
        SaveManager.getInstance()._resetSavePhysicalStatsForTest();
    }

    public static function tick():Void {
        try {
            if(_sample==0) prepare();
            var count:Number=_sizes[_index];
            var start:Number=getTimer();
            var op:String="scale."+count+"."+_sample;
            if(!RewardStashService.begin(op,{source:"test",operationId:op},null,null)) throw new Error(RewardStashService.lastError);
            var result:Object=RewardStashService.end("scale",{success:true},"reward.stash_take");
            if(!result.success) throw new Error(result.error);
            _times.push(getTimer()-start);
            var phases:Object=SaveManager.getInstance()._getRewardCommitTimingForTest();
            for(var phase:String in _phases) _phases[phase].push(phases[phase]);
            start=getTimer();
            var page:Object=RewardStashService.page(Math.max(0,count-32));
            _pageTimes.push(getTimer()-start);
            if(!page.success || page.entries.length!=Math.min(count,32)) throw new Error("scale_page_failed");
            _sample++;
            if(_sample<20) return;
            var stats:Object=SaveManager.getInstance()._getSavePhysicalStatsForTest();
            var bytes:Number=SharedObject.getLocal(_root.savePath).getSize();
            _times.sort(Array.NUMERIC); _pageTimes.sort(Array.NUMERIC);
            var phaseP95:Object={};
            for(var phase:String in _phases) { _phases[phase].sort(Array.NUMERIC); phaseP95[phase]=_phases[phase][18]; }
            trace("[STASH_SCALE] "+new LiteJSON().stringify({entries:count,samples:20,solBytes:bytes,
                fullSaveP95Ms:_times[18],fullSaveP99Ms:_times[19],pageP95Ms:_pageTimes[18],pageP99Ms:_pageTimes[19],
                flushAttempts:stats.flushAttempt,flushSuccess:stats.flushSuccess,packCount:stats.packGameState,phaseP95Ms:phaseP95}));
            if(stats.flushAttempt!=20 || stats.flushSuccess!=20 || stats.packGameState!=20) throw new Error("scale_save_count_failed");
            _index++; _sample=0;
            if(_index>=_sizes.length) finish(true);
        } catch(error) { trace("[FAIL] real stash scale: "+error); finish(false); }
    }

    private static function finish(ok:Boolean):Void {
        delete _node.onEnterFrame; _node.removeMovieClip();
        // An unresolved physical result must remain with its isolated role until explicitly settled.
        if(RewardStashService.pendingOperationId()!="") {
            trace("[STASH_SCALE_PENDING] "+RewardStashService.pendingOperationId());
            _done(); return;
        }
        ItemUtil.itemDataDict=_metadata; ItemUtil.equipmentDict=_equipment;
        for(var k:Number=0;k<_keys.length;k++) _root[_keys[k]]=_backup[_keys[k]];
        RewardInboxService.resetForTests();
        trace("[STASH_SCALE_COMPLETE] success="+ok);
        _done();
    }
}
