/**
 * Detaches serialization-shaped data without writing Dictionary IDs onto source objects.
 * Repeated aliases become independent values. Cycles and excessive depth fail before a
 * candidate is published; this is deliberately not a general runtime-object clone.
 */
class org.flashNight.gesh.object.PersistedSnapshot {
    public static function clone(value:Object):Object {
        return copyValue(value,0,{remaining:524288});
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
