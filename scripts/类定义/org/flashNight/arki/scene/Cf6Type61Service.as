import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.scene.BookRunService;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.gesh.object.PersistedSnapshot;

/** 61路线固定配额只由此域交付；保存未知时查原操作，清场不能绕过候选。 */
class org.flashNight.arki.scene.Cf6Type61Service {
    private static var room:Object;
    private static var watchClip:MovieClip;
    private static var pendingClear:Object;

    private static function whole(value,low:Number,high:Number):Boolean {
        return typeof value == "number" && !isNaN(value) && isFinite(value) && Math.floor(value) == value && value >= low && value <= high;
    }
    public static function validDefinition(data:Object):Boolean {
        var c:Object=data.type61;
        if (c == null || !(c.checkpoints instanceof Array) || c.checkpoints.length != 19 || c.deliveryItems == null
                || !(c.ammoCatalog instanceof Array) || c.ammoCatalog.length != 13
                || !(c.fieldSupplies instanceof Array) || c.fieldSupplies.length != 59
                || !(c.shopIds instanceof Array) || c.shopIds.length != 6
                || !(c.choicePoolIds instanceof Array) || c.choicePoolIds.length != 11
                || !(c.learnableSkills instanceof Array) || c.learnableSkills.length < 1 || c.learnableSkills.length > 80
                || !(c.midMods instanceof Array) || c.midMods.length != 3 || c.recipeUnlocks == null) return false;
        if (c.initialConstellationNode !== "TUTORIAL" || !(c.ordinaryConstellations instanceof Array)
                || c.ordinaryConstellations.length != 4) return false;
        var constellations:Array=["光剑天秤","光斧金牛","光刀狮子","光刃摩羯"];
        for (var star:Number=0;star<4;star++) if(c.ordinaryConstellations[star] !== constellations[star]) return false;
        var sums:Object={money:0,kpoints:0,stones:0,skillPoints:0};
        var seen:Object={}, level:Number=35;
        var nodes:Array=["TUTORIAL"];
        for (var i:Number=0;i<c.checkpoints.length;i++) {
            var row:Object=c.checkpoints[i], id:String="A"+(i<9 ? "0" : "")+String(i+1);
            if (row.mapId !== id || !whole(row.level,level+1,60)) return false;
            level=row.level;nodes.push(id);
            for (var name:String in sums) {
                if (!whole(row[name],0,4000000)) return false;
                sums[name]+=row[name];
            }
        }
        if (level !== 60 || sums.money !== 4720000 || sums.kpoints !== 100000 || sums.stones !== 10000 || sums.skillPoints !== 1640) return false;
        var itemNodes:Number=0;
        for (var node:String in c.deliveryItems) {if (!contains(nodes,node)) return false;itemNodes++;}
        if (itemNodes != 20) return false;
        for (i=0;i<nodes.length;i++) {
            var items:Array=c.deliveryItems[nodes[i]],stoneCount:Number=0;
            if (!(items instanceof Array) || items.length > 32) return false;
            for (var j:Number=0;j<items.length;j++) {
                var item:Object=items[j];
                if (typeof item.name != "string" || item.name == "" || length(item.name) > 96 || !whole(item.count,1,10000)
                        || contains(["金币","金钱","K点","技能点","经验值"],item.name)) return false;
                if (item.name === "强化石") stoneCount+=item.count;
            }
            if (stoneCount !== (i==0 ? 0 : c.checkpoints[i-1].stones)) return false;
        }
        var highs:Number=0;
        for (i=0;i<c.fieldSupplies.length;i++) {
            var field:Object=c.fieldSupplies[i];
            var key:String=field.map+"."+field.wave+"."+field.phase;
            if (typeof field.high != "boolean" || !whole(field.wave,1,6) || typeof field.map != "string"
                    || !(contains(nodes,field.map) || field.map === "A20") || field.map === "TUTORIAL"
                    || (field.phase !== "primary" && !(field.phase === "robot" && field.map === "A20" && field.wave === 6))
                    || seen[key] === true) return false;
            seen[key]=true;if (field.high) highs++;
        }
        if (highs != 29) return false;
        var tables:Array=[c.ammoCatalog,c.shopIds,c.choicePoolIds,c.learnableSkills,c.midMods];
        for (var t:Number=0;t<tables.length;t++) {
            seen={};
            for (i=0;i<tables[t].length;i++) {
                var value=tables[t][i];
                if (typeof value != "string" || value == "" || length(value)>96 || seen["v."+value] === true) return false;
                seen["v."+value]=true;
                if (t==1 && value.indexOf("书中-CF6六一-") !== 0 || t==2 && value.indexOf("cf6.type61.") !== 0
                        || t==3 && contains(["铁匠","口才","驾驶","烹饪","解密"],value)) return false;
            }
        }
        return true;
    }

