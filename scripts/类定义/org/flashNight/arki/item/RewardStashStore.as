import org.flashNight.gesh.object.PersistedSnapshot;

/** v2 当前奖励库存的纯数据合同。没有 _root、SaveManager、面板或领取会话副作用。 */
class org.flashNight.arki.item.RewardStashStore {
    public static var VERSION:Number = 2;
    public static var TAKE_LIMIT:Number = 32;
    public static var PAGE_SIZE:Number = 32;
    private static var MAX_INTEGER:Number = 9007199254740991;

    public static function create(storeId:String, legacy:Object):Object {
        return {v:2, storeId:storeId, commitRevision:0, sequence:0,
            entries:[], lastCommit:null, legacy:legacy};
    }

    /** Candidate arrays are private; stock rows are replaced, never edited in place. */
    public static function candidate(raw:Object):Object {
        var copy:Object = {};
        for(var key:String in raw) {
            if (key == "entries") copy.entries = raw.entries instanceof Array ? raw.entries.slice() : PersistedSnapshot.clone(raw.entries);
            else copy[key] = PersistedSnapshot.clone(raw[key]);
        }
        // A known AMF shape repair also replaces its row, preserving the committed before-image.
        if(copy.entries instanceof Array) for(var i:Number=0;i<copy.entries.length;i++) {
            var row:Object=copy.entries[i];
            if(row != null && emptyObject(row.item.value.mods)) copy.entries[i]=PersistedSnapshot.clone(row);
        }
        return copy;
    }

    /** 只归一化已知空数组形状；非空错误对象原样保留并拒绝写入。 */
    public static function normalize(raw:Object):Object {
        if (raw == null || raw.v !== 2) return {ok:false, changed:false, error:"future_reward_inbox"};
        var changed:Boolean = false;
        var repairs:Array = [];
        var entries:Object = raw.entries;
        if (emptyObject(entries)) { entries = []; repairs.push({owner:raw,key:"entries",value:entries}); changed = true; }
        if (typeof raw.storeId != "string" || raw.storeId.length == 0
                || !whole(raw.commitRevision) || !whole(raw.sequence)
                || !(entries instanceof Array)) {
            return {ok:false, changed:changed, error:"malformed_reward_stash"};
        }
        var seen:Object = {};
        var stacks:Object = {};
        for (var i:Number = 0; i < entries.length; i++) {
            var row:Object = entries[i];
            var checkedItem:Object = row == null ? null : row.item;
            if (row != null && row.item != null && typeof row.item.value == "object"
                    && emptyObject(row.item.value.mods)) {
                checkedItem = PersistedSnapshot.clone(row.item); checkedItem.value.mods = [];
                repairs.push({owner:row.item.value,key:"mods",value:[]}); changed = true;
            }
            if (row == null || typeof row.entryId != "string" || row.entryId.length == 0
                    || seen["$" + row.entryId] === true || !whole(row.revision)
                    || row.revision < 1 || !validItem(checkedItem)) {
                return {ok:false, changed:changed, error:"malformed_reward_stash_entry"};
            }
            var prefix:String = raw.storeId + ".e";
            var suffix:String = String(row.entryId).substr(prefix.length);
            var identity:Number = Number(suffix);
            if (String(row.entryId).indexOf(prefix) != 0 || !whole(identity) || identity < 1
                    || String(identity) !== suffix || identity > raw.sequence) return {ok:false, changed:changed, error:"malformed_stash_identity"};
            if (typeof row.item.value == "number") {
                if (stacks["$" + row.item.name] === true) return {ok:false, changed:changed, error:"duplicate_stash_stack"};
                stacks["$" + row.item.name] = true;
            }
            seen["$" + row.entryId] = true;
        }
        if (raw.lastCommit != null) {
            var receipt:Object = raw.lastCommit;
            if (typeof receipt.operationId != "string" || typeof receipt.fingerprint != "string"
                    || !whole(receipt.beforeRevision) || !whole(receipt.afterRevision)
                    || receipt.afterRevision != raw.commitRevision
                    || receipt.afterRevision != receipt.beforeRevision + 1
                    || receipt.result == null || typeof receipt.result != "object") {
                return {ok:false, changed:changed, error:"malformed_reward_stash_receipt"};
            }
            var arrays:Array = ["accepted", "blocked", "packages"];
            for (var a:Number = 0; a < arrays.length; a++) {
                if (emptyObject(receipt.result[arrays[a]])) {
                    repairs.push({owner:receipt.result,key:arrays[a],value:[]}); changed = true;
                }
            }
        }
        for (var fix:Number = 0; fix < repairs.length; fix++) repairs[fix].owner[repairs[fix].key] = repairs[fix].value;
        return {ok:true, changed:changed, feature:raw};
    }

    public static function validItem(item:Object):Boolean {
        if (item == null || typeof item.name != "string" || item.name.length == 0
                || typeof item.lastUpdate != "number" || !isFinite(item.lastUpdate)) return false;
        if (typeof item.value == "number") return whole(item.value) && item.value > 0;
        if (item.value != null && item.value.mods instanceof Array) {
            for (var m:Number = 0; m < item.value.mods.length; m++)
                if (typeof item.value.mods[m] != "string" || item.value.mods[m].length == 0) return false;
        }
        return typeof item.value == "object" && item.value != null
            && !(item.value instanceof Array) && typeof item.value.level == "number"
            && whole(item.value.level) && item.value.level > 0
            && item.value.mods instanceof Array;
    }

