/** 策划语义键到旧兵种类型的索引。展示名、素材 linkage 不作为身份别名。 */
class org.flashNight.arki.unit.UnitRegistry {
    private static var typesByKey:Object = null;
    private static var maxId:Number = 2147483647;

    public static function initialize(units:Array):Void {
        // Failed reloads must not leave the previous semantic catalog usable.
        typesByKey = null;
        if (!(units instanceof Array) || units.length == 0) {
            throw new Error("Unit registry must be a non-empty array");
        }
        var next:Object = {};
        var seenIds:Object = {};
        next.__proto__ = null;
        seenIds.__proto__ = null;
        for (var i:Number = 0; i < units.length; i++) {
            var unit:Object = units[i];
            var id:Number = unit.id;
            if (typeof unit.id != "number" || isNaN(id) || id < 0
                    || id > maxId || id != Math.floor(id)) {
                throw new Error("Invalid unit id at " + i);
            }
            var legacy:String = "兵种" + id;
            if (seenIds[legacy] === true) throw new Error("Duplicate unit id: " + id);
            seenIds[legacy] = true;
            if (typeof unit.spritename != "string" || unit.spritename == "") {
                throw new Error("Missing unit spritename: " + id);
            }
            if (unit.hasOwnProperty("key")) {
                if (!validKey(unit.key)) throw new Error("Invalid unit key: " + id);
                if (next[unit.key] !== undefined) throw new Error("Duplicate unit key: " + unit.key);
                next[unit.key] = legacy;
            }
        }
        typesByKey = next;
    }

    /** Legacy existence remains checked against the actual 兵种库 by StageInfo. */
    public static function resolveType(reference):String {
        if (typeof reference != "string") throw new Error("Unit reference must be a string");
        if (isLegacyType(reference)) return reference;
        if (!validKey(reference) || typesByKey === null || typesByKey === undefined
                || typesByKey[reference] === undefined) {
            throw new Error("Unknown unit reference: " + reference);
        }
        return String(typesByKey[reference]);
    }

    public static function isLegacyType(value:String):Boolean {
        if (value.length < 3 || value.length > 12 || value.substr(0, 2) != "兵种") return false;
        if (value.length > 3 && value.charAt(2) == "0") return false;
        for (var i:Number = 2; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 48 || code > 57) return false;
        }
        return Number(value.substr(2)) <= maxId;
    }

    public static function validKey(value):Boolean {
        if (typeof value != "string" || value.length == 0 || value.length > 96) return false;
        var first:Number = value.charCodeAt(0);
        if (!isLetter(first)) return false;
        var parts:Array = value.split(".");
        if (parts.length < 2) return false;
        for (var i:Number = 0; i < parts.length; i++) {
            var part:String = parts[i];
            if (part == "" || part == "__proto__" || part == "prototype" || part == "constructor") return false;
            for (var j:Number = 0; j < part.length; j++) {
                var code:Number = part.charCodeAt(j);
                if (!(isLetter(code) || (code > 47 && code < 58)
                        || code == 95 || code == 45 || (i > 0 && code == 183))) return false;
            }
        }
        return true;
    }

    private static function isLetter(code:Number):Boolean {
        return (code > 64 && code < 91) || (code > 96 && code < 123)
            || (code > 13311 && code < 40960);
    }
}
