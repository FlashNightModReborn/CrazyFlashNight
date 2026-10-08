import org.flashNight.gesh.object.PersistedSnapshot;

import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.ChoiceRewardDefinition;
import org.flashNight.arki.item.ChoiceRewardStore;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardStashStore;

/** Freeze, choose and admit share RewardStashService's full-save fence. */
class org.flashNight.arki.item.ChoiceRewardService {
    private static var _pools:Array;
    private static var _randomValues:Array;
    public static function pool(poolId:String, itemName:String):Object {
        if (_pools == null) _pools = ChoiceRewardDefinition.get();
        for (var i:Number = 0; i < _pools.length; i++)
            if (_pools[i].id === poolId && (itemName == "" || _pools[i].itemName === itemName)) return _pools[i];
        return null;
    }
    private static function scope(pool:Object):Object {
        var slot:String = String(_root.savePath);
        if (!ChoiceRewardStore.text(slot, 128) || slot == "undefined") return null;
        if (pool.scope.kind === "character") return {ownerSlot:slot, scopeKind:"character", bookId:"", runIdentity:""};
        var run:Object = _root._saveExt.bookRun;
        if (pool.scope.kind !== "book" || run == null || run.slot !== slot
                || run.bookId !== pool.scope.bookId || run.outcome !== "active"
                || !RewardStashStore.whole(run.seed) || run.seed < 1
                || !RewardStashStore.whole(run.startedAt) || run.startedAt < 1) return null;
        return {ownerSlot:slot, scopeKind:"book", bookId:run.bookId,
            runIdentity:String(run.seed) + "." + String(run.startedAt)};
    }
    private static function owns(offer:Object):Boolean {
        var current:Object = scope({scope:{kind:offer.scopeKind, bookId:offer.bookId}});
        return current != null && current.ownerSlot === offer.ownerSlot && current.runIdentity === offer.runIdentity;
    }
    private static function randomInt(bound:Number):Number {
        var value:Number = _randomValues != null && _randomValues.length > 0 ? Number(_randomValues.shift()) : Math.random();
        if (!isFinite(value) || value < 0 || value >= 1) throw new Error("invalid_choice_rng");
        return Math.floor(value * bound);
    }
    private static function skillEligible(skills:Array):Boolean {
        for (var i:Number = 0; i < skills.length; i++)
            if (!SkillLoadoutService.rewardSkillStatus(skills[i].skillKey, skills[i].level).success) return false;
        return true;
    }
    private static function ownedEquipment(name:String):Boolean {
        var sources:Array = [_root.物品栏.背包, _root.物品栏.装备栏];
        for (var c:Number = 0; c < sources.length; c++) {
            var items:Object = sources[c].toObject();
            for (var key:String in items) if (items[key].name === name) return true;
        }
        return RewardStashStore.ownedQuantity(RewardStashService.peek(),name) > 0;
    }
    private static function useful(entry:Object):Boolean {
        if (!skillEligible(entry.skills == null ? [] : entry.skills)) return false;
        if (entry.skills.length > 0) return true;
        for (var i:Number = 0; i < entry.entries.length; i++)
            if (!ItemUtil.isEquipment(entry.entries[i].itemName) || !ownedEquipment(entry.entries[i].itemName)) return true;
        return false;
    }
    private static function selectionResolved(committed:Boolean):Boolean {
        return SkillLoadoutService.resolveRewardSkills(committed);
    }
    public static function snapshot():Object {
        var store:Object = RewardStashService.committedFeature();
        var offers:Array = [];
        if (store != null && store.v === 2) {
            if (!ChoiceRewardStore.normalize(store.choiceOffers, String(store.storeId))) return {success:false,error:"invalid_choice_store"};
            var saved:Array = store.choiceOffers == null ? [] : store.choiceOffers.offers;
            for (var i:Number = 0; i < saved.length; i++) {
                var offer:Object = saved[i];
                if (!owns(offer)) continue;
                var options:Array = [];
                for (var c:Number = 0; c < offer.options.length; c++) {
                    var option:Object = offer.options[c], items:Array = [];
                    for (var n:Number = 0; n < option.items.length; n++) {
                        var item:Object = option.items[n];
                        var meta:Object = ItemUtil.itemDataDict[item.name];
                        // A detached copy is presentation only; never attach a candidate to inventory.
                        var preview:org.flashNight.arki.item.BaseItem = org.flashNight.arki.item.BaseItem.createFromObject(
                            org.flashNight.gesh.object.PersistedSnapshot.clone(item));
                        var detail:String = org.flashNight.gesh.tooltip.TooltipComposer.generateIntroPanelContent(preview, meta, item.value)
                            + org.flashNight.gesh.tooltip.TooltipComposer.generateItemDescriptionText(meta, preview);
                        detail = org.flashNight.gesh.string.StringUtils.htmlToPlainTextFast(detail);
                        items.push({itemName:item.name, displayName:String(meta.displayname || item.name),
                            quantity:RewardStashStore.quantity(item), level:Math.max(0, Number(meta.data.level) || 0),
                            icon:String(meta.icon || item.name), details:detail.substr(0, 4096)});
                    }
                    var skills:Array = [];
                    for (var s:Number = 0; s < option.skills.length; s++) {
                        var grant:Object = option.skills[s];
                        var state:Object = SkillLoadoutService.inspectSkill(grant.skillKey);
                        var metadata:Object = _root.技能表对象[grant.skillKey];
                        skills.push({skillKey:grant.skillKey,level:grant.level,currentLevel:SkillLoadoutService.committedRewardSkillLevel(grant.skillKey),
                            description:org.flashNight.gesh.string.StringUtils.htmlToPlainTextFast(String(metadata.Description || "")).substr(0,2048)});
                    }
                    var projectedOption:Object = {optionId:option.optionId, title:option.title, description:option.description, items:items,
                        skills:skills,kCost:option.kCost == undefined ? 0 : option.kCost,
                        available:RewardStashService.pendingOperationId() == "" && skillEligible(option.skills == null ? [] : option.skills)};
                    // 旧冻结候选没有 grade：读边降级省略，不把非法值投给 Host 白名单。
                    if (ChoiceRewardStore.isGrade(option.grade)) projectedOption.grade = option.grade;
                    options.push(projectedOption);
                }
                offers.push({offerId:offer.offerId, title:offer.title, options:options});
            }
        }
        return {success:true, storeId:store != null && store.v === 2 ? store.storeId : "",
            revision:store != null && store.v === 2 ? store.commitRevision : 0,
            offers:offers, kpoints:RewardStashService.committedKPoints(), pendingOperationId:RewardStashService.pendingOperationId()};
    }
    public static function open(params:Object, source:Object, definition:Object, fingerprint:String):Object {
        var binding:Object = scope(definition);
        if (binding == null) return {success:false,error:"choice_context_unavailable"};
        var store:Object = RewardStashService.peek();
        if (store != null && !ChoiceRewardStore.normalize(store.choiceOffers, String(store.storeId))) return {success:false,error:"invalid_choice_store"};
        if (store != null && store.choiceOffers != null
                && store.choiceOffers.offers.length >= ChoiceRewardStore.LIMIT) return {success:false,error:"choice_limit"};
        var context:Object = {source:"item_use", reason:"choice_open", operationId:params.operationId};
        if (!RewardStashService.begin(String(params.operationId), context, null, null)) return {success:false,error:RewardStashService.lastError};
        try {
            store = RewardStashService.peek();
            var saved:Object = ChoiceRewardStore.ensure(store);
            if (!RewardStashStore.whole(saved.sequence + 1)) return RewardStashService.cancel("choice_limit");
            saved.sequence++;
            var offer:Object = {offerId:store.storeId + ".choice." + saved.sequence,
                poolId:definition.id, poolVersion:definition.version, title:definition.title,
                ownerSlot:binding.ownerSlot, scopeKind:binding.scopeKind, bookId:binding.bookId,
                runIdentity:binding.runIdentity, options:[]};
            for (var g:Number = 0; g < definition.groups.length; g++) {
                var group:Object = definition.groups[g];
                var available:Array = [];
                for (var a:Number = 0; a < group.entries.length; a++) if (useful(group.entries[a])) available.push(group.entries[a]);
                for (var d:Number = 0; d < group.draw && available.length > 0; d++) {
                    var total:Number = 0;
                    for (var w:Number = 0; w < available.length; w++) total += available[w].weight;
                    var hit:Number = randomInt(total), index:Number = 0;
                    while (index < available.length - 1 && hit >= available[index].weight) { hit -= available[index].weight; index++; }
                    var chosen:Object = available.splice(index, 1)[0], frozen:Array = [];
                    // 目录由生成器校验过封闭枚举；编入产物若被改坏，按既有 invalid_reward_pack 失败关闭。
                    if (chosen.grade !== undefined && !ChoiceRewardStore.isGrade(chosen.grade)) return RewardStashService.cancel("invalid_reward_pack");
                    for (var e:Number = 0; e < chosen.entries.length; e++) {
                        var entry:Object = chosen.entries[e];
                        var item:BaseItem = BaseItem.create(String(entry.itemName), Number(entry.quantity));
                        if (item == null) return RewardStashService.cancel("invalid_reward_pack");
                        frozen.push(item.toObject());
                    }
                    var pushedOption:Object = {optionId:chosen.id, title:chosen.title, description:chosen.description, items:frozen,
                        skills:chosen.skills == null ? [] : PersistedSnapshot.clone(chosen.skills), kCost:chosen.kCost == undefined ? 0 : chosen.kCost};
                    if (chosen.grade !== undefined) pushedOption.grade = chosen.grade;
                    offer.options.push(pushedOption);
                }
            }
            saved.offers.push(offer);
            if (!ChoiceRewardStore.normalize(saved, String(store.storeId))) return RewardStashService.cancel("invalid_choice_store");
            var remaining:Number = Number(source.item.value) - 1;
            source.inventory.addValue(String(source.slot), -1);
            var after:Object = source.inventory.getItem(source.slot);
            if ((after == null ? 0 : Number(after.value)) !== remaining) return RewardStashService.cancel("stale_source");
            PlayerAssetTransaction.recordItems("loss", [{name:params.source.itemName, value:1}], context);
            return RewardStashService.end(fingerprint, {success:true,kind:"choiceOpen",offerId:offer.offerId,
                consumed:1,remaining:remaining}, "item_use.choice_open");
        } catch (choiceError) { return RewardStashService.cancel("invalid_reward_pack"); }
    }
    public static function choose(params:Object):Object {
        if (RewardStashService.pendingOperationId() != "") return {success:false,error:"commit_pending"};
        var fingerprint:String = new LiteJSON().stringify(["choice", params.storeId, params.expectedRevision, params.offerId, params.optionId]);
        var store:Object = RewardStashService.peek();
        var inspected:Object = RewardStashStore.inspectCommand(store, String(params.storeId), Number(params.expectedRevision), String(params.operationId), fingerprint);
        if (inspected.state === "committed") return inspected.result;
        if (inspected.state !== "fresh") return {success:false,error:"stale_stash"};
        if (!ChoiceRewardStore.normalize(store.choiceOffers, String(store.storeId))) return {success:false,error:"invalid_choice_store"};
        var offer:Object = ChoiceRewardStore.find(store.choiceOffers, String(params.offerId));
        if (offer == null) return {success:false,error:"stale_choice"};
        if (!owns(offer)) return {success:false,error:"choice_context_unavailable"};
        var option:Object = null;
        for (var c:Number = 0; c < offer.options.length; c++) if (offer.options[c].optionId === params.optionId) option = offer.options[c];
        if (option == null) return {success:false,error:"invalid_choice"};
        var cost:Number = option.kCost == undefined ? 0 : Number(option.kCost);
        if (!RewardStashStore.whole(_root.虚拟币) || _root.虚拟币 < cost) return {success:false,error:"insufficient_kpoints"};
        if (!skillEligible(option.skills == null ? [] : option.skills)) return {success:false,error:"no_reward_upgrade"};
        var context:Object = {source:"item_use", reason:"choice_select", operationId:params.operationId};
        if (!RewardStashService.begin(String(params.operationId), context, selectionResolved, null)) return {success:false,error:RewardStashService.lastError};
        try {
            if (option.skills.length > 0 && !SkillLoadoutService.prepareRewardSkills(option.skills)) return RewardStashService.cancel("invalid_skill_reward");
            _root.虚拟币 -= cost;
            if (cost > 0) PlayerAssetTransaction.recordCurrencyDeltas(0, -cost, context);
            var selectedItems:Array = option.items;
            if (!RewardStashService.admit(selectedItems, true, true, context)) return RewardStashService.cancel("invalid_reward_pack");
            var saved:Object = RewardStashService.peek().choiceOffers;
            for (var i:Number = 0; i < saved.offers.length; i++) if (saved.offers[i].offerId === params.offerId) { saved.offers.splice(i, 1); break; }
            return RewardStashService.end(fingerprint, {success:true,kind:"choiceSelect",offerId:params.offerId,
                optionId:params.optionId,rewardReady:true}, "item_use.choice_select");
        } catch (selectError) { return RewardStashService.cancel("invalid_reward_pack"); }
    }
    public static function setPoolsForTests(pools:Array):Void { _pools = pools; }
    public static function setRandomValuesForTests(values:Array):Void { _randomValues = values; }
}
