/** 二次转义 SaveManager 已用严格 JSON 生成的快照文本。 */
class org.flashNight.neur.Server.ArchiveShadowWire {
    public static function stringify(codec:FastJSON, message:Object):String {
        var payload:Object = message.payload;
        if (message.task !== "archive" || message.extra !== undefined
                || payload.op !== "shadow" || typeof payload.slot !== "string"
                || typeof payload.data !== "string") {
            return codec.stringify(message);
        }
        for (var name:String in payload) {
            if (name !== "op" && name !== "slot" && name !== "data") {
                return codec.stringify(message);
            }
        }

        var dataJson:String = payload.data;
        // FP20 的 Array.join 会替换孤立代理项。保留这种旧报文的编码。
        if ([dataJson].join("") !== dataJson) {
            return codec.stringify(message);
        }
        for (var code:Number = 0; code < 32; code++) {
            var control:String = String.fromCharCode(code);
            if (control.length > 0 && dataJson.indexOf(control) >= 0) {
                return codec.stringify(message);
            }
        }

        var emptyEnvelope:Object = new Object();
        emptyEnvelope.task = message.task;
        emptyEnvelope.payload = {op:payload.op, slot:payload.slot, data:""};
        emptyEnvelope.callId = message.callId;
        var envelope:String = codec.stringify(emptyEnvelope);
        var marker:String = "\"data\":\"\"";
        var offset:Number = envelope == null ? -1 : envelope.indexOf(marker);
        if (offset < 0 || envelope.indexOf(marker, offset + marker.length) >= 0) {
            // 原消息尚未进入身份缓存。
            return codec.stringify(message);
        }
        var endingQuote:Number = offset + marker.length - 1;
        var escaped:String = dataJson.split("\\").join("\\\\").split("\"").join("\\\"");
        return envelope.substring(0, endingQuote) + escaped + envelope.substring(endingQuote);
    }
}
