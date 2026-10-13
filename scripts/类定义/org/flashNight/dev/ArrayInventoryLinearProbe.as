import org.flashNight.arki.item.itemCollection.*;

/** Query-only experiment. Structural writes retain the frozen baseline implementation. */
class org.flashNight.dev.ArrayInventoryLinearProbe extends org.flashNight.dev.ArrayInventoryTreeBaseline {
    public function ArrayInventoryLinearProbe(initial:Object, slotCapacity:Number) {
        super(initial, slotCapacity);
    }
    public function getIndexes():Array {
        var result:Array = [];
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit; slot++) {
            if (slotItems[slot] != null) result.push(slot);
        }
        return result;
    }
    public function getItemArray():Array {
        var result:Array = [];
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit; slot++) {
            var item:Object = slotItems[slot];
            if (item != null) result.push(item);
        }
        return result;
    }
    public function searchFirstKey(name:String):String {
        if (name == null || name == "") return undefined;
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit; slot++) {
            var item:Object = slotItems[slot];
            if (item != null && item.name == name) return String(slot);
        }
        return undefined;
    }
    public function getFirstVacancy():Number {
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit; slot++) {
            if (slotItems[slot] == null) return slot;
        }
        return -1;
    }
    public function getVacancies(amount:Number):Array {
        if (isNaN(amount)) amount = 16;
        var result:Array = [];
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit && result.length < amount; slot++) {
            if (slotItems[slot] == null) result.push(slot);
        }
        return result;
    }
    public function find(callback:Function) {
        if (typeof callback !== "function") return null;
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit; slot++) {
            var item:Object = slotItems[slot];
            if (item != null && callback(item)) return item;
        }
        return null;
    }
    public function findIndex(callback:Function):Number {
        if (typeof callback !== "function") return -1;
        var slotItems:Object = items;
        var limit:Number = capacity;
        for (var slot:Number = 0; slot < limit; slot++) {
            var item:Object = slotItems[slot];
            if (item != null && callback(item)) return slot;
        }
        return -1;
    }
}
