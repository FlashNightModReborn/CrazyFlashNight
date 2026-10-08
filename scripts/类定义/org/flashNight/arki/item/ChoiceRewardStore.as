import org.flashNight.gesh.object.PersistedSnapshot;

import org.flashNight.arki.item.RewardStashStore;

/** Pending choices live inside the durable reward store, never in the panel. */
class org.flashNight.arki.item.ChoiceRewardStore {
    public static var LIMIT:Number = 16;
    public static function text(value:Object, limit:Number):Boolean {
        if (typeof value != "string" || value.length < 1 || value.length > limit) return false;
        for (var i:Number = 0; i < value.length; i++) if (value.charCodeAt(i) < 32) return false;
        return true;
    }
    // 档级封闭枚举（与 tools/choice_reward_catalog.py 的 GRADES 同源）；旧冻结候选缺省合法。
    public static function isGrade(value:Object):Boolean {
        return value === "low" || value === "medium" || value === "high" || value === "special";
    }
    public static function normalize(raw:Object, storeId:String, deferredRepairs:Array):Boolean {
        if (raw === undefined) return true;
        if (raw == null || raw.v !== 1 || !RewardStashStore.whole(raw.sequence)) return false;
        var repairs:Array = [];
        var offers:Object = raw.offers;
        if (RewardStashStore.emptyObject(offers)) { offers = []; repairs.push({owner:raw,key:"offers",value:offers}); }
        if (!(offers instanceof Array) || offers.length > LIMIT) return false;
        var ids:Object = {};
        for (var i:Number = 0; i < offers.length; i++) {
            var o:Object = offers[i];
            if (o == null || !text(o.offerId, 160) || ids["$" + o.offerId] === true
                    || String(o.offerId).indexOf(storeId + ".choice.") != 0
                    || !text(o.poolId, 64) || !text(o.title, 96) || !text(o.ownerSlot, 128)
                    || !RewardStashStore.whole(o.poolVersion) || o.poolVersion < 1
                    || (o.scopeKind !== "character" && o.scopeKind !== "book")
                    || typeof o.bookId != "string" || typeof o.runIdentity != "string"
                    || (o.scopeKind == "book" && (!text(o.bookId, 64) || !text(o.runIdentity, 96)))
                    || (o.scopeKind == "character" && (o.bookId != "" || o.runIdentity != ""))
                    || !(o.options instanceof Array) || o.options.length < 2 || o.options.length > 4) return false;
            var suffix:String = String(o.offerId).substr((storeId + ".choice.").length);
            var identity:Number = Number(suffix);
            if (!RewardStashStore.whole(identity) || identity < 1 || identity > raw.sequence || String(identity) !== suffix) return false;
            ids["$" + o.offerId] = true;
            var seen:Object = {};
            for (var c:Number = 0; c < o.options.length; c++) {
                var option:Object = o.options[c];
                if (option == null || !text(option.optionId, 64) || seen["$" + option.optionId] === true
                        || !text(option.title, 64) || !text(option.description, 256)
                        || (option.kCost !== undefined && (!RewardStashStore.whole(option.kCost) || option.kCost > 1200))
                        || (option.grade !== undefined && !isGrade(option.grade))) return false;
                var skills:Object = option.skills === undefined ? [] : option.skills;
                if (RewardStashStore.emptyObject(skills)) { skills = []; repairs.push({owner:option,key:"skills",value:skills}); }
                if (!(skills instanceof Array) || skills.length > 2) return false;
                var skillIds:Object = {};
                for (var s:Number = 0; s < skills.length; s++) {
                    var skill:Object = skills[s];
                    if (!text(skill.skillKey,64) || skillIds["$"+skill.skillKey] === true
                            || !RewardStashStore.whole(skill.level) || skill.level < 1 || skill.level > 100) return false;
                    skillIds["$"+skill.skillKey] = true;
                }
                if (o.scopeKind != "book" && (skills.length > 0 || Number(option.kCost) > 0)) return false;
                var items:Object = option.items;
                if (RewardStashStore.emptyObject(items)) { items = []; repairs.push({owner:option,key:"items",value:items}); }
                if (!(items instanceof Array) || items.length > 16 || items.length == 0 && skills.length == 0) return false;
                seen["$" + option.optionId] = true;
                for (var n:Number = 0; n < items.length; n++) {
                    var item:Object = items[n];
                    var checked:Object = item;
                    if (item != null && typeof item.value == "object" && RewardStashStore.emptyObject(item.value.mods)) {
                        checked = PersistedSnapshot.clone(item); checked.value.mods = [];
                        repairs.push({owner:item.value,key:"mods",value:[]});
                    }
                    if (!RewardStashStore.validItem(checked)) return false;
                }
            }
        }
        for (var r:Number = 0; r < repairs.length; r++) {
            if (deferredRepairs != null) deferredRepairs.push(repairs[r]);
            else repairs[r].owner[repairs[r].key] = repairs[r].value;
        }
        return true;
    }
    public static function ensure(store:Object):Object {
        if (store.choiceOffers === undefined) store.choiceOffers = {v:1, sequence:0, offers:[]};
        return store.choiceOffers;
    }
    public static function find(raw:Object, offerId:String):Object {
        if (raw == null || !(raw.offers instanceof Array)) return null;
        for (var i:Number = 0; i < raw.offers.length; i++) if (raw.offers[i].offerId === offerId) return raw.offers[i];
        return null;
    }
}
