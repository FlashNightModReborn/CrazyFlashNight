import org.flashNight.arki.scene.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.neur.Server.SaveManager;

/** Actual AVM1 and RewardStash/SaveManager fence, isolated nonce storage; no player slot is opened. */
class org.flashNight.arki.scene.Cf6Type61ServiceTest {
    private static var passed:Number,failed:Number,projected:Number;
    private static var world:MovieClip,hero:MovieClip;
    private static var manager:Object,spawns:Array;
    private static var before:Object,present:Object,keys:Array;
    private static function check(ok:Boolean,label:String):Void {
        if (ok) passed++;else {failed++;trace("[FAIL] Cf6Type61: "+label);}
    }
    public static function captureRoot():Void {
        keys=["savePath","允许存档","角色名","等级","经验值","技能点数","基础身价值","身价","存档系统","mydata","_saveExt",
            "暂停","UpdateTaskProgress","物品栏","收集品栏","金钱","虚拟币","gameworld","控制目标","当前关卡名","主角被动技能",
            "商城已购买物品","UI系统","tasks_to_do","tasks_finished","task_chains_progress","等级限制","最大等级","根据等级得升级所需经验",
            "根据等级计算获得技能点","主角是否升级","健身房主角是否升级","投影已提交任务成长","经验值计算","宠物升级加载","isChallengeMode",
            "技能表对象","技能表","发布消息","难度等级","根据等级计算值","敌人函数","物品UI函数","pickupItemManager","基建系统","getItemData","isEasyMode","打怪掉钱机率"];
        before={};present={};
        for (var i:Number=0;i<keys.length;i++) {before[keys[i]]=_root[keys[i]];present[keys[i]]=_root.hasOwnProperty(keys[i]);}
    }
    private static function amount(name:String):Number {
        var total:Number=Number(ItemUtil.getTotal(name))+RewardStashStore.ownedQuantity(RewardStashService.peek(),name);
        var drugs:Object=_root.物品栏.药剂栏, indexes:Array=drugs.getIndexes();
        for (var i:Number=0;i<indexes.length;i++) {
            var item:Object=drugs.getItem(indexes[i]);if(item.name === name) total+=Number(item.value);
        }
        return total;
    }
    private static function scene(id:String):Void {
        var api:Object=Cf6Type61Service;
        api.release(api.room);api.room=null;api.pendingClear=null;
        manager.mapId=id;manager.currentStage++;manager.isCleared=false;
        world.__stageReturnWorldIdentity={};delete world.__cf6Type61Field;
        hero.hp=100;hero._x=100;hero._y=hero.Z轴坐标=200;
        Cf6Type61Service.beginRoom(world,world.__stageReturnWorldIdentity,id);
    }
    private static function makeMetadata(config:Object):Void {
        ItemUtil.itemDataDict={};ItemUtil.equipmentDict={};ItemUtil.materialDict={};ItemUtil.informationMaxValueDict={};
        var medicines:Object={};
        for (var node:String in config.medicineDeliveries) for (var d:Number=0;d<config.medicineDeliveries[node].length;d++) medicines[config.medicineDeliveries[node][d].name]=true;
        var ammo:Object={};for (var a:Number=0;a<config.ammoCatalog.length;a++) ammo[config.ammoCatalog[a]]=true;
        for(var star:Number=0;star<config.ordinaryConstellations.length;star++) {
            var starName:String=config.ordinaryConstellations[star];
            ItemUtil.itemDataDict[starName]={name:starName,displayname:starName,icon:"材料盒子",price:0,type:"武器",use:"刀",data:{level:35,weight:0}};
            ItemUtil.equipmentDict[starName]=true;
        }
        var materials:Object={强化石:true,传感器:true,高耐力橡胶:true,红外夜视仪:true,战术鱼骨零件:true,高强度合金:true};
        for (node in config.deliveryItems) for (var i:Number=0;i<config.deliveryItems[node].length;i++) {
            var name:String=config.deliveryItems[node][i].name;
            ItemUtil.itemDataDict[name]={name:name,displayname:name,icon:"材料盒子",price:10,type:materials[name] ? "收集品" : "消耗品",
                use:materials[name] ? "材料" : medicines[name] ? "药剂" : ammo[name] ? "弹夹" : "礼包",data:{level:0,weight:0}};
            if (materials[name]) ItemUtil.materialDict[name]=true;
        }
    }
    public static function runAllTests():Boolean {
        passed=0;failed=0;projected=0;spawns=[];
        var definition:Object=BookDefinition, oldDefinition:Object=definition._type61;
        var stageType:Object=StageManager,oldManager:Object=stageType.instance;
        var itemData:Object=ItemUtil.itemDataDict,equipmentData:Object=ItemUtil.equipmentDict,materialData:Object=ItemUtil.materialDict,infoData:Object=ItemUtil.informationMaxValueDict;
        var recovery:Object=LevelUpRecovery,oldCapture:Function=recovery.captureIntentOwner;
        var service:Object=Cf6Type61Service,oldRoom:Object=service.room,oldWatch:Object=service.watchClip,oldPending:Object=service.pendingClear;
        var slot:String="cf7_env_type61_"+new Date().getTime()+"_"+Math.floor(Math.random()*1000000000);
        var so:SharedObject=SharedObject.getLocal(slot);
        var ownedFixture:Boolean=false;
        var sm:SaveManager=SaveManager.getInstance();
        try {
            for (var occupied:String in so.data) throw new Error("owned_fixture_collision");
            ownedFixture=true;
            trace("[CF6_TYPE61_FIXTURE] slot="+slot);
            _root.savePath=slot;_root.允许存档=true;_root.角色名="Type61Fixture";
            _root.等级=35;_root.经验值=17372868;_root.技能点数=1050;_root.基础身价值=1000;_root.身价=35000;
            _root.金钱=30000;_root.虚拟币=0;_root.存档系统={dirtyMark:false};_root.mydata={fixture:slot};
            _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"type61",slot:slot,seed:17,startedAt:1000,outcome:"active"},retained:{value:7}};
            _root.商城已购买物品=[];_root.主角被动技能={};_root.UI系统={};_root.基建系统={infrastructure:{}};
            _root.tasks_to_do=[];_root.tasks_finished=[];_root.task_chains_progress={};_root.等级限制=100;
            _root.UpdateTaskProgress=function():Void {};
            _root.发布消息=function(message:String):Void {};
            _root.isChallengeMode=function():Boolean {return false;};
            _root.投影已提交任务成长=function(level:Number,owner:Object):Void {projected++;};
            _root.根据等级计算值=function(low:Number,high:Number,level:Number):Number {return low;};
            _root.技能表对象={枪械攻击:{UnlockLevel:1},炼金:{UnlockLevel:40},铁匠:{UnlockLevel:1}};
            _root.物品栏={};
            var containers:Array=["背包","药剂栏","装备栏","仓库","战备箱"];
            for (var c:Number=0;c<containers.length;c++) _root.物品栏[containers[c]]=new ArrayInventory(null,containers[c]=="药剂栏" ? 8 : 50);
            _root.收集品栏={材料:new DictCollection(null),情报:new InformationCollection(null)};
            var config:Object=Cf6Type61Fixture.config();makeMetadata(config);
            definition._type61={id:"cf6-sting",routeId:"type61",stageName:"书中历险-毒刺行动",type61:config};
            world=_root.createEmptyMovieClip("__type61FixtureWorld",_root.getNextHighestDepth());
            hero=world.createEmptyMovieClip("hero",world.getNextHighestDepth());
            _root.gameworld=world;_root.控制目标="hero";_root.当前关卡名="书中历险-毒刺行动";
            _root.难度等级=1;
            manager={mapId:"TUTORIAL",currentStage:-1,isActive:true,isFailed:false,isFinished:false,isCleared:false,clears:0,
                currentBookMapId:function():String {return this.mapId;},clearStage:function():Void {this.isCleared=true;this.clears++;}};
            stageType.instance=manager;
            recovery.captureIntentOwner=function(operation:String):Object {return {operationId:operation,fixture:slot};};
            service.room=null;service.watchClip=null;service.pendingClear=null;
            _root.pickupItemManager={createCollectible:function(name:String,count:Number,x:Number,y:Number,flying:Boolean,params:Object):Void {
                spawns.push({name:name,count:count,x:x,y:y,id:params.一次性领取ID});
            }};
            PauseManager.install();PauseManager.set(false,"type61_fixture");RewardInboxService.resetForTests();
            sm._configureSaveFlowForTest({saveInFlight:false,flushResult:true,beforeLocalCommit:null});
            testDefinition(config);
            testActorPreparation(sm);
            testGrants(sm,config);
            testAccess();
            testDifficulty();
            testField();
            testCurrency();
            testSale();
        } catch (error) {check(false,"fixture exception: "+error);}
        finally {
            if (RewardStashService.pendingOperationId() != "") {
                sm._configureSaveFlowForTest({flushResult:true,beforeLocalCommit:null});RewardStashService.resume(RewardStashService.pendingOperationId());
            }
            service.release(service.room);
            if (service.watchClip != null && service.watchClip !== oldWatch) service.watchClip.removeMovieClip();
            service.room=oldRoom;service.watchClip=oldWatch;service.pendingClear=oldPending;
            sm._configureSaveFlowForTest({flushResult:undefined,saveInFlight:false,beforeLocalCommit:null});
            if (world != null) world.removeMovieClip();
            definition._type61=oldDefinition;stageType.instance=oldManager;recovery.captureIntentOwner=oldCapture;
            ItemUtil.itemDataDict=itemData;ItemUtil.equipmentDict=equipmentData;ItemUtil.materialDict=materialData;ItemUtil.informationMaxValueDict=infoData;
            RewardInboxService.resetForTests();
            for (var k:Number=0;k<keys.length;k++) {if(present[keys[k]]) _root[keys[k]]=before[keys[k]];else delete _root[keys[k]];}
            // This generated nonce was proved empty before this test and is never a player slot.
            if (ownedFixture && RewardStashService.pendingOperationId()=="") so.clear();
        }
        trace("Cf6Type61ServiceTest Tests Passed: "+passed);
        trace("Cf6Type61ServiceTest Tests Failed: "+failed);
        return failed==0;
    }
    private static function testDefinition(config:Object):Void {
        check(Cf6Type61Service.validDefinition({type61:config}),"generated 19-checkpoint budget validates in AVM1");
        var bad:Object=PersistedSnapshot.clone(config);bad.checkpoints[0].money++;
        check(!Cf6Type61Service.validDefinition({type61:bad}),"one extra gold invalidates fixed budget");
        bad=PersistedSnapshot.clone(config);bad.checkpoints[0].skillPoints=Number.NaN;
        check(!Cf6Type61Service.validDefinition({type61:bad}),"NaN SP is rejected in actual AVM1");
        bad=PersistedSnapshot.clone(config);bad.deliveryItems.A01.push({name:"金币",count:1});
        check(!Cf6Type61Service.validDefinition({type61:bad}),"currency cannot hide in inventory delivery rows");
        bad=PersistedSnapshot.clone(config);bad.fieldSupplies[1]=bad.fieldSupplies[0];
        check(!Cf6Type61Service.validDefinition({type61:bad}),"duplicate field source rejected");
        bad=PersistedSnapshot.clone(config);bad.learnableSkills.push("铁匠");
        check(!Cf6Type61Service.validDefinition({type61:bad}),"forbidden teacher entry rejected");
    }
    private static function testGrants(sm:SaveManager,config:Object):Void {
        scene("TUTORIAL");Cf6Type61Service.tick();
        check(_root._saveExt.bookRun.type61Claims.TUTORIAL === true && RewardStashService.pendingOperationId()=="","initial delivery has a durable once marker");
        check(_root.金钱==30000 && _root.技能点数==1050,"initial supply does not repay preset SP or starting cash");
        check(amount("61计划初始主枪自选箱")==1 && amount("战术鱼骨零件")==1 && amount("复活币")==1,"initial main choice, fishbone and revive granted once");
        check(amount("榴弹弹药")==2 && amount("突击步枪通用弹药")==0,"initial main ammunition is deferred to selected gun while grenade reserve exists");
        var starTotal:Number=0;
        for(var star:Number=0;star<config.ordinaryConstellations.length;star++) starTotal+=amount(config.ordinaryConstellations[star]);
        check(starTotal==1 && amount("61计划普通星座箱")==0,"tutorial directly grants exactly one usable ordinary constellation");
        Cf6Type61Service.tick();check(amount("大HP药剂")==6,"repeated initial tick cannot grant another pack");
        var starAfter:Number=0;
        for(star=0;star<config.ordinaryConstellations.length;star++) starAfter+=amount(config.ordinaryConstellations[star]);
        check(starAfter==1,"repeated initial tick cannot reroll or duplicate the constellation");
        scene("A01");check(Cf6Type61Service.interceptClear(manager,world),"clear is held before checkpoint commit");
        check(_root.暂停===true,"checkpoint owns a pause before an automatic exit can run");
        Cf6Type61Service.tick();
        check(_root.金钱==65000 && _root.等级==36 && _root.技能点数==1110,"A01 exact cash and XP gap cause one natural 60-SP upgrade");
        check(amount("强化石")==18 && amount("61计划普通星座箱")==0,"A01 stones arrive without repaying the initial constellation");
        check(manager.clears==0 && _root.暂停===true,"committed receipt keeps pause until clear resumes");
        Cf6Type61Service.tick();check(manager.clears==1 && _root.暂停===false,"clear resumes once before releasing checkpoint pause");
        var money:Number=_root.金钱,points:Number=_root.技能点数;
        check(!Cf6Type61Service.interceptClear(manager,world),"claimed map no longer intercepts");
        Cf6Type61Service.tick();check(_root.金钱==money && _root.技能点数==points,"duplicate clear cannot repay currency or natural SP");
        scene("A02");sm._configureSaveFlowForTest({flushResult:"pending"});
        Cf6Type61Service.interceptClear(manager,world);Cf6Type61Service.tick();
        var operation:String=RewardStashService.pendingOperationId(),packed:Number=sm._getSavePhysicalStatsForTest().packGameState;
        var oldProjection:Number=projected;
        check(operation!="" && _root.暂停===true && manager.clears==1,"unknown save holds exit and gameplay");
        check(RewardStashService.committedKPoints()==0 && _root.虚拟币==3000,"unknown after-image K is not published as committed balance");
        Cf6Type61Service.interceptClear(manager,world);
        for(var i:Number=0;i<61;i++) Cf6Type61Service.tick();
        check(RewardStashService.pendingOperationId()===operation && sm._getSavePhysicalStatsForTest().packGameState==packed,"unknown queries preserve operation and never repack rewards");
        check(projected==oldProjection,"unknown save cannot project level recovery");
        sm._configureSaveFlowForTest({flushResult:true});RewardStashService.resume(operation);
        check(_root.金钱==115000 && _root.虚拟币==3000 && _root.等级==37 && _root.技能点数==1170,"same after image settles exactly A02 quota");
        check(_root.暂停===true && manager.clears==1,"resolved unknown keeps automatic handoff behind clear");
        Cf6Type61Service.tick();check(manager.clears==2 && _root.暂停===false,"resolved checkpoint resumes one clear");
        check(amount("强化石")==80 && amount("传感器")==4 && amount("高耐力橡胶")==4,"material totals survive pending save without duplication");
        scene("A03");var beforeGold:Number=_root.金钱,beforeXp:Number=_root.经验值,beforeSp:Number=_root.技能点数;
        config.deliveryItems.A03.push({name:"不存在的61配给",count:1});
        Cf6Type61Service.interceptClear(manager,world);Cf6Type61Service.tick();config.deliveryItems.A03.pop();
        check(_root.金钱==beforeGold && _root.经验值==beforeXp && _root.技能点数==beforeSp,"invalid late item rolls back already staged money, XP and SP");
        check(_root._saveExt.bookRun.type61Claims.A03 !== true && RewardStashService.pendingOperationId()=="","failed candidate cannot consume checkpoint allowance");
        check(manager.clears==2 && _root.暂停===false,"known failure leaves retreat possible without opening exit");
    }
    private static function testActorPreparation(sm:SaveManager):Void {
        var definition:Object=BookDefinition,previous:Object=definition._type61;
        var oldSkills:Object=_root.技能表对象,oldRows:Object=_root.技能表,oldRead:Function=_root.getItemData;
        var inputs:Object=Cf6Type61Fixture.actorInputs();
        var book:Object=Cf6Type61Fixture.book();
        var api:Object=sm;
        try {
            for(var name:String in inputs.items) {ItemUtil.itemDataDict[name]=inputs.items[name];ItemUtil.equipmentDict[name]=true;}
            _root.getItemData=function(name:String):Object {return ItemUtil.getRawItemData(name);};
            var loader:Object=org.flashNight.gesh.xml.LoadXml.SkillDataLoader.getInstance();
            loader.applySkillData({Skill:inputs.skills});
            definition._type61=book;
            check(book.economy.eliteWeapons[3].choices.length===1 && Cf6EconomyRules.valid(book),"K-only removal preserves one E4 gun quota with a valid canonical route");
            var removedChoice:Object=book.economy.eliteWeapons[1].choices.pop();
            check(!Cf6EconomyRules.valid(book),"other two-option elite quotas still require real alternatives");
            book.economy.eliteWeapons[1].choices.push(removedChoice);
            var beforeSp:Number=_root.技能点数,beforeMoney:Number=_root.金钱;
            var loadout:Object=api.prepareCf6Loadout("type61");
            check(loadout!=null && loadout.skills.length==80 && loadout.quickSkills.length==10,"actual preparation accepts source level35 actor and ten quick slots");
            var count:Number=0,baseArmor:Boolean=true;
            for(var slot:String in loadout.equipment) {count++;if(loadout.equipment[slot].value.level!==1)baseArmor=false;}
            check(count==6 && baseArmor && loadout.equipment.颈部装备.name=="战斗狂人军牌","detached preparation includes five armor pieces and the level35 necklace");
            check(loadout.passives.铁匠.等级===1 && loadout.passives.铁匠.启用===true,"real skill metadata yields enabled smith one");
            check(loadout.passives.移动射击.等级===10 && loadout.passives.移动射击.启用===true,"equipped mixed skill activates its passive component");
            var stimulant:Number=0;for(var i:Number=0;i<loadout.skills.length;i++) if(loadout.skills[i][0]==="兴奋剂")stimulant=loadout.skills[i][1];
            check(stimulant===5,"partial skill level is preserved instead of forcing historical max level");
            check(_root.技能点数===beforeSp && _root.金钱===beforeMoney,"preflight never modifies current actor balances");
            var metadata:Object=_root.技能表对象.铁匠,oldMax=metadata.MaxLevel,oldUnlock=metadata.UnlockLevel;
            metadata.MaxLevel=Number.NaN;check(api.prepareCf6Loadout("type61")==null,"NaN skill maximum fails before character replacement");metadata.MaxLevel=oldMax;
            metadata.UnlockLevel=Number.NaN;check(api.prepareCf6Loadout("type61")==null,"NaN skill unlock level fails before character replacement");metadata.UnlockLevel=oldUnlock;
            var firstName:String=book.actor.equipment[0].name,originalLevel:Number=ItemUtil.itemDataDict[firstName].data.level;
            ItemUtil.itemDataDict[firstName].data.level=36;
            check(api.prepareCf6Loadout("type61")==null && _root.技能点数===beforeSp,"unwearable initial armor cannot clear the original actor");
            ItemUtil.itemDataDict[firstName].data.level=originalLevel;
        } finally {definition._type61=previous;_root.技能表对象=oldSkills;_root.技能表=oldRows;_root.getItemData=oldRead;}
    }
    private static function testAccess():Void {
        scene("A01");_root.等级=35;
        check(Cf6Type61Service.enhancementCap()==5,"starting enhancement cap is five");
        _root._saveExt.bookRun.type61Claims.A08=true;check(Cf6Type61Service.enhancementCap()==7,"A08 unlocks seven");
        _root._saveExt.bookRun.type61Claims.A14=true;check(Cf6Type61Service.enhancementCap()==9,"A14 unlocks nine");
        _root._saveExt.bookRun.type61Claims.A16=true;check(Cf6Type61Service.enhancementCap()==11,"A16 unlocks eleven");
        delete _root._saveExt.bookRun.type61Claims.A08;delete _root._saveExt.bookRun.type61Claims.A14;delete _root._saveExt.bookRun.type61Claims.A16;
        check(!SkillLoadoutService.commitLearn("铁匠",2,0,0).success && !SkillLoadoutService.rewardSkillStatus("铁匠",2).success,"both learning and reward grants reject smith upgrades");
        check(!Cf6Type61Service.skillAllowed("口才") && !Cf6Type61Service.skillAllowed("驾驶") && !Cf6Type61Service.skillAllowed("烹饪") && !Cf6Type61Service.skillAllowed("解密"),"all excluded skills reject independently of teacher UI");
        check(Cf6Type61Service.skillAllowed("枪械攻击") && !Cf6Type61Service.skillAllowed("炼金"),"current actor level still gates legal skills");
        _root.等级=40;check(Cf6Type61Service.skillAllowed("炼金"),"alchemy opens at its real level");
        _root.等级=Number.NaN;check(!Cf6Type61Service.skillAllowed("枪械攻击"),"NaN actor level cannot pass AVM1 comparison");_root.等级=40;
        check(Cf6Type61Service.kShopAllowed("榴弹弹药") && !Cf6Type61Service.kShopAllowed("钛合金P90"),"A01 ammo is available before late K weapons");
        check(Cf6Type61Service.shopAllowed("书中-CF6六一-A01") && !Cf6Type61Service.shopAllowed("书中-CF6毒刺-35级"),"historical and global coin shop identities cannot bypass chapter catalog");
        check(!Cf6Type61Service.recipeAllowed("craft.unified61.helmet"),"unified repair remains locked until A05");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A01"})=="武器合成","first merchant opens available weapon recipes through the workbench");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A16"})=="","future merchant cannot open workbench");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A01"},"craft_necklace")=="饰品合成","first merchant exposes necklace recipes directly");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A01"},"craft_plugins")=="","empty locked plugin category is not offered early");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A01"},"craft_untrusted")=="","unrecognized crafting action cannot select a category");
        manager.mapId="A05";check(Cf6Type61Service.recipeAllowed("craft.unified61.helmet"),"A05 exposes canonical unified recipe");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A05"})=="进阶防具","A05 merchant opens unified armor category");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A05"},"craft_plugins")=="插件合成" && Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A05"},"craft_iron")=="铁枪会","A05 exposes both plugin recipe categories without hidden navigation");
        manager.mapId="A10";check(!Cf6Type61Service.recipeAllowed("craft.cf6-type61.titanium.0"),"titanium upgrade cannot run before A11");
        manager.mapId="A11";check(Cf6Type61Service.kShopAllowed("钛合金P90") && Cf6Type61Service.kShopAllowed("SVD"),"A11 exposes P90 and SVD prices");
        check(!Cf6Type61Service.kShopAllowed("钛合金61式胸甲") && !Cf6Type61Service.kShopAllowed("血色光剑天秤"),"direct titanium armor and stars stay forbidden");
        check(Cf6Type61Service.recipeAllowed("craft.cf6-type61.titanium.0"),"A11 exposes consuming titanium upgrade before instructor");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A11"})=="书中配给","A11 merchant directly opens titanium upgrade category");
        manager.mapId="A16";check(Cf6Type61Service.recipeAllowed("craft.cf6-type61.titanium.0"),"later nodes retain consuming titanium upgrade");
        check(Cf6Type61Service.craftingCategory({NPC商店检索名:"书中-CF6六一-A16"})=="书中配给" && Cf6Type61Service.kShopAllowed("M134暴力版"),"A16 exposes titanium workbench and original K-only Gatling");
        manager.mapId="Axx";check(!Cf6Type61Service.nodeReached("A01"),"NaN map index cannot unlock goods");
        _root._saveExt.bookRun.routeId="historical";
        check(!Cf6Type61Service.recipeAllowed("craft.cf6-type61.titanium.0") && Cf6Type61Service.enhancementCap()==-1,"historical route cannot use Type61 prices or enhancement cap");
        check(Cf6Type61Service.kShopAllowed("钛合金61式胸甲"),"unrelated K shop rules remain unchanged");
        _root._saveExt.bookRun.routeId="type61";scene("A10");
    }
    private static function testDifficulty():Void {
        var ordinary:MovieClip=world.createEmptyMovieClip("ordinary",world.getNextHighestDepth());
        ordinary.hp_min=ordinary.hp_max=100;ordinary.空手攻击力_min=ordinary.空手攻击力_max=10;
        ordinary.装备防御力=0;
        _root.难度等级=7;_root.敌人函数.根据等级初始数值.call(ordinary,35);
        check(ordinary.hp满血值==100 && ordinary.空手攻击力==10,"ordinary birth freezes factor one without reading changed global difficulty");
        ordinary.cf6DifficultyScale=2.5;check(Cf6Type61Service.enemyScale(ordinary)==1,"changing parameter after birth cannot rescale a unit");
        var guard:MovieClip=world.createEmptyMovieClip("guard",world.getNextHighestDepth());guard.cf6DifficultyScale=2.5;
        guard.hp_min=guard.hp_max=100;guard.空手攻击力_min=guard.空手攻击力_max=10;guard.等级=35;guard.是否为敌人=true;guard.产生源="enemy";
        _root.敌人函数.根据等级初始数值.call(guard,35);
        check(guard.hp满血值==250 && guard.空手攻击力==25 && _root.难度等级==7,"local hell scales HP and unarmed attack without mutating global mode");
        var child:MovieClip=world.createEmptyMovieClip("guard__tyrant",world.getNextHighestDepth());child.等级=35;child.是否为敌人=true;child.产生源="enemy";
        guard.guardTransform={active:true,attempted:true,retired:false,world:world,name:child._name,level:35,side:true,source:"enemy"};
        check(Cf6Type61Service.enemyScale(child)==2.5,"exact guard native successor inherits frozen difficulty");
        guard.guardTransform.retired=true;check(Cf6Type61Service.enemyScale(child)==2.5,"already born successor retains factor after parent retires");
        var elder:MovieClip=world.createEmptyMovieClip("elder",world.getNextHighestDepth());elder.cf6DifficultyScale=2.5;Cf6Type61Service.enemyScale(elder);
        var robot:MovieClip=world.createEmptyMovieClip("elder__elderbot",world.getNextHighestDepth());robot.等级=60;robot.是否为敌人=true;robot.产生源="enemy";robot.elderSpawnIdentity={};elder.elderIdentity={};world.__elderWorldIdentity={};
        elder.elderTransform={active:true,attempted:true,retired:false,world:world,name:robot._name,level:60,side:true,source:"enemy",spawnIdentity:robot.elderSpawnIdentity,parentIdentity:elder.elderIdentity,worldIdentity:world.__elderWorldIdentity};
        check(Cf6Type61Service.enemyScale(robot)==2.5,"elder robot inherits only matching native phase identities");
        var stale:MovieClip=world.createEmptyMovieClip("unrelated__elderbot",world.getNextHighestDepth());stale.elderSpawnIdentity={};
        check(Cf6Type61Service.enemyScale(stale)==1,"unrelated transform-like names receive no hell inheritance");
        _root._saveExt.bookRun.routeId="historical";check(Cf6Type61Service.enemyScale(guard)==7,"historical path preserves original global multiplier");
        _root._saveExt.bookRun.routeId="type61";_root.难度等级=1;
    }
    private static function testField():Void {
        scene("A01");spawns=[];PauseManager.set(false,"type61_fixture");
        var api:Object=Cf6Type61Service;
        Cf6Type61Service.queueField(world,4,"primary");api.tickField(world);
        check(spawns.length==1 && spawns[0].name=="61计划战场急救包","high-pressure wave begins with pure medical entity");
        for (var i:Number=0;i<89;i++) api.tickField(world);
        check(spawns.length==2 && spawns[1].name=="61计划战场弹药包","equipped-ammo entity is delayed into the encounter");
        var carrier:MovieClip=world.createEmptyMovieClip("fieldCarrier",world.getNextHighestDepth());carrier.cf6Type61FieldWave=4;carrier._x=300;carrier.Z轴坐标=200;carrier.hp=Number.NaN;
        Cf6Type61Service.enemyFieldReward(carrier);check(spawns.length==2,"NaN death cannot claim field buff");
        carrier.hp=0;Cf6Type61Service.enemyFieldReward(carrier);check(spawns.length==3,"finite carrier death grants its one buff");
        Cf6Type61Service.enemyFieldReward(carrier);Cf6Type61Service.queueField(world,4,"primary");
        for(i=0;i<320;i++) api.tickField(world);
        check(spawns.length==3,"repeated death, wave start and fallback timer cannot duplicate entities");
        delete world.__cf6Type61Field;Cf6Type61Service.queueField(world,4,"primary");Cf6Type61Service.finishField(world,4);
        check(spawns.length==3,"recreated field watcher honors persisted issued identities");
        scene("A20");Cf6Type61Service.queueField(world,6,"primary");Cf6Type61Service.queueField(world,6,"robot");Cf6Type61Service.interceptClear(manager,world);
        check(spawns.length==9,"quick final clear flushes distinct human and robot phase allowances");
        var ids:Object={},unique:Boolean=true;
        for(i=0;i<spawns.length;i++) {if(ids[spawns[i].id])unique=false;ids[spawns[i].id]=true;}
        check(unique,"all emitted categories and phases own distinct one-time pickup identities");
        _root._saveExt.bookRun.routeId="historical";Cf6Type61Service.queueField(world,5,"primary");api.tickField(world);
        check(spawns.length==9,"historical route never receives Type61 field supplies");_root._saveExt.bookRun.routeId="type61";
    }
    private static function testSale():Void {
        ItemUtil.itemDataDict["出售测试枪"]={name:"出售测试枪",type:"武器",use:"长枪",price:10000,data:{level:35}};
        ItemUtil.equipmentDict["出售测试枪"]=true;
        var item:Object={name:"出售测试枪",value:{level:11,mods:[]}};
        var quote:Object=_root.物品UI函数.计算售卖总价(item,1);
        check(quote.总价==2500 && quote.强化收益==0,"single enhanced weapon sells for quarter base price only");
        check(_root.物品UI函数.计算售卖总价(item,2).总价==5000,"batch sale uses the same base-price rule");
        _root.主角被动技能.口才={启用:true,等级:10};
        check(_root.物品UI函数.计算售卖总价(item,1).总价==2500,"unexpected eloquence state cannot restore equipment sale arbitrage");
        _root._saveExt.bookRun.routeId="historical";
        check(_root.物品UI函数.计算售卖总价(item,1).总价>2500,"historical sale pricing remains untouched");
        _root._saveExt.bookRun.routeId="type61";
    }
    private static function testCurrency():Void {
        var rngType:Object=org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
        var oldRng:Object=rngType.instance;
        var depthType:Object=org.flashNight.gesh.depth.DepthManager,oldDepth:Object=depthType.instance;
        var weatherType:Object=org.flashNight.arki.weather.WeatherSystem,oldWeather:Function=weatherType.getInstance;
        var oldAttach:Function=world.attachMovie,oldPickup:Object=_root.pickupItemManager;
        var pickup:org.flashNight.arki.unit.Action.PickUp.PickUpManager;
        var run:Object=_root._saveExt.bookRun;
        try {
            rngType.instance={randomCheck:function(n:Number):Boolean {return true;},randomInteger:function(lo:Number,hi:Number):Number {return lo;},random:function(bound:Number):Number {return 100;}};
            depthType.instance={updateDepth:function(target:Object,y:Number):Void {}};
            weatherType.getInstance=function():Object {return {coinTimeMultiplier:1};};
            _root.isEasyMode=function():Boolean {return false;};_root.打怪掉钱机率=6;
            _root.getItemData=function(name:String):Object {return {displayname:name};};
            world.attachMovie=function(linkage:String,name:String,depth:Number,params:Object):MovieClip {
                var mc:MovieClip=this.createEmptyMovieClip(name,depth);
                for(var key:String in params) mc[key]=params[key];
                mc.焦点高亮框=mc.createEmptyMovieClip("focus",1);return mc;
            };
            pickup=new org.flashNight.arki.unit.Action.PickUp.PickUpManager();_root.pickupItemManager=pickup;
            pickup.createCollectible("金钱",1000,100,200,false,{敌人死亡货币:true});
            check(world.可拾取物0.物品名=="K点" && world.可拾取物0.数量==1000,"only marked Type61 death money uses the existing random K conversion");
            pickup.createCollectible("金币",500000,100,200,false,{精确货币数量:true});
            check(world.可拾取物1.物品名=="金钱" && world.可拾取物1.数量==500000,"fixed large cash remains exact despite level cap and forced K RNG");
            pickup.createCollectible("金币",5,100,200,false,{精确货币数量:true});
            check(world.可拾取物2.数量==5,"fixed small cash does not receive random-drop padding");
            pickup.createCollectible("金钱",1000,100,200,false,{});
            check(world.可拾取物3.物品名=="金钱","unmarked Type61 fixed source cannot be converted");
            pickup.createCollectible("K点",2,100,200,false,{});
            check(world.可拾取物4.物品名=="K点" && world.可拾取物4.数量==2,"book fixed K still bypasses small-drop padding");
            run.routeId="historical";pickup.createCollectible("金钱",1000,100,200,false,{敌人死亡货币:true});
            check(world.可拾取物5.物品名=="金钱","historical death currency protection is unchanged");
            run.bookId="repair-campus";_root.当前关卡名="书中历险-修理大学";
            // The campus name is taken from its canonical definition, not assumed from the UI title.
            _root.当前关卡名=String(BookDefinition.get("repair-campus").stageName);
            pickup.createCollectible("金钱",1000,100,200,false,{敌人死亡货币:true});
            check(world.可拾取物6.物品名=="金钱","campus death currency protection is unchanged");
            run.bookId="cf6-sting";run.routeId="type61";_root.当前关卡名="书中历险-毒刺行动";
            var enemy:Object={hp:0,hp满血值:2000,_x:100,_y:200,不掉钱:false};
            _root.敌人函数.随机掉钱.call(enemy);
            check(world.可拾取物7.敌人死亡货币===true && world.可拾取物7.物品名=="K点","actual enemy death helper supplies the provenance marker");
            delete _root._saveExt.bookRun;pickup.createCollectible("金钱",1000,100,200,false,{});
            check(world.可拾取物8.物品名=="K点","ordinary world retains its original conversion rule");
        } finally {
            _root._saveExt.bookRun=run;run.bookId="cf6-sting";run.routeId="type61";_root.当前关卡名="书中历险-毒刺行动";
            if(pickup!=null)pickup.destroy();world.attachMovie=oldAttach;_root.pickupItemManager=oldPickup;
            rngType.instance=oldRng;depthType.instance=oldDepth;weatherType.getInstance=oldWeather;
        }
    }
}
