

/**
 * Web Panel 打开请求的受控 JSON 信封构造器。
 * fields / initFields 均为有序的 {name:String,value:String} 数组。
 */
class org.flashNight.arki.ui.PanelRequestEnvelope {
    public static function build(panel:String, source:String, fields:Array, initFields:Array):String {
        var payload:String = '{"task":"panel_request","panel":"'
            + escapeString(panel) + '","source":"' + escapeString(source) + '"';
        payload += appendFields(fields);
        if (initFields != null && initFields.length > 0) {
            payload += ',"initData":{' + appendInnerFields(initFields) + '}';
        }
        return payload + '}';
    }

    private static function appendFields(fields:Array):String {
        if (fields == null || fields.length == 0) return "";
        var result:String = "";
        for (var i:Number = 0; i < fields.length; i++) {
            var field:Object = fields[i];
            result += ',"' + escapeString(String(field.name)) + '":"'
                + escapeString(String(field.value)) + '"';
        }
        return result;
    }

    private static function appendInnerFields(fields:Array):String {
        var result:String = "";
        for (var i:Number = 0; i < fields.length; i++) {
            if (i > 0) result += ",";
            var field:Object = fields[i];
            result += '"' + escapeString(String(field.name)) + '":"'
                + escapeString(String(field.value)) + '"';
        }
        return result;
    }

    public static function escapeString(value:String):String {
        var input:String = value == null ? "" : String(value);
        var result:String = "";
        var hex:String = "0123456789abcdef";
        for (var i:Number = 0; i < input.length; i++) {
            var character:String = input.charAt(i);
            var code:Number = input.charCodeAt(i);
            if (character == '"') result += '\\"';
            else if (character == "\\") result += "\\\\";
            else if (code == 8) result += "\\b";
            else if (code == 9) result += "\\t";
            else if (code == 10) result += "\\n";
            else if (code == 12) result += "\\f";
            else if (code == 13) result += "\\r";
            else if (code < 32) result += "\\u00" + hex.charAt(Math.floor(code / 16)) + hex.charAt(code % 16);
            else result += character;
        }
        return result;
    }
}