    public static function quantity(item:Object):Number {
        return typeof item.value == "number" ? Number(item.value) : 1;
    }

    /** 在调用者拥有的候选上追加。装备逐实例，数字值物品按名字跨批次合并。 */
    public static function append(store:Object, items:Array):Boolean {
        if (store == null || store.v !== 2 || !(items instanceof Array)) return false;
        // 先全部校验和规划溢出，避免非法尾项造成前半批可见。
        var totals:Object = {};
        var indexes:Object = {};
        for (var i:Number = 0; i < store.entries.length; i++) {
            var existing:Object = store.entries[i];
            if (typeof existing.item.value == "number") {
                totals["$" + existing.item.name] = existing.item.value;
                indexes["$" + existing.item.name] = i;
            }
        }
        for (var j:Number = 0; j < items.length; j++) {
            var item:Object = items[j];
            if (!validItem(item)) return false;
            if (typeof item.value == "number") {
                var totalKey:String = "$" + item.name;
                var previous:Number = totals[totalKey] == undefined ? 0 : Number(totals[totalKey]);
                if (item.value > MAX_INTEGER - previous) return false;
                totals[totalKey] = previous + item.value;
            }
        }
        if (items.length > MAX_INTEGER - Number(store.sequence)) return false;
        for (var rk:String in indexes) if (items.length > MAX_INTEGER - store.entries[Number(indexes[rk])].revision) return false;
        for (var k:Number = 0; k < items.length; k++) {
            var next:Object = PersistedSnapshot.clone(items[k]);
            var key:String = "$" + next.name;
            var index = typeof next.value == "number" ? indexes[key] : undefined;
            if (index !== undefined) {
                var target:Object = PersistedSnapshot.clone(store.entries[Number(index)]);
                store.entries[Number(index)] = target;
                target.item.value += next.value;
                target.item.lastUpdate = Math.max(target.item.lastUpdate, next.lastUpdate);
                target.revision++;
            } else {
                store.sequence++;
                var row:Object = {entryId:store.storeId + ".e" + store.sequence,
                    revision:1, item:next};
                store.entries.push(row);
                if (typeof next.value == "number") indexes[key] = store.entries.length - 1;
            }
        }
        return true;
    }

    public static function find(store:Object, entryId:String):Object {
        if (store == null || !(store.entries instanceof Array)) return null;
        for (var i:Number = 0; i < store.entries.length; i++) {
            if (store.entries[i].entryId === entryId) return store.entries[i];
        }
        return null;
    }

    public static function removeQuantity(store:Object, entryId:String, count:Number):Boolean {
        var row:Object = find(store, entryId);
        if (row == null || !whole(count) || count < 1 || count > quantity(row.item)) return false;
        if (typeof row.item.value == "number" && count < row.item.value) {
            if (row.revision >= MAX_INTEGER) return false;
            var updated:Object = PersistedSnapshot.clone(row);
            updated.item.value -= count;
            updated.revision++;
            for(var position:Number=0;position<store.entries.length;position++)
                if(store.entries[position] === row) { store.entries[position] = updated; break; }
            return true;
        }
        for (var i:Number = 0; i < store.entries.length; i++) {
            if (store.entries[i] === row) { store.entries.splice(i, 1); return true; }
        }
        return false;
    }

    /** 丢失/过期 receipt 永远不能重新 admit：expectedRevision 必须仍等于当前修订。 */
    public static function inspectCommand(store:Object, storeId:String, expectedRevision:Number,
                                          operationId:String, fingerprint:String):Object {
        if (store == null || store.v !== 2 || store.storeId !== storeId) return {state:"stale"};
        var last:Object = store.lastCommit;
        if (last != null && last.operationId === operationId) {
            if (last.fingerprint !== fingerprint || last.beforeRevision !== expectedRevision) return {state:"conflict"};
            return {state:"committed", result:PersistedSnapshot.clone(last.result)};
        }
        if (store.commitRevision !== expectedRevision || !whole(expectedRevision + 1)) return {state:"stale"};
        return {state:"fresh"};
    }

    public static function recordCommit(store:Object, operationId:String,
                                         fingerprint:String, result:Object):Void {
        var before:Number = Number(store.commitRevision);
        if (!whole(before) || before >= MAX_INTEGER) throw new Error("stash_revision_exhausted");
        store.commitRevision = before + 1;
        store.lastCommit = {operationId:operationId, fingerprint:fingerprint,
            beforeRevision:before, afterRevision:store.commitRevision,
            result:PersistedSnapshot.clone(result)};
    }

    public static function ownedQuantity(store:Object, itemName:String):Number {
        var total:Number = 0;
        if (store == null || store.v !== 2 || !(store.entries instanceof Array)) return 0;
        for (var i:Number = 0; i < store.entries.length; i++) {
            var item:Object = store.entries[i].item;
            if (item.name === itemName) total += quantity(item);
        }
        return total;
    }

    public static function whole(value:Object):Boolean {
        return typeof value == "number" && isFinite(Number(value))
            && Number(value) >= 0 && Number(value) <= MAX_INTEGER
            && Math.floor(Number(value)) === Number(value);
    }

    public static function emptyObject(value:Object):Boolean {
        if (value == null || typeof value != "object" || value instanceof Array) return false;
        for (var key:String in value) return false;
        return true;
    }
}
