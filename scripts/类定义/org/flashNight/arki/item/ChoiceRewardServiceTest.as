import org.flashNight.arki.item.*;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.arki.skill.SkillLoadoutService;

class org.flashNight.arki.item.ChoiceRewardServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var sequence:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) { passed++; trace("[PASS] " + label); }
        else { failed++; trace("[FAIL] " + label); }
    }
    private static function request(cmd:String):Object {
        var store:Object = RewardStashService.peek();
        return {task:"cmd", action:"itemUse" + cmd.charAt(0).toUpperCase() + cmd.substr(1),
            callId:++sequence,v:2,panelInstanceId:"choice.test",sessionGeneration:1,
            operationId:"choice.test." + sequence,storeId:store == null ? "" : store.storeId,
            expectedRevision:store == null ? 0 : store.commitRevision};
    }
    private static function openRequest():Object {
        var p:Object = request("stashOpen");
        var bag:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 50);
        p.source = {physicalSlot:0,slotLease:String(bag.slots[0].slotLease),itemName:"选择测试礼包",backpackVersion:Number(bag.containerVersion)};
        return p;
    }
    private static function choiceRequest(offer:Object, optionId:String):Object {
        var p:Object = request("stashChoose"); p.offerId = offer.offerId; p.optionId = optionId; return p;
    }
    private static function snap():Object {
        return ItemUseService.execute("stashChoices", {task:"cmd",action:"itemUseStashChoices",callId:++sequence,v:2,panelInstanceId:"choice.test",sessionGeneration:1}).data;
    }
    private static function catalog():Array {
        var options:Array = [];
        var grades:Array = ["low","medium","high","special"];
        for (var i:Number=0;i<4;i++) options.push({id:"bundle."+i,weight:1,title:"配给"+i,description:"武器与弹药"+i,
            grade:grades[i],
            entries:[{itemName:"选择测试刀",quantity:1},{itemName:"选择测试弹",quantity:10+i}]});
        return [{id:"test.pool",version:1,title:"测试配给",itemName:"选择测试礼包",scope:{kind:"book",bookId:"test-book"},
            groups:[{draw:1,entries:[options[0]]},{draw:2,entries:options.slice(1)}]}];
    }
    public static function runAllTests():Boolean {
        passed=0;failed=0;sequence=0;
        var keys:Array=["savePath","允许存档","角色名","等级","基础身价值","身价","存档系统","mydata","_saveExt","暂停","UpdateTaskProgress","物品栏","收集品栏","金钱","虚拟币","经验值","技能点数","gameworld","主角被动技能","商城已购买物品","主角技能表","技能表对象","动态更新技能冷却领域","_技能原始数值"];
        var before:Object={}; for(var k:Number=0;k<keys.length;k++) before[keys[k]]=_root[keys[k]];
        var meta:Object=ItemUtil.itemDataDict, equipment:Object=ItemUtil.equipmentDict, materials:Object=ItemUtil.materialDict, info:Object=ItemUtil.informationMaxValueDict;
        var sm:SaveManager=SaveManager.getInstance();
        var slot:String="CF7_ChoiceReward_Isolated_Test";
        var so:SharedObject=SharedObject.getLocal(slot); so.clear();
        _root.savePath=slot; _root.允许存档=true; _root.角色名="ChoiceTest"; _root.等级=9; _root.基础身价值=1000;
        _root.金钱=0; _root.虚拟币=0; _root.经验值=0; _root.技能点数=0; _root.商城已购买物品=[];
        _root.存档系统={dirtyMark:false}; _root.主角被动技能={}; _root.UpdateTaskProgress=function():Void {};
        _root._saveExt={bookRun:{slot:slot,bookId:"test-book",seed:17,startedAt:100,outcome:"active"}};
        _root.物品栏={}; var containers:Array=["背包","药剂栏","装备栏","仓库","战备箱"];
        for(var c:Number=0;c<containers.length;c++) _root.物品栏[containers[c]]=new org.flashNight.arki.item.itemCollection.ArrayInventory(null,50);
        _root.收集品栏={材料:new org.flashNight.arki.item.itemCollection.DictCollection(null),情报:new org.flashNight.arki.item.itemCollection.InformationCollection(null)};
        ItemUtil.itemDataDict={选择测试礼包:{name:"选择测试礼包",displayname:"选择礼包",icon:"a",type:"消耗品",use:"礼包",data:{level:0,rewardPack:{mode:"playerChoice",poolId:"test.pool"}}},
            选择测试刀:{name:"选择测试刀",displayname:"测试刀",icon:"b",type:"武器",use:"刀",data:{level:1}},
            选择测试短枪:{name:"选择测试短枪",displayname:"测试短枪",icon:"b",type:"武器",use:"手枪",data:{level:1}},
            选择测试弹:{name:"选择测试弹",displayname:"测试弹",icon:"c",type:"收集品",use:"材料",data:{level:0}}};
        ItemUtil.equipmentDict={选择测试刀:true,选择测试短枪:true}; ItemUtil.materialDict={选择测试弹:true}; ItemUtil.informationMaxValueDict={};
        ChoiceRewardService.setPoolsForTests(catalog());
        ItemUseService.setContextValidator(function(panel:String,generation:Number):Object {return {success:panel=="choice.test"&&generation==1,error:"stale_session"};});
        RewardInboxService.resetForTests();
        try {
            sm._configureSaveFlowForTest({saveInFlight:false,flushResult:true});
            _root.物品栏.背包.add(0,BaseItem.create("选择测试礼包",5));
            var capability:Object=ItemUseService.buildCandidateUseAction(_root.物品栏.背包.getItem(0),ItemUtil.itemDataDict["选择测试礼包"],0,"lease",0);
            check(capability.useAction.command=="openChoice","choice pack has a distinct non-bulk capability");
            check(capability.useAction.packMode=="playerChoice","choice pack capability exposes its declared pack mode");
            ItemUtil.itemDataDict["选择测试固定包"]={name:"选择测试固定包",displayname:"固定包",icon:"a",type:"消耗品",use:"礼包",data:{level:0,rewardPack:{mode:"fixed",entries:{entry:[{itemName:"选择测试弹",quantityMin:1,quantityMax:1}]}}}};
            var fixedCapability:Object=ItemUseService.buildCandidateUseAction({name:"选择测试固定包",value:1},ItemUtil.itemDataDict["选择测试固定包"],1,"lease",0);
            check(fixedCapability.useAction.command=="open"&&fixedCapability.useAction.packMode=="fixed","fixed pack capability exposes its declared pack mode");
            check(snap().offers.length==0&&_root._saveExt.rewardInbox==undefined,"choice snapshot does not create a save feature");
            var many:Object=openRequest(); many.action="itemUseStashOpenMany"; many.count=2;
            check(!ItemUseService.execute("stashOpenMany",many).success&&_root.物品栏.背包.getItem(0).value==5,"bulk opening choices is rejected without consumption");
            var bad:Object=openRequest(); bad.source.slotLease="wrong";
            check(!ItemUseService.execute("stashOpen",bad).success,"stale source is rejected");
            bad=openRequest();bad.panelInstanceId="other";
            check(!ItemUseService.execute("stashOpen",bad).success,"foreign panel cannot open");
            sm._configureSaveFlowForTest({flushResult:false});
            var rejectedOpen:Object=ItemUseService.execute("stashOpen",openRequest());
            check(!rejectedOpen.success&&rejectedOpen.error=="save_not_committed","failed durable open is rejected at the save boundary");
            check(_root.物品栏.背包.getItem(0).value==5&&snap().offers.length==0,"failed open restores pack and no choices leak");
            sm._configureSaveFlowForTest({flushResult:"pending"});
            ChoiceRewardService.setRandomValuesForTests([0,0,0.99]);
            var opening:Object=openRequest();
            var result:Object=ItemUseService.execute("stashOpen",opening);
            if(result.error!="commit_pending") trace("Choice open diagnostic: " + new LiteJSON().stringify(result));
            check(!result.success&&result.error=="commit_pending","pending open holds the shared fence");
            var frozen:String=new LiteJSON().stringify(RewardStashService.peek().choiceOffers);
            check(snap().offers.length==0&&snap().pendingOperationId==opening.operationId,"uncommitted candidates are not shown");
            check(!ItemUseService.execute("stashOpen",openRequest()).success,"pending open blocks another draw");
            var query:Object={task:"cmd",action:"itemUseStashQuery",callId:++sequence,v:2,panelInstanceId:"choice.test",sessionGeneration:1,
                operationId:opening.operationId,storeId:opening.storeId,expectedRevision:opening.expectedRevision};
            sm._configureSaveFlowForTest({flushResult:true});
            result=ItemUseService.execute("stashQuery",query);
            check(result.success&&result.data.state=="committed"&&result.data.result.kind=="choiceOpen","exact query resolves the opening receipt");
            check(new LiteJSON().stringify(RewardStashService.peek().choiceOffers)==frozen,"query preserves exact frozen candidates");
            check(_root.物品栏.背包.getItem(0).value==4,"opening consumes exactly one pack");
            var duplicateOpen:Object=ItemUseService.execute("stashOpen",opening);
            check(!duplicateOpen.success&&duplicateOpen.error=="stale_stash"&&_root.物品栏.背包.getItem(0).value==4,"initial empty-store write cannot be replayed after creation; exact query owns recovery");
            var offer:Object=snap().offers[0];
            check(offer.options.length==3&&offer.options[0].optionId=="bundle.0"&&offer.options[1].optionId=="bundle.1"&&offer.options[2].optionId=="bundle.3","group guarantee and weighted draw are without replacement");
            check(offer.options[0].grade=="low"&&offer.options[1].grade=="medium"&&offer.options[2].grade=="special","frozen options project their declared grades");
            check(RewardStashService.peek().entries.length==0,"opening grants no unselected inventory");
            var saved:Object=so.data[SaveManager.SAVE_KEY].ext;
            check(saved.rewardInbox.choiceOffers.offers[0].offerId==offer.offerId,"full-save payload owns the frozen offer");
            _root._saveExt=PersistedSnapshot.clone(saved);
            check(new LiteJSON().stringify(snap().offers[0])==new LiteJSON().stringify(offer),"serialized reload reproduces identical visible options");
            _root.savePath="another-slot";
            check(snap().offers.length==0&&!ItemUseService.execute("stashChoose",choiceRequest(offer,"bundle.0")).success,"another save slot cannot read or claim this offer");
            _root.savePath=slot;_root._saveExt.bookRun.seed=18;
            check(snap().offers.length==0&&!ItemUseService.execute("stashChoose",choiceRequest(offer,"bundle.0")).success,"a new run in the same slot cannot claim an old offer");
            _root._saveExt.bookRun.seed=17;
            var changed:Array=catalog();changed[0].groups[0].entries[0].entries[1].quantity=999;
            ChoiceRewardService.setPoolsForTests(changed);
            check(new LiteJSON().stringify(snap().offers[0])==new LiteJSON().stringify(offer),"catalog updates cannot replace already frozen contents");
            check(!ItemUseService.execute("stashChoose",choiceRequest(offer,"forged")).success,"unoffered identity is rejected");
            var stale:Object=choiceRequest(offer,"bundle.0");stale.expectedRevision=0;
            check(!ItemUseService.execute("stashChoose",stale).success,"stale store revision cannot select");
            var badGradePools:Array=catalog();badGradePools[0].groups[0].entries[0].grade="legendary";
            ChoiceRewardService.setPoolsForTests(badGradePools);
            var badGradeResult:Object=ItemUseService.execute("stashOpen",openRequest());
            check(!badGradeResult.success&&badGradeResult.error=="invalid_reward_pack"
                &&_root.物品栏.背包.getItem(0).value==4&&snap().offers.length==1,"invalid catalog grade fails closed without consuming the pack or shadowing the pending offer");
            ChoiceRewardService.setPoolsForTests(catalog());
            for(var fill:Number=1;fill<50;fill++) _root.物品栏.背包.add(fill,BaseItem.create("选择测试刀",1));
            sm._configureSaveFlowForTest({flushResult:false});
            check(!ItemUseService.execute("stashChoose",choiceRequest(offer,"bundle.0")).success,"failed selection does not claim success");
            check(snap().offers.length==1&&RewardStashService.peek().entries.length==0,"failed selection restores offer and stock together");
            sm._configureSaveFlowForTest({flushResult:"pending"});
            var selecting:Object=choiceRequest(offer,"bundle.0");
            result=ItemUseService.execute("stashChoose",selecting);
            check(!result.success&&result.error=="commit_pending","pending selection retains the write fence");
            check(snap().offers.length==1,"pending selection only projects committed choices");
            check(!ItemUseService.execute("stashChoose",choiceRequest(offer,"bundle.1")).success,"another choice cannot race an unknown result");
            sm._configureSaveFlowForTest({flushResult:true});
            query.operationId=selecting.operationId;query.storeId=selecting.storeId;query.expectedRevision=selecting.expectedRevision;query.callId=++sequence;
            result=ItemUseService.execute("stashQuery",query);
            check(result.success&&result.data.result.kind=="choiceSelect","selection query returns the original receipt");
            check(snap().offers.length==0&&RewardStashService.peek().entries.length==1,"full backpack keeps only overflowing equipment in stash");
            check(_root.收集品栏.材料.getValue("选择测试弹")==10,"frozen ammunition routes directly to materials even with a full backpack");
            check(ItemUseService.execute("stashChoose",selecting).success&&RewardStashService.peek().entries.length==1&&_root.收集品栏.材料.getValue("选择测试弹")==10,"duplicate selection does not grant twice");
            check(so.data[SaveManager.SAVE_KEY].ext.rewardInbox.choiceOffers.offers.length==0,"selected offer removal is in the same saved payload as rewards");
            ChoiceRewardService.setPoolsForTests(catalog());
            var nextOpening:Object=openRequest();
            result=ItemUseService.execute("stashOpen",nextOpening);
            check(result.success&&result.data.offerId!=offer.offerId,"next pack gets a new durable offer identity");
            check(ItemUseService.execute("stashOpen",nextOpening).success&&snap().offers.length==1,"existing-store duplicate opening replays the same receipt without reroll");
            check(!ItemUseService.execute("stashChoose",selecting).success&&_root.收集品栏.材料.getValue("选择测试弹")==10,"old receipt after another write never regrants rewards");
            var corrupt:Object=PersistedSnapshot.clone(RewardStashService.peek());corrupt.choiceOffers.v=2;
            check(!RewardStashStore.normalize(corrupt).ok,"future choice versions fail closed");
            corrupt=PersistedSnapshot.clone(RewardStashService.peek());corrupt.choiceOffers.offers[0].options[1].optionId=corrupt.choiceOffers.offers[0].options[0].optionId;
            check(!RewardStashStore.normalize(corrupt).ok,"duplicate candidate identities are rejected on restore");
            corrupt=PersistedSnapshot.clone(RewardStashService.peek());corrupt.choiceOffers.offers[0].options[0].grade="legendary";
            check(!RewardStashStore.normalize(corrupt).ok,"corrupt frozen grades fail closed");
            corrupt=PersistedSnapshot.clone(RewardStashService.peek());corrupt.choiceOffers.offers[0].options[0].items[0].value.mods={};
            var repaired:Object=RewardStashStore.normalize(corrupt);
            check(repaired.ok&&repaired.changed&&corrupt.choiceOffers.offers[0].options[0].items[0].value.mods instanceof Array,"known empty AMF arrays are repaired and reported");
            corrupt.choiceOffers.offers[0].options[0].items[0].value.mods={};
            corrupt.choiceOffers.offers[0].options[1].optionId=corrupt.choiceOffers.offers[0].options[0].optionId;
            check(!RewardStashStore.normalize(corrupt).ok&&!(corrupt.choiceOffers.offers[0].options[0].items[0].value.mods instanceof Array),"invalid tail does not mutate the committed prefix during validation");
            // A paid, skill-only card uses the same durable fence as ordinary item rewards.
            _root.主角技能表=[];
            _root.技能表对象={测试战技:{Name:"测试战技",Type:"武术",Passive:false,Equippable:true,MaxLevel:10,UnlockLevel:15,UnlockSP:20,UpgradeSP:20,MP:10,CD:1000,Description:"测试说明"}};
            _root.动态更新技能冷却领域=function():Boolean {return true;};
            SkillLoadoutService.testOnlyUseRoot(null);
            var paidPools:Array=catalog();
            paidPools[0].groups[0].entries[0]={id:"skill.1",weight:1,title:"战技",description:"直接授予2级",entries:[],skills:[{skillKey:"测试战技",level:2}],kCost:300};
            ChoiceRewardService.setPoolsForTests(paidPools);
            _root.虚拟币=400;
            result=ItemUseService.execute("stashOpen",openRequest());
            var paidOffer:Object=snap().offers[snap().offers.length-1];
            check(result.success&&paidOffer.options[0].skills[0].level==2&&paidOffer.options[0].items.length==0&&paidOffer.options[0].kCost==300,"skill-only offer freezes exact skill level and price");
            _root.虚拟币=200;
            result=ItemUseService.execute("stashChoose",choiceRequest(paidOffer,"skill.1"));
            check(!result.success&&result.error=="insufficient_kpoints"&&_root.虚拟币==200&&_root.主角技能表.length==0,"insufficient K neither teaches nor consumes the offer");
            _root.虚拟币=400;sm._configureSaveFlowForTest({flushResult:false});
            result=ItemUseService.execute("stashChoose",choiceRequest(paidOffer,"skill.1"));
            check(!result.success&&_root.虚拟币==400&&_root.主角技能表.length==0,"rejected save rolls back paid skill and K together");
            sm._configureSaveFlowForTest({flushResult:"pending"});
            var paidRequest:Object=choiceRequest(paidOffer,"skill.1");
            result=ItemUseService.execute("stashChoose",paidRequest);
            check(!result.success&&result.error=="commit_pending"&&snap().kpoints==400,"unknown commit projects the committed K balance");
            check(!SkillLoadoutService.buildSnapshot("manage",null).success,"uncommitted skill grant is not exposed as a learned skill snapshot");
            check(SkillLoadoutService.commitLearn("测试战技",3,20,SkillLoadoutService.getRevision()).error=="commit_pending","ordinary skill edits cannot race a pending paid grant");
            sm._configureSaveFlowForTest({flushResult:true});
            query.operationId=paidRequest.operationId;query.storeId=paidRequest.storeId;query.expectedRevision=paidRequest.expectedRevision;query.callId=++sequence;
            result=ItemUseService.execute("stashQuery",query);
            check(result.success&&_root.虚拟币==100&&_root.主角技能表[0][1]==2&&_root.技能点数==0,"exact query commits the named level once without SP cost or trainer unlock");
            check(_root.主角技能表[0][2]===false&&_root.主角技能表[0][4]===false,"active reward skill does not overwrite player quick slots");
            check(ItemUseService.execute("stashChoose",paidRequest).success&&_root.虚拟币==100,"duplicate paid selection cannot charge twice");
            _root.物品栏.背包.addValue("0",3);
            result=ItemUseService.execute("stashOpen",openRequest());
            var filtered:Object=snap().offers[snap().offers.length-1];
            check(result.success&&filtered.options.length==2&&filtered.options[0].optionId!="skill.1","owned skill at the reward level is removed before drawing");
            paidPools[0].groups[0].entries[0].skills[0].level=3;
            ChoiceRewardService.setPoolsForTests(paidPools);_root.虚拟币=700;
            result=ItemUseService.execute("stashOpen",openRequest());
            var upgraded:Object=snap().offers[snap().offers.length-1];
            check(result.success&&upgraded.options[0].skills[0].currentLevel==2&&upgraded.options[0].skills[0].level==3,"higher fixed-level reward remains eligible");
            sm._configureSaveFlowForTest({flushResult:false});
            result=ItemUseService.execute("stashChoose",choiceRequest(upgraded,"skill.1"));
            check(!result.success&&_root.虚拟币==700&&_root.主角技能表[0][1]==2,"upgrade rejection preserves previous skill level");
            sm._configureSaveFlowForTest({flushResult:true});
            result=ItemUseService.execute("stashChoose",choiceRequest(upgraded,"skill.1"));
            check(result.success&&_root.虚拟币==400&&_root.主角技能表[0][1]==3,"upgrade replaces level instead of adding levels or refunding SP");
            corrupt=PersistedSnapshot.clone(RewardStashService.peek());corrupt.choiceOffers.offers[0].options[0].kCost=-1;
            check(!RewardStashStore.normalize(corrupt).ok,"negative frozen prices fail closed");
            var dualPools:Array=catalog();
            dualPools[0].groups[0].entries[0].entries=[{itemName:"选择测试短枪",quantity:1},{itemName:"选择测试短枪",quantity:1},{itemName:"选择测试弹",quantity:24}];
            ChoiceRewardService.setPoolsForTests(dualPools);_root.物品栏.背包.addValue("0",1);
            result=ItemUseService.execute("stashOpen",openRequest());
            var dualOffer:Object=snap().offers[snap().offers.length-1];
            var dualItems:Array=RewardStashService.peek().choiceOffers.offers[RewardStashService.peek().choiceOffers.offers.length-1].options[0].items;
            check(result.success&&dualItems[0].name=="选择测试短枪"&&dualItems[1].name=="选择测试短枪"&&dualItems[0]!==dualItems[1]&&dualItems[0].value!==dualItems[1].value,"dual short guns freeze as two independent equipment instances");
            var dualRequest:Object=choiceRequest(dualOffer,"bundle.0");
            _root.物品栏.背包.remove(49);
            var ammoBefore:Number=_root.收集品栏.材料.getValue("选择测试弹");
            sm._configureSaveFlowForTest({flushResult:false});
            result=ItemUseService.execute("stashChoose",dualRequest);
            check(!result.success&&RewardStashStore.ownedQuantity(RewardStashService.peek(),"选择测试短枪")==0&&_root.物品栏.背包.getItem(49)==null&&_root.收集品栏.材料.getValue("选择测试弹")==ammoBefore,"failed split delivery restores backpack, stash and materials together");
            sm._configureSaveFlowForTest({flushResult:true});
            dualRequest=choiceRequest(dualOffer,"bundle.0");
            result=ItemUseService.execute("stashChoose",dualRequest);
            check(result.success&&RewardStashStore.ownedQuantity(RewardStashService.peek(),"选择测试短枪")==1&&_root.物品栏.背包.getItem(49).name=="选择测试短枪","one free slot receives one gun; only the second gun overflows");
            var characterPools:Array=catalog();characterPools[0].scope={kind:"character"};
            ChoiceRewardService.setPoolsForTests(characterPools);delete _root._saveExt.bookRun;
            result=ItemUseService.execute("stashOpen",openRequest());
            check(result.success&&snap().offers.length==1,"generic character choice works outside a book and hides old book offers");
            _root.物品栏.背包.remove(48);
            var characterOffer:Object=snap().offers[0];
            var stashCount:Number=RewardStashService.peek().entries.length;
            var directRequest:Object=choiceRequest(characterOffer,"bundle.0");
            result=ItemUseService.execute("stashChoose",directRequest);
            check(result.success&&_root.物品栏.背包.getItem(48).name=="选择测试刀"&&RewardStashService.peek().entries.length==stashCount,"available backpack space receives the complete equipment instance without new stash rows");
            check(so.data[SaveManager.SAVE_KEY].ext.rewardInbox.choiceOffers.offers.length==RewardStashService.peek().choiceOffers.offers.length,"direct inventory delivery and offer retirement share one durable save");
        } finally {
            if(RewardStashService.pendingOperationId()!="") {sm._configureSaveFlowForTest({flushResult:true});RewardStashService.resume(RewardStashService.pendingOperationId());}
            sm._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false});so.clear();
            ItemUseService.setContextValidator(null);ChoiceRewardService.setPoolsForTests(null);ChoiceRewardService.setRandomValuesForTests(null);
            ItemUtil.itemDataDict=meta;ItemUtil.equipmentDict=equipment;ItemUtil.materialDict=materials;ItemUtil.informationMaxValueDict=info;
            for(var r:Number=0;r<keys.length;r++) _root[keys[r]]=before[keys[r]];
            SkillLoadoutService.testOnlyUseRoot(null);
            RewardInboxService.resetForTests();
        }
        trace("ChoiceRewardServiceTest Tests Passed: "+passed);
        trace("ChoiceRewardServiceTest Tests Failed: "+failed);
        return failed==0;
    }
}