    public static function isActive():Boolean {
        var run:Object=_root._saveExt.bookRun;
        return run != null && run.bookId === "cf6-sting" && run.routeId === "type61"
            && run.outcome === "active" && run.slot === String(_root.savePath);
    }
    public static function skillAllowed(name:String):Boolean {
        if (!isActive()) return true;
        if (name == "铁匠" || name == "口才" || name == "驾驶" || name == "烹饪" || name == "解密") return false;
        var meta:Object=_root.技能表对象[name];
        var level:Number=Number(meta.UnlockLevel);
        return meta != null && whole(level,1,60) && whole(Number(_root.等级),1,60) && level <= Number(_root.等级);
    }
    public static function enhancementCap():Number {
        if (!isActive()) return -1;
        var claimed:Object=_root._saveExt.bookRun.type61Claims;
        return claimed.A16 === true ? 11 : claimed.A14 === true ? 9 : claimed.A08 === true ? 7 : 5;
    }
    private static function contains(rows:Array,name:String):Boolean {
        for (var i:Number=0;i<rows.length;i++) if (rows[i] === name) return true;
        return false;
    }
    public static function nodeReached(node:String):Boolean {
        if (!isActive() || !BookRunService.isBookStageContext()) return false;
        if (StageManager.instance == null) return false;
        var id:String=StageManager.instance.currentBookMapId();
        var currentIndex:Number=Number(id.substr(1)),required:Number=Number(node.substr(1));
        if (!whole(currentIndex,1,20) || !whole(required,1,20)
                || id !== "A"+(currentIndex<10 ? "0" : "")+String(currentIndex)
                || node !== "A"+(required<10 ? "0" : "")+String(required)) return false;
        return _root._saveExt.bookRun.type61Claims[node] === true || currentIndex >= required;
    }
    public static function shopAllowed(shopId:String):Boolean {
        var own:Boolean=shopId.indexOf("书中-CF6六一-") === 0;
        if (!isActive()) return !own;
        return own && contains(BookDefinition.get("cf6-sting","type61").type61.shopIds,shopId)
            && nodeReached(shopId.substr(length(shopId)-3));
    }
    /** 场内整备商人调用既有合成工作台；动作执行时再次核对本局和节点。 */
    public static function craftingCategory(npc:Object,actionId:String):String {
        if (!isActive() || typeof npc.NPC商店检索名 != "string"
                || !shopAllowed(npc.NPC商店检索名)) return "";
        if(actionId===undefined || actionId==="craft")
            return nodeReached(BookDefinition.get("cf6-sting","type61").type61.titaniumUpgrade.unlockNode)
                ? "书中配给" : nodeReached("A05") ? "进阶防具" : "武器合成";
        var categories:Object={craft_weapons:"武器合成",craft_plugins:"插件合成",craft_iron:"铁枪会",craft_necklace:"饰品合成",craft_armor:"进阶防具"};
        var prefixes:Object={craft_weapons:"craft.weapon.",craft_plugins:"craft.plugin.",craft_iron:"craft.iron-spear.",craft_necklace:"craft.accessory.",craft_armor:"craft.unified61."};
        var prefix=prefixes[actionId];
        if(typeof prefix!="string") return "";
        var unlocks:Object=BookDefinition.get("cf6-sting","type61").type61.recipeUnlocks;
        for(var id:String in unlocks) if(id.indexOf(prefix)===0 && nodeReached(unlocks[id])) return categories[actionId];
        return "";
    }
    public static function kShopAllowed(name:String):Boolean {
        if (!isActive()) return true;
        var config:Object=BookDefinition.get("cf6-sting","type61").type61;
        if (contains(config.kShopEarly,name)) return nodeReached("A01");
        var unlock=config.kShopUnlocks[name];
        if (typeof unlock == "string") return nodeReached(unlock);
        return nodeReached("A01") && contains(config.kShopEarly,name)
            || nodeReached("A11") && contains(config.kShopLate,name);
    }
    public static function recipeAllowed(id:String):Boolean {
        if (!isActive()) return id.indexOf("craft.cf6-type61.") !== 0;
        var node=BookDefinition.get("cf6-sting","type61").type61.recipeUnlocks[id];
        return typeof node == "string" && nodeReached(node);
    }
    public static function modOfferUsable(options:Array,gunOnly:Boolean):Boolean {
        if (!isActive()) return false;
        var containers:Array=[_root.物品栏.背包,_root.物品栏.装备栏];
        for (var c:Number=0;c<containers.length;c++) {
            var items:Object=containers[c].toObject();
            for (var key:String in items) {
                if (!ItemUtil.isEquipment(String(items[key].name))) continue;
                var item:BaseItem=BaseItem.createFromObject(PersistedSnapshot.clone(items[key]));
                var data:Object=item.getData();
                if (gunOnly && data.use !== "长枪" && data.use !== "手枪") continue;
                for (var o:Number=0;o<options.length;o++) for (var m:Number=0;m<options[o].items.length;m++)
                    if (org.flashNight.arki.item.EquipmentUtil.isModMaterialAvailable(item,data,String(options[o].items[m].name)) === 1) return true;
            }
        }
        return false;
    }
    /** 出生冻结；原生变身后继从仍活着的精确变身拥有者继承，主线继续读原难度。 */
    public static function enemyScale(target:Object):Number {
        if (!isActive() || !BookRunService.isBookStageContext() || target._parent !== _root.gameworld) return Number(_root.难度等级);
        var owner:Object=StageReturnFlow.worldIdentity(_root.gameworld);
        if (target.__cf6DifficultyOwner === owner && (target.__cf6DifficultyScale === 1 || target.__cf6DifficultyScale === 2.5)) return target.__cf6DifficultyScale;
        var scale:Number=target.cf6DifficultyScale === 2.5 ? 2.5 : 1;
        var targetName:String=String(target._name), world:MovieClip=_root.gameworld;
        if (target.cf6DifficultyScale === undefined && (target.elderSpawnIdentity != undefined
                || targetName.substr(length(targetName)-8) === "__tyrant")) for (var key:String in world) {
            var parent=world[key];
            if (typeof parent != "movieclip" || parent._parent !== _root.gameworld || parent.__cf6DifficultyOwner !== owner) continue;
            var elder:Boolean=target.elderSpawnIdentity != undefined;
            var phase:Object=elder ? parent.elderTransform : parent.guardTransform;
            if (phase == null || phase.active !== true || phase.attempted !== true || phase.retired === true || phase.error !== undefined
                    || phase.world !== _root.gameworld || phase.name !== target._name || phase.level !== target.等级 || phase.side !== target.是否为敌人
                    || phase.source !== target.产生源 || (phase.child != undefined && phase.child !== target)) continue;
            if (elder && (phase.spawnIdentity !== target.elderSpawnIdentity || phase.parentIdentity !== parent.elderIdentity
                    || phase.worldIdentity !== _root.gameworld.__elderWorldIdentity)) continue;
            if (!elder && target._name !== parent._name+"__tyrant") continue;
            if (parent.__cf6DifficultyScale === 2.5) scale=2.5;
            break;
        }
        target.__cf6DifficultyOwner=owner;target.__cf6DifficultyScale=scale;
        return scale;
    }
    public static function queueField(world:MovieClip,wave:Number,phase:String):Void {
        if (!isActive() || !BookRunService.isBookStageContext() || world !== _root.gameworld) return;
        var owner:Object=StageReturnFlow.worldIdentity(world), id:String=StageManager.instance.currentBookMapId();
        if (owner == null) return;
        var config:Object=BookDefinition.get("cf6-sting","type61").type61;
        var row:Object=null;
        for (var i:Number=0;i<config.fieldSupplies.length;i++) {
            var candidate:Object=config.fieldSupplies[i];
            if (candidate.map === id && candidate.wave === wave && candidate.phase === phase) {row=candidate;break;}
        }
        if (row == null) return;
        var state:Object=world.__cf6Type61Field;
        if (state == null) {state={owner:owner,run:PersistedSnapshot.clone(_root._saveExt.bookRun),mapId:id,events:[]};world.__cf6Type61Field=state;}
        if (state.owner !== owner || !BookRunRules.sameCf6Run(state.run,_root._saveExt.bookRun)) return;
        var key:String=id+"."+wave+"."+phase;
        for (i=0;i<state.events.length;i++) if (state.events[i].key === key) return;
        var seed:Number=(Number(state.run.seed)+Number(id.substr(1))*131+wave*29+(phase === "robot" ? 997 : 0)) % 2147483647;
        seed=(seed*48271)%2147483647;
        var hasBuff:Boolean=row.high === true || seed/2147483647 < 0.5;
        seed=(seed*48271)%2147483647;
        var buffs:Array=["61计划战场火力包","61计划战场机动包","61计划战场防护包"];
        state.events.push({key:key,wave:wave,phase:phase,age:0,high:row.high === true,
            buff:hasBuff ? buffs[Math.floor(seed/2147483647*3)] : "",finished:false});
    }
    private static function currentField(world:MovieClip):Object {
        var state:Object=world.__cf6Type61Field;
        return world === _root.gameworld && isActive() && state.owner === StageReturnFlow.worldIdentity(world)
            && BookRunRules.sameCf6Run(state.run,_root._saveExt.bookRun) ? state : null;
    }
    public static function finishField(world:MovieClip,wave:Number):Void {
        var state:Object=currentField(world);
        if (state == null) return;
        for (var i:Number=0;i<state.events.length;i++) if (state.events[i].wave === wave) state.events[i].finished=true;
        tickField(world);
    }
    public static function enemyFieldReward(target:Object):Void {
        var state:Object=currentField(_root.gameworld);
        var hp:Number=Number(target.hp);
        if (state == null || _root.暂停 || RewardStashService.pendingOperationId() != ""
                || target._parent !== _root.gameworld || !isFinite(hp) || isNaN(hp) || hp>0) return;
        for (var i:Number=0;i<state.events.length;i++) {
            var event:Object=state.events[i];
            if (event.phase === "primary" && target.cf6Type61FieldWave === event.wave && event.buff != "")
                emitField(state,event,"buff",event.buff,target);
        }
    }
    private static function tickField(world:MovieClip):Void {
        var state:Object=currentField(world);
        if (state == null || _root.暂停 || org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
                || RewardStashService.pendingOperationId() != "") return;
        var hero:Object=world[_root.控制目标];
        if (hero == null || !(Number(hero.hp)>0)) return;
        for (var i:Number=0;i<state.events.length;i++) {
            var event:Object=state.events[i];event.age++;
            if (event.high) {
                emitField(state,event,"heal","61计划战场急救包",hero);
                if (event.age>=90 || event.finished) emitField(state,event,"ammo","61计划战场弹药包",hero);
            }
            // Finite carrier kills are preferred; quick clears or an unspawned optional carrier cannot lose the allowance.
            if (event.buff != "" && (event.age>=300 || event.finished)) emitField(state,event,"buff",event.buff,hero);
        }
    }
    private static function emitField(state:Object,event:Object,kind:String,name:String,target:Object):Void {
        var run:Object=_root._saveExt.bookRun;
        var key:String=event.key+"."+kind;
        if (event[kind+"Issued"] === true || run.type61FieldIssued[key] === true) return;
        var x:Number=Number(target._x),y:Number=Number(target.Z轴坐标);
        if (!isFinite(y) || isNaN(y)) y=Number(target._y);
        if (!isFinite(x) || isNaN(x) || !isFinite(y) || isNaN(y) || _root.pickupItemManager == null) return;
        // Mark the attempt before entering a native creation callback. Unknown creation is never replayed.
        event[kind+"Issued"]=true;
        if (run.type61FieldIssued == null) run.type61FieldIssued={};
        run.type61FieldIssued[key]=true;
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark=true;
        _root.pickupItemManager.createCollectible(name,1,x,y,false,
            {一次性领取ID:"cf6.61."+run.seed+"."+run.startedAt+"."+key});
    }
    public static function beginRoom(world:MovieClip, owner:Object, mapId:String):Void {
        if (!isActive() || !BookRunService.isBookStageContext() || world !== _root.gameworld
                || owner == null || owner !== StageReturnFlow.worldIdentity(world)) return;
        if (current(room) && room.owner === owner) return;
        // A live unknown commit owns its pause even if an illegal caller attempts to replace the room.
        if (room != null && room.operationId != "" && RewardStashService.pendingOperationId() != "") return;
        release(room);
        var run:Object=_root._saveExt.bookRun;
        room={world:world,owner:owner,mapId:mapId,manager:StageManager.instance,
            stage:StageManager.instance.currentStage,slot:String(_root.savePath),
            runIdentity:PersistedSnapshot.clone(run),operationId:"",frames:0,failed:false,
            clearRequested:pendingClear != null && pendingClear.owner === owner
                && pendingClear.manager === StageManager.instance && pendingClear.stage === StageManager.instance.currentStage};
        pendingClear=null;
        if (watchClip == null || watchClip._name == undefined) watchClip=_root.createEmptyMovieClip("__cf6Type61",_root.getNextHighestDepth());
        watchClip.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6Type61Service.tick();};
    }
    private static function current(r:Object):Boolean {
        return r != null && r === room && isActive() && BookRunService.isBookStageContext()
            && r.world === _root.gameworld && r.owner === StageReturnFlow.worldIdentity(_root.gameworld)
            && r.slot === String(_root.savePath) && BookRunRules.sameCf6Run(r.runIdentity,_root._saveExt.bookRun)
            && r.manager === StageManager.instance && r.stage === r.manager.currentStage
            && r.manager.isActive === true && r.manager.isFailed !== true && r.manager.isFinished !== true;
    }
    public static function interceptClear(manager:Object, world:MovieClip):Boolean {
        if (!isActive()) return false;
        if (manager !== StageManager.instance || world !== _root.gameworld) return true;
        var field:Object=currentField(world);
        for (var f:Number=0;f<field.events.length;f++) field.events[f].finished=true;
        tickField(world);
        var id:String=String(manager.currentBookMapId());
        var checkpoint:Object=checkpointFor(id);
        // Tutorial still waits for its initial delivery, but the terminal boss has no economic grant.
        if (checkpoint == null && id != "TUTORIAL") return false;
        if (RewardStashService.pendingOperationId() == "" && _root._saveExt.bookRun.type61Claims[id] === true) return false;
        world.允许通行=false;
        if (current(room)) {
            room.clearRequested=true;
            if (room.lease == undefined) room.lease=PauseManager.lease(true,"cf6_type61_reward");
        }
        else pendingClear={owner:StageReturnFlow.worldIdentity(world),manager:manager,stage:manager.currentStage};
        return true;
    }
    private static function checkpointFor(id:String):Object {
        var rows:Array=BookDefinition.get("cf6-sting","type61").type61.checkpoints;
        for (var i:Number=0;i<rows.length;i++) if (rows[i].mapId === id) return rows[i];
        return null;
    }
    private static function release(r:Object):Void {
        if (r != null && r.lease != undefined) {PauseManager.releaseLease(r.lease);r.lease=undefined;}
    }
    public static function tick():Void {
        var r:Object=room;
        if (r == null) return;
        if (r.operationId != "") {
            // The only retry while unknown is a query of the same durable operation.
            if (++r.frames % 60 == 0 && RewardStashService.pendingOperationId() === r.operationId)
                RewardStashService.resume(r.operationId);
            return;
        }
        if (!current(r)) {release(r);room=null;delete watchClip.onEnterFrame;return;}
        if (r.failed || org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()) return;
        tickField(r.world);
        var claims:Object=_root._saveExt.bookRun.type61Claims;
        if (claims.TUTORIAL !== true) {deliver(r,"TUTORIAL");return;}
        if (!r.clearRequested) return;
        if (claims[r.mapId] !== true && checkpointFor(r.mapId) != null) {deliver(r,r.mapId);return;}
        r.clearRequested=false;
        try {r.manager.clearStage();} finally {release(r);}
    }
    private static function deliver(r:Object,id:String):Void {
        if (!current(r) || RewardStashService.pendingOperationId() != "") return;
        var config:Object=BookDefinition.get("cf6-sting","type61").type61;
        var row:Object=checkpointFor(id);
        if (id != "TUTORIAL" && row == null) return;
        var operation:String="cf6.61."+String(r.runIdentity.seed)+"."+String(r.runIdentity.startedAt)+"."+id;
        var context:Object={source:"cf6_type61",reason:"checkpoint",operationId:operation};
        r.operationId=operation;r.frames=0;
        if (r.lease == undefined) r.lease=PauseManager.lease(true,"cf6_type61_reward");
        var domain:Object={room:r,id:id,beforeLevel:Number(_root.等级)};
        try {domain.growthOwner=org.flashNight.arki.unit.Action.Regeneration.LevelUpRecovery.captureIntentOwner(operation);}
        catch (ownerError) {fail(r,"growth_owner_unavailable");return;}
        if (!RewardStashService.begin(operation,context,resolved,domain)) {
            r.operationId="";release(r);
            if (RewardStashService.lastError != "commit_pending") fail(r,RewardStashService.lastError);
            return;
        }
        try {
            var run:Object=_root._saveExt.bookRun;
            if (!BookRunRules.sameCf6Run(r.runIdentity,run) || run.type61Claims[id] === true) throw new Error("stale_checkpoint");
            var scalars:Array=[];
            if (row != null) {
                if (row.money > 0) scalars.push({name:"金币",value:row.money});
                if (row.kpoints > 0) scalars.push({name:"K点",value:row.kpoints});
                if (scalars.length > 0 && !ItemUtil.acquire(scalars,context)) throw new Error("invalid_currency_reward");
                var threshold:Number=Number(_root.根据等级得升级所需经验(row.level-1));
                if (!RewardStashStore.whole(threshold) || threshold < 1) throw new Error("invalid_growth_threshold");
                var gap:Number=Math.max(0,threshold-Number(_root.经验值));
                var growth:Array=[];
                if (gap > 0) growth.push({name:"经验值",value:gap});
                if (row.skillPoints > 0) growth.push({name:"技能点",value:row.skillPoints});
                if (growth.length > 0 && ItemUtil.require(growth) == null) throw new Error("invalid_growth_reward");
                _root.经验值+=gap;_root.技能点数+=row.skillPoints;
                if (gap > 0) PlayerAssetTransaction.recordEffect("gain","experience","经验值",gap,context);
                if (row.skillPoints > 0) PlayerAssetTransaction.recordEffect("gain","skillpoint","技能点",row.skillPoints,context);
                if (!applyGrowth()) throw new Error("invalid_growth_state");
            }
            var items:Array=config.deliveryItems[id];
            for (var i:Number=0;i<items.length;i++) {
                var item:BaseItem=BaseItem.create(resolveMainAmmo(String(items[i].name)),items[i].count);
                if (item == null || !RewardStashService.admit([item.toObject()],true,true,context)) throw new Error("invalid_checkpoint_item");
            }
            if (id === "TUTORIAL") {
                // The existing durable tutorial claim owns the random weapon too.
                // A retry of the same candidate never rerolls or grants a second copy.
                var starName:String=initialConstellation(config,run.seed);
                var starItem:BaseItem=BaseItem.create(starName,1);
                if (starItem == null || !ItemUtil.isEquipment(starName)
                        || !RewardStashService.admit([starItem.toObject()],true,true,context)) throw new Error("invalid_initial_constellation");
                if (run.type61Constellations == null) run.type61Constellations={};
                run.type61Constellations[starName]=true;
            }
            if (run.type61Claims == null) run.type61Claims={};
            run.type61Claims[id]=true;
            var result:Object=RewardStashService.end("cf6.type61.v1|"+id,
                {success:true,mapId:id},"reward.cf6_type61");
            if (result.success !== true && result.error != "commit_pending" && r.operationId != "") fail(r,String(result.error));
        } catch (error) {
            var cancelled:Object=RewardStashService.cancel("cf6_checkpoint_failed");
            if (cancelled.error != "commit_pending") fail(r,String(error));
        }
    }
    private static function initialConstellation(config:Object,seed:Number):String {
        if (!whole(seed,1,2147483646) || config.initialConstellationNode !== "TUTORIAL"
                || config.ordinaryConstellations.length != 4) return "";
        var roll:Number=(seed*48271)%2147483647;
        return config.ordinaryConstellations[Math.floor(roll/2147483647*4)];
    }
    private static function applyGrowth():Boolean {
        if (!RewardStashStore.whole(Number(_root.等级)) || !RewardStashStore.whole(Number(_root.经验值))
                || !RewardStashStore.whole(Number(_root.技能点数))) return false;
        while (_root.等级 < 60) {
            var required:Number=Number(_root.根据等级得升级所需经验(_root.等级));
            if (!RewardStashStore.whole(required) || required < 1) return false;
            if (_root.经验值 < required) break;
            var points:Number=Number(_root.根据等级计算获得技能点(Number(_root.等级)+1));
            if (!RewardStashStore.whole(points) || !RewardStashStore.whole(Number(_root.技能点数)+points)) return false;
            _root.等级++;_root.技能点数+=points;
        }
        _root.身价=_root.基础身价值*_root.等级;
        return true;
    }
    private static function resolveMainAmmo(name:String):String {
        if (name !== "突击步枪通用弹药") return name;
        var equipped:Object=_root.物品栏.装备栏.getItem("长枪");
        var actual:String=String(ItemUtil.getRawItemData(String(equipped.name)).data.clipname);
        var known:Array=BookDefinition.get("cf6-sting","type61").type61.ammoCatalog;
        if (contains(known,actual)) return actual;
        actual=String(_root._saveExt.bookRun.type61MainAmmo);
        return contains(known,actual) ? actual : name;
    }
    private static function resolved(committed:Boolean, domain:Object):Boolean {
        var r:Object=domain.room;
        r.operationId="";
        // Keep the vehicle/door from consuming its one-shot handoff before clearStage resumes.
        if (!committed || !r.clearRequested || !current(r)) release(r);
        if (!committed) {fail(r,"save_not_committed");return true;}
        if (!current(r)) return true;
        try {_root.投影已提交任务成长(domain.beforeLevel,domain.growthOwner);} catch (projectionError) {trace("[CF6 Type61] committed growth projection failed");}
        try {_root.发布消息(domain.id == "TUTORIAL" ? "61计划初始配给已到账，请在背包选择主枪并装备。" : domain.id+"配额已到账，可整备后前往出口。奖励暂存可领取背包未容纳的物品。");} catch (noticeError) { }
        return true;
    }
    private static function fail(r:Object, reason:String):Void {
        if (RewardStashService.pendingOperationId() != "") return;
        r.operationId="";r.failed=true;release(r);
        try {_root.发布消息("61计划配额未完成保存，出口保持关闭。请返回书架后重试。" );} catch (noticeError) { }
        trace("[CF6 Type61] checkpoint failed: "+reason);
    }
}
