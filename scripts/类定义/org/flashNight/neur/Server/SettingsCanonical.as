import org.flashNight.neur.Server.SettingsCanonicalSchema;

/** Pure encoding of the actual fixed projection. It never rounds, fills, migrates or hashes. */
class org.flashNight.neur.Server.SettingsCanonical {
    public static function encode(settings:Object, keys:Array, savedRows:Boolean):String {
        if (settings == null || typeof settings != "object" || settings instanceof Array
                || !(keys instanceof Array) || keys.length != 36) return null;
        var fields:Array = SettingsCanonicalSchema.SETTING_IDS;
        var ownCount:Number = 0;
        for (var name:String in settings) {
            if (settings.hasOwnProperty(name)) ownCount++;
        }
        if (ownCount != 14) return null;
        var parts:Array = ["cf7.settings.payload.v1"];
        for (var i:Number = 0; i < 14; i++) {
            if (!settings.hasOwnProperty(fields[i])) return null;
            var value:Object = settings[fields[i]];
            var encoded:Number;
            if (isBooleanIndex(i)) {
                if (typeof value != "boolean") return null;
                encoded = value === true ? 1 : 0;
            } else if (i == 6) {
                if (typeof value != "number" || isNaN(value) || value < 0.5 || value > 3) return null;
                encoded = Math.round(value * 10);
                if (value != encoded / 10) return null;
            } else if (i == 13) {
                if (typeof value != "string") return null;
                encoded = -1;
                for (var m:Number = 0; m < SettingsCanonicalSchema.PLAY_MODES.length; m++) {
                    if (value === SettingsCanonicalSchema.PLAY_MODES[m]) encoded = m;
                }
                if (encoded < 0) return null;
            } else {
                var minimum:Number = i == 10 ? 1 : 0;
                var maximum:Number = i < 2 ? 100 : i == 10 ? 2 : 1;
                if (!integer(value, minimum, maximum)) return null;
                encoded = Number(value);
            }
            parts.push("s" + i + "=" + String(encoded));
        }
        var seen:Object = {};
        for (var k:Number = 0; k < 36; k++) {
            var row:Object = keys[k];
            if (row == null || typeof row != "object") return null;
            if (savedRows && (!(row instanceof Array) || row.length < 3)) return null;
            var id:Object = savedRows ? row[1] : row.id;
            var code:Object = savedRows ? row[2] : row.keyCode;
            if (typeof id != "string" || id !== SettingsCanonicalSchema.KEY_IDS[k]
                    || !integer(code, 0, 255) || seen["code." + code] === true) return null;
            seen["code." + code] = true;
            parts.push("k" + k + "=" + String(code));
        }
        return parts.join("|");
    }
    private static function integer(value:Object, minimum:Number, maximum:Number):Boolean {
        if (typeof value != "number") return false;
        var number:Number = Number(value);
        return !isNaN(number) && number >= minimum && number <= maximum && number == Math.floor(number);
    }
    private static function isBooleanIndex(index:Number):Boolean {
        var indexes:Array = SettingsCanonicalSchema.BOOLEAN_INDEXES;
        for (var i:Number = 0; i < indexes.length; i++) if (indexes[i] == index) return true;
        return false;
    }
}
