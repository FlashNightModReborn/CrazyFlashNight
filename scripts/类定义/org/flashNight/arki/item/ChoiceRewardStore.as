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
                        || !(option.items instanceof Array) || option.items.length < 1 || option.items.length > 16) return false;
                seen["$" + option.optionId] = true;
                for (var n:Number = 0; n < option.items.length; n++) {
                    var item:Object = option.items[n];
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
