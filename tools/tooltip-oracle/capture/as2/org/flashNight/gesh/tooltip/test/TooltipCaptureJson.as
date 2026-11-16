class org.flashNight.gesh.tooltip.test.TooltipCaptureJson {
    private static var _json:LiteJSON;
    // Offline transport only. Join escaped spans once instead of repeatedly
    // copying a growing HTML string. The baseline content is unchanged.
    public static function runAllTests():Void {
        if (verifySerialization()) trace("CAPTURE_JSON_MATCH|true");
        else trace("[TEST_FAIL] capture JSON differs from baseline LiteJSON");
    }

    public static function quote(value:String):String {
        var parts:Array = [];
        var start:Number = 0;
        for (var index:Number = 0; index < value.length; index++) {
            var code:Number = value.charCodeAt(index);
            if (code > 31 && code != 34 && code != 92) continue;
            var replacement:String;
            if (code == 34) replacement = "\\\"";
            else if (code == 92) replacement = "\\\\";
            else if (code == 9) replacement = "\\t";
            else if (code == 10) replacement = "\\n";
            else if (code == 13) replacement = "\\r";
            else if (code == 8) replacement = "\\b";
            else if (code == 12) replacement = "\\f";
            else {
                var hex:String = code.toString(16);
                while (hex.length < 4) hex = "0" + hex;
                replacement = "\\u" + hex;
            }
            parts.push(value.substring(start,index));
            parts.push(replacement);
            start = index + 1;
        }
        parts.push(value.substring(start));
        return "\"" + parts.join("") + "\"";
    }

    public static function stringify(arg):String {
        var kind:String = typeof arg;
        if (kind == "string") return quote(String(arg));
        if (kind == "number") return isFinite(Number(arg)) ? String(arg) : "null";
        if (kind == "boolean") return arg ? "true" : "false";
        if (kind != "object" || arg == null) return "null";
        var parts:Array = [];
        if (arg instanceof Array) {
            for (var i:Number = 0; i < arg.length; i++) parts.push(stringify(arg[i]));
            return "[" + parts.join(",") + "]";
        }
        for (var key:String in arg) {
            kind = typeof arg[key];
            if (kind != "undefined" && kind != "function") {
                parts.push(quote(key) + ":" + stringify(arg[key]));
            }
        }
        return "{" + parts.join(",") + "}";
    }

    public static function verifySerialization():Boolean {
        _json = new LiteJSON();
        var values:Array = [null, undefined, true, false, 0, -1.25, 0/0, 1/0,
            "", "中文 \"引号\" \\ 路径\n换行\r\t", [], {text:"<B>旧内容</B>", missing:undefined}];
        var holes:Array = new Array(3);
        holes[1] = "middle";
        values.push(holes);
        for (var code:Number = 0; code < 32; code++) values.push(String.fromCharCode(code));
        for (var i:Number = 0; i < values.length; i++) {
            if (stringify(values[i]) != _json.stringifySafe(values[i])) {
                trace("TC_SERIALIZER_MISMATCH|case=" + i + "|expected="
                    + _json.stringifySafe(_json.stringifySafe(values[i])) + "|actual="
                    + _json.stringifySafe(stringify(values[i])));
                return false;
            }
        }
        trace("TC_SERIALIZER_CHECK|cases=" + values.length + "|match=LiteJSON.stringifySafe");
        return true;
    }

}
