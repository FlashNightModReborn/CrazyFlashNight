/**
 * Detaches serialization-shaped data without writing Dictionary IDs onto source objects.
 * Repeated aliases become independent values. Cycles and excessive depth fail before a
 * candidate is published; this is deliberately not a general runtime-object clone.
 */
class org.flashNight.gesh.object.PersistedSnapshot {
    public static function clone(value:Object):Object {
        return copyValue(value,0,{remaining:524288});
    }
    /** Persistence-shaped copy keeps unknown serialized fields, including __ names. */
    public static function cloneData(value:Object):Object {
        return copyData(value, 0, {remaining:524288}, []);
    }
    /** AS2 Array(value) wraps value; use a typed copy instead of a constructor cast. */
    public static function cloneArrayData(value:Array):Array {
        var copy:Object = cloneData(value);
        var result:Array = [];
        result.length = value.length;
        for (var key:String in copy) result[key] = copy[key];
        return result;
    }
    private static function copyData(value:Object, depth:Number, budget:Object, path:Array):Object {
        if (typeof value == "movieclip") throw new Error("snapshot_runtime_object");
        if (typeof value == "function") return undefined; // AMF does not persist function bodies.
        if (value == null || typeof value != "object") return value;
        if (depth > 64 || --budget.remaining < 0) throw new Error("snapshot_shape_budget");
        for (var ancestor:Number = 0; ancestor < path.length; ancestor++) {
            if (path[ancestor] === value) throw new Error("snapshot_cycle");
        }
        if (value instanceof Date) return new Date(value.getTime());
        if (value instanceof XML) return new XML(value.toString());
        path.push(value);
        var result:Object = value instanceof Array ? [] : {};
        if (value instanceof Array) {
            for (var index:Number = 0; index < value.length; index++) {
                result[index] = copyData(value[index], depth + 1, budget, path);
            }
        }
        for (var key:String in value) {
            var numericKey:Number = Number(key);
            if (value instanceof Array && !isNaN(numericKey) && numericKey >= 0 && numericKey < value.length
                    && numericKey == Math.floor(numericKey) && String(numericKey) == key) continue;
            if (Object.prototype.hasOwnProperty.call(value, key) && typeof value[key] != "function") {
                // Arrays may also carry named AMF properties; do not erase them.
                result[key] = copyData(value[key], depth + 1, budget, path);
            }
        }
        path.pop();
        return result;
    }
    private static function copyValue(value:Object, depth:Number, budget:Object):Object {
        if (value == null || typeof value != "object") return value;
        if (depth > 64 || --budget.remaining < 0) throw new Error("snapshot_shape_budget");
        if (value instanceof Date) return new Date(value.getTime());
        var result:Object;
        if (value instanceof Array) {
            result = [];
            for(var i:Number=0;i<value.length;i++) {
                var element:Object=value[i];
                result[i]=element == null || typeof element != "object" ? element : copyValue(element,depth+1,budget);
            }
        } else {
            result = {};
            for(var key:String in value) {
                if(value.hasOwnProperty(key) && !(key.charCodeAt(0)==95 && key.charCodeAt(1)==95)) {
                    var field:Object=value[key];
                    result[key]=field == null || typeof field != "object" ? field : copyValue(field,depth+1,budget);
                }
            }
        }
        return result;
    }
}
